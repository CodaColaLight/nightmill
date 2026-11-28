#!/usr/bin/env bash
# Tests for #341 (iteration 63): /fix has a fast lane for low-risk bugs. The key review.fastLane names the priorities
# whose bugs start in it and the paths a fix may change; in the lane one fixer writes the regression test and the fix,
# the affected check runs and the pull request opens without the tester and the code review; a fix that changes a path
# outside the lane's paths or in parallel.hotFiles, needs a story trigger or is partial leaves the lane and the long way
# starts from the tester; the pull request says which lane it took; auto-merge is unchanged. Only the contracts are
# checked: the key in the schema, the example, the README and the validator, and in /fix the commands, the step names
# it reports and the lines it parses; the wording of the lane is the manual check's (iteration 73). Text is joined
# (newlines to spaces, runs of spaces made one) before it is searched. Usage: bash tests/test-fast-lane.sh [repository path]
set -uo pipefail
cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 1
fail=0
CASE=""
step() { CASE=$1; echo "-- $1"; }

flat() { tr '\n' ' ' | sed -E 's/ +/ /g'; }

# need_in <label> <joined text> <text>...
need_in() {
  local label=$1 flatf=$2 text; shift 2
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) ;;
      *) echo "FAIL: [${CASE}] ${label} does not say: ${text}"; fail=1 ;;
    esac
  done
}
need() { local f=$1; shift; need_in "$f" "$(flat < "$f")" "$@"; }
# check <label> <expected> <actual>
check() {
  if [ "$2" != "$3" ]; then echo "FAIL: [${CASE}] $1: expected '$2', got '$3'"; fail=1; fi
}

F=skills/fix/SKILL.md
SCHEMA=schema/nightmill.schema.json
EXAMPLE=templates/nightmill.example.json

# shellcheck source=scripts/lib/json.sh
. scripts/lib/json.sh

echo "== the fast lane of /fix"

# Criterion 1: the configuration says which bugs take the fast lane
step "schema: fastLane"
json_load "${SCHEMA}" || { echo "FAIL: [${CASE}] schema: fastLane: ${SCHEMA} cannot be read"; fail=1; }
base=properties.review.properties.fastLane
check "schema: fastLane type" object "$(json_get "${base}.type")"
[ -n "$(json_get "${base}.description")" ] || { echo "FAIL: [${CASE}] schema: ${base} has no description"; fail=1; }
for k in priorities paths; do
  p=${base}.properties.${k}
  check "schema: fastLane ${k} type" array "$(json_get "${p}.type")"
  check "schema: fastLane ${k} items type" string "$(json_get "${p}.items.type")"
  check "schema: fastLane ${k} default is an array" array "$(json_kind "${p}.default")"
  check "schema: fastLane ${k} default is empty" 0 "$(json_len "${p}.default")"
  [ -n "$(json_get "${p}.description")" ] || { echo "FAIL: [${CASE}] schema: ${p} has no description"; fail=1; }
done

step "example: fastLane"
json_load "${EXAMPLE}" || { echo "FAIL: [${CASE}] example: fastLane: ${EXAMPLE} cannot be read"; fail=1; }
check "example: review.fastLane.priorities" array "$(json_kind review.fastLane.priorities)"
check "example: review.fastLane.paths" array "$(json_kind review.fastLane.paths)"

step "readme: fastLane"
if ! grep -qF -- '| `review.fastLane` |' README.md; then
  echo "FAIL: [${CASE}] README.md has no configuration table row starting with the cell"' `review.fastLane`'; fail=1
fi

step "validator: fastLane"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill.XXXXXX")
printf '%s\n' '{"review":{"fastLane":{"priorities":"Low"}}}' > "${tmp}/config.json"
out=$(bash scripts/validate-config.sh "${tmp}/config.json" 2>&1); rc=$?
rm -rf "${tmp}"
case "${out}" in
  *'error: review.fastLane.priorities: expected array, got string'*) ;;
  *) echo "FAIL: [${CASE}] validator: fastLane: no 'error: review.fastLane.priorities: expected array, got string' in: ${out}"; fail=1 ;;
esac
check "validator: fastLane exit code" 1 "${rc}"

# Criteria 2 and 3: the commands of the lane, the result field and the check line /fix parses, the step names it reports
step "fix: lane"
need "$F" 'review.fastLane.priorities' 'review.fastLane.paths' 'parallel.hotFiles' \
  '<verification.check> --affected' 'check: AFFECTED' '`Story trigger:`' \
  'reset --mixed -q <lane base>' 'stash push -m "Fast lane attempt for #<issue>: <title>"' \
  '`fixer` | `fast-fix` |' '`session` | `lane-left` |'

[ "${fail}" = 0 ] && echo "FAST LANE OK" || { echo "FAST LANE FAILED"; exit 1; }
