# Iteration 25: a tester agent writes the failing tests before /next implements

Status: delivered in iteration 25 (PR #93)

Story: #42, epic #41 (Independent test writing). Adds the agent `agents/tester.md` and a tester step in
`skills/next/SKILL.md`: after the story is In progress and the slot is taken, and before the implementer is launched, a
`tester` subagent on the model the configuration gives the role writes at least one test for every acceptance
criterion of the approved spec into the slot's working tree, runs them and confirms that they fail because the
behaviour is missing; it commits nothing. The session checks that the tester left only test files and fixtures, and the
implementer then makes those tests pass and commits them together with the code, once the check is green. Changes
`skills/next/SKILL.md`, one sentence of `skills/workflow/SKILL.md`, `README.md`, `.claude/CLAUDE.md` (the layout line),
`tests/lint.sh` and `CHANGELOG.md`.

**Not a story trigger.** `roles.tester.model` already exists (iteration 10: in the schema with the default `sonnet`, in
`templates/nightmill.example.json`, in this repository's config and in the README's roles table), so no config key is
added, renamed or removed. The slot marker, the status flow and who sets a status do not change; writing the tests
happens while the story is In progress. The rule "never commit red" does not change anywhere: no red commit is ever made
(decision 4). The PR may auto-merge. The change touches `skills` and `agents`, so the manual check of
`verification.manualCheckPaths` applies.

**Order.** This iteration is implemented after #67 (iteration 23, `slot --report`) has merged. #67 changes
`skills/next/SKILL.md`, `skills/fix/SKILL.md` and `skills/workflow/SKILL.md` (a hot file in `parallel.hotFiles`), the
README and the lint; the two skills this story changes are the same files. The changes below are written against the
step numbering of `skills/next/SKILL.md` on `main` today (section "2. Implement the approved story", steps 1 to 8, and
the sections "The implementer" and "The code review"); this iteration renumbers none of those steps, so the references
#67 puts into the skill ("step 2.2", "step 3", "step 4", ...) stay valid. Where #67's step table meets the tester, it is
said below ("Reporting the step").

## Goal

Before the implementer starts, a separate tester agent writes the tests for every acceptance criterion of the spec and
confirms that they fail, so that what is tested is decided from the spec and not by the agent that writes the code.

## Facts this rests on

- Iteration 13 made `/next` hand the tests and the code to one `implementer` subagent (a fresh agent, never a fork,
  never the `worker`, the model passed explicitly, counted against the agent limit). Its prompt's step 1 is "Turn each
  acceptance criterion into a test named for the behaviour it protects, and watch it fail", step 3 "Run the check ...
  When it is green, commit ... Never commit red." Its spec says: "when the tester arrives, step 1 of the prompt
  changes". Its decision 5: a partly done story gets a pull request with its green commits, and the rest is filed as a
  new story. `/next` step 3 checks the implementer's result with `git -C <slot> status --short` empty and
  `git -C <slot> log origin/<git.baseBranch>..HEAD` not empty.
- "Agent roles and models" in the workflow skill already lists `tester` ("writes the failing tests from the approved
  spec, before the implementer"; produces "the tests"; reviewed by "`codeReviewer`, with the change"), the rule for its
  model (`roles.tester.model` when it is a non-empty string, else the schema default, passed explicitly, never a fork)
  and the stop line when the model cannot be used. The schema default of `roles.tester.model` is `sonnet`; the lint's
  `role_defaults` pins it. The validator compares `tester` with no other role (iteration 15), as the epic decided.
- Iterations 18 and 20 gave the two reviewers an agent file each (`agents/code-reviewer.md`,
  `agents/spec-reviewer.md`) whose `tools:` line limits what they can do and whose `model:` line the lint keeps equal to
  the schema default of their role. The lint's iteration-13 section allows exactly `agents/worker.md` and those two
  files under `agents/`. A plugin agent is addressed as `nightmill:<name>`.
- The workflow skill says, in "Verify before every commit": "Run the check ... before every commit. Never commit red."
  `.claude/CLAUDE.md`, `templates/CLAUDE.snippet.md`, `skills/check/SKILL.md` and `skills/fix/SKILL.md` state the same
  rule. CI runs on every push and pull request to the base branch; `/next` pushes the branch only when it opens the pull
  request (step 6).
- The slot is taken fresh from the up-to-date base (`slot --take`), so before the tester the branch has no commit of its
  own and a clean tree. `slot --release` refuses a slot with uncommitted files. A slot is outside the project directory;
  whether a subagent's writes there prompt was observed in iteration 13's manual check and is unchanged here.
- `verification.benchRule` of this repository is "A script that runs in the smoke tests keeps its scenario there; a new
  script flag gets a smoke step in both shells", and its invariants include "Both shells — every script exists in
  PowerShell and bash and behaves the same". Both are configuration, so a skill can pass them on without naming them.
- #67 (iteration 23) adds `slot --report <step> --slot N --skill <s> --role <r>` and a step table to `/next`: role
  `implementer`, step `implement` "just before the implementer is launched (step 3)"; the implementer itself reports
  `tests` before its step 1, `code` before its step 2, `check` and `commit`. Its marker table names the roles in use
  (`session`, `implementer`, `fixer` or `codeReviewer`), and its report command refuses only a role that is "empty, not
  given, or not 1 to 40 characters of `A-Z`, `a-z`, `0-9` and `-`, starting with a letter or digit"; any value of that
  form is accepted.

## Decisions

**1. An agent file for the tester.** Iteration 13 gave the producers no agent file because a prompt and a model were
all they needed. The tester differs in two ways: what it may touch is narrower than what its tools allow, and #43 will
launch the same agent from `/fix`. So its standing rules (what to write, what not to touch, that it commits nothing, the
result block) live once in `agents/tester.md`, as the reviewers' do, and the skill's prompt carries only the facts of
the story. Its `model:` line is kept equal to the schema default of `roles.tester.model` by the lint; the call overrides
it explicitly as always.

**2. Tools: `Read, Grep, Glob, Write, Edit, Bash`; no `Agent`.** It must write test files and run them, so it needs
`Write`, `Edit` and `Bash`; without `Agent` it cannot start another agent. An agent file cannot limit `Write` and `Edit`
to some paths, so "only test files and test fixtures" is enforced twice: by the rule in the agent's body, and by the
session, which lists every path the tester changed or added with `git -C <slot> status --porcelain` and stops when one
is not a test path (decision 3).

**3. The test path rule is fixed in the plugin, not a config key.** A path, relative to the root of the repository, is
a test path when a directory in it is named `test`, `tests`, `__tests__`, `spec`, `testdata`, `fixtures` or
`__fixtures__`, or its file name starts with `test_` or `test-`, or contains `_test.`, `.test.`, `-test.`, `_spec.`,
`.spec.`, `Test.` or `Tests.` (case as written); and it is never under `iterations.specDir` or `iterations.decisionsDir`
and never `iterations.changelog`. These are the common layouts of test code across languages, not a value of one
project, so they do not break the Config-driven invariant; the three exclusions come from the configuration. The rule
is written once as a single line starting `Test paths:` and appears identically in the agent file and in the skill; the
lint compares the two. A project whose tests live elsewhere gets a stop with the paths named, never a silent pass. A
config key for the pattern (for example `verification.testPaths`) would let such a project widen it; the issue asks for
no key, so none is added here; it is a later story if a project needs it.

**4. The tester does not commit; "never commit red" is unchanged.** The tester writes its tests into the slot's working
tree, runs them to see them fail and leaves them there uncommitted (new or modified test files). The implementer commits
them together with the code, once the check is green (its existing step 3). So no red commit exists, nothing red can be
pushed, and the rule "never commit red" keeps its wording everywhere: the workflow skill's "Verify before every commit",
`.claude/CLAUDE.md`, `templates/CLAUDE.snippet.md`, `skills/check/SKILL.md` and `skills/fix/SKILL.md` are not changed.

**5. The tester's files are the interface for #44 and #45.** The session records `<tester files>`, the paths that
`git -C <slot> status --porcelain --untracked-files=all` lists after the tester returned (the whole tree was clean
before it). The implementer's prompt and the pull request name them, with the criterion-to-test list. #44 (the
implementer may not edit these files, and the way back to the tester) and #45 (the code reviewer checks them against the
spec) can build on that list; this story does neither.

