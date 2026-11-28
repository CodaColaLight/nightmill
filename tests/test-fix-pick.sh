#!/usr/bin/env bash
# Regression test for #118: /fix N refuses an issue that is not Ready or lacks the bug label. Only the contracts are
# checked: skills/fix/SKILL.md names the status Ready and the key labels.bug; the refusal, its wording and its place in
# step 1 are the reviewers' (iteration 76).
set -u
cd "$(dirname "$0")/.." || exit 1
f=skills/fix/SKILL.md
fail=0
[ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }

grep -qw 'Ready' "$f" || { echo "FAIL: $f does not name the status Ready"; fail=1; }
grep -qF 'labels.bug' "$f" || { echo "FAIL: $f does not name the key labels.bug"; fail=1; }

[ "$fail" = 0 ] && echo "ok: /fix names Ready and labels.bug"
exit "$fail"
