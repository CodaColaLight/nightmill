#!/usr/bin/env bash
# tests/test-ci-smoke-bash-timeout.sh - regression test for #264: the `bash scripts smoke tests` job of
# .github/workflows/ci.yml was cancelled at its 7 minute limit (PR #263 ran 435 s, main 377 s) before the suite
# finished. The rule of docs/specs/iteration-38-ci-hardening.md (decision 2): about 3 times the longest run, rounded
# up to whole minutes. Longest known run 435 s -> 1305 s -> 22 minutes. The limit stays a bound on a hung job, so it
# stays far below the 360 default. tests/lint.sh calls this file.
#   tests/test-ci-smoke-bash-timeout.sh [<root>]
set -uo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ci="$root/.github/workflows/ci.yml"
longest=435
min=$(( (3 * longest + 59) / 60 ))
max=60
fail=0

[ -f "$ci" ] || { echo "FAIL: $ci is missing"; exit 1; }

t=$(LC_ALL=C awk '
  /^jobs:[[:space:]]*$/ { inj = 1; next }
  inj && /^[^[:space:]#]/ { inj = 0 }
  inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; next }
  inj && job == "smoke-bash:" && /^    timeout-minutes: [0-9]+$/ { print $2; exit }' "$ci")

if [ -z "$t" ]; then
  echo "FAIL: job smoke-bash has no '    timeout-minutes: <number>' line"; fail=1
else
  if [ "$t" -lt "$min" ]; then
    echo "FAIL: smoke-bash has timeout-minutes: $t; the longest run is ${longest} s and 3 times that needs at least $min"; fail=1
  fi
  if [ "$t" -gt "$max" ]; then
    echo "FAIL: smoke-bash has timeout-minutes: $t; the limit must stay a bound on a hung job (at most $max)"; fail=1
  fi
fi
# the required check keeps its name
if ! grep -qxF '    name: bash scripts smoke tests' "$ci"; then
  echo "FAIL: the job name 'bash scripts smoke tests' (a required check) is missing or renamed"; fail=1
fi

[ "$fail" = 0 ] && echo "ok: smoke-bash timeout-minutes $t" || exit 1
