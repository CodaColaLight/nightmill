#!/usr/bin/env bash
# tests/test-slot-low-defects.sh - bug 322 (split from 140): the low-severity defects of slot.sh and new-worktree.sh.
#   1 --release trusts any merged PR with the head name: it compares headRefOid with the branch tip (as --reap does)
#   2 --release and --abandon refuse a slot whose branch is not the marker's branch
#   3 --status only reads: it does not create the worktree root
#   4 git older than 2.31 gets a message that names the version, not "run from inside a git checkout"
#   5 gh never prompts: GH_PROMPT_DISABLED is set for --reap and --release
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-slotlow.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
S="$here/scripts/slot.sh"
N="$here/scripts/new-worktree.sh"
real_git=$(command -v git)

fail() { echo "FAIL: $*" >&2; exit 1; }

# A fake gh: "pr list" answers from $GH_FIX/merged.txt (branch TAB number TAB head commit), prints only the requested
# --json fields, and logs every call with the value of GH_PROMPT_DISABLED it saw.
mkdir -p "$tmp/bin" "$tmp/fix"
: > "$tmp/fix/merged.txt"; : > "$tmp/gh.log"
cat > "$tmp/bin/gh" <<'EOF2'
#!/usr/bin/env bash
echo "prompt=[${GH_PROMPT_DISABLED:-}] $*" >> "$GH_LOG"
[ "$1 $2" = "pr list" ] || { echo "unexpected gh call: $*" >&2; exit 1; }
state=""; head=""; fields="number"
while [ $# -gt 0 ]; do
  case "$1" in --state) state=$2; shift ;; --head) head=$2; shift ;; --json) fields=$2; shift ;; esac
  shift
done
if [ "$state" != merged ]; then echo "[]"; exit 0; fi
row=$(awk -F'\t' -v h="$head" '$1 == h' "$GH_FIX/merged.txt" | head -1)
if [ -z "$row" ]; then echo "[]"; exit 0; fi
n=$(printf '%s' "$row" | cut -f2); o=$(printf '%s' "$row" | cut -f3)
parts=""
for f in ${fields//,/ }; do
  case "$f" in
    number) parts="$parts\"number\":$n," ;;
    headRefOid) parts="$parts\"headRefOid\":\"$o\"," ;;
    createdAt) parts="$parts\"createdAt\":\"\"," ;;
    mergedAt) parts="$parts\"mergedAt\":\"\"," ;;
    closingIssuesReferences) parts="$parts\"closingIssuesReferences\":[]," ;;
  esac
done
echo "[{${parts%,}}]"
EOF2
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GH_FIX="$tmp/fix" GH_LOG="$tmp/gh.log"
unset GH_PROMPT_DISABLED

# mkrepo <name> <worktree root>: a repository with an origin, the configuration on main and origin/HEAD set
mkrepo() {
  git init -q --bare "$tmp/$1-origin.git"
  git init -q -b main "$tmp/$1"
  ( cd "$tmp/$1"
    git config core.autocrlf false
    mkdir -p .claude
    cat > .claude/nightmill.json <<EOF2
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": { "root": "$2", "slots": 3 }
}
EOF2
    git add -A
    git -c user.name=t -c user.email=t@example.invalid commit -qm init
    git remote add origin "$tmp/$1-origin.git"
    git push -q origin main
    git remote set-head origin main )
}
rep() { set +e; out=$(cd "$tmp/work" && bash "$S" "$@" 2>"$tmp/err.txt"); rc=$?; set -e; err=$(cat "$tmp/err.txt"); }
# work_commit <slot dir> <branch>: a commit on the branch, pushed
work_commit() {
  echo "$2" > "$1/work.txt"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -qm work
  git -C "$1" push -q origin "$2" 2>/dev/null
}

mkrepo work ../wt
wt="$tmp/wt"; slots="$wt/.slots"
bad=0

case_1() {
  echo "== --release does not trust a merged PR whose head commit is not the branch tip"
  rep --take feat/a --slot 1
  [ "$rc" = 0 ] || fail "take feat/a: exit $rc: $err"
  work_commit "$wt/slot-1" feat/a
  printf '%s\t%s\t%s\n' feat/a 9 "0000000000000000000000000000000000000000" > "$tmp/fix/merged.txt"
  rep --release 1
  [ "$rc" != 0 ] || fail "release freed the slot for a merged PR with another head commit: $out"
  [ -f "$slots/slot-1.json" ] || fail "release removed the marker for a merged PR with another head commit"
  printf '%s\t%s\t%s\n' feat/a 9 "$(git -C "$wt/slot-1" rev-parse HEAD)" > "$tmp/fix/merged.txt"
  rep --release 1
  [ "$rc" = 0 ] || fail "release refused a merged PR whose head commit is the branch tip: $err"
  [ ! -f "$slots/slot-1.json" ] || fail "release left the marker of a matching merged PR"
}

