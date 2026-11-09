#!/usr/bin/env bash
# Regression test for #118: /fix N takes the number as given and never checks that the issue is
# Ready or carries the bug label. Step 1 ("Pick the issue") of skills/fix/SKILL.md must, with a
# number, refuse an issue whose status is not Ready and an issue without labels.bug, say so in one
# line and change nothing, all before step 3 (status, slot, agent). The skill is text the model
# follows, so this checks text.
set -u
cd "$(dirname "$0")/.." || exit 1
f=skills/fix/SKILL.md
fail=0
# Step 1 only: from "1. **Pick the issue.**" up to (not including) "2. ", joined into one line.
step=$(awk '/^1\. \*\*Pick the issue/{on=1} /^2\. /{on=0} on' "$f" | tr '\n' ' ')
if [ -z "$step" ]; then echo "FAIL: step 1 not found in $f"; exit 1; fi
r='(refus|reject|declin)'

# (a) a numbered issue whose status is not Ready is refused
if ! grep -i -E "$r[^.]*(status|Ready)|(status|Ready)[^.]*$r|not Ready" <<<"$step" >/dev/null; then
  echo "FAIL: $f step 1 does not refuse a numbered issue whose status is not Ready"; fail=1
fi

# (b) a numbered issue without labels.bug (a story or an epic) is refused
if ! grep -i -E "$r[^.]*(labels\.bug|bug label|story|stories|epic)|(without|lack|missing|no|not (carry|have|labelled))[^.]*labels\.bug[^.]*$r|(story|epic)[^.]*$r" <<<"$step" >/dev/null; then
  echo "FAIL: $f step 1 does not refuse a numbered issue without the labels.bug label"; fail=1
fi

# (c) the refusal is one line and changes nothing
if ! grep -i -E 'one line|single line|one sentence' <<<"$step" >/dev/null; then
  echo "FAIL: $f step 1 does not say the refusal is one line"; fail=1
fi
if ! grep -i -E "(nothing|no)[^.]*(is |are )?(changed|change)|changes? nothing|leave[s]? .*unchanged" <<<"$step" >/dev/null; then
  echo "FAIL: $f step 1 does not say that nothing is changed on a refusal"; fail=1
fi

# (d) the check sits in step 1, which precedes the status change, slot and agents of steps 3 and 4
if ! grep -i -E "$r" <<<"$step" >/dev/null; then
  echo "FAIL: $f step 1 holds no refusal, so the check cannot come before step 3"; fail=1
fi

[ "$fail" = 0 ] && echo "ok: /fix N checks Ready and labels.bug before any change"
exit "$fail"