**6. The session's step stays "step 3"; nothing is renumbered.** The tester is part of step 3 of "2. Implement the
approved story", before the implementer, with its own section "The tester" beside "The implementer". The later step
numbers, which iteration 19 and #67 refer to, keep their values.

**7. A partial tester goes on.** A criterion the tester cannot test, or a test it cannot make fail for the right
reason, is reported in its result (`partial`); the session goes on to the implementer, which writes a test for each
criterion the tester did not test (its step 1, below), and the pull request shows both. A `partial` tester alone does
not withhold auto-merge: every criterion still gets a test, the code reviewer checks that, and step 7's existing reasons
decide. When no criterion can be tested, the tester writes nothing and returns `partial` with every criterion
`not tested`; there is nothing to check, and the run goes on and the implementer writes the tests. A `failed` tester, a
missing block, a commit by the tester, no changed path with any other result (a `complete`, or a `partial` with a tested
criterion), or a path that is not a test path stops the run as a failed implementer does today.

**8. The testing rules are passed from the configuration.** The issue names `verification.benchRule` and "the
two-shells rule for scripts". The second is a rule of this repository, which its configuration holds as an invariant
(and in its bench rule); a skill may not name it (Config-driven). So the prompt passes `verification.check`,
`verification.benchRule` and every line of `invariants`, and the agent's body says that a rule asking for a test in more
than one place (for example a script that exists in two shells) gets a test in each place.

