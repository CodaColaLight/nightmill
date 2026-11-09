---
name: story
description: Turn the maintainer's one-line idea into a story issue on the board, filed from the story form under the right epic. Use when asked to file, write or create a story.
argument-hint: <one-line idea>
disable-model-invocation: true
allowed-tools: Bash(cat .claude/nightmill.json *), Bash(echo "NO CONFIG* run /nightmill:init first")
---

Turn this one-line idea into a story issue: $ARGUMENTS

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json 2>/dev/null || echo "NO CONFIG: run /nightmill:init first"`

Read the configuration first. *The maintainer* is `maintainer.name`; `<owner>`, `<repo>`, `<project>` come
from `github`; label names from `labels`; areas from `areas`. Where this text and the configuration
disagree, the configuration wins.

1. **Find the parent epic:** `gh issue list --label <labels.epic> --state open --json number,title`. If it
   is not clear which epic fits, ask; if none fits, propose a new epic (form: `.github/ISSUE_TEMPLATE/epic.yml`)
   and ask before creating it.
2. **Fill every field of `.github/ISSUE_TEMPLATE/story.yml`**, in its order and with its `###` headings:
   Area (from `areas`), Epic (`#number`), Context (link specs and decisions, do not repeat them), Goal (one
   sentence a user would understand), Acceptance criteria (testable checkboxes, **no numbers**: numbers go in
   the spec), Invariants (tick the ones that apply), Out of scope, Verification, Agent notes (files likely
   touched, known gotchas, related issues). Show the draft to the maintainer and adjust.
3. **Create it:**
   `gh issue create --title "[Story] <title>" --label <labels.story>,<labels.needsSpec>,<labels.areaPrefix><area>,<labels.priorityPrefix><prio> --body-file <file>`.
   Priority is one of `board.priorities`, lower-cased for the label.
4. **Attach it to the epic as a sub-issue**
   (`gh api graphql -f query='mutation($p:ID!,$c:ID!){ addSubIssue(input:{issueId:$p, subIssueId:$c}){ issue { number } } }' -f p=<epic node id> -f c=<story node id>`,
   node ids from `gh issue view N --json id`), make sure it is on the board with status **Backlog**
   (`gh project item-add <project> --owner <owner> --url <issue url>` if it is not there yet), and set its
   `board.areaField` and `board.priorityField` fields. Read the item back and report its status.

Never set Ready or Approved; only the maintainer does. New stories start in Backlog.
