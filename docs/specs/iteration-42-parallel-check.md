# Iteration 42: the check runs its independent steps in parallel and has a quick mode for the inner loop

Status: delivered in iteration 42 (PR #208)

Story: #200, epic #47 (Unattended runs). `tests/check.sh` starts its steps as background jobs, up to a limit
(`verification.checkJobs`, default 4, never more than the machine's processors), writes each step's output to a file
of its own and prints the files whole, in the fixed order of its step list, whatever order the steps finish in. A
limit of 1 runs the steps one after another in the foreground, as today. `--quick` runs the lint and the bash smoke
tests only, says so in its first and last line and never prints `ALL CHECKS PASSED`. `/next` and `/fix` let the
implementer and the fixer run the quick check (the check command with ` --quick`, decision 10) while they write code;
every commit and every pull request still gets the full check. CI runs each smoke job's tests through the same runner,
and the lint keeps its lists in step with the check's. Changes
`tests/check.sh`, `tests/check.ps1`, `tests/smoke-check.sh` (new), `tests/smoke-check.ps1` (new),
`tests/smoke-stages.sh`, `tests/smoke-stages.ps1`, `tests/lint.sh`, `.github/workflows/ci.yml`,
`schema/nightmill.schema.json`, `templates/nightmill.example.json`, `.claude/nightmill.json`,
`skills/workflow/SKILL.md`, `skills/check/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`,
`README.md`, `CONTRIBUTING.md` and `CHANGELOG.md`. No script in `scripts/`, no agent, no hook.

## Story trigger and manual check

**This is a story trigger**: "a new, renamed or removed config key". One key is added, under `verification`
(decision 2), and none is renamed or removed:

- `verification.checkJobs`: integer, `minimum` 1, `default` 4. Schema text: `"How many independent steps the check
  command runs at the same time (1 to 16), for a check command that reads it; nightmill's own tests/check.sh does, and
  runs no more steps at once than the machine has processors. 1 runs them one after another."`

It goes into `schema/nightmill.schema.json` (in `verification.properties`, after `benchRule`), into
`templates/nightmill.example.json` (`"checkJobs": 4`, after `benchRule`) and into the README's configuration table
(the `verification` row). This repository's `.claude/nightmill.json` gets `"checkJobs": 4`. No other key is added:
the quick mode is an option of the check command, not a key (decision 10). The previous version
reads a config with the key unchanged: the schema says "Unknown keys are ignored", `scripts/validate-config.*`
validate against the schema of their own version, and no script of the previous version reads `verification` beyond
`check` (Facts). So the config stays readable by the previous version (invariant "Compatible").

- *A change to the status flow or who sets a status*: no. No status, no board call changes.
- *A change to the slot marker format*: no. No script in `scripts/` changes; `slot-N.json` and iteration 41's
  `ledger.tsv` are untouched.

Because it is a story trigger, `/next` does not enable auto-merge on its pull request (step 7 of `/next`); the
maintainer merges it.

**The manual check applies**: `skills` is in `verification.manualCheckPaths`, and `skills/workflow`, `check`, `next`
and `fix` change. The issue's own Verification asks for it; its steps are under Tests. Every script that
changes has a smoke step in both shells: `tests/check.sh` is the only runner, `tests/check.ps1` passes its parameters
to it (decision 8), and `tests/smoke-check.sh` / `tests/smoke-check.ps1` run the same cases through each.

**Order.** This story waits for #199 (iteration 41, the stage times; its spec is on `spec/41-stage-times`, PR #202,
not yet on `main`). It builds on iteration 41's decision 13 (`-- <name>: ok (<duration>)`, the `Times:` block,
`NIGHTMILL_CHECK_STEPS`, the clock of `scripts/lib/ledger.sh`) and on its `tests/smoke-stages.*`, and supplies the
baseline the 40% rule is measured against (decision 14). It is implemented only after #199 is merged. Two hot files
of `parallel.hotFiles` change, `schema/nightmill.schema.json` and `skills/workflow/SKILL.md`, so `parallel.doNotPair`
("two tasks that ... both change the schema") forbids pairing it with any other schema change, and it is not paired
with a story that changes the workflow skill. #157 (the lint that keeps CI, `check.sh` and the README in step) and
#149 (a commit per criterion) are related; see Left.

## Facts this rests on

Read on `main` at d299241 (iteration 38 merged), with iteration 41's spec read from `origin/spec/41-stage-times`
(`git show origin/spec/41-stage-times:docs/specs/iteration-41-stage-times.md`), and #149, #157, #179 and #199 read with
`gh issue view` (read only).

- **The check today.** `tests/check.sh` (70 lines) runs every step through `run <name> <command...>` in this order:
  `lint` (`bash tests/lint.sh`); 14 bash smoke tests (`smoke-json.sh`, `smoke-hook.sh`, `smoke-release.sh`,
  `smoke-slot.sh`, `smoke-render.sh`, `smoke-validate.sh`, `smoke-status.sh`, `smoke-template-board.sh`,
  `smoke-models.sh`, `smoke-load.sh`, `smoke-room.sh`, `smoke-control.sh`, `smoke-dashboard.sh`, `smoke-panel.sh`);
  when `pwsh` or else `powershell` is on the PATH, 13 PowerShell smoke tests (`smoke-slot.ps1`, `smoke-render.ps1`,
  `smoke-hook.ps1`, `smoke-release.ps1`, `smoke-validate.ps1`, `smoke-status.ps1`, `smoke-template-board.ps1`,
  `smoke-models.ps1`, `smoke-load.ps1`, `smoke-room.ps1`, `smoke-control.ps1`, `smoke-dashboard.ps1`,
  `smoke-panel.ps1`), each as `"$ps" -NoProfile -ExecutionPolicy Bypass -File tests/<name>`, else the line
  `SKIPPED: PowerShell smoke tests (no pwsh or powershell)`; when `claude` is on the PATH `claude plugin validate`
  (`claude plugin validate . --strict`) and, when `claude plugin test --help` succeeds, `claude plugin test`
  (`claude plugin test .`), else `SKIPPED: claude plugin validate (claude is not installed)` and
  `SKIPPED: claude plugin test not available`. Each step prints `== <name>`, its own output live, then
  `-- <name>: ok` or `-- <name>: FAILED`. At the end: the `SKIPPED:` lines, then `CHECK FAILED: <names>` (exit 1) or
  `ALL CHECKS PASSED` (exit 0). It has no options. `tests/check.ps1` (8 lines) only runs `tests/check.sh` with the
  `bash` that `Get-Command bash` finds and returns its exit code; it passes no arguments.
