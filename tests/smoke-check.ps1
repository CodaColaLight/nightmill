# tests/smoke-check.ps1 - the parallel check and its quick mode (iteration 42), through tests/check.ps1 (which runs
# tests/check.sh with bash): fixture steps (NIGHTMILL_CHECK_STEPS, lines <name> TAB <command> [TAB <kind> [TAB
# <reason>]]), the order and the verdict, the limit of 1, the quick mode, -Only and the usage errors, the limit from
# the config, two checks at once, and the lint section that keeps the check's step list and CI in step.
# NIGHTMILL_CLOCK_FILE holds one fixed time, so every duration is 0s. Same cases and same expected text as
# tests/smoke-check.sh (-Jobs 3 for --jobs 3, -Quick, -Only). Runs on Windows PowerShell 5.1 and pwsh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell -ErrorAction SilentlyContinue).Source
if (-not $psExe) { $psExe = (Get-Command pwsh).Source }
$bashExe = (Get-Command bash).Source
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nm-chk-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $tmp | Out-Null
$tf = $tmp -replace '\\', '/'
$clockF = "$tf/clock"
$USAGE = 'usage: tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh] [--summary <file>]'
$env:NIGHTMILL_CLOCK_FILE = $clockF
foreach ($v in "UPDATE_STATUS_FIXTURES", "UPDATE_DASHBOARD_FIXTURES", "UPDATE_PANEL_FIXTURES", "NIGHTMILL_CHECK_STEPS") { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }

