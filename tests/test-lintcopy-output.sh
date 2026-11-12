#!/usr/bin/env bash
# tests/test-lintcopy-output.sh - regression test for #217: when the lint fails on the copy of the repository that a
# smoke test makes, the smoke test must print the lint's FAIL: lines, not only its own failure line.
# Method: copy the repository without .git, add a JSON file that does not parse (the lint then fails on any copy of
# that tree, the smoke tests' other steps do not read it), run the copy's smoke script and read its output.
# Not a smoke script: run it with `bash tests/test-lintcopy-output.sh`. Needs bash, git, tar and awk.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-lintcopy-output.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
unset UPDATE_STATUS_FIXTURES UPDATE_DASHBOARD_FIXTURES UPDATE_PANEL_FIXTURES NIGHTMILL_CHECK_STEPS
bad=0

check_script() { # check_script <smoke script name>
  local s=$1 d="$tmp/$1"
  mkdir -p "$d"
  ( cd "$here" && tar -cf - --exclude=.git . ) | ( cd "$d" && tar -xf - )
  printf '{ "broken": \n' > "$d/lintcopy-broken.json"
  local out rc
  set +e
  out=$(cd "$d" && bash "tests/$s" 2>&1); rc=$?
  set -e
  if [ "$rc" = 0 ]; then echo "FAIL: $s passed although the lint fails on its copy"; bad=1; return; fi
  case "$out" in *"the lint fails on an unchanged copy of the repository"*) ;; *)
    echo "FAIL: $s did not reach the lint-on-a-copy case, so this test proves nothing: $out"; bad=1; return ;; esac
  case "$out" in *"FAIL: ./lintcopy-broken.json does not parse"*) ;; *)
    echo "FAIL: $s hides the lint's FAIL lines when the lint fails on its copy: $out"; bad=1 ;; esac
}

check_script smoke-status.sh
check_script smoke-release.sh

# Regression test for #280: tests/test-spec-template.sh took 5m16s in CI because its lint cases ran the whole
# tests/lint.sh once per scenario (a filled-in template, three faults, the exempt specs, ...). The cost is counted, not
# timed: a shim named bash, first on the PATH, logs every call of tests/lint.sh with its arguments and passes every
# call, logged or not, to the real bash unchanged. A call without an argument is a full lint run; the test may make at
# most one for all its cases (a call with an argument, or another script, runs only a part). It must still end well.
real_bash=$(command -v bash)
shim="$tmp/shim"; lintlog="$tmp/lint-calls.log"
mkdir -p "$shim"; : > "$lintlog"; : > "$lintlog.out"
cat > "$shim/bash" <<'SHIM'
#!@REAL@
case "${1:-}" in
  tests/lint.sh|*/tests/lint.sh)
    echo "lint.sh ${*:2}" >> "@LOG@"
    if [ "$#" -gt 1 ]; then
      # a call with an argument: keep its stdout in a log too (the status is the real call's), stderr untouched
      "@REAL@" "$@" | tee -a "@LOG@.out"
      exit "${PIPESTATUS[0]}"
    fi ;;
esac
exec "@REAL@" "$@"
SHIM
sed -e "s|@REAL@|$real_bash|g" -e "s|@LOG@|$lintlog|g" "$shim/bash" > "$shim/bash.new" && mv "$shim/bash.new" "$shim/bash"
chmod +x "$shim/bash"
set +e
spec_out=$(cd "$here" && PATH="$shim:$PATH" bash tests/test-spec-template.sh 2>&1); spec_rc=$?
set -e
full_runs=$(awk '$0 == "lint.sh " { n++ } END { print n + 0 }' "$lintlog")
if [ "$spec_rc" != 0 ] || [ "$(printf '%s\n' "$spec_out" | tail -n 1)" != "SPEC TEMPLATE OK" ]; then
  echo "FAIL: tests/test-spec-template.sh did not end with SPEC TEMPLATE OK (exit $spec_rc), so its lint calls prove nothing: $(printf '%s\n' "$spec_out" | tail -n 5)"
  bad=1
fi
if [ "$full_runs" -gt 1 ]; then
  echo "FAIL: tests/test-spec-template.sh runs the whole lint $full_runs times; at most 1 for all its cases (#280)"
  bad=1
fi
# A call with an argument must run only the part it names: no section header but the spec one may appear in its output
# (a lint that ignores --specs and runs every section would print "== forbidden words" and the others).
part_runs=$(awk '$0 != "lint.sh " { n++ } END { print n + 0 }' "$lintlog")
other_sections=$(grep '^== ' "$lintlog.out" | grep -vxF '== specs follow the template' || true)
if [ "$part_runs" -lt 1 ]; then
  echo "FAIL: tests/test-spec-template.sh makes no call of tests/lint.sh with an argument, so the spec cases do not run the spec section alone (#280)"
  bad=1
