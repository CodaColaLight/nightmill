#!/usr/bin/env bash
# Regression test for #138: the 0.2.0 changelog section names neither the skills
# change of #54 nor decision 0003, and the changelog rule in .claude/CLAUDE.md
# covers only iterations. Offline: reads CHANGELOG.md and .claude/CLAUDE.md only.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

section=$(awk '/^## 0\.2\.0( |$)/{on=1; next} /^## /{on=0} on' CHANGELOG.md)
if [ -z "${section}" ]; then
  echo "FAIL: CHANGELOG.md has no '## 0.2.0' section"
  exit 1
fi

# (a) the #54 skills change
if ! grep -Eqi '#54([^0-9]|$)' <<<"${section}"; then
  echo "FAIL: the 0.2.0 section does not name the skills change of #54"
  fail=1
fi

# (b) decision 0003
if ! grep -Eq '0003' <<<"${section}"; then
  echo "FAIL: the 0.2.0 section does not name decision 0003"
  fail=1
fi

# (c) the changelog rule covers skills/agents/scripts/hooks
rule=$(awk '/CHANGELOG by version/{on=1; print; next} on && /^- \*\*/{on=0} on && /^## /{on=0} on' .claude/CLAUDE.md)
for d in skills agents scripts hooks; do
  if ! grep -Eq "${d}/" <<<"${rule}"; then
    echo "FAIL: the 'CHANGELOG by version' rule does not mention a change under ${d}/"
    fail=1
  fi
done

[ "${fail}" -eq 0 ] && echo "OK: changelog coverage"
exit "${fail}"
