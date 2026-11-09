#!/usr/bin/env bash
# tests/check.sh - the local equivalent of CI, in one command (verification.check in .claude/nightmill.json).
#   tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh]
# The steps are the lines of the step list below (between '# steps: begin' and '# steps: end'; tests/lint.sh reads it
# and fails on a smoke script that is not in it), then the two claude steps:
#   lint                      tests/lint.sh
#   bash <file>               the bash smoke tests and regression tests (they need git and the tools every POSIX shell has, no jq)
#   ps <file>                 the PowerShell smoke tests (when powershell or pwsh is on the PATH)
#   claude plugin validate    claude plugin validate --strict (when claude is on the PATH)
#   claude plugin test        claude plugin test . (the module test hooks/panel.test.tsx; when claude has it)
# Up to L steps run at the same time (iteration 42): L is --jobs N, else verification.checkJobs, else 4; the last two
# are capped at the machine's processors, and any UPDATE_*_FIXTURES=1 makes L 1. With L = 1 the steps run one after
# another in the foreground; with more, each step's output goes to a file of its own and is printed whole, in the
# order of the list, whatever order the steps finish in. The steps marked 'first' are started before the others. The
# two claude steps run one after the other in one job.
#   --quick        the lint and the bash smoke tests only; never prints the line of a passed full check
#   --only a,b     exactly the named steps (CI runs its smoke jobs this way)
#   --jobs N       the limit for this run, 1 to 16, not capped
#   --powershell   the PowerShell for the ps steps (default: pwsh, else powershell)
# Exit code is non-zero when any step that ran failed (2 for a usage error). Skipped steps are listed at the end. Each
# result line carries the step's time, and a Times: block after the last step lists every step's time and the total
# (iteration 41; the total is the wall time from the start to the end of the last step).
# For the tests only: NIGHTMILL_CHECK_STEPS names a file of <name> TAB <command> [TAB <kind> [TAB <reason> [TAB first]]]
# lines (kind lint, bash, ps or claude; bash when left out; a step with a reason is not run and is listed as SKIPPED:
# <reason>; first marks a step to start first, as in the step list; empty fields keep their place); the check then runs exactly those steps (bash -c <command>) instead of its own. NIGHTMILL_CLOCK_FILE (see
# scripts/lib/ledger.sh) is the clock the times are read from. CI sets neither.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
. scripts/lib/ledger.sh
. scripts/lib/json.sh

USAGE='usage: tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh]'
usage() { echo "$USAGE" >&2; exit 2; }
whole_1_16() { [[ "$1" =~ ^[1-9][0-9]?$ ]] && [ "$1" -le 16 ]; }

mode=full; only=""; jobs=""; psopt=""; seen=" "
while [ $# -gt 0 ]; do
  case $1 in
    --quick|--only|--jobs|--powershell)
      case $seen in *" $1 "*) usage ;; esac
      seen="$seen$1 " ;;
  esac
  case $1 in
    --quick) mode=quick; shift ;;
    --only) { [ $# -ge 2 ] && [ -n "$2" ]; } || usage; only=$2; mode=only; shift 2 ;;
    --jobs) [ $# -ge 2 ] || usage; whole_1_16 "$2" || usage; jobs=$2; shift 2 ;;
    --powershell) [ $# -ge 2 ] || usage; case $2 in powershell|pwsh) psopt=$2 ;; *) usage ;; esac; shift 2 ;;
    *) usage ;;
  esac
done
case $seen in *" --quick "*) case $seen in *" --only "*) usage ;; esac ;; esac

# The step list: k_kind, k_name, k_first ('first' or empty), k_skip (a reason, or empty), k_cmd (fixture steps only)
n=0
add() { # add <kind> <name> [first]
  k_kind[n]=$1; k_name[n]=$2; k_first[n]=${3:-}; k_skip[n]=""; k_cmd[n]=""; n=$((n + 1))
}

ps=""
if [ -n "$psopt" ]; then
  if command -v "$psopt" >/dev/null 2>&1; then ps=$psopt; fi
elif command -v pwsh >/dev/null 2>&1; then ps=pwsh
elif command -v powershell >/dev/null 2>&1; then ps=powershell
fi

