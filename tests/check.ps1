# tests/check.ps1 - runs tests/check.sh through Git's bash, for a PowerShell prompt.
#   powershell -ExecutionPolicy Bypass -File tests\check.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) { Write-Error "bash not found (Git for Windows provides it)"; exit 2 }
& $bash.Source "$root/tests/check.sh"
exit $LASTEXITCODE
