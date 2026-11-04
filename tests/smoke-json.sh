#!/usr/bin/env bash
# tests/smoke-json.sh - scripts/lib/json.awk and json.sh, the JSON reader of the bash scripts: the exact
# records for a fixture, the library functions, the errors for invalid JSON, and - only when jq is installed
# (CI) - a cross-check that every value the scripts read equals what jq reads. Needs no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
T=$'\t'

eq() { # eq <name> <expected> <actual>
  [ "$2" = "$3" ] || fail "$1: expected [$2], got [$3]"
}

flat() { JSON_MODE=flat JSON_FILE="$1" LC_ALL=C awk -f "$here/scripts/lib/json.awk"; }

cat > "$tmp/fixture.json" <<'EOF'
{
  "s": "hello",
  "q": "say \"hi\" \\ back \/ slash",
  "nl": "line1\nline2\ttabbed\r",
  "u": "café 😀 — dash",
  "n0": 0, "nneg": -1, "nfrac": 2.5, "nexp": 1e3, "nnegexp": -0.5E-2,
  "t": true, "f": false, "z": null,
  "e1": {}, "e2": [],
  "arr": [1, "two", [3, 4], {"k": "v"}],
  "obj": {"a": {"b": {"c": "deep"}}}
}
EOF

echo "== parser: the exact records for a fixture"
{
  printf '%s\n' "${T}object${T}16"
  printf '%s\n' "s${T}string${T}hello"
  printf '%s\n' 'q'"${T}string${T}"'say "hi" \\ back / slash'
  printf '%s\n' 'nl'"${T}string${T}"'line1\nline2\ttabbed\r'
  printf '%s\n' "u${T}string${T}café 😀 — dash"
  printf '%s\n' "n0${T}number${T}0" "nneg${T}number${T}-1" "nfrac${T}number${T}2.5" "nexp${T}number${T}1e3" "nnegexp${T}number${T}-0.5E-2"
  printf '%s\n' "t${T}boolean${T}true" "f${T}boolean${T}false" "z${T}null${T}"
  printf '%s\n' "e1${T}object${T}0" "e2${T}array${T}0"
  printf '%s\n' "arr${T}array${T}4" "arr[0]${T}number${T}1" "arr[1]${T}string${T}two" "arr[2]${T}array${T}2" "arr[2][0]${T}number${T}3" "arr[2][1]${T}number${T}4" "arr[3]${T}object${T}1" "arr[3].k${T}string${T}v"
  printf '%s\n' "obj${T}object${T}1" "obj.a${T}object${T}1" "obj.a.b${T}object${T}1" "obj.a.b.c${T}string${T}deep"
} > "$tmp/expected.flat"
flat "$tmp/fixture.json" > "$tmp/got.flat" || fail "the fixture did not parse"
if ! cmp -s "$tmp/expected.flat" "$tmp/got.flat"; then
  diff "$tmp/expected.flat" "$tmp/got.flat" >&2 || true
  fail "the flat records differ from the expected ones"
fi

echo "== library"
json_load "$tmp/fixture.json" || fail "json_load failed"
eq "json_get string" "hello" "$(json_get s)"
eq "json_get escapes" 'say "hi" \ back / slash' "$(json_get q)"
eq "json_get newline, tab, carriage return" $'line1\nline2\ttabbed\r' "$(json_get nl)"
eq "json_get unicode" "café 😀 — dash" "$(json_get u)"
eq "json_get number" "2.5" "$(json_get nfrac)"
eq "json_get boolean" "true" "$(json_get t)"
eq "json_get null gives the default" "dflt" "$(json_get z dflt)"
eq "json_get null without default" "" "$(json_get z)"
eq "json_get an object gives the default" "d" "$(json_get e1 d)"
eq "json_get a missing path gives the default" "d" "$(json_get nope.x d)"
eq "json_get nested array item" "4" "$(json_get 'arr[2][1]')"
eq "json_get deep" "deep" "$(json_get obj.a.b.c)"
eq "json_len array" "4" "$(json_len arr)"
eq "json_len nested array" "2" "$(json_len 'arr[2]')"
eq "json_len empty object" "0" "$(json_len e1)"
eq "json_len empty array" "0" "$(json_len e2)"
eq "json_len missing" "0" "$(json_len nothing)"
eq "json_len object" "1" "$(json_len obj.a.b)"
eq "json_keys root, in file order" "s q nl u n0 nneg nfrac nexp nnegexp t f z e1 e2 arr obj" "$(json_keys '' | tr '\n' ' ' | sed 's/ $//')"
eq "json_keys nested" "b" "$(json_keys obj.a)"
eq "json_keys of an object in an array" "k" "$(json_keys 'arr[3]')"
json_has z || fail "json_has: a null value exists"
json_has 'arr[2][1]' || fail "json_has: an array item exists"
if json_has nothing; then fail "json_has: a missing path does not exist"; fi
eq "json_quote" '"a \"q\" \\ b\nc\td\u0001 — e"' "$(json_quote $'a "q" \\ b\nc\td\x01 — e')"
eq "json_quote plain" '"plain"' "$(json_quote plain)"
printf '{\n  "slot": 3,\n  "branch": "feat/x",\n  "since": "2026-11-05T01:02:03"\n}\n' > "$tmp/marker.expected"
json_marker 3 feat/x 2026-11-05T01:02:03 > "$tmp/marker.got"
cmp -s "$tmp/marker.expected" "$tmp/marker.got" || fail "json_marker is not byte for byte the marker format"
json_load "$tmp/marker.got" || fail "the marker does not parse"
eq "marker slot" "3" "$(json_get slot)"
eq "marker branch" "feat/x" "$(json_get branch)"
eq "marker since" "2026-11-05T01:02:03" "$(json_get since)"
json_load "$here/templates/nightmill.example.json" || fail "the example config does not parse"
eq 'a key that starts with a dollar sign' "https://raw.githubusercontent.com/CodaColaLight/nightmill/main/schema/nightmill.schema.json" "$(json_get '$schema')"

