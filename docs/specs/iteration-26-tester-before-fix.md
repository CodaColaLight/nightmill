# Iteration 26: a tester agent writes the failing regression test before /fix fixes

Status: draft, awaiting approval (#43)

Story: #43, epic #41 (Independent test writing). Puts the tester of iteration 25 (`agents/tester.md`) in front of the
fixer in `skills/fix/SKILL.md`: after the bug is In progress and the slot is taken, and before the fixer is launched, a
`tester` subagent on the model the configuration gives the role writes a regression test from the bug report into the
slot's working tree, runs it and confirms that it fails for the reason the report gives; it commits nothing. The session
checks that the tester left only test files and fixtures and that it reproduced the bug; a bug it cannot reproduce
stops the run before any fixer starts. The fixer then makes that test pass and commits it together with the fix, once
the check is green. Changes `skills/fix/SKILL.md`, the `description:` line of `agents/tester.md`, one table row of
`skills/workflow/SKILL.md`, `README.md`, `tests/lint.sh` and `CHANGELOG.md`.

**Not a story trigger.** `roles.tester.model` exists since iteration 10 (schema default `sonnet`), so no config key is
added, renamed or removed. The slot marker, the status flow and who sets a status do not change; writing the
regression test happens while the bug is In progress. The rule "never commit red" does not change anywhere: no red
commit is ever made (decision 5). The PR may auto-merge. The change touches `skills` and `agents`, so the manual check of
`verification.manualCheckPaths` applies.

**Order.** #42 (iteration 25, the tester agent) and #35 (iteration 13, the fixer subagent) are delivered and on `main`.
The changes below are written against `skills/fix/SKILL.md` on `main` today: steps 1 to 6, the sections "Reporting the
steps", "The fixer", "The code review", "Batch mode: `/fix all`" and "Hard rules". This iteration renumbers none of those
steps, so the references to "step 4", "step 5" and "step 6" in the skill and in iteration 23's table stay valid.
`skills/workflow/SKILL.md` is in `parallel.hotFiles`.

## Goal

Before the fixer starts, a separate tester agent writes a test that reproduces the bug and confirms that it fails for
the reason in the report, so that the bug is proven independently of the fix.

## Facts this rests on

- Iteration 13 made `/fix` hand the failing test and the fix to one `fixer` subagent (a fresh agent, omit
  `subagent_type`, never a fork, never the `worker`, the model passed explicitly, counted against the agent limit). Its
  prompt's step 1 is "Write the test that fails for the reason in the issue first, named for the behaviour it protects,
  and watch it fail.", its step 4 "Run the check ... When it is green, commit ... Never commit red." `/fix` step 3 of
  "The fixer" checks the result with `git -C <slot> status --short` empty and
  `git -C <slot> log origin/<git.baseBranch>..HEAD` not empty. The PR carries `Fixed by the fixer role on <model>.` and
  the sections Cause, Fix and How verified.
- Iteration 25 added `agents/tester.md` (`name: tester`, tools `Read, Grep, Glob, Write, Edit, Bash`, no `Agent`,
  `model:` equal to the schema default `sonnet`, pinned by the lint) and the section "The tester" in `/next`. Its
  decision 1 says the agent file exists because "#43 will launch the same agent from `/fix`". The agent's body is
  written for a story: "the spec and the acceptance criteria in your prompt", "for every acceptance criterion, at least
  one test", "the implementer commits them with the code once the check is green", and the result block `Result:`,
  `Criteria:`, `Tests:`, `Failing:`, `Files:`, `Left:`. `complete` means every criterion has a test and every test fails
  because the behaviour is missing; `partial` means a criterion is `not tested` or a test `passes` or
  `fails for another reason`. The body carries the single `Test paths:` line, which the lint compares with the one in
  `skills/next/SKILL.md`. Its description line ends "Used by /next on the tester model."
- In `/next` the session records `<tester files>` with `git -C <slot> status --porcelain --untracked-files=all`, checks
  that the tester committed nothing and that every path is a test path, and stops with
  `Stopped: the tester changed files that are not tests: <paths>` or `Stopped: the tester returned failed: <Left, or the
  reason>`, leaving the status at In progress and the slot taken, committing, pushing and reverting nothing. A `partial`
  tester goes on to the implementer in `/next` (iteration 25 decision 7).
- The workflow skill's "Agent roles and models" lists `tester` as "writes the failing tests from the approved spec,
  before the implementer", and `fixer` as "fixes a bug", producing "the fix and its
  regression test". Its rule for the model: `roles.<role>.model` when a non-empty string, else the schema default,
  passed explicitly, never a fork; a model that cannot be used stops with
  `Stopped: the <role> role cannot run on <model>: <the reason>. Nothing was started on another model.`
- Iteration 23 gave `/fix` its step table (`--skill fix`): `slot-taken` after the take, role `fixer` step `fix` "just
  before the fixer is launched (step 4)", the fixer's own `test`, `code`, `check`, `commit`, the code review, fix rounds,
  `manual-check`, `pull-request`, `done`, and `stopped` "on any `Stopped:` line, or a bug skipped in batch mode, after
  the take". Its report command accepts any role of 1 to 40 characters of `A-Z`, `a-z`, `0-9` and `-`, so `tester`
  needs no script change (iteration 25 decision 9 relied on the same).
- Iterations 18 and 19 put the code review between the fixer's result and the pull request; its prompt carries facts,
  not the fixer's account, and fix rounds launch a fresh fixer with the same prompt plus the blocking lines.
- "Batch mode: `/fix all`" today: one fixer at a time, each launch counted; at most 5 bugs per run; one branch per bug
  from up-to-date `origin/<git.baseBranch>`; a bug is skipped, not stopped on, when it is a story, "when the test cannot
  reproduce it", when the check stays red after three attempts, or when the fix grows into a story trigger ("Commit what
  exists to the local branch (do not push), leave the status as it is"); a fixer model that cannot be used ends the
  whole run.
- The bug form (`templates/ISSUE_TEMPLATE/bug.yml`) has "What happens", "What should happen", "How to reproduce" and
  "Evidence". A bug needs no spec, milestone, iteration number or CHANGELOG entry.
- The lint pins in `skills/fix/SKILL.md`, among others: `roles.fixer.model`, `never writes the code itself`,
  `Stopped: the fixer role cannot run on`, `Stopped: the fixer returned failed`, `Fixed by the fixer role on`, `Cause:`,
  `Fix:`, `Test:`, the code review and review-section items, `--capacity --porcelain` or `-Capacity -Porcelain`, and
  `--report`, `-Report`, `slot-taken`, `code-review`, `done`. The section "== a tester writes the failing tests first"
  checks only `agents/tester.md` and `skills/next/SKILL.md`.

## Decisions

**1. The same agent, unchanged in body; the prompt maps a bug onto it.** The tester's standing rules (only test files,
the `Test paths:` line, run and see it fail, do not commit, the result block) are what a regression test needs, so the
body of `agents/tester.md` is not changed and every lint pin of iteration 25 on it keeps passing. The `/fix` prompt says
how to read the story words for a bug: "story" is the bug, "the spec" and "the acceptance criteria" are the bug report
and the one criterion the prompt gives, "the implementer" is the fixer. Only the frontmatter's `description:` changes,
from "... Used by /next on the tester model." to "... Used by /next and by /fix (for a bug's regression test) on the
tester model.", so the agent's own description is not false; the lint pins that `/fix` is named there.

