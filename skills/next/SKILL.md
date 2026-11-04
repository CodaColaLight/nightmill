---
name: next
description: Implement the next Approved story from the board - slot, tests, code, check, PR, auto-merge. Use when asked to pick up the next story, implement an approved spec, or start an approved story. Writing the spec for a Ready story is /spec.
argument-hint: [issue-number]
disable-model-invocation: true
---

Implement the next Approved story from the board: $ARGUMENTS

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json`

Read the configuration first. Below, *the maintainer* is `maintainer.name`; `<owner>`, `<repo>` and
`<project>` come from `github`; status names from `board.statuses`; label names from `labels`. Where this
text and the configuration disagree, the configuration wins. The process rules are in the `workflow`
skill of this plugin; this skill is the step list.

## 1. Pick the issue

Follow **Picking an issue** in the `workflow` skill with the status **Approved** (`board.statuses.approved`).

- If `$ARGUMENTS` holds an issue number, take that issue; refuse when it is not at Approved.
- Otherwise list the board: `gh project item-list <project> --owner <owner> --limit 200 --format json`
  and take the highest-priority Approved story that is not an epic and not a bug (bugs go through `/fix`).
- Nothing Approved: change nothing and never start a spec. List the Ready stories, one line each as
  `#N "<title>" (<priority>)` in priority order, then print `Nothing is Approved. Run /spec N to write a spec.`
  With no Ready story either, print `Nothing is Approved or Ready.` Then stop.
- Print the line `Picking #N "<title>": <status>, <priority>, <reason>` before the first change.
- Read the issue with `gh issue view N --json number,title,labels,body,milestone,comments`, its parent epic,
  and every spec and decision either references.

## 2. Implement the approved story

1. Set the status to **In progress** and read it back (`gh project item-list` for the item id,
   `gh project field-list` for the field and option ids, then `gh project item-edit`). Find the spec: the
   issue comment `/spec` left (`Spec: <path> (PR #<pr>)`), else the milestone's spec in
   `iterations.specDir`. Read it completely; the spec is the contract. The iteration number N is the one
   in the spec's file name.
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