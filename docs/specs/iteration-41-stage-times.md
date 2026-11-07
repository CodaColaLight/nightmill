# Iteration 41: the time a story spends in each stage is recorded and shown

Status: draft, awaiting approval (#199)

Story: #199, epic #47 (Unattended runs). The slot scripts that already run append one line per event (a take, every
report, every freeing) to a record file beside the slot markers, `<worktrees.root>/.slots/ledger.tsv`. A new
read-only command, `scripts/stages.sh` / `scripts/stages.ps1`, prints from that file the time per stage of one issue or
of the last N takes, with each stage's share of the total. The wait for CI and the merge is its own stage
(`ci-and-merge`), taken from the pull request's open and merge times, which the freeing already asks `gh` for. A stretch
that has no report shows as `not-reported`, and a duration that cannot be known shows as `unknown`, never as `0s`.
`tests/check.sh` prints the time of each of its steps and the total. Changes `scripts/slot.sh`, `scripts/slot.ps1`,
`scripts/lib/ledger.sh` (new), `scripts/lib/ledger.ps1` (new), `scripts/stages.sh` (new), `scripts/stages.ps1` (new),
`scripts/lib/stages.awk` (new, optional, see Files touched), `tests/check.sh`, `tests/smoke-slot.sh`,
`tests/smoke-slot.ps1`, `tests/smoke-stages.sh` (new), `tests/smoke-stages.ps1` (new), `tests/fixtures/stages/` (new),
`tests/lint.sh`, `.github/workflows/ci.yml`, `README.md` and `CHANGELOG.md`. No skill, no agent, no hook, no schema, no
config, no status script.

## Story trigger and manual check

**Not a story trigger.** None of `escalation.storyTriggers` applies:

- *A change to the status flow or who sets a status*: no. The record is not a board status, and nothing reads or sets
  one.
- *A new, renamed or removed config key*: no. The record's path comes from the existing `worktrees.root`, and no
  threshold or flag is added. The schema, `templates/nightmill.example.json` and the README's configuration table do
  not change.
- *A change to the slot marker format*: no. `slot-N.json` keeps exactly the keys and text it has today: the finished
  marker (`slot`, `branch`, `since`), the marker after a report (the same plus `skill`, `role`, `step`, `reported`) and
  the claim (iteration 34: plus `state`, `pid`). The record is a new file in `.slots` whose name does not match
  `slot-*.json`, so the previous version's `last_slot` / `Get-LastSlot`, take, reap and status never see it (Facts). The
  agent notes' advice "a new file is safer than a new field" is followed.

No path in `verification.manualCheckPaths` (`skills`, `agents`, `hooks`) changes, so **the manual check of the
configuration does not apply**. The story's own Verification asks the maintainer for one end-to-end look on a real
slot; its steps are under Tests. Every script that changes exists in both shells and gets smoke steps in both
(`tests/smoke-slot.*`, `tests/smoke-stages.*`). `tests/check.sh` has no PowerShell logic of its own: `tests/check.ps1`
runs it through bash (Facts), so the check's times are printed in both shells by the same code, and the PowerShell
smoke test checks them through `tests/check.ps1`.

**Order.** `scripts/slot.sh` and `scripts/slot.ps1` are in `parallel.hotFiles`, and `parallel.doNotPair` forbids two
tasks that both change the slot scripts. This iteration is never implemented at the same time as #189 (iteration 35,
marker retries), #190 (iteration 36, interrupted take) or #193 (a slot whose agent is alive is not shown as stalled).
Whichever is Approved first is merged first; the next rebases on it. The rules below do not depend on the order: the
record is appended after the marker changes those specs touch and never replaces one of them. **Note for #193:** if
its refresh calls `--report` with the same step every interval, each call appends a step line and the table's `runs`
column counts each refresh (decision 8); #193's spec should refresh without `--report`, or say that the table counts a
repeated step of the same take once. This spec does not decide that for #193.

## Facts this rests on

Read on `main` at d299241 (iteration 38 merged; iterations 35, 36, 37, 39 and 40 have specs, not yet code).