**2. A bug has one criterion, built from the title.** The prompt gives the tester exactly one acceptance criterion,
`1. <the issue's title, without a leading "[Bug] "> is fixed`, and the report in full, and says what the test must do:
follow the report's "How to reproduce" as closely as a test can, expect what "What should happen" says, and fail because
what "What happens" says happens. A body without those headings (a bug filed another way) is still passed in full; the
criterion needs only the title. At least one test is written, and one in each place a testing rule asks for (the agent's
own rule 2).

**3. Reproduced means `Result: complete`; anything less stops the run.** In `/next` a `partial` tester goes on, because
the implementer writes the missing tests. In `/fix` the issue's out of scope excludes "fixing a bug that has no
reproducible test", and the fixer no longer writes the test (decision 6). So after the tester's file checks, a
`Result: complete` (the criterion has a test and every test `fails:`) goes on to the fixer, and a `Result: partial` (the
criterion `not tested`, or a test that `passes` or `fails for another reason`) is "cannot reproduce": the session prints
`Stopped: the tester could not reproduce bug #<issue>: <the reason>. The fixer was not started.` No new result line is
added to the agent: the existing block already says which of the three cases it is, and the reason comes from it.

**4. A stop leaves things as `/next`'s tester stops do.** On every tester stop the status stays In progress, the slot
stays taken, nothing is committed, pushed or reverted, and the tester's files stay uncommitted in the slot (a passing or
wrongly failing test of an unreproduced bug included), so the maintainer can read what was tried. `slot --release`
refuses the dirty slot, as after any tester stop in `/next`; the maintainer clears it by hand. The status is never set
back to Ready (only the maintainer does).

