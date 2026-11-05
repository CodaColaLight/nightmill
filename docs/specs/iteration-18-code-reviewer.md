# Iteration 18: a separate code reviewer reviews the change before the pull request opens

Status: delivered in iteration 18 (PR #75)

Story: #36, epic #29 (Independent code review). Adds the agent `agents/code-reviewer.md`, a new section "Findings and
fix rounds" in `skills/workflow/SKILL.md`, and a review step in `skills/next/SKILL.md` and `skills/fix/SKILL.md`: after
the implementer (or fixer) has returned with a green check and before the pull request opens, a `codeReviewer`
subagent on the model the configuration gives the role reads the change, reports findings in one fixed format, and
what is blocking goes back to a new implementer (or fixer) for at most `review.maxFixRounds` fix rounds. Adds a lint
section and one README sentence. No config key (it reads `roles.codeReviewer.model` and `review.maxFixRounds` of
iteration 10), no script, no change to the status flow or the slot marker: none of `escalation.storyTriggers`
applies, so the PR may auto-merge. The change touches `skills` and `agents`, so the manual check applies.
`skills/workflow/SKILL.md` is a hot file: no other task may change it while this one is in flight.

## Goal

Before a pull request opens, a different agent, on a model at least as strong as the author's, reviews the change
against the spec and the project's rules, and the author fixes what is found.

## Facts this rests on

- Iteration 13 made `/next` and `/fix` launch an `implementer` or `fixer` subagent (a fresh agent, never a fork, never
  the `worker`, the model passed explicitly, counted against `parallel.maxAgents`), commit its work when the check
  is green, and return a result block (`Result:`, `Check:`, `Commits:`, ...). The session reads the result and the
  branch, then continues with the manual check, the CHANGELOG entry and the pull request. This iteration inserts the
  review between "read the result" and "the manual check".
- The workflow skill's "Agent roles and models" defines how a model is picked (`roles.<role>.model`, else the schema
  default, passed explicitly) and what happens when it cannot be used (`Stopped: the <role> role cannot run on
  <model>: ...`, nothing started on another model). `codeReviewer` is one of the seven roles; its default is `opus`.
- Iteration 15 gave the validator the pairing rule: `codeReviewer` must rank at least as high as `implementer` and
  `fixer`, an error line `codeReviewer on "<m1>" ranks below implementer on "<m2>"` on the path
  `roles.codeReviewer.model`. The skills can run the validator (`validate-config`, either shell) and read that line
  instead of comparing ranks themselves.
- `review.maxFixRounds` (default 2, minimum 0) is "how many times a producer may fix what its reviewer found before the
  work is handed to the maintainer".
- A plugin's agent is addressed as `nightmill:<name>` (the `worker` is `nightmill:worker`). An agent file may list the
  tools the agent gets (`tools:`); an agent without `Bash`, `Write` and `Edit` cannot change a file, and one without
  `Agent` cannot start another agent. `agents/worker.md` has `model: haiku`, kept equal to the schema default by the
  lint ("agent roles are defined in the workflow skill"); the call's `model` overrides it.
- The slot is a worktree outside the project directory, so a read there may prompt where the project allows only
  reads inside it. This was **not tested** when this was written; the manual check observes it. A refused read
  makes the review fail, and a review that fails stops the run (decision 6).
- #37 (the review section of the pull request and the auto-merge rule) and #30 (the spec review) follow this story.
  #30 reuses the findings format and the fix rounds, which is why they are written once in the workflow skill.

## Decisions

**1. An agent file for the reviewer, none for the producers.** Iteration 13 decided against an agent file for the
implementer and the fixer because the prompt and the model are all they need. The reviewer is different: it must not
change anything, and an agent definition can say so with a tool list (`Read`, `Grep`, `Glob`), which is stronger than
a sentence in a prompt. So `agents/code-reviewer.md` exists, its `model:` line is kept equal to the schema default of
`roles.codeReviewer.model` by the lint (as for the `worker`), and the call overrides it explicitly as always.

**2. The reviewer gets facts, not the implementer's story.** The prompt carries the issue's acceptance criteria, the
spec's path, the invariants of the configuration, the diff of the branch against the base, and the implementer's
`Check:` line (a fact, not an opinion). It does not carry the implementer's own account (its `Criteria`, `Left` or
`Decisions` lines) or any of its transcript: the reviewer shares no context with it, so it cannot be talked into
agreeing. It runs without `Bash`, so it does not re-run the check; "the check is green" is read from the `Check:`
line, and CI is the independent run.

