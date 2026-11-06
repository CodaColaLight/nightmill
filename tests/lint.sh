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
    agents/worker.md|agents/code-reviewer.md|agents/spec-reviewer.md|agents/tester.md) ;;
    *) echo "FAIL: $a: only the worker, the two reviewers and the tester have an agent file (the implementer's and the fixer's prompts are in the skills)"; fail=1 ;;
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

echo "== capacity is wired"
# The slot count and the agent limit can be changed during a session (iteration 22): both slot scripts keep the live
# values in capacity.json and have the capacity command, the skills read the agent limit from it at every decision to
# start an agent (not once from the configuration), and the README says how and what wins.
for f in scripts/slot.sh scripts/slot.ps1; do
  grep -qF 'capacity.json' "$f" || { echo "FAIL: $f does not keep the live values in capacity.json"; fail=1; }
done
grep -qF -- '--capacity' scripts/slot.sh || { echo "FAIL: scripts/slot.sh has no --capacity"; fail=1; }
grep -qF -- '-Capacity' scripts/slot.ps1 || { echo "FAIL: scripts/slot.ps1 has no -Capacity"; fail=1; }
for w in '--capacity --porcelain' '-Capacity -Porcelain'; do
  grep -qF -- "$w" skills/workflow/SKILL.md || { echo "FAIL: skills/workflow/SKILL.md does not read the agent limit with $w"; fail=1; }
done
for f in skills/next/SKILL.md skills/fix/SKILL.md skills/spec/SKILL.md; do
  if ! grep -qF -- '--capacity --porcelain' "$f" && ! grep -qF -- '-Capacity -Porcelain' "$f"; then
    echo "FAIL: $f does not read the agent limit with the capacity command"; fail=1
  fi
  if grep -qF 'At `parallel.maxAgents` wait' "$f"; then
    echo "FAIL: $f still waits at parallel.maxAgents read once (the agent limit is read at every decision)"; fail=1
  fi
done
for w in '--capacity' '-Capacity' 'WORKER_SLOTS'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done

echo "== slots report what their agent does"
# A skill that works in a slot records its skill, role, step and the time in the slot's marker (iteration 23): both
# slot scripts have the report command and decide running or stalled from worktrees.stalledAfterMinutes; /status
# prints the agent state the slot script gives (no rule of its own) in one Slots section; /next and /fix report at
# each step; the schema, the example and the README carry the key, and the README says what the states mean.
for f in scripts/slot.sh scripts/slot.ps1; do
  for w in 'reported' 'stalledAfterMinutes'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not carry the report item: $w"; fail=1; }
  done
done
grep -qF -- '--report' scripts/slot.sh || { echo "FAIL: scripts/slot.sh has no --report"; fail=1; }
grep -qF -- '-Report' scripts/slot.ps1 || { echo "FAIL: scripts/slot.ps1 has no -Report"; fail=1; }
for f in scripts/lib/status.awk scripts/status.ps1; do
  if grep -qF 'slots: none busy' "$f"; then echo "FAIL: $f still prints 'slots: none busy' (the Slots section lists every slot)"; fail=1; fi
  if grep -qF 'stalledAfterMinutes' "$f"; then echo "FAIL: $f reads stalledAfterMinutes (the slot script decides running or stalled)"; fail=1; fi
done
for f in skills/next/SKILL.md skills/fix/SKILL.md; do
  for w in '--report' '-Report' 'slot-taken' 'code-review' 'done'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the report item: $w"; fail=1; }
  done
done
grep -qF '"stalledAfterMinutes": { "type": "integer", "minimum": 1, "default": 30,' schema/nightmill.schema.json || { echo "FAIL: the schema has no stalledAfterMinutes with default 30"; fail=1; }
for f in templates/nightmill.example.json README.md; do
  grep -qF 'stalledAfterMinutes' "$f" || { echo "FAIL: $f does not mention stalledAfterMinutes"; fail=1; }
done
for w in 'running' 'stalled' 'unknown'; do
  grep -qF -- "**$w**" README.md || { echo "FAIL: README.md does not say what $w means"; fail=1; }
done