real_steps() {
# steps: begin
add lint lint
add bash smoke-json.sh
add bash smoke-hook.sh
add bash smoke-release.sh
add bash smoke-slot.sh first
add bash smoke-render.sh
add bash smoke-validate.sh
add bash smoke-status.sh
add bash smoke-template-board.sh
add bash smoke-models.sh
add bash smoke-load.sh
add bash smoke-room.sh
add bash smoke-control.sh
add bash smoke-dashboard.sh
add bash smoke-panel.sh
add bash smoke-stages.sh
add bash smoke-check.sh
add bash test-lintcopy-output.sh
add bash test-lint-pipefail.sh
add bash test-release-resume.sh
add bash test-json-bom.sh
add bash test-render-quoting.sh
add ps smoke-slot.ps1 first
add ps smoke-render.ps1
add ps smoke-hook.ps1
add ps smoke-release.ps1
add ps smoke-validate.ps1
add ps smoke-status.ps1
add ps smoke-template-board.ps1
add ps smoke-models.ps1
add ps smoke-load.ps1
add ps smoke-room.ps1
add ps smoke-control.ps1
add ps smoke-dashboard.ps1
add ps smoke-panel.ps1
add ps smoke-stages.ps1
add ps smoke-check.ps1
add ps test-lintcopy-output.ps1
add ps test-release-resume.ps1
add ps test-json-bom.ps1
add ps test-render-quoting.ps1
# steps: end
  local i
  if [ -z "$ps" ]; then
    for ((i = 0; i < n; i++)); do
      [ "${k_kind[i]}" != ps ] || k_skip[i]="PowerShell smoke tests (no pwsh or powershell)"
    done
  fi
  add claude "claude plugin validate"
  add claude "claude plugin test"
  if command -v claude >/dev/null 2>&1; then
    if ! claude plugin test --help >/dev/null 2>&1 </dev/null; then
      k_skip[n - 1]="claude plugin test not available"
    fi
  else
    k_skip[n - 2]="claude plugin validate (claude is not installed)"
    k_skip[n - 1]="claude plugin test not available"
  fi
}

if [ -n "${NIGHTMILL_CHECK_STEPS:-}" ]; then
  # Split on every tab, so an empty field (an empty reason before 'first') keeps its place; read with IFS=$'\t'
  # would merge adjacent tabs, because a tab is IFS white space.
  while IFS= read -r f_line || [ -n "$f_line" ]; do
    f_line=${f_line%$'\r'}
    f=(); while :; do
      case $f_line in *$'\t'*) f+=("${f_line%%$'\t'*}"); f_line=${f_line#*$'\t'} ;; *) f+=("$f_line"); break ;; esac
    done
    f_name=${f[0]}; f_cmd=${f[1]:-}; f_kind=${f[2]:-}; f_reason=${f[3]:-}; f_first=${f[4]:-}
    [ -n "$f_name" ] || continue
    case ${f_kind:-bash} in lint|bash|ps|claude) ;; *) echo "check: $NIGHTMILL_CHECK_STEPS: unknown kind $f_kind" >&2; exit 2 ;; esac
    case $f_first in ""|first) ;; *) echo "check: $NIGHTMILL_CHECK_STEPS: the fifth field is first or empty, not $f_first" >&2; exit 2 ;; esac
    add "${f_kind:-bash}" "$f_name" $f_first
    k_cmd[n - 1]=$f_cmd; k_skip[n - 1]=$f_reason
  done < "$NIGHTMILL_CHECK_STEPS"
  fixture=1
else
  real_steps
  fixture=0
fi

# The selection: sel[i] is 1 for a step this run takes
for ((i = 0; i < n; i++)); do
  case $mode in
    full) sel[i]=1 ;;
    quick) case ${k_kind[i]} in lint|bash) sel[i]=1 ;; *) sel[i]=0 ;; esac ;;
    only) sel[i]=0 ;;
  esac
