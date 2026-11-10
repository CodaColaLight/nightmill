#!/usr/bin/env bash
# scripts/guard.sh - the PreToolUse guard hook (bash; iteration 47, #110). hooks/hooks.json runs it before every Bash
# and PowerShell tool call. It refuses, with exit code 2 and one line on stderr, what the workflow skill's hard rules
# forbid and a deny rule cannot recognise:
#   - a board status edit to Ready or Approved (gh project item-edit with that option id, or the GraphQL mutation
#     updateProjectV2ItemFieldValue naming it); the option ids are read at run time with gh project field-list,
#     only for a command that edits a status, and a status edit is refused when they cannot be read
#   - every merge that is not gh pr merge ... --auto, gh pr merge with --admin, and a merge through gh api
#   - a force push and a push to git.baseBranch in every git form, git -C <slot path> push included
#   - (iteration 50, #253) a remote branch delete (git push --delete, -d, --prune, --mirror or an empty source :<ref>),
#     a forced local branch delete (git branch -D, or --delete with --force), and a GraphQL mutation (gh api graphql)
#     with a top-level field outside the six the skills need, or a query sent from a file (--input, query=@<file>)
# Everything else: exit 0 and no output, so the normal permission flow decides. Off (exit 0) where the project has no
# .claude/nightmill.json, and for input that is not valid JSON, another tool or an empty command.
# The command is split into segments at && || ; | & and newlines outside quotes and each segment into words; a
# command substitution $(...) or `...` is judged as a command of its own. No other shell parsing. The rules are in
# docs/specs/iteration-47-enforce-hard-rules.md (decision 5) and
# docs/specs/iteration-50-refuse-other-deletes.md (decisions 3 to 5); scripts/guard.ps1 is the same in PowerShell.
#   CLAUDE_PROJECT_DIR   the project root (set by Claude Code); the current directory when unset
# Needs bash and awk, no jq (lib/json.sh reads the event and the config); gh only for a status edit.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/json.sh"

json_load /dev/stdin 2>/dev/null || exit 0
tool=$(json_get tool_name)
case "$tool" in Bash|PowerShell) ;; *) exit 0 ;; esac
cmd=$(json_get tool_input.command)
[ -n "$cmd" ] || exit 0

root=${CLAUDE_PROJECT_DIR:-$PWD}
cfg="$root/.claude/nightmill.json"
[ -f "$cfg" ] || exit 0
# json_get (lib/json.sh) reads JSON_FLAT; json_load leaves it as it is on failure, so a config that is not valid JSON
# gives the defaults below, not the event.
# shellcheck disable=SC2034
JSON_FLAT=""
json_load "$cfg" 2>/dev/null || :
owner=$(json_get github.owner)
number=$(json_get github.projectNumber)
field=$(json_get board.statusField Status)
ready=$(json_get board.statuses.ready Ready)
approved=$(json_get board.statuses.approved Approved)
base=$(json_get git.baseBranch main)
[ -n "$base" ] || base=main

refuse() { printf '%s\n' "$1" >&2; exit 2; }

