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

echo "== forbidden words"
words=tests/forbidden-words.local.txt
if [ -n "${FORBIDDEN_WORDS:-}" ]; then
  words=$(mktemp); trap 'rm -f "$words"' EXIT
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
  head -1 "$s" | grep -qx -- '---' || { echo "FAIL: $s has no frontmatter"; fail=1; }
  grep -q '^name: ' "$s" || { echo "FAIL: $s has no name"; fail=1; }
  grep -q '^description: ' "$s" || { echo "FAIL: $s has no description"; fail=1; }
  if grep -q 'nightmill.json' "$s" && ! grep -q '^!`' "$s"; then
    echo "FAIL: $s mentions the config but does not inject it"; fail=1
  fi
done
for a in agents/*.md; do
  grep -q '^name: ' "$a" || { echo "FAIL: $a has no name"; fail=1; }
done

echo "== spec and next stay split"
# /spec writes the spec for a Ready story, /next implements an Approved one (iteration 2).
if [ -f skills/spec/SKILL.md ]; then
  grep -q 'Spec review' skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not set Spec review"; fail=1; }
  grep -q 'Ready' skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not take Ready stories"; fail=1; }
  grep -q 'Picking #' skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not print the picking line"; fail=1; }
else
  echo "FAIL: skills/spec/SKILL.md is missing"; fail=1
fi
grep -q 'Approved' skills/next/SKILL.md || { echo "FAIL: skills/next/SKILL.md does not take Approved stories"; fail=1; }
grep -q 'Picking #' skills/next/SKILL.md || { echo "FAIL: skills/next/SKILL.md does not print the picking line"; fail=1; }
if grep -q '^## 2\. A Ready story' skills/next/SKILL.md; then
  echo "FAIL: skills/next/SKILL.md still holds the spec procedure (it belongs in /spec)"; fail=1
fi
grep -q 'Picking an issue' skills/workflow/SKILL.md || { echo "FAIL: skills/workflow/SKILL.md has no 'Picking an issue' section"; fail=1; }

echo "== init skill keeps the install-chat steps"
# /init detects, asks seven questions in order, plans, confirms once, applies with gh and git (iteration 1).
for w in validate-config createProjectV2View updateProjectV2View BOARD_LAYOUT updateProjectV2Field 'gh label create' 'gh project link'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention $w"; fail=1; }
done
i=0
for t in 'maintainer name' 'check command' 'areas' 'invariants' 'manual-check paths' 'slot count' 'ports'; do
  i=$((i + 1))
  grep -q -- "^$i\. \*\*$t\*\*" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md question $i is not '$t'"; fail=1; }
done
if grep -qF 'Do not edit settings.json yourself' skills/init/SKILL.md; then
  echo "FAIL: skills/init/SKILL.md still tells the model not to edit settings.json (the install chat offers it)"; fail=1
fi
# The API cannot configure board workflows, so /init must always print the table of what to set by hand.
for w in 'Pull request linked to issue' 'Pull request merged' 'Item closed' 'Item added to project' 'workflows(first' 'projects/<n>/workflows' 'no mutation' 'grouping or sorting' 'Code changes requested' 'Code review approved' 'Item reopened' 'Auto-archive items' 'updated:@today-1d' 'rate limits'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention the board workflow item: $w"; fail=1; }
done
grep -qF 'Workflows settings' skills/workflow/SKILL.md || { echo "FAIL: skills/workflow/SKILL.md does not say who sets the board workflows"; fail=1; }

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
  for w in 'tests/check.sh' '--plugin-dir' 'SECURITY.md' 'Ready' 'Approved' 'PowerShell' 'bash'; do
    grep -qF -- "$w" CONTRIBUTING.md || { echo "FAIL: CONTRIBUTING.md does not mention $w"; fail=1; }
  done
else
  echo "FAIL: CONTRIBUTING.md is missing"; fail=1
fi
for f in nightmill-bug nightmill-idea; do
  p=.github/ISSUE_TEMPLATE/$f.yml
  if [ -f "$p" ]; then
    head -1 "$p" | grep -q '^name: ' || { echo "FAIL: $p does not start with name:"; fail=1; }
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

echo "== schema keywords are supported"
# scripts/validate-config.* understand type, properties, required, items, minimum, minItems,
# additionalProperties and enum. A schema that gains another constraint would be silently ignored by them.
for kw in '$ref' anyOf oneOf allOf not if pattern format const maxItems uniqueItems minLength maxLength maximum dependencies; do
  if grep -qF "\"$kw\"" schema/nightmill.schema.json; then
    echo "FAIL: schema/nightmill.schema.json uses \"$kw\", which scripts/validate-config.* does not support"; fail=1
  fi
done

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
[ "$(json_get "$p.default")" = 2 ] || { echo "FAIL: schema: review.maxFixRounds default is not 2"; fail=1; }
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
    [ "$(json_get review.maxFixRounds)" = 2 ] || { echo "FAIL: $f: review.maxFixRounds is not the schema default 2"; fail=1; }
  fi
done
for pair in $role_defaults; do
  grep -qF -- "${pair%%:*}" README.md || { echo "FAIL: README.md does not mention the role ${pair%%:*}"; fail=1; }
done
for w in 'roles' 'models.ranking' 'review.maxFixRounds'; do
  grep -qF -- "\`$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done

echo "== agent roles are defined in the workflow skill"
# The workflow skill has the section "Agent roles and models" (iteration 11): it names every role of the schema,
# states how a model is resolved and what happens when it cannot be used, the old "always pass a model" rule is
# gone, and the worker agent's own model is the schema default.
wf=skills/workflow/SKILL.md
if grep -qxF '## Agent roles and models' "$wf"; then
  section=$(awk '/^## Agent roles and models$/ { s = 1; next } s && /^## / { exit } s { print }' "$wf")
  json_load schema/nightmill.schema.json
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '%s\n' "$section" | grep -qF -- "\`$r\`" || { echo "FAIL: $wf: the section 'Agent roles and models' does not name the role $r"; fail=1; }
  done < <(json_keys properties.roles.properties)
  for w in 'roles.<role>.model' 'properties.roles.properties.R.properties.model' 'schema/nightmill.schema.json' 'explicitly' 'never inherited from the session' 'never launched as a fork' 'Stopped: the <role> role cannot run on <model>' 'never falls back' 'Reviewed by'; do
    printf '%s\n' "$section" | grep -qF -- "$w" || { echo "FAIL: $wf: the section 'Agent roles and models' does not say: $w"; fail=1; }
  done
  worker_default=$(json_get properties.roles.properties.worker.properties.model.default)
  worker_model=$(sed -n 's/^model:[[:space:]]*//p' agents/worker.md | head -1)
  [ "$worker_model" = "$worker_default" ] || { echo "FAIL: agents/worker.md has model '$worker_model', the schema default of roles.worker.model is '$worker_default'"; fail=1; }
