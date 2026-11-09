#!/usr/bin/env bash
# scripts/load.sh - the machine's CPU load and free memory, the agent limit, the slots in use and a suggested agent
# limit with the reason (nightmill). Bash twin of load.ps1; the rules and the texts are in
# docs/specs/iteration-24-machine-load.md.
#
#   load.sh [--porcelain]      # --porcelain: one tab separated line per value, by name, for scripts
#
# Run it from inside the project: any checkout or worktree of it. It measures for parallel.loadWindowSeconds seconds
# (default 10), one sample a second (scripts/lib/load.sh), reads the agent limit and the slots from slot.sh --capacity
# --porcelain and slot.sh --status --porcelain, and prints. It only reads: it never changes the agent limit or the
# slot count (slot.sh --capacity --agent-limit N does that).
# Exit code 0 with a suggestion, 1 when the CPU load or the free memory is unavailable (no suggestion), 2 for a usage
# error, no checkout, no or invalid config, a failed slot script or an unusable NIGHTMILL_LOAD_FIXTURE.
set -euo pipefail

usage() { echo "usage: load.sh [--porcelain]" >&2; exit 2; }

porcelain=0
while [ $# -gt 0 ]; do
  case "$1" in
    --porcelain) porcelain=1 ;;
    *) usage ;;
  esac
  shift
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/json.sh
. "$here/lib/json.sh"
# shellcheck source=scripts/lib/load.sh
. "$here/lib/load.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "load: run load.sh from inside a checkout of the project" >&2; exit 2; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "load: no $cfg (run /nightmill:init)" >&2; exit 2; }
json_load "$cfg" || exit 2

load_settings

# The slot numbers, from the slot script of the same plugin (its standard error passes through)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-load.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
slot_call() { # slot_call <output file> <arguments...>
  local out=$1
  shift
  if ! bash "$here/slot.sh" "$@" > "$out" 2> "$tmp/err"; then
    echo "load: slot.sh failed: $(tr '\n' ' ' < "$tmp/err" | sed 's/ *$//')" >&2; exit 2
  fi
  cat "$tmp/err" >&2
}
slot_call "$tmp/capacity" --capacity --porcelain
slot_call "$tmp/status" --status --porcelain
limit=$(awk -F '\t' '$1 == "agents" { print $2 }' "$tmp/capacity")
limit_from=$(awk -F '\t' '$1 == "agents" { print $3 }' "$tmp/capacity")
limit_cfg=$(awk -F '\t' '$1 == "agents" { print $4 }' "$tmp/capacity")
slot_count=$(awk -F '\t' '$1 == "slots" { print $2 }' "$tmp/capacity")
busy=$(awk -F '\t' '$2 == "busy" { n++ } END { print n + 0 }' "$tmp/status")

# The measurement and the suggestion
rc=0
load_measure "$LOAD_WINDOW" || rc=$?
[ "$rc" = 0 ] || exit 2
load_suggest "$busy"

direction=""
if [ -n "$LOAD_SUGGEST" ]; then
  if [ "$LOAD_SUGGEST" -gt "$limit" ]; then direction=raise
  elif [ "$LOAD_SUGGEST" -lt "$limit" ]; then direction=lower
  else direction=keep; fi
fi
none=""
if [ -z "$LOAD_CPU" ] && [ -z "$LOAD_FREE" ]; then none="the CPU load and the free memory are unavailable"
elif [ -z "$LOAD_CPU" ]; then none="the CPU load is unavailable"
elif [ -z "$LOAD_FREE" ]; then none="the free memory is unavailable"; fi

if [ "$porcelain" = 1 ]; then
  if [ -n "$LOAD_CPU" ]; then printf 'cpu\t%s\n' "$LOAD_CPU"; else printf 'cpu\tunavailable\t%s\n' "$LOAD_CPU_WHY"; fi
  if [ -n "$LOAD_FREE" ]; then
    printf 'memory-free\t%s\nmemory-total\t%s\n' "$LOAD_FREE" "$LOAD_TOTAL"
  else
    printf 'memory-free\tunavailable\t%s\nmemory-total\tunavailable\t%s\n' "$LOAD_MEM_WHY" "$LOAD_MEM_WHY"
  fi
  printf 'window\t%s\t%s\n' "$LOAD_SAMPLES" "$LOAD_FROM"
  printf 'agent-limit\t%s\t%s\n' "$limit" "$limit_from"
  printf 'slot-count\t%s\n' "$slot_count"
  printf 'slots-busy\t%s\n' "$busy"
  printf 'agents-running\t%s\n' "$busy"
  printf 'memory-per-agent\t%s\n' "$LOAD_GB"
  printf 'ceiling\t%s\n' "$LOAD_CEILING"
  if [ -n "$LOAD_SUGGEST" ]; then printf 'suggested\t%s\t%s\t%s\n' "$LOAD_SUGGEST" "$direction" "$LOAD_REASON"
  else printf 'suggested\tnone\tunavailable\n'; fi
else
  if [ "$LOAD_FROM" = fixture ]; then how=" from NIGHTMILL_LOAD_FIXTURE"; else how=", 1 s apart"; fi
  if [ -n "$LOAD_CPU" ]; then
    echo "cpu: $LOAD_CPU% busy (mean of $LOAD_SAMPLES samples$how)"
  else
    echo "cpu: unavailable ($LOAD_CPU_WHY)"
  fi
  if [ -n "$LOAD_FREE" ]; then echo "memory: $LOAD_FREE MB free of $LOAD_TOTAL MB (lowest of $LOAD_SAMPLES samples)"
  else echo "memory: unavailable ($LOAD_MEM_WHY)"; fi
  case "$limit_from" in
    live) echo "agent limit: $limit (live; config $limit_cfg)" ;;
    *) echo "agent limit: $limit ($limit_from)" ;;
  esac
  echo "slots: $busy of $slot_count in use"
  echo "agents running: $busy (counted from the busy slots)"
  if [ -n "$LOAD_SUGGEST" ]; then
    echo "suggested agent limit: $LOAD_SUGGEST (now $limit: $direction)"
    echo "why: $LOAD_WHY"
  else
    echo "suggested agent limit: none ($none)"
  fi
fi

if [ -n "$LOAD_SUGGEST" ]; then exit 0; fi
exit 1
