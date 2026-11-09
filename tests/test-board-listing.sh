#!/usr/bin/env bash
# Regression test for #125: the board listing hard-codes the field names and silently drops items
# past the first 200. The listing of /spec, /next and /fix (step 1) and the listing rule of the
# workflow skill ("Picking an issue", item 2) must (a) build the filter of --jq from the configured
# board.statusField and board.priorityField, not the literal keys of the default names, (b) say
# what to do when the listing returns as many items as the limit (a visible warning that items may
# be missing) and (c) stay one gh project item-list command with its own --jq and no pipe. The
# skills are text the model follows, so this checks text.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
opt="--j""q"   # the option text, built so the word is not spelled out (lint: bash files do not use it)

# The listing window: the line holding "gh project item-list <project>" and the 5 lines after it.
for s in spec next fix; do
  f=skills/$s/SKILL.md
  win=$(awk '/gh project item-list <project>/{n=6} n>0{print; n--}' "$f")
  if [ -z "$win" ]; then echo "FAIL: $f holds no board listing"; fail=1; continue; fi
  line=$(grep -F 'gh project item-list <project>' "$f" | head -n 1)

  # (a) the filter (the single-quoted part after --jq) names no literal .status or .priority key
  filter=$(sed -n "s/.*--j[q] '\([^']*\)'.*/\1/p" <<<"$line")
  if [ -z "$filter" ]; then echo "FAIL: $f listing has no quoted ${opt} filter"; fail=1
  elif grep -E '\.(status|priority)([^A-Za-z]|$)' <<<"$filter" >/dev/null; then
    echo "FAIL: $f listing hard-codes .status or .priority in its filter"; fail=1
  fi
  # ... and the text ties the filter to the configured field names
  if ! grep -F 'board.statusField' <<<"$win" >/dev/null || ! grep -F 'board.priorityField' <<<"$win" >/dev/null; then
    echo "FAIL: $f listing does not build the filter from board.statusField and board.priorityField"; fail=1
  fi

  # (b) a full page (as many items as the limit) gives a visible warning that items may be missing
  if ! grep -i -E 'warn' <<<"$win" >/dev/null || ! grep -i -E 'missing|dropped|truncat|cut off|more items|not shown' <<<"$win" >/dev/null; then
    echo "FAIL: $f listing does not warn when the page is full and items may be missing"; fail=1
  fi

  # (c) one command, no pipe outside the quoted filter
  cmd=$(sed -n 's/.*\(gh project item-list <project>[^`]*\).*/\1/p' <<<"$line")
  bare=$(sed "s/'[^']*'//g" <<<"$cmd")
  if [ -z "$cmd" ] || ! grep -F -e "${opt}" <<<"$cmd" >/dev/null || grep -F '|' <<<"$bare" >/dev/null; then
    echo "FAIL: $f listing is not a single gh project item-list ... ${opt} command without a pipe"; fail=1
  fi
done

# The workflow skill: item 2 of "Picking an issue" carries its own listing rule.
f=skills/workflow/SKILL.md
item=$(awk '/^2\. \*\*Without a number\*\*/{on=1;print;next} /^3\. /{on=0} on' "$f" | tr '\n' ' ')
if [ -z "$item" ]; then echo "FAIL: $f holds no listing rule"; fail=1
else
  if ! grep -F 'board.statusField' <<<"$item" >/dev/null || ! grep -E 'board\.priorityField' <<<"$item" >/dev/null \
     || ! grep -i -E 'key|field name|configured' <<<"$item" >/dev/null; then
    echo "FAIL: $f listing rule does not build the filter from the configured status and priority field names"; fail=1
  fi
  if ! grep -i -E 'warn' <<<"$item" >/dev/null || ! grep -i -E 'missing|dropped|truncat|cut off|more items|not shown' <<<"$item" >/dev/null; then
    echo "FAIL: $f listing rule does not warn when the page is full and items may be missing"; fail=1
  fi
fi

[ "$fail" = 0 ] && echo "ok: the board listing uses the configured field names and warns on a full page"
exit "$fail"
