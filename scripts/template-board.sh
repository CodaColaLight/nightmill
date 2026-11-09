#!/usr/bin/env bash
# scripts/template-board.sh - can /init copy nightmill's template board for this config? (nightmill)
#
#   template-board.sh --config <file>
#
# <file> is the candidate config /init builds before it shows the plan. The script reads the template's
# location from templates/board-template.json in the plugin, the board field names and the eight status
# names from <file> (a key the file does not have takes its default from schema/nightmill.schema.json), and
# asks GitHub what the template board looks like. It only reads: gh project view and gh project field-list,
# never gh project copy or any mutation.
#
# Prints exactly one line:
#   template: usable (<owner>/<number>)
#   template: not usable: <reason>      none published | not reachable | fields differ | statuses differ
# Exit code 0 whenever the line was printed, "usable" or not. Exit 2 for a usage error, an unreadable file, gh
# missing or not logged in; the message goes to standard error. The rules and the texts are in
# docs/specs/iteration-9-init-template-board.md; template-board.ps1 prints the same.
# Needs git, gh and bash (awk, no jq).
set -euo pipefail

usage() { echo "usage: template-board.sh --config <file>" >&2; exit 2; }
die() { echo "template-board.sh: $*" >&2; exit 2; }

config=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || usage; config=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done
[ -n "$config" ] || usage

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "$here")
# shellcheck source=lib/json.sh
. "$here/lib/json.sh"

tpl="$root/templates/board-template.json"
schema="$root/schema/nightmill.schema.json"
for f in "$config" "$tpl" "$schema"; do
  [ -f "$f" ] && [ -r "$f" ] || die "cannot read $f"
done

# the defaults come from the schema, the values from the candidate config
json_load "$schema" || exit 2
statuses="backlog ready spec specReview approved inProgress review done"
for k in statusField priorityField areaField; do
  printf -v "d_$k" '%s' "$(json_get "properties.board.properties.$k.default")"
done
for k in $statuses; do
  printf -v "d_$k" '%s' "$(json_get "properties.board.properties.statuses.properties.$k.default")"
done
json_load "$config" || exit 2
cfg() { local def="d_${1##*.}"; json_get "board.$1" "${!def}"; } # cfg statusField | cfg statuses.review
f_status=$(cfg statusField)
f_priority=$(cfg priorityField)
f_area=$(cfg areaField)
wanted=""
for k in $statuses; do
  wanted="$wanted$(cfg "statuses.$k")"$'\n'
done
wanted=${wanted%$'\n'}

# where the template lives: owner a non-empty string, number an integer or null
json_load "$tpl" || exit 2
t_owner=$(json_get owner)
[ -n "$t_owner" ] || die "$tpl: owner must be a non-empty string"
t_kind=$(printf '%s\n' "$JSON_FLAT" | awk -F '\t' '$1 == "number" { print $2 }')
t_number=""
case "$t_kind" in
  null) ;;
  number)
    t_number=$(json_get number)
    case "$t_number" in
      ''|*[!0-9]*|0*) die "$tpl: number must be an integer or null" ;;
    esac ;;
  *) die "$tpl: number must be an integer or null" ;;
esac

command -v gh >/dev/null 2>&1 || die "gh is not installed or not on the PATH"

if [ -z "$t_number" ]; then
  echo "template: not usable: none published"
  exit 0
fi

gh auth status >/dev/null 2>&1 || die "gh is not logged in (run gh auth login)"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-template-board.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
if ! gh project view "$t_number" --owner "$t_owner" --format json > "$tmp/view.json" 2> "$tmp/err" \
  || ! gh project field-list "$t_number" --owner "$t_owner" --limit 50 --format json > "$tmp/fields.json" 2> "$tmp/err" \
  || ! json_load "$tmp/fields.json"; then
  echo "template: not usable: not reachable"
  exit 0
fi

# the index in fields[] of the single select field called $1, empty when there is none
field_index() {
  printf '%s\n' "$JSON_FLAT" | JSON_NAME=$1 awk -F '\t' '
    $1 ~ /^fields\[[0-9]+\]\.name$/ { i = $1; sub(/^fields\[/, "", i); sub(/\]\.name$/, "", i); name[i] = $3 }
    $1 ~ /^fields\[[0-9]+\]\.type$/ { i = $1; sub(/^fields\[/, "", i); sub(/\]\.type$/, "", i); type[i] = $3 }
    END {
      for (i = 0; i in name || i in type; i++)
        if (name[i] == ENVIRON["JSON_NAME"] && type[i] == "ProjectV2SingleSelectField") { print i; exit }
    }'
}
for f in "$f_status" "$f_priority" "$f_area"; do
  if [ -z "$(field_index "$f")" ]; then echo "template: not usable: fields differ"; exit 0; fi
done

si=$(field_index "$f_status")
n=$(json_len "fields[$si].options")
have=""; i=0
while [ "$i" -lt "$n" ]; do
  have="$have$(json_get "fields[$si].options[$i].name")"$'\n'
  i=$((i + 1))
done
if [ "${have%$'\n'}" != "$wanted" ]; then
  echo "template: not usable: statuses differ"
  exit 0
fi

echo "template: usable ($t_owner/$t_number)"
