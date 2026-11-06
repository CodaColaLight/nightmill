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
      Write-Utf8 (Join-Path $wt ".slots\slot-$($f[0]).json") ("{`n  `"slot`": $($f[0]),`n  `"branch`": `"$($f[1])`",`n  `"since`": `"$($f[2])`"`n}`n")
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
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
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