else
  echo "FAIL: $wf has no section '## Agent roles and models'"; fail=1
fi
for w in 'a strong model for specs and implementation' 'Always pass a model'; do
  if grep -qF -- "$w" "$wf"; then echo "FAIL: $wf still says '$w' (the roles section replaces it)"; fail=1; fi
done

echo "== status is wired"
# /status (iteration 8): the skill, both scripts and both smoke tests exist, the README names the skill, and the
# scripts only read: no board edit, merge, comment or GraphQL mutation anywhere in them.
for f in skills/status/SKILL.md scripts/status.sh scripts/status.ps1 scripts/lib/status.awk tests/smoke-status.sh tests/smoke-status.ps1; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
grep -qF '/nightmill:status' README.md || { echo "FAIL: README.md does not mention /nightmill:status"; fail=1; }
for f in scripts/status.sh scripts/status.ps1 scripts/lib/status.awk; do
  if [ -f "$f" ] && grep -nE 'item-edit|item-add|item-archive|item-delete|pr merge|issue edit|issue comment|issue close|mutation' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -q .; then
    echo "FAIL: $f changes something; /status only reads"; fail=1
  fi
done

echo "== template board is wired"
# /init copies nightmill's template board when it can and builds the board field by field when it cannot
# (iteration 9): the location is templates/board-template.json (owner a non-empty string, number an integer or
# null), the check is scripts/template-board.* (read only), /init uses both ways and says which, the README
# describes the template.
tb=templates/board-template.json
if [ -f "$tb" ]; then
  grep -Eq '"owner":[[:space:]]*"[^"]+"' "$tb" || { echo "FAIL: $tb: owner must be a non-empty string"; fail=1; }
  grep -Eq '"number":[[:space:]]*(null|[1-9][0-9]*)[[:space:]]*[,}]' "$tb" || { echo "FAIL: $tb: number must be an integer or null"; fail=1; }
