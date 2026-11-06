---
name: workflow
description: The development process of this project under nightmill - the issue board and its status flow, stories versus bugs, specs, the spec gate, worker slots and parallel work, PRs and auto-merge, verification. Load this before touching an issue, a board status, a spec, a worktree slot or a pull request.
---

# The nightmill workflow

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json 2>/dev/null || echo "NO CONFIG: run /nightmill:init first"`

Read the configuration above first. In this text, *the maintainer* is `maintainer.name`, *the board* is
GitHub project `github.projectNumber` of `github.owner`, status names come from `board.statuses`, and
*the check* is `verification.check`. Where this text and the configuration disagree, the configuration wins.

## What lives where

- **Requirements live in GitHub Issues**: epics group stories (`labels.epic`, `labels.story`); bugs are
  defects in shipped behaviour (`labels.bug`). Issue forms are in `.github/ISSUE_TEMPLATE/`.
- **Specs** live in `iterations.specDir`, named by `iterations.specPattern`: exact rules and numbers, a
  "Not done" list, and a status line once delivered. Numbers live only in the spec, never in the issue.
- **Decisions** go in `iterations.decisionsDir`, short and dated. Check there before deciding anything twice.
- **One CHANGELOG entry per iteration** in `iterations.changelog`, newest first.

## The status flow (fixed)

```
Backlog > Ready > Spec > Spec review > Approved > In progress > Review > Done
```

| Status | Meaning | Who sets it |
|---|---|---|
| Backlog | Filed, not reviewed | /story, the maintainer |
| Ready | Acceptance criteria reviewed; an agent may start the spec (or, for a bug, the fix) | **only the maintainer** |
| Spec | An agent is writing the spec | the agent, the moment it picks the story up |
| Spec review | The spec is written and merged; waiting for the maintainer | the agent, when the spec PR is open |
| Approved | The maintainer approved the spec; **any** worker may implement it | **only the maintainer** |
| In progress | Being implemented (stories) or fixed (bugs) | the agent, when it starts |
| Review | A PR is open | the agent, when the PR opens |
| Done | Merged or closed | the PR's `Closes #N`, or the maintainer |

Bugs skip the spec: Ready > In progress > Review > Done.

The board must show the real state at every moment. Set a status the moment the state changes, then
**read it back** (`gh project item-list`) before telling anyone a status. Never set Ready or Approved.
Board automation may overwrite a status seconds after a PR is linked; after opening a PR set Review
again once the link has registered. Look option ids up at runtime (`gh project field-list`); never
keep them in notes.

Four statuses are also set by the board's own **workflows**, not only by an agent: Backlog (item added),
In progress (item reopened), Review (pull request linked, code review approved, code changes requested)
and Done (item closed, pull request merged). Two more workflows add items (all issues and PRs of the
repository, and the sub-issues of an epic) and one archives closed items a day after their last update;
that filter is kept short on purpose, so each board query fetches few items and stays clear of GitHub's
rate limits. The GitHub API cannot create, enable or configure workflows, so the maintainer sets them
once in the board's Workflows settings in the browser; `/init` prints the exact table. If a status stops
moving on its own, read `projectV2.workflows { nodes { name enabled } }` first: replacing the Status
options disables the workflows that pointed at a removed option.

## Stories and bugs

- An agent only works on issues whose status is Ready (spec, or bug fix) or Approved (implementation).
- Every PR closes exactly one story or fixes one bug. `/spec` writes the spec for a Ready story, `/next`
  implements an Approved one, `/fix` fixes a bug, `/story` files a story.
- **Bugs are not iterations**: no spec, milestone, iteration number or CHANGELOG entry. A failing test
  first, then the smallest fix of the cause. A fix that needs one of `escalation.storyTriggers` is a story.
- **A story only partly done**: file the rest as a new story under the same epic (`/story`), link both
  issues, say so in the PR, and let the PR close the old issue. Never leave a half-done issue open or
  tick criteria that were not met.