**3. Only blocking findings go back.** A finding is **blocking** when it breaks something the story promised or the
project requires: an acceptance criterion without a test, a change that does not do what the spec says, work beyond
the spec, a violated invariant, an item of the spec's "Not done" list done anyway, a check that is not green. Anything
else (naming, small style, a possible simplification) is **advisory**. Advisory findings are reported and never
fixed in the loop.

**4. A fix is a new agent.** The implementer is a one-shot subagent. A fix round launches a fresh implementer (or
fixer), on the same role model, with the same prompt as before plus the blocking findings and the instruction to fix
only those, run the check and commit. It has no memory of the first run; the findings and the spec are its input.

**5. Rounds.** The first review is round 0. With blocking findings and fewer than `review.maxFixRounds` fix rounds
used, run a fix round, then the review again; so a story gets at most `1 + review.maxFixRounds` reviews. With
`maxFixRounds` 0 the change is reviewed once and nothing is sent back.

**6. A review that cannot be obtained stops the run.** A launch the model cannot take, a reviewer that returns no
findings block, or an error: the session stops. It never opens the pull request as if the review had found nothing.

**7. Until #37, blocking findings left over stop auto-merge.** When the fix rounds are used up and blocking findings
remain, the session still opens the pull request, lists them under a plain heading and does not enable auto-merge,
because a pull request that merges by itself over a known blocking defect is the thing this story exists to prevent.
#37 replaces the plain heading with the full review section and the rule in "CI and merging".

## The agent

`agents/code-reviewer.md`:

```markdown
---
name: code-reviewer
description: Reviews a change against its spec and the project's rules before the pull request opens. Reads only, changes nothing, and reports findings in one fixed format. Used by /next and /fix on the codeReviewer model.
tools: Read, Grep, Glob
model: opus
---
```

and a body that says, in this order:

1. You review a change you did not write, with fresh eyes. You change nothing: no file, no board item, no pull
   request, no branch. You start no other agent and you ask no questions; you work from the prompt and from what you
   can read.
2. Check, and say so in a finding when it fails: every acceptance criterion has a test that would fail without the
   change; the change does what the spec says and nothing beyond it; no item of the spec's "Not done" list was done;
   every invariant of the project holds; the `Check:` line in the prompt reports green (a missing or red line is a
   blocking finding).
3. A finding is **blocking** (it breaks one of the points above) or **advisory** (anything else). Do not pad: report
   what you can point at.
4. End your last message with exactly the block of "Findings and fix rounds" in the workflow skill, and nothing after it.

The body repeats the format so that the agent file is complete by itself; the lint compares the format lines of the
agent with those of the workflow skill.

## The workflow skill: "Findings and fix rounds"

A new section `## Findings and fix rounds` in `skills/workflow/SKILL.md`, after "Agent roles and models" and before
"Parallel work". It is the contract of #36 and #30. Its text:

```markdown
## Findings and fix rounds

A reviewer role reports its findings in one format, and the producer it reviewed fixes the blocking ones in rounds.

The last message of a reviewer ends with exactly this block:

Review: findings | no findings
Blocking: <n>
Advisory: <n>
- blocking <file>:<line> <what is wrong, one line>
- advisory <file>:<line> <what is wrong, one line>

`<file>` is relative to the root of the repository and `<line>` is the line after the change; a finding about
something missing (a test that is not there) names the file where it belongs and `-` as the line. `no findings`
is an explicit result, with `Blocking: 0` and `Advisory: 0` and no finding lines. The two counts equal the number of
finding lines of each kind. A reply that is not of this form is no review.

**Blocking** is a finding that breaks something the story promised or the project requires: a criterion without a
test, a change that does not do what the spec says, work beyond the spec, a violated invariant, an item of the "Not
done" list done anyway, a check that is not green. Everything else is **advisory**. Advisory findings are reported and
never sent back.

**Rounds.** The first review is round 0. While blocking findings remain and fewer than `review.maxFixRounds` fix rounds
have been used, the producer fixes exactly the blocking findings (a new agent of the same role and model, never a
fork), runs the check and commits, and the reviewer runs again. A story is reviewed at most `1 + review.maxFixRounds`
times; with `review.maxFixRounds` at 0 it is reviewed once and nothing is sent back. A reviewer is a fresh agent every
time and never sees the producer's own account of its work.

**The pairing.** Before a reviewer is launched, the reviewer's model must rank at least as high as the producer's. A
skill checks it with the validator (`validate-config`) and stops, naming both roles and both models, when the
validator reports `<reviewer> on "<model>" ranks below <producer> on "<model>"`; it never compares ranks itself.

**A review that cannot be had** (the model cannot be used, no valid block, an error) stops the run; it is never read as
"no findings".
```

