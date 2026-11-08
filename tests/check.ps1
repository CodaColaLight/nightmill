# tests/check.ps1 - runs tests/check.sh through Git's bash, for a PowerShell prompt, with the same options.
#   powershell -ExecutionPolicy Bypass -File tests\check.ps1 [-Quick | -Only <step>[,<step>...]] [-Jobs <1-16>] [-PowerShell powershell|pwsh]
#   -Quick       --quick: the lint and the bash smoke tests only; the full check does not run
#   -Only        --only: exactly the named steps
#   -Jobs        --jobs: how many steps run at the same time (tests/check.sh checks the value)
#   -PowerShell  --powershell: the PowerShell for the PowerShell smoke tests
param([switch]$Quick, [string]$Only, [string]$Jobs, [string]$PowerShell)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) { Write-Error "bash not found (Git for Windows provides it)"; exit 2 }
$a = @()
if ($Quick) { $a += "--quick" }
if ($PSBoundParameters.ContainsKey("Only")) { $a += "--only"; $a += $Only }
if ($PSBoundParameters.ContainsKey("Jobs")) { $a += "--jobs"; $a += $Jobs }
if ($PSBoundParameters.ContainsKey("PowerShell")) { $a += "--powershell"; $a += $PowerShell }
& $bash.Source "$root/tests/check.sh" @a
exit $LASTEXITCODE
