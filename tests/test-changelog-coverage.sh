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
# The clause (split at ';' and at sentence ends) that gives a change an entry or bullet
# must itself name all four directories; a mention elsewhere (scripts/release.sh) does not count.
clauses=$(tr '\n' ' ' <<<"${rule}" | sed -E 's/; /\n/g; s/\. /\n/g')
for d in skills agents scripts hooks; do
  found=0
  while IFS= read -r clause; do
    if grep -Eqi 'bullet|entry' <<<"${clause}" && grep -Eq "${d}/" <<<"${clause}"; then
      found=1
    fi
  done <<<"${clauses}"
  if [ "${found}" -eq 0 ]; then
    echo "FAIL: no clause of the 'CHANGELOG by version' rule gives a change under ${d}/ an entry"
    fail=1
  fi
done

[ "${fail}" -eq 0 ] && echo "OK: changelog coverage"
exit "${fail}"