Together with `Reviewed by` in the roles table this is all the workflow skill says about reviews; the section does not
say what happens to blocking findings left after the last round: that is the skills' step (decision 7) until #37.

## `/next` and `/fix`

After the producer's `Result:` block has been read (and not `failed`) and before the manual check, in `/next` step 2.4
(a new step 4 "Review", the later steps keep their order and move down by one) and in `/fix` between steps 4 and 5:

1. **The pairing.** Run `validate-config` of the shell in use on the project's config
   (`"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config <project>/.claude/nightmill.json`, or
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" <project>/.claude/nightmill.json`). When it reports a line
   on `roles.codeReviewer.model` with the text `ranks below`, stop with
   `Stopped: the codeReviewer ranks below the implementer: <the text of that line>. Nothing was reviewed; the status of
   #<issue> is In progress and the slot is taken.` (`fixer` for `/fix`; the line may name the other producer, then name
   it). When the validator cannot run (exit code 2, missing script), stop with
   `Stopped: the pairing could not be checked: <the reason>. Nothing was reviewed.` A model of the reviewer that is not
   in `models.ranking` is only a warning of the validator and does not stop the run.
2. **Count and launch.** Count the agents as for the producer. One Agent call: `subagent_type` `nightmill:code-reviewer`,
   not a fork, with the `model` that **Agent roles and models** gives `codeReviewer` (`roles.codeReviewer.model`, else
   the schema default), passed explicitly. When the model cannot be used, stop with that section's line for
   `codeReviewer`, naming the status and the slot.
3. **The prompt**, filled in by the session:

   ```markdown
   Review the change on branch <branch> in the checkout at <absolute slot path> (use that path for every file you
   read) for story #<issue> "<title>" (bug #<issue> for /fix).

   The acceptance criteria of the issue (the bug report for /fix): <verbatim>.
   The spec: <path in the slot> (read it; for /fix, the spec the bug touches, if any).
   The invariants of the project: <config invariants, one per line>.
   The implementer's check: <its Check: line>.

   The change, as `git diff <base>...<branch>`: <the diff; when it is longer than 2000 lines, the --stat and the
   instruction to read the files>.

   End with the findings block of the workflow skill, and nothing after it.
   ```
4. **Read the block.** Valid and `no findings`: go on. Valid with findings: **advisory only**: go on and keep them. With
   **blocking**: while fewer than `review.maxFixRounds` fix rounds have been used, launch the fix (a fresh implementer or
   fixer, as in the producer's step, with its prompt and, added at the end, "Fix exactly these blocking findings and
   nothing else, run the check, commit": <the blocking lines>), read its `Result:` block as before (`failed` stops the
   run as for the producer), and review again from step 2 (the pairing is checked once, not again).
   No valid block, or an error: stop with `Stopped: the code review could not be had: <the reason>. Nothing was opened.`
5. **After the last review.** Blocking findings that remain are listed in the pull request under the heading
   `Open review findings` (each as in the block) and auto-merge is **not** enabled; the pull request says so. Advisory
   findings are listed under `Review notes`, one line each. The pull request gets one line under the producer's line:
   `Reviewed by the codeReviewer role on <model> after <r> fix round(s).`

The manual check, the CHANGELOG entry, the pull request, the statuses and every hard rule stay with the session as
before. A `partial` result is reviewed like a complete one.

## README

In "Agent roles and models", one sentence: before a pull request opens, `/next` and `/fix` have a `codeReviewer`
subagent on its configured model review the change and send the blocking findings back to the implementer or fixer for
at most `review.maxFixRounds` rounds; the findings format and the rounds are in the workflow skill.

`.claude/CLAUDE.md`, the layout line `agents  worker.md` becomes `agents  worker.md, code-reviewer.md`.

## Tests

Each acceptance criterion of #36 is a test or a manual scenario. `/next` and `/fix` are conversations, so the lint
pins the wording the behaviour depends on and the manual check does the rest.

**`tests/lint.sh`**, new section "== a separate code reviewer reviews the change":

- `agents/code-reviewer.md` exists with `name: code-reviewer`; its `tools:` line is exactly `Read, Grep, Glob` (so it
  has no `Bash`, `Write`, `Edit` or `Agent`); its `model:` line equals the schema default of
  `roles.codeReviewer.model`; its body says that it changes nothing and contains `acceptance criterion`,
  `Not done`, `invariant`, `Check:`, `blocking`, `advisory` and `no findings`;
- `skills/workflow/SKILL.md` has a line that is exactly `## Findings and fix rounds`, and that section contains
  `Review: findings | no findings`, `- blocking <file>:<line>`, `- advisory <file>:<line>`, `review.maxFixRounds`,
  `1 + review.maxFixRounds`, `validate-config`, `ranks below`, `never sees the producer's own account` and `is never
  read as`; the format lines of the section equal the format lines of `agents/code-reviewer.md`;
- `skills/next/SKILL.md` and `skills/fix/SKILL.md` each contain `nightmill:code-reviewer`, `roles.codeReviewer.model`,
  `Findings and fix rounds`, `validate-config`, `Stopped: the codeReviewer ranks below`, `Stopped: the code review could
  not be had`, `Open review findings`, `Reviewed by the codeReviewer role on` and `not a fork`;
- the check "no agent file for the implementer and the fixer" of iteration 13 now allows exactly `agents/worker.md` and
  `agents/code-reviewer.md` and still rejects any other file under `agents/`;
- the section "agent roles are defined in the workflow skill" still passes (the new section does not remove a phrase).

`bash tests/check.sh` stays green.

## Verification

The change touches `skills` and `agents`, so the manual check applies. In a throwaway project with nightmill installed
from this checkout (`claude --plugin-dir <checkout>`), a board and an Approved throwaway story (and a Ready throwaway
bug for `/fix`):

1. **A planted defect is caught and fixed.** A story whose spec makes the implementer likely to leave a criterion
   without a test (or a planted failing detail in the spec): `/next` runs the implementer, then the reviewer returns a
   block with a `blocking` finding naming the file and line, a fix round runs a fresh implementer, the check runs, the
   reviewer runs again and returns `Review: no findings`; the pull request says `Reviewed by the codeReviewer role on
   opus after 1 fix round(s).`
2. **No findings is explicit.** A trivial story: the reviewer returns `Review: no findings`, `Blocking: 0`, `Advisory: 0`
   and the run goes on without a fix round.
3. **Advisory only** goes on, is listed under `Review notes` and does not block auto-merge.
4. **Rounds are used up.** A planted defect the implementer cannot fix (a spec that cannot be met): after
   `review.maxFixRounds` rounds the pull request is opened with `Open review findings`, auto-merge is off and the
   pull request says why. With `review.maxFixRounds` at 0 the change is reviewed once and nothing is sent back.
5. **The reviewer changes nothing.** `git status` of the slot and the board are unchanged by the review; the agent
   has no `Bash`, `Write` or `Edit`.
6. **The pairing stops the run.** `roles.codeReviewer.model` set to `haiku`: `Stopped: the codeReviewer ranks below the
   implementer: ...`, nothing reviewed, no pull request. A `no-such-model` for the reviewer: the `Stopped:` line of the
   workflow skill for `codeReviewer`.
7. **`/fix` does the same** with a planted defect in a bug fix and the fixer.
8. **Permissions.** Note whether the reviewer's reads inside the slot prompt or are refused; a refused read ends in
   `Stopped: the code review could not be had`.

The PR's "How verified" lists the eight results and the check.

## Not done

- No review section in the pull request body with the reviewer's model, the implementer's model, the rounds and the
  fixed findings, and no rule in "CI and merging": that is #37. This story only keeps auto-merge off when blocking
  findings remain and lists them.
- No spec review (#30, #39, #40): it reuses the findings format and the rounds written here.
- No tester agent (#42 to #45): the reviewer checks that every criterion has a test, whoever wrote it.
- No run of the check by the reviewer, no comment on the issue or label for findings, no new board status.
- No change to the status flow, to who sets a status, to the slot marker or to any config key; no script.
- No agent file for the implementer, the fixer or the spec writer.
