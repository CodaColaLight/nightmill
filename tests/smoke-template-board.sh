#!/usr/bin/env bash
# tests/smoke-template-board.sh - template-board.sh against fixtures: a fake gh answers from
# tests/fixtures/template-board/, the plugin files are copied to a throwaway root so that each scenario can
# have its own templates/board-template.json. The line must be the one smoke-template-board.ps1 expects too, so
# both shells print the same. Needs bash and awk, no jq, no network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-template-board.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
FIX="$here/tests/fixtures/template-board"

fail() { echo "FAIL: $*" >&2; exit 1; }

# a plugin root of its own: scripts, schema and a template location the scenarios change
plugin="$tmp/plugin"
mkdir -p "$plugin/templates" "$plugin/schema"
cp -R "$here/scripts" "$plugin/scripts"
cp "$here/schema/nightmill.schema.json" "$plugin/schema/"
S="$plugin/scripts/template-board.sh"

# a fake gh: it answers from $GH_FIX/$GH_FIELDS and logs every call to $GH_LOG
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "auth status")
    if [ -n "${GH_NOAUTH:-}" ]; then echo "You are not logged into any GitHub hosts." >&2; exit 1; fi
    exit 0 ;;
  "project view"|"project field-list")
    if [ -n "${GH_UNREACHABLE:-}" ]; then echo "GraphQL: Could not resolve to a ProjectV2 with the number 7." >&2; exit 1; fi
    if [ "$2" = view ]; then echo '{"number": 7, "title": "nightmill template", "public": true}'; else cat "$GH_FIX/$GH_FIELDS"; fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