- **There are 14 `smoke-*.sh` and 13 `smoke-*.ps1` files** in `tests/`; `smoke-json.sh` has no PowerShell twin (it
  tests the bash JSON reader). Iteration 41 adds `smoke-stages.sh` and `smoke-stages.ps1` to the check and to CI.
  No open spec besides 41 adds a smoke script (35, 36, 37, 39 and 40 checked).
- **After iteration 41** (its decision 13): each result line is `-- <name>: ok (<duration>)` or
  `-- <name>: FAILED (<duration>)`; after the last step and before the `SKIPPED:` lines comes the block `Times:`, one
  line per step `printf '  %-28s %8s\n' <name> <duration>` "in the order they ran" and
  `printf '  %-28s %8s\n' total <duration>`, the total "from the check's start to the end of its last step (so at
  least the sum)"; the clock is that of `scripts/lib/ledger.sh` (seconds since 1970, `NIGHTMILL_CLOCK_FILE` for tests).
  `NIGHTMILL_CHECK_STEPS` names a file of lines `<name> TAB <command>`; when set, the check runs exactly those steps
  (`run <name> bash -c <command>`) in file order and skips its PowerShell and `claude` steps without a `SKIPPED:`
  line. Its test `== the check's step times` in `tests/smoke-stages.*` moves one fixture clock from step to step and
  expects the durations 12s, 1m15s, 1h01m and the total 1h03m: it needs the steps to run one after another.
- **Nothing reads the check's lines** but people and agents: the skills report "the check's last summary line"
  (`skills/check/SKILL.md`: "Report the final summary line"; the `Check:` line of the implementer's and the fixer's
  result blocks in `skills/next/SKILL.md` and `skills/fix/SKILL.md`). No script greps `ALL CHECKS PASSED`.
- **What every smoke script shares** (read script by script; `grep` for `mktemp`, `GetTempPath`, `worktree add`,
  `$here`, ports, `TMPDIR`, `UPDATE_`, sleeps and clocks):

  | Script (both shells unless named) | Temp folder | Worktrees, repositories | Writes outside its temp folder |
  |---|---|---|---|
  | `smoke-json.sh` | `mktemp -d` | none | no; calls `jq` only as an oracle when it is installed |
  | `smoke-hook` | `mktemp -d` / `nm-hook-<guid>` | none | no |
  | `smoke-release` | `mktemp -d` / `nm-rel-<guid>` | repositories under it; copies the repository (`tar`, `robocopy`) into `<tmp>/repocopy` and runs the lint there | no |
  | `smoke-slot` | `mktemp -d` / `nightmill-smoke-<guid>` | a repository and its slot worktrees under `<tmp>/wt` (`"root": "../wt"`); `ports` are only hint text, no socket is opened | no; the fake `gh` is in `<tmp>/bin` |
  | `smoke-render` | `mktemp -d` / `nightmill-render-<guid>` | a project under it | no |
  | `smoke-validate` | `mktemp -d` / `nm-val-<guid>` | copies the repository into `<tmp>/repocopy`, `<tmp>/repocopy2` | no; reads `.claude/nightmill.json` |
  | `smoke-status` | `mktemp -d` / `nm-status-<guid>` | `<tmp>/work`, `<tmp>/wt`; bash copies the repository into `<tmp>/repocopy` | only with `UPDATE_STATUS_FIXTURES=1`: `tests/fixtures/status/*/expected*.txt` |
  | `smoke-template-board` | `mktemp -d` / `nm-tplboard-<guid>` | a plugin copy under it | no |
  | `smoke-models` | `mktemp -d` / `nm-mod-<guid>` | a repository and a second worktree `<tmp>/repo-wt2` | no |
  | `smoke-load` | `mktemp -d` / `nm-load-<guid>` | `<tmp>/work`, `<tmp>/wt` | no; readings from `NIGHTMILL_LOAD_FIXTURE` |
  | `smoke-room` | `mktemp -d` / `nm-room-<guid>` | `<tmp>/work` | no; asserts on the wall clock (decision 4) |
  | `smoke-control` | `mktemp -d` / `nm-control-<guid>` | `<tmp>/work`, `<tmp>/wt`, `<tmp>/plain` | no |
  | `smoke-dashboard` | `mktemp -d` / `nm-dash-<guid>` | `<tmp>/work`, `<tmp>/wt` | only with `UPDATE_DASHBOARD_FIXTURES=1`: `tests/fixtures/dashboard/run-stall-old-free/expected.html` |
  | `smoke-panel` | `mktemp -d` / `nm-panel-<guid>` | `<tmp>/work`, `<tmp>/wt` | only with `UPDATE_PANEL_FIXTURES=1`: `tests/fixtures/panel/run-stall-old-free/expected.txt` |

  So no smoke script uses a fixed path, a fixed temp name, a port or the repository's git state; worktrees are created
  only under each script's own temp folder; the repository is only read. The one shared file is a fixture that a bash
  test rewrites when an `UPDATE_*_FIXTURES` variable is 1 while its PowerShell twin reads the same file. Neither the
  lint (`mktemp` only) nor any test sets or writes global git config, `HOME` or the real `gh`. `claude plugin validate`
  and `claude plugin test` were not checked for files they write (decision 4).
- **Load-sensitive assertions.** `smoke-room.sh` asserts a `--since` value within 5 s of the clock, a pause of at least
  1 s and a minute count from `now - 1700`; `smoke-room.ps1` fails a call that takes 30 s or more. `smoke-slot.*` wait
  up to 60 s (`Wait-For`, `Wait-Claims`) and 120 s (the claim gate) for background takes. These margins are wide
  against a few steps at once; see Risks.
