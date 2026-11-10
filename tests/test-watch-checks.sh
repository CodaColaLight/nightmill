#!/usr/bin/env bash
# Tests for #145 (iteration 46): after enabling auto-merge, /next, /fix and /spec watch the pull request's
# checks and fix a red one within review.maxFixRounds. The skills are conversations, so this pins the wording
# the behaviour depends on. Text is joined (newlines to spaces, runs of spaces made one) before it is searched.
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

# count <file> <text>: how many times the text is in the joined file
count() { flat "$1" | grep -o -F -- "$2" | wc -l | tr -d ' '; }

W=skills/workflow/SKILL.md
N=skills/next/SKILL.md
F=skills/fix/SKILL.md
S=skills/spec/SKILL.md

echo "== a red pull request is fixed within bounds"

# Criterion 1: the watch, bounded in time
need "$W" \
  'at most `review.watchChecksMinutes` minutes' \
  'review.watchChecksMinutes must be a whole number of at least 1; using 30' \
  '10 times in a row' \
  'gh pr checks <pr> --watch --fail-fast --interval 30' \
  'gh pr checks <pr> --json name,bucket,link,workflow' \
  'Only a pull request with auto-merge on is watched' \
  '`worktrees.stalledAfterMinutes` minus 30 seconds' \
  'were still running after'
need "$N" 'Watching the checks' '| `session` | `watch-checks` |'
need "$F" 'Watching the checks' '| `session` | `watch-checks` |'
need "$S" 'Watching the checks'

# Criterion 2: a red check is fixed and pushed, at most review.maxFixRounds times
need "$W" \
  'check fix round' \
  'at most `review.maxFixRounds` check fix rounds' \
  'actions/jobs/<job>/logs' \
  '--allow-escape-sequences' \
  'startswith("Check fix round ")' \
  'the round could not be recorded:'
need "$N" 'Check fix round <k> of <review.maxFixRounds>' 'is red (check fix round <k> of' \
  'check-fix-<k>' 'check-review-<k>' 'Fix the cause in this change, run the check, commit.' \
  'not known (resumed run)'
need "$F" 'Check fix round <k> of <review.maxFixRounds>' 'is red (check fix round <k> of' \
  'check-fix-<k>' 'check-review-<k>' 'Fix the cause in this change, run the check, commit.'
need "$S" 'Check fix round <k> of <review.maxFixRounds>' 'is red (check fix round <k> of' \
  'Fix the cause in the spec file and run the check; do not commit, the session commits.' \
  'docs: iteration <N> spec (#<issue>), check fix round <k>'

# Criterion 3: rounds used up, comment on the issue, label blocked, stop, never force a merge
need "$W" \
  'Checks of PR #<pr> are red after <r> <check fix round | check fix rounds>' \
  'Checks of PR #<pr> are not watched after <r> <check fix round | check fix rounds>' \
  "the branch on origin is not this run's last commit" \
  'the branch could not be created:' \
  '--add-label blocked' \
  'never with `--admin`' \
  'never retries or re-runs a CI job (`gh run rerun`)'
need "$N" 'handed-over' 'never `gh run rerun`'
need "$F" 'handed-over' 'never `gh run rerun`'
need "$S" 'never `gh run rerun`'
for f in skills/*/SKILL.md; do
  flatf=$(flat "$f")
  case "${flatf}" in
    *"gh pr merge --admin"*) echo "FAIL: ${f} forces a merge or re-runs a check"; fail=1 ;;
  esac
  reruns=$(count "$f" 'gh run rerun')
  nevers=$(( $(count "$f" 'never retries or re-runs a CI job (`gh run rerun`)') + $(count "$f" 'never `gh run rerun`') ))
  if [ "${reruns}" != "${nevers}" ]; then
    echo "FAIL: ${f} forces a merge or re-runs a check"; fail=1
  fi
done

# Criterion 4: green needs nothing more
need "$W" 'Checks of PR #<pr> are green (<n> <check | checks>)'

# The key (criterion 1)
case "$(flat schema/nightmill.schema.json)" in
  *'"watchChecksMinutes": { "type": "integer", "minimum": 1, "default": 30, "description": "Minutes /next, /fix and'*) ;;
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

# Only the comments the criteria and the count need
for f in skills/*/SKILL.md; do
  flatf=$(flat "$f")
  for text in '--body "Checks of PR #<pr> were still running' 'Fixed by the <role> role'; do
    case "${flatf}" in
      *"${text}"*) echo "FAIL: ${f} comments where no rule asks for it"; fail=1 ;;
    esac
  done
done

[ "${fail}" = 0 ] && echo "WATCH CHECKS OK" || { echo "WATCH CHECKS FAILED"; exit 1; }