elif ! grep -qxF '== specs follow the template' "$lintlog.out"; then
  echo "FAIL: no call of tests/lint.sh with an argument ran the spec section (#280)"
  bad=1
fi
if [ -n "$other_sections" ]; then
  echo "FAIL: a call of tests/lint.sh with an argument ran more than the spec section (#280): $(printf '%s\n' "$other_sections" | sort -u | head -n 3 | tr '\n' ';') ...)"
  bad=1
fi
# Regression test for #293: tests/smoke-check.sh ran the lint section "the check runs every smoke script" on about 11
# throwaway copies of the repository, and since iteration 55 that range holds the section "the PowerShell job runs in
# parts", which started tests/test-ci-parts.sh with its 18 cases (sed, awk and cp, slow under Git Bash) once per copy:
# smoke-check.ps1 took 10m22s and bounded part 3 of the PowerShell job. The cost is counted, not timed. A shim named cp,
# first on the PATH, logs every cp whose destination is the scratch root of a case of tests/test-ci-parts.sh (each case
# starts with one: cp tests/check.sh <tmp>/case-<name>/tests/check.sh) and passes every call to the real cp. The bound is
# one run of the cases: what one direct run of tests/test-ci-parts.sh logs. smoke-check.sh may log no more for all its
# lint copies, and it must still end well (its case "cips" needs the part rule's FAIL line on a copy).
# smoke-check.ps1 runs the same lint through Git Bash, so this bash count covers the shared cause.
real_cp=$(command -v cp)
cpshim="$tmp/cpshim"; cplog="$tmp/cp-calls.log"
mkdir -p "$cpshim"; : > "$cplog"
cat > "$cpshim/cp" <<SHIM
#!/bin/sh
for a in "\$@"; do
  case "\$a" in */nightmill-ci-parts.*/case-*/tests/check.sh) echo "\$a" >> "$cplog" ;; esac
done
exec "$real_cp" "\$@"
SHIM
chmod +x "$cpshim/cp"
set +e
parts_out=$(cd "$here" && PATH="$cpshim:$PATH" bash tests/test-ci-parts.sh "$here" 2>&1); parts_rc=$?
set -e
one_run=$(wc -l < "$cplog" | tr -d ' ')
if [ "$parts_rc" != 0 ] || [ "$one_run" -lt 5 ]; then
  echo "FAIL: one run of tests/test-ci-parts.sh (exit $parts_rc) logged $one_run case copies, so the count proves nothing: $(printf '%s\n' "$parts_out" | tail -n 3)"
  bad=1
fi
: > "$cplog"
set +e
check_out=$(cd "$here" && PATH="$cpshim:$PATH" bash tests/smoke-check.sh 2>&1); check_rc=$?
set -e
check_runs=$(wc -l < "$cplog" | tr -d ' ')
if [ "$check_rc" != 0 ]; then
  echo "FAIL: tests/smoke-check.sh did not pass (exit $check_rc), so its count proves nothing: $(printf '%s\n' "$check_out" | tail -n 5)"
  bad=1
fi
if [ "$one_run" -ge 5 ] && [ "$check_runs" -gt "$one_run" ]; then
  echo "FAIL: tests/smoke-check.sh runs the cases of tests/test-ci-parts.sh $check_runs case copies in all; at most $one_run (one run of the cases, #293)"
  bad=1
fi
# No PowerShell runs here, so the .ps1 half is a text check: a code line (not a comment) of tests/smoke-check.ps1 that
# writes run-section.sh must export NIGHTMILL_CI_PARTS_RULES_ONLY=1 before the lint section text ($secText) is appended,
# as smoke-check.sh does. Whitespace around the line is free.
ps1_ok=$(awk '
  /^[[:space:]]*#/ { next }
  /run-section\.sh/ && /export[[:space:]]+NIGHTMILL_CI_PARTS_RULES_ONLY=1/ {
    e = index($0, "NIGHTMILL_CI_PARTS_RULES_ONLY=1"); s = index($0, "$secText")
    if (s > e) ok = 1
  }
  END { print ok + 0 }' "$here/tests/smoke-check.ps1")
if [ "$ps1_ok" != 1 ]; then
  echo "FAIL: tests/smoke-check.ps1 does not export NIGHTMILL_CI_PARTS_RULES_ONLY=1 in the run-section.sh its Lint-In writes, before the lint section; the PowerShell job would run the cases of tests/test-ci-parts.sh on every lint copy (#293)"
  bad=1
fi
[ "$bad" = 0 ] || exit 1
echo "LINTCOPY OUTPUT OK"
