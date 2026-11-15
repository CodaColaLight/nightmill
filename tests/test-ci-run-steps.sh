#!/usr/bin/env bash
# tests/test-ci-run-steps.sh - rule 2 of tests/test-ci-parts.sh counts every run step of the part job (bug #296; iteration 55,
# #289): the job smoke-powershell-part may have exactly one run line (the tests/check.sh ... --only ${{ matrix.only }} call), so
# that no step runs outside the parts' lists, and a step written in the compact form `- run: ...` counts as a run line like
# one written `run: ...` after a `- name:` or `- shell:` line. Each case is a scratch copy of .github/workflows/ci.yml (the
# real file is never touched) with a second run step added to the part job in the compact form: after the check step, before
# the checkout step, and as a block (`- run: |`); the rules (NIGHTMILL_CI_PARTS_RULES_ONLY=1, no cases of their own) must
# print the FAIL line of rule 2 ("does not run tests/check.sh --only"), and must stay quiet on the real file.
#   tests/test-ci-run-steps.sh
# Exit 1 on any failure, else 0 with the line "OK: rule 2 counts the - run: steps". Needs bash, awk and sed.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-ci-run-steps.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
RULE2='does not run tests/check.sh --only'

[ -f "$here/tests/test-ci-parts.sh" ] || { bad "tests/test-ci-parts.sh does not exist"; exit 1; }
[ -f "$here/.github/workflows/ci.yml" ] || { bad ".github/workflows/ci.yml does not exist"; exit 1; }
[ -f "$here/tests/check.sh" ] || { bad "tests/check.sh does not exist"; exit 1; }

mkroot() { # mkroot <name>: a scratch root with a copy of tests/check.sh and of the workflow
  local d="$tmp/$1"
  mkdir -p "$d/tests" "$d/.github/workflows"
  cp "$here/tests/check.sh" "$d/tests/check.sh"
  cp "$here/.github/workflows/ci.yml" "$d/.github/workflows/ci.yml"
  echo "$d"
}

# run_rules <root>: out (the rules' output), rc
run_rules() {
  out=$(NIGHTMILL_CI_PARTS_RULES_ONLY=1 bash "$here/tests/test-ci-parts.sh" "$1" 2>&1); rc=$?
}

# the real file: the part job has its one run line, and the rules pass
real="$here/.github/workflows/ci.yml"
n=$(tr -d '\r' < "$real" | awk '/^  [A-Za-z]/ { job = $1 } job == "smoke-powershell-part:" && /^ *(- )?run:/ { n++ } END { print n + 0 }')
[ "$n" = 1 ] || bad "setup: the real ci.yml has $n run lines in the job smoke-powershell-part, not 1"
[ "$fail" = 0 ] || exit 1

d=$(mkroot real)
run_rules "$d"
[ "$rc" = 0 ] || bad "the real ci.yml: the rules fail (exit $rc): $out"

# case_run_step <name> <awk program>: change the copy once, then the rules must fail with the FAIL line of rule 2
case_run_step() {
  local name=$1 prog=$2 d f
  d=$(mkroot "$name"); f="$d/.github/workflows/ci.yml"
  awk "$prog" "$f" > "$f.new" && mv "$f.new" "$f"
  if cmp -s "$f" "$here/.github/workflows/ci.yml"; then bad "case $name: the mutation changed nothing"; return; fi
  run_rules "$d"
  if [ "$rc" = 0 ]; then bad "case $name: the rules pass although the part job has a second run step"; return; fi
  case "$out" in
    *"FAIL:"*"$RULE2"*) ;;
    *) bad "case $name: exit $rc but no rule 2 FAIL line ('$RULE2'): $out" ;;
  esac
}

# a `- run: echo x` step after the check step (the case of the bug report)
case_run_step after '
  { print }
  /^  [A-Za-z]/ { job = $1 }
  job == "smoke-powershell-part:" && /^        run: bash tests\/check\.sh --powershell powershell/ { print "      - run: echo x" }'

# a `- run: echo x` step before the checkout step of the part job
case_run_step before '
  /^  [A-Za-z]/ { job = $1 }
  job == "smoke-powershell-part:" && /^      - uses: actions\/checkout/ { print "      - run: echo x" }
  { print }'

# a `- run: |` step with a block, after the check step
case_run_step block '
  { print }
  /^  [A-Za-z]/ { job = $1 }
  job == "smoke-powershell-part:" && /^        run: bash tests\/check\.sh --powershell powershell/ { print "      - run: |"; print "          echo x" }'

[ "$fail" = 0 ] || exit 1
echo "OK: rule 2 counts the - run: steps"
