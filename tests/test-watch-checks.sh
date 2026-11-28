#!/usr/bin/env bash
# Tests for #145 (iteration 46): after enabling auto-merge, /next, /fix and /spec watch the pull request's
# checks and fix a red one within review.maxFixRounds. Only the contracts are checked: the config keys and their
# schema values, the commands and their flags, the commands that must not appear, the prefixes other lines parse
# (`Check fix round `, `Checks of PR #<pr> are red`, `Checks of PR #<pr> are not watched`) and the step names passed to
# --report; the sentences of the watch, its warnings and hand-over reasons are the reviewers' (iteration 76). Text is
# joined (newlines to spaces, runs of spaces made one) before it is searched.
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
      *) echo "FAIL: ${f} does not say the watch item: ${text}"; fail=1 ;;
    esac
  done
}

W=skills/workflow/SKILL.md
N=skills/next/SKILL.md
F=skills/fix/SKILL.md
S=skills/spec/SKILL.md

echo "== a red pull request is fixed within bounds"

# The keys, the commands and the parsed lines of the workflow skill
need "$W" \
  'review.watchChecksMinutes' 'review.maxFixRounds' 'worktrees.stalledAfterMinutes' \
  'gh pr checks <pr> --watch --fail-fast --interval 30' \
  'gh pr checks <pr> --json name,bucket,link,workflow' \
  'actions/jobs/<job>/logs' \
  '--allow-escape-sequences' \
  'startswith("Check fix round ")' \
  '--add-label blocked' \
  'Checks of PR #<pr> are red' \
  'Checks of PR #<pr> are not watched'

# The step names passed to --report and the comment prefix of a round
need "$N" '| `session` | `watch-checks` |' 'check-fix-<k>' 'check-review-<k>' 'handed-over' 'Check fix round '
need "$F" '| `session` | `watch-checks` |' 'check-fix-<k>' 'check-review-<k>' 'handed-over' 'Check fix round '
need "$S" 'Check fix round ' '"docs: iteration <N> spec (#<issue>), check fix round <k>"'

# No skill forces a merge
for f in skills/*/SKILL.md; do
  flatf=$(flat "$f")
  case "${flatf}" in
    *"gh pr merge --admin"*) echo "FAIL: ${f} forces a merge"; fail=1 ;;
  esac
done

# The key (criterion 1)
case "$(flat schema/nightmill.schema.json)" in
  *'"watchChecksMinutes": { "type": "integer", "minimum": 1, "default": 30,'*) ;;
  *) echo "FAIL: schema/nightmill.schema.json does not carry the key review.watchChecksMinutes"; fail=1 ;;
esac
case "$(flat templates/nightmill.example.json)" in
  *'"watchChecksMinutes": 30'*) ;;
  *) echo "FAIL: templates/nightmill.example.json does not carry the key review.watchChecksMinutes"; fail=1 ;;
esac
case "$(flat README.md)" in
  *'| `review.watchChecksMinutes` |'*) ;;
  *) echo "FAIL: README.md does not carry the key review.watchChecksMinutes"; fail=1 ;;
esac

# The command forms: every command has a run permission already
for f in skills/*/SKILL.md; do
  flatf=$(flat "$f")
  for text in 'gh run view' '--log-failed' '`sleep ' 'git -C <checkout>'; do
    case "${flatf}" in
      *"${text}"*) echo "FAIL: ${f} runs a command that has no run permission: ${text}"; fail=1 ;;
    esac
  done
done
need "$W" 'git -C <slot path> push -u origin <branch>' 'git push -u origin <branch>'

# No comment while the checks still run
for f in skills/*/SKILL.md; do
  flatf=$(flat "$f")
  text='--body "Checks of PR #<pr> were still running'
  case "${flatf}" in
    *"${text}"*) echo "FAIL: ${f} comments where no rule asks for it"; fail=1 ;;
  esac
done

[ "${fail}" = 0 ] && echo "WATCH CHECKS OK" || { echo "WATCH CHECKS FAILED"; exit 1; }
