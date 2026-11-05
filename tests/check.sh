#!/usr/bin/env bash
# tests/check.sh - the local equivalent of CI, in one command (verification.check in .claude/nightmill.json).
#   1. tests/lint.sh
#   2. the bash smoke tests (they need git and the tools every POSIX shell has, no jq)
#   3. the PowerShell smoke tests (when powershell or pwsh is on the PATH)
#   4. claude plugin validate --strict (when claude is on the PATH)
# Exit code is non-zero when any step that ran failed. Skipped steps are listed at the end.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
failed=(); skipped=()

run() { # run <name> <command...>
  local name=$1; shift
  echo; echo "== $name"
  if "$@"; then echo "-- $name: ok"; else echo "-- $name: FAILED"; failed+=("$name"); fi
}

run "lint" bash tests/lint.sh
run "smoke-json.sh" bash tests/smoke-json.sh
run "smoke-hook.sh" bash tests/smoke-hook.sh
run "smoke-release.sh" bash tests/smoke-release.sh
run "smoke-slot.sh" bash tests/smoke-slot.sh
run "smoke-render.sh" bash tests/smoke-render.sh
run "smoke-validate.sh" bash tests/smoke-validate.sh
run "smoke-status.sh" bash tests/smoke-status.sh
run "smoke-template-board.sh" bash tests/smoke-template-board.sh

ps=""
if command -v pwsh >/dev/null 2>&1; then ps=pwsh; elif command -v powershell >/dev/null 2>&1; then ps=powershell; fi
if [ -n "$ps" ]; then
  run "smoke-slot.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-slot.ps1
  run "smoke-render.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-render.ps1
  run "smoke-hook.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-hook.ps1
  run "smoke-release.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-release.ps1
  run "smoke-validate.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-validate.ps1
  run "smoke-status.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-status.ps1
  run "smoke-template-board.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-template-board.ps1
else
  skipped+=("PowerShell smoke tests (no pwsh or powershell)")
fi

if command -v claude >/dev/null 2>&1; then
  run "claude plugin validate" claude plugin validate . --strict
else
  skipped+=("claude plugin validate (claude is not installed)")
fi

echo
for s in ${skipped[@]+"${skipped[@]}"}; do echo "SKIPPED: $s"; done
if [ ${#failed[@]} -gt 0 ]; then echo "CHECK FAILED: ${failed[*]}"; exit 1; fi
echo "ALL CHECKS PASSED"
