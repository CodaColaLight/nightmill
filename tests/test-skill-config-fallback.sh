#!/usr/bin/env bash
# tests/test-skill-config-fallback.sh - regression for #127, #111 and #241: the config injection of workflow, spec, next, fix,
# story and check reads the configuration from the base branch (origin/HEAD) and must fall back to the "run /nightmill:init" hint when there is no config, and each skill (init too, for this part only) must declare allowed-tools
# that cover its own injection command. A skill is text plus an injection the harness runs, so the test runs the
# injection command itself, with the argument conversion of Git Bash on Windows made visible in every shell and not
# switched off by the caller (bug 302).
set -uo pipefail
unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL  # the default of Git Bash, where bug 302 is; a caller that set them hides it
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

mkdir -p "$work/empty"
# mkrepo <dir> <set-head: yes|no>: a repository with a bare origin; origin/main has a config with the marker
# base-marker-5520, the working tree's file the marker tree-marker-9913 (not committed)
mkrepo() {
  local d=$1
  mkdir -p "$d/.claude"
  git init -q --bare "$d.origin.git"
  git init -q -b main "$d"
  printf '{"marker":"base-marker-5520"}\n' > "$d/.claude/nightmill.json"
  git -C "$d" add -A
  git -C "$d" -c user.name=t -c user.email=t@example.invalid commit -qm base
  git -C "$d" remote add origin "$d.origin.git"
  git -C "$d" push -q origin main
  if [ "$2" = yes ]; then git -C "$d" remote set-head origin main; fi
  printf '{"marker":"tree-marker-9913"}\n' > "$d/.claude/nightmill.json"
}
mkrepo "$work/withhead" yes
mkrepo "$work/nohead" no

# Bug 302: in Git Bash on Windows an argument of the form <ref>:<path> is taken for a list of paths and rewritten before
# git.exe starts, so "git show origin/HEAD:.claude/nightmill.json" exits 128 unless the conversion is off for that call.
# The injection must work without the caller having switched the conversion off (a session with MSYS_NO_PATHCONV=1 for
# everything breaks scripts/slot.sh, see #300), so the variables are unset at the top, and a git shim first on the PATH makes
# the bug visible in every shell: it exits 128 for an argument of the form <ref>:<path> (a prefix of more than one
# character, a colon, a path; the value of -C is not one) unless MSYS_NO_PATHCONV is set or MSYS2_ARG_CONV_EXCL holds
# *, as Git Bash itself does; any other call goes to the real git. The injected line is run as written in the skill.
real_git=$(command -v git)
mkdir "$work/shim"
cat > "$work/shim/git" <<SHIM
#!/usr/bin/env bash
if [ -z "\${MSYS_NO_PATHCONV:-}" ]; then
  case "\${MSYS2_ARG_CONV_EXCL:-}" in
    *'*'*) ;;
    *)
      skip=""
      for a in "\$@"; do
        if [ -n "\$skip" ]; then skip=""; continue; fi
        if [ "\$a" = -C ]; then skip=1; continue; fi
        if [[ "\$a" =~ ^[A-Za-z0-9_./-]{2,}:[^:]+\$ ]]; then
          echo "fatal: path '\$a' does not exist (argument converted by the shell)" >&2
          exit 128
        fi
      done ;;
  esac
fi
exec "$real_git" "\$@"
SHIM
chmod +x "$work/shim/git"
export PATH="$work/shim:$PATH"
# the shim itself: it refuses the shape with the conversion on and lets it through with the conversion off
rc=0; (cd "$work/withhead" && git show origin/HEAD:.claude/nightmill.json >/dev/null 2>&1) || rc=$?
[ "$rc" -eq 128 ] || bad "the git shim does not refuse origin/HEAD:.claude/nightmill.json (exit $rc)"
rc=0; (cd "$work/withhead" && MSYS_NO_PATHCONV=1 git show origin/HEAD:.claude/nightmill.json >/dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || bad "the git shim refuses the shape with the conversion off (exit $rc)"

# check_allowed_tools <name> <skill file> <injection command>: allowed-tools covers the injection command
check_allowed_tools() {
  local name=$1 skill=$2 cmd=$3 allowed rules rule part covered uncovered pat base
  allowed=$(awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} /^allowed-tools:/{print}' "$skill")
  if [ -z "$allowed" ]; then bad "$name: no allowed-tools in the frontmatter"; return 0; fi
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
}

for name in workflow spec next fix story check; do
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

  # a repository whose origin/HEAD has a config: the first line names the base ref, the base config is printed, the
  # working tree's config is not
  out=$(cd "$work/withhead" && bash -c "$cmd" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || bad "$name: with origin/HEAD the injection exits $rc"
  [ "$(printf '%s\n' "$out" | head -n 1)" = "origin/main" ] || bad "$name: the first line is not origin/main (output: $out)"
  case "$out" in
    *base-marker-5520*) ;;
    *) bad "$name: the base config is not printed (output: $out)" ;;
  esac
  case "$out" in
    *tree-marker-9913*) bad "$name: the working tree's config is printed (output: $out)" ;;
  esac

  # a repository with origin/main but no origin/HEAD: the output says so
  out=$(cd "$work/nohead" && bash -c "$cmd" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || bad "$name: without origin/HEAD the injection exits $rc"
  case "$out" in
    *"NO origin/HEAD, but"*) ;;
    *) bad "$name: without origin/HEAD the output lacks 'NO origin/HEAD, but' (output: $out)" ;;
  esac
  case "$out" in
    *base-marker-5520*) bad "$name: without origin/HEAD a config is printed as the base (output: $out)" ;;
  esac

  check_allowed_tools "$name" "$skill" "$cmd"
done

# init has no base-branch injection (it reads the working tree's file), so only its allowed-tools are checked
echo "== /init config injection"
skill="$here/skills/init/SKILL.md"
line=$(grep -m1 '^!`.*nightmill\.json' "$skill" || true)
if [ -z "$line" ]; then
  bad "init: no config injection line"
else
  cmd=${line#'!`'}
  cmd=${cmd%'`'}
  check_allowed_tools init "$skill" "$cmd"
fi

if [ "$errors" -ne 0 ]; then echo "$errors failure(s)" >&2; exit 1; fi
echo "OK"
