# scripts/session-start.ps1 - the SessionStart hook (PowerShell). Where nightmill is enabled but the project
# has no .claude/nightmill.json, prints one line that makes Claude offer /nightmill:init. Silent when the
# config exists, when NIGHTMILL_HINT=off (any case), or when the project directory does not exist.
# hooks/hooks.json wires session-start.sh; this script is the same behaviour for a machine that runs hooks
# through PowerShell only, to be wired by hand (see the README).
# Always exits 0: a hook must never break a session. ASCII only, no BOM needed.
#   CLAUDE_PROJECT_DIR   the project root (set by Claude Code); the current directory when unset
#   NIGHTMILL_HINT=off   never print the line (for plugins enabled at user scope)
$ErrorActionPreference = "SilentlyContinue"

if ($env:NIGHTMILL_HINT -and ($env:NIGHTMILL_HINT -ieq "off")) { exit 0 }

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { $root = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $root -PathType Container)) { exit 0 }
if (Test-Path -LiteralPath (Join-Path $root ".claude/nightmill.json") -PathType Leaf) { exit 0 }

Write-Output 'nightmill is enabled in this project but not set up (no .claude/nightmill.json). Offer the user to run /nightmill:init, a short install chat that creates the board, labels, config and issue forms. Mention it once; do not run it unless the user agrees.'
exit 0
