---
name: next
description: Take the next story from the board - implement an Approved story, or write the spec for a Ready one. Use when asked to pick up the next story, start a story, spec an issue, or implement an approved spec.
argument-hint: [issue-number]
disable-model-invocation: true
---

Pick up the next story from the board: $ARGUMENTS

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json`

Read the configuration first. Below, *the maintainer* is `maintainer.name`; `<owner>`, `<repo>` and
`<project>` come from `github`; status names from `board.statuses`; label names from `labels`. Where this
text and the configuration disagree, the configuration wins. The process rules are in the `workflow`
skill of this plugin; this skill is the step list.

## 1. Pick the issue

- If `$ARGUMENTS` holds an issue number, take that issue in whatever status it is in (Ready or Approved).
- Otherwise list the board: `gh project item-list <project> --owner <owner> --limit 200 --format json`.
  Keep open issues that are not epics and not bugs (bugs go through `/fix`).
  Candidates are **Approved items first** (work already approved beats new specs), then **Ready** items.
  Within a group take the highest `board.priorityField`; on a tie ask the maintainer which.
- Nothing Approved or Ready: say so and stop.
- Read the issue with `gh issue view N --json number,title,labels,body,milestone,comments`, its parent epic,
  and every spec and decision either references.

## 2. A Ready story: write the spec, then stop

1. Set the status to **Spec** right away and read it back (`gh project item-list` for the item id,
   `gh project field-list` for the field and option ids, then `gh project item-edit`). Not In progress:
   nothing is being implemented yet.
2. Pick the iteration number N: the higher of the latest entry in `iterations.changelog` and the highest
   milestone matching `iterations.milestonePattern` (`gh api repos/<owner>/<repo>/milestones --paginate`,
   state all; another task may have claimed a number that is not merged yet), plus 1. Create the
   milestone if missing and put the issue in it.
3. Write `<iterations.specDir>/<iterations.specPattern>` from the acceptance criteria: exact rules and
   numbers, a "Not done" list, and the status line `Status: draft, awaiting approval (#N)`.
4. Open the spec as its own PR: a branch `<git.specPrefix><N>-<slug>` from up-to-date
   `origin/<git.baseBranch>` (the working tree must be clean; if it is not, say so and stop), commit the
   spec only, push, PR titled `docs: iteration <N> spec (#<issue>)` with the body `Spec for #<issue>.`
   (not `Closes`), and `gh pr merge <pr> <git.mergeFlags>`: a spec PR is docs only. Switch back to the
   branch you came from.
5. Set the status to **Spec review** and read it back. Comment on the issue:
   `Spec: <path> (PR #<pr>). Waiting for approval.`
6. **Stop.** Show the spec to the maintainer. Only the maintainer sets Approved. If the maintainer asks
   for changes, revise the spec in a follow-up PR and keep the status at Spec review.

## 3. An Approved story: implement

1. Set the status to **In progress** and read it back. Find the spec: the issue comment from step 2.5,
   else the milestone's spec in `iterations.specDir`. Read it completely; the spec is the contract.
2. Take a slot: `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Take <git.featurePrefix><slug>` (PowerShell)
   or `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --take <git.featurePrefix><slug>` (bash). Work in that
   worktree; `-Release N` after the merge. Without slots, `git switch -c` from up-to-date `origin/<git.baseBranch>`.
   Respect `parallel.maxAgents` and `parallel.hotFiles`.
3. Turn each acceptance criterion into a test named for the behaviour it protects. Implement. Follow
   `verification.benchRule` when set.
4. Run the check (`/nightmill:check`). If the change touches any of `verification.manualCheckPaths`,
   also do `verification.manualCheckText` and note the steps for the PR.
5. Add the CHANGELOG entry for iteration N and change the spec's status line to
   `Status: delivered in iteration <N> (PR #<pr>)`. Rebase on `origin/<git.baseBranch>`; on a CHANGELOG
   conflict keep both entries in iteration order.
6. Open a PR titled `Iteration <N>: <what> (#<issue>)` with `Closes #<issue>` and a "How verified"
   section (tests, the check, the manual check). Set the status to **Review**, read it back, and check
   it again after a minute (board automation may have changed it).
7. Enable auto-merge: `gh pr merge <pr> <git.mergeFlags>`, because the spec was approved. Do **not**,
   and say why in the PR, when the PR changes one of `escalation.storyTriggers`, is partial, or skipped
   a required manual check.
8. If the story ends up only partly done: file the rest as a new story under the same epic (`/story`),
   link both issues, say so in the PR. The PR still closes the old issue; never tick criteria that were not met.

## Hard rules

Never set Ready or Approved (only the maintainer does). Never close an epic. Never delete files
without asking. Never merge any other way than `gh pr merge <pr> <git.mergeFlags>` (a plain
`gh pr merge` would bypass the checks).
