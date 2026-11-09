#!/usr/bin/env bash
# tests/test-interrupt-docs.sh - the README and the header comment of both slot scripts describe what an interruption
# of a take does (iteration 36, #190): the paragraph after "Retries (iteration 35)" in scripts/slot.sh and
# scripts/slot.ps1, and the sentences in the README's "Why slots".
#   tests/test-interrupt-docs.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*" >&2; bad=1; }
# has <file> <text>: the file holds the text (a fixed string, joined lines)
has() {
  local flat
  flat=$(tr '\n' ' ' < "$1" | sed 's/ # / /g')
  case "$flat" in *"$2"*) return 0 ;; *) return 1 ;; esac
}
# header <file>: the comment lines before the first line that is not a comment
header() { sed -n '1,/^[^#]/p' "$1" | sed '$d'; }

tmp=$(mktemp "${TMPDIR:-/tmp}/nightmill-intrdocs.XXXXXX")
trap 'rm -f "$tmp"' EXIT

header "$root/scripts/slot.sh" > "$tmp"
for t in 'Interruption (iteration 36): a take stopped by INT (Ctrl+C) or TERM after it has claimed its slot runs the same' \
  'prints "<step> interrupted (INT)" or "(TERM)" with the outcome and exits 130 or 143.' \
  'it leaves its claim without the process id; --abandon frees it.' \
  'second signal does not stop a restore.' \
  'A signal sent with kill to the take alone waits for the running command.' \
  '(KILL, a closed window) leaves a claim that is dead once its process has' \
  'Same behaviour as slot.ps1, which prints "<step> stopped" and cannot set the exit code.'; do
  has "$tmp" "$t" || fail "scripts/slot.sh: the header does not say: $t"
done
grep -n '^# Retries (iteration 35)' "$tmp" > /dev/null || fail "scripts/slot.sh: no Retries paragraph in the header"
r=$(grep -n '^# Retries (iteration 35)' "$tmp" | cut -d: -f1 || true)
i=$(grep -n '^# Interruption (iteration 36)' "$tmp" | cut -d: -f1 || true)
r2=$(grep -n '^# Record (iteration 41)' "$tmp" | cut -d: -f1 || true)
{ [ -n "$r" ] && [ -n "$i" ] && [ -n "$r2" ] && [ "$r" -lt "$i" ] && [ "$i" -lt "$r2" ]; } ||
  fail "scripts/slot.sh: the Interruption paragraph is not directly after the Retries paragraph"

header "$root/scripts/slot.ps1" > "$tmp"
for t in 'Interruption (iteration 36): a take stopped by Ctrl+C after it has claimed its slot runs, in a finally block, the' \
  'same restore as a failed step, prints "<step> stopped" with the outcome.' \
  'it leaves its claim without the process id; -Abandon frees it.' \
  '(Stop-Process, a closed console) leaves a claim that is dead once its' \
  'Same behaviour as slot.sh, which names the signal and exits 130 or 143.'; do
  has "$tmp" "$t" || fail "scripts/slot.ps1: the header does not say: $t"
done
if has "$tmp" 'A signal sent with kill'; then fail "scripts/slot.ps1: the header keeps the sentence on kill"; fi

for t in 'A take that is interrupted after it has claimed its slot (Ctrl+C, or a TERM signal in bash) puts the slot back and frees it as a failed take does' \
  '"warm-up 1 interrupted (INT); slot 1 is free again" (bash, exit 130, or 143 for TERM)' \
  '"warm-up 1 stopped; slot 1 is free again" (PowerShell, which cannot tell why it was stopped and keeps its own exit code)' \
  'Interrupted while it writes its finished marker, it leaves the claim, and -Abandon N (--abandon N) frees it.' \
  'A take that is killed without a chance to clean up (Stop-Process, kill -KILL, a closed window) leaves a claim that slot -Status shows as ended; -Abandon N frees it.'; do
  has "$root/README.md" "$t" || fail "README.md does not say: $t"
done

[ "$bad" = 0 ] || exit 1
echo "interruption docs OK"
