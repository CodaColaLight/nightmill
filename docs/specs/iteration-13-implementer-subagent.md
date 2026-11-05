# Iteration 13: /next and /fix hand the coding to a subagent on the configured model

Status: delivered in iteration 13 (PR #61)

Story: #35, epic #29 (Independent code review). Changes `skills/next/SKILL.md` and `skills/fix/SKILL.md` so that the
tests and the code of a story are written by an `implementer` subagent, and those of a bug fix by a `fixer`
subagent, each on the model the configuration gives the role. The session keeps everything else. Adds one sentence
to `README.md` and a lint section. No config key (it reads `roles.implementer.model` and `roles.fixer.model` of
iteration 10), no script, no change to the status flow or the slot marker, and no change to
`skills/workflow/SKILL.md` (a hot file): none of `escalation.storyTriggers` applies, so the PR may auto-merge. The
change is in `skills/`, so the manual check of `verification.manualCheckPaths` applies.

## Goal

The code of an approved story or of a bug fix is written by a defined agent with a known model, so that the code
reviewer of #36 can be chosen at least as strong as its author. The session that runs `/next` or `/fix` only
orchestrates: the board, the slot, the CHANGELOG, the pull request.

## Facts this rests on

- Iteration 11 put the rule for picking a role's model in the workflow skill, section "Agent roles and models": the
  model is `roles.<role>.model`, else the schema default, passed explicitly as the `model` of the Agent call; a
  role is never launched as a fork; a model that cannot be used stops the run with a `Stopped:` line and nothing
  starts on another model. This iteration is the first caller of that rule for `implementer` and `fixer`; it
  repeats none of it beyond the two phrases the lint pins and points at the section for the rest.
- Today `/next` (step 2.3 and 2.4) and `/fix` (steps 4 to 6) do the work in the session. `agents/worker.md` is the
  only agent file; the `worker` runs on `haiku` and is for mechanical jobs, so it is not used for this.
- A subagent started with the Agent tool starts in the working directory of the session, not in the slot. A slot is
  a worktree under `worktrees.root`, a different directory, so the prompt names the slot's absolute path and tells
  the subagent to use it for every file and every git command. (The tool's own `isolation: worktree` makes a new
  worktree of its own; it is not used, because the slot is the worktree.)
- A slot is outside the project directory, so the edit permission of iteration 12 (`Edit(**)`) does not cover it.
  Whether a subagent's write there prompts the maintainer, or is refused because a background agent has nobody to
  ask, was **not tested** when this was written; the manual check below observes it. A refused write makes the
  result `failed` or `partial` with the reason; covering slots is the next story of the unattended-runs epic (#47).
- `parallel.maxAgents` and "at most that many agents (subagents, slot builds, your own builds) at the same time"
  are already in the workflow skill and `/next` step 2.2 says "respect" it.

## Decisions

**1. No agent file for the two roles.** The role is the prompt in the skill; the model is passed on the call. An
`agents/implementer.md` would carry a `model:` line that must be kept equal to the schema default by a lint, as
`agents/worker.md` is, for no gain: the Agent call overrides it anyway. One place per role: the schema holds the
default, the skill holds the prompt.

**2. The subagent commits, the session pushes.** The subagent commits its work on the slot's branch once the check
is green and never pushes. The reviewer of #36 can then read a branch with commits, and the CHANGELOG entry and the
spec status line (which need the pull request number) stay a second commit by the session, as today.

**3. The session does not re-run the check to verify the subagent.** It reads the result block and the branch
(`git -C <slot> status --short` empty, `git -C <slot> log origin/<git.baseBranch>..HEAD` not empty). Re-running a
check that takes minutes would double the cost; CI is the independent run, since a PR merges only when its jobs
pass. The check is still run by the session when the session itself commits (the CHANGELOG commit), as today.

**4. The manual check stays with the session.** The subagent runs the automated check and reports whether
`verification.manualCheckPaths` were touched; the session does `verification.manualCheckText` and notes the steps,
because it may need the maintainer (a real project, a real board).

**5. Three outcomes, not two.** The issue says a subagent that "fails or reports a partial result" is handled by the
existing rule for a story only partly done. That rule (file the rest as a new story, link both, the PR still closes
the old issue) needs a pull request to hang on, so it covers a `partial` result with green commits. A `failed`
result has nothing to open a PR for: the session opens no pull request, leaves the status at In progress and the
slot taken, and says so. This is the one place the spec goes beyond the issue's wording; the maintainer may prefer
that a failure also files a story.

**6. A role's work is never done inline.** The workflow skill lets a skill "queue or do the work inline" when the
agent limit is reached. For `implementer` and `fixer` the session queues and never writes the code itself, which is
the point of the story.

## What `/next` does

Step 2.3 and 2.4 of `/next` become the following; steps 2.1, 2.2 and 2.5 to 2.8, the picking section and the hard
rules stay as they are, except where named.

1. **Count.** The slot is taken (2.2) as before. Before the launch the session counts the agents running (the
   workflow rule: subagents, slot builds, its own builds). At `parallel.maxAgents` it waits for one to end and says
   what it waits for; it never writes the code itself instead. The implementer is one agent, and its prompt forbids
   launching others, so it counts as exactly one.
2. **Launch.** One Agent call: a fresh agent (omit `subagent_type`; not `nightmill:worker`), not a fork, with the
   `model` that **Agent roles and models** gives the role `implementer` (`roles.implementer.model`, else the schema
   default), passed explicitly, and the prompt below. When the model cannot be used, the run stops with the line of
   that section for `implementer`; the status stays In progress and the slot stays taken, and the line says both.
3. **Read the result.** The subagent's last message ends with the result block below.
   - `Result: complete` and the branch has commits, tree clean: go on with step 2.4 (the manual check, the session's
     part) and 2.5.
   - `Result: partial`: go on the same way, and 2.7 and 2.8 apply (no auto-merge, the rest filed as a new story, the
     criteria not met are not ticked).
   - `Result: failed`, no result block, or an error: no pull request. Print `Stopped: the implementer returned
     failed: <Left>` plus the branch and the slot, change nothing on the board (it stays In progress), commit and
     push nothing. Never start another agent on the same story in the same run, and never set Ready.
4. **The pull request** (2.6) gets one more line, directly under `Closes #<issue>`:
   `Written by the implementer role on <model>.`, where `<model>` is the exact string passed as `model` in the
   Agent call. Its "How verified" section is written from the result block (tests, check) and from the session's own
   manual check.

### The implementer's prompt

`/next` fills the placeholders and passes this as the prompt. The text is the contract; the lint pins the phrases
in bold.

```markdown
You are the implementer for story #<issue> "<title>" in <owner>/<repo>.

Work only in the slot at <absolute slot path>, on branch <branch>. Use that absolute path for every file and
`git -C <slot path>` for every git command; your working directory is not the slot.

Read the spec <path in the slot> completely: it is the contract. The acceptance criteria of the issue are:
<the criteria, verbatim>. The issue body, in full: <body>.

Do this:
1. Turn each acceptance criterion into a test named for the behaviour it protects, and watch it fail.
2. Implement until the tests pass. <verification.benchRule, when set>
3. Run the check: <verification.check>. When it is green, commit the work on the branch with a message that names
   the story. Never commit red.

**Do not push**, do not open or edit a pull request, do not touch the board, any issue or any status, do not edit
`CHANGELOG.md` or the spec's status line, do not create or switch branches, do not delete files (report them under
Left instead), and **do not launch other agents**. If the spec is unclear or wrong, do not decide it yourself: stop
that part and say so under Left.

End your last message with exactly this block:

Result: complete | partial | failed
Criteria: <one line per acceptance criterion: met or not met, and the test that protects it>
Tests: <the tests added or changed>
Check: <the check's last summary line>, green or red
Commits: <hash and subject, one per line; none>
Manual check: needed | not needed (<the verification.manualCheckPaths touched>)
Left: <what is not done and why; nothing>
```

## What `/fix` does

Steps 4 to 6 of `/fix` become a launch of a `fixer` subagent, the same way: steps 1 to 3 (pick, decide bug or story,
In progress and the slot) and step 7 (the pull request, the status, auto-merge) stay with the session, as do the
hard rules, "Batch mode" and its cap. The session decides that it is a bug (step 2) before the launch; the fixer is
never asked to decide it.

- **Count, launch and read the result** exactly as for `/next`, with the role `fixer` (`roles.fixer.model`) and the
  phrases `Stopped: the fixer role cannot run on <model>` and `Stopped: the fixer returned failed: <Left>`.
- **The fixer's prompt** is the implementer's with these changes: the introduction is "the fixer for bug #<issue>";
  the steps are "write the test that fails for the reason in the issue first, named for the behaviour it protects,
  and watch it fail; fix the cause, not the symptom, with the smallest diff that does it; if the fix changes a rule
  or number that a spec states, correct that spec's text; do not add a CHANGELOG entry; a different problem you
  notice is not yours to fix, name it under Left"; it must not decide that the bug is a story, and says under Left
  when the fix needs one of `escalation.storyTriggers`. The result block replaces `Criteria` and `Tests` with
  `Cause: <one line>`, `Fix: <one line>` and `Test: <name, and how it failed before the fix>`.
- **The pull request** (step 7) gets the line `Fixed by the fixer role on <model>.` under `Fixes #<issue>`, and its
  Cause, Fix and How verified sections are written from the result block.
- **A partial fix** keeps the rule `/fix` already has: the PR says what is left and auto-merge is not enabled.
- **Batch mode.** One fixer at a time, each bug's launch counted, the next bug starts only after the previous
  fixer has returned. A `failed` result is a skip of that bug by the existing rule ("commit what exists to the local
  branch (do not push), leave the status as it is"). A model that cannot be used is **not** a skip: it ends the
  whole run with the `Stopped:` line, because every later bug would fail the same way, and the report lists the
  bugs not started.

## README

In "Agent roles and models", one sentence: `/next` and `/fix` hand the coding to an `implementer` or `fixer`
subagent on the configured model, and the pull request says which model it ran on; the session keeps the board,
the slot, the CHANGELOG and the pull request. The table rows of `/nightmill:next` and `/nightmill:fix` need no
change.

## Tests

Each acceptance criterion of #35 is a test or a manual scenario; names are the behaviour protected. `/next` and
`/fix` are conversations, so the lint pins the wording the behaviour depends on and the manual check does the rest.

**`tests/lint.sh`**, new section "== /next and /fix hand the coding to a subagent":

- `skills/next/SKILL.md` contains: `roles.implementer.model`, `Agent roles and models`, `explicitly`,
  `not a fork`, `parallel.maxAgents`, `never writes the code itself`, `Result: complete | partial | failed`,
  `Written by the implementer role on`, `Stopped: the implementer role cannot run on`,
  `Stopped: the implementer returned failed`, `Do not push`, `do not launch other agents`;
- `skills/fix/SKILL.md` contains the same with `fixer` for `implementer`, `Fixed by the fixer role on`,
  `Cause:`, `Fix:`, `Test:`;
- each of them still contains what the session keeps: `Picking #` (next) or its pick step, `slot`, `gh pr merge`,
  `Never set Ready or Approved`, and `/next` also `CHANGELOG`;
- each of them says `not nightmill:worker` (the launch is a fresh agent, never the mechanical `worker`);
- `agents/` still holds only `worker.md` (no agent file for the two roles, decision 1).

`bash tests/check.sh` stays green.

## Verification

The change touches `skills`, so the manual check applies. In a throwaway project with nightmill installed from this
checkout (`claude --plugin-dir <checkout>`), a board, one Approved throwaway story whose spec asks for a small script
change, and one Ready throwaway bug:

1. **Story, default model.** No `roles` block. `/next`: the session prints `opus`, launches one agent with that
   `model` and the prompt, the subagent writes tests and code in the slot and returns the result block, the session
   adds the CHANGELOG entry and opens the PR, and the PR body says `Written by the implementer role on opus.`
   The status went In progress, Review as before.
2. **Story, configured model.** `roles.implementer.model` set to `sonnet`: the Agent call and the PR line say
   `sonnet`. Set to an empty string: `opus` again.
3. **Bug.** `/fix`: the same with the fixer, the failing test first, and `Fixed by the fixer role on <model>.`
4. **The session does not code.** In 1 and 3 the session makes no edit to a source or test file; its own commit
   touches the CHANGELOG and the spec status line only (read `git show --stat` of each commit on the branch: the
   subagent's commit holds the tests and the code, the session's holds nothing else).
5. **A model that cannot be used.** `roles.implementer.model` set to `no-such-model`: the session prints
   `Stopped: the implementer role cannot run on no-such-model: ...` naming that the status is In progress and the
   slot is taken, and starts nothing on another model. The same for `/fix` and `roles.fixer.model`; in `/fix all`
   the run ends there and lists the bugs not started.
6. **Partial.** A throwaway spec with one criterion that cannot be met: the result is `partial`, the PR says so,
   auto-merge is not enabled, the rest is filed as a new story under the same epic and linked, and that criterion
   is not ticked.
7. **Failed.** A prompt-level failure (for example the check cannot go green): `Stopped: the implementer returned
   failed`, no PR, the status stays In progress, nothing pushed.
8. **Agent limit.** `parallel.maxAgents` set to 1 with another agent running: the session says what it waits for
   and does not write the code itself.
9. **Permissions.** Note what happens when the subagent writes in the slot (a prompt, a refusal, or nothing); the PR
   records it. A refusal is reported by the subagent as `partial` or `failed` with the reason.

The PR's "How verified" lists the nine results and the check.

## Not done

- No review of the code (#36, #37), no tester agent (#42 to #45): until #42 the implementer writes the tests too, as
  the issue says; when the tester arrives, step 1 of the prompt changes.
- No agent file for `implementer` or `fixer`, no `/models` table (#34), no check that a reviewer ranks at least as
  high as its producer (#32).
- Nothing in `skills/workflow/SKILL.md` changes; its "or do the work inline" stays for other work. `/next` and `/fix`
  queue.
- Slots are still outside the project directory and not covered by the edit permission; a subagent's writes there
  may prompt or be refused (see the facts). Covering them is a story of epic #47.
- No retry of a failed or partial subagent with a second agent: `review.maxFixRounds` belongs to the review stories.
- No new rule for a partial bug fix beyond the existing one (no auto-merge, the PR says what is left).
- No change to the status flow, to who sets a status, to the slot marker or to any config key.
