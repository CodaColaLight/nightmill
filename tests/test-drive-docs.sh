#!/usr/bin/env bash
# tests/test-drive-docs.sh - the driver, its keys, the workflow template and the README section (iteration 52, #164).
# Iteration 53 (#165): the driver also passes --max-turns and --max-budget-usd and edits an issue only to add blocked.
# Iteration 54 (#166): the driver also calls history.sh --run for its summary.
# Parts S (the driver sets no status), K (the config keys), T (the template), R (the README: the flags, keys, files and
# variables it names; its headings, their order and its sentences are the manual check's, iteration 73).
#   tests/test-drive-docs.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }
readme="$root/README.md"
schema="$root/schema/nightmill.schema.json"
example="$root/templates/nightmill.example.json"
tpl="$root/templates/workflows/nightmill-drive.yml"

forbidden=(--bare --dangerously-skip-permissions bypassPermissions --allowedTools --continue --resume)
# "issue edit" is allowed only as `issue edit <n> --add-label blocked` (iteration 53, decision 8)
nostatus=(item-edit item-add item-delete field-create updateProjectV2ItemFieldValue single-select-option-id "issue close" "pr merge" "label create")

# --- Part S ---
f=scripts/drive.sh
p="$root/$f"
if [ ! -f "$p" ]; then
  fail "$f: missing"
else
  for w in "/nightmill:fix all" "/nightmill:next" "--permission-mode manual" "--output-format json" "--max-turns" "--max-budget-usd" "issue comment" "nightmill-stop" "nightmill-drive.lock"; do
    grep -qF -- "$w" "$p" || fail "$f: does not contain '$w'"
  done
  # iteration 54 (#166): the summary carries the history of the run, computed by the history script of the same folder
  hw='history.sh" --run'
  grep -qF -- "$hw" "$p" || fail "$f: does not contain '$hw'"
  for w in "${nostatus[@]}" "${forbidden[@]}"; do
    if grep -qF -- "$w" "$p"; then fail "$f: contains '$w'"; fi
  done
  # every gh issue edit adds the label blocked and nothing else
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [[ "$l" == *"issue edit"*"--add-label blocked"* ]] || fail "$f: an 'issue edit' that does not add the label blocked: $l"
    for w in --remove-label --add-assignee --title --body --milestone; do
      case "$l" in *"$w"*) fail "$f: an 'issue edit' with $w: $l" ;; esac
    done
  done < <(grep -F 'issue edit' "$p" || true)
fi
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  mode=$(git -C "$root" ls-files -s scripts/drive.sh | awk '{ print $1 }')
  [ "$mode" = "100755" ] || fail "scripts/drive.sh: mode '$mode' in the index, 100755 expected"
fi
if [ -f "$schema" ]; then
  for k in backlog ready spec specReview approved inProgress review "done"; do
    grep -qE "^[[:space:]]*\"$k\": \{" "$schema" || fail "schema/nightmill.schema.json: board.statuses has no key $k"
  done
  st=$(awk '/"statuses": \{/ { s = 1; next } s && /"properties": \{/ { p = 1; next } s && p && /^ *"[A-Za-z]+": \{ *"type"/ { n++ } s && p && /^ *\}/ { exit } END { print n + 0 }' "$schema")
  [ "$st" = 8 ] || fail "schema/nightmill.schema.json: board.statuses has $st keys, 8 expected"
else
  fail "schema/nightmill.schema.json: missing"
fi

# --- Part K ---
# entry <key>: the schema lines of the "unattended" key <key> (from its line to the line holding its closing brace)
entry() { awk -v k="$1" '/"unattended": \{/ { u = 1 } u && $0 ~ "\"" k "\": \\{" { s = 1 } s { print } s && /\}/ { exit }' "$schema"; }
for k in maxMinutes summaryIssue; do
  e=$(entry "$k" | tr '\n' ' ')
  case "$e" in *'"type": "integer"'*) ;; *) fail "schema: unattended.$k is not an integer" ;; esac
  case "$e" in *'"minimum": 1'*) ;; *) fail "schema: unattended.$k has no minimum 1" ;; esac
