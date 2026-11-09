#!/usr/bin/env bash
# tests/test-skill-config-fallback.sh - regression for #127: the config injection of spec, next, fix, story and check
# must fall back to the "run /nightmill:init" hint when there is no config, and each skill must declare allowed-tools
# that cover its own injection command. A skill is text plus an injection the harness runs, so the test runs the
# injection command itself.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-skillcfg.XXXXXX")
trap 'rm -rf "$work"' EXIT
errors=0
bad() { echo "FAIL: $*" >&2; errors=$((errors + 1)); }

# split_parts <command>: print the parts of a compound command, one per line, split at && || ; | |& & and newlines
# outside quotes; an & that belongs to a redirection (2>&1, &>) stays with its part.
split_parts() {
  local str=$1 i ch prev="" next quote="" cur=""
  for ((i = 0; i < ${#str}; i++)); do
    ch=${str:i:1}
    next=${str:i+1:1}
    if [ -n "${quote}" ]; then
      cur+=$ch
      [ "$ch" = "$quote" ] && quote=""
    elif [ "$ch" = '"' ] || [ "$ch" = "'" ]; then
      quote=$ch
      cur+=$ch
    elif [ "$ch" = "&" ] && { [ "$prev" = ">" ] || [ "$prev" = "<" ] || [ "$next" = ">" ]; }; then
      cur+=$ch
    elif [ "$ch" = "&" ] || [ "$ch" = "|" ] || [ "$ch" = ";" ] || [ "$ch" = $'\n' ]; then
      printf '%s\n' "$cur"
      cur=""
      # the second char of && || |& is part of the operator
      if [ "$ch" != ";" ] && [ "$ch" != $'\n' ] && { [ "$next" = "&" ] || { [ "$ch" = "|" ] && [ "$next" = "|" ]; }; }; then
        i=$((i + 1))
        ch=$next
      fi
    else
      cur+=$ch
    fi
    prev=$ch
  done
  printf '%s\n' "$cur"
}

mkdir -p "$work/empty" "$work/withcfg/.claude"
printf '{"marker":"cfg-present-7431"}\n' > "$work/withcfg/.claude/nightmill.json"

for name in spec next fix story check; do
  skill="$here/skills/$name/SKILL.md"
  echo "== /$name config injection"
  if [ ! -f "$skill" ]; then bad "$name: skills/$name/SKILL.md missing"; continue; fi
  line=$(grep -m1 '^!`.*nightmill\.json' "$skill" || true)
  if [ -z "$line" ]; then bad "$name: no config injection line"; continue; fi
  cmd=${line#'!`'}
  cmd=${cmd%'`'}

  # no config: exit 0 and the hint naming /nightmill:init
  out=$(cd "$work/empty" && bash -c "$cmd" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || bad "$name: without a config the injection exits $rc, not 0 (output: $out)"
  case "$out" in
    *"/nightmill:init"*) ;;
    *) bad "$name: without a config the injection does not print the /nightmill:init hint (output: $out)" ;;
  esac

  # with a config: the config is printed
  out=$(cd "$work/withcfg" && bash -c "$cmd" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || bad "$name: with a config the injection exits $rc"
  case "$out" in
    *cfg-present-7431*) ;;
    *) bad "$name: with a config the injection does not print the config" ;;
  esac

  # allowed-tools covers the injection command
  allowed=$(awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} /^allowed-tools:/{print}' "$skill")
  if [ -z "$allowed" ]; then bad "$name: no allowed-tools in the frontmatter"; continue; fi
  rules=()
  while IFS= read -r rule; do
    rules+=("$rule")
  done < <(printf '%s\n' "${allowed#allowed-tools:}" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep '^Bash(' || true)
  # Claude Code splits a compound command at && || ; | |& & and newlines; every part needs its own rule
  uncovered=""
  while IFS= read -r part; do
    part=${part#"${part%%[![:space:]]*}"}
    part=${part%"${part##*[![:space:]]}"}
    [ -n "${part}" ] || continue
    covered=0
    for rule in "${rules[@]+"${rules[@]}"}"; do
      pat=${rule#Bash(}
      pat=${pat%)}
      base=${pat% \*}
      # shellcheck disable=SC2254
      case "$part" in
        $pat) covered=1 ;;
        "$base") covered=1 ;;
      esac
    done
    [ "$covered" -eq 1 ] || uncovered="${uncovered}[${part}] "
  done < <(split_parts "$cmd")
  [ -z "$uncovered" ] || bad "$name: allowed-tools has no rule for part(s) of the injection command: $uncovered"
done

if [ "$errors" -ne 0 ]; then echo "$errors failure(s)" >&2; exit 1; fi
echo "OK"
