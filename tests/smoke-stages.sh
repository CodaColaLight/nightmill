#!/usr/bin/env bash
# tests/smoke-stages.sh - the stage record (iteration 41): stages.sh against the fixture record in
# tests/fixtures/stages/ (ledger.tsv and the expected tables beside it), the step times of tests/check.sh against
# fixture steps, and the duration text. The clock comes from NIGHTMILL_CLOCK_FILE (test only), never from the system
# clock. T0 of the fixture is 2026-11-07T08:00:00Z, 1794038400 seconds since 1970. Needs bash, git and awk, no jq,
# no network (a fake gh logs every call; stages.sh must make none).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-stages.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
ST="$here/scripts/stages.sh"
FIX="$here/tests/fixtures/stages"
T0=1794038400

fail() { echo "FAIL: $*" >&2; exit 1; }

# A fake gh that records every call: the table is read-only and works without the network.
mkdir -p "$tmp/bin"
: > "$tmp/gh.log"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
echo "stages must not call gh" >&2
exit 1
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log"

# The project: a throwaway repository with the worktrees root ../wt; the record is <root>/.slots/ledger.tsv.
git init -q -b main "$tmp/work"
cd "$tmp/work"
mkdir -p .claude
cat > .claude/nightmill.json <<'EOF'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": { "root": "../wt", "slots": 2 }
}
EOF
L="$tmp/wt/.slots/ledger.tsv"
mkdir -p "$tmp/wt/.slots"
cp "$FIX/ledger.tsv" "$L"
CLOCK="$tmp/clock"
export NIGHTMILL_CLOCK_FILE="$CLOCK"
# the fixture clock: 13700 s after T0, so that the running take D has run for 11m40s
echo $((T0 + 13700)) > "$CLOCK"

