#!/usr/bin/env bash
# tests/test-ci-summary.sh - the job table of a CI run (iteration 55, decision 7): tests/ci-jobs-summary.sh on a fixture
# of the jobs API's lines (tests/fixtures/ci-summary/jobs.tsv: job and step lines, a skipped step, a line of four
# fields, a line of another kind, a bad stamp, a job still running) against tests/fixtures/ci-summary/jobs.md byte for
# byte; then the same input without --now, and the usage errors. Needs bash, awk and sed, no jq, no network.
#   tests/test-ci-summary.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$here/tests/ci-jobs-summary.sh"
fx="$here/tests/fixtures/ci-summary"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-ci-summary.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

[ -f "$tool" ] || { bad "tests/ci-jobs-summary.sh does not exist"; exit 1; }
[ -f "$fx/jobs.tsv" ] && [ -f "$fx/jobs.md" ] || { bad "the fixtures tests/fixtures/ci-summary/jobs.tsv and jobs.md are missing"; exit 1; }

run() { # run <args...>: out (a file), rc; the fixture on standard input
  bash "$tool" "$@" < "$fx/jobs.tsv" > "$tmp/out.txt" 2> "$tmp/err.txt"; rc=$?
}

# with --now: byte for byte
run --parts 'PowerShell smoke part ' --now 2026-11-11T10:20:00Z
[ "$rc" = 0 ] || bad "with --now: exit $rc: $(cat "$tmp/err.txt")"
if ! cmp -s "$tmp/out.txt" "$fx/jobs.md"; then
  bad "with --now: the output differs from tests/fixtures/ci-summary/jobs.md: $(diff "$fx/jobs.md" "$tmp/out.txt" | head -n 20)"
fi

# without --now: the running job says 'running', its running step is left out, nothing is marked (running)
run --parts 'PowerShell smoke part '
[ "$rc" = 0 ] || bad "without --now: exit $rc: $(cat "$tmp/err.txt")"
grep -qxF '| PowerShell scripts smoke tests | in_progress | running |' "$tmp/out.txt" || bad "without --now: the final job's row does not say 'running'"
if grep -qF '(running)' "$tmp/out.txt"; then bad "without --now: a (running) mark is printed"; fi
if grep -qF '| Job times |' "$tmp/out.txt"; then bad "without --now: the running step 'Job times' is not left out"; fi
grep -qxF '| Every part succeeded | 1s |' "$tmp/out.txt" || bad "without --now: the finished steps of the final job are missing"
grep -qxF 'PowerShell scripts smoke tests: 9m20s from the start of the first part to the end of the last (4 parts).' "$tmp/out.txt" || bad "without --now: the chain line is wrong"
n=$(grep -c '^#### Slowest steps: ' "$tmp/out.txt")
[ "$n" = 8 ] || bad "without --now: $n step sections, wanted 8 (one per job)"
if grep -qE 'Post Run actions/checkout|not-a-time|four' "$tmp/out.txt"; then bad "without --now: a skipped step or a bad line is printed"; fi
# at most five rows per section
rows=$(awk '/^#### Slowest steps:/ { n = 0; inx = 1; next } inx && /^\| / && !/^\| Step \|/ { n++; if (n > 5) print "more than five"; }' "$tmp/out.txt")
[ -z "$rows" ] || bad "a section has more than five rows"

# no part: the chain line is left out
printf 'job\tsolo\tsuccess\t2026-11-11T10:00:00Z\t2026-11-11T10:00:10Z\n' | bash "$tool" --parts 'PowerShell smoke part ' > "$tmp/solo.txt" 2>/dev/null
rc=$?
[ "$rc" = 0 ] || bad "no part: exit $rc"
if grep -qF 'from the start of the first part' "$tmp/solo.txt"; then bad "no part: the chain line is printed"; fi
grep -qxF '| solo | success | 10s |' "$tmp/solo.txt" || bad "no part: the table row is wrong: $(cat "$tmp/solo.txt")"

# usage errors: exit 2 with something on standard error
usage_case() { # usage_case <args...>
  run "$@"
  [ "$rc" = 2 ] || bad "usage ($*): exit $rc, wanted 2"
  [ -s "$tmp/err.txt" ] || bad "usage ($*): nothing on standard error"
}
usage_case --now 2026-11-11T10:20:00Z
usage_case --parts 'PowerShell smoke part ' --now ''
usage_case --parts 'PowerShell smoke part ' --now yesterday
usage_case --parts 'PowerShell smoke part ' --bogus

[ "$fail" = 0 ] || exit 1
echo "OK: the job table"
