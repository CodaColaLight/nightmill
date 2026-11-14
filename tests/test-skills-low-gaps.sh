#!/usr/bin/env bash
# tests/test-skills-low-gaps.sh - regression test for #142 (LOW-SKILLS): the low-severity gaps in the skills that a
# text check can pin without a design choice. Each check names the item of the bug report it pins.
#   (a) agents/worker.md has a `tools:` line in its frontmatter, so the "mechanical" worker does not inherit every tool
#   (b) skills/spec/SKILL.md removes the label that /story sets (labels.needsSpec) when the spec is written
#   (c) a skill with `disable-model-invocation: true` has no "Use when asked ..." in its description: the model never
#       invokes it, so the sentence triggers nothing
#   (d) one spelling of the permission rule for `gh project` across the skills: `Bash(gh project *)` or
#       `Bash(gh project:*)`, never both (either one passes)
# Items that need a design choice (where the check runs on the base, the hot-file action in /next, the config injected
# twice, the one way to describe Done, the changelog entry format, the SessionStart matcher, rate limits) are not pinned.
#   tests/test-skills-low-gaps.sh [<root>]
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
fail=0

# the frontmatter of a file: the lines between the first two '---'
front() { awk '/^---[[:space:]]*$/ { n++; next } n == 1 { print } n >= 2 { exit }' "$1"; }

# (a) the worker lists its tools
worker="$root/agents/worker.md"
if [ ! -f "$worker" ]; then
  echo "FAIL: $worker is missing"; fail=1
elif ! front "$worker" | grep -qE '^tools:[[:space:]]*[A-Za-z]'; then
  echo "FAIL: agents/worker.md has no 'tools:' line in its frontmatter, so the mechanical worker inherits every tool"
  fail=1
fi

# (b) /spec takes the needs-spec label off the story
spec="$root/skills/spec/SKILL.md"
if [ ! -f "$spec" ]; then
  echo "FAIL: $spec is missing"; fail=1
elif ! grep -E 'labels\.needsSpec|needs-spec' "$spec" | grep -qiE 'remov|delet|drop'; then
  echo "FAIL: skills/spec/SKILL.md never removes the labels.needsSpec label (needs-spec) that /story sets"
  fail=1
fi

# (c) a skill the model cannot invoke does not say "Use when asked ..."
for f in "$root"/skills/*/SKILL.md; do
  rel=${f#"$root"/}
  fm=$(front "$f")
  grep -qE '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' <<<"$fm" || continue
  if grep -E '^description:' <<<"$fm" | grep -qiE 'use (it )?when (asked|someone asks|the maintainer asks)'; then
    echo "FAIL: $rel sets disable-model-invocation: true but its description says \"Use when asked ...\"," \
      "which never triggers it"
    fail=1
  fi
done

# (d) one spelling of the gh project permission rule
colon=$(grep -rlF 'Bash(gh project:*)' "$root"/skills 2>/dev/null | sed "s|^$root/||" | tr '\n' ' ')
space=$(grep -rlF 'Bash(gh project *)' "$root"/skills 2>/dev/null | sed "s|^$root/||" | tr '\n' ' ')
if [ -n "$colon" ] && [ -n "$space" ]; then
  echo "FAIL: the skills spell the gh project permission rule two ways: Bash(gh project:*) in $colon" \
    "and Bash(gh project *) in $space"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "ok: the low-severity skill gaps pinned by #142 are closed"
exit "$fail"
