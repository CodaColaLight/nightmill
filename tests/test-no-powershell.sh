#!/usr/bin/env bash
# tests/test-no-powershell.sh - no PowerShell script is left, and none is named (iteration 68, #365, decision record
# 0004 step 4). Called from tests/lint.sh.
#   tests/test-no-powershell.sh [<root>]   # root: the checkout to read (default: this one)
# Rule 1: the only PowerShell files are the three on the list below. Rule 2: no text file outside docs/ and
# CHANGELOG.md names another one. The cases at the end run both rules on scratch trees; they build every name of a
# PowerShell file from a variable, so this file names none.
# Exit 1 on any failure, else 0 with the line "OK: no PowerShell script is left or named". Needs bash, find, grep, sed.
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

ext=ps1
keep="tests/check.$ext tools/make-icon.$ext tools/make-social-preview.$ext"

# scan <root>: the FAIL lines of both rules on stdout
scan() {
  local r=$1 f p files
  while IFS= read -r f; do
    p=${f#"$r"/}
    case "$p" in
      "tests/check.$ext" | "tools/make-icon.$ext" | "tools/make-social-preview.$ext") continue ;;
    esac
    echo "FAIL: $p is a PowerShell file; only tests/check.$ext, tools/make-icon.$ext and tools/make-social-preview.$ext are left (decision record 0004)"
  done < <(find "$r" \( -name .git -o -path "$r/tmp" \) -prune -o -type f \
    \( -iname "*.$ext" -o -iname '*.psm1' -o -iname '*.psd1' \) -print | LC_ALL=C sort)
  # rule 2: one grep over every text file outside docs/, CHANGELOG.md and the three files of rule 1
  if [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null || true)" = "$(cd "$r" && pwd -P)" ]; then
    files=$(git -C "$r" ls-files -co --exclude-standard)
  else
    files=$(find "$r" \( -name .git -o -path "$r/tmp" \) -prune -o -type f ! -name '*.log' ! -name .DS_Store \
      ! -path "$r/.claude/settings.local.json" ! -path "$r/tests/forbidden-words.local.txt" -print | sed "s#^$r/##")
  fi
  files=$(printf '%s\n' "$files" | grep -v -e '^docs/' -e '^CHANGELOG\.md$' -e "^tests/check\\.$ext\$" \
    -e "^tools/make-icon\\.$ext\$" -e "^tools/make-social-preview\\.$ext\$" -e '^$' || true)
  [ -n "$files" ] || return 0
  (cd "$r" && printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -HInoE "[A-Za-z0-9_-]+\\.$ext" 2>/dev/null || true) |
    awk -F: -v ext="$ext" '{
      path = $1; n = $2; name = $3
      for (i = 4; i <= NF; i++) name = name ":" $i
      if (name == "check." ext || name == "make-icon." ext || name == "make-social-preview." ext) next
      print "FAIL: " path ":" n " names " name ", which is gone (#365)"
    }'
}

bad=0
out=$(scan "$root")
if [ -n "$out" ]; then printf '%s\n' "$out" >&2; bad=1; fi

# The cases, on scratch trees.
work=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-nops.XXXXXX")
trap 'rm -rf "$work"' EXIT
n=0
mktree() { # sets $d: a tree with the three files that stay
  n=$((n + 1)); d="$work/c$n"
  mkdir -p "$d/tests" "$d/tools" "$d/scripts" "$d/docs"
  : > "$d/tests/check.$ext"; : > "$d/tools/make-icon.$ext"; : > "$d/tools/make-social-preview.$ext"
}
expect() { # <case> <text, empty for no output>
  local got
  got=$(scan "$d" 2>&1) || true
  if [ -z "$2" ]; then
    [ -z "$got" ] || { echo "FAIL: no-powershell case $1: expected no output, got: $got" >&2; bad=1; }
  else
    case "$got" in
      *"$2"*) ;;
      *) echo "FAIL: no-powershell case $1: expected '$2', got: $got" >&2; bad=1 ;;
    esac
  fi
}
mktree; expect three ''
mktree; : > "$d/scripts/a.$ext"; expect 'rule 1 file' "FAIL: scripts/a.$ext is a PowerShell file; only tests/check.$ext, tools/make-icon.$ext and tools/make-social-preview.$ext are left (decision record 0004)"
mktree; mkdir -p "$d/tools/x" "$d/scripts/lib"; : > "$d/tools/x/Y.PS1"; : > "$d/scripts/lib/m.psm1"
expect 'rule 1 case' "FAIL: tools/x/Y.PS1 is a PowerShell file"
expect 'rule 1 psm1' "FAIL: scripts/lib/m.psm1 is a PowerShell file"
mktree; printf 'a\nrun slot.%s now\n' "$ext" > "$d/README.md"; expect 'rule 2 script' "FAIL: README.md:2 names slot.$ext, which is gone (#365)"
mktree; printf 'run tests/smoke-a.%s\n' "$ext" > "$d/README.md"; expect 'rule 2 test' "FAIL: README.md:1 names smoke-a.$ext, which is gone (#365)"
mktree; printf 'tests/check.%s tools/make-icon.%s *.%s tools/make-social-preview.%s\n' "$ext" "$ext" "$ext" "$ext" > "$d/README.md"; expect 'rule 2 kept names' ''
mktree; printf 'slot.%s\n' "$ext" > "$d/docs/a.md"; printf 'slot.%s\n' "$ext" > "$d/CHANGELOG.md"; expect 'rule 2 docs and changelog' ''
mktree; mkdir -p "$d/.claude" "$d/tmp"; printf 'slot.%s\n' "$ext" > "$d/.claude/settings.local.json"
printf 'slot.%s\n' "$ext" > "$d/tmp/x.txt"; printf 'slot.%s\n' "$ext" > "$d/a.log"; expect 'rule 2 ignored files' ''

if [ "$bad" -ne 0 ]; then exit 1; fi
echo "OK: no PowerShell script is left or named"
