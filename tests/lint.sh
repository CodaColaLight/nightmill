#!/usr/bin/env bash
# tests/lint.sh - nightmill stays generic and well-formed.
#   1. No word from the private word list (names of the project nightmill was extracted from,
#      its maintainer, ...) appears anywhere in the repository. The list is not committed:
#      it is tests/forbidden-words.local.txt (gitignored) or the FORBIDDEN_WORDS variable
#      (one word per line; CI sets it from a secret). Without either the check is skipped.
#   2. Every JSON file parses.
#   3. Every skill has frontmatter with name and description; every skill that reads the config
#      injects it with the !` ` preamble.
#   4. Shell scripts pass bash -n; shellcheck runs when installed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
# `bash tests/lint.sh --specs` runs only the section "specs follow the template" (bug #280: tests/test-spec-template.sh
# runs it on many throwaway copies, the whole lint only once); with no argument every section runs.
case "${1:-}" in ''|--specs) ;; *) echo "usage: bash tests/lint.sh [--specs]" >&2; exit 2 ;; esac
lint_specs() {
echo "== specs follow the template"
# Specs are written from templates/spec.md (iteration 40): the title, a status line and seven required headings, once
# each and in order. The template is checked against the list below, a spec from iteration 40 on in iterations.specDir
# is checked against it, and the specs before are exempt (written before the template). Fence lines (^```) and what
# they hold are skipped, a trailing carriage return and trailing blanks are ignored.
spec_req=('## Story trigger and manual check' '## Criteria and rules' '## Tests' '## Files touched' '## Risks' '## Size estimate' '## Not done')
spec_form() { # spec_form <file> <N>: one FAIL line per problem, nothing when the form is right
  SPEC_REQ=$(printf '%s\n' "${spec_req[@]}") SPEC_N=$2 SPEC_FILE=$1 LC_ALL=C awk '
    BEGIN { nreq = split(ENVIRON["SPEC_REQ"], req, "\n"); f = ENVIRON["SPEC_FILE"]; want = "# Iteration " ENVIRON["SPEC_N"] ":" }
    { l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l) }
    l ~ /^```/ { infence = !infence; next }
    infence { next }
    l ~ /^#+ / {
      if (!seenh) { seenh = 1; if (substr(l, 1, length(want)) == want) titleok = 1 }
      if (l ~ /^## /) seen2 = 1
      for (i = 1; i <= nreq; i++) if (l == req[i]) { cnt[i]++; if (!(i in at)) at[i] = NR }
      next
    }
    !seen2 && l ~ /^Status: / { st = 1 }
    END {
      if (!titleok) printf "FAIL: %s: the first heading is not \047%s\047\n", f, want
      if (!st) printf "FAIL: %s: no \047Status: \047 line before the first \047## \047 heading\n", f
      for (i = 1; i <= nreq; i++) {
        if (!(i in cnt)) printf "FAIL: %s: missing heading \047%s\047\n", f, req[i]
        else if (cnt[i] > 1) printf "FAIL: %s: heading \047%s\047 appears %d times\n", f, req[i], cnt[i]
      }
      for (i = 1; i <= nreq; i++) for (j = i + 1; j <= nreq; j++)
        if ((i in at) && (j in at) && at[j] < at[i]) printf "FAIL: %s: heading \047%s\047 comes before \047%s\047\n", f, req[j], req[i]
    }' "$1"
}
spec_cases() { # spec_cases <dir>: the self-test of spec_form on specs filled in from the template; prints only FAIL lines
  local d=$1 out
  sed 's/<N>/99/' templates/spec.md > "$d/ok.md"
  sed '/^## Risks$/d' "$d/ok.md" > "$d/norisks.md"
  sed -e 's/^## Tests$/## @@A@@/' -e 's/^## Files touched$/## Tests/' -e 's/^## @@A@@$/## Files touched/' "$d/ok.md" > "$d/swapped.md"
  awk '$0 == "## Not done" { print "```"; print; print "```"; next } { print }' "$d/ok.md" > "$d/fenced.md"
  out=$(spec_form "$d/ok.md" 99)
  [ -z "$out" ] || printf 'FAIL: the spec form check rejected a spec filled in from templates/spec.md:\n%s\n' "$out"
  out=$(spec_form "$d/norisks.md" 99)
  case "$out" in *"missing heading '## Risks'"*) ;; *) echo "FAIL: the spec form check accepted a spec without '## Risks'" ;; esac
  out=$(spec_form "$d/swapped.md" 99)
  case "$out" in *'comes before'*) ;; *) echo "FAIL: the spec form check accepted a spec with '## Tests' and '## Files touched' exchanged" ;; esac
  out=$(spec_form "$d/fenced.md" 99)
  case "$out" in *"missing heading '## Not done'"*) ;; *) echo "FAIL: the spec form check accepted a spec with '## Not done' inside a fence" ;; esac
  out=$(spec_form "$d/ok.md" 98)
  case "$out" in *'the first heading'*) ;; *) echo "FAIL: the spec form check accepted a spec whose first heading has another number" ;; esac
}
out=$(spec_form templates/spec.md '<N>')
[ -z "$out" ] || { printf '%s\n' "$out"; fail=1; }
grep -Fx 'Status: draft, awaiting approval (#<issue>)' templates/spec.md >/dev/null || { echo "FAIL: templates/spec.md lacks the line 'Status: draft, awaiting approval (#<issue>)'"; fail=1; }
spec_tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-lint.XXXXXX")
rc=0; cases_out=$(spec_cases "$spec_tmp") || rc=$?
rm -rf "$spec_tmp"
[ -z "$cases_out" ] || { printf '%s\n' "$cases_out"; fail=1; }
[ "$rc" = 0 ] || { echo "FAIL: the spec form self-test exited $rc"; fail=1; }
json_load .claude/nightmill.json
spec_dir=$(json_get iterations.specDir)
spec_pat=$(json_get iterations.specPattern)
if [ -z "$spec_dir" ]; then
  echo "FAIL: .claude/nightmill.json has no iterations.specDir"; fail=1
elif [ "$spec_pat" != 'iteration-<N>-<slug>.md' ]; then
  echo "FAIL: .claude/nightmill.json: iterations.specPattern is '$spec_pat', the lint knows only 'iteration-<N>-<slug>.md'"; fail=1
else
  spec_old=0
  for f in "$spec_dir"/iteration-*.md; do
    [ -f "$f" ] || continue
    if [[ "${f##*/}" =~ ^iteration-([0-9]+)-.+\.md$ ]]; then
      n=$((10#${BASH_REMATCH[1]}))
      if [ "$n" -lt 40 ]; then
        spec_old=$((spec_old + 1))
      else
        out=$(spec_form "$f" "$n")
        [ -z "$out" ] || { printf '%s\n' "$out"; fail=1; }
      fi
    else
      echo "FAIL: $f: the name does not match iteration-<N>-<slug>.md"; fail=1
    fi
  done
  echo "exempt: $spec_old specs below iteration 40 (written before the template)"
fi
}
if [ "${1:-}" = --specs ]; then
  # shellcheck source=scripts/lib/json.sh
  . scripts/lib/json.sh
  lint_specs
  [ "$fail" = 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
  exit 0
fi


echo "== forbidden words"
words=tests/forbidden-words.local.txt
if [ -n "${FORBIDDEN_WORDS:-}" ]; then
  words=$(mktemp "${TMPDIR:-/tmp}/nightmill-lint.XXXXXX"); trap 'rm -f "$words"' EXIT
  printf '%s
' "$FORBIDDEN_WORDS" > "$words"
fi
if [ ! -s "$words" ]; then
  echo "skipped: no word list (tests/forbidden-words.local.txt or FORBIDDEN_WORDS)"
elif grep -rniF --exclude-dir=.git --exclude=forbidden-words.local.txt -f "$words" . ; then
  echo "FAIL: project-specific words found (see above)"; fail=1
fi

echo "== json"
# Every JSON file parses, checked with the same strict parser the scripts use (scripts/lib/json.awk).
while IFS= read -r f; do
  JSON_MODE=check JSON_FILE="$f" LC_ALL=C awk -f scripts/lib/json.awk || { echo "FAIL: $f does not parse"; fail=1; }
done < <(find . -path ./.git -prune -o -name '*.json' -print)

echo "== skills"
for s in skills/*/SKILL.md; do
  head -1 "$s" | grep -x -- '---' >/dev/null || { echo "FAIL: $s has no frontmatter"; fail=1; }
  grep -q '^name: ' "$s" || { echo "FAIL: $s has no name"; fail=1; }
  grep -q '^description: ' "$s" || { echo "FAIL: $s has no description"; fail=1; }
  if grep -q 'nightmill.json' "$s" && ! grep -q '^!`' "$s"; then
    echo "FAIL: $s mentions the config but does not inject it"; fail=1
  fi
done
for a in agents/*.md; do
  grep -q '^name: ' "$a" || { echo "FAIL: $a has no name"; fail=1; }
done

echo "== skills use the status names of the schema"
# The status names /spec and /next move a story by are the schema's defaults of board.statuses (ready, specReview,
# approved): a contract, so they are checked in the whole skill file.
for w in 'Ready' 'Spec review'; do
  grep -qF -- "$w" skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not use the status $w"; fail=1; }
done
grep -qF -- 'Approved' skills/next/SKILL.md || { echo "FAIL: skills/next/SKILL.md does not use the status Approved"; fail=1; }

echo "== init skill keeps the install-chat steps"
# /init applies the install chat with these commands and API calls (iteration 1); the wording of its questions and
# its steps is the manual check's (iteration 73: tests check contracts, not the wording of skills).
for w in validate-config createProjectV2View updateProjectV2View BOARD_LAYOUT updateProjectV2Field 'gh label create' 'gh project link' 'workflows(first' 'projects/<n>/workflows'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention $w"; fail=1; }
done
# /init reads the board's workflows (workflows(first: 20) { nodes { name enabled } }) and matches these names in the
# output, so they are a contract with the API; the filter of Auto-archive items is set by hand and not checked.
for w in 'Item added to project' 'Item closed' 'Pull request merged' 'Pull request linked to issue' 'Code review approved' \
         'Code changes requested' 'Item reopened' 'Auto-archive items'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not name the board workflow: $w"; fail=1; }
done

echo "== session-start hook is wired"
# The SessionStart hook offers /init where nightmill is not set up (iteration 3): hooks/hooks.json has the
# event map under "hooks", a SessionStart entry with matcher startup, and every command runs a script of
# this plugin that exists.
if [ -f hooks/hooks.json ]; then
  grep -q '"hooks"' hooks/hooks.json || { echo "FAIL: hooks/hooks.json has no top-level hooks key"; fail=1; }
  grep -q '"SessionStart"' hooks/hooks.json || { echo "FAIL: hooks/hooks.json has no SessionStart entry"; fail=1; }
  grep -Eq '"matcher": *"startup"' hooks/hooks.json || { echo "FAIL: the SessionStart entry does not use matcher startup"; fail=1; }
  n_cmd=$(grep -c '"command":' hooks/hooks.json || true)
  n_ok=$(grep '"command":' hooks/hooks.json | grep -c '\${CLAUDE_PLUGIN_ROOT}/scripts/' || true)
  [ "$n_cmd" -ge 1 ] && [ "$n_cmd" = "$n_ok" ] || { echo "FAIL: every hook command must run \${CLAUDE_PLUGIN_ROOT}/scripts/<script>"; fail=1; }
  for c in $(grep -o '\${CLAUDE_PLUGIN_ROOT}/scripts/[A-Za-z0-9._-]*' hooks/hooks.json | sort -u); do
    [ -f "scripts/${c##*/scripts/}" ] || { echo "FAIL: hooks/hooks.json names scripts/${c##*/scripts/}, which does not exist"; fail=1; }
  done
else
  echo "FAIL: hooks/hooks.json is missing"; fail=1
fi

echo "== contributor files are wired"
# CONTRIBUTING.md, the two forms for outsiders and the pull request template exist and say what the spec of
# iteration 4 requires. Whether GitHub accepts the forms is checked in the browser's issue chooser.
if [ -f CONTRIBUTING.md ]; then
  for w in 'tests/check.sh' '--plugin-dir' 'SECURITY.md'; do
    grep -qF -- "$w" CONTRIBUTING.md || { echo "FAIL: CONTRIBUTING.md does not mention $w"; fail=1; }
  done
  # 'Ready' and 'Approved' are the schema defaults of board.statuses.
  for w in 'Ready' 'Approved'; do
    grep -qF -- "$w" CONTRIBUTING.md || { echo "FAIL: CONTRIBUTING.md does not mention $w"; fail=1; }
  done
else
  echo "FAIL: CONTRIBUTING.md is missing"; fail=1
fi
for f in nightmill-bug nightmill-idea; do
  p=.github/ISSUE_TEMPLATE/$f.yml
  if [ -f "$p" ]; then
    head -1 "$p" | grep '^name: ' >/dev/null || { echo "FAIL: $p does not start with name:"; fail=1; }
    grep -q '^body:' "$p" || { echo "FAIL: $p has no body:"; fail=1; }
  else
    echo "FAIL: $p is missing"; fail=1
  fi
done
for id in shell os claude_code_version nightmill_version config; do
  grep -q "^    id: $id\$" .github/ISSUE_TEMPLATE/nightmill-bug.yml 2>/dev/null || { echo "FAIL: nightmill-bug.yml has no field $id"; fail=1; }
done
[ -f .github/pull_request_template.md ] || { echo "FAIL: .github/pull_request_template.md is missing"; fail=1; }

echo "== release metadata agrees"
# The version in plugin.json, the first version heading of CHANGELOG.md below "## Unreleased" and the
# README's "Version X.Y.Z." line must name the same version, and the heading must carry a date (iteration 5).
pj_version=$(grep -E '^[[:space:]]*"version":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' .claude-plugin/plugin.json | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
cl_heading=$(awk '/^## Unreleased[[:space:]]*$/ { u = 1; next } u && /^## / { print; exit }' CHANGELOG.md)
cl_version=$(printf '%s\n' "$cl_heading" | sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+) \([0-9]{4}-[0-9]{2}-[0-9]{2}\)[[:space:]]*$/\1/p')
rd_version=$(sed -nE 's/^Version ([0-9]+\.[0-9]+\.[0-9]+)\..*/\1/p' README.md | head -1)
if [ -z "$pj_version" ] || [ "$pj_version" != "$cl_version" ] || [ "$pj_version" != "$rd_version" ]; then
  echo "FAIL: versions disagree: plugin.json='$pj_version' CHANGELOG.md='$cl_version' (heading: '$cl_heading') README.md='$rd_version'"; fail=1
fi

echo "== config validates"
# The example and this repository's own config pass the validator with --strict (iteration 6).
for f in templates/nightmill.example.json .claude/nightmill.json; do
  out=$(bash scripts/validate-config.sh --strict "$f" 2>&1) || { echo "$out"; echo "FAIL: $f does not validate"; fail=1; }
done

echo "== reviewer pairing is checked"
# The validator (scripts/lib/validate.awk) rejects a reviewer ranked below the role it reviews and warns about a
# model that is not in models.ranking (iteration 15); a change that drops the rule fails here.
for w in 'ranks below' 'is not in models.ranking'; do
  grep -qF -- "$w" scripts/lib/validate.awk || { echo "FAIL: scripts/lib/validate.awk does not carry the pairing rule text: $w"; fail=1; }
done
# the validator this lint runs on the example and on the repository's own config has the rule
pair_cfg=$(mktemp "${TMPDIR:-/tmp}/nightmill-lint.XXXXXX")
sed 's/"specReviewer": { "model": "opus" }/"specReviewer": { "model": "haiku" }/' templates/nightmill.example.json > "$pair_cfg"
if out=$(bash scripts/validate-config.sh "$pair_cfg" 2>&1); then
  echo "FAIL: scripts/validate-config.sh accepted a spec reviewer on a model ranked below the spec writer's"; fail=1
elif ! printf '%s\n' "$out" | grep -F 'ranks below' >/dev/null; then
  echo "FAIL: scripts/validate-config.sh did not say 'ranks below' for a spec reviewer ranked below the spec writer"; fail=1
fi
rm -f "$pair_cfg"

echo "== schema keywords are supported"
# scripts/validate-config.* understand type, properties, required, items, minimum, minItems,
# additionalProperties, enum, pattern and not (iteration 48). A schema that gains another constraint would be silently
# ignored by them. `maximum` is allowed (iteration 53): the validator ignores it and the script that reads the key
# (scripts/gate.*) checks the upper end, as slot and room do.
for kw in '$ref' anyOf oneOf allOf if format const maxItems uniqueItems minLength maxLength dependencies; do
  if grep -qF "\"$kw\"" schema/nightmill.schema.json; then
    echo "FAIL: schema/nightmill.schema.json uses \"$kw\", which scripts/validate-config.* does not support"; fail=1
  fi
done
# not is supported only as an object whose one key is pattern, and a pattern holds only characters that ECMA-262, POSIX
# ERE (awk) and .NET read the same way: letters, digits, space and -=_.*()?|^$ (no backslash, no class). A key named
# pattern or not directly under properties is a property, not the keyword.
schema_flat=$(JSON_MODE=flat JSON_FILE=schema/nightmill.schema.json LC_ALL=C awk -f scripts/lib/json.awk) || schema_flat=""
while IFS="$(printf '\t')" read -r sk_path sk_kind sk_val; do
  case "$sk_path" in *properties.not|*properties.pattern) continue ;; esac
  case "$sk_path" in
    not|*.not)
      if [ "$sk_kind" != object ]; then
        echo "FAIL: schema/nightmill.schema.json: $sk_path is not an object with the one key pattern"; fail=1
      else
        sk_keys=$(printf '%s\n' "$schema_flat" | SK_P="$sk_path." LC_ALL=C awk -F '\t' 'index($1, ENVIRON["SK_P"]) == 1 { r = substr($1, length(ENVIRON["SK_P"]) + 1); if (r !~ /[.[]/) print r }')
        [ "$sk_keys" = pattern ] || { echo "FAIL: schema/nightmill.schema.json: $sk_path has a key other than pattern (only not: { pattern } is supported)"; fail=1; }
      fi ;;
    pattern|*.pattern)
      if [ "$sk_kind" != string ]; then
        echo "FAIL: schema/nightmill.schema.json: $sk_path is not a string"; fail=1
      elif printf '%s\n' "$sk_val" | LC_ALL=C grep '[^A-Za-z0-9 =_.*()?|^$-]' >/dev/null; then
        echo "FAIL: schema/nightmill.schema.json: $sk_path holds a character outside letters, digits, space and -=_.*()?|^\$: $sk_val"; fail=1
      fi ;;
  esac
