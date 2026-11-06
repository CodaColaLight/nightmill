# tests/smoke-status.ps1 - status.ps1 against fixtures: a fake gh (a gh.cmd first on the PATH) answers from
# tests/fixtures/status/<scenario>/, the slot markers are written from markers.txt, and the clock is fixed
# (NIGHTMILL_NOW = 2026-11-05T12:00:00). The exact output must equal the expected*.txt files that
# smoke-status.sh uses, so both shells print the same. No network.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$S = Join-Path $here "scripts\status.ps1"
$FIX = Join-Path $here "tests\fixtures\status"
$NOW = "1793880000"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-status-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Read-Lf([string]$path) { ([IO.File]::ReadAllText($path, $utf8)) -replace "`r`n", "`n" }

try {
  # the project: one config with four slots, in a throwaway repository
  $work = Join-Path $tmp "work"
  git init -q -b main $work
  New-Item -ItemType Directory (Join-Path $work ".claude") | Out-Null
  $withSlots = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" },
  "worktrees": { "root": "../wt", "slots": 4 }
}
'@
  $noSlots = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" }
}
'@
  $cfgFile = Join-Path $work ".claude\nightmill.json"
  Write-Utf8 $cfgFile $withSlots
  $plain = Join-Path $tmp "plain"
  git init -q -b main $plain

  # a fake gh: it answers from $env:GH_FIX, logs every call to $env:GH_LOG, fails when GH_FAIL is set
  $bin = Join-Path $tmp "bin"
  New-Item -ItemType Directory $bin | Out-Null
  Write-Utf8 (Join-Path $bin "gh-fake.ps1") @'