- **The marker** is `<worktrees.root>/.slots/slot-N.json` (`marker()` in `slot.sh`, `Get-Marker` in `slot.ps1`). A
  report (`--report <step> --slot N --skill <s> --role <r>`, iteration 23) rewrites it through a temporary file
  `slot-N.report.tmp` and moves it over the marker only while the marker exists ("a report never brings back a released
  slot"; bash `mv -f`, PowerShell `[System.IO.File]::Replace`). The `reported` stamp is the **local** time without a
  zone (`date +%Y-%m-%dT%H:%M:%S`, `(Get-Date).ToString('s')`); so are `since` and the claim's `since`. Every reader
  reads the marker by key (`json_get`, `ConvertFrom-Json`). `--release N` and `--abandon N` and the automatic release
  (`reap_all` / `Invoke-Reap`) delete the marker; release and reap also delete the local branch (`git branch -D`).
  Nothing in `.slots` keeps a trace of a freed slot today.
- **Other files in `.slots`:** `capacity.json` (iteration 22), `slot-N.warmup-<i>` stamps, and the temporary files
  `slot-N.report.tmp`, `slot-N.take.tmp`, `slot-N.claim.<pid>.tmp`, `slot-N.left.<pid>.tmp`. `last_slot` /
  `Get-LastSlot` look only at `slot-*.json`. `scripts/status.*`, `scripts/dashboard.*`, `scripts/panel.*`,
  `hooks/panel.tsx`, `scripts/load.*`, `scripts/control.*` read the slots only through `slot.* --status --porcelain`.
  So a new file `ledger.tsv` in `.slots` is invisible to the previous version.
- **The gh calls of the freeing.** `reap_all` / `Invoke-Reap` run `gh pr list --state merged --head <branch> --json
  number,headRefOid` and free a slot for the first merged PR whose `headRefOid` is the tip of the local branch.
  `--release` runs `gh pr list --state merged --head <branch> --json number -q '.[0].number'` and refuses with
  `no merged PR for <branch>. Merge it first, or free the slot with --abandon N.` (`-Abandon N` in PowerShell) when it
  prints nothing. `--abandon` calls no `gh`.
- **gh can give the times and the issue.** `gh pr list --json` (gh 2.103.3, checked) lists `createdAt`, `mergedAt` and
  `closingIssuesReferences` among its fields. Checked on this repository: `gh pr list --state merged --limit 3 --json
  number,createdAt,mergedAt,closingIssuesReferences,headRefName` gives for PR #201 `"createdAt":"2026-11-07T20:48:23Z"`,
  `"mergedAt":"2026-11-07T21:00:02Z"` and `closingIssuesReferences` `[{"number":154, ...}]` (a merged PR keeps its
  closing reference), and for the spec PRs #198 and #197 an empty list (their bodies say `Spec for #<issue>.`, no
  closing keyword). The times are UTC with a `Z`.
- **The branch does not carry the issue for a story.** `/next` takes `<git.featurePrefix><slug>` (no number); `/fix`
  takes `<git.fixPrefix><number>-<slug>`. The PR of `/next` has `Closes #<issue>`, the PR of `/fix` `Fixes #N`
  (`skills/next/SKILL.md` step 6, `skills/fix/SKILL.md` step 6), so `closingIssuesReferences` of the merged PR names the
  issue in both.
- **The step names** are the report tables of `/next` and `/fix` ("Reporting the steps"): `slot-taken`, `write-tests`,
  `implement` / `fix`, `tests` / `test`, `code`, `check`, `commit`, `code-review`, `dispute-<k>`, `test-finding-<k>`,
  `fix-round-<k>`, `manual-check`, `changelog` (`/next` only), `pull-request`, `done`, `stopped`. The session reports
  `pull-request` before it opens the PR (step 6) and `done` after step 7 (enabling auto-merge); it does not wait for CI.
  So the time from the PR's `createdAt` to its `mergedAt` is the wait for CI and the merge.
- **`/spec` takes no slot and has no report table.** `skills/spec/SKILL.md` step 1 creates `<git.specPrefix><N>-<slug>`
  with `git switch -c` in the checkout; the README says "`/spec` takes no slot and is not shown". So no script that runs
  today sees a spec's steps (see Decisions 11 and Left).
- **The check.** `tests/check.sh` runs every step through `run <name> <command...>`, which prints `== <name>`, then
  `-- <name>: ok` or `-- <name>: FAILED`, and collects the failures; at the end it prints `SKIPPED: <what>` lines,
  then `CHECK FAILED: <names>` (exit 1) or `ALL CHECKS PASSED`. It measures no time. `tests/check.ps1` only runs
  `tests/check.sh` with Git's bash and returns its exit code. No script, skill or workflow reads the `-- <name>: ok`
  lines (searched: only `tests/check.sh` itself has them); CI runs each smoke file as its own step in
  `.github/workflows/ci.yml` (jobs `smoke-bash`, `smoke-powershell`), not through `tests/check.sh`.
- **Fixture clocks today.** `NIGHTMILL_NOW` (seconds since 1970, the local time read as UTC) fixes "now" for
  `slot.* --status --porcelain` (`slot.sh` line 423, `slot.ps1` line 470), `scripts/control.*`, `scripts/dashboard.*`
  and `scripts/panel.*`. It is one fixed value per process; no script reads a clock that a test can move during one run,
  and no script takes its written stamps (`since`, `reported`) from a fixture. `NIGHTMILL_CLAIM_GATE` (iteration 34) is
  a test-only variable of the same kind. `tests/smoke-slot.sh` puts a fake `gh` first on the PATH that answers
  `pr list` from `$GH_FIX/merged.txt` (rows of branch, number, head commit) and handles `-q` for the release's query;
  `tests/smoke-slot.ps1` has its twin.
