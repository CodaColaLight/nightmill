#!/usr/bin/env bash
# tests/test-lint-agreement-cases.sh [<root>] - the cases of iteration 51 (#157): runs
# tests/test-lint-agreement.sh against scratch trees, one broken rule each, and against this checkout. The rule file
# is sourced once and its check runs in this shell; one case also starts it as a process, for its exit code (bug #270:
# a start per case made the PowerShell CI job slow).
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
rule="$root/tests/test-lint-agreement.sh"
# shellcheck source=tests/test-lint-agreement.sh
. "$rule"
work=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-agree-cases.XXXXXX")
trap 'rm -rf "$work"' EXIT
bad=0
n=0

mkbase() { # <dir>
  mkdir -p "$1/tests" "$1/scripts"
  : > "$1/tests/smoke-a.sh"; : > "$1/tests/smoke-a.ps1"; : > "$1/tests/smoke-json.sh"
  : > "$1/scripts/a.sh"; : > "$1/scripts/a.ps1"
  {
    echo "# readme"
    echo "bash tests/smoke-a.sh   # a"
    echo "bash tests/smoke-json.sh"
    echo "powershell -ExecutionPolicy Bypass -File tests/smoke-a.ps1"
  } > "$1/README.md"
}

out=""; rc=0
run() { # <dir>: sets out (stdout+stderr) and rc, from the rule file's check in this shell
  rc=0
  out=$(check "$1" 2>&1) || rc=$?
}
runfile() { # <dir>: the same, from a start of the rule file (its exit code and its self-test)
  rc=0
  out=$(bash "$rule" "$1" 2>&1) || rc=$?
}

expect() { # <case> <text>: exit 1 and the text in the output
  case "$out" in
    *"FAIL: $2"*) [ "$rc" -eq 1 ] || { echo "FAIL: $1: exit $rc, expected 1" >&2; bad=1; } ;;
    *) echo "FAIL: $1: expected FAIL: $2, got: $out" >&2; bad=1 ;;
  esac
}

newcase() { n=$((n + 1)); d="$work/c$n"; mkbase "$d"; }

# clean
newcase; run "$d"
[ "$rc" -eq 0 ] || { echo "FAIL: clean: exit $rc, got: $out" >&2; bad=1; }
case "$out" in *"OK: lists and twins agree"*) ;; *) echo "FAIL: clean: no OK line, got: $out" >&2; bad=1 ;; esac
case "$out" in *"FAIL:"*) echo "FAIL: clean: unexpected FAIL, got: $out" >&2; bad=1 ;; esac

# clean with carriage returns in the README
newcase; sed 's/$/\r/' "$d/README.md" > "$d/R" && mv "$d/R" "$d/README.md"; run "$d"
[ "$rc" -eq 0 ] || { echo "FAIL: crlf readme: exit $rc, got: $out" >&2; bad=1; }

# unlisted
newcase; grep -v 'smoke-a.sh' "$d/README.md" > "$d/R" && mv "$d/R" "$d/README.md"; run "$d"
expect unlisted "README.md does not list tests/smoke-a.sh"

# twice
newcase; echo "powershell -ExecutionPolicy Bypass -File tests/smoke-a.ps1" >> "$d/README.md"; run "$d"
expect twice "README.md lists tests/smoke-a.ps1 more than once"

# missing file
newcase; echo "bash tests/smoke-nope.sh" >> "$d/README.md"; run "$d"
expect missing "README.md lists tests/smoke-nope.sh, which does not exist"

# wrong shell
newcase; echo "bash tests/smoke-a.ps1" >> "$d/README.md"; run "$d"
expect shell "README.md runs tests/smoke-a.ps1 in the wrong shell"

# malformed
newcase; echo "bash tests/smoke-a.sh now" >> "$d/README.md"; run "$d"
expect malformed "README.md: malformed smoke line"

# a mention inside a sentence is not a list line
newcase; echo "Run bash tests/smoke-nope.sh to try it." >> "$d/README.md"; run "$d"
[ "$rc" -eq 0 ] || { echo "FAIL: sentence mention: exit $rc, got: $out" >&2; bad=1; }

# no twin
newcase; : > "$d/tests/smoke-b.sh"; echo "bash tests/smoke-b.sh" >> "$d/README.md"; run "$d"
expect "no twin" "tests/smoke-b.sh has no PowerShell twin tests/smoke-b.ps1"

# exception gone
newcase; rm "$d/tests/smoke-json.sh"; grep -v 'smoke-json' "$d/README.md" > "$d/R" && mv "$d/R" "$d/README.md"; run "$d"
expect "exception gone" "the twin exceptions name tests/smoke-json.sh, which does not exist"

# exception twinned
newcase; : > "$d/tests/smoke-json.ps1"
echo "powershell -ExecutionPolicy Bypass -File tests/smoke-json.ps1" >> "$d/README.md"; run "$d"
expect "exception twinned" "the twin exceptions name tests/smoke-json.sh, which has a PowerShell twin"

# script without a twin
newcase; : > "$d/scripts/b.sh"; run "$d"
expect script "scripts/b.sh has no PowerShell twin scripts/b.ps1"

# scripts/lib is not read
newcase; mkdir "$d/scripts/lib"; : > "$d/scripts/lib/json.sh"; run "$d"
[ "$rc" -eq 0 ] || { echo "FAIL: scripts/lib: exit $rc, got: $out" >&2; bad=1; }

# missing README
newcase; rm "$d/README.md"; run "$d"
expect "no readme" "README.md missing"

# one problem does not hide the next
newcase; : > "$d/scripts/b.sh"; echo "bash tests/smoke-nope.sh" >> "$d/README.md"; runfile "$d"
expect "all rules run" "scripts/b.sh has no PowerShell twin scripts/b.ps1"
expect "all rules run" "README.md lists tests/smoke-nope.sh, which does not exist"

# this checkout: a copy of its file names with the README lines for stages and guard removed
d="$work/real"; mkdir -p "$d/tests" "$d/scripts"
for f in "$root"/tests/smoke-*; do : > "$d/tests/$(basename "$f")"; done
for f in "$root"/scripts/*.sh "$root"/scripts/*.ps1; do : > "$d/scripts/$(basename "$f")"; done
grep -v -e 'tests/smoke-stages\.' -e 'tests/smoke-guard\.' "$root/README.md" \
  | grep -v -e '^bash tests/smoke-stages' -e '^bash tests/smoke-guard' > "$d/README.md" || true
run "$d"
for f in smoke-stages.sh smoke-stages.ps1 smoke-guard.sh smoke-guard.ps1; do
  expect "real tree without the four lines" "README.md does not list tests/$f"
done

# this checkout agrees
run "$root"
[ "$rc" -eq 0 ] || { echo "FAIL: this checkout: exit $rc, got: $out" >&2; bad=1; }
case "$out" in *"OK: lists and twins agree"*) ;; *) echo "FAIL: this checkout: no OK line, got: $out" >&2; bad=1 ;; esac

if [ "$bad" -ne 0 ]; then exit 1; fi
echo "OK: lint agreement cases"