# The verdicts, one line per judged segment, in order: R<TAB><kind> (refused), I<TAB><option id> (an item-edit),
# Q<TAB><segment text> (a GraphQL status edit), M<TAB><field> (a GraphQL mutation not on the allow list). Tabs and newlines inside a word or text become spaces.
verdicts=$(G_CMD=$cmd G_PS=$([ "$tool" = PowerShell ] && echo 1 || echo 0) G_BASE=$base LC_ALL=C awk '
function clean(x) { gsub(/[\t\n\r]/, " ", x); return x }
function ends(w, suf) { return length(w) >= length(suf) && substr(w, length(w) - length(suf) + 1) == suf }
function word_end() { if (inword) { nw++; W[nw] = cur }; cur = ""; inword = 0 }
function seg_end() { word_end(); if (nw > 0) judge(); nw = 0; segtext = "" }
# the end of the command substitution that starts after position p of s (the position of its closing character)
function sub_close(s, p, n, closer,   j, ch, q, depth) {
  q = ""; depth = 1
  for (j = p; j <= n; j++) {
    ch = substr(s, j, 1)
    if (closer == "`") { if (ch == "`") return j; continue }
    if (q != "") { if (ch == q) q = ""; continue }
    if (ch == "\047" || ch == "\"") { q = ch; continue }
    if (ch == "(") depth++
    else if (ch == ")") { depth--; if (depth == 0) return j }
  }
  return n + 1
}
function scan(s,   n, i, c, d, q, j, esc) {
  n = length(s); q = ""; nw = 0; cur = ""; inword = 0; segtext = ""
  esc = (ENVIRON["G_PS"] == "1") ? "`" : "\\"
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); d = substr(s, i + 1, 1)
    if (q == "\047") { segtext = segtext c; if (c == "\047") q = ""; else cur = cur c; continue }
    if (c == esc) { segtext = segtext c d; cur = cur d; inword = 1; i++; continue }
    if ((c == "$" && d == "(") || (c == "`" && esc != "`")) {
      j = (c == "`") ? sub_close(s, i + 1, n, "`") : sub_close(s, i + 2, n, ")")
      nq++; QUEUE[nq] = (c == "`") ? substr(s, i + 1, j - i - 1) : substr(s, i + 2, j - i - 2)
      segtext = segtext substr(s, i, j - i + 1); cur = cur substr(s, i, j - i + 1); inword = 1; i = j; continue
    }
    if (q == "\"") { segtext = segtext c; if (c == "\"") q = ""; else cur = cur c; continue }
    if (c == "\047" || c == "\"") { segtext = segtext c; q = c; inword = 1; continue }
    if (c == ";" || c == "|" || c == "&" || c == "\n") { seg_end(); continue }
    segtext = segtext c
    if (c == " " || c == "\t" || c == "\r") { word_end(); continue }
    cur = cur c; inword = 1
  }
  seg_end()
}
function verdict(kind, val) { print kind "\t" clean(val); judged = 1 }
function judge(   k, first) {
  k = 1
  while (k <= nw && W[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
  if (k > nw) return
  first = W[k]
  if (first == "gh" || first ~ /\/gh$/ || first == "gh.exe") judge_gh(k)
  else if (first == "git" || first ~ /\/git$/ || first == "git.exe") judge_git(k)
}
# gql_bad <document>: the first top-level field of a mutation in the GraphQL document that is not on the allow list,
# or "". Strings and comments are skipped, names inside parentheses (arguments, variables) and nested selections are
# not looked at; a name at brace depth 0 is an operation keyword (or a name), one at depth 1 a top-level field.
function gql_bad(s,   n, i, j, c, p, b, inmut, nm) {
  n = length(s); p = 0; b = 0; inmut = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\"") {
      for (i++; i <= n; i++) { c = substr(s, i, 1); if (c == "\\") { i++; continue }; if (c == "\"") break }
      continue
    }
    if (c == "#") { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
    if (c == "(") { p++; continue }
    if (c == ")") { if (p > 0) p--; continue }
    if (p > 0) continue
    if (c == "{") { b++; continue }
    if (c == "}") { if (b > 0) b--; continue }
    if (c !~ /[_A-Za-z]/) continue
    j = i
    while (j < n && substr(s, j + 1, 1) ~ /[_0-9A-Za-z]/) j++
    nm = substr(s, i, j - i + 1); i = j
    if (b == 0) {
      if (nm == "mutation") inmut = 1
      else if (nm == "query" || nm == "subscription" || nm == "fragment") inmut = 0
    } else if (b == 1 && inmut && !(nm in ALLOW)) return nm
  }
  return ""
}
function judge_gh(k,   m, w, merge, api, gql, auto, admin, disable, rest, edit, opt, doc, isdoc, bad) {
  merge = 0; api = 0; gql = 0; auto = 0; admin = 0; disable = 0; rest = 0; edit = 0; opt = ""
  for (m = k + 1; m <= nw; m++) {
    w = W[m]
    if (w == "pr" && m < nw && W[m + 1] == "merge") merge = 1
    if (w == "project" && m < nw && W[m + 1] == "item-edit") edit = 1
    if (w == "api") api = 1
    if (w == "graphql") gql = 1
    if (w == "--auto") auto = 1
    if (w == "--admin" || substr(w, 1, 8) == "--admin=") admin = 1
    if (w == "--disable-auto") disable = 1
    if (w ~ /pulls\/[0-9]+\/merge/) rest = 1
    if (w == "--single-select-option-id" && m < nw) opt = W[m + 1]
    else if (substr(w, 1, 26) == "--single-select-option-id=") opt = substr(w, 27)
  }
  if (merge && !disable) {
    if (admin) { verdict("R", "admin"); return }
    if (!auto) { verdict("R", "auto"); return }
  }
  if (api && rest) { verdict("R", "api"); return }
  if (api && gql && index(segtext, "mergePullRequest")) { verdict("R", "api"); return }
  if (api && gql) {
    for (m = k + 1; m <= nw; m++) {
      w = W[m]
      if (w == "--input" || substr(w, 1, 8) == "--input=") { verdict("R", "unread"); return }
      doc = ""; isdoc = 1
      if (substr(w, 1, 6) == "query=") doc = substr(w, 7)
      else if (substr(w, 1, 8) == "-fquery=" || substr(w, 1, 8) == "-Fquery=") doc = substr(w, 9)
      else if (substr(w, 1, 18) == "--raw-field=query=") doc = substr(w, 19)
      else if (substr(w, 1, 14) == "--field=query=") doc = substr(w, 15)
      else isdoc = 0
      if (!isdoc) continue
      if (substr(doc, 1, 1) == "@") { verdict("R", "unread"); return }
      bad = gql_bad(doc)
      if (bad != "") { verdict("M", bad); return }
    }
  }
  if (edit) { verdict("I", opt); return }
  if (api && gql && index(segtext, "updateProjectV2ItemFieldValue")) verdict("Q", segtext)
}
function judge_git(k,   m, w, sc, skip, b, del, frc) {
  b = ENVIRON["G_BASE"]; sc = 0
  for (m = k + 1; m <= nw; m++) {
    w = W[m]
    if (w == "-C" || w == "-c" || w == "--git-dir" || w == "--work-tree") { m++; continue }
    if (substr(w, 1, 1) == "-") continue
    sc = m; break
  }
  if (!sc) return
  if (W[sc] == "branch") {
    del = 0; frc = 0
    for (m = sc + 1; m <= nw; m++) {
      w = W[m]
      if (w ~ /^-[A-Za-z]*D[A-Za-z]*$/) { verdict("R", "fbd"); return }
      if (w == "--delete" || w ~ /^-[A-Za-z]*d[A-Za-z]*$/) del = 1
      if (w == "--force" || w ~ /^-[A-Za-z]*f[A-Za-z]*$/) frc = 1
    }
    if (del && frc) verdict("R", "fbd")
    return
  }
  if (W[sc] != "push") return
  for (m = sc + 1; m <= nw; m++) {
    w = W[m]
    if (substr(w, 1, 7) == "--force" || w ~ /^-[A-Za-z]*f[A-Za-z]*$/ || substr(w, 1, 1) == "+") { verdict("R", "force"); return }
  }
  skip = 0
  for (m = sc + 1; m <= nw; m++) {
    w = W[m]
    if (skip) { skip = 0; continue }
    if (w == "-o" || w == "--push-option" || w == "--repo" || w == "--receive-pack" || w == "--exec") { skip = 1; continue }
    if (w == "--delete" || w == "--prune" || w == "--mirror" || w ~ /^-[A-Za-z]*d[A-Za-z]*$/) { verdict("R", "delete"); return }
    if (substr(w, 1, 1) == ":" && length(w) > 1) { verdict("R", "delete"); return }
  }
  skip = 0
  for (m = sc + 1; m <= nw; m++) {
    w = W[m]
    if (skip) { skip = 0; continue }
    if (w == "-o" || w == "--push-option" || w == "--repo" || w == "--receive-pack" || w == "--exec") { skip = 1; continue }
    if (substr(w, 1, 1) == "-") continue
    if (w == b || ends(w, ":" b) || ends(w, "refs/heads/" b)) { verdict("R", "base"); return }
  }
}
BEGIN {
  # the GraphQL mutations the skills send (iteration 50, decision 5); every other one is refused
  split("addSubIssue createProjectV2View enablePullRequestAutoMerge updateProjectV2Field updateProjectV2ItemFieldValue updateProjectV2View", AL, " ")
  for (ai in AL) ALLOW[AL[ai]] = 1
  nq = 0
  scan(ENVIRON["G_CMD"])
  for (qi = 1; qi <= nq && qi <= 64; qi++) scan(QUEUE[qi])
}')

# word_in <text> <id>: the id occurs in the text as a whole word (no letter, digit, _ or - right before or after it)
word_in() {
  local t=$1 id=$2 b a
  [ -n "$id" ] || return 1
  while :; do
    case "$t" in *"$id"*) ;; *) return 1 ;; esac
    b=${t%%"$id"*}; a=${t#*"$id"}
    case "$b" in *[A-Za-z0-9_-]) ;; *) case "$a" in [A-Za-z0-9_-]*) ;; *) return 0 ;; esac ;; esac
    t="x$a"
  done
}