- **Arithmetic for stamps** exists in both shells: `epoch_of` (`slot.sh`) and `Get-Stamp` (`slot.ps1`) turn
  `YYYY-MM-DDTHH:MM:SS` into seconds since 1970 read as UTC, the arithmetic of `stamp` in `scripts/lib/status.awk`.
- **Retries on Windows.** Iteration 35's spec (#189, not yet implemented) tries a marker change up to 21 times, 0.25 s
  apart, because a reader that holds a file open on Windows makes a write fail for a moment.
- **#165 (limits and run ledger)** has no spec (`docs/specs` has none; `gh pr list --state all --search 165` lists no
  PR for it). Its criterion: "Cost, duration and turns of each run are read from the headless result and appended to a
  ledger, one line per run, in an untracked folder". **#166 (history and metrics)** computes "from the run ledger (see
  the limits story)" cycle time per status, fix rounds, cost per issue and slot utilisation.
- **The numbers of the context** (pull requests merging in 4 to 8 minutes early, 46 to 114 minutes recently) are not
  needed by any rule here; this story only measures.

## Decisions

**1. One record file, shared with the later run ledger: `<worktrees.root>/.slots/ledger.tsv`.** It lives beside the
slot markers and `capacity.json`, outside the repository with the default root (`../<repo>-wt`) and never committed,
shared by every worktree of the project, so it survives a release, an abandon, a reap and the deletion of the branch.
It is append-only: no script rewrites, truncates or deletes it (the maintainer may delete it; the next line creates
it again). **#165's run lines go into the same file**, as lines of their own kind (`run`) under the rule of decision 2;
readers skip a kind they do not know. So there is one ledger: this iteration writes its first three kinds, #165 adds
one, #166 reads all of them. That is the answer to the agent notes' "say which file the lines go to if the two meet";
#165's spec settles its own fields after field 2.

**2. The line format.** UTF-8 without a byte order mark, LF, one event per line, exactly 11 fields separated by a tab
(10 tabs), no field quoted, an absent value an empty field:

| # | Field | `take` | `step` | `free` |
|---|---|---|---|---|
| 1 | kind | `take` | `step` | `free` |
| 2 | stamp: when the line was written, UTC `YYYY-MM-DDTHH:MM:SSZ` | the take's finish | the report | the freeing |
| 3 | slot | N | N | N |
| 4 | branch | the take's branch | the marker's `branch` | the marker's `branch` |
| 5 | name | `take` | the step | `released`, `reaped` or `abandoned` |
| 6 | skill | empty | `--skill` | empty |
| 7 | role | empty | `--role` | empty |
| 8 | pr | empty | empty | the merged PR's number (released, reaped); else empty |
| 9 | from | the claim's time (UTC stamp) | empty | the PR's `createdAt`, as gh gives it; else empty |
| 10 | to | the take's finish (UTC stamp, the same as field 2) | empty | the PR's `mergedAt`; else empty |
| 11 | issues | empty | empty | the numbers of the PR's `closingIssuesReferences`, in gh's order, joined by `,`; else empty |

No field can hold a tab or a newline: steps, skills and roles are checked by the report (`[A-Za-z0-9][A-Za-z0-9-]{0,39}`),
git refuses control characters in branch names, and the rest are numbers and stamps. The first two fields are the
same for every kind, present and future (decision 1). Example lines (tabs shown as `→`):

```
take→2026-11-07T08:00:40Z→1→feat/stage-times→take→→→→2026-11-07T08:00:00Z→2026-11-07T08:00:40Z→
step→2026-11-07T08:00:45Z→1→feat/stage-times→slot-taken→next→session→→→→
free→2026-11-07T10:30:00Z→1→feat/stage-times→released→→→207→2026-11-07T09:20:30Z→2026-11-07T09:40:00Z→199
```

**3. Who writes which line, and when.** Only `scripts/slot.sh` and `scripts/slot.ps1`, in the commands that already
run; no skill, agent or extra call writes the record.

- **Take:** the take reads the record clock (decision 4) when it claims the slot (where `claim_since` / `$script:claimSince`
  is set today) and again in `finish_take` / `Complete-Take`, after the finished marker has replaced the claim, and then
  appends the `take` line. A take that fails (any `restore_take` / `Undo-Take`, a failed marker write) appends nothing.
- **Report:** `--report` appends its `step` line after its marker move succeeded. A report refused for any reason
  (no slot number, slot not in use, a claim, a bad name, an invalid marker) and a report whose marker vanished before
  the move (`rm -f "$tmpr"` / `Remove-Item $tmpReport` today) append nothing.
