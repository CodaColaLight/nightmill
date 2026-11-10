# Iteration 52: a driver runs /fix all and /next headless in a loop and posts one summary, and a workflow template runs it on a schedule

Status: delivered in iteration 52 (PR #269)

Story #164, epic #163 (capabilities of comparable tools), gap 1 of the gap analysis of 2026-11-05. Today every run
starts with a person typing a command; the README's `## Running unattended` (iteration 49) gives the `claude -p` lines
but nothing starts them. After this iteration a driver script, `scripts/drive.sh` and `scripts/drive.ps1`, runs
`/nightmill:fix all` and then `/nightmill:next <N>` headless, round after round, until no Ready bug and no Approved
story is left, its time limit is reached or its kill switch is set. It checks for a free slot and room on the machine
before each step, takes nothing that a run could not start, posts one summary comment (what was picked, merged,
blocked, and what it cost) and leaves no process running. A workflow template, `templates/workflows/nightmill-drive.yml`,
runs the same driver on a schedule and on demand on a self-hosted runner. Two config keys are added
(`unattended.maxMinutes`, `unattended.summaryIssue`). Changes `scripts/drive.sh` and `scripts/drive.ps1` (new),
`templates/workflows/nightmill-drive.yml` (new), `schema/nightmill.schema.json`, `templates/nightmill.example.json`,
`README.md`, `tests/smoke-drive.sh` and `tests/smoke-drive.ps1` (new) with fixtures under `tests/fixtures/drive/`,
`tests/test-drive-docs.sh` (new), `tests/lint.sh`, `tests/check.sh`, `.github/workflows/ci.yml` and `CHANGELOG.md`.

## Story trigger and manual check

**A story trigger: a new config key.** Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The driver sets no status and adds none; the statuses it
  causes are the ones `/fix` and `/next` set themselves (decision 9). No decision record is needed, and none of
  `docs/decisions/` 0001 to 0003 is contradicted: they say how nightmill develops and releases itself. This repository
  does not install the workflow (Not done), so 0003's "work on the installed release" is untouched.
- *A new, renamed or removed config key*: **yes**, two new keys under a new object `unattended`: `maxMinutes` and
  `summaryIssue` (decision 6). Each goes into `schema/nightmill.schema.json` with a description and a default (or, for
  `summaryIssue`, the stated absence), into `templates/nightmill.example.json` and into the README's configuration
  table. Nothing is renamed or removed. **Compatible** (invariant not ticked in the issue, checked anyway): the schema
  says "Unknown keys are ignored", and the previous version's `validate-config` reports an unknown top-level key as a
  warning, not an error; only its `--strict` fails on it. So a config with `unattended` stays readable by 0.6.0.
- *A change to the slot marker format*: no. The driver reads `slot --status --porcelain` and calls `slot --reap`, as
  `/status` and every take do; no marker, field or file under `<worktrees.root>/.slots/` changes. The driver's own two
  files (the lock and the kill switch) live in the git common directory, not beside the markers (decisions 4 and 5).
  The slot scripts are hot files and are not touched.

**The manual check does not apply.** `verification.manualCheckPaths` is `skills`, `agents`, `hooks`; no file under
them changes. No skill calls the driver, so no **Run permissions** rule is added and `/init` does not change. The
truth of the headless facts the driver rests on is checked by the implementer's probe (Tests, "The probe").

**Both shells** (invariant ticked): the driver exists as `scripts/drive.sh` and `scripts/drive.ps1` with the same
rules, lines and exit codes, except where a decision names a difference of the platform (signals, decision 8). Each has
a smoke test, `tests/smoke-drive.sh` and `tests/smoke-drive.ps1`, in the step list of `tests/check.sh` and in the
matching `--only` list of `ci.yml`, and both are listed in the README (iteration 51's agreement lint).

**Order with other work.**

- *#165* (limits, a kill switch and a run ledger) is at Backlog with no spec and lands after this one (decision 1 says
  what this spec takes and what it leaves to #165).
- *#213* (the skills grant their own scripts) is open: until it lands, an upgrade of nightmill needs `/init` again
  before a headless run, as `### Before the first run` says. The driver adds no rule of its own, so #213 does not need
  to land first.
- *#176* (a claim protocol) is open. The driver runs one driver per repository (decision 4) and starts `/next` only
  with a number, so the driver itself never races another driver for an item; an interactive session beside it can,
  as today (Risks).
- The permission bug the agent notes name is closed: #109 (the run permissions, iteration 43) and #110 (the deny
  rules and the guard, iteration 47); iteration 50 (#253) is merged. Iteration 49 (#160) is merged, and this spec
  builds on its `## Running unattended`.

## Facts this rests on

Read on `main` at 757012e (iteration 51 merged), on 2026-11-10, read only. The issues were read with
`gh issue view <n> --json number,state,title`: #165, #213, #176, #169 and #47 are open. Claude Code 2.1.322 is
installed here; `claude --help`, `claude --version` and `claude plugin list --json` were run, nothing else with
`claude`.

- **No trigger exists.** No file in `scripts/` loops over skills, and no workflow under `templates/` exists. The
  README says "Nothing in nightmill starts runs on a schedule yet ([#164](...))" (`## Running unattended`) and "no
  trigger that starts runs ships yet ([#164](...))" (under the Security model's table).
- **The headless command** is iteration 49's: `claude -p "/nightmill:fix all" --permission-mode manual` and
  `claude -p "/nightmill:next <N>" --permission-mode manual`, in the main checkout, on the base branch, with a clean
  tree, in a trusted workspace with `/init`'s four permission lines applied. `--output-format json` prints one JSON
  object whose `result` is the final message and which carries `total_cost_usd` and `num_turns` (iteration 49 Facts;
  the probe checks the fields).
- **`/fix all`** "Fixes every Ready bug without asking the maintainer anything", sets In progress only after a take
  succeeded, ends with one table (`| Bug | Result | PR | Slot | Cause or reason | Verified |`), stops the whole run "if
  the working tree is dirty at the start", and has its own limit `parallel.fixAllMaxBugs` (default 0: no limit). Its
  gate already says "The pause flag and the limits of an unattended run, once they exist, are checked there".
- **`/next` without a number** asks the maintainer on a tie of priorities (workflow skill, **Picking an issue** rule
  2), and nobody answers a headless run (README, `### Before the first run`). With a number it takes that story.
  `/next` sets In progress (step 2.1) **before** it takes a slot (step 2.2), so a `/next` that finds every slot busy
  leaves its story at In progress with nothing behind it (iteration 49, Left).
- **The board listing** of the scripts is `gh project item-list <n> --owner <o> --limit 200 --format json`, read with
  `scripts/lib/json.awk` in bash and `ConvertFrom-Json` in PowerShell (`scripts/status.*`); an item's status and
  priority are under the lower-cased names of `board.statusField` and `board.priorityField`, its labels under
  `labels`, its number and type under `content`.
- **The slots and the room.** `slot.sh --status --porcelain` prints `<n>\tfree` for a free slot and a ten-field busy
  line otherwise; `slot.sh --reap` frees every busy slot whose pull request merged. `room.sh` exits 0 (start), 1 (no
  room yet; it has paused; call again with the value of its `room: call again with` line), 2 (it cannot run) or 3 (the
  longest wait ran out); the skills' handling is in the workflow skill's **Room on the machine**.
- **The configuration** that governs a run is the base branch's (`scripts/lib/baseconfig.*`, iteration 48).
- **A plugin's install path** is printed by `claude plugin list --json` as `installPath` of the entry whose `id` is
  `nightmill@nightmill`; it ends in the version folder, so it changes with every upgrade.
- **GitHub Actions** (in substance, from GitHub's documentation): pushes and pull requests made with the workflow's
  `GITHUB_TOKEN` start no other workflow run, so a pull request opened with it would never get its required checks;
  that token also cannot write a Projects board owned by a user account. A `schedule` trigger reads its `cron` only
  from the workflow file on the default branch. A cancelled run sends the step SIGINT, then SIGTERM, then kills it
  within about ten seconds. A self-hosted runner runs jobs as the user it was installed for, with that user's files
  and logins.

## Decisions

**1. What this spec takes from #165's subject, and what it leaves.** The criteria need "a limit is reached or the kill
switch is set" and "what it cost" now, before #165. This spec gives the driver the smallest pieces that make its own
loop end and report, and nothing that bounds a skill:

- *Taken here:* one wall-clock limit for a whole driver run (`unattended.maxMinutes`, decision 6), checked by the
  driver between steps; a kill switch that only the driver reads, between steps (decision 5); one driver per
  repository (decision 4); and the cost as Claude Code reports it in each step's JSON result (`total_cost_usd`), summed
  in the summary (decision 10).
- *Left to #165:* the minutes per issue, the turns per role, the issues per run, the cost per issue, a turn or budget
  flag on the `claude -p` line (`--max-turns`, `--max-budget-usd`), the pause flag read from the base branch's config
  or an epic's label and checked by every skill, the run ledger file, and the `blocked` label. The driver writes no
  ledger: the summary comment is its only record. When #165 lands, its pause flag and limits are added to the driver's
  checks of decision 3 step 1, beside the kill switch and the time limit, which stay.

Reason: the loop must end by itself without #165 or the criteria cannot be met; a run-level clock and a local stop
file are the two that need no skill change and do not overlap a per-issue or per-role limit.

**2. What the driver runs.** "Ready or Approved" in the criteria is read as the work the two named skills take: a
**Ready bug** (`/fix all`) and an **Approved story** (`/next`). A Ready story waits for `/spec`, which the criteria do
not name; the driver does not run it and lists such stories in the summary (decision 10). Each step is exactly one of:

```
claude -p "/nightmill:fix all" --permission-mode manual --output-format json
claude -p "/nightmill:next <N>" --permission-mode manual --output-format json
```

run in the main checkout (the parent of `git rev-parse --git-common-dir`), with stdout to `<run dir>/step-<k>.json` and
stderr to `<run dir>/step-<k>.err` (decision 7). No other flag: not `--bare`, `--dangerously-skip-permissions`,
`--permission-mode bypassPermissions` or `auto`, `--allowedTools`, `--continue` or `--resume` (iteration 49
decision 3). `/next` always gets a number (decision 3 step 4), so it never asks on a tie.

**3. The loop.** The driver takes no argument (`-h` or `--help` prints the usage line; any other argument prints it on
stderr and exits 2). Run from inside any checkout of the project:

0. **Start checks** (decision 11; a failure is "cannot start"): the config, the lock (decision 4), the kill switch,
   `gh auth status`, `claude` on the `PATH`, then `git -C <main> fetch origin`, then the main checkout on
   `git.baseBranch` with `git -C <main> status --porcelain --untracked-files=all` printing nothing.
1. **Before every step** (also the first) check, in this order: the kill switch (decision 5), the time limit (decision
   6), the main checkout clean on `git.baseBranch` (as in 0). The first that holds ends the run with its reason.
2. **Read the board** (`gh project item-list`, as in the Facts). Keep the items whose `content.type` is `Issue` and
   that carry no `labels.epic` label. A *bug* carries `labels.bug`; a *story* does not. *R* is the Ready bugs, *A* the
   Approved stories, both without the items this run has already tried. A listing that returns 200 items prints
   `drive: the board listing returned 200 items, its limit; items past it may be missing` and the summary repeats it.
   When *R* and *A* are both empty the run ends: `nothing Ready or Approved` when the board has no Ready bug and no
   Approved story at all, else `nothing new to pick: every Ready bug and Approved story left was tried in this run`.
3. **When *R* is not empty**: the slot and room checks (decision 11), then the `/fix all` step. Every bug of *R* (as
   read in 2) counts as tried, whatever the step did. Then from 1 again, and read the board again before 4.
4. **When *A* is not empty**: take the story with the highest `board.priorityField` in the order of
   `board.priorities` (an item without a priority, or with one not in the list, ranks last). When two or more stories
   share that highest rank, the driver does not choose: the run ends with
   `a tie of priorities among the Approved stories #<a>, #<b> (<priority or no priority>); the maintainer sets one higher`.
   Otherwise the slot and room checks, then `/nightmill:next <N>`; *N* counts as tried.
5. A step whose `claude` exits non-zero ends the run with `claude exited <code> in <the step's prompt>`. Otherwise go
   to 1.

Each item is tried at most once per run, so the loop ends after at most as many steps as items became Ready or
Approved during the run, and the time limit ends it in any case. One round is at most one `/fix all` and one `/next`;
`/fix all` comes first because it asks nothing and frees its slots once its pull requests are open, and `/next` holds
its slot until its merge.

**4. One driver per repository.** The lock is the file `nightmill-drive.lock` in the git common directory, created
only when it does not exist (bash: `set -C` and a redirection; PowerShell: `[IO.File]::Open` with `CreateNew`), holding
the driver's process id and its start stamp on two lines. When it exists and its process is alive, the driver cannot
start: `another driver runs for this repository (pid <p>, since <stamp>)`. When its process has ended, the driver says
`drive: removed a stale lock of pid <p>` and takes it. The driver removes its lock on every exit it gets to run (also
after a signal, decision 8). The workflow template adds a concurrency group (decision 12). No config key: one driver
per repository is a rule, not a project value, and the parallel work inside a run is already bounded by
`worktrees.slots` and `parallel.maxAgents`.

**5. The kill switch.** The file `nightmill-stop` in the git common directory (for the main checkout:
`.git/nightmill-stop`). Only its existence counts; the driver never creates, reads or removes it. Set it with
`touch .git/nightmill-stop` (PowerShell: `New-Item .git/nightmill-stop`), clear it by deleting it. Checked at the
start and before every step (decision 3 step 1): set at the start, the run cannot start; set later, the run ends with
`the kill switch is set (.git/nightmill-stop)` after the step that was running has ended. It stops no step: to stop now,
stop the driver (decision 8). It is in the git directory so that it never makes the tree dirty (which would stop
`/fix all`), and it is per repository and per machine, so it reaches every way the driver is started there, also the
workflow on a self-hosted runner. #165's pause flag is the project-wide switch; this one is local (decision 1).

**6. The config keys.** A new object `unattended` in the schema, both keys optional:

| Key | Type | Default | Rule |
|---|---|---|---|
| `unattended.maxMinutes` | integer, 1 to 1440 | 240 | No step starts once this many minutes have passed since the driver started; the running step is not stopped. Reason: `the time limit of <m> minutes (unattended.maxMinutes) is reached` |
| `unattended.summaryIssue` | integer, at least 1 | none (absent) | The issue the summary is posted on as a comment; absent: the summary is printed only |

A value that is not a JSON number written as a whole number in range (`0`, `1441`, `2.5`, `"60"`, `true`) stops the
driver before anything else with `drive: unattended.<key> must be a whole number from <lo> to <hi>, got <the value as JSON>`
(for `summaryIssue`: `of at least 1`) on stderr and exit 2. The schema descriptions say what the rule says, and that
both are read by `scripts/drive.*` only. No `schedule` key: GitHub reads a `cron` only from the workflow file, so a key
would have to be rendered into a file under `.github/` (which is never auto-merged, iteration 48) and would be a second
source of the same value; the cron line lives in the project's copy of the template (decision 12). No `concurrency`
key (decision 4). The clock is read with `ledger_clock` of `scripts/lib/ledger.*`, so `NIGHTMILL_CLOCK_FILE` moves it
in the tests.

**7. The run's files.** `mktemp -d "${TMPDIR:-/tmp}/nightmill-drive.XXXXXX"` (PowerShell: a folder of the same
pattern under `[IO.Path]::GetTempPath()`), holding each step's `.json` and `.err` and the summary as `summary.md`. It is
kept, and its path is the driver's last stdout line, `drive: run files in <dir>`. It is never named in the comment,
which carries no local path (decision 10).

**8. No process left running.** The driver starts nothing in the background except the step it waits for: no `/loop`,
no controller, no dashboard. Each step runs as its own process group (bash: job control, `set -m`, so the group id is
the step's process id; PowerShell on Windows: the step's process tree by `ParentProcessId`, which Windows keeps after a
parent ends; PowerShell on macOS and Linux: the step started through `/bin/sh` with job control, which writes the
step's group id into the run folder). After every step, and on every exit, any process still in a step's group (on
Windows: in its tree) is sent TERM, and after 5 seconds KILL (Windows: `Stop-Process -Force` at once). On SIGINT or
SIGTERM (Ctrl+C, `kill <pid>`, a cancelled workflow run) the driver does the same to the running step at once, does
not start another, posts the summary with the reason `stopped by <SIGINT | SIGTERM>`, removes its lock and exits 130
or 143. A second signal does not interrupt that clean-up. PowerShell handles Ctrl+C with `try`/`finally` and, as
`slot.ps1` does, cannot set the signal's exit code; it exits 1 there. The summary's last line before the messages is
`Processes: none left running.`, or `Processes: <k> left behind by a step were ended; none left running.` A process
that is still alive after KILL is named (`Processes: <pid> could not be ended.`) and the exit code is 1. The 5 seconds
fit a cancelled workflow run's ten (Facts).

**9. No status is set or added.** The driver sets no status, adds no status, no field, no item and no label, edits
and closes no issue and merges nothing. Its only GitHub write is the one `gh issue comment` of decision 10. Its `gh`
calls are exactly: `gh auth status`, `gh project item-list`, `gh pr list` (decision 10), and `gh issue comment`; its
`git` calls are `rev-parse`, `fetch origin`, `symbolic-ref`, `status` and those of `scripts/lib/baseconfig.*`; it calls
`slot.* --reap`, `slot.* --status --porcelain` and `room.*`. The statuses a run leaves are those `/fix` and `/next` set
(In progress, Review; Done by the pull request's `Closes`/`Fixes`), as `### When a run is stopped` describes. A comment
changes no board status. Commenting on an issue that is not on the board adds no item; an issue already on the board
keeps its status.

**10. The summary.** At the end of every run that got past the config read (decision 11), the driver builds one
Markdown text, prints it on stdout, writes it to `summary.md` and, when `unattended.summaryIssue` is set and `gh` is
signed in, posts it once with `gh issue comment <summaryIssue> --repo <owner>/<repo> --body-file <run dir>/summary.md`.
Then it prints one of `drive: summary posted to #<n>`, `drive: summary not posted: unattended.summaryIssue is not set`,
or `drive: summary not posted: <the reason>` (gh not signed in, or the comment failed: its stderr on one line; this
makes the exit code 1 when it would be 0). The text, in this order:

1. `**nightmill driver run** <start> to <end> UTC (<duration>). Ended: <reason>.` Stamps are `YYYY-MM-DDTHH:MM:SSZ`
   (`ledger_stamp`), the duration is `ledger_duration`. For a run that cannot start, `Did not start: <reason>.` takes
   the place of `Ended:`, and items 2 to 5 are left out.
2. The table of the items a step was run for, in the order they were tried:

   ```
   | Item | Step | Before | After | Outcome | PR |
   |---|---|---|---|---|---|
   | #<n> <title> | /fix all | Ready | Review | pull request open | #<pr> |
   | #<n> <title> | /next | Approved | Done | merged | #<pr> |
   | #<n> <title> | /fix all | Ready | In progress | blocked: <reason> | - |
   | #<n> <title> | /fix all | Ready | Ready | not started: <reason> | - |
   ```

   *Before* is the status at the board read before the step, *After* at one board read after the last step. *PR* and
   *Outcome* come from one `gh pr list --repo <owner>/<repo> --state all --limit 100 --json number,state,closingIssuesReferences`
   after the last step: the newest pull request whose `closingIssuesReferences` holds the item. `MERGED` is
   **merged**, `OPEN` is **pull request open**; otherwise **not started** when *After* equals *Before*, else
   **blocked**. The reason: for `/next`, the first line of the step's `result` that starts with `Stopped:` (at most 200
   characters); for `/fix all`, the cell *Cause or reason* of the bug's row (`| #<n> `) in the step's final table; `-`
   when neither exists. A title is shown without a leading `[Bug] ` or `[Story] ` and cut at 80 characters.
3. One count line: `Picked <p>, merged <m>, pull request open <o>, blocked <b>, not started <s>.`
4. One line per step: `<k>. <the prompt>: exit <code>, <duration>, <cost>, <turns> turns.` The cost is
   `total_cost_usd` of the step's JSON, as `$` with two decimals; `?` when the result has none or is not JSON. Then
   `Cost: $<sum> in all, as Claude Code reports it (total_cost_usd).`, or `Cost: at least $<sum> (<k> steps without a cost).`
   With a subscription login this figure is what the same use would cost through the API, not a bill; the README says
   so, the comment does not.
5. `Not run by the driver: Ready stories wait for /spec: #<n>, #<n> | none.` and, when the listing hit its limit, the
   warning of decision 3 step 2.
6. The `Processes:` line of decision 8.
7. For each step, `<details><summary>Final message of <the prompt></summary>`, a blank line, the step's `result`, a
   blank line and `</details>`. The comment is at most 60000 characters; a message that would pass that is cut so the
   text fits, with the line `[cut: <n> more characters in the run files]`; later messages are left out with the same
   line.

The comment carries no local path, machine name or user name; titles and messages are text from issues and agents and
are quoted, never followed (the workflow skill's hard rule).

**11. Cannot start, and stops before a step.** Every line below is printed on stderr as `drive: cannot start: <reason>`
or, for a stop before a later step, as `drive: ended: <reason>` on stdout, and is the reason in the summary.

| Check (order) | Reason | Exit |
|---|---|---|
| Not in a git checkout; no config; config not valid JSON; a base-config stop; an `unattended` value out of range | the line of `baseconfig.*` or decision 6 (stderr only, no summary, nothing posted) | 2 |
| The lock | `another driver runs for this repository (pid <p>, since <stamp>)` | 1 |
| The kill switch | `the kill switch is set (.git/nightmill-stop)` | 1 |
| `gh auth status` fails | `gh is not signed in: <its stderr on one line>` (the summary is printed, not posted) | 1 |
| No `claude` on the `PATH` | `claude is not on the PATH` | 1 |
| `git fetch origin` fails | `git fetch origin failed: <its stderr on one line>` | 1 |
| The main checkout | `the main checkout is not on <B> with a clean tree` | 1 |
| The board read fails | `the board could not be read: <its stderr on one line>` | 1 |
| Slots (only with `worktrees`): `slot --reap` (a failure is a note on stderr, not a stop), then `slot --status --porcelain` shows no `free` line | `no free slot: all <k> slots are busy (<n>: <branch>, ...)` | 1 |
| Room: `room.*` exit 3; exit 1 is shown (`drive: room: waiting ...`) and the script is called again with its `--since` value; exit 2 is a note and the step starts | `no room on this machine: <its gave-up line>` | 1 |

The slot and room checks run before each step, after decision 3 step 1. **Exit codes:** 0 when the run ends for a
reason of decision 3 or 6 or at the kill switch after the start (also `nothing Ready or Approved` at the first board
read), and when a slot or room check stops it after at least one step ran (the board then shows what the run did);
1 when the run cannot start (every row of the table but the first, and a slot or room check before the first step),
when a step's `claude` exited non-zero, or when the summary could not be posted (decision 10); 2 for the first row
and a usage error; 130 or 143 after a signal (decision 8). The slot check comes
before `/next` because `/next` sets In progress before its take (Facts); before `/fix all` it saves a run that could
start nothing. Without `worktrees`, `/next` leaves the main checkout on its branch, so the check of decision 3 step 1
ends the run before the next step; the README says to use slots with the driver.

**12. The workflow template.** `templates/workflows/nightmill-drive.yml`, for a project to copy to
`.github/workflows/nightmill-drive.yml`. Its header comment says how to install it (the steps of decision 13) and that
it is a template, not this repository's workflow. Its content, exactly apart from the comments:

```yaml
name: nightmill driver
on:
  schedule:
    - cron: "17 2 * * *"
  workflow_dispatch:
permissions: {}
concurrency:
  group: nightmill-drive
  cancel-in-progress: false
jobs:
  drive:
    runs-on: [self-hosted, nightmill]
    timeout-minutes: 480
    steps:
      - name: Run the driver (macOS, Linux)
        if: runner.os != 'Windows'
        shell: bash
        env:
          NIGHTMILL_CHECKOUT: ${{ vars.NIGHTMILL_CHECKOUT }}
        run: |
          [ -n "$NIGHTMILL_CHECKOUT" ] || { echo "Set the repository variable NIGHTMILL_CHECKOUT to the path of the main checkout on this runner." >&2; exit 2; }
          root=$(claude plugin list --json | awk '/"id": "nightmill@nightmill"/ { f = 1 } f && /"installPath":/ { sub(/.*"installPath": *"/, ""); sub(/".*/, ""); print; exit }')
          [ -n "$root" ] || { echo "nightmill is not installed for the runner's user (claude plugin list)." >&2; exit 2; }
          cd "$NIGHTMILL_CHECKOUT"
          bash "$root/scripts/drive.sh"
      - name: Run the driver (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        env:
          NIGHTMILL_CHECKOUT: ${{ vars.NIGHTMILL_CHECKOUT }}
        run: |
          if (-not $env:NIGHTMILL_CHECKOUT) { Write-Error "Set the repository variable NIGHTMILL_CHECKOUT to the path of the main checkout on this runner."; exit 2 }
          $p = claude plugin list --json | ConvertFrom-Json | Where-Object { $_.id -eq 'nightmill@nightmill' } | Select-Object -First 1
          if (-not $p) { Write-Error "nightmill is not installed for the runner's user (claude plugin list)."; exit 2 }
          Set-Location $env:NIGHTMILL_CHECKOUT
          powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $p.installPath 'scripts/drive.ps1')
          exit $LASTEXITCODE
```

Why each part:

- **Schedule and on demand:** `schedule` (02:17 UTC daily, off the full hour; the project edits its copy) and
  `workflow_dispatch` (the Run workflow button, `gh workflow run nightmill-drive.yml`). A board item event is not a
  repository workflow trigger, so the driver polls the board when it runs (the agent notes).
- **A self-hosted runner, labelled `nightmill`, as the maintainer's user, in the main checkout.** A headless run needs
  the trusted workspace, `/init`'s `.claude/settings.local.json` (untracked, so never in a fresh clone), the installed
  plugin, the `gh` login and the slots (`### Before the first run`). They exist on the machine where `/init` ran, not
  on a GitHub-hosted runner. `NIGHTMILL_CHECKOUT` is a repository variable, not a config key, because it is one
  machine's path and the config on the base branch is shared by every machine.
- **`permissions: {}`:** the job uses no `GITHUB_TOKEN`. Pull requests opened with it would start no CI and so never
  auto-merge, and it cannot write a board owned by a user (Facts). Every `gh` and `git push` call uses the runner
  user's own `gh` login, whose scopes the README names (decision 13). The template references no secret and sets no
  `GH_TOKEN` or `GITHUB_TOKEN`.
- **`concurrency`** with `cancel-in-progress: false`: a scheduled run never cancels a running one; the lock (decision 4)
  also covers a driver started by hand.
- **`timeout-minutes: 480`**: above the default `unattended.maxMinutes` (240) plus one step started just before it.
- No `uses:` line, so no action to pin; `${{ }}` only in `env:` values, never inside `run:` (no expression is pasted
  into a script).

**13. The README.** A new `## Running on a schedule` directly after `## Running unattended` and before
`## Developing nightmill`, with exactly four sub-headings in this order: `### The driver`, `### Limits and the kill switch`,
`### The summary`, `### The workflow template`. What each holds, the wording the implementer's:

- `### The driver`: the commands `bash "<plugin>/scripts/drive.sh"` and
  `powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin>/scripts/drive.ps1"`, run in the main checkout,
  where `<plugin>` is `installPath` of `claude plugin list --json`; that it needs everything of
  `### Before the first run` and slots (`worktrees`); the loop of decision 3 in short (`/nightmill:fix all`, then
  `/nightmill:next <N>` with the highest-priority Approved story, a tie ends the run, each item at most once); that
  Ready stories are not run (`/spec`); the exit codes of decision 11; and one example line for a local scheduler
  (cron: `17 2 * * * cd <checkout> && bash <plugin>/scripts/drive.sh >> "$HOME/nightmill-drive.log" 2>&1`), with
  the note that `<plugin>` changes with each upgrade.
- `### Limits and the kill switch`: `unattended.maxMinutes` (default 240), checked between steps;
  `.git/nightmill-stop` and how to set and clear it; one driver per repository; that a running step is stopped only
  by stopping the driver (Ctrl+C, `kill <pid>`, cancelling the workflow run), which ends the step's processes and
  still posts the summary, with what a stopped step leaves linked to [When a run is stopped](#when-a-run-is-stopped);
  `parallel.fixAllMaxBugs` as `/fix all`'s own limit; and that limits per issue, per role and per cost and a pause
  flag are not there yet ([#165](...)).
- `### The summary`: `unattended.summaryIssue` (no default: printed only), the parts of decision 10, that the cost is
  `total_cost_usd` as Claude Code reports it (with a subscription login the API price of the same use, not a bill),
  and a suggestion to use one open issue kept for the purpose.
- `### The workflow template`: the copy command
  (`cp "<plugin>/templates/workflows/nightmill-drive.yml" .github/workflows/`), that the change goes through a pull
  request and is not auto-merged (a `.github/` change, iteration 48); the runner (self-hosted, installed as the user
  who ran `/init`, label `nightmill`, the repository variable `NIGHTMILL_CHECKOUT`); **the token scope**: the
  workflow's `GITHUB_TOKEN` gets no permission (`permissions: {}`) and is not used, and the runner user's `gh` login
  needs the scopes `repo`, `read:org` and `project` (`gh auth refresh -s project`), plus `workflow` for a story or bug
  whose change touches `.github/workflows/` (without it that push is refused); **the permission settings**: those of
  `### Before the first run`, unchanged, and `--permission-mode manual`, which the driver passes; the cron line and that
  GitHub may start a scheduled run late or, in a public repository without activity for 60 days, turn the schedule
  off; and **the warning** that a self-hosted runner on a public repository can be given work by a pull request from a
  fork, so a public repository either requires approval for every outside contributor's workflow runs, or uses a
  local scheduler (the cron line above) instead. It links [Security model](#security-model).

Changed sentences elsewhere in the README:

- `## Running unattended`, first paragraph: "Nothing in nightmill starts runs on a schedule yet ([#164](...)), and no
  limit or kill switch bounds a run yet ([#165](...))." becomes "To start runs on a schedule, see
  [Running on a schedule](#running-on-a-schedule) ([#164](...)); a driver run is bounded by its time limit and kill
  switch, but no limit bounds a single run yet ([#165](...))."
- `### When a run is stopped`: "There is no kill switch yet ([#165](...))." becomes "The driver's kill switch stops a
  driver between steps ([Limits and the kill switch](#limits-and-the-kill-switch)); a pause flag for every run comes
  with [#165](...)."
- Under the Security model's table: "no trigger that starts runs ships yet ([#164](...))" becomes "the driver and the
  workflow template that start runs are in [Running on a schedule](#running-on-a-schedule) ([#164](...))".
- `## What is in the plugin`: one row
  `| \`scripts/drive.ps1\`, \`scripts/drive.sh\` | Runs \`/nightmill:fix all\` and \`/nightmill:next <N>\` headless in a loop until nothing is Ready or Approved, the time limit is reached or the kill switch is set, then posts one summary. Sets no status. |`
  after the row of `scripts/control.*`, and one row `| \`templates/workflows/nightmill-drive.yml\` | A workflow for the project to copy: runs the driver on a schedule and on demand on a self-hosted runner. |`
  before the row of `schema/nightmill.schema.json`.
- The configuration table: one row after `worktrees`:
  `| \`unattended\` | For \`scripts/drive.*\`: the most minutes one driver run starts steps for (\`maxMinutes\`, default 240) and the issue its summary is posted on (\`summaryIssue\`, no default: printed only) |`.
- `## Developing nightmill`: `bash tests/smoke-drive.sh   # drive.sh against a fake claude, a fake gh and throwaway slots`
  after the line of `smoke-guard.sh`, and `powershell -ExecutionPolicy Bypass -File tests/smoke-drive.ps1` after the
  line of `smoke-guard.ps1`.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | A driver script (PowerShell and bash) runs the fix skill in batch mode and then the next skill headless, in a loop, until nothing is Ready or Approved, a limit is reached or the kill switch is set | Decisions 1, 2, 3, 5, 6; Tests, smoke cases `loop`, `nothing`, `tie`, `tried once`, `time limit`, `kill switch later` |
| 2 | A workflow template under `templates/` runs the same on a schedule and on demand, with the permission settings and the token scope the README names | Decisions 12, 13; Tests, `tests/test-drive-docs.sh` parts T and R |
| 3 | At the end the driver posts one summary (what was picked, merged, blocked, and what it cost) as a comment, and leaves no process running | Decisions 7, 8, 10; Tests, smoke cases `loop`, `no issue`, `comment fails`, `left behind`, `signal` |
| 4 | A run that cannot start (no slot, no room on the machine, a limit) says why and ends cleanly | Decisions 4, 5, 6, 11; Tests, smoke cases `no slot`, `no room`, `lock`, `kill switch`, `bad limit`, `dirty`, `gh` |
| 5 | No status is added and no status is set by the driver that a skill would not set | Decision 9; Tests, the gh log of every smoke case and `tests/test-drive-docs.sh` part S |

"A limit" in criterion 4 is, today, the one-driver lock and an unusable `unattended` value at the start, and the time
limit before a later step; #165's limits join decision 3 step 1 when they exist (decision 1).

## Tests

**`tests/smoke-drive.sh` and `tests/smoke-drive.ps1`** (same cases, same expected lines). Each builds a throwaway
project under `mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-drive.XXXXXX"` (removed by a trap): a bare repository as
`origin`, a clone as the main checkout with `origin/HEAD` set and a committed `.claude/nightmill.json` (owner `acme`,
repo `widgets`, project 1, `worktrees` with `root` `../wt` and `slots` 2, `parallel.roomCheck` false, `unattended`
with `summaryIssue` 9 and `maxMinutes` 60). On the `PATH` before everything else:

- a fake **`gh`** that appends each call's arguments to `$GH_LOG`; answers `project item-list` from the file
  `$BOARD` (a board JSON the case writes, rewritten by the fake `claude`), `pr list` from `$PRS`, `auth status` with
  exit 0 (exit 1 when `GH_AUTH_FAIL` is set), `issue comment` by copying the body file to `$COMMENT` (exit 1 when
  `GH_COMMENT_FAIL` is set); and fails on any other call with `fake gh: unexpected call`;
- a fake **`claude`** (on Windows a `claude.cmd` calling a `.ps1`) that appends its arguments to `$CLAUDE_LOG`, applies
  the case's next line of `$SCRIPT` (set an item's status in `$BOARD`, add a PR to `$PRS`, create the kill switch,
  advance `NIGHTMILL_CLOCK_FILE`, start a `sleep 300` in the background and write its pid, sleep, exit with a code),
  and prints one JSON object with `result` (two lines, the second `Stopped: ...` where the case says), `total_cost_usd`
  and `num_turns`.

The cases and what each asserts (exit code, the `drive: ...` lines, the claude log, the comment):

| Case | Setup | Expected |
|---|---|---|
| nothing | no Ready bug, no Approved story, one Ready story | exit 0; no claude call; comment `Ended: nothing Ready or Approved.` and `Ready stories wait for /spec: #<n>` |
| loop | bug #11 Ready; stories #21 Approved High, #22 Approved Low; `/fix all` moves #11 to Review with an open PR; each `/next N` moves N to Done with a merged PR; costs 0.50, 1.25, 1.25 | exit 0; claude calls in order `/nightmill:fix all`, `/nightmill:next 21`, `/nightmill:next 22`, each with `--permission-mode manual --output-format json` and nothing else; comment with three rows (`pull request open`, `merged`, `merged`), `Picked 3, merged 2, pull request open 1, blocked 0, not started 0.`, `Cost: $3.00 in all`, three `<details>` blocks, `Processes: none left running.`; `drive: summary posted to #9` |
| blocked | as loop, but `/next 21` leaves #21 at In progress and prints `Stopped: the check is red` | row of #21 `blocked: Stopped: the check is red`; #22 is still tried |
| tie | stories #21 and #23 Approved High | exit 0; no `/next` call; reason `a tie of priorities among the Approved stories #21, #23 (High); the maintainer sets one higher` |
| tried once | `/fix all` leaves #11 at Ready (not started) | `/fix all` runs once; reason `nothing new to pick: ...`; row `not started` |
| time limit | `maxMinutes` 1; the first step advances the clock by 61 s | one claude call; reason `the time limit of 1 minutes (unattended.maxMinutes) is reached`; exit 0 |
| kill switch | `.git/nightmill-stop` exists | exit 1; no claude call; stderr `drive: cannot start: the kill switch is set (.git/nightmill-stop)`; comment `Did not start: ...` |
| kill switch later | the first step creates it | one claude call; reason the kill switch; exit 0 |
| no slot | `slots` 1 and its slot taken with `slot --take` before the run | exit 1; no claude call; reason starts `no free slot: all 1 slots are busy (1: ` |
| no room | `parallel.roomCheck` true, run against a copy of `scripts/` whose `room.*` is a stub that exits 3 with a gave-up line (`room.*` measures with the system clock, so a real wait would take a minute) | exit 1; no claude call; reason starts `no room on this machine: ` |
| lock | a lock holding the smoke script's own live pid | exit 1; reason starts `another driver runs for this repository (pid ` |
| stale lock | a lock holding the pid of a process that has ended | `drive: removed a stale lock of pid <p>`; the run goes on |
| bad limit | `maxMinutes` 0, then `"60"`, then `summaryIssue` 0 | exit 2; the line of decision 6; no gh call at all; no comment |
| dirty | an untracked file in the main checkout | exit 1; reason `the main checkout is not on main with a clean tree` |
| gh | `GH_AUTH_FAIL` | exit 1; `drive: summary not posted: gh is not signed in` ; no `issue comment` call |
| claude fails | the first step exits 3 | exit 1; reason `claude exited 3 in /nightmill:fix all` |
| no issue | `summaryIssue` absent | the summary on stdout; `drive: summary not posted: unattended.summaryIssue is not set`; no `issue comment` call |
| comment fails | `GH_COMMENT_FAIL` | exit 1; `drive: summary not posted: ` with the fake's stderr |
| left behind | the step starts `sleep 300` in the background and exits 0 | that pid is not alive after the driver exits; `Processes: 1 left behind by a step were ended; none left running.` |
| signal | (bash only, as `smoke-slot.sh`'s interruption cases) TERM to the driver while the step sleeps | exit 143; the step's process gone; comment `Ended: stopped by SIGTERM.`; no lock left |
| long | a step whose `result` is 70000 characters | the comment is at most 60000 characters and holds `[cut: ` |

In every case, every line of `$GH_LOG` starts with one of `auth status`, `project item-list`, `pr list`,
`issue comment` (criterion 5); the slot calls go through the real `scripts/slot.*`; no lock file is left after the run.
`tests/smoke-drive.sh` is `add bash smoke-drive.sh` after `add bash test-guard-rules.sh` (the last bash step) and
`tests/smoke-drive.ps1` is `add ps smoke-drive.ps1` after `add ps smoke-guard.ps1` (the last step) in `tests/check.sh`,
and both go at the end of the matching `--only` list of `ci.yml`, so the lists stay in the step list's order. Each smoke test runs in under 60 seconds (the case `no room` uses the stub, not a real
wait).

**`tests/test-drive-docs.sh [<root>]`** (default: this checkout), `set -euo pipefail`, bash and awk only, called from
a new lint section directly after `== running unattended is documented`:

```
echo "== the driver is wired"
# Iteration 52 (#164): the driver's flags, that it sets no status, the workflow template and the README section.
bash tests/test-drive-docs.sh "$PWD" || fail=1
```

Each miss is one `FAIL: <file>: <what>` on stderr; the script exits 1 after all checks.

- **Part S (the driver, criterion 5 and decision 2).** `scripts/drive.sh` and `scripts/drive.ps1` exist; each contains
  `/nightmill:fix all`, `/nightmill:next`, `--permission-mode manual`, `--output-format json`, `issue comment`,
  `nightmill-stop` and `nightmill-drive.lock`; neither contains `item-edit`, `item-add`, `item-delete`, `field-create`,
  `updateProjectV2ItemFieldValue`, `single-select-option-id`, `issue edit`, `issue close`, `pr merge`, `label create`,
  `--bare`, `--dangerously-skip-permissions`, `bypassPermissions`, `--allowedTools`, `--continue` or `--resume`.
  `scripts/drive.sh` is `100755` in the index (already enforced for every `scripts/*.sh` by
  `tests/test-script-modes.sh`). The schema's `board.statuses` still has exactly the eight keys `backlog`, `ready`,
  `spec`, `specReview`, `approved`, `inProgress`, `review`, `done`.
- **Part K (the keys).** The schema has `unattended.maxMinutes` as an integer with `minimum` 1, `maximum` 1440 and
  `default` 240, and `unattended.summaryIssue` as an integer with `minimum` 1 and no `default`; the example config has
  `"unattended"` with `maxMinutes` 240; the README's configuration table has a row starting `` | `unattended` | `` that
  holds `maxMinutes`, `default 240` and `summaryIssue`.
- **Part T (the template, criterion 2).** `templates/workflows/nightmill-drive.yml` exists and has, as whole lines:
  `on:`, `  schedule:`, a line matching `^    - cron: "[0-9*/ ,-]+"$`, `  workflow_dispatch:`, `permissions: {}`,
  `concurrency:`, `  group: nightmill-drive`, `  cancel-in-progress: false`, `    runs-on: [self-hosted, nightmill]`,
  a line `    timeout-minutes: <n>` with `<n>` from 1 to 4320, `          bash "$root/scripts/drive.sh"`; it contains
  `scripts/drive.ps1` and `NIGHTMILL_CHECKOUT: ${{ vars.NIGHTMILL_CHECKOUT }}`; it has no line matching
  `uses:`, no `secrets.`, no `GITHUB_TOKEN`, no `GH_TOKEN`, no `: write`, none of the forbidden flags of part S; and
  every line containing `${{` matches `^ *NIGHTMILL_CHECKOUT: \$\{\{ vars\.NIGHTMILL_CHECKOUT \}\}$`.
- **Part R (the README, criteria 2 and 3).** `README.md` has exactly one line `## Running on a schedule`, after
  `## Running unattended` and before `## Developing nightmill`; its section has the four sub-headings of decision 13,
  once each, in order, and no other `### `; it contains `scripts/drive.sh`, `scripts/drive.ps1`,
  `templates/workflows/nightmill-drive.yml`, `.git/nightmill-stop`, `` `unattended.maxMinutes` (default <d>) `` with
  `<d>` the schema default, `unattended.summaryIssue`, `total_cost_usd`, `permissions: {}`, `GITHUB_TOKEN`, `repo`,
  `read:org`, `project`, `workflow`, `self-hosted`, `NIGHTMILL_CHECKOUT`, `--permission-mode manual`,
  `(#before-the-first-run)`, `(#when-a-run-is-stopped)`, `(#security-model)` and a link to #165 in the form of
  iteration 39; the `## What is in the plugin` table has a row starting `` | `scripts/drive.ps1`, `scripts/drive.sh` | ``.
  The Security model section no longer contains `no trigger that starts runs ships yet`, and `## Running unattended`
  no longer contains `Nothing in nightmill starts runs on a schedule yet`.

The existing pins keep passing: `tests/test-unattended-docs.sh` (the five sub-headings of `## Running unattended` are
unchanged; its section still links #164 and #165, and `### When a run is stopped` still links #165),
`tests/test-security-model.sh` (pin 12 still links #160, #164 and #213 outside the table; the table is not changed),
iteration 51's `tests/test-lint-agreement.sh` (both smoke files listed, twins present), `== the check runs every smoke
script`, `== CI runs with least privilege` (only `ci.yml`'s `--only` lists change), `== temporary files have a
template`, `== bash files do not use jq`, `== config validates` (the example against the schema) and the forbidden-words
lint over every new file.

**Verification of the pins:** in a scratch copy of the repository, break each once and see its `FAIL:` line, then
restore: add `gh project item-edit` to a comment of `drive.sh`, drop `--output-format json` from `drive.ps1`, change
`permissions: {}` to `contents: write`, add `uses: actions/checkout@v4`, put `${{ github.event.inputs.x }}` in a `run:`
line, drop `### The summary`, change the schema default of `maxMinutes`. "How verified" lists each.

**The probe** (by the implementer, recorded in "How verified"; it starts no skill and changes no board):

1. `claude -p "/nightmill:status" --permission-mode manual --output-format json` once in this repository: the object
   has `result`, `total_cost_usd` and `num_turns`. A field under another name changes decision 10 and the smoke
   fake to that name.
2. `bash scripts/drive.sh` and `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/drive.ps1` in a checkout
   of this repository with `.git/nightmill-stop` created first: each prints
   `drive: cannot start: the kill switch is set (.git/nightmill-stop)`, the summary on stdout and
   `drive: summary not posted: unattended.summaryIssue is not set` (this repository sets no `unattended`), exits 1, and
   leaves no lock. This runs the real `gh auth status`, `git fetch` and base-config read and posts nothing.

**What only a real run shows:** that a scheduled workflow run on a self-hosted runner reaches `/fix all` without a
denial, and what a cancelled run posts. They are stated as GitHub and iteration 49 describe them (Left). No manual
check applies (Story trigger and manual check).

## Files touched

- `scripts/drive.sh` (new, `100755`) and `scripts/drive.ps1` (new): decisions 2 to 11, with a header comment as
  `scripts/room.sh` has (usage, what it reads and calls, exit codes, the spec's path).
- `templates/workflows/nightmill-drive.yml` (new): decision 12.
- `schema/nightmill.schema.json`: the object `unattended` with the two keys of decision 6.
- `templates/nightmill.example.json`: `"unattended": { "maxMinutes": 240 }` after `worktrees` (`summaryIssue` is left
  out, as it has no default; the README says so).
- `README.md`: decision 13.
- `tests/smoke-drive.sh`, `tests/smoke-drive.ps1` (new) and `tests/fixtures/drive/` (the board and PR JSON files the
  cases start from).
- `tests/test-drive-docs.sh` (new): parts S, K, T and R.
- `tests/lint.sh`: the section `== the driver is wired`, nothing else.
- `tests/check.sh`: the two `add` lines.
- `.github/workflows/ci.yml`: `smoke-drive.sh` at the end of the bash `--only` list (after `test-guard-rules.sh`) and
  `smoke-drive.ps1` at the end of the PowerShell list (after `smoke-guard.ps1`), matching the step list. Nothing else.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 52 (#164): a driver, scripts/drive.sh and drive.ps1, runs
  /nightmill:fix all and /nightmill:next <N> headless in a loop until no Ready bug or Approved story is left, its time
  limit (unattended.maxMinutes, default 240) is reached or its kill switch (.git/nightmill-stop) is set; it checks for a
  free slot and room before each step, sets no status, ends every process it started and posts one summary (picked,
  merged, blocked, cost) on unattended.summaryIssue. templates/workflows/nightmill-drive.yml runs it on a schedule and on
  demand on a self-hosted runner. New config keys: unattended.maxMinutes, unattended.summaryIssue.` (paths, commands and
  keys in backticks).

Not touched: `skills/`, `agents/`, `hooks/`, every other script in `scripts/` (the slot scripts above all),
`scripts/lib/`, `tests/test-unattended-docs.sh`, `tests/test-security-model.sh`, this repository's `.claude/` files and
`.github/workflows/` apart from the `--only` lists, `SECURITY.md`, `CONTRIBUTING.md`.

## Risks

- **The pull request is not auto-merged.** It changes `.github/workflows/ci.yml` (the `--only` lists, which the lint
  ties to the step list), and iteration 48 holds back auto-merge for a `.github/` change. The maintainer merges it.
- **A self-hosted runner on a public repository.** A fork's pull request can change a workflow to run on it. The
  template triggers only on `schedule` and `workflow_dispatch`, but that does not protect the runner from other
  workflows. The README warns and names the two ways out (decision 13); the template cannot enforce either.
- **A cancelled workflow run may not post.** GitHub gives a cancelled step about ten seconds. The driver's clean-up is
  5 seconds plus one `gh` call; on a slow network the summary may be lost. The kill switch is the clean stop.
- **The driver picks for `/next`.** It repeats the picking rule of the workflow skill (status, not epic, not bug,
  priority order) in a script. A later change of that rule must change the driver too; part S does not catch a drift.
  The tie rule is stricter than `/fix all`'s order (which breaks ties by number) on purpose, because the workflow skill
  asks the maintainer on a tie of stories.
- **An interactive session beside the driver** can take the same item before the driver's `/next` sets In progress,
  until #176. The README's `### Several runs at once` already says to run at most one `/next` without a number.
- **A step that runs long.** The time limit is checked between steps, so a driver run can last `maxMinutes` plus one
  step (a `/next` includes up to `review.watchChecksMinutes` per push). #165's minutes per issue bound a step.
- **The cost figure** is Claude Code's own and is an estimate under a subscription login; the summary says where it
  comes from.
- **`claude plugin list --json`** is relied on for the install path in the template; a change of its form breaks the
  template's first step with its own message, not silently.
- **Size.** This is the largest iteration of the epic so far; the slot scripts are not touched, which keeps it clear of
  the hot files.

## Size estimate

`L`: about 330 lines in `scripts/drive.sh`, 330 in `scripts/drive.ps1`, 260 in `tests/smoke-drive.sh`, 260 in
`tests/smoke-drive.ps1`, 60 of fixtures, 130 in `tests/test-drive-docs.sh`, 45 in the template, 95 in `README.md`, 4
in the schema, 1 in the example config, 4 in `tests/lint.sh`, 2 in `tests/check.sh`, 2 in `ci.yml`, 8 in
`CHANGELOG.md`: about 1530 changed lines in fourteen files.

## Not done

- No `/spec` step: Ready stories are listed in the summary, not specified (decision 2).
- No limits per issue, per role or per cost, no `--max-turns` or `--max-budget-usd`, no pause flag in the config or as a
  label, no run ledger and no `blocked` label (#165, decision 1). The kill switch is local and read by the driver only.
- No schedule or concurrency config key, and no rendering of the template by `/init` or `render-templates` (decisions
  6 and 12). `/init` does not change and installs nothing new.
- No trigger on a GitHub event (an issue assigned or labelled, a comment, a board item event), no label mirror, and no
  tracking comment during the run: one summary at the end only.
- No GitHub-hosted runner recipe, no container and no sandbox (#169).
- No tie-break for stories of the same priority (Left).
- No change to `/fix`, `/next` or any skill, so the order "In progress, then take" of `/next` stays; the driver's slot
  check only makes it unlikely in a driver run.
- No loading of the load controller in a driver run; `/loop /nightmill:control` stays interactive.
- No claim protocol (#176).
- This repository does not install the workflow in its own `.github/workflows/`.

## Left

- **"Until nothing is Ready or Approved"** is read as no Ready bug and no Approved story (decision 2): with Ready
  stories on the board and `/spec` not run, a literal reading would never end the loop. If the maintainer wants the
  driver to run `/spec` for Ready stories too, that is a change to decisions 2 and 3 (one more step per round), not
  made here because the criteria name only the fix and the next skill.
- **A tie of story priorities ends the run** (decision 3 step 4), following the workflow skill's "On a tie ask the
  maintainer". If the maintainer prefers `/fix all`'s order for stories as well (then the lowest issue number), that is
  a rule change in the driver and a sentence in the workflow skill, for the maintainer to decide.
- **Self-hosted only.** The template targets a runner on the machine where `/init` ran, because a headless run needs
  that machine's untracked settings, trust and login (decision 12). A GitHub-hosted recipe would need `/init`'s
  personal rules generated without the chat and a Claude Code login in a secret; whether that is wanted is a question
  for #165 or a later story.
- **Not verified by a run:** a scheduled run on a self-hosted runner from start to summary; whether `claude -p`
  started from the runner's service sees the same login and keychain as an interactive terminal (on macOS a runner
  installed as a launch agent of the user, not as a system service, is assumed); what a cancelled run posts. The probe
  settles the JSON fields and the start checks; the maintainer's first scheduled run shows the rest, and its result may
  change a README sentence in a later pull request.