echo "== a tester writes the failing tests first"
# /next has a tester subagent write the failing tests for every acceptance criterion before the implementer (iteration
# 25): an agent file whose tool list has no Agent, the same test path rule in the agent and in the skill, and /next that
# launches it, checks its files and carries its result into the implementer's prompt and the pull request. /next is a
# conversation, so the lint pins the wording the behaviour depends on; the manual check does the behaviour.
ta=agents/tester.md
nx=skills/next/SKILL.md
if [ -f "$ta" ]; then
  grep -qx 'name: tester' "$ta" || { echo "FAIL: $ta has no 'name: tester'"; fail=1; }
  [ "$(sed -n 's/^tools:[[:space:]]*//p' "$ta" | head -1)" = "Read, Grep, Glob, Write, Edit, Bash" ] || { echo "FAIL: $ta: the tools must be exactly 'Read, Grep, Glob, Write, Edit, Bash' (no Agent)"; fail=1; }
  json_load schema/nightmill.schema.json
  ta_default=$(json_get properties.roles.properties.tester.properties.model.default)
  [ "$(sed -n 's/^model:[[:space:]]*//p' "$ta" | head -1)" = "$ta_default" ] || { echo "FAIL: $ta: model is not the schema default of roles.tester.model ($ta_default)"; fail=1; }
  for w in 'acceptance criterion' 'not tested' 'named for the behaviour' 'only test files and test fixtures' 'production code' \
           'fails for another reason' 'passes' 'Do not commit' 'Do not stage, stash or commit anything' 'do not push' \
           'do not launch other agents' 'Result: complete | partial | failed' 'Criteria:' 'Tests:' 'Failing:' 'Files:' 'Left:'; do
    grep -qF -- "$w" "$ta" || { echo "FAIL: $ta does not say: $w"; fail=1; }
  done
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
for w in 'nightmill:tester' 'roles.tester.model' 'Stopped: the tester role cannot run on' 'Stopped: the tester returned failed' \
         'Stopped: the tester changed files that are not tests' 'status --porcelain --untracked-files=all' '<tester files>' \
         'never writes the tests or the code itself' 'verification.benchRule' 'Do not commit: leave the tests uncommitted in the slot' \
         "Run the tester's tests" "into the slot's working tree and has not committed them" \
         'Commit them together with your code, once the check is green' "If you cannot meet a criterion, do not commit the tester's test of it" \
         'unmet: <path> (criterion <n>)' 'Unmet tests for #' '-m "Unmet tests for #<issue>: <title>"' 'stash list' 'stash pop stash@{<n>}' \
         'not committed: criterion not met' 'Tests written first by the tester role on' \
         'never writes the code itself' 'git -C <slot> log origin/<git.baseBranch>..HEAD'; do
  grep -qF -- "$w" "$nx" || { echo "FAIL: $nx does not mention the tester item: $w"; fail=1; }
done
for w in 'Turn each acceptance criterion into a test' '-m "unmet tests"'; do
  if grep -qF -- "$w" "$nx"; then echo "FAIL: $nx still says '$w'"; fail=1; fi
done
# the tests of unmet criteria are set aside first in step 5, before the CHANGELOG entry is committed
grep -qE '^5\. When the implementer.s result is `partial`' "$nx" || { echo "FAIL: $nx: step 5 does not begin by setting the tests of unmet criteria aside"; fail=1; }
wfs=skills/workflow/SKILL.md
vsection=$(awk '/^## Verify before every commit$/ { s = 1; next } s && /^## / { exit } s { print }' "$wfs")
printf '%s\n' "$vsection" | grep -qF 'Never commit red.' || { echo "FAIL: $wfs: the section 'Verify before every commit' no longer says: Never commit red."; fail=1; }
dsection=$(awk '/^## Definition of done$/ { s = 1; next } s && /^## / { exit } s { print }' "$wfs")
for w in 'written first by the' 'seen failing before the code'; do
  printf '%s\n' "$dsection" | grep -qF -- "$w" || { echo "FAIL: $wfs: the section 'Definition of done' does not say: $w"; fail=1; }
done
grep -qF 'agents/tester.md' README.md || { echo "FAIL: README.md does not mention agents/tester.md"; fail=1; }

