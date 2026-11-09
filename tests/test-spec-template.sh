#!/usr/bin/env bash
# tests/test-spec-template.sh - story #150 (iteration 40): specs are written from templates/spec.md and the lint
# checks the headings of every spec from iteration 40 on in iterations.specDir.
# (a) templates/spec.md has the title, the status line and the seven required headings once each, in order;
# (b) skills/spec/SKILL.md, agents/spec-reviewer.md and README.md point at the template;
# (c) the lint, run on throwaway copies of the repository, accepts a spec filled in from the template, rejects one
#     with a heading missing or out of order or inside a fence, and exempts specs below iteration 40.
# Needs bash, tar, awk and sed. Not a smoke script: run it with `bash tests/test-spec-template.sh`.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-spec-template.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
unset NIGHTMILL_CHECK_STEPS
bad=0
fail() { echo "FAIL: $*"; bad=1; }

req=('## Story trigger and manual check' '## Criteria and rules' '## Tests' '## Files touched' '## Risks' '## Size estimate' '## Not done')
tpl="$here/templates/spec.md"

echo "== the template has the required sections"
if [ ! -f "$tpl" ]; then
  fail "templates/spec.md does not exist"
else
  first=$(sed -n '1p' "$tpl")
  case "$first" in '# Iteration <N>:'*) ;; *) fail "templates/spec.md: the first line is not '# Iteration <N>: ...': $first" ;; esac
  if ! grep -Fxq 'Status: draft, awaiting approval (#<issue>)' "$tpl"; then
    fail "templates/spec.md lacks the line 'Status: draft, awaiting approval (#<issue>)'"
  fi
  prev=0
  for h in "${req[@]}"; do
    c=$(grep -Fxc -- "$h" "$tpl")
    if [ "$c" != 1 ]; then fail "templates/spec.md has the heading '$h' $c times, not once"; continue; fi
    ln=$(grep -Fxn -- "$h" "$tpl" | sed -n '1s/:.*//p')
    if [ "$ln" -le "$prev" ]; then fail "templates/spec.md: '$h' is out of order"; fi
    prev=$ln
  done
  # a section of the template whose guidance begins 'Optional.' is not required
  for h in '## Facts this rests on' '## Decisions' '## Left'; do
    ln=$(grep -Fxn -- "$h" "$tpl" | sed -n '1s/:.*//p')
    if [ -z "$ln" ]; then fail "templates/spec.md lacks the optional section '$h'"; continue; fi
    nxt=$(sed -n "$((ln + 2))p" "$tpl")
    case "$nxt" in '<!-- Optional.'*) ;; *) fail "templates/spec.md: the comment under '$h' does not begin 'Optional.'" ;; esac
  done
  if ! grep -Fq '| # | Acceptance criterion |' "$tpl"; then fail "templates/spec.md has no criteria table"; fi
  for w in S M L; do
    if ! grep -Fq "$w (" "$tpl"; then fail "templates/spec.md: the size estimate does not name the scale '$w'"; fi
  done
fi

echo "== the skill, the reviewer and the README point at the template"
joined() { tr '\n' ' ' <"$here/$1"; }
skill=$(joined skills/spec/SKILL.md)
agent=$(joined agents/spec-reviewer.md)
readme=$(joined README.md)
n=$(printf '%s' "$skill" | grep -o 'templates/spec.md' | wc -l | tr -d ' ')
if [ "$n" -lt 2 ]; then fail "skills/spec/SKILL.md names templates/spec.md $n times, not at least twice (writer and reviewer prompt)"; fi
case "$skill" in *'keep its headings, with their exact text and in their order'*) ;; *) fail "skills/spec/SKILL.md does not tell the writer to keep the template's headings in order" ;; esac
case "$skill" in *'as the model for the form'*) fail "skills/spec/SKILL.md still takes the latest spec as the model for the form" ;; esac
case "$agent" in *'templates/spec.md'*) ;; *) fail "agents/spec-reviewer.md does not name templates/spec.md" ;; esac
case "$agent" in *'in its order'*) ;; *) fail "agents/spec-reviewer.md does not check the template's headings 'in its order'" ;; esac
case "$readme" in *'templates/spec.md'*) ;; *) fail "README.md does not name templates/spec.md" ;; esac

