#!/usr/bin/env bash
# tests/smoke-history.sh - scripts/history.sh against a fixture ledger, fixture board pages and a fake gh (iteration 54,
# #166; docs/specs/iteration-54-history-metrics.md, "Tests"). smoke-history.ps1 runs the same cases against the same
# expected files in tests/fixtures/history/. The clock is NIGHTMILL_CLOCK_FILE (test only): 2026-11-09T12:00:00Z,
# 1794225600 seconds since 1970. Needs bash, git and awk, no jq, no network (the fake gh answers the one board query).
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
H="$here/scripts/history.sh"
FIX="$here/tests/fixtures/history"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-history.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
CLOCK_NOW=1794225600

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$H" ] || fail "scripts/history.sh does not exist"

# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"
# shellcheck source=../scripts/lib/ledger.sh
. "$here/scripts/lib/ledger.sh"

# the fake gh: logs every call to $GH_LOG, answers api graphql from $BOARD_DIR/page-<i>.json by the after value it is
# given (no after: page 1; after=cur1: page 2), exit 1 with a message when GH_FAIL is set, fails on any other call
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
if [ "${1:-} ${2:-}" = "api graphql" ]; then
  if [ -n "${GH_FAIL:-}" ]; then echo "fake gh: boom" >&2; exit 1; fi
  after=""; prev=""
  for a in "$@"; do
    case "$prev" in -f|-F|--raw-field|--field) case "$a" in after=*) after=${a#after=} ;; esac ;; esac
    prev=$a
  done
  case "$after" in
    "") f="$BOARD_DIR/page-1.json" ;;
    cur1) f="$BOARD_DIR/page-2.json" ;;
    *) echo "fake gh: no page after $after" >&2; exit 1 ;;
  esac
  cat "$f"
  exit 0
fi
echo "fake gh: unexpected call: $*" >&2
exit 1
GH
chmod +x "$tmp/bin/gh"

# the project: a committed config (the default statuses), the worktrees root ../wt, the ledger in <root>/.slots
main="$tmp/work"
L="$tmp/wt/.slots/ledger.tsv"
git init -q -b main "$main"
git -C "$main" config user.email t@example.com
git -C "$main" config user.name t
mkdir -p "$main/.claude" "$tmp/wt/.slots"
# set_cfg [<the JSON string literal of the Backlog name>]: write and commit the config
set_cfg() {
  local board=""
  [ -z "${1:-}" ] || board=$',\n'"  \"board\": { \"statuses\": { \"backlog\": $1 } }"
  printf '{\n  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },\n  "maintainer": { "name": "Alex" },\n  "verification": { "check": "true" },\n  "labels": { "epic": "epic" },\n  "worktrees": { "root": "../wt", "slots": 2 }%s\n}\n' "$board" > "$main/.claude/nightmill.json"
  git -C "$main" add -A
  git -C "$main" commit -q --allow-empty -m config
}
set_cfg
cp "$FIX/ledger.tsv" "$L"
export GH_LOG="$tmp/gh.log" BOARD_DIR="$FIX" NIGHTMILL_CLOCK_FILE="$tmp/clock"
unset GH_FAIL
set_clock() { echo "$1" > "$NIGHTMILL_CLOCK_FILE"; }
set_clock "$CLOCK_NOW"
: > "$GH_LOG"

# snapshot: the checkout (tree and refs) and the ledger; history changes neither
snap() { { git -C "$main" status --porcelain --untracked-files=all; git -C "$main" rev-parse HEAD; [ -f "$L" ] && cksum < "$L"; } 2>&1; }
[ -z "$(git -C "$main" status --porcelain --untracked-files=all)" ] || fail "the test project is not clean before the first run"