**9. One report step for the tester, made by the session.** #67's table gets one row: role `tester`, step `write-tests`,
reported by the session just before the tester is launched, as the session reports `implement` for the implementer and
`code-review` for the reviewer. #67's report command accepts any role of the form it gives (1 to 40 characters of
`A-Z`, `a-z`, `0-9` and `-`, starting with a letter or digit), so `tester` needs no change to #67's spec or script. The
tester reports nothing itself, so its prompt carries no report command; finer steps for it are left to a later story.
The implementer's `tests` step (before its step 1) keeps its name: its step 1 now runs the tester's tests and writes
those for untested criteria.

**10. A partial implementer: the tests of unmet criteria stay uncommitted and travel with the rest.** Iteration 13
decision 5 is kept as it is: a `partial` implementer result gets a pull request with its green commits, and the rest is
filed as a new story. A tester test of a criterion the implementer could not meet fails, so it cannot be committed
green; it is therefore not committed. The implementer leaves the file uncommitted in the slot (a file that also holds
tests of other criteria stays uncommitted as a whole) and lists it under Left as `unmet: <path> (criterion <n>)`; to run
the check and commit the rest it sets those files aside with `git stash` and puts them back after the commit, so the
committed state is the checked state. The session's tree check of step 3 accepts exactly those paths when they are in
`<tester files>`; any other dirty path still fails it as today. Before step 5's rebase the session stashes those paths
(the rebase and the later `slot --release` need a clean tree; nothing is deleted), the pull request's "How verified"
names them as `not committed: criterion not met`, and the new story filed by step 8 gets the paths, the stash's message
and the text of each test in its body, so the tests are not lost. Steps 7 and 8 apply as today: no auto-merge, the unmet
criteria not ticked.

## The agent

`agents/tester.md`:

```markdown
---
name: tester
description: Writes the failing tests for every acceptance criterion of an approved spec before any code exists, runs them and reports why they fail. Writes only test files and test fixtures, leaves them uncommitted in the slot, and reports in one fixed block. Used by /next on the tester model.
tools: Read, Grep, Glob, Write, Edit, Bash
model: sonnet
---
```

and a body that says, in this order:

1. You write the tests of a story before any code for it exists, from the spec and the acceptance criteria in your
   prompt, in the slot your prompt names (the absolute path for every file, `git -C <slot>` for every git command). You
   do not write the code. You start no other agent and you ask no questions.
2. **For every acceptance criterion, at least one test**, named for the behaviour it protects (not for the criterion's
   number), in the project's existing test files and layout; where the spec's Tests section names a file or a case, use
   it. A test checks the behaviour the criterion promises. Follow the project's testing rules in your prompt; a rule that
   asks for a test in more than one place (for example a script that exists in two shells) gets a test in each place.
   A criterion you cannot test automatically is reported under `Criteria` as `not tested: <reason>`, never skipped
   silently.
