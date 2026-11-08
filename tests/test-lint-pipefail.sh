#!/usr/bin/env bash
# Regression test for #220: under `set -o pipefail`, `<producer> | grep -q ...`
# fails at random. grep -q exits at its first match, the producer gets SIGPIPE
# (141) and pipefail turns that into a failed pipeline, so a check reports text
# as missing although it is there. The race depends on timing, so this test is
# deterministic: (1) it shows the mechanism with a large producer, and (2) it
# requires that no script under tests/ and scripts/ that sets pipefail pipes
# into grep -q (or --quiet / --silent).
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

# 1. The mechanism, as in the report: a producer that keeps writing after the match.
rc=$(bash -c 'set -o pipefail; { echo "needle"; yes | head -c 200000; } | grep -q needle; echo $?')
if [ "$rc" = "0" ]; then
  echo "NOTE: the mechanism did not show on this machine this time (timing)"
fi

# 2. No pipe into grep -q in a script that sets pipefail.
pat='\|[[:space:]]*grep([[:space:]]+-[-A-Za-z]*)*[[:space:]]+(-[A-Za-z]*q[A-Za-z]*|--quiet|--silent)([[:space:]]|$)'
self="tests/test-lint-pipefail.sh"
for f in tests/*.sh scripts/*.sh scripts/lib/*.sh; do
  [ -f "$f" ] || continue
  [ "$f" = "$self" ] && continue
  grep -Eq '^[[:space:]]*set[[:space:]]+-[A-Za-z]*o[[:space:]]+pipefail|^[[:space:]]*set[[:space:]]+-o[[:space:]]+pipefail' "$f" || continue
  hits=$(grep -nE -- "$pat" "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' || true)
  if [ -n "$hits" ]; then
    n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    echo "FAIL: $f sets pipefail and pipes into grep -q on $n line(s); the producer can get SIGPIPE (first: $(printf '%s\n' "$hits" | head -1 | cut -c1-100))"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "OK: no pipe into grep -q under pipefail"
