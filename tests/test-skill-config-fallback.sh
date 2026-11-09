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
  covered=0
  while IFS= read -r rule; do
    pat=${rule#Bash(}
    pat=${pat%)}
    base=${pat% \*}
    # shellcheck disable=SC2254
    case "$cmd" in
      $pat) covered=1 ;;
      "$base") covered=1 ;;
    esac
  done < <(printf '%s\n' "${allowed#allowed-tools:}" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep '^Bash(' || true)
  [ "$covered" -eq 1 ] || bad "$name: allowed-tools does not cover the injection command: $cmd"
done

if [ "$errors" -ne 0 ]; then echo "$errors failure(s)" >&2; exit 1; fi
echo "OK"