3. **Only test files and test fixtures.** You write only paths that match the line below; no production code, no stub
   or placeholder of the code under test, no change to the spec, the CHANGELOG, the configuration, CI, a skill or a
   script under test. If a test cannot be written without such a change, do not make it: report the criterion as
   `not tested` with the reason. Do not delete files.

   `Test paths: a directory in the path is named test, tests, __tests__, spec, testdata, fixtures or __fixtures__, or the file name starts with test_ or test-, or contains _test. .test. -test. _spec. .spec. Test. or Tests.; never under iterations.specDir or iterations.decisionsDir, never iterations.changelog.`
4. **Run the new tests and confirm that they fail because the behaviour is missing**, with the command that runs them
   (the project's check is in your prompt). A test that passes now, or that fails for another reason (a syntax error, a
   wrong path, a missing fixture, a wrong expectation), is fixed; one you cannot fix is reported under `Failing`. Never
   weaken a test to make it fail or pass.
5. **Do not commit.** Leave the tests in the slot's working tree, uncommitted; the implementer commits them with the
   code once the check is green. Do not stage, stash or commit anything, do not push, do not open or edit a pull
   request, do not touch the board, any issue or any status, do not create or switch branches, and do not launch other
   agents. If the spec is unclear or contradicts itself, do not decide it: report it under Left.
6. End your last message with exactly this block, and nothing after it:

   ```
   Result: complete | partial | failed
   Criteria: <one line per acceptance criterion, in the issue's order: <n>. <criterion> -> <test name> (<file>)[, <test name> (<file>)...] | <n>. <criterion> -> not tested: <reason>>
   Tests: <every test added or changed, one per line: <test name> (<file>)>
   Failing: <one line per test: <test name>: fails: <the failure, one line, naming the missing behaviour> | <test name>: passes: <why> | <test name>: fails for another reason: <the reason>>
   Files: <every file written or changed, one per line; none>
   Left: <what is not done and why; nothing>
   ```

   `complete`: every criterion has at least one test and every test fails because the behaviour is missing.
   `partial`: at least one criterion is `not tested` or one test `passes` or `fails for another reason`; when no
   criterion could be tested, write nothing and report `Files: none`. `failed`: you could not do the work.

## `/next`

All changes are in `skills/next/SKILL.md`. The picking section, steps 1, 2, 4 and 7 of "2. Implement the approved
story", "The code review" and "Hard rules" stay as they are, except where named.

### Step 3

Step 3 becomes:

> 3. **Have the tests written first, then hand the coding to the implementer.** The session never writes the tests or
>    the code itself. A subagent in the role `tester` writes the failing tests from the spec (see "The tester" below);
>    then a subagent in the role `implementer` writes the code that makes them pass (see "The implementer" below): for
>    each, count the agents, launch it, read its result.

### The tester (new section, before "The implementer")

The session keeps the board, the slot and every hard rule; the failing tests are the tester's.

1. **Count.** Before the launch count the agents running, as for the implementer (the live agent limit from
   `slot.ps1 -Capacity -Porcelain` or `slot.sh --capacity --porcelain`, else `parallel.maxAgents`). At the limit wait for
   one to end and say what you wait for; the session never writes the tests itself instead. The tester is one agent (its
   agent file has no `Agent` tool), and it has returned before the implementer is launched, so a story runs at most one
   producer at a time.
2. **Launch.** One Agent call: `subagent_type` `nightmill:tester`, not a fork, not nightmill:worker, with the `model`
   that **Agent roles and models** in the `workflow` skill gives the role `tester` (`roles.tester.model`, else the schema
   default), passed explicitly, and the prompt below. When the model cannot be used, stop with the line of that section
   for `tester` (`Stopped: the tester role cannot run on <model>: <the reason>. Nothing was started on another model.`)
   and add that the status of #<issue> is In progress and the slot is taken; no implementer is launched.
