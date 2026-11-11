#!/usr/bin/env bash
# tests/test-story-invocable.sh - regression test for #119: /next (step 8) and the workflow skill tell the agent to file
# the rest of a partial story with `/story`, but skills/story/SKILL.md sets `disable-model-invocation: true`, so the
# Skill tool refuses it. The invariant: while story has that flag, no skill tells the agent to file a story with
# `/story`. Either fix passes: the flag is removed from story, or the steps are inlined where they are needed (and the
# line no longer sends the agent to `/story`). Lines that tell the maintainer to file (fix: "suggest the maintainer
# files it") or only describe the skill ("`/story` files a story") are not instructions to the agent.
#   tests/test-story-invocable.sh [<root>]
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
story="$root/skills/story/SKILL.md"
fail=0
[ -f "$story" ] || { echo "FAIL: $story is missing"; exit 1; }

# the frontmatter is the lines between the first two '---'
flag=$(awk '/^---[[:space:]]*$/ { n++; next } n == 1 && /^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ { print "yes"; exit } n >= 2 { exit }' "$story")
if [ "$flag" != yes ]; then
  echo "ok: skills/story/SKILL.md is invocable by the model"
  exit 0
fi

for f in "$root"/skills/*/SKILL.md; do
  [ "$f" = "$story" ] && continue
  rel=${f#"$root"/}
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    echo "FAIL: $rel:$hit"
    echo "      tells the agent to file a story with /story, but skills/story/SKILL.md has disable-model-invocation: true," \
      "so the Skill tool refuses it; remove the flag or carry the filing steps in place"
    fail=1
  done < <(grep -nE '/story' "$f" | grep -E '\b(file|filing)\b' | grep -viE 'maintainer')
done
exit "$fail"
