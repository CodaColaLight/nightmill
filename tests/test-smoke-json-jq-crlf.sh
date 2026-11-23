#!/usr/bin/env bash
# tests/test-smoke-json-jq-crlf.sh - regression for #372: tests/smoke-json.sh failed in Git Bash on Windows at
# "cross-check against jq" (json_keys worktrees: the two lists print the same names). A native jq.exe ends the
# lines it prints with CRLF, so the expected list carried a carriage return the parser's list does not.
# This test puts a stand-in jq (the fixture tests/fixtures/smoke-json-crlf/jq, a file named like the tool it stands
# for) on PATH that prints the key lists like jq.exe does (CRLF line ends, unless -b / --binary is given, as jq.exe
# documents) and answers the other calls with plain LF; smoke-json.sh must still pass, and must really have run the
# cross-check. The tool is never named outside a comment here: the lint lets only tests/smoke-json.sh call it.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-test-smoke-json-crlf.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin"
cp "$here"/tests/fixtures/smoke-json-crlf/* "$tmp/bin/"
chmod +x "$tmp"/bin/*
standin=("$tmp"/bin/*)
[ "${#standin[@]}" = 1 ] || fail "the fixture directory holds ${#standin[@]} files, expected the one stand-in"
export NIGHTMILL_ROOT="$here"

echo "== the stand-in prints CRLF line ends for the key lists"
cfg="$here/templates/nightmill.example.json"
n=$("${standin[0]}" -r '.worktrees | keys_unsorted[]' "$cfg" | tr -cd '\r' | wc -c | tr -d ' ')
[ "$n" -gt 1 ] || fail "the stand-in prints no CRLF ($n carriage returns)"
n=$("${standin[0]}" -b -r '.worktrees | keys_unsorted[]' "$cfg" | tr -cd '\r' | wc -c | tr -d ' ')
[ "$n" = 0 ] || fail "the stand-in printed CR with -b"

echo "== smoke-json.sh passes when the tool prints CRLF line ends"
rc=0
out=$(PATH="$tmp/bin:$PATH" bash "$here/tests/smoke-json.sh" 2>&1) || rc=$?
case "$out" in *"cross-check skipped"*) fail "the cross-check was skipped, the stand-in was not found: $out" ;; esac
[ "$rc" = 0 ] || fail "smoke-json.sh exit $rc with a CRLF tool: $out"
case "$out" in *"JSON OK"*) ;; *) fail "smoke-json.sh did not end with JSON OK: $out" ;; esac

echo "ok"