- **Spec first.** The spec is a PR of its own (docs only, auto-merged). Implementation starts only
  from Approved. A spec that needs changes stays in Spec review while it is revised.

## Picking an issue

`/spec` and `/next` pick their issue by one rule and differ only in the status they take: `/spec` takes a
**Ready** story (`board.statuses.ready`), `/next` an **Approved** one (`board.statuses.approved`).

1. **With a number**, take that issue. An epic or a bug is refused (bugs go through `/fix`). An issue
   whose board status is not the skill's status is refused with one line that names the status found and
   the skill that takes it, for example `#12 is at Spec review, not Ready; /spec only takes Ready stories.`
   Nothing is changed.
2. **Without a number**, list the board (`gh project item-list`, filtered with its own `--jq`; do not pipe it into `python` or `jq`, which the project's permission rule `Bash(gh project *)` does not cover), keep open issues at the skill's status
   that are not epics and not bugs, and take the highest `board.priorityField` (the order of
   `board.priorities`; an item without a priority ranks last). On a tie ask the maintainer which, listing
   the tied issues.
3. **Before the first change** (board, branch, file, slot) print one line:
   `Picking #N "<title>": <status>, <priority>, <reason>`, where the reason is `named by number`,
   `only <status> story` or `highest priority of K <status> stories`.

With nothing at the skill's status the skill changes nothing and says so. `/next` then lists the Ready
stories and points to `/spec N`; it never starts a spec itself.

## Definition of done

Spec approved, every acceptance criterion is a test (in `/next` written first by the `tester`
and seen failing before the code), the check is green, the manual check
(`verification.manualCheckText`) is done when a change touches `verification.manualCheckPaths`, the
PR says how it was verified. `verification.benchRule` applies when set. Tests are mandatory.

## Verify before every commit

Run the check (`/nightmill:check`) before every commit. Never commit red. If CI is red where the local
run was green, fix the local loop, not just the test.

## Agent roles and models

Seven roles do the work of a story. Each runs as a subagent on the model the configuration gives it
(`roles.<role>.model`); the model of the session that orchestrates does not decide who writes or who reviews.

| Role | Does | Produces | Reviewed by |
|---|---|---|---|
| `specWriter` | writes the spec of a Ready story | the spec file | `specReviewer` |
| `specReviewer` | reviews a spec before it goes to Spec review | findings on the spec | the maintainer |
| `tester` | writes the failing tests from the approved spec, before the implementer, and a bug's regression test from the report, before the fixer | the tests | `codeReviewer`, with the change |
| `implementer` | writes the code of an Approved story | the change | `codeReviewer` |
| `codeReviewer` | reviews the change before the pull request opens | findings on the change | the maintainer |
| `fixer` | fixes a bug | the fix and its regression test | `codeReviewer` |
| `worker` | does a mechanical, fully specified job | the job's result, read back by the caller | the caller |

A reviewer ranks at least as high as each role it reviews: `specReviewer` over `specWriter`, `codeReviewer` over
`implementer` and `fixer`. `models.ranking` holds the order.

**Which model.** The model of a role R is `roles.R.model` when the configuration has it as a non-empty string;
otherwise the `default` of `properties.roles.properties.R.properties.model` in
`${CLAUDE_PLUGIN_ROOT}/schema/nightmill.schema.json`. Pass it explicitly as the `model` of the Agent call on every
launch of a role; a model is never inherited from the session, and a launch without one would run on it. A role
is never launched as a fork: a fork runs on the session's model whatever is passed. The `worker` agent follows
the same rule; the `model:` in `agents/worker.md` is only the default for a project without configuration and
equals the schema default.

**When the model cannot be used** (the launch is refused, the model is unknown, or this account cannot run it),
stop. Print `Stopped: the <role> role cannot run on <model>: <the reason>. Nothing was started on another model.`
and change nothing further; a status or file already changed stays, and the line says which. The maintainer fixes
`roles.<role>.model`. A skill never falls back to another model, not to the session's, not to a model of the same
level, not to the `worker`, because a reviewer must not drop below its producer unnoticed.

Work the session does itself is not a role. A role's work goes to a subagent only where a skill's own steps say so.

## Findings and fix rounds

A reviewer role reports its findings in one format, and the producer it reviewed fixes the blocking ones in rounds.

The last message of a reviewer ends with exactly this block:

```
Review: findings | no findings
Blocking: <n>
Advisory: <n>
- blocking <file>:<line> <what is wrong, one line>
- advisory <file>:<line> <what is wrong, one line>
```

`<file>` is relative to the root of the repository and `<line>` is the line after the change; a finding about something
missing (a test that is not there) names the file where it belongs and `-` as the line. `no findings` is an explicit
result, with `Blocking: 0` and `Advisory: 0` and no finding lines. The two counts equal the number of finding lines of
each kind. A reply that is not of this form is no review.

**Blocking** is a finding that breaks something the story promised or the project requires: a criterion without a test
or with only tests that would not fail for a wrong implementation, a tester's test removed, skipped,
loosened or made conditional, a change that does not do what the spec says, work beyond the spec, a violated invariant,
an item of the "Not done" list done anyway, a check that is not green. Everything else is **advisory**. Advisory findings are reported and never
sent back.

**Rounds.** The first review is round 0. While blocking findings remain and fewer than `review.maxFixRounds` fix rounds
have been used, the producer fixes exactly the blocking findings (a new agent of the same role and model, never a
fork), runs the check and commits, and the reviewer runs again. A story is reviewed at most `1 + review.maxFixRounds`
times; with `review.maxFixRounds` at 0 it is reviewed once and nothing is sent back. A reviewer is a fresh agent every
time and never sees the producer's own account of its work.
In `/next` and `/fix` the same rounds also pay for a dispute over a tester's test (the tester answers, then a new
producer runs) and for a round undone because the producer changed the tester's tests: each costs one of
`review.maxFixRounds`, and `Fix rounds used` counts them. In `/next` and `/fix` a blocking finding of the code reviewer
whose text begins with `test: ` is a test finding, whatever file it names: it goes to the `tester`, the others to the
producer, in the same fix round, which costs one of `review.maxFixRounds` whatever it holds; a test finding the tester
answered `stands:` is not sent to it again, and a round in which the tester answered every test finding `stands:`, added
no file and there is no code finding ends the rounds.

