#!/usr/bin/env bash
# Tests for #332 (iteration 58): when the review rounds are used up and every open blocking finding names a concrete
# fix, /spec, /next and /fix propose one extra review round; review.maxFixRounds defaults to 3. Only the contracts are
# checked: the key and its default in the schema, the example and the README, the answer the skills read, the step
# name they report, the commands they run and the line /next and /spec read back; the wording of the proposal and the
# rule is the manual check's (iteration 73). Text is joined (newlines to spaces, runs of spaces made one) before it is
# searched. Usage: bash tests/test-extra-round.sh [repository path]
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

# the maintainer's answer the skills read
need "$W" '`extra round`'
for f in "$S" "$N" "$F"; do need "$f" 'review.maxFixRounds'; done
# the commands and the step name of the extra round
need "$S" 'git commit -m "docs: iteration <N> spec (#<issue>), extra review round"'
# /spec looks for the comment with this prefix when it resumes
need "$S" 'Extra review round on PR #<pr>:'
need "$N" 'gh pr edit <pr> --body-file' 'fix-round-<k>'
need "$F" 'gh pr edit <pr> --body-file' 'fix-round-<k>'
# a pull request whose findings are still open keeps a line the skills read back when they resume
for f in "$W" "$N" "$F"; do
  need "$f" 'Auto-merge is not enabled:'
done

# the default is 3 and every place that pins it agrees
need README.md '`review.maxFixRounds` (default 3)'
case "$(flat < schema/nightmill.schema.json)" in
  *'"maxFixRounds": { "type": "integer", "minimum": 0, "default": 3,'*) ;;
  *) echo "FAIL: schema/nightmill.schema.json does not give review.maxFixRounds the default 3"; fail=1 ;;
esac
need templates/nightmill.example.json '"maxFixRounds": 3'
gone templates/nightmill.example.json '"maxFixRounds": 2'

[ "${fail}" = 0 ] && echo "EXTRA ROUND OK" || { echo "EXTRA ROUND FAILED"; exit 1; }
