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
- Otherwise list the board: `gh project item-list <project> --owner <owner> --limit 200 --format json --jq '.items[] | [.content.number, .content.type, .status, .priority, ((.labels // []) | join(",")), .content.title] | @tsv'`
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
3. **Hand the coding to the implementer.** The session never writes the code itself; the tests and the code are
   written by a subagent in the role `implementer` (see "The implementer" below): count the agents, launch it,
   read its result.
4. **Have the change reviewed** by a different agent, the `codeReviewer` (see "The code review" below), and let
   the implementer fix what is blocking. Then, if the change touches any of `verification.manualCheckPaths`, do
   `verification.manualCheckText` yourself (the subagent runs the check, not this) and note the steps for the PR.
5. Add the CHANGELOG entry for iteration N and change the spec's status line to
   `Status: delivered in iteration <N> (PR #<pr>)`. Rebase on `origin/<git.baseBranch>`; on a CHANGELOG
   conflict keep both entries in iteration order.
6. Open a PR titled `Iteration <N>: <what> (#<issue>)` with `Closes #<issue>`, directly under it the line
   `Written by the implementer role on <model>.` (`<model>` is the exact string passed as `model` in the
   Agent call), and a "How verified" section written from the result block (tests, the check) and your own
   manual check, and the `## Review` section of "The code review" (step 5 there). Set the status to **Review**, read it
   back, and check it again after a minute (board automation may have changed it).
7. Enable auto-merge: `gh pr merge <pr> <git.mergeFlags>`, because the spec was approved. Do **not**,
   and say why in the PR, when the PR changes one of `escalation.storyTriggers`, is partial, skipped
   a required manual check, or has blocking review findings left.
8. If the story ends up only partly done: file the rest as a new story under the same epic (`/story`),
   link both issues, say so in the PR. The PR still closes the old issue; never tick criteria that were not met.

## The implementer

The session keeps the picking line, the board statuses, the slot, the manual check, the CHANGELOG entry, the
pull request and every hard rule. The tests and the code are the implementer's.

1. **Count.** Before the launch count the agents running (the workflow rule: subagents, slot builds, your own
   builds). At `parallel.maxAgents` wait for one to end and say what you wait for; the session never writes the
   code itself instead. The implementer is one agent (its prompt forbids launching others).
2. **Launch.** One Agent call: a fresh agent (omit `subagent_type`; not nightmill:worker), not a fork, with the
   `model` that **Agent roles and models** in the `workflow` skill gives the role `implementer`
   (`roles.implementer.model`, else the schema default), passed explicitly, and the prompt below. When the model
   cannot be used, stop with the line of that section for `implementer`
   (`Stopped: the implementer role cannot run on <model>: <the reason>. Nothing was started on another model.`)
   and add that the status of #<issue> is In progress and the slot is taken.
3. **Read the result.** The subagent's last message ends with the result block below. Check the branch:
   `git -C <slot> status --short` is empty and `git -C <slot> log origin/<git.baseBranch>..HEAD` is not. Do not
   re-run the whole check to verify it; CI is the independent run.
   - `Result: complete`: go on with step 4.
   - `Result: partial`: go on with step 4; steps 7 and 8 apply (no auto-merge, the rest filed as a new story,
     the criteria that were not met are not ticked).
   - `Result: failed`, no result block, or an error: open no pull request. Print
     `Stopped: the implementer returned failed: <Left>` with the branch and the slot, leave the status at
     In progress, commit and push nothing. Do not start another agent on this story in this run; never set Ready.

The prompt, with the placeholders filled in (the criteria and the body verbatim):

```markdown
You are the implementer for story #<issue> "<title>" in <owner>/<repo>.

Work only in the slot at <absolute slot path>, on branch <branch>. Use that absolute path for every file and
`git -C <slot path>` for every git command; your working directory is not the slot.

Read the spec <path in the slot> completely: it is the contract. The acceptance criteria of the issue are:
<the criteria, verbatim>. The issue body, in full: <body>.

Do this:
1. Turn each acceptance criterion into a test named for the behaviour it protects, and watch it fail.
2. Implement until the tests pass. <verification.benchRule, when set>
3. Run the check: <verification.check>. When it is green, commit the work on the branch with a message that
   names the story. Never commit red.

Do not push, do not open or edit a pull request, do not touch the board, any issue or any status, do not edit
`CHANGELOG.md` or the spec's status line, do not create or switch branches, do not delete files (report them
under Left instead), and do not launch other agents. If the spec is unclear or wrong, do not decide it
yourself: stop that part and say so under Left.

End your last message with exactly this block:

Result: complete | partial | failed
Criteria: <one line per acceptance criterion: met or not met, and the test that protects it>
Tests: <the tests added or changed>
Check: <the check's last summary line>, green or red
Commits: <hash and subject, one per line; none>
Manual check: needed | not needed (<the verification.manualCheckPaths touched>)
Left: <what is not done and why; nothing>
```

