#!/usr/bin/env bash
# Tests for #110 (iteration 47): the deny rules /init writes and the PreToolUse guard hook. The static checks of the
# spec's lint section "the guard and the deny rules", kept in a file of their own: the hook wiring, the guard scripts'
# refusal lines, the Deny rules bullet of skills/init/SKILL.md, the rules' fixed prefixes, the collision of the rules
# with the commands the skills write, the workflow skill's sentences and the README. Text is joined before it is searched.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fail=0

flat() { tr '\n' ' ' < "$1" | sed -E 's/ +/ /g'; }
bad() { echo "FAIL: $*"; fail=1; }

# need <file> <text>...: each text must be in the joined file
need() {
  local f=$1 text flatf; shift
  if [ ! -f "$f" ]; then bad "$f does not exist"; return; fi
  flatf=$(flat "$f")
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) ;;
      *) bad "$f lacks: ${text}" ;;
    esac
  done
}

I=skills/init/SKILL.md
W=skills/workflow/SKILL.md
H=hooks/hooks.json

echo "== the hook is wired"
need "$H" '"PreToolUse"' '"matcher": "Bash|PowerShell"' 'bash \"${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh\"'
if grep -F 'scripts/guard.sh' "$H" | grep -F 'exit 0' >/dev/null; then bad "$H: the guard command ends in exit 0, which hides exit code 2"; fi
need "$H" '"SessionStart"' 'session-start.sh' './panel.tsx'

echo "== the guard scripts"
for s in scripts/guard.sh scripts/guard.ps1; do
  need "$s" \
    'nightmill guard: refused: a merge without --auto.' \
    'nightmill guard: refused: gh pr merge with --admin.' \
    'nightmill guard: refused: a merge through gh api.' \
    'nightmill guard: refused: a force push.' \
    'nightmill guard: refused: a push to ' \
    'nightmill guard: refused: setting ' \
    'nightmill guard: refused: a status edit, because the ' \
    'field-list'
done

echo "== init: the Deny rules bullet"
RULES=(
  'Bash(gh pr merge *--admin*)'
  'Bash(gh issue delete *)'
  'Bash(gh project delete *)'
  'Bash(gh repo delete *)'
  'Bash(gh api *-X DELETE*)'
  'Bash(gh api *-XDELETE*)'
  'Bash(gh api *--method DELETE*)'
  'Bash(gh api *--method=DELETE*)'
  'Bash(git push --force*)'
  'Bash(git push * --force*)'
  'Bash(git push -f*)'
  'Bash(git push * -f*)'
  'Bash(git push * +*)'
  'Bash(git push * <B>)'
  'Bash(git push * <B> *)'
  'Bash(git push *:<B>)'
  'Bash(git push *:<B> *)'
  'Bash(git push *:refs/heads/<B>*)'
)
bullet=""
if [ -f "$I" ]; then
  bullet=$(awk '/^- \*\*Deny rules\*\*/ {on=1; print; next} on && /^(- |#)/ {exit} on {print}' "$I" | tr '\n' ' ' | sed -E 's/ +/ /g')
fi
if [ -z "$bullet" ]; then
  bad "$I has no '- **Deny rules**' bullet"
else
  for t in 'permissions.deny' '.claude/settings.json' 'without removing or reordering an entry' \
    "Deny rules: declined (the forbidden actions are refused only by the plugin's guard hook and the skills' text)"; do
    case "$bullet" in *"$t"*) ;; *) bad "$I: the Deny rules bullet lacks: $t" ;; esac
  done
  for r in "${RULES[@]}"; do
    case "$bullet" in *"$r"*) ;; *) bad "$I: the Deny rules bullet lacks the rule $r" ;; esac
  done
  case "$bullet" in *'Bash(git -C'*) bad "$I: the Deny rules bullet holds a rule with git -C" ;; esac
fi
for h in '## 4. Confirm once' '## 5. Apply'; do
  sec=$(awk -v h="$h" 'index($0, h) == 1 {on=1; next} on && /^## / {exit} on {print}' "$I" 2>/dev/null | tr '\n' ' ')
  case "$sec" in *[Dd]eny\ rules*) ;; *) bad "$I: step '$h' does not name the deny rules" ;; esac
done