# hist <arguments>: history.sh from the main checkout; stdout in out.txt, stderr in err.txt, the exit code in $code. The
# checkout and the ledger are as before, and the fake gh saw nothing but the board query (a read: no mutation).
hist() {
  local before after l
  before=$(snap); : > "$GH_LOG"
  (cd "$main" && PATH="${HIST_PATH:-$tmp/bin:$PATH}" bash "$H" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  code=$?
  out=$(cat "$tmp/out.txt"); err=$(cat "$tmp/err.txt")
  after=$(snap)
  [ "$before" = "$after" ] || fail "history $*: the checkout or the ledger changed"
  if [ -s "$GH_LOG" ]; then
    while IFS= read -r l; do
      case "$l" in "api graphql "*repositoryOwner*) ;; *) fail "history $*: a gh call other than the board query: $l" ;; esac
      case "$l" in *mutation*) fail "history $*: a gh call with a mutation: $l" ;; esac
    done < "$GH_LOG"
  fi
}
want_code() { [ "$code" = "$1" ] || fail "$2: exit $code, $1 expected ($err)"; }
same() { # same <name> <expected file>: the last stdout is byte for byte the file
  if ! cmp -s "$2" "$tmp/out.txt"; then diff "$2" "$tmp/out.txt" >&2 || true; fail "$1: the output differs from $2"; fi
}
has() { case "$1" in *"$2"*) ;; *) fail "$3: '$2' not found in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) fail "$3: '$2' found in: $1" ;; esac; }
only_malformed_note() { # the one note on standard error: the skipped malformed line of the fixture ledger
  [ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" = 1 ] || fail "$1: standard error is not one line: $err"
  grep -qE '^history: skipped 1 malformed lines of .*ledger\.tsv$' <<<"$err" || fail "$1: the note about the malformed line: $err"
}
cell() { # cell <issue number> <column from the left, 1 = #n>: a cell of an issue row of the last text output
  awk -v n="#$1" -v c="$2" '$1 == n { print $c }' "$tmp/out.txt"
}

echo "== text"
hist
want_code 0 text
same text "$FIX/expected-text.txt"
only_malformed_note text
# the rules, one line each, so that a wrong table is named and not only different
[ "$(cell 12 8) $(cell 12 9) $(cell 12 11)" = '2 1 $3.00' ] || fail "text: #12 is not rounds 2, checks 1, \$3.00: $(grep '^#12 ' "$tmp/out.txt")"
[ "$(cell 13 8) $(cell 13 9) $(cell 13 11)" = '0 0 $2.50' ] || fail "text: #13 is not rounds 0, checks 0, \$2.50: $(grep '^#13 ' "$tmp/out.txt")"
[ "$(cell 14 8) $(cell 14 9) $(cell 14 11)" = '- 0 $3.00' ] || fail "text: #14 is not rounds -, checks 0, \$3.00: $(grep '^#14 ' "$tmp/out.txt")"
has "$out" 'cost: $8.90 in 4 headless runs; $0.40 on no issue; 1 runs without a cost' text
has "$out" 'slots: 3 (record), utilisation 32%' text
has "$out" 'note: 1 stays at a status not in board.statuses were not counted' text
has "$out" 'note: 1 takes have no take line; their held time starts at their first line' text
# the median is the lower middle of an even count (Backlog: 2h10m and 15h05m) and the middle of an odd one (Ready)
grep -qE '^Backlog +2 +2h10m +15h05m +17h15m$' <<<"$out" || fail "text: the Backlog row (the lower middle of two stays)"
grep -qE '^Ready +3 +30m00s +3h00m +3h40m$' <<<"$out" || fail "text: the Ready row (the middle of three stays)"
# a take that has no code-review has no rounds, an issue with a take and none of the round names has 0
# the epic #5 and the project 2 event are not counted: no #5 row, and the Approved stay of #13 is 2h25m
if grep -q '^#5 ' "$tmp/out.txt"; then fail "text: the epic is listed"; fi
[ "$(cell 13 5)" = 2h25m ] || fail "text: the project 2 event cut the Approved stay of #13: $(cell 13 5)"
# the text holds no carriage return and ends with one LF
if grep -q "$(printf '\r')" "$tmp/out.txt"; then fail "text: a carriage return in the output"; fi
[ "$(tail -c 1 "$tmp/out.txt" | od -An -tx1 | tr -d ' \n')" = 0a ] || fail "text: the output does not end with LF"

echo "== json"
hist --json
want_code 0 json
same json "$FIX/expected.json"
only_malformed_note json
json_check "$tmp/out.txt" || fail "json: the output is not valid JSON"
[ "$(wc -l < "$tmp/out.txt" | tr -d ' ')" = 1 ] || fail "json: the output is not one line"
if grep -q "$(printf '\r')" "$tmp/out.txt"; then fail "json: a carriage return in the output"; fi
# its numbers are the text form's, before formatting
cp "$tmp/out.txt" "$tmp/json.out"
hist
cp "$tmp/out.txt" "$tmp/text.out"
json_load "$tmp/json.out" || fail "json: cannot load the output"
[ "$(json_len statuses)" = 7 ] || fail "json: not seven statuses"
for i in 0 1 2 3 4 5 6; do
  want=$(awk -v r="$((i + 4))" 'NR == r { print $(NF - 3), $(NF - 2), $(NF - 1), $NF }' "$tmp/text.out")
  got="$(json_get "statuses[$i].stays") $(ledger_duration "$(json_get "statuses[$i].median")") $(ledger_duration "$(json_get "statuses[$i].max")") $(ledger_duration "$(json_get "statuses[$i].total")")"
  [ "$got" = "$want" ] || fail "json: status $i is [$got], the text form has [$want]"
done
for i in 0 1 2; do
  n=$(json_get "issues[$i].number")
  want=$(awk -v n="#$n" '$1 == n { print $8, $9, $10, substr($11, 2) }' "$tmp/text.out")
  got="$(json_get "issues[$i].rounds" -) $(json_get "issues[$i].checks" -) $(json_get "issues[$i].runs") $(json_get "issues[$i].cost")"
  [ "$got" = "$want" ] || fail "json: issue #$n is [$got], the text form has [$want]"
done
[ "$(json_get cost.total)" = 8.90 ] && [ "$(json_get cost.runs)" = 4 ] && [ "$(json_get cost.withoutCost)" = 1 ] && [ "$(json_get cost.noIssue)" = 0.40 ] || fail "json: the cost object"
[ "$(json_get slots.count)" = 3 ] && [ "$(json_get slots.from)" = record ] && [ "$(json_get slots.utilisation)" = 32 ] || fail "json: the slots object"
[ "$(json_get run -)" = - ] || fail "json: run is not null"

echo "== html"
rm -rf "$tmp/report"
hist --html "$tmp/report/sub"
want_code 0 html
[ "$out" = "history: wrote $tmp/report/sub/index.html" ] || fail "html: stdout is [$out]"
only_malformed_note html
[ "$(ls -A "$tmp/report/sub")" = index.html ] || fail "html: the folder holds more than index.html: $(ls -A "$tmp/report/sub")"
if ! cmp -s "$FIX/expected.html" "$tmp/report/sub/index.html"; then diff "$FIX/expected.html" "$tmp/report/sub/index.html" >&2 || true; fail "html: the page differs from expected.html"; fi
for w in '<script' '<link' '<a ' 'href' 'src=' 'url(' '@import' 'http' 'refresh' '<form' '<input'; do
  if grep -qiF -- "$w" "$tmp/report/sub/index.html"; then fail "html: the page contains '$w'"; fi
done
if grep -q "$(printf '\r')" "$tmp/report/sub/index.html"; then fail "html: a carriage return in the page"; fi
[ "$(head -c 3 "$tmp/report/sub/index.html" | od -An -tx1 | tr -d ' \n')" != efbbbf ] || fail "html: a byte order mark"
# a second run replaces the page; a name from the configuration is escaped
set_cfg '"A&B <x>"'
hist --html "$tmp/report/sub"
want_code 0 "html second run"
page=$(cat "$tmp/report/sub/index.html")
has "$page" '<td>A&amp;B &lt;x&gt;</td>' "html escaping"
hasnt "$page" 'A&B' "html escaping"
hasnt "$page" '<x>' "html escaping"
[ "$(ls -A "$tmp/report/sub")" = index.html ] || fail "html second run: the folder holds more than index.html"
set_cfg

echo "== html not writable"
printf 'not a folder\n' > "$tmp/afile"
hist --html "$tmp/afile"
want_code 1 "html not writable"
has "$err" "history: cannot write " "html not writable"
[ -z "$out" ] || fail "html not writable: stdout is [$out]"
[ "$(cat "$tmp/afile")" = "not a folder" ] || fail "html not writable: the file was changed"
if [ -n "$(find "$tmp" -name '.index.html.*' 2>/dev/null)" ]; then fail "html not writable: a temporary file is left"; fi
# a folder that cannot be written to (skipped when the process may write anywhere)
mkdir -p "$tmp/ro"
chmod a-w "$tmp/ro"
if ! ( : > "$tmp/ro/probe" ) 2>/dev/null; then
  hist --html "$tmp/ro/sub"
  want_code 1 "html in a read-only folder"
  has "$err" "history: cannot write " "html in a read-only folder"
  if [ -n "$(find "$tmp" -name '.index.html.*' 2>/dev/null)" ]; then fail "html in a read-only folder: a temporary file is left"; fi
fi
chmod u+w "$tmp/ro"

echo "== names from the configuration lose their control characters"
set_cfg '"Back\u0007log"'
hist
want_code 0 names
grep -qE '^Backlog +[0-9?]+ ' <<<"$out" || fail "names: the Backlog row (the name without its control character): $out"
if LC_ALL=C grep -q "[$(printf '\001-\010\013-\037\177')]" "$tmp/out.txt"; then fail "names: a control character reached the output"; fi
set_cfg

echo "== window"
hist --from 2026-11-09T04:30:00Z --to 2026-11-09T05:15:00Z
want_code 0 window
# the take without a take line is outside this window; the note about it is not part of this comparison
grep -v 'no take line' "$tmp/out.txt" > "$tmp/out.window"
cp "$tmp/out.window" "$tmp/out.txt"
same window "$FIX/expected-window.txt"
# the boundaries are included: the In progress stay of #13 ends at 04:30:00, the window's start
[ "$(cell 13 6)" = 30m00s ] || fail "window: the stay that ends at the start of the window is not counted: $(cell 13 6)"
if grep -q '^#12 \|^#14 ' "$tmp/out.window"; then fail "window: an issue without a take, a stay or a run in the window is listed"; fi
hist --from 2026-11-09 --to 2026-11-09
want_code 0 "window of dates"
has "$out" "history 2026-11-09T00:00:00Z to 2026-11-09T00:00:00Z (0s)" "window of dates"
# a window of 0 seconds: no share and no utilisation
has "$out" "utilisation -" "window of 0 seconds"

echo "== run"
hist --run 2026-11-09T01:00:00Z
want_code 0 run
same run "$FIX/expected-run.txt"
has "$out" "driver run 2026-11-09T01:00:00Z" run
has "$out" 'cost: $8.50 in 2 headless runs;' run
hist --json --run 2026-11-09T01:00:00Z
want_code 0 "run json"
json_load "$tmp/out.txt" || fail "run json: not valid JSON"
[ "$(json_get run)" = 2026-11-09T01:00:00Z ] && [ "$(json_get to)" = 2026-11-09T05:10:00Z ] || fail "run json: run and to: $(cat "$tmp/out.txt")"

echo "== run unknown"
hist --run 2026-11-08T00:00:00Z
want_code 0 "run unknown"
has "$out" "note: no run lines for the driver run 2026-11-08T00:00:00Z" "run unknown"
has "$out" "history 2026-11-08T00:00:00Z to 2026-11-09T12:00:00Z (36h00m), driver run 2026-11-08T00:00:00Z" "run unknown"
has "$out" 'cost: $0.00 in 0 headless runs; $0.00 on no issue; 0 runs without a cost' "run unknown"

echo "== gate agrees"
# the fixture ledger of the gate (iteration 53): the spend of #21 is $4.00 and of #12 $3.00 (half of $6.00 for #11,#12)
cp "$here/tests/fixtures/gate/ledger.tsv" "$L"
set_clock 1794297660
hist --from 1970-01-01
want_code 0 "gate agrees"
[ "$(cell 21 11)" = '$4.00' ] || fail "gate agrees: the cost of #21 is [$(cell 21 11)], \$4.00 expected: $out"
[ "$(cell 12 11)" = '$3.00' ] || fail "gate agrees: the cost of #12 is [$(cell 12 11)], \$3.00 expected: $out"
[ "$(cell 11 11)" = '$3.00' ] || fail "gate agrees: the cost of #11 is [$(cell 11 11)], \$3.00 expected: $out"
has "$out" 'cost: $10.00 in 2 headless runs; $0.00 on no issue; 0 runs without a cost' "gate agrees"
cp "$FIX/ledger.tsv" "$L"
set_clock "$CLOCK_NOW"

echo "== board fails"
GH_FAIL=1; export GH_FAIL
hist
want_code 0 "board fails"
same "board fails" "$FIX/expected-boardfails.txt"
hist --json
want_code 0 "board fails json"
same "board fails json" "$FIX/expected-boardfails.json"
json_check "$tmp/out.txt" || fail "board fails json: not valid JSON"
unset GH_FAIL
# no gh at all: only the system tools on the PATH
if ! PATH="/usr/bin:/bin" command -v gh >/dev/null 2>&1; then
  HIST_PATH="/usr/bin:/bin"; export HIST_PATH
  hist
  want_code 0 "no gh"
  has "$out" "note: the board was not read: " "no gh"
  grep -qE '^Backlog +\? +\? +\? +\?$' <<<"$out" || fail "no gh: the status rows are not ?: $out"
  grep -qE '^#12 +\? +\? +\? +\? +\? +\? +2 +1 +1 +\$3\.00$' <<<"$out" || fail "no gh: the row of #12 (times ?, the ledger parts as in text): $out"
  [ ! -s "$GH_LOG" ] || fail "no gh: the fake gh was called"
  unset HIST_PATH
fi

echo "== no ledger"
rm -f "$L"
hist
want_code 0 "no ledger"
grep -qE '^note: no record yet: .*/wt/\.slots/ledger\.tsv$' <<<"$out" || fail "no ledger: the note: $out"
# the window is the default week before now, and the status block comes from the board
has "$out" "history 2026-11-02T12:00:00Z to 2026-11-09T12:00:00Z (168h00m)" "no ledger"
[ "$(sed -n 3,10p "$tmp/out.txt")" = "$(sed -n 3,10p "$FIX/expected-text.txt")" ] || fail "no ledger: the status block is not the one of the board: $out"
hasnt "$out" "no issue in the window" "no ledger"
for n in 12 13 14; do
  [ "$(cell $n 11)" = - ] || fail "no ledger: the cost of #$n is [$(cell $n 11)], - expected: $out"
done
hist --json
want_code 0 "no ledger json"
json_check "$tmp/out.txt" || fail "no ledger json: not valid JSON"
cp "$FIX/ledger.tsv" "$L"

echo "== usage"
for args in "--json --html $tmp/x" "--run 2026-11-09T01:00:00Z --from 2026-01-01" "--run 2026-11-09T01:00:00Z --to 2026-11-10" "--from 2026-13-01" \
  "--from 2026-11-09 --to 2026-11-08" "--html" "--json --json" "--bogus" "--run 2026-11-09" "--from" "--from 2026-11-09 --from 2026-11-09" "extra"; do
  # shellcheck disable=SC2086
  hist $args
  want_code 2 "usage ($args)"
  grep -q '^usage: history\.sh' <<<"$err" || fail "usage ($args): no usage line on standard error: [$err]"
  [ -z "$out" ] || fail "usage ($args): printed [$out]"
  [ ! -s "$GH_LOG" ] || fail "usage ($args): gh was called"
done
[ ! -e "$tmp/x" ] || fail "usage: a folder was made"
hist --help
want_code 0 help
[[ "$out" == "usage: history.sh"* ]] || fail "help: no usage line on standard output: [$out]"

echo "== outside a checkout and without a config"
mkdir -p "$tmp/plain"
if ! git -C "$tmp/plain" rev-parse --git-dir >/dev/null 2>&1; then
  (cd "$tmp/plain" && PATH="$tmp/bin:$PATH" bash "$H") > "$tmp/out.txt" 2> "$tmp/err.txt"; code=$?
  [ "$code" = 2 ] || fail "outside a checkout: exit $code"
fi
git init -q -b main "$tmp/plain"
(cd "$tmp/plain" && PATH="$tmp/bin:$PATH" bash "$H") > "$tmp/out.txt" 2> "$tmp/err.txt"; code=$?
[ "$code" = 2 ] && grep -q 'nightmill.json' "$tmp/err.txt" || fail "no config: exit $code: $(cat "$tmp/err.txt")"

echo "== a ledger that cannot be read"
rm -f "$L"
mkdir "$L"
hist
want_code 1 "a ledger that is a folder"
has "$err" "history: cannot read " "a ledger that is a folder"
rmdir "$L"
cp "$FIX/ledger.tsv" "$L"

echo "smoke-history.sh: ok"
