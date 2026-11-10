#!/usr/bin/env bash
# tests/test-config-from-base.sh - iteration 48 (#111): the skills and the slot script read the config from the base
# branch, git.mergeFlags must contain --auto and never --admin, and a change under .claude/ or .github/ is never
# auto-merged. Pins on the text of the schema, the skills, the scripts and the README, as the spec's lint section lists
# them. tests/lint.sh calls this file.
#   tests/test-config-from-base.sh [<root>]   # root: the checkout to read (default: this one)
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }

# flat <file>: the file's text on one line, whitespace squeezed
flat() { tr '\n' ' ' < "$1" | sed -E 's/[[:space:]]+/ /g'; }
# has <flat text> <needle>
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
# need <file> <needle>: the file (flattened) contains the needle
need() {
  local text
  [ -f "$root/$1" ] || { fail "$1: missing"; return; }
  text=$(flat "$root/$1")
  has "$text" "$2" || fail "$1: lacks: $2"
}
# lacks <file> <needle>
lacks() {
  local text
  [ -f "$root/$1" ] || { fail "$1: missing"; return; }
  text=$(flat "$root/$1")
  if has "$text" "$2"; then fail "$1: still has: $2"; fi
}

echo "== git.mergeFlags: pattern, not and a description"
schema=$(flat "$root/schema/nightmill.schema.json")
has "$schema" '"pattern": "^(.* )?--auto( .*)?$"' || fail "schema: git.mergeFlags has no pattern for the word --auto"
has "$schema" '"not": { "pattern": "^(.* )?--admin(( |=).*)?$" }' || fail "schema: git.mergeFlags has no not-pattern for the word --admin"
mf=${schema#*'"mergeFlags"'}
mf=${mf%%'"description"'*}
has "$mf" '"default": "--auto --squash"' || fail "schema: git.mergeFlags lost its default"
tail_text=${schema#*'"mergeFlags"'}
desc=${tail_text#*'"description": "'}
desc=${desc%%'"'*}
has "$tail_text" 'Must contain the word --auto and never --admin' || fail "schema: the description of git.mergeFlags does not say it must contain --auto and never --admin"
[ -n "$desc" ] || fail "schema: git.mergeFlags has no description"

echo "== the lint accepts pattern and not, and polices them"
lint="$root/tests/lint.sh"
if [ -f "$lint" ]; then
  kwline=$(grep -F 'for kw in' "$lint" | grep -F 'anyOf' | head -n 1 || true)
  [ -n "$kwline" ] || fail "tests/lint.sh: the forbidden keyword list is not found"
  case " $kwline " in *" pattern "*) fail "tests/lint.sh: pattern is still on the forbidden keyword list" ;; esac
  case " $kwline " in *" not "*) fail "tests/lint.sh: not is still on the forbidden keyword list" ;; esac
fi

echo "== the merge step checks --auto and --admin before it runs"
for f in skills/workflow/SKILL.md skills/spec/SKILL.md skills/next/SKILL.md skills/fix/SKILL.md; do
  need "$f" 'it must contain --auto and never --admin'
done

echo "== the injection and allowed-tools of the six skills"
inj='!`git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || git for-each-ref --count=1 --format="NO origin/HEAD, but %(refname)" refs/remotes/origin; git show origin/HEAD:.claude/nightmill.json 2>/dev/null || echo "NO BASE CONFIG: read .claude/nightmill.json of the working tree (cat .claude/nightmill.json); without it, run /nightmill:init first"`'
allowed='allowed-tools: Bash(git symbolic-ref -q --short refs/remotes/origin/HEAD *), Bash(git for-each-ref --count=1 *), Bash(git show origin/*:.claude/nightmill.json *), Bash(echo "NO BASE CONFIG*"), Bash(cat .claude/nightmill.json *)'
for name in workflow spec next fix story check; do
  f="$root/skills/$name/SKILL.md"
  [ -f "$f" ] || { fail "skills/$name/SKILL.md: missing"; continue; }
  grep -qxF -- "$inj" "$f" || fail "skills/$name/SKILL.md: the injection line of the base configuration is not there exactly"
  grep -qxF -- "$allowed" "$f" || fail "skills/$name/SKILL.md: allowed-tools is not exactly the base configuration's rules"
  if grep -F '!`cat .claude/nightmill.json' "$f" >/dev/null; then fail "skills/$name/SKILL.md: still injects the working tree's config with cat"; fi
  grep -F -- 'Project configuration on the base branch (`origin/HEAD:.claude/nightmill.json`; the first line names the base ref; see **The configuration**' "$f" >/dev/null || fail "skills/$name/SKILL.md: the lead-in of the injection is not the base configuration's"
done
need skills/workflow/SKILL.md '**The configuration**'
need skills/workflow/SKILL.md 'git remote set-head origin --auto'
need skills/workflow/SKILL.md 'git show origin/<git.baseBranch>:.claude/nightmill.json'
lacks skills/workflow/SKILL.md 'read from `.claude/nightmill.json` when it starts'
need skills/workflow/SKILL.md 'read from the run'"'"'s configuration (**The configuration**) when it starts'
need skills/workflow/SKILL.md 'origin/HEAD is not set, so the base branch'"'"'s configuration cannot be found; run git remote set-head origin --auto once'
need skills/workflow/SKILL.md 'nightmill: no branch of origin is known; the configuration is read from the working tree.'
need skills/workflow/SKILL.md 'nightmill: origin/HEAD has no .claude/nightmill.json; the configuration is read from the working tree.'
for name in spec next fix; do
  need "skills/$name/SKILL.md" 'validate-config.sh" --base'
  need "skills/$name/SKILL.md" 'validate-config.ps1" -Base'
done
# init keeps writing and validating the working tree's file
[ -f "$root/skills/init/SKILL.md" ] && { need skills/init/SKILL.md '!`cat .claude/nightmill.json'; }

echo "== the scripts read the base configuration"
for f in scripts/lib/baseconfig.sh scripts/lib/baseconfig.ps1; do
  [ -f "$root/$f" ] || fail "$f: missing"
done
need scripts/slot.sh 'lib/baseconfig'
need scripts/slot.ps1 'lib\baseconfig'
lacks scripts/slot.sh '.claude/nightmill.json"'
lacks scripts/slot.ps1 '".claude\nightmill.json"'
need scripts/validate-config.sh '--base'
need scripts/validate-config.ps1 '-Base'

echo "== a change under .claude/ or .github/ is never auto-merged"
wf=skills/workflow/SKILL.md
need $wf '--no-renames'
need $wf '.claude/'
need $wf '.github/'
need $wf 'Auto-merge is not enabled: it changes'
need $wf ', under .claude/ or .github/, which is never auto-merged.'
need $wf 'Auto-merge is not enabled: the changed paths could not be listed ('
need $wf 'the fix of round'
need $wf ', under .claude/ or .github/, which is never auto-merged'
for name in spec next fix; do
  need "skills/$name/SKILL.md" 'which is never auto-merged'
done

echo "== the README"
need README.md 'git remote set-head origin --auto'
need README.md 'contains `--auto` and never `--admin`'
need README.md 'A change under `.claude/` or `.github/` is not auto-merged'
need README.md 'The guard hook and the other scripts (status, room, control, models, the dashboard and the pane) read the config from the base branch'
need README.md 'merge flags (with `--auto`, never `--admin`)'

if [ "$bad" -ne 0 ]; then exit 1; fi
echo "OK"
