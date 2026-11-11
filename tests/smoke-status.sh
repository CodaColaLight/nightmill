#!/usr/bin/env bash
# tests/smoke-status.sh - status.sh against fixtures: a fake gh answers from tests/fixtures/status/<scenario>/,
# the slot markers are written from markers.txt, and the clock is fixed (NIGHTMILL_NOW = 2026-11-05T12:00:00).
# The exact output is compared with expected*.txt in the scenario folder; UPDATE_STATUS_FIXTURES=1 rewrites them
# (read the diff before committing). Needs bash and awk, no jq, no network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-status.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/status.sh"
FIX="$here/tests/fixtures/status"
NOW=1793880000

fail() { echo "FAIL: $*" >&2; exit 1; }

# The project: one config with four slots, in a throwaway repository.
git init -q -b main "$tmp/work"
cd "$tmp/work"
mkdir -p .claude
cat > .claude/nightmill.json <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" },
  "worktrees": { "root": "../wt", "slots": 4 }
}
EOF
sed '/"worktrees"/d; s/"specPrefix": "spec\/" },/"specPrefix": "spec\/" }/' .claude/nightmill.json > "$tmp/no-slots.json"
cp .claude/nightmill.json "$tmp/with-slots.json"
mkdir "$tmp/plain" && git init -q -b main "$tmp/plain"

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
markers() { # markers <scenario>: set the busy slots of the scenario; a line with the four report columns (skill,
  # role, step, reported) is a seven-key marker, a line without them the three-key marker of a take
  rm -rf "$tmp/wt"; mkdir -p "$tmp/wt/.slots"
  local n branch since skill role step reported
  while IFS=$'\t' read -r n branch since skill role step reported; do
    [ -n "$n" ] || continue
    if [ -n "$skill" ]; then
      json_marker_report "$n" "$branch" "$since" "$skill" "$role" "$step" "$reported" > "$tmp/wt/.slots/slot-$n.json"
    else
      json_marker "$n" "$branch" "$since" > "$tmp/wt/.slots/slot-$n.json"
    fi
  done < "$FIX/$1/markers.txt"
}

# base_sync <dir> (iteration 48): slot.sh reads the config on origin/HEAD, not the working tree's file, so before a run
# origin/HEAD of the test repository is made to hold the working tree's config: a commit of that one file, with no
# remote needed (refs/remotes/origin/main and origin/HEAD are set directly). Without the file nothing changes.
base_sync() {
  local d=$1 blob tree commit
  [ -f "$d/.claude/nightmill.json" ] || return 0
  blob=$(git -C "$d" hash-object -w -- "$d/.claude/nightmill.json")
  tree=$(printf '100644 blob %s\tnightmill.json\n' "$blob" | git -C "$d" mktree)
  tree=$(printf '040000 tree %s\t.claude\n' "$tree" | git -C "$d" mktree)
  commit=$(git -C "$d" -c user.name=t -c user.email=t@example.invalid commit-tree -m base "$tree")
  git -C "$d" update-ref refs/remotes/origin/main "$commit"
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

run_in() { # run_in <dir> <scenario> [args]: the status output, the exit code in $code
  local dir=$1 scn=$2
  shift 2
  base_sync "$dir"
  : > "$tmp/gh.log"
  set +e
  (cd "$dir" && PATH="$tmp/bin:$PATH" GH_FIX="$FIX/$scn" GH_LOG="$tmp/gh.log" NIGHTMILL_NOW=$NOW bash "$S" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  set -e
}

expect() { # expect <name> <expected file>: the last output equals the file
  if [ "${UPDATE_STATUS_FIXTURES:-}" = 1 ]; then cp "$tmp/out.txt" "$2"; return 0; fi
  if ! cmp -s "$2" "$tmp/out.txt"; then
    diff "$2" "$tmp/out.txt" >&2 || true
    fail "$1: the output differs from $2"
  fi
}

echo "== the table (full board, two busy slots)"
markers a
run_in "$tmp/work" a
[ "$code" = 0 ] || fail "exit code $code: $(cat "$tmp/err.txt")"
expect "table" "$FIX/a/expected.txt"
# the rules, one line each, so that a wrong table is named and not only different
out=$(cat "$tmp/out.txt")
first=$(printf '%s\n' "$out" | sed -n 2p)
case "$first" in " 2  Config validator against the sche...  Spec review"*) ;; *) fail "Spec review is not the first row: $first" ;; esac
case "$(printf '%s\n' "$out" | sed -n 3p)" in " 3  "*"Approved"*) ;; *) fail "Approved is not the second row" ;; esac
for needle in 'Big plan' 'Backlog one' 'Done one' 'A pull request on the board'; do
  case "$out" in *"$needle"*) fail "'$needle' must not be listed" ;; esac