echo "== a tester reproduces the bug before /fix"
# /fix has the same tester write a regression test from the bug report before the fixer (iteration 26): the same test
# path rule as the agent, the launch, the checks of its files, the stop when it cannot reproduce the bug, the fixer that
# runs the test and commits it with the fix, and the pull request that shows it. /fix is a conversation, so the lint
# pins the wording the behaviour depends on (each item on one line); the manual check does the behaviour.
fx=skills/fix/SKILL.md
n_tp=$(grep -cE "$tp_re" "$fx" 2>/dev/null || true)
[ "$n_tp" = 1 ] || { echo "FAIL: $fx has ${n_tp:-no} lines starting with 'Test paths:' (exactly one expected)"; fail=1; }
tp_fix=$(grep -E "$tp_re" "$fx" 2>/dev/null | head -1 | sed -E 's/^[[:space:]`]+//; s/[[:space:]`]+$//' || true)
if [ -z "$tp_agent" ] || [ "$tp_agent" != "$tp_fix" ]; then
  echo "FAIL: the 'Test paths:' line differs between $ta and $fx"; fail=1
fi
sed -n 's/^description:[[:space:]]*//p' "$ta" 2>/dev/null | head -1 | grep -qF '/fix' || { echo "FAIL: $ta: the description does not name /fix"; fail=1; }
for w in 'nightmill:tester' 'roles.tester.model' 'Stopped: the tester role cannot run on' 'Stopped: the tester returned failed' \
         'Stopped: the tester changed files that are not tests' 'Stopped: the tester could not reproduce bug #' \
         'The fixer was not started.' 'status --porcelain --untracked-files=all' '<tester files>' \
         'never writes the test or the code itself' 'verification.benchRule' 'Write the failing regression test for bug #' \
         'Do not commit: leave the test uncommitted in the slot' '"the implementer" as the fixer' \
         'The one acceptance criterion: 1. <title> is fixed.' "Run the tester's test and watch it fail" \
         "into the slot's working tree and has not committed it" 'Commit it together with your fix, once the check is green' \
         'A fix that does not make this test pass is not a fix' 'In a fix round the test may already be committed with your earlier fix' \
         'diff --name-only origin/<git.baseBranch>..HEAD' 'Reproduced first by the tester role on' \
         "The test's diff is longer than 60 lines" 'write-tests' 'One producer at a time' 'Tester files for #<issue>: <title>'; do
  grep -qF -- "$w" "$fx" || { echo "FAIL: $fx does not mention the tester item: $w"; fail=1; }
done
for w in 'Write the test that fails for the reason in the issue first' 'One fixer at a time'; do
  if grep -qF -- "$w" "$fx"; then echo "FAIL: $fx still says '$w'"; fail=1; fi
done
rsection=$(awk '/^## Agent roles and models$/ { s = 1; next } s && /^## / { exit } s { print }' skills/workflow/SKILL.md)
printf '%s\n' "$rsection" | grep -E '^\| `tester` \|' | grep -qF 'before the fixer' || { echo "FAIL: skills/workflow/SKILL.md: the tester row of 'Agent roles and models' does not say: before the fixer"; fail=1; }
grep -qF 'before the fixer' README.md || { echo "FAIL: README.md does not say the tester works before the fixer"; fail=1; }

echo "== the tester's tests are guarded"
# The implementer and the fixer may not change the tester's files (iteration 27): their prompts forbid it, the session
# records every tester file as a blob, checks it after every result with git and undoes a change as a failed round, and
# a disputed test goes back to the tester, who revises it or says why it stands; a dispute and an undone round each use
# one fix round, and a dispute still open keeps auto-merge off. /next and /fix are conversations, so the lint pins the
# wording the behaviour depends on (each item on one line); the manual check does the behaviour.
for w in 'A dispute' 'revised:' 'stands:' 'never weaken a test to let the code pass' 'Change only the files named in the dispute' 'Answers:'; do
  grep -qF -- "$w" "$ta" || { echo "FAIL: $ta does not say the dispute item: $w"; fail=1; }
