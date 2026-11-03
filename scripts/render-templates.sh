#!/usr/bin/env bash
# scripts/render-templates.sh - write the project's GitHub issue forms from the nightmill templates.
# Bash twin of render-templates.ps1.
#   render-templates.sh [--project <dir>] [--force]
# Reads areas, invariants, labels and verification from .claude/nightmill.json and fills the {{...}}
# placeholders in templates/ISSUE_TEMPLATE/*.yml. Without --force an existing form that differs is
# left alone and listed. Needs jq.
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
command -v jq >/dev/null 2>&1 || { echo "render-templates.sh needs jq" >&2; exit 1; }

cfg="$project/.claude/nightmill.json"
[ -f "$cfg" ] || { echo "no $cfg (run /nightmill:init)" >&2; exit 1; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
src="$here/../templates/ISSUE_TEMPLATE"
dst="$project/.github/ISSUE_TEMPLATE"
mkdir -p "$dst"

[ "$(jq -r '.areas // [] | length' "$cfg")" -gt 0 ] || { echo "nightmill.json needs at least one entry in areas" >&2; exit 1; }
export AREAS; AREAS=$(jq -r '.areas | "[" + join(", ") + "]"' "$cfg")
# tojson gives a double-quoted JSON string, which is a valid double-quoted YAML scalar.
export INVARIANTS; INVARIANTS=$(jq -r '.invariants // [] | map("        - label: " + tojson + "\n          required: false") | join("\n")' "$cfg")
inv_count=$(jq -r '.invariants // [] | length' "$cfg")
export CHECK_COMMAND; CHECK_COMMAND=$(jq -r '.verification.check // ""' "$cfg")
export MANUAL_CHECK; MANUAL_CHECK=$(jq -r '.verification.manualCheckText // "Manual check as the story describes"' "$cfg")
export LABEL_EPIC; LABEL_EPIC=$(jq -r '.labels.epic // "epic"' "$cfg")
export LABEL_STORY; LABEL_STORY=$(jq -r '.labels.story // "story"' "$cfg")
export LABEL_BUG; LABEL_BUG=$(jq -r '.labels.bug // "bug"' "$cfg")
export LABEL_NEEDS_SPEC; LABEL_NEEDS_SPEC=$(jq -r '.labels.needsSpec // "needs-spec"' "$cfg")
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
