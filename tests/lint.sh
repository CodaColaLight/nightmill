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

echo "== reviewer pairing is checked"
# The validators reject a reviewer ranked below the role it reviews and warn about a model that is not in
# models.ranking (iteration 15). Both shells carry the rule, so a shell that drops it fails here on a machine
# that can run only the other one.
for w in 'ranks below' 'is not in models.ranking'; do
  grep -qF -- "$w" scripts/lib/validate.awk || { echo "FAIL: scripts/lib/validate.awk does not carry the pairing rule text: $w"; fail=1; }
  grep -qF -- "$w" scripts/validate-config.ps1 || { echo "FAIL: scripts/validate-config.ps1 does not carry the pairing rule text: $w"; fail=1; }
done
# the validator this lint runs on the example and on the repository's own config has the rule
pair_cfg=$(mktemp)
sed 's/"specReviewer": { "model": "opus" }/"specReviewer": { "model": "haiku" }/' templates/nightmill.example.json > "$pair_cfg"
if out=$(bash scripts/validate-config.sh "$pair_cfg" 2>&1); then
  echo "FAIL: scripts/validate-config.sh accepted a spec reviewer on a model ranked below the spec writer's"; fail=1
elif ! printf '%s\n' "$out" | grep -qF 'ranks below'; then
  echo "FAIL: scripts/validate-config.sh did not say 'ranks below' for a spec reviewer ranked below the spec writer"; fail=1
fi
rm -f "$pair_cfg"

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

echo "== models is wired"
# /models (iteration 16): the skill, both scripts and both smoke tests exist, the README names the skill, the scripts
# only read, the roles of the scripts are the roles of the schema, the skill does not name the config file (so it
# needs no injection), and the check and CI run the smoke tests.
for f in skills/models/SKILL.md scripts/models.sh scripts/models.ps1 scripts/lib/models.awk tests/smoke-models.sh tests/smoke-models.ps1; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
grep -qF '/nightmill:models' README.md || { echo "FAIL: README.md does not mention /nightmill:models"; fail=1; }
for f in scripts/models.sh scripts/models.ps1 scripts/lib/models.awk; do
  if [ -f "$f" ] && grep -nE '(^|[^a-z])gh +[a-z]|curl|Set-Content|Out-File|Add-Content|Remove-Item|New-Item|git +(add|commit|push|switch|checkout|fetch|worktree|config|branch|reset|rm|mv|clean|stash|init|merge|rebase|pull)' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -q .; then
    echo "FAIL: $f writes or calls out; /models only reads"; fail=1
  fi
done
json_load schema/nightmill.schema.json
while IFS= read -r r; do
  [ -n "$r" ] || continue
  grep -qF -- "$r" scripts/lib/models.awk || { echo "FAIL: scripts/lib/models.awk does not know the role $r of the schema"; fail=1; }
  grep -qF -- "$r" scripts/models.ps1 || { echo "FAIL: scripts/models.ps1 does not know the role $r of the schema"; fail=1; }
done < <(json_keys properties.roles.properties)
if grep -qF 'nightmill.json' skills/models/SKILL.md; then
  echo "FAIL: skills/models/SKILL.md names the config file; it would have to inject it"; fail=1
fi
for f in tests/check.sh .github/workflows/ci.yml; do
  grep -qF 'smoke-models' "$f" || { echo "FAIL: $f does not run smoke-models"; fail=1; }
done

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

