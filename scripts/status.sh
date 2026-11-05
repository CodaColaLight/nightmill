#!/usr/bin/env bash
# scripts/status.sh - one table of what waits for the maintainer and what is stuck (nightmill).
#
#   status.sh [--all]
#
# Joins the board items, the pull requests and the busy slots and prints them as one table, Spec review and
# Approved first, with stale states flagged. --all also lists the items at Backlog and Done. It only reads:
# gh project item-list / project view, gh pr list, gh api graphql (a query) and slot.sh --status --porcelain.
# Run it from inside the project: any checkout or worktree of it. Settings come from .claude/nightmill.json
# in the main checkout (github, board.statuses, labels.epic, git.specPrefix, worktrees). The rules and the
# texts are in docs/specs/iteration-8-status.md; status.ps1 prints the same.
# Needs git, gh, bash and awk, no jq. Exit code 0 when the table was printed (flags do not change it), 2 for a
# usage error, a missing or unreadable config, a missing gh or a failed gh call.
# NIGHTMILL_NOW (seconds since 1970, with the local time zone taken as UTC) fixes the clock; the smoke test uses it.
set -euo pipefail

usage() { echo "usage: status.sh [--all]" >&2; exit 2; }
die() { echo "status.sh: $*" >&2; exit 2; }

all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) all=1 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/json.sh"

command -v gh >/dev/null 2>&1 || die "gh is not installed or not on the PATH"
gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "run status.sh from inside a git checkout of the project"
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || die "no $cfg (run /nightmill:init)"
json_load "$cfg" || exit 2

owner=$(json_get github.owner); repo=$(json_get github.repo); number=$(json_get github.projectNumber)
{ [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$number" ]; } || die "github.owner, github.repo and github.projectNumber are needed in $cfg"
st() { json_get "board.statuses.$1" "$2"; }
# the statuses in the order of the table, tab separated
order="$(st specReview 'Spec review')	$(st approved Approved)	$(st inProgress 'In progress')	$(st review Review)	$(st spec Spec)	$(st ready Ready)	$(st backlog Backlog)	$(st done Done)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

flat() { JSON_MODE=flat JSON_FILE="$1" LC_ALL=C awk -f "$here/lib/json.awk"; }
run() { # run <what> <output file> <command...>: a failed call ends the script with the reason
  local what=$1 out=$2
  shift 2
  "$@" > "$out" 2> "$tmp/err" || die "$what failed: $(tr '\n' ' ' < "$tmp/err")"
}

run "gh project item-list" "$tmp/items.json" gh project item-list "$number" --owner "$owner" --limit 200 --format json
flat "$tmp/items.json" > "$tmp/items.flat" || die "gh project item-list gave no valid JSON"

run "gh pr list" "$tmp/prs.json" gh pr list --repo "$owner/$repo" --state all --limit 100 \
  --json number,title,headRefName,state,isDraft,updatedAt,statusCheckRollup,closingIssuesReferences
flat "$tmp/prs.json" > "$tmp/prs.flat" || die "gh pr list gave no valid JSON"

# the time of each item's last status change: GraphQL, a page of 100 items at a time
run "gh project view" "$tmp/view.json" gh project view "$number" --owner "$owner" --format json
flat "$tmp/view.json" > "$tmp/view.flat" || die "gh project view gave no valid JSON"
project_id=$(awk -F '\t' '$1 == "id" { print $3 }' "$tmp/view.flat")
[ -n "$project_id" ] || die "gh project view did not give the project id"
query='query($id: ID!, $after: String) { node(id: $id) { ... on ProjectV2 { items(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { createdAt content { ... on Issue { number timelineItems(last: 1, itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) { nodes { ... on ProjectV2ItemStatusChangedEvent { createdAt } } } } } } } } } }'
agefiles=""; after=""; page=0
while :; do
  page=$((page + 1))
  if [ -z "$after" ]; then
    run "gh api graphql" "$tmp/age$page.json" gh api graphql -f query="$query" -f id="$project_id"
  else
    run "gh api graphql" "$tmp/age$page.json" gh api graphql -f query="$query" -f id="$project_id" -f after="$after"
  fi
  flat "$tmp/age$page.json" > "$tmp/age$page.flat" || die "gh api graphql gave no valid JSON"
  agefiles="$agefiles $tmp/age$page.flat"
  more=$(awk -F '\t' '$1 == "data.node.items.pageInfo.hasNextPage" { print $3 }' "$tmp/age$page.flat")
  after=$(awk -F '\t' '$1 == "data.node.items.pageInfo.endCursor" { print $3 }' "$tmp/age$page.flat")
  { [ "$more" = true ] && [ -n "$after" ] && [ "$page" -lt 20 ]; } || break
done

# the slots, only when the project has a worktrees section
slots_configured=0
: > "$tmp/slots.tsv"
if json_has worktrees; then
  slots_configured=1
  bash "$here/slot.sh" --status --porcelain > "$tmp/slots.tsv" 2> "$tmp/err" || die "slot.sh failed: $(tr '\n' ' ' < "$tmp/err")"
fi

if [ -n "${NIGHTMILL_NOW:-}" ]; then now=$NIGHTMILL_NOW; nowl=""; else now=$(date +%s); nowl=$(date +%Y-%m-%dT%H:%M:%S); fi

ST_ALL=$all ST_NOW=$now ST_NOWL=$nowl ST_SPECPREFIX=$(json_get git.specPrefix spec/) ST_EPIC=$(json_get labels.epic epic) \
  ST_ORDER=$order ST_ITEMS="$tmp/items.flat" ST_PRS="$tmp/prs.flat" ST_AGEFILES="${agefiles# }" ST_SLOTS="$tmp/slots.tsv" \
  ST_SLOTS_CONFIGURED=$slots_configured LC_ALL=C awk -f "$here/lib/status.awk"
