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
   `git switch -c <git.fixPrefix><number>-<slug>` from up-to-date `origin/<git.baseBranch>`. Right after the take
   report the step `slot-taken` (see "Reporting the steps" below); from here on every step is reported there.
4. **Have the bug reproduced first, then hand the fix to the fixer.** The session
   never writes the test or the code itself. A subagent in the role `tester` writes a regression test that fails for
   the reason in the issue (see "The tester" below); then a subagent in the role `fixer` fixes the cause with the
   smallest diff and makes that test pass (see "The fixer" below): for each, count the agents, launch it, read its
   result. The fixer corrects a spec's text when the fix changes a rule or number the spec states, adds no CHANGELOG
   entry, and runs the check. A bug the tester cannot reproduce is not fixed in this run.
5. **Have the fix reviewed, then do the manual check.** A different agent, the `codeReviewer`, reviews the fix and
   the fixer fixes what is blocking (see "The code review" below). A change under any of
   `verification.manualCheckPaths` also gets `verification.manualCheckText`, done by the session (the fixer runs the
   check, not this).
6. **Open a PR** titled `fix: <what> (#N)` with `Fixes #N`, directly under it the line
   `Fixed by the fixer role on <model>.` (`<model>` is the exact string passed as `model` in the fixer's Agent call),
   and the sections Cause, Fix and How verified, and the `## Review` section of "The code review" (step 5 there).
   How verified is written from the tester's and the fixer's result blocks (the test, the check) and the manual
   steps, and begins with:

   ````
   Reproduced first by the tester role on <model>, failing before the fix:
   - <the tester's Criteria line, as it wrote it>
   - <each of the tester's Failing lines, as it wrote them>

   ```diff
   <git -C <slot> diff origin/<git.baseBranch>..HEAD -- <tester files>>
   ```
   ````

   `<model>` there is the exact string passed as `model` in the tester's Agent call. When the diff is longer than 60
   lines, the fenced block is replaced by
   `The test's diff is longer than 60 lines: see <tester files, comma-separated> in the change.`
   Set the status to Review and read it back. For a complete fix enable auto-merge (`gh pr merge <pr> <git.mergeFlags>`); not for a partial fix, one
   that has blocking review findings left, or one that touches `escalation.storyTriggers` (that is a story).

## Reporting the steps

A slot records what its agent is doing, so `/status` shows it `running` or `stalled`. A report is one call of the
shell in use, with N the slot number the take printed (`Slot N is yours`):
`"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Report <step> -Slot <n> -Skill fix -Role <role>` or
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --report <step> --slot <n> --skill fix --role <role>`. A report that
fails never stops the run: go on, and name a failed report you made yourself once, in your final message. A report
is not a board status. A run without slots (no `worktrees`, `git switch -c` in a single checkout) took no slot and
reports nothing. In batch mode each bug reports to its own slot.

| When | Role | Step |
|---|---|---|
| right after the take (step 3) | `session` | `slot-taken` |
| just before the tester is launched (step 4, "The tester") | `tester` | `write-tests` |
| just before the fixer is launched (step 4) | `fixer` | `fix` |
| the fixer, before its step 1 / step 2 | `fixer` | `test` / `code` |
| the fixer, before every run of the check | `fixer` | `check` |
| the fixer, before its commit | `fixer` | `commit` |
| just before each launch of the code reviewer | `codeReviewer` | `code-review` |
| just before the launch of fix round k | `fixer` | `fix-round-<k>` |
| the manual check (step 5), when it applies | `session` | `manual-check` |
| opening the pull request (step 6) | `session` | `pull-request` |
| after step 6 | `session` | `done` |
| on any `Stopped:` line, or a bug skipped in batch mode, after the take | `session` | `stopped` |

The fixer reports its own steps (the paragraph in its prompt); the session reports the others, the tester's and the
code review too: the tester's prompt carries no report command, and the code reviewer cannot run a script. A
`Stopped:` line of "The tester" reports `stopped` like every other. A slot whose last step is `done` waits for its merge and shows
`stalled` once `worktrees.stalledAfterMinutes` has passed, until it is freed.

## The tester

The session keeps the pick, the decision that it is a bug, the board, the slot and every hard rule; the regression test
is the tester's.

1. **Count.** Before the launch count the agents running, as for the fixer (the live agent limit from
   `slot.ps1 -Capacity -Porcelain` or `slot.sh --capacity --porcelain`, else `parallel.maxAgents`). At the limit wait for
   one to end and say what you wait for; the session never writes the test itself instead. The tester is one agent (its
   agent file has no `Agent` tool), and it has returned before the fixer is launched, so a bug runs at most one producer
   at a time.
2. **Launch.** One Agent call: `subagent_type` `nightmill:tester`, not a fork, not nightmill:worker, with the `model`
   that **Agent roles and models** in the `workflow` skill gives the role `tester` (`roles.tester.model`, else the schema
   default), passed explicitly, and the prompt below. When the model cannot be used, stop with the line of that section
   for `tester` (`Stopped: the tester role cannot run on <model>: <the reason>. Nothing was started on another model.`)
   and add that the status of #<issue> is In progress and the slot is taken; no fixer is launched.
3. **Read the result.** The subagent's last message ends with the block of `agents/tester.md`. Record `<tester files>`,
   the paths of `git -C <slot> status --porcelain --untracked-files=all` (the path after the two status letters; every
   file is listed, not only its directory), then check, in this order:
   - `git -C <slot> log origin/<git.baseBranch>..HEAD` is empty (the tester committed nothing), and `<tester files>`
     is not empty; the one exception is a `Result: partial` whose `Criteria` line is `not tested`, where nothing is
     written and `<tester files>` is empty;
   - every path of `<tester files>` is a test path by this line, with `iterations.specDir`, `iterations.decisionsDir`
     and `iterations.changelog` read from the configuration:

     `Test paths: a directory in the path is named test, tests, __tests__, spec, testdata, fixtures or __fixtures__, or the file name starts with test_ or test-, or contains _test. .test. -test. _spec. .spec. Test. or Tests.; never under iterations.specDir or iterations.decisionsDir, never iterations.changelog.`

   Then, in this order:
   - A path that is not a test path: print
     `Stopped: the tester changed files that are not tests: <the paths, comma-separated>` with the branch and the slot.
   - `Result: failed`, no result block, an error, a commit, or no changed path outside that exception: print
     `Stopped: the tester returned failed: <Left, or the reason>` with the branch and the slot.
   - `Result: partial`: the bug is not reproduced. Print
     `Stopped: the tester could not reproduce bug #<issue>: <the reason>. The fixer was not started.` with the branch
     and the slot. `<the reason>` is the `not tested:` reason of the `Criteria` line, else every `Failing` line that is
     not `fails:`, joined with `; `.
   - `Result: complete`, and both checks hold: the bug is reproduced; go on with "The fixer". Keep the tester's
     `Criteria` and `Failing` lines, `<tester files>` and the model passed, for the fixer's prompt and the pull request.

   On any of the three `Stopped:` lines: launch no fixer, open no pull request, leave the status at In progress and the
   slot taken, the tester's files uncommitted in the slot; commit, push and revert nothing. Do not start another agent on
   this bug in this run; never set Ready. In "Batch mode" each of the three is a skip of that bug (see there).

The prompt, with the placeholders filled in (the body verbatim; `<title>` without a leading `[Bug] ` in the criterion):

```markdown
Write the failing regression test for bug #<issue> "<title>" in <owner>/<repo>.

The slot: <absolute slot path>, branch <branch>. Use that absolute path for every file and `git -C <slot path>` for
every git command; your working directory is not the slot. The branch holds no fix for this bug yet.
Do not commit: leave the test uncommitted in the slot.

This is a bug, not a story, and it has no spec of its own. In your instructions read "story" as this bug, "the spec" and
"the acceptance criteria" as the bug report and the one criterion below, and "the implementer" as the fixer.

The one acceptance criterion: 1. <title> is fixed.
The bug report, in full: <body>.
The spec the bug touches, if any: <path in the slot, or "none"> (read it; it states the rule the bug breaks).

The test reproduces the bug: it follows the report's "How to reproduce" as closely as a test can, expects what the
report says should happen, and fails because what the report says happens does happen. A test that passes now does not
reproduce the bug, and neither does one that fails for another reason; report either under `Failing` as your
instructions say. A bug you cannot reproduce with a test is reported, never forced: do not weaken or bend a test to make
it fail.

The project's testing rules:
- the check: <verification.check>
- the bench rule: <verification.benchRule, or "none">
- the invariants: <config invariants, one per line>

In this project iterations.specDir is <iterations.specDir>, iterations.decisionsDir is <iterations.decisionsDir> and
iterations.changelog is <iterations.changelog>.

End with the result block of your instructions, and nothing after it.
```

## The fixer

The session keeps the pick, the decision that it is a bug (step 2, before any launch; the fixer is never asked to
decide it), the status, the slot, the manual check, the pull request and every hard rule. The regression test is the
tester's; the fix, and the commit of both, are the fixer's. The fixer is launched only after "The tester" went on.

1. **Count.** Before the launch count the agents running (the workflow rule: subagents, slot builds, your own
   builds). At the agent limit (read it now, as the workflow skill says: `slot.ps1 -Capacity -Porcelain` or
   `slot.sh --capacity --porcelain`, the live value, else `parallel.maxAgents`) wait for one to end and say what you
   wait for; the session never writes the code itself instead. The fixer is one agent (its prompt forbids launching others).
2. **Launch.** One Agent call: a fresh agent (omit `subagent_type`; not nightmill:worker), not a fork, with the
   `model` that **Agent roles and models** in the `workflow` skill gives the role `fixer` (`roles.fixer.model`,
   else the schema default), passed explicitly, and the prompt below. When the model cannot be used, stop with the
   line of that section for `fixer`
   (`Stopped: the fixer role cannot run on <model>: <the reason>. Nothing was started on another model.`) and add
   that the status of #<issue> is In progress and the slot is taken.
3. **Read the result.** The subagent's last message ends with the result block below. Check the branch:
   `git -C <slot> status --short` is empty, `git -C <slot> log origin/<git.baseBranch>..HEAD` is not, and every path
   of `<tester files>` is listed by `git -C <slot> diff --name-only origin/<git.baseBranch>..HEAD` (the test was
   committed, not dropped). When any of the three checks fails, it is handled as `Result: failed`: print
   `Stopped: the fixer returned failed: <Left, or the check that failed>` with the branch and the slot. The same holds
   when "The code review" reads the result of a fix round. Do not re-run the whole check to verify it; CI is the
   independent run.
   - `Result: complete`: go on with step 5.
   - `Result: partial`: go on with step 5; the PR says what is left and auto-merge is not enabled.
   - `Result: failed`, no result block, or an error: open no pull request. Print
     `Stopped: the fixer returned failed: <Left>` with the branch and the slot, leave the status at In progress,
     commit and push nothing. Do not start another agent on this bug in this run; never set Ready.

The prompt, with the placeholders filled in (the issue body verbatim; the report command with the absolute path of the
script, as `${CLAUDE_PLUGIN_ROOT}` expands in the session; a fix round's prompt carries it too, so inside a fix round
the step `fix-round-<k>` is followed by the steps of the prompt):

```markdown
You are the fixer for bug #<issue> "<title>" in <owner>/<repo>.

Work only in the slot at <absolute slot path>, on branch <branch>. Use that absolute path for every file and
`git -C <slot path>` for every git command; your working directory is not the slot.

The bug, in full: <body>.

The tester has written a regression test for this bug into the slot's working tree and has not committed it; it
fails for the reason in the issue, because the fix does not exist yet. It is at: <tester files, one per line>. The
test: <the tester's Criteria line>. How it fails now: <the tester's Failing lines>.
Commit it together with your fix, once the check is green. A fix that does not make this test pass is not a fix: then
commit nothing, report `failed` and say why under Left.
In a fix round the test may already be committed with your earlier fix: then run it and the check, and fix exactly
the blocking findings.

Do this:
1. Run the tester's test and watch it fail for the reason in the issue.
2. Fix the cause, not the symptom, with the smallest diff that does it. <verification.benchRule, when set>
3. If the fix changes a rule or number that a spec states, correct that spec's text. Do not add a CHANGELOG entry.
4. Run the check: <verification.check>. When it is green, commit the work on the branch with a message that
   names the bug. Never commit red.

Report your progress with `<the report command of the shell in use, with --slot <n> --skill fix --role fixer
(PowerShell: -Slot, -Skill, -Role) and the step as the value of --report / -Report>`: before step 1 (`test`), before
step 2 (`code`), before every run of the check (`check`) and before the commit (`commit`). It writes only the slot's
marker outside the repository and is not a status; when it fails, go on.

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

- **One producer at a time.** Each bug's tester and fixer launches are counted; the tester has returned before the
  fixer is launched, and the next bug starts only after the previous bug's fixer has returned or its run stopped. A
  `failed` fixer, and each `Stopped:` line of "The tester" except a model that cannot be used, is a skip of that bug
  by the rule below. A model that cannot be used, for the tester or the fixer, is **not** a skip: it ends the whole run with the
  `Stopped:` line, because every later bug would fail the same way, and the report lists the bugs not started.
- **Order and cap.** All open `labels.bug` items with status Ready, by `board.priorities` (highest first),
  then by issue number; no ties to ask about. At most 5 per run; the rest go in the report for the next run.
- **One branch per bug, each from up-to-date `origin/<git.baseBranch>`**, not on top of the previous fix.
  After a bug's PR is open, switch back to the base branch, `git pull --ff-only`, and start the next.
  Nothing waits for a merge. If a bug touches a file an earlier PR of this run changed, say so in its PR
  ("overlaps #N, will conflict until that merges").
- **A bug that cannot be done is skipped, not stopped on.** Skip it when step 2 says it is a story (report
  "needs a story", no status change), when the tester cannot reproduce it
  (`Stopped: the tester could not reproduce bug #`), when the check is still red after three honest attempts, or
  when the fix grows into one of `escalation.storyTriggers`. Commit what exists to the local branch (do not push).
  For a bug skipped at the tester, commit nothing: the tester's files stay uncommitted in the bug's slot; in a single
  checkout without slots set them aside with
  `git stash push --include-untracked -m "Tester files for #<issue>: <title>" -- <tester files>` before switching
  back to the base branch. Leave the status as it is (never set Ready), and say why in the report.
- **The whole run stops** if the working tree is dirty at the start, `git` or `gh` fails on authentication
  or network, or the check is red on a clean base branch (that is not a bug fix: report it).
- **Never** merge any other way than with `git.mergeFlags` on a complete fix, push to the base branch,
  close an issue by hand (the PR's `Fixes #N` does), or edit an issue.
- **End with a table:** issue, PR (or "skipped"), one-line cause (`not reproduced: <the reason>` for a bug skipped
  at the tester), and what was verified. Name the manual
  check as not done where it could not be done.

## Hard rules

Never set Ready or Approved (only the maintainer does). Never close an epic. Never delete files without
asking. Never run a plain `gh pr merge` (it would bypass the checks).