3. **Read the result.** The subagent's last message ends with the block of `agents/tester.md`. Record `<tester files>`,
   the paths of `git -C <slot> status --porcelain --untracked-files=all` (the path after the two status letters; every
   file is listed, not only its directory), then check, in this order:
   - `git -C <slot> log origin/<git.baseBranch>..HEAD` is empty (the tester committed nothing), and `<tester files>`
     is not empty; the one exception is a `Result: partial` whose every `Criteria` line is `not tested` (decision 7),
     where nothing is written, `<tester files>` is empty and there is nothing to check;
   - every path of `<tester files>` is a test path by this line, with `iterations.specDir`, `iterations.decisionsDir`
     and `iterations.changelog` read from the configuration:

     `Test paths: a directory in the path is named test, tests, __tests__, spec, testdata, fixtures or __fixtures__, or the file name starts with test_ or test-, or contains _test. .test. -test. _spec. .spec. Test. or Tests.; never under iterations.specDir or iterations.decisionsDir, never iterations.changelog.`

   Then:
   - `Result: complete` or `Result: partial`, and both checks hold: go on with "The implementer". Keep the tester's
     `Criteria` and `Failing` lines, `<tester files>` and the model passed, for the implementer's prompt and the pull
     request.
   - A path that is not a test path: print
     `Stopped: the tester changed files that are not tests: <the paths, comma-separated>` with the branch and the slot.
   - `Result: failed`, no result block, an error, a commit, or no changed path outside that exception: print
     `Stopped: the tester returned failed: <Left, or the reason>` with the branch and the slot.

   On either `Stopped:` line: launch no implementer, open no pull request, leave the status at In progress and the slot
   taken, commit, push and revert nothing. Do not start another agent on this story in this run; never set Ready.

The prompt, with the placeholders filled in (the criteria and the body verbatim):

```markdown
Write the failing tests for story #<issue> "<title>" in <owner>/<repo>.

The slot: <absolute slot path>, branch <branch>. Use that absolute path for every file and `git -C <slot path>` for
every git command; your working directory is not the slot. The branch holds no code for this story yet. Do not commit:
leave the tests uncommitted in the slot.

The spec: <path in the slot> (read it completely; it is the contract).
The acceptance criteria of the issue, in order: <the criteria, verbatim>.
The issue body, in full: <body>.

The project's testing rules:
- the check: <verification.check>
- the bench rule: <verification.benchRule, or "none">
- the invariants: <config invariants, one per line>

In this project iterations.specDir is <iterations.specDir>, iterations.decisionsDir is <iterations.decisionsDir> and
iterations.changelog is <iterations.changelog>.

End with the result block of your instructions, and nothing after it.
```

### The implementer

- The section's first paragraph says: "The session keeps the picking line, the board statuses, the slot, the manual
  check, the CHANGELOG entry, the pull request and every hard rule. The failing tests are the tester's; the code, and a
  test for a criterion the tester did not test, are the implementer's, and so is the commit of both."
- Its step 1 (Count) and step 2 (Launch) are unchanged; the implementer is launched only after "The tester" went on.
- Its step 3 (Read the result) keeps its check as it is: `git -C <slot> status --short` is empty and
  `git -C <slot> log origin/<git.baseBranch>..HEAD` is not. So a `complete` result has committed the tester's tests
  together with the code, under a green check. A red implementer result needs no new rule: the implementer commits only
  on a green check, so the tests and the code stay uncommitted and the check fails as it does today.
- Its step 3's `Result: partial` branch (go on with step 4; steps 7 and 8 apply: no auto-merge, the rest filed as a new
  story, the unmet criteria not ticked) gets this sentence (decision 10): "For a `Result: partial`, the tree check
  accepts exactly the paths the result lists under Left as `unmet: <path> (criterion <n>)` that are in
  `<tester files>`: `git -C <slot> status --porcelain --untracked-files=all` may list those paths and no other. Any
  other dirty path fails the check as it does today." The same holds when "The code review" reads the result of a fix
  round.
