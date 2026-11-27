#!/usr/bin/env bash
# tests/test-docs-low-gaps.sh - regression test for #143 (LOW-DOCS): the low-severity inaccuracies in the README,
# .claude/CLAUDE.md, the schema and the forms that a text check can pin without a design choice. Each check names the
# item of the bug report it pins.
#   (a) the README's "What is in the plugin" table names every script in scripts/ (as `scripts/<name>.`) and every
#       skill (as `/nightmill:<name>`, the workflow skill as "`workflow` skill")
#   (b) the layout in .claude/CLAUDE.md names every skill folder on its `skills` line, every script in scripts/ on its
#       `scripts` line, and shows hooks/ and tests/fixtures
#   (c) the bug form's "What is affected" list (.github/ISSUE_TEMPLATE/nightmill-bug.yml, written by hand, not rendered
#       from templates/) names every skill and every script; the marketplace description names every skill as /<name>
#   (d) decision 0001 carries a note that 0003 partly supersedes it
#   (e) the schema's text about unknown keys agrees with the validator, which reports an unknown key as a warning
#   (f) no .ps1 file has a byte outside ASCII (an em dash) without a byte order mark: Windows PowerShell 5.1 reads a
#       file without one as ANSI (tests/smoke-render.ps1)
# Not pinned, they need a design or wording choice: the slot root guidance, the template board note, whether $schema and
# $id point to a version, the default of iterations.changelog (a story). Already fixed when this test was written: the
# README says the hook needs bash, the template board is described in the README.
#   tests/test-docs-low-gaps.sh [<root>]
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
fail=0

# tokens <text>: the words of a text (letters, digits and hyphens), one per line
tokens() { printf '%s\n' "$1" | tr -c 'A-Za-z0-9-' '\n'; }
# has_token <tokens> <name>: the name is one of the words, whole
has_token() { grep -qxF -- "$2" <<<"$1"; }

