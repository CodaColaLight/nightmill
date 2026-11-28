#!/usr/bin/env bash
# tests/test-security-model.sh - the README's "Security model" (iteration 39, #159) names the rules, keys, scopes and
# files it is about, links the issues it cites in one form, and SECURITY.md links to it. Only the contracts are checked
# (a permission rule, a key, a flag, a token scope, a file name, a link); the sentences, the headings and their order are
# the manual check's (iteration 73).
#   tests/test-security-model.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }
readme="$root/README.md"
secmd="$root/SECURITY.md"
[ -f "$readme" ] || { echo "FAIL: README.md missing" >&2; exit 1; }

# contains <flat text> <needle>
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
flat=$(tr '\n' ' ' < "$readme" | sed -E 's/ +/ /g')

repo=$(grep -oE '/plugin marketplace add [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$readme" | head -1 | sed 's|.* ||')
[ -n "$repo" ] || fail "README.md: no /plugin marketplace add line"

# 1. the allow rules of /init's Permissions bullet appear in backticks in the README
bullet=$(awk '/^- \*\*Permissions\*\*:/ { s = 1; print; next } s && /^- \*\*/ { exit } s { print }' "$root/skills/init/SKILL.md" | tr '\n' ' ' | sed -E 's/ +/ /g')
rules=$(printf '%s' "$bullet" | grep -oE '`Bash\([^`]*\)`' | grep -v '<' || true)
[ -n "$rules" ] || fail "skills/init/SKILL.md: no Bash(...) rule found in the Permissions bullet"
while IFS= read -r r; do
  [ -n "$r" ] || continue
  contains "$flat" "$r" || fail "README.md does not list $r"
done <<EOF2
$rules
EOF2
contains "$flat" '`Edit(**)`' || fail "README.md does not list \`Edit(**)\`"
contains "$flat" '`Bash(<' || fail "README.md does not list the check's rule \`Bash(<...>)\`"

# 2. the links to the permission subsections, the keys, flags and files the model is about
for a in '(#the-run-permissions)' '(#the-edit-permission)' '(#the-deny-rules-and-the-guard)' 'permissions.deny' 'scripts/guard.sh' \
  '--admin' '--auto' 'bypassPermissions' 'worktrees.warmup'; do
  contains "$flat" "$a" || fail "README.md does not contain $a"
done

# 3. the token scopes and the command that removes one
for w in '`repo`' '`read:org`' '`gist`' '`project`' '`workflow`' '--remove-scopes workflow'; do
  contains "$flat" "$w" || fail "README.md does not contain $w"
done

# 4. every issue link has the same number twice and the right URL
links=$(printf '%s' "$flat" | grep -oE '\[#[0-9]+\]\([^)]*\)' || true)
while IFS= read -r l; do
  [ -n "$l" ] || continue
  a=${l#\[#}; a=${a%%\]*}
  want="[#$a](https://github.com/$repo/issues/$a)"
  [ "$l" = "$want" ] || fail "README.md: link $l should be $want"
done <<EOF4
$links
EOF4
# 5. the issues the security model cites are linked
for n in 108 110 111 127 134 142 154 160 162 164 165 169 176 177 178 213 253 254; do
  contains "$flat" "[#$n](https://github.com/$repo/issues/$n)" || fail "README.md does not link #$n"
done

# 6. SECURITY.md links to the section
if [ -f "$secmd" ]; then
  grep -qF 'README.md#security-model' "$secmd" || fail "SECURITY.md does not contain README.md#security-model"
else
  fail "SECURITY.md missing"
fi

[ "$bad" = 0 ] && echo "ok: the security model is documented"
exit "$bad"