- **The prompt.** After the paragraph with the spec, the criteria and the body, one paragraph is added:

  ```markdown
  The tester has written the tests for the acceptance criteria into the slot's working tree and has not committed them;
  they fail because the code does not exist yet. They are at: <tester files, one per line>. Which test covers which
  criterion: <the tester's Criteria lines>. Commit them together with your code, once the check is green.
  If you cannot meet a criterion, do not commit the tester's test of it: leave that file uncommitted in the slot (a file
  that also holds tests of other criteria stays uncommitted as a whole) and list it under Left as
  `unmet: <path> (criterion <n>)`. To run the check and commit the rest, set those files aside with
  `git -C <slot path> stash push --include-untracked -m "unmet tests" -- <the paths>`, and put them back with
  `git -C <slot path> stash pop` after the commit.
  ```

  When the tester wrote nothing (decision 7), the paragraph is instead "The tester could test no acceptance criterion
  and wrote no test."

  and step 1 of "Do this:" changes from "Turn each acceptance criterion into a test named for the behaviour it protects,
  and watch it fail." to:

  ```markdown
  1. Run the tester's tests and watch them fail. For each criterion the tester marked `not tested`, write a test named
     for the behaviour it protects and watch it fail.
  ```

  Steps 2 and 3 ("Implement until the tests pass", "Run the check ... Never commit red."), the forbidden actions
  (including "do not delete files") and the result block are unchanged. The fix rounds of "The code review" use this
  same prompt, so they carry the paragraph too. The prompt adds no rule against editing the tester's tests and no way
  back to the tester; both are #44's.

### Step 5: the tests of unmet criteria

Step 5 gets one sentence before "Rebase on `origin/<git.baseBranch>`" (decision 10): "When the implementer's result is
`partial` and lists `unmet:` paths under Left, first copy the text of each (`git -C <slot> diff -- <path>` for a changed
file, the file for a new one) for step 8, then set them aside with
`git -C <slot> stash push --include-untracked -m "Unmet tests for #<issue>: <title>" -- <the paths>`, so the tree is
clean for the rebase and for the release of the slot."

### Step 6: "How verified"

Step 6 says that the "How verified" section is written from the tester's and the implementer's result blocks (tests,
the check) and the session's own manual check, and that it begins with:

```
Tests written first by the tester role on <model>, failing before the code:
- <the tester's Criteria lines, one per line, as it wrote them>
```

`<model>` is the exact string passed as `model` in the tester's Agent call. For a criterion marked `not tested`, the
line gets `; tested by the implementer: <the test of the implementer's Criteria line>`. Each `Failing` line that is not
`fails:` follows as `- not failing as expected: <the line>`. Each `unmet:` path of a partial implementer result follows
as `- not committed: criterion not met: <path> (criterion <n>)`. The rest of "How verified" (the implementer's tests,
the check, the manual check) and the `## Review` section after it are unchanged.

### Step 8: the rest of a partial story

Step 8 gets one sentence: "When tests of unmet criteria were set aside in step 5, the new story's body lists their
paths, the stash's message `Unmet tests for #<issue>: <title>` and the text copied in step 5, so the tests are not
lost." Step 7 is unchanged: a partial pull request does not auto-merge.

### Reporting the step (with #67)

#67's table in `/next` gets one row, placed before the row "just before the implementer is launched (step 3)":

| When | Role | Step |
|---|---|---|
| just before the tester is launched (step 3, "The tester") | `tester` | `write-tests` |