done
sed -n 's/^description:[[:space:]]*//p' "$ta" 2>/dev/null | head -1 | grep -qF 'disputes' || { echo "FAIL: $ta: the description does not say the tester answers when its tests are disputed"; fail=1; }
for f in "$nx" "$fx"; do
  for w in '<tester blobs>' '<round base>' '<dispute base>' 'is still <dispute base>' \
           'replaces the old line of <tester blobs> for that path' 'keeps its old line' \
           'whose answers are all stands: fails the check' 'but answered every test in it stands:' \
           'nothing committed and the dispute is still open' 'diff --no-index -- /dev/null <path>' \
           'hash-object -w -- <path>' 'rev-parse -q --verify HEAD:<path>' 'merge-base --is-ancestor <round base> HEAD' \
           'reset --mixed -q <round base>' 'update-index --add --cacheinfo <mode>,<blob>,<path>' 'checkout-index -f --' \
           'Stopped: the tester returned failed: it deleted <path>' 'do not edit, rename, move, overwrite or delete any of them' \
           "You may add tests of your own, in files that are not the tester's" \
           'a change to one fails your round, and the round is undone' \
           "If you believe a tester's test is wrong or cannot be satisfied, do not change it" \
           'Disputes: <one line per disputed test' 'Answer a dispute over your' 'The tester has answered the dispute' \
           'that change is undone' 'dispute-<k>' '## Disputed tests' '- Disputes still open: <d>' \
           'revised by the tester after a dispute in fix round' \
           "Auto-merge is not enabled: a dispute over the tester's tests is still open (see Disputed tests)."; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the guard item: $w"; fail=1; }
  done
done
grep -qF "Stopped: the implementer changed the tester's tests" "$nx" || { echo "FAIL: $nx does not stop when the implementer changed the tester's tests"; fail=1; }
for w in "Stopped: the fixer changed the tester's tests" '-m "Disputed test for #<issue>: <title>"'; do
  grep -qF -- "$w" "$fx" || { echo "FAIL: $fx does not mention the guard item: $w"; fail=1; }
done
gsection=$(awk '/^## Findings and fix rounds$/ { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' skills/workflow/SKILL.md)
printf '%s\n' "$gsection" | grep -qF "a dispute over a tester's test" || { echo "FAIL: skills/workflow/SKILL.md: the section 'Findings and fix rounds' does not say: a dispute over a tester's test"; fail=1; }
grep -qF 'Disputed tests' README.md || { echo "FAIL: README.md does not mention Disputed tests"; fail=1; }

echo "== the code reviewer reviews the tests"
# The code reviewer judges the tests (iteration 29): every criterion has a test that would fail for a wrong
# implementation, no test of the tester's was weakened compared with what it first wrote, and a test that cannot fail is
# reported. A finding whose fix belongs in the tester's tests begins with "test: " and goes to the tester through the
# dispute launch, in the same fix round as the code findings. The skills and the agent are conversations, so the lint
# pins the wording the behaviour depends on (each item on one line); the manual check does the behaviour.
for w in 'would fail for a plausible wrong implementation' "No test of the tester's was weakened" 'removed, skipped, loosened' \
         'made conditional' 'is not removed' 'always true' 'never fails' 'only a mock' 'begins its text with' '`test: `' \
         'rule 1 wins' "never an existing file that is not the tester's" 'matches the `Test paths:` line in your prompt'; do
  grep -qF -- "$w" "$cr" || { echo "FAIL: $cr does not say the test review item: $w"; fail=1; }
done
if grep -qF 'or the like' "$cr"; then echo "FAIL: $cr says 'or the like' (name what is meant)"; fail=1; fi
for f in "$nx" "$fx"; do
  for w in '<tester originals>' 'diff <original blob> <blob>' "The tester's files, written before the code" \
           "The tester's revisions after its first launch" "and not the tester's" \
           'A blocking line is a test finding when its text begins with' '`test: `, whatever file it names' \
           'is not sent to the tester again' 'test-finding-<k>' "Answer the code review's findings on your" \
           'read "a dispute" as these findings' 'The tester has answered the code review' \
           "tester's answer to the code review in fix round" 'the `Test paths:` line of "The tester", step 3' \
           'exempt from the check that every disputed file exists' 'this file exists: revise it or say why it stands' \
           'this path does not exist yet: create it, or write the missing test in another new file on a test path, or say why none is needed' \
           'this file is not yours: leave it unchanged' 'When their number differs from the number of test findings sent'; do
    grep -qF -- "$w" "$f" || { echo "FAIL: $f does not mention the test review item: $w"; fail=1; }
  done
