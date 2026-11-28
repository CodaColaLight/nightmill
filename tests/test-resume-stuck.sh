#!/usr/bin/env bash
# Tests for #112 (iteration 44): /spec N and /next N finish a story that an earlier run left at Spec,
# Spec review, In progress or Review. Only the contracts are checked: the status names in the workflow skill, the
# branch patterns, commands and the parsed lines (`Spec for #<issue>.`, the `resumed` step row) in /spec and /next,
# `/spec N` and `/next N` in the status skill and the README rows of both commands; the sentences of the resume are the
# reviewers' (iteration 76). Text is joined (newlines to spaces, runs of spaces made one) before it is searched.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fail=0

flat() { tr '\n' ' ' < "$1" | sed -E 's/ +/ /g'; }

# need <file> <text>...: each text must be in the joined file
need() {
  local f=$1 text flatf; shift
  flatf=$(flat "$f")
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) ;;
      *) echo "FAIL: ${f} does not say the resume item: ${text}"; fail=1 ;;
    esac
  done
}

echo "== a stuck story is continued"
need skills/workflow/SKILL.md 'Spec' 'Spec review' 'In progress' 'Review'

need skills/spec/SKILL.md '<git.specPrefix><N>-*' 'Spec for #<issue>.'

need skills/next/SKILL.md \
  '<git.featurePrefix><N>-<slug>' "closingIssuesReferences" "--status --porcelain" \
  "slot --abandon <s>" '| `session` | `resumed` |'

need skills/status/SKILL.md '/spec N' '/next N'

for row in '/nightmill:spec [N]' '/nightmill:next [N]'; do
  grep -F -- "| \`${row}\`" README.md >/dev/null || { echo "FAIL: README.md has no row ${row}"; fail=1; }
done

[ "${fail}" = 0 ] && echo "RESUME STUCK OK" || { echo "RESUME STUCK FAILED"; exit 1; }