done
case "$out" in *"not shown: 2 at Backlog, 1 at Done (use --all)"*) ;; *) fail "the 'not shown' line" ;; esac
case "$out" in *"[Story]"*|*"[Bug]"*) fail "a [Story] or [Bug] prefix was not removed" ;; esac
printf '%s\n' "$out" | grep '^ *5  .*stale: Review but the PR is merged$' >/dev/null || fail "Review with a merged PR is not flagged"
printf '%s\n' "$out" | grep '^ *8  .*stale: Spec but no spec PR$' >/dev/null || fail "Spec without a spec PR is not flagged"
printf '%s\n' "$out" | grep '^ *9  .*Spec  .* 40m *$' >/dev/null || fail "a fresh Spec must not be flagged: $(printf '%s\n' "$out" | grep '^ *9 ')"
printf '%s\n' "$out" | grep '^ *6  .*alex  *#34 open, ci pass' >/dev/null || fail "an assignee is not shown, or the PR column is wrong"
printf '%s\n' "$out" | grep '^ *4  .*slot 1  *#33 open, ci fail' >/dev/null || fail "a slot is not shown as the worker"
printf '%s\n' "$out" | grep '^ *14  .*#41 open, ci none' >/dev/null || fail "the open PR must win over the merged one"
printf '%s\n' "$out" | grep '^ *15  .*#42 open, ci fail' >/dev/null || fail "a failing status context is not ci fail"
printf '%s\n' "$out" | grep '^ *16  .*#43 draft' >/dev/null || fail "a draft PR"
printf '%s\n' "$out" | grep '^ *7  .*#35 open, ci pending' >/dev/null || fail "a running check is not ci pending"
printf '%s\n' "$out" | grep '^ *6  .*#34 open' >/dev/null || fail "the implementation PR must be shown at Review, not the spec PR"
printf '%s\n' "$out" | grep '^ *2  .*#31 open, ci pass' >/dev/null || fail "the spec PR must be shown at Spec review"
printf '%s\n' "$out" | grep '^ *10  .* 6d' >/dev/null || fail "an item without a status event takes its creation time"
# oldest first inside Review
order=$(printf '%s\n' "$out" | grep ' Review ' | awk '{ printf "%s ", $1 }')
[ "$order" = "7 5 14 6 17 16 15 " ] || fail "Review is not ordered oldest first: $order"

echo "== --all"
run_in "$tmp/work" a --all
[ "$code" = 0 ] || fail "--all exit code $code"
expect "--all" "$FIX/a/expected-all.txt"
case "$(cat "$tmp/out.txt")" in *"not shown"*) fail "--all must not print 'not shown'" ;; esac
grep -q 'Backlog one' "$tmp/out.txt" && grep -q 'Done one' "$tmp/out.txt" || fail "--all does not list Backlog and Done"