skills=()
for d in "$root"/skills/*/; do [ -d "$d" ] && skills+=("$(basename "$d")"); done
scripts=()
for f in "$root"/scripts/*.sh; do [ -f "$f" ] && scripts+=("$(basename "$f" .sh)"); done

# (a) the README table
readme="$root/README.md"
if [ ! -f "$readme" ]; then
  echo "FAIL: $readme is missing"; fail=1
else
  sect=$(awk '/^## What is in the plugin[[:space:]]*$/ { on = 1; next } on && /^## / { exit } on { print }' "$readme")
  if [ -z "$sect" ]; then
    echo "FAIL: README.md has no section '## What is in the plugin'"; fail=1
  else
    for s in "${scripts[@]}"; do
      if ! grep -qF -- "scripts/$s.sh" <<<"$sect"; then
        echo "FAIL: README.md 'What is in the plugin' does not name scripts/$s.sh"; fail=1
      fi
    done
    for k in "${skills[@]}"; do
      if [ "$k" = workflow ]; then
        want='`workflow` skill'
      else
        want="/nightmill:$k"
      fi
      if ! grep -qF -- "$want" <<<"$sect"; then
        echo "FAIL: README.md 'What is in the plugin' does not name the skill $k ($want)"; fail=1
      fi
    done
  fi
fi

# (b) the layout in .claude/CLAUDE.md
claude="$root/.claude/CLAUDE.md"
if [ ! -f "$claude" ]; then
  echo "FAIL: $claude is missing"; fail=1
else
  layout=$(awk '/^## Layout[[:space:]]*$/ { on = 1; next } on && /^## / { exit } on { print }' "$claude")
  # a layout line and the indented lines that continue it
  block() { awk -v k="$1" '$1 == k { on = 1; print; next } on && /^[[:space:]]+[^[:space:]]/ { print; next } { on = 0 }' <<<"$layout"; }
  skill_t=$(tokens "$(block skills)")
  script_t=$(tokens "$(block scripts)")
  all_t=$(tokens "$layout")
  for k in "${skills[@]}"; do
    has_token "$skill_t" "$k" || { echo "FAIL: .claude/CLAUDE.md layout: the skills line does not name skills/$k"; fail=1; }
  done
  for s in "${scripts[@]}"; do
    has_token "$script_t" "$s" || { echo "FAIL: .claude/CLAUDE.md layout: the scripts line does not name scripts/$s"; fail=1; }
  done
  has_token "$all_t" hooks || { echo "FAIL: .claude/CLAUDE.md layout does not show hooks/"; fail=1; }
  has_token "$all_t" fixtures || { echo "FAIL: .claude/CLAUDE.md layout does not show tests/fixtures"; fail=1; }
fi

# (c) the bug form and the marketplace description
form="$root/.github/ISSUE_TEMPLATE/nightmill-bug.yml"
if [ ! -f "$form" ]; then
  echo "FAIL: $form is missing"; fail=1
else
  opts=$(awk '/label:[[:space:]]*What is affected/ { on = 1; next } on && /^[[:space:]]*validations:/ { exit } on { print }' "$form")
  if [ -z "$opts" ]; then
    echo "FAIL: nightmill-bug.yml has no 'What is affected' list"; fail=1
  else
    skill_t=$(tokens "$(grep -E -- '^[[:space:]]*-[[:space:]]*A skill' <<<"$opts")")
    script_t=$(tokens "$(grep -E -- '^[[:space:]]*-[[:space:]]*A script' <<<"$opts")")
    for k in "${skills[@]}"; do
      has_token "$skill_t" "$k" || { echo "FAIL: nightmill-bug.yml 'What is affected': the skill list does not name $k"; fail=1; }
    done
    for s in "${scripts[@]}"; do
      has_token "$script_t" "$s" || { echo "FAIL: nightmill-bug.yml 'What is affected': the script list does not name $s"; fail=1; }
    done
  fi
fi
market="$root/.claude-plugin/marketplace.json"
if [ ! -f "$market" ]; then
  echo "FAIL: $market is missing"; fail=1
else
  mtext=$(cat "$market")
  for k in "${skills[@]}"; do
    [ "$k" = workflow ] && continue
    if ! grep -qE -- "/$k([^A-Za-z0-9-]|\$)" <<<"$mtext"; then
      echo "FAIL: .claude-plugin/marketplace.json: the description does not name the skill /$k"; fail=1
    fi
  done
fi

# (d) decision 0001 says 0003 partly supersedes it
dec=$(ls "$root"/docs/decisions/0001-*.md 2>/dev/null | head -1)
if [ -z "$dec" ]; then
  echo "FAIL: docs/decisions/0001-*.md is missing"; fail=1
elif ! grep -qiE -- 'supersed.*0003|0003.*supersed' "$dec"; then
  echo "FAIL: docs/decisions/0001 has no note that it is partly superseded by 0003"; fail=1
fi

# (e) the schema does not claim that unknown keys are ignored when the validator warns about them
schema="$root/schema/nightmill.schema.json"
vawk="$root/scripts/lib/validate.awk"
if [ ! -f "$schema" ] || [ ! -f "$vawk" ]; then
  echo "FAIL: $schema or $vawk is missing"; fail=1
else
  if grep -qF -- 'vfinding(cpath, "warning", msg)' "$vawk"; then
    rootdesc=$(sed -n 's/^  "description":[[:space:]]*"\(.*\)",[[:space:]]*$/\1/p' "$schema" | head -1)
    if grep -qiE -- 'unknown keys? (are|is) ignored' <<<"$rootdesc" && ! grep -qiE -- 'warn' <<<"$rootdesc"; then
      echo "FAIL: schema/nightmill.schema.json says unknown keys are ignored, but scripts/validate-config.* reports an unknown key as a warning (an error with --strict): '$rootdesc'"
      fail=1
    fi
  else
    echo "FAIL: scripts/lib/validate.awk no longer reports an unknown key as a warning; revise check (e) of tests/test-docs-low-gaps.sh"; fail=1
  fi
fi

# (f) a .ps1 file with a byte outside ASCII has a byte order mark
while IFS= read -r f; do
  [ -f "$f" ] || continue
  LC_ALL=C grep -q $'[\x80-\xff]' "$f" || continue
  bom=$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')
  if [ "$bom" != "efbbbf" ]; then
    echo "FAIL: ${f#"$root"/} has a character outside ASCII (an em dash) and no byte order mark: Windows PowerShell 5.1 reads it as ANSI"
    fail=1
  fi
done < <(find "$root" -name '*.ps1' -not -path '*/.git/*' -not -path '*/node_modules/*' | sort)

[ "$fail" -eq 0 ] && echo "ok: the low-severity documentation gaps pinned by #143 are closed"
exit "$fail"
