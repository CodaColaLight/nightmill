# tests/smoke-stages.ps1 - the stage record (iteration 41): stages.ps1 against the fixture record in
# tests/fixtures/stages/ (ledger.tsv and the expected tables beside it), the step times of tests/check.sh (through
# tests/check.ps1) against fixture steps, and the duration text. The clock comes from NIGHTMILL_CLOCK_FILE (test
# only), never from the system clock. T0 of the fixture is 2026-11-07T08:00:00Z, 1794038400 seconds since 1970. No
# network: a fake gh logs every call, and stages.ps1 must make none. Same cases and same expected text as
# tests/smoke-stages.sh. Runs on Windows PowerShell 5.1 and pwsh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$ST = Join-Path $here "scripts\stages.ps1"
$psExe = (Get-Command powershell).Source
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nightmill-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $tmp | Out-Null
$tf = $tmp -replace '\\', '/'
$FIX = Join-Path $here "tests\fixtures\stages"
$T0 = [long]1794038400

function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Read-Lf([string]$path) { ([System.IO.File]::ReadAllText($path)) -replace "`r`n", "`n" }
function Block([string]$name) { Read-Lf (Join-Path $FIX "expected-$name.txt") }
# Run-Child <file> <arguments> [environment]: a child process in the project; Out, Err (LF) and Code
function Run-Child([string]$file, [string]$arguments, [hashtable]$extraEnv = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $file
  $psi.Arguments = $arguments
  $psi.WorkingDirectory = "$tmp\work"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{ Out = $out; Err = ($errTask.Result -replace "`r`n", "`n"); Code = $p.ExitCode }
}
# Stages <arguments> [environment]: stages.ps1 from inside the project; the standard output is kept byte for byte
function Stages([string]$arguments, [hashtable]$extraEnv = @{}) {
  Run-Child $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$ST`" $arguments" $extraEnv
}
function Cell([string]$out, [string]$name, [int]$idx) { # the idx-th whitespace separated cell of the row of <name>
  foreach ($l in ($out -split "`n")) { $f = @($l -split '\s+' | Where-Object { $_ -ne "" }); if ($f.Count -gt $idx -and $f[0] -ceq $name) { return $f[$idx] } }
  return "<none>"
}
function Has-Line([string]$text, [string]$pattern) { [regex]::IsMatch($text, "(?m)$pattern") }

# A fake gh that records every call: the table is read-only and works without the network.
$bin = Join-Path $tmp "bin"
New-Item -ItemType Directory $bin | Out-Null
$ghLog = Join-Path $tmp "gh.log"
[System.IO.File]::WriteAllText($ghLog, "")
[System.IO.File]::WriteAllText((Join-Path $bin "gh-fake.ps1"), "Add-Content -Path `$env:GH_LOG -Value (`$args -join ' ')`n[Console]::Error.WriteLine('stages must not call gh')`nexit 1`n")
[System.IO.File]::WriteAllText((Join-Path $bin "gh.cmd"), "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n")
$env:PATH = "$bin;" + $env:PATH
$env:GH_LOG = $ghLog