- **Free:** `--release` (name `released`), each slot the reap frees (`reaped`) and `--abandon` of a finished take
  (`abandoned`) append their `free` line after the marker is deleted, and before the `Slot N is free ...` line is
  printed. `--abandon` of a dead claim (iteration 34: a take that did not finish) appends nothing, because that take
  wrote no line.
- **The gh query of the freeing** asks for three more fields, so the times and the issue come without another call:
  the reap `--json number,headRefOid,createdAt,mergedAt,closingIssuesReferences` (the PR it frees for is chosen as
  today, by `headRefOid`); the release `--json number,createdAt,mergedAt,closingIssuesReferences`, and it takes the
  first element, the same PR whose number `-q '.[0].number'` printed. The release's refusal, its exit codes and both
  commands' printed lines stay exactly as they are; a missing field gives an empty field in the line. `--abandon` calls
  no `gh` and writes `pr`, `from`, `to` and `issues` empty.

**4. The record clock, and the fixture clock for the tests.** Every new reading of the time (the record's stamps, the
check's step times, "now" in the table) is seconds since 1970 in UTC: the file named by the test-only variable
`NIGHTMILL_CLOCK_FILE` when it is set (its first line, which must match `^[0-9]{1,12}$`; read again at every reading,
so a test moves the clock by writing the file), else the system clock (`date +%s` in bash,
`[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()` in PowerShell). A set but unusable `NIGHTMILL_CLOCK_FILE` (missing,
unreadable, another first line) gives one line on standard error, `ledger: NIGHTMILL_CLOCK_FILE is not usable; using
the system clock`, and the system clock. Seconds become the stamp `YYYY-MM-DDTHH:MM:SSZ` by arithmetic in bash (the
inverse of `epoch_of`; no `date -d` or `date -r`, which differ between GNU and BSD) and by
`[DateTimeOffset]::FromUnixTimeSeconds(<s>).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss", InvariantCulture) + "Z"` in
PowerShell. UTC because gh's `createdAt` and `mergedAt` are UTC: local stamps would put the CI wait off by the zone's
offset and break across a daylight saving change. The marker's `since` and `reported` stay local (no format change);
`NIGHTMILL_NOW` keeps its meaning and its readers. The helpers live in `scripts/lib/ledger.sh` (sourced by `slot.sh`,
`stages.sh` and `tests/check.sh`) and `scripts/lib/ledger.ps1` (dot-sourced by `slot.ps1` and `stages.ps1`): the clock,
the stamp, the duration text (decision 9) and the append (decision 5).

**5. The append never changes what a command does.** One line is appended in one write: bash `printf '...\n' ... >>
"$state/ledger.tsv"`; PowerShell `[System.IO.File]::AppendAllText(<path>, <line> + "`n", <UTF-8 without BOM>)`. A failed
write is tried again up to 21 tries in all, 0.25 s apart (the numbers of iteration 35), because on Windows another
appender or a reader can hold the file for a moment. After the last failed try one line goes to standard error:
`slot: the record was not written (<first line of the error>)`. The command's exit code, its other output and its
marker change are those it has without the record: a report still exits 0, a take still prints its hints, a release
still frees the slot. A failed record line is never a reason to stop.

**6. Stages: which lines form one take.** The table reads the file top to bottom, keeps only lines of the kinds
`take`, `step`, `free` with exactly 11 fields, field 2 a stamp of the form above and field 3 a whole number; it skips a
line of another kind silently and a malformed line of these kinds with one note at the end, on standard error:
`stages: skipped <k> malformed lines of <path>`. Per slot number:

- A `take` line starts a new take of that slot. If the slot already has a take without a `free` line, that earlier take
  ends at its last line and its state is `not freed`.
- A `step` line belongs to the slot's current take; when the slot has none (a take by the previous version, which wrote
  no `take` line), it starts a take whose start is **unknown**.
- A `free` line ends the slot's current take; when the slot has none (taken and worked on by the previous version, freed
  by this one), it is a take of its own with an unknown start and no steps.
- A take without a `free` line at the end of the file is `running`.

**7. Stages: how the time of a take is split.** Times are whole seconds; a negative difference counts as 0.

- **Start** S: field 9 of the `take` line (the claim). Unknown without a `take` line.
- **Cut** C, where the agent's time ends: for a `free` line with `from` and `to` both set (a merged PR), C = `from`
  (the PR opened), except that when `from` is earlier than the take's first known time (S, else its first line) C is the
  stamp of the take's last `step` line before `to` (a take of a branch whose PR was already open). For any other `free`
  line, C = its stamp. For a running or not-freed take, C = now (decision 4), or the last line for `not freed`.
