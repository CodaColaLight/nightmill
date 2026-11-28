#!/usr/bin/env bash
# tests/test-unattended-docs.sh - the README's "Running unattended" (iteration 49, #160) gives the headless commands
# with their flags and the keys and defaults a run depends on. Only the contracts are checked (a command and its flags,
# a config key and its schema default, a file name, a line a skill parses); the headings, their order and the
# sentences are the manual check's (iteration 73). The whole README is searched.
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
flat=$(tr '\n' ' ' < "$readme" | sed -E 's/ +/ /g')

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

# 1. the four command lines; their --max-turns are the schema's limits.turnsPerRole.session (200) and that times
# limits.issuesPerRun (2000, iteration 53); the skills and the plugin still have these names
cmd_lines=$(grep '^claude -p ' "$readme" || true)
[ -n "$cmd_lines" ] || fail "README.md has no line starting 'claude -p '"
d_session=$(awk '/"turnsPerRole": \{/ { t = 1 } t && /"session": \{/ { s = 1 } s && /"default":/ { sub(/.*"default": */, ""); sub(/[^0-9].*/, ""); print; exit }' "$schema")
d_issues=$(awk '/"issuesPerRun": \{/ { s = 1 } s && /"default":/ { sub(/.*"default": */, ""); sub(/[^0-9].*/, ""); print; exit }' "$schema")
case "$d_session$d_issues" in ''|*[!0-9]*) fail "schema/nightmill.schema.json: limits.turnsPerRole.session or limits.issuesPerRun has no numeric default" ;; esac
if [ -n "$d_session" ] && [ -n "$d_issues" ]; then
  [ "$d_session" = 200 ] || fail "schema: limits.turnsPerRole.session default is $d_session, 200 expected (the README commands use --max-turns 200)"
  [ $((d_session * d_issues)) = 2000 ] || fail "schema: limits.turnsPerRole.session times limits.issuesPerRun is $((d_session * d_issues)), 2000 expected (the README's /nightmill:fix all uses --max-turns 2000)"
fi
for pair in '/nightmill:next=200' '/nightmill:next 112=200' '/nightmill:fix 57=200' '/nightmill:fix all=2000'; do
  cmd=${pair%=*}; turns=${pair##*=}
  line=$(printf '%s\n' "$cmd_lines" | grep -F -- "claude -p \"$cmd\" " | head -1 || true)
  if [ -z "$line" ]; then fail "README.md has no line for claude -p \"$cmd\""; continue; fi
  case "$line " in *" --max-turns $turns "*) ;; *) fail "README.md: the line for $cmd has no '--max-turns $turns': $line" ;; esac
done
for w in 'limits.turnsPerRole.session' 'limits.issuesPerRun' '--max-budget-usd'; do
  contains "$flat" "$w" || fail "README.md does not mention $w"
done
grep -xF 'name: next' "$root/skills/next/SKILL.md" >/dev/null || fail "skills/next/SKILL.md: no line 'name: next'"
grep -xF 'name: fix' "$root/skills/fix/SKILL.md" >/dev/null || fail "skills/fix/SKILL.md: no line 'name: fix'"
grep -E '^argument-hint:.*all' "$root/skills/fix/SKILL.md" >/dev/null || fail "skills/fix/SKILL.md: argument-hint has no 'all'"
grep -E '"name": *"nightmill"' "$root/.claude-plugin/plugin.json" >/dev/null || fail ".claude-plugin/plugin.json: name is not nightmill"

# 2. every claude -p line uses manual mode and none of the forbidden flags
while IFS= read -r line; do
  [ -n "$line" ] || continue
  contains "$line" '--permission-mode manual' || fail "README.md: a 'claude -p' line lacks --permission-mode manual: $line"
  for bad_flag in '--bare' '--dangerously-skip-permissions' '--permission-mode bypassPermissions' '--permission-mode auto' '--allowedTools'; do
    if contains "$line" "$bad_flag"; then fail "README.md: a 'claude -p' line contains $bad_flag: $line"; fi
  done
done <<EOF2
$cmd_lines
EOF2
for w in '--bare' 'bypassPermissions' '--dangerously-skip-permissions' '--output-format json'; do
  contains "$flat" "$w" || fail "README.md does not mention $w"
done

# 3. the settings a run needs: the files, the keys and the command that writes them
# The README must contain the literal text ~/.claude.json; the tilde is not meant to expand.
# shellcheck disable=SC2088
for w in '.claude/settings.json' '.claude/settings.local.json' '/nightmill:init' 'hasTrustDialogAccepted' \
  '~/.claude.json' 'defaultMode' '.claude/'; do
  contains "$flat" "$w" || fail "README.md does not contain $w"
done

# 4. several runs at once: the keys with their schema defaults, the variable, the slot script's line /fix reads
contains "$flat" "\`worktrees.slots\` (default $d_slots)" || fail "README.md lacks \`worktrees.slots\` (default $d_slots)"
if ! contains "$flat" "\`parallel.maxAgents\`, default $d_agents" && ! contains "$flat" "\`parallel.maxAgents\` (default $d_agents)"; then
  fail "README.md lacks \`parallel.maxAgents\` with default $d_agents"
fi
for w in 'WORKER_SLOTS' 'all <k> slots are busy' '/fix all'; do
  contains "$flat" "$w" || fail "README.md does not contain $w"
done
grep -F 'slots are busy' "$root/scripts/slot.sh" >/dev/null || fail "scripts/slot.sh no longer contains 'slots are busy'"

# 5. watching a run: the commands and the key with its schema default
for w in 'claude -p "/nightmill:status"' '/nightmill:status'; do
  contains "$flat" "$w" || fail "README.md does not contain $w"
done
contains "$flat" "review.watchChecksMinutes\` (default $d_watch)" || contains "$flat" "review.watchChecksMinutes (default $d_watch)" ||
  fail "README.md lacks review.watchChecksMinutes (default $d_watch)"

# 6. a stopped run: the slot step /next reads, the command that frees a slot, the key with its schema default, the
# statuses (the schema's defaults of board.statuses) and the command that resumes
for w in 'take-died' '--abandon N' "\`worktrees.stalledAfterMinutes\` (default $d_stalled)" '/nightmill:next <N>' \
  'In progress' 'Review' 'Ready'; do
  contains "$flat" "$w" || fail "README.md does not contain $w"
done

[ "$bad" = 0 ] && echo "ok: running unattended is documented"
exit "$bad"
