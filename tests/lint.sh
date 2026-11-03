#!/usr/bin/env bash
# tests/lint.sh - nightmill stays generic and well-formed.
#   1. No word from tests/forbidden-words.txt (names of the project nightmill was extracted from,
#      its maintainer, ...) appears anywhere in the repository.
#   2. Every JSON file parses.
#   3. Every skill has frontmatter with name and description; every skill that reads the config
#      injects it with the !` ` preamble.
#   4. Shell scripts pass bash -n; shellcheck runs when installed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0

echo "== forbidden words"
if grep -rniF --exclude-dir=.git --exclude=forbidden-words.txt -f tests/forbidden-words.txt . ; then
  echo "FAIL: project-specific words found (see above)"; fail=1
fi

echo "== json"
while IFS= read -r f; do
  if command -v jq >/dev/null 2>&1; then jq . "$f" >/dev/null || { echo "FAIL: $f does not parse"; fail=1; }
  else python3 -I -m json.tool "$f" >/dev/null || { echo "FAIL: $f does not parse"; fail=1; }
  fi
done < <(find . -path ./.git -prune -o -name '*.json' -print)

echo "== skills"
for s in skills/*/SKILL.md; do
  head -1 "$s" | grep -qx -- '---' || { echo "FAIL: $s has no frontmatter"; fail=1; }
  grep -q '^name: ' "$s" || { echo "FAIL: $s has no name"; fail=1; }
  grep -q '^description: ' "$s" || { echo "FAIL: $s has no description"; fail=1; }
  if grep -q 'nightmill.json' "$s" && ! grep -q '^!`' "$s"; then
    echo "FAIL: $s mentions the config but does not inject it"; fail=1
  fi
done
for a in agents/*.md; do
  grep -q '^name: ' "$a" || { echo "FAIL: $a has no name"; fail=1; }
done

echo "== shell"
for f in scripts/*.sh tests/*.sh; do
  bash -n "$f" || { echo "FAIL: $f does not parse"; fail=1; }
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning scripts/*.sh tests/*.sh || fail=1
else
  echo "(shellcheck not installed, skipped)"
fi

[ "$fail" = 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