- **End** E: `to` for a merged PR, else C. So the hours between a merge and a late reap are not counted.
- **Rows**, in the order they first occur:
  - `take`: from S to field 10 of the `take` line (fetch, worktree, warm-up).
  - `not-reported`: from the take's finish to its first `step` line (or to C when there is none). With an unknown start,
    the stretch before the first line is `not-reported` with the time **unknown**.
  - each step name: from its line's stamp to the next `step` line's stamp, the last one to C. A `step` line at or after
    C is dropped (its time lies inside the wait, or after the end) and not counted.
  - `ci-and-merge`: from C to `to`, only for a merged PR. This is the wait for CI and the merge after the PR opened,
    never added to an agent's step.
- **Total**: E − S when S is known; **unknown** otherwise. A take with every stage known sums to its total.

**8. One row per stage name, with a count.** Rows of the same name in one take are added (two runs of `check`, the
stretches of `not-reported`); the `runs` column is the number of lines (or stretches) that gave time to that row: it
shows the check runs and the fix rounds. A row whose time has an unknown part has the time `unknown`. Step names are
printed exactly as reported; the scripts add only `take`, `not-reported` and `ci-and-merge`. No step name is mapped or
grouped.

**9. Durations and shares in text.** A duration of t seconds is `<t>s` for t < 60 (`0s`, `42s`), `<m>m<ss>s` for
t < 3600 (`1m05s`, `39m00s`), `<h>h<mm>m` from 3600 on (`1h40m`, `26h03m`; the seconds are dropped, the minutes are
whole minutes, not rounded). Unknown is the word `unknown`. The share is `floor(100 × t / total + 0.5)` followed by `%`,
and `-` when the row or the total is unknown or the total is 0. Rounded shares need not add up to 100.

**10. The command: `scripts/stages.sh` / `scripts/stages.ps1`, read-only.**

```
stages.sh [--issue N | --last N]      (PowerShell: stages.ps1 [-Issue N | -Last N])
```

- `--issue N`: every take whose `free` line names N in field 11, in file order. N matches `^[1-9][0-9]{0,9}$`.
- `--last N`: the last N takes by the position of their first line, printed in file order (oldest of them first),
  N from 1 to 999. Without an option: `--last 5`. Both options at once, another argument or a bad N: the usage line on
  standard error, exit 1.
- It finds the main checkout and `worktrees.root` the way `slot.*` does (outside a git checkout or without
  `.claude/nightmill.json`: the same message as `slot.*`, exit 1). It calls no `gh`, needs no network, and writes no
  file.
- No `ledger.tsv`: `no record yet: <path>`, exit 0. A record that cannot be read: `stages: cannot read <path>`, exit 1.
- `--issue N` with no matching take: `#N: no record; every stage unknown (no slot took it, or a version before iteration
  41 freed it)`, exit 0. That is also how a story that merged while no slot held it is shown (decision 12).
- Otherwise exit 0, and per take (a blank line between takes):

```
<who>  <branch>  slot <n>  <state>
  stage                runs     time  share
  <name>               <runs> <time> <share>
  ...
  total                       <time> <share>
```

`<who>` is `#<n>` per issue of field 11 joined by `,` (`#12,#13`), or `-`. `<state>` is `merged <to>`, `released
<stamp>` / `reaped <stamp>` (freed, no PR times), `abandoned <stamp>`, `running` or `not freed`. The column lines use
`printf '  %-20s %4s %8s %6s\n'` (the header with `stage`, `runs`, `time`, `share`; the total row with an empty `runs`
and the share `100%`, or `-` when the total is unknown or 0). A name longer than 20 characters pushes its row to the
right. Both shells print the same bytes (LF).

Worked example, the take of the fixture of Tests (S = 0 s): `take` 40s, `not-reported` 5s, `slot-taken` 15s,
`write-tests` 10m00s, `implement` 39m00s, `check` 2 runs 20m00s, `commit` 1m00s, `code-review` 9m00s, `pull-request`
30s, `done` dropped (reported after the PR opened), `ci-and-merge` 19m30s, total 1h40m (6000 s); the shares of
`implement`, `check` and `ci-and-merge` are `39%`, `20%`, `20%`.

**11. `/spec` is not recorded.** The issue asks for "the step names of the report tables of /next, /fix and /spec", but
`/spec` takes no slot and has no report table (Facts), and recording it would need the skill to call a script at each
step, which criterion 7 ("no skill gets longer and no extra agent call is needed") forbids. So a spec's time is not in
the record; the table covers from the take of `/next` or `/fix` to the merge. Named under Left.

**12. A story that merges while no slot holds it** (worked in a single checkout, taken by hand outside the slots, or its
slot abandoned before the merge) is shown from what the record has: no line at all gives the `no record` line of
decision 10; an abandoned take is shown up to the abandon (`abandoned <stamp>`) with no `ci-and-merge` row, and since it
named no PR, `--issue N` does not find it (`--last` does). The table does not ask gh for the times of a PR the record
does not name; that would be a network call at print time and a second source.