# st <arguments>: stages.sh from inside the project; standard output in $out, standard error in $err, exit code in $rc
st() { set +e; out=$(bash "$ST" "$@" 2>"$tmp/err.txt"; echo "rc=$?"); set -e; rc=${out##*rc=}; out=${out%rc=*}; err=$(cat "$tmp/err.txt"); }
# same output as the files: the command substitution drops no trailing newline here, since "rc=" follows it
block() { cat "$FIX/expected-$1.txt"; }
nl=$'\n'

echo "== stages from a fixture record"
# Take A (slot 1, merged, issue 12): the worked example of decision 10
st --issue 12
[ "$rc" = 0 ] || fail "--issue 12: exit $rc: $err"
[ "$out" = "$(block a)${nl}" ] || fail "--issue 12: the table is not the worked example; got: [$out] wanted: [$(block a)]"
# the same bytes, trailing newline included
cmp -s <(bash "$ST" --issue 12 2>/dev/null) "$FIX/expected-a.txt" || fail "--issue 12: the bytes differ from expected-a.txt"
# two check runs are added, done is dropped, ci-and-merge is not inside pull-request, total equals to - S
grep -qE '^  check +2 +20m00s +20%$' <<<"$out" || fail "--issue 12: the two check runs are not added: $out"
if grep -qE '^  done ' <<<"$out"; then fail "--issue 12: done (reported after the PR opened) is counted: $out"; fi
grep -qE '^  pull-request +1 +30s +1%$' <<<"$out" || fail "--issue 12: pull-request is not 30s: $out"
grep -qE '^  ci-and-merge +1 +19m30s +20%$' <<<"$out" || fail "--issue 12: ci-and-merge is not 19m30s: $out"
grep -qE '^  total +1h40m +100%$' <<<"$out" || fail "--issue 12: the total is not 1h40m (to minus the take's start, not the free line): $out"

# no option: the last 5 takes, here all four, in file order, a blank line between them
st
[ "$rc" = 0 ] || fail "no option: exit $rc: $err"
want="$(block a)${nl}${nl}$(block b)${nl}${nl}$(block c)${nl}${nl}$(block d)${nl}"
[ "$out" = "$want" ] || fail "no option: not the four takes in file order; got: [$out]"
# take B, a take by the previous version: not-reported unknown, total unknown, every share -, ci-and-merge known
grep -qE '^  not-reported +1 +unknown +-$' <<<"$out" || fail "take B: not-reported is not unknown: $out"
grep -qE '^  total +unknown +-$' <<<"$out" || fail "take B: the total is not unknown: $out"
grep -qE '^  ci-and-merge +1 +12m30s +-$' <<<"$out" || fail "take B: ci-and-merge is not known: $out"
# take C: an unreported step (a take line and no step line) is known, abandoned, with no ci-and-merge
grep -qE '^-  feat/c  slot 1  abandoned 2026-11-07T11:21:40Z$' <<<"$out" || fail "take C: the header: $out"
# take D: running, the last step runs to the fixture clock
grep -qE '^-  feat/d  slot 2  running$' <<<"$out" || fail "take D: not running: $out"
[ "$(grep -c 'unknown' <<<"$out")" = 2 ] || fail "unknown shows more or less than the two cells of take B: $out"

# a line of a later kind is skipped without a note; the one with 10 fields and the one with a bad stamp give one note
[ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" = 1 ] || fail "standard error is not one line: $err"
grep -qE '^stages: skipped 2 malformed lines of .*ledger\.tsv$' <<<"$err" || fail "no note about the two malformed lines: $err"

# --last 1: take D only; --last 2: C and D
st --last 1
[ "$rc" = 0 ] && [ "$out" = "$(block d)${nl}" ] || fail "--last 1: exit $rc, got: [$out]"
st --last 2
[ "$rc" = 0 ] && [ "$out" = "$(block c)${nl}${nl}$(block d)${nl}" ] || fail "--last 2: exit $rc, got: [$out]"

# --issue 99: the no-record line, exit 0
st --issue 99
[ "$rc" = 0 ] || fail "--issue 99: exit $rc: $err"
grep -qF '#99: no record; every stage unknown (no slot took it, or a version before iteration 41 freed it)' <<<"$out$err" || fail "--issue 99: the no-record line: [$out] [$err]"
if grep -qE '^  total ' <<<"$out"; then fail "--issue 99 printed a table: $out"; fi
# --issue 7 is a PR number, not an issue: nothing matches
st --issue 7
grep -qF '#7: no record;' <<<"$out$err" || fail "--issue 7 matched the PR number: [$out]"

# usage errors: the usage line on standard error, nothing on standard output, exit 1
for args in "--last 0" "--last x" "--last 1000" "--last -1" "--last" "--issue 0" "--issue x" "--issue 01" "--issue 12345678901" "--issue 1 --last 2" "--last 2 --issue 1" "extra" "--issue 12 extra"; do
  # shellcheck disable=SC2086
  st $args
  [ "$rc" = 1 ] || fail "usage ($args): exit $rc: [$out] [$err]"
  [[ "$err" == "usage: "* ]] || fail "usage ($args): no usage line on standard error: [$err]"
  [ -z "$out" ] || fail "usage ($args): printed [$out]"
done

# read-only: no gh call, the record and its folder unchanged
before=$(cd "$tmp/wt" && find . | sort | tr '\n' ' ')
cp "$L" "$tmp/ledger.before"
st --last 5; st --issue 12
[ ! -s "$tmp/gh.log" ] || fail "stages.sh called gh: $(cat "$tmp/gh.log")"
cmp -s "$L" "$tmp/ledger.before" || fail "stages.sh changed the record"
[ "$before" = "$(cd "$tmp/wt" && find . | sort | tr '\n' ' ')" ] || fail "stages.sh wrote a file"

# no file: the no-record-yet line, exit 0; a record that cannot be read: exit 1
rm -f "$L"
st
[ "$rc" = 0 ] || fail "no file: exit $rc: $err"
grep -qE '^no record yet: .*ledger\.tsv$' <<<"$out$err" || fail "no file: [$out] [$err]"
st --issue 12
[ "$rc" = 0 ] && grep -qE '^no record yet: .*ledger\.tsv$' <<<"$out$err" || fail "no file with --issue: exit $rc [$out] [$err]"
mkdir "$L"
st
[ "$rc" = 1 ] || fail "a record that is a folder: exit $rc: [$out] [$err]"
grep -qE '^stages: cannot read .*ledger\.tsv' <<<"$err" || fail "a record that is a folder: standard error [$err]"
rmdir "$L"

echo "== a take by the previous version freed by this one, and a take that was never freed"
# a free line with no take before it is a take of its own with an unknown start and no steps; a take line followed by
# a second take line of the same slot is the first one "not freed", ended at its last line
{
  printf 'free\t2026-11-07T08:30:00Z\t1\tfeat/p\treleased\t\t\t5\t2026-11-07T08:10:00Z\t2026-11-07T08:20:00Z\t31\n'
  printf 'take\t2026-11-07T09:00:30Z\t2\tfeat/q\ttake\t\t\t\t2026-11-07T09:00:00Z\t2026-11-07T09:00:30Z\t\n'
  printf 'step\t2026-11-07T09:00:40Z\t2\tfeat/q\tslot-taken\tnext\tsession\t\t\t\t\n'
  printf 'take\t2026-11-07T10:00:30Z\t2\tfeat/r\ttake\t\t\t\t2026-11-07T10:00:00Z\t2026-11-07T10:00:30Z\t\n'
} > "$L"
st --issue 31
[ "$rc" = 0 ] || fail "free without a take: exit $rc: $err"
grep -qF '#31  feat/p  slot 1  merged 2026-11-07T08:20:00Z' <<<"$out" || fail "free without a take: the header: $out"
grep -qE '^  total +unknown +-$' <<<"$out" || fail "free without a take: the total is not unknown: $out"
st --last 5
grep -qF -- '-  feat/q  slot 2  not freed' <<<"$out" || fail "a take followed by a second take is not 'not freed': $out"
grep -qF -- '-  feat/r  slot 2  running' <<<"$out" || fail "the last take of slot 2 is not running: $out"
cp "$FIX/ledger.tsv" "$L"

echo "== the check's step times"
# NIGHTMILL_CHECK_STEPS (test only) names a file of <name> TAB <command> lines; the check runs exactly those steps.
# The steps move the fixture clock by 12 s, 75 s and 3700 s.
clock_step() { printf '%s' "echo \$(( \$(cat '$CLOCK') + $1 )) > '$CLOCK'"; } # a command that moves the clock by $1 s
steps="$tmp/steps.txt"
{
  printf 'one\t%s\n' "$(clock_step 12)"
  printf 'two\t%s; exit 1\n' "$(clock_step 75)"
  printf 'three\t%s\n' "$(clock_step 3700)"
} > "$steps"
echo "$T0" > "$CLOCK"
set +e; out=$(NIGHTMILL_CHECK_STEPS="$steps" bash "$here/tests/check.sh" --jobs 1 2>"$tmp/err.txt"); rc=$?; set -e
[ "$rc" = 1 ] || fail "check with a failing step: exit $rc: $out"
[ "$(head -n 1 <<<"$out")" = "check: full, 1 at a time (--jobs 1)" ] || fail "check: the header with --jobs 1: $out"
grep -qxF -- '-- one: ok (12s)' <<<"$out" || fail "check: the result line of step one: $out"
grep -qxF -- '-- two: FAILED (1m15s)' <<<"$out" || fail "check: the result line of step two: $out"
grep -qxF -- '-- three: ok (1h01m)' <<<"$out" || fail "check: the result line of step three: $out"
grep -qxF -- '== one' <<<"$out" || fail "check: the == line of step one is gone: $out"
grep -qxF 'CHECK FAILED: two' <<<"$out" || fail "check: CHECK FAILED: two: $out"
if grep -q '^SKIPPED:' <<<"$out"; then fail "check with fixture steps printed a SKIPPED line: $out"; fi
if grep -q 'ALL CHECKS PASSED' <<<"$out"; then fail "check with a failing step passed: $out"; fi
want=$(printf 'Times:\n  %-28s %8s\n  %-28s %8s\n  %-28s %8s\n  %-28s %8s' one 12s two 1m15s three 1h01m total 1h03m)
got=$(printf '%s\n' "$out" | awk '/^Times:$/ { p = 1 } p { print } /^  total / { p = 0 }')
[ "$got" = "$want" ] || fail "check: the Times block is not the three steps and the total of 3787 s; got: [$got] wanted: [$want]"
# the block comes after the last step and before the verdict
[ "$(printf '%s\n' "$out" | grep -n -m1 '^-- three:' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n -m1 '^Times:$' | cut -d: -f1)" ] || fail "check: Times comes before the last step: $out"
[ "$(printf '%s\n' "$out" | grep -n -m1 '^Times:$' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n -m1 '^CHECK FAILED' | cut -d: -f1)" ] || fail "check: Times comes after the verdict: $out"
# a second run with three passing steps
{
  printf 'one\t%s\n' "$(clock_step 12)"
  printf 'two\t%s\n' "$(clock_step 75)"
  printf 'three\t%s\n' "$(clock_step 3700)"
} > "$steps"
echo "$T0" > "$CLOCK"
set +e; out=$(NIGHTMILL_CHECK_STEPS="$steps" bash "$here/tests/check.sh" --jobs 1 2>"$tmp/err.txt"); rc=$?; set -e
[ "$rc" = 0 ] || fail "check with passing steps: exit $rc: $out"
grep -qxF -- '-- two: ok (1m15s)' <<<"$out" || fail "check: the result line of a passing step two: $out"
grep -qxF 'ALL CHECKS PASSED' <<<"$out" || fail "check: no ALL CHECKS PASSED: $out"
grep -qE '^  total +1h03m$' <<<"$out" || fail "check: the total of the passing run: $out"
if grep -q '^SKIPPED:' <<<"$out"; then fail "check with fixture steps printed a SKIPPED line: $out"; fi

echo "== the duration text"
# 0, 59, 60, 3599, 3600, 3659 and 93780 seconds, as the time column of a take whose steps last that long
cp "$FIX/ledger-durations.tsv" "$L"
st --last 1
[ "$rc" = 0 ] || fail "durations: exit $rc: $err"
cell() { awk -v n="$1" '$1 == n { print $3 }' <<<"$out"; }
for pair in d0=0s d59=59s d60=1m00s d3599=59m59s d3600=1h00m d3659=1h00m d93780=26h03m; do
  got=$(cell "${pair%%=*}")
  [ "$got" = "${pair#*=}" ] || fail "duration text of ${pair%%=*}: got '$got', wanted '${pair#*=}'; $out"
done
[ "$(awk '$1 == "total" { print $2 }' <<<"$out")" = 29h05m ] || fail "the total of 104757 s is not 29h05m: $out"
# a zero that is known is shown as 0s, not as unknown
[ "$(cell not-reported)" = 0s ] && [ "$(cell take)" = 0s ] || fail "known zero stretches are not 0s: $out"
if grep -q unknown <<<"$out"; then fail "a take with every stage known shows unknown: $out"; fi

# an unusable NIGHTMILL_CLOCK_FILE gives one note and the system clock (a running take runs to "now")
echo $((T0 + 13700)) > "$CLOCK"
cp "$FIX/ledger.tsv" "$L"
note='ledger: NIGHTMILL_CLOCK_FILE is not usable; using the system clock'
for bad in missing empty text long; do
  case "$bad" in
    missing) rm -f "$tmp/badclock" ;;
    empty) : > "$tmp/badclock" ;;
    text) echo "soon" > "$tmp/badclock" ;;
    long) echo 1234567890123 > "$tmp/badclock" ;;
  esac
  set +e; out=$(NIGHTMILL_CLOCK_FILE="$tmp/badclock" bash "$ST" --last 1 2>"$tmp/err.txt"); rc=$?; set -e
  err=$(cat "$tmp/err.txt")
  [ "$rc" = 0 ] || fail "unusable clock ($bad): exit $rc: $err"
  grep -qxF "$note" <<<"$err" || fail "unusable clock ($bad): no note on standard error: [$err]"
  grep -qF -- '-  feat/d  slot 2  running' <<<"$out" || fail "unusable clock ($bad): the running take is not shown: $out"
  # with the system clock the running take of 2026-11-07T11:37:00Z has run for a different time than with the fixture
  if grep -qE '^  implement +1 +10m00s ' <<<"$out"; then fail "unusable clock ($bad): the fixture clock was used: $out"; fi
done
# a usable clock prints no note
st --last 1
if grep -qF "$note" <<<"$err"; then fail "a usable clock gave the note: $err"; fi

echo "SMOKE OK"
