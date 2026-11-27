#!/usr/bin/env bash
# tests/test-lint-agreement-cost.sh - regression test for #270: since iteration 51 the PowerShell CI job took 25 to 32
# minutes (11 before; limit 38). The files that ran the lint on a copy of the repository slowed down: the PowerShell
# smoke test of the check 2m53s -> 19m49s, those of the release and the validator about 5m -> 11m, the PowerShell lint
# copy test 3m -> 4m. The lint section "== the README lists every smoke file" (until iteration 68 "== the lists and
# the shell twins agree") is the cause the report points at. It runs
# tests/test-lint-agreement.sh once and tests/test-lint-agreement-cases.sh, which runs that same file again for every
# case (about 17 times); each run of the rule file also runs its own self-test (11 more runs of the rules), and the
# rules are the same ones. Starting a process is what costs time under Git Bash on Windows, so the test counts how
# often the section starts the rule file.
# Bound: at most 3 runs of tests/test-lint-agreement.sh for the whole section. Today it is 18; a run of the rule
# file costs 0.3 s here, the cases file 3.9 s (13 times as much, nearly all of the section). 3 is far from 18.
#   tests/test-lint-agreement-cost.sh [<root>]
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
max=3
lint="$root/tests/lint.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-agree-cost.XXXXXX")
trap 'rm -rf "$work"' EXIT
fail=0

[ -f "$lint" ] || { echo "FAIL: $lint is missing"; exit 1; }

# the lint section, as written in tests/lint.sh: from its header to the next header
section=$(awk '
  index($0, "echo \"== the README lists every smoke file\"") == 1 { s = 1; next }
  s && index($0, "echo \"== ") == 1 { exit }
  s { print }' "$lint")
if [ -z "$section" ]; then
  echo "FAIL: tests/lint.sh has no section '== the README lists every smoke file'"; exit 1
fi

# a scratch checkout: the cases file as it is, the rule file replaced by one that counts its runs
mkdir -p "$work/tests"
for f in "$root"/tests/test-lint-agreement*.sh; do
  [ -f "$f" ] && cp "$f" "$work/tests/"
done
cat > "$work/tests/test-lint-agreement.sh" <<STUB
#!/usr/bin/env bash
echo run >> "$work/runs"
echo "OK: the README lists every smoke file"
STUB
: > "$work/runs"

( cd "$work" && fail=0 && eval "$section" ) > "$work/out" 2>&1
runs=$(wc -l < "$work/runs" | tr -d ' ')

if [ "$runs" -gt "$max" ]; then
  echo "FAIL: the lint section 'the README lists every smoke file' starts tests/test-lint-agreement.sh $runs times; at most $max (each start is a slow process tree under Git Bash on Windows, #270)"
  fail=1
fi
[ "$fail" = 0 ] && echo "ok: the agreement section starts the rule file $runs times" || exit 1
