#!/usr/bin/env bash
# shellcheck disable=SC2034
# scripts/lib/baseconfig.sh - the configuration that governs a run: .claude/nightmill.json on the base branch, not the
# working tree's file (iteration 48, #111). Source it after lib/json.sh. Bash twin of lib/baseconfig.ps1.
#
#   base_config <main checkout>
#
# The rule (the workflow skill's **The configuration**):
#   1. With refs/remotes/origin/HEAD (origin/<X>), the base ref is origin/HEAD; no pull request can change it.
#   2. Without it, but with a remote-tracking branch of origin: stop (run git remote set-head origin --auto once).
#      With no remote-tracking branch at all (no origin, never fetched): the working tree's file, with a note.
#   3. git show origin/HEAD:.claude/nightmill.json; when the file is not on that branch: the working tree's file, with
#      a note. Text that is not valid JSON stops.
#   4. When git.baseBranch (<B>, default main) of that configuration is not <X>: git show origin/<B>:... instead, and
#      a stop when that fails. git.baseBranch of that second file is not followed.
#   5. No fetch: the last fetched state is read.
# Leaves:
#   base_cfg_file   the file to read: a temporary file made with mktemp (base_cfg_tmp, the caller removes it) or, after
#                   a fallback, the working tree's path (which may not exist: the caller says "no <path>")
#   base_cfg_tmp    the temporary file, "" after a fallback
#   base_cfg_from   where it came from: origin/HEAD:.claude/nightmill.json, origin/<B>:.claude/nightmill.json, or the
#                   working tree's path
#   base_cfg_note   the fallback's line ("" when there was none); the caller prints it on standard error
#   base_cfg_stop   the stop line; base_config then returns 1
# JSON_FLAT is left as it is after the function's own reads; the caller loads base_cfg_file itself.

base_config() {
  local m=$1 c=.claude/nightmill.json head x b ref
  base_cfg_file="$m/$c"; base_cfg_tmp=""; base_cfg_from="$m/$c"; base_cfg_note=""; base_cfg_stop=""
  head=$(git -C "$m" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || head=""
  if [ -z "$head" ]; then
    if [ -n "$(git -C "$m" for-each-ref --count=1 refs/remotes/origin 2>/dev/null)" ]; then
      base_cfg_stop="origin/HEAD is not set, so the base branch's configuration cannot be found; run git remote set-head origin --auto once"
      return 1
    fi
    base_cfg_note="nightmill: no branch of origin is known; the configuration is read from the working tree."
    return 0
  fi
  base_cfg_tmp=$(mktemp "${TMPDIR:-/tmp}/nightmill-baseconfig.XXXXXX") || { base_cfg_stop="cannot make a temporary file"; return 1; }
  if ! _base_config_show "$m" "origin/HEAD:$c" > "$base_cfg_tmp" 2>/dev/null; then
    rm -f "$base_cfg_tmp"; base_cfg_tmp=""
    base_cfg_note="nightmill: origin/HEAD has no .claude/nightmill.json; the configuration is read from the working tree."
    return 0
  fi
  ref=origin/HEAD
  _base_config_json "$ref" || return 1
  b=$(json_get git.baseBranch); b=${b:-main}
  x=${head#origin/}
  if [ "$x" != "$b" ]; then
    ref="origin/$b"
    if ! _base_config_show "$m" "$ref:$c" > "$base_cfg_tmp" 2>/dev/null; then
      rm -f "$base_cfg_tmp"; base_cfg_tmp=""
      base_cfg_stop="origin/$b has no .claude/nightmill.json (git.baseBranch of the configuration on origin/HEAD)"
      return 1
    fi
    _base_config_json "$ref" || return 1
  fi
  base_cfg_file=$base_cfg_tmp
  base_cfg_from="$ref:$c"
  return 0
}

# _base_config_show <checkout> <ref>:<path>: git show with Git Bash's path conversion off, which otherwise takes
# <ref>:<path> for a path list and rewrites it (#300). The conversion stays on for the checkout's path (a /c/... or
# /tmp/... path that git.exe does not understand unconverted), so the call changes into it instead of using git -C.
_base_config_show() {
  (cd "$1" && MSYS_NO_PATHCONV=1 git show "$2")
}

# _base_config_json <ref>: loads base_cfg_tmp; a text that is not valid JSON is a stop
_base_config_json() {
  local err
  if ! err=$(json_load "$base_cfg_tmp" 2>&1); then
    err=${err#"json: $base_cfg_tmp: "}
    rm -f "$base_cfg_tmp"; base_cfg_tmp=""
    base_cfg_stop="the configuration on $1 is not valid JSON: $err"
    return 1
  fi
  json_load "$base_cfg_tmp"
}