**The pairing.** Before a reviewer is launched, the reviewer's model must rank at least as high as the producer's. A
skill checks it with the validator (`validate-config`) and stops, naming both roles and both models, when the validator
reports `<reviewer> on "<model>" ranks below <producer> on "<model>"`; it never compares ranks itself.

**A review that cannot be had** (the model cannot be used, no valid block, an error) stops the run; it is never read as
"no findings".

**The pull request.** A pull request that went through a review has a section `## Review`, after "How verified", in
this form (the lines are the same for a story and for a bug; `<producer>` is `implementer` or `fixer`):

```
## Review

- Reviewer: codeReviewer role on <model>
- Author: <producer> role on <model>
- Fix rounds used: <r> of <review.maxFixRounds>
- Findings fixed: <n>
- Findings still open: <b> blocking, <a> advisory
```

It is followed by one line per fixed finding, `fixed in round <k>: blocking <file>:<line> <text>`, and one line per open
finding exactly as the reviewer wrote it in its last review, `- blocking <file>:<line> <text>` or
`- advisory <file>:<line> <text>`. `<model>` is the exact string passed as `model` in the Agent call. The findings still
open are those of the last review; the findings fixed are the blocking findings that were sent back in an earlier round
and are not repeated in the last review with the same file and text (the line is not compared). With no findings the
counts are 0 and there are no finding lines. With a blocking finding still open the pull request is opened all the
same, the section says so, and the pull request says
`Auto-merge is not enabled: blocking review findings are still open (see Review).`

