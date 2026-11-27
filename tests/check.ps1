# tests/check.ps1 - runs tests/check.sh through Git's bash, for a PowerShell prompt, with the same options.
#   powershell -ExecutionPolicy Bypass -File tests\check.ps1 [-Quick | -Only <step>[,<step>...] | -Affected [-Within <step>[,<step>...]]] [-Jobs <1-16>] [-Summary <file>]
#   -Quick       --quick: the lint and the bash smoke tests only; the full check does not run
#   -Only        --only: exactly the named steps
#   -Affected    --affected: the lint and the steps the paths changed against origin/<git.baseBranch> map to
#                (NIGHTMILL_CHECK_PATHS and NIGHTMILL_CHECK_MAP, for the tests, pass through to tests/check.sh)
#   -Within      --within (with -Affected only): of the named steps, those the changed paths select; where -Affected
#                alone would run the full check, exactly the named steps
#   -Jobs        --jobs: how many steps run at the same time (tests/check.sh checks the value)
#   -Summary     --summary: appends the check's wall time and its five slowest steps to this Markdown file
param([switch]$Quick, [string]$Only, [switch]$Affected, [string]$Within, [string]$Jobs, [string]$Summary)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) { Write-Error "bash not found (Git for Windows provides it)"; exit 2 }
$a = @()
if ($Quick) { $a += "--quick" }
if ($PSBoundParameters.ContainsKey("Only")) { $a += "--only"; $a += $Only }
if ($Affected) { $a += "--affected" }
if ($PSBoundParameters.ContainsKey("Within")) { $a += "--within"; $a += $Within }
if ($PSBoundParameters.ContainsKey("Jobs")) { $a += "--jobs"; $a += $Jobs }
if ($PSBoundParameters.ContainsKey("Summary")) { $a += "--summary"; $a += $Summary }
& $bash.Source "$root/tests/check.sh" @a
exit $LASTEXITCODE