# lookup: the option ids of Ready and Approved into rid and aid, once; sets why and returns 1 when they cannot be read
looked=0; lookup_ok=0; rid=""; aid=""; why=""
lookup() {
  local expr out name id
  if [ "$looked" = 1 ]; then [ "$lookup_ok" = 1 ]; return; fi
  looked=1
  if [ -z "$owner" ] || [ -z "$number" ]; then why="github.owner or github.projectNumber is missing"; return 1; fi
  expr='.fields[] | select(.name == '$(json_quote "$field")') | .options[]? | select(.name == '$(json_quote "$ready")' or .name == '$(json_quote "$approved")') | "\(.name)\t\(.id)"'
  # -q is the short form of gh's jq flag
  if ! out=$(gh project field-list "$number" --owner "$owner" --format json -q "$expr" 2>/dev/null); then
    why="gh project field-list failed"; return 1
  fi
  while IFS=$'\t' read -r name id; do
    id=${id%$'\r'}
    [ "$name" = "$ready" ] && rid=$id
    [ "$name" = "$approved" ] && aid=$id
  done <<< "$out"
  if [ -z "$rid$aid" ]; then why="gh printed neither id"; return 1; fi
  lookup_ok=1
}

status_refuse() {
  refuse "nightmill guard: refused: setting $1 on the board. Only the maintainer sets $ready and $approved."
}
lookup_refuse() {
  refuse "nightmill guard: refused: a status edit, because the $ready and $approved option ids could not be read ($why). Read the board and try again; never set $ready or $approved."
}

