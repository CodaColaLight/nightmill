#!/usr/bin/env bash
# tests/smoke-dashboard.sh - dashboard.sh against fixtures and a fake gh: the page is rendered once (--once) into a
# temporary folder of the test from tests/fixtures/dashboard/run-stall-old-free/ (and tests/fixtures/status/c), the
# slot markers are written from markers.txt and the clock is fixed (NIGHTMILL_NOW = 2026-11-05T12:00:00). The page
# must equal expected.html, which smoke-dashboard.ps1 compares with too; UPDATE_DASHBOARD_FIXTURES=1 rewrites it
# (read the diff before committing). Needs bash and awk, no jq, no network. Nothing sleeps.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-dashboard.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
D="$here/scripts/dashboard.sh"
S="$here/scripts/status.sh"
FIX="$here/tests/fixtures/dashboard/run-stall-old-free"
SFIX="$here/tests/fixtures/status"
NOW=1793880000
pages="$tmp/pages"
mkdir -p "$pages"
page="$pages/nightmill-dashboard-acme-widgets.html"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The project: one config with four slots, in a throwaway repository.
git init -q -b main "$tmp/work"
cd "$tmp/work"
mkdir -p .claude
cat > "$tmp/with-slots.json" <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" },
  "worktrees": { "root": "../wt", "slots": 4 }
}
EOF
cp "$tmp/with-slots.json" .claude/nightmill.json
sed '/"worktrees"/d; s/"specPrefix": "spec\/" },/"specPrefix": "spec\/" }/' "$tmp/with-slots.json" > "$tmp/no-slots.json"
sed '/"repo"/s/"repo": "widgets", //' "$tmp/with-slots.json" > "$tmp/no-repo.json"
grep -q '"repo"' "$tmp/no-repo.json" && fail "the config copy without github.repo still has it"
with_refresh() { sed "s/\"slots\": 4 }/\"slots\": 4, \"dashboardRefreshSeconds\": $1 }/" "$tmp/with-slots.json" > .claude/nightmill.json; }
mkdir "$tmp/plain" && git init -q -b main "$tmp/plain"
mkdir "$tmp/nogit"

# A fake gh: it answers from $GH_FIX, logs every call to $GH_LOG, fails when GH_FAIL is set.
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
if [ -n "${GH_FAIL:-}" ]; then echo "HTTP 401: bad credentials" >&2; exit 1; fi
case "$1 $2" in
  "project item-list") cat "$GH_FIX/items.json" ;;
  "project view") echo '{"id": "PVT_test", "number": 1}' ;;
  "pr list") cat "$GH_FIX/prs.json" ;;
  "api graphql") cat "$GH_FIX/ages.json" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"
markers() { # markers <markers.txt>: set the busy slots; a line with the four report columns is a seven-key marker
  rm -rf "$tmp/wt"; mkdir -p "$tmp/wt/.slots"
  local n branch since skill role step reported
  while IFS=$'\t' read -r n branch since skill role step reported; do
    [ -n "$n" ] || continue
    if [ -n "$skill" ]; then
      json_marker_report "$n" "$branch" "$since" "$skill" "$role" "$step" "$reported" > "$tmp/wt/.slots/slot-$n.json"
    else
      json_marker "$n" "$branch" "$since" > "$tmp/wt/.slots/slot-$n.json"
    fi
  done < "$1"
}