done <<SKEOF
$schema_flat
SKEOF

echo "== roles and models are described"
# The agent roles, the model ranking and the fix rounds (iteration 10): all optional, each with a type, a default
# and a description in the schema; the example and this repository's config carry them; the README names them.
# shellcheck source=scripts/lib/json.sh
. scripts/lib/json.sh
role_defaults="specWriter:opus specReviewer:opus tester:sonnet implementer:opus codeReviewer:opus fixer:opus worker:haiku"
rank_default="haiku sonnet opus fable"
json_load schema/nightmill.schema.json
for k in roles models review; do
  json_has "properties.$k" || { echo "FAIL: schema has no $k"; fail=1; }
  [ -n "$(json_get "properties.$k.description")" ] || { echo "FAIL: schema: $k has no description"; fail=1; }
  if json_has "properties.$k.required"; then echo "FAIL: schema: $k has a required list (the keys are optional)"; fail=1; fi
  n=$(json_len required)
  for ((j = 0; j < n; j++)); do
    [ "$(json_get "required[$j]")" != "$k" ] || { echo "FAIL: schema: $k is in the root required list"; fail=1; }
  done
done
for pair in $role_defaults; do
  r=${pair%%:*}; d=${pair#*:}; p=properties.roles.properties.$r
  [ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: roles.$r has no description"; fail=1; }
  [ "$(json_get "$p.properties.model.type")" = string ] || { echo "FAIL: schema: roles.$r.model is not a string"; fail=1; }
  [ "$(json_get "$p.properties.model.default")" = "$d" ] || { echo "FAIL: schema: roles.$r.model default is not $d"; fail=1; }
  [ -n "$(json_get "$p.properties.model.description")" ] || { echo "FAIL: schema: roles.$r.model has no description"; fail=1; }
  if json_has "$p.required" || json_has "$p.properties.model.required"; then echo "FAIL: schema: roles.$r has a required list"; fail=1; fi
done
p=properties.models.properties.ranking
[ "$(json_get "$p.type")" = array ] || { echo "FAIL: schema: models.ranking is not an array"; fail=1; }
[ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: models.ranking has no description"; fail=1; }
[ "$(json_len "$p.default")" = 4 ] || { echo "FAIL: schema: models.ranking default is not the four aliases"; fail=1; }
j=0
for m in $rank_default; do
  [ "$(json_get "$p.default[$j]")" = "$m" ] || { echo "FAIL: schema: models.ranking default[$j] is not $m"; fail=1; }
  j=$((j + 1))
done
p=properties.review.properties.maxFixRounds
[ "$(json_get "$p.type")" = integer ] || { echo "FAIL: schema: review.maxFixRounds is not an integer"; fail=1; }
[ "$(json_get "$p.minimum")" = 0 ] || { echo "FAIL: schema: review.maxFixRounds minimum is not 0"; fail=1; }
[ "$(json_get "$p.default")" = 3 ] || { echo "FAIL: schema: review.maxFixRounds default is not 3"; fail=1; }
[ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: review.maxFixRounds has no description"; fail=1; }
for f in templates/nightmill.example.json .claude/nightmill.json; do
  json_load "$f"
  for pair in $role_defaults; do
    r=${pair%%:*}; d=${pair#*:}
    json_has "roles.$r.model" || { echo "FAIL: $f has no roles.$r.model"; fail=1; continue; }
    if [ "$f" = templates/nightmill.example.json ] && [ "$(json_get "roles.$r.model")" != "$d" ]; then
      echo "FAIL: $f: roles.$r.model is not the schema default $d"; fail=1
    fi
  done
  json_has models.ranking || { echo "FAIL: $f has no models.ranking"; fail=1; }
  json_has review.maxFixRounds || { echo "FAIL: $f has no review.maxFixRounds"; fail=1; }
  if [ "$f" = templates/nightmill.example.json ]; then
    j=0
    for m in $rank_default; do
      [ "$(json_get "models.ranking[$j]")" = "$m" ] || { echo "FAIL: $f: models.ranking[$j] is not the schema default $m"; fail=1; }
      j=$((j + 1))
    done
    [ "$(json_len models.ranking)" = 4 ] || { echo "FAIL: $f: models.ranking is not the schema default"; fail=1; }
    [ "$(json_get review.maxFixRounds)" = 3 ] || { echo "FAIL: $f: review.maxFixRounds is not the schema default 3"; fail=1; }
  fi
done
for pair in $role_defaults; do
  grep -qF -- "${pair%%:*}" README.md || { echo "FAIL: README.md does not mention the role ${pair%%:*}"; fail=1; }
done
for w in 'roles' 'models.ranking' 'review.maxFixRounds'; do
  grep -qF -- "\`$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done

echo "== agent roles are defined in the workflow skill"
# The workflow skill names every role of the schema and the key and schema path a model is resolved from (iteration
# 11), and the worker agent's own model is the schema default. The wording of the rules is the manual check's.
wf=skills/workflow/SKILL.md
json_load schema/nightmill.schema.json
while IFS= read -r r; do
  [ -n "$r" ] || continue
  grep -qF -- "\`$r\`" "$wf" || { echo "FAIL: $wf does not name the role $r"; fail=1; }
done < <(json_keys properties.roles.properties)
for w in 'roles.<role>.model' 'properties.roles.properties.R.properties.model' 'schema/nightmill.schema.json'; do
  grep -qF -- "$w" "$wf" || { echo "FAIL: $wf does not say: $w"; fail=1; }
done
worker_default=$(json_get properties.roles.properties.worker.properties.model.default)
worker_model=$(sed -n 's/^model:[[:space:]]*//p' agents/worker.md | head -1)
[ "$worker_model" = "$worker_default" ] || { echo "FAIL: agents/worker.md has model '$worker_model', the schema default of roles.worker.model is '$worker_default'"; fail=1; }

echo "== status is wired"
# /status (iteration 8): the skill, both scripts and both smoke tests exist, the README names the skill, and the
# scripts only read: no board edit, merge, comment or GraphQL mutation anywhere in them.
for f in skills/status/SKILL.md scripts/status.sh scripts/lib/status.awk tests/smoke-status.sh; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
grep -qF '/nightmill:status' README.md || { echo "FAIL: README.md does not mention /nightmill:status"; fail=1; }
for f in scripts/status.sh scripts/lib/status.awk; do
  if [ -f "$f" ] && grep -nE 'item-edit|item-add|item-archive|item-delete|pr merge|issue edit|issue comment|issue close|mutation' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f changes something; /status only reads"; fail=1
  fi
done

echo "== template board is wired"
# /init copies nightmill's template board when it can and builds the board field by field when it cannot
# (iteration 9): the location is templates/board-template.json (owner a non-empty string, number an integer or
# null), the check is scripts/template-board.* (read only), and /init runs the copy command and the check.
tb=templates/board-template.json
if [ -f "$tb" ]; then
  grep -Eq '"owner":[[:space:]]*"[^"]+"' "$tb" || { echo "FAIL: $tb: owner must be a non-empty string"; fail=1; }
  grep -Eq '"number":[[:space:]]*(null|[1-9][0-9]*)[[:space:]]*[,}]' "$tb" || { echo "FAIL: $tb: number must be an integer or null"; fail=1; }
else
  echo "FAIL: $tb is missing"; fail=1
fi
for f in scripts/template-board.sh tests/smoke-template-board.sh; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
f=scripts/template-board.sh
if [ -f "$f" ] && grep -nE 'project copy|project link|item-edit|item-add|item-archive|item-delete|field-create|project edit|api graphql|mutation' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
  echo "FAIL: $f changes something; the template check only reads"; fail=1
fi
for w in 'gh project copy' 'template-board'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention $w"; fail=1; }
done

echo "== models is wired"
# /models (iteration 16): the skill, both scripts and both smoke tests exist, the README names the skill, the scripts
# only read, the roles of the scripts are the roles of the schema, the skill does not name the config file (so it
# needs no injection), and the check and CI run the smoke tests.
for f in skills/models/SKILL.md scripts/models.sh scripts/lib/models.awk tests/smoke-models.sh; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
grep -qF '/nightmill:models' README.md || { echo "FAIL: README.md does not mention /nightmill:models"; fail=1; }
for f in scripts/models.sh scripts/lib/models.awk; do
  if [ -f "$f" ] && grep -nE '(^|[^a-z])gh +[a-z]|curl|Set-Content|Out-File|Add-Content|Remove-Item|New-Item|git +(add|commit|push|switch|checkout|fetch|worktree|config|branch|reset|rm|mv|clean|stash|init|merge|rebase|pull)' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f writes or calls out; /models only reads"; fail=1
  fi
done
json_load schema/nightmill.schema.json
while IFS= read -r r; do
  [ -n "$r" ] || continue
  grep -qF -- "$r" scripts/lib/models.awk || { echo "FAIL: scripts/lib/models.awk does not know the role $r of the schema"; fail=1; }
done < <(json_keys properties.roles.properties)
if grep -qF 'nightmill.json' skills/models/SKILL.md; then
  echo "FAIL: skills/models/SKILL.md names the config file; it would have to inject it"; fail=1
fi
grep -qF 'smoke-models' tests/check.sh || { echo "FAIL: tests/check.sh does not run smoke-models"; fail=1; }

echo "== init installs the edit permission"
# /init adds the rule Edit(**) to permissions.allow of .claude/settings.local.json (iteration 12): the rule, the file
# and the git command it runs.
for w in 'Edit(**)' '.claude/settings.local.json' 'git check-ignore'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention the edit permission item: $w"; fail=1; }
done
# Edit(/**) is not scoped to the project on every platform; only Edit(**) is written
for f in skills/init/SKILL.md README.md; do
  if grep -qF 'Edit(/**)' "$f"; then
    echo "FAIL: $f contains Edit(/**), which reaches outside the project; write Edit(**)"; fail=1
  fi
done
for w in 'Edit(**)' '.claude/settings.local.json'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention the edit permission item: $w"; fail=1; }
done

echo "== init installs the run permissions"
# /init adds the Run permissions line (iteration 43): git commands, scripts, the slot root and an edit rule for the
# slots, in .claude/settings.local.json: the rules, the files and keys they go into and the git command that finds the
# slot root; the wording of the line is the manual check's.
ini=skills/init/SKILL.md
for w in '.claude/settings.local.json' '.claude/settings.json' 'additionalDirectories' 'permissions.additionalDirectories' \
         'Edit(//' '/slot-*/**' 'git rev-parse --path-format=absolute --git-common-dir' \
         'Bash(git fetch origin)' 'Bash(git switch *)' 'Bash(git add *)' 'Bash(git commit *)' \
         'Bash(git push -u origin <Sp>*)' 'Bash(git push -u origin <Fe>*)' 'Bash(git push -u origin <Fx>*)' \
         'Bash(git pull --ff-only)' 'Bash(git rebase origin/<B>)' 'Bash(git rebase --continue)' \
         'Bash(git stash push *)' 'Bash(git stash list)' 'Bash(git ls-tree *)' 'Bash(git rev-parse *)' 'Bash(<C> --quick)' \
         'Bash(git -C <S> status *)' 'Bash(git -C <S> diff *)' 'Bash(git -C <S> log *)' 'Bash(git -C <S> add *)' \
         'Bash(git -C <S> commit *)' 'Bash(git -C <S> stash push *)' 'Bash(git -C <S> stash list)' \
         'Bash(git -C <S> stash pop *)' 'Bash(git -C <S> hash-object *)' 'Bash(git -C <S> rev-parse *)' \
         'Bash(git -C <S> ls-tree *)' 'Bash(git -C <S> merge-base *)' 'Bash(git -C <S> reset --mixed -q *)' \
         'Bash(git -C <S> reset -q -- *)' 'Bash(git -C <S> update-index *)' 'Bash(git -C <S> checkout-index *)' \
         'Bash(git -C <S> symbolic-ref *)' 'Bash(git -C <S> rebase origin/<B>)' 'Bash(git -C <S> rebase --continue)' \
         'Bash(git -C <S> push -u origin <Fe>*)' 'Bash(git -C <S> push -u origin <Fx>*)' \
         'Bash(bash "<P>/scripts/<name>.sh" *)'; do
  grep -qF -- "$w" "$ini" || { echo "FAIL: $ini does not mention the run permissions item: $w"; fail=1; }
done
# #364: init writes the bash form of the script rules only
if grep -qF -- 'Bash(powershell' "$ini"; then echo "FAIL: $ini writes a PowerShell allow rule; init writes the bash form only (#364)"; fail=1; fi
# no broad rule: no bare git push, no git wildcard, no git -C wildcard, no hard reset
for w in 'Bash(git push *)' 'Bash(git push:*)' 'Bash(git *)' 'Bash(git:*)' 'Bash(git -C *' 'Bash(git -C:*)' 'reset --hard'; do
  if grep -qF -- "$w" "$ini"; then echo "FAIL: $ini contains the too broad rule text: $w"; fail=1; fi
done
if grep -qE 'Bash\([^)]*slot-\* ' "$ini"; then echo "FAIL: $ini has a slot-* wildcard inside a Bash( rule"; fail=1; fi
# the skills' slot git commands each have a B rule
for f in skills/next/SKILL.md skills/fix/SKILL.md agents/tester.md; do
  while IFS= read -r c; do
    sub=${c##* }
    case "$c" in
      *stash*) sub="stash ${c##* }" ;;
    esac
    rest=$(printf '%s' "$c" | sed -E 's/^git -C <slot( path)?> //')
    case "$rest" in
      stash\ *) sub=$(printf '%s' "$rest" | awk '{print $1" "$2}') ;;
      reset\ --mixed*) sub='reset --mixed' ;;
      reset\ -q*) sub='reset -q' ;;
      *) sub=${rest%% *} ;;
    esac
    grep -qF -- "git -C <S> $sub" "$ini" || { echo "FAIL: $f runs git -C <slot> $sub, which no Run permissions rule covers"; fail=1; }
  done < <(grep -oE 'git -C <slot( path)?> (stash [a-z]+|reset (--mixed|-q)|[a-z-]+)' "$f" | sort -u)
done
# every script call is the one form the rule matches
for f in skills/*/SKILL.md; do
  while IFS= read -r m; do
    case "$m" in
      bash\ \"*.sh\") ;;
      *) echo "FAIL: $f: $m is not the one script form"; fail=1 ;;
    esac
  done < <(grep -oE '(bash |powershell -NoProfile -ExecutionPolicy Bypass -File )?"\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[a-z-]+\.(sh|ps1)"' "$f")
done
for w in 'git fetch origin' 'git switch -c' 'git push -u origin'; do
  grep -qF -- "$w" skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not write the command in one form: $w"; fail=1; }
done
for f in skills/next/SKILL.md skills/fix/SKILL.md; do
  for w in 'git fetch origin' 'git -C <slot path> rebase origin/' 'git -C <slot path> push -u origin' \
           'cd <absolute slot path> && <verification.check>' '-m "<message>"'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not write the command in one form: $w"; fail=1; }
  done
done
# each skill that injects the config declares allowed-tools for the injection
for f in skills/*/SKILL.md; do
  grep -q '^!`' "$f" || continue
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")
  if ! printf '%s\n' "$fm" | grep -E '^allowed-tools:' | grep -F 'Bash(cat .claude/nightmill.json *)' >/dev/null; then
    echo "FAIL: $f: the injection has no matching allowed-tools"; fail=1
  fi
  # an injection line is the working tree's cat (/init) or the base configuration's git line (iteration 48), whose
  # every part tests/test-skill-config-fallback.sh checks against allowed-tools
  if grep '^!`' "$f" | grep -v -e '^!`cat \.claude/nightmill\.json' -e '^!`git symbolic-ref -q --short refs/remotes/origin/HEAD ' >/dev/null; then
    echo "FAIL: $f: the injection has no matching allowed-tools (an injection line does not start !\`cat .claude/nightmill.json or !\`git symbolic-ref)"; fail=1
  fi
  if grep '^!`git symbolic-ref' "$f" >/dev/null && ! printf '%s\n' "$fm" | grep -E '^allowed-tools:' | grep -F 'Bash(MSYS_NO_PATHCONV=1 git show origin/*:.claude/nightmill.json *)' >/dev/null; then
    echo "FAIL: $f: the base configuration's injection has no matching allowed-tools"; fail=1
  fi
done
# README
grep -qF -- 'additionalDirectories' README.md || { echo "FAIL: README.md does not mention the run permissions item: additionalDirectories"; fail=1; }

echo "== /next and /fix hand the coding to a subagent"
# /next launches an implementer subagent and /fix a fixer subagent on the configured model (iteration 13): the keys,
# the result block the session reads and the merge command; the wording of the launch is the manual check's.
for pair in "next:implementer" "fix:fixer"; do
  skill=${pair%%:*}; role=${pair##*:}
  f=skills/$skill/SKILL.md
  for w in "roles.$role.model" 'parallel.maxAgents' 'Result: complete | partial | failed' 'gh pr merge'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the subagent item: $w"; fail=1; }
  done
done
for w in 'Cause:' 'Fix:' 'Test:'; do
  grep -qF -- "$w" skills/fix/SKILL.md || { echo "FAIL: skills/fix/SKILL.md: the fixer's result block lacks $w"; fail=1; }
done
# no agent file for the producers: the prompt is in the skill, the default model is in the schema. The agents are
# the worker and the two reviewers (iterations 18 and 20), which need a tool list that keeps them read-only.
for a in agents/*.md; do
  case "$a" in
    agents/worker.md|agents/code-reviewer.md|agents/spec-reviewer.md|agents/tester.md) ;;
    *) echo "FAIL: $a: only the worker, the two reviewers and the tester have an agent file (the implementer's and the fixer's prompts are in the skills)"; fail=1 ;;
  esac
done

echo "== /spec hands the writing to a subagent"
# /spec launches a specWriter subagent on the configured model (iteration 14): the keys, the result block, the merge
# command and the first line of the spec pull request's body, which /spec reads back when it resumes.
f=skills/spec/SKILL.md
for w in 'roles.specWriter.model' 'parallel.maxAgents' 'Result: complete | partial | failed' 'gh pr merge' 'Spec for #'; do
  grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the subagent item: $w"; fail=1; }
done
# a spec pull request says Spec for, never Closes
if grep -qF 'Closes #' "$f"; then
  echo "FAIL: $f tells the session to write 'Closes #'; a spec pull request says 'Spec for #'"; fail=1
fi

echo "== a separate code reviewer reviews the change"
# The code reviewer (iteration 18): an agent file whose name, tool list and model Claude Code reads (the tools keep it
# read-only), the findings block the session parses, the same in the agent file and in the workflow skill, and /next
# and /fix that launch it by its agent type on its key, after the pairing check of the validator.
cr=agents/code-reviewer.md
wf=skills/workflow/SKILL.md
fmt='^(Review: findings \| no findings|Blocking: <n>|Advisory: <n>|- blocking <file>:<line> .*|- advisory <file>:<line> .*)$'
if [ -f "$cr" ]; then
  grep -qx 'name: code-reviewer' "$cr" || { echo "FAIL: $cr has no 'name: code-reviewer'"; fail=1; }
  [ "$(sed -n 's/^tools:[[:space:]]*//p' "$cr" | head -1)" = "Read, Grep, Glob" ] || { echo "FAIL: $cr: the tools must be exactly 'Read, Grep, Glob' (no Bash, Write, Edit or Agent)"; fail=1; }
  json_load schema/nightmill.schema.json
  cr_default=$(json_get properties.roles.properties.codeReviewer.properties.model.default)
  [ "$(sed -n 's/^model:[[:space:]]*//p' "$cr" | head -1)" = "$cr_default" ] || { echo "FAIL: $cr: model is not the schema default of roles.codeReviewer.model ($cr_default)"; fail=1; }
  # the format of the block is the same in the agent file and in the workflow skill
  [ -n "$(grep -E "$fmt" "$cr")" ] || { echo "FAIL: $cr has no line of the findings block"; fail=1; }
  [ "$(grep -E "$fmt" "$wf")" = "$(grep -E "$fmt" "$cr")" ] || { echo "FAIL: the format lines of the findings block differ between $wf and $cr"; fail=1; }
else
  echo "FAIL: $cr is missing"; fail=1
fi
for w in 'review.maxFixRounds' 'validate-config'; do
  grep -qF -- "$w" "$wf" || { echo "FAIL: $wf does not mention the code review item: $w"; fail=1; }
done
for f in skills/next/SKILL.md skills/fix/SKILL.md; do
  for w in 'nightmill:code-reviewer' 'roles.codeReviewer.model' 'validate-config'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the code review item: $w"; fail=1; }
  done
done

echo "== the review is recorded in the pull request"
# A blocking finding that is still open keeps auto-merge off (iteration 19): the pull request body then has a line
# that starts 'Auto-merge is not enabled:', which /next reads when it resumes (its resume table, row N1). The other
# lines of the '## Review' section are written, not parsed, so their wording is the manual check's.
for f in "$wf" skills/next/SKILL.md skills/fix/SKILL.md; do
  grep -qF -- 'Auto-merge is not enabled:' "$f" || { echo "FAIL: $f does not mention the review item: Auto-merge is not enabled:"; fail=1; }
done

echo "== slots free themselves"
# A busy slot whose pull request has merged is freed by -Reap / --reap and by the first step of every take
# (iteration 17), with the tip check and the report text; the README says when it happens.
f=scripts/slot.sh
for w in 'released automatically' 'headRefOid'; do
  grep -qF -- "$w" "$f" || { echo "FAIL: $f does not carry the automatic release item: $w"; fail=1; }
done
grep -qF -- '--reap' README.md || { echo "FAIL: README.md does not mention --reap"; fail=1; }

echo "== capacity is wired"
# The slot count and the agent limit can be changed during a session (iteration 22): both slot scripts keep the live
# values in capacity.json and have the capacity command, the skills read the agent limit from it at every decision to
# start an agent (not once from the configuration), and the README says how and what wins.
f=scripts/slot.sh
grep -qF 'capacity.json' "$f" || { echo "FAIL: $f does not keep the live values in capacity.json"; fail=1; }
grep -qF -- '--capacity' scripts/slot.sh || { echo "FAIL: scripts/slot.sh has no --capacity"; fail=1; }
grep -qF -- '--capacity --porcelain' skills/workflow/SKILL.md || { echo "FAIL: skills/workflow/SKILL.md does not read the agent limit with --capacity --porcelain"; fail=1; }
for f in skills/next/SKILL.md skills/fix/SKILL.md skills/spec/SKILL.md; do
  if ! grep -qF -- '--capacity --porcelain' "$f"; then
    echo "FAIL: $f does not read the agent limit with the capacity command"; fail=1
  fi
done
for w in '--capacity' 'WORKER_SLOTS'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done

echo "== slots report what their agent does"
# A skill that works in a slot records its skill, role, step and the time in the slot's marker (iteration 23): both
# slot scripts have the report command and decide running or stalled from worktrees.stalledAfterMinutes; /status
# prints the agent state the slot script gives (no rule of its own) in one Slots section; /next and /fix report at
# each step; the schema, the example and the README carry the key.
f=scripts/slot.sh
for w in 'reported' 'stalledAfterMinutes'; do
  grep -qF -- "$w" "$f" || { echo "FAIL: $f does not carry the report item: $w"; fail=1; }
done
grep -qF -- '--report' scripts/slot.sh || { echo "FAIL: scripts/slot.sh has no --report"; fail=1; }
f=scripts/lib/status.awk
if grep -qF 'slots: none busy' "$f"; then echo "FAIL: $f still prints 'slots: none busy' (the Slots section lists every slot)"; fail=1; fi
if grep -qF 'stalledAfterMinutes' "$f"; then echo "FAIL: $f reads stalledAfterMinutes (the slot script decides running or stalled)"; fail=1; fi
for f in skills/next/SKILL.md skills/fix/SKILL.md; do
  for w in '--report' 'slot-taken' 'code-review' 'done'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the report item: $w"; fail=1; }
  done
done
grep -qF '"stalledAfterMinutes": { "type": "integer", "minimum": 1, "default": 30,' schema/nightmill.schema.json || { echo "FAIL: the schema has no stalledAfterMinutes with default 30"; fail=1; }
for f in templates/nightmill.example.json README.md; do
  grep -qF 'stalledAfterMinutes' "$f" || { echo "FAIL: $f does not mention stalledAfterMinutes"; fail=1; }
done

echo "== the stage record is wired"
# The time a story spends in each stage is recorded and shown (iteration 41): scripts/slot.sh appends one line per
# take, report and freeing to <worktrees.root>/.slots/ledger.tsv; scripts/stages.sh prints the table;
# tests/check.sh and CI run its smoke test; the README names the record and the script; no skill writes or mentions the record (the scripts that already run write it).
f=scripts/slot.sh
grep -qF 'ledger.tsv' "$f" || { echo "FAIL: $f does not carry the record file: ledger.tsv"; fail=1; }
f=scripts/stages.sh
[ -f "$f" ] || { echo "FAIL: $f does not exist"; fail=1; }
w='smoke-stages.sh'
grep -qF -- "$w" tests/check.sh || { echo "FAIL: tests/check.sh does not run $w"; fail=1; }
for w in 'ledger.tsv' 'stages.sh'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention the stage record item: $w"; fail=1; }
done
if grep -rqF 'ledger.tsv' skills; then
  echo "FAIL: a file in skills/ mentions ledger.tsv (no skill gets longer for the record): $(grep -rlF 'ledger.tsv' skills | tr '\n' ' ')"; fail=1
fi

echo "== history is wired"
# How the work went (iteration 54, #166): the history scripts, the page renderer, both smoke tests and the expected page
# exist; the three history files only read (no board edit, merge, comment, mutation, slot action, browser opener or
# listener) and the page they write links, loads and runs nothing; the README names the command, the page and the JSON
# form of /status; the status skill says how to ask for JSON; no skill names the history script (the maintainer runs it).
for f in scripts/history.sh scripts/lib/history.awk tests/smoke-history.sh tests/fixtures/history/expected.html; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
for f in scripts/history.sh scripts/lib/history.awk; do
  [ -f "$f" ] || continue
  if grep -nE -- 'item-edit|item-add|item-delete|pr merge|issue edit|issue comment|mutation|--take|--release|--abandon|--reap|--report|--capacity|-Take|-Release|-Abandon|-Reap|-Report|-Capacity|Start-Process|xdg-open|HttpListener' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f changes, serves or opens something; the history only reads"; fail=1
  fi
  if grep -nE -- '<script|<link|href|src=|url\(|@import|http-equiv' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f writes a page that links, loads or runs something; the page needs no network"; fail=1
  fi
done
for w in 'history.sh' '--html' 'status.sh --json'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
grep -qF -- '--json' skills/status/SKILL.md || { echo "FAIL: skills/status/SKILL.md does not mention --json"; fail=1; }
if grep -rqF 'history.sh' skills; then
  echo "FAIL: a file in skills/ names history.sh (the history is a script the maintainer runs, not a skill): $(grep -rlF 'history.sh' skills | tr '\n' ' ')"; fail=1
fi

echo "== a tester writes the failing tests first"
# /next has a tester subagent write the failing tests for every acceptance criterion before the implementer (iteration
# 25): an agent file whose name, tool list (no Agent) and model Claude Code reads, the result block /next parses, the
# same test path rule in the agent and in the skill, and /next that launches it by its agent type on its key, checks
# its files with git and sets the tests of unmet criteria aside. The wording of the prompts is the manual check's.
ta=agents/tester.md
nx=skills/next/SKILL.md
if [ -f "$ta" ]; then
  grep -qx 'name: tester' "$ta" || { echo "FAIL: $ta has no 'name: tester'"; fail=1; }
  [ "$(sed -n 's/^tools:[[:space:]]*//p' "$ta" | head -1)" = "Read, Grep, Glob, Write, Edit, Bash" ] || { echo "FAIL: $ta: the tools must be exactly 'Read, Grep, Glob, Write, Edit, Bash' (no Agent)"; fail=1; }
  json_load schema/nightmill.schema.json
  ta_default=$(json_get properties.roles.properties.tester.properties.model.default)
  [ "$(sed -n 's/^model:[[:space:]]*//p' "$ta" | head -1)" = "$ta_default" ] || { echo "FAIL: $ta: model is not the schema default of roles.tester.model ($ta_default)"; fail=1; }
  for w in 'Result: complete | partial | failed' 'Criteria:' 'Tests:' 'Failing:' 'Files:' 'Left:'; do
    grep -qF -- "$w" "$ta" || { echo "FAIL: $ta does not have the result field: $w"; fail=1; }
  done
  # /next and /fix parse the Criteria value not tested
  grep -qF -- 'not tested' "$ta" || { echo "FAIL: $ta does not say: not tested"; fail=1; }
else
  echo "FAIL: $ta is missing"; fail=1
fi
# the test path rule is one line, the same in the agent file and in the skill
tp_re='^[[:space:]]*`?Test paths:'
for f in "$ta" "$nx"; do
  n_tp=$(grep -cE "$tp_re" "$f" 2>/dev/null || true)
  [ "$n_tp" = 1 ] || { echo "FAIL: $f has ${n_tp:-no} lines starting with 'Test paths:' (exactly one expected)"; fail=1; }
done
tp_agent=$(grep -E "$tp_re" "$ta" 2>/dev/null | head -1 | sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//' || true)
tp_next=$(grep -E "$tp_re" "$nx" | head -1 | sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//' || true)
if [ -z "$tp_agent" ] || [ "$tp_agent" != "$tp_next" ]; then
  echo "FAIL: the 'Test paths:' line differs between $ta and $nx"; fail=1
fi
for w in 'nightmill:tester' 'roles.tester.model' 'verification.benchRule' 'status --porcelain --untracked-files=all' \
         'stash list' 'stash pop stash@{<n>}' 'git -C <slot> log origin/<git.baseBranch>..HEAD' \
         '-m "Unmet tests for #<issue>: <title>"' 'unmet: <path> (criterion <n>)'; do
  grep -qF -- "$w" "$nx" || { echo "FAIL: $nx does not mention the tester item: $w"; fail=1; }
done
grep -qF 'agents/tester.md' README.md || { echo "FAIL: README.md does not mention agents/tester.md"; fail=1; }

echo "== a tester reproduces the bug before /fix"
# /fix has the same tester write a regression test from the bug report before the fixer (iteration 26): the same test
# path rule as the agent, the launch by agent type on its key, the git commands that check and set aside its files and
# the step name it reports. The wording of the prompts is the manual check's.
fx=skills/fix/SKILL.md
n_tp=$(grep -cE "$tp_re" "$fx" 2>/dev/null || true)
[ "$n_tp" = 1 ] || { echo "FAIL: $fx has ${n_tp:-no} lines starting with 'Test paths:' (exactly one expected)"; fail=1; }
tp_fix=$(grep -E "$tp_re" "$fx" 2>/dev/null | head -1 | sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//' || true)
if [ -z "$tp_agent" ] || [ "$tp_agent" != "$tp_fix" ]; then
  echo "FAIL: the 'Test paths:' line differs between $ta and $fx"; fail=1
fi
for w in 'nightmill:tester' 'roles.tester.model' 'verification.benchRule' 'status --porcelain --untracked-files=all' \
         'diff --name-only origin/<git.baseBranch>..HEAD' '-m "Tester files for #<issue>: <title>"' 'write-tests'; do
  grep -qF -- "$w" "$fx" || { echo "FAIL: $fx does not mention the tester item: $w"; fail=1; }
done

echo "== the tester's tests are guarded"
# The implementer and the fixer may not change the tester's files (iteration 27): the session records every tester
# file as a blob, checks it after every result with git and undoes a change; a disputed test goes back to the tester,
# whose answer lines the session parses. The git commands, the answer and dispute fields and the stash messages stay;
# the wording of the prompts is the manual check's.
for w in 'revised:' 'stands:' 'Answers:'; do
  grep -qF -- "$w" "$ta" || { echo "FAIL: $ta does not say the dispute item: $w"; fail=1; }
done
for f in "$nx" "$fx"; do
  for w in 'diff --no-index -- /dev/null <path>' 'hash-object -w -- <path>' 'rev-parse -q --verify HEAD:<path>' \
           'merge-base --is-ancestor <round base> HEAD' 'reset --mixed -q <round base>' \
           'update-index --add --cacheinfo <mode>,<blob>,<path>' 'checkout-index -f --' 'dispute-<k>' 'Disputes:'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the guard item: $w"; fail=1; }
  done
done
grep -qF -- '-m "Disputed test for #<issue>: <title>"' "$fx" || { echo "FAIL: $fx does not mention the guard item: -m \"Disputed test for #<issue>: <title>\""; fail=1; }

echo "== the code reviewer reviews the tests"
# The code reviewer judges the tests (iteration 29): a finding whose fix belongs in the tester's tests begins with
# "test: ", which /next and /fix parse to send it to the tester, and its files are named test-finding-<k>.
cr=agents/code-reviewer.md
for f in "$cr" "$nx" "$fx"; do
  grep -qF -- '`test: `' "$f" || { echo "FAIL: $f does not mention the test review item: \`test: \`"; fail=1; }
done
for f in "$nx" "$fx"; do
  grep -qF -- 'test-finding-<k>' "$f" || { echo "FAIL: $f does not mention the test review item: test-finding-<k>"; fail=1; }
done

echo "== a separate spec reviewer reviews the spec"
# The spec reviewer (iteration 20): an agent file whose name, tool list (read-only) and model Claude Code reads, the
# findings block /spec parses (the same format lines as the code reviewer and the workflow skill), and /spec that
# launches it by its agent type on its key, after the pairing check of the validator.
sr=agents/spec-reviewer.md
sfmt='^(Review: findings \| no findings|Blocking: <n>|Advisory: <n>|- blocking <file>:<line> .*|- advisory <file>:<line> .*)$'
if [ -f "$sr" ]; then
  grep -qx 'name: spec-reviewer' "$sr" || { echo "FAIL: $sr has no 'name: spec-reviewer'"; fail=1; }
  [ "$(sed -n 's/^tools:[[:space:]]*//p' "$sr" | head -1)" = "Read, Grep, Glob" ] || { echo "FAIL: $sr: the tools must be exactly 'Read, Grep, Glob' (no Bash, Write, Edit or Agent)"; fail=1; }
  json_load schema/nightmill.schema.json
  sr_default=$(json_get properties.roles.properties.specReviewer.properties.model.default)
  [ "$(sed -n 's/^model:[[:space:]]*//p' "$sr" | head -1)" = "$sr_default" ] || { echo "FAIL: $sr: model is not the schema default of roles.specReviewer.model ($sr_default)"; fail=1; }
  # the format of the block is the same in the three files
  [ -n "$(grep -E "$sfmt" "$sr")" ] || { echo "FAIL: $sr has no line of the findings block"; fail=1; }
  if [ -f agents/code-reviewer.md ] && [ "$(grep -E "$sfmt" agents/code-reviewer.md)" != "$(grep -E "$sfmt" "$sr")" ]; then
    echo "FAIL: the format lines of the findings block differ between agents/code-reviewer.md and $sr"; fail=1
  fi
  if [ "$(grep -E "$sfmt" skills/workflow/SKILL.md)" != "$(grep -E "$sfmt" "$sr")" ]; then
    echo "FAIL: the format lines of the findings block differ between skills/workflow/SKILL.md and $sr"; fail=1
  fi
else
  echo "FAIL: $sr is missing"; fail=1
fi
for w in 'nightmill:spec-reviewer' 'roles.specReviewer.model' 'validate-config'; do
  grep -qF -- "$w" skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not mention the spec review item: $w"; fail=1; }
done

echo "== the spec review is recorded in the spec pull request"
# The spec comment on the issue says 'Waiting for approval.', which /next reads to tell whether the body was edited
# after it (iteration 21), and an open blocking finding puts a line that starts 'Auto-merge is not enabled' in the spec
# pull request's body, which /spec reads when it resumes (its resume table, row S1).
for w in 'Waiting for approval.' 'Auto-merge is not enabled:'; do
  grep -qF -- "$w" skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not mention the spec review item: $w"; fail=1; }
done

lint_specs

echo "== load is wired"
# A read-only command measures CPU load and free memory and suggests an agent limit (iteration 24): both scripts, both
# libraries and both smoke tests exist, the scripts only read, the libraries carry every reader, the schema, the example
# and the README carry the three keys, and the check and CI run the tests.
for f in scripts/load.sh scripts/lib/load.sh tests/smoke-load.sh; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
for f in scripts/load.sh scripts/lib/load.sh; do
  if [ -f "$f" ] && grep -nE 'Set-Content|Out-File|Add-Content|Remove-Item|New-Item|Move-Item|--slot-count|--agent-limit|-SlotCount|-AgentLimit|--clear|-Clear|--take|--release|--abandon|--reap|(^|[^A-Za-z0-9_-])gh +[a-z]' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f writes or changes something; load only reads"; fail=1
  fi
done
f=scripts/lib/load.sh
for w in NIGHTMILL_LOAD_FIXTURE /proc/stat /proc/meminfo MemAvailable vm_stat hw.memsize; do
  grep -qF -- "$w" "$f" 2>/dev/null || { echo "FAIL: $f does not carry the reader item: $w"; fail=1; }
done
json_load schema/nightmill.schema.json
for spec in maxSuggestedAgents:4:1 memoryPerAgentGB:8:1 loadWindowSeconds:10:2; do
  k=${spec%%:*}; rest=${spec#*:}; d=${rest%%:*}; lo=${rest#*:}; p=properties.parallel.properties.$k
  [ "$(json_get "$p.type")" = integer ] || { echo "FAIL: schema: parallel.$k is not an integer"; fail=1; }
  [ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: parallel.$k has no description"; fail=1; }
  [ "$(json_get "$p.default")" = "$d" ] || { echo "FAIL: schema: parallel.$k default is not $d"; fail=1; }
  [ "$(json_get "$p.minimum")" = "$lo" ] || { echo "FAIL: schema: parallel.$k minimum is not $lo"; fail=1; }
done
json_load templates/nightmill.example.json
for spec in maxSuggestedAgents:4 memoryPerAgentGB:8 loadWindowSeconds:10; do
  k=${spec%%:*}; d=${spec#*:}
  [ "$(json_get "parallel.$k")" = "$d" ] || { echo "FAIL: templates/nightmill.example.json: parallel.$k is not the schema default $d"; fail=1; }
done
for w in load.sh maxSuggestedAgents memoryPerAgentGB loadWindowSeconds; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
f=tests/smoke-load.sh
grep -qF NIGHTMILL_LOAD_FIXTURE "$f" 2>/dev/null || { echo "FAIL: $f does not set NIGHTMILL_LOAD_FIXTURE"; fail=1; }
grep -qF 'smoke-load' tests/check.sh || { echo "FAIL: tests/check.sh does not run smoke-load"; fail=1; }

echo "== room is wired"
# A skill checks that the machine has room before it starts an agent (iteration 28): both room scripts and both smoke
# tests exist, the scripts only read and hold back, they measure 3 samples with the library, the schema, the example and
# the README carry the five keys, the rule's script is named in the workflow skill only, and the check and CI run the
# tests.
for f in scripts/room.sh tests/smoke-room.sh; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
f=scripts/room.sh
if [ -f "$f" ] && grep -nE 'Set-Content|Out-File|Add-Content|Remove-Item|New-Item|Move-Item|--slot-count|--agent-limit|-SlotCount|-AgentLimit|--clear|-Clear|--take|--release|--abandon|--reap|(^|[^A-Za-z0-9_-])gh +[a-z]|slot\.sh|--capacity|-Capacity|Stop-Process|taskkill|(^|[^A-Za-z0-9_-])kill( |$)' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
  echo "FAIL: $f writes, changes or stops something, or calls a slot script; room only reads and holds back"; fail=1
fi
for w in 'load_measure 3' 'room_settings' '--since'; do
  grep -qF -- "$w" scripts/room.sh 2>/dev/null || { echo "FAIL: scripts/room.sh does not carry: $w"; fail=1; }
done
json_load schema/nightmill.schema.json
p=properties.parallel.properties.roomCheck
[ "$(json_get "$p.type")" = boolean ] || { echo "FAIL: schema: parallel.roomCheck is not a boolean"; fail=1; }
[ "$(json_get "$p.default")" = true ] || { echo "FAIL: schema: parallel.roomCheck default is not true"; fail=1; }
[ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: parallel.roomCheck has no description"; fail=1; }
for spec in roomMinFreeMB:2000 roomMaxCpuPercent:90 roomPauseSeconds:60 roomMaxWaitMinutes:30; do
  k=${spec%%:*}; d=${spec#*:}; p=properties.parallel.properties.$k
  [ "$(json_get "$p.type")" = integer ] || { echo "FAIL: schema: parallel.$k is not an integer"; fail=1; }
  [ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: parallel.$k has no description"; fail=1; }
  [ "$(json_get "$p.default")" = "$d" ] || { echo "FAIL: schema: parallel.$k default is not $d"; fail=1; }
  [ "$(json_get "$p.minimum")" = 1 ] || { echo "FAIL: schema: parallel.$k minimum is not 1"; fail=1; }
done
json_load templates/nightmill.example.json
for spec in roomCheck:true roomMinFreeMB:2000 roomMaxCpuPercent:90 roomPauseSeconds:60 roomMaxWaitMinutes:30; do
  k=${spec%%:*}; d=${spec#*:}
  [ "$(json_get "parallel.$k")" = "$d" ] || { echo "FAIL: templates/nightmill.example.json: parallel.$k is not the schema default $d"; fail=1; }
done
# the workflow skill runs the script and stops with a line whose prefix 'Stopped: ' the driver reads (scripts/drive.sh)
for w in 'scripts/room.sh' 'Stopped: '; do
  grep -qF -- "$w" skills/workflow/SKILL.md || { echo "FAIL: skills/workflow/SKILL.md does not say: $w"; fail=1; }
done
for s in skills/next/SKILL.md skills/fix/SKILL.md skills/spec/SKILL.md; do
  for w in room.sh roomMin; do
    if grep -qF -- "$w" "$s"; then echo "FAIL: $s names $w (the rule lives in the workflow skill only)"; fail=1; fi
  done
done
for w in room.sh roomCheck roomMinFreeMB roomMaxCpuPercent roomPauseSeconds roomMaxWaitMinutes; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
f=tests/smoke-room.sh
grep -qF NIGHTMILL_LOAD_FIXTURE "$f" 2>/dev/null || { echo "FAIL: $f does not set NIGHTMILL_LOAD_FIXTURE"; fail=1; }
grep -qF 'smoke-room' tests/check.sh || { echo "FAIL: tests/check.sh does not run smoke-room"; fail=1; }

echo "== control is wired"
# An opt-in controller adjusts the agent limit from the measured load (iteration 30): both control scripts, the skill and
# both smoke tests exist, the scripts change the numbers only through the slot script and stop nothing, the libraries
# read the five keys, the schema, the example and the README carry them, and the check and CI run the tests.
for f in scripts/control.sh skills/control/SKILL.md tests/smoke-control.sh; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
f=scripts/control.sh
if [ -f "$f" ]; then
  if grep -nE 'Set-Content|Out-File|Add-Content|Remove-Item|New-Item|Move-Item|Copy-Item|WriteAll|IO\.File\]::|json_marker|--clear|--take|--release|--abandon|--reap|--report|Stop-Process|taskkill|(^|[^A-Za-z0-9_-])gh +[a-z]|(^|[^A-Za-z0-9_-])kill( |$)|(^|[^A-Za-z0-9_-])(mv|cp|tee|mkdir) ' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f writes, removes or stops something; control changes the numbers only through the slot script"; fail=1
  fi
fi
for w in '--capacity' '--agent-limit' '--slot-count' 'load_measure' 'load_suggest' 'control_settings' 'NIGHTMILL_NOW'; do
  grep -qF -- "$w" scripts/control.sh 2>/dev/null || { echo "FAIL: scripts/control.sh does not carry: $w"; fail=1; }
done
for w in control_settings controlMode; do
  grep -qF -- "$w" scripts/lib/load.sh || { echo "FAIL: scripts/lib/load.sh does not carry: $w"; fail=1; }
done
json_load schema/nightmill.schema.json
p=properties.parallel.properties.controlMode
[ "$(json_get "$p.type")" = string ] || { echo "FAIL: schema: parallel.controlMode is not a string"; fail=1; }
[ "$(json_get "$p.default")" = off ] || { echo "FAIL: schema: parallel.controlMode default is not off"; fail=1; }
[ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: parallel.controlMode has no description"; fail=1; }
if [ "$(json_len "$p.enum")" != 3 ] || [ "$(json_get "$p.enum[0]")" != off ] || [ "$(json_get "$p.enum[1]")" != report ] || [ "$(json_get "$p.enum[2]")" != apply ]; then
  echo "FAIL: schema: parallel.controlMode enum is not off, report, apply"; fail=1
fi
for spec in controlMinAgents:1 controlMaxAgents:4 controlCooldownMinutes:15 controlIntervalMinutes:5; do
  k=${spec%%:*}; d=${spec#*:}; p=properties.parallel.properties.$k
  [ "$(json_get "$p.type")" = integer ] || { echo "FAIL: schema: parallel.$k is not an integer"; fail=1; }
  [ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: parallel.$k has no description"; fail=1; }
  [ "$(json_get "$p.default")" = "$d" ] || { echo "FAIL: schema: parallel.$k default is not $d"; fail=1; }
  [ "$(json_get "$p.minimum")" = 1 ] || { echo "FAIL: schema: parallel.$k minimum is not 1"; fail=1; }
done
json_load templates/nightmill.example.json
for spec in controlMode:off controlMinAgents:1 controlMaxAgents:4 controlCooldownMinutes:15 controlIntervalMinutes:5; do
  k=${spec%%:*}; d=${spec#*:}
  [ "$(json_get "parallel.$k")" = "$d" ] || { echo "FAIL: templates/nightmill.example.json: parallel.$k is not the schema default $d"; fail=1; }
done
s=skills/control/SKILL.md
if [ -f "$s" ]; then
  for w in 'scripts/control.sh' 'control: next pass in'; do
    grep -qF -- "$w" "$s" || { echo "FAIL: $s does not say: $w"; fail=1; }
  done
  for w in 'nightmill.json' '--agent-limit' '-AgentLimit' '--slot-count' '-SlotCount'; do
    if grep -qF -- "$w" "$s"; then echo "FAIL: $s names $w (the skill changes nothing itself)"; fail=1; fi
  done
fi
for w in /nightmill:control control.sh /loop controlMode controlMinAgents controlMaxAgents controlCooldownMinutes controlIntervalMinutes; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
f=tests/smoke-control.sh
for w in NIGHTMILL_LOAD_FIXTURE NIGHTMILL_NOW; do
  grep -qF "$w" "$f" 2>/dev/null || { echo "FAIL: $f does not set $w"; fail=1; }
done
grep -qF 'smoke-control' tests/check.sh || { echo "FAIL: tests/check.sh does not run smoke-control"; fail=1; }

echo "== dashboard is wired"
# A page in the browser shows the slots and what waits (iteration 31): the dashboard scripts, the renderer, both smoke
# tests and the expected page exist; the three dashboard files only read (no slot action, no gh call, no listener, no
# browser opener, nothing on the page that links, loads or acts); they carry the refresh, the escaping, the clock and
# the porcelain call; status has its porcelain form; the schema, the example and the README carry the key; the check
# and CI run the tests.
for f in scripts/dashboard.sh scripts/lib/dashboard.awk tests/smoke-dashboard.sh tests/fixtures/dashboard/run-stall-old-free/expected.html; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
for f in scripts/dashboard.sh scripts/lib/dashboard.awk; do
  [ -f "$f" ] || continue
  if grep -nE -- '--take|--release|--abandon|--reap|--report|--capacity|-Take|-Release|-Abandon|-Reap|-Report|-Capacity|item-edit|pr merge|issue edit|issue comment|mutation|(^|[^A-Za-z0-9_-])gh +[a-z]|HttpListener|TcpListener|socat|nc -l|http\.server|Start-Process|xdg-open|open http|cmd /c start|<form|<button|<input|<a |href|src=|<link|@import|url\(|fetch\(|XMLHttpRequest|WebSocket|localStorage|sessionStorage' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f changes, serves, opens or links something; the dashboard only reads and shows"; fail=1
  fi
done
f=scripts/lib/dashboard.awk
for w in 'http-equiv="refresh"' '&amp;' '&lt;' '&gt;' '&quot;' '&#39;'; do
  grep -qF -- "$w" "$f" 2>/dev/null || { echo "FAIL: $f does not carry: $w"; fail=1; }
done
f=scripts/dashboard.sh
for w in NIGHTMILL_NOW dashboardRefreshSeconds stalledAfterMinutes; do
  grep -qF -- "$w" "$f" 2>/dev/null || { echo "FAIL: $f does not carry: $w"; fail=1; }
done
grep -qF -- 'status.sh" --porcelain' scripts/dashboard.sh 2>/dev/null || { echo "FAIL: scripts/dashboard.sh does not call status.sh --porcelain"; fail=1; }
grep -qF -- '--porcelain)' scripts/status.sh || { echo "FAIL: scripts/status.sh has no --porcelain"; fail=1; }
grep -qF -- '"dashboardRefreshSeconds": { "type": "integer", "minimum": 10, "default": 60,' schema/nightmill.schema.json || { echo "FAIL: schema: worktrees.dashboardRefreshSeconds is not an integer of at least 10, default 60"; fail=1; }
json_load templates/nightmill.example.json
[ "$(json_get worktrees.dashboardRefreshSeconds)" = 60 ] || { echo "FAIL: templates/nightmill.example.json: worktrees.dashboardRefreshSeconds is not 60"; fail=1; }
for w in dashboard.sh dashboardRefreshSeconds --porcelain; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
grep -qF 'smoke-dashboard' tests/check.sh || { echo "FAIL: tests/check.sh does not run smoke-dashboard"; fail=1; }

echo "== slots pane is wired"
# A pane beside the Claude chat shows the slots (iteration 32): a hooks module named under "modules" in hooks.json,
# the panel scripts it runs, their smoke tests and the expected records exist; the module and the scripts only read
# (no button, input, select or link, no file, store, state, prompt, tool, agent, http or model call, no slot action, no
# gh call, no reader of the slot markers); the scripts carry the porcelain call, the clock and the interval key; the
# schema, the example and the README carry the key; the check and CI run the tests. Each phrase stands
# on one line of its file.
for f in hooks/panel.tsx hooks/panel.test.tsx scripts/panel.sh tests/smoke-panel.sh tests/fixtures/panel/run-stall-old-free/expected.txt tests/fixtures/panel/run-stall-old-free/markers.txt; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
grep -qF '"modules": ["./panel.tsx"]' hooks/hooks.json 2>/dev/null || { echo "FAIL: hooks/hooks.json does not name the module: \"modules\": [\"./panel.tsx\"]"; fail=1; }
grep -q '"SessionStart"' hooks/hooks.json 2>/dev/null || { echo "FAIL: hooks/hooks.json lost its SessionStart hook"; fail=1; }
for w in 'nightmill-slots' 'scripts/panel.sh' '$.clock.every(' '$.ui.open(' "'unknown'"; do
  grep -qF -- "$w" hooks/panel.tsx 2>/dev/null || { echo "FAIL: hooks/panel.tsx does not carry: $w"; fail=1; }
done
# outside comment lines the module draws nothing that can be pressed and reaches nothing but the panel script
if [ -f hooks/panel.tsx ]; then
  panel_code=$(grep -vE '^[[:space:]]*(//|/\*|\*)' hooks/panel.tsx || true)
  for w in Button Input Select Link onPress '$.fs.' '$.store.' '$.state.' '$.prompt.' '$.tool.' '$.agent.' '$.http.' '$.model.' '$.command.run' '$.session.append' 'slot.sh' '.slots'; do
    if printf '%s\n' "$panel_code" | grep -F -- "$w" >/dev/null; then echo "FAIL: hooks/panel.tsx uses $w outside a comment; the pane is read-only and runs only the panel script"; fail=1; fi
  done
fi
grep -qF -- 'slot.sh" --status --porcelain' scripts/panel.sh 2>/dev/null || { echo "FAIL: scripts/panel.sh does not call slot.sh --status --porcelain"; fail=1; }
f=scripts/panel.sh
for w in panelRefreshSeconds NIGHTMILL_NOW; do
  grep -qF -- "$w" "$f" 2>/dev/null || { echo "FAIL: $f does not carry: $w"; fail=1; }
done
if [ -f "$f" ]; then
  panel_script=$(grep -vE '^[[:space:]]*#' "$f" || true)
  for w in '.slots' '--take' '--release' '--abandon' '--reap' '--report' '--capacity' '-Take' '-Release' '-Abandon' '-Reap' '-Report' '-Capacity'; do
    if printf '%s\n' "$panel_script" | grep -F -- "$w" >/dev/null; then echo "FAIL: $f uses $w outside a comment; the panel script only reads through slot --status --porcelain"; fail=1; fi
  done
  if printf '%s\n' "$panel_script" | grep -E '(^|[^A-Za-z0-9_-])gh +[a-z]' >/dev/null; then echo "FAIL: $f calls gh; the panel needs no gh"; fail=1; fi
fi
grep -qF '"panelRefreshSeconds": { "type": "integer", "minimum": 5, "default": 15,' schema/nightmill.schema.json || { echo "FAIL: schema: worktrees.panelRefreshSeconds is not an integer of at least 5, default 15"; fail=1; }
json_load templates/nightmill.example.json
[ "$(json_get worktrees.panelRefreshSeconds)" = 15 ] || { echo "FAIL: templates/nightmill.example.json: worktrees.panelRefreshSeconds is not 15"; fail=1; }
for w in /nightmill-slots panelRefreshSeconds; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
grep -qF -- smoke-panel tests/check.sh || { echo "FAIL: tests/check.sh does not carry: smoke-panel"; fail=1; }
for f in tests/check.sh .github/workflows/ci.yml; do
  grep -qF -- 'claude plugin test' "$f" || { echo "FAIL: $f does not carry: claude plugin test"; fail=1; }
done
for w in 'claude plugin test --help' 'claude plugin test not available'; do
  grep -qF -- "$w" tests/check.sh || { echo "FAIL: tests/check.sh does not carry: $w"; fail=1; }
done

echo "== temporary files have a template"
# Bug 115: on macOS a call without a template ignores $TMPDIR and lands in /var/folders, which a sandbox denies; every
# call names a template under ${TMPDIR:-/tmp} (for example "${TMPDIR:-/tmp}/nightmill.XXXXXX").
bare_tmp=$(grep -nE '(^|[^A-Za-z0-9_.-])mktemp( -d)?[ ]*([)`;|&]|$)' scripts/*.sh scripts/lib/*.sh tests/*.sh | grep -vE '^[^:]+:[0-9]+:[ ]*#' | grep -vF 'command -v mktemp' || true)
if [ -n "$bare_tmp" ]; then
  echo "FAIL: mktemp without a template (use a template under \${TMPDIR:-/tmp}):"; printf '%s\n' "$bare_tmp"; fail=1
fi

echo "== the check starts the longest steps first"
# Iteration 42, decision 1 (and #279): exactly the longest steps of a CI run carry the mark 'first' in the step list of
# tests/check.sh, so with a limit above 1 they start before all others and the total is set by the slowest step.
# A mark is any field from the fourth on (iteration 70: the CI marks may follow 'first'), so the names are compared.
firsts=$(awk '/^# steps: begin$/ { p = 1; next } /^# steps: end$/ { p = 0 } p { for (i = 4; i <= NF; i++) if ($i == "first") print $3 }' tests/check.sh | tr '\n' '|')
want_firsts="smoke-slot.sh|test-spec-template.sh|"
if [ "$firsts" != "$want_firsts" ]; then
  echo "FAIL: tests/check.sh: the steps marked first are not exactly the longest steps (docs/specs/iteration-42-parallel-check.md, decision 1): $firsts"; fail=1
fi
grep -qF 'k_first[i]}" = first' tests/check.sh || { echo "FAIL: tests/check.sh does not start the steps marked first first"; fail=1; }

echo "== the check runs every smoke script"
# Iteration 42, decision 11: the step list of tests/check.sh (between '# steps: begin' and '# steps: end') runs every
# smoke script once, in its own shell; the check has one place that prints the all-passed line; the key and the quick
# mode are wired in the schema, the example, the README, the contributor guide and the skills; and CI runs its smoke
# jobs through tests/check.sh $CHECK_SELECT (--only, or --affected --within on a pull request) and the groups of the
# check (iteration 70): the bash job @with-jq, then @without-jq after it hides jq, the Git Bash parts @gitbash-<k> (checked
# in the next section but one), and no other job name begins with a required one. No step is named in the workflow:
# the step list is the only list, its bash lines are in name order, and every tests/smoke-*.sh is a step and every
# tests/test-*.sh a step or started by this lint (a test file must run somewhere).
chk_block=""
chk_nb=$(grep -cx '# steps: begin' tests/check.sh || true)
chk_ne=$(grep -cx '# steps: end' tests/check.sh || true)
chk_lb=$(grep -nx '# steps: begin' tests/check.sh | head -n 1 | cut -d: -f1 || true)
chk_le=$(grep -nx '# steps: end' tests/check.sh | head -n 1 | cut -d: -f1 || true)
if [ "$chk_nb" = 1 ] && [ "$chk_ne" = 1 ] && [ "$chk_le" -gt "$chk_lb" ]; then
  chk_block=$(sed -n "$((chk_lb + 1)),$((chk_le - 1))p" tests/check.sh | grep -v '^[[:space:]]*$' || true)
  # the marks in their order (iteration 70); the CI marks on bash lines only, never nogitbash with alone
  if printf '%s\n' "$chk_block" | grep -vE '^add (lint|bash) [A-Za-z0-9._-]+( first)?( slow)?( jq)?( nogitbash)?( alone)?$' >/dev/null ||
    printf '%s\n' "$chk_block" | grep -E '^add lint .* (jq|nogitbash|alone)( |$)| nogitbash alone$' >/dev/null; then chk_block=""; fi
fi
if [ -z "$chk_block" ]; then
  echo "FAIL: tests/check.sh: the step list between '# steps: begin' and '# steps: end' is missing or malformed"; fail=1
else
  # Iteration 62, decision 8 rule 2: exactly the slow steps of decision 4 carry the mark 'slow' (a lint line never)
  chk_slows=$(printf '%s\n' "$chk_block" | awk '{ for (i = 4; i <= NF; i++) if ($i == "slow") print $2 " " $3 }' | tr '\n' '|')
  want_slows="bash test-lintcopy-output.sh|"
  if [ "$chk_slows" != "$want_slows" ]; then
    echo "FAIL: tests/check.sh: the steps marked slow are not exactly the slow steps (docs/specs/iteration-62-slow-tests-out-of-check.md, decision 4): $chk_slows"; fail=1
  fi
  # Iteration 62, decision 8 rule 3: every profiled step (decision 1) and every slow step says in a '# Time: ' line of
  # its header where its time goes; one awk pass over the files (bug #270: no process per line)
  chk_prof=""
  for b in $(printf '%s\n' "$chk_block" | awk '{ for (i = 4; i <= NF; i++) if ($i == "slow") print $3 }'); do
    case " $chk_prof " in *" tests/$b "*) ;; *) chk_prof="$chk_prof tests/$b" ;; esac
  done
  # shellcheck disable=SC2086
  while IFS= read -r x; do
    echo "FAIL: $x has no '# Time: ' note in its header (docs/specs/iteration-62-slow-tests-out-of-check.md, decision 1)"; fail=1
  done < <(awk '
    FNR == 1 { if (prev != "" && !hit) print prev; prev = FILENAME; hit = 0; head = 1; sub(/^\357\273\277/, "") }
    { sub(/\r$/, "") }
    head && !/^#/ { head = 0 }
    head && /^# Time: / { hit = 1 }
    END { if (prev != "" && !hit) print prev }' $chk_prof 2>/dev/null </dev/null)
  # every smoke file is a step, once; a test file is a step, once, or started by a line of this lint that is no
  # comment (iteration 70). One awk pass each for the counts and the starts (bug #270: no process per file).
  chk_counts=$(printf '%s\n' "$chk_block" | awk '$2 == "bash" { c[$3]++ } END { printf "|"; for (k in c) printf "%s:%d|", k, c[k] }')
  chk_started="|$(awk '{ l = $0; sub(/^[[:space:]]+/, "", l); if (l ~ /^#/) next
      while (match(l, /bash tests\/[A-Za-z0-9._-]+/)) { print substr(l, RSTART + 11, RLENGTH - 11); l = substr(l, RSTART + RLENGTH) } }' tests/lint.sh | tr '\n' '|')"
  for f in tests/smoke-*.sh tests/test-*.sh; do
    [ -f "$f" ] || continue
    b=${f#tests/}
    case $chk_counts in
      *"|$b:1|"*) ;;
      *"|$b:"*) echo "FAIL: tests/check.sh runs tests/$b more than once"; fail=1 ;;
      *) case $b in
           smoke-*) echo "FAIL: tests/check.sh does not run tests/$b"; fail=1 ;;
           *) case $chk_started in *"|$b|"*) ;; *) echo "FAIL: tests/$b runs nowhere: it is no step of tests/check.sh and tests/lint.sh does not start it"; fail=1 ;; esac ;;
         esac ;;
    esac
  done
  # the bash lines in name order (decision 2): the first that is not after the one before it
  chk_order=$(printf '%s\n' "$chk_block" | LC_ALL=C awk '$2 == "bash" { if (prev != "" && !($3 > prev)) { print $3 " comes after " prev; exit } prev = $3 }')
  [ -z "$chk_order" ] || { echo "FAIL: tests/check.sh: the bash steps of the step list are not in name order: $chk_order"; fail=1; }
  while read -r _ k b _; do
    case $k in bash) [ -f "tests/$b" ] || { echo "FAIL: tests/check.sh runs tests/$b, which does not exist"; fail=1; } ;; esac
  done <<<"$chk_block"
  printf '%s\n' "$chk_block" | grep -x 'add lint lint' >/dev/null || { echo "FAIL: tests/check.sh does not run the lint"; fail=1; }
fi
chk_np=$(grep -o 'ALL CHECKS PASSED' tests/check.sh | wc -l | tr -d ' ')
[ "$chk_np" = 1 ] || { echo "FAIL: tests/check.sh prints ALL CHECKS PASSED in more than one place"; fail=1; }
grep -qF '"checkJobs"' schema/nightmill.schema.json || { echo "FAIL: schema/nightmill.schema.json does not mention \"checkJobs\""; fail=1; }
json_load templates/nightmill.example.json
[ "$(json_get verification.checkJobs)" = 4 ] || { echo "FAIL: templates/nightmill.example.json does not mention verification.checkJobs 4"; fail=1; }
# Iteration 56 (#307): verification.platform is wired in the schema, the example, the README, the init skill and the check
json_load schema/nightmill.schema.json
pf=properties.verification.properties.platform
[ "$(json_get "$pf.type")" = string ] || { echo "FAIL: schema: verification.platform is not a string"; fail=1; }
[ "$(json_get "$pf.default")" = all ] || { echo "FAIL: schema: verification.platform default is not all"; fail=1; }
[ -n "$(json_get "$pf.description")" ] || { echo "FAIL: schema: verification.platform has no description"; fail=1; }
for j in 0 1 2; do
  case $j in 0) m=all ;; 1) m=windows ;; 2) m=unix ;; esac
  [ "$(json_get "$pf.enum[$j]")" = "$m" ] || { echo "FAIL: schema: verification.platform enum[$j] is not $m"; fail=1; }
done
json_load templates/nightmill.example.json
[ "$(json_get verification.platform)" = all ] || { echo "FAIL: templates/nightmill.example.json does not mention verification.platform all"; fail=1; }
for fw in 'README.md' 'skills/init/SKILL.md' 'tests/check.sh'; do
  grep -qF -- 'verification.platform' "$fw" || { echo "FAIL: $fw does not mention verification.platform"; fail=1; }
done
grep -E '^\| `verification` \|.*`platform`' README.md >/dev/null || { echo "FAIL: README.md: the verification row of the configuration table does not mention platform"; fail=1; }
for fw in 'README.md|checkJobs' 'README.md|--quick' 'CONTRIBUTING.md|--quick' \
  'skills/workflow/SKILL.md|--quick' 'skills/workflow/SKILL.md|check: QUICK' 'skills/next/SKILL.md|--quick' \
  'skills/next/SKILL.md|check: QUICK' 'skills/fix/SKILL.md|--quick' 'skills/fix/SKILL.md|check: QUICK' \
  'skills/check/SKILL.md|--quick' 'skills/check/SKILL.md|check: QUICK'; do
  grep -qF -- "${fw#*|}" "${fw%%|*}" || { echo "FAIL: ${fw%%|*} does not mention ${fw#*|}"; fail=1; }
done
chk_ci=.github/workflows/ci.yml
# Iteration 70, decision 5 (in place of iteration 60, decision 8 rule 5): the bash job has two check lines with
# $CHECK_SELECT, the group @with-jq before the step that hides jq, the group @without-jq after it; --only and --affected
# occur only in the env line of CHECK_SELECT. Iteration 64, decision 6: the two lines are counted in the job smoke-bash
# only (from "  smoke-bash:" to the next line that starts with two spaces and a letter), so the Git Bash job's check line
# of the same shape does not count; one awk reads the file once (bug #270)
chk_sel='run: bash tests/check.sh --summary "$GITHUB_STEP_SUMMARY" $CHECK_SELECT '
chk_bash_lines=$(awk -v sel="$chk_sel" '
  /^  smoke-bash:/ { in_job = 1; next }
  in_job && /^  [A-Za-z]/ { in_job = 0 }
  in_job { s = $0; sub(/^[[:space:]]*(- )?/, "", s); if (index(s, sel) == 1) print NR ":" $0 }' "$chk_ci" || true)
chk_hide=$(grep -nE '^[[:space:]]*- name: Hide jq' "$chk_ci" | head -n 1 | cut -d: -f1 || true)
chk_l1=$(printf '%s\n' "$chk_bash_lines" | sed -n 1p); chk_l2=$(printf '%s\n' "$chk_bash_lines" | sed -n 2p)
if [ "$(printf '%s' "$chk_bash_lines" | grep -c . || true)" != 2 ] || [ -z "$chk_hide" ] ||
  [ "${chk_l1##*"$chk_sel"}" != @with-jq ] || [ "${chk_l1%%:*}" -ge "$chk_hide" ] ||
  [ "${chk_l2##*"$chk_sel"}" != @without-jq ] || [ "${chk_l2%%:*}" -le "$chk_hide" ]; then
  echo "FAIL: $chk_ci: the bash smoke job does not run tests/check.sh --summary \"\$GITHUB_STEP_SUMMARY\" \$CHECK_SELECT @with-jq, then @without-jq after it hides jq"; fail=1
fi
# no step name in the workflow, comments included (iteration 70, decision 5): CI takes its steps from the step list
chk_names=$(printf '%s\n' "$chk_block" | awk '$2 == "bash" { printf "%s ", $3 }')
while IFS= read -r x; do
  [ -z "$x" ] || { echo "FAIL: $chk_ci names the step $x (CI takes its steps from the step list of tests/check.sh)"; fail=1; }
done < <(awk -v names="$chk_names" 'BEGIN { k = split(names, nm, " ") }
  { for (i = 1; i <= k; i++) if (!(nm[i] in hit) && index($0, nm[i])) { hit[nm[i]] = 1; o[++no] = nm[i] } }
  END { for (i = 1; i <= no; i++) print o[i] }' "$chk_ci")
chk_env_line="  CHECK_SELECT: \${{ github.event_name == 'pull_request' && '--affected --within' || '--only' }}"
if grep -E -e '--only|--affected' "$chk_ci" | grep -vxF -- "$chk_env_line" >/dev/null; then
  echo "FAIL: $chk_ci: --only or --affected occurs outside the env line of CHECK_SELECT"; fail=1
fi
while IFS= read -r l; do
  x=$(printf '%s\n' "$l" | grep -oE 'tests/smoke-[A-Za-z0-9._-]+' | head -n 1 || true)
  echo "FAIL: $chk_ci runs ${x:-a smoke file} outside tests/check.sh"; fail=1
done < <(grep -E 'run: bash tests/smoke-|-File tests/smoke-' "$chk_ci" || true)
for req in 'Lint (generic, JSON, skills, shell)' 'bash scripts smoke tests' 'Git Bash scripts smoke tests'; do
  [ "$(grep -cxF -- "    name: $req" "$chk_ci" || true)" = 1 ] || { echo "FAIL: $chk_ci: the required job $req is missing"; fail=1; }
done
# a job name that begins with a required name would add a check such as 'bash scripts smoke tests (1)' (iteration 55, decision 5)
while IFS= read -r l; do
  l=${l%$'\r'}; t="${l#"${l%%[![:space:]]*}"}"; t=${t#- }; t=${t#name: }
  for req in 'Lint (generic, JSON, skills, shell)' 'bash scripts smoke tests' 'Git Bash scripts smoke tests'; do
    [ "$l" != "    name: $req" ] || continue
    case $t in "$req"*) echo "FAIL: $chk_ci: the job name '$t' begins with the required name '$req'"; fail=1 ;; esac
  done
done < <(grep -E '^[[:space:]]*(- )?name: ' "$chk_ci" || true)

echo "== every script and every test step is in the map"
# Iteration 59, decision 7: the map of tests/check.sh --affected (between '# affects: begin' and '# affects: end') is
# well formed, names only steps, names every bash step, maps every script and
# every file under tests/fixtures/ (bug #379), holds
# the shared and lintonly lines of decision 3, and the skills and the README describe the mode. The matching is the
# case pattern of the check, in this process (bug #270: no process per path).
aff_block=""
aff_nb=$(grep -cx '# affects: begin' tests/check.sh || true)
aff_ne=$(grep -cx '# affects: end' tests/check.sh || true)
aff_lb=$(grep -nx '# affects: begin' tests/check.sh | head -n 1 | cut -d: -f1 || true)
aff_le=$(grep -nx '# affects: end' tests/check.sh | head -n 1 | cut -d: -f1 || true)
if [ "$aff_nb" = 1 ] && [ "$aff_ne" = 1 ] && [ "$aff_le" -gt "$aff_lb" ]; then
  aff_block=$(sed -n "$((aff_lb + 1)),$((aff_le - 1))p" tests/check.sh | grep -v '^[[:space:]]*$' || true)
  if printf '%s\n' "$aff_block" | grep -vE '^(map [^ ]+ [^ ].*|shared [^ ]+|lintonly [^ ]+)$' >/dev/null; then aff_block=""; fi
fi
if [ -z "$aff_block" ]; then
  echo "FAIL: tests/check.sh: the map between '# affects: begin' and '# affects: end' is missing or malformed"; fail=1
else
  aff_n=0
  while IFS= read -r l; do
    aff_kind[aff_n]=${l%% *}; r=${l#* }; aff_steps[aff_n]=""
    if [ "${aff_kind[aff_n]}" = map ]; then aff_pat[aff_n]=${r%% *}; aff_steps[aff_n]=",${r#* },"; else aff_pat[aff_n]=$r; fi
    aff_n=$((aff_n + 1))
  done <<<"$aff_block"
  # the steps of the list, in list order, then the two claude steps
  aff_names=()
  while read -r _ k b _; do [ -z "$b" ] || aff_names+=("$b"); done <<<"$chk_block"
  aff_names+=("claude plugin validate" "claude plugin test")
  aff_all="|"; for b in "${aff_names[@]}"; do aff_all="$aff_all$b|"; done
  # rule 2: every name of a map line is a step
  for ((j = 0; j < aff_n; j++)); do
    [ "${aff_kind[j]}" = map ] || continue
    r=${aff_steps[j]#,}
    while [ -n "$r" ]; do
      x=${r%%,*}; r=${r#*,}
      case $aff_all in *"|$x|"*) ;; *) echo "FAIL: tests/check.sh: the map names $x, which is not a step"; fail=1 ;; esac
    done
  done
  # rule 3: every bash step is named by a map line
  while read -r _ k b _; do
    case $k in bash) ;; *) continue ;; esac
    hit=""
    for ((j = 0; j < aff_n; j++)); do case ${aff_steps[j]} in *",$b,"*) hit=1; break ;; esac; done
    [ -n "$hit" ] || { echo "FAIL: tests/check.sh: no path maps to the step $b"; fail=1; }
  done <<<"$chk_block"
  # aff_select <path>: aff_got is what the path selects by decision 4: 'shared', or its steps in list order
  aff_select() {
    local p=$1 j x names="," shared=""
    for ((j = 0; j < aff_n; j++)); do
      # shellcheck disable=SC2254
      case $p in
        ${aff_pat[j]})
          case ${aff_kind[j]} in shared) shared=1 ;; map) names="$names${aff_steps[j]#,}" ;; esac ;;
      esac
    done
    if [ -n "$shared" ]; then aff_got=shared; return; fi
    aff_got=""
    for x in "${aff_names[@]}"; do case $names in *",$x,"*) aff_got="$aff_got,$x" ;; esac; done
  }
  # rule 4: every script maps to a step or is shared
  for f in scripts/*.sh scripts/lib/*; do
    [ -f "$f" ] || continue
    aff_select "$f"
    [ -n "$aff_got" ] || { echo "FAIL: tests/check.sh: $f maps to no step"; fail=1; }
  done
  # rule 4b (bug #379): every file under tests/fixtures/ maps to a step, is shared or is lintonly, else a change to it
  # makes --affected run the full check; one failure per fixture directory, naming the path
  aff_fixdirs="|"
  if [ -d tests/fixtures ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      fd=${f#tests/fixtures/}; fd=tests/fixtures/${fd%%/*}
      case $aff_fixdirs in *"|$fd|"*) continue ;; esac
      aff_select "$f"
      if [ -z "$aff_got" ]; then
        for ((j = 0; j < aff_n; j++)); do
          [ "${aff_kind[j]}" = lintonly ] || continue
          # shellcheck disable=SC2254
          case $f in ${aff_pat[j]}) aff_got=lintonly; break ;; esac
        done
      fi
      [ -n "$aff_got" ] || { echo "FAIL: tests/check.sh: $f is in no line of the map (add a line: map $fd/* <the steps that read it>)"; fail=1; aff_fixdirs="$aff_fixdirs$fd|"; }
    done < <(find tests/fixtures -type f | LC_ALL=C sort)
  fi
  # rule 6: the lines of decision 3
  # (iteration 60, decision 7: a change to the workflow runs every step of every list; iteration 62, decision 6: a
  # release pull request, which always changes plugin.json, runs every step, the slow ones too)
  for l in 'shared scripts/lib/*' 'shared tests/check.sh' 'shared tests/check.ps1' 'lintonly docs/*' 'shared .github/workflows/*' 'shared .claude-plugin/plugin.json'; do
    case $'\n'"$aff_block"$'\n' in *$'\n'"$l"$'\n'*) ;; *) echo "FAIL: tests/check.sh: the map does not have the line $l"; fail=1 ;; esac
  done
fi
# rule 7: the skills and the README describe the mode
for fw in 'skills/workflow/SKILL.md|--affected' 'skills/workflow/SKILL.md|check: AFFECTED' \
  'skills/check/SKILL.md|--affected' 'skills/check/SKILL.md|check: AFFECTED' 'README.md|--affected'; do
  grep -qF -- "${fw#*|}" "${fw%%|*}" || { echo "FAIL: ${fw%%|*} does not mention ${fw#*|}"; fail=1; }
done

echo "== the CI parts are well formed"
# Rules 7 to 11 of tests/test-ci-parts.sh (iterations 55, 64, 66, 68 and 70): the final job smoke-gitbash has a Job
# times step, and only it has a job-level permissions block (rules 7 and 8); the Git Bash parts and their run step, and
# the final job that fails unless every part succeeded (rules 10a and 10b); rule 11 pins the CI marks of the step list
# (jq, nogitbash, alone) to the steps earlier specs chose and the matrix's part count to the one the list makes. The rules and their
# cases live in tests/test-ci-parts.sh, started once (bug #270: each process costs time in the lint copies).
bash tests/test-ci-parts.sh "$PWD" || fail=1

echo "== the final CI job writes the job times"
# Bug #295: the rule of tests/test-ci-parts.sh that pins the Job times step (decision 7) is broken once per case in
# tests/test-ci-job-times.sh. The lint copies of tests/smoke-check.sh check the rules only, so they skip it (#293).
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-ci-job-times.sh || fail=1
# Bug #296: rule 10a counts every run step of the part job, `- run: ...` too; tests/test-ci-run-steps.sh adds one per case.
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-ci-run-steps.sh || fail=1

echo "== CI selects the steps a pull request affects"
# Iteration 60, decision 8: on a pull request every smoke job runs tests/check.sh --affected --within <its list>, on
# every other event --only <its list>, through one workflow variable (1); every job starts on every event, so the
# three required names always report: no path filter on 'on:' (2), no 'if:' on a required job or its steps but the
# if: always() of smoke-gitbash (1); the smoke jobs fetch the history, so origin/main exists
# (4). One awk pass (bug #270: no process per line); it assumes the block style ci.yml uses (jobs at 2 spaces, job
# keys at 4).
ci_sel_env="  CHECK_SELECT: \${{ github.event_name == 'pull_request' && '--affected --within' || '--only' }}"
while IFS= read -r l; do
  case $l in
    env) echo "FAIL: $chk_ci: the env block is not exactly the line '$ci_sel_env'"; fail=1 ;;
    on) echo "FAIL: $chk_ci: the 'on:' block is not exactly push to main and pull_request (a path filter would leave a required job unreported)"; fail=1 ;;
    if\ *) echo "FAIL: $chk_ci: job ${l#if } has an 'if:' (a required job runs on every event)"; fail=1 ;;
    depth\ *) echo "FAIL: $chk_ci: job ${l#depth } does not check out with fetch-depth: 0 (the changed paths need origin/main)"; fail=1 ;;
  esac
done < <(LC_ALL=C awk -v want="$ci_sel_env" '
  { sub(/\r$/, "") }
  # the column-0 blocks env: and on:
  /^[^[:space:]#]/ { blk = $0; if (blk == "env:") nenv++; if (blk == "on:") non++ }
  blk == "env:" && /^[[:space:]]/ { env[++ne] = $0 }
  blk == "on:" && /^[[:space:]]/ { on[++no] = $0 }
  # the jobs
  blk == "jobs:" && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); next }
  blk != "jobs:" { job = "" }
  job != "" && /^    if:/ { if (!(job == "smoke-gitbash" && $0 == "    if: always()") && !bad[job]++) print "if " job }
  job != "" && /^      +(- )?if:/ && (job == "lint" || job == "smoke-bash") && !bad[job]++ { print "if " job }
  job != "" && /^[[:space:]]+fetch-depth: 0[[:space:]]*$/ { depth[job] = 1 }
  END {
    if (nenv != 1 || ne != 1 || env[1] != want) print "env"
    if (non != 1 || no != 3 || on[1] != "  push:" || on[2] != "    branches: [main]" || on[3] != "  pull_request:") print "on"
    if (!depth["smoke-bash"]) print "depth smoke-bash"
  }' "$chk_ci")

echo "== the README lists every smoke file"
# Iteration 51 (#157): the README lists every tests/smoke-*.sh once. The rule lives in tests/test-lint-agreement.sh.
bash tests/test-lint-agreement.sh "$PWD" || fail=1
# #340: the lint copies of tests/smoke-check.sh check the rules only; the cases run once, in the lint.
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-lint-agreement-cases.sh "$PWD" || fail=1

echo "== the agreement section stays cheap"
# Bug #270: the section above made the CI job 25 to 32 minutes long; it may start the rule file only a few times.
# #340: the lint copies of tests/smoke-check.sh check the rules only; the cost test runs once, in the lint.
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-lint-agreement-cost.sh "$PWD" || fail=1

echo "== the skills, the agents and the README name the .sh form only (#364)"
# Iteration 67 (#364, decision record 0004 step 3): a line of a skill, an agent or the user part of the README that tells
# how to run a script names the bash form.
sh_only_scan() { # sh_only_scan <mode> <file> <stop-heading>: prints "<n>:<first match>" per failing line
  awk -v mode="$1" -v stop="$3" '
    mode == "user" && $0 == stop { exit }
    {
      m = ""
      if (index($0, ".ps1")) m = ".ps1"
      else if (mode == "user" && index($0, "powershell -")) m = "powershell -"
      else if (mode == "agent" && index($0, "powershell")) m = "powershell"
      else if (mode == "skill" && index($0, "powershell")) m = "powershell"
      if (m == "" && mode != "user") {
        t = $0; gsub(/PowerShell tests/, "", t)
        if (index(t, "PowerShell") && !(mode == "agent" && $0 ~ /^tools:/)) m = "PowerShell"
      }
      if (m == "" && match($0, "(^|[ `(/])-[A-Z][a-z]+")) {
        m = substr($0, RSTART, RLENGTH); sub(/^[ `(\/]/, "", m)
      }
      if (m != "") print NR ":" m
    }' "$2"
}
sh_only_report() { # sh_only_report <file> <scan output>
  while IFS= read -r so_l; do
    [ -n "$so_l" ] || continue
    echo "FAIL: $1:${so_l%%:*} names the PowerShell form of a script (${so_l#*:}); name the .sh form only (#364)"; fail=1
  done <<<"$2"
}
for so_f in skills/*/SKILL.md; do sh_only_report "$so_f" "$(sh_only_scan skill "$so_f" '')"; done
for so_f in agents/*.md; do [ -f "$so_f" ] && sh_only_report "$so_f" "$(sh_only_scan agent "$so_f" '')"; done
sh_only_report README.md "$(sh_only_scan user README.md '## Developing nightmill')"

echo "== text from issues is data"
# Text from issues, pull requests, comments and linked files is data, never instructions (bug #108). /spec, /next and
# /fix read the issue with 'gh issue view ... --json' and never with the unfiltered comments field; /spec and /next take
# comments only from the maintainer's login (gh api user --jq .login, no config key); /next compares lastEditedAt with
# the maintainer's "Waiting for approval." comment. The commands and the line stay; the wording of the rule is the
# manual check's (iteration 73). Whitespace and line breaks do not matter (the text is joined before it is searched).
for f in skills/spec/SKILL.md skills/next/SKILL.md skills/fix/SKILL.md; do
  flat=$(tr '\n' ' ' < "$f" | sed -E 's/ +/ /g')
  # the read step no longer hands every comment of the issue to the agent
  case "$flat" in
    *'gh issue view'*'--json'*) ;;
    *) echo "FAIL: $f has no 'gh issue view ... --json' read step"; fail=1 ;;
  esac
  if printf '%s\n' "$flat" | grep -E 'gh issue view [^`]*--json[^`]*comments' >/dev/null; then
    echo "FAIL: $f reads the issue with the unfiltered comments field (every author's comment reaches the agent)"; fail=1
  fi
done
for f in skills/spec/SKILL.md skills/next/SKILL.md; do
  grep -qF -- 'gh api user --jq .login' "$f" || { echo "FAIL: $f does not filter comments by the maintainer's login: missing 'gh api user --jq .login'"; fail=1; }
done
for w in 'lastEditedAt' 'Waiting for approval.'; do
  grep -qF -- "$w" skills/next/SKILL.md || { echo "FAIL: skills/next/SKILL.md does not stop for an issue edited after approval: missing '$w'"; fail=1; }
done

echo "== the security model is documented"
# Iteration 39 (#159): the README's Security model names the rules, the files and the links; SECURITY.md links to it.
# The checks live in tests/test-security-model.sh.
bash tests/test-security-model.sh "$PWD" || fail=1

echo "== the guard reads a GraphQL keyword only as a definition's first name"
# Iteration 50 (#253): an operation named query, subscription or fragment stays the kind its first name says, in
# scripts/guard.sh. The cases live in tests/test-guard-gql-keyword.sh.
bash tests/test-guard-gql-keyword.sh "$PWD" || fail=1

echo "== running unattended is documented"
# Iteration 49 (#160): the README gives the headless commands with their flags and the keys and defaults a run depends
# on. The checks live in tests/test-unattended-docs.sh.
bash tests/test-unattended-docs.sh "$PWD" || fail=1

echo "== the driver is wired"
# Iteration 52 (#164): the driver's flags, that it sets no status, the workflow template and the flags, keys and files
# the README names.
bash tests/test-drive-docs.sh "$PWD" || fail=1

echo "== the pause flag and the limits are wired"
# Iteration 53 (#165): the limits keys, the gate in the skills, the driver's flags and ledger, the README rows.
bash tests/test-limits-docs.sh "$PWD" || fail=1

echo "== an agent can file a story with /story"
# Bug #119: /next and the workflow send the agent to /story to file the rest of a partial story, so story must not set
# disable-model-invocation: true while they do. The pin lives in tests/test-story-invocable.sh.
bash tests/test-story-invocable.sh "$PWD" || fail=1

echo "== the low-severity skill gaps are closed"
# Bug #142 (LOW-SKILLS): the worker lists its tools, /spec removes needs-spec, one spelling of the gh project permission
# rule. The checks live in tests/test-skills-low-gaps.sh.
bash tests/test-skills-low-gaps.sh "$PWD" || fail=1

echo "== the low-severity documentation gaps are closed"
# Bug #143 (LOW-DOCS): every skill and script is named in the README, the CLAUDE.md layout, the bug form and the
# marketplace description, a .ps1 file with a non-ASCII character has a byte order mark. The checks live in
# tests/test-docs-low-gaps.sh.
bash tests/test-docs-low-gaps.sh "$PWD" || fail=1

echo "== one interpreter runs a warm-up command"
# Bug #133: slot.sh and new-worktree.sh run worktrees.warmup[].command in bash, and the schema says so.
bash tests/test-warmup-interpreter.sh || fail=1

echo "== the config comes from the base branch"
# Iteration 48 (#111): the skills and the slot script read the config from the base branch, git.mergeFlags must contain
# --auto and never --admin, and a change under .claude/ or .github/ is never auto-merged. The checks live in
# tests/test-config-from-base.sh.
bash tests/test-config-from-base.sh "$PWD" || fail=1

echo "== the bash smoke job has room for the suite"
# Bug #264: the smoke-bash job's timeout-minutes is about 3 times the longest run (435 s -> 22), at most 60. The pin
# lives in tests/test-ci-smoke-bash-timeout.sh.
bash tests/test-ci-smoke-bash-timeout.sh "$PWD" || fail=1

echo "== CI runs with least privilege"
# The workflow is hardened (iteration 38, finding MD-T3 of the review of 0.2.0): a read-only token and no job-level
# permissions but those of smoke-gitbash (1, amended by iteration 55), a timeout on every job (2), a concurrency group that cancels pull request runs only (3), a comment on
# the three job names the ruleset on main requires (4), every action pinned by its full commit SHA with the release in a
# trailing comment (5), and Dependabot's github-actions entry kept (6). It reads the files with grep and awk only and
# assumes the block style ci.yml uses (jobs at 2 spaces, job keys at 4); anything it cannot match fails. It cannot check
# that a SHA exists or belongs to the release in its comment, that GitHub accepts the expressions, that the two names
# still match the ruleset, or that Dependabot runs. The two paths can be overridden (LINT_CI_YML, LINT_DEPENDABOT_YML)
# so the same code can be run on a copy; the defaults are the repository's files.
ci_yml=${LINT_CI_YML:-.github/workflows/ci.yml}
dependabot_yml=${LINT_DEPENDABOT_YML:-.github/dependabot.yml}
ci_req_comment='    # Required check: the ruleset on main requires this name; renaming it blocks every pull request.'
ci_conc_group='  group: ci-${{ github.event_name == '\''pull_request'\'' && github.ref || github.run_id }}'
ci_conc_cancel='  cancel-in-progress: ${{ github.event_name == '\''pull_request'\'' }}'
ci_pin_re='^[[:space:]]*(- )?uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$'
if [ -f "$ci_yml" ]; then
  # 1. permissions: contents: read at column 0 and nothing else; no write scope. The job-level rule (only
  # smoke-gitbash, with contents: read and actions: read; iterations 55 and 68) lives in tests/test-ci-parts.sh
  # (rule 8), as the smoke-bash timeout pin lives in tests/test-ci-smoke-bash-timeout.sh.
  perm=$(LC_ALL=C awk '
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (L[i] == "permissions:") { p = i; break }
      if (!p) { print "missing"; exit }
      if (L[p + 1] != "  contents: read") { print "contents"; exit }
      if (L[p + 2] ~ /^[[:space:]]/) { print "scope"; exit }
      print "ok"
    }' "$ci_yml")
  case "$perm" in
    ok) ;;
    missing) echo "FAIL: $ci_yml has no 'permissions:' block at the top (column 0)"; fail=1 ;;
    contents) echo "FAIL: $ci_yml: the line after 'permissions:' is not exactly '  contents: read'"; fail=1 ;;
    *) echo "FAIL: $ci_yml: 'permissions:' grants a scope besides 'contents: read'"; fail=1 ;;
  esac
  if grep -qF ': write' "$ci_yml"; then
    echo "FAIL: $ci_yml grants a write permission (': write')"; fail=1
  fi
  # 2. every job in the jobs: section has a timeout-minutes from 1 to 360 before the next job
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      nojobs) echo "FAIL: $ci_yml has no job in its 'jobs:' section"; fail=1 ;;
      missing\ *) echo "FAIL: $ci_yml: job ${line#missing } has no '    timeout-minutes: <number>' line"; fail=1 ;;
      range\ *) echo "FAIL: $ci_yml: job ${line#range } (timeout-minutes must be from 1 to 360)"; fail=1 ;;
    esac
  done < <(LC_ALL=C awk '
    function flush() {
      if (job == "") return
      n++
      if (t == "") print "missing " job
      else if (t + 0 < 1 || t + 0 > 360) print "range " job " has timeout-minutes " t
    }
    /^jobs:[[:space:]]*$/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { flush(); job = ""; inj = 0; next }
    inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); t = ""; next }
    inj && job != "" && t == "" && /^    timeout-minutes: [0-9]+$/ { t = $2; next }
    END { flush(); if (n == 0) print "nojobs" }' "$ci_yml")
  # 3. the concurrency block (column 0) holds exactly the two lines of the spec, and nothing cancels a run on main
  if grep -qxF 'concurrency:' "$ci_yml"; then
    conc=$(LC_ALL=C awk '$0 == "concurrency:" { s = 1; next } s && /^[[:space:]]/ { print; next } s { exit }' "$ci_yml")
    n_conc=$(printf '%s\n' "$conc" | grep -c . || true)
    if [ "$n_conc" != 2 ] || ! printf '%s\n' "$conc" | grep -xF -- "$ci_conc_group" >/dev/null || ! printf '%s\n' "$conc" | grep -xF -- "$ci_conc_cancel" >/dev/null; then
      echo "FAIL: $ci_yml: the 'concurrency:' block is not exactly the two lines '$ci_conc_group' and '$ci_conc_cancel'"; fail=1
    fi
  else
    echo "FAIL: $ci_yml has no 'concurrency:' block at the top (column 0)"; fail=1
  fi
  if grep -qE 'cancel-in-progress:[[:space:]]*true' "$ci_yml"; then
    echo "FAIL: $ci_yml has 'cancel-in-progress: true' (a run on main must never be cancelled)"; fail=1
  fi
  # 4. the two names the ruleset requires carry the comment on the line directly above them
  while IFS= read -r req; do
    ln_list=$(grep -nxF -- "    name: $req" "$ci_yml" | cut -d: -f1 || true)
    if [ -z "$ln_list" ]; then
      echo "FAIL: $ci_yml has no line '    name: $req' (the ruleset on main requires this name)"; fail=1
      continue
    fi
    for ln in $ln_list; do
      above=
      [ "$ln" -le 1 ] || above=$(sed -n "$((ln - 1))p" "$ci_yml")
      [ "$above" = "$ci_req_comment" ] || { echo "FAIL: $ci_yml:$ln: the line above 'name: $req' is not the comment '${ci_req_comment#    }'"; fail=1; }
    done
  done <<'EOF'
Lint (generic, JSON, skills, shell)
bash scripts smoke tests
Git Bash scripts smoke tests
EOF
  n_cm=$(grep -cF -- "${ci_req_comment#    }" "$ci_yml" || true)
  [ "$n_cm" = 3 ] || { echo "FAIL: $ci_yml has the 'Required check' comment $n_cm times (exactly 3 expected, one per required job)"; fail=1; }
  # 5. every uses: line is pinned by a 40-character lower-case SHA with the release in a trailing comment
  n_uses=0
  while IFS= read -r sel; do
    [ -n "$sel" ] || continue
    n_uses=$((n_uses + 1))
    printf '%s\n' "${sel#*:}" | grep -E "$ci_pin_re" >/dev/null || { echo "FAIL: $ci_yml:${sel%%:*}: not pinned as '<owner>/<action>@<40 hex> # vX.Y.Z':${sel#*:}"; fail=1; }
  done < <(grep -nE '^[[:space:]]*(- )?uses:' "$ci_yml" || true)
  [ "$n_uses" -ge 1 ] || { echo "FAIL: $ci_yml has no 'uses:' line (the pins cannot be checked)"; fail=1; }
else
  echo "FAIL: $ci_yml is missing"; fail=1
fi
# 6. Dependabot keeps the actions current
if [ -f "$dependabot_yml" ]; then
  grep -qxF '  - package-ecosystem: "github-actions"' "$dependabot_yml" || { echo "FAIL: $dependabot_yml has no '  - package-ecosystem: \"github-actions\"' entry"; fail=1; }
else
  echo "FAIL: $dependabot_yml is missing"; fail=1
fi

echo "== /fix all runs bugs in parallel"
# /fix all fixes Ready bugs in parallel, one per free slot, and ends only when every Ready bug has a pull request, was
# skipped with a reason or is listed as not started (iteration 33): the key parallel.fixAllMaxBugs (default 0: no limit,
# any other value that is not a whole number stops the run), one producer at a time per bug, one take at a time, the slot
# freed with --abandon once the branch is the head of the open pull request and held when its files are uncommitted,
# overlapping bugs that wait, the pause flag at each start, the Stopped line with the two lists, and one table at the end.
# The keys, the flags and the commands stay; the wording of the batch is the manual check's (iteration 73).
fx=skills/fix/SKILL.md
for w in 'parallel.fixAllMaxBugs' 'parallel.hotFiles' 'parallel.doNotPair' 'git.mergeFlags' '--abandon' '--json headRefOid' \
         '--untracked-files=all'; do
  grep -qF -- "$w" "$fx" || { echo "FAIL: $fx does not say the /fix all item: $w"; fail=1; }
done
grep -qF '"fixAllMaxBugs": { "type": "integer", "minimum": 0, "default": 0,' schema/nightmill.schema.json || { echo "FAIL: schema: parallel.fixAllMaxBugs is not an integer with minimum 0 and default 0"; fail=1; }
json_load templates/nightmill.example.json
[ "$(json_get parallel.fixAllMaxBugs)" = 0 ] || { echo "FAIL: templates/nightmill.example.json: parallel.fixAllMaxBugs is not the schema default 0"; fail=1; }
grep -qF -- 'fixAllMaxBugs' README.md || { echo "FAIL: README.md does not mention fixAllMaxBugs"; fail=1; }

echo "== bash files do not use jq"
# The bash scripts and their tests read JSON with scripts/lib/json.sh (iteration 7), so they run on a machine
# with only git, gh and bash. Only tests/smoke-json.sh may call jq, as an oracle when it is installed, and
# this file names it in its own checks. A mention in a comment line is fine. The step list of tests/check.sh carries
# the CI mark jq and the groups @with-jq and @without-jq (iteration 70), so the check and the two tests of the marks,
# tests/smoke-check.sh and tests/test-ci-parts.sh, name the word without calling jq.
for f in scripts/*.sh scripts/lib/* tests/*.sh; do
  case "$f" in tests/smoke-json.sh|tests/lint.sh|tests/check.sh|tests/smoke-check.sh|tests/test-ci-parts.sh) continue ;; esac
  if grep -nw jq "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep . >/dev/null; then
    echo "FAIL: $f uses jq outside a comment; read JSON with scripts/lib/json.sh"; fail=1
  fi
done

echo "== an extra review round is proposed"
# Iteration 58 (#332): when the review rounds run out on fixable findings, /spec, /next and /fix propose one extra
# round; review.maxFixRounds defaults to 3. The checks live in tests/test-extra-round.sh.
bash tests/test-extra-round.sh "$PWD" || fail=1

echo "== the fast lane of /fix"
# Iteration 63 (#341): review.fastLane sends low-risk bugs through /fix in one pass; a fix that leaves the lane's
# paths, touches a hot file, needs a story trigger or is partial goes the long way. The checks live in
# tests/test-fast-lane.sh.
bash tests/test-fast-lane.sh "$PWD" || fail=1

echo "== a spec stays within its size limit"
# Iteration 71 (#347): iterations.maxSpecLines; the checks live in tests/test-spec-size-limit.sh.
bash tests/test-spec-size-limit.sh "$PWD" || fail=1

echo "== a take killed in its warm-up leaves the claim with the pid it recorded"
# Bug #373: tests/smoke-slot.sh, interruption case 4, failed in Git Bash on Windows because the case asked for the
# killed take's Windows pid after the take was reaped. tests/test-slot-killed-take.sh runs that case (read from the
# smoke test) alone. The lint copies of tests/smoke-check.sh check the rules only, so they skip it.
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-slot-killed-take.sh "$PWD" || fail=1

echo "== the jq cross-check of smoke-json.sh passes when jq prints CRLF line ends"
# Bug #372: tests/smoke-json.sh failed in Git Bash on Windows because a native jq.exe ends every line with CRLF
# unless it is given -b. tests/test-smoke-json-jq-crlf.sh runs smoke-json.sh with a stand-in that prints CRLF. The
# lint copies of tests/smoke-check.sh check the rules only, so they skip it.
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-smoke-json-jq-crlf.sh "$PWD" || fail=1

echo "== the driver ends the background process a step leaves behind"
# Bug #374: tests/smoke-drive.sh, the case "left behind", failed in Git Bash on Windows: the driver lists the step's
# process group with ps -A -o, which the ps of Git Bash does not take, so it ended nothing and the step's background
# process stayed alive. tests/test-drive-leftover.sh runs that case (read from the smoke test) alone. The lint copies
# of tests/smoke-check.sh check the rules only, so they skip it.
[ "${NIGHTMILL_CI_PARTS_RULES_ONLY:-}" = 1 ] || bash tests/test-drive-leftover.sh "$PWD" || fail=1

echo "== the invariant is Bash only (#363)"
# Iteration 65 (#363, decision record 0004 step 2): the invariant Both shells becomes Bash only, one text in the project
# config and the two issue forms (rendered from the config). Earlier issues keep their old checkbox text; the files
# below do not.
bash_only='Bash only — every script is bash and behaves the same in bash on Linux and macOS and in Git Bash on Windows; the PowerShell files are frozen, and no new one is added'
json_load .claude/nightmill.json
bo_n=$(json_len invariants); bo_have=0; bo_both=0; bo_i=0
while [ "$bo_i" -lt "$bo_n" ]; do
  bo_v=$(json_get "invariants[$bo_i]")
  [ "$bo_v" = "$bash_only" ] && bo_have=$((bo_have + 1))
  case "$bo_v" in 'Both shells'*) bo_both=$((bo_both + 1)) ;; esac
  bo_i=$((bo_i + 1))
done
[ "$bo_have" = 1 ] || { echo "FAIL: .claude/nightmill.json: no invariant is the Bash only text"; fail=1; }
[ "$bo_both" = 0 ] || { echo "FAIL: .claude/nightmill.json: an invariant still begins with Both shells"; fail=1; }
for bo_f in story.yml bug.yml; do
  bo_p=.github/ISSUE_TEMPLATE/$bo_f
  [ "$(grep -cxF -- "        - label: \"$bash_only\"" "$bo_p" 2>/dev/null || true)" = 1 ] || { echo "FAIL: $bo_p does not carry the Bash only invariant"; fail=1; }
  if grep -qF -- 'Both shells —' "$bo_p" 2>/dev/null; then echo "FAIL: $bo_p still carries the Both shells invariant"; fail=1; fi
done

echo "== no PowerShell script is left, and none is named (#365)"
# Iteration 68 (#365, decision record 0004 step 4): only tests/check.ps1 and the two image tools are PowerShell files, and
# no text outside docs/ and CHANGELOG.md names another one (tests/test-no-powershell.sh, rules 1 and 2 and their cases).
bash tests/test-no-powershell.sh "$PWD" || fail=1

echo "== shell"
for f in scripts/*.sh scripts/lib/*.sh tests/*.sh; do
  bash -n "$f" || { echo "FAIL: $f does not parse"; fail=1; }
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning scripts/*.sh scripts/lib/*.sh tests/*.sh || fail=1
else
  echo "(shellcheck not installed, skipped)"
fi

[ "$fail" = 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