done
n_crit=$(grep -cF 'The one acceptance criterion: 1. <title> is fixed.' "$fx" || true)
[ "${n_crit:-0}" -ge 2 ] || { echo "FAIL: $fx says 'The one acceptance criterion: 1. <title> is fixed.' on ${n_crit:-0} lines (at least 2 expected)"; fail=1; }
crsection=$(awk '/^## The code review$/ { s = 1; next } s && /^```/ { f = !f } s && !f && /^## / { exit } s { print }' "$fx")
printf '%s\n' "$crsection" | grep -qF 'The one acceptance criterion: 1. <title> is fixed.' || { echo "FAIL: $fx: the reviewer's prompt does not carry the one acceptance criterion"; fail=1; }
for w in 'loosened or made conditional' 'is a test finding'; do
  printf '%s\n' "$gsection" | grep -qF -- "$w" || { echo "FAIL: skills/workflow/SKILL.md: the section 'Findings and fix rounds' does not say: $w"; fail=1; }
done
grep -qF 'test finding' README.md || { echo "FAIL: README.md does not mention a test finding"; fail=1; }

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

echo "== load is wired"
# A read-only command measures CPU load and free memory and suggests an agent limit (iteration 24): both scripts, both
# libraries and both smoke tests exist, the scripts only read, the libraries carry every reader, the schema, the example
# and the README carry the three keys, /init's rule of thumb is the schema default, and the check and CI run the tests.
for f in scripts/load.sh scripts/load.ps1 scripts/lib/load.sh scripts/lib/load.ps1 tests/smoke-load.sh tests/smoke-load.ps1; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
for f in scripts/load.sh scripts/load.ps1 scripts/lib/load.sh scripts/lib/load.ps1; do
  if [ -f "$f" ] && grep -nE 'Set-Content|Out-File|Add-Content|Remove-Item|New-Item|Move-Item|--slot-count|--agent-limit|-SlotCount|-AgentLimit|--clear|-Clear|--take|--release|--abandon|--reap|(^|[^A-Za-z0-9_-])gh +[a-z]' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -q .; then
    echo "FAIL: $f writes or changes something; load only reads"; fail=1
  fi
done
for f in scripts/lib/load.sh scripts/lib/load.ps1; do
  for w in NIGHTMILL_LOAD_FIXTURE /proc/stat /proc/meminfo MemAvailable vm_stat hw.memsize; do
    grep -qF -- "$w" "$f" 2>/dev/null || { echo "FAIL: $f does not carry the reader item: $w"; fail=1; }
  done
done
for w in Win32_PerfRawData_PerfOS_Processor Win32_OperatingSystem; do
  grep -qF -- "$w" scripts/lib/load.ps1 2>/dev/null || { echo "FAIL: scripts/lib/load.ps1 does not read $w"; fail=1; }
done
for w in LoadPercentage Get-Counter; do
  if grep -qF -- "$w" scripts/lib/load.ps1 2>/dev/null; then echo "FAIL: scripts/lib/load.ps1 uses $w (see the spec of iteration 24)"; fail=1; fi
