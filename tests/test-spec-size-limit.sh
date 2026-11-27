#!/usr/bin/env bash
# Tests for #347 (iteration 71): a spec stays short. The key iterations.maxSpecLines holds the most lines a spec file
# may have (0, the default, and an absent key: no limit); with a limit the spec writer's prompt states it, the spec
# reviewer reports a spec over it as a blocking finding, and a story that does not fit gets a split proposed as a
# comment on its issue instead of a spec; the spec template names what does not belong in a spec. The skills are
# conversations, so this pins the wording the behaviour depends on. Text is joined (newlines to spaces, runs of
# spaces made one) before it is searched. Usage: bash tests/test-spec-size-limit.sh [repository path]
set -uo pipefail
cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 1
fail=0
CASE=""
step() { CASE=$1; echo "-- $1"; }
miss() { echo "FAIL: $1: $2"; fail=1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-spec-size.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

flat() { tr '\n' ' ' | sed -E 's/ +/ /g'; }

# need <criterion> <file> <text>...: the joined file holds each text
need() {
  local crit=$1 f=$2 text flatf; shift 2
  if [ ! -f "$f" ]; then miss "$crit" "$f does not exist"; return; fi
  flatf=$(flat < "$f")
  for text in "$@"; do
    case "${flatf}" in
      *"${text}"*) ;;
      *) miss "$crit" "[${CASE}] $f does not say: ${text}" ;;
    esac
  done
}

SCHEMA=schema/nightmill.schema.json
EXAMPLE=templates/nightmill.example.json
SPEC=skills/spec/SKILL.md
REV=agents/spec-reviewer.md
TPL=templates/spec.md

# shellcheck source=scripts/lib/json.sh
. scripts/lib/json.sh

echo "== a spec stays within its size limit"

# Criterion 1: the configuration holds the limit
step schema
desc='The most lines a spec file may have, every line counted (blank lines, headings and the status line too). /spec tells the spec writer the limit, the spec reviewer reports a spec over it as a blocking finding, and a story that does not fit gets a split proposed on its issue instead of a spec. 0: no limit.'
if json_load "$SCHEMA"; then
  base=properties.iterations.properties.maxSpecLines
  [ "$(json_get "$base.type")" = integer ] || miss 1 "schema: $base.type is not integer"
  [ "$(json_get "$base.minimum")" = 0 ] || miss 1 "schema: $base.minimum is not 0"
  [ "$(json_get "$base.default")" = 0 ] || miss 1 "schema: $base.default is not 0"
  [ "$(json_get "$base.description" | flat | sed -E 's/ +$//')" = "$desc" ] || miss 1 "schema: $base.description is not the text of decision 1"
else
  miss 1 "schema: $SCHEMA cannot be read"
fi

step example
if json_load "$EXAMPLE"; then
  [ "$(json_kind iterations.maxSpecLines)" = number ] && [ "$(json_get iterations.maxSpecLines)" = 0 ] ||
    miss 1 "example: $EXAMPLE has no iterations.maxSpecLines of 0"
else
  miss 1 "example: $EXAMPLE cannot be read"
fi

step validate
ex=$(flat < "$EXAMPLE")
withval() { # withval <json value text>: the example with iterations.maxSpecLines set to it
  case "$ex" in
    *'"maxSpecLines": 0'*) printf '%s' "${ex/'"maxSpecLines": 0'/"\"maxSpecLines\": $1"}" ;;
    *) printf '%s' "${ex/'"decisionsDir": "docs/decisions"'/"\"decisionsDir\": \"docs/decisions\", \"maxSpecLines\": $1"}" ;;
  esac
}
vrun() { # vrun <name> <value text> <expected exit code>
  local f="$tmp/$1.json" out rc
  withval "$2" > "$f"
  out=$(bash scripts/validate-config.sh --strict "$f" 2>&1)
  rc=$?
  [ "$rc" = "$3" ] || miss 1 "validate: maxSpecLines $2 under --strict: expected exit $3, got $rc: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"
}
vrun ok 120 0
vrun negative -1 1
vrun string '"x"' 1

step readme
row=$(grep -F -- '| `iterations` |' README.md | head -1)
case "$row" in *'`maxSpecLines`'*) ;; *) miss 1 "readme: the iterations row of README.md does not name \`maxSpecLines\`" ;; esac
case "$row" in *'default 0: no limit'*) ;; *) miss 1 "readme: the iterations row of README.md does not say: default 0: no limit" ;; esac

step applies
need 1 "$SPEC" 'The size limit applies only when iterations.maxSpecLines in the base-branch configuration is at least 1; with the key absent or 0 nothing below is added.'
if [ -f "$SPEC" ]; then
  case "$(flat < "$SPEC")" in
    *'Result: complete | partial | failed | split'*) miss 1 "applies: $SPEC changes the unconditional result block to include split" ;;
  esac
fi

# Criterion 2: the writer is told the limit, the reviewer reports a spec over it
step writer
need 2 "$SPEC" \
  '<only when the size limit applies: The spec has at most <iterations.maxSpecLines> lines, every line of the file counted (blank lines, headings and the status line too). If the story cannot be specified within that, write no spec file: return Result: split with Spec: none and, on the Split line, the two or more stories it should be split into.' \
  'The size limit of a spec: <iterations.maxSpecLines> lines.'

step reviewer
need 2 "$REV" \
  'when your prompt gives a size limit, the spec has at most that many lines (the number of its last line as Read shows it).' \
  '- blocking <file>:<limit + 1> the spec has <n> lines, over the limit of <limit> (iterations.maxSpecLines)'

# Criterion 3: a spec that cannot fit proposes a split on the issue and stops
step split
sentence='With Result: split, the block below gets one last line after Left: Split: <the proposed stories, one per line as "- <title>: <the acceptance criteria it takes>">.'
need 3 "$SPEC" \
  "$sentence" \
  'Split proposed for #<issue>: the story does not fit in a spec of <limit> lines (iterations.maxSpecLines).' \
  'The maintainer decides. #<issue> stays at Spec; no spec pull request was opened.' \
  'The maintainer decides. #<issue> stays at Spec review; the spec pull request #<pr> is not changed by this proposal.' \
  'Split proposed for #<issue>:' \
  'gh issue comment <issue> --body-file' \
  'Stopped: #<issue> does not fit the spec size limit of <limit> lines; a split is proposed on the issue. The status of #<issue> is Spec.'
if [ -f "$SPEC" ]; then
  s=$(flat < "$SPEC")
  tail=${s#*'<only when the size limit applies:'}
  if [ "$tail" = "$s" ]; then
    miss 3 "split: $SPEC has no conditional paragraph of the size limit"
  else
    para=${tail%%"$sentence"*}
    if [ "$para" = "$tail" ]; then
      miss 3 "split: the sentence about Result: split is not in the conditional paragraph (after '<only when the size limit applies:')"
    else
      case "$para" in *'Result: complete | partial | failed'*) miss 3 "split: the sentence about Result: split is not in the conditional paragraph but after the unconditional result block" ;; esac
    fi
  fi
fi

# Criterion 4: the spec template names what does not belong in a spec
step template
need 4 "$TPL" '<!-- Not in a spec: the issue restated (point to it), the history of a decision (state the rule and its reason only), the text of other specs (name the spec and its rule). -->'

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "test-spec-size-limit: ok"