- **CI** (`.github/workflows/ci.yml`): jobs `lint`, `smoke-bash` (`ubuntu-latest`, `timeout-minutes: 7`: `bash
  tests/smoke-json.sh`, then "Hide jq", then 13 `run: bash tests/smoke-<x>.sh` steps), `smoke-powershell`
  (`windows-latest`, `timeout-minutes: 38`: 13 `run: powershell -NoProfile -ExecutionPolicy Bypass -File
  tests/smoke-<x>.ps1` steps, so Windows PowerShell 5.1, never `pwsh`) and `validate` (not blocking). The ruleset on
  `main` requires the names `Lint (generic, JSON, skills, shell)`, `bash scripts smoke tests` and `PowerShell scripts
  smoke tests`. CI does not run `tests/check.sh` today.
- **The lint ties the check and CI by name today**: `== models is wired`, `== load is wired`, `== room is wired`,
  `== control is wired`, `== dashboard is wired` and `== slots pane is wired` grep both `tests/check.sh` and
  `.github/workflows/ci.yml` for `smoke-models`, `smoke-load`, `smoke-room`, `smoke-control`, `smoke-dashboard`,
  `smoke-panel` and `claude plugin test`, and `tests/check.sh` for `claude plugin test --help` and `claude plugin test
  not available`. No lint rule says that every smoke file is run by the check.
- **The schema** has `verification` with `check` (required), `manualCheckPaths`, `manualCheckText`, `benchRule`, and no
  `default` among them. `scripts/validate-config.*` support `type`, `properties`, `required`, `items`, `minimum`,
  `minItems`, `additionalProperties` and `enum`; `maximum` is refused by the lint (`== schema keywords are
  supported`), so a range is stated in the description and checked by the reader, as for `parallel.loadWindowSeconds`
  ("in seconds (2 to 60)").
- **Where the skills run the check.** `skills/workflow/SKILL.md` "Verify before every commit": "Run the check
  (`/nightmill:check`) before every commit. Never commit red." `skills/check/SKILL.md` runs `verification.check` and
  reports the final summary line. In `/next` the implementer runs the check in its step 3 before its commit, and in
  every fix round ("run the check, commit"); the session runs it after the rebase in step 5 for the CHANGELOG commit,
  before the pull request. In `/fix` the fixer runs it in its step 4 before its commit and in every fix round. Both
  report the step `check` "before every run of the check". The tester's prompt lists the check among the testing
  rules. `/nightmill:init` adds one permission rule `Bash(<the exact check command>)` for `verification.check`.
- **This machine**: Windows, Git's bash, `powershell` (5.1) on the PATH and no `pwsh`, `claude` with `plugin test`,
  `nproc` prints 4. Measured with a scratch script that runs the steps of `tests/check.sh` one after another and times
  each (no `claude plugin test`, to write nothing in the repository), on an otherwise idle machine:
  `lint` 194 s, `smoke-json.sh` 16 s, `smoke-hook.sh` 3 s, `smoke-release.sh` 472 s, `smoke-slot.sh` 2243 s,
  `smoke-render.sh` 50 s, `smoke-validate.sh` 771 s, `smoke-status.sh` 1094 s, `smoke-template-board.sh` 258 s,
  `smoke-models.sh` 58 s: 5159 s (1h25m) for the first ten steps, all green. The run was stopped there, during
  `smoke-load.sh`, so there is no number for the rest and none for a whole run; the CPU load read during it
  (`Win32_Processor.LoadPercentage`) was 0%. These numbers are not the baseline (decision 14); they only show that
  one step, `smoke-slot.sh`, is 43% of the part measured, and set the start order (decision 1). GitHub documents 4 processors for the standard `ubuntu-latest` and `windows-latest` runners of a
  public repository (not checked on a run; the check prints its limit, so the first run shows it).

## Decisions

**1. One step list, in one fixed order, for output and start.** `tests/check.sh` holds its steps in one block between
the lines `# steps: begin` and `# steps: end`, one line per step, `add <kind> <name>`:

- `add lint lint` runs `bash tests/lint.sh`;
- `add bash <file>` runs `bash tests/<file>`;
- `add ps <file>` runs `"$ps" -NoProfile -ExecutionPolicy Bypass -File tests/<file>` (decision 7 for `$ps`).

The list is today's order with iteration 41's `smoke-stages.*` and this story's `smoke-check.*` at the end of their
shell. After the block, the two `claude` steps keep today's code (their names, their availability tests and their
`SKIPPED:` texts, which the lint pins) and are added to the list behind the `ps` steps with the kind `claude`. The
steps are printed in list order; the order of output never depends on which step finishes first.

**Start order.** A line may end with the word `first` (`add bash smoke-slot.sh first`). The steps marked `first` are
started before all others, in list order; then the rest, in list order. Exactly two lines carry it,
`add bash smoke-slot.sh first` and `add ps smoke-slot.ps1 first`, because `smoke-slot.sh` alone took 2243 s of a
sequential run on this machine (Facts): started fourth in today's order behind steps that the other lanes could
take, it would end last and set the total. The mark changes when a step starts, never where its output is printed.
With L = 1 it is ignored: the steps run in list order, as today.

**2. The limit.** The check runs at most L steps at the same time, where L is, in this order of precedence:

1. `--jobs N` (PowerShell `-Jobs N`), N a whole number from 1 to 16 (`^[1-9][0-9]?$` and at most 16), taken as given;
2. else `verification.checkJobs` of `.claude/nightmill.json` at the repository root, read with `scripts/lib/json.sh`
   (`json_load`, `json_get`), when it is a whole number from 1 to 16;
3. else 4. A value that is present but not a whole number from 1 to 16 gives one line on standard error,
   `check: verification.checkJobs must be a whole number from 1 to 16; using 4`, and 4. A missing or unreadable
   config file gives 4 without a note (the lint reports a broken config).

A limit from 2 or 3 is then capped at the number of processors: `nproc`, else `getconf _NPROCESSORS_ONLN`; when neither
prints a whole number of at least 1, no cap. `--jobs` is not capped, so a test can ask for parallelism on any machine.
When any of `UPDATE_STATUS_FIXTURES`, `UPDATE_DASHBOARD_FIXTURES` or `UPDATE_PANEL_FIXTURES` is `1`, L is 1 whatever
the rest says (decision 4). A smaller list than L runs all at once. The default 4 is safe because it is capped at the
processors and the steps wait more than they compute (CPU near idle during a run, per the issue).

**3. How the steps run and print.** The first line of every run is the header of decision 5 or 6.

