#!/usr/bin/env bash
# Tests for #332 (iteration 58): when the review rounds are used up and every open blocking finding names a concrete
# fix, /spec, /next and /fix propose one extra review round; review.maxFixRounds defaults to 3. The skills are
# conversations, so this pins the wording the behaviour depends on. Text is joined (newlines to spaces, runs of spaces
# made one) before it is searched. Usage: bash tests/test-extra-round.sh [repository path]
set -uo pipefail
cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 1
fail=0

flat() { tr '\n' ' ' | sed -E 's/ +/ /g'; }

# need <label> <joined text> <text>...
need_in() {
  local label=$1 flatf=$2 text; shift 2
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) ;;
      *) echo "FAIL: ${label} does not say the extra round item: ${text}"; fail=1 ;;
    esac
  done
}
need() { local f=$1; shift; need_in "$f" "$(flat < "$f")" "$@"; }
gone() {
  local f=$1 text flatf; shift
  flatf=$(flat < "$f")
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) echo "FAIL: ${f} still says: ${text}"; fail=1 ;;
    esac
  done
}

W=skills/workflow/SKILL.md
N=skills/next/SKILL.md
F=skills/fix/SKILL.md
S=skills/spec/SKILL.md

echo "== an extra review round is proposed"

# W is the section 'Findings and fix rounds', code fences skipped
Wtext=$(awk '/^## Findings and fix rounds$/ { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' "$W" | flat)
needW() { need_in "$W (Findings and fix rounds)" "$Wtext" "$@"; }

# Criterion 1: the proposal and the round
needW '**When the rounds are used up.**' 'each names a concrete fix' \
  'Proposed: one extra review round, the <producer> role on <model> and then the <reviewer> role on <model>, to fix:' \
  'Answer `extra round` to run it now'
for f in "$S" "$N" "$F"; do need "$f" 'When the rounds are used up' 'review.maxFixRounds + 1'; done
need "$S" 'docs: iteration <N> spec (#<issue>), extra review round'
need "$N" 'gh pr edit <pr> --body-file' 'fix-round-<k>'
need "$F" 'gh pr edit <pr> --body-file' 'fix-round-<k>'

# Criterion 2: a finding that needs a decision stops the run and the message names it
needW 'Decision needed:' 'so no extra round is proposed' 'a choice between designs' 'a story trigger:' \
  'a conflict with' 'the tester stands by the test' 'no concrete fix named' 'a dispute over'

# Criterion 3: the rule tells the two cases apart, each message names its case
needW 'needs a decision' 'fixable' 'a stop is the safe side'
need "$F" 'blocking review findings are still open, fixable: a revision is the next step' \
  'blocking review findings are still open, a decision is needed:'

# Criterion 4: the same cycle, counted and marked in the Review section
needW '- Extra rounds used: 1 of 1, accepted by the maintainer' 'fixed in the extra round: blocking <file>:<line> <text>' \
  '## Review' '- Reviewer: codeReviewer role on <model>' '- Author: <producer> role on <model>' \
  '- Fix rounds used: <r> of <review.maxFixRounds>' '- Findings fixed: <n>' \
  '- Findings still open: <b> blocking, <a> advisory' 'fixed in round <k>:'
need "$S" 'Extra review round on PR #<pr>:'

# Criterion 5: a decline or an unattended run leaves the pull request as opened
needW 'No extra round: PR #<pr> stays as it was opened, with auto-merge off and the findings listed in its Review section.' \
  'at most one extra round per pull request' 'The extra review round did not finish:'
fixbatch=$(awk 'index($0, "## Batch mode: `/fix all`") == 1 { s = 1; next } s && /^## / { exit } s { print }' "$F" | flat)
need_in "$F (Batch mode: /fix all)" "$fixbatch" 'proposes no extra round'
for f in "$W" "$N" "$F"; do
  need "$f" 'Auto-merge is not enabled: blocking review findings are still open (see Review).'
done

# Criterion 6: a merge is never offered while fixable findings are open
needW 'A revision is the next step, not a merge.' 'this run did not hold the review and proposes no extra round'
gone "$S" "the pull request waits for the maintainer's merge (when the spec is accepted) or revision"

# Decision 9: the check fix rounds do not change
needW 'An extra round is not a check fix round'

# Criterion 7: the default is 3 and every place that pins it agrees
need README.md '`review.maxFixRounds` (default 3)'
gone README.md '`review.maxFixRounds` (default 2)'
need schema/nightmill.schema.json 'propose one extra round'
case "$(flat < schema/nightmill.schema.json)" in
  *'"maxFixRounds": { "type": "integer", "minimum": 0, "default": 3,'*) ;;
  *) echo "FAIL: schema/nightmill.schema.json does not give review.maxFixRounds the default 3"; fail=1 ;;
esac
need templates/nightmill.example.json '"maxFixRounds": 3'
gone templates/nightmill.example.json '"maxFixRounds": 2'

[ "${fail}" = 0 ] && echo "EXTRA ROUND OK" || { echo "EXTRA ROUND FAILED"; exit 1; }
