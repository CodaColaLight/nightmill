#!/usr/bin/env bash
# Regression test for #120: agents/worker.md hard-coded `gh pr merge <n> --auto --squash`, so a project with other
# git.mergeFlags got a worker that refused its own merge command. Only the commands are checked: no gh pr merge with a
# strategy flag in the agent file, and --auto in it; how it says the command comes from the prompt is the reviewers'
# (iteration 76).
set -u
cd "$(dirname "$0")/.." || exit 1
f=agents/worker.md
fail=0
text=$(cat "$f")

# 1. No hard-coded --squash (or --rebase / --merge) flag in a gh pr merge command.
if printf '%s\n' "$text" | grep -E -- 'gh pr merge[^`]*--(squash|rebase|merge)\b' >/dev/null; then
  echo "FAIL: $f hard-codes a merge strategy flag in a gh pr merge command"; fail=1
fi

# 2. The merge command it runs contains --auto.
if ! printf '%s\n' "$text" | grep -E -- '--auto' >/dev/null; then
  echo "FAIL: $f does not require --auto in the merge command"; fail=1
fi

[ "$fail" = 0 ] && echo "ok: worker merge command has no strategy flag and needs --auto"
exit "$fail"