**5. The tester does not commit; "never commit red" is unchanged.** As in iteration 25 decision 4: the regression test
stays uncommitted until the fixer commits it with the fix on a green check, so no red commit exists and nothing red is
pushed. The fixer's step 4 ("... Never commit red.") is unchanged.

**6. The fixer runs the tester's test instead of writing one, and must commit it.** The fixer's step 1 becomes "Run the
tester's test and watch it fail for the reason in the issue." A paragraph tells it where the test is (as `/next`'s
implementer prompt does since iteration 25), that it commits the test with the fix once the check is green, and that a
fix that does not make the test pass is no fix: it commits nothing and reports `failed`. A bug has one criterion, so
there is no "unmet criterion" path as in `/next` (iteration 25 decision 10): either the test passes and is committed, or
the fixer fails. The session checks, besides today's tree and log checks, that every path of `<tester files>` is in
`git -C <slot> diff --name-only origin/<git.baseBranch>..HEAD`, so the test was committed, not dropped.

**7. The rule that the fixer may not edit the test is #44's.** Acceptance criterion 4 says the fixer makes the test pass
"under the same rule as in #44", and #44 has no spec yet. This iteration delivers the hook only: the fixer's prompt says
where the tester's test is and which bug it reproduces, exactly as `/next`'s implementer prompt does after iteration 25.
It adds no rule against editing or deleting the test and no way back to the tester; when #44 is delivered, its rule
applies to the fixer through this same paragraph, as to the implementer.

