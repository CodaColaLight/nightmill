#!/usr/bin/env bash
# tests/test-check-skill.sh - regression for #124: /check must stop after three attempts and report, tell an
# environmental failure from a code failure, and allow fixing a test written in the same task. The skill is text the
# model follows, so the test checks its text.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
skill="$here/skills/check/SKILL.md"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$skill" ] || fail "skills/check/SKILL.md missing"
# the full-check part: everything before the quick-mode paragraph, flattened to one lowercase line
body=$(awk '/^`\/nightmill:check quick`/{exit} {print}' "$skill" | tr '\n' ' ' | tr -s ' ' | tr 'A-Z' 'a-z')

echo "== /check does not re-run without bound"
case "$body" in *"re-run until it passes"*) fail "still says to re-run until it passes, with no bound" ;; esac

echo "== /check stops after three attempts and reports"
grep -Eq 'three (attempts|runs|tries)|3 (attempts|runs|tries)|at most (three|3)|up to (three|3)|(three|3) (honest )?attempts' <<<"$body" \
  || fail "no bound of three attempts"
grep -Eq 'stop' <<<"$body" || fail "does not say to stop"
grep -Eq 'report' <<<"$body" || fail "does not say to report"

echo "== /check tells an environmental failure from a code failure"
grep -Eq 'environment' <<<"$body" || fail "no mention of an environmental failure"
grep -Eq 'network|missing tool' <<<"$body" || fail "no example of an environmental cause (network, a missing tool)"
grep -Eq 'code failure|failure in the code|code (is|was) at fault|cause in the code|a failure of the code' <<<"$body" \
  || fail "does not name a code failure against the environmental one"

echo "== /check may fix a test written in the same task"
grep -Eq 'test (that )?(you |it )?(wrote|written|added|created)[^.]*(this|the same) task|(this|the same) task[^.]*test' <<<"$body" \
  || fail "no leave to fix a test written in this task"
case "$body" in *"(not the test)"*) fail "still forbids fixing the test without exception" ;; esac

echo "test-check-skill: ok"
