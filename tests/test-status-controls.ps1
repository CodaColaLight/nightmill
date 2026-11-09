# tests/test-status-controls.ps1 - regression for #134, PowerShell twin of test-status-controls.sh: an issue title
# with terminal control characters (ESC, BEL, DEL, written as JSON \u escapes) must not reach the output of
# status.ps1, in the table or with -Porcelain. Not run on the machine where it was written (no PowerShell there).
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$S = Join-Path $here "scripts\status.ps1"
$FIX = Join-Path $here "tests\fixtures\status-controls"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-statusctl-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

try {
  $work = Join-Path $tmp "work"
  git init -q -b main $work
  New-Item -ItemType Directory (Join-Path $work ".claude") | Out-Null
  Write-Utf8 (Join-Path $work ".claude\nightmill.json") @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" }
}
'@
  $bin = Join-Path $tmp "bin"
  New-Item -ItemType Directory $bin | Out-Null
  Write-Utf8 (Join-Path $bin "gh-fake.ps1") @'
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

  $env:GH_FIX = $FIX
  $env:NIGHTMILL_NOW = "1793880000"
  $env:PATH = "$bin;$env:PATH"

  foreach ($mode in @("table", "porcelain")) {
    Write-Host "== ${mode}: controls removed from the title"
    Push-Location $work
    try {
      if ($mode -eq "porcelain") { $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $S -Porcelain 2>&1 | Out-String }
      else { $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $S 2>&1 | Out-String }
      $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code -ne 0) { Fail "${mode}: exit code ${code}: $out" }
    if ($out -notmatch 'RED') { Fail "${mode}: the title is not printed at all" }
    if ($out -match '[\x01-\x08\x0B-\x1F\x7F]') { Fail "${mode}: a control character from the title reached the output" }
    if (-not $out.Contains('x[31mRED]0;textend')) { Fail "${mode}: the printable text of the title was not kept" }
  }
  Write-Host "ok"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
