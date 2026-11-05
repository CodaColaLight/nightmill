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
4. **Hand the fix to the fixer.** The session never writes the code itself; the failing test and the fix are
   written by a subagent in the role `fixer` (see "The fixer" below): count the agents, launch it, read its
   result. It writes the test that fails for the reason in the issue first, fixes the cause with the smallest
   diff, corrects a spec's text when the fix changes a rule or number the spec states, adds no CHANGELOG entry,
   and runs the check.
5. **Have the fix reviewed, then do the manual check.** A different agent, the `codeReviewer`, reviews the fix and
   the fixer fixes what is blocking (see "The code review" below). A change under any of
   `verification.manualCheckPaths` also gets `verification.manualCheckText`, done by the session (the fixer runs the
   check, not this).
6. **Open a PR** titled `fix: <what> (#N)` with `Fixes #N`, directly under it the line
   `Fixed by the fixer role on <model>.` (`<model>` is the exact string passed as `model` in the Agent call),
   and the sections Cause, Fix and How verified, written from the result block (the test, the check) and the
   manual steps, and the `## Review` section of "The code review" (step 5 there). Set the status to Review and read it
   back. For a complete fix enable auto-merge (`gh pr merge <pr> <git.mergeFlags>`); not for a partial fix, one
   that has blocking review findings left, or one that touches `escalation.storyTriggers` (that is a story).

## The fixer

The session keeps the pick, the decision that it is a bug (step 2, before any launch; the fixer is never asked to
decide it), the status, the slot, the manual check, the pull request and every hard rule. The failing test and
the fix are the fixer's.

1. **Count.** Before the launch count the agents running (the workflow rule: subagents, slot builds, your own
   builds). At `parallel.maxAgents` wait for one to end and say what you wait for; the session never writes the
   code itself instead. The fixer is one agent (its prompt forbids launching others).
2. **Launch.** One Agent call: a fresh agent (omit `subagent_type`; not nightmill:worker), not a fork, with the
   `model` that **Agent roles and models** in the `workflow` skill gives the role `fixer` (`roles.fixer.model`,
   else the schema default), passed explicitly, and the prompt below. When the model cannot be used, stop with the
   line of that section for `fixer`
   (`Stopped: the fixer role cannot run on <model>: <the reason>. Nothing was started on another model.`) and add
   that the status of #<issue> is In progress and the slot is taken.
3. **Read the result.** The subagent's last message ends with the result block below. Check the branch:
   `git -C <slot> status --short` is empty and `git -C <slot> log origin/<git.baseBranch>..HEAD` is not. Do not
   re-run the whole check to verify it; CI is the independent run.
   - `Result: complete`: go on with step 5.
   - `Result: partial`: go on with step 5; the PR says what is left and auto-merge is not enabled.
   - `Result: failed`, no result block, or an error: open no pull request. Print
     `Stopped: the fixer returned failed: <Left>` with the branch and the slot, leave the status at In progress,
     commit and push nothing. Do not start another agent on this bug in this run; never set Ready.

The prompt, with the placeholders filled in (the issue body verbatim):

```markdown
You are the fixer for bug #<issue> "<title>" in <owner>/<repo>.

Work only in the slot at <absolute slot path>, on branch <branch>. Use that absolute path for every file and
`git -C <slot path>` for every git command; your working directory is not the slot.

The bug, in full: <body>.

Do this:
1. Write the test that fails for the reason in the issue first, named for the behaviour it protects, and watch it
   fail.
2. Fix the cause, not the symptom, with the smallest diff that does it. <verification.benchRule, when set>
3. If the fix changes a rule or number that a spec states, correct that spec's text. Do not add a CHANGELOG entry.
4. Run the check: <verification.check>. When it is green, commit the work on the branch with a message that
   names the bug. Never commit red.

Do not push, do not open or edit a pull request, do not touch the board, any issue or any status, do not create
or switch branches, do not delete files (report them under Left instead), and do not launch other agents. Do not
decide that the bug is a story: when the fix needs one of <escalation.storyTriggers> or a design choice, stop and
say so under Left. A different problem you notice is not yours to fix: name it under Left.

End your last message with exactly this block:

Result: complete | partial | failed
Cause: <one line>
Fix: <one line>
Test: <the test's name, and how it failed before the fix>
Check: <the check's last summary line>, green or red
Commits: <hash and subject, one per line; none>
Manual check: needed | not needed (<the verification.manualCheckPaths touched>)
Left: <what is not done and why; nothing>
```

