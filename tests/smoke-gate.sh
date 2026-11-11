#!/usr/bin/env bash
# tests/smoke-gate.sh - scripts/gate.sh against a throwaway project and a fake gh (iteration 53, #165;
# docs/specs/iteration-53-run-limits.md, "Tests"). smoke-gate.ps1 runs the same cases. Needs bash, git and awk, no network.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
G="$here/scripts/gate.sh"
fx="$here/tests/fixtures/gate"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-gate.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$G" ] || fail "scripts/gate.sh does not exist"

# the fake gh: answers api graphql from $EPIC (exit 1 when GH_FAIL is set), logs every call, fails on any other
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
if [ "${1:-} ${2:-}" = "api graphql" ]; then
  if [ -n "${GH_FAIL:-}" ]; then echo "fake gh: boom" >&2; exit 1; fi
  cat "$EPIC"
  exit 0
fi
echo "fake gh: unexpected call" >&2
exit 1
GH
chmod +x "$tmp/bin/gh"

T0=1794297600 # the claim of the take of slot 1 in the fixture ledger, 2026-11-10T08:00:00Z

c="$tmp/p"
mkdir -p "$c"
git init -q --bare -b main "$c/origin.git"
git clone -q "$c/origin.git" "$c/main" 2>/dev/null
main="$c/main"
git -C "$main" config user.email t@example.com
git -C "$main" config user.name t
git -C "$main" checkout -q -b main 2>/dev/null || true
L="$c/wt/.slots/ledger.tsv"
export GH_LOG="$c/gh.log" EPIC="$c/epic.json" NIGHTMILL_CLOCK_FILE="$c/clock"
: > "$GH_LOG"
echo $((T0 + 60)) > "$NIGHTMILL_CLOCK_FILE"

# set_cfg <limits member or empty>: write, commit and push the config on main in the main checkout
set_cfg() {
  mkdir -p "$main/.claude"
  printf '{\n  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },\n  "maintainer": { "name": "Alex" },\n  "verification": { "check": "true" },\n  "worktrees": { "root": "../wt", "slots": 2 }%s\n}\n' "${1:+,$'\n'  $1}" > "$main/.claude/nightmill.json"
  git -C "$main" add -A
  git -C "$main" commit -q --allow-empty -m "config"
  git -C "$main" push -q origin main 2>/dev/null
}
set_cfg ""
git -C "$main" remote set-head origin main >/dev/null 2>&1
git -C "$main" fetch -q origin
reset_ledger() { mkdir -p "$c/wt/.slots"; cp "$fx/ledger.tsv" "$L"; }
reset_ledger
epic() { cp "$fx/$1" "$EPIC"; }
epic epic-none.json

# snapshot: the tree, the ledger and the remote-tracking refs
snap() { { git -C "$main" status --porcelain; git -C "$main" for-each-ref; git -C "$main" rev-parse HEAD; [ -f "$L" ] && cksum < "$L"; } 2>&1; }

# gate <args>: run the gate from the main checkout; $out, $err, $code; the gate changes nothing and calls only api graphql
gate() {
  local before after
  before=$(snap); : > "$GH_LOG"
  (cd "$main" && PATH="$tmp/bin:$PATH" bash "$G" "$@") > "$c/out.txt" 2> "$c/err.txt"
  code=$?
  out=$(cat "$c/out.txt"); err=$(cat "$c/err.txt"); all="$out"$'\n'"$err"
  after=$(snap)
  [ "$before" = "$after" ] || fail "gate $*: the tree, the ledger or a ref changed"
  if [ -s "$GH_LOG" ]; then
    while IFS= read -r l; do
      case "$l" in "api graphql"*) ;; *) fail "gate $*: a gh call other than api graphql: $l" ;; esac
    done < "$GH_LOG"
  fi
}
want_code() { [ "$code" = "$1" ] || fail "$2: exit $code, $1 expected ($all)"; }
has() { case "$1" in *"$2"*) ;; *) fail "$3: '$2' not found in: $1" ;; esac; }
last_lines() { # last_lines <case> <line>...: the end of stdout is exactly these lines
  local what=$1 want got n
  shift
  want=$(printf '%s\n' "$@"); n=$#
  got=$(tail -n "$n" "$c/out.txt")
  [ "$got" = "$want" ] || fail "$what: the last $n lines are [$got], [$want] expected"
}
clock_at() { echo $((T0 + $1 * 60)) > "$NIGHTMILL_CLOCK_FILE"; }