echo "== the lint checks the headings of specs from iteration 40 on"
copy() { # copy <dir>
  mkdir -p "$1"
  ( cd "$here" && tar -cf - --exclude=.git . ) | ( cd "$1" && tar -xf - )
}
runlint() { # runlint <dir>: the lint's output, whatever its status
  ( cd "$1" && bash tests/lint.sh 2>&1 ) || true
}
if [ ! -f "$tpl" ]; then
  fail "no template to fill in, the lint cases are not run"
else
  # unchanged copy: the real specs (1 to 45) must pass, and the exempt count is printed
  d0="$tmp/base"; copy "$d0"
  out=$(runlint "$d0")
  case "$out" in *'== specs follow the template'*) ;; *) fail "the lint has no section '== specs follow the template'" ;; esac
  case "$out" in *'exempt: '*' specs below iteration 40 (written before the template)'*) ;; *) fail "the lint prints no 'exempt: <k> specs below iteration 40 (written before the template)' line" ;; esac
  case "$out" in *'FAIL: docs/specs/'*) fail "the lint fails a spec on main: $out" ;; esac

  mk() { # mk <name> <sed script or ''>: copy with docs/specs/iteration-99-case.md made from the template
    local d="$tmp/$1"; copy "$d"
    sed -e 's/<N>/99/' ${2:+-e "$2"} "$tpl" >"$d/docs/specs/iteration-99-case.md"
    printf '%s' "$d"
  }
  d=$(mk ok '')
  out=$(runlint "$d")
  case "$out" in *'FAIL: '*'iteration-99-case.md'*) fail "the lint rejects a spec filled in from the template: $out" ;; esac

  d=$(mk norisks '/^## Risks$/d')
  out=$(runlint "$d")
  case "$out" in *"missing heading '## Risks'"*) ;; *) fail "the lint accepts a spec without '## Risks': $out" ;; esac

  d=$(mk nostatus '/^Status: /d')
  out=$(runlint "$d")
  case "$out" in *"no 'Status: ' line"*) ;; *) fail "the lint accepts a spec without a Status line: $out" ;; esac

  d=$(mk badtitle '1s/.*/# Something else/')
  out=$(runlint "$d")
  case "$out" in *"the first heading is not '# Iteration"*) ;; *) fail "the lint accepts a spec whose first heading is not '# Iteration <N>:': $out" ;; esac

  d=$(mk twice '/^## Tests$/a\
\
## Tests')
  out=$(runlint "$d")
  case "$out" in *"heading '## Tests' appears 2 times"*) ;; *) fail "the lint accepts a spec with '## Tests' twice: $out" ;; esac

  d=$(mk swapped 's/^## Tests$/## @@A@@/; s/^## Files touched$/## Tests/; s/^## @@A@@$/## Files touched/')
  out=$(runlint "$d")
  case "$out" in *'comes before'*) ;; *) fail "the lint accepts a spec with '## Tests' and '## Files touched' exchanged: $out" ;; esac

  d=$(mk fenced '/^## Not done$/{i\
```
a\
```
}')
  out=$(runlint "$d")
  case "$out" in *"missing heading '## Not done'"*) ;; *) fail "the lint counts a heading inside a fence: $out" ;; esac

  # a spec below iteration 40 is exempt, whatever its headings
  d="$tmp/exempt"; copy "$d"
  printf '# Iteration 3: old\n\nStatus: delivered\n\n## Goal\n' >"$d/docs/specs/iteration-3-old.md"
  out=$(runlint "$d")
  case "$out" in *'FAIL: '*'iteration-3-old.md'*) fail "the lint checks a spec below iteration 40: $out" ;; esac

  # a file in the folder that does not match iteration-*.md is ignored
  d="$tmp/other"; copy "$d"
  printf 'notes\n' >"$d/docs/specs/notes.md"
  out=$(runlint "$d")
  case "$out" in *'FAIL: '*'notes.md'*) fail "the lint checks a file that is not iteration-*.md: $out" ;; esac
fi

[ "$bad" = 0 ] || exit 1
echo "SPEC TEMPLATE OK"
