---
name: fix
description: Fix one bug from the board without an iteration - failing test first, smallest fix, one PR. "all" works through every Ready bug in turn. Use when asked to fix a bug issue.
argument-hint: [issue-number | all]
disable-model-invocation: true
---

Fix one bug from GitHub Issues, without an iteration: $ARGUMENTS (`all` = every Ready bug in turn, see "Batch mode")

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json`

Read the configuration first. *The maintainer* is `maintainer.name`; `<owner>`, `<repo>`, `<project>` come
from `github`; status names from `board.statuses`; label names from `labels`. Where this text and the
configuration disagree, the configuration wins. The process rules are in the `workflow` skill of this plugin.

A bug is a defect in shipped behaviour (form: `.github/ISSUE_TEMPLATE/bug.yml`). It needs no spec,
milestone, iteration number or CHANGELOG entry.

1. **Pick the issue.** If `$ARGUMENTS` has a number, use it; otherwise list the items whose status is
   Ready on the board (`gh project item-list <project> --owner <owner> --limit 200 --format json --jq '.items[] | [.content.number, .content.type, .status, .priority, ((.labels // []) | join(",")), .content.title] | @tsv'`), keep
   open issues labelled `labels.bug`, take the highest `board.priorityField` and ask the maintainer on a
   tie. Nothing Ready: say so and stop. Read it with `gh issue view N --json number,title,labels,body`.
2. **Decide whether it is a bug.** If the fix needs one of `escalation.storyTriggers` or a design choice,
   stop: say so and suggest the maintainer files it as a story (`/story`).
3. **Set the status to In progress** and read it back (`gh project item-list`, `gh project field-list`,
   `gh project item-edit`). Work in a slot: `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Take <git.fixPrefix><number>-<slug>`
   (bash: `slot.sh --take ...`); `-Release N` after the merge. In a single checkout without slots,
   `git switch -c <git.fixPrefix><number>-<slug>` from up-to-date `origin/<git.baseBranch>`.
4. **Write the test that fails for the reason in the issue first**, named for the behaviour it protects,
   and watch it fail. Then fix the cause, not the symptom, with the smallest diff that does it.
   `verification.benchRule` applies when set. A different problem you notice goes in a new issue.
5. If the fix changes a rule or number that a spec states, correct that spec's text. Do not add a
   CHANGELOG entry.
6. **Run the check** (`/nightmill:check`). A change under any of `verification.manualCheckPaths` also
   gets `verification.manualCheckText`.
7. **Open a PR** titled `fix: <what> (#N)` with `Fixes #N` and the sections Cause, Fix and How verified
   (the test, the check, the manual steps). Set the status to Review and read it back. For a complete
   fix enable auto-merge (`gh pr merge <pr> <git.mergeFlags>`); not for a partial fix or one that touches
   `escalation.storyTriggers` (that is a story).

## Batch mode: `/fix all`

Works through every Ready bug, one after another, without asking the maintainer anything. Steps 1 to 7
are the same for each bug, with these differences:

- **Order and cap.** All open `labels.bug` items with status Ready, by `board.priorities` (highest first),
  then by issue number; no ties to ask about. At most 5 per run; the rest go in the report for the next run.
- **One branch per bug, each from up-to-date `origin/<git.baseBranch>`**, not on top of the previous fix.
  After a bug's PR is open, switch back to the base branch, `git pull --ff-only`, and start the next.
  Nothing waits for a merge. If a bug touches a file an earlier PR of this run changed, say so in its PR
  ("overlaps #N, will conflict until that merges").
- **A bug that cannot be done is skipped, not stopped on.** Skip it when step 2 says it is a story (report
  "needs a story", no status change), when the test cannot reproduce it, when the check is still red after
  three honest attempts, or when the fix grows into one of `escalation.storyTriggers`. Commit what exists
  to the local branch (do not push), leave the status as it is (never set Ready), and say why in the report.
- **The whole run stops** if the working tree is dirty at the start, `git` or `gh` fails on authentication
  or network, or the check is red on a clean base branch (that is not a bug fix: report it).
- **Never** merge any other way than with `git.mergeFlags` on a complete fix, push to the base branch,
  close an issue by hand (the PR's `Fixes #N` does), or edit an issue.
- **End with a table:** issue, PR (or "skipped"), one-line cause, and what was verified. Name the manual
  check as not done where it could not be done.

## Hard rules

Never set Ready or Approved (only the maintainer does). Never close an epic. Never delete files without
asking. Never run a plain `gh pr merge` (it would bypass the checks).
