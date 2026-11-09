#!/usr/bin/env bash
# tests/test-json-bom.sh - regression for #132: a UTF-8 byte order mark at the start of .claude/nightmill.json
# (Windows PowerShell 5.1 writes one) must not make the bash scripts reject the file; the PowerShell twins accept it.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

printf '\357\273\277' > "$tmp/bom.json"
cat "$here/templates/nightmill.example.json" >> "$tmp/bom.json"
[ "$(head -c 3 "$tmp/bom.json" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] || fail "fixture has no BOM"

echo "== validate-config.sh accepts a config with a BOM"
rc=0
out=$(bash "$here/scripts/validate-config.sh" "$tmp/bom.json" 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "validate-config.sh exit $rc on a BOM config: $out"
case "$out" in *"not valid JSON"*) fail "BOM config reported as not valid JSON: $out" ;; esac

echo "== json_load and json_check accept a BOM and read the same values as without"
json_check "$tmp/bom.json" || fail "json_check rejected a BOM file"
json_load "$tmp/bom.json" || fail "json_load rejected a BOM file"
with=$JSON_FLAT
json_load "$here/templates/nightmill.example.json"
[ "$with" = "$JSON_FLAT" ] || fail "records differ with a BOM"

echo "== a small object with a BOM"
printf '\357\273\277{"a": "b"}\n' > "$tmp/small.json"
json_load "$tmp/small.json" || fail "json_load rejected a BOM object"
[ "$(json_get a)" = "b" ] || fail "value after BOM not read"

echo "ok"