while IFS=$'\t' read -r kind val; do
  case "$kind" in
    R)
      case "$val" in
        auto) refuse "nightmill guard: refused: a merge without --auto. Merge only with gh pr merge <pr> <git.mergeFlags>; git.mergeFlags must contain --auto." ;;
        admin) refuse "nightmill guard: refused: gh pr merge with --admin. Never merge past the checks." ;;
        api) refuse "nightmill guard: refused: a merge through gh api. Merge only with gh pr merge <pr> <git.mergeFlags>." ;;
        force) refuse "nightmill guard: refused: a force push. Push only with git push -u origin <branch>, never forced." ;;
        base) refuse "nightmill guard: refused: a push to $base. Never push to the base branch." ;;
        delete) refuse "nightmill guard: refused: deleting a remote branch. Push only with git push -u origin <branch>; never --delete, --prune, --mirror or an empty source." ;;
        fbd) refuse "nightmill guard: refused: a forced branch delete. Delete only a merged branch, with git branch -d <branch>." ;;
        unread) refuse "nightmill guard: refused: a GraphQL query the guard cannot read (--input or query=@<file>). Send it inline, as gh api graphql -f query='...'." ;;
      esac ;;
    M) refuse "nightmill guard: refused: the GraphQL mutation $val, which no skill sends." ;;
    I)
      lookup || lookup_refuse
      if [ -n "$val" ] && [ "$val" = "$rid" ]; then status_refuse "$ready"; fi
      if [ -n "$val" ] && [ "$val" = "$aid" ]; then status_refuse "$approved"; fi ;;
    Q)
      lookup || lookup_refuse
      if word_in "$val" "$rid"; then status_refuse "$ready"; fi
      if word_in "$val" "$aid"; then status_refuse "$approved"; fi ;;
  esac
done <<< "$verdicts"
exit 0
