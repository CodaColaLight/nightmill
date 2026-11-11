#!/usr/bin/env bash
# tests/ci-jobs-summary.sh - the job table of a CI run as Markdown (iteration 55, decision 7), for the run's summary page.
#   tests/ci-jobs-summary.sh --parts <prefix> [--now <stamp>]
# Reads on standard input lines of five tab-separated fields (the final job of .github/workflows/ci.yml makes them
# from the jobs API with gh api --jq):
#   job  <job name> <result> <start> <end>
#   step <job name> <step name> <start> <end>
# Stamps are YYYY-MM-DDTHH:MM:SSZ; either may be empty. Prints a table of every job's wall time, in input order, the
# line of the chain of the jobs whose name begins with <prefix> (the earliest start to the latest end), and per job its
# five slowest steps. A job or step without an end counts to --now and is marked (running); without --now a job says
# running and such a step is left out. A stamp that does not parse gives ? (a job) or leaves the step out. A line of
# another kind or with fewer than five fields is skipped. Exit 0, or 2 with the usage on standard error. Needs no jq
# and no network.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$here/scripts/lib/ledger.sh"

USAGE='usage: tests/ci-jobs-summary.sh --parts <prefix> [--now <stamp>]'
usage() { echo "$USAGE" >&2; exit 2; }
is_stamp() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; }

parts=""; have_parts=0; now=""; have_now=0
while [ $# -gt 0 ]; do
  case $1 in
    --parts) [ $# -ge 2 ] || usage; [ "$have_parts" = 0 ] || usage; parts=$2; have_parts=1; shift 2 ;;
    --now) [ $# -ge 2 ] || usage; [ "$have_now" = 0 ] || usage; is_stamp "$2" || usage; now=$2; have_now=1; shift 2 ;;
    *) usage ;;
  esac
done
[ "$have_parts" = 1 ] || usage
now_s=""
[ "$have_now" = 0 ] || now_s=$(ledger_epoch "$now")

# secs_of <start> <end>: sets secs (the seconds, or empty when they cannot be told) and run (1 when counted to --now)
secs_of() {
  secs=""; run=0
  is_stamp "$1" || return 0
  if [ -z "$2" ]; then
    [ -n "$now_s" ] || return 0
    secs=$((now_s - $(ledger_epoch "$1"))); run=1
  elif is_stamp "$2"; then
    secs=$(($(ledger_epoch "$2") - $(ledger_epoch "$1")))
  fi
}

nj=0; ns=0
j_name=(); j_res=(); j_wall=(); s_job=(); s_name=(); s_secs=(); s_run=()
chain_min=""; chain_max=""; chain_n=0
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  # split on every tab, so an empty field keeps its place
  f=()
  while :; do
    case $line in *$'\t'*) f+=("${line%%$'\t'*}"); line=${line#*$'\t'} ;; *) f+=("$line"); break ;; esac
  done
  [ "${#f[@]}" -ge 5 ] || continue
  case ${f[0]} in
    job)
      j_name[nj]=${f[1]}; j_res[nj]=${f[2]}
      secs_of "${f[3]}" "${f[4]}"
      if ! is_stamp "${f[3]}" || { [ -n "${f[4]}" ] && ! is_stamp "${f[4]}"; }; then
        j_wall[nj]="?"
      elif [ -z "${f[4]}" ] && [ -z "$now_s" ]; then
        j_wall[nj]="running"
      elif [ "$run" = 1 ]; then
        j_wall[nj]="$(ledger_duration "$secs") (running)"
      else
        j_wall[nj]=$(ledger_duration "$secs")
      fi
      case ${f[1]} in
        "$parts"*)
          if is_stamp "${f[3]}" && is_stamp "${f[4]}"; then
            a=$(ledger_epoch "${f[3]}"); b=$(ledger_epoch "${f[4]}")
            { [ -n "$chain_min" ] && [ "$chain_min" -le "$a" ]; } || chain_min=$a
            { [ -n "$chain_max" ] && [ "$chain_max" -ge "$b" ]; } || chain_max=$b
            chain_n=$((chain_n + 1))
          fi ;;
      esac
      nj=$((nj + 1)) ;;
    step)
      secs_of "${f[3]}" "${f[4]}"
      [ -n "$secs" ] || continue
      s_job[ns]=${f[1]}; s_name[ns]=${f[2]}; s_secs[ns]=$secs; s_run[ns]=$run
      ns=$((ns + 1)) ;;
  esac
done

echo "### Job times"
echo
echo "| Job | Result | Wall time |"
echo "|---|---|---|"
for ((i = 0; i < nj; i++)); do
  echo "| ${j_name[i]} | ${j_res[i]} | ${j_wall[i]} |"
done
echo
if [ "$chain_n" -gt 0 ]; then
  echo "PowerShell scripts smoke tests: $(ledger_duration $((chain_max - chain_min))) from the start of the first part to the end of the last ($chain_n parts)."
  echo
fi
for ((i = 0; i < nj; i++)); do
  rows=$(for ((k = 0; k < ns; k++)); do
    [ "${s_job[k]}" != "${j_name[i]}" ] || printf '%s\t%s\n' "${s_secs[k]}" "$k"
  done | sort -t$'\t' -k1,1nr -k2,2n | head -n 5)
  [ -n "$rows" ] || continue
  echo "#### Slowest steps: ${j_name[i]}"
  echo
  echo "| Step | Time |"
  echo "|---|---|"
  while IFS=$'\t' read -r _ k; do
    mark=""; [ "${s_run[k]}" != 1 ] || mark=" (running)"
    echo "| ${s_name[k]} | $(ledger_duration "${s_secs[k]}")$mark |"
  done <<<"$rows"
  echo
done
exit 0