done
json_load schema/nightmill.schema.json
for spec in maxSuggestedAgents:4:1 memoryPerAgentGB:8:1 loadWindowSeconds:10:2; do
  k=${spec%%:*}; rest=${spec#*:}; d=${rest%%:*}; lo=${rest#*:}; p=properties.parallel.properties.$k
  [ "$(json_get "$p.type")" = integer ] || { echo "FAIL: schema: parallel.$k is not an integer"; fail=1; }
  [ -n "$(json_get "$p.description")" ] || { echo "FAIL: schema: parallel.$k has no description"; fail=1; }
  [ "$(json_get "$p.default")" = "$d" ] || { echo "FAIL: schema: parallel.$k default is not $d"; fail=1; }
  [ "$(json_get "$p.minimum")" = "$lo" ] || { echo "FAIL: schema: parallel.$k minimum is not $lo"; fail=1; }
done
gb_default=$(json_get properties.parallel.properties.memoryPerAgentGB.default)
json_load templates/nightmill.example.json
for spec in maxSuggestedAgents:4 memoryPerAgentGB:8 loadWindowSeconds:10; do
  k=${spec%%:*}; d=${spec#*:}
  [ "$(json_get "parallel.$k")" = "$d" ] || { echo "FAIL: templates/nightmill.example.json: parallel.$k is not the schema default $d"; fail=1; }
done
grep -qF -- "one per $gb_default GB" skills/init/SKILL.md || { echo "FAIL: skills/init/SKILL.md does not say 'one per $gb_default GB' (the schema default of parallel.memoryPerAgentGB)"; fail=1; }
for w in load.sh load.ps1 maxSuggestedAgents memoryPerAgentGB loadWindowSeconds 'rate limits' 'token budget'; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
for f in tests/smoke-load.sh tests/smoke-load.ps1; do
  grep -qF NIGHTMILL_LOAD_FIXTURE "$f" 2>/dev/null || { echo "FAIL: $f does not set NIGHTMILL_LOAD_FIXTURE"; fail=1; }
done
for f in tests/check.sh .github/workflows/ci.yml; do
  grep -qF 'smoke-load' "$f" || { echo "FAIL: $f does not run smoke-load"; fail=1; }
done

echo "== room is wired"
# A skill checks that the machine has room before it starts an agent (iteration 28): both room scripts and both smoke
# tests exist, the scripts only read and hold back, they measure 3 samples with the library, the schema, the example and
# the README carry the five keys, the rule is in the workflow skill once and the three skills point to it at every
# launch, and the check and CI run the tests.
for f in scripts/room.sh scripts/room.ps1 tests/smoke-room.sh tests/smoke-room.ps1; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
for f in scripts/room.sh scripts/room.ps1; do
  if [ -f "$f" ] && grep -nE 'Set-Content|Out-File|Add-Content|Remove-Item|New-Item|Move-Item|--slot-count|--agent-limit|-SlotCount|-AgentLimit|--clear|-Clear|--take|--release|--abandon|--reap|(^|[^A-Za-z0-9_-])gh +[a-z]|slot\.sh|slot\.ps1|--capacity|-Capacity|Stop-Process|taskkill|(^|[^A-Za-z0-9_-])kill( |$)' "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -q .; then
    echo "FAIL: $f writes, changes or stops something, or calls a slot script; room only reads and holds back"; fail=1
  fi
done
for w in 'load_measure 3' 'room_settings' '--since'; do
  grep -qF -- "$w" scripts/room.sh 2>/dev/null || { echo "FAIL: scripts/room.sh does not carry: $w"; fail=1; }
done
for w in 'Measure-Load -Samples 3' 'Get-RoomSettings' 'Since'; do
  grep -qF -- "$w" scripts/room.ps1 2>/dev/null || { echo "FAIL: scripts/room.ps1 does not carry: $w"; fail=1; }
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
for w in 'scripts/room.ps1' 'scripts/room.sh' 'Stopped: no room on this machine' 'never changes the agent limit, stops an agent or releases a slot'; do
  grep -qF -- "$w" skills/workflow/SKILL.md || { echo "FAIL: skills/workflow/SKILL.md does not say: $w"; fail=1; }
done
for spec in next:7 fix:6 spec:3; do
  s=skills/${spec%%:*}/SKILL.md; want=${spec#*:}
  n_room=$(grep -cF 'check the room on the machine' "$s" || true)
  [ "${n_room:-0}" -ge "$want" ] || { echo "FAIL: $s says 'check the room on the machine' on ${n_room:-0} lines (at least $want expected)"; fail=1; }
  for w in room.sh room.ps1 roomMin; do
    if grep -qF -- "$w" "$s"; then echo "FAIL: $s names $w (the rule lives in the workflow skill only)"; fail=1; fi
  done
done
for w in room.sh room.ps1 roomCheck roomMinFreeMB roomMaxCpuPercent roomPauseSeconds roomMaxWaitMinutes; do
  grep -qF -- "$w" README.md || { echo "FAIL: README.md does not mention $w"; fail=1; }
done
for f in tests/smoke-room.sh tests/smoke-room.ps1; do
  grep -qF NIGHTMILL_LOAD_FIXTURE "$f" 2>/dev/null || { echo "FAIL: $f does not set NIGHTMILL_LOAD_FIXTURE"; fail=1; }
done
for f in tests/check.sh .github/workflows/ci.yml; do
  grep -qF 'smoke-room' "$f" || { echo "FAIL: $f does not run smoke-room"; fail=1; }
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