## The code review

After the implementer's result (not `failed`) and before the manual check, a different agent reviews the change. The
findings format, the rounds and the pairing rule are in **Findings and fix rounds** in the `workflow` skill.

1. **The pairing.** Run `validate-config` of the shell in use on the project's config
   (`"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config <project>/.claude/nightmill.json`, or
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" <project>/.claude/nightmill.json`). When it reports a line
   on `roles.codeReviewer.model` with the text `ranks below`, stop with
   `Stopped: the codeReviewer ranks below the implementer: <the text of that line>. Nothing was reviewed; the status of #<issue> is In progress and the slot is taken.`
   (the line may name the other producer, then name it). When the validator cannot run (exit code 2, missing
   script), stop with `Stopped: the pairing could not be checked: <the reason>. Nothing was reviewed.` A reviewer
   model that is not in `models.ranking` is only a warning of the validator and does not stop the run.
2. **Count and launch.** Count the agents as for the implementer. One Agent call: `subagent_type`
   `nightmill:code-reviewer`, not a fork, with the `model` that **Agent roles and models** gives `codeReviewer`
   (`roles.codeReviewer.model`, else the schema default), passed explicitly. When the model cannot be used, stop with
   that section's line for `codeReviewer`, naming the status and the slot.
3. **The prompt**, filled in by the session. It carries facts, not the implementer's own account (its `Criteria`,
   `Left` and `Decisions` lines): the reviewer shares no context with the implementer.

   ```markdown
   Review the change on branch <branch> in the checkout at <absolute slot path> (use that path for every file you
   read) for story #<issue> "<title>".

   The acceptance criteria of the issue: <verbatim>.
   The spec: <path in the slot> (read it).
   The invariants of the project: <config invariants, one per line>.
   The implementer's check: <its Check: line>.

   The change, as `git diff <base>...<branch>`: <the diff; when it is longer than 2000 lines, the --stat and the
   instruction to read the files>.

   End with the findings block of the workflow skill, and nothing after it.
   ```
4. **Read the block.** `no findings`, or advisory findings only: go on and keep the advisory lines. With blocking
   findings, while fewer than `review.maxFixRounds` fix rounds have been used: launch the fix (a fresh implementer, as
   in "The implementer", with its prompt and, added at the end, "Fix exactly these blocking findings and nothing
   else, run the check, commit": the blocking lines), read its `Result:` block as before (`failed` stops the run as
   there), and review again from step 2 (the pairing is checked once, not again). No valid block, or an error: stop
   with `Stopped: the code review could not be had: <the reason>. Nothing was opened.`
5. **After the last review: the `## Review` section.** Build the section that **Findings and fix rounds** describes
   (the paragraph "The pull request" of the `workflow` skill) from what you held during the run: the blocks of all
   reviews, the fix rounds used and the models you passed to the Agent calls. `Findings still open` are those of the
   last review, as the reviewer wrote them; `Findings fixed` are the blocking findings sent back in an earlier round
   and not repeated in the last review with the same file and text. Put the section after "How verified" and remove
   nothing else from the body. When the last review has a blocking finding, do **not** enable auto-merge and say, where
   step 7 says why auto-merge was withheld,
   `Auto-merge is not enabled: blocking review findings are still open (see Review).`
   Otherwise the rule of step 7 decides, unchanged. Your final message to the maintainer says whether auto-merge is
   on and, if not, that blocking findings are open.

A `partial` result is reviewed like a complete one.

## Hard rules

Never set Ready or Approved (only the maintainer does). Never close an epic. Never delete files
without asking. Never merge any other way than `gh pr merge <pr> <git.mergeFlags>` (a plain
`gh pr merge` would bypass the checks).