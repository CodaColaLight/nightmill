#!/usr/bin/env bash
# tests/test-unattended-docs.sh - the README has a "Running unattended" section (iteration 49, #160). Pins on the
# text; the spec's 11 pins.
#   tests/test-unattended-docs.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }
readme="$root/README.md"
schema="$root/schema/nightmill.schema.json"
[ -f "$readme" ] || { echo "FAIL: README.md missing" >&2; exit 1; }

# contains <flat text> <needle>
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
flatten() { tr '\n' ' ' | sed -E 's/ +/ /g'; }

# default_of <key>: the default of a one-line schema entry
default_of() {
  grep -E "^[[:space:]]*\"$1\": \{" "$schema" | head -1 | sed -E 's/.*"default": *([0-9]+).*/\1/' || true
}
d_slots=$(default_of slots)
d_agents=$(default_of maxAgents)
d_watch=$(default_of watchChecksMinutes)
d_stalled=$(default_of stalledAfterMinutes)
for v in "$d_slots" "$d_agents" "$d_watch" "$d_stalled"; do
  case "$v" in ''|*[!0-9]*) fail "schema/nightmill.schema.json: a default is missing or not a number" ;; esac
done

repo=$(grep -oE '/plugin marketplace add [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$readme" | head -1 | sed 's|.* ||' || true)
[ -n "$repo" ] || fail "README.md: no /plugin marketplace add line"

# part <heading line>: the lines of sec after that heading up to the next '### '
part() { printf '%s\n' "$sec" | awk -v h="$1" '$0 == h { s = 1; next } s && /^### / { exit } s { print }'; }

# 1. exactly one heading, after the limit sub-section and before Developing nightmill
n=$(grep -c '^## Running unattended$' "$readme" || true)
if [ "$n" != "1" ]; then
  fail "README.md has $n lines '## Running unattended', 1 expected"
else
  ln=$(grep -n '^## Running unattended$' "$readme" | head -1 | cut -d: -f1)
  al=$(grep -n '^### Adjusting the limit to the load$' "$readme" | head -1 | cut -d: -f1 || true)
  dv=$(grep -n '^## Developing nightmill$' "$readme" | head -1 | cut -d: -f1 || true)
  { [ -n "$al" ] && [ "$ln" -gt "$al" ]; } || fail "README.md: '## Running unattended' is not after '### Adjusting the limit to the load'"
  { [ -n "$dv" ] && [ "$ln" -lt "$dv" ]; } || fail "README.md: '## Running unattended' is not before '## Developing nightmill'"
fi

sec=$(awk '/^## Running unattended$/ { s = 1; print; next } s && /^## / { exit } s { print }' "$readme")
if [ -z "$sec" ]; then
  fail "README.md has no section '## Running unattended'"
  echo "FAIL: stopping: nothing else to check" >&2
  exit 1
fi
flat=$(printf '%s\n' "$sec" | flatten)

# 2. five sub-headings, once each, in order, and no other '### '
prev=0
for h in '### Before the first run' '### The commands' '### Several runs at once' '### Watching a run' '### When a run is stopped'; do
  c=$(printf '%s\n' "$sec" | grep -cxF "$h" || true)
  if [ "$c" != "1" ]; then fail "README.md: the section has $c lines '$h', 1 expected"; continue; fi
  l=$(printf '%s\n' "$sec" | grep -nxF "$h" | head -1 | cut -d: -f1)
  [ "$l" -gt "$prev" ] || fail "README.md: '$h' is out of order"
  prev=$l
done
cnt=$(printf '%s\n' "$sec" | grep -c '^### ' || true)
[ "$cnt" = "5" ] || fail "README.md: the section has $cnt lines starting '### ', 5 expected"

# 3. the four command lines in a code block of '### The commands'; the skills still have these names
cmds=$(part '### The commands')
block=$(printf '%s\n' "$cmds" | awk '/^```/ { b = !b; next } b { print }')
for c in \
  'claude -p "/nightmill:next" --permission-mode manual' \
  'claude -p "/nightmill:next 112" --permission-mode manual' \
  'claude -p "/nightmill:fix 57" --permission-mode manual' \
  'claude -p "/nightmill:fix all" --permission-mode manual'; do
  printf '%s\n' "$block" | grep -xF -- "$c" >/dev/null || fail "README.md: '### The commands' has no code-block line: $c"
done
grep -xF 'name: next' "$root/skills/next/SKILL.md" >/dev/null || fail "skills/next/SKILL.md: no line 'name: next'"
grep -xF 'name: fix' "$root/skills/fix/SKILL.md" >/dev/null || fail "skills/fix/SKILL.md: no line 'name: fix'"
grep -E '^argument-hint:.*all' "$root/skills/fix/SKILL.md" >/dev/null || fail "skills/fix/SKILL.md: argument-hint has no 'all'"
grep -E '"name": *"nightmill"' "$root/.claude-plugin/plugin.json" >/dev/null || fail ".claude-plugin/plugin.json: name is not nightmill"

# 4. every claude -p line uses manual mode and none of the forbidden flags
while IFS= read -r line; do
  [ -n "$line" ] || continue
  contains "$line" '--permission-mode manual' || fail "README.md: a 'claude -p' line lacks --permission-mode manual: $line"
  for bad_flag in '--bare' '--dangerously-skip-permissions' '--permission-mode bypassPermissions' '--permission-mode auto' '--allowedTools'; do
    if contains "$line" "$bad_flag"; then fail "README.md: a 'claude -p' line contains $bad_flag: $line"; fi
  done
done <<EOF2
$(printf '%s\n' "$sec" | grep '^claude -p ' || true)
EOF2
if ! printf '%s\n' "$sec" | grep '^claude -p ' >/dev/null; then fail "README.md: the section has no line starting 'claude -p '"; fi
for w in '--bare' 'bypassPermissions' '--dangerously-skip-permissions' 'default' '--output-format json'; do
  contains "$flat" "$w" || fail "README.md: the section does not mention $w"
done

# 5. the settings a run needs
before=$(part '### Before the first run' | flatten)
# The README must contain the literal text ~/.claude.json; the tilde is not meant to expand.
# shellcheck disable=SC2088
for w in '**Permissions**' '**Deny rules**' '**Edit permission**' '**Run permissions**' '.claude/settings.json' '.claude/settings.local.json' \
  '(#the-edit-permission)' '(#the-run-permissions)' '(#the-deny-rules-and-the-guard)' '/nightmill:init' 'hasTrustDialogAccepted' \
  '~/.claude.json' 'this workspace has not been trusted' 'defaultMode' '.claude/'; do
  contains "$before" "$w" || fail "README.md: '### Before the first run' does not contain $w"
done
for h in '### The edit permission' '### The run permissions' '### The deny rules and the guard'; do
  grep -xF "$h" "$readme" >/dev/null || fail "README.md has no heading '$h'"
done

# 6. /init again, #213, the guard's limits, #164 and #165
contains "$before" '/init' || fail "README.md: '### Before the first run' does not contain /init"
contains "$before" "[#213](https://github.com/$repo/issues/213)" || fail "README.md: '### Before the first run' does not link #213"
contains "$flat" '(#what-is-enforced)' || fail "README.md: the section does not contain (#what-is-enforced)"
for n in 164 165; do
  contains "$flat" "[#$n](https://github.com/$repo/issues/$n)" || fail "README.md: the section does not link #$n"
done

# 7. several runs at once
several=$(part '### Several runs at once' | flatten)
contains "$several" "\`worktrees.slots\` (default $d_slots)" || fail "README.md: '### Several runs at once' lacks \`worktrees.slots\` (default $d_slots)"
if ! contains "$several" "\`parallel.maxAgents\`, default $d_agents" && ! contains "$several" "\`parallel.maxAgents\` (default $d_agents)"; then
  fail "README.md: '### Several runs at once' lacks \`parallel.maxAgents\` with default $d_agents"
fi
for w in 'WORKER_SLOTS' 'all <k> slots are busy' 'In progress' '/fix all' '(#changing-the-numbers-during-a-session)' '(#room-for-one-more-agent)' \
  "[#176](https://github.com/$repo/issues/176)"; do
  contains "$several" "$w" || fail "README.md: '### Several runs at once' does not contain $w"
done
grep -F 'slots are busy' "$root/scripts/slot.sh" >/dev/null || fail "scripts/slot.sh no longer contains 'slots are busy'"

# 8. watching a run
watching=$(part '### Watching a run' | flatten)
for w in 'claude -p "/nightmill:status"' '/nightmill:status' '**running**' '**stalled**' '(#what-a-slots-agent-is-doing)' \
  '(#watching-the-run-in-a-browser)' '(#watching-the-run-beside-the-chat)' "review.watchChecksMinutes\` (default $d_watch)" 'exit code'; do
  case "$w" in
    review.watchChecksMinutes*) contains "$watching" "$w" || contains "$watching" "review.watchChecksMinutes (default $d_watch)" || fail "README.md: '### Watching a run' lacks review.watchChecksMinutes (default $d_watch)" ;;
    *) contains "$watching" "$w" || fail "README.md: '### Watching a run' does not contain $w" ;;
  esac
