#!/usr/bin/env bash
# tests/smoke-models.sh - scripts/models.sh: the table of every agent role, its model, where the model comes from,
# its rank and whether its pairing holds. The defaults are printed and named, a reviewer below its producer and a
# model that is not in the ranking are flagged, tester and worker never are, an invalid ranking is reported, usage
# errors exit 2, nothing is changed, the verdict agrees with validate-config, and the default config is found from a
# subfolder and from a second worktree. Same cases as smoke-models.ps1. Needs bash, awk and git, no jq.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-models.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
M="$here/scripts/models.sh"
V="$here/scripts/validate-config.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

ex=$(cat "$here/templates/nightmill.example.json")
bare='{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true"}}'

# edit <text> <old> <new>: replace a piece of the text; the piece has to exist
edit() {
  case "$1" in *"$2"*) ;; *) fail "fixture: '$2' is not in the example" ;; esac
  printf '%s' "${1/"$2"/$3}"
}

declare -A DOES=(
  [specWriter]='writes the spec of a Ready story'
  [specReviewer]='reviews specWriter'
  [tester]='writes the failing tests before the code'
  [implementer]='writes the code of an Approved story'
  [codeReviewer]='reviews implementer and fixer'
  [fixer]='fixes a bug'
  [worker]='does mechanical, fully specified jobs'
)

