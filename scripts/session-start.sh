#!/usr/bin/env bash
# scripts/session-start.sh - the SessionStart hook (bash). Where nightmill is enabled but the project has
# no .claude/nightmill.json, prints one line that makes Claude offer /nightmill:init. Silent when the
# config exists, when NIGHTMILL_HINT=off (any case), or when the project directory does not exist.
# Always exits 0: a hook must never break a session. Needs nothing but bash.
#   CLAUDE_PROJECT_DIR   the project root (set by Claude Code); the current directory when unset
#   NIGHTMILL_HINT=off   never print the line (for plugins enabled at user scope)
case "${NIGHTMILL_HINT:-}" in [Oo][Ff][Ff]) exit 0 ;; esac

root=${CLAUDE_PROJECT_DIR:-$PWD}
[ -d "$root" ] || exit 0
[ -f "$root/.claude/nightmill.json" ] && exit 0

printf '%s\n' 'nightmill is enabled in this project but not set up (no .claude/nightmill.json). Offer the user to run /nightmill:init, a short install chat that creates the board, labels, config and issue forms. Mention it once; do not run it unless the user agrees.'
exit 0