**13. The check's times.** `tests/check.sh` sources `scripts/lib/ledger.sh`, reads the clock (decision 4) when it
starts and before and after each `run`, and:

- appends the step's duration to its result line: `-- <name>: ok (<duration>)` or `-- <name>: FAILED (<duration>)`;
- prints, after the last step and before the `SKIPPED:` lines, the block `Times:`, one line per step that ran in the
  order they ran, `printf '  %-28s %8s\n' <name> <duration>`, and the line `printf '  %-28s %8s\n' total <duration>`,
  the total being from the check's start to the end of its last step (so at least the sum);
- keeps `== <name>`, the `SKIPPED:` lines, `CHECK FAILED: <names>`, `ALL CHECKS PASSED` and the exit code as they are.

For the tests only, `NIGHTMILL_CHECK_STEPS` names a file of lines `<name> TAB <command>`; when it is set, the check runs
exactly those steps (`run <name> bash -c <command>`), in file order, instead of its own list, and skips its PowerShell
and `claude` steps without a `SKIPPED:` line, so a smoke test can run the check with fixture steps that move the
fixture clock. The header comment says that both test variables (`NIGHTMILL_CHECK_STEPS`, `NIGHTMILL_CLOCK_FILE`) are
for the tests only, as `slot.*` says of `NIGHTMILL_CLAIM_GATE`. CI does not set them. The check does not write the
record: a check that runs in a slot is already timed by the `check` step the implementer or fixer reports.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | Every reported step is kept with its start time; the duration is known after the slot is freed; the marker stays readable by the previous version | Decisions 2, 3, 7; marker unchanged (Story trigger) |
| 2 | The record survives release and abandon and branch deletion; one line per step, readable and parseable | Decisions 1, 2, 5 |
| 3 | The check reports each step's time and the total, in both shells | Decision 13; `tests/check.ps1` runs `tests/check.sh` (Story trigger) |
| 4 | A command prints, for one issue or the last N, the time per stage and its share, in the slots' step names | Decisions 8, 9, 10 |
| 5 | The CI and merge wait is its own stage, not agent time | Decisions 3 (gh fields), 7 (`ci-and-merge`, cut C) |
| 6 | Unreported steps show as unknown, never zero | Decisions 6, 7, 9, 12 |
| 7 | Written by the scripts that already run; no skill longer, no extra agent call | Decisions 3, 11 |
| 8 | Same in both shells; smoke steps with fixture reports and clock: per-step durations, total, an unreported step, a released slot, the check's times | Decisions 4, 13; Tests |
| 9 | The README says where the record lives, what the stages are and how to read the table | Files touched (README) |

## Tests

All steps exist in both shells with the same cases and the same expected text; the clock comes from
`NIGHTMILL_CLOCK_FILE` everywhere, never from the system clock.

**`tests/smoke-stages.sh` and `tests/smoke-stages.ps1`** (new; wired into `tests/check.sh` and both CI jobs).

- `== stages from a fixture record` (criteria 4, 5, 6): `tests/fixtures/stages/ledger.tsv` and the expected outputs
  beside it. Times below in seconds after a fixed `T0`; the fixture writes them as stamps.
  - Take A, slot 1, merged, issue 12: `take` from T0 to T0+40; steps `slot-taken` +45, `write-tests` +60, `implement`
    +660, `check` +3000, `check` +3600, `commit` +4200, `code-review` +4260, `pull-request` +4800, `done` +4900; `free`
    `released` at +9000, PR 7, `from` +4830, `to` +6000, issues `12`. `stages --issue 12` prints exactly the rows of the
    worked example of decision 10 (asserts: the per-step durations, two `check` runs added, `done` dropped,
    `ci-and-merge` 19m30s and not inside `pull-request`, total 1h40m equal to `to` − S though the free line is at +9000,
    the shares).
  - Take B, slot 2: only `step` lines and a `free` `reaped` line with PR times (a take by the previous version): the
    first row is `not-reported` with time `unknown`, the total is `unknown`, every share `-`, and `ci-and-merge` is
    known.
  - Take C, slot 1: a `take` line and no `step` line, then `free` `abandoned` (an unreported step): rows `take` and
    `not-reported` with known times, no `ci-and-merge`, a known total; state `abandoned <stamp>`.
  - Take D, slot 2: a `take` line and two steps, no `free`: state `running`, the last step runs to the fixture clock.
  - A line of kind `run` (a later kind) is skipped without a note; one line with 10 fields and one with a bad stamp give
    `stages: skipped 2 malformed lines of <path>` on standard error.
  - `--issue 99`: the `no record` line, exit 0. No option: the last 5 (here all four, in file order). `--last 1`: take D
    only. `--last 0`, `--last x`, `--issue 1 --last 2`: usage, exit 1. No file: `no record yet: <path>`, exit 0.