try {
  # The project: a throwaway repository with the worktrees root ../wt; the record is <root>\.slots\ledger.tsv.
  git init -q -b main "$tmp\work"
  New-Item -ItemType Directory "$tmp\work\.claude", "$tmp\wt\.slots" | Out-Null
  [System.IO.File]::WriteAllText("$tmp\work\.claude\nightmill.json", @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": { "root": "../wt", "slots": 2 }
}
'@)
  $L = "$tmp\wt\.slots\ledger.tsv"
  Copy-Item "$FIX\ledger.tsv" $L
  $clock = "$tmp\clock"
  $env:NIGHTMILL_CLOCK_FILE = $clock
  function Set-Clock([long]$v) { [System.IO.File]::WriteAllText($clock, "$v`n") }
  # the fixture clock: 13700 s after T0, so that the running take D has run for 11m40s
  Set-Clock ($T0 + 13700)

  Write-Host "== stages from a fixture record"
  # Take A (slot 1, merged, issue 12): the worked example of decision 10
  $r = Stages "-Issue 12"
  if ($r.Code -ne 0) { Fail "-Issue 12: exit $($r.Code): $($r.Err)" }
  if ($r.Out -cne (Block "a")) { Fail "-Issue 12: the bytes are not the worked example; got: [$($r.Out)] wanted: [$(Block 'a')]" }
  if (-not (Has-Line $r.Out '^  check +2 +20m00s +20%$')) { Fail "-Issue 12: the two check runs are not added: $($r.Out)" }
  if (Has-Line $r.Out '^  done ') { Fail "-Issue 12: done (reported after the PR opened) is counted: $($r.Out)" }
  if (-not (Has-Line $r.Out '^  pull-request +1 +30s +1%$')) { Fail "-Issue 12: pull-request is not 30s: $($r.Out)" }
  if (-not (Has-Line $r.Out '^  ci-and-merge +1 +19m30s +20%$')) { Fail "-Issue 12: ci-and-merge is not 19m30s: $($r.Out)" }
  if (-not (Has-Line $r.Out '^  total +1h40m +100%$')) { Fail "-Issue 12: the total is not 1h40m (to minus the take's start, not the free line): $($r.Out)" }

  # no option: the last 5 takes, here all four, in file order, a blank line between them
  $r = Stages ""
  if ($r.Code -ne 0) { Fail "no option: exit $($r.Code): $($r.Err)" }
  $want = (Block "a") + "`n" + (Block "b") + "`n" + (Block "c") + "`n" + (Block "d")
  if ($r.Out -cne $want) { Fail "no option: not the four takes in file order; got: [$($r.Out)]" }
  if (-not (Has-Line $r.Out '^  not-reported +1 +unknown +-$')) { Fail "take B: not-reported is not unknown: $($r.Out)" }
  if (-not (Has-Line $r.Out '^  total +unknown +-$')) { Fail "take B: the total is not unknown: $($r.Out)" }
  if (-not (Has-Line $r.Out '^  ci-and-merge +1 +12m30s +-$')) { Fail "take B: ci-and-merge is not known: $($r.Out)" }
  if (-not (Has-Line $r.Out '^-  feat/c  slot 1  abandoned 2026-11-07T11:21:40Z$')) { Fail "take C: the header: $($r.Out)" }
  if (-not (Has-Line $r.Out '^-  feat/d  slot 2  running$')) { Fail "take D: not running: $($r.Out)" }
  if ([regex]::Matches($r.Out, 'unknown').Count -ne 2) { Fail "unknown shows more or less than the two cells of take B: $($r.Out)" }
  # a line of a later kind is skipped without a note; the one with 10 fields and the one with a bad stamp give one note
  if (@($r.Err -split "`n" | Where-Object { $_ -ne "" }).Count -ne 1) { Fail "standard error is not one line: $($r.Err)" }
  if (-not (Has-Line $r.Err '^stages: skipped 2 malformed lines of .*ledger\.tsv$')) { Fail "no note about the two malformed lines: $($r.Err)" }

  $r = Stages "-Last 1"
  if ($r.Code -ne 0 -or $r.Out -cne (Block "d")) { Fail "-Last 1: exit $($r.Code), got: [$($r.Out)]" }
  $r = Stages "-Last 2"
  if ($r.Code -ne 0 -or $r.Out -cne ((Block "c") + "`n" + (Block "d"))) { Fail "-Last 2: exit $($r.Code), got: [$($r.Out)]" }

  $r = Stages "-Issue 99"
  if ($r.Code -ne 0) { Fail "-Issue 99: exit $($r.Code): $($r.Err)" }
  if (-not "$($r.Out)$($r.Err)".Contains('#99: no record; every stage unknown (no slot took it, or a version before iteration 41 freed it)')) { Fail "-Issue 99: the no-record line: [$($r.Out)] [$($r.Err)]" }
  if (Has-Line $r.Out '^  total ') { Fail "-Issue 99 printed a table: $($r.Out)" }
  $r = Stages "-Issue 7"
  if (-not "$($r.Out)$($r.Err)".Contains('#7: no record;')) { Fail "-Issue 7 matched the PR number: [$($r.Out)]" }

  # usage errors: the usage line on standard error, nothing on standard output, exit 1
  foreach ($a in "-Last 0", "-Last x", "-Last 1000", "-Issue 0", "-Issue x", "-Issue 01", "-Issue 12345678901", "-Issue 1 -Last 2", "-Last 2 -Issue 1", "extra", "-Issue 12 extra") {
    $r = Stages $a
    if ($r.Code -ne 1) { Fail "usage ($a): exit $($r.Code): [$($r.Out)] [$($r.Err)]" }
    if (-not $r.Err.StartsWith("usage: ")) { Fail "usage ($a): no usage line on standard error: [$($r.Err)]" }
    if ($r.Out) { Fail "usage ($a): printed [$($r.Out)]" }
  }

  # read-only: no gh call, the record and its folder unchanged
  $before = (Get-ChildItem -Recurse -Force "$tmp\wt" | ForEach-Object { $_.FullName }) -join "|"
  $ledgerBefore = [System.IO.File]::ReadAllBytes($L)
  $null = Stages "-Last 5"; $null = Stages "-Issue 12"
  if ((Get-Content $ghLog -Raw)) { Fail "stages.ps1 called gh: $(Get-Content $ghLog -Raw)" }
  if (([System.IO.File]::ReadAllBytes($L) -join ",") -ne ($ledgerBefore -join ",")) { Fail "stages.ps1 changed the record" }
  if ($before -ne ((Get-ChildItem -Recurse -Force "$tmp\wt" | ForEach-Object { $_.FullName }) -join "|")) { Fail "stages.ps1 wrote a file" }

  # no file: the no-record-yet line, exit 0; a record that cannot be read: exit 1
  Remove-Item $L
  $r = Stages ""
  if ($r.Code -ne 0) { Fail "no file: exit $($r.Code): $($r.Err)" }
  if (-not (Has-Line "$($r.Out)$($r.Err)" '^no record yet: .*ledger\.tsv\r?$')) { Fail "no file: [$($r.Out)] [$($r.Err)]" }
  $r = Stages "-Issue 12"
  if ($r.Code -ne 0 -or -not (Has-Line "$($r.Out)$($r.Err)" '^no record yet: .*ledger\.tsv\r?$')) { Fail "no file with -Issue: exit $($r.Code) [$($r.Out)] [$($r.Err)]" }
  New-Item -ItemType Directory $L | Out-Null
  $r = Stages ""
  if ($r.Code -ne 1) { Fail "a record that is a folder: exit $($r.Code): [$($r.Out)] [$($r.Err)]" }
  if (-not (Has-Line $r.Err '^stages: cannot read .*ledger\.tsv')) { Fail "a record that is a folder: standard error [$($r.Err)]" }
  Remove-Item $L

  Write-Host "== a take by the previous version freed by this one, and a take that was never freed"
  $lines = @(
    "free`t2026-11-07T08:30:00Z`t1`tfeat/p`treleased`t`t`t5`t2026-11-07T08:10:00Z`t2026-11-07T08:20:00Z`t31",
    "take`t2026-11-07T09:00:30Z`t2`tfeat/q`ttake`t`t`t`t2026-11-07T09:00:00Z`t2026-11-07T09:00:30Z`t",
    "step`t2026-11-07T09:00:40Z`t2`tfeat/q`tslot-taken`tnext`tsession`t`t`t`t",
    "take`t2026-11-07T10:00:30Z`t2`tfeat/r`ttake`t`t`t`t2026-11-07T10:00:00Z`t2026-11-07T10:00:30Z`t"
  )
  [System.IO.File]::WriteAllText($L, (($lines -join "`n") + "`n"))
  $r = Stages "-Issue 31"
  if ($r.Code -ne 0) { Fail "free without a take: exit $($r.Code): $($r.Err)" }
  if (-not $r.Out.Contains('#31  feat/p  slot 1  merged 2026-11-07T08:20:00Z')) { Fail "free without a take: the header: $($r.Out)" }
  if (-not (Has-Line $r.Out '^  total +unknown +-$')) { Fail "free without a take: the total is not unknown: $($r.Out)" }
  $r = Stages "-Last 5"
  if (-not $r.Out.Contains('-  feat/q  slot 2  not freed')) { Fail "a take followed by a second take is not 'not freed': $($r.Out)" }
  if (-not $r.Out.Contains('-  feat/r  slot 2  running')) { Fail "the last take of slot 2 is not running: $($r.Out)" }
  Copy-Item "$FIX\ledger.tsv" $L -Force

  Write-Host "== the check's step times"
  # NIGHTMILL_CHECK_STEPS (test only) names a file of <name> TAB <command> lines; the check runs exactly those steps,
  # here through tests/check.ps1 (bash). The steps move the fixture clock by 12 s, 75 s and 3700 s.
  $clockF = "$tf/clock"
  function Clock-Step([int]$s) { "echo `$(( `$(cat '$clockF') + $s )) > '$clockF'" }
  $steps = "$tmp\steps.txt"
  function Write-Steps([string]$two) {
    [System.IO.File]::WriteAllText($steps, ("one`t" + (Clock-Step 12) + "`ntwo`t" + (Clock-Step 75) + $two + "`nthree`t" + (Clock-Step 3700) + "`n"))
  }
  $checkPs = Join-Path $here "tests\check.ps1"
  function Run-Check { Run-Child $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$checkPs`"" @{ NIGHTMILL_CHECK_STEPS = "$tf/steps.txt"; NIGHTMILL_CLOCK_FILE = $clockF } }
  Write-Steps "; exit 1"
  Set-Clock $T0
  $r = Run-Check
  $o = $r.Out -replace "`r`n", "`n"
  if ($r.Code -ne 1) { Fail "check with a failing step: exit $($r.Code): $o" }
  foreach ($ln in "-- one: ok (12s)", "-- two: FAILED (1m15s)", "-- three: ok (1h01m)", "== one", "CHECK FAILED: two") {
    if (-not (Has-Line $o ("^" + [regex]::Escape($ln) + "$"))) { Fail "check: the line '$ln' is missing: $o" }
  }
  if (Has-Line $o '^SKIPPED:') { Fail "check with fixture steps printed a SKIPPED line: $o" }
  if ($o.Contains("ALL CHECKS PASSED")) { Fail "check with a failing step passed: $o" }
  $row = { param($n, $t) ("  {0,-28} {1,8}" -f $n, $t) }
  $wantBlock = "Times:`n" + ((& $row "one" "12s"), (& $row "two" "1m15s"), (& $row "three" "1h01m"), (& $row "total" "1h03m") -join "`n") + "`n"
  if (-not $o.Contains($wantBlock)) { Fail "check: the Times block is not the three steps and the total of 3787 s; wanted: [$wantBlock] in: [$o]" }
  $iThree = $o.IndexOf("-- three:"); $iTimes = $o.IndexOf("Times:"); $iVerdict = $o.IndexOf("CHECK FAILED")
  if (-not ($iThree -ge 0 -and $iThree -lt $iTimes -and $iTimes -lt $iVerdict)) { Fail "check: Times is not between the last step and the verdict: $o" }
  # a second run with three passing steps
  Write-Steps ""
  Set-Clock $T0
  $r = Run-Check
  $o = $r.Out -replace "`r`n", "`n"
  if ($r.Code -ne 0) { Fail "check with passing steps: exit $($r.Code): $o" }
  if (-not (Has-Line $o '^-- two: ok \(1m15s\)$')) { Fail "check: the result line of a passing step two: $o" }
  if (-not (Has-Line $o '^ALL CHECKS PASSED$')) { Fail "check: no ALL CHECKS PASSED: $o" }
  if (-not (Has-Line $o '^  total +1h03m$')) { Fail "check: the total of the passing run: $o" }
  if (Has-Line $o '^SKIPPED:') { Fail "check with fixture steps printed a SKIPPED line: $o" }

  Write-Host "== the duration text"
  # 0, 59, 60, 3599, 3600, 3659 and 93780 seconds, as the time column of a take whose steps last that long
  Copy-Item "$FIX\ledger-durations.tsv" $L -Force
  $r = Stages "-Last 1"
  if ($r.Code -ne 0) { Fail "durations: exit $($r.Code): $($r.Err)" }
  $pairs = [ordered]@{ d0 = "0s"; d59 = "59s"; d60 = "1m00s"; d3599 = "59m59s"; d3600 = "1h00m"; d3659 = "1h00m"; d93780 = "26h03m" }
  foreach ($k in $pairs.Keys) {
    $got = Cell $r.Out $k 2
    if ($got -cne $pairs[$k]) { Fail "duration text of $k`: got '$got', wanted '$($pairs[$k])'; $($r.Out)" }
  }
  if ((Cell $r.Out "total" 1) -cne "29h05m") { Fail "the total of 104757 s is not 29h05m: $($r.Out)" }
  if ((Cell $r.Out "not-reported" 2) -cne "0s" -or (Cell $r.Out "take" 2) -cne "0s") { Fail "known zero stretches are not 0s: $($r.Out)" }
  if ($r.Out.Contains("unknown")) { Fail "a take with every stage known shows unknown: $($r.Out)" }

  # an unusable NIGHTMILL_CLOCK_FILE gives one note and the system clock (a running take runs to "now")
  Copy-Item "$FIX\ledger.tsv" $L -Force
  Set-Clock ($T0 + 13700)
  $note = "ledger: NIGHTMILL_CLOCK_FILE is not usable; using the system clock"
  $badFile = "$tmp\badclock"
  foreach ($bad in "missing", "empty", "text", "long") {
    Remove-Item $badFile -ErrorAction SilentlyContinue
    switch ($bad) {
      "empty" { [System.IO.File]::WriteAllText($badFile, "") }
      "text" { [System.IO.File]::WriteAllText($badFile, "soon`n") }
      "long" { [System.IO.File]::WriteAllText($badFile, "1234567890123`n") }
    }
    $r = Stages "-Last 1" @{ NIGHTMILL_CLOCK_FILE = $badFile }
    if ($r.Code -ne 0) { Fail "unusable clock ($bad): exit $($r.Code): $($r.Err)" }
    if (-not (Has-Line $r.Err ("^" + [regex]::Escape($note) + "$"))) { Fail "unusable clock ($bad): no note on standard error: [$($r.Err)]" }
    if (-not $r.Out.Contains('-  feat/d  slot 2  running')) { Fail "unusable clock ($bad): the running take is not shown: $($r.Out)" }
    if (Has-Line $r.Out '^  implement +1 +10m00s ') { Fail "unusable clock ($bad): the fixture clock was used: $($r.Out)" }
  }
  $r = Stages "-Last 1"
  if ($r.Err.Contains($note)) { Fail "a usable clock gave the note: $($r.Err)" }

  Write-Host "SMOKE OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
