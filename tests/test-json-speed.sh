#!/usr/bin/env bash
# tests/test-json-speed.sh - regression for #131: json.awk built a string one character at a time (out = out c),
# which is quadratic, so status.sh was slow on boards with long issue bodies. json_load must take time
# linear in the length of the strings, and must still read them back exactly (escapes among plain runs).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-json-speed.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

now_ms() {
  local t
  t=$(date +%s%N 2>/dev/null || true)
  case "${t}" in
    *N*|"") perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000' ;;
    *) echo $((t / 1000000)) ;;
  esac
}

# One repeating unit: a plain run with escapes (newline, quote, backslash) and a non-ASCII letter among it.
plain='The quick brown fox jumps over the lazy dog, 0123456789 - plain text. '
unit_json="${plain}"'\n\"\\é'
unit_text="${plain}"$'\n"\\é'

# make_file FILE REPEATS: 10 strings of REPEATS units, then a value after them.
make_file() {
  local file=$1 reps=$2 body="" i
  for ((i = 0; i < reps; i++)); do body="${body}${unit_json}"; done
  {
    printf '{\n'
    for ((i = 0; i < 10; i++)); do printf '  "body%s": "%s",\n' "${i}" "${body}"; done
    printf '  "after": "still here",\n  "number": 42\n}\n'
  } > "${file}"
}

small_reps=60
factor=12
large_reps=$((small_reps * factor))
make_file "${tmp}/small.json" "${small_reps}"
make_file "${tmp}/large.json" "${large_reps}"

echo "== json_load reads the long strings back exactly"
expected=""
for ((i = 0; i < large_reps; i++)); do expected="${expected}${unit_text}"; done
json_load "${tmp}/large.json" || fail "json_load failed on the large file"
got=$(json_get body9; printf x); got=${got%x}
[ "${got}" = "${expected}" ] || fail "body9 differs: expected ${#expected} chars, got ${#got}"
got=$(json_get body0; printf x); got=${got%x}
[ "${got}" = "${expected}" ] || fail "body0 differs: expected ${#expected} chars, got ${#got}"
[ "$(json_get after)" = "still here" ] || fail "the value after the long strings is lost"
[ "$(json_get number)" = "42" ] || fail "the number after the long strings is lost"

echo "== json_load time grows linearly with the string length"
t0=$(now_ms)
json_load "${tmp}/small.json" || fail "json_load failed on the small file"
t1=$(now_ms)
json_load "${tmp}/large.json" || fail "json_load failed on the large file"
t2=$(now_ms)
small_ms=$((t1 - t0))
large_ms=$((t2 - t1))
limit=$((small_ms * factor * 3 + 500))
echo "small ${small_ms} ms, large ${large_ms} ms (${factor}x longer strings), limit ${limit} ms"
if [ "${large_ms}" -gt "${limit}" ]; then
  fail "time is not linear: ${factor}x longer strings took ${large_ms} ms, more than ${limit} ms"
fi
if [ "${large_ms}" -gt 10000 ]; then
  fail "10 strings of $((large_reps * ${#unit_text})) chars took ${large_ms} ms, above the 10000 ms ceiling"
fi

if [ "${failures}" -gt 0 ]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi
echo "OK"