Add-Content -Path $env:GH_LOG -Value ($args -join " ")
if ($env:GH_FAIL) { [Console]::Error.WriteLine("HTTP 401: bad credentials"); exit 1 }
$what = "$($args[0]) $($args[1])"
$file = switch ($what) {
  "project item-list" { "items.json" }
  "pr list" { "prs.json" }
  "api graphql" { "ages.json" }
  default { $null }
}
if ($what -eq "project view") { [Console]::Out.Write('{"id": "PVT_test", "number": 1}'); exit 0 }
if (-not $file) { [Console]::Error.WriteLine("unexpected gh call: $($args -join ' ')"); exit 1 }
[Console]::Out.Write([IO.File]::ReadAllText((Join-Path $env:GH_FIX $file)))
exit 0
'@
  Write-Utf8 (Join-Path $bin "gh.cmd") "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n"

  function Set-Markers([string]$scn) {
    $wt = Join-Path $tmp "wt"
    if (Test-Path $wt) { Remove-Item -Recurse -Force $wt }
    New-Item -ItemType Directory (Join-Path $wt ".slots") | Out-Null
    foreach ($line in (Read-Lf (Join-Path $FIX "$scn\markers.txt")) -split "`n") {
      if (-not $line) { continue }
      $f = $line -split "`t"
      # a line with the four report columns (skill, role, step, reported) is a seven-key marker (iteration 23)
      if ($f.Count -ge 7) {
        Write-Utf8 (Join-Path $wt ".slots\slot-$($f[0]).json") ("{`n  `"slot`": $($f[0]),`n  `"branch`": `"$($f[1])`",`n  `"since`": `"$($f[2])`",`n  `"skill`": `"$($f[3])`",`n  `"role`": `"$($f[4])`",`n  `"step`": `"$($f[5])`",`n  `"reported`": `"$($f[6])`"`n}`n")
      } else {
        Write-Utf8 (Join-Path $wt ".slots\slot-$($f[0]).json") ("{`n  `"slot`": $($f[0]),`n  `"branch`": `"$($f[1])`",`n  `"since`": `"$($f[2])`"`n}`n")
      }
    }
  }

  # Run-S <dir> <scenario> <arguments> [fail]: run status.ps1 in a child powershell; Out, Err, Code
  function Run-S([string]$dir, [string]$scn, [string]$extra = "", [bool]$ghFails = $false) {
    $log = Join-Path $tmp "gh.log"
    Write-Utf8 $log ""
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$S`" $extra"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["PATH"] = "$bin;" + $env:PATH
    $psi.EnvironmentVariables["GH_FIX"] = (Join-Path $FIX $scn)
    $psi.EnvironmentVariables["GH_LOG"] = $log
    $psi.EnvironmentVariables["NIGHTMILL_NOW"] = $NOW
    if ($ghFails) { $psi.EnvironmentVariables["GH_FAIL"] = "1" }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    # standard output as bytes, so that the porcelain cases can check for CR bytes
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $script:OutBytes = $ms.ToArray()
    $out = $utf8.GetString($script:OutBytes)
    $script:OutRaw = $out
    $script:Out = $out -replace "`r`n", "`n"
    $script:Err = $errTask.Result
    $script:Code = $p.ExitCode
  }

  function Expect([string]$name, [string]$file) {
    $want = Read-Lf $file
    if ($script:Out -ne $want) {
      Write-Host "--- expected ($file)"; Write-Host $want; Write-Host "--- got"; Write-Host $script:Out
      Fail "$name`: the output differs from $file"
    }
  }

  Write-Host "== the table (full board, two busy slots)"
  Set-Markers "a"
  Run-S $work "a"
  if ($Code -ne 0) { Fail "exit code $Code`: $Err" }
  Expect "table" (Join-Path $FIX "a\expected.txt")

  Write-Host "== -All"
  Run-S $work "a" "-All"
  if ($Code -ne 0) { Fail "-All exit code $Code`: $Err" }
  Expect "-All" (Join-Path $FIX "a\expected-all.txt")

  Write-Host "== no slot busy: In progress and Spec flags"
  Set-Markers "b"
  Run-S $work "b"
  if ($Code -ne 0) { Fail "exit code $Code`: $Err" }
  Expect "no busy slot" (Join-Path $FIX "b\expected.txt")
  if ((@($Out -split "`n" | Where-Object { $_ -ne "" }) | Select-Object -Last 1) -ne "capacity: slots 4 (config), agents 2 (default)") { Fail "the capacity line is not the last line" }
  if ($Out.Contains("slots: none busy")) { Fail "'slots: none busy' is still printed" }
  foreach ($n in 1, 2, 3, 4) { if ($Out -notmatch "(?m)^   $n  free$") { Fail "slot $n is not a free row that ends after free" } }

  Write-Host "== the capacity line says when live values are in force"
  $capFile = Join-Path $tmp "wt\.slots\capacity.json"
  Write-Utf8 $capFile "{`n  `"slots`": 3,`n  `"maxAgents`": 3,`n  `"since`": `"2026-11-05T11:00:00`"`n}`n"
  Run-S $work "b"
  if ($Code -ne 0) { Fail "exit code $Code`: $Err" }
  Expect "live capacity" (Join-Path $FIX "b\expected-live.txt")
  Remove-Item $capFile

  Write-Host "== the same without a worktrees section: no slots part"
  Write-Utf8 $cfgFile $noSlots
  Run-S $work "b"
  Expect "no slots configured" (Join-Path $FIX "b\expected-noslots.txt")
  if ($Out -match "(?m)^capacity:") { Fail "no capacity line without a worktrees section" }
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== busy slots and their flags"
  Set-Markers "c"
  Run-S $work "c"
  if ($Code -ne 0) { Fail "exit code $Code`: $Err" }
  Expect "slots" (Join-Path $FIX "c\expected.txt")
  if ($Err) { Fail "status printed on standard error: $Err" }
  # the Slots section (iteration 23): every slot with its agent state, skill, step and the age of the last report
  foreach ($want in @(
      "(?m)^slot  State  Agent    Branch       Skill             Step   Report  Since  PR          Flag$",
      "(?m)^   1  busy   stalled  feat/merged  next/session      done       1d ",
      "(?m)^   2  busy   unknown  feat/closed  \?                 \?           - ",
      "(?m)^   3  busy   stalled  feat/stale   next/implementer  check      2d ",
      "(?m)^   4  busy   running  feat/new     fix/fixer         test       5m    10m  -$")) {
    if ($Out -notmatch $want) { Fail "the Slots section has no line $want" }
  }
  foreach ($flag in "stale: busy, PR merged (slot --release 1)", "stale: busy, PR closed (slot --abandon 2)", "stale: busy, no open PR") {
    if (-not $Out.Contains($flag)) { Fail "the flag '$flag' is gone" }
  }

  Write-Host "== an unusable stalledAfterMinutes: the same table and the slot script's note"
  Write-Utf8 $cfgFile $withSlots.Replace('"slots": 4 }', '"slots": 4, "stalledAfterMinutes": 0 }')
  Run-S $work "c"
  if ($Code -ne 0) { Fail "stalledAfterMinutes 0: exit code $Code`: $Err" }
  Expect "stalledAfterMinutes 0" (Join-Path $FIX "c\expected.txt")
  if ($Err -notmatch "(?m)^slot: worktrees\.stalledAfterMinutes must be a whole number of at least 1; using 30\r?$") { Fail "stalledAfterMinutes 0: no note on standard error: $Err" }
  Write-Utf8 $cfgFile $withSlots
  Run-S $work "c"

  Write-Host "== porcelain"
  # status.ps1 -Porcelain (iteration 31): the cells of the text tables, tab separated, one record kind per line
  function Check-Porcelain([string]$name) {
    if ($script:OutBytes -contains [byte]13) { Fail "$name`: a carriage return in the porcelain output" }
    $nb = $script:OutBytes.Length
    if ($nb -lt 1 -or $script:OutBytes[$nb - 1] -ne 10) { Fail "$name`: the porcelain output does not end with LF" }
    if ($nb -ge 2 -and $script:OutBytes[$nb - 2] -eq 10) { Fail "$name`: the porcelain output ends with an empty line" }
    foreach ($l in ($script:OutRaw.TrimEnd("`n") -split "`n")) {
      $nf = @($l -split "`t").Count
      if ($l.StartsWith("item`t") -and $nf -ne 8) { Fail "$name`: an item line with $nf fields: $l" }
      if ($l.StartsWith("slot`t") -and $nf -ne 11) { Fail "$name`: a slot line with $nf fields: $l" }
    }
  }
  foreach ($scn in "a", "b", "c") {
    Set-Markers $scn
    Run-S $work $scn "-Porcelain"
    if ($Code -ne 0) { Fail "porcelain $scn`: exit code $Code`: $Err" }
    $want = Read-Lf (Join-Path $FIX "$scn\expected-porcelain.txt")
    if ($OutRaw -cne $want) {
      Write-Host "--- expected"; Write-Host $want; Write-Host "--- got"; Write-Host $OutRaw
      Fail "porcelain $scn`: the output differs from expected-porcelain.txt"
    }
    Check-Porcelain "porcelain $scn"
  }
  Set-Markers "a"
  Run-S $work "a" "-Porcelain"
  $lines = @($OutRaw -split "`n")
  if ($lines -notcontains ("slot`t3`tfree" + ("`t" * 8))) { Fail "porcelain: a free slot is not slot, 3, free and eight empty fields" }
  $item2 = @($lines | Where-Object { $_.StartsWith("item`t2`t") })
  if ($item2.Count -ne 1 -or -not $item2[0].EndsWith("`tConfig validator against the schema, run by init and the lint")) { Fail "porcelain: the title of item 2 is not whole: $item2" }

  Write-Host "== porcelain without worktrees"
  Set-Markers "b"
  Write-Utf8 $cfgFile $noSlots
  Run-S $work "b" "-Porcelain"
  if ($Code -ne 0) { Fail "porcelain without worktrees: exit code $Code" }
  if ($OutRaw -cmatch "(?m)^(slot|capacity)") { Fail "porcelain without worktrees prints a slot or capacity line" }
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== porcelain -All"
  Set-Markers "a"
  Run-S $work "a" "-All -Porcelain"
  if ($Code -ne 0) { Fail "porcelain -All: exit code $Code" }
  if ($OutRaw -cnotmatch "(?m)^item`t[0-9]+`tBacklog`t" -or $OutRaw -cnotmatch "(?m)^item`t[0-9]+`tDone`t") { Fail "porcelain -All does not list Backlog and Done" }
  if ($OutRaw.Contains("not shown")) { Fail "porcelain -All prints 'not shown'" }
  Check-Porcelain "porcelain -All"

  Write-Host "== porcelain with a failing gh"
  Run-S $work "a" "-Porcelain" $true
  if ($Code -ne 2 -or $Err -notmatch "bad credentials") { Fail "porcelain with a failing gh must exit 2 with its message: $Code $Err" }
  if ($OutBytes.Length -ne 0) { Fail "porcelain with a failing gh printed on standard output: $OutRaw" }
  Set-Markers "c"
  Run-S $work "c"

  Write-Host "== reads only"
  $log = [IO.File]::ReadAllText((Join-Path $tmp "gh.log"))
  foreach ($c in @("project item-list", "project view", "pr list", "api graphql")) {
    if (-not $log.Contains($c)) { Fail "gh $c was never called" }
  }
  if ($log -match 'item-edit|item-add|item-archive|pr merge|issue edit|issue comment|issue close|mutation') { Fail "status.ps1 changed something: $log" }

  Write-Host "== errors"
  Run-S $work "a" "--nope"
  if ($Code -ne 2) { Fail "an unknown option must exit 2, got $Code" }
  Run-S $plain "a"
  if ($Code -ne 2 -or $Err -notmatch "nightmill.json") { Fail "no config must exit 2 and name the file: $Code $Err" }
  Run-S $work "a" "" $true
  if ($Code -ne 2 -or $Err -notmatch "bad credentials") { Fail "a failing gh must exit 2 with its message: $Code $Err" }

  Write-Host "STATUS OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
