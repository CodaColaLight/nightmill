#!/usr/bin/env bash
# scripts/render-templates.sh - write the project's GitHub issue forms from the nightmill templates.
#   render-templates.sh [--project <dir>] [--force]
# Reads areas, invariants, labels and verification from .claude/nightmill.json and fills the {{...}}
# placeholders in templates/ISSUE_TEMPLATE/*.yml. Without --force an existing form that differs is
# left alone and listed. Needs bash and awk, no jq.
set -euo pipefail

project=$(pwd); force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) project=${2:?}; shift ;;
    --force) force=1 ;;
    *) echo "usage: render-templates.sh [--project <dir>] [--force]" >&2; exit 1 ;;
  esac
  shift
done
. "$(dirname "${BASH_SOURCE[0]}")/lib/json.sh"

cfg="$project/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 1; }
json_load "$cfg" || exit 1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
src="$here/../templates/ISSUE_TEMPLATE"
dst="$project/.github/ISSUE_TEMPLATE"
mkdir -p "$dst"

areas_count=$(json_len areas)
[ "$areas_count" -gt 0 ] || { echo "nightmill.json needs at least one entry in areas" >&2; exit 1; }
# json_quote gives a double-quoted JSON string, which is a valid double-quoted YAML scalar: areas, labels and
# invariants all go through it, so `,` `:` `#` and `"` in them keep the forms valid YAML.
export AREAS; AREAS="["
for ((i = 0; i < areas_count; i++)); do
  if [ "$i" -gt 0 ]; then AREAS+=", "; fi
  AREAS+=$(json_quote "$(json_get "areas[$i]")")
done
AREAS+="]"
# Iteration 57 (#329): only an item that is a string with at least one character is rendered, every character
# kept (a trailing newline too: the value is read with a sentinel, so the command substitution drops nothing);
# the block is removed when no item is rendered.
inv_total=$(json_len invariants); inv_count=0
export INVARIANTS; INVARIANTS=""
for ((i = 0; i < inv_total; i++)); do
  [ "$(json_kind "invariants[$i]")" = string ] || continue
  inv=$(json_get "invariants[$i]"; printf x); inv=${inv%x}
  [ -n "$inv" ] || continue
  if [ "$inv_count" -gt 0 ]; then INVARIANTS+=$'\n'; fi
  INVARIANTS+="        - label: $(json_quote "$inv")"$'\n'"          required: false"
  inv_count=$((inv_count + 1))
done
export CHECK_COMMAND; CHECK_COMMAND=$(json_get verification.check "")
# An empty label or manualCheckText counts as not set (iteration 57, #329)
export MANUAL_CHECK; MANUAL_CHECK=$(json_text verification.manualCheckText "Manual check as the story describes")
export LABEL_EPIC; LABEL_EPIC=$(json_quote "$(json_text labels.epic "epic")")
export LABEL_STORY; LABEL_STORY=$(json_quote "$(json_text labels.story "story")")
export LABEL_BUG; LABEL_BUG=$(json_quote "$(json_text labels.bug "bug")")
export LABEL_NEEDS_SPEC; LABEL_NEEDS_SPEC=$(json_quote "$(json_text labels.needsSpec "needs-spec")")
export INV_COUNT=$inv_count

render() { # file
  awk '
    function sub_all(line, key, val) { # literal replacement, no regex, no & magic
      out = ""; k = "{{" key "}}"
      while ((i = index(line, k)) > 0) { out = out substr(line, 1, i - 1) val; line = substr(line, i + length(k)) }
      return out line
    }
    BEGIN { skip = 0 }
    /^  # \{\{INVARIANTS_BEGIN\}\}$/ { if (ENVIRON["INV_COUNT"] == "0") skip = 1; next }
    /^  # \{\{INVARIANTS_END\}\}$/   { skip = 0; next }
    skip == 1 { next }
    /^\{\{INVARIANTS\}\}$/ { print ENVIRON["INVARIANTS"]; next }
    {
      line = $0
      line = sub_all(line, "AREAS", ENVIRON["AREAS"])
      line = sub_all(line, "CHECK_COMMAND", ENVIRON["CHECK_COMMAND"])
      line = sub_all(line, "MANUAL_CHECK", ENVIRON["MANUAL_CHECK"])
      line = sub_all(line, "LABEL_EPIC", ENVIRON["LABEL_EPIC"])
      line = sub_all(line, "LABEL_STORY", ENVIRON["LABEL_STORY"])
      line = sub_all(line, "LABEL_BUG", ENVIRON["LABEL_BUG"])
      line = sub_all(line, "LABEL_NEEDS_SPEC", ENVIRON["LABEL_NEEDS_SPEC"])
      print line
    }' "$1"
}

kept=()
for f in "$src"/*.yml; do
  name=$(basename "$f")
  out="$dst/$name"
  text=$(render "$f")
  if [ -f "$out" ] && [ "$force" = 0 ]; then
    if [ "$(tr -d '\r' < "$out")" != "$text" ]; then kept+=("$name"); continue; fi
  fi
  printf '%s\n' "$text" > "$out"
  echo "wrote $out"
done
if [ ${#kept[@]} -gt 0 ]; then
  echo "kept (differ from the rendered text; use --force to overwrite): ${kept[*]}"
fi