A spec pull request has the same section with `specReviewer role on <model>` as the reviewer and `specWriter role on
<model>` as the author, after the two lines `Spec for #<issue>.` and `Written by the specWriter role on <model>.` (it
has no "How verified"); when a blocking finding is still open the comment on the issue says so (see `/spec`).

## Parallel work

- One task per slot. Slots are permanent worktrees with warm build output; take one with the slot
  script (`-Take <branch>`), free it after the merge (`-Release N`), list them (`-Status`). The
  scripts are at `${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1` and `${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh`. A skill
  that works in a slot reports each step with `-Report <step>` / `--report <step>` (the steps are in `/next` and
  `/fix`), and `/status` shows the slot `running` while the last report is at most `worktrees.stalledAfterMinutes`
  old, `stalled` after that (also a slot that waits for its merge after its last step, `done`), `unknown` without a
  report.
- At most the agent limit agents (subagents, slot builds, your own builds) at the same time. The limit is the live
  value set during the session, else `parallel.maxAgents`. Read it at every decision to start an agent, never once per
  session: `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Capacity -Porcelain` or
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --capacity --porcelain` (the line `agents`, second field). When the
  command fails, use `parallel.maxAgents` of the configuration and say so. Before launching one, count the running
  ones; queue or do the work inline otherwise. A lowered limit stops no running agent: wait until fewer run than it
  says. The slot count is changed the same way (`-Capacity -SlotCount N`, `--capacity --slot-count N`); a raised count
  is used by the next take.
- **Room on the machine.** When the count allows a start (a subagent, a slot build such as a take's warm-up, your own
  build), check right before it that the machine has room, after the count and before the step report of that launch
  (only a `dispute-<k>` step is reported before its count):
  `"${CLAUDE_PLUGIN_ROOT}/scripts/room.ps1"` or `bash "${CLAUDE_PLUGIN_ROOT}/scripts/room.sh"`. Exit 0: start; say a
  `not checked: unavailable` line once per run. Exit 1: say its `room: waiting` line, then run it again at once with
  the value of its `room: call again with` line (`-Since <n>`, `--since <n>`; the script has paused), until another
  exit code; then count again before the start. Exit 3: start nothing and print
  `Stopped: no room on this machine to start the <role, slot, manual check or check> after <w> min: <the details of its gave-up line>. Nothing was started.`
  The check itself commits, pushes, reverts, stops or releases nothing, and the board status stays. In `/next` and
  `/fix` the slot (taken or not), the branch and the files stay as they are; `/spec` does its clean-up of "The spec
  writer" step 5, as for its other `Stopped:` lines. Exit 2, or a script that cannot run: say once per run
  `The room check failed: <its standard error on one line>; starting without it.` and start.
  The check never changes the agent limit, stops an agent or releases a slot; `parallel.roomCheck` false turns it off.
- Not two tasks over the same files; `parallel.hotFiles` stay with one task. Never pair
  `parallel.doNotPair`. Rebase on the base branch before the PR.
- Prefer a fresh agent with a short, specific prompt over a fork. Give a role's agent the model that **Agent roles
  and models** gives it.
- Do not launch agents just to wait on a dependency; start them when it has merged.

## CI and merging

CI runs on every push and PR to `git.baseBranch`; a PR merges only when its blocking jobs pass.
After opening a PR run `gh pr merge <n> <git.mergeFlags>` (never a plain `gh pr merge`: an admin
bypass would let a red PR through) when it is a story whose spec was approved, a spec PR, or a
complete bug fix. Do not, and say why in the PR, when it changes one of `escalation.storyTriggers`,
is partial, skips a required manual check, has a blocking review finding still open (a spec PR too), or the
maintainer asked to review it. A red PR is fixed, never forced.

## Hard rules

Never set Ready or Approved. Never close an epic. Never delete files without asking. Never push to
the base branch. Never merge any other way than with `git.mergeFlags`.
