#!/usr/bin/env bash
# tests/smoke-hook.sh - scripts/session-start.sh (the SessionStart hook): one line when the project has
# no .claude/nightmill.json, nothing when it has one, nothing when NIGHTMILL_HINT=off, exit code 0 always.
# Also runs the command hooks/hooks.json wires. Needs no jq and no network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
S="$here/scripts/session-start.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bare" "$tmp/cfg/.claude"
echo '{}' > "$tmp/cfg/.claude/nightmill.json"

# expect_hint <name> <output>: exactly one non-empty line that names /nightmill:init
expect_hint() {
  local n
  n=$(printf '%s\n' "$2" | grep -c . || true)
  [ "$n" = 1 ] || fail "$1: expected one line, got $n: $2"
  case "$2" in *"/nightmill:init"*) ;; *) fail "$1: the line does not name /nightmill:init: $2";; esac
}
expect_silent() { [ -z "$2" ] || fail "$1: expected no output, got: $2"; }

echo "== no config: one line"
out=$(CLAUDE_PROJECT_DIR="$tmp/bare" bash "$S") || fail "exit code $? with no config"
expect_hint "no config" "$out"

echo "== config present: silent"
out=$(CLAUDE_PROJECT_DIR="$tmp/cfg" bash "$S") || fail "exit code $? with config"
expect_silent "config present" "$out"

echo "== NIGHTMILL_HINT=off (any case): silent"
for v in off Off OFF; do
  out=$(CLAUDE_PROJECT_DIR="$tmp/bare" NIGHTMILL_HINT=$v bash "$S") || fail "exit code $? with NIGHTMILL_HINT=$v"
  expect_silent "NIGHTMILL_HINT=$v" "$out"
done
out=$(CLAUDE_PROJECT_DIR="$tmp/bare" NIGHTMILL_HINT=on bash "$S") || fail "exit code $? with NIGHTMILL_HINT=on"
expect_hint "NIGHTMILL_HINT=on" "$out"

echo "== CLAUDE_PROJECT_DIR unset: the current directory is used"
out=$(cd "$tmp/bare" && env -u CLAUDE_PROJECT_DIR bash "$S") || fail "exit code $? in the bare directory"
expect_hint "cwd without config" "$out"
out=$(cd "$tmp/cfg" && env -u CLAUDE_PROJECT_DIR bash "$S") || fail "exit code $? in the configured directory"
expect_silent "cwd with config" "$out"

echo "== a directory that does not exist: exit 0, no output"
out=$(CLAUDE_PROJECT_DIR="$tmp/does-not-exist" bash "$S") || fail "exit code $? for a missing directory"
expect_silent "missing directory" "$out"

echo "== the command hooks/hooks.json wires, run by bash"
cmd=$(grep '"command":' "$here/hooks/hooks.json" | sed 's/^[^:]*: *"//; s/",* *$//; s/\\"/"/g')
cmd=${cmd//'${CLAUDE_PLUGIN_ROOT}'/$here}
out=$(CLAUDE_PROJECT_DIR="$tmp/bare" bash -c "$cmd") || fail "hooks.json command: exit code $? with no config"
expect_hint "hooks.json command, no config" "$out"
out=$(CLAUDE_PROJECT_DIR="$tmp/cfg" bash -c "$cmd") || fail "hooks.json command: exit code $? with config"
expect_silent "hooks.json command, config present" "$out"

echo "HOOK OK"