done
if [ "$mode" = only ]; then
  rest=$only,
  while [ -n "$rest" ]; do
    want=${rest%%,*}; rest=${rest#*,}
    [ -n "$want" ] || usage
    hit=""
    for ((i = 0; i < n; i++)); do
      if [ "${k_name[i]}" = "$want" ]; then sel[i]=1; hit=1; fi
    done
    [ -n "$hit" ] || { echo "check: no step named $want" >&2; usage; }
  done
fi

# The limit L and why
if [ -n "$jobs" ]; then
  L=$jobs; why="--jobs $jobs"
else
  L=4; why="default 4"
  if [ -f .claude/nightmill.json ] && json_load .claude/nightmill.json >/dev/null 2>&1; then
    if json_has verification.checkJobs; then
      v=$(json_get verification.checkJobs)
      if whole_1_16 "$v"; then
        L=$v; why="verification.checkJobs $v"
      else
        echo "check: verification.checkJobs must be a whole number from 1 to 16; using 4" >&2
      fi
    fi
  fi
  procs=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  if [[ "$procs" =~ ^[0-9]+$ ]] && [ "$procs" -ge 1 ] && [ "$L" -gt "$procs" ]; then
    L=$procs; why="$why, capped at $procs processors"
  fi
fi
for u in UPDATE_STATUS_FIXTURES UPDATE_DASHBOARD_FIXTURES UPDATE_PANEL_FIXTURES; do
  if [ "${!u:-}" = 1 ]; then L=1; why="$u is set"; break; fi
done

case $mode in
  full) echo "check: full, $L at a time ($why)" ;;
  quick) echo "check: QUICK, $L at a time ($why): the lint and the bash smoke tests only; the full check does not run" ;;
  only)
    names=""
    for ((i = 0; i < n; i++)); do [ "${sel[i]}" = 1 ] && names="$names${names:+,}${k_name[i]}"; done
    echo "check: only $names, $L at a time ($why)" ;;
esac

# step_cmd <i>: runs step i
step_cmd() {
  local i=$1
  if [ "$fixture" = 1 ]; then bash -c "${k_cmd[i]}"; return; fi
  case ${k_kind[i]} in
    lint) bash tests/lint.sh ;;
    bash) bash "tests/${k_name[i]}" ;;
    ps) "$ps" -NoProfile -ExecutionPolicy Bypass -File "tests/${k_name[i]}" ;;
    claude)
      case ${k_name[i]} in
        "claude plugin validate") claude plugin validate . --strict ;;
        "claude plugin test") claude plugin test . ;;
      esac ;;
  esac
}

failed=(); times=()
ledger_clock; check_start=$ledger_s; check_end=$ledger_s
# result <i> <rc> <t0> <t1>: the result line of step i, its time and the verdict
result() {
  local name=${k_name[$1]} d
  d=$(ledger_duration $(($4 - $3)))
  if [ "$2" = 0 ]; then echo "-- $name: ok ($d)"; else echo "-- $name: FAILED ($d)"; failed+=("$name"); fi
  [ "$4" -le "$check_end" ] || check_end=$4
  times+=("$(printf '  %-28s %8s' "$name" "$d")")
}
# times_block: the Times: block (every step that ran, in list order, then the total from the start to the end of the
# last step)
times_block() {
  local l
  echo
  echo "Times:"
  for l in ${times[@]+"${times[@]}"}; do printf '%s\n' "$l"; done
  printf '  %-28s %8s\n' total "$(ledger_duration $((check_end - check_start)))"
}

# The steps that run, in list order (prints), and the jobs, in start order (starts: the steps marked first, then the
# rest). Consecutive claude steps form one group: they run one after the other in the job of the first (g_next).
prints=(); starts=(); lead=""
for ((i = 0; i < n; i++)); do
  g_next[i]=""; s_job[i]=""
  [ "${sel[i]}" = 1 ] && [ -z "${k_skip[i]}" ] || { lead=""; continue; }
  prints+=("$i")
  if [ "${k_kind[i]}" = claude ] && [ -n "$lead" ]; then
    j=$lead; while [ -n "${g_next[j]}" ]; do j=${g_next[j]}; done
    g_next[j]=$i; s_job[i]=$lead
  else
    s_job[i]=$i
    if [ "${k_kind[i]}" = claude ]; then lead=$i; else lead=""; fi
  fi
done
# With L = 1 the start order is the list order (the 'first' marks are ignored)
if [ "$L" = 1 ]; then
  starts=(${prints[@]+"${prints[@]}"})
else
  for pass in first rest; do
    for i in ${prints[@]+"${prints[@]}"}; do
      [ "${s_job[i]}" = "$i" ] || continue
      if { [ "$pass" = first ] && [ "${k_first[i]}" = first ]; } || { [ "$pass" = rest ] && [ "${k_first[i]}" != first ]; }; then
        starts+=("$i")
      fi
    done
  done
fi

