#!/usr/bin/env bash
# tests/test-ci-job-name-rule.sh - bug #294: the lint rule that fails a job name that begins with a required check name
# (tests/lint.sh, section "the check runs every smoke script"; iteration 55, decision 5) is worded the same everywhere.
# The spec docs/specs/iteration-55-ci-parallel-powershell.md says "begins with" for this rule, never "contains": a name
# that merely contains a required name is allowed (the rule would not fire on it), so "contains" misstates the rule.
# The rule itself is pinned by the lint_break case "cibegins" in tests/smoke-check.sh and tests/smoke-check.ps1.
# Not a smoke script: run it with `bash tests/test-ci-job-name-rule.sh`. Needs bash, grep and tr.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bad=0
fail() { echo "FAIL: $*"; bad=1; }

spec="$here/docs/specs/iteration-55-ci-parallel-powershell.md"
if [ ! -f "$spec" ]; then
  fail "docs/specs/iteration-55-ci-parallel-powershell.md does not exist"
else
  # one line of text, so a phrase broken across two lines of the spec is still found
  flat=$(tr -d '\r' < "$spec" | tr '\n' ' ' | tr -s ' ')
  # grep gets the text with a here-string, not a pipe: under pipefail a pipe into grep -q can fail by SIGPIPE (#220)
  if grep -Eqi 'contains? (a|the|one of the) required (check )?name' <<<"$flat"; then
    fail "the iteration 55 spec says a job name 'contains' a required name; the rule is 'begins with' (bug #294)"
  fi
  grep -qF "begins with the required name" <<<"$flat" \
    || fail "the iteration 55 spec does not give the FAIL text 'begins with the required name' of the job-name rule"
fi

grep -qF "begins with the required name" "$here/tests/lint.sh" \
  || fail "tests/lint.sh has no rule that fails a job name that begins with a required name"

if [ "$bad" = 0 ]; then echo "OK: the job-name rule is worded 'begins with'"; fi
exit "$bad"