case_2() {
  echo "== --release and --abandon refuse a slot on another branch than the marker's"
  rep --take feat/b --slot 1
  [ "$rc" = 0 ] || fail "take feat/b: exit $rc: $err"
  work_commit "$wt/slot-1" feat/b
  printf '%s\t%s\t%s\n' feat/b 10 "$(git -C "$wt/slot-1" rev-parse HEAD)" > "$tmp/fix/merged.txt"
  git -C "$wt/slot-1" switch -q -c feat/other
  rep --release 1
  [ "$rc" != 0 ] || fail "release freed a slot whose branch is not the marker's: $out"
  [ -f "$slots/slot-1.json" ] || fail "release removed the marker of a slot on another branch"
  rep --abandon 1
  [ "$rc" != 0 ] || fail "abandon freed a slot whose branch is not the marker's: $out"
  [ -f "$slots/slot-1.json" ] || fail "abandon removed the marker of a slot on another branch"
  git -C "$wt/slot-1" switch -q feat/b
  git -C "$wt/slot-1" branch -q -D feat/other
  rep --abandon 1
  [ "$rc" = 0 ] || fail "abandon refused a slot on the marker's branch: $err"
}

case_3() {
  echo "== --status does not create the worktree root"
  mkrepo ro ../ro-wt
  set +e; out=$(cd "$tmp/ro" && bash "$S" --status 2>&1); rc=$?; set -e
  [ "$rc" = 0 ] || fail "status: exit $rc: $out"
  [ ! -e "$tmp/ro-wt" ] || fail "--status created the worktree root $tmp/ro-wt"
}

case_4() {
  echo "== git older than 2.31 is named in the message"
  mkdir -p "$tmp/oldgit"
  printf '%s
' '#!/usr/bin/env bash'     'case "$*" in'     '  *--version*) echo "git version 2.30.1"; exit 0 ;;'     '  *--path-format*) echo "fatal: unknown option: --path-format=absolute" >&2; exit 129 ;;'     'esac'     "exec \"$real_git\" \"\$@\"" > "$tmp/oldgit/git"
  chmod +x "$tmp/oldgit/git"
  for script in "$S --status" "$N feat/x"; do
    # shellcheck disable=SC2086
    set +e; err=$(cd "$tmp/work" && PATH="$tmp/oldgit:$PATH" bash $script 2>&1 >/dev/null); rc=$?; set -e
    [ "$rc" != 0 ] || fail "$(basename "${script%% *}"): old git was accepted"
    case "$err" in *"2.30.1"*) ;; *) fail "$(basename "${script%% *}"): the message does not name the git version: $err" ;; esac
  done
}

case_5() {
  echo "== gh is called with GH_PROMPT_DISABLED set (--reap and --release)"
  mkrepo gp ../gp-wt
  ( cd "$tmp/gp" && bash "$S" --take feat/p --slot 1 >/dev/null 2>&1 )
  work_commit "$tmp/gp-wt/slot-1" feat/p
  printf '%s\t%s\t%s\n' feat/p 11 "$(git -C "$tmp/gp-wt/slot-1" rev-parse HEAD)" > "$tmp/fix/merged.txt"
  : > "$tmp/gh.log"
  ( cd "$tmp/gp" && bash "$S" --reap >/dev/null 2>&1 ) || true
  grep -q 'pr list' "$tmp/gh.log" || fail "--reap did not call gh"
  if grep -q 'prompt=\[\]' "$tmp/gh.log"; then fail "--reap called gh without GH_PROMPT_DISABLED: $(cat "$tmp/gh.log")"; fi
  ( cd "$tmp/gp" && bash "$S" --take feat/q --slot 1 >/dev/null 2>&1 )
  work_commit "$tmp/gp-wt/slot-1" feat/q
  printf '%s\t%s\t%s\n' feat/q 12 "$(git -C "$tmp/gp-wt/slot-1" rev-parse HEAD)" > "$tmp/fix/merged.txt"
  : > "$tmp/gh.log"
  ( cd "$tmp/gp" && bash "$S" --release 1 >/dev/null 2>&1 ) || true
  grep -q 'pr list' "$tmp/gh.log" || fail "--release did not call gh"
  if grep -q 'prompt=\[\]' "$tmp/gh.log"; then fail "--release called gh without GH_PROMPT_DISABLED: $(cat "$tmp/gh.log")"; fi
}

( case_1 ) || bad=1
( case_2 ) || bad=1
( case_3 ) || bad=1
( case_4 ) || bad=1
( case_5 ) || bad=1
[ "$bad" = 0 ] || exit 1
echo "ok"
