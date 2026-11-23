#!/usr/bin/env bash
# tests/test-slot-killed-take.sh - bug #373: tests/smoke-slot.sh failed in Git Bash on Windows, in the section
# "interruption (iteration 36)": "FAIL: interruption 4: the marker changed:", the marker being the claim of slot 1,
# "state": "taking", "branch": "feat/i5". Case 4 kills a take with KILL and expects the claim it left to hold the
# take's process id. The claim holds the Windows id of the take (slot.sh my_pid, /proc/<pid>/winpid), and the case
# asks for that id (bg_winpid) after the take has been killed and reaped, when /proc/<pid>/winpid is gone and
# bg_winpid answers the shell's own pid instead: not the pid in the marker.
# This file runs the real case 4 (intr_case4) of tests/smoke-slot.sh, with the helpers it calls (read from that file
# by name, so a change there is run here) against the real scripts/slot.sh in a throwaway repository, without the
# twelve minutes of the sections before it. Where there is no /proc/<pid>/winpid (Linux, macOS) the two ids are the
# same and the case passes, as it did before. tests/lint.sh calls this file.
#   tests/test-slot-killed-take.sh [<root>]   # root: the checkout to read (default: this one)
set -euo pipefail
here=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-killedtake.XXXXXX")
S="$here/scripts/slot.sh"
smoke="$here/tests/smoke-slot.sh"
i_pids=(); bg_pids=(); i_p=""; i_gate=""; i_rc=0; i_last=""
# fail: no process of the takes is left, the gates are open, the throwaway directory goes
fail() {
  local p
  for p in ${i_pids[@]+"${i_pids[@]}"}; do kill -KILL -- "-$p" 2>/dev/null || true; done
  : > "$tmp/go"; : > "$tmp/claim-go"
  echo "FAIL: $*" >&2
  exit 1
}
trap 'p=""; for p in ${i_pids[@]+"${i_pids[@]}"}; do kill -KILL -- "-$p" 2>/dev/null || true; done; rm -rf "$tmp"' EXIT

# grab <name>: the definition of a function of tests/smoke-slot.sh, from its first line to its closing brace
grab() {
  awk -v n="$1" '
    !on && index($0, n "() {") == 1 {
      on = 1; print
      if ($0 ~ /\}[[:space:]]*(#.*)?$/) exit
      next
    }
    on { print }
    on && /^}/ { exit }' "$smoke"
}
[ -f "$smoke" ] || fail "tests/smoke-slot.sh is missing"
helpers=""
for f in intr_case4 i_pidgate i_start i_poll i_sign_gatepid i_sign i_end i_gone waitfor bg_alive bg_winpid c_porc9 \
  taking_text c_same rep mget c_ref; do
  def=$(grab "$f")
  [ -n "$def" ] || fail "tests/smoke-slot.sh no longer defines $f, which the case of a killed take needs"
  helpers="$helpers$def"$'\n'
done
# the definitions are run as they stand in the smoke test
eval "$helpers"
# shellcheck source=../scripts/lib/json.sh
. "$here/scripts/lib/json.sh"

# the throwaway repository, as the smoke test makes it: origin, a main checkout with the config committed on the base
# branch, a fake gh that finds nothing to reap
mkdir -p "$tmp/bin"
printf '%s\n' '#!/bin/sh' 'echo "[]"' > "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config core.autocrlf false
CFG="$tmp/work/.claude/nightmill.json"
S1="$tmp/wt/.slots"
marker() { echo "$tmp/wt/.slots/slot-$1.json"; }
gate_cmd="i=0; while [ ! -e '$tmp/go' ]; do i=\$((i+1)); [ \$i -lt 1200 ] || exit 9; sleep 0.1; done"
mkdir -p .claude
write_cfg() { # write_cfg <worktrees.warmup as JSON>: the test config with that warm-up, committed and pushed to origin main
  cat > "$CFG" <<EOF
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "warmup": $1
  }
}
EOF
  git -C "$tmp/work" add .claude/nightmill.json
  git -C "$tmp/work" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "config"
  git -C "$tmp/work" push -q origin main
}
git remote add origin "$tmp/origin.git"
write_cfg '[]'
git remote set-head origin main
# slot 1 exists and is detached at origin/main, as in the smoke test when the interruption section starts
bash "$S" --take feat/init --slot 1 --skip-warmup >/dev/null 2>&1 || fail "the setup take failed"
bash "$S" --abandon 1 >/dev/null 2>&1 || fail "the setup --abandon failed"
git -C "$tmp/wt/slot-1" switch -q --detach origin/main
git -C "$tmp/work" branch -q -D feat/init
i_clean() { # a clean start for the case: slot 1 free and detached, no pid files, the branches gone
  local b
  rm -f "$tmp/gate.pid" "$tmp/go" "$tmp/claim-go" "$(marker 1)" "$S1"/slot-1.claim.*.tmp "$S1"/slot-1.left.*.tmp "$S1/slot-1.take.tmp"
  git -C "$tmp/wt/slot-1" switch -q -f --detach origin/main
  i_pids=(); bg_pids=(); i_gate=""
  for b in "$@"; do git -C "$tmp/work" branch -q -D "$b" 2>/dev/null || true; done
}

echo "== a take killed in its warm-up leaves the claim with the process id the take recorded (bug #373)"
intr_case4
: > "$tmp/go"
echo "KILLED TAKE OK"
