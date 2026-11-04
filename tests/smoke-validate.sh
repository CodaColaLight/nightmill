#!/usr/bin/env bash
# tests/smoke-validate.sh - scripts/validate-config.sh: the example is clean, every kind of mistake is reported
# on the line that names the key, unknown keys are warnings (errors with --strict), findings print sorted, enum
# and closed objects work with a schema of their own, usage errors exit 2, this repository's own config passes,
# and the lint notices a schema keyword the validator does not support. Same cases as smoke-validate.ps1.
# Needs bash and awk, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
V="$here/scripts/validate-config.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

ex=$(cat "$here/templates/nightmill.example.json")

# edit <text> <old> <new>: replace a piece of the text; the piece has to exist
edit() {
  case "$1" in *"$2"*) ;; *) fail "fixture: '$2' is not in the example" ;; esac
  printf '%s' "${1/"$2"/$3}"
}

i=0
# check <name> <config text> <expected exit code> <extra args, space separated or empty> <expected lines...>
check() {
  local name=$1 text=$2 code=$3 extra=$4; shift 4
  i=$((i + 1))
  local f="$tmp/case$i.json" out rc
  printf '%s\n' "$text" > "$f"
  set +e
  # shellcheck disable=SC2086
  out=$(bash "$V" $extra "$f" 2>&1)
  rc=$?
  set -e
  [ "$rc" = "$code" ] || fail "$name: expected exit code $code, got $rc: $out"
  local l
  for l in "$@"; do
    printf '%s\n' "$out" | grep -qxF -- "$l" || fail "$name: missing the line '$l' in: $out"
  done
}

echo "== the example is clean"
check "example" "$ex" 0 "" "0 errors, 0 warnings"
check "example strict" "$ex" 0 "--strict" "0 errors, 0 warnings"

echo "== errors name the key"
check "owner missing" "$(edit "$ex" '"owner": "acme", ' '')" 1 "" "error: github.owner: required key is missing" "1 error, 0 warnings"
check "slots a string" "$(edit "$ex" '"slots": 2' '"slots": "two"')" 1 "" "error: worktrees.slots: expected integer, got string"
check "project number 0" "$(edit "$ex" '"projectNumber": 1' '"projectNumber": 0')" 1 "" "error: github.projectNumber: must be at least 1, got 0"
check "areas empty" "$(edit "$ex" '"areas": ["core", "api", "ui", "infra", "docs"]' '"areas": []')" 1 "" "error: areas: needs at least 1 items, got 0"
check "areas item a number" "$(edit "$ex" '["core", "api", ' '["core", 3, ')" 1 "" "error: areas[1]: expected string, got integer"
check "port a string" "$(edit "$ex" '"server": 8100' '"server": "x"')" 1 "" "error: worktrees.ports.server: expected integer, got string"
check "maintainer missing" "$(edit "$ex" '"maintainer": { "name": "Alex" },' '')" 1 "" "error: maintainer: required key is missing"
check "check a boolean" "$(edit "$ex" '"check": "bash scripts/check.sh"' '"check": true')" 1 "" "error: verification.check: expected string, got boolean"
check "root an array" "[1]" 1 "" "error: .: expected object, got array"
check "trailing comma" '{"a": 1,}' 1 "" "error: .: not valid JSON" "1 error, 0 warnings"

echo "== several findings print sorted, the summary counts them"
multi=$(edit "$(edit "$(edit "$ex" '"owner": "acme", ' '')" '"slots": 2' '"slots": "two"')" '"github": {' '"worktree": 1, "github": {')
printf '%s\n' "$multi" > "$tmp/multi.json"
set +e; out=$(bash "$V" "$tmp/multi.json" 2>&1); rc=$?; set -e
[ "$rc" = 1 ] || fail "several findings: expected exit code 1, got $rc"
want=$'error: github.owner: required key is missing\nwarning: worktree: unknown key (did you mean "worktrees"?)\nerror: worktrees.slots: expected integer, got string\n2 errors, 1 warning'
got=$(printf '%s\n' "$out" | tail -n +2)
[ "$got" = "$want" ] || fail "several findings: wrong lines or order. Got:
$got
Wanted:
$want"

echo "== unknown keys are warnings"
typo=$(edit "$ex" '"github": {' '"worktree": 2, "github": {')
check "typo" "$typo" 0 "" 'warning: worktree: unknown key (did you mean "worktrees"?)' "0 errors, 1 warning"
check "typo strict" "$typo" 1 "--strict" 'warning: worktree: unknown key (did you mean "worktrees"?)'
check "unknown nested key" "$(edit "$ex" '"owner": "acme",' '"owner": "acme", "org": "x",')" 0 "" "warning: github.org: unknown key"

echo "== enum and closed objects, with a schema of their own"
mini="$tmp/mini.schema.json"
printf '%s\n' '{"type":"object","additionalProperties":false,"required":["mode"],"properties":{"mode":{"type":"string","enum":["fast","slow"]}}}' > "$mini"
printf '%s\n' '{"mode":"medium","extra":1}' > "$tmp/mini.json"
set +e; out=$(bash "$V" --schema "$mini" "$tmp/mini.json" 2>&1); rc=$?; set -e
[ "$rc" = 1 ] || fail "enum: expected exit code 1, got $rc"
for l in 'error: extra: unknown key is not allowed' 'error: mode: must be one of: fast, slow, got "medium"' '2 errors, 0 warnings'; do
  printf '%s\n' "$out" | grep -qxF -- "$l" || fail "enum: missing the line '$l' in: $out"
done
printf '%s\n' '{"mode":"fast"}' > "$tmp/mini.json"
bash "$V" --schema "$mini" "$tmp/mini.json" >/dev/null || fail "enum: a valid value was refused"

echo "== usage errors exit 2"
set +e; err=$(bash "$V" "$tmp/does-not-exist.json" 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" = 2 ] || fail "missing file: expected exit code 2, got $rc"
case "$err" in *"does-not-exist.json"*) ;; *) fail "missing file: the message does not name the path: $err" ;; esac
set +e; bash "$V" --no-such-option "$tmp/case1.json" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "unknown option: expected exit code 2, got $rc"

echo "== this repository's own config passes with --strict"
bash "$V" --strict "$here/.claude/nightmill.json" >/dev/null || fail "the repository's own config does not validate"

echo "== the lint notices a schema keyword the validator does not support"
cp_dir="$tmp/repocopy"; mkdir -p "$cp_dir"
( cd "$here" && tar -cf - --exclude=.git . ) | ( cd "$cp_dir" && tar -xf - )
sed 's/^\(  "title":\)/  "pattern": "x",\n\1/' "$cp_dir/schema/nightmill.schema.json" > "$cp_dir/s.tmp" && mv "$cp_dir/s.tmp" "$cp_dir/schema/nightmill.schema.json"
if out=$(cd "$cp_dir" && bash tests/lint.sh 2>&1); then fail "the lint accepted a schema with a pattern keyword"; fi
case "$out" in *pattern*) ;; *) fail "the lint did not name the keyword: $out" ;; esac

echo "VALIDATE OK"