It is reported by the session with the report command of #67 (`--report write-tests --slot <n> --skill next --role
tester`, or `-Report write-tests -Slot <n> -Skill next -Role tester`), under #67's rule that a failed report never stops
a run. A `Stopped:` line of "The tester" reports `stopped` as every other `Stopped:` line after the take. The tester's
prompt carries no report command (decision 9).

## The workflow skill

One sentence, nothing else; "Agent roles and models" already describes the `tester` and is not changed, and neither is
"Verify before every commit" (decision 4).

- **"Definition of done"**: after "every acceptance criterion is a test" add "(in `/next` written first by the `tester`
  and seen failing before the code)".

## README

In "Agent roles and models", one paragraph before the one on the `codeReviewer`: "Before the implementer starts, `/next`
has a `tester` subagent on its configured model (`agents/tester.md`) write at least one test for every acceptance
criterion from the approved spec into the slot, uncommitted, and run them to see them fail for the missing behaviour; it
writes only test files and fixtures, and the session stops when it leaves anything else. The implementer then makes
those tests pass and commits them with the code once the check is green. The pull request's How verified names the
tester's model and which test covers which criterion."

`.claude/CLAUDE.md`, the layout line `agents  worker.md, code-reviewer.md, spec-reviewer.md` becomes
`agents  worker.md, code-reviewer.md, spec-reviewer.md, tester.md`.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others:
`- Iteration 25 (#42): a tester agent writes the failing tests before /next implements. ...`, naming the agent
`agents/tester.md` (tools `Read, Grep, Glob, Write, Edit, Bash`, no `Agent`; `model:` kept equal to the schema default
`sonnet` by the lint), its launch as `nightmill:tester` on `roles.tester.model` after the slot and before the
implementer, at least one test per criterion and `not tested` reported, the tests run and seen failing and left
uncommitted, the `Test paths:` rule and the session's `git status --porcelain` check, the implementer's new step 1 and
its commit of the tests with the code once green (so no red commit), the tests of unmet criteria of a partial result
left uncommitted, named in the pull request and carried to the new story, the first lines of "How verified", the report
step `write-tests`, and that no config key, status, slot marker or "never commit red" text changes.

## Tests

Each acceptance criterion of #42 is a lint check or a manual scenario. `/next` is a conversation, so the lint pins the
wording the behaviour depends on, and the manual check does the behaviour.

**`tests/lint.sh`**, new section "== a tester writes the failing tests first":

- `agents/tester.md` exists with `name: tester`; its `tools:` line is exactly `Read, Grep, Glob, Write, Edit, Bash` (so
  it has no `Agent`); its `model:` line equals the schema default of `roles.tester.model` (criterion 1); its body
  contains `acceptance criterion`, `not tested`, `named for the behaviour`, `only test files and test fixtures`,
  `production code`, `fails for another reason`, `passes`, `Do not commit`, `Do not stage, stash or commit anything`,
  `do not push`, `do not launch other agents`, `Result: complete | partial | failed`, `Criteria:`, `Tests:`,
  `Failing:`, `Files:` and `Left:` (criteria 2, 3, 4);
- the line that starts with `Test paths:` occurs exactly once in `agents/tester.md` and exactly once in
  `skills/next/SKILL.md`, and the two lines are equal after the leading spaces and backticks are removed (criterion 4);
- `skills/next/SKILL.md` contains `nightmill:tester`, `roles.tester.model`, `Stopped: the tester role cannot run on`,
  `Stopped: the tester returned failed`, `Stopped: the tester changed files that are not tests`,
  `status --porcelain --untracked-files=all`, `<tester files>`, `never writes the tests or the code itself`,
  `verification.benchRule`, `Do not commit: leave the tests uncommitted in the slot`, `Run the tester's tests`,
  `into the slot's working tree and has not committed them`, `Commit them together with your code, once the check is
  green`, `If you cannot meet a criterion, do not commit the tester's test of it`, `unmet: <path> (criterion <n>)`,
  `Unmet tests for #`, `not committed: criterion not met` and `Tests written first by the tester role on` (criteria 1,
  3, 4, 5), and no longer contains `Turn each acceptance criterion into a test` (the implementer's old step 1);
- `skills/next/SKILL.md` still contains `never writes the code itself` and
  `git -C <slot> log origin/<git.baseBranch>..HEAD` (iteration 13's checks, unchanged);
- the section "Verify before every commit" of `skills/workflow/SKILL.md` still contains `Never commit red.`, and its
  "Definition of done" contains `written first by the` and `seen failing before the code`;
- `README.md` contains `agents/tester.md`;
- the check on `agents/` of iteration 13 now allows exactly `agents/worker.md`, `agents/code-reviewer.md`,
  `agents/spec-reviewer.md` and `agents/tester.md`, and its message says "only the worker, the two reviewers and the
  tester have an agent file (the implementer's and the fixer's prompts are in the skills)".

`bash tests/check.sh` stays green.

## Verification

The change touches `skills` and `agents`, so the manual check applies. In a throwaway project with nightmill loaded
from a separate checkout of this branch (`claude --plugin-dir <checkout>`; never in the checkout being edited,
decision 0003), a board, and an Approved throwaway story with two acceptance criteria that ask for a small script
change, and its spec:

1. **Tests before code, default model.** No `roles` block. Run `/next`. The tester is launched as `nightmill:tester` with
   `model` `sonnet`. When it returns and before the implementer is launched, `git -C <slot> log origin/<base>..HEAD` is
   empty, `git -C <slot> status --porcelain --untracked-files=all` lists only test paths, and running the tests in the
   slot fails, the failures naming the missing behaviour. After the run, the implementer's commit holds those test files
   and the code, so the failing tests existed before the first line of code (criteria 1, 3, 4).
2. **Every criterion is covered.** The tester's `Criteria` has two lines, one per criterion, each naming at least one
   test named for the behaviour; the pull request's "How verified" begins with
   `Tests written first by the tester role on sonnet, failing before the code:` and those two lines (criteria 2, 5).
3. **Configured model.** `roles.tester.model` set to `haiku`: the Agent call and the "How verified" line say `haiku`.
   Set to an empty string: `sonnet` again.
4. **A criterion that cannot be tested.** A third criterion that only a person can judge ("the maintainer finds the
   message clear"): the tester returns `partial` with `3. ... -> not tested: <reason>`; the run goes on; the pull request
   shows the line with the implementer's test or no test, and the code reviewer's findings follow the existing rules.
   With only that criterion (none testable), the tester writes nothing, returns `partial` with `Files: none`, and the
   run goes on to the implementer.
5. **Only test files.** A spec whose Tests section asks for a fixture under a path that is not a test path (for example
   `src/sample.json`): the tester reports the criterion `not tested` instead of writing it, or, if it writes the file,
   the session prints `Stopped: the tester changed files that are not tests: src/sample.json`, launches no implementer,
   and the status stays In progress with the slot taken. Record which of the two happened (criterion 4).
6. **A model that cannot be used.** `roles.tester.model` set to `no-such-model`: `Stopped: the tester role cannot run on
   no-such-model: ...`, naming the status In progress and the taken slot; no implementer is launched.
7. **Nothing red is committed or pushed.** Between the tester's return and the implementer's green commit,
   `git -C <slot> log origin/<base>..HEAD` and `git ls-remote origin <branch>` print nothing; the first push is the
   session's in step 6, and CI on the pull request is green. A run whose implementer cannot make any test pass ends in
   `Stopped: the implementer returned failed`, with nothing committed and nothing pushed.
8. **A partial result with an unmet criterion.** A spec whose second criterion the implementer cannot meet in the run
   (for example it names a behaviour the spec's own design rules out): the implementer commits the first criterion's
   test with the code, green, and lists the second's file under Left as `unmet: <path> (criterion 2)`; the session's
   tree check accepts that path and goes on; before the rebase it is stashed as `Unmet tests for #<issue>: <title>`
   (`git stash list` shows it, the tree is clean); the pull request's "How verified" has
   `- not committed: criterion not met: <path> (criterion 2)`, does not auto-merge and leaves criterion 2 unticked;
   the new story filed for the rest names the path, the stash and the test's text (decision 10).
9. **The report step** (with #67 merged): while the tester runs, the slot's marker has role `tester`, step
   `write-tests`.

The PR's "How verified" lists the nine results and the check.

## Not done

- The tester before `/fix` (#43): `/fix` and its fixer are not changed; the fixer still writes its own failing test.
- The rule that the implementer never edits or deletes the tester's tests, and the way back to the tester for a doubtful
  or unmet test (#44): #44 specifies both. Here the implementer's prompt only learns where the tests are, runs them,
  commits them with the code and leaves the test of an unmet criterion uncommitted; nothing in the workflow detects an
  edit yet.
- The code reviewer checking the tests against the spec and that none was weakened (#45): its prompt and agent file are
  not changed; it sees the tester's tests in the diff of the implementer's commits as before.
- No re-run of the tester in a fix round; a blocking finding about a tester's test goes to the implementer by the
  existing rules until #44 and #45.
- No change to "never commit red" anywhere (decision 4): not in the workflow skill, `.claude/CLAUDE.md`,
  `templates/CLAUDE.snippet.md`, `skills/check/SKILL.md` or `skills/fix/SKILL.md`.
- No config key for the test paths (decision 3), no new role, no change to `roles.tester.model`'s default, to the
  validator, to `/nightmill:models` or to the pairing (the tester is compared with no role).
- No new board status, no change to the status flow, to who sets a status or to the slot marker; no decision record.
- No report command inside the tester's prompt and no finer tester steps than `write-tests` (decision 9); no change to
  #67's spec.
- No change to `skills/spec/SKILL.md`.
