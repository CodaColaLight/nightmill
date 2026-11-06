# Iteration 23: slots record what their agent is doing and /status shows it

Status: delivered in iteration 23 (PR #92)

Story: #67, epic #47 (Unattended runs). Adds one command to the slot scripts, `slot.sh --report <step>` and
`slot.ps1 -Report <step>`, that writes which skill and role works in a slot, its current step and the time of the
report into the slot's marker; adds the config key `worktrees.stalledAfterMinutes`; makes `slot --status --porcelain`
carry the report and whether the agent is running or stalled; turns the slots part of `/status` into one Slots
section that lists every slot; and makes `/next` and `/fix` (and the implementer and fixer they launch) report at
each step. Changes `scripts/slot.ps1`, `scripts/slot.sh`, `scripts/lib/json.sh`, `scripts/status.ps1`,
`scripts/status.sh`, `scripts/lib/status.awk`, `skills/status/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`,
`skills/workflow/SKILL.md`, `schema/nightmill.schema.json`, `templates/nightmill.example.json`, the smoke tests of the
slots and of `/status` with their fixtures, the lint, the README and the CHANGELOG.

**This is a story trigger**, twice over: a new config key (`worktrees.stalledAfterMinutes`, "a new, renamed or removed
config key") and new keys in the slot marker ("a change to the slot marker format"). The status flow and who sets a
status do not change. The pull request therefore does **not** auto-merge; it says so. The skills change, so the manual
check of `verification.manualCheckPaths` applies. The slot scripts, the schema and the workflow skill are in
`parallel.hotFiles`, and the pairing rule forbids two tasks that both change the slot scripts or the schema.

**Order.** This iteration is implemented after #78 (iteration 22, `slot --capacity`) has merged, and after #60
(iteration 17, merged). It builds on the numbers and texts of `docs/specs/iteration-22-capacity.md` as specified there
(the fifth porcelain field `retiring`, the `capacity:` line of `/status`, the effective slot count), not on unmerged
code. If #78 merges with a different porcelain layout, the new fields of this iteration follow #78's last field and
the field numbers below move with them; nothing else changes.

## Goal

The maintainer sees in `/status` which slots are free, which are busy, what the agent in each busy slot is doing and
whether it is still alive.

## Facts this rests on

- A slot is busy while `<worktrees.root>/.slots/slot-N.json` exists. `--take` writes it with the keys `slot`, `branch`,
  `since` in that order (bash through `json_marker` in `scripts/lib/json.sh`, LF, 2-space indent; PowerShell through
  `ConvertTo-Json`, whose key order the smoke test does not pin). `--release`, `--abandon` and the automatic release
  (`--reap` and the first step of every take, iteration 17) remove it. Nothing else writes it, so a session that
  finished, crashed or was abandoned leaves a marker that looks the same as a live one.
- `since` is local wall-clock time, `YYYY-MM-DDTHH:MM:SS` (bash `date +%Y-%m-%dT%H:%M:%S`, PowerShell
  `(Get-Date).ToString("s")`). `/status` compares it with the local time read as if it were UTC (`nowl` in
  `lib/status.awk`, `$nowLocal` in `status.ps1`); `NIGHTMILL_NOW` (seconds since 1970, local time taken as UTC) fixes
  that clock for the smoke tests.
- Every reader of a marker reads it by key: `marker_field` (`json_get`) in bash, `ConvertFrom-Json` in PowerShell.
  The previous version reads only `slot`, `branch` and `since`, so further keys are ignored by it.
- `slot --status --porcelain` prints `<n> TAB busy TAB <branch> TAB <since>` or `<n> TAB free`; after #78 a busy slot
  above the slot count gets a fifth field, `retiring`. `lib/status.awk` splits on every tab (`split(line, r, "\t")`)
  and reads the first four fields; `status.ps1` splits with `-split "`t"` and reads the first four.
- `/status` prints, when the project has `worktrees`, an empty line, then `slots: none busy` or the heading `slots`
  and a table of the **busy** slots only (`slot  Branch  Since  PR  Flag`), and after #78 the line
  `capacity: slots <n> (<source>), agents <m> (<source>)`. The `stale:` flags of a busy slot are
  `stale: busy, PR merged (slot --release N)`, `stale: busy, PR closed (slot --abandon N)` and
  `stale: busy, no open PR` (no PR and the marker older than the 2-hour grace).
- `/next` and `/fix` take a slot (`/next` step 2.2, `/fix` step 3) and hand the code to a subagent in the role
  `implementer` or `fixer`, then to a `codeReviewer` (tools `Read, Grep, Glob`: it cannot run a script). `/spec`
  takes no slot: it creates a branch in the checkout it runs in ("The spec writer", step 1).
- The schema keywords the validators understand are `type`, `properties`, `required`, `items`, `minimum`, `minItems`,
  `additionalProperties` and `enum`; the lint fails on `maximum` and the others. An unknown key is a warning of the
  validator, never an error (without `--strict`).

## Decisions

**1. The report lives in the marker.** Four keys are added after the three that exist; nothing is removed or renamed,
so the previous version reads the marker as before. No second file per slot, so a released slot loses its report with
its marker.

**2. A report is a command, `slot --report <step>`.** The skill and the role are named on every call; the slot is
always given by number (the number the take printed, `Slot N is yours`). The script does not guess the slot from the
working directory: the implementer and the fixer do not run in the slot directory.

**3. The take does not report.** `--take` writes the marker it writes today, so a slot taken by hand, or a marker of
the previous version, is busy with an unknown step. The skill reports right after its take.

**4. Running or stalled is decided by the slot script**, once, from the last report and the threshold, and printed in
the porcelain line. `/status`, and later the page (#68) and the panel (#69), show that word; none of them repeats the
rule.

**5. Three agent states: `running`, `stalled`, `unknown`.** A busy slot with a report is `running` or `stalled` by
the age of that report, as the issue says. A busy slot without a report (a marker of the previous version, a take by
hand, a take with no report yet, a `reported` that cannot be read) is `unknown`: busy with an unknown step
(criterion 3). A skill reports the step `done` when its work in the slot is over (the pull request is open) and
`stopped` when it stops with a `Stopped:` line after the take; these are ordinary step names with no special meaning.
So a slot that waits for its merge after its last report shows `stalled` once the threshold has passed: that is the
issue's rule (no recent report is stalled), and the step column says `done`. `slot --release`, `--reap` (or the
automatic release of the next take, iteration 17) frees it.

**6. The reviewer is reported by the session.** The `codeReviewer` cannot run a script, so the session reports the
review step with the role `codeReviewer` just before it launches the reviewer. The implementer and the fixer report
their own steps.

**7. The threshold is minutes, default 30.** Reports come at step boundaries; the implementer's longest stretch
without one is between two runs of the check. 30 minutes is long enough not to call such a stretch stalled and short
enough for a crashed session to show within half an hour. It is a project value (a slow build makes stretches
longer), so it is configuration, not a constant like the 2-hour grace of `/status`.

**8. A long step shows as stalled; there is no heartbeat.** A step that runs longer than the threshold without a
report (a code review, whose agent cannot run a script; a slow check) shows `stalled` while it runs. That is an
accepted limit: `stalled` means "no report for a while, look at it", never that something is stopped or freed, and a
project with long steps raises `worktrees.stalledAfterMinutes`. No hook, timer or background process reports between
steps.

**9. `/spec` does not report.** It takes no slot (it branches in the checkout it runs in), so there is no marker to
write, and showing agents outside the slots is out of scope of #67. A report for `/spec` would need a second record
outside `.slots` and a second reader; it is left to a later story if wanted. `skills/spec/SKILL.md` is not changed.

## The marker

After a report the marker has seven keys, in this order (LF, 2-space indent, as `json_marker` writes):

```json
{
  "slot": 1,
  "branch": "feat/a",
  "since": "2026-11-06T09:00:00",
  "skill": "next",
  "role": "implementer",
  "step": "check",
  "reported": "2026-11-06T09:41:12"
}
```

| Key | Value |
|---|---|
| `slot`, `branch`, `since` | `slot` is N; `branch` and `since` are copied as text from the marker, unchanged (an empty string when the marker lacks one) |
| `skill` | the skill that works in the slot: `next` or `fix` (any value of the form below is accepted) |
| `role` | who works at this step: `session` (the orchestrating session, not a role of "Agent roles and models"), `implementer`, `fixer` or `codeReviewer` |
| `step` | the current step, one of the names in "The skills"; none has a special meaning (decision 5) |
| `reported` | the local time of the report, `YYYY-MM-DDTHH:MM:SS`, the format of `since` |

bash writes it with a new function of `scripts/lib/json.sh`,
`json_marker_report SLOT BRANCH SINCE SKILL ROLE STEP REPORTED` (the text above, each string through
`json_quote`). PowerShell writes the same text, built line by line (not `ConvertTo-Json` of a hashtable, whose key
order is not fixed), each string escaped as `json_quote` does (backslash, double quote, control characters), with
`Write-Lf`; for the same values both shells write the same bytes. Both write to a temporary file
`slot-N.report.tmp` in `.slots` and move it over the marker, so a reader never sees half a marker; the move happens
only when the marker still exists at that moment (a report never brings back a slot that was released while it ran),
and otherwise the temporary file is removed. The take's marker is unchanged.

`slot.ps1` reads `since` and `reported` as the text in the file, in every command: under PowerShell 7, whose
`ConvertFrom-Json` turns such a text into a date, a date value is formatted back with `ToString("s")`, so both shells
copy and print the same text.

## `--report`

| | bash | PowerShell |
|---|---|---|
| Report a step | `slot.sh --report <step> --slot N --skill <skill> --role <role>` | `slot.ps1 -Report <step> -Slot N -Skill <skill> -Role <role>` |

On success it rewrites the marker of slot N as above, prints nothing and exits 0. It needs no `gh`, no network and no
git command beyond finding the main checkout and the configuration, like every other flag. It works on any slot that
has a marker, also a retiring one (#78).

It refuses, writes one line to standard error, leaves the marker byte for byte as it was and exits 1, when:

| Case | Message |
|---|---|
| no slot number (`--slot` missing or 0) | `report needs a slot number` |
| slot N has no marker | `slot N is not in use` (the text of `--release`) |
| the step, the skill or the role is empty, not given, or not 1 to 40 characters of `A-Z`, `a-z`, `0-9` and `-`, starting with a letter or digit (checked in that order: step, skill, role) | `report: the <step\|skill\|role> must be 1 to 40 letters, digits or -, got "<text>"` |
| the marker is not valid JSON | `slot N: the marker is not valid JSON` |

A usage error comes before all of these: `--report` together with `--take`, `--release`, `--abandon`, `--reap`,
`--status` or `--capacity`, or `--skill` / `--role` without `--report`, prints the usage line and exits 1; the usage
line gains `--report <step> --slot N --skill <s> --role <r>` (PowerShell: `-Report <step> -Slot N -Skill <s> -Role <r>`).
`slot.ps1` knows that `-Report` was given from `$PSBoundParameters`, so `-Report ""` is the empty step of the table.

The character rule keeps the porcelain line free of tabs and newlines. The checks run in the order of the table; the
first that fails is reported. Both shells give the same messages, with one exception: `--report` as the last word,
with no value at all, is the usage line in bash, while PowerShell's parameter binding refuses `-Report` without an
argument with its own message (exit code not 0 in both).

## The config key

`worktrees.stalledAfterMinutes`: integer, minimum 1, default 30.

- **Schema** (`properties.worktrees.properties`): `"stalledAfterMinutes": { "type": "integer", "minimum": 1,
  "default": 30, "description": "Minutes without a report after which the agent in a busy slot counts as stalled
  instead of running (slot --status --porcelain, /status). /next and /fix report at each step with slot --report." }`.
  No `maximum` (the validators do not support it).
- **Example template**: `"stalledAfterMinutes": 30` in `worktrees` of `templates/nightmill.example.json`, after
  `slots`. This repository's own `.claude/nightmill.json` is not changed (the default applies).
- **README** configuration table (below).
- **Read by** `slot.sh` (`json_get worktrees.stalledAfterMinutes`) and `slot.ps1` (`$wt.stalledAfterMinutes`), every
  time they print `--status --porcelain`. A value is used when it is a JSON number written as 1 to 6 digits without a
  leading zero, sign, fraction or exponent (1 to 999999): bash checks the kind `number` in the parsed records and the
  text against `^[1-9][0-9]{0,5}$`; PowerShell checks that the value is an `[int]` or `[long]` from 1 to 999999. When
  the key is absent or `null`, or `worktrees` is absent, the threshold is 30 and nothing is said. Any other value
  (`0`, `-5`, `2.5`, `30.0`, `"30"`, `"x"`, `true`) gives 30 and one line on standard error,
  `slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30`; the porcelain output and its
  exit code are as with 30. A configuration file that is missing is the error it is today (`no ... (run
  /nightmill:init)`). `status.*` do not read the key; they pass that line through to their own standard error
  (`status.sh` copies the standard error of a successful `slot.sh` call to its standard error; `status.ps1` runs
  `slot.ps1` in its own process, where the line already reaches standard error). Their output and exit code do not
  change.
- The previous version ignores the key; its validator, with its own schema, warns `unknown key` for it (not an error).

## Running and stalled

For a busy slot, with `threshold` = `stalledAfterMinutes` × 60 seconds and `age` = now − `reported` in seconds (both
local wall-clock times on one scale, as `/status` compares `since`; `NIGHTMILL_NOW`, when set, is now, in the slot
scripts as in the status scripts; a negative age counts as 0):

| Agent state | When |
|---|---|
| `unknown` | the marker has no `reported` key, or its value is not of the form `YYYY-MM-DDTHH:MM:SS` (a marker of the previous version, a take with no report yet, a hand-written marker) |
| `running` | otherwise, `age <= threshold` |
| `stalled` | otherwise, `age > threshold` |

With the default, a report 30 minutes old is running and one 30 minutes and 1 second old is stalled. The step plays no
part (decision 5): a slot whose last step is `done` or `stopped` is running or stalled by its age like any other. A
free slot has no agent state.

Both shells turn `reported` and now into seconds with the arithmetic of `stamp` in `lib/status.awk` (days from year,
month and day, plus hours, minutes and seconds), not with a date parser, so every value of the form gives a number and
the two shells agree to the second. Without `NIGHTMILL_NOW`, now is the local time of the clock read the same way
(`date +%Y-%m-%dT%H:%M:%S`, `(Get-Date).ToString("s")`). `/status` calls the slot script with its own environment, so
under the smoke tests' fixed `NIGHTMILL_NOW` the slot script and `/status` use the same now.

## `slot --status --porcelain`

A free slot: `<n> TAB free`, unchanged. A busy slot, ten fields:

```
<n> TAB busy TAB <branch> TAB <since> TAB <retiring> TAB <agent> TAB <skill> TAB <role> TAB <step> TAB <reported>
```

| Field | Content |
|---|---|
| 1-4 | unchanged: the slot number, `busy`, the branch, `since` as written |
| 5 | `retiring` for a busy slot above the slot count (#78), else empty; from this iteration it is always present, so the fields after it keep their positions |
| 6 | `running`, `stalled` or `unknown` |
| 7, 8, 9 | `skill`, `role`, `step` as written, or empty when the key is absent |
| 10 | `reported` as written, or empty when absent |

Empty fields stay (two tabs in a row); readers split on every tab. Which slots are listed is #78's rule, unchanged.
Without `--porcelain`, `--status` is unchanged. `--status` in both forms stays read-only: no `gh` call, no marker
written.

## `/status`: the Slots section

When the project has `worktrees`, the slots part of `/status` becomes one section: an empty line, the heading
`slots`, a table with one row per line of `slot --status --porcelain`, in the order the script prints them (by slot
number, free and busy alike), then #78's `capacity:` line. `slots: none busy` (iteration 8) is no longer printed: with
no busy slot the table lists every slot as free. A retiring busy slot (#78) is a busy row like any other; `/status`
does not mark it, as #78 specifies. Without `worktrees` nothing about slots is printed, as today.

| Column | Busy slot | Free slot |
|---|---|---|
| `slot` (right aligned) | the number | the number |
| `State` | `busy` | `free` |
| `Agent` | field 6 | empty |
| `Branch` | the branch | empty |
| `Skill` | `<skill>/<role>`; a missing part is `?`; `?` when both are missing | empty |
| `Step` | the step, `?` when missing | empty |
| `Report` (right aligned) | the age of `reported` (`<m>m`, `<h>h`, `<d>d`, the `Age` rule of iteration 8), `-` when it is missing or not of the form | empty |
| `Since` (right aligned) | the age of the marker, as today | empty |
| `PR` | the pull request whose head is the branch, with its CI for an open one, as today (`#23 open, ci pass`, `#20 merged`, `-`) | empty |
| `Flag` | the existing `stale:` flags, same conditions and texts | empty |

The table is printed by the existing table function (two spaces between columns, trailing spaces cut), so a free row
ends after `free`. An example with the clock at 2026-11-05T12:00:00:

```
slots
slot  State  Agent    Branch    Skill             Step   Report  Since  PR                 Flag
   1  busy   running  feat/a    next/implementer  check      3m     2h  #23 open, ci pass
   2  busy   unknown  feat/old  ?                 ?           -     3d  #20 merged         stale: busy, PR merged (slot --release 2)
   3  free
capacity: slots 3 (config), agents 2 (default)
```

The `stale:` flags are not changed and no new flag is added: `stalled` is shown in `Agent` only. The PR
and CI lookup is the one that exists (`pick` by head branch); it is done for busy slots only. The `Who` column of the
board table and the `In progress` flag keep reading the busy slots as before. Both shells print the same.

`skills/status/SKILL.md`: the description says "the slots and what their agents do" instead of "busy slots"; in the
second of its three added lines, a `stalled` slot is one whose agent has not reported for
`worktrees.stalledAfterMinutes` (the session may have ended or crashed; with the step `done` the run is over and the
slot waits for its merge): the maintainer looks at it and, if it was dropped, frees it with `slot --abandon N`; a
merged one is freed by `slot --release N`, `--reap` or the next take. The skill still changes nothing.

## The skills

A report is one call of the shell in use:
`"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Report <step> -Slot <n> -Skill <skill> -Role <role>` or
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --report <step> --slot <n> --skill <skill> --role <role>`. A report that
fails never stops a run: the session goes on and names a failed report it made itself once, in its final message (the
implementer and the fixer go on and name nothing; their result block is unchanged). A report is not a
board status. A run without slots (no `worktrees`, `git switch -c` in a single checkout) took no slot and reports
nothing.

**`/next`** (`--skill next`), slot N from the take:

| When | Role | Step |
|---|---|---|
| right after the take (step 2.2) | `session` | `slot-taken` |
| just before the implementer is launched (step 3) | `implementer` | `implement` |
| the implementer, before its step 1 / step 2 | `implementer` | `tests` / `code` |
| the implementer, before every run of the check | `implementer` | `check` |
| the implementer, before its commit | `implementer` | `commit` |
| just before each launch of the code reviewer ("The code review", step 2) | `codeReviewer` | `code-review` |
| just before the launch of fix round k ("The code review", step 4) | `implementer` | `fix-round-<k>` |
| the manual check (step 4), when it applies | `session` | `manual-check` |
| the CHANGELOG entry and the rebase (step 5) | `session` | `changelog` |
| opening the pull request (step 6) | `session` | `pull-request` |
| after step 7 (and step 8 when it applies) | `session` | `done` |
| on any `Stopped:` line after the take | `session` | `stopped` |

**`/fix`** (`--skill fix`), the same shape:

| When | Role | Step |
|---|---|---|
| right after the take (step 3) | `session` | `slot-taken` |
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

In batch mode each bug reports to its own slot.

**The implementer and fixer prompts** gain, after "Do this:", one paragraph with the command filled in by the session
(with the absolute path of the script, as `${CLAUDE_PLUGIN_ROOT}` expands in the session):
"Report your progress with `<the report command of the shell in use, with --slot <n> --skill <next|fix> --role
<implementer|fixer> (PowerShell: -Slot, -Skill, -Role) and the step as the value of --report / -Report>`: before step 1
(`tests`, for the fixer `test`), before step 2 (`code`), before every run of the check (`check`) and before the commit
(`commit`). It writes only the slot's marker outside the repository and is not a status; when it fails, go on." The
fix-round prompts are the same prompts and carry it too, so inside a fix round the step `fix-round-<k>` is followed by
the steps of the prompt.

**`/spec`** takes no slot, so it reports nothing and its file is not changed by this iteration (decision 9).

**`skills/workflow/SKILL.md`**, "Parallel work", the first bullet gains one sentence: a skill that works in a slot
reports each step with `-Report` / `--report` (the steps are in `/next` and `/fix`), and `/status` shows the slot
`running` while the last report is at most `worktrees.stalledAfterMinutes` old, `stalled` after that (also a slot
that waits for its merge after its last step, `done`), `unknown` without a report.

## README

- "What is in the plugin": the slot scripts row gets `-Report <step>` among the listed flags; the `/nightmill:status`
  row says "every slot with what its agent is doing (running, stalled)" instead of "busy slots".
- "Why slots" gains a paragraph "What a slot's agent is doing": `/next` and `/fix`, and the implementer and fixer
  they launch, record their skill, role and current step in the slot's marker at each step (`-Report` /
  `--report`); `/status` lists every slot with its agent state: **running** while the last report is at most
  `worktrees.stalledAfterMinutes` minutes old (default 30), **stalled** when it is older (the session may have ended,
  crashed or been abandoned; look at it, and free the slot with `-Abandon` if it was dropped), **unknown** when the
  slot has no report (taken by hand or by an older version). A slot whose run is over (step `done`) and that waits for
  its merge also shows stalled once the threshold has passed; `-Release`, `-Reap` or the next take frees it. Nothing
  is stopped or freed because a slot is stalled, and a step longer than the threshold
  (a long code review or check) shows stalled while it runs (decision 8); `/spec` takes no slot and is not shown.
- Configuration table, the `worktrees` row: "Slot root, count, port bases, warm-up commands, run hints, and
  `stalledAfterMinutes` (default 30): the minutes without a report after which a busy slot's agent counts as stalled".

## CHANGELOG

One bullet under `Unreleased`, in the form of the others:
`- Iteration 23 (#67): slots record what their agent is doing and /status shows it. ...` naming `--report` /
`-Report`, the four marker keys, the key `worktrees.stalledAfterMinutes` (default 30), the porcelain fields 5 to 10,
the agent states `running`, `stalled` and `unknown`, the Slots section of `/status` and that `slots: none busy` is gone, the reporting steps of `/next` and `/fix`, and
that the marker and the config stay readable by the previous version.

## Tests

Each acceptance criterion of #67 is a test or a manual scenario. Names are the behaviour protected.

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**, the same cases in both, new section "== reports", in the
throwaway repository the file builds (two slots, no `stalledAfterMinutes` in its config):

1. **A report writes the fields**: after a take of slot 1, `--report tests --slot 1 --skill next --role implementer`
   exits 0 and prints nothing; the marker's keys are `slot`, `branch`, `since`, `skill`, `role`, `step`, `reported`
   in that order; `slot`, `branch` and `since` have the values the take wrote; `reported` has the form
   `YYYY-MM-DDTHH:MM:SS`.
2. **A second report replaces the step and the time and keeps `since`.**
3. **Refusals change nothing**: no slot number; slot 2 without a marker (`slot 2 is not in use`); a step that is
   empty, `a b`, `a.b`, 41 characters long or holds a tab (40 characters are accepted); a missing `--skill`; a missing
   `--role`; a marker that is not valid JSON (written by hand, restored afterwards); `--report` with `--status`; `--skill`
   without `--report`: each exits 1 with its message on standard error (the usage line for the last two) and the marker
   is byte for byte as before; no `slot-N.report.tmp` is left in `.slots`.
4. **Porcelain carries the fields**: the busy line has ten fields, fields 1 to 4 as before, field 5 empty, field 6
   `running`, fields 7 to 10 the reported values; a free line is still `2<TAB>free`.
5. **Running and stalled by the default threshold**: a marker with `reported` set by hand and `NIGHTMILL_NOW` fixed:
   1800 seconds later is `running`, 1801 seconds later is `stalled`.
6. **The threshold comes from the config**: with `"stalledAfterMinutes": 5` in a copy of the config, 301 seconds is
   `stalled` and 300 is `running`.
7. **An unusable threshold falls back to 30**: `0`, `-5`, `2.5`, `30.0`, `"30"`, `"x"` and `true` each give the line
   on standard error, exit 0 and the states of case 5; `null`, a missing key and a config without `worktrees` give the
   states of case 5 and nothing on standard error.
8. **The step plays no part**: a marker with the step `done` and one with `stopped` are `running` 1800 seconds after
   `reported` and `stalled` 1801 seconds after it, as in case 5.
9. **A marker of the previous version is busy with an unknown step**: the three-key marker (written by
   `json_marker` / the hand text of case 11 of iteration 17) gives `busy`, field 5 empty, field 6 `unknown`, fields 7
   to 10 empty.
10. **A reported slot is released, reaped and abandoned as before**: `--abandon` frees a slot with seven keys; `--reap`
    frees a merged one (the fake `gh` of iteration 17); the marker is gone afterwards.
11. **The take is unchanged**: the existing case "the marker format is unchanged" (keys `slot`, `branch`, `since`)
    still passes, and `--status` without `--porcelain` prints what it printed.
12. **`--status` stays read-only**: after a `--status --porcelain` with reported slots the fake `gh` log is empty and
    the markers are byte for byte the same.

**`tests/smoke-status.sh` and `tests/smoke-status.ps1`**: `markers.txt` of a scenario gains four optional columns
(`skill`, `role`, `step`, `reported`); a line with them is written as a seven-key marker, a line without them as the
three-key marker it is today. With the fixed clock (2026-11-05T12:00:00, no `stalledAfterMinutes`, so 30 minutes),
scenario `c` becomes:

| Slot | Branch | Report columns | Agent | Flag (unchanged) |
|---|---|---|---|---|
| 1 | `feat/merged` | `next`, `session`, `done`, `2026-11-04T09:00:00` | `stalled` | `stale: busy, PR merged (slot --release 1)` |
| 2 | `feat/closed` | none | `unknown` | `stale: busy, PR closed (slot --abandon 2)` |
| 3 | `feat/stale` | `next`, `implementer`, `check`, `2026-11-02T13:00:00` | `stalled` | `stale: busy, no open PR` |
| 4 | `feat/new` | `fix`, `fixer`, `test`, `2026-11-05T11:55:00` | `running` | none |

Its `expected.txt` and those of `a` (two three-key markers: both `unknown`) and `b` (four free slots instead of
`slots: none busy`) are rewritten to the new section. Added checks: the header line of the section; each agent state in
its row; a `Report` of `5m` for slot 4 and `-` for the unknown slot; free rows end after `free`; every `stale:` flag
text of the existing checks is still there; without `worktrees` nothing about slots is printed; with
`"stalledAfterMinutes": 0` in the config `/status` exits 0, prints the same table and has the warning of the slot
script on standard error. Both shells compare against the same expected files.

**`tests/lint.sh`**, new section "== slots report what their agent does": both slot scripts contain `reported`,
`stalledAfterMinutes` and `--report` / `-Report`; `scripts/lib/status.awk` and `scripts/status.ps1` no longer
contain `slots: none busy` (they print the agent state the slot script gives and contain no rule for it, decision 4); `skills/next/SKILL.md` and `skills/fix/SKILL.md` each contain
`--report`, `-Report`, `slot-taken`, `code-review` and `done`; the schema has `stalledAfterMinutes` with `"default":
30`; `templates/nightmill.example.json` and `README.md` contain `stalledAfterMinutes`, and the README contains
`running`, `stalled` and `unknown`. The existing "config validates" and "schema keywords are supported" sections cover the new
key.

`bash tests/check.sh` stays green.

## Verification

The skills change, so the manual check applies. In a throwaway project with nightmill loaded from a separate checkout
of this branch (`claude --plugin-dir <checkout>`), a board with an Approved throwaway story, and
`"stalledAfterMinutes": 2` in its config:

1. Run `/next`. As soon as the slot's marker gets a new `reported` time (read the marker in `.slots`),
   `/nightmill:status` in a second session shows the slot `busy`, `running`, with `next/implementer` (or
   `next/session`), the step of that report and a `Report` of `0m` or `1m` (under 2 minutes).
2. Kill the first session right after a report. `/status` at once still shows `running`; once the marker's
   `reported` is more than 2 minutes old (check the clock against it; no new report can come), `/status` shows the
   same slot `stalled` with a `Report` of `2m` or more; the slot stays busy and nothing was freed or stopped.
3. In another run that reaches the pull request, the slot shows the step `done`: `running` right after that report,
   `stalled` once it is more than 2 minutes old, and busy until it is freed (after the merge, by the next take,
   `-Reap` or `-Release`).
4. A slot taken by hand with `slot --take` shows `unknown`, `?` and a `Report` of `-` at any age.

The PR's "How verified" lists the four results and the check, and says that auto-merge is off because the change is a
story trigger.

## Not done

- No page in the browser (#68) and no panel beside the chat (#69); they read the porcelain fields of this iteration.
- No starting, stopping or steering of an agent from any view; no automatic freeing or abandoning of a stalled slot
  (#60 frees merged slots only, unchanged).
- No report from `/spec` (it takes no slot; decision 9, `skills/spec/SKILL.md` unchanged), from the `codeReviewer`
  itself (it cannot run a script) or from agents outside the slots; no content of an agent's conversation.
- No heartbeat between reports (no hook, no timer): liveness is the age of the last step report, so a step longer
  than the threshold shows `stalled` while it runs (decision 8).
- No new `stale:` flag; `stalled` is shown in the `Agent` column only.
- No state of its own for a finished run: a slot that waits for its merge after its last report (`done`) shows
  `stalled` once the threshold has passed, by the issue's rule (decision 5), until `--release`, `--reap` or the next
  take frees it.
- No change to the human `slot --status` text, to `--take`'s marker, to `--release`, `--abandon`, `--reap`, the
  warm-up, the ports or `--capacity`.
- No change to the status flow or to who sets a status; no decision record.
- Nothing that leaves the machine.
