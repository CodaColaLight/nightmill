#!/usr/bin/env bash
# tests/check.sh - the local equivalent of CI, in one command (verification.check in .claude/nightmill.json).
#   1. tests/lint.sh
#   2. the bash smoke tests (they need git and the tools every POSIX shell has, no jq)
#   3. the PowerShell smoke tests (when powershell or pwsh is on the PATH)
#   4. claude plugin validate --strict (when claude is on the PATH)
#   5. claude plugin test . (the module test hooks/panel.test.tsx; when claude has the plugin test subcommand)
# Exit code is non-zero when any step that ran failed. Skipped steps are listed at the end. Each result line carries the
# step's time, and a Times: block after the last step lists every step's time and the total (iteration 41).
# For the tests only: NIGHTMILL_CHECK_STEPS names a file of <name> TAB <command> lines; the check then runs exactly
# those steps (bash -c <command>) instead of its own, without its PowerShell and claude steps and without a SKIPPED:
# line. NIGHTMILL_CLOCK_FILE (see scripts/lib/ledger.sh) is the clock the times are read from. CI sets neither.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
. scripts/lib/ledger.sh
failed=(); skipped=(); times=()

ledger_clock; check_start=$ledger_s; check_end=$ledger_s
run() { # run <name> <command...>
  local name=$1 t0 d; shift
  echo; echo "== $name"
  ledger_clock; t0=$ledger_s
  if "$@"; then
    ledger_clock; d=$(ledger_duration $((ledger_s - t0))); echo "-- $name: ok ($d)"
  else
    ledger_clock; d=$(ledger_duration $((ledger_s - t0))); echo "-- $name: FAILED ($d)"; failed+=("$name")
  fi
  check_end=$ledger_s
  times+=("$(printf '  %-28s %8s' "$name" "$d")")
}
# times_block: the Times: block (every step that ran, then the total from the start to the end of the last step)
times_block() {
  local l
  echo
  echo "Times:"
  for l in ${times[@]+"${times[@]}"}; do printf '%s\n' "$l"; done
  printf '  %-28s %8s\n' total "$(ledger_duration $((check_end - check_start)))"
}

if [ -n "${NIGHTMILL_CHECK_STEPS:-}" ]; then
  while IFS=$'\t' read -r step_name step_cmd || [ -n "$step_name" ]; do
    [ -n "$step_name" ] || continue
    run "$step_name" bash -c "$step_cmd" </dev/null
  done < "$NIGHTMILL_CHECK_STEPS"
  times_block
  echo
  if [ ${#failed[@]} -gt 0 ]; then echo "CHECK FAILED: ${failed[*]}"; exit 1; fi
  echo "ALL CHECKS PASSED"
  exit 0
fi

run "lint" bash tests/lint.sh
run "smoke-json.sh" bash tests/smoke-json.sh
run "smoke-hook.sh" bash tests/smoke-hook.sh
run "smoke-release.sh" bash tests/smoke-release.sh
run "smoke-slot.sh" bash tests/smoke-slot.sh
run "smoke-render.sh" bash tests/smoke-render.sh
run "smoke-validate.sh" bash tests/smoke-validate.sh
run "smoke-status.sh" bash tests/smoke-status.sh
run "smoke-template-board.sh" bash tests/smoke-template-board.sh
run "smoke-models.sh" bash tests/smoke-models.sh
run "smoke-load.sh" bash tests/smoke-load.sh
run "smoke-room.sh" bash tests/smoke-room.sh
run "smoke-control.sh" bash tests/smoke-control.sh
run "smoke-dashboard.sh" bash tests/smoke-dashboard.sh
run "smoke-panel.sh" bash tests/smoke-panel.sh
run "smoke-stages.sh" bash tests/smoke-stages.sh

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
  run "smoke-models.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-models.ps1
  run "smoke-load.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-load.ps1
  run "smoke-room.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-room.ps1
  run "smoke-control.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-control.ps1
  run "smoke-dashboard.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-dashboard.ps1
  run "smoke-panel.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-panel.ps1
  run "smoke-stages.ps1" "$ps" -NoProfile -ExecutionPolicy Bypass -File tests/smoke-stages.ps1
else
  skipped+=("PowerShell smoke tests (no pwsh or powershell)")
fi

if command -v claude >/dev/null 2>&1; then
  run "claude plugin validate" claude plugin validate . --strict
  if claude plugin test --help >/dev/null 2>&1 </dev/null; then
    run "claude plugin test" claude plugin test .
  else
    skipped+=("claude plugin test not available")
  fi
else
  skipped+=("claude plugin validate (claude is not installed)")
  skipped+=("claude plugin test not available")
fi

times_block
echo
for s in ${skipped[@]+"${skipped[@]}"}; do echo "SKIPPED: $s"; done
if [ ${#failed[@]} -gt 0 ]; then echo "CHECK FAILED: ${failed[*]}"; exit 1; fi
echo "ALL CHECKS PASSED"