# table <role|model|from|rank|check>...: the expected table, with the padding worked out here (an oracle written
# apart from the script): every column but the last as wide as its widest cell, two spaces between, no trailing space
table() {
  local r role model from rank check w1=4 w2=4 w3=5 w4=4 w5=4
  for r in "$@"; do
    IFS='|' read -r role model from rank check <<<"$r"
    (( ${#role} > w1 )) && w1=${#role}
    (( ${#DOES[$role]} > w2 )) && w2=${#DOES[$role]}
    (( ${#model} > w3 )) && w3=${#model}
    (( ${#from} > w4 )) && w4=${#from}
    (( ${#rank} > w5 )) && w5=${#rank}
  done
  printf '%-*s  %-*s  %-*s  %-*s  %-*s  %s\n' "$w1" role "$w2" does "$w3" model "$w4" from "$w5" rank check | sed 's/ *$//'
  for r in "$@"; do
    IFS='|' read -r role model from rank check <<<"$r"
    printf '%-*s  %-*s  %-*s  %-*s  %-*s  %s\n' "$w1" "$role" "$w2" "${DOES[$role]}" "$w3" "$model" "$w4" "$from" "$w5" "$rank" "$check" | sed 's/ *$//'
  done
}

i=0
# run <name> <config text> <expected output>: exit 0 and the whole output equal to the expected text
run() {
  local name=$1 text=$2 want=$3 f out rc
  i=$((i + 1))
  f="$tmp/case$i.json"
  printf '%s\n' "$text" > "$f"
  set +e; out=$(bash "$M" --config "$f" 2>&1); rc=$?; set -e
  [ "$rc" = 0 ] || fail "$name: expected exit code 0, got $rc: $out"
  [ "$out" = "$want" ] || fail "$name: wrong output. Got:
$out
Wanted:
$want"
}

DEF_ROWS=(
  'specWriter|opus|default|3|-' 'specReviewer|opus|default|3|ok' 'tester|sonnet|default|2|-'
  'implementer|opus|default|3|-' 'codeReviewer|opus|default|3|ok' 'fixer|opus|default|3|-' 'worker|haiku|default|1|-'
)
CFG_ROWS=(
  'specWriter|opus|config|3|-' 'specReviewer|opus|config|3|ok' 'tester|sonnet|config|2|-'
  'implementer|opus|config|3|-' 'codeReviewer|opus|config|3|ok' 'fixer|opus|config|3|-' 'worker|haiku|config|1|-'
)
RK_CFG='ranking: haiku < sonnet < opus < fable (config)'
SW='"specWriter": { "model": "opus" }'; SR='"specReviewer": { "model": "opus" }'
CR='"codeReviewer": { "model": "opus" }'; RK='"ranking": ["haiku", "sonnet", "opus", "fable"]'

echo "== no keys prints the defaults and says so"
want1=$(cat <<'EOF'
role          does                                      model   from     rank  check
specWriter    writes the spec of a Ready story          opus    default  3     -
specReviewer  reviews specWriter                        opus    default  3     ok
tester        writes the failing tests before the code  sonnet  default  2     -
implementer   writes the code of an Approved story      opus    default  3     -
codeReviewer  reviews implementer and fixer             opus    default  3     ok
fixer         fixes a bug                               opus    default  3     -
worker        does mechanical, fully specified jobs     haiku   default  1     -

ranking: haiku < sonnet < opus < fable (default)
pairings: ok
No role model and no ranking in the config: these are the defaults of the schema.
EOF
)
run "no keys" "$bare" "$want1"
[ "$(table "${DEF_ROWS[@]}")"$'\n\nranking: haiku < sonnet < opus < fable (default)\npairings: ok\nNo role model and no ranking in the config: these are the defaults of the schema.' = "$want1" ] || fail "fixture: the oracle table differs from the literal example"

echo "== a fully configured config"
run "example" "$ex" "$(table "${CFG_ROWS[@]}")"$'\n\n'"$RK_CFG"$'\npairings: ok'

echo "== a reviewer below its producer is flagged"
want3=$(cat <<'EOF'
role          does                                      model   from     rank  check
specWriter    writes the spec of a Ready story          opus    config   3     -
specReviewer  reviews specWriter                        sonnet  config   2     BELOW specWriter
tester        writes the failing tests before the code  sonnet  default  2     -
implementer   writes the code of an Approved story      opus    default  3     -
codeReviewer  reviews implementer and fixer             opus    default  3     ok
fixer         fixes a bug                               opus    default  3     -
worker        does mechanical, fully specified jobs     haiku   default  1     -

ranking: haiku < sonnet < opus < fable (default)
pairings: 1 below, 0 not ranked
EOF
)
case3="$bare"; case3=${case3%\}}',"roles":{"specWriter":{"model":"opus"},"specReviewer":{"model":"sonnet"}}}'
run "spec reviewer below" "$case3" "$want3"

echo "== the code reviewer below both producers"
case4=$(edit "$ex" "$CR" '"codeReviewer": { "model": "haiku" }')
run "code reviewer below" "$case4" "$(table 'specWriter|opus|config|3|-' 'specReviewer|opus|config|3|ok' 'tester|sonnet|config|2|-' \
  'implementer|opus|config|3|-' 'codeReviewer|haiku|config|1|BELOW implementer, fixer' 'fixer|opus|config|3|-' 'worker|haiku|config|1|-')"$'\n\n'"$RK_CFG"$'\npairings: 2 below, 0 not ranked'

echo "== a model that is not in the ranking is flagged"
case5a=$(edit "$ex" "$SR" '"specReviewer": { "model": "mystery" }')
run "unranked reviewer" "$case5a" "$(table 'specWriter|opus|config|3|-' 'specReviewer|mystery|config|-|NOT RANKED' 'tester|sonnet|config|2|-' \
  'implementer|opus|config|3|-' 'codeReviewer|opus|config|3|ok' 'fixer|opus|config|3|-' 'worker|haiku|config|1|-')"$'\n\n'"$RK_CFG"$'\npairings: 0 below, 1 not ranked'
case5b=$(edit "$ex" '"implementer": { "model": "opus" }' '"implementer": { "model": "mystery" }')
run "unranked producer" "$case5b" "$(table 'specWriter|opus|config|3|-' 'specReviewer|opus|config|3|ok' 'tester|sonnet|config|2|-' \
  'implementer|mystery|config|-|NOT RANKED' 'codeReviewer|opus|config|3|ok' 'fixer|opus|config|3|-' 'worker|haiku|config|1|-')"$'\n\n'"$RK_CFG"$'\npairings: 0 below, 1 not ranked'

echo "== tester and worker are never flagged"
run "tester and worker" "$(edit "$(edit "$ex" '"tester": { "model": "sonnet" }' '"tester": { "model": "haiku" }')" '"worker": { "model": "haiku" }' '"worker": { "model": "mystery" }')" \
  "$(table 'specWriter|opus|config|3|-' 'specReviewer|opus|config|3|ok' 'tester|haiku|config|1|-' \
  'implementer|opus|config|3|-' 'codeReviewer|opus|config|3|ok' 'fixer|opus|config|3|-' 'worker|mystery|config|-|-')"$'\n\n'"$RK_CFG"$'\npairings: ok'

echo "== same level in one ranking entry"
same=$(edit "$(edit "$ex" "$RK" '"ranking": ["haiku", "sonnet", "opus=claude-opus-5-5", "fable"]')" "$SW" '"specWriter": { "model": "claude-opus-5-5" }')
run "same level" "$same" "$(table 'specWriter|claude-opus-5-5|config|3|-' 'specReviewer|opus|config|3|ok' 'tester|sonnet|config|2|-' \
  'implementer|opus|config|3|-' 'codeReviewer|opus|config|3|ok' 'fixer|opus|config|3|-' 'worker|haiku|config|1|-')"$'\n\nranking: haiku < sonnet < opus=claude-opus-5-5 < fable (config)\npairings: ok'

echo "== an empty model takes the default"
run "empty model" "$(edit "$ex" "$SR" '"specReviewer": { "model": "" }')" "$(table 'specWriter|opus|config|3|-' 'specReviewer|opus|default|3|ok' 'tester|sonnet|config|2|-' \
  'implementer|opus|config|3|-' 'codeReviewer|opus|config|3|ok' 'fixer|opus|config|3|-' 'worker|haiku|config|1|-')"$'\n\n'"$RK_CFG"$'\npairings: ok'

echo "== an invalid ranking"
run "invalid ranking" "$(edit "$ex" "$RK" '"ranking": "opus"')" "$(table 'specWriter|opus|config|-|-' 'specReviewer|opus|config|-|-' 'tester|sonnet|config|-|-' \
  'implementer|opus|config|-|-' 'codeReviewer|opus|config|-|-' 'fixer|opus|config|-|-' 'worker|haiku|config|-|-')"$'\n\nranking: invalid (needs a non-empty list; run validate-config)\npairings: not checked'

echo "== usage errors exit 2"
set +e; err=$(bash "$M" --config "$tmp/does-not-exist.json" 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" = 2 ] || fail "missing config: expected exit code 2, got $rc"
case "$err" in *"does-not-exist.json"*) ;; *) fail "missing config: the message does not name the path: $err" ;; esac
printf '%s\n' '{"a": 1,}' > "$tmp/bad.json"
set +e; bash "$M" --config "$tmp/bad.json" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "invalid JSON: expected exit code 2, got $rc"
printf '%s\n' '[1]' > "$tmp/arr.json"
set +e; bash "$M" --config "$tmp/arr.json" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "a config that is not an object: expected exit code 2, got $rc"
set +e; bash "$M" --no-such-option >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "unknown option: expected exit code 2, got $rc"

echo "== it changes nothing"
ro="$tmp/ro"; mkdir -p "$ro"
printf '%s\n' "$ex" > "$ro/nightmill.json"
before_cfg=$(cat "$ro/nightmill.json"); before_ls=$(ls -la "$ro" | sed 1d | awk '{ print $1, $5, $9 }')
bash "$M" --config "$ro/nightmill.json" >/dev/null
[ "$(cat "$ro/nightmill.json")" = "$before_cfg" ] || fail "the config changed"
[ "$(ls -la "$ro" | sed 1d | awk '{ print $1, $5, $9 }')" = "$before_ls" ] || fail "the folder changed"

echo "== it agrees with validate-config"
# the number of errors the validator gives for the pairing rule is B and the number of warnings is U
agree() {
  local name=$1 text=$2 f="$tmp/agree.json" out summary b u e w
  printf '%s\n' "$text" > "$f"
  out=$(bash "$M" --config "$f")
  summary=$(printf '%s\n' "$out" | grep '^pairings: ')
  b=0; u=0
  case "$summary" in
    "pairings: ok"|"pairings: not checked") ;;
    *) b=${summary#pairings: }; b=${b%% below*}; u=${summary#*below, }; u=${u%% not ranked*} ;;
  esac
  set +e; vout=$(bash "$V" "$f" 2>&1); set -e
  e=$(printf '%s\n' "$vout" | grep -c '^error: ' || true)
  w=$(printf '%s\n' "$vout" | grep -c '^warning: ' || true)
  [ "$e" = "$b" ] || fail "$name: the table counts $b below, the validator $e errors: $vout"
  [ "$w" = "$u" ] || fail "$name: the table counts $u not ranked, the validator $w warnings: $vout"
}
agree "example" "$ex"
agree "spec reviewer below" "$case3"
agree "code reviewer below" "$case4"
agree "unranked reviewer" "$case5a"
agree "unranked producer" "$case5b"
agree "same level" "$same"

echo "== it finds the config from a subfolder and from a second worktree"
repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/.claude" "$repo/sub"
printf '%s\n' "$case3" > "$repo/.claude/nightmill.json"
echo x > "$repo/sub/x.txt"
( cd "$repo" && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm init && git worktree add -q "$tmp/repo-wt2" -b other )
for d in "$repo/sub" "$tmp/repo-wt2"; do
  out=$(cd "$d" && bash "$M")
  [ "$out" = "$want3" ] || fail "from $d: wrong output. Got:
$out"
done

echo "MODELS OK"