echo "== go"
gate
want_code 0 go
last_lines go "gate: issues per run: 10" "gate: go"

echo "== paused"
set_cfg '"limits": { "paused": true }'
gate
want_code 1 paused
has "$all" "gate: paused: limits.paused is true on origin/HEAD:.claude/nightmill.json" paused
gate --issue 21
want_code 1 "paused with an issue"
set_cfg ""

echo "== paused on a branch only"
git -C "$main" checkout -q -b feat/unpause 2>/dev/null
mkdir -p "$main/.claude"
printf '{\n  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },\n  "maintainer": { "name": "Alex" },\n  "verification": { "check": "true" },\n  "worktrees": { "root": "../wt", "slots": 2 },\n  "limits": { "paused": true }\n}\n' > "$main/.claude/nightmill.json"
git -C "$main" commit -q -am "pause on a branch"
gate
want_code 0 "paused on a branch only"
git -C "$main" checkout -q main

echo "== paused, not yet fetched"
git clone -q "$c/origin.git" "$c/other" 2>/dev/null
git -C "$c/other" config user.email t@example.com
git -C "$c/other" config user.name t
printf '{\n  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },\n  "maintainer": { "name": "Alex" },\n  "verification": { "check": "true" },\n  "worktrees": { "root": "../wt", "slots": 2 },\n  "limits": { "paused": true }\n}\n' > "$c/other/.claude/nightmill.json"
git -C "$c/other" commit -q -am "pause"
git -C "$c/other" push -q origin main 2>/dev/null
gate
want_code 0 "paused, not yet fetched (the gate does not fetch)"
git -C "$main" fetch -q origin
gate
want_code 1 "paused after the fetch"
has "$all" "gate: paused: limits.paused is true on origin/HEAD:.claude/nightmill.json" "paused after the fetch"
git -C "$c/other" revert --no-edit HEAD >/dev/null 2>&1
git -C "$c/other" push -q origin main 2>/dev/null
git -C "$main" pull -q --rebase origin main 2>/dev/null
git -C "$main" fetch -q origin
gate
want_code 0 "unpaused again"

echo "== epic"
epic epic-paused.json
gate --issue 21
want_code 4 "epic paused"
has "$all" "gate: paused: epic #5 has the label paused" "epic paused"
epic epic-open.json
gate --issue 21
want_code 0 "epic not paused (a parent without the label)"
epic epic-none.json
gate --issue 21
want_code 0 "epic not paused (no parent)"
# the query is made with --issue only
gate
[ ! -s "$GH_LOG" ] || fail "no --issue: gh was called"

echo "== gh fails"
GH_FAIL=1; export GH_FAIL
gate --issue 21
want_code 2 "gh fails"
has "$all" "gate: cannot check: the epic of #21 could not be read: " "gh fails"
has "$all" "fake gh: boom" "gh fails"
unset GH_FAIL

echo "== cost"
set_cfg '"limits": { "costPerIssueUsd": 5 }'
gate --issue 21; want_code 0 "cost 21 under"
last_lines "cost 21 under" 'gate: spent on #21: $4.00 of $5.00' "gate: go"
set_cfg '"limits": { "costPerIssueUsd": 4 }'
gate --issue 21; want_code 3 "cost 21 at the limit"
has "$all" 'gate: limit: #21 has spent $4.00 in headless runs; the limit is $4.00 (limits.costPerIssueUsd)' "cost 21 at the limit"
set_cfg '"limits": { "costPerIssueUsd": 3.01 }'
gate --issue 12; want_code 0 "cost 12 under (half of the 11,12 line)"
last_lines "cost 12 under" 'gate: spent on #12: $3.00 of $3.01' "gate: go"
set_cfg '"limits": { "costPerIssueUsd": 3 }'
gate --issue 12; want_code 3 "cost 12 at the limit"
has "$all" '#12 has spent $3.00 in headless runs; the limit is $3.00' "cost 12 at the limit"
set_cfg ""