echo "== no slot busy: In progress and Spec flags"
markers b
run_in "$tmp/work" b
[ "$code" = 0 ] || fail "exit code $code"
expect "no busy slot" "$FIX/b/expected.txt"
grep -q '^ *20  .*stale: In progress, no PR and no busy slot$' "$tmp/out.txt" || fail "In progress with no PR and no slot is not flagged"
grep -q '^ *21  .*In progress' "$tmp/out.txt" && ! grep -q '^ *21  .*stale' "$tmp/out.txt" || fail "a fresh In progress must not be flagged"
grep -q '^ *22  .*stale: Review but the PR is closed$' "$tmp/out.txt" || fail "Review with a closed PR is not flagged"
! grep -q '^ *23  .*stale' "$tmp/out.txt" || fail "Spec with a merged spec PR must not be flagged"
grep -q '^ *26  .*stale: Spec but no spec PR$' "$tmp/out.txt" || fail "Spec with only a closed spec PR is not flagged"
! grep -q 'slots: none busy' "$tmp/out.txt" || fail "'slots: none busy' is still printed"
for n in 1 2 3 4; do grep -qx "   $n  free" "$tmp/out.txt" || fail "slot $n is not a free row that ends after free"; done
[ "$(tail -n 1 "$tmp/out.txt")" = "capacity: slots 4 (config), agents 2 (default)" ] || fail "the capacity line is not the last line"

echo "== the capacity line says when live values are in force"
printf '{\n  "slots": 3,\n  "maxAgents": 3,\n  "since": "2026-11-05T11:00:00"\n}\n' > "$tmp/wt/.slots/capacity.json"
run_in "$tmp/work" b
[ "$code" = 0 ] || fail "exit code $code: $(cat "$tmp/err.txt")"
expect "live capacity" "$FIX/b/expected-live.txt"
grep -qx 'capacity: slots 3 (live; config 4), agents 3 (live; config 2)' "$tmp/out.txt" || fail "the live capacity line"
rm -f "$tmp/wt/.slots/capacity.json"

echo "== the same without a worktrees section: no slots part"
cp "$tmp/no-slots.json" "$tmp/work/.claude/nightmill.json"
run_in "$tmp/work" b
expect "no slots configured" "$FIX/b/expected-noslots.txt"
! grep -q 'slots' "$tmp/out.txt" || fail "the slots part must be left out"
! grep -q '^capacity:' "$tmp/out.txt" || fail "no capacity line without a worktrees section"
cp "$tmp/with-slots.json" "$tmp/work/.claude/nightmill.json"

echo "== busy slots and their flags"
markers c
run_in "$tmp/work" c
[ "$code" = 0 ] || fail "exit code $code"
expect "slots" "$FIX/c/expected.txt"
grep -q 'stale: busy, PR merged (slot --release 1)$' "$tmp/out.txt" || fail "a busy slot with a merged PR"
grep -q 'stale: busy, PR closed (slot --abandon 2)$' "$tmp/out.txt" || fail "a busy slot with a closed PR"
grep -q 'feat/stale .*stale: busy, no open PR$' "$tmp/out.txt" || fail "an old busy slot without a PR"
grep -q 'feat/new ' "$tmp/out.txt" && ! grep -q 'feat/new .*stale' "$tmp/out.txt" || fail "a new busy slot without a PR must not be flagged"
# the Slots section (iteration 23): every slot with its agent state, skill, step and the age of the last report
grep -qx 'slot  State  Agent    Branch       Skill             Step   Report  Since  PR          Flag' "$tmp/out.txt" || fail "the header of the Slots section"
grep -q '^   1  busy   stalled  feat/merged  next/session      done       1d ' "$tmp/out.txt" || fail "slot 1: stalled, next/session, done"
grep -q '^   2  busy   unknown  feat/closed  ?                 ?           - ' "$tmp/out.txt" || fail "slot 2: a three-key marker is unknown, ?, -"
grep -q '^   3  busy   stalled  feat/stale   next/implementer  check      2d ' "$tmp/out.txt" || fail "slot 3: stalled"
grep -qx '   4  busy   running  feat/new     fix/fixer         test       5m    10m  -' "$tmp/out.txt" || fail "slot 4: running, a Report of 5m"

