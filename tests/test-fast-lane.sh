#!/usr/bin/env bash
# Tests for #341 (iteration 63): /fix has a fast lane for low-risk bugs. The key review.fastLane names the priorities
# whose bugs start in it and the paths a fix may change; in the lane one fixer writes the regression test and the fix,
# the affected check runs and the pull request opens without the tester and the code review; a fix that changes a path
# outside the lane's paths or in parallel.hotFiles, needs a story trigger or is partial leaves the lane and the long way
# starts from the tester; the pull request says which lane it took; auto-merge is unchanged. The skills are
# conversations, so this pins the wording the behaviour depends on. Text is joined (newlines to spaces, runs of spaces
# made one) before it is searched. Usage: bash tests/test-fast-lane.sh [repository path]
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
gone() {
  local f=$1 text flatf; shift
  flatf=$(flat < "$f")
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) echo "FAIL: [${CASE}] ${f} still says: ${text}"; fail=1 ;;
    esac
  done
}
# check <label> <expected> <actual>
check() {
  if [ "$2" != "$3" ]; then echo "FAIL: [${CASE}] $1: expected '$2', got '$3'"; fail=1; fi
}

W=skills/workflow/SKILL.md
F=skills/fix/SKILL.md
SCHEMA=schema/nightmill.schema.json
EXAMPLE=templates/nightmill.example.json

# a section of a skill, from its '## ' heading line to the next one, code fences skipped when looking for the end
section() {
  awk -v h="$2" '$0 == h { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' "$1" | flat
}

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

step "fix: absent key"
need "$F" 'No lane line is printed' 'has no `Lane:` line' 'runs exactly as today' \
  'Lane: fast for #<issue>: priority <p> is in review.fastLane.priorities.' \
  'Lane: long for #<issue>: priority <p | none> is not in review.fastLane.priorities.' \
  'Lane: long for #<issue>: review.fastLane is not valid.'

# Criterion 2: one agent writes the test and the fix, the affected check runs, no review round
step "fix: one agent"
fast=$(section "$F" '## The fast lane')
[ -n "${fast}" ] || { echo "FAIL: [${CASE}] ${F} has no section '## The fast lane'"; fail=1; }
need_in "$F (The fast lane)" "${fast}" \
  'No tester and no code review follow: you write the regression test and the fix.' \
  'Write the regression test and watch it fail for the reason in the issue' \
  '<verification.check> --affected' 'check: AFFECTED' \
  'Story trigger: <none |' \
  'Step 5 runs without "The code review"'
need "$F" '`fixer` | `fast-fix` |'

# Criterion 3: a fix that leaves the lane goes the long way, and the run says so
step "fix: leaving"
need_in "$F (The fast lane)" "${fast}" \
  'is in the hot file entry' 'is outside review.fastLane.paths' \
  'the fix needs a story trigger:' 'the fixer returned partial:' \
  'whatever its `Result:`' \
  'reset --mixed -q <lane base>' \
  'stash push -m "Fast lane attempt for #<issue>: <title>"' \
  'Leaving the fast lane for #<issue>:' \
  'An earlier one-pass attempt' \
  "The tester's prompt does not mention the attempt"
need "$F" '`session` | `lane-left` |'
# the story-trigger rule comes before the failed stop, so a stop on a trigger leaves the lane
trigger_head=${fast%%'the fix needs a story trigger:'*}
failed_head=${fast%%'the fixer returned failed:'*}
if [ "${#trigger_head}" -ge "${#failed_head}" ]; then
  echo "FAIL: [${CASE}] ${F} (The fast lane): the story-trigger reason does not come before 'the fixer returned failed:'"; fail=1
fi

# Criterion 4: the pull request says which lane it took
step "fix: lane line"
need "$F" \
  'Lane: fast (review.fastLane): one fixer wrote the regression test and the fix; no tester and no code review.' \
  'Lane: long: priority <p | none> is not in review.fastLane.priorities.' \
  'Lane: long: review.fastLane is not valid.' \
  'Lane: long: left the fast lane: <reason>. Its work is in the stash entry "Fast lane attempt for #<issue>: <title>".' \
  'Reproduced first by the fixer role on <model> in the fast lane, failing before the fix:'

step "workflow: fast lane"
Wtext=$(section "$W" '## Findings and fix rounds')
need_in "$W (Findings and fix rounds)" "${Wtext}" \
  'A bug that stays in the fast lane of `/fix` (`review.fastLane`) has no code review, no fix round and no `## Review` section; its pull request says so in its `Lane:` line.'
need "$W" 'not in the fast lane of /fix'

# Criterion 5: auto-merge is unchanged (texts that exist today and must stay)
step "fix: auto-merge kept"
need "$F" 'For a complete fix enable auto-merge' 'it must contain --auto and never --admin' \
  'which is never auto-merged'
need "$W" 'CI runs on every push and PR to `git.baseBranch`; a PR merges only when its blocking jobs pass.'

[ "${fail}" = 0 ] && echo "FAST LANE OK" || { echo "FAST LANE FAILED"; exit 1; }