else
  echo "FAIL: $tb is missing"; fail=1
fi
for f in scripts/template-board.sh scripts/template-board.ps1 tests/smoke-template-board.sh tests/smoke-template-board.ps1; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
for f in scripts/template-board.sh scripts/template-board.ps1; do
  if [ -f "$f" ] && grep -nE 'project copy|project link|item-edit|item-add|item-archive|item-delete|field-create|project edit|api graphql|mutation' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -q .; then
    echo "FAIL: $f changes something; the template check only reads"; fail=1
  fi
done
for w in 'gh project copy' 'template-board' 'field by field'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention $w"; fail=1; }
done
grep -qF 'The template board' README.md || { echo "FAIL: README.md has no section 'The template board'"; fail=1; }

echo "== init installs the edit permission"
# /init adds the rule Edit(**) to permissions.allow of .claude/settings.local.json (iteration 12). /init is a
# conversation, so the lint pins the wording the behaviour depends on; the manual check does the behaviour.
for w in '**Edit permission**' 'Edit(**)' '.claude/settings.local.json' 'git check-ignore' 'declined (edits will prompt)' '**exists**'; do
  grep -qF -- "$w" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not mention the edit permission item: $w"; fail=1; }
done
# the Confirm once step shows the local file's text next to the CLAUDE.md and settings.json edits
if ! sed -n '/^## 4\. Confirm once/,/^## 5\. Apply/p' skills/init/SKILL.md | grep -qF '.claude/settings.local.json'; then
  echo "FAIL: skills/init/SKILL.md: the Confirm once step does not show .claude/settings.local.json"; fail=1
fi
# the edit-permission line itself says that no entry of an existing file is removed or reordered
if ! sed -n '/^- \*\*Edit permission\*\*/,/^- \*\*Board workflows\*\*/p' skills/init/SKILL.md | grep -qF 'without removing or reordering an entry'; then
  echo "FAIL: skills/init/SKILL.md: the Edit permission line does not say no entry is removed or reordered"; fail=1
fi
# Edit(/**) is not scoped to the project on every platform; only Edit(**) is written
for f in skills/init/SKILL.md README.md; do
  if grep -qF 'Edit(/**)' "$f"; then
    echo "FAIL: $f contains Edit(/**), which reaches outside the project; write Edit(**)"; fail=1
  fi
done
for w in 'Edit(**)' '.claude/settings.local.json' '### The edit permission'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention the edit permission item: $w"; fail=1; }
done

echo "== bash files do not use jq"
# The bash scripts and their tests read JSON with scripts/lib/json.sh (iteration 7), so they run on a machine
# with only git, gh and bash. Only tests/smoke-json.sh may call jq, as an oracle when it is installed, and
# this file names it in its own checks. A mention in a comment line is fine.
for f in scripts/*.sh scripts/lib/* tests/*.sh; do
  case "$f" in tests/smoke-json.sh|tests/lint.sh) continue ;; esac
  if grep -nw jq "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -q .; then
    echo "FAIL: $f uses jq outside a comment; read JSON with scripts/lib/json.sh"; fail=1
  fi
done

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