- **L = 1**: each step runs in the foreground, its output going straight to the terminal, exactly as today
  (`== <name>`, the output, `-- <name>: ok (<duration>)`), one after another in list order.
- **L ≥ 2**: the check makes one folder with `mktemp -d` (removed by a `trap` on `EXIT`) and starts each step as a
  background job in the start order of decision 1: `( t0=<clock>; <command> > "$dir/<i>.log" 2>&1 < /dev/null; rc=$?; t1=<clock>; printf '%s %s %s\n'
  "$rc" "$t0" "$t1" > "$dir/<i>.tmp" && mv "$dir/<i>.tmp" "$dir/<i>.done" ) &`, `<i>` the step's position in the list,
  `<clock>` the clock of `scripts/lib/ledger.sh`. Standard output and standard error of a step go into one file in the
  order the step wrote them; standard input is `/dev/null`. It starts steps in list order while fewer than L run, and
  looks for finished steps every 0.2 s (`sleep 0.2`; no `wait -n`, which bash 3.2 lacks). A job whose process has
  ended (`kill -0` fails) without a `.done` file counts as finished with exit code 1 and the line
  `(the step ended without a result)` after its output.
- **Printing (L ≥ 2)**: as soon as the first step not yet printed has finished, the check prints its section whole,
  `== <name>`, the content of its log file, `-- <name>: ok (<duration>)` or `-- <name>: FAILED (<duration>)`, and goes
  on with the next one; a step that finished early waits until every step before it in the list is printed. So
  sections are never interleaved and the bytes of the output are those of L = 1 for steps that write only to standard
  output, except the header (Tests check this).
- The duration of a step is `t1 - t0`, measured inside its job; the total of iteration 41 stays "from the check's start
  to the end of its last step": the check's start to the largest `t1`. The `Times:` block lists the steps in list
  order (for L = 1 that is "the order they ran" of iteration 41). With L ≥ 2 the total is the wall time and is shorter
  than the sum of the steps; iteration 41's remark "(so at least the sum)" holds only for L = 1. Nothing else of
  iteration 41's decision 13 changes.
- **Interruption**: on `INT` or `TERM` the check sends `TERM` to every job it started that still runs, removes its
  folder and exits 130, printing `CHECK INTERRUPTED` as its last line. A step's own child processes are not hunted
  down (Risks).

**4. Shared state: one ordered group, and one switch to a single lane.** The table under Facts shows no two smoke
scripts share a path, a temp name, a port or a repository, so every `lint`, `bash` and `ps` step runs beside any
other. Two exceptions:

- The two `claude` steps form one group: `claude plugin test` starts only after `claude plugin validate` has ended (in
  the same background job, each with its own section and time). Whether they write in the plugin folder was not
  checked, and running them one after another costs little. The group runs beside the other steps.
- The `UPDATE_*_FIXTURES` variables make a bash smoke test rewrite a fixture its PowerShell twin reads; with any of
  them at `1` the check runs with L = 1 (decision 2), so a maintainer who regenerates fixtures gets today's run.

No smoke script changes for this story. A test found later to disturb another when they run together is made
independent (its own temp folder, its own names), never dropped and never weakened.

**5. The full check's lines.** The header, the first line of every full run:

```
check: full, <L> at a time (<why>)
```

`<why>` is `--jobs <N>`, `verification.checkJobs <v>` or `default 4`, followed by `, capped at <p> processors` when the
cap lowered it, or is `<VARIABLE> is set` (the first of the three set, in the order of decision 2) when an
`UPDATE_*_FIXTURES` variable forced 1. Then the sections, the `Times:` block of iteration 41, the `SKIPPED:` lines as
today (same texts; in list order), and the verdict exactly as today: `CHECK FAILED: <names>` (the failed steps in list
order, separated by spaces as `${failed[*]}` prints them) and exit 1, or `ALL CHECKS PASSED` and exit 0. A step that
cannot run is listed as skipped as today and is not a failure.

**6. The quick mode: `--quick` (PowerShell `-Quick`).** It runs the steps of kind `lint` and `bash` and no other, under
the same limit. Its header is

```
check: QUICK, <L> at a time (<why>): the lint and the bash smoke tests only; the full check does not run
```

then the sections and the `Times:` block as in the full run, no `SKIPPED:` line for the PowerShell and `claude`
steps (they are left out, not skipped), and as its last line either

```
QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)
```

and exit 0, or

```
QUICK CHECK FAILED: <names> (the full check has not run)
```

and exit 1. The quick mode never prints `ALL CHECKS PASSED` and never prints `CHECK FAILED: ` at the start of a line.

**7. `--only` and `--powershell`, for CI.**

- `--only <name>[,<name>...]` (PowerShell `-Only`) runs exactly the named steps of the list, in list order, under the
  same limit and rules. A name that is not in the list is a usage error. Its header is
  `check: only <the names, comma-separated, in list order>, <L> at a time (<why>)`, its last line
  `SELECTED CHECKS PASSED (<k> of <n> steps; the full check has not run)` (exit 0) or
  `SELECTED CHECKS FAILED: <names> (the full check has not run)` (exit 1). A named `ps` step without PowerShell gives
  today's `SKIPPED: PowerShell smoke tests (no pwsh or powershell)`, a named `claude` step without `claude` today's
  `SKIPPED:` line.
- `--powershell powershell|pwsh` (PowerShell `-PowerShell`) picks the PowerShell for the `ps` steps instead of today's
  rule (`pwsh`, else `powershell`); when the named one is not on the PATH the `ps` steps are skipped with today's line.
  CI uses it to keep testing Windows PowerShell 5.1 (Facts).

**8. Options, usage and `tests/check.ps1`.**

```
tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh]
```

`--quick` with `--only`, an option given twice, a missing or bad value, an unknown step or any other argument: the
line `usage: tests/check.sh [--quick | --only <step>[,<step>...]] [--jobs <1-16>] [--powershell powershell|pwsh]` on
standard error, and for an unknown step first `check: no step named <name>`, then exit 2, before any step runs. No
argument: the full check, as today. `tests/check.ps1` gets `param([switch]$Quick, [string]$Only, [string]$Jobs,
[string]$PowerShell)` and passes `--quick`, `--only <Only>`, `--jobs <Jobs>` and `--powershell <PowerShell>` for each
one given (`$Jobs` is a string, so `tests/check.sh` validates it and both shells give the same usage error), then
returns the exit code of `tests/check.sh` as today. Its header comment names the parameters.

