#!/usr/bin/env bash
# tests/test-drive-leftover.sh - regression for #374: tests/smoke-drive.sh failed in Git Bash on Windows at the case
# "left behind": "FAIL: left behind: the step's background process is still alive". The step starts a background
# process (sleep 300) and ends; scripts/drive.sh finds what is left of the step's process group with
# `ps -A -o pid= -o pgid=` (alive_in) and ends it with kill -TERM/-KILL on the group. The ps of Git Bash (MSYS) takes
# neither -A nor -o ("ps: unknown option -- A"), so the driver finds nothing, ends nothing, and the process lives on:
# a real leftover, not a wrong answer of the test's own kill -0.
# This file runs the real case "left behind" of tests/smoke-drive.sh: the fake gh, the fake claude and the helpers are
# read from that file (from "# --- the fake gh ---" up to the FIX line, so a change there is run here) and the case is
# run against the real scripts/drive.sh, without the minutes of the cases around it. The case passes where ps takes
# those options (Linux, macOS), as before. tests/lint.sh calls this file.
#   tests/test-drive-leftover.sh [<root>]   # root: the checkout to read (default: this one)
# shellcheck disable=SC2034  # fx is read by the helpers loaded with eval below
set -uo pipefail
here=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
D="$here/scripts/drive.sh"
smoke="$here/tests/smoke-drive.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-drive-leftover.XXXXXX")
bgpid=""
cleanup() {
  [ -z "$bgpid" ] || kill "$bgpid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$D" ] || fail "scripts/drive.sh does not exist"
[ -f "$smoke" ] || fail "tests/smoke-drive.sh does not exist"

export TMPDIR="$tmp/runs"
mkdir -p "$TMPDIR" "$tmp/bin"
fx="$here/tests/fixtures/drive"

# the setup of the smoke test, as it stands there
setup=$(awk '/^# --- the fake gh ---/ { on = 1 } on { print } on && /^FIX=/ { exit }' "$smoke")
case "$setup" in *"new_case()"*"drive()"*"FIX="*) ;; *) fail "tests/smoke-drive.sh no longer holds the setup (fake gh, fake claude, new_case, drive) this test reads" ;; esac
eval "$setup"

echo "== a step's background process is gone when the driver ends the step (bug #374)"
new_case; board board-loop.tsv; script "bg status:11:Review pr:101:OPEN:11"; drive
want_code 0 "left behind"
[ -s "$BGPID" ] || fail "left behind: the step never started its background process"
bgpid=$(cat "$BGPID")
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$bgpid" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$bgpid" 2>/dev/null; then fail "left behind: the step's background process $bgpid is still alive after the driver ended"; fi
bgpid=""
has "$COMMENT" "Processes: 1 left behind by a step were ended; none left running." "left behind"
audit "left behind"
echo "ok"
