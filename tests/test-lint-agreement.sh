#!/usr/bin/env bash
# tests/test-lint-agreement.sh - the README lists every smoke file once (iterations 51 and 68, #157). Called from
# tests/lint.sh.
#   tests/test-lint-agreement.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

# agree <root>: the FAIL lines of the rules, on stderr; nothing when the tree agrees
agree() {
  local r=$1 f
  # the README's list lines against the smoke files (decision 2)
  if [ -f "$r/README.md" ]; then
    {
      for f in "$r"/tests/smoke-*; do [ -f "$f" ] && echo "${f##*/}"; done
      echo "--"
      cat "$r/README.md"
    } | awk '
      !inreadme && $0 == "--" { inreadme = 1; next }
      !inreadme { nfiles++; files[nfiles] = $0; have[$0] = 1; next }
      {
        sub(/\r$/, "")
        if (index($0, "bash tests/smoke-") != 1) next
        pre = "bash tests/"
        rest = substr($0, length(pre) + 1)
        match(rest, /^[A-Za-z0-9._-]+/)
        nm = substr(rest, 1, RLENGTH)
        tl = substr(rest, RLENGTH + 1)
        if (tl != "" && tl !~ /^[ \t]+#/) { print "FAIL: README.md: malformed smoke line: " $0; next }
        if (!(nm in have)) print "FAIL: README.md lists tests/" nm ", which does not exist"
        cnt[nm]++
      }
      END {
        for (i = 1; i <= nfiles; i++) {
          nm = files[i]
          if (nm !~ /\.sh$/) continue
          if (!(nm in cnt)) print "FAIL: README.md does not list tests/" nm
          else if (cnt[nm] > 1) print "FAIL: README.md lists tests/" nm " more than once"
        }
      }' >&2
  else
    echo "FAIL: README.md missing" >&2
  fi
}

# check <root>: the FAIL lines of agree on stderr and status 1, or the OK line on stdout
check() {
  local o
  o=$(agree "$1" 2>&1) || true
  if [ -n "$o" ]; then printf '%s\n' "$o" >&2; return 1; fi
  echo "OK: the README lists every smoke file"
}

# Sourced (tests/test-lint-agreement-cases.sh, bug #270): only the functions; every start of this file costs a
# process tree under Git Bash on Windows.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi

bad=0
check "$root" > /dev/null || bad=1

# The self-test (decision 6): the rules on trees built here, one change each.
work=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-agree.XXXXXX")
trap 'rm -rf "$work"' EXIT
n=0
mkbase() { # <dir>
  mkdir -p "$1/tests" "$1/scripts"
  : > "$1/tests/smoke-a.sh"; : > "$1/tests/smoke-json.sh"
  : > "$1/scripts/a.sh"
  printf '%s\n' 'bash tests/smoke-a.sh   # a' 'bash tests/smoke-json.sh' > "$1/README.md"
}
newcase() { n=$((n + 1)); d="$work/c$n"; mkbase "$d"; }
# selftest <case> <expected text, empty for no output>: runs agree on $d
selftest() {
  local got
  got=$(agree "$d" 2>&1) || true
  if [ -z "$2" ]; then
    [ -z "$got" ] || { echo "FAIL: the agreement self-test: $1: expected no output, got: $got" >&2; bad=1; }
  else
    case "$got" in
      *"$2"*) ;;
      *) echo "FAIL: the agreement self-test: $1: expected $2, got: $got" >&2; bad=1 ;;
    esac
  fi
}
drop() { grep -v -- "$1" "$d/README.md" > "$d/R" || true; mv "$d/R" "$d/README.md"; }

newcase; selftest clean ''
newcase; drop 'smoke-a\.sh'; selftest unlisted 'README.md does not list tests/smoke-a.sh'
newcase; echo 'bash tests/smoke-a.sh' >> "$d/README.md"
selftest twice 'README.md lists tests/smoke-a.sh more than once'
newcase; echo 'bash tests/smoke-nope.sh' >> "$d/README.md"
selftest missing 'README.md lists tests/smoke-nope.sh, which does not exist'
newcase; echo 'bash tests/smoke-a.sh now' >> "$d/README.md"; selftest malformed 'README.md: malformed smoke line'
newcase; : > "$d/tests/smoke-b.sh"; echo 'bash tests/smoke-b.sh' >> "$d/README.md"; : > "$d/scripts/b.sh"
selftest 'no twin needed' ''

if [ "$bad" -ne 0 ]; then exit 1; fi
echo "OK: the README lists every smoke file"