function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Write-Lf([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n")) }
function Read-Lf([string]$path) { ([System.IO.File]::ReadAllText($path)) -replace "`r`n", "`n" }
function Has-Line([string]$text, [string]$line) { @($text -split "`n") -ccontains $line }
function Head-Line([string]$text) { @($text -split "`n")[0] }
function Last-Line([string]$text) { $l = @(($text -split "`n") | Where-Object { $_ -ne "" }); $l[$l.Count - 1] }
# Barrier [bash test]: a loop of at most 300 tries, 0.1 s apart, then exit 9
function Barrier([string]$test) { "i=0; until $test; do i=`$((i+1)); [ `$i -gt 300 ] && exit 9; sleep 0.1; done" }
# Start-Child <file> <arguments> <workdir> [environment]: a started process; read it with Wait-Child
function Start-Child([string]$file, [string]$arguments, [string]$dir, [hashtable]$extraEnv = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $file
  $psi.Arguments = $arguments
  $psi.WorkingDirectory = $dir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  [pscustomobject]@{ P = $p; ErrTask = $p.StandardError.ReadToEndAsync(); OutTask = $p.StandardOutput.ReadToEndAsync() }
}
function Wait-Child($c) {
  $c.P.WaitForExit()
  [pscustomobject]@{ Out = ($c.OutTask.Result -replace "`r`n", "`n"); Err = ($c.ErrTask.Result -replace "`r`n", "`n"); Code = $c.P.ExitCode }
}
# $nrepo: a copy of tests/check.sh, tests/check.ps1 and scripts/lib with a configuration of its own that has no platform key,
# so the cases that do not test the key do not read this repository's own .claude/nightmill.json (its verification.platform
# may be windows, unix, all or absent)
$nrepo = "$tmp\nrepo"
New-Item -ItemType Directory "$nrepo\tests", "$nrepo\scripts", "$nrepo\.claude" | Out-Null
Copy-Item "$here\tests\check.sh", "$here\tests\check.ps1" "$nrepo\tests\"
Copy-Item "$here\scripts\lib" "$nrepo\scripts\lib" -Recurse
[System.IO.File]::WriteAllText("$nrepo\.claude\nightmill.json", "{ `"verification`": { `"check`": `"true`" } }`n")
# Check <steps-file> <check.ps1 arguments> [dir of the checkout, nrepo by default] [environment]: tests/check.ps1 with fixture steps
function Check([string]$steps, [string]$cargs, [string]$root = $nrepo, [hashtable]$extraEnv = @{}) {
  $e = @{ NIGHTMILL_CHECK_STEPS = $steps; NIGHTMILL_CLOCK_FILE = $clockF }
  foreach ($k in $extraEnv.Keys) { $e[$k] = $extraEnv[$k] }
  Wait-Child (Start-Child $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$root\tests\check.ps1`" $cargs" $root $e)
}
$procs = $null
try {
  $n = [int](& $bashExe -c 'nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null' 2>$null)
  if ($n -ge 1) { $procs = $n }
} catch { $procs = $null }
function Expect-Header([int]$l, [string]$why) {
  if ($procs -and $l -gt $procs) { $l = $procs; $why = "$why, capped at $procs processors" }
  "check: full, $l at a time ($why)"
}

try {
  [System.IO.File]::WriteAllText("$tmp\clock", "1794038400`n")

  Write-Host "== order and verdict"
  $steps = "$tf/steps1.txt"
  Write-Lf "$tmp\steps1.txt" ("one`t" + (Barrier "[ -f '$tf/two.done' ]") + "; echo `"out of one`"`n" +
    "two`techo `"out of two`"; touch `"$tf/two.done`"`n" +
    "three`techo `"out of three`"; exit 1`n" +
    "four`ttrue`tbash`tfour cannot run here`n")
  $r = Check $steps "-Jobs 3"
  $o = $r.Out
  if ($r.Code -ne 1) { Fail "order: exit $($r.Code): $o" }
  if ((Head-Line $o) -cne "check: full, 3 at a time (--jobs 3)") { Fail "order: the header: $o" }
  $want = "== one", "out of one", "-- one: ok (0s)", "== two", "out of two", "-- two: ok (0s)", "== three", "out of three", "-- three: FAILED (0s)"
  $got = @(); $on = $false
  foreach ($l in ($o -split "`n")) {
    if ($l -ceq "== one") { $on = $true }
    if ($on -and $l -ne "") { $got += $l }
    if ($l -clike "-- three:*") { $on = $false }
  }
  if (($got -join "`n") -cne ($want -join "`n")) { Fail "order: the sections are not whole and in list order; got: [$($got -join '|')]" }
  $names = @(); $on = $false
  foreach ($l in ($o -split "`n")) {
    if ($l -ceq "Times:") { $on = $true }
    if ($on -and $l -ne "") { $w = @($l.Trim() -split '\s+')[0]; if ("Times:", "one", "two", "three", "total" -ccontains $w) { $names += $w } }
    if ($l -match '^  total ') { $on = $false }
  }
  if (($names -join " ") -cne "Times: one two three total") { Fail "order: the Times block: [$($names -join ' ')] in: $o" }
  if (-not (Has-Line $o "SKIPPED: four cannot run here")) { Fail "order: no SKIPPED line for four: $o" }
  if (-not (Has-Line $o "CHECK FAILED: three")) { Fail "order: no CHECK FAILED: three: $o" }
  if ($o.Contains("ALL CHECKS PASSED")) { Fail "order: a failing check passed: $o" }

  Write-Host "== the limit of 1"
  $log = "$tf/limit.log"
  function Write-Abc([string]$wait) {
    Write-Lf "$tmp\abc.txt" ("a`techo `"start a`" >> `"$log`"; echo `"out of a`"; $wait echo `"end a`" >> `"$log`"`n" +
      "b`techo `"start b`" >> `"$log`"; echo `"b line 1`"; echo `"b line 2`"; echo `"end b`" >> `"$log`"`n" +
      "c`techo `"start c`" >> `"$log`"; echo `"out of c`"; echo `"end c`" >> `"$log`"`n")
  }
  function Log-Lines { if (Test-Path "$tmp\limit.log") { @((Read-Lf "$tmp\limit.log") -split "`n" | Where-Object { $_ -ne "" }) } else { @() } }
  Write-Abc ""
  Write-Lf "$tmp\limit.log" ""
  $r = Check "$tf/abc.txt" "-Jobs 1"
  if ($r.Code -ne 0) { Fail "limit 1: exit $($r.Code): $($r.Out)" }
  if ((Log-Lines) -join "," -cne "start a,end a,start b,end b,start c,end c") { Fail "limit 1: the steps did not run one after another: $((Log-Lines) -join ',')" }
  if ((Last-Line $r.Out) -cne "ALL CHECKS PASSED") { Fail "limit 1: the last line: $($r.Out)" }
  $out1 = $r.Out
  Write-Abc ((Barrier "grep -q 'start c' '$log'") + ";")
  Write-Lf "$tmp\limit.log" ""
  $r = Check "$tf/abc.txt" "-Jobs 3"
  if ($r.Code -ne 0) { Fail "limit 3: exit $($r.Code): $($r.Out)" }
  $ll = Log-Lines
  $ic = [array]::IndexOf($ll, "start c"); $ia = [array]::IndexOf($ll, "end a")
  if (-not ($ic -ge 0 -and $ia -ge 0 -and $ic -lt $ia)) { Fail "limit 3: c did not start before a ended: $($ll -join ',')" }
  $rest3 = ($r.Out -split "`n" | Select-Object -Skip 1) -join "`n"
  $rest1 = ($out1 -split "`n" | Select-Object -Skip 1) -join "`n"
  if ($rest3 -cne $rest1) { Fail "limit 3: the output differs from -Jobs 1 beyond the header: [$($r.Out)] vs [$out1]" }

  Write-Host "== quick"
  $qlog = "$tf/quick.log"
  function Write-Quick([string]$bcmd) {
    Write-Lf "$tmp\quick.txt" ("l`techo l >> `"$qlog`"`tlint`n" +
      "b`techo b >> `"$qlog`"; $bcmd`tbash`n" +
      "p`techo p >> `"$qlog`"`tps`n" +
      "c`techo c >> `"$qlog`"`tclaude`n")
  }
  function Qlog-Lines { if (Test-Path "$tmp\quick.log") { @((Read-Lf "$tmp\quick.log") -split "`n" | Where-Object { $_ -ne "" }) } else { @() } }
  Write-Quick "true"
  Write-Lf "$tmp\quick.log" ""
  $r = Check "$tf/quick.txt" "-Quick"
  $o = $r.Out
  if ($r.Code -ne 0) { Fail "quick: exit $($r.Code): $o" }
  if ((@(Qlog-Lines) | Sort-Object) -join "," -cne "b,l") { Fail "quick: the steps that ran: $((Qlog-Lines) -join ',')" }
  if ((Head-Line $o) -cnotmatch '^check: QUICK, [0-9]+ at a time \(.+\): the lint and the bash smoke tests only; the full check does not run$') { Fail "quick: the first line: $o" }
  if ((Last-Line $o) -cne "QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)") { Fail "quick: the last line: $o" }
  if ($o.Contains("ALL CHECKS PASSED")) { Fail "quick: printed ALL CHECKS PASSED: $o" }
  if ($o -cmatch '(?m)^SKIPPED:') { Fail "quick: printed a SKIPPED line: $o" }
  Write-Quick "exit 1"
  Write-Lf "$tmp\quick.log" ""
  $r = Check "$tf/quick.txt" "-Quick"
  $o = $r.Out
  if ($r.Code -ne 1) { Fail "quick failing: exit $($r.Code): $o" }
  if ((Last-Line $o) -cne "QUICK CHECK FAILED: b (the full check has not run)") { Fail "quick failing: the last line: $o" }
  if ($o -cmatch '(?m)^CHECK FAILED: ') { Fail "quick failing: a line starts with CHECK FAILED: $o" }
  if ($o.Contains("ALL CHECKS PASSED")) { Fail "quick failing: printed ALL CHECKS PASSED: $o" }

  Write-Host "== only and usage"
  Write-Quick "true"
  Write-Lf "$tmp\quick.log" ""
  $r = Check "$tf/quick.txt" "-Only b,l -Jobs 1"
  $o = $r.Out
  if ($r.Code -ne 0) { Fail "only: exit $($r.Code): $o" }
  if ((Qlog-Lines) -join "," -cne "l,b") { Fail "only: the steps did not run in list order: $((Qlog-Lines) -join ',')" }
  if (-not (Head-Line $o).StartsWith("check: only l,b,")) { Fail "only: the header: $o" }
  if ((Last-Line $o) -cne "SELECTED CHECKS PASSED (2 of 4 steps; the full check has not run)") { Fail "only: the last line: $o" }
  function Usage-Case([string]$cargs) {
    Write-Lf "$tmp\quick.log" ""
    $r = Check "$tf/quick.txt" $cargs
    if ($r.Code -ne 2) { Fail "usage ($cargs): exit $($r.Code): $($r.Out)" }
    if (-not (Has-Line $r.Err $USAGE)) { Fail "usage ($cargs): no usage line on standard error: $($r.Err)" }
    if ((Qlog-Lines).Count -ne 0) { Fail "usage ($cargs): a step ran" }
    $r
  }
  $r = Usage-Case "-Only nope"
  if (-not (Has-Line $r.Err "check: no step named nope")) { Fail "usage: no 'no step named nope' line: $($r.Err)" }
  foreach ($a in "-Quick -Only b", "-Jobs 0", "-Jobs 17", "-Jobs x", "-PowerShell cmd") { $null = Usage-Case $a }
  # a bare '-Jobs' and an extra argument are given to the shell script as they are: PowerShell binds the first
  # to the parameter and the second to nothing, and a repeated -Quick fails in PowerShell's own binding, so they are run through bash with the same arguments
  foreach ($a in @("--jobs"), @("extra"), @("--quick", "--quick")) {
    Write-Lf "$tmp\quick.log" ""
    $c = Start-Child $bashExe ("tests/check.sh " + ($a -join " ")) $nrepo @{ NIGHTMILL_CHECK_STEPS = "$tf/quick.txt"; NIGHTMILL_CLOCK_FILE = $clockF }
    $r = Wait-Child $c
    if ($r.Code -ne 2) { Fail "usage ($a): exit $($r.Code): $($r.Out)" }
    if (-not (Has-Line $r.Err $USAGE)) { Fail "usage ($a): no usage line on standard error: $($r.Err)" }
    if ((Qlog-Lines).Count -ne 0) { Fail "usage ($a): a step ran" }
  }

  Write-Host "== the limit from the config"
  $repo = "$tmp\repo"
  New-Item -ItemType Directory "$repo\tests", "$repo\scripts", "$repo\.claude" | Out-Null
  Copy-Item "$here\tests\check.sh", "$here\tests\check.ps1" "$repo\tests\"
  Copy-Item "$here\scripts\lib" "$repo\scripts\lib" -Recurse
  Write-Lf "$tmp\one-step.txt" "only`ttrue`n"
  function Cfg([string]$extra, [hashtable]$extraEnv = @{}, [string]$cargs = "") {
    Write-Lf "$repo\.claude\nightmill.json" "{ `"verification`": { `"check`": `"true`"$extra } }`n"
    $r = Check "$tf/one-step.txt" $cargs $repo $extraEnv
    if ($r.Code -ne 0) { Fail "config ($extra): exit $($r.Code): $($r.Out) $($r.Err)" }
    $r
  }
  $NOTE = "check: verification.checkJobs must be a whole number from 1 to 16; using 4"
  $r = Cfg ', "checkJobs": 2'
  if ((Head-Line $r.Out) -cne (Expect-Header 2 "verification.checkJobs 2")) { Fail "config 2: the header: $($r.Out)" }
  $r = Cfg ', "checkJobs": 99'
  if ((Head-Line $r.Out) -cne (Expect-Header 4 "default 4")) { Fail "config 99: the header: $($r.Out)" }
  if (-not (Has-Line $r.Err $NOTE)) { Fail "config 99: no note: $($r.Err)" }
  $r = Cfg ', "checkJobs": "x"'
  if ((Head-Line $r.Out) -cne (Expect-Header 4 "default 4")) { Fail "config x: the header: $($r.Out)" }
  if (-not (Has-Line $r.Err $NOTE)) { Fail "config x: no note: $($r.Err)" }
  $r = Cfg ''
  if ((Head-Line $r.Out) -cne (Expect-Header 4 "default 4")) { Fail "config none: the header: $($r.Out)" }
  if ($r.Err.Contains($NOTE)) { Fail "config none: a note for a missing key: $($r.Err)" }
  $r = Cfg ', "checkJobs": 2' @{ UPDATE_PANEL_FIXTURES = "1" } "-Jobs 3"
  if ((Head-Line $r.Out) -cne "check: full, 1 at a time (UPDATE_PANEL_FIXTURES is set)") { Fail "config UPDATE: the header: $($r.Out)" }

  Write-Host "== the platform from the config"
  # verification.platform (iteration 56): windows skips the bash steps, unix skips the ps steps, the lint and the claude steps
  # always run, -Only ignores the key. Four fixture steps l (lint), b (bash), p (ps), c (claude), each appending its name to one log.
  $plog = "$tf/platform.log"
  $WIN_LINE = "SKIPPED: bash tests (verification.platform is windows)"
  $UNIX_LINE = "SKIPPED: PowerShell tests (verification.platform is unix)"
  $PNOTE = "check: verification.platform must be windows, unix or all; running both families"
  function Write-Plat([string]$reasonB, [string]$reasonP) {
    Write-Lf "$tmp\plat.txt" ("l`techo l >> `"$plog`"`tlint`n" +
      "b`techo b >> `"$plog`"`tbash`t$reasonB`n" +
      "p`techo p >> `"$plog`"`tps`t$reasonP`n" +
      "c`techo c >> `"$plog`"`tclaude`n")
  }
  # Plat-Run <platform as JSON, or - for no key> <check.ps1 arguments>: the result of the check in $repo; Log is what the steps wrote
  function Plat-Run([string]$val, [string]$cargs = "") {
    $pl = if ($val -ceq "-") { "" } else { ", `"platform`": $val" }
    Write-Lf "$repo\.claude\nightmill.json" "{ `"verification`": { `"check`": `"true`"$pl } }`n"
    Write-Lf "$tmp\platform.log" ""
    $r = Check "$tf/plat.txt" ("-Jobs 1 " + $cargs) $repo
    $log = (@((Read-Lf "$tmp\platform.log") -split "`n" | Where-Object { $_ -ne "" }) -join ",") + ","
    $r | Add-Member -NotePropertyName Log -NotePropertyValue $log -PassThru
  }
  function Skipped-Lines([string]$text) { @($text -split "`n" | Where-Object { $_ -clike "SKIPPED:*" }) }
  Write-Plat "" ""
  # windows: the PowerShell tests only
  $r = Plat-Run '"windows"'
  if ($r.Code -ne 0) { Fail "platform windows: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,p,c,") { Fail "platform windows: the steps that ran: $($r.Log)" }
  if (@(Skipped-Lines $r.Out) -join "|" -cne $WIN_LINE) { Fail "platform windows: the SKIPPED lines are not just '$WIN_LINE': $($r.Out)" }
  if (Has-Line $r.Out "== b") { Fail "platform windows: a section for the skipped bash step: $($r.Out)" }
  if ((Last-Line $r.Out) -cne "ALL CHECKS PASSED") { Fail "platform windows: the last line: $($r.Out)" }
  # unix: the bash tests only
  $r = Plat-Run '"unix"'
  if ($r.Code -ne 0) { Fail "platform unix: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,b,c,") { Fail "platform unix: the steps that ran: $($r.Log)" }
  if (@(Skipped-Lines $r.Out) -join "|" -cne $UNIX_LINE) { Fail "platform unix: the SKIPPED lines are not just '$UNIX_LINE': $($r.Out)" }
  if (Has-Line $r.Out "== p") { Fail "platform unix: a section for the skipped ps step: $($r.Out)" }
  if ((Last-Line $r.Out) -cne "ALL CHECKS PASSED") { Fail "platform unix: the last line: $($r.Out)" }
  # the platform's reason replaces the step's own reason
  Write-Plat "" "no pwsh here"
  $r = Plat-Run '"unix"'
  if ($r.Code -ne 0) { Fail "platform unix, p with a reason: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,b,c,") { Fail "platform unix, p with a reason: the steps that ran: $($r.Log)" }
  if (-not (Has-Line $r.Out $UNIX_LINE)) { Fail "platform unix, p with a reason: no platform line: $($r.Out)" }
  if (Has-Line $r.Out "SKIPPED: no pwsh here") { Fail "platform unix, p with a reason: the step's own reason was printed: $($r.Out)" }
  Write-Plat "other reason" ""
  $r = Plat-Run '"windows"'
  if (-not (Has-Line $r.Out $WIN_LINE)) { Fail "platform windows, b with a reason: no platform line: $($r.Out)" }
  if (Has-Line $r.Out "SKIPPED: other reason") { Fail "platform windows, b with a reason: the step's own reason was printed: $($r.Out)" }
  # a skipped step of the kept family keeps its own reason, and both lines print in list order
  Write-Plat "" "no pwsh here"
  $r = Plat-Run '"windows"'
  if ($r.Code -ne 0) { Fail "platform windows, p with a reason: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,c,") { Fail "platform windows, p with a reason: the steps that ran: $($r.Log)" }
  if (@(Skipped-Lines $r.Out) -join "|" -cne "$WIN_LINE|SKIPPED: no pwsh here") { Fail "platform windows, p with a reason: the SKIPPED lines or their order: $($r.Out)" }
  if ((Last-Line $r.Out) -cne "ALL CHECKS PASSED") { Fail "platform windows, p with a reason: the last line: $($r.Out)" }
  # all and no key: today's behaviour, both families, nothing skipped, nothing on standard error
  Write-Plat "" ""
  $r = Plat-Run '"all"'
  if ($r.Code -ne 0) { Fail "platform all: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,b,p,c,") { Fail "platform all: the steps that ran: $($r.Log)" }
  if (@(Skipped-Lines $r.Out).Count -ne 0) { Fail "platform all: a SKIPPED line: $($r.Out)" }
  if ($r.Err -ne "") { Fail "platform all: standard error is not empty: $($r.Err)" }
  $outAll = $r.Out
  $r = Plat-Run '-'
  if ($r.Code -ne 0) { Fail "platform not set: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,b,p,c,") { Fail "platform not set: the steps that ran: $($r.Log)" }
  if (@(Skipped-Lines $r.Out).Count -ne 0) { Fail "platform not set: a SKIPPED line: $($r.Out)" }
  if ($r.Err -ne "") { Fail "platform not set: standard error is not empty: $($r.Err)" }
  if ($r.Out -cne $outAll) { Fail "platform not set: the output differs from platform all: [$($r.Out)] vs [$outAll]" }
  # any other value: the note, and both families run
  foreach ($bad in '"linux"', '3') {
    $r = Plat-Run $bad
    if ($r.Code -ne 0) { Fail "platform ${bad}: exit $($r.Code): $($r.Out) $($r.Err)" }
    if ($r.Log -cne "l,b,p,c,") { Fail "platform ${bad}: the steps that ran: $($r.Log)" }
    if (-not (Has-Line $r.Err $PNOTE)) { Fail "platform ${bad}: no note on standard error: $($r.Err)" }
    if (@(Skipped-Lines $r.Out).Count -ne 0) { Fail "platform ${bad}: a SKIPPED line: $($r.Out)" }
  }
  # -Quick: the lint and the bash steps, then the key
  $QUICK_LAST = "QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)"
  $r = Plat-Run '"windows"' "-Quick"
  if ($r.Code -ne 0) { Fail "platform windows, quick: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,") { Fail "platform windows, quick: the steps that ran: $($r.Log)" }
  if (-not (Has-Line $r.Out $WIN_LINE)) { Fail "platform windows, quick: no platform line: $($r.Out)" }
  if ((Last-Line $r.Out) -cne $QUICK_LAST) { Fail "platform windows, quick: the last line: $($r.Out)" }
  $r = Plat-Run '"unix"' "-Quick"
  if ($r.Code -ne 0) { Fail "platform unix, quick: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "l,b,") { Fail "platform unix, quick: the steps that ran: $($r.Log)" }
  if (@(Skipped-Lines $r.Out).Count -ne 0) { Fail "platform unix, quick: a SKIPPED line: $($r.Out)" }
  if ((Last-Line $r.Out) -cne $QUICK_LAST) { Fail "platform unix, quick: the last line: $($r.Out)" }
  # -Only ignores the key, and does not read it either
  foreach ($plat in '"windows"', '"unix"') {
    $r = Plat-Run $plat "-Only b,p"
    if ($r.Code -ne 0) { Fail "platform $plat, only: exit $($r.Code): $($r.Out) $($r.Err)" }
    if ($r.Log -cne "b,p,") { Fail "platform $plat, only: the steps that ran: $($r.Log)" }
    if (@(Skipped-Lines $r.Out).Count -ne 0) { Fail "platform $plat, only: a SKIPPED line: $($r.Out)" }
    if ((Last-Line $r.Out) -cne "SELECTED CHECKS PASSED (2 of 4 steps; the full check has not run)") { Fail "platform $plat, only: the last line: $($r.Out)" }
  }
  $r = Plat-Run '"linux"' "-Only b"
  if ($r.Code -ne 0) { Fail "platform linux, only: exit $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Log -cne "b,") { Fail "platform linux, only: the steps that ran: $($r.Log)" }
  if ($r.Err.Contains($PNOTE)) { Fail "platform linux, only: a note for a key that -Only does not read: $($r.Err)" }

  Write-Host "== two checks at once"
  New-Item -ItemType Directory "$tmp\tmpA", "$tmp\tmpB" | Out-Null
  $psSh = $psExe -replace '\\', '/'   # the steps run under bash -c, which would strip backslashes
  $hf = $here -replace '\\', '/'      # the steps run in the throwaway checkout, so they name the scripts of this one
  foreach ($x in "A", "B") {
    $o2 = if ($x -eq "A") { "B" } else { "A" }
    Write-Lf "$tmp\two$x.txt" ("run`techo `"run $x`"; touch `"$tf/started$x`"; " + (Barrier "[ -f '$tf/started$o2' ]") + "`n" +
      "render`t'$psSh' -NoProfile -ExecutionPolicy Bypass -File '$hf/tests/smoke-render.ps1'`n" +
      "hook`t'$psSh' -NoProfile -ExecutionPolicy Bypass -File '$hf/tests/smoke-hook.ps1'`n")
  }
  $cs = @{}
  foreach ($x in "A", "B") {
    $cs[$x] = Start-Child $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$nrepo\tests\check.ps1`" -Jobs 2" $nrepo @{ TMPDIR = "$tf/tmp$x"; TEMP = "$tmp\tmp$x"; TMP = "$tmp\tmp$x"; NIGHTMILL_CHECK_STEPS = "$tf/two$x.txt"; NIGHTMILL_CLOCK_FILE = $clockF }
  }
  foreach ($x in "A", "B") {
    $o2 = if ($x -eq "A") { "B" } else { "A" }
    $r = Wait-Child $cs[$x]
    if ($r.Code -ne 0) { Fail "two checks: run $x exit $($r.Code): $($r.Out)" }
    if (-not (Has-Line $r.Out "ALL CHECKS PASSED")) { Fail "two checks: run $x did not pass: $($r.Out)" }
    if (-not (Has-Line $r.Out "run $x")) { Fail "two checks: run $x lacks its own line: $($r.Out)" }
    if (Has-Line $r.Out "run $o2") { Fail "two checks: run $x holds the line of run $o2`: $($r.Out)" }
    $secs = (@($r.Out -split "`n" | Where-Object { $_ -cmatch "^-- (run|render|hook): " } | ForEach-Object { ($_ -split ":")[0].Substring(3) }) -join " ")
    if ($secs -cne "run render hook") { Fail "two checks: run $x sections not in list order: $($r.Out)" }
    if (@(Get-ChildItem -Force "$tmp\tmp$x").Count -ne 0) { Fail "two checks: run $x left files in its temp folder: $((Get-ChildItem -Force "$tmp\tmp$x" | ForEach-Object Name) -join ' ')" }
  }

  Write-Host "== summary"
  # -Summary <file> (--summary) appends the wall time and the five slowest steps (iteration 55, decision 6). The steps move the clock.
  $sclock = "$tf/sclock"
  $sumSteps = ""
  foreach ($pair in "a:5", "b:30", "c:1", "d:30", "e:12", "f:7") {
    $nm, $sec = $pair -split ":"
    $extra = ""
    if ($nm -ceq "e") { $extra = "; exit 1" }
    $sumSteps += "$nm`tc=`$(cat `"$sclock`"); echo `$((c+$sec)) > `"$sclock`"$extra`n"
  }
  Write-Lf "$tmp\sum-steps.txt" $sumSteps
  Write-Lf "$tmp\sclock" "1794038400`n"
  $plain = Check "$tf/sum-steps.txt" "-Jobs 1" $nrepo @{ NIGHTMILL_CLOCK_FILE = $sclock }
  Write-Lf "$tmp\sclock" "1794038400`n"
  if (Test-Path "$tmp\summary.md") { Remove-Item "$tmp\summary.md" }
  $r = Check "$tf/sum-steps.txt" "-Jobs 1 -Summary `"$tf/summary.md`"" $nrepo @{ NIGHTMILL_CLOCK_FILE = $sclock }
  if ($r.Code -ne 1) { Fail "summary: exit $($r.Code), wanted 1 (e fails): $($r.Out)" }
  if ($plain.Code -ne 1) { Fail "summary: the run without -Summary exited $($plain.Code)" }
  if ($r.Out -cne $plain.Out) { Fail "summary: the standard output differs from a run without -Summary: [$($r.Out)] vs [$($plain.Out)]" }
  if (-not (Test-Path "$tmp\summary.md")) { Fail "summary: no summary file was written" }
  $wantSum = @('### tests/check.sh', '', 'Wall time: 1m25s for 6 steps, 1 at a time: FAILED', '', '| Slowest step | Time |', '|---|---|',
    '| `b` | 30s |', '| `d` | 30s |', '| `e` | 12s |', '| `f` | 7s |', '| `a` | 5s |', '') -join "`n"
  $gotSum = (Read-Lf "$tmp\summary.md").TrimEnd("`n")
  if ($gotSum -cne $wantSum.TrimEnd("`n")) { Fail "summary: the summary file is not as wanted; got: [$gotSum] wanted: [$wantSum]" }
  if (-not (Read-Lf "$tmp\summary.md").EndsWith("| ``a`` | 5s |`n`n")) { Fail "summary: the section does not end with one empty line" }
  if ((Last-Line $r.Out) -cne "CHECK FAILED: e") { Fail "summary: the last line: $($r.Out)" }
  # a passing run appends a second section: the file is appended to, not replaced
  Write-Lf "$tmp\sum2.txt" "x`ttrue`ny`ttrue`n"
  if (Test-Path "$tmp\summary2.md") { Remove-Item "$tmp\summary2.md" }
  foreach ($i in 1, 2) {
    $r = Check "$tf/sum2.txt" "-Jobs 1 -Summary `"$tf/summary2.md`"" $nrepo @{ NIGHTMILL_CLOCK_FILE = $sclock }
    if ($r.Code -ne 0) { Fail "summary twice: run $i exit $($r.Code): $($r.Out)" }
  }
  $s2 = Read-Lf "$tmp\summary2.md"
  if (@($s2 -split "`n" | Where-Object { $_ -ceq "### tests/check.sh" }).Count -ne 2) { Fail "summary twice: not two sections: $s2" }
  if (@($s2 -split "`n" | Where-Object { $_ -ceq "Wall time: 0s for 2 steps, 1 at a time: passed" }).Count -ne 2) { Fail "summary twice: the wall time lines: $s2" }
  # an empty value is the usage error (twice and without a value cannot be given through PowerShell parameters; tests/smoke-check.sh has them)
  $r = Check "$tf/sum2.txt" "-Summary `"`""
  if ($r.Code -ne 2) { Fail "summary usage (empty value): exit $($r.Code): $($r.Out)" }
  if (-not (Has-Line $r.Err $USAGE)) { Fail "summary usage (empty value): no usage line: $($r.Err)" }
  # a file that cannot be written: the note, and the exit code of the steps
  New-Item -ItemType Directory "$tmp\sumdir" | Out-Null
  Write-Lf "$tmp\sclock" "1794038400`n"
  $r = Check "$tf/sum-steps.txt" "-Jobs 1 -Summary `"$tf/sumdir`"" $nrepo @{ NIGHTMILL_CLOCK_FILE = $sclock }
  if ($r.Code -ne 1) { Fail "summary to a directory: exit $($r.Code), wanted 1: $($r.Out)" }
  if (-not (Has-Line $r.Err "check: cannot write the summary to $tf/sumdir")) { Fail "summary to a directory: no 'cannot write' line: $($r.Err)" }
  if ((Last-Line $r.Out) -cne "CHECK FAILED: e") { Fail "summary to a directory: the last line: $($r.Out)" }

  Write-Host "== the slowest steps of the real list start first"
  # The real step list of tests/check.sh (between '# steps: begin' and '# steps: end'): the steps measured slowest in CI
  # (issue 279) carry the 'first' mark. Only these are pinned; more steps may be marked later.
  $realList = New-Object System.Collections.ArrayList
  $onList = $false
  foreach ($l in ((Read-Lf (Join-Path $here "tests\check.sh")) -split "`n")) {
    if ($l -ceq '# steps: end') { $onList = $false }
    if ($onList) { [void]$realList.Add($l) }
    if ($l -ceq '# steps: begin') { $onList = $true }
  }
  foreach ($want in "bash test-spec-template.sh", "bash smoke-slot.sh", "ps smoke-slot.ps1", "ps smoke-check.ps1", "ps smoke-validate.ps1", "ps smoke-release.ps1", "ps smoke-drive.ps1", "ps test-lintcopy-output.ps1") {
    if (-not (Has-Line ($realList -join "`n") "add $want first")) { Fail "slowest steps: 'add $want first' is not in the step list of tests/check.sh" }
  }

  Write-Host "== the lint: the check runs every smoke script"
  # The section of tests/lint.sh is run alone (through bash) on scratch copies of the files it reads, each broken once.
  $lintText = Read-Lf (Join-Path $here "tests\lint.sh")
  $sec = New-Object System.Collections.ArrayList
  $on = $false
  foreach ($l in ($lintText -split "`n")) {
    if ($l -ceq 'echo "== the check runs every smoke script"') { $on = $true }
    if ($l -ceq 'echo "== text from issues is data"') { $on = $false }
    if ($on) { [void]$sec.Add($l) }
  }
  if ($sec.Count -eq 0) { Fail "lint: tests/lint.sh has no section '== the check runs every smoke script'" }
  $secText = $sec -join "`n"
  function Make-Copy([string]$d) {
    foreach ($s in "tests", ".github\workflows", "schema", "templates", "scripts") { New-Item -ItemType Directory "$d\$s" -Force | Out-Null }
    # every script in tests\, so a step that is not a smoke-* file exists
    Get-ChildItem "$here\tests" -File | Where-Object { $_.Extension -in ".sh", ".ps1" } | ForEach-Object { Copy-Item $_.FullName "$d\tests\" }
    Copy-Item "$here\.github\workflows\ci.yml" "$d\.github\workflows\"
    Copy-Item "$here\schema\nightmill.schema.json" "$d\schema\"
    Copy-Item "$here\templates\nightmill.example.json" "$d\templates\"
    Copy-Item "$here\scripts\lib" "$d\scripts\lib" -Recurse
    Copy-Item "$here\README.md", "$here\CONTRIBUTING.md" $d
    Copy-Item "$here\skills" "$d\skills" -Recurse
  }
  function Lint-In([string]$d) {
    $df = $d -replace '\\', '/'
    # NIGHTMILL_CI_PARTS_RULES_ONLY: the copy checks the rules of tests/test-ci-parts.sh, its cases run once in the lint (#293)
    Write-Lf "$tmp\run-section.sh" ("set -euo pipefail`ncd `"$df`"`nfail=0`nexport NIGHTMILL_CI_PARTS_RULES_ONLY=1`n. scripts/lib/json.sh`n" + $secText + "`nexit `$fail`n")
    Wait-Child (Start-Child $bashExe "`"$tf/run-section.sh`"" $d @{})
  }
  # Lint-Break <name> <file> <line transform: a scriptblock from the lines to the new lines> <expected text>
  function Lint-Break([string]$name, [string]$file, [scriptblock]$edit, [string]$expected) {
    $d = "$tmp\lint-$name"
    Make-Copy $d
    $lines = @((Read-Lf "$d\$file") -split "`n")
    $new = & $edit $lines
    Write-Lf "$d\$file" ((@($new) -join "`n") + "`n")
    $r = Lint-In $d
    $all = $r.Out + $r.Err
    if ($r.Code -eq 0) { Fail "lint ${name}: passed on a broken copy: $all" }
    if (-not $all.Contains($expected)) { Fail "lint ${name}: no '$expected' in: $all" }
    Remove-Item $d -Recurse -Force
  }
  Make-Copy "$tmp\lint-ok"
  $r = Lint-In "$tmp\lint-ok"
  if ($r.Code -ne 0 -or ($r.Out + $r.Err).Contains("FAIL")) { Fail "lint: the section fails on the repository as it is: $($r.Out) $($r.Err)" }
  Remove-Item "$tmp\lint-ok" -Recurse -Force
  $CI = ".github\workflows\ci.yml"
  Lint-Break "missing" "tests\check.sh" { param($ls) $ls | Where-Object { $_ -notmatch '^add bash smoke-hook\.sh' } } "FAIL: tests/check.sh does not run tests/smoke-hook.sh"
  Lint-Break "twice" "tests\check.sh" { param($ls) foreach ($l in $ls) { $l; if ($l -match '^add bash smoke-hook\.sh') { $l } } } "FAIL: tests/check.sh runs tests/smoke-hook.sh more than once"
  Lint-Break "nofile" "tests\check.sh" { param($ls) foreach ($l in $ls) { if ($l -ceq "# steps: end") { "add bash smoke-nope.sh" }; $l } } "FAIL: tests/check.sh runs tests/smoke-nope.sh, which does not exist"
  Lint-Break "twopassed" "tests\check.sh" { param($ls) $ls; 'echo "ALL CHECKS PASSED"' } "FAIL: tests/check.sh prints ALL CHECKS PASSED in more than one place"
  Lint-Break "cibash" $CI { param($ls) foreach ($l in $ls) { if ($l -like '*run: bash tests/check.sh --summary*') { $l.Replace("smoke-hook.sh,", "") } else { $l } } } "FAIL: .github/workflows/ci.yml does not run tests/smoke-hook.sh"
  Lint-Break "cips" $CI { param($ls) foreach ($l in $ls) { if ($l -like '*only: smoke-hook.ps1,*') { $l.Replace("smoke-hook.ps1,", "") } else { $l } } } "FAIL: .github/workflows/ci.yml: tests/smoke-hook.ps1 runs in no PowerShell part"
  Lint-Break "cijson" $CI { param($ls) foreach ($l in $ls) { if ($l -like '*run: bash tests/check.sh --summary*') { $l.Replace("--only ", "--only smoke-json.sh,") } else { $l } } } "FAIL: .github/workflows/ci.yml: tests/smoke-json.sh is not a step of its job or is named twice"
  Lint-Break "ciswap" $CI { param($ls) foreach ($l in $ls) { if ($l -like '*run: bash tests/check.sh --summary*') { $l.Replace("smoke-hook.sh,smoke-release.sh", "smoke-release.sh,smoke-hook.sh") } else { $l } } } "FAIL: .github/workflows/ci.yml: the --only list is not in the order of the step list"
  Lint-Break "cidirect" $CI { param($ls) $ls; "      - run: bash tests/smoke-render.sh" } "FAIL: .github/workflows/ci.yml runs tests/smoke-render.sh outside tests/check.sh"
  Lint-Break "cirename" $CI { param($ls) $ls | ForEach-Object { $_.Replace("name: bash scripts smoke tests", "name: bash scripts smoke") } } "the required job bash scripts smoke tests is missing"
  # verification.platform is wired in the schema, the example, the README, the init skill and the check (iteration 56, decision 10)
  Lint-Break "platformschema" "schema\nightmill.schema.json" { param($ls) $ls | ForEach-Object { $_.Replace('"platform"', '"platformx"') } } 'FAIL: schema: verification.platform is not a string'
  Lint-Break "platformexample" "templates\nightmill.example.json" { param($ls) $ls | ForEach-Object { $_.Replace('"platform": "all"', '"platform": "unix"') } } "FAIL: templates/nightmill.example.json does not mention verification.platform all"
  Lint-Break "platformreadme" "README.md" { param($ls) $ls | ForEach-Object { $_.Replace("verification.platform", "verification-platform") } } "FAIL: README.md does not mention verification.platform"
  Lint-Break "platforminit" "skills\init\SKILL.md" { param($ls) $ls | ForEach-Object { $_.Replace("verification.platform", "verification-platform") } } "FAIL: skills/init/SKILL.md does not mention verification.platform"
  Lint-Break "platformcheck" "tests\check.sh" { param($ls) $ls | ForEach-Object { $_.Replace("verification.platform", "verification-platform") } } "FAIL: tests/check.sh does not mention verification.platform"

  Write-Host "smoke-check: ok"
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
