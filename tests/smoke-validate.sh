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
    printf '%s\n' "$out" | grep -xF -- "$l" >/dev/null || fail "$name: missing the line '$l' in: $out"
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

echo "== roles, models and review"
check "new keys clean" "$ex" 0 "" "0 errors, 0 warnings"
check "new keys clean strict" "$ex" 0 "--strict" "0 errors, 0 warnings"
check "no new keys" '{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true"}}' 0 "" "0 errors, 0 warnings"
check "model not a string" "$(edit "$ex" '"implementer": { "model": "opus" }' '"implementer": { "model": 3 }')" 1 "" "error: roles.implementer.model: expected string, got integer"
roles_open='"roles": {'; models_open='"models"'
case "$ex" in *"$roles_open"*) ;; *) fail "fixture: the roles block is not in the example" ;; esac
roles_before=${ex%%"$roles_open"*}; models_after=${ex#*"$models_open"}
roles_arr="${roles_before}\"roles\": [],"$'\n  '"${models_open}${models_after}"
check "roles not an object" "$roles_arr" 1 "" "error: roles: expected object, got array"
check "ranking not an array" "$(edit "$ex" '"ranking": ["haiku", "sonnet", "opus", "fable"]' '"ranking": "opus"')" 1 "" "error: models.ranking: expected array, got string"
check "ranking empty" "$(edit "$ex" '"ranking": ["haiku", "sonnet", "opus", "fable"]' '"ranking": []')" 1 "" "error: models.ranking: needs at least 1 items, got 0"
check "ranking entry not a string" "$(edit "$ex" '"ranking": ["haiku", "sonnet", ' '"ranking": ["haiku", 3, ')" 1 "" "error: models.ranking[1]: expected string, got integer"
check "fix rounds negative" "$(edit "$ex" '"maxFixRounds": 2' '"maxFixRounds": -1')" 1 "" "error: review.maxFixRounds: must be at least 0, got -1"
check "fix rounds a string" "$(edit "$ex" '"maxFixRounds": 2' '"maxFixRounds": "two"')" 1 "" "error: review.maxFixRounds: expected integer, got string"
check "zero fix rounds" "$(edit "$ex" '"maxFixRounds": 2' '"maxFixRounds": 0')" 0 "" "0 errors, 0 warnings"
rolecase=$(edit "$ex" '"codeReviewer"' '"codereviewer"')
check "role key wrong case" "$rolecase" 0 "" 'warning: roles.codereviewer: unknown key (did you mean "codeReviewer"?)'
check "role key wrong case strict" "$rolecase" 1 "--strict" 'warning: roles.codereviewer: unknown key (did you mean "codeReviewer"?)'
check "unknown key in a role" "$(edit "$ex" '"implementer": { "model": "opus" }' '"implementer": { "model": "opus", "effort": "high" }')" 0 "" "warning: roles.implementer.effort: unknown key"

echo "== the reviewer pairing"
SW='"specWriter": { "model": "opus" }'; SR='"specReviewer": { "model": "opus" }'
CR='"codeReviewer": { "model": "opus" }'; RK='"ranking": ["haiku", "sonnet", "opus", "fable"]'
bare='{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true"}'
check "reviewer stronger" "$(edit "$ex" "$SW" '"specWriter": { "model": "sonnet" }')" 0 "" "0 errors, 0 warnings"
check "code reviewer stronger" "$(edit "$ex" "$CR" '"codeReviewer": { "model": "fable" }')" 0 "" "0 errors, 0 warnings"
same=$(edit "$(edit "$ex" "$RK" '"ranking": ["haiku", "sonnet", "opus=claude-opus-5-5", "fable"]')" "$SW" '"specWriter": { "model": "claude-opus-5-5" }')
check "same level in one entry" "$same" 0 "" "0 errors, 0 warnings"
check "spec reviewer below spec writer" "$(edit "$ex" "$SR" '"specReviewer": { "model": "sonnet" }')" 1 "" \
  'error: roles.specReviewer.model: specReviewer on "sonnet" ranks below specWriter on "opus"' "1 error, 0 warnings"
# two errors on one path sort by their text: fixer before implementer
printf '%s\n' "$(edit "$ex" "$CR" '"codeReviewer": { "model": "haiku" }')" > "$tmp/pair2.json"
set +e; out=$(bash "$V" "$tmp/pair2.json" 2>&1); rc=$?; set -e
[ "$rc" = 1 ] || fail "code reviewer below two producers: expected exit code 1, got $rc"
want=$'error: roles.codeReviewer.model: codeReviewer on "haiku" ranks below fixer on "opus"\nerror: roles.codeReviewer.model: codeReviewer on "haiku" ranks below implementer on "opus"\n2 errors, 0 warnings'
got=$(printf '%s\n' "$out" | tail -n +2)
[ "$got" = "$want" ] || fail "code reviewer below two producers: wrong lines or order. Got:
$got
Wanted:
$want"
unr=$(edit "$ex" "$SR" '"specReviewer": { "model": "mystery" }')
check "unranked reviewer" "$unr" 0 "" 'warning: roles.specReviewer.model: model "mystery" is not in models.ranking, so specReviewer cannot be compared' "0 errors, 1 warning"
check "unranked reviewer strict" "$unr" 1 "--strict" 'warning: roles.specReviewer.model: model "mystery" is not in models.ranking, so specReviewer cannot be compared'
check "unranked producer" "$(edit "$ex" '"implementer": { "model": "opus" }' '"implementer": { "model": "mystery" }')" 0 "" \
  'warning: roles.implementer.model: model "mystery" is not in models.ranking, so implementer cannot be compared' "0 errors, 1 warning"
check "tester and worker are not compared" "$(edit "$(edit "$ex" '"tester": { "model": "sonnet" }' '"tester": { "model": "haiku" }')" '"worker": { "model": "haiku" }' '"worker": { "model": "mystery" }')" 0 "" "0 errors, 0 warnings"
check "defaults fill a missing role" "$bare"',"roles":{"specReviewer":{"model":"sonnet"}}}' 1 "" \
  'error: roles.specReviewer.model: specReviewer on "sonnet" ranks below specWriter on "opus"' "1 error, 0 warnings"
check "an empty model takes the default" "$(edit "$ex" "$SR" '"specReviewer": { "model": "" }')" 0 "" "0 errors, 0 warnings"
check "the keys are absent" "$bare}" 0 "" "0 errors, 0 warnings"
printf '%s\n' "$(edit "$ex" "$RK" '"ranking": ["haiku", "fable"]')" > "$tmp/norank.json"
set +e; out=$(bash "$V" "$tmp/norank.json" 2>&1); rc=$?; set -e
[ "$rc" = 0 ] || fail "a ranking without the default models: expected exit code 0, got $rc"
want=$'warning: roles.codeReviewer.model: model "opus" is not in models.ranking, so codeReviewer cannot be compared\nwarning: roles.fixer.model: model "opus" is not in models.ranking, so fixer cannot be compared\nwarning: roles.implementer.model: model "opus" is not in models.ranking, so implementer cannot be compared\nwarning: roles.specReviewer.model: model "opus" is not in models.ranking, so specReviewer cannot be compared\nwarning: roles.specWriter.model: model "opus" is not in models.ranking, so specWriter cannot be compared\n0 errors, 5 warnings'
got=$(printf '%s\n' "$out" | tail -n +2)
[ "$got" = "$want" ] || fail "a ranking without the default models: wrong lines or order. Got:
$got
Wanted:
$want"
check "a bad ranking gives only its own error" "$(edit "$ex" "$RK" '"ranking": "opus"')" 1 "" "error: models.ranking: expected array, got string" "1 error, 0 warnings"

echo "== enum and closed objects, with a schema of their own"
mini="$tmp/mini.schema.json"
printf '%s\n' '{"type":"object","additionalProperties":false,"required":["mode"],"properties":{"mode":{"type":"string","enum":["fast","slow"]}}}' > "$mini"
printf '%s\n' '{"mode":"medium","extra":1}' > "$tmp/mini.json"
set +e; out=$(bash "$V" --schema "$mini" "$tmp/mini.json" 2>&1); rc=$?; set -e
[ "$rc" = 1 ] || fail "enum: expected exit code 1, got $rc"
for l in 'error: extra: unknown key is not allowed' 'error: mode: must be one of: fast, slow, got "medium"' '2 errors, 0 warnings'; do
  printf '%s\n' "$out" | grep -xF -- "$l" >/dev/null || fail "enum: missing the line '$l' in: $out"
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

echo "== the lint notices a role the workflow skill does not name"
cp_dir2="$tmp/repocopy2"; mkdir -p "$cp_dir2"
( cd "$here" && tar -cf - --exclude=.git . ) | ( cd "$cp_dir2" && tar -xf - )
sed 's/fixer/fix-er/g' "$cp_dir2/skills/workflow/SKILL.md" > "$cp_dir2/w.tmp" && mv "$cp_dir2/w.tmp" "$cp_dir2/skills/workflow/SKILL.md"
if out=$(cd "$cp_dir2" && bash tests/lint.sh 2>&1); then fail "the lint accepted a workflow skill without the fixer role"; fi
case "$out" in *fixer*) ;; *) fail "the lint did not name the role: $out" ;; esac

echo "VALIDATE OK"
