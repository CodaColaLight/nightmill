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
mkdir -p "$shim"; : > "$lintlog"
cat > "$shim/bash" <<'SHIM'
#!@REAL@
case "${1:-}" in
  tests/lint.sh|*/tests/lint.sh) echo "lint.sh ${*:2}" >> "@LOG@" ;;
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
[ "$bad" = 0 ] || exit 1
echo "LINTCOPY OUTPUT OK"