done
for h in '### What a slot'"'"'s agent is doing' '### Watching the run in a browser' '### Watching the run beside the chat'; do
  grep -xF "$h" "$readme" >/dev/null || fail "README.md has no heading '$h'"
done

# 9. when a run is stopped
stopped=$(part '### When a run is stopped' | flatten)
for w in 'Ctrl+C' 'SIGTERM' '143' 'take-died' '-Abandon N' '--abandon N' 'In progress' 'Review' 'auto-merge' '**running**' '**stalled**' \
  "\`worktrees.stalledAfterMinutes\` (default $d_stalled)" '/nightmill:next <N>' 'Ready' "[#165](https://github.com/$repo/issues/165)"; do
  contains "$stopped" "$w" || fail "README.md: '### When a run is stopped' does not contain $w"
done
grep -F 'another run is working on it' "$root/skills/next/SKILL.md" >/dev/null || fail "skills/next/SKILL.md no longer contains 'another run is working on it'"
grep -F '`stalled` and `unknown` are resumed' "$root/skills/next/SKILL.md" >/dev/null || fail "skills/next/SKILL.md no longer contains '\`stalled\` and \`unknown\` are resumed'"

# 10. the cross-references
hl=$(grep '^- \*\*Headless runs:\*\*' "$readme" | head -1 || true)
if [ -z "$hl" ]; then
  fail "README.md has no line starting '- **Headless runs:**'"
else
  contains "$hl" '(#running-unattended)' || fail "README.md: the Headless runs bullet does not link (#running-unattended)"
  contains "$hl" '#160' || fail "README.md: the Headless runs bullet does not contain #160"
fi
secm=$(awk '/^## Security model$/ { s = 1; print; next } s && /^## / { exit } s { print }' "$readme" | flatten)
contains "$secm" '(#running-unattended)' || fail "README.md: the Security model section does not link (#running-unattended)"
if contains "$secm" 'is not described yet'; then fail "README.md: the Security model section still says 'is not described yet'"; fi

# 11. every issue link in the section has the same number twice and the right URL
links=$(printf '%s' "$flat" | grep -oE '\[#[0-9]+\]\([^)]*\)' || true)
while IFS= read -r l; do
  [ -n "$l" ] || continue
  a=${l#\[#}; a=${a%%\]*}
  want="[#$a](https://github.com/$repo/issues/$a)"
  [ "$l" = "$want" ] || fail "README.md: link $l should be $want"
done <<EOF3
$links
EOF3

[ "$bad" = 0 ] && echo "ok: running unattended is documented"
exit "$bad"