- `== the check's step times` (criterion 3): a temporary `NIGHTMILL_CHECK_STEPS` file with three steps that each write
  a new time into the clock file (+12 s and exit 0, +75 s and exit 1, +3700 s and exit 0), run through `tests/check.sh`
  (bash) and through `tests/check.ps1` (PowerShell). Asserts `-- one: ok (12s)`, `-- two: FAILED (1m15s)`, `-- three: ok
  (1h01m)`, the `Times:` block with the three lines and `total` `1h03m` (3787 s), `CHECK FAILED: two`, exit 1, and no
  `SKIPPED:` line; a second run with three passing steps ends with `ALL CHECKS PASSED`, exit 0.
- `== the duration text` (decision 9): 0, 59, 60, 3599, 3600, 3659 and 93780 seconds give `0s`, `59s`, `1m00s`,
  `59m59s`, `1h00m`, `1h00m`, `26h03m`; an unusable `NIGHTMILL_CLOCK_FILE` gives its note and a stamp from the system
  clock.

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**, one new section `== the record (iteration 41)` at the end, before
`SMOKE OK` (criteria 1, 2, 7, 8). The fake `gh` learns to answer `--json` with `createdAt`, `mergedAt` and
`closingIssuesReferences` from three more columns of `merged.txt`, in both tests. With the clock file at T0:

- a take of slot 1 (clock moved by the warm-up to T0+30) appends one `take` line with `from` T0 and `to` T0+30;
- two reports (`slot-taken` at T0+35, `implement` at T0+100) append two `step` lines with those stamps, and the marker
  afterwards has exactly the seven keys of iteration 23 (read by key, as the previous version does);
- a refused report (slot 2, not in use) and a report after the slot is freed append nothing;
- `--release 1` with a merged PR (number, `createdAt`, `mergedAt`, issue 41) deletes the branch, prints its line as
  today and appends the `free` `released` line with those fields; `stages.sh --issue 41` then shows `take`,
  `not-reported`, `slot-taken`, `implement`, `ci-and-merge` and the total (a released slot, the branch gone);
- a take and `--abandon` append `take` and `free` `abandoned` with empty PR fields; a take, a merged PR and a second
  take (the reap) append `free` `reaped`; a dead claim freed with `--abandon` appends nothing;
- with `ledger.tsv` made a directory, a report exits 0, updates the marker and prints `slot: the record was not written
  (...)` once on standard error, after the retries (the test allows for their 5 s);
- every line in the file has exactly 11 tab-separated fields.

**`tests/lint.sh`**, one new section `== the stage record is wired`, after `== slots report what their agent does`:
both slot scripts carry `ledger.tsv`; `scripts/stages.sh` and `scripts/stages.ps1` exist; `tests/check.sh` and
`.github/workflows/ci.yml` run `smoke-stages.sh` and `smoke-stages.ps1`; `README.md` mentions `ledger.tsv`,
`ci-and-merge`, `not-reported` and `stages.sh`; no file in `skills/` mentions `ledger.tsv` (criterion 7).