cfg_default="$tmp/default.json"           # no board section at all: every name takes the schema default
cat > "$cfg_default" <<'EOF'
{ "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 }, "maintainer": { "name": "Alex" } }
EOF
cfg_area="$tmp/area.json"                 # the area field is renamed
cat > "$cfg_area" <<'EOF'
{ "board": { "areaField": "Module" } }
EOF
cfg_status="$tmp/status.json"             # one status is renamed
cat > "$cfg_status" <<'EOF'
{ "board": { "statuses": { "review": "In review" } } }
EOF
cfg_custom="$tmp/custom.json"             # a renamed status field, area field and status, all present in fields-custom.json
cat > "$cfg_custom" <<'EOF'
{ "board": { "statusField": "Stage", "areaField": "Module", "statuses": { "review": "In review" } } }
EOF

setup_template() { # setup_template <json>: the template location of the next run
  printf '%s\n' "$1" > "$plugin/templates/board-template.json"
}

run() { # run <config> <fields fixture> [args...]: Out, Err and Code of one run; env GH_UNREACHABLE / GH_NOAUTH pass through
  local config=$1 fields=$2
  shift 2
  : > "$tmp/gh.log"
  set +e
  (PATH="$tmp/bin:$PATH" GH_FIX="$FIX" GH_FIELDS="$fields" GH_LOG="$tmp/gh.log" bash "$S" "$@" --config "$config") > "$tmp/out.txt" 2> "$tmp/err.txt"
  Code=$?
  set -e
  Out=$(cat "$tmp/out.txt")
}

expect() { # expect <name> <line>: exit code 0 and exactly that one line
  [ "$Code" = 0 ] || fail "$1: exit code $Code: $(cat "$tmp/err.txt")"
  [ "$Out" = "$2" ] || fail "$1: expected '$2', got '$Out'"
  echo "ok: $1"
}

echo "== a usable template"
setup_template '{ "owner": "acme", "number": 7 }'
run "$cfg_default" fields-ok.json
expect "usable, every name from the schema defaults" "template: usable (acme/7)"
run "$cfg_custom" fields-custom.json
expect "usable, field and status names from the config" "template: usable (acme/7)"

echo "== not usable"
setup_template '{ "owner": "acme", "number": null }'
run "$cfg_default" fields-ok.json
expect "number is null" "template: not usable: none published"
grep -q . "$tmp/gh.log" && fail "a template without a number must not call gh: $(cat "$tmp/gh.log")"
setup_template '{ "owner": "acme", "number": 7 }'
GH_UNREACHABLE=1 run "$cfg_default" fields-ok.json
expect "gh cannot read the project" "template: not usable: not reachable"
run "$cfg_area" fields-ok.json
expect "the config renames a field the template does not have" "template: not usable: fields differ"
run "$cfg_default" fields-area-text.json
expect "the area field is not single select" "template: not usable: fields differ"
run "$cfg_status" fields-ok.json
expect "the config renames a status" "template: not usable: statuses differ"
run "$cfg_default" fields-missing-status.json
expect "a Status option is missing in the template" "template: not usable: statuses differ"
run "$cfg_default" fields-swapped-status.json
expect "the Status options are in another order" "template: not usable: statuses differ"

echo "== reads only"
run "$cfg_default" fields-ok.json
for c in 'project view' 'project field-list' 'auth status'; do
  grep -q "$c" "$tmp/gh.log" || fail "gh $c was never called"
done
if grep -E 'copy|link|item-|field-create|api|mutation|edit|delete' "$tmp/gh.log"; then fail "template-board.sh changed or asked for more than it should"; fi
grep -q '^project view 7 --owner acme' "$tmp/gh.log" || fail "the template is not read from the owner and number of board-template.json: $(cat "$tmp/gh.log")"

echo "== errors"
run "$cfg_default" fields-ok.json --nope
[ "$Code" = 2 ] && [ -z "$Out" ] || fail "an unknown option must exit 2 with no output, got $Code '$Out'"
set +e
(PATH="$tmp/bin:$PATH" GH_FIX="$FIX" GH_FIELDS=fields-ok.json GH_LOG="$tmp/gh.log" bash "$S") > "$tmp/out.txt" 2> "$tmp/err.txt"
Code=$?
set -e
[ "$Code" = 2 ] && grep -q 'usage' "$tmp/err.txt" || fail "no --config must exit 2 with the usage: $Code $(cat "$tmp/err.txt")"
run "$tmp/does-not-exist.json" fields-ok.json
[ "$Code" = 2 ] && grep -q 'does-not-exist.json' "$tmp/err.txt" || fail "an unreadable config must exit 2 and name the file: $Code $(cat "$tmp/err.txt")"
printf '{ "board": ' > "$tmp/broken.json"
run "$tmp/broken.json" fields-ok.json
[ "$Code" = 2 ] || fail "a config that is not JSON must exit 2, got $Code"
GH_NOAUTH=1 run "$cfg_default" fields-ok.json
[ "$Code" = 2 ] && grep -q 'not logged in' "$tmp/err.txt" || fail "gh not logged in must exit 2 with a message: $Code $(cat "$tmp/err.txt")"
setup_template '{ "owner": "acme", "number": "seven" }'
run "$cfg_default" fields-ok.json
[ "$Code" = 2 ] && grep -q 'number must be an integer or null' "$tmp/err.txt" || fail "a template number that is not an integer must exit 2: $Code $(cat "$tmp/err.txt")"
setup_template '{ "owner": "", "number": 7 }'
run "$cfg_default" fields-ok.json
[ "$Code" = 2 ] && grep -q 'owner must be a non-empty string' "$tmp/err.txt" || fail "an empty owner must exit 2: $Code $(cat "$tmp/err.txt")"
# no gh at all: only the system tools on the PATH
setup_template '{ "owner": "acme", "number": 7 }'
set +e
(PATH="/usr/bin:/bin" bash "$S" --config "$cfg_default") > "$tmp/out.txt" 2> "$tmp/err.txt"
Code=$?
set -e
if ! PATH="/usr/bin:/bin" command -v gh >/dev/null 2>&1; then
  [ "$Code" = 2 ] && grep -q 'gh is not installed' "$tmp/err.txt" || fail "a missing gh must exit 2 with a message: $Code $(cat "$tmp/err.txt")"
fi

echo "TEMPLATE-BOARD OK"