echo "== errors: invalid JSON is refused with the file and the reason"
bad() { # bad <name> <text> <reason fragment>
  local f="$tmp/bad-$1.json" err
  printf '%s' "$2" > "$f"
  if err=$(json_check "$f" 2>&1); then fail "$1: invalid JSON was accepted"; fi
  case "$err" in *"json: $f: "*"$3"*) ;; *) fail "$1: wrong message (wanted '$3'): $err" ;; esac
  if json_load "$f" 2>/dev/null; then fail "$1: json_load accepted invalid JSON"; fi
}
bad "trailing-comma" '{"a": 1,}' "expected a string key"
bad "trailing-comma-array" '[1,]' "unexpected character"
bad "single-quotes" "{'a': 1}" "expected a string key"
bad "comment" '{"a": 1 /* c */}' "expected ',' or '}'"
bad "leading-zero" '{"a": 01}' "leading zero"
bad "plus" '{"a": +1}' "unexpected character"
# a file always ends with a newline when read, so an unterminated string stops at that control character
bad "unterminated-string" '{"a": "x' "control character in string"
bad "unterminated-object" '{"a": 1' "expected ',' or '}'"
bad "unterminated-array" '[1, 2' "expected ',' or ']'"
bad "text-after" '{"a": 1} x' "unexpected text after the value"
bad "empty-file" '' "unexpected end of input"
bad "raw-tab" "{\"a\": \"x${T}y\"}" "control character in string"
bad "bad-escape" '{"a": "\x"}' "bad escape"
bad "bad-unicode-escape" '{"a": "\u12"}' "bad \\u escape"
bad "lone-surrogate" '{"a": "\ud83d"}' "lone surrogate"
bad "nul-escape" '{"a": "\u0000"}' "not supported"
bad "missing-colon" '{"a" 1}' "expected ':'"
bad "bad-literal" '{"a": tru}' "unexpected character"
deep65=$(printf '[%.0s' $(seq 1 65))$(printf ']%.0s' $(seq 1 65))
bad "nesting-65" "$deep65" "nesting too deep"
deep64=$(printf '[%.0s' $(seq 1 64))$(printf ']%.0s' $(seq 1 64))
printf '%s' "$deep64" > "$tmp/deep64.json"
json_check "$tmp/deep64.json" || fail "nesting of 64 levels was refused"
if json_check "$tmp/does-not-exist.json" 2>/dev/null; then fail "a missing file was accepted"; fi

echo "== cross-check against jq"
if ! command -v jq >/dev/null 2>&1; then
  echo "(jq not installed, cross-check skipped)"
else
  cfg="$here/templates/nightmill.example.json"
  json_load "$cfg"
  for p in git.baseBranch worktrees.root worktrees.slots verification.check verification.manualCheckText \
           labels.epic labels.story labels.bug labels.needsSpec worktrees.warmup[0].dir worktrees.warmup[0].command \
           worktrees.warmup[0].lockfile worktrees.warmup[5].dir worktrees.runHints[0] worktrees.runHints[1] \
           areas[0] areas[4] invariants[0] invariants[1] worktrees.ports.server worktrees.ports.client \
           github.projectNumber github.owner maintainer.name verification.benchRule labels.nothing worktrees.nothing.x; do
    eq "jq cross-check json_get $p" "$(jq -r ".$p // empty" "$cfg")" "$(json_get "$p")"
  done
  for p in areas invariants worktrees.warmup worktrees.runHints worktrees.ports nothing; do
    eq "jq cross-check json_len $p" "$(jq -r ".$p // [] | length" "$cfg")" "$(json_len "$p")"
  done
  for p in worktrees worktrees.ports labels github; do
    eq "jq cross-check json_keys $p" "$(jq -r ".$p | keys_unsorted[]" "$cfg")" "$(json_keys "$p")"
  done
  eq "jq cross-check json_keys of the root" "$(jq -r 'keys_unsorted[]' "$cfg")" "$(json_keys '')"
  json_load "$tmp/fixture.json"
  for k in s q nl u nfrac t; do
    eq "jq cross-check fixture $k" "$(jq -r ".$k // empty" "$tmp/fixture.json")" "$(json_get "$k")"
  done
  for v in 'plain' 'a "q" \ b' $'tab\there' 'é — 😀' 'back\slash' 'both "x" and \y'; do
    eq "jq cross-check json_quote [$v]" "$(jq -nr --arg s "$v" '$s | tojson')" "$(json_quote "$v")"
  done
fi

echo "JSON OK"
