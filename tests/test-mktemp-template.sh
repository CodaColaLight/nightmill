#!/usr/bin/env bash
# tests/test-mktemp-template.sh - bug 115: on sandboxed macOS a bare mktemp ignores $TMPDIR and is denied.
# (a) no bash file in scripts/, scripts/lib/ or tests/ calls mktemp without a template;
# (b) status.sh, load.sh, control.sh and slot.sh --status succeed with a mktemp shim first on PATH that refuses a
# call without a template (the sandbox's message, exit 1) and hands a templated call to the real mktemp.
# Needs bash and awk, no network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-mktemp.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== no bare mktemp in the source"
bare=""
for f in "$here"/scripts/*.sh "$here"/scripts/lib/*.sh "$here"/tests/*.sh; do
  [ "$f" = "$here/tests/test-mktemp-template.sh" ] && continue
  hits=$(awk -v file="${f#"$here"/}" '
    /^[ \t]*#/ { next }
    {
      line = $0
      while ((pos = match(line, /(^|[^A-Za-z0-9_.-])mktemp([ \t]|$|[)`;|&"])/)) > 0) {
        rest = substr(line, pos + RLENGTH - 1)
        sub(/^[ \t]*(-d[ \t]*)?/, "", rest)
        if (rest == "" || rest ~ /^[)`;|&]/) print file ":" NR ": " $0
        line = substr(line, pos + RLENGTH)
      }
    }' "$f")
  [ -z "$hits" ] || bare="$bare$hits"$'\n'
done
[ -z "$bare" ] || fail "mktemp without a template:"$'\n'"$bare"

echo "== the scripts run with a mktemp that refuses a bare call"
real=$(command -v mktemp)
mkdir "$tmp/shim"
cat > "$tmp/shim/mktemp" <<SHIM
#!/usr/bin/env bash
have=""
for a in "\$@"; do case "\$a" in -*) ;; *) have=1 ;; esac; done
if [ -z "\$have" ]; then
  echo "mktemp: mkdtemp failed on /var/folders/xx/T/tmp.XXXXXXXXXX: Operation not permitted" >&2
  exit 1
fi
exec "$real" "\$@"
SHIM
chmod +x "$tmp/shim/mktemp"

# A fake gh for status.sh
cat > "$tmp/shim/gh" <<'EOF2'
#!/usr/bin/env bash
case "$1 $2" in
  "project item-list") cat "$GH_FIX/items.json" ;;
  "project view") echo '{"id": "PVT_test", "number": 1}' ;;
  "pr list") cat "$GH_FIX/prs.json" ;;
  "api graphql") cat "$GH_FIX/ages.json" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF2
chmod +x "$tmp/shim/gh"

work="$tmp/work"
git init -q -b main "$work"
mkdir -p "$work/.claude" "$tmp/wt/.slots" "$tmp/fx"
cat > "$work/.claude/nightmill.json" <<'EOF2'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" },
  "verification": { "check": "true" },
  "parallel": { "controlMode": "report" },
  "worktrees": { "root": "../wt", "slots": 2 }
}
EOF2
printf '10 500 2000\n10 500 2000\n10 500 2000\n' > "$tmp/fx/roomy"

run() { # run <name> <script> [args]: must exit 0 under the shim
  local name=$1 s=$2
  shift 2
  set +e
  (cd "$work" && PATH="$tmp/shim:$PATH" GH_FIX="$here/tests/fixtures/status/a" NIGHTMILL_NOW=1793880000 \
    NIGHTMILL_LOAD_FIXTURE="$tmp/fx/roomy" bash "$here/scripts/$s" "$@") > "$tmp/out.txt" 2> "$tmp/err.txt"
  local code=$?
  set -e
  [ "$code" = 0 ] || fail "$name: exit $code: $(tr '\n' ' ' < "$tmp/err.txt")"
}

run "status.sh" status.sh
run "load.sh" load.sh
run "control.sh" control.sh
run "slot.sh --status" slot.sh --status

echo "test-mktemp-template: ok"