echo "== an unusable stalledAfterMinutes: the same table and the slot script's note"
sed 's/"slots": 4 }/"slots": 4, "stalledAfterMinutes": 0 }/' "$tmp/with-slots.json" > "$tmp/work/.claude/nightmill.json"
grep -q '"stalledAfterMinutes": 0' "$tmp/work/.claude/nightmill.json" || fail "the config copy has no stalledAfterMinutes"
run_in "$tmp/work" c
[ "$code" = 0 ] || fail "stalledAfterMinutes 0: exit code $code"
expect "stalledAfterMinutes 0" "$FIX/c/expected.txt"
grep -qx 'slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30' "$tmp/err.txt" || fail "stalledAfterMinutes 0: no note on standard error: $(cat "$tmp/err.txt")"
cp "$tmp/with-slots.json" "$tmp/work/.claude/nightmill.json"
run_in "$tmp/work" c
[ ! -s "$tmp/err.txt" ] || fail "status printed on standard error: $(cat "$tmp/err.txt")"

echo "== porcelain"
# status.sh --porcelain (iteration 31): the cells of the text tables, tab separated, one record kind per line
no_cr_one_lf() { # no_cr_one_lf <name>: the last output holds no CR byte and ends with exactly one LF
  if LC_ALL=C grep -q "$(printf '\r')" "$tmp/out.txt"; then fail "$1: a carriage return in the porcelain output"; fi
  [ "$(tail -c 1 "$tmp/out.txt" | od -An -tx1 | tr -d ' \n')" = 0a ] || fail "$1: the porcelain output does not end with LF"
  [ "$(tail -c 2 "$tmp/out.txt" | od -An -tx1 | tr -d ' \n')" != 0a0a ] || fail "$1: the porcelain output ends with an empty line"
}
fields_ok() { # fields_ok <name>: every item line has eight fields and every slot line eleven
  awk -F '\t' '($1 == "item" && NF != 8) || ($1 == "slot" && NF != 11) { bad = 1; print "  " $0 } END { exit bad }' "$tmp/out.txt" >&2 \
    || fail "$1: a porcelain line with the wrong number of fields"
}
for scn in a b c; do
  markers "$scn"
  run_in "$tmp/work" "$scn" --porcelain
  [ "$code" = 0 ] || fail "porcelain $scn: exit code $code: $(cat "$tmp/err.txt")"
  expect "porcelain $scn" "$FIX/$scn/expected-porcelain.txt"
  no_cr_one_lf "porcelain $scn"
  fields_ok "porcelain $scn"
done
markers a
run_in "$tmp/work" a --porcelain
grep -qxF "$(printf 'slot\t3\tfree\t\t\t\t\t\t\t\t')" "$tmp/out.txt" || fail "porcelain: a free slot is not slot, 3, free and eight empty fields"
grep -q "$(printf '^item\t2\t')" "$tmp/out.txt" || fail "porcelain: no item 2 line"
grep "$(printf '^item\t2\t')" "$tmp/out.txt" | grep "$(printf '\t')Config validator against the schema, run by init and the lint\$" >/dev/null \
  || fail "porcelain: the title of item 2 is not whole: $(grep "$(printf '^item\t2\t')" "$tmp/out.txt")"
