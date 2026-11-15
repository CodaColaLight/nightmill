#!/usr/bin/env bash
# tests/test-ci-job-times.sh - the final CI job's job-times step is pinned (bug #295; iteration 55, decision 7): the rules
# of tests/test-ci-parts.sh fail when the job smoke-powershell has no step that runs tests/ci-jobs-summary.sh with
# `if: always()` and `continue-on-error: true`. Each case is a scratch copy of .github/workflows/ci.yml (the real file
# is never touched) changed once: the step removed, its `if: always()` removed, its `continue-on-error: true` removed,
# its call of tests/ci-jobs-summary.sh removed; the rules (NIGHTMILL_CI_PARTS_RULES_ONLY=1, no cases of their own) must
# print a FAIL line that names the job times step, and must stay quiet on the real file.
#   tests/test-ci-job-times.sh
# Exit 1 on any failure, else 0 with the line "OK: the job times step is pinned". Needs bash, awk and sed.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-ci-job-times.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

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

# the real file: the step is there, with both lines, and the rules pass
real="$here/.github/workflows/ci.yml"
step=$(tr -d '\r' < "$real" | awk '/^      - name: Job times$/ { on = 1; print; next } on && (/^      - / || /^  [A-Za-z]/ || /^[^[:space:]]/ || $0 == "") { on = 0 } on')
case "$step" in *"        if: always()"*) ;; *) bad "setup: the real ci.yml has no 'if: always()' in its Job times step" ;; esac
case "$step" in *"        continue-on-error: true"*) ;; *) bad "setup: the real ci.yml has no 'continue-on-error: true' in its Job times step" ;; esac
case "$step" in *"tests/ci-jobs-summary.sh"*) ;; *) bad "setup: the real ci.yml's Job times step does not call tests/ci-jobs-summary.sh" ;; esac
[ "$fail" = 0 ] || exit 1

d=$(mkroot real)
run_rules "$d"
[ "$rc" = 0 ] || bad "the real ci.yml: the rules fail (exit $rc): $out"

# case_job_times <name> <awk program>: change the copy once, then the rules must fail and name the job times step
case_job_times() {
  local name=$1 prog=$2 d f
  d=$(mkroot "$name"); f="$d/.github/workflows/ci.yml"
  awk "$prog" "$f" > "$f.new" && mv "$f.new" "$f"
  if cmp -s "$f" "$here/.github/workflows/ci.yml"; then bad "case $name: the mutation changed nothing"; return; fi
  run_rules "$d"
  if [ "$rc" = 0 ]; then bad "case $name: the rules pass although the Job times step is broken"; return; fi
  case "$out" in
    *FAIL:*) ;;
    *) bad "case $name: exit $rc but no FAIL line: $out"; return ;;
  esac
  case "$(printf '%s' "$out" | tr 'A-Z' 'a-z')" in
    *"job times"*|*"job-times"*|*"ci-jobs-summary"*) ;;
    *) bad "case $name: no FAIL line names the job times step (Job times or ci-jobs-summary): $out" ;;
  esac
}

# the whole step removed: from its '- name: Job times' line to the next step, job or blank line
case_job_times nostep '
  /^      - name: Job times[[:space:]]*$/ { skip = 1; next }
  skip && (/^      - / || /^  [A-Za-z]/ || /^[^[:space:]]/ || /^[[:space:]]*$/) { skip = 0 }
  skip { next }
  { print }'

# 'if: always()' removed from the step only (the final job keeps its own)
case_job_times noalways '
  /^      - name: Job times[[:space:]]*$/ { inst = 1; print; next }
  inst && (/^      - / || /^  [A-Za-z]/ || /^[^[:space:]]/ || /^[[:space:]]*$/) { inst = 0 }
  inst && /^        if: always\(\)[[:space:]]*$/ { next }
  { print }'

# 'continue-on-error: true' removed from the step only
case_job_times nocontinue '
  /^      - name: Job times[[:space:]]*$/ { inst = 1; print; next }
  inst && (/^      - / || /^  [A-Za-z]/ || /^[^[:space:]]/ || /^[[:space:]]*$/) { inst = 0 }
  inst && /^        continue-on-error: true[[:space:]]*$/ { next }
  { print }'

# the step stays, but no longer runs tests/ci-jobs-summary.sh
case_job_times nocall '
  /^      - name: Job times[[:space:]]*$/ { inst = 1; print; next }
  inst && (/^      - / || /^  [A-Za-z]/ || /^[^[:space:]]/ || /^[[:space:]]*$/) { inst = 0 }
  inst { gsub(/tests\/ci-jobs-summary\.sh/, "tests/other-summary.sh") }
  { print }'

[ "$fail" = 0 ] || exit 1
echo "OK: the job times step is pinned"
