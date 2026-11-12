#!/usr/bin/env bash
# tests/test-restricted-path-git.sh - bug 303: tests/smoke-history.sh fails in Git Bash on Windows at its case "no gh".
# The case runs history.sh with HIST_PATH="/usr/bin:/bin", to have only the system tools on the PATH and no gh. On Linux
# and macOS git lives in /usr/bin; in Git for Windows it does not (/ucrt64/bin/git), so with that PATH history.sh has no
# git either, cannot tell that it is inside a checkout and exits 2 where the case expects 0.
# The restricted PATH is built inside the smoke tests, so this test reads every PATH assignment out of tests/*.sh that
# names a system directory (HIST_PATH=... or PATH=..., a double-quoted value without a plain $variable, which leaves
# out the "$tmp/bin:$PATH" lookups), evaluates the value as the smoke test would (a $(...) in it runs here) and
# checks that, with that value as the PATH, git is found. The case that hides gh must hide only gh.
# Passes everywhere git is in /usr/bin or /bin; fails in Git for Windows until every restricted PATH carries git.
# Needs bash and git, no network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
self=$(basename "${BASH_SOURCE[0]}")

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is not installed: the test cannot say anything"

# the assignments of a PATH to a system directory only: PATH="..." or HIST_PATH="..." with a double-quoted value that
# holds no $name or ${name}, only literal text or $( ... )
found=0
for f in "$here"/tests/*.sh; do
  [ "$(basename "$f")" = "$self" ] && continue
  while IFS= read -r assign; do
    [ -n "$assign" ] || continue
    value=${assign#*=}
    case "$value" in *"/usr/bin"*|*"/bin"*) ;; *) continue ;; esac
    found=$((found + 1))
    resolved=$(eval "printf '%s' $value") || fail "$(basename "$f"): the value $value of [$assign] cannot be evaluated"
    if ! (PATH="$resolved" command -v git >/dev/null 2>&1); then
      fail "$(basename "$f"): [$assign] builds the PATH [$resolved], on which git is not found; the case would run without git (here git is $(command -v git))"
    fi
  done < <(grep -ohE '(HIST_PATH|PATH)="([^"$]|\$\([^)]*\))*"' "$f" || true)
done

[ "$found" -gt 0 ] || fail "no restricted PATH found in tests/*.sh: the pattern of this test no longer matches the smoke tests"

echo "RESTRICTED-PATH-GIT OK ($found restricted PATH assignments checked)"
