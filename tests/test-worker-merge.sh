#!/usr/bin/env bash
# Regression test for #120: agents/worker.md hard-codes `gh pr merge <n> --auto --squash` as the
# only merge it may run, so a project with git.mergeFlags `--auto --rebase` gets a worker that
# refuses its own merge command. The worker must run only the merge command its prompt gives,
# and that command must contain --auto. The agent file is text the model follows, so this checks text.
set -u
cd "$(dirname "$0")/.." || exit 1
f=agents/worker.md
fail=0
text=$(cat "$f")

# 1. No hard-coded --squash (or --rebase / --merge) flag as the only allowed merge.
if printf '%s\n' "$text" | grep -E -- 'gh pr merge[^`]*--(squash|rebase|merge)\b' >/dev/null; then
  echo "FAIL: $f hard-codes a merge strategy flag in a gh pr merge command"; fail=1
fi

# 2. It still forbids a plain merge and requires --auto in the command the prompt gives.
if ! printf '%s\n' "$text" | grep -i -E 'merge command' >/dev/null || \
   ! printf '%s\n' "$text" | grep -E -- '--auto' >/dev/null; then
  echo "FAIL: $f does not say the merge command comes from the prompt and must contain --auto"; fail=1
fi
if ! printf '%s\n' "$text" | grep -i -E 'prompt (gives|says|names|states)|(given|named|stated) (in|by) (your|the) prompt' >/dev/null; then
  echo "FAIL: $f does not tie the merge command to the one the prompt gives"; fail=1
fi

[ "$fail" = 0 ] && echo "ok: worker merge command comes from the prompt"
exit "$fail"