echo "== the rules have a fixed prefix"
for r in "${RULES[@]}"; do
  body=${r#Bash(}
  ok=0
  for p in 'gh pr merge ' 'gh issue delete ' 'gh project delete ' 'gh repo delete ' 'gh api ' 'git push '; do
    case "$body" in "$p"*) ok=1 ;; esac
  done
  [ "$ok" = 1 ] || bad "tests/test-guard-rules.sh: the deny rule $r has no fixed prefix"
done

echo "== no rule matches a command the skills write"
# split_cmds: one span per line on stdin; prints its subcommands at && || ; | outside quotes
split_cmds() {
  awk '{
    s = $0; n = length(s); cur = ""; q = ""
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); d = substr(s, i + 1, 1)
      if (q != "") { cur = cur c; if (c == q) q = ""; continue }
      if (c == "\"" || c == "\047") { q = c; cur = cur c; continue }
      if ((c == "&" && d == "&") || (c == "|" && d == "|")) { print cur; cur = ""; i++; continue }
      if (c == ";" || c == "|") { print cur; cur = ""; continue }
      cur = cur c
    }
    print cur
  }'
}
FREE='x push main -f +x --force :main :refs/heads/main --admin -X DELETE --method DELETE x'
# fill <branch>: the placeholders of one command line on stdin
fill() {
  sed -E \
    -e 's#<(slot path|slot|absolute slot path)>#/w/slot-1#g' \
    -e "s#<git\\.[A-Za-z]*Prefix><N>-<slug>#$1#g" \
    -e "s#<branch>#$1#g" \
    -e 's#<git\.mergeFlags>#--auto --squash#g' \
    -e 's#<git\.baseBranch>#main#g' \
    -e 's#<(pr|n|N|issue|k|job)>#5#g' \
    -e 's#<owner>#o#g; s#<repo>#r#g; s#<login>#u#g' \
    -e 's#<[A-Za-z. ]*id>#I_1#g' \
    -e "s#<[^>]*>#$FREE#g"
}
matches() { # matches <command> <rule body without Bash( and ) >
  local pat=$2
  # shellcheck disable=SC2053
  [[ "$1" == $pat ]]
}
# the rules in force: the bullet's own, with main for <B>
live=()
if [ -n "$bullet" ]; then
  while IFS= read -r r; do live+=("${r//<B>/main}"); done < <(printf '%s\n' "$bullet" | grep -o 'Bash([^)]*)')
fi
[ "${#live[@]}" = 18 ] || bad "$I: the Deny rules bullet holds ${#live[@]} Bash(...) rules, not 18"
unbody() { local x=${1#Bash(}; printf '%s' "${x%)}"; }
# the matcher's own check
matches 'git push --force origin x' "$(unbody 'Bash(git push --force*)')" || bad "tests/test-guard-rules.sh: the deny-rule matcher is wrong"
if matches 'git -C /w/slot-1 stash push -m "x push main -f"' "$(unbody 'Bash(git push * main)')"; then
  bad "tests/test-guard-rules.sh: the deny-rule matcher is wrong"
fi
spans=$(for f in skills/*/SKILL.md agents/*.md; do
  grep -o '`[^`]*`' "$f" | sed -E 's/^`//; s/`$//' | grep -E '^(git|gh) ' | sed "s#^#$f	#"
done)
if [ "${#live[@]}" -gt 0 ]; then
  for br in spec/47-x feat/47-x fix/12-x; do
    while IFS=$'\t' read -r file span; do
      [ -n "$span" ] || continue
      while IFS= read -r sub; do
        sub=$(printf '%s' "$sub" | sed -E 's/^ +//; s/ +$//')
        [ -n "$sub" ] || continue
        for r in "${live[@]}"; do
          if matches "$sub" "$(unbody "$r")"; then bad "$file: $sub matches the deny rule $r"; fi
        done
      done < <(printf '%s\n' "$span" | fill "$br" | split_cmds)
    done <<< "$spans"
  done
fi

echo "== the workflow skill"
need "$W" 'A refused command is final' 'deny rules refuse a merge with `--admin`'
for f in skills/*/SKILL.md; do
  case "$(flat "$f")" in *'gh pr merge --admin'*) bad "$f holds the joined text gh pr merge --admin" ;; esac
done

echo "== the README"
need README.md '### The deny rules and the guard' 'permissions.deny' 'scripts/guard.sh' 'Git Bash' '0002'
case "$(flat README.md)" in *'base branch still prompts'*) bad "README.md still says: base branch still prompts" ;; esac

[ "$fail" = 0 ] && echo "GUARD RULES OK"
exit "$fail"
