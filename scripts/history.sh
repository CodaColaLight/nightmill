#!/usr/bin/env bash
# scripts/history.sh - how the work went in a window (iteration 54). Bash twin of history.ps1.
#   history.sh [--from <t>] [--to <t>] | [--run <stamp>]   [--json | --html <dir>]
# <t> is YYYY-MM-DD (00:00:00Z of that day) or YYYY-MM-DDTHH:MM:SSZ; <stamp> the second form. The window is [from, to],
# both ends included: to defaults to now, from to the earliest line of the record (or a week before to); --run <stamp>
# is the window of one driver run, and only that run's run lines count.
# Reads the record <worktrees.root>/.slots/ledger.tsv (take, step, free and run lines) and prints the fix rounds and
# check fix rounds per issue, the cost per issue and the slot utilisation; the time issues stayed at each board status
# comes from the board's status changes, read with one query, the only gh command it calls (a read):
#   gh api graphql -f query='query($o: String!, $n: Int!, $after: String) { repositoryOwner(login: $o) { ... } }'
# A board that cannot be read gives ? and a note, never 0. The text (default), one JSON line (--json) or one static
# page, <dir>/index.html, that needs no network (--html). It writes nothing else and sets nothing on GitHub. The
# computation is in lib/history.awk. Exit 0 when it printed or wrote its output, 1 for a record that cannot be read
# or a page that cannot be written, 2 for a usage error, outside a checkout or without the config.
# NIGHTMILL_CLOCK_FILE (tests only, see lib/ledger.sh) fixes "now". docs/specs/iteration-54-history-metrics.md.
set -euo pipefail

usage_text="usage: history.sh [--from <t>] [--to <t>] | [--run <stamp>]   [--json | --html <dir>]"
usage() { echo "$usage_text" >&2; exit 2; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/json.sh"
. "$here/lib/ledger.sh"

# when <stamp> is a real UTC stamp, its seconds since 1970 in t_s (the stamp printed back from them is the same)
stamp_ok() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  t_s=$(ledger_epoch "$1")
  [ "$(ledger_stamp "$t_s")" = "$1" ]
}
time_ok() { # <t>: a date or a stamp
  local v=$1
  if [[ "$v" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then v="${v}T00:00:00Z"; fi
  stamp_ok "$v"
}

from=""; to=""; run=""; mode=text; dir=""
has_from=0; has_to=0; has_run=0; has_json=0; has_html=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) echo "$usage_text"; exit 0 ;;
    --from) [ $# -ge 2 ] && [ "$has_from" = 0 ] || usage; time_ok "$2" || usage; from=$t_s; has_from=1; shift ;;
    --to) [ $# -ge 2 ] && [ "$has_to" = 0 ] || usage; time_ok "$2" || usage; to=$t_s; has_to=1; shift ;;
    --run) [ $# -ge 2 ] && [ "$has_run" = 0 ] || usage; stamp_ok "$2" || usage; run=$2; has_run=1; shift ;;
    --json) [ "$has_json" = 0 ] || usage; has_json=1; mode=json ;;
    --html) [ $# -ge 2 ] && [ "$has_html" = 0 ] && [ -n "$2" ] || usage
      case "$2" in -*) usage ;; esac
      dir=$2; has_html=1; mode=html; shift ;;
    *) usage ;;
  esac
  shift
done
if [ "$has_json" = 1 ] && [ "$has_html" = 1 ]; then usage; fi
if [ "$has_run" = 1 ] && { [ "$has_from" = 1 ] || [ "$has_to" = 1 ]; }; then usage; fi
ledger_clock
# ledger_s is set by ledger_clock (lib/ledger.sh)
# shellcheck disable=SC2154
now=$ledger_s
if [ "$has_from" = 1 ] && [ "$from" -gt "${to:-$now}" ]; then usage; fi

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "run history.sh from inside a git checkout of the project" >&2; exit 2; }
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 2; }
json_load "$cfg" || exit 2
root_rel=$(json_get worktrees.root); root_rel=${root_rel:-"../$(basename "$main")-wt"}
if [ -d "$main/$root_rel" ]; then root=$(cd "$main/$root_rel" && pwd); else root="$main/$root_rel"; fi
record="$root/.slots/ledger.tsv"
ledger=""
if [ -e "$record" ]; then
  if [ ! -f "$record" ] || [ ! -r "$record" ]; then echo "history: cannot read $record" >&2; exit 1; fi
  ledger=$record
fi