dir=""; started=()
# stop_jobs: TERM to every job this run started that still runs, then the run's folder is removed
stop_jobs() {
  local s
  for s in ${started[@]+"${started[@]}"}; do
    [ "${j_live[s]}" != 1 ] || kill -TERM "${j_pid[s]}" 2>/dev/null
  done
  [ -z "$dir" ] || rm -rf "$dir"
}
interrupted() {
  stop_jobs
  echo
  echo "CHECK INTERRUPTED"
  exit 130
}
trap interrupted INT TERM

if [ "$L" = 1 ]; then
  for i in ${prints[@]+"${prints[@]}"}; do
    echo; echo "== ${k_name[i]}"
    ledger_clock; t0=$ledger_s
    step_cmd "$i" </dev/null; rc=$?
    ledger_clock
    result "$i" "$rc" "$t0" "$ledger_s"
  done
else
  dir=$(mktemp -d) || { echo "check: mktemp -d failed" >&2; exit 1; }
  trap stop_jobs EXIT
  # start_job <i>: step i (and the steps of its group) as one background job
  start_job() {
    local i=$1
    (
      j=$i
      while [ -n "$j" ]; do
        ledger_clock; t0=$ledger_s
        step_cmd "$j" > "$dir/$j.log" 2>&1 < /dev/null; rc=$?
        ledger_clock; t1=$ledger_s
        printf '%s %s %s\n' "$rc" "$t0" "$t1" > "$dir/$j.tmp" && mv "$dir/$j.tmp" "$dir/$j.done"
        j=${g_next[j]}
      done
    ) &
    j_pid[i]=$!; j_live[i]=1; started+=("$i")
    ledger_clock; j_t0[i]=$ledger_s
  }
  ns=${#starts[@]}; np=${#prints[@]}; next=0; running=0; p=0
  while [ "$p" -lt "$np" ]; do
    for ((q = 0; q < next; q++)); do
      i=${starts[q]}
      if [ "${j_live[i]}" = 1 ] && ! kill -0 "${j_pid[i]}" 2>/dev/null; then
        wait "${j_pid[i]}" 2>/dev/null; j_live[i]=0; running=$((running - 1))
      fi
    done
    while [ "$running" -lt "$L" ] && [ "$next" -lt "$ns" ]; do
      start_job "${starts[next]}"; next=$((next + 1)); running=$((running + 1))
    done
    while [ "$p" -lt "$np" ]; do
      i=${prints[p]}; job=${s_job[i]}
      if [ -f "$dir/$i.done" ]; then
        read -r rc t0 t1 < "$dir/$i.done"
        echo; echo "== ${k_name[i]}"
        cat "$dir/$i.log"
        result "$i" "$rc" "$t0" "$t1"
      elif [ -n "${j_live[job]:-}" ] && ! kill -0 "${j_pid[job]}" 2>/dev/null && [ ! -f "$dir/$i.done" ]; then
        ledger_clock
        echo; echo "== ${k_name[i]}"
        [ ! -f "$dir/$i.log" ] || cat "$dir/$i.log"
        echo "(the step ended without a result)"
        result "$i" 1 "${j_t0[job]}" "$ledger_s"
      else
        break
      fi
      p=$((p + 1))
    done
    [ "$p" -ge "$np" ] || sleep 0.2
  done
  wait 2>/dev/null
fi

times_block
echo
# the steps that cannot run, in list order, each text once (the steps --quick leaves out are not listed)
shown="|"
for ((i = 0; i < n; i++)); do
  [ "${sel[i]}" = 1 ] && [ -n "${k_skip[i]}" ] || continue
  case $shown in *"|${k_skip[i]}|"*) continue ;; esac
  shown="$shown${k_skip[i]}|"
  echo "SKIPPED: ${k_skip[i]}"
done
case $mode in
  quick)
    if [ ${#failed[@]} -gt 0 ]; then echo "QUICK CHECK FAILED: ${failed[*]} (the full check has not run)"; exit 1; fi
    echo "QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)"
    exit 0 ;;
  only)
    if [ ${#failed[@]} -gt 0 ]; then echo "SELECTED CHECKS FAILED: ${failed[*]} (the full check has not run)"; exit 1; fi
    k=0; for ((i = 0; i < n; i++)); do [ "${sel[i]}" = 1 ] && k=$((k + 1)); done
    echo "SELECTED CHECKS PASSED ($k of $n steps; the full check has not run)"
    exit 0 ;;
esac
if [ ${#failed[@]} -gt 0 ]; then echo "CHECK FAILED: ${failed[*]}"; exit 1; fi
echo "ALL CHECKS PASSED"