run_d() { # run_d <dir> <gh fixture dir> <temp folder> [args]: the output in out.txt and err.txt, the exit code in $code
  local dir=$1 fix=$2 tdir=$3
  shift 3
  : > "$tmp/gh.log"
  set +e
  (cd "$dir" && PATH="$tmp/bin:$PATH" GH_FIX="$fix" GH_LOG="$tmp/gh.log" NIGHTMILL_NOW=$NOW TMPDIR="$tdir" bash "$D" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  set -e
}
has() { grep -qF -- "$1" "$page" || fail "$2: the page does not hold: $1"; }
hasnot() { if grep -qF -- "$1" "$page"; then fail "$2: the page holds: $1"; fi; }

markers "$FIX/markers.txt"
git_before=$(git -C "$tmp/work" status --porcelain --untracked-files=all)
marker_sums() { (cd "$tmp/wt/.slots" && cksum ./*); }
sums_before=$(marker_sums)

echo "== the page names every slot"
run_d "$tmp/work" "$FIX" "$pages" --once
[ "$code" = 0 ] || fail "exit code $code: $(cat "$tmp/err.txt")"
[ ! -s "$tmp/err.txt" ] || fail "something on standard error: $(cat "$tmp/err.txt")"
[ -f "$page" ] || fail "no page at $page"
[ "$(sed -n 1p "$tmp/out.txt")" = "dashboard: wrote $page" ] || fail "the first line: $(sed -n 1p "$tmp/out.txt")"
sed -n 2p "$tmp/out.txt" | grep -x 'dashboard: open file:///.*/nightmill-dashboard-acme-widgets\.html in a browser' >/dev/null || fail "the second line: $(sed -n 2p "$tmp/out.txt")"
[ "$(wc -l < "$tmp/out.txt" | tr -d ' ')" = 2 ] || fail "standard output is not two lines: $(cat "$tmp/out.txt")"
if [ "${UPDATE_DASHBOARD_FIXTURES:-}" = 1 ]; then cp "$page" "$FIX/expected.html"; fi
if ! cmp -s "$FIX/expected.html" "$page"; then
  diff "$FIX/expected.html" "$page" >&2 || true
  fail "the page differs from $FIX/expected.html"
fi
for n in 1 2 3 4; do
  [ "$(grep -cE "^<tr><td class=\"num\">$n</td><td( class=\"free\")?>(busy|free)</td>" "$page")" = 1 ] || fail "slot $n is not one row of the slot table"
done

echo "== each state is a word and a colour"
for w in '<td class="running">running</td>' '<td class="stalled">stalled</td>' '<td class="unknown">unknown</td>' \
  '<td class="free">free</td>' '<td class="flagged">stale: busy, no open PR</td>' \
  '<td class="flagged">stale: busy, PR merged (slot --release 3)</td>'; do
  has "$w" "states"
done

echo "== what waits"
l2=$(grep -nF '<tr><td class="num">2</td><td>Read the' "$page" | cut -d: -f1)
l3=$(grep -nF '<tr><td class="num">3</td><td>Approved and waiting' "$page" | cut -d: -f1)
l6=$(grep -nF '<tr><td class="num">6</td><td>Path' "$page" | cut -d: -f1)
{ [ -n "$l2" ] && [ -n "$l3" ] && [ -n "$l6" ] && [ "$l2" -lt "$l3" ] && [ "$l3" -lt "$l6" ]; } || fail "the items are not 2, 3, 6 in that order: $l2 $l3 $l6"
hasnot 'Busy one' "what waits"
hasnot 'At review' "what waits"
grep -F '<tr><td class="num">2</td>' "$page" | grep -F '<td>#31 open, ci pass</td><td class="num">5h</td>' >/dev/null || fail "item 2: the PR and age cells"
grep -F '<tr><td class="num">3</td><td>Approved' "$page" | grep -F '<td>Approved</td><td>-</td><td class="num">2d</td>' >/dev/null || fail "item 3: the PR and age cells"
has '<p>capacity: slots 4 (config), agents 2 (default)</p>' "what waits"

echo "== hostile text is escaped"
has 'feat/&lt;b&gt;&amp;&#39;x' "escaping"
has 'Read the &lt;b&gt;spec&lt;/b&gt; &amp; &quot;approve&quot; — café' "escaping"
hasnot '<b>' "escaping"
hasnot 'feat/<b' "escaping"

echo "== a title is decoded before the tab becomes a space"
set +e
(cd "$tmp/work" && PATH="$tmp/bin:$PATH" GH_FIX="$FIX" GH_LOG="$tmp/gh.log" NIGHTMILL_NOW=$NOW bash "$S" --porcelain) > "$tmp/porc.txt" 2> "$tmp/err.txt"
code=$?
set -e
[ "$code" = 0 ] || fail "status.sh --porcelain: exit code $code"
grep -qxF "$(printf 'item\t6\tApproved\t-\t-\t1d\t\tPath C:\\temp and more')" "$tmp/porc.txt" || fail "the item 6 line: $(grep "$(printf '^item\t6')" "$tmp/porc.txt")"
has '<tr><td class="num">6</td><td>Path C:\temp and more</td><td>Approved</td><td>-</td><td class="num">1d</td></tr>' "title"
hasnot 'temp\tand' "title"
hasnot 'C:\\temp' "title"
hasnot "$(printf 'C:\\\temp')" "title"

echo "== self-contained and read-only"
run_d "$tmp/work" "$FIX" "$pages" --once
[ "$(grep -cF '<script>' "$page")" = 1 ] || fail "not exactly one <script>"
[ "$(grep -cF '<meta http-equiv="refresh" content="60">' "$page")" = 1 ] || fail "not exactly one refresh of 60"
for w in 'data-every="60"' 'data-epoch="1793880000"' 'Rendered at 2026-11-05 12:00:00' '(worktrees.stalledAfterMinutes)' '30 minutes'; do
  has "$w" "self-contained"
done
for w in '<link' 'src=' 'href' '@import' 'url(' 'http://' 'https://' '<form' '<button' '<input' '<a ' 'fetch(' 'XMLHttpRequest' 'WebSocket' 'localStorage' 'sessionStorage'; do
  hasnot "$w" "self-contained"
done
for c in 'project item-list' 'project view' 'pr list' 'api graphql'; do
  grep -q "^$c" "$tmp/gh.log" || fail "gh $c was never called"
done
if grep -vE '^(project item-list|project view|pr list|api graphql) ' "$tmp/gh.log" | grep . >/dev/null; then fail "another gh call: $(cat "$tmp/gh.log")"; fi
if grep -E 'item-edit|item-add|item-archive|pr merge|issue edit|issue comment|issue close|mutation' "$tmp/gh.log"; then fail "the dashboard changed something"; fi

echo "== gh cannot be read"
GH_FAIL=1 run_d "$tmp/work" "$FIX" "$pages" --once
[ "$code" = 0 ] || fail "a failing gh: exit code $code: $(cat "$tmp/err.txt")"
has '<p class="unknown">unknown: the board could not be read (status.sh: gh project item-list failed: HTTP 401: bad credentials)' "gh fails"
has 'HTTP 401: bad credentials)' "gh fails"
has '<p class="unknown">unknown: the pull requests, CI and flags of the slots could not be read (' "gh fails"
for w in '<td class="running">running</td>' '<td class="stalled">stalled</td>' '<td class="unknown">unknown</td>' '<td class="free">free</td>' \
  '<td class="num">2026-11-05T11:55:00</td><td class="num">2026-11-05T10:00:00</td>' '<p class="unknown">capacity: unknown</p>'; do
  has "$w" "gh fails"
done
for n in 1 2 3; do
  grep -F "<tr><td class=\"num\">$n</td>" "$page" | grep -F '<td class="unknown">unknown</td><td class="unknown">unknown</td></tr>' >/dev/null || fail "gh fails: slot $n has no unknown PR and Flag"
  if grep -F "<tr><td class=\"num\">$n</td>" "$page" | grep -F '<td class="free">' >/dev/null; then fail "gh fails: slot $n is shown free"; fi
done
hasnot 'Nothing waits' "gh fails"

echo "== an unreadable marker is never free"
printf '{ not json' > "$tmp/wt/.slots/slot-2.json"
run_d "$tmp/work" "$FIX" "$pages" --once
[ "$code" = 0 ] || fail "an unreadable marker: exit code $code"
hasnot '<td class="num">2</td><td class="free">free</td>' "unreadable marker"
has '<tr><td class="num">2</td><td>busy</td><td class="unknown">unknown</td>' "unreadable marker"
markers "$FIX/markers.txt"

echo "== nothing waits"
markers "$SFIX/c/markers.txt"
run_d "$tmp/work" "$SFIX/c" "$pages" --once
[ "$code" = 0 ] || fail "nothing waits: exit code $code"
has '<p>Nothing waits for you: no item at Spec review or Approved.</p>' "nothing waits"
for row in '<tr><td class="num">1</td><td>busy</td><td class="stalled">stalled</td><td>feat/merged</td>' \
  '<tr><td class="num">2</td><td>busy</td><td class="unknown">unknown</td><td>feat/closed</td>' \
  '<tr><td class="num">3</td><td>busy</td><td class="stalled">stalled</td><td>feat/stale</td>' \
  '<tr><td class="num">4</td><td>busy</td><td class="running">running</td><td>feat/new</td>'; do
  has "$row" "nothing waits"
done

echo "== not all items read is not nothing waits"
cp -r "$SFIX/c" "$tmp/c250"
sed 's/"totalCount": 1/"totalCount": 250/' "$SFIX/c/items.json" > "$tmp/c250/items.json"
grep -q '"totalCount": 250' "$tmp/c250/items.json" || fail "the fixture copy has no totalCount 250"
run_d "$tmp/work" "$tmp/c250" "$pages" --once
has '<p class="unknown">unknown: no item at Spec review or Approved among the items read; not all board items were read.</p>' "partial board"
has '<li>the board has 250 items, only the first 200 were read</li>' "partial board"
hasnot 'Nothing waits' "partial board"
markers "$FIX/markers.txt"

echo "== without worktrees"
cp "$tmp/no-slots.json" .claude/nightmill.json
run_d "$tmp/work" "$FIX" "$pages" --once
[ "$code" = 0 ] || fail "without worktrees: exit code $code"
has '<p>No slots: .claude/nightmill.json has no worktrees section.</p>' "without worktrees"
has '<tr><td class="num">2</td><td>Read the' "without worktrees"
has '<tr><td class="num">3</td><td>Approved and waiting' "without worktrees"
hasnot '<th>slot</th>' "without worktrees"
cp "$tmp/with-slots.json" .claude/nightmill.json

echo "== the interval is a config value"
with_refresh 15
run_d "$tmp/work" "$FIX" "$pages" --once
[ "$code" = 0 ] || fail "refresh 15: exit code $code"
[ ! -s "$tmp/err.txt" ] || fail "refresh 15: something on standard error: $(cat "$tmp/err.txt")"
for w in 'content="15"' 'data-every="15"' 'reloads every 15 s' 'more than 45 s'; do has "$w" "refresh 15"; done
for v in 0 9 3601 2.5 60.0 '"60"' true; do
  with_refresh "$v"
  run_d "$tmp/work" "$FIX" "$pages" --once
  [ "$code" = 0 ] || fail "refresh $v: exit code $code"
  [ "$(cat "$tmp/err.txt")" = "dashboard: worktrees.dashboardRefreshSeconds must be a whole number from 10 to 3600; using 60" ] || fail "refresh $v: the warning: $(cat "$tmp/err.txt")"
  has 'content="60"' "refresh $v"
done
with_refresh null
run_d "$tmp/work" "$FIX" "$pages" --once
[ ! -s "$tmp/err.txt" ] || fail "refresh null: a warning: $(cat "$tmp/err.txt")"
has 'content="60"' "refresh null"
cp "$tmp/with-slots.json" .claude/nightmill.json

echo "== errors"
errpages="$tmp/errpages"; mkdir -p "$errpages"
for args in "--nope" "--help" "--once --once"; do
  # shellcheck disable=SC2086
  run_d "$tmp/work" "$FIX" "$errpages" $args
  [ "$code" = 2 ] || fail "$args: exit code $code"
  grep -qxF 'usage: dashboard.sh [--once]' "$tmp/err.txt" || fail "$args: no usage line: $(cat "$tmp/err.txt")"
done
run_d "$tmp/nogit" "$FIX" "$errpages" --once
[ "$code" = 2 ] && grep -qF 'from inside a checkout' "$tmp/err.txt" || fail "outside a checkout: $code $(cat "$tmp/err.txt")"
run_d "$tmp/plain" "$FIX" "$errpages" --once
[ "$code" = 2 ] && grep -qF 'run /nightmill:init' "$tmp/err.txt" || fail "no config: $code $(cat "$tmp/err.txt")"
cp "$tmp/no-repo.json" .claude/nightmill.json
run_d "$tmp/work" "$FIX" "$errpages" --once
[ "$code" = 2 ] && grep -qF 'github.owner and github.repo are needed' "$tmp/err.txt" || fail "no repo: $code $(cat "$tmp/err.txt")"
cp "$tmp/with-slots.json" .claude/nightmill.json
[ -z "$(ls -A "$errpages")" ] || fail "an error case wrote a page: $(ls -A "$errpages")"

echo "== a page that cannot be written"
run_d "$tmp/work" "$FIX" "$tmp/missing" --once
[ "$code" = 1 ] || fail "a missing temporary folder: exit code $code"
[ "$(wc -l < "$tmp/err.txt" | tr -d ' ')" = 1 ] || fail "not one line on standard error: $(cat "$tmp/err.txt")"
grep -qF "dashboard: cannot write $tmp/missing/nightmill-dashboard-acme-widgets.html: " "$tmp/err.txt" || fail "the message: $(cat "$tmp/err.txt")"
[ ! -e "$tmp/missing" ] || fail "the missing folder was created"

echo "== the address is percent-encoded"
spaced="$tmp/my pages"; mkdir -p "$spaced"
run_d "$tmp/work" "$FIX" "$spaced" --once
[ "$code" = 0 ] || fail "a temporary folder with a space: exit code $code"
sed -n 2p "$tmp/out.txt" | grep -F 'my%20pages/nightmill-dashboard-acme-widgets.html in a browser' >/dev/null || fail "the space is not %20: $(sed -n 2p "$tmp/out.txt")"
rm -rf "$spaced"

echo "== nothing is written in the project or the slots"
[ "$(git -C "$tmp/work" status --porcelain --untracked-files=all)" = "$git_before" ] || fail "git status changed: $(git -C "$tmp/work" status --porcelain --untracked-files=all)"
[ "$(marker_sums)" = "$sums_before" ] || fail "a marker changed"
[ "$(ls -A "$tmp/wt/.slots" | sort | tr '\n' ' ')" = "slot-1.json slot-2.json slot-3.json " ] || fail ".slots holds other files: $(ls -A "$tmp/wt/.slots")"
[ "$(ls -A "$pages")" = "nightmill-dashboard-acme-widgets.html" ] || fail "the temporary folder holds more than the page: $(ls -A "$pages")"

echo "DASHBOARD OK"
