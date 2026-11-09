#!/usr/bin/env bash
# Tests for #112 (iteration 44): /spec N and /next N finish a story that an earlier run left at Spec,
# Spec review, In progress or Review. The skills are conversations, so this pins the wording the
# behaviour depends on. Text is joined (newlines to spaces, runs of spaces made one) before it is searched.
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
need skills/workflow/SKILL.md \
  "also takes Spec and Spec review" "also takes In progress and Review" "its own artefacts" \
  "the first unfinished step" "Resuming #<n> at <step>" "nothing to continue" "another run is working on it"
wf=$(flat skills/workflow/SKILL.md)
case "${wf}" in
  *"/spec only takes Ready stories"*) echo "FAIL: skills/workflow/SKILL.md still refuses every status but the skill's own"; fail=1 ;;
esac

need skills/spec/SKILL.md \
  '<git.specPrefix><N>-*' 'Spec for #<issue>.' \
  "The spec file exists from an earlier run that did not finish" \
  "every step of /spec is done; the spec waits for approval" \
  "resumed by /spec at the spec review" "never deletes a branch the run did not create" \
  "is not set again; it is read back" "an open one is reused" "only when no comment"

need skills/next/SKILL.md \
  '<git.featurePrefix><N>-<slug>' "closingIssuesReferences" "--status --porcelain" \
  "is running (last report" "slot --abandon <s>" '| `session` | `resumed` |' \
  "Resumed by /next at the code review" "resumed by /next at the code review" \
  "is not set again; it is read back" "an open one is reused" "has no entry for iteration N"

need skills/status/SKILL.md '/spec N' '/next N'
st=$(flat skills/status/SKILL.md)
case "${st}" in
  *'with nothing behind it is `/next`, `/spec` or the maintainer'*) echo "FAIL: skills/status/SKILL.md still sends a stuck item to /next, /spec or the maintainer without a number"; fail=1 ;;
esac

for row in '/nightmill:spec [N]' '/nightmill:next [N]'; do
  line=$(grep -F -- "| \`${row}\`" README.md | head -n 1)
  case "${line}" in
    *"continues a story"*) ;;
    *) echo "FAIL: README.md row ${row} does not say the resume item: continues a story"; fail=1 ;;
  esac
done

[ "${fail}" = 0 ] && echo "RESUME STUCK OK" || { echo "RESUME STUCK FAILED"; exit 1; }