echo "== minutes"
clock_at 179
gate --issue 21 --slot 1; want_code 0 "minutes 179"
clock_at 180
gate --issue 21 --slot 1; want_code 3 "minutes 180"
has "$all" "gate: limit: #21 has been worked on for 180 minutes in this run; the limit is 180 (limits.minutesPerIssue)" "minutes 180"
echo "== run started later"
(cd "$main" && PATH="$tmp/bin:$PATH" NIGHTMILL_RUN_STARTED=$((T0 + 180 * 60 - 600)) bash "$G" --issue 21 --slot 1) > "$c/out.txt" 2> "$c/err.txt"
code=$?; all=$(cat "$c/out.txt" "$c/err.txt")
want_code 0 "run started later"
echo "== not measured"
clock_at 500
gate --issue 21; want_code 0 "not measured"
has "$(cat "$c/err.txt")" "gate: minutes per issue not measured (no slot and no driver run)" "not measured"
clock_at 1

echo "== turns"
gate --role tester --turns 150; want_code 0 "tester 150"
gate --role tester --turns 151; want_code 3 "tester 151"
has "$all" "gate: limit: the tester role took 151 turns; the limit is 150 (limits.turnsPerRole.tester)" "tester 151"
gate --role session --turns 201; want_code 3 "session 201"
gate --role session --turns 200; want_code 0 "session 200"
gate --role boss --turns 1; want_code 2 "unknown role"
has "$all" "gate: cannot check: unknown role boss" "unknown role"
set_cfg '"limits": { "turnsPerRole": { "worker": 5 } }'
gate --role worker --turns 6; want_code 3 "a configured role limit"
has "$all" "(limits.turnsPerRole.worker)" "a configured role limit"
gate --role tester --turns 150; want_code 0 "a role keeps its default beside a configured one"
set_cfg ""

echo "== issues left"
for pair in 3=3 0=0 20=10 10=10 x=10; do
  (cd "$main" && PATH="$tmp/bin:$PATH" NIGHTMILL_ISSUES_LEFT="${pair%%=*}" bash "$G") > "$c/out.txt" 2> "$c/err.txt"
  code=$?; all=$(cat "$c/out.txt" "$c/err.txt")
  want_code 0 "issues left ${pair%%=*}"
  last_lines "issues left ${pair%%=*}" "gate: issues per run: ${pair#*=}" "gate: go"
done

echo "== bad value"
bad() { # bad <limits members> <message>
  set_cfg "\"limits\": { $1 }"
  gate --issue 21
  want_code 2 "bad value ($1)"
  has "$all" "gate: cannot check: $2" "bad value ($1)"
  [ ! -s "$GH_LOG" ] || fail "bad value ($1): gh was called"
}
bad '"paused": "yes"' 'limits.paused must be true or false, got "yes"'
bad '"minutesPerIssue": 0' 'limits.minutesPerIssue must be a whole number from 1 to 1440, got 0'
bad '"minutesPerIssue": 1441' 'limits.minutesPerIssue must be a whole number from 1 to 1440, got 1441'
bad '"minutesPerIssue": 2.5' 'limits.minutesPerIssue must be a whole number from 1 to 1440, got 2.5'
bad '"costPerIssueUsd": 0' 'limits.costPerIssueUsd must be a number from 0.01 to 10000, got 0'
bad '"turnsPerRole": { "tester": "9" }' 'limits.turnsPerRole.tester must be a whole number from 1 to 10000, got "9"'
bad '"issuesPerRun": 101' 'limits.issuesPerRun must be a whole number from 1 to 100, got 101'
set_cfg ""

echo "== no ledger"
rm -f "$L"
gate --issue 21; want_code 0 "no ledger"
last_lines "no ledger" 'gate: spent on #21: $0.00 of $25.00' "gate: go"
reset_ledger

echo "== usage"
gate --turns 3; want_code 2 "turns without role"
has "$err" "usage" "turns without role"
gate --issue x; want_code 2 "issue x"
has "$err" "usage" "issue x"
gate --role tester; want_code 2 "role without turns"
gate --bogus; want_code 2 "unknown option"
gate --help; want_code 0 "help"
has "$out" "gate.sh" "help"

echo "smoke-gate.sh: ok"