echo "== /next and /fix hand the coding to a subagent"
# /next launches an implementer subagent and /fix a fixer subagent on the configured model (iteration 13). Both
# are conversations, so the lint pins the wording the behaviour depends on; the manual check does the behaviour.
for pair in "next:implementer" "fix:fixer"; do
  skill=${pair%%:*}; role=${pair##*:}
  f=skills/$skill/SKILL.md
  for w in "roles.$role.model" 'Agent roles and models' 'explicitly' 'not a fork' 'not nightmill:worker' 'parallel.maxAgents' \
           'never writes the code itself' 'Result: complete | partial | failed' \
           "Stopped: the $role role cannot run on" "Stopped: the $role returned failed" 'Do not push' 'do not launch other agents'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the subagent item: $w"; fail=1; }
  done
  # what the session keeps
  for w in 'slot' 'gh pr merge' 'Never set Ready or Approved'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f lost what the session keeps: $w"; fail=1; }
  done
done
grep -qF 'Written by the implementer role on' skills/next/SKILL.md || { echo "FAIL: skills/next/SKILL.md: the pull request does not name the implementer's model"; fail=1; }
grep -qF 'Fixed by the fixer role on' skills/fix/SKILL.md || { echo "FAIL: skills/fix/SKILL.md: the pull request does not name the fixer's model"; fail=1; }
for w in 'Picking #' 'CHANGELOG'; do
  grep -qF -- "$w" skills/next/SKILL.md || { echo "FAIL: skills/next/SKILL.md lost what the session keeps: $w"; fail=1; }
done
for w in 'Cause:' 'Fix:' 'Test:'; do
  grep -qF -- "$w" skills/fix/SKILL.md || { echo "FAIL: skills/fix/SKILL.md: the fixer's result block lacks $w"; fail=1; }
done
# no agent file for the producers: the prompt is in the skill, the default model is in the schema. The agents are
# the worker and the two reviewers (iterations 18 and 20), which need a tool list that keeps them read-only.
for a in agents/*.md; do
  case "$a" in
    agents/worker.md|agents/code-reviewer.md|agents/spec-reviewer.md) ;;
    *) echo "FAIL: $a: only the worker and the two reviewers have an agent file (the producers' prompts are in the skills)"; fail=1 ;;
  esac
done

echo "== /spec hands the writing to a subagent"
# /spec launches a specWriter subagent on the configured model (iteration 14). It is a conversation, so the lint
# pins the wording the behaviour depends on; the manual check does the behaviour.
f=skills/spec/SKILL.md
for w in 'roles.specWriter.model' 'Agent roles and models' 'explicitly' 'not a fork' 'not nightmill:worker' 'parallel.maxAgents' \
         'never writes the spec itself' 'Result: complete | partial | failed' \
         'Stopped: the specWriter role cannot run on' 'Stopped: the specWriter returned' \
         'Written by the specWriter role on' 'Do not commit and do not push' 'do not launch other agents'; do
  grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the subagent item: $w"; fail=1; }
done
# what the session keeps
for w in 'Picking #' 'Spec review' 'gh pr merge' 'Spec for #' 'Never set Ready or Approved'; do
  grep -qF -- "$w" "$f" || { echo "FAIL: $f lost what the session keeps: $w"; fail=1; }
done
# a spec pull request says Spec for, never Closes
if grep -qF 'Closes #' "$f"; then
  echo "FAIL: $f tells the session to write 'Closes #'; a spec pull request says 'Spec for #'"; fail=1
fi

echo "== a separate code reviewer reviews the change"
# The code reviewer (iteration 18): an agent file whose tool list keeps it read-only, a section "Findings and fix
# rounds" in the workflow skill that holds the findings format and the rounds, and /next and /fix that launch it
# between the producer's result and the pull request. The skills are conversations, so the lint pins the wording.
cr=agents/code-reviewer.md
if [ -f "$cr" ]; then
  grep -qx 'name: code-reviewer' "$cr" || { echo "FAIL: $cr has no 'name: code-reviewer'"; fail=1; }
  [ "$(sed -n 's/^tools:[[:space:]]*//p' "$cr" | head -1)" = "Read, Grep, Glob" ] || { echo "FAIL: $cr: the tools must be exactly 'Read, Grep, Glob' (no Bash, Write, Edit or Agent)"; fail=1; }
  json_load schema/nightmill.schema.json
  cr_default=$(json_get properties.roles.properties.codeReviewer.properties.model.default)
  [ "$(sed -n 's/^model:[[:space:]]*//p' "$cr" | head -1)" = "$cr_default" ] || { echo "FAIL: $cr: model is not the schema default of roles.codeReviewer.model ($cr_default)"; fail=1; }
  for w in 'changes nothing' 'acceptance criterion' 'Not done' 'invariant' 'Check:' 'blocking' 'advisory' 'no findings'; do
    grep -qF -- "$w" "$cr" || { echo "FAIL: $cr does not say: $w"; fail=1; }
  done
else
  echo "FAIL: $cr is missing"; fail=1
fi
wf=skills/workflow/SKILL.md
if grep -qxF '## Findings and fix rounds' "$wf"; then
  # the section ends at the next "## " heading that is not inside a code fence (the Review template has one)
  fsection=$(awk '/^## Findings and fix rounds$/ { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' "$wf")
  for w in 'Review: findings | no findings' '- blocking <file>:<line>' '- advisory <file>:<line>' 'review.maxFixRounds' '1 + review.maxFixRounds' 'validate-config' 'ranks below' "never sees the producer's own account" 'is never read as'; do
    printf '%s\n' "$fsection" | grep -qF -- "$w" || { echo "FAIL: $wf: the section 'Findings and fix rounds' does not say: $w"; fail=1; }
  done
  # the format of the block is the same in the agent file and in the workflow skill
  fmt='^(Review: findings \| no findings|Blocking: <n>|Advisory: <n>|- blocking <file>:<line> .*|- advisory <file>:<line> .*)$'
  if [ -f "$cr" ] && [ "$(printf '%s\n' "$fsection" | grep -E "$fmt")" != "$(grep -E "$fmt" "$cr")" ]; then
    echo "FAIL: the format lines of the findings block differ between $wf and $cr"; fail=1
  fi
else
  echo "FAIL: $wf has no section '## Findings and fix rounds'"; fail=1
fi
for f in skills/next/SKILL.md skills/fix/SKILL.md; do
  for w in 'nightmill:code-reviewer' 'roles.codeReviewer.model' 'Findings and fix rounds' 'validate-config' 'Stopped: the codeReviewer ranks below' 'Stopped: the code review could not be had' 'not a fork'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the code review item: $w"; fail=1; }
  done
done

echo "== the review is recorded in the pull request"
# The pull request of a story or a bug has a section "## Review" (iteration 19), defined once in the workflow skill,
# and a blocking finding that is still open keeps auto-merge off: the section "CI and merging" names it, and /next
# and /fix say so in one fixed sentence. The interim text of iteration 18 is replaced, not kept beside the new one.
sentence='Auto-merge is not enabled: blocking review findings are still open (see Review).'
for w in '## Review' '- Reviewer: codeReviewer role on <model>' '- Author: <producer> role on <model>' '- Fix rounds used: <r> of <review.maxFixRounds>' '- Findings fixed: <n>' '- Findings still open: <b> blocking, <a> advisory' 'fixed in round <k>:' "$sentence"; do
  printf '%s\n' "$fsection" | grep -qF -- "$w" || { echo "FAIL: $wf: the section 'Findings and fix rounds' does not say: $w"; fail=1; }
done
cisection=$(awk '/^## CI and merging$/ { s = 1; next } s && /^## / { exit } s { print }' "$wf")
printf '%s\n' "$cisection" | grep -qF 'blocking review finding' || { echo "FAIL: $wf: the section 'CI and merging' does not name an open blocking review finding"; fail=1; }
for f in skills/next/SKILL.md skills/fix/SKILL.md; do
  for w in '## Review' 'Findings fixed' 'Findings still open' "$sentence"; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the review item: $w"; fail=1; }
  done
  for w in 'Open review findings' 'Review notes' 'Reviewed by the codeReviewer role on'; do
    if grep -qF -- "$w" "$f"; then echo "FAIL: $f still has the interim text '$w' of iteration 18 (it is replaced by the Review section)"; fail=1; fi
  done
done

echo "== slots free themselves"
# A busy slot whose pull request has merged is freed by -Reap / --reap and by the first step of every take
# (iteration 17), in both shells, with the tip check and the report text; the README says when it happens.
for f in scripts/slot.sh scripts/slot.ps1; do
  for w in 'released automatically' 'headRefOid'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not carry the automatic release item: $w"; fail=1; }
  done
done
for w in '--reap' '-Reap'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done

echo "== a separate spec reviewer reviews the spec"
# The spec reviewer (iteration 20): an agent file whose tool list keeps it read-only, the findings block of
# "Findings and fix rounds" (the same format lines as the code reviewer and the workflow skill), and /spec that
# launches it after the writer and before the commit. /spec is a conversation, so the lint pins the wording.
sr=agents/spec-reviewer.md
sfmt='^(Review: findings \| no findings|Blocking: <n>|Advisory: <n>|- blocking <file>:<line> .*|- advisory <file>:<line> .*)$'
if [ -f "$sr" ]; then
  grep -qx 'name: spec-reviewer' "$sr" || { echo "FAIL: $sr has no 'name: spec-reviewer'"; fail=1; }
  [ "$(sed -n 's/^tools:[[:space:]]*//p' "$sr" | head -1)" = "Read, Grep, Glob" ] || { echo "FAIL: $sr: the tools must be exactly 'Read, Grep, Glob' (no Bash, Write, Edit or Agent)"; fail=1; }
  json_load schema/nightmill.schema.json
  sr_default=$(json_get properties.roles.properties.specReviewer.properties.model.default)
  [ "$(sed -n 's/^model:[[:space:]]*//p' "$sr" | head -1)" = "$sr_default" ] || { echo "FAIL: $sr: model is not the schema default of roles.specReviewer.model ($sr_default)"; fail=1; }
  for w in 'changes nothing' 'acceptance criterion' 'Not done' 'decision' 'escalation' 'scope' 'blocking' 'advisory' 'no findings'; do
    grep -qF -- "$w" "$sr" || { echo "FAIL: $sr does not say: $w"; fail=1; }
  done
  # the format of the block is the same in the three files
  if [ -f agents/code-reviewer.md ] && [ "$(grep -E "$sfmt" agents/code-reviewer.md)" != "$(grep -E "$sfmt" "$sr")" ]; then
    echo "FAIL: the format lines of the findings block differ between agents/code-reviewer.md and $sr"; fail=1
  fi
  wsection=$(awk '/^## Findings and fix rounds$/ { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' skills/workflow/SKILL.md)
  if [ "$(printf '%s\n' "$wsection" | grep -E "$sfmt")" != "$(grep -E "$sfmt" "$sr")" ]; then
    echo "FAIL: the format lines of the findings block differ between skills/workflow/SKILL.md and $sr"; fail=1
  fi
else
  echo "FAIL: $sr is missing"; fail=1
fi
for w in 'nightmill:spec-reviewer' 'roles.specReviewer.model' 'Findings and fix rounds' 'validate-config' 'Stopped: the specReviewer ranks below' 'Stopped: the spec review could not be had' 'not a fork'; do
  grep -qF -- "$w" skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not mention the spec review item: $w"; fail=1; }
done

echo "== the spec review is recorded in the spec pull request"
# The spec pull request has the same "## Review" section as a code pull request (iteration 21), the roles substituted,
# an open blocking finding keeps auto-merge off with the same sentence and is said on the issue, and the interim text
# of iteration 20 is replaced, not kept beside the new section.
sentence='Auto-merge is not enabled: blocking review findings are still open (see Review).'
swf=skills/workflow/SKILL.md
swsection=$(awk '/^## Findings and fix rounds$/ { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' "$swf")
for w in 'A spec pull request has the same section' 'specReviewer role on <model>' 'specWriter role on <model>'; do
  printf '%s\n' "$swsection" | grep -qF -- "$w" || { echo "FAIL: $swf: the section 'Findings and fix rounds' does not say: $w"; fail=1; }
done
swci=$(awk '/^## CI and merging$/ { s = 1; next } s && /^## / { exit } s { print }' "$swf")
printf '%s\n' "$swci" | grep -qF '(a spec PR too)' || { echo "FAIL: $swf: the section 'CI and merging' does not name a spec PR (a spec PR too)"; fail=1; }
for w in '## Review' 'Findings fixed' 'Findings still open' "$sentence" 'Blocking review findings are still open (' 'Spec: <path> (PR #<pr>). Waiting for approval.'; do
  grep -qF -- "$w" skills/spec/SKILL.md || { echo "FAIL: skills/spec/SKILL.md does not mention the spec review item: $w"; fail=1; }
done
for w in 'Open review findings' 'Review notes' 'Reviewed by the specReviewer role on'; do
  if grep -qF -- "$w" skills/spec/SKILL.md; then echo "FAIL: skills/spec/SKILL.md still has the interim text '$w' of iteration 20 (it is replaced by the Review section)"; fail=1; fi
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
