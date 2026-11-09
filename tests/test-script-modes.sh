#!/usr/bin/env bash
# Regression test for #114: skills call scripts directly but they are committed
# non-executable. (a) every scripts/*.sh with a shebang is 100755 in the git
# index; (b) no skill or agent runs a plugin script without `bash "` or
# `powershell -NoProfile -ExecutionPolicy Bypass -File "` in front of it.
set -u
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0

# (a) modes in the index, not on the file system
while IFS= read -r line; do
  mode=${line%% *}
  f=${line#*$'\t'}
  case "$f" in scripts/*.sh) ;; *) continue ;; esac
  case "$f" in scripts/*/*) continue ;; esac
  first=$(git show ":$f" 2>/dev/null | head -n 1)
  case "$first" in
    '#!'*)
      if [ "$mode" != "100755" ]; then
        echo "FAIL: $f has a shebang but is committed $mode, expected 100755"
        fail=1
      fi
      ;;
  esac
done < <(git ls-files -s scripts)

# (b) every quoted call of a plugin script has an interpreter in front
for f in skills/*/SKILL.md agents/*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    n=${hit%%:*}
    rest=${hit#*:}
    pre=${rest%%\"\$\{CLAUDE_PLUGIN_ROOT\}*}
    case "$pre" in
      *'bash '|*'-NoProfile -ExecutionPolicy Bypass -File ') ;;
      *)
        echo "FAIL: $f:$n runs a plugin script without bash \" or powershell -NoProfile -ExecutionPolicy Bypass -File \" in front"
        fail=1
        ;;
    esac
  done < <(grep -noE '.{0,60}"\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[^"]*\.(sh|ps1)"' "$f" || true)
done

if [ "$fail" -eq 0 ]; then echo "OK: script modes and skill calls"; fi
exit "$fail"
