---
name: spec
description: Write the spec for a Ready story as its own PR and stop at Spec review. Use when asked to spec a story, write the spec for an issue, or start the next Ready story. Implementing an Approved story is /next.
argument-hint: [issue-number]
disable-model-invocation: true
---

Write the spec for a Ready story: $ARGUMENTS

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json`

Read the configuration first. Below, *the maintainer* is `maintainer.name`; `<owner>`, `<repo>` and
`<project>` come from `github`; status names from `board.statuses`; label names from `labels`. Where this
text and the configuration disagree, the configuration wins. The process rules are in the `workflow`
skill of this plugin; this skill is the step list.

## 1. Pick the issue

Follow **Picking an issue** in the `workflow` skill with the status **Ready** (`board.statuses.ready`).

- If `$ARGUMENTS` holds an issue number, take that issue; refuse when it is not at Ready.
- Otherwise list the board: `gh project item-list <project> --owner <owner> --limit 200 --format json --jq '.items[] | [.content.number, .content.type, .status, .priority, ((.labels // []) | join(",")), .content.title] | @tsv'`
  and take the highest-priority Ready story that is not an epic and not a bug (bugs go through `/fix`).
- Nothing Ready: print `Nothing is Ready.`, add `Approved: #N ... Run /next to implement.` when Approved
  stories exist, change nothing and stop.
- Print the line `Picking #N "<title>": <status>, <priority>, <reason>` before the first change.
- Read the issue with `gh issue view N --json number,title,labels,body,milestone,comments`, its parent epic,
  and every spec and decision either references.

## 2. Write the spec, then stop

1. Set the status to **Spec** right away and read it back (`gh project item-list` for the item id,
   `gh project field-list` for the field and option ids, then `gh project item-edit`). Not In progress:
   nothing is being implemented yet.
2. Pick the iteration number N: the higher of the latest entry in `iterations.changelog` and the highest
   milestone matching `iterations.milestonePattern` (`gh api repos/<owner>/<repo>/milestones?state=all --paginate`;
   another task may have claimed a number that is not merged yet), plus 1. Create the
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
6. **Stop.** Show the spec to the maintainer. Only the maintainer sets Approved; then `/next` implements it.
   If the maintainer asks for changes, revise the spec in a follow-up PR and keep the status at Spec review.

## Hard rules

Never set Ready or Approved (only the maintainer does). Never close an epic. Never delete files
without asking. Never merge any other way than `gh pr merge <pr> <git.mergeFlags>` (a plain
`gh pr merge` would bypass the checks).