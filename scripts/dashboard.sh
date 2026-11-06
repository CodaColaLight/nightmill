#!/usr/bin/env bash
# scripts/dashboard.sh - a page in the browser with the slots and what waits for the maintainer (nightmill).
#
#   dashboard.sh            rewrite the page every worktrees.dashboardRefreshSeconds seconds until Ctrl-C
#   dashboard.sh --once     render it once and exit
#
# Read-only. Each render runs status.sh --porcelain once (the cells of /status, from the same code) and, when that
# fails, slot.sh --status --porcelain (no network), and writes one self-contained HTML page, built by
# lib/dashboard.awk, to <temp>/nightmill-dashboard-<owner>-<repo>.html; the page reloads itself. It never calls
# the GitHub CLI itself, starts no server and opens no browser: it prints the file:// address to open once.
# Run it from inside the project: any checkout or worktree of it. The rules are in
# docs/specs/iteration-31-dashboard.md; dashboard.ps1 writes the same page.
# Exit code 0 after --once wrote the page, 1 when the page could not be written the first time, 2 for a usage error,
# no checkout, no or invalid config, no owner or repo. Needs git, bash and awk, no jq.
# NIGHTMILL_NOW (seconds since 1970) fixes the clock of the page and of the child scripts; the smoke test uses it.
set -uo pipefail

usage() { echo "usage: dashboard.sh [--once]" >&2; exit 2; }
die() { echo "dashboard: $*" >&2; exit 2; }

once=0
case $# in
  0) ;;
  1) [ "$1" = "--once" ] || usage; once=1 ;;
  *) usage ;;
esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/json.sh"

gitdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "run dashboard.sh from inside a checkout of the project"
[ -n "$gitdir" ] || die "run dashboard.sh from inside a checkout of the project"
main=$(dirname "$gitdir")
cfg="$main/.claude/nightmill.json"
[ -f "$cfg" ] || die "no $cfg (run /nightmill:init)"
json_load "$cfg" || exit 2
owner=$(json_get github.owner); repo=$(json_get github.repo)
{ [ -n "$owner" ] && [ -n "$repo" ]; } || die "github.owner and github.repo are needed in $cfg"

# the settings, read once at the start
setting() { # setting <path>: "<kind> TAB <value>" of the path, empty when absent
  printf '%s\n' "$JSON_FLAT" | K="$1" LC_ALL=C awk -F '\t' '$1 == ENVIRON["K"] { r = $2 "\t" $3 } END { if (r != "") print r }'
}
every=60
rec=$(setting worktrees.dashboardRefreshSeconds)
if [ -n "$rec" ]; then
  kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
  if [ "$kind" != "null" ]; then
    if [ "$kind" = "number" ] && [[ "$val" =~ ^[1-9][0-9]{0,5}$ ]] && [ "$val" -ge 10 ] && [ "$val" -le 3600 ]; then
      every=$val
    else
      echo "dashboard: worktrees.dashboardRefreshSeconds must be a whole number from 10 to 3600; using 60" >&2
    fi
  fi
fi
# worktrees.stalledAfterMinutes for the legend only (the slot script's note reaches the page's notes)
stalled=30
rec=$(setting worktrees.stalledAfterMinutes)
if [ -n "$rec" ]; then
  kind=${rec%%$'\t'*}; val=${rec#*$'\t'}
  if [ "$kind" = "number" ] && [[ "$val" =~ ^[1-9][0-9]{0,5}$ ]]; then stalled=$val; fi
fi
sr=$(json_get board.statuses.specReview 'Spec review')
ap=$(json_get board.statuses.approved Approved)
wt=0
if json_has worktrees; then wt=1; fi

# the page: in the temporary folder, one per project, the same file on every start
tmpdir=${TMPDIR:-/tmp}
tmpdir=${tmpdir%/}
safe() { printf '%s\n' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'; }
page="$tmpdir/nightmill-dashboard-$(safe "$owner")-$(safe "$repo").html"
upath=$page
if command -v cygpath >/dev/null 2>&1; then upath="/$(cygpath -m "$page")"; fi
url="file://$(printf '%s\n' "$upath" | LC_ALL=C awk '
  BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
  {
    s = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c ~ /[A-Za-z0-9._~\/:-]/) s = s c
      else s = s sprintf("%%%02X", ord[c])
    }
    printf "%s", s
  }')"

# capture <command...>: run it, its standard output in CAP_OUT, its standard error in CAP_ERR, its exit code in
# CAP_CODE; kept in shell variables, never in a file
capture() {
  CAP_OUT=""; CAP_ERR=""; CAP_CODE=""
  {
    IFS= read -r -d '' CAP_ERR
    IFS= read -r -d '' CAP_OUT
    IFS= read -r -d '' CAP_CODE
  } < <( (printf '\0%s\0%d\0' "$("$@")" "$?" 1>&2) 2>&1 )
}

PAGE=""
render() {
  local e t st_code st_out st_err sl_ran=0 sl_code="" sl_out="" sl_err=""
  capture bash "$here/status.sh" --porcelain
  st_code=$CAP_CODE; st_out=$CAP_OUT; st_err=$CAP_ERR
  if [ "$st_code" != "0" ] && [ "$wt" = 1 ]; then
    capture bash "$here/slot.sh" --status --porcelain
    sl_ran=1; sl_code=$CAP_CODE; sl_out=$CAP_OUT; sl_err=$CAP_ERR
  fi
  if [ -n "${NIGHTMILL_NOW:-}" ]; then e=$NIGHTMILL_NOW; t=""; else e=$(date +%s); t=$(date '+%Y-%m-%d %H:%M:%S'); fi
  PAGE=$(DB_N=$every DB_E=$e DB_T=$t DB_M=$stalled DB_O=$owner DB_R=$repo DB_SR=$sr DB_AP=$ap DB_WT=$wt \
    DB_ST_NAME="status.sh" DB_ST_CODE=$st_code DB_ST_OUT=$st_out DB_ST_ERR=$st_err \
    DB_SL_RAN=$sl_ran DB_SL_NAME="slot.sh" DB_SL_CODE=$sl_code DB_SL_OUT=$sl_out DB_SL_ERR=$sl_err \
    LC_ALL=C awk -f "$here/lib/dashboard.awk")
}

# write_page: PAGE to the page through a sibling temporary file moved over it; 1 with one line when it fails
pending=""
trap 'if [ -n "$pending" ]; then rm -f "$pending"; fi' EXIT
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM
write_page() {
  local t err
  if ! t=$(mktemp "$page.XXXXXX" 2>&1); then
    echo "dashboard: cannot write $page: $(printf '%s' "$t" | tr '\r\n' '  ')" >&2
    return 1
  fi
  pending=$t
  if ! err=$( { printf '%s\n' "$PAGE" > "$t"; } 2>&1 ) || ! err=$(mv -f "$t" "$page" 2>&1); then
    rm -f "$t"; pending=""
    echo "dashboard: cannot write $page: $(printf '%s' "$err" | tr '\r\n' '  ')" >&2
    return 1
  fi
  pending=""
}

render
write_page || exit 1
if [ "$once" = 1 ]; then
  echo "dashboard: wrote $page"
  echo "dashboard: open $url in a browser"
  exit 0
fi
echo "dashboard: open $url in a browser"
echo "dashboard: rewriting the page every $every s; stop with Ctrl-C (the page stays as last written)"
while :; do
  sleep "$every"
  render
  write_page || true
done
