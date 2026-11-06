# tests/smoke-panel.ps1 - panel.ps1 against fixtures (iteration 32): the slot markers of
# tests/fixtures/panel/run-stall-old-free/ are written into a throwaway project, the clock is fixed
# (NIGHTMILL_NOW = 2026-11-05T12:00:00) and every case runs panel.ps1 in a child powershell. The output must equal
# tests/fixtures/panel/run-stall-old-free/expected.txt, the file smoke-panel.sh compares with too, so both shells
# print the same bytes. A fake gh (a gh.cmd first on the PATH) logs its calls: the panel never calls it. No network.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$PANEL = Join-Path $here "scripts\panel.ps1"
$FIX = Join-Path $here "tests\fixtures\panel\run-stall-old-free"
$NOW = "1793880000"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-panel-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$TAB = "`t"
$NoteInterval = "note${TAB}worktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15"

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Read-Lf([string]$path) { ([IO.File]::ReadAllText($path, $utf8)) -replace "`r`n", "`n" }

try {
  # the project: one config with four slots and no panelRefreshSeconds, in a throwaway repository
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
  function Set-WorktreesKey([string]$fragment) {
    Write-Utf8 $cfgFile $withSlots.Replace('"slots": 4 }', ('"slots": 4, ' + $fragment + ' }'))
    if (-not ([IO.File]::ReadAllText($cfgFile).Contains($fragment))) { Fail "the config copy has no $fragment" }
  }
  $plain = Join-Path $tmp "plain"
  git init -q -b main $plain
  $nogit = Join-Path $tmp "nogit"
  New-Item -ItemType Directory $nogit | Out-Null
  $tdir = Join-Path $tmp "tdir"
  New-Item -ItemType Directory $tdir | Out-Null

  # a fake gh: it logs every call to %GH_LOG% and fails. The panel never calls it.
  $bin = Join-Path $tmp "bin"
  New-Item -ItemType Directory $bin | Out-Null
  $ghLog = Join-Path $tmp "gh.log"
  Write-Utf8 $ghLog ""
  Write-Utf8 (Join-Path $bin "gh.cmd") "@echo off`r`necho %*>>`"%GH_LOG%`"`r`nexit /b 1`r`n"

  $wt = Join-Path $tmp "wt"
  function Set-Markers {
    if (Test-Path $wt) { Remove-Item -Recurse -Force $wt }
    New-Item -ItemType Directory (Join-Path $wt ".slots") | Out-Null
    foreach ($line in (Read-Lf (Join-Path $FIX "markers.txt")) -split "`n") {
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

  # Run-P <dir> <arguments> <extra environment>: run panel.ps1 in a child powershell; OutRaw, OutBytes, Err, Code
  function Run-P([string]$dir, [string]$extra = "", [hashtable]$extraEnv = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PANEL`" $extra"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["PATH"] = "$bin;" + $env:PATH
    $psi.EnvironmentVariables["GH_LOG"] = $ghLog
    $psi.EnvironmentVariables["NIGHTMILL_NOW"] = $NOW
    $psi.EnvironmentVariables["TEMP"] = $tdir
    $psi.EnvironmentVariables["TMP"] = $tdir
    foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = $extraEnv[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    # standard output as bytes, so that the cases can check for CR bytes
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $script:OutBytes = $ms.ToArray()
    $script:OutRaw = $utf8.GetString($script:OutBytes)
    $script:Err = $errTask.Result
    $script:Code = $p.ExitCode
  }

  function Same([string]$name, [string]$want) {
    if ($script:OutRaw -cne $want) {
      Write-Host "--- expected"; Write-Host $want; Write-Host "--- got"; Write-Host $script:OutRaw
      Fail "$name`: the output differs"
    }
  }
  function Lines { @($script:OutRaw -split "`n" | Where-Object { $_ -ne "" }) }

  Set-Markers
  $markersWritten = @{}
  foreach ($f in Get-ChildItem (Join-Path $wt ".slots")) { $markersWritten[$f.Name] = [IO.File]::ReadAllText($f.FullName) }
  $before = (git -C $work status --porcelain --untracked-files=all) -join "`n"
  $good = Read-Lf (Join-Path $FIX "expected.txt")

  Write-Host "== the records of the slots"
  Run-P $work
  if ($Code -ne 0) { Fail "exit code $Code`: $Err" }
  # a carriage return left on a slot line would make '4 free' unreadable and the output an unknown record
  if ($OutBytes -contains [byte]13) { Fail "a carriage return in the output" }
  Same "records" $good
  if ($Err) { Fail "the panel printed on standard error: $Err" }
  $l = Lines
  if ($l[0] -ne "time${TAB}12:00:00") { Fail "the first record is not the time of NIGHTMILL_NOW: $($l[0])" }
  if ($l[1] -ne "every${TAB}15") { Fail "the second record is not every 15: $($l[1])" }

  Write-Host "== field counts"
  $slotLines = @($l | Where-Object { $_.StartsWith("slot${TAB}") })
  if ($slotLines.Count -ne 4) { Fail "not four slot records" }
  foreach ($s in $slotLines) { if (@($s -split "`t").Count -ne 8) { Fail "a slot record without eight fields: $s" } }
  if (-not ($OutRaw.Contains("`nslot${TAB}4${TAB}free${TAB}${TAB}${TAB}${TAB}${TAB}`n"))) { Fail "the free slot is not slot, 4, free and five empty fields" }

  Write-Host "== the interval is a config value"
  Set-WorktreesKey '"panelRefreshSeconds": 30'
  Run-P $work
  if ($Code -ne 0) { Fail "30: exit code $Code`: $Err" }
  Same "panelRefreshSeconds 30" $good.Replace("every${TAB}15`n", "every${TAB}30`n")
  foreach ($v in "5", "3600") {
    Set-WorktreesKey "`"panelRefreshSeconds`": $v"
    Run-P $work
    if ($Code -ne 0) { Fail "$v`: exit code $Code" }
    Same "panelRefreshSeconds $v" $good.Replace("every${TAB}15`n", "every${TAB}$v`n")
  }
  foreach ($v in "0", "4", "3601", "2.5", "15.0", '"15"', "true") {
    Set-WorktreesKey "`"panelRefreshSeconds`": $v"
    Run-P $work
    if ($Code -ne 0) { Fail "$v`: exit code $Code`: $Err" }
    Same "panelRefreshSeconds $v" ($good + $NoteInterval + "`n")
  }
  Set-WorktreesKey '"panelRefreshSeconds": null'
  Run-P $work
  if ($Code -ne 0) { Fail "null: exit code $Code" }
  Same "panelRefreshSeconds null" $good
  Write-Utf8 $cfgFile $withSlots
  Run-P $work
  Same "no panelRefreshSeconds" $good

  Write-Host "== the slot script's notes pass"
  Set-WorktreesKey '"stalledAfterMinutes": 0'
  Run-P $work
  if ($Code -ne 0) { Fail "stalledAfterMinutes 0: exit code $Code`: $Err" }
  Same "stalledAfterMinutes 0" ($good + "note${TAB}slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30`n")
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== an unreadable marker is never free"
  $mk2 = Join-Path $wt ".slots\slot-2.json"
  Write-Utf8 $mk2 "{ not json"
  Run-P $work
  if ($Code -ne 0) { Fail "unreadable marker: exit code $Code`: $Err" }
  if ($OutRaw -match "(?m)^slot`t2`tfree") { Fail "a slot with an unreadable marker is listed free" }
  # slot.ps1 fails on a marker that is not valid JSON: the whole read is an unknown record and no slot record
  if (-not ($OutRaw -cmatch "(?m)^unknown`t[^`t`n]+`n")) { Fail "an unreadable marker does not give an unknown record: $OutRaw" }
  if ($OutRaw -cmatch "(?m)^slot`t") { Fail "a slot record after a failed slot script: $OutRaw" }
  Write-Utf8 $mk2 $markersWritten["slot-2.json"]

  Write-Host "== a failing slot script is unknown"
  Run-P $work "" @{ WORKER_SLOTS = "abc" }
  if ($Code -ne 0) { Fail "WORKER_SLOTS=abc: exit code $Code`: $Err" }
  Same "WORKER_SLOTS=abc" "time${TAB}12:00:00`nevery${TAB}15`nunknown${TAB}WORKER_SLOTS must be a number from 1 to 99`n"
  Run-P $work
  Same "after WORKER_SLOTS" $good

  Write-Host "== without worktrees"
  Write-Utf8 $cfgFile $noSlots
  Run-P $work
  if ($Code -ne 0) { Fail "no worktrees: exit code $Code`: $Err" }
  Same "no worktrees" "time${TAB}12:00:00`nevery${TAB}15`nnoslots`n"
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== errors"
  foreach ($a in "--help", "x") {
    Run-P $work $a
    if ($Code -ne 2) { Fail "argument $a`: exit code $Code, expected 2" }
    if (-not $Err.Contains("usage: panel.ps1")) { Fail "argument $a`: no usage line: $Err" }
    if ($OutBytes.Length -ne 0) { Fail "argument $a`: output on standard output" }
  }
  Run-P $nogit
  if ($Code -ne 2) { Fail "outside a checkout: exit code $Code, expected 2" }
  if (-not $Err.Contains("run panel.ps1 from inside a checkout of the project")) { Fail "outside a checkout: $Err" }
  if ($OutBytes.Length -ne 0) { Fail "outside a checkout: output on standard output" }
  Run-P $plain
  if ($Code -ne 2) { Fail "no config: exit code $Code, expected 2" }
  if (-not $Err.Contains("run /nightmill:init")) { Fail "no config: $Err" }
  if ($OutBytes.Length -ne 0) { Fail "no config: output on standard output" }
  Write-Utf8 $cfgFile "{ not json"
  Run-P $work
  if ($Code -ne 2) { Fail "a config that is not valid JSON: exit code $Code, expected 2" }
  if (-not $Err.Contains("is not valid JSON")) { Fail "a config that is not valid JSON: $Err" }
  if ($OutBytes.Length -ne 0) { Fail "a config that is not valid JSON: output on standard output" }
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== nothing is changed"
  $after = (git -C $work status --porcelain --untracked-files=all) -join "`n"
  if ($after -ne $before) { Fail "git status of the project changed: $after" }
  $slotFiles = @(Get-ChildItem -Force (Join-Path $wt ".slots") | ForEach-Object { $_.Name })
  if ($slotFiles.Count -ne $markersWritten.Count) { Fail ".slots holds other files: $slotFiles" }
  foreach ($name in $markersWritten.Keys) {
    if (-not (Test-Path (Join-Path $wt ".slots\$name"))) { Fail "the marker $name is gone" }
    if ([IO.File]::ReadAllText((Join-Path $wt ".slots\$name")) -cne $markersWritten[$name]) { Fail "the marker $name changed" }
  }
  $root = @(Get-ChildItem -Force $wt | ForEach-Object { $_.Name })
  if ($root.Count -ne 1 -or $root[0] -ne ".slots") { Fail "the slot root holds more than .slots: $root" }
  if ([IO.File]::ReadAllText($ghLog).Trim()) { Fail "the panel called gh: $([IO.File]::ReadAllText($ghLog))" }
  $left = @(Get-ChildItem -Force $tdir | Where-Object { $_.Name -notlike "__PSScriptPolicyTest_*" } | ForEach-Object { $_.Name })
  if ($left.Count -ne 0) { Fail "the panel left files in its temporary folder: $left" }

  Write-Host "PANEL OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