done
e=$(entry maxMinutes | tr '\n' ' ')
case "$e" in *'"default": 240'*) ;; *) fail "schema: unattended.maxMinutes has no default 240" ;; esac
e=$(entry summaryIssue | tr '\n' ' ')
case "$e" in *'"default"'*) fail "schema: unattended.summaryIssue has a default" ;; esac
if [ -f "$example" ]; then
  grep -q '"unattended"' "$example" || fail "templates/nightmill.example.json: no unattended"
  grep -q '"maxMinutes": 240' "$example" || fail "templates/nightmill.example.json: no maxMinutes 240"
else
  fail "templates/nightmill.example.json: missing"
fi
row=$(grep -F '| `unattended` |' "$readme" | head -1 || true)
for w in maxMinutes "default 240" summaryIssue; do
  case "$row" in *"$w"*) ;; *) fail "README.md: the configuration table row of unattended lacks '$w'" ;; esac
done

# --- Part T ---
if [ ! -f "$tpl" ]; then
  fail "templates/workflows/nightmill-drive.yml: missing"
else
  for l in 'on:' '  schedule:' '  workflow_dispatch:' 'permissions: {}' 'concurrency:' '  group: nightmill-drive' \
           '  cancel-in-progress: false' '    runs-on: [self-hosted, nightmill]' '          bash "$root/scripts/drive.sh"'; do
    grep -qxF -- "$l" "$tpl" || fail "nightmill-drive.yml: no line '$l'"
  done
  grep -qE '^    - cron: "[0-9*/ ,-]+"$' "$tpl" || fail "nightmill-drive.yml: no cron line"
  t=$(sed -n 's/^    timeout-minutes: \([0-9][0-9]*\)$/\1/p' "$tpl" | head -1)
  if [ -z "$t" ] || [ "$t" -lt 1 ] || [ "$t" -gt 4320 ]; then fail "nightmill-drive.yml: timeout-minutes missing or not from 1 to 4320"; fi
  grep -qF 'shell: pwsh' "$tpl" && fail "nightmill-drive.yml: still has a shell: pwsh step"
  ext=ps1
  grep -qF "drive.$ext" "$tpl" && fail "nightmill-drive.yml: still names drive.$ext"
  grep -qF 'NIGHTMILL_CHECKOUT: ${{ vars.NIGHTMILL_CHECKOUT }}' "$tpl" || fail "nightmill-drive.yml: no NIGHTMILL_CHECKOUT variable"
  for w in 'uses:' 'secrets.' GITHUB_TOKEN GH_TOKEN ': write' "${forbidden[@]}"; do
    if grep -qF -- "$w" "$tpl"; then fail "nightmill-drive.yml: contains '$w'"; fi
  done
  while IFS= read -r l; do
    [[ "$l" =~ ^\ *NIGHTMILL_CHECKOUT:\ \$\{\{\ vars\.NIGHTMILL_CHECKOUT\ \}\}$ ]] || fail "nightmill-drive.yml: an expression outside the env value: $l"
  done < <(grep -F '${{' "$tpl" || true)
fi

# --- Part R ---
d=$(sed -n '/"maxMinutes": {/,/}/p' "$schema" | sed -n 's/.*"default": *\([0-9]*\).*/\1/p' | head -1)
for w in scripts/drive.sh templates/workflows/nightmill-drive.yml .git/nightmill-stop \
         "\`unattended.maxMinutes\` (default ${d:-240})" unattended.summaryIssue total_cost_usd 'permissions: {}' GITHUB_TOKEN \
         repo read:org project workflow self-hosted NIGHTMILL_CHECKOUT -- '--permission-mode manual'; do
  [ "$w" != -- ] || continue
  grep -qF -- "$w" "$readme" || fail "README.md lacks '$w'"
done
grep -qF '| `scripts/drive.sh` |' "$readme" || fail "README.md: no row of scripts/drive.sh in the plugin table"

exit "$bad"
