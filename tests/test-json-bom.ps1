# tests/test-json-bom.ps1 - regression for #132, PowerShell twin of test-json-bom.sh: a config saved with a UTF-8
# byte order mark (Windows PowerShell 5.1 Set-Content -Encoding UTF8) is accepted by validate-config.ps1.
# Not run on the machine where it was written (no PowerShell there).
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-bom-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }

$utf8 = New-Object System.Text.UTF8Encoding $false
$text = [IO.File]::ReadAllText((Join-Path $here "templates\nightmill.example.json"), $utf8)
$file = Join-Path $tmp "bom.json"
$bytes = [byte[]](0xEF, 0xBB, 0xBF) + $utf8.GetBytes($text)
[IO.File]::WriteAllBytes($file, $bytes)

Write-Host "== validate-config.ps1 accepts a config with a BOM"
$out = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "scripts\validate-config.ps1") -Config $file 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail "validate-config.ps1 exit $LASTEXITCODE on a BOM config: $out" }
if ($out -match "not valid JSON") { Fail "BOM config reported as not valid JSON: $out" }
Remove-Item -Recurse -Force $tmp
Write-Host "ok"
