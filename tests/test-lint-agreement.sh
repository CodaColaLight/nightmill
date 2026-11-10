#!/usr/bin/env bash
# tests/test-lint-agreement.sh - the README lists every smoke file, every tests/smoke-*.sh has a .ps1 twin (except
# the listed ones) and every scripts/*.sh has a .ps1 twin (iteration 51, #157). Called from tests/lint.sh.
#   tests/test-lint-agreement.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

# The smoke scripts without a PowerShell twin: one file name per line, each with the reason after '#'.
twin_exceptions='
smoke-json.sh  # tests scripts/lib/json.awk and json.sh, the JSON reader of the bash scripts; the PowerShell scripts read JSON with ConvertFrom-Json (iteration 7)
'

# agree <root>: the FAIL lines of the rules, on stderr; nothing when the tree agrees
agree() {
  local r=$1 f b x
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
        sh = ""
        if (index($0, "bash tests/smoke-") == 1) { sh = "bash"; pre = "bash tests/" }
        else if (index($0, "powershell -ExecutionPolicy Bypass -File tests/smoke-") == 1) {
          sh = "ps"; pre = "powershell -ExecutionPolicy Bypass -File tests/"
        }
        if (sh == "") next
        rest = substr($0, length(pre) + 1)
        match(rest, /^[A-Za-z0-9._-]+/)
        nm = substr(rest, 1, RLENGTH)
        tl = substr(rest, RLENGTH + 1)
        if (tl != "" && tl !~ /^[ \t]+#/) { print "FAIL: README.md: malformed smoke line: " $0; next }
        if (!(nm in have)) print "FAIL: README.md lists tests/" nm ", which does not exist"
        if ((sh == "bash" && nm !~ /\.sh$/) || (sh == "ps" && nm !~ /\.ps1$/)) {
          print "FAIL: README.md runs tests/" nm " in the wrong shell"; next
        }
        cnt[nm]++
      }
      END {
        for (i = 1; i <= nfiles; i++) {
          nm = files[i]
          if (nm !~ /\.(sh|ps1)$/) continue
          if (!(nm in cnt)) print "FAIL: README.md does not list tests/" nm
          else if (cnt[nm] > 1) print "FAIL: README.md lists tests/" nm " more than once"
        }
      }' >&2
  else
    echo "FAIL: README.md missing" >&2
  fi
  # every smoke script has a PowerShell twin, and the exceptions stay exact (decision 3)
  for f in "$r"/tests/smoke-*.sh; do
    [ -f "$f" ] || continue
    b=${f##*/}
    if is_exception "$b"; then continue; fi
    [ -f "$r/tests/${b%.sh}.ps1" ] || echo "FAIL: tests/$b has no PowerShell twin tests/${b%.sh}.ps1" >&2
  done
  while IFS= read -r x; do
    x=${x%%#*}; x=$(printf '%s' "$x" | tr -d ' \t')
    [ -n "$x" ] || continue
    if [ ! -f "$r/tests/$x" ]; then
      echo "FAIL: the twin exceptions name tests/$x, which does not exist" >&2
    elif [ -f "$r/tests/${x%.sh}.ps1" ]; then
      echo "FAIL: the twin exceptions name tests/$x, which has a PowerShell twin" >&2
    fi
  done <<<"$twin_exceptions"
  # every script has a PowerShell twin; scripts/lib is not read (decision 4)
  for f in "$r"/scripts/*.sh; do
    [ -f "$f" ] || continue
    b=${f##*/}
    [ -f "$r/scripts/${b%.sh}.ps1" ] || echo "FAIL: scripts/$b has no PowerShell twin scripts/${b%.sh}.ps1" >&2
  done
}

# is_exception <file name>: whether the name is on the list of twin exceptions
is_exception() {
  local x
  while IFS= read -r x; do
    x=${x%%#*}; x=$(printf '%s' "$x" | tr -d ' \t')
    [ "$x" = "$1" ] && return 0
  done <<<"$twin_exceptions"
  return 1
}

bad=0
out=$(agree "$root" 2>&1) || true
if [ -n "$out" ]; then printf '%s\n' "$out" >&2; bad=1; fi

# The self-test (decision 6): the rules on trees built here, one change each.
work=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-agree.XXXXXX")
trap 'rm -rf "$work"' EXIT
n=0
mkbase() { # <dir>
  mkdir -p "$1/tests" "$1/scripts"
  : > "$1/tests/smoke-a.sh"; : > "$1/tests/smoke-a.ps1"; : > "$1/tests/smoke-json.sh"
  : > "$1/scripts/a.sh"; : > "$1/scripts/a.ps1"
  printf '%s\n' 'bash tests/smoke-a.sh   # a' 'bash tests/smoke-json.sh' \
    'powershell -ExecutionPolicy Bypass -File tests/smoke-a.ps1' > "$1/README.md"
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
newcase; echo 'powershell -ExecutionPolicy Bypass -File tests/smoke-a.ps1' >> "$d/README.md"
selftest twice 'README.md lists tests/smoke-a.ps1 more than once'
newcase; echo 'bash tests/smoke-nope.sh' >> "$d/README.md"
selftest missing 'README.md lists tests/smoke-nope.sh, which does not exist'
newcase; echo 'bash tests/smoke-a.ps1' >> "$d/README.md"
selftest shell 'README.md runs tests/smoke-a.ps1 in the wrong shell'
newcase; echo 'bash tests/smoke-a.sh now' >> "$d/README.md"; selftest malformed 'README.md: malformed smoke line'
newcase; : > "$d/tests/smoke-b.sh"; echo 'bash tests/smoke-b.sh' >> "$d/README.md"
selftest 'no twin' 'tests/smoke-b.sh has no PowerShell twin tests/smoke-b.ps1'
newcase; rm "$d/tests/smoke-json.sh"; drop 'smoke-json'
selftest 'exception gone' 'the twin exceptions name tests/smoke-json.sh, which does not exist'
newcase; : > "$d/tests/smoke-json.ps1"; echo 'powershell -ExecutionPolicy Bypass -File tests/smoke-json.ps1' >> "$d/README.md"
selftest 'exception twinned' 'the twin exceptions name tests/smoke-json.sh, which has a PowerShell twin'
newcase; : > "$d/scripts/b.sh"; selftest script 'scripts/b.sh has no PowerShell twin scripts/b.ps1'

if [ "$bad" -ne 0 ]; then exit 1; fi
echo "OK: lists and twins agree"
