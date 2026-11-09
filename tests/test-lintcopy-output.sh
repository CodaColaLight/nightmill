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
[ "$bad" = 0 ] || exit 1
echo "LINTCOPY OUTPUT OK"
