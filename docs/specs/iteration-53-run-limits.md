# Iteration 53: limits per issue, per role and per run, a pause flag and a run ledger bound what an unattended run spends

Status: delivered in iteration 53 (PR #274)

Story #165, epic #163 (capabilities of comparable tools), gap 2 of the gap analysis of 2026-11-05. Today only `/fix all`
caps its work (`parallel.fixAllMaxBugs`), no skill reads a pause flag, and nothing records what a headless run cost.
Iteration 52 (#164; its spec is on `main` as `docs/specs/iteration-52-unattended-driver.md`) adds the driver `scripts/drive.*` with a run-wide time limit
(`unattended.maxMinutes`), a local kill switch (`.git/nightmill-stop`) and the cost of each step in its summary, and
leaves the rest to this story (its decision 1). After this iteration a new object `limits` in the config bounds the
minutes per issue, the turns per role, the issues per run and the cost per issue, and holds the pause flag; a new
script, `scripts/gate.sh` and `scripts/gate.ps1`, checks the pause flag (in the base branch's config, or the label
`paused` on the issue's epic) and the limits, and the skills that change anything run it before every step; the driver
runs it before every step too, starts every `claude -p` with `--max-turns` and `--max-budget-usd`, and appends one
`run` line per headless run to the existing record `<worktrees.root>/.slots/ledger.tsv`; a breached limit labels the
issue `blocked`, comments why and stops that issue's work, setting no status. `/check` is already bounded (#124,
Facts); it only gets the gate. Changes `scripts/gate.sh` and `scripts/gate.ps1` (new), `scripts/drive.sh` and
`scripts/drive.ps1` (from iteration 52), `schema/nightmill.schema.json`, `templates/nightmill.example.json`,
`skills/workflow/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/spec/SKILL.md`,
`skills/check/SKILL.md`, `skills/story/SKILL.md`, `skills/control/SKILL.md`, `skills/init/SKILL.md`, `README.md`,
`tests/smoke-gate.sh` and `tests/smoke-gate.ps1` (new) with fixtures under `tests/fixtures/gate/`,
`tests/smoke-drive.sh` and `tests/smoke-drive.ps1`, `tests/smoke-stages.sh` and `tests/smoke-stages.ps1`,
`tests/test-limits-docs.sh` (new), `tests/test-drive-docs.sh`, `tests/test-unattended-docs.sh`, `tests/lint.sh`,
`tests/check.sh`, `.github/workflows/ci.yml` and `CHANGELOG.md`.

## Story trigger and manual check

**A story trigger: new config keys.** Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The gate and the driver set no status and add none; a breach
  leaves the board status where the run left it (decision 9). `blocked` and `paused` are labels, not statuses; the
  eight statuses and who sets them do not change, so no decision record is needed. None of `docs/decisions/` 0001 to
  0003 is touched: they say how nightmill develops and releases itself.
- *A new, renamed or removed config key*: **yes**, a new object `limits` with `paused`, `minutesPerIssue`,
  `turnsPerRole.<role>` (eight roles), `issuesPerRun` and `costPerIssueUsd` (decision 2). Each goes into
  `schema/nightmill.schema.json` with a description and a default, into `templates/nightmill.example.json` and into
  the README's configuration table. Nothing is renamed or removed; `parallel.fixAllMaxBugs`, `unattended.maxMinutes`
  and `unattended.summaryIssue` stay as they are. **Compatible** (invariant not ticked, checked anyway): the schema
  says "Unknown keys are ignored", and the previous version's `validate-config` reports an unknown top-level key as a
  warning, not an error (`scripts/lib/validate.awk`), so a config with `limits` stays readable by it. The new `run`
  lines in `ledger.tsv` are skipped by the previous version's `stages.*`, which reads only the kinds `take`, `step`
  and `free` (`scripts/lib/stages.awk` line 56; iteration 41 decision 1 reserved the kind `run` for this story).
- *A change to the slot marker format*: no. No marker, field or file named `slot-*.json` changes; the slot scripts are
  not touched. `ledger.tsv` is not a marker, and the gate only reads it.

**The manual check applies**: `skills/` changes (`verification.manualCheckPaths`). Its steps are under Tests. The
config-governs-itself rule (#111, iteration 48) is kept: the gate reads `limits` only from the base branch's
configuration with `scripts/lib/baseconfig.*` (decision 4), so a branch cannot unpause or raise the limits of its own
run.

**Both shells** (invariant ticked): `scripts/gate.sh` and `scripts/gate.ps1` have the same arguments, lines and exit
codes, each with a smoke test (`tests/smoke-gate.sh`, `tests/smoke-gate.ps1`) in the step list of `tests/check.sh`,
in the matching `--only` list of `ci.yml` and in the README (iteration 51's agreement lint). The driver's changes are
made in both of iteration 52's files and get cases in both of its smoke tests.

**Order with other work.**

- *Iteration 52 (#164)* must be merged first: this spec changes `scripts/drive.*`, `tests/smoke-drive.*`,
  `tests/test-drive-docs.sh` and the README section `## Running on a schedule`, which it creates. It is written
  against its spec on `main` (`docs/specs/iteration-52-unattended-driver.md`); where the merged code differs in a name or a line,
  the implementer follows the merged code and keeps the rules below.
- *Iteration 45 (#213, the skills grant their own scripts)* has a draft spec and is open. If it lands first, `gate`
  is granted in each gating skill's `allowed-tools` as that spec grants `room`, instead of group D of `/init`'s
  **Run permissions** (decision 11); the rest is unchanged.
- `skills/workflow/SKILL.md` and `schema/nightmill.schema.json` are in `parallel.hotFiles`, and `parallel.doNotPair`
  forbids two tasks that both change the schema: this iteration is not implemented beside another schema change.
- *#166 (history and metrics)* will read the `run` lines; their fields are fixed here (decision 7).

## Facts this rests on

Read on `main` at 757012e (iteration 51 merged) on 2026-11-10, and iteration 52's spec, now on `main` as
`docs/specs/iteration-52-unattended-driver.md`. `claude --version` prints
`2.1.322 (Claude Code)`; `claude --help` was read, no other `claude` command was run.

- **`/check` is already bounded** (#124, closed): `skills/check/SKILL.md` says "Re-run the check after each fix, at
  most three attempts in all; when the third attempt still fails, stop and report the failing step and what was
  tried", tells an environmental failure from a code failure, and allows fixing a test written in the same task.
  `tests/test-check-skill.sh` pins it and is a step of `tests/check.sh`. Criterion 6 holds on `main`.
- **Today's limits.** `/fix all` has `parallel.fixAllMaxBugs` (default 0: no limit) and a gate before each start
  whose text says "The pause flag and the limits of an unattended run, once they exist, are checked there before each
  start, by the rules that set them. A pause stops new starts." No other skill limits issues, time, turns or cost.
  Review rounds are bounded by `review.maxFixRounds`, a watch by `review.watchChecksMinutes`.
- **Iteration 52 (approved spec).** It takes `unattended.maxMinutes` (default 240; no step starts after it), the
  kill switch `nightmill-stop` in the git common directory (read only by the driver, before every step), one driver per
  repository (a lock), and `total_cost_usd` and `num_turns` of each step's `--output-format json` result for its
  summary. Each step is exactly `claude -p "/nightmill:fix all" ...` or `claude -p "/nightmill:next <N>" ...` with
  `--permission-mode manual --output-format json`; its decision 1 leaves "a turn or budget flag on the `claude -p`
  line (`--max-turns`, `--max-budget-usd`)" to #165 and says #165's pause flag and limits join its checks before every
  step (decision 3 step 1). Its decision 9 says the driver adds no label and its only GitHub write is the summary
  comment; its `tests/test-drive-docs.sh` part S forbids `issue edit` in `scripts/drive.*`. It writes no ledger.
- **The headless flags.** `claude --help` of 2.1.322 lists `--max-budget-usd <amount>` ("Maximum dollar amount to
  spend on API calls (only works with --print)") and `--output-format json`; it does **not** list `--max-turns`,
  which iteration 52 names and earlier Claude Code documentation describes for print mode. Whether 2.1.322 accepts it,
  and the `subtype` its result carries when a turn or budget limit ends a run, is settled by the probe (Tests).
- **The stage record** (iteration 41): `<worktrees.root>/.slots/ledger.tsv`, UTF-8, LF, 11 tab-separated fields,
  append-only, written today only by `scripts/slot.*` through `ledger_append` of `scripts/lib/ledger.*`; field 1 is the
  kind and field 2 the UTC stamp for every kind; "#165's run lines go into the same file, as lines of their own kind
  (`run`)", readers skip a kind they do not know (decision 1), and #165 settles its fields after field 2 (Left).
  A `take` line has the slot in field 3 and the claim's UTC stamp in field 9. The root is `worktrees.root` relative to
  the main checkout, default `../<main folder>-wt` (`scripts/stages.sh` lines 35 to 37), so with the default the
  file is outside the repository and never tracked.
- **The configuration that governs a run** is the base branch's (`scripts/lib/baseconfig.*`, iteration 48 decision 1):
  `origin/HEAD`, then `git.baseBranch`; the working tree's file only without a remote branch or before the base has
  one; no fetch.
- **The `blocked` label** exists: `/init` creates it (`000000`, "Waiting on another issue (name it in the body)"), and
  **Watching the checks** adds it with `gh issue edit <issue> --add-label blocked` at a hand-over, printing
  `The label blocked could not be added: <the first line of gh's message>; /init creates it.` when that fails. No
  `paused` label exists. Label names other than `blocked` come from `labels`.
- **Epics.** A story or bug is a sub-issue of its epic (`/story` step 5 attaches it; the board adds sub-issues of an
  epic). GraphQL `Issue.parent` names it. The guard (iteration 50) refuses GraphQL mutations not on its list and lets
  queries pass.
- **Run permissions.** A skill runs a plugin script as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" ...`, granted
  by group D of `/init`'s **Run permissions** for `slot`, `room`, `validate-config` and `status` (8 rules); the count
  is `24 + 21 × worktrees.slots`, pinned by `tests/lint.sh` (`'24 + 21'`) and in the README (66 for 2 slots).
- **The validator** reads `type`, `minimum`, `enum`, `pattern`, `not` and `additionalProperties`; it ignores
  `maximum` (`scripts/lib/validate.awk`), so a range's upper end is checked by the script that reads the key, as
  `slot`, `room` and iteration 52 do.
- **The skills' steps.** `/next` and `/fix` report every step to the slot ("Reporting the steps"); every launch of a
  role, every take and the manual check are preceded by the room check (**Room on the machine** in the workflow skill),
  whether or not `parallel.roomCheck` turns that check off. Claude Code's result of an Agent call ends with a usage
  block that names the launch's `tool_uses` (seen in this session's own Agent results; the probe checks it for a
  headless run).

## Decisions

**1. How this fits iteration 52.** Iteration 52 gives a driver run its run-wide limits; this story gives every run
(driver or not) its per-issue, per-role and per-run limits and the project-wide pause. Nothing of iteration 52 is
removed:

| | Kill switch (iteration 52) | Pause flag (this story) |
|---|---|---|
| Where | the file `nightmill-stop` in the git common directory | `limits.paused` in the base branch's config, or the label `paused` on the issue's epic |
| Reaches | the driver on this machine | every gating skill and every driver, on every machine |
| Read by | the driver only, before each step | `scripts/gate.*`: the gating skills before every step, the driver before every step |
| Set by | `touch .git/nightmill-stop` | a merged change of the config, or a label on the epic |
| Effect | the driver starts no further step | no further step starts; a running step stops at its next step |

| | `unattended.maxMinutes` (iteration 52) | `limits.*` (this story) |
|---|---|---|
| Bounds | one driver run's wall clock | one issue's minutes in a run, one issue's cost over all runs, one role's turns per launch, one run's issues |

The record: `ledger.tsv` of iteration 41 is **the** run ledger. This story adds the kind `run` (decision 7), written by
the driver only; the stage lines (`take`, `step`, `free`) are unchanged, and `stages.*` keeps skipping the new kind.
Iteration 52's summary keeps its cost line; the ledger is the durable record it did not have.

**2. The config keys.** A new object `limits`, every key optional:

| Key | Type | Default | Rule |
|---|---|---|---|
| `limits.paused` | boolean | `false` | `true` pauses every gating skill and every driver of the project (decision 5) |
| `limits.minutesPerIssue` | integer, 1 to 1440 | 180 | The most minutes one run works on one issue (decision 6.1) |
| `limits.turnsPerRole.<role>` | integer, 1 to 10000 | `session` 200, `specWriter` 150, `specReviewer` 80, `tester` 150, `implementer` 300, `codeReviewer` 80, `fixer` 200, `worker` 40 | The most turns one launch of the role takes; for `session`, the turns of a headless run per issue (decisions 6.3 and 8) |
| `limits.issuesPerRun` | integer, 1 to 100 | 10 | The most issues one run starts (decision 6.4) |
| `limits.costPerIssueUsd` | number, 0.01 to 10000 | 25 | The most US dollars, as Claude Code reports them, spent on one issue over all headless runs (decision 6.2) |

`<role>` is one of the seven roles of **Agent roles and models** plus `session`, the role the slot reports already use
for the orchestrating session; another key under `turnsPerRole` is an unknown key (a validator warning, ignored). A
value of the wrong type or out of range is never taken as its default or as no limit: the gate exits 2 with
`gate: cannot check: limits.<key> must be <rule>, got <the value as JSON>` (`<rule>`: `true or false`,
`a whole number from <lo> to <hi>`, `a number from 0.01 to 10000`). The schema holds `type`, `minimum`, `maximum` and
`default` for each (the validator checks all but `maximum`; the gate checks the range), and each description says
what the rule says and who reads it. No limit can be turned off: the largest values are the off switch in practice.
The numbers are judgements for a default project, not measured; the README says to tune them.

**3. The gate: `scripts/gate.sh` / `scripts/gate.ps1`.**

```
bash "<plugin>/scripts/gate.sh" [--issue <n>] [--slot <s>] [--role <role> --turns <t>]
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin>/scripts/gate.ps1" [-Issue <n>] [-Slot <s>] [-Role <role> -Turns <t>]
```

Run from inside any checkout of the project (the main checkout is the parent of `git rev-parse --git-common-dir`).
`<n>`, `<s>`, `<t>` are whole numbers of at least 1; `--role` and `--turns` come together; `-h`/`--help` prints the
usage; anything else prints the usage on stderr and exits 2. Reads the base configuration, `ledger.tsv`, the clock
(`ledger_clock`, so `NIGHTMILL_CLOCK_FILE` moves it in the tests), the environment variables `NIGHTMILL_RUN_STARTED`
and `NIGHTMILL_ISSUES_LEFT` (decision 8), and with `--issue` one `gh api graphql` query. Writes nothing, changes nothing
on GitHub. The checks, in this order; the first that holds prints its line and exits:

1. **The config.** `base_config` of the main checkout, as `scripts/slot.*` reads it. A stop of `baseconfig.*` exits 2
   with `gate: cannot check: <its line>`; a fallback prints its note on stderr and goes on.
   The gate does not fetch (iteration 48 decision 1 step 5: no fetch is added to the scripts); it reads the last fetched
   state of the base branch, as every reader of `baseconfig` does.
2. **The values** of decision 2, exit 2 on the first bad one.
3. **The project pause.** `limits.paused` is `true`: exit 1, `gate: paused: limits.paused is true on <base_cfg_from>`.
4. **The epic pause** (with `--issue`): `gh api graphql -f query='query { repository(owner: "<owner>", name: "<repo>") { issue(number: <n>) { parent { number labels(first: 100) { nodes { name } } } } } }'`.
   A failed call exits 2 with `gate: cannot check: the epic of #<n> could not be read: <gh's stderr on one line>`. A
   parent with the label `paused` (exact name): exit 4, `gate: paused: epic #<e> has the label paused`. No parent, or
   no such label: go on.
5. **The cost per issue** (with `--issue`): `spent` is the sum, over the `run` lines of `ledger.tsv` whose field 6
   lists `<n>`, of field 10 divided by the number of issues in field 6 (decision 7); a line with an empty field 10 adds
   0. `spent` ≥ `limits.costPerIssueUsd`: exit 3,
   `gate: limit: #<n> has spent $<spent> in headless runs; the limit is $<l> (limits.costPerIssueUsd)`. Money is
   printed with two decimals.
6. **The minutes per issue** (with `--issue`): the start is the later of the claim stamp (field 9) of the last `take`
   line of slot `<s>` (with `--slot`) and `NIGHTMILL_RUN_STARTED` (when set). Elapsed minutes (whole, rounded down) ≥
   `limits.minutesPerIssue`: exit 3,
   `gate: limit: #<n> has been worked on for <m> minutes in this run; the limit is <l> (limits.minutesPerIssue)`.
   Without either start the check is not made and `gate: minutes per issue not measured (no slot and no driver run)`
   goes to stderr.
7. **The turns per role** (with `--role`): `<t>` > `limits.turnsPerRole.<role>`: exit 3,
   `gate: limit: the <role> role took <t> turns; the limit is <l> (limits.turnsPerRole.<role>)`. A role not in the list
   of decision 2 exits 2 with `gate: cannot check: unknown role <role>`.
8. **Go.** Exit 0; stdout ends with, in this order: `gate: issues per run: <k>` (`<k>`: `limits.issuesPerRun`, or
   `NIGHTMILL_ISSUES_LEFT` when it is set to a whole number of at least 0 and smaller than `limits.issuesPerRun`;
   otherwise, also when it is larger, equal or not a whole number, `limits.issuesPerRun`), with `--issue` also
   `gate: spent on #<n>: $<spent> of $<l>`, and last `gate: go`.

**Exit codes:** 0 go, 1 the project is paused, 2 cannot check (also a usage error), 3 a limit is breached, 4 the
issue's epic is paused. With `--issue` but `gh` unusable the gate fails closed (exit 2): a pause that cannot be read
is never taken as no pause. The ledger path is resolved as `scripts/stages.*` resolve it; a missing file is no spend
and no take line. PowerShell reads the config with `ConvertFrom-Json` and the ledger with `ledger.ps1`, as `slot.ps1`
does.

**4. The pause flag cannot be changed by the branch it governs.** The gate reads `limits` only from the configuration
of decision 3 step 1, never from the working tree's file except in `baseconfig`'s two fallbacks (no remote branch known, or a
base without a config, where no base exists to govern). A pull request that sets `limits.paused` to `false` or raises a
limit governs no run until it is merged and fetched (by a take or the driver's start, iteration 48 decision 1 step 5); as a change under `.claude/` it is never auto-merged (iteration
48 decision 6), so only the maintainer's merge unpauses. The label is not in any branch: a pull request cannot change
it.

**5. Where the skills run the gate.** A new paragraph **The pause and the limits** in the workflow skill, after
**Parallel work**, holds the rule; `/next`, `/fix`, `/spec`, `/check`, `/story` and `/control` each name it in one
line at the top of their step list. "Every step" is, exactly:

1. at the start of the run, before the first change (before the picking line), without `--issue`;
2. once the issue is known (`/spec`, `/next`, `/fix`; each bug of `/fix all`), right after the picking line and before
   the first change, with `--issue <n>`;
3. at every point where **Room on the machine** says to check the room (every launch of a role, every take, the manual
   check, the session's own check), right before that check and whether or not `parallel.roomCheck` is on, with
   `--issue` and, once a slot is taken, `--slot`;
4. right after every launch of a role returns, with `--role <role> --turns <t>` added, `<t>` the `tool_uses` of the
   Agent result's usage; when the result names none, the check is not made and the skill says once per run
   `the turns of a launch are not reported; limits.turnsPerRole is not checked`;
5. before every push, before every pull request is opened, and before every watch call of **Watching the checks**;
6. in `/check`, before each run of the check (at most three, unchanged); in `/story`, before step 4 (create); in
   `/control`, before the pass.

`/status`, `/models` and `/init` do not run the gate: the first two change nothing and are how the maintainer looks at
a paused project; `/init` is the maintainer's interactive setup, which creates the `paused` label (decision 11). The
workflow skill is rules, not a run.

**What the skill does with the exit code.**

- **0**: go on. `/fix all` takes `gate: issues per run: <k>` of its first gate call as part of its run limit
  (decision 6.4).
- **1** (the project is paused): stop the run with `Stopped: paused: <the gate's reason>. Nothing more was started.`
  No label, no comment, no status; the slot, branch and files stay as they are and the slot reports `stopped`. In
  `/fix all` it is a stop of the whole run ("The whole run stops"): no new start, no further step of any bug; agents
  already running are waited for and their results checked by that bug's rules.
- **4** (the issue's epic is paused): as 1 for `/spec`, `/next` and `/fix <n>`; in `/fix all` it ends that bug only:
  a bug not yet started is listed as `not started` with the reason `paused: epic #<e> has the label paused`; a bug in
  flight stops where it is and is listed as `stopped` with that reason. The run goes on.
- **2** (cannot check): as 1, with `Stopped: the gate could not check the pause and the limits: <the reason>. Nothing more was started.`
  A gate that cannot run (a missing script, a shell error) is the same.
- **3** (a limit is breached): the breach of decision 9 for that issue. `/spec`, `/next` and `/fix <n>` then end the
  run; in `/fix all` it ends that bug only (a skip, as "A bug that cannot be done is skipped" says, with its slot
  held), and the run goes on.

**6. What each limit counts.**

1. **Minutes per issue**: wall-clock minutes from the later of the issue's slot take and the start of the driver step
   (decision 3 step 6), checked at every gate call. A resumed run under the driver starts a new count; a run without a
   slot and without the driver is not timed (Not done). The driver does not stop a running step on time (iteration 52
   decision 6 does not either); the bound acts at the next step.
2. **Cost per issue**: the sum of `total_cost_usd` of the headless runs that worked on the issue, over all runs, from
   the ledger; a run for several bugs (`/fix all`) shares its cost equally among the bugs of its field 6 (the bugs whose board status changed in the step, decision 7). Inside a run the
   cost is bounded by `--max-budget-usd` (decision 8), which Claude Code enforces.
3. **Turns per role**: for the seven roles, the tool uses of one launch, compared after it returns (decision 5 rule
   4); a launch is not stopped while it runs. For `session`, the turns of a headless run, passed as `--max-turns` by
   the driver (decision 8), which Claude Code enforces while it runs.
4. **Issues per run**: in `/fix all`, the run limit becomes the smallest of `parallel.fixAllMaxBugs` (when not 0) and
   `<k>` of the gate's first `gate: issues per run:` line; the rest of "Order, the run limit and new Ready bugs" is
   unchanged, also the reason `run limit of <k> reached`. `/spec`, `/next` and `/fix <n>` start one issue. In the
   driver, decision 8. A bug skipped as `needs a story` still does not count.

**7. The run ledger: the kind `run` in `ledger.tsv`.** The driver appends one line after every `claude -p` it ran
(also after one that failed or was ended by a signal), with `ledger_append` (the 21 tries of iteration 41 decision 5;
a failed write prints `drive: the run ledger was not written (<first line>)` on stderr and changes nothing else). It
creates `<root>/.slots/` when missing. 11 fields, tab-separated, an absent value empty:

| # | Field | Value |
|---|---|---|
| 1 | kind | `run` |
| 2 | stamp | when the line is written (the step's end), UTC `YYYY-MM-DDTHH:MM:SSZ` |
| 3 | driver | the driver run's start stamp, UTC (the same for every step of one driver run) |
| 4 | step | the step's number `k` in that run |
| 5 | prompt | `/nightmill:fix all` or `/nightmill:next <N>` |
| 6 | issues | the issue numbers the step worked on, joined by `,`: for `/next N` `N`; for `/fix all` the bugs whose board status after the step differs from before it, in the order of the summary table; empty when none |
| 7 | ended | `ok` (exit 0, `subtype` `success`), `max-turns`, `max-budget` (the `subtype` names of the probe, whatever the exit code), `exit <code>`, `signal`, or `no-result` (stdout not one JSON object) |
| 8 | from | the step's start, UTC |
| 9 | duration | `duration_ms` of the result, as given |
| 10 | cost | `total_cost_usd` of the result, as given |
| 11 | turns | `num_turns` of the result, as given |

Fields 9 to 11 are read from the headless result (criterion 4); a field the result lacks is empty. No field holds a
tab or a newline (numbers, stamps and the two fixed prompt forms). The folder is untracked: with the default root it is
outside the repository, and a root inside the main checkout that is not ignored makes the tree dirty, which stops the
driver before its first step (iteration 52 decision 3). Only the driver writes `run` lines; a `claude -p` started by
hand is not recorded (Not done), because only its caller sees its result.

**8. The driver.** Additions to iteration 52 and one amendment of it (After every step, below); everything else there
stands.

- **Before every step** (iteration 52 decision 3 step 1), after the kill switch and the time limit and before the
  clean-checkout check: `scripts/gate.sh` (`gate.ps1`) without arguments. Exit 1 ends the run with
  `paused: <the reason>` (exit 0 when a step ran before, else "cannot start", exit 1); exit 2 ends it with
  `the gate could not check the pause and the limits: <the reason>` (exit 1). Then the issue count: when `started`
  (below) has reached `limits.issuesPerRun`, the run ends with
  `the issue limit of <k> per run (limits.issuesPerRun) is reached` (exit 0).
- **`started`** counts the items of this run whose board status after their step differs from the status before it
  (iteration 52's *Before*, and as *After* the board read before the next step, decision 3 step 2 there). `left` is
  `limits.issuesPerRun − started`.
- **Before a `/next N` step**: `gate --issue N`. Exit 4: N counts as tried, is not run, and its summary row is
  `not started: paused: epic #<e> has the label paused`. Exit 3: the breach of decision 9 by the driver for N; N counts
  as tried and is not run, row `blocked: <the reason>`. Exit 1 or 2 as above.
- **The step line** gains two flags and two variables, nothing else:

  ```
  NIGHTMILL_RUN_STARTED=<step start, seconds> NIGHTMILL_ISSUES_LEFT=<left> claude -p "<prompt>" --permission-mode manual --output-format json --max-turns <T> --max-budget-usd <B>
  ```

  (PowerShell sets the two variables in the step process's environment.) For `/next N`: `T` is
  `limits.turnsPerRole.session` and `B` is `limits.costPerIssueUsd` minus the spend of `gate: spent on #N:`, with two
  decimals, at least `0.01`. For `/fix all`: with `k` the smallest of the number of Ready bugs read for the step,
  `left` and `parallel.fixAllMaxBugs` (when not 0), `T` is `limits.turnsPerRole.session × k` and `B` is
  `limits.costPerIssueUsd × k`. The variables reach the gate through Claude Code's shell tool, which inherits the
  environment (the probe checks it).
- **After every step**: the `run` line of decision 7. When field 7 is `max-turns` or `max-budget`, the step was
  stopped by a limit inside it: every item of the step that is not done gets the breach of decision 9, whatever
  status the run left it at (decision 9: Spec, In progress or Review). For `/next N` that is N unless the board shows
  it at Done after the step; for `/fix all` it is every bug of field 6 (its status changed in the step) that the board
  shows at In progress or Review after it. The reason is
  `the headless run reached its turn limit of <T> (limits.turnsPerRole.session × <k>)` or
  `the headless run reached its budget of $<B> (limits.costPerIssueUsd × <k>)`; such items are `blocked: <reason>` in
  the summary. A step ended by a signal to the driver (iteration 52 decision 8) is not a limit and labels nothing. Then
  the loop goes on with the next item (decision 3 step 1 of iteration 52), whatever exit code `claude` returned for
  that step.
- **Amendment of iteration 52 decision 3 step 5** (the maintainer's decision for this story), for this one case only: a
  step whose result's `subtype` is the one the probe recorded for `--max-turns` or for `--max-budget-usd` (field 7
  `max-turns` or `max-budget`) is a limit breach, not a failed step. It does not end the run with
  `claude exited <code> in <the step's prompt>`, and it does not by itself make the driver's exit code 1 (iteration 52's
  exit code "when a step's `claude` exited non-zero" applies only to a step that ends the run by step 5). Its summary
  step line still shows its exit code. Every other step whose `claude` exits non-zero (field 7 `exit <code>` or
  `no-result`) still ends the run by step 5 as iteration 52 says.
- **The summary** (iteration 52 decision 10) gains nothing new but these reasons and outcomes; the count line counts a
  `blocked: limit` row as blocked.
- **Writes.** Iteration 52 decision 9's list of `gh` calls gains exactly five: for a breach (decision 9)
  `gh api user --jq .login`, `gh issue view <n> --json comments`, `gh issue comment <n> --body-file <file>` and
  `gh issue edit <n> --add-label blocked`, and, through the gate, its `gh api graphql` query (decision 3 step 4). The
  list of the driver is then exactly: `gh auth status`, `gh project item-list`, `gh pr list`, `gh issue comment`
  (the summary, and the breach comment), `gh api graphql`, `gh api user`, `gh issue view` and `gh issue edit`. Its only
  GitHub writes are the summary comment, the breach comment and the `blocked` label. Still no status, no field, no
  item, no other label.

**9. The breach.** For issue `<n>` and the gate's (or the driver's) reason `<reason>`, in this order:

1. **One comment**, `gh issue comment <n> --body-file <file>`, unless a comment of the agent's login (`gh api user --jq .login`)
   among the issue's comments (`gh issue view <n> --json comments`, fields `author.login` and `body`) already starts
   with `Stopped by a limit: ` and names the same config key:
   `Stopped by a limit: <reason>. Labelled blocked; the board status (<status>) and the work (<the slot and branch | the branch | nothing>) are left as they are for the maintainer.`
2. **The label**: `gh issue edit <n> --add-label blocked`; on failure print
   `The label blocked could not be added: <the first line of gh's message>; /init creates it.` and go on (the line of
   **Watching the checks**).
3. **Stop**: print `Stopped: limit: <reason>. Labelled blocked.`, report `stopped` to the slot when the run has one,
   and end the issue's work as decision 5 says.

No status is set or added: the item stays at the status the run gave it (Spec, In progress or Review), the slot stays
taken with its files, nothing is reverted, pushed or deleted, auto-merge is left as it is. A `blocked` label already on
the issue does not stop a run and is not removed; the maintainer removes it, raises the limit or moves the item.
Run-wide limits (`limits.issuesPerRun`, `unattended.maxMinutes`, the kill switch, a pause) breach no issue and label
nothing.

**10. Hand-started headless runs** (README `### The commands`). The four command lines gain `--max-turns`, with the
defaults: `--max-turns 200` for `/nightmill:next`, `/nightmill:next 112` and `/nightmill:fix 57`, `--max-turns 2000`
(200 × 10) for `/nightmill:fix all`; the log example line too. The text says the numbers are
`limits.turnsPerRole.session` (times `limits.issuesPerRun` for `/fix all`), that `--max-budget-usd <amount>` bounds
the cost the same way, and that the driver passes both from the config. The gate runs inside such a run as in any
other; only the ledger line is missing.

**11. `/init`.** **Labels** gains one row after `blocked`: `` | `paused` | `FBCA04` | Pauses every run on the issues of this epic (nightmill's pause flag) | ``.
**Run permissions** group D names `gate` beside `slot`, `room`, `validate-config` and `status`: 10 rules, and
**Count** becomes `26 + 21 × worktrees.slots` rules (68 for 2 slots, 110 for 4); its plan sentence says "the five
scripts". The README's `### The run permissions` follows. A project upgraded from an earlier version runs `/init`
again, as the README already says until #213.

**12. The README.**

- The configuration table: one row after `unattended` (iteration 52):
  `` | `limits` | The pause flag (`paused`, default false) and the limits of every run: minutes per issue (`minutesPerIssue`, default 180), turns per launch of each role and of a headless session per issue (`turnsPerRole.<role>`, default `session` 200, `implementer` 300, ...), issues per run (`issuesPerRun`, default 10), cost per issue (`costPerIssueUsd`, default 25). Read from the base branch only |``.
- `## Running on a schedule` › `### Limits and the kill switch` (iteration 52): the sentence that limits per issue,
  per role and per cost and a pause flag are not there yet becomes the rules of decisions 1, 6, 8 and 9 in short: the
  table of decision 1, how to pause (`limits.paused` merged, or the label `paused` on an epic) and unpause, what a
  breach leaves (the comment, `blocked`, no status), and the `run` lines of the ledger with their fields.
- `### The commands`: decision 10.
- `### When a run is stopped`: iteration 52's "a pause flag for every run comes with [#165](...)" becomes "the pause
  flag stops every run at its next step ([Limits and the kill switch](#limits-and-the-kill-switch),
  [#165](...))".
- The Security model table: the row `An unattended run is bounded by limits and a kill switch` gets the state
  `enforced by scripts/gate.* (the pause flag and the limits, before every step of the skills that change anything and of the driver) and by Claude Code (--max-turns, --max-budget-usd on the driver's runs); a launch of a role is checked after it returns`,
  still linking #165.
- `## What is in the plugin`: a row
  `` | `scripts/gate.ps1`, `scripts/gate.sh` | Checks the pause flag and the limits before a step: exit 0 go, 1 paused, 2 cannot check, 3 a limit is breached, 4 the epic is paused. Changes nothing. | ``
  after the row of `scripts/drive.*`.
- `### Where a story's time went`: one sentence that `ledger.tsv` also holds the driver's `run` lines, which
  `stages.*` skips.
- `## Developing nightmill`: `bash tests/smoke-gate.sh    # gate.sh: the pause flag and the limits against a throwaway repository`
  after the line of `smoke-drive.sh`, and `powershell -ExecutionPolicy Bypass -File tests/smoke-gate.ps1` after the
  line of `smoke-drive.ps1`.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | Config values bound the minutes per issue, the turns per role, the issues per run and the cost per issue, each with a default | Decisions 2, 3 (steps 5 to 8), 6, 8; Tests, `smoke-gate` cases `cost`, `minutes`, `turns`, `issues left`, `bad value`, `test-limits-docs.sh` part K |
| 2 | A pause flag, read from the base branch's config or a label on the epic, is checked before every step of every skill and by the driver | Decisions 1, 3 (steps 1, 3, 4), 4, 5, 8; Tests, `smoke-gate` cases `paused`, `paused on a branch only`, `epic paused`, `gh fails`; `smoke-drive` case `paused`; `test-limits-docs.sh` part G |
| 3 | Headless runs are started with a turn limit | Decisions 8, 10; Tests, `smoke-drive` case `flags`, the probe, `test-unattended-docs.sh` part 3 |
| 4 | Cost, duration and turns of each run are read from the headless result and appended to a ledger, one line per run, in an untracked folder | Decisions 1, 7; Tests, `smoke-drive` case `ledger`, `smoke-stages` case `run lines` |
| 5 | A breached limit labels the issue `blocked`, comments why and stops; no status is added | Decisions 5, 8, 9; Tests, `smoke-drive` cases `max turns`, `budget`, `spent`; manual check step 3 |
| 6 | `/check` stops after a bounded number of attempts (see the bug) | Already holds (Facts; #124): at most three attempts, pinned by `tests/test-check-skill.sh`, unchanged; `/check` gets the gate (decision 5 rule 6) |

"Every skill" in criterion 2 is read as every skill that changes something (decision 5; Left).

## Tests

**`tests/smoke-gate.sh` and `tests/smoke-gate.ps1`** (same cases, same expected lines). Each builds a throwaway
project under `mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-gate.XXXXXX"` (removed by a trap): a bare repository as
`origin`, a clone as the main checkout with `origin/HEAD` set and a committed and pushed `.claude/nightmill.json`
(owner `acme`, repo `widgets`, `worktrees.root` `../wt`), `NIGHTMILL_CLOCK_FILE` set, and a fake `gh` first on the
`PATH` that answers `api graphql` from `$EPIC` (a JSON file the case writes; exit 1 when `GH_FAIL` is set), logs every
call to `$GH_LOG`, and fails on any other call. The ledger is `tests/fixtures/gate/ledger.tsv` copied to
`<root>/.slots/ledger.tsv` (a `take` line of slot 1, a `run` line for `21` with cost `4.00`, a `run` line for `11,12`
with cost `6.00`, and `take`, `step`, `free` lines of other slots).

| Case | Setup | Expected |
|---|---|---|
| go | no `limits`, no option | exit 0; last lines `gate: issues per run: 10`, `gate: go` |
| paused | `limits.paused` true on `origin` | exit 1; `gate: paused: limits.paused is true on origin/HEAD:.claude/nightmill.json` |
| paused on a branch only | `limits.paused` true in the working tree only, committed on a branch, not on `origin` | exit 0 |
| paused, not yet fetched | the pause pushed to `origin` from a second clone after the checkout's last fetch | exit 0 (the gate does not fetch); after the test runs `git fetch origin` in the checkout, exit 1 |
| epic paused | `--issue 21`, `$EPIC` a parent #5 with label `paused` | exit 4; `gate: paused: epic #5 has the label paused` |
| epic not paused | parent without the label; then no parent | exit 0 both |
| gh fails | `--issue 21`, `GH_FAIL` | exit 2; starts `gate: cannot check: the epic of #21 could not be read: ` |
| cost | `--issue 21` with `costPerIssueUsd` 5, then 4; `--issue 12` (half of the `11,12` line) with 3.01, then 3 | exit 0 with `gate: spent on #21: $4.00 of $5.00`; exit 3 with `#21 has spent $4.00 in headless runs; the limit is $4.00`; exit 0 with `$3.00 of $3.01`; exit 3 |
| minutes | `--issue 21 --slot 1`, clock 179 then 180 minutes after the take's field 9 | exit 0; exit 3 with `has been worked on for 180 minutes in this run` |
| run started later | as minutes, `NIGHTMILL_RUN_STARTED` 10 minutes before the clock | exit 0 |
| not measured | `--issue 21`, no slot, no variable | the note on stderr; exit 0 |
| turns | `--role tester --turns 150`, then 151; `--role session --turns 201`; `--role boss --turns 1` | exit 0; exit 3 `the tester role took 151 turns; the limit is 150 (limits.turnsPerRole.tester)`; exit 3; exit 2 `unknown role boss` |
| issues left | `NIGHTMILL_ISSUES_LEFT` 3; then 0; then 20 | `gate: issues per run: 3`; `0`; `10` |
| bad value | `paused` `"yes"`; `minutesPerIssue` 0, 1441, 2.5; `costPerIssueUsd` 0; `turnsPerRole.tester` `"9"`; `issuesPerRun` 101 | exit 2 with the line of decision 2 each; no `gh` call |
| no ledger | the ledger removed | `--issue 21` spends `$0.00`; exit 0 |
| usage | `--turns 3` without `--role`; `--issue x` | exit 2; the usage on stderr |

In every case the fake `gh`'s log holds only `api graphql` calls, the tree and the ledger are byte for byte as
before (the gate writes nothing), and the remote-tracking refs are unchanged (the gate does not fetch). Each test runs in under 30 seconds.

**`tests/smoke-drive.sh` and `tests/smoke-drive.ps1`** (iteration 52's), new cases; the fake `gh` also answers
`api graphql` (no parent), `issue edit` (logged) and `api user` (`agent`), and the fake `claude` prints `subtype`,
`duration_ms`, `total_cost_usd` and `num_turns`, and records its environment's two variables:

| Case | Setup | Expected |
|---|---|---|
| flags | loop of iteration 52 (bug #11, stories #21, #22) | the claude log: `/nightmill:fix all ... --max-turns 200 --max-budget-usd 25.00`, `/nightmill:next 21 ... --max-turns 200 --max-budget-usd 25.00`; `NIGHTMILL_ISSUES_LEFT` 10, 9, 8; `NIGHTMILL_RUN_STARTED` set |
| ledger | as flags | three `run` lines appended, 11 fields each; fields 4, 5, 6: line 1 `1`, `/nightmill:fix all`, `11`; line 2 `2`, `/nightmill:next 21`, `21`; line 3 `3`, `/nightmill:next 22`, `22`; in every line field 7 `ok` and fields 9, 10, 11 the fake's numbers for that step; field 3 the same in all three |
| paused | the fake's first step, in the main checkout on `main`, commits `limits.paused` true and runs `git push origin main` from there: the push moves the checkout's `origin/main`, and so `origin/HEAD`, without a fetch (iteration 48 decision 1 step 5), and leaves the tree clean and on `main` | one claude call; reason `paused: limits.paused is true on origin/HEAD:.claude/nightmill.json`; exit 0 |
| paused at start | `limits.paused` true before the run | exit 1; `drive: cannot start: paused: ...`; no claude call |
| issue limit | `issuesPerRun` 2, three items | two claude calls; reason `the issue limit of 2 per run (limits.issuesPerRun) is reached` |
| max turns | `/next 21` ends with `subtype` of the probe for turns and its exit code, #21 left at In progress; run again with the fake exiting 0, then 1 | each time: `gh issue comment 21` with `Stopped by a limit: the headless run reached its turn limit of 200`, `gh issue edit 21 --add-label blocked`; row `blocked: ...`; #22 still tried; no `claude exited` reason; no status call |
| budget | the same with the budget `subtype` | the same with `reached its budget of $25.00` |
| limit at Review | `/fix all` ends with the budget `subtype`, #11 moved to Review with an open PR; then `/next 21` ends with the turns `subtype`, #21 left at Review | `gh issue comment 11` and `gh issue edit 11 --add-label blocked`, the same for #21; rows `blocked: ...`; no status call |
| spent | a fixture ledger with `run` lines for #21 summing $25.00 | no `/next 21` call; comment and label for #21; row `blocked: limit: #21 has spent $25.00 ...` |
| epic paused | #21's parent has `paused` | no `/next 21` call; no comment, no label; row `not started: paused: epic #<e> has the label paused` |
| comment once | as spent, with the comment already there from the login `agent` | no second `issue comment`; the label is added |

In every case no `gh` call of iteration 52's forbidden list is made (`project item-edit`, `issue close`, ...).

**`tests/smoke-stages.sh` and `tests/smoke-stages.ps1`**, case `run lines`: the fixture ledger with `run` lines added
between its lines prints the same tables as without them and no `skipped ... malformed lines` note (criterion 4,
compatibility).

**`tests/test-limits-docs.sh [<root>]`** (new; bash and awk, `set -euo pipefail`), called from a new lint section
directly after `== the driver is wired`:

```
echo "== the pause flag and the limits are wired"
# Iteration 53 (#165): the limits keys, the gate in the skills, the driver's flags and ledger, the README rows.
bash tests/test-limits-docs.sh "$PWD" || fail=1
```

- **Part K (keys).** The schema's `limits` has `paused` (boolean, default false), `minutesPerIssue` (integer, minimum
  1, maximum 1440, default 180), `issuesPerRun` (1, 100, 10), `costPerIssueUsd` (number, minimum 0.01, maximum 10000,
  default 25) and `turnsPerRole` with exactly the eight keys of decision 2, each an integer with minimum 1, maximum 10000
  and its default; each key has a `description`. The example config has `"limits"` with every key at its default. The
  README's configuration table has a row starting `` | `limits` | `` that holds each key name and `default <d>` for
  `minutesPerIssue`, `issuesPerRun`, `costPerIssueUsd` and `session`, `<d>` read from the schema.
- **Part G (the gate in the skills).** The workflow skill has the heading `**The pause and the limits**` and names
  `scripts/gate.sh`, `scripts/gate.ps1`, the five exit codes, `Stopped: paused: `, `Stopped: limit: `,
  `Stopped by a limit: `, `--add-label blocked`, `tool_uses` and `limits.turnsPerRole is not checked`. Each of
  `skills/{next,fix,spec,check,story,control}/SKILL.md` contains `**The pause and the limits**` and a call
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"` and its PowerShell form; `skills/fix/SKILL.md` no longer contains
  `once they exist`; `skills/{status,models}/SKILL.md` contain no `gate.sh`. `skills/init/SKILL.md` has the `paused`
  row, `gate` in group D and `26 + 21`.
- **Part D (the driver).** `scripts/drive.sh` and `scripts/drive.ps1` contain `--max-turns`, `--max-budget-usd`,
  `NIGHTMILL_RUN_STARTED`, `NIGHTMILL_ISSUES_LEFT`, `gate.`, `ledger_append` (PowerShell: the `ledger.ps1` append) and
  `run`; every `issue edit` in them is followed on its line by `--add-label blocked`.
- **Part R (README).** The rows of decision 12, `.git/nightmill-stop` and `limits.paused` in
  `### Limits and the kill switch`, and the label `paused`.

Changed pins: `tests/test-drive-docs.sh` part S allows `issue edit` only as `issue edit <n> --add-label blocked`
(decision 8) and adds `--max-turns` and `--max-budget-usd` to the required words; `tests/test-unattended-docs.sh` part
3 pins the four new command lines of decision 10 exactly and checks that `200` and `2000` are the schema's
`limits.turnsPerRole.session` default and that times `limits.issuesPerRun`'s; `tests/lint.sh`'s
`== init installs the run permissions` pins `'26 + 21'` instead of `'24 + 21'`. Everything else keeps passing:
`tests/test-check-skill.sh` (criterion 6, unchanged), `tests/test-security-model.sh` (the #165 row stays), iteration
51's agreement lint (both new smoke files listed and twinned), `== the check runs every smoke script`, `== config
validates`, `== temporary files have a template`, `== bash files do not use jq`, the forbidden-words lint.
`tests/smoke-gate.sh` is `add bash smoke-gate.sh` after `add bash smoke-drive.sh`, `tests/smoke-gate.ps1` is
`add ps smoke-gate.ps1` after `add ps smoke-drive.ps1` in `tests/check.sh`, and both go in the matching `--only` list
of `ci.yml` in that order.

**The probe** (implementation step 1, by the implementer, recorded in "How verified"; it starts no skill that changes
anything and changes no board):

1. `claude -p "/nightmill:status" --permission-mode manual --output-format json --max-turns 1` and the same with
   `--max-budget-usd 0.01`, once each, in a scratch checkout: each is accepted (no unknown-option error) and its JSON
   has `subtype`, `duration_ms`, `total_cost_usd` and `num_turns`; the `subtype` and the exit code of `claude` of a
   run ended by each limit are recorded; the `subtype` is used for `max-turns` and `max-budget` in decision 7 and the
   smoke fakes, and the exit code is what the fakes of the cases `max turns`, `budget` and `limit at Review` exit
   with. Whatever the exit code is, decision 8's amendment holds; the probe changes no rule.
2. `NIGHTMILL_ISSUES_LEFT=3 claude -p "Run printenv NIGHTMILL_ISSUES_LEFT in the shell and print its output" --permission-mode manual --output-format json --max-turns 3`
   prints `3` (the variable reaches the shell tool).
3. In an interactive session, one Agent launch: its result's usage names `tool_uses`.

If `--max-turns` is refused, criterion 3 cannot be met with this Claude Code; the implementer stops with `partial`, no
file changed, and the maintainer decides (Left). If 2 fails, decision 8's variables are replaced by a file
`nightmill-run.json` in the git common directory that the driver writes before a step and removes after it; that is a
spec change for the maintainer, not made by the implementer. If 3 fails, rule 4 of decision 5 says its "not reported"
line and nothing else changes.

**The manual check** (`claude --plugin-dir <a separate checkout>` in a scratch project with a board, slots and a
Ready bug #B under an epic #E):

1. `limits.paused` true merged to the base branch: `/nightmill:check` prints `Stopped: paused: limits.paused is true on origin/HEAD:...`
   and runs nothing; `/nightmill:fix <B>` stops the same way before step 3 with no status change.
2. The pause removed, the label `paused` on #E: `/nightmill:fix all` lists #B as `not started` with
   `paused: epic #E has the label paused`; removing the label lets it start.
3. `limits.turnsPerRole.tester` 1 merged: `/nightmill:fix <B>`, after the tester returns, comments
   `Stopped by a limit: the tester role took <t> turns; ...`, adds `blocked`, prints `Stopped: limit: ...`; #B stays at
   In progress, its slot taken, and `/nightmill:status` shows the slot `stopped`.
4. With iteration 52's driver, `limits.costPerIssueUsd` 0.01 merged and one Approved story: the driver runs one
   `/nightmill:next <N>` step that stops on its budget, labels and comments, appends one `run` line to `ledger.tsv`, and
   its summary row is `blocked: the headless run reached its budget of $0.01 ...`.

## Files touched

- `scripts/gate.sh` (new, `100755`) and `scripts/gate.ps1` (new): decision 3, with a header comment as
  `scripts/room.sh` has (usage, what it reads, exit codes, the spec's path).
- `scripts/drive.sh` and `scripts/drive.ps1`: decisions 7 and 8.
- `schema/nightmill.schema.json`: the object `limits` of decision 2.
- `templates/nightmill.example.json`: `"limits": { "paused": false, "minutesPerIssue": 180, "turnsPerRole": { ... }, "issuesPerRun": 10, "costPerIssueUsd": 25 }`
  after `unattended`, every role with its default.
- `skills/workflow/SKILL.md`: the paragraph **The pause and the limits** (decisions 5, 6, 9).
- `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/spec/SKILL.md`: one line at the top of the step list naming
  the paragraph; in `/fix` the gate of "Batch mode" says what decision 5 says for exit 1, 2, 3 and 4 and decision 6.4
  for the run limit, replacing "once they exist".
- `skills/check/SKILL.md`, `skills/story/SKILL.md`, `skills/control/SKILL.md`: one sentence each, decision 5 rule 6.
- `skills/init/SKILL.md`: decision 11.
- `README.md`: decision 12.
- `tests/smoke-gate.sh`, `tests/smoke-gate.ps1` (new), `tests/fixtures/gate/` (new): the ledger and the epic JSON.
- `tests/smoke-drive.sh`, `tests/smoke-drive.ps1`: the new cases and the wider fakes.
- `tests/smoke-stages.sh`, `tests/smoke-stages.ps1`: the case `run lines`.
- `tests/test-limits-docs.sh` (new); `tests/test-drive-docs.sh`, `tests/test-unattended-docs.sh`: the changed pins.
- `tests/lint.sh`: the section `== the pause flag and the limits are wired` and `'26 + 21'`.
- `tests/check.sh`: the two `add` lines. `.github/workflows/ci.yml`: the two `--only` entries, nothing else.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 53 (#165): limits, a pause flag and a run ledger bound an unattended
  run. New config object limits: paused (default false), minutesPerIssue (180), turnsPerRole.<role> (session 200,
  implementer 300, ...), issuesPerRun (10), costPerIssueUsd (25), read from the base branch only. scripts/gate.sh and
  gate.ps1 check the pause flag (limits.paused, or the label paused on the issue's epic) and the limits; /next, /fix,
  /spec, /check, /story and /control run it before every step, and the driver before every step. The driver starts
  each claude -p with --max-turns and --max-budget-usd and appends one run line per headless run (cost, duration,
  turns from its JSON result) to <worktrees.root>/.slots/ledger.tsv. A breached limit comments on the issue, labels it
  blocked and stops its work; no status is set. /init creates the label paused and grants the gate script (run /init
  again). New config keys: limits.*.` (paths, commands and keys in backticks).

Not touched: `scripts/slot.*`, `scripts/lib/*` (the gate sources `baseconfig`, `json` and `ledger` as they are),
`scripts/stages.*`, `agents/`, `hooks/`, `skills/status`, `skills/models`, `templates/workflows/nightmill-drive.yml`,
`.claude/` of this repository, `SECURITY.md`, `CONTRIBUTING.md`.

## Risks

- **A gate call before every step costs, with an issue, a GraphQL query.** A `/next` makes a few dozen calls, far
  below the rate limit. The gate reads no network for the config.
- **A config pause reaches a running skill late.** The gate reads the last fetched base branch (no fetch, iteration
  48 decision 1 step 5), so a merged `limits.paused` reaches a run at its next gate call after the next fetch in that
  repository: the next take, or the driver's start. A skill that takes no further slot runs on until it ends; the label
  `paused` on the epic and the kill switch are read live.
- **A gate that fails closed stops runs on a network blip** (exit 2 on a failed epic read). That is the choice of the
  issue ("must not be changeable"): a pause that cannot be read is not taken as no pause. `/fix all` already stops on
  a `gh` network failure.
- **Turns of a role are checked after the launch.** A launch that loops is not stopped by `turnsPerRole` while it
  runs; inside a driver step, the session's `--max-turns` and the step's `--max-budget-usd` stop it (if Claude Code
  counts a subagent's spend in the session's, which the probe does not show). A hand-started run without the flags has
  only the after-the-fact check.
- **The cost share of a `/fix all` step is an average.** A cheap bug and an expensive one of the same step are charged
  the same; per-bug cost is not reported by Claude Code.
- **The minutes count wall clock**, including the wait for CI in a watch: a slow CI can breach `minutesPerIssue` on a
  pull request that is fine. The default (180) leaves room for six watches of 30 minutes.
- **Breaches leave work for the maintainer**: a `blocked` item at In progress with a taken slot. The comment names what
  is left; `/nightmill:status` shows it.
- **Hot files.** The workflow skill and the schema change; not paired with another schema story.
- **Size.** Large; the slot scripts are not touched.

## Size estimate

`L`: about 220 lines in `scripts/gate.sh`, 220 in `scripts/gate.ps1`, 90 each in the two driver scripts, 200 each in
`tests/smoke-gate.*`, 120 each in the `smoke-drive.*` cases, 20 each in `smoke-stages.*`, 30 of fixtures, 120 in
`tests/test-limits-docs.sh`, 20 in the changed pins, 30 in the schema, 12 in the example config, 60 in the workflow
skill, 30 across the other skills, 10 in `/init`, 70 in the README, 6 in `tests/lint.sh`, 2 in `tests/check.sh`, 2 in
`ci.yml`, 12 in `CHANGELOG.md`: about 1920 changed lines in about thirty files.

## Not done

- No change to `/check`'s bound of three attempts (#124 delivered it); no config key for it.
- No ledger line for a `claude -p` started by hand, and no ledger without the driver: only the caller sees a headless
  result. No rotation or pruning of `ledger.tsv`, and no reading of the `run` lines beyond the gate's spend (#166).
- No stop of a running step on time: minutes per issue act at the next step. No minutes for a run without a slot and
  without the driver.
- No per-bug cost inside `/fix all` beyond the equal share.
- No gate in `/status`, `/models` or `/init` (decision 5), and no display of the pause in `/status` or the dashboard.
- No pause by a label on the issue itself or on a story's parent of a parent; only the direct epic. No config key for
  the label name (`paused`, as `blocked`, is a fixed name `/init` creates).
- No automatic removal of `blocked`, no unpause by the driver, no alerts or notifications beyond the issue comment and
  iteration 52's summary.
- No change to the kill switch, the lock, `unattended.maxMinutes` or the workflow template of iteration 52.
- No `git fetch` in the gate or in any other script or skill (iteration 48 decision 1 step 5 stands).
- No `maxTurns` in the agent files: they are the same for every project, and the limit is a project's value.
- No budget per project, per agent or per day beyond these keys.

## Left

- **"Every skill"** is read as every skill that changes something (decision 5). If the maintainer wants `/status`,
  `/models` or `/init` gated too, that is one line each; `/status` gated would stop the maintainer from looking at a
  paused project.
- **"The turns per role"** is read as a limit per launch of each role, counted as the launch's `tool_uses`, plus a
  `session` role for the headless run's `--max-turns` (decision 2). Claude Code offers no per-launch turn flag on an
  Agent call, so a role is checked after it returns, not stopped while it runs. If the maintainer wants a hard stop per
  role, it needs a mechanism this spec does not have (a `maxTurns` in each agent file, which is not per project, or a
  hook that counts a subagent's calls).
- **"Stops"** in criterion 5 is read as: the work on that issue stops; a `/fix all` run and a driver run go on with
  their other items, as they do for a skipped bug. If a breach should end the whole run, decisions 5 and 8 change in
  one sentence each.
- **"A label on the epic"** is read as the label `paused` on the issue's direct parent epic, pausing that epic's issues;
  the project-wide switch is `limits.paused`. A config pause needs a merged pull request under `.claude/`, which is
  never auto-merged, and reaches a running skill at its next gate call after the base branch was next fetched (a
  take, the driver's start); the gate does not fetch, as iteration 48 decision 1 step 5 says. A fetch in the gate would
  amend that decision and is the maintainer's call, not made here. If the maintainer
  wants an instant project-wide switch without a merge, the kill switch covers the driver on one machine; a label on a
  fixed issue would cover all, and is not asked here.
- **"Each run"** in criterion 4 is read as each headless run the driver starts (decision 7): a `claude -p` started by
  hand gets no ledger line, because only its caller sees its result (Not done). If the maintainer wants those recorded
  too, it needs a wrapper or a hook that sees the result, which this spec does not have.
- **Not verified by a run:** whether Claude Code 2.1.322 accepts `--max-turns` (not in its `--help`), the `subtype`
  names of the two limits and the exit code of `claude` for a run they end (decision 8's amendment holds whatever it
  is), that the environment reaches the shell tool, and the usage block of an Agent result in a
  headless run. The probe settles them before any file changes, and its outcomes are listed there.
