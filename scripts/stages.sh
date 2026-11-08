#!/usr/bin/env bash
# scripts/stages.sh - where a story's time went (iteration 41). Bash twin of stages.ps1.
#   stages.sh [--issue N | --last N]      # one issue, or the last N takes (default: --last 5)
# Reads the record <worktrees.root>/.slots/ledger.tsv that slot.sh and slot.ps1 append to (a take, every report, every
# freeing) and prints per take the time of each stage and its share of the total: take, not-reported, the reported
# step names as the slots reported them, and ci-and-merge (from the pull request's open to its merge). A time that
# cannot be known is unknown, never 0s. Read-only: it calls no gh, needs no network and writes no file. The
# computation is in lib/stages.awk. NIGHTMILL_CLOCK_FILE (tests only, see lib/ledger.sh) fixes "now".
set -euo pipefail

usage() { echo "usage: stages.sh [--issue N | --last N]" >&2; exit 1; }

mode=last; n=5; has_issue=0; has_last=0
while [ $# -gt 0 ]; do
  case "$1" in
    --issue) [ $# -ge 2 ] && [ "$has_issue" = 0 ] || usage; n=$2; has_issue=1; mode=issue; shift ;;
    --last) [ $# -ge 2 ] && [ "$has_last" = 0 ] || usage; n=$2; has_last=1; mode=last; shift ;;
    *) usage ;;
  esac
  shift
done
if [ "$has_issue" = 1 ] && [ "$has_last" = 1 ]; then usage; fi
if [ "$mode" = issue ]; then [[ "$n" =~ ^[1-9][0-9]{0,9}$ ]] || usage
else [[ "$n" =~ ^[1-9][0-9]{0,2}$ ]] || usage; fi

here=$(dirname "${BASH_SOURCE[0]}")
. "$here/lib/json.sh"
. "$here/lib/ledger.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "run stages.sh from inside a git checkout of the project" >&2; exit 1; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 1; }
json_load "$cfg" || exit 1
root_rel=$(json_get worktrees.root); root_rel=${root_rel:-"../$(basename "$main")-wt"}
if [ -d "$main/$root_rel" ]; then root=$(cd "$main/$root_rel" && pwd); else root="$main/$root_rel"; fi
record="$root/.slots/ledger.tsv"

if [ ! -e "$record" ]; then echo "no record yet: $record"; exit 0; fi
if [ ! -f "$record" ] || [ ! -r "$record" ]; then echo "stages: cannot read $record" >&2; exit 1; fi

ledger_clock
LC_ALL=C awk -v NOW="$ledger_s" -v MODE="$mode" -v N="$n" -v PATHNAME="$record" -f "$here/lib/stages.awk" "$record" \
  || { echo "stages: cannot read $record" >&2; exit 1; }