echo "== porcelain without worktrees"
markers b
cp "$tmp/no-slots.json" "$tmp/work/.claude/nightmill.json"
run_in "$tmp/work" b --porcelain
[ "$code" = 0 ] || fail "porcelain without worktrees: exit code $code"
if grep -qE '^(slot|capacity)' "$tmp/out.txt"; then fail "porcelain without worktrees prints a slot or capacity line"; fi
cp "$tmp/with-slots.json" "$tmp/work/.claude/nightmill.json"
echo "== porcelain --all"
markers a
run_in "$tmp/work" a --all --porcelain
[ "$code" = 0 ] || fail "porcelain --all: exit code $code"
grep -q "$(printf '^item\t[0-9]*\tBacklog\t')" "$tmp/out.txt" && grep -q "$(printf '^item\t[0-9]*\tDone\t')" "$tmp/out.txt" || fail "porcelain --all does not list Backlog and Done"
if grep -q 'not shown' "$tmp/out.txt"; then fail "porcelain --all prints 'not shown'"; fi
fields_ok "porcelain --all"
echo "== porcelain with a failing gh"
set +e
base_sync "$tmp/work"
(cd "$tmp/work" && PATH="$tmp/bin:$PATH" GH_FIX="$FIX/a" GH_LOG="$tmp/gh.log" GH_FAIL=1 NIGHTMILL_NOW=$NOW bash "$S" --porcelain) > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
[ "$code" = 2 ] && grep -q 'bad credentials' "$tmp/err.txt" || fail "porcelain with a failing gh must exit 2 with its message: $code $(cat "$tmp/err.txt")"
[ ! -s "$tmp/out.txt" ] || fail "porcelain with a failing gh printed on standard output: $(cat "$tmp/out.txt")"
markers c
run_in "$tmp/work" c

echo "== reads only"
for c in 'project item-list' 'project view' 'pr list' 'api graphql'; do
  grep -q "$c" "$tmp/gh.log" || fail "gh $c was never called"
done
if grep -E 'item-edit|item-add|item-archive|pr merge|issue edit|issue comment|issue close|mutation' "$tmp/gh.log"; then fail "status.sh changed something"; fi

echo "== errors"
run_in "$tmp/work" a --nope
[ "$code" = 2 ] || fail "an unknown option must exit 2, got $code"
run_in "$tmp/plain" a
[ "$code" = 2 ] && grep -q 'nightmill.json' "$tmp/err.txt" || fail "no config must exit 2 and name the file: $(cat "$tmp/err.txt")"
set +e
base_sync "$tmp/work"
(cd "$tmp/work" && PATH="$tmp/bin:$PATH" GH_FIX="$FIX/a" GH_LOG="$tmp/gh.log" GH_FAIL=1 NIGHTMILL_NOW=$NOW bash "$S") > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
[ "$code" = 2 ] && grep -q 'bad credentials' "$tmp/err.txt" || fail "a failing gh must exit 2 with its message: $code $(cat "$tmp/err.txt")"