**9. Two runs of the check on one machine.** A run's only state of its own is the folder of decision 3, from
`mktemp -d`, so two runs (in two slots, or two in one checkout) never share a file. Every step's state is its own temp
folder (Facts). A smoke case runs two checks at once (Tests).

**10. The skills: the quick check only while code is written, the full check before every commit.** A commit is never
made after the quick check alone, and since every commit of a slot's branch is pushed with the pull request, "the full
check before a commit that is pushed" is "the full check before every commit". No config key is added for it (the
issue names one key, the limit): *the quick check* is the check command with ` --quick` appended
(`bash tests/check.sh --quick` here). It counts as a quick check only when its first line starts with `check: QUICK`
(decision 6); when it does not (a project's check without a quick mode, which may fail on the argument or ignore it),
the agent stops using it for the rest of its task and runs the check instead, so a project without a quick mode runs
the full check everywhere, as today. Exactly:

- `skills/workflow/SKILL.md`: line 14 gains `*the quick check* is the check with ` --quick` appended, for a check
  whose first line then starts with `check: QUICK``. "Verify
  before every commit" keeps its first sentence and gains: "While code is being written and before the work is done,
  an agent may run the quick check instead, as often as it likes, to see where it stands. The quick check never stands
  for the check: the check runs before every commit, before every pull request and in every fix round, and a
  `Check:` line reports the check's last line, never the quick check's."
- `skills/next/SKILL.md`, the implementer's prompt: the testing rules gain `- the quick check:
  <verification.check> --quick (only when its first line starts with "check: QUICK"; else run the check)`; step 2 becomes "Implement until the tests pass. While you work
  you may run the quick check to see where you stand; it is not the check of step 3 and you do not report it as
  `check`. <verification.benchRule, when set>"; step 3 (the check, then the commit) and every fix-round prompt ("run the
  check, commit") stay the full check. The session's check after the rebase in step 5 stays the full check. The
  `Check:` line of the result block becomes `Check: <the last line of the check (never of the quick check)>, green or
  red`.
- `skills/fix/SKILL.md`, the fixer's prompt: the same three changes (testing rules, its step 2, the `Check:` line); its
  step 4 and the fix rounds stay the full check.
- `skills/check/SKILL.md`: `/nightmill:check` runs `verification.check` as today. `/nightmill:check quick` runs
  `<verification.check> --quick` and reports its last line with the words "quick check: not the check before a
  commit"; when its first line does not start with `check: QUICK` it says
  `the check command has no quick mode; running the check` and runs `verification.check`. The description keeps
  "Use before every commit".
- `skills/init/SKILL.md` does not change (no key to propose, no permission rule added; see Left).
- The tester's prompt, the reviewers and the step names of the report tables do not change; a quick run is part of
  the step `code`.

**11. The lint: no smoke script the check does not run.** A new section `== the check runs every smoke script` in
`tests/lint.sh`, before `== text from issues is data`:

1. `tests/check.sh` has exactly one line `# steps: begin` and one `# steps: end` after it, and every non-empty line
   between them matches `^add (lint|bash|ps) [A-Za-z0-9._-]+( first)?$`; else
   `FAIL: tests/check.sh: the step list between '# steps: begin' and '# steps: end' is missing or malformed`.
2. Every file `tests/smoke-*.sh` appears exactly once as `add bash <file>` and every `tests/smoke-*.ps1` exactly once
   as `add ps <file>`; else `FAIL: tests/check.sh does not run tests/<file>` or
   `FAIL: tests/check.sh runs tests/<file> more than once`. A `.sh` listed as `ps` or the other way round counts as
   not run.
3. Every `bash` and `ps` name in the block is a file in `tests/`; else
   `FAIL: tests/check.sh runs tests/<file>, which does not exist`. The block has `add lint lint`; else
   `FAIL: tests/check.sh does not run the lint`.
4. `ALL CHECKS PASSED` occurs exactly once in `tests/check.sh`; else
   `FAIL: tests/check.sh prints ALL CHECKS PASSED in more than one place`.
5. The key and words are wired: `schema/nightmill.schema.json` has `"checkJobs"`,
   `templates/nightmill.example.json` has `verification.checkJobs` 4 (read with `json_get`), `README.md` mentions
   `checkJobs` and `--quick`, `CONTRIBUTING.md` mentions `--quick`, and `skills/workflow/SKILL.md`,
   `skills/next/SKILL.md`, `skills/fix/SKILL.md` and `skills/check/SKILL.md` mention `--quick` and `check: QUICK`;
   each miss is `FAIL: <file> does not mention <word>`.
6. CI runs what the check runs (criterion 9). In `.github/workflows/ci.yml`:
   - exactly one line is `run: bash tests/check.sh --only <names>` and exactly one is
     `run: bash tests/check.sh --powershell powershell --only <names>`; else
     `FAIL: .github/workflows/ci.yml: the smoke jobs do not run tests/check.sh --only`;
   - the names of the first are, comma-separated and each once, exactly the `add bash` files of the step list except
     `smoke-json.sh`, and the names of the second exactly the `add ps` files, both in list order; a missing name is
     `FAIL: .github/workflows/ci.yml does not run tests/<file>`, an extra or repeated one
     `FAIL: .github/workflows/ci.yml: tests/<file> is not a step of its job or is named twice`, and the right names in
     another order `FAIL: .github/workflows/ci.yml: the --only list is not in the order of the step list`;
   - `run: bash tests/smoke-json.sh` occurs exactly once, and no other line runs a smoke file directly
     (`run: bash tests/smoke-` or `-File tests/smoke-`); else
     `FAIL: .github/workflows/ci.yml runs tests/<file> outside tests/check.sh`;
   - the three `name:` lines that the ruleset requires (Facts) are each present exactly once; else
     `FAIL: .github/workflows/ci.yml: the required job <name> is missing`.

The existing greps of `tests/check.sh` and `ci.yml` (Facts) keep passing: the names stay in both files (decision 12).

**12. CI: the same runner, the same jobs.** No job is added, removed or renamed, no `name:`, `runs-on`,
`timeout-minutes`, `permissions`, `concurrency` or pin changes, and the `validate` job stays as it is. Only the test
steps of the two smoke jobs change:

- `smoke-bash`: `run: bash tests/smoke-json.sh` and "Hide jq" stay first, as today; the 13 `run: bash
  tests/smoke-<x>.sh` steps become one step
  `run: bash tests/check.sh --only <every bash file of the step list but smoke-json.sh, comma-separated, in list order>`. So
  `smoke-json.sh` still runs once, with `jq`, and the rest without it, as today.
- `smoke-powershell`: the 13 `run: powershell ...` steps become one step with `shell: bash` (Git's bash on the Windows
  runner) and `run: bash tests/check.sh --powershell powershell --only <every ps file of the step list, comma-separated,
  in list order>`.

Each job then runs its tests with the limit of decision 2 (this repository's `verification.checkJobs` 4, capped at
the runner's processors) and prints the header, the sections in order, the `Times:` block and its verdict; the job
fails when the check exits non-zero. The required checks are the same three names. Every smoke file is still named in
`ci.yml`, so the lint's greps hold, and rule 6 of decision 11 keeps the two `--only` lists equal to the step list.

**13. What changes of iteration 41.** Its rules stay; this story adds to them:

- The `Times:` block lists steps in list order, and the total is the wall time (decision 3).
- `NIGHTMILL_CHECK_STEPS` lines may have a third field, the kind (`lint`, `bash`, `ps` or `claude`; a line with two
  fields is `bash`, so iteration 41's files keep their meaning), and a fourth, a reason: a step with a reason is not
  run and is listed as `SKIPPED: <reason>`, so the tests can show a step that cannot run. `--quick` and `--only` select
  among the fixture steps by kind and name; the limit applies to them as to the real steps. Each fixture step still
  runs as `bash -c <command>`.
- Its test `== the check's step times` in `tests/smoke-stages.sh` and `.ps1` runs the check with `--jobs 1` /
  `-Jobs 1`, because its three steps move one shared fixture clock in turn; its expected lines stay, plus the header.

**14. The measurement and the 40% rule.** On one machine, idle but for the check, with PowerShell and `claude` on the
PATH: *before* is the `total` of the `Times:` block of `bash tests/check.sh` on `main` with iteration 41 merged and
this story not; *after* is the `total` of `bash tests/check.sh` on the branch, with its default limit (the header
shows it). Both numbers, the header line of the after run and the machine's processor count go into "How verified" of
the pull request. The story is done when after ≤ 0.6 × before. The steps added by this story (`smoke-check.*`) count
in after. When after is above 0.6 × before, the implementer reports `partial` with both numbers and the five longest
steps of the after run; it does not drop or shorten a test to reach the number.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | Independent steps run at once, up to a configured limit with a safe default; 1 runs them in order as today | Decisions 2, 3, 4; key `verification.checkJobs` (Story trigger) |
| 2 | Output readable, in a fixed order, each step whole under its name, never interleaved | Decisions 1, 3 |
| 3 | Verdict unchanged: non-zero exit on a failure, failed steps listed, unrunnable steps skipped | Decisions 5, 13 |
| 4 | No test dropped or weakened; the lint fails on a smoke script the check does not run | Decisions 4, 11, 12, 14 |
| 5 | Shared state made independent or grouped; a smoke case shows two parallel checks do not disturb each other | Facts (the table), decisions 4, 9; Tests (`== two checks at once`) |
| 6 | Quick mode: lint and bash smoke only; says it is quick and the full check has not run; never the all-passed line | Decision 6 |
| 7 | `/next`, `/fix`, `/check` use the quick mode only between steps, the full check before a commit and a pull request; the manual check and "run the check before every commit" hold | Decision 10 |
| 8 | Total and per-step times from the timing story's report; before and after measured; at least 40% shorter | Decisions 3, 13, 14 |
| 9 | CI uses the same parallelism, no change to the jobs that must pass | Decisions 11 (rule 6), 12; Tests (`tests/lint.sh`, the pull request's CI run) |
| 10 | Same in PowerShell and bash, smoke steps in both: order, verdict, failing, skipped, limit 1, quick | Decision 8; Tests |
| 11 | README and contributor guide describe the limit, the quick mode and when each is used | Files touched (README, CONTRIBUTING) |

## Tests

**`tests/smoke-check.sh` and `tests/smoke-check.ps1`** (new; in the step list and in both CI jobs' `--only`). The bash
test runs `bash tests/check.sh`, the PowerShell test runs `tests/check.ps1` with the same PowerShell that runs it and
PowerShell parameters (`-Jobs 3` for `--jobs 3`, `-Quick`, `-Only`); the cases and the expected text are the same.
Each case writes its own `NIGHTMILL_CHECK_STEPS` file in the test's temp folder and sets `NIGHTMILL_CLOCK_FILE` to a
file that holds one fixed time, so every duration is `0s`. A "barrier" below is a loop of at most 300 tries 0.1 s
apart waiting for a file, then exit 9.

- `== order and verdict` (criteria 2, 3): steps `one` (waits for the file `two.done`, prints `out of one`, exits 0),
  `two` (prints `out of two`, creates `two.done`, exits 0), `three` (prints `out of three`, exits 1), `four` (kind
  `bash`, reason `four cannot run here`). With `--jobs 3`: the header `check: full, 3 at a time (--jobs 3)`; the
  sections `== one`, `out of one`, `-- one: ok (0s)`, then `== two` ..., then `== three`, `out of three`,
  `-- three: FAILED (0s)`, in that order though `two` finished first; no line of one section between the lines of
  another; the `Times:` block with `one`, `two`, `three` and `total`; `SKIPPED: four cannot run here`;
  `CHECK FAILED: three`; exit 1; no `ALL CHECKS PASSED`.
- `== the limit of 1` (criteria 1, 10): steps `a`, `b`, `c` that each append `start <name>` and `end <name>` to one
  log, with `b` printing two lines. With `--jobs 1` the log is exactly `start a`, `end a`, `start b`, `end b`,
  `start c`, `end c` and the last line is `ALL CHECKS PASSED`, exit 0. With `--jobs 3` and a barrier in `a` that waits
  for `start c`, the log has `start c` before `end a` (they ran at once), and the output equals that of `--jobs 1`
  line for line except the header.
- `== quick` (criterion 6): steps of each kind, `l` (`lint`), `b` (`bash`), `p` (`ps`), `c` (`claude`), each
  appending its name to a log. `--quick`: the log holds `l` and `b` only; the first line is
  `check: QUICK, <L> at a time (<why>): the lint and the bash smoke tests only; the full check does not run`; the last
  line is `QUICK CHECK PASSED (the lint and the bash smoke tests only; the full check has not run)`; exit 0; no line
  `ALL CHECKS PASSED`, no `SKIPPED:` line. With `b` failing: the last line
  `QUICK CHECK FAILED: b (the full check has not run)`, exit 1, no line starting `CHECK FAILED: `.
- `== only and usage` (decision 7, 8): `--only b,l` runs `l` then `b` (list order), header `check: only l,b, ...`, last
  line `SELECTED CHECKS PASSED (2 of 4 steps; the full check has not run)`. Each of `--only nope` (also
  `check: no step named nope`), `--quick --only b`, `--jobs 0`, `--jobs 17`, `--jobs x`, `--jobs`, `--powershell
  cmd`, `--quick --quick` and `extra` gives the usage line on standard error, exit 2, and no step runs (the log stays
  empty).
- `== the limit from the config` (decision 2): a copy of `tests/check.sh`, `tests/check.ps1` and `scripts/lib/` in a
  throwaway repository with its own `.claude/nightmill.json` and a one-step `NIGHTMILL_CHECK_STEPS` file. With
  `"checkJobs": 2`: the header ends `(verification.checkJobs 2)`, or `(verification.checkJobs 2, capped at 1
  processors)` on a one-processor machine (the test reads `nproc` the same way); with `"checkJobs": 99` and with
  `"checkJobs": "x"`: the note `check: verification.checkJobs must be a whole number from 1 to 16; using 4` on standard
  error and `(default 4)` before any cap; without the key: `(default 4)`; with `UPDATE_PANEL_FIXTURES=1` and
  `--jobs 3`: `check: full, 1 at a time (UPDATE_PANEL_FIXTURES is set)`.
- `== two checks at once` (criterion 5): two checks started together in the same checkout, each with `--jobs 2`, its
  own `TMPDIR` (an empty folder) and its own steps file: a step that prints `run A` (`run B`) and waits by barrier for
  the other run's started-file, then `bash tests/smoke-render.sh` and `bash tests/smoke-hook.sh` (PowerShell test:
  `smoke-render.ps1` and `smoke-hook.ps1` run with its own PowerShell). Both exit 0 with `ALL CHECKS PASSED`, each
  output holds its own `run` line and not the other's, its sections in list order, and after both have exited both
  `TMPDIR` folders are empty (each run removed its own folder).

**`tests/smoke-stages.sh` and `tests/smoke-stages.ps1`** (iteration 41): `== the check's step times` runs the check
with `--jobs 1` / `-Jobs 1` (decision 13); the rest of the case is unchanged.

**`tests/lint.sh`**: the section of decision 11. Break each rule once in a scratch copy and see it fail: remove
`add bash smoke-hook.sh`, list a file twice, list `smoke-nope.sh`, add a second `echo "ALL CHECKS PASSED"`; in a
scratch copy of `ci.yml` (rule 6): drop `smoke-hook.sh` from the bash `--only` list, drop `smoke-hook.ps1` from the
PowerShell one, name `smoke-json.sh` in the bash list, swap two names, add back a line
`run: bash tests/smoke-render.sh`, and rename `name: bash scripts smoke tests`; each gives its `FAIL:` line.

**The pull request's CI run** (criterion 9): the implementer reads the logs of the run on the pull request
(`gh run view --log`, read only) and writes into "How verified" the header line of each smoke job (for example
`check: only smoke-slot.sh,..., 4 at a time (verification.checkJobs 4)`, or with `, capped at <p> processors`) and
its `total`, and that the three required checks passed under their names. A header with `1 at a time` on a runner
that reports more than one processor is a finding.

**The full check on the branch**: `bash tests/check.sh` green (and `tests/check.ps1` from a PowerShell prompt), with
the new smoke steps, and the measurement of decision 14 written into the pull request.

**Manual check by the maintainer** (skills change): in a second clone of this repository on the branch, with nightmill loaded from a separate checkout of the branch
(`claude --plugin-dir <that checkout>`, started in the second clone, never in the checkout being loaded), run
`/nightmill:next` on a small Approved story and watch: the implementer runs `bash tests/check.sh --quick` while it
writes code and `bash tests/check.sh` before its commit, every fix round runs the full check, the session runs the
full check after the rebase, and the pull request's "How verified" shows `ALL CHECKS PASSED`, never a `QUICK` line.
Run `/nightmill:check quick` once and see its words.

## Files touched

- `tests/check.sh`: the step list (decision 1), the options (decisions 6, 7, 8), the limit (decision 2), the runner
  and printer (decision 3), the groups (decision 4), the lines (decisions 5, 6, 7), the extended
  `NIGHTMILL_CHECK_STEPS` (decision 13). The header comment lists the options and says that the step list is what the
  lint reads.
- `tests/check.ps1`: the parameters of decision 8.
- `tests/smoke-check.sh`, `tests/smoke-check.ps1` (new); `tests/smoke-stages.sh`, `tests/smoke-stages.ps1`: the
  sections of Tests.
- `tests/lint.sh`: decision 11.
- `.github/workflows/ci.yml`: decision 12.
- `schema/nightmill.schema.json`, `templates/nightmill.example.json`, `.claude/nightmill.json`: the key (Story
  trigger).
- `skills/workflow/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/check/SKILL.md`: decision 10.
- `README.md`: the `verification` row of the configuration table becomes "The check command, which paths also need a
  manual check and what that check is, an optional bench rule, how many steps of the check run at once
  (`checkJobs`, default 4, for a check that reads it)". "Developing nightmill" gains, after the code block, a paragraph: `tests/check.sh`
  runs up to `verification.checkJobs` steps at once (never more than the processors; `--jobs N` for one run; 1 runs
  them one after another, as before), prints each step whole and in a fixed order, and its times;
  `bash tests/check.sh --quick` runs the lint and the bash smoke tests only and says that the full check has not run;
  use it while writing code, and the full check before every commit and pull request; CI runs the smoke jobs through
  `tests/check.sh --only`. The code block gains the lines `bash tests/check.sh --quick` and `bash tests/smoke-check.sh`
  / `powershell -ExecutionPolicy Bypass -File tests/smoke-check.ps1`.
- `CONTRIBUTING.md`: "Before you open a pull request" keeps `bash tests/check.sh` and replaces the paragraph after it
  with: what the full check runs (the lint, the bash and PowerShell smoke tests, `claude plugin validate` and
  `claude plugin test` when they are installed), that it runs up to `verification.checkJobs` steps at once and lists
  what it skipped, that `bash tests/check.sh --quick` is for the loop while writing and is never the check before a
  commit or a pull request, and that CI runs all of them.
- `CHANGELOG.md`, one bullet under `Unreleased`: `- Iteration 42 (#200): the check runs its independent steps in
  parallel and has a quick mode. tests/check.sh runs up to verification.checkJobs steps at once (new key, default 4,
  capped at the processors; --jobs N for one run; 1 runs them one after another), prints each step whole in a fixed
  order with its time, and keeps its verdict; --quick runs the lint and the bash smoke tests only and never prints ALL
  CHECKS PASSED. /next and /fix may run the check with --quick while code is written and run the full check
  before every commit and pull request. CI runs its smoke jobs through tests/check.sh --only. A lint rule fails when a
  smoke script is not in the check or the CI lists differ from the check's.`

## Risks

- **Load-sensitive tests.** Steps that assert on the wall clock (`smoke-room.*`) or wait for background processes
  (`smoke-slot.*`) run slower beside three others. Their margins (5 s, 30 s, 60 s, 120 s) are wide; a test that fails
  only in parallel is a finding to fix in that test (decision 4), and `--jobs 1` gives today's run meanwhile.
- **The longest step bounds the gain.** No parallel run is shorter than its longest step. `smoke-slot.sh` took 2243 s
  of the sequential run measured here (Facts); the target holds only while the longest step is at most 60% of the
  sequential total. Decision 1 starts the two slot tests first; decision 14 makes a missed target visible (`partial`
  with the five longest steps) instead of letting a test be cut or the marks be moved silently. See Left.
- **Windows process start.** Each PowerShell step starts a new Windows PowerShell and many `git` and `bash` processes;
  four at once may contend for disk more than for CPU. The measurement shows it.
- **`bash` on the Windows runner.** `shell: bash` names Git's bash on GitHub's Windows images; a bare `bash` on the PATH
  could be another. Iteration 41's `smoke-stages.ps1` already runs `tests/check.ps1` (which uses `Get-Command bash`) in
  that job, so the same question exists there.
- **An interrupted check** may leave a step's child processes (a `git` or a PowerShell) running for a while; they
  write only into their own temp folders.
- **The polling** adds up to 0.2 s per step to the wall time, about 6 s over 30 steps; negligible against minutes.

## Size estimate

`L`: about 700 changed lines. `tests/check.sh` about 200 (most of the file is rewritten), `tests/check.ps1` about 20,
the two smoke tests about 350 together, `smoke-stages.*` about 4, the lint about 90, CI about 30 (26 lines become 4),
the schema, the example and the config about 4, the four skills about 25, README and CONTRIBUTING about 25, CHANGELOG
about 8.

## Not done

- Choosing which tests run from the files that changed, rewriting or removing a test, or making one smoke test faster
  (the issue's Out of scope); a cache or a remote runner.
- Any change to which CI jobs block a merge, their names, the matrix, the timeouts, the permissions or the pins
  (#154, #155, #156).
- The lint that every smoke file is in the README, and that every `.sh` has a `.ps1` twin (#157); this story adds
  "the check runs every smoke script" and "the CI `--only` lists equal the step list" (decision 11, rules 2 and 6).
- A parallel or quick mode for a project's own check command: `verification.checkJobs` is read by nightmill's
  `tests/check.sh`, and a project's check uses it, or has a `--quick`, only if it implements them.
- A second config key for the quick check, and a permission rule for it in `/nightmill:init` (see Left).
- A timeout per step, a retry of a failed step, a progress line while a step runs (L ≥ 2 prints a section only when it
  and every step before it are done).
- `/spec`, the tester and the reviewers: they run no check and do not change. The quick check in `.claude/CLAUDE.md`'s
  command list.
- Commits per criterion (#149): see Left.

## Left

- **"A commit that is pushed".** The issue asks for "the full check before a commit that is pushed" and also keeps
  "run the check before every commit". Every commit of a slot's branch is pushed with the pull request, so this spec
  reads both as "the full check before every commit" and lets the quick check run only while code is written, with no
  commit after it (decision 10). A looser reading (quick before a local commit, full only before the push) would let
  more runs be quick but would make "run the check before every commit" true only of the quick check; that is for the
  maintainer to choose, and for #149 (a commit and a push per criterion), whose spec should say which check each of
  its commits gets.
- **The quick check without a key.** The issue names one new key (the limit), so the quick check is the check command
  with ` --quick` appended, recognised by its first line `check: QUICK` (decision 10); no key and no init change. Two
  consequences for the maintainer: a project's check gets a quick mode only by implementing `--quick` and that header,
  and `/nightmill:init`'s exact rule `Bash(<the exact check command>)` (Facts) does not cover `<check> --quick`, so in
  an unattended run (epic #47) the first quick check may ask for permission until the maintainer allows it. A key of
  its own (`verification.quickCheck`) and an init rule for it would settle both, but they are a further config key and
  a story of their own.
- **The start order and the 40%.** The two `first` marks of decision 1 come from one sequential run on this machine
  (Facts). If the before and after runs show that another step sets the total, moving a mark is a change of this spec
  for the maintainer to approve, not the implementer's choice; and if one smoke test alone is longer than 60% of the
  sequential total, the 40% cannot be reached by running steps side by side, and making that test faster is the story
  of its own the issue names under Out of scope.
- **#157 and `ci.yml`.** After decision 12, `ci.yml` names the smoke files in two `--only` lists instead of one step
  each, and rule 6 of decision 11 checks those lists against the step list. #157's "every `tests/smoke-*` file is
  listed in `ci.yml`" then holds through the step list; its spec should build on rule 6 rather than repeat it.