**Manual check by the maintainer** (the issue's Verification, not `verification.manualCheckPaths`): with this branch
installed as a preview, take a story through a slot with `/next`, let it run through the check and the pull request,
release the slot after the merge, then run `scripts/stages.sh --issue <n>`: each stage has a plausible duration,
`ci-and-merge` matches the PR's open and merge times on GitHub, and the total matches the time on the wall from the
take to the merge. Run `bash tests/check.sh` and see the `Times:` block.

## Files touched

- `scripts/lib/ledger.sh`, `scripts/lib/ledger.ps1` (new): the clock, the stamp, the duration text and the append with
  its retries (decisions 4, 5, 9). Header comments name `NIGHTMILL_CLOCK_FILE` as test-only.
- `scripts/slot.sh`, `scripts/slot.ps1`: source the helpers; the `take`, `step` and `free` lines (decision 3); the gh
  fields of reap and release; a header paragraph after "Claim (iteration 34)": `# Record (iteration 41): the take, every
  report and every freeing append one line to <root>/.slots/ledger.tsv (see scripts/stages.sh); a failed append prints
  one note and changes nothing else. Same behaviour as slot.ps1.` (in `slot.ps1`: `slot.sh`, `stages.ps1`). No other
  change of output, exit codes or marker text.
- `scripts/stages.sh`, `scripts/stages.ps1` (new): the command of decision 10. The bash side may keep the computation in
  `scripts/lib/stages.awk`, as `status.sh` keeps its in `scripts/lib/status.awk`.
- `tests/check.sh`: decision 13. `tests/check.ps1` does not change.
- `tests/smoke-stages.sh`, `tests/smoke-stages.ps1`, `tests/fixtures/stages/` (new); `tests/smoke-slot.sh`,
  `tests/smoke-slot.ps1`: the sections of Tests.
- `tests/lint.sh`: the section of Tests.
- `.github/workflows/ci.yml`: `run: bash tests/smoke-stages.sh` in `smoke-bash` and `run: powershell -NoProfile
  -ExecutionPolicy Bypass -File tests/smoke-stages.ps1` in `smoke-powershell`, after the panel steps; no other change
  (permissions, timeouts, concurrency and pins of iteration 38 stay).
- `README.md`: a new subsection `### Where a story's time went`, after "What a slot's agent is doing": where the record
  lives (`<worktrees.root>/.slots/ledger.tsv`, untracked, append-only, kept after release, abandon and branch deletion),
  that the slot scripts write it (take, report, freeing) and nothing else does, the line kinds in one sentence, the
  stages (`take`, `not-reported`, the reported step names, `ci-and-merge` from the PR's open to its merge), how to run
  `scripts/stages.sh --issue N` / `--last N` (and `stages.ps1 -Issue N` / `-Last N`), what `runs`, `time`, `share`,
  `unknown` and `-` mean, that `/spec` is not recorded, and that `tests/check.sh` prints its step times. In "What is in
  the plugin", if it lists the scripts, `stages`.
- `CHANGELOG.md`, one bullet under `Unreleased`: `- Iteration 41 (#199): the time a story spends in each stage is
  recorded and shown. The take, every report and every freeing append one line to <worktrees.root>/.slots/ledger.tsv,
  which survives the release and the branch; scripts/stages.sh (stages.ps1) prints per issue or for the last N takes
  the time and share of each stage, with the wait for CI and the merge as its own stage (ci-and-merge) and unreported
  time as not-reported or unknown, never 0. tests/check.sh prints the time of each step and the total. The marker and
  the config do not change.`

## Risks

- **Concurrent appends.** Two slots can append at the same moment. A single short `>>` write is atomic on POSIX file
  systems with `O_APPEND`; Git for Windows emulates append, and PowerShell's `AppendAllText` takes the file for a moment.
  The retries of decision 5 cover a refused open; an interleaved line would be malformed and skipped with a note
  (decision 6), never fatal.
- **Clock jumps.** A system clock set back makes a difference negative; it counts as 0 (decision 7), so a row may be too
  short, never negative.
- **A reused branch name at `--release`.** The release keeps taking the first merged PR for the branch (as its message
  does today), so an older PR of the same name would give wrong PR times. The reap matches by head commit and is not
  affected.
- **`closingIssuesReferences` of another repository** (a `Closes owner/other#N`) is recorded as its number alone and
  could match `--issue N` of this repository. Rare; the line still carries the PR number.
- **The file grows** by about 20 lines per story (a few kilobytes); no rotation is needed for years of use.
- **The check output changes** (a time on each result line, the `Times:` block). Nothing parses those lines (Facts).

## Size estimate

L: about 1000 changed lines. The two helper libraries about 120, the slot scripts about 80 together, the two stage
commands about 350, the check about 30, the smoke tests and fixtures about 400, lint, CI, README and CHANGELOG about 50.

## Not done

- The time of `/spec` (no slot, no report; decision 11) and of anything before a take (Ready to Approved, waiting for
  the maintainer before the take).
- The time a story waits for the maintainer outside the CI wait (a PR whose auto-merge is withheld waits inside
  `ci-and-merge`, which then is the wait for CI and for the maintainer together; they are not told apart).
- Cost, tokens and turns (#165's run lines), cycle time per board status, totals across takes or issues, charts, a
  browser report, history across projects (#166 builds on this record).
- Linking an abandoned take to its issue, or several takes of one issue that did not end in a merge.
- Timing a project's own check command: only nightmill's `tests/check.sh` prints step times; in a slot, every check
  run is timed as the `check` step.
- Any change to the marker, to `--status`, to `stalledAfterMinutes`, to the stale flag, or to any threshold; any
  speed-up.
- Rotating or pruning `ledger.tsv`.

## Left

- **`/spec` in the stages.** The issue names "the report tables of /next, /fix and /spec", but `/spec` has no report
  table and takes no slot, and criterion 7 forbids a longer skill. This spec records `/next` and `/fix` only
  (decision 11). If the spec stage is wanted, that is a separate story that changes `/spec` (a slot or a report call).
- **#165's fields.** Decision 1 puts #165's run lines into `ledger.tsv` with the kind `run` and the first two fields of
  decision 2; their other fields, and whether the file's place under `worktrees.root` suits a project without slots,
  are for #165's spec to settle.
- **#193 and `--report`.** See the note under Order: whether a refresh writes step lines is for #193's spec.
