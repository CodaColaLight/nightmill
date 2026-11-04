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
while IFS= read -r f; do
  if command -v jq >/dev/null 2>&1; then jq . "$f" >/dev/null || { echo "FAIL: $f does not parse"; fail=1; }
  else python3 -I -m json.tool "$f" >/dev/null || { echo "FAIL: $f does not parse"; fail=1; }
  fi
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
# The example and this repository's own config pass the validator with --strict (iteration 6): the bash
# validator when jq is installed, else the PowerShell one, else the check is skipped.
ps_cmd=""
if command -v pwsh >/dev/null 2>&1; then ps_cmd=pwsh; elif command -v powershell >/dev/null 2>&1; then ps_cmd=powershell; fi
for f in templates/nightmill.example.json .claude/nightmill.json; do
  if command -v jq >/dev/null 2>&1; then
    out=$(bash scripts/validate-config.sh --strict "$f" 2>&1) || { echo "$out"; echo "FAIL: $f does not validate"; fail=1; }
  elif [ -n "$ps_cmd" ]; then
    out=$("$ps_cmd" -NoProfile -ExecutionPolicy Bypass -File scripts/validate-config.ps1 -Config "$f" -Strict 2>&1) || { echo "$out"; echo "FAIL: $f does not validate"; fail=1; }
  else
    echo "skipped $f (no jq and no PowerShell)"
  fi
done

echo "== schema keywords are supported"
# scripts/validate-config.* understand type, properties, required, items, minimum, minItems,
# additionalProperties and enum. A schema that gains another constraint would be silently ignored by them.
for kw in '$ref' anyOf oneOf allOf not if pattern format const maxItems uniqueItems minLength maxLength maximum dependencies; do
  if grep -qF "\"$kw\"" schema/nightmill.schema.json; then
    echo "FAIL: schema/nightmill.schema.json uses \"$kw\", which scripts/validate-config.* does not support"; fail=1
  fi
done

echo "== shell"
for f in scripts/*.sh tests/*.sh; do
  bash -n "$f" || { echo "FAIL: $f does not parse"; fail=1; }
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning scripts/*.sh tests/*.sh || fail=1
else
  echo "(shellcheck not installed, skipped)"
fi

[ "$fail" = 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