owner=$(json_get github.owner); repo=$(json_get github.repo); number=$(json_get github.projectNumber)
epic=$(json_get labels.epic epic)
have_wt=0; json_has worktrees && have_wt=1
slots=$(json_get worktrees.slots)
st() { json_get "board.statuses.$1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-history.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# the board: one query, paged by 100 items, at most 20 pages (decision 6); a failure is a note, never a stop
query='query($o: String!, $n: Int!, $after: String) { repositoryOwner(login: $o) { ... on ProjectV2Owner { projectV2(number: $n) { items(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { content { ... on Issue { number labels(first: 50) { nodes { name } } timelineItems(first: 100, itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) { nodes { ... on ProjectV2ItemStatusChangedEvent { createdAt status project { number } } } } } } } } } } } }'
board=1; board_note=""; more=0
: > "$tmp/board.tsv"
one_line() { tr '\r\n' '  ' < "$1" | sed 's/[[:space:]]*$//'; }
if [ -z "$owner" ] || [ -z "$number" ]; then
  board=0; board_note="github.owner and github.projectNumber are not set"
elif ! command -v gh >/dev/null 2>&1; then
  board=0; board_note="gh is not installed or not on the PATH"
else
  after=""; page=0
  while :; do
    page=$((page + 1))
    if [ -z "$after" ]; then set -- gh api graphql -f query="$query" -f o="$owner" -F n="$number"
    else set -- gh api graphql -f query="$query" -f o="$owner" -F n="$number" -f after="$after"; fi
    if ! "$@" > "$tmp/page.json" 2> "$tmp/err"; then
      board=0; board_note=$(one_line "$tmp/err"); board_note=${board_note:-gh api graphql failed}; break
    fi
    if ! JSON_MODE=flat JSON_FILE="$tmp/page.json" LC_ALL=C awk -f "$here/lib/json.awk" > "$tmp/page.flat" 2> /dev/null \
      || ! awk -F '\t' '$1 == "data.repositoryOwner.projectV2.items" && $2 == "object" { f = 1 } END { exit !f }' "$tmp/page.flat"; then
      board=0; board_note="gh api graphql gave no board items"; break
    fi
    awk -v p="$page" '{ print p "\t" $0 }' "$tmp/page.flat" >> "$tmp/board.tsv"
    hasmore=$(awk -F '\t' '$1 == "data.repositoryOwner.projectV2.items.pageInfo.hasNextPage" { print $3 }' "$tmp/page.flat")
    after=$(awk -F '\t' '$1 == "data.repositoryOwner.projectV2.items.pageInfo.endCursor" && $2 == "string" { print $3 }' "$tmp/page.flat")
    [ "$hasmore" = true ] && [ -n "$after" ] || break
    if [ "$page" -ge 20 ]; then more=1; break; fi
  done
fi

compute() {
  H_LEDGER=$ledger H_PATHNAME=$record H_NOW=$now H_FROM=$from H_TO=$to H_RUN=$run H_MODE=$mode \
    H_BOARD=$board H_BOARDFILE="$tmp/board.tsv" H_BOARDNOTE=$board_note H_MORE=$more H_PN=$number H_EPIC=$epic \
    H_ST_backlog=$(st backlog) H_ST_ready=$(st ready) H_ST_spec=$(st spec) H_ST_specReview=$(st specReview) \
    H_ST_approved=$(st approved) H_ST_inProgress=$(st inProgress) H_ST_review=$(st review) H_ST_done=$(st 'done') \
    H_HAVEWT=$have_wt H_SLOTS=$slots H_OWNER=$owner H_REPO=$repo LC_ALL=C awk -f "$here/lib/history.awk"
}

if [ "$mode" != html ]; then
  compute || exit 1
  exit 0
fi

# the page (decision 11): a temporary file in <dir>, moved over index.html, so a reader never sees half a page
page_path="$dir/index.html"
cannot() { echo "history: cannot write $page_path ($(printf '%s\n' "$1" | head -n 1))" >&2; exit 1; }
err=$(mkdir -p "$dir" 2>&1) || cannot "$err"
part=$(mktemp "$dir/.index.html.XXXXXX" 2> "$tmp/err") || cannot "$(cat "$tmp/err")"
if ! compute > "$part" 2> "$tmp/aerr"; then
  rm -f "$part"
  if grep -q '^history: cannot read ' "$tmp/aerr"; then cat "$tmp/aerr" >&2; exit 1; fi
  cannot "$(cat "$tmp/aerr")"
fi
cat "$tmp/aerr" >&2
chmod 644 "$part" 2>/dev/null || true
err=$(mv -f "$part" "$page_path" 2>&1) || { rm -f "$part"; cannot "$err"; }
echo "history: wrote $page_path"