**8. Nothing is renumbered.** The tester is part of step 4 ("Have the bug reproduced first, then hand the fix to the
fixer"), with its own section "The tester" before "The fixer", as iteration 25 did inside `/next`'s step 3.

**9. The pull request shows the test, not only its name.** "How verified" begins with
`Reproduced first by the tester role on <model>, failing before the fix:`, the tester's `Criteria` line and its
`Failing` lines, then the text of the test as committed: the output of
`git -C <slot> diff origin/<git.baseBranch>..HEAD -- <tester files>` in a fenced `diff` block when it is at most 60 lines,
otherwise the line `The test's diff is longer than 60 lines: see <tester files, comma-separated> in the change.`

**10. Batch mode: tester then fixer per bug, one producer at a time.** Each bug runs its tester and then its fixer in its
own slot, each launch counted; the next bug starts only after the previous bug's fixer has returned or its run stopped.
A tester stop (`returned failed`, `changed files that are not tests`, `could not reproduce`) is a skip of that bug. For a
tester skip nothing is committed (the existing "Commit what exists to the local branch" is for a fixer skip and does not
apply: the tester's files are red or not a reproduction); the files stay uncommitted in that bug's slot. In a single
checkout without slots they are set aside with
`git stash push --include-untracked -m "Tester files for #<issue>: <title>" -- <tester files>` before switching back to
the base branch, so the next bug starts from a clean tree. A tester model that cannot be used ends the whole run, as a
fixer model does.

**11. One report step for the tester, made by the session.** `/fix`'s table gets the row role `tester`, step
`write-tests`, "just before the tester is launched", as in `/next`. The tester reports nothing itself; its prompt
carries no report command.

**12. The role's description says it in two places, not three.** The workflow skill's role table and the README's roles
table describe the tester as working "before the implementer"; both get "and a bug's regression test from the report,
before the fixer". The schema's `description` of `roles.tester` (`schema/nightmill.schema.json`, a hot file under the
`doNotPair` rule) is not changed in this iteration; it stays true for stories.

## The agent

`agents/tester.md`: only the `description:` line changes, to

```
description: Writes the failing tests for every acceptance criterion of an approved spec before any code exists, runs them and reports why they fail. Writes only test files and test fixtures, leaves them uncommitted in the slot, and reports in one fixed block. Used by /next and by /fix (for a bug's regression test) on the tester model.
```

`name`, `tools`, `model` and the body stay byte for byte as they are (decision 1).

## `/fix`

All changes are in `skills/fix/SKILL.md`. Steps 1, 2, 3 and 5, "The code review" and "Hard rules" stay as they are,
except where named.

### Step 4

Step 4 becomes:

> 4. **Have the bug reproduced first, then hand the fix to the fixer.** The session never writes the test or the code
>    itself. A subagent in the role `tester` writes a regression test that fails for the reason in the issue (see "The
>    tester" below); then a subagent in the role `fixer` fixes the cause with the smallest diff and makes that test pass
>    (see "The fixer" below): for each, count the agents, launch it, read its result. The fixer corrects a spec's text
>    when the fix changes a rule or number the spec states, adds no CHANGELOG entry, and runs the check. A bug the tester
>    cannot reproduce is not fixed in this run.

(The phrase `never writes the code itself` stays in "The fixer", step 1, so iteration 13's pin keeps passing.)

### The tester (new section, before "The fixer")

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
     `Stopped: the tester could not reproduce bug #<issue>: <the reason>. The fixer was not started.` with the branch and
     the slot. `<the reason>` is the `not tested:` reason of the `Criteria` line, else every `Failing` line that is not
     `fails:`, joined with `; `.
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

### The fixer

- The section's first paragraph ends, instead of "The failing test and the fix are the fixer's.", with: "The regression
  test is the tester's; the fix, and the commit of both, are the fixer's. The fixer is launched only after "The tester"
  went on."
- Its step 1 (Count) and step 2 (Launch) are unchanged.
- Its step 3 (Read the result) checks, besides `git -C <slot> status --short` empty and
  `git -C <slot> log origin/<git.baseBranch>..HEAD` not empty, that every path of `<tester files>` is listed by
  `git -C <slot> diff --name-only origin/<git.baseBranch>..HEAD` (decision 6). When any of the three checks fails, it
  is handled as `Result: failed`: print `Stopped: the fixer returned failed: <Left, or the check that failed>` with the
  branch and the slot. The same holds when "The code review" reads the result of a fix round. The `Result: complete`,
  `Result: partial` and `Result: failed` branches are otherwise unchanged.
- **The prompt.** After the line "The bug, in full: <body>." one paragraph is added:

  ```markdown
  The tester has written a regression test for this bug into the slot's working tree and has not committed it; it
  fails for the reason in the issue, because the fix does not exist yet. It is at: <tester files, one per line>. The
  test: <the tester's Criteria line>. How it fails now: <the tester's Failing lines>. Commit it together with your fix,
  once the check is green. A fix that does not make this test pass is not a fix: then commit nothing, report `failed`
  and say why under Left.
  ```

  and step 1 of "Do this:" changes from "Write the test that fails for the reason in the issue first, named for the
  behaviour it protects, and watch it fail." to:

  ```markdown
  1. Run the tester's test and watch it fail for the reason in the issue.
  ```

  Steps 2, 3 and 4, the report paragraph (the step `test` is still reported before step 1), the forbidden actions
  (including "do not delete files") and the result block (its `Test:` line now names the tester's test and how it failed
  before the fix) are unchanged. The fix rounds of "The code review" use this same prompt, so they carry the paragraph
  too; the tester is not launched again in a fix round. The prompt adds no rule against editing the tester's test and no
  way back to the tester; both are #44's (decision 7).

### Step 6: "How verified"

Step 6 says that "How verified" is written from the tester's and the fixer's result blocks and the manual steps, and
that it begins with:

````
Reproduced first by the tester role on <model>, failing before the fix:
- <the tester's Criteria line, as it wrote it>
- <each of the tester's Failing lines, as it wrote them>

```diff
<git -C <slot> diff origin/<git.baseBranch>..HEAD -- <tester files>>
```
````

`<model>` is the exact string passed as `model` in the tester's Agent call. When the diff is longer than 60 lines, the
fenced block is replaced by `The test's diff is longer than 60 lines: see <tester files, comma-separated> in the
change.` The rest of "How verified" (the fixer's `Test:` and `Check:` lines, the manual steps), the line
`Fixed by the fixer role on <model>.`, the sections Cause and Fix, the `## Review` section and the auto-merge rule are
unchanged.

### Reporting the steps

The table gets one row, placed before the row "just before the fixer is launched (step 4)":

| When | Role | Step |
|---|---|---|
| just before the tester is launched (step 4, "The tester") | `tester` | `write-tests` |

It is reported by the session with the existing command (`--report write-tests --slot <n> --skill fix --role tester`,
or `-Report write-tests -Slot <n> -Skill fix -Role tester`), under the existing rule that a failed report never stops a
run. A `Stopped:` line of "The tester" reports `stopped`, as every other `Stopped:` line after the take; in batch mode
the skipped bug reports `stopped` to its own slot. The tester's prompt carries no report command (decision 11).

### Batch mode

"Batch mode: `/fix all`" changes in three places (decision 10):

- **"One fixer at a time"** becomes **"One producer at a time."**: "Each bug's tester and fixer launches are counted;
  the tester has returned before the fixer is launched, and the next bug starts only after the previous bug's fixer has
  returned or its run stopped. A `failed` fixer, and each `Stopped:` line of "The tester" except a model that cannot be
  used, is a skip of that bug by the rule below. A model that cannot be used, for the tester or the fixer, is **not** a
  skip: ..." (the rest of the paragraph unchanged).
- In **"A bug that cannot be done is skipped"**, "when the test cannot reproduce it" becomes "when the tester cannot
  reproduce it (`Stopped: the tester could not reproduce bug #`)", and one sentence is added after "Commit what exists
  to the local branch (do not push)": "For a bug skipped at the tester, commit nothing: the tester's files stay
  uncommitted in the bug's slot; in a single checkout without slots set them aside with
  `git stash push --include-untracked -m "Tester files for #<issue>: <title>" -- <tester files>` before switching back
  to the base branch."
- The final table's cause column says `not reproduced: <the reason>` for such a skip.

The cap of 5 bugs per run, the order, one branch per bug and the stops of the whole run are unchanged.

## The workflow skill

One table cell, nothing else. In "Agent roles and models", the `tester` row's "Does" becomes "writes the failing tests
from the approved spec, before the implementer, and a bug's regression test from the report, before the fixer". The
`fixer` row, "Definition of done", "Verify before every commit" and the bug rule ("A failing test first, then the
smallest fix of the cause") are not changed.

## README

- The roles table's `tester` row: "Writes the failing tests from the approved spec, before the implementer, and a bug's
  regression test from the report, before the fixer".
- After the paragraph "Before the implementer starts, `/next` has a `tester` subagent ...", one paragraph: "`/fix` does
  the same before the fixer: the `tester` writes a regression test from the bug report into the slot, uncommitted, and
  runs it to see it fail for the reason the report gives. A bug it cannot reproduce stops the run before any fixer
  starts (in `/fix all` the bug is skipped). The fixer then makes the test pass and commits it with the fix once the
  check is green; the pull request's How verified names the tester's model and shows the test."

## CHANGELOG

One bullet under `Unreleased`, above iteration 25's, in the form of the others:
`- Iteration 26 (#43): a tester agent writes the failing regression test before /fix fixes. ...`, naming the launch of
`nightmill:tester` on `roles.tester.model` after the slot and before the fixer, the bug report as the one criterion,
the test run and seen failing for the reason in the report and left uncommitted, the `Test paths:` check, the new stop
`Stopped: the tester could not reproduce bug #<issue>: ... The fixer was not started.` (a skip in `/fix all`), the
fixer's new step 1 and its commit of the test with the fix once green (checked with `git diff --name-only`), the first
lines of "How verified" with the test's diff, the report step `write-tests`, that the agent's body is unchanged (only its
description), and that no config key, status, slot marker or "never commit red" text changes; the rule that the fixer
may not edit the test is #44's.

## Tests

`/fix` is a conversation, so the lint pins the wording the behaviour depends on, and the manual check does the
behaviour.

**`tests/lint.sh`**, new section "== a tester reproduces the bug before /fix", after "== a tester writes the failing
tests first" (it reuses that section's `tp_re` and `tp_agent`):

- the line that starts with `Test paths:` occurs exactly once in `skills/fix/SKILL.md` and equals the one of
  `agents/tester.md` after the leading and trailing spaces and backticks are removed (criterion 3);
- the `description:` line of `agents/tester.md` contains `/fix` (decision 1);
- `skills/fix/SKILL.md` contains `nightmill:tester`, `roles.tester.model`, `Stopped: the tester role cannot run on`,
  `Stopped: the tester returned failed`, `Stopped: the tester changed files that are not tests`,
  `Stopped: the tester could not reproduce bug #`, `The fixer was not started.`,
  `status --porcelain --untracked-files=all`, `<tester files>`, `never writes the test or the code itself`,
  `verification.benchRule`, `Write the failing regression test for bug #`,
  `Do not commit: leave the test uncommitted in the slot`, `"the implementer" as the fixer`,
  `The one acceptance criterion: 1. <title> is fixed.`, `Run the tester's test and watch it fail`,
  `into the slot's working tree and has not committed it`, `Commit it together with your fix, once the check is green`,
  `A fix that does not make this test pass is not a fix`, `diff --name-only origin/<git.baseBranch>..HEAD`,
  `Reproduced first by the tester role on`, `The test's diff is longer than 60 lines`, `write-tests`,
  `One producer at a time` and `Tester files for #<issue>: <title>` (criteria 1 to 5);
- `skills/fix/SKILL.md` no longer contains `Write the test that fails for the reason in the issue first` (the fixer's
  old step 1) or `One fixer at a time`;
- the `tester` row of the table in "Agent roles and models" of `skills/workflow/SKILL.md`, and `README.md`, contain
  `before the fixer`.

The existing pins keep passing and are not changed: iteration 13's on `skills/fix/SKILL.md` (`never writes the code
itself` stays in "The fixer", step 1; `Stopped: the fixer returned failed`, `Fixed by the fixer role on`, `Cause:`,
`Fix:`, `Test:`), iterations 18, 19, 22 and 23's on `/fix`, and iteration 25's section, which reads only
`agents/tester.md` (whose body is unchanged) and `skills/next/SKILL.md` (unchanged). `bash tests/check.sh` stays green.

## Verification

The change touches `skills` and `agents`, so the manual check applies. In a throwaway project with nightmill loaded from
a separate checkout of this branch (`claude --plugin-dir <checkout>`; never in the checkout being edited, decision 0003),
a board, slots, and a Ready throwaway bug filed with the bug form against a small script (for example a script that
prints a wrong count), with "How to reproduce" steps a test can follow:

1. **The test exists and fails before the fix, default model.** No `roles` block. Run `/fix N`. The tester is launched
   as `nightmill:tester` with `model` `sonnet`, before any fixer. When it returns and before the fixer is launched,
   `git -C <slot> log origin/<base>..HEAD` is empty, `git -C <slot> status --porcelain --untracked-files=all` lists only
   test paths, and running that test in the slot fails, the failure naming the wrong count of the report (criteria 1,
   2, 3).
2. **The fixer makes it pass.** After the run the fixer's commit holds the tester's test file and the fix
   (`git diff --name-only origin/<base>..HEAD` lists the test file), the check is green, and the fixer's prompt named
   the test's path (criterion 4).
3. **The pull request.** Under `Fixed by the fixer role on opus.`, "How verified" begins with
   `Reproduced first by the tester role on sonnet, failing before the fix:`, the `Criteria` line, the `Failing` line and
   the test's diff in a `diff` block (criterion 5).
4. **Configured model.** `roles.tester.model` set to `haiku`: the Agent call and the "How verified" line say `haiku`.
   Set to an empty string: `sonnet` again.
5. **A bug that cannot be reproduced.** A second throwaway bug whose report describes behaviour that already works:
   the tester returns `partial` (its test `passes`, or the criterion `not tested`); the session prints
   `Stopped: the tester could not reproduce bug #<n>: <reason>. The fixer was not started.`, launches no fixer, opens no
   pull request, the status stays In progress, the slot stays taken with the tester's files uncommitted, and the slot's
   marker shows step `stopped` (criterion 2).
6. **Only test files.** A report whose reproduction needs a file outside the test paths (for example `src/sample.json`):
   the tester reports the criterion `not tested` (then step 5's stop), or, if it writes the file, the session prints
   `Stopped: the tester changed files that are not tests: src/sample.json` and launches no fixer. Record which of the two
   happened (criterion 3).
7. **A model that cannot be used.** `roles.tester.model` set to `no-such-model`: `Stopped: the tester role cannot run on
   no-such-model: ...`, naming the status In progress and the taken slot; no fixer is launched. In `/fix all` the same
   ends the whole run and the report lists the bugs not started.
8. **Nothing red is committed or pushed.** Between the tester's return and the fixer's green commit,
   `git -C <slot> log origin/<base>..HEAD` and `git ls-remote origin <branch>` print nothing; CI on the pull request is
   green.
9. **Batch mode.** Both bugs Ready, `/fix all`: each bug gets its own slot, its tester before its fixer, never two
   producers at once; the unreproducible bug is skipped with nothing committed and `not reproduced: <reason>` in the
   final table, the other gets its pull request.
10. **The report step.** While the tester runs, the slot's marker has skill `fix`, role `tester`, step `write-tests`.

The PR's "How verified" lists the ten results and the check.

## Not done

- The rule that the fixer never edits or deletes the tester's test, and the way back to the tester for a doubtful test
  (#44): here the fixer only learns where the test is, runs it and commits it with the fix (decision 7). Nothing detects
  an edit of the test yet.
- The code reviewer checking the regression test against the report and that it was not weakened (#45): its prompt and
  agent file are not changed.
- Fixing a bug that has no reproducible test (out of scope): such a bug stops at the tester; there is no fallback to the
  fixer writing the test, and no other way to fix it in `/fix`. A bug that only a conversation can show (for example a
  wording in a skill no test reaches) stops the same way.
- No re-run of the tester in a fix round; no second tester launch after a stop in the same run.
- No change to the body, `name`, `tools` or `model` of `agents/tester.md`, to `/next`, to `skills/spec/SKILL.md`, to the
  code review in `/fix`, or to the `Test paths:` rule.
- No change to the schema (the `description` of `roles.tester` included, decision 12), to `roles.tester.model`'s
  default, to the validator, to `/nightmill:models` or to the pairing; no config key.
- No change to "never commit red" anywhere (decision 5).
- No new board status, no change to the status flow, to who sets a status or to the slot marker; no decision record;
  no script change.