echo "== json"
# status.sh --json (iteration 54, #166): the cells of the text tables as one JSON object on one line, the same cells as
# --porcelain; the expected files are tests/fixtures/status/<scenario>/expected.json (d: a title with a quote, a
# backslash, a letter outside ASCII and a tab; it has no porcelain file, its cells are compared with a live --porcelain)
# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"
cells_match() { # cells_match <name> <json file> <porcelain file>: the items and slots of the JSON hold the cells of the porcelain, in order
  local name=$1 jf=$2 pf=$3 i n key col want got
  json_load "$jf" || fail "$name: cannot load the JSON"
  n=$(awk -F '\t' '$1 == "item" { c++ } END { print c + 0 }' "$pf")
  [ "$(json_len items)" = "$n" ] || fail "$name: $(json_len items) items in the JSON, $n in the porcelain"
  for ((i = 0; i < n; i++)); do
    for pair in number:2 status:3 who:4 pr:5 age:6 flag:7 title:8; do
      key=${pair%%:*}; col=${pair##*:}
      want=$(awk -F '\t' -v i="$i" -v c="$col" '$1 == "item" { if (k++ == i) { print $c; exit } }' "$pf")
      got=$(json_get "items[$i].$key")
      [ "$got" = "$want" ] || fail "$name: item $i $key is [$got] in the JSON and [$want] in the porcelain"
    done
  done
  n=$(awk -F '\t' '$1 == "slot" { c++ } END { print c + 0 }' "$pf")
  if [ "$n" = 0 ]; then
    [ "$(json_len slots)" = 0 ] || fail "$name: slots in the JSON, none in the porcelain"
  else
    [ "$(json_len slots)" = "$n" ] || fail "$name: $(json_len slots) slots in the JSON, $n in the porcelain"
  fi
  for ((i = 0; i < n; i++)); do
    for pair in slot:2 state:3 agent:4 branch:5 skill:6 step:7 report:8 since:9 pr:10 flag:11; do
      key=${pair%%:*}; col=${pair##*:}
      want=$(awk -F '\t' -v i="$i" -v c="$col" '$1 == "slot" { if (k++ == i) { print $c; exit } }' "$pf")
      got=$(json_get "slots[$i].$key")
      [ "$got" = "$want" ] || fail "$name: slot $i $key is [$got] in the JSON and [$want] in the porcelain"
    done
  done
  want=$(awk -F '\t' '$1 == "capacity" { print $2 }' "$pf")
  [ "$(json_get capacity)" = "$want" ] || fail "$name: capacity is [$(json_get capacity)] in the JSON and [$want] in the porcelain"
}
for scn in a b c d; do
  markers "$scn"
  run_in "$tmp/work" "$scn" --json
  [ "$code" = 0 ] || fail "json $scn: exit code $code: $(cat "$tmp/err.txt")"
  expect "json $scn" "$FIX/$scn/expected.json"
  no_cr_one_lf "json $scn"
  [ "$(wc -l < "$tmp/out.txt" | tr -d ' ')" = 1 ] || fail "json $scn: the output is not one line"
  json_check "$tmp/out.txt" || fail "json $scn: the output is not valid JSON"
  [ ! -s "$tmp/err.txt" ] || fail "json $scn: status printed on standard error: $(cat "$tmp/err.txt")"
  cp "$tmp/out.txt" "$tmp/json.out"
  if [ -f "$FIX/$scn/expected-porcelain.txt" ]; then
    cells_match "json $scn" "$tmp/json.out" "$FIX/$scn/expected-porcelain.txt"
  else
    run_in "$tmp/work" "$scn" --porcelain
    cp "$tmp/out.txt" "$tmp/porcelain.out"
    cells_match "json $scn" "$tmp/json.out" "$tmp/porcelain.out"
  fi
done
echo "== json --all"
markers a
run_in "$tmp/work" a --all --json
[ "$code" = 0 ] || fail "json --all: exit code $code: $(cat "$tmp/err.txt")"
no_cr_one_lf "json --all"
json_check "$tmp/out.txt" || fail "json --all: the output is not valid JSON"
grep -q '"status":"Backlog"' "$tmp/out.txt" && grep -q '"status":"Done"' "$tmp/out.txt" || fail "json --all does not list Backlog and Done"
if grep -q 'not shown' "$tmp/out.txt"; then fail "json --all prints 'not shown'"; fi
cp "$tmp/out.txt" "$tmp/json.out"
run_in "$tmp/work" a --all --porcelain
cp "$tmp/out.txt" "$tmp/porcelain.out"
cells_match "json --all" "$tmp/json.out" "$tmp/porcelain.out"
# without --all the Backlog and Done items are not there
run_in "$tmp/work" a --json
if grep -q '"status":"Backlog"\|"status":"Done"' "$tmp/out.txt"; then fail "json: the Backlog or Done items are listed without --all"; fi
echo "== json: the title of scenario d is escaped"
markers d
run_in "$tmp/work" d --json
grep -qF 'Say \"hi\" at C:\\dir café end' "$tmp/out.txt" || fail "json d: the title is not Say \\\"hi\\\" at C:\\\\dir café end: $(cat "$tmp/out.txt")"
grep -q "$(printf 'caf\303\251 end')" "$tmp/out.txt" || fail "json d: the letter is not written as its UTF-8 bytes"
if LC_ALL=C grep -q "[$(printf '\001-\037\177')]" "$tmp/out.txt"; then fail "json d: a control byte in the output"; fi
echo "== json without worktrees: slots and capacity are null"
cp "$tmp/no-slots.json" "$tmp/work/.claude/nightmill.json"
markers b
run_in "$tmp/work" b --json
[ "$code" = 0 ] || fail "json without worktrees: exit code $code"
case "$(cat "$tmp/out.txt")" in *'"slots":null,"capacity":null}') ;; *) fail "json without worktrees: slots and capacity are not null: $(tail -c 120 "$tmp/out.txt")" ;; esac
json_check "$tmp/out.txt" || fail "json without worktrees: the output is not valid JSON"
cp "$tmp/with-slots.json" "$tmp/work/.claude/nightmill.json"
echo "== json: usage and a failing gh"
markers a
for args in "--porcelain --json" "--json --porcelain" "--all --porcelain --json"; do
  # shellcheck disable=SC2086
  run_in "$tmp/work" a $args
  [ "$code" = 2 ] || fail "$args: exit code $code, 2 expected"
  grep -qxF 'usage: status.sh [--all] [--porcelain | --json]' "$tmp/err.txt" || fail "$args: no usage line: $(cat "$tmp/err.txt")"
  [ ! -s "$tmp/out.txt" ] || fail "$args: printed on standard output: $(cat "$tmp/out.txt")"