## The code review

After the fixer's result (not `failed`) and before the manual check, a different agent reviews the fix. The findings
format, the rounds and the pairing rule are in **Findings and fix rounds** in the `workflow` skill.

1. **The pairing.** Run `validate-config` of the shell in use on the project's config
   (`"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config <project>/.claude/nightmill.json`, or
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" <project>/.claude/nightmill.json`). When it reports a line
   on `roles.codeReviewer.model` with the text `ranks below`, stop with
   `Stopped: the codeReviewer ranks below the fixer: <the text of that line>. Nothing was reviewed; the status of #<issue> is In progress and the slot is taken.`
   (the line may name the other producer, then name it). When the validator cannot run (exit code 2, missing
   script), stop with `Stopped: the pairing could not be checked: <the reason>. Nothing was reviewed.` A reviewer
   model that is not in `models.ranking` is only a warning of the validator and does not stop the run.
2. **Count and launch.** Count the agents as for the fixer. One Agent call: `subagent_type`
   `nightmill:code-reviewer`, not a fork, with the `model` that **Agent roles and models** gives `codeReviewer`
   (`roles.codeReviewer.model`, else the schema default), passed explicitly. When the model cannot be used, stop with
   that section's line for `codeReviewer`, naming the status and the slot.
3. **The prompt**, filled in by the session. It carries facts, not the fixer's own account (its `Cause`, `Fix` and
   `Left` lines): the reviewer shares no context with the fixer.

   ```markdown
   Review the fix on branch <branch> in the checkout at <absolute slot path> (use that path for every file you read)
   for bug #<issue> "<title>".

   The bug report: <verbatim>.
   The spec the bug touches, if any: <path in the slot> (read it).
   The invariants of the project: <config invariants, one per line>.
   The fixer's check: <its Check: line>.

   The change, as `git diff <base>...<branch>`: <the diff; when it is longer than 2000 lines, the --stat and the
   instruction to read the files>.

   End with the findings block of the workflow skill, and nothing after it.
   ```
4. **Read the block.** `no findings`, or advisory findings only: go on and keep the advisory lines. With blocking
   findings, while fewer than `review.maxFixRounds` fix rounds have been used: launch the fix (a fresh fixer, as in
   "The fixer", with its prompt and, added at the end, "Fix exactly these blocking findings and nothing else, run
   the check, commit": the blocking lines), read its `Result:` block as before (`failed` stops the run as there), and
   review again from step 2 (the pairing is checked once, not again). No valid block, or an error: stop with
   `Stopped: the code review could not be had: <the reason>. Nothing was opened.` In "Batch mode" this is a stop of
   that bug, handled like a `failed` fixer (skipped), except for a model that cannot be used, which ends the run.
5. **After the last review: the `## Review` section.** Build the section that **Findings and fix rounds** describes
   (the paragraph "The pull request" of the `workflow` skill, with `Author: fixer role on <model>`) from what you held
   during the run: the blocks of all reviews, the fix rounds used and the models you passed to the Agent calls.
   `Findings still open` are those of the last review, as the reviewer wrote them; `Findings fixed` are the blocking
   findings sent back in an earlier round and not repeated in the last review with the same file and text. Put the
   section after "How verified" and remove nothing else from the body. When the last review has a blocking finding,
   do **not** enable auto-merge and say, where step 6 says why auto-merge was withheld,
   `Auto-merge is not enabled: blocking review findings are still open (see Review).`
   Otherwise the rule of step 6 decides, unchanged. Your final message to the maintainer says whether auto-merge is
   on and, if not, that blocking findings are open.

A `partial` result is reviewed like a complete one.

## Batch mode: `/fix all`

Works through every Ready bug, one after another, without asking the maintainer anything. Steps 1 to 6
are the same for each bug, with these differences:

- **One fixer at a time.** Each bug's launch is counted; the next bug starts only after the previous fixer has
  returned. A `failed` result is a skip of that bug by the rule below. A model that cannot be used is **not** a
  skip: it ends the whole run with the `Stopped:` line, because every later bug would fail the same way, and the
  report lists the bugs not started.
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