done
run_in "$tmp/work" a --nope
[ "$code" = 2 ] && grep -qxF 'usage: status.sh [--all] [--porcelain | --json]' "$tmp/err.txt" || fail "--nope: the usage line names --json: $(cat "$tmp/err.txt")"
set +e
base_sync "$tmp/work"
(cd "$tmp/work" && PATH="$tmp/bin:$PATH" GH_FIX="$FIX/a" GH_LOG="$tmp/gh.log" GH_FAIL=1 NIGHTMILL_NOW=$NOW bash "$S" --json) > "$tmp/out.txt" 2> "$tmp/err.txt"
code=$?
set -e
[ "$code" = 2 ] && grep -q 'bad credentials' "$tmp/err.txt" || fail "json with a failing gh must exit 2 with its message: $code $(cat "$tmp/err.txt")"
[ ! -s "$tmp/out.txt" ] || fail "json with a failing gh printed on standard output: $(cat "$tmp/out.txt")"
# --json makes the same gh calls as the text form and changes nothing
: > "$tmp/gh.log"
run_in "$tmp/work" a --json
for c in 'project item-list' 'project view' 'pr list' 'api graphql'; do
  grep -q "$c" "$tmp/gh.log" || fail "json: gh $c was never called"
done
if grep -E 'item-edit|item-add|item-archive|pr merge|issue edit|issue comment|issue close|mutation' "$tmp/gh.log"; then fail "status.sh --json changed something"; fi
echo "== the text form and the porcelain form are unchanged"
for scn in a b c; do
  markers "$scn"
  run_in "$tmp/work" "$scn"
  expect "text $scn" "$FIX/$scn/expected.txt"
  run_in "$tmp/work" "$scn" --porcelain
  expect "porcelain $scn" "$FIX/$scn/expected-porcelain.txt"
done

echo "== the lint notices a status script that changes the board"
cp_dir="$tmp/repocopy"; mkdir -p "$cp_dir"
( cd "$here" && tar -cf - --exclude=.git . ) | ( cd "$cp_dir" && tar -xf - )
# On a failure the lint's FAIL: lines (else its whole output) follow, so a CI log names the rule (#217).
if ! out=$(cd "$cp_dir" && bash tests/lint.sh 2>&1); then
  fail "the lint fails on an unchanged copy of the repository
$(printf '%s\n' "$out" | grep 'FAIL:' || printf '%s\n' "$out")"
fi
printf '
gh project item-edit --id x
' >> "$cp_dir/scripts/status.sh"
if out=$(cd "$cp_dir" && bash tests/lint.sh 2>&1); then fail "the lint accepted a status script with gh project item-edit"; fi
case "$out" in *"scripts/status.sh changes something"*) ;; *) fail "the lint did not name the script: $out" ;; esac

echo "STATUS OK"
