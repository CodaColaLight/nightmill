# Iteration 28: a skill waits for room on the machine before it starts an agent

Status: delivered in iteration 28 (PR #102)

Story: #81, epic #47 (Unattended runs). Adds one check, `scripts/room.sh` and `scripts/room.ps1`, that measures free
memory and CPU load with the library of iteration 24 (`scripts/lib/load.*`) and answers whether the machine has room
for one more agent. When it does not, it says why in one line, pauses and tells the skill to call it again, until there
is room or the longest wait has run out. The rule is written once, in "Parallel work" of `skills/workflow/SKILL.md`;
`/next`, `/spec` and `/fix` point to it at every step where they count the agents before a start. Adds five config
keys under `parallel`. Changes `scripts/lib/load.sh`, `scripts/lib/load.ps1` (an optional message prefix and the room
settings; nothing that `scripts/load.*` prints changes), `skills/workflow/SKILL.md`, `skills/next/SKILL.md`,
`skills/spec/SKILL.md`, `skills/fix/SKILL.md`, `schema/nightmill.schema.json`, `templates/nightmill.example.json`,
`README.md`, `CHANGELOG.md`, `tests/lint.sh`, `tests/check.sh` and `.github/workflows/ci.yml`; adds
`scripts/room.sh`, `scripts/room.ps1`, `tests/smoke-room.sh` and `tests/smoke-room.ps1`. No agent, no hook, no change
to the slot scripts, the slot marker, `capacity.json`, `scripts/load.*`, `/status` or the status flow.

**This is a story trigger**: five new config keys ("a new, renamed or removed config key"). The status flow and who
sets a status do not change, and neither does the slot marker. The pull request therefore does **not** auto-merge; it
says so. The skills change (`skills` is in `verification.manualCheckPaths`), so the manual check applies (see
Verification).

**Order.** #80 (iteration 24, the measurement library) and #78 (iteration 22, the effective agent limit) are merged
and on `main`. #44 (iteration 27, spec in review) changes `skills/next/SKILL.md`, `skills/fix/SKILL.md` and
`skills/workflow/SKILL.md`; the workflow skill is in `parallel.hotFiles`, so this iteration is implemented **after #44
has merged**, rebased on it, and never in parallel with it. The edits below name the steps by their headings and
numbers ("The tester", step 1 "Count"; "The code review", step 2 "Count and launch"); when #44 rewords a sentence of
those steps, the pointer sentence of this iteration goes at the end of the step as it then stands. This iteration
does not change the slot scripts (also hot files).

## Goal

A skill that is about to start another agent first checks that the machine has room for it, and waits and says why
when it does not.

## Facts this rests on

- The skills count the agents before every start: "At most the agent limit agents (subagents, slot builds, your own
  builds) at the same time ... Before launching one, count the running ones" (`skills/workflow/SKILL.md`, "Parallel
  work"), and in their "Count" steps: `/next` "The tester" 1, "The implementer" 1, "The code review" 2; `/spec` "The
  spec writer" 2, "The spec review" 2; `/fix` "The tester" 1, "The fixer" 1, "The code review" 2. A fix round is
  launched "as in" the implementer, fixer or writer; `/spec` launches its fix round in "The spec review" step 4 ("a fix
  round (a fresh specWriter, ...)"). After #44 (iteration 27) `/next` and `/fix` gain one more counted launch: the
  tester's dispute launch, "The tester's files" rule 5 ("report `dispute-<k>`, count the agents, record
  `<dispute base>` ..., launch the tester with the dispute prompt"); the producer's launch after a dispute or an undone
  round is a fix round like the others (iteration 27, decision 9). `/next` step 2.2 and `/fix` step 3 take a slot, and
  the take runs `worktrees.warmup` (a slot build). The session's own builds are the manual check (`/next` step 4,
  `/fix` step 5) and, in `/next` step 5, its run of the check before it commits the CHANGELOG entry and the spec's
  status line (the workflow rule "Run the check before every commit").
- The library of iteration 24: `load_measure SAMPLES` (bash) and `Measure-Load -Samples <n>` (PowerShell) measure one
  sample a second, give the mean CPU load in whole percent and the lowest free memory in MB (10^6 bytes), and leave a
  value empty (`$null`) with its reason when it cannot be read. `NIGHTMILL_LOAD_FIXTURE` replaces the readings by a
  file and nothing sleeps. An unusable fixture is return code 2 / a thrown message. The settings reader
  `_load_setting` / `Get-LoadSetting` prints `load: parallel.<key> must be a whole number from <low> to <high>; using
  <default>`; its bash form accepts at most six digits.
- Readings on a Windows 11 machine with 16 GB (iteration 24, Facts): about 6150 MB free at rest. A floor of 8 GB
  (`parallel.memoryPerAgentGB`) would hold every start on such a machine.
- Claude Code runs one shell call of a skill with a time limit (2 minutes unless the call asks for more, at most 10
  minutes), and a bare `sleep` as a tool call may be refused or cut short by the host. A conversation cannot sleep
  between two calls.
- The JSON reader of the bash scripts gives a JSON `true`/`false` the kind `boolean`; both validators accept
  `"type": "boolean"` (`scripts/lib/validate.awk`, `scripts/validate-config.ps1`). The schema has no boolean key yet.
  The validators understand `type`, `properties`, `required`, `items`, `minimum`, `minItems`, `additionalProperties`
  and `enum`; no `maximum`.
- `/status` shows a slot `stalled` when its last report is older than `worktrees.stalledAfterMinutes` (default 30);
  "a step longer than the threshold shows stalled while it runs" (iteration 23, decision 8).

## Decisions

**1. A new script, `scripts/room.sh` / `scripts/room.ps1`, not a mode of `scripts/load.*`.** The load command shows
numbers and a suggestion, is pinned read-only by the lint, takes 10 seconds and reads the slot scripts; the room check
answers yes or no, pauses when the answer is no, has its own exit codes, and reads no slot. Both reuse the library, so
the two measure the same way. Like the load command, the room script writes nothing and calls no slot script.

**2. The pause is inside the script; the loop is in the skill; one call is short.** One call measures once and, when
there is no room, prints the waiting line, pauses `parallel.roomPauseSeconds` (at most 90) and exits 1; the skill then
calls again at once. So the skill never runs a `sleep` of its own, and one call lasts at most the window (3 s) plus the
pause (90 s) plus the reads, under the 2-minute time limit of a shell call without asking for more. A script that waited
the whole longest wait inside one call (30 minutes by default) would exceed any tool time limit. The script cannot
remember between calls (it writes nothing), so the first call prints the moment the wait began (seconds since
1970-01-01 UTC) and the skill passes it back with `--since` / `-Since`; the script compares it with the clock and
ends the wait itself. The skill keeps no clock.

**3. The check's window is 3 samples, a constant, not `parallel.loadWindowSeconds`.** A run of `/next` starts five
agents or more; 10 seconds before each is too slow, one reading is too noisy. Three one-second samples (mean CPU,
lowest free memory) cost 3 seconds. It is a constant of the method like iteration 24's 80%, not a config key (the issue
lists the keys). With a fixture, the fixture's samples are used, as in iteration 24.

**4. Room means: free memory ≥ `parallel.roomMinFreeMB` and CPU load ≤ `parallel.roomMaxCpuPercent`.** Free memory is
iteration 24's "available" memory, the lowest of the window. The floor is its own key, default 2000 MB, and not
`memoryPerAgentGB` × 1000: that key is a long-run average for a count over the total memory, and at 8000 MB it would
hold every start on a 16 GB machine at rest (Facts). The CPU default is 90%, above iteration 24's aim of 80%, so normal
load never holds a start and a saturated machine does. 100 lets the CPU never hold.

**5. An unavailable measure is not checked; the other one still is.** When the CPU load cannot be read the CPU is not
checked and the script says so; when the memory can be read it still holds a start when short. With both unavailable
the check passes. A machine without readings therefore behaves as today. The skill passes the "not checked" line on
once per run of the skill (the script prints it on every call; the skill does not repeat it).

**6. A failed check starts the agent.** A room script that exits 2 (no config, invalid config, unusable fixture) or
cannot run is treated like an unavailable measure: the skill says so once per run and starts, as a failed
`slot --capacity` falls back to the configuration today. Only the longest wait running out stops a task.

**7. The longest wait stops that task with a `Stopped:` line; in `/fix all` it ends the run.** The check itself
commits, pushes, reverts, stops or releases nothing, and the board status stays. In `/next` and `/fix` the slot (taken
or not), the branch and the files stay as they are. `/spec` does its own clean-up of "The spec writer" step 5, as for
its other `Stopped:` lines after a launch that could not happen: it commits an unfinished spec to the local branch
without pushing, or deletes the empty branch the run itself created, and switches back; the story stays at Spec. In
batch mode the next bug would wait on the same
machine for another full wait, so a wait that runs out ends the whole run, as a model that cannot be used does, and the
report lists the bugs not started.

**8. No new report step.** The issue asks for none. While a skill waits, `/status` shows the slot's last report; a
wait longer than `worktrees.stalledAfterMinutes` since that report shows `stalled`, which iteration 23 already allows
for a long step. A wait that runs out reports `stopped` by the existing row "on any `Stopped:` line after the take".

**9. Five config keys under `parallel`, prefixed `room`**, beside the agent limit and the three keys of iteration 24:
`roomCheck` (the switch, a boolean, the first boolean of the schema), `roomMinFreeMB`, `roomMaxCpuPercent`,
`roomPauseSeconds`, `roomMaxWaitMinutes`. MB for the floor, because the manual check sets it just above what is free.

**10. The settings are read in the library.** `_load_setting` / `Get-LoadSetting` get an optional prefix (default
`load`), so the room's warnings say `room:` and `scripts/load.*` prints exactly what it prints today. New functions
`room_settings` / `Get-RoomSettings` read the five keys.

## The command

| | bash | PowerShell |
|---|---|---|
| The first check | `scripts/room.sh` | `scripts/room.ps1` |
| A check while waiting | `scripts/room.sh --since <n>` | `scripts/room.ps1 -Since <n>` |

Run from inside the project (any checkout or worktree of it), like the load command. The lines it prints (below) and
its exit codes are the interface the skills read. Steps, in this order:

1. Arguments: `--since <n>` (`-Since <n>`), at most once. `<n>` matches `^[1-9][0-9]{0,11}$` (1 to 12 digits, no
   leading zero). Anything else, including `-h`, `--help`, `--since 0` and a `<n>` that is not of that form, writes
   `usage: room.sh [--since <seconds>]` (`usage: room.ps1 [-Since <seconds>]`) to standard error and exits 2.
   `room.ps1` parses its own arguments (no typed `param` binding for `-Since`), so in both shells `--since` / `-Since`
   without a value exits 2 with the usage line.
2. The configuration, found and read as `scripts/load.*` does (iteration 24, "The command", step 2), with `room:` for
   `load:` and `room.sh` / `room.ps1` for `load.sh` / `load.ps1` in the messages: `room: run room.sh from inside a
   checkout of the project`, `room: no <path> (run /nightmill:init)`, an invalid config; each exit 2.
3. The settings (see "The config keys"); a wrong value gives one warning on standard error and the default.
4. **Off.** When `parallel.roomCheck` is `false`: print `room: not checked (parallel.roomCheck is false)`, exit 0. Nothing is measured, the fixture is not read, nothing sleeps.
5. The clock: `now` = seconds since 1970-01-01 UTC (`date +%s`; `[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`).
   `since` = the `--since` value, else `now`. `waited` = `now − since`, 0 when negative.
6. The measurement: `load_measure 3` / `Measure-Load -Samples 3`. An unusable fixture: the library's message on
   standard error (it begins `load:`, unchanged), nothing on standard output, exit 2.
7. The judgement, each measure on its own, with `X` = `roomMinFreeMB`, `Y` = `roomMaxCpuPercent`, `F` the free memory,
   `C` the CPU load:
   - memory: unavailable → not checked; `F ≥ X` → ok; else **short**.
   - CPU: unavailable → not checked; `C ≤ Y` → ok; else **high**.
   - Neither short nor high → **room**, exit 0.
   - Short or high, and `waited < roomMaxWaitMinutes × 60` → **wait**: print, pause `roomPauseSeconds` seconds
     (`sleep` / `Start-Sleep`), exit 1.
   - Short or high, and `waited ≥ roomMaxWaitMinutes × 60` → **gave up**: print, no pause, exit 3.

   Room is judged before the clock: a check that finds room starts the agent however long the wait was.

**Exit codes:** 0 start (room, off, or nothing that could be checked holds it); 1 no room yet, the script has paused,
call again with `--since`; 2 usage error, no checkout, no or invalid config, unusable fixture; 3 the longest wait ran
out, start nothing. A warning about a config value does not change the exit code.

### What it prints

Standard output only, these lines and nothing else. The details: memory short is `free memory <F> MB, limit at least <X> MB`; CPU high is `CPU <C>%, limit at most <Y>%`;
both are joined by `; `, memory first. `<what>` is `memory`, `CPU` or `memory and CPU`. `<w>` = `⌊waited / 60⌋`,
`<m>` = `roomMaxWaitMinutes`, `<p>` = `roomPauseSeconds`.

First, one line per unavailable measure, memory first:

```
room: free memory not checked: unavailable (<reason>)
room: CPU load not checked: unavailable (<reason>)
```

Then exactly one result:

| Result | Lines |
|---|---|
| room | `room: yes: free memory <F> MB (at least <X>), CPU <C>% (at most <Y>%)`; an unavailable part reads `free memory not checked` or `CPU not checked` |
| wait | `room: waiting for <what>: <details> (waited <w> of <m> min; next check in <p> s)` and `room: call again with --since <since>` (PowerShell: `-Since <since>`) |
| gave up | `room: gave up after <w> min: <details>` |
| off | `room: not checked (parallel.roomCheck is false)` |

Examples (`X` 2000, `Y` 90, pause 60, longest wait 30):

```
room: yes: free memory 6000 MB (at least 2000), CPU 40% (at most 90%)
room: waiting for memory: free memory 1500 MB, limit at least 2000 MB (waited 0 of 30 min; next check in 60 s)
room: call again with --since 1762430000
room: waiting for memory and CPU: free memory 1500 MB, limit at least 2000 MB; CPU 95%, limit at most 90% (waited 4 of 30 min; next check in 60 s)
room: gave up after 30 min: free memory 1500 MB, limit at least 2000 MB
```

## The config keys

Five keys under `parallel`, each optional:

| Key | Type | Default | Used when | Schema |
|---|---|---|---|---|
| `parallel.roomCheck` | boolean | `true` | `true` or `false` | `"type": "boolean"` |
| `parallel.roomMinFreeMB` | integer | 2000 | 1 to 999999 | `"minimum": 1` |
| `parallel.roomMaxCpuPercent` | integer | 90 | 1 to 100 | `"minimum": 1` |
| `parallel.roomPauseSeconds` | integer | 60 | 1 to 90 | `"minimum": 1` |
| `parallel.roomMaxWaitMinutes` | integer | 30 | 1 to 1440 | `"minimum": 1` |

- **Schema**, in `properties.parallel.properties` after `loadWindowSeconds`, no `maximum`:
  - `"roomCheck": { "type": "boolean", "default": true, "description": "Whether /next, /spec and /fix check that the
    machine has room (scripts/room.*: free memory and CPU load) before they start an agent, and wait while it has not.
    false starts agents as before." }`
  - `"roomMinFreeMB": { "type": "integer", "minimum": 1, "default": 2000, "description": "The free memory, in MB of
    10^6 bytes (1 to 999999), below which scripts/room.* holds the start of another agent." }`
  - `"roomMaxCpuPercent": { "type": "integer", "minimum": 1, "default": 90, "description": "The CPU load, in percent
    (1 to 100), above which scripts/room.* holds the start of another agent. 100: the CPU never holds a start." }`
  - `"roomPauseSeconds": { "type": "integer", "minimum": 1, "default": 60, "description": "Seconds scripts/room.*
    pauses before the next check while there is no room (1 to 90)." }`
  - `"roomMaxWaitMinutes": { "type": "integer", "minimum": 1, "default": 30, "description": "The longest a skill waits
    for room, in minutes (1 to 1440); then it stops that task and starts nothing." }`
- **Example template**: in `parallel` of `templates/nightmill.example.json`, after `loadWindowSeconds`:
  `"roomCheck": true`, `"roomMinFreeMB": 2000`, `"roomMaxCpuPercent": 90`, `"roomPauseSeconds": 60`,
  `"roomMaxWaitMinutes": 30`. This repository's own `.claude/nightmill.json` is not changed (the defaults apply).
- **README**, the configuration table (see README).
- **Read by** the library only, for the room script. An integer key is used as in iteration 24 ("The config keys":
  a whole number without sign, fraction or exponent, within the range); otherwise the default and one line on standard
  error, `room: parallel.<key> must be a whole number from <low> to <high>; using <default>`. `roomCheck` is used when
  it is a JSON `true` or `false` (bash: kind `boolean`; PowerShell: a `[bool]`); otherwise (`"false"`, `0`, `1`) the
  default and `room: parallel.roomCheck must be true or false; using true`. Absent or `null`, or no `parallel`: the
  default, nothing said. The warnings come in the order of the table.
- The previous version ignores the keys; its validator warns `unknown key` for them (not an error).

## The library

Both files keep their header and gain these lines in it.

**`scripts/lib/load.sh`:** `_load_setting KEY LOW HIGH DEFAULT [PREFIX]`, the prefix of the warning, default `load`
(every existing call is unchanged). New:

| Function | Sets |
|---|---|
| `room_settings` | `ROOM_ON` (`true` or `false`), `ROOM_MIN_FREE`, `ROOM_MAX_CPU`, `ROOM_PAUSE`, `ROOM_MAX_WAIT` (warnings on standard error, prefix `room`) |

**`scripts/lib/load.ps1`:** `Get-LoadSetting` gains `[string]$Prefix = "load"`. New:

| Function | Returns |
|---|---|
| `Get-RoomSettings $Config` | an object with `On` (`[bool]`), `MinFree`, `MaxCpu`, `Pause`, `MaxWait` |

`load_settings`, `load_measure`, `load_suggest` and their PowerShell twins do not change; `scripts/load.*` prints the
same as before (its smoke tests are unchanged and stay green).

## The rule in the workflow skill

`skills/workflow/SKILL.md`, "Parallel work": one new bullet directly after the bullet that begins "At most the agent
limit agents", in exactly these words and line breaks. The lint greps line by line, so each pinned phrase
(`scripts/room.ps1`, `scripts/room.sh`, `Stopped: no room on this machine`,
`never changes the agent limit, stops an agent or releases a slot`) stays on one line of the skill:

```markdown
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
```

The order is: the count, the room check, the step report of the launch (`write-tests`, `implement`, `code-review`,
`fix-round-<k>`), the launch. The one exception is the dispute step `dispute-<k>` of "The tester's files" rule 5
(iteration 27), which is reported before the count. So while a skill waits, `/status` shows the slot's previous step
(at a dispute, `dispute-<k>`). Nothing else in the workflow skill changes.

## The pointers in the skills

One sentence, the same everywhere, in exactly these words:

```markdown
Then check the room on the machine (**Parallel work** in the `workflow` skill).
```

For a take and a manual check:

```markdown
Before it, check the room on the machine (**Parallel work** in the `workflow` skill).
```

For the session's run of the check in `/next` step 5:

```markdown
Before you run the check for that commit, check the room on the machine (**Parallel work** in the `workflow` skill).
```

The fix round of `/spec` "The spec review" step 4 takes the words its row gives. The phrase
`check the room on the machine` stays on one line in every pointer (the lint counts it line by line). The
three skills name neither `room.sh`, `room.ps1` nor a `room` key: the rule lives in the workflow skill only. The steps
and rules are named as they stand after #44 has merged.

| Skill | Where | Sentence | A wait that runs out leaves |
|---|---|---|---|
| `/next` | step 2.2, before "Take a slot" | Before it | status In progress, no slot taken |
| `/next` | "The tester", 1. Count, at the end | Then | status In progress, the slot taken |
| `/next` | "The implementer", 1. Count, at the end (also each fix round, launched "as in" it, and the implementer's launch after a dispute or an undone round) | Then | status In progress, the slot taken, the tester's files uncommitted |
| `/next` | "The tester's files", rule 5, directly after "count the agents" | Then | status In progress, the slot taken, the implementer's commits on the local branch, the disputed files uncommitted |
| `/next` | "The code review", 2. Count and launch, after "Count the agents as for the implementer." | Then | status In progress, the slot taken, the commits on the local branch, nothing pushed or opened |
| `/next` | step 4, before "do `verification.manualCheckText` yourself" | Before it | as for the code review |
| `/next` | step 5, after "Rebase on `origin/<git.baseBranch>`; on a CHANGELOG conflict keep both entries in iteration order." | Before you run the check | as for the code review, the CHANGELOG entry and the spec's status line uncommitted |
| `/spec` | "The spec writer", 2. Count, at the end | Then | status Spec; the clean-up of "The spec writer" step 5 (an unfinished spec committed to the local branch and not pushed, or the empty branch the run created deleted; back to the branch it came from) |
| `/spec` | "The spec review", 2. Count and launch, after "Count the agents as for the writer." | Then | status Spec; the clean-up of "The spec writer" step 5 |
| `/spec` | "The spec review", 4. Read the block: the words `have been used: a fix round (a fresh` become ``have been used: check the room on the machine (**Parallel work** in the `workflow` skill), then a fix round (a fresh`` | (its own words, given here) | status Spec; the clean-up of "The spec writer" step 5 |
| `/fix` | step 3, before "Work in a slot" | Before it | status In progress, no slot taken |
| `/fix` | "The tester", 1. Count, at the end | Then | status In progress, the slot taken |
| `/fix` | "The fixer", 1. Count, at the end (also each fix round, and the fixer's launch after a dispute or an undone round) | Then | status In progress, the slot taken, the tester's files uncommitted |
| `/fix` | "The tester's files", rule 5, directly after "count the agents" | Then | as in `/next` |
| `/fix` | "The code review", 2. Count and launch, after "Count the agents as for the fixer." | Then | as in `/next` |
| `/fix` | step 5, before the manual check | Before it | as for the code review |

The last column is what the rule leaves at that point: in `/next` and `/fix` what "stay as they are" means, in `/spec`
the clean-up of "The spec writer" step 5 that the rule names; the skills gain no text for it. In a slot,
the `Stopped:` line reports `stopped` by the existing row of "Reporting the steps". In "The tester's files" rule 5,
#44 reports `dispute-<k>` before the count, so during a wait there `/status` shows `dispute-<k>`; this iteration does not
move that report.

`/fix`, "Batch mode", the bullet "One producer at a time" gains at its end: `A wait for room that runs out is not a
skip either: it ends the run in the same way.`

## README

- "What is in the plugin": a row after the load scripts, `scripts/room.ps1`, `scripts/room.sh` | Before `/next`,
  `/spec` and `/fix` start an agent: checks free memory and CPU load, and pauses while the machine has no room. Changes
  nothing.
- Configuration table, the `parallel` row, at the end: "; and for the room check before each start
  (`scripts/room.*`) whether it runs (`roomCheck`, default true), the free memory it needs (`roomMinFreeMB`, default
  2000), the highest CPU load (`roomMaxCpuPercent`, default 90), the pause between checks (`roomPauseSeconds`, default
  60) and the longest wait (`roomMaxWaitMinutes`, default 30)".
- "Why slots" gains, after "Is the machine used well?", a subsection **"Room for one more agent"**: what is checked
  (free memory at least `roomMinFreeMB`, 2000 MB by default, and CPU load at most `roomMaxCpuPercent`, 90% by default,
  over 3 one-second samples, with the readers of the load command) and when (before every subagent, take and manual
  check of `/next`, `/spec` and `/fix`, after the agent count); what a skill says while it waits (the `room: waiting`
  line), the pause (60 s) and the longest wait (30 min), after which the skill stops that task and starts nothing
  (`/fix all` ends its run); that a measure it cannot take is not checked and said once; that the check never changes
  the agent limit, stops an agent or frees a slot; that a slot whose skill waits longer than `stalledAfterMinutes`
  shows stalled in `/status`; the two commands; and how to switch it off:
  `"parallel": { "roomCheck": false }`.
- "Developing nightmill": `bash tests/smoke-room.sh   # room.sh against a fixture of readings` and
  `powershell -ExecutionPolicy Bypass -File tests/smoke-room.ps1`.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 28 (#81): a skill waits for room on the machine
before it starts an agent. ...` naming `scripts/room.sh` / `scripts/room.ps1` and `--since`, the rule
(free memory ≥ `roomMinFreeMB`, CPU ≤ `roomMaxCpuPercent`, 3 samples), the exit codes 0/1/2/3, the pause in the script
and the loop in the skill, the `Stopped:` line when the longest wait runs out (`/fix all` ends its run), unavailable
measures not checked and said once, the rule in "Parallel work" with pointers in `/next`, `/spec` and `/fix`, the five
keys with their defaults, that the check never changes the agent limit, stops an agent or frees a slot, and that the
keys are ignored by the previous version.

## Tests

Each acceptance criterion of #81 is a test or a manual scenario. Names are the behaviour protected.

**`tests/smoke-room.sh` and `tests/smoke-room.ps1`**, the same cases in both. Every call that measures sets
`NIGHTMILL_LOAD_FIXTURE`. The file builds a throwaway repository (`git init`, a `.claude/nightmill.json` with
`github`, `maintainer`, `verification`, and `parallel` with `"roomPauseSeconds": 1` unless a case says otherwise) and
writes fixture files of three samples into its temporary folder: **ok** (CPU 30, 40, 50; free 6000, 6500, 7000 of
16000), **short** (CPU 40 each; free 2500, 1500, 3000 of 16000), **high** (CPU 95 each; free 6000 each of 16000),
**both** (CPU 95; free 1500), and, each on the samples of **ok** (CPU 30, 40, 50; free 6000, 6500, 7000 of 16000),
**cpu-gone** (sample 2 CPU `-`), **mem-gone** (sample 1 free `-`), **all-gone** (sample 1 free `-` and sample 2 CPU `-`).

1. **Room**: ok gives exit 0 and exactly `room: yes: free memory 6000 MB (at least 2000), CPU 40% (at most 90%)`.
2. **No room, memory**: short gives exit 1, the line `room: waiting for memory: free memory 1500 MB, limit at least
   2000 MB (waited 0 of 30 min; next check in 1 s)` (the lowest sample counts) and `room: call again with --since <n>`
   (`-Since <n>`) with `<n>` within 5 of the clock before the call; the call lasts at least 1 s (it paused).
3. **No room, CPU and both**: high gives `waiting for CPU: CPU 95%, limit at most 90%`; both gives `waiting for memory
   and CPU:` with both details, memory first; each exit 1.
4. **The limits are config values**: short with `"roomMinFreeMB": 1000` is room; high with `"roomMaxCpuPercent": 100`
   is room; ok with `"roomMinFreeMB": 999999` waits for memory.
5. **Wait, then room**: a call on short prints `--since <n>`; a second call with `--since <n>` on ok exits 0 with the
   room line.
6. **The longest wait**: short with `--since <now − 1700>` exits 1 and says `waited 28 of 30 min`; with
   `"roomPauseSeconds": 90` and `--since <now − 1800>` exits 3, prints only
   `room: gave up after 30 min: free memory 1500 MB, limit at least 2000 MB` and returns within 30 s (no pause); with `"roomMaxWaitMinutes": 1` and
   `--since <now − 60>` exits 3 with `gave up after 1 min`. Ok with `--since <now − 3600>` exits 0 (room comes first).
   A `--since` in the future counts as waited 0.
7. **Unavailable is not checked and said**: cpu-gone gives `room: CPU load not checked: unavailable (sample 2 has no
   CPU reading)` and `room: yes: free memory 6000 MB (at least 2000), CPU not checked`, exit 0; mem-gone with a short
   CPU (a fixture with CPU 95 and free `-` in sample 1) gives the memory line and waits for CPU, exit 1; all-gone gives
   both lines and `room: yes: free memory not checked, CPU not checked`, exit 0.
8. **Switched off**: `"roomCheck": false` and `"roomPauseSeconds": 90` with short, and with `NIGHTMILL_LOAD_FIXTURE`
   naming a missing file, gives exit 0, exactly `room: not checked (parallel.roomCheck is false)`, and returns within
   30 s (no pause).
9. **Unusable config values fall back**, each on the **ok** fixture (nothing pauses, so a fallback to the 60 s default
   never sleeps): `0`, `-1`, `8.5`, `"60"`, `true` and `91` for `roomPauseSeconds`; `0` and `101` for
   `roomMaxCpuPercent`; `0` and `1000000` for `roomMinFreeMB`; `0` and `1441` for `roomMaxWaitMinutes`; `"false"`, `0`
   and `1` for `roomCheck`: the warning line on standard error, exit 0, and the default in force where the room line
   shows it (`at least 2000`, `at most 90%`; `roomCheck` measured, not off). For `roomMaxWaitMinutes` also short with
   `--since <now − 1800>`: `gave up after 30 min`, exit 3, no pause. `null` and an absent key: no warning.
10. **Errors**: an unknown option, `--since x`, `--since 0`, `--since 0123`, a 13-digit `--since` and `--since` without
    a value exit 2 with the usage line; outside a git
    checkout exits 2; a repository without `.claude/nightmill.json` exits 2 with `run /nightmill:init`; an unusable
    fixture (a missing file, one sample) exits 2 with the library's message and nothing on standard output.
11. **Nothing is changed**: after all cases the config is byte for byte as written, the output of
    `git status --porcelain --untracked-files=all` of the throwaway repository is the same as before the first case,
    and the script created no `.slots` folder.

`tests/smoke-load.sh` and `tests/smoke-load.ps1` are unchanged and stay green (the prefix argument changes no output).

**`tests/check.sh`** runs `smoke-room.sh` with the bash smoke tests and `smoke-room.ps1` with the PowerShell ones;
**`.github/workflows/ci.yml`** gets `bash tests/smoke-room.sh` in the bash job (after jq is hidden) and
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-room.ps1` in the PowerShell job.

**`tests/lint.sh`**, new section "== room is wired":

- `scripts/room.sh`, `scripts/room.ps1`, `tests/smoke-room.sh` and `tests/smoke-room.ps1` exist.
- The two room scripts only read and hold back: outside comment lines neither contains any word of the load pin
  (`Set-Content` ... `--reap`, a `gh` call) nor `slot.sh`, `slot.ps1`, `--capacity`, `-Capacity`, `Stop-Process`,
  `taskkill` or a `kill` command (`(^|[^A-Za-z0-9_-])kill( |$)`).
- Both room scripts contain `load_measure 3` / `Measure-Load -Samples 3`, `room_settings` / `Get-RoomSettings`, and
  `--since` / `Since`.
- The schema has the five keys: `roomCheck` of type `boolean` with default `true` and a description; the four integers
  with a description, defaults 2000, 90, 60, 30 and minimum 1; `templates/nightmill.example.json` has the five with the
  schema defaults.
- `skills/workflow/SKILL.md` contains `scripts/room.ps1`, `scripts/room.sh`, `Stopped: no room on this machine` and
  `never changes the agent limit, stops an agent or releases a slot`.
- `skills/next/SKILL.md`, `skills/spec/SKILL.md` and `skills/fix/SKILL.md` each contain `check the room on the machine`
  on at least that many lines (`/next` seven: step 2.2, "The tester", "The implementer", "The tester's files" rule 5,
  "The code review", steps 4 and 5; `/fix` six: step 3, "The tester", "The fixer", "The tester's files" rule 5, "The
  code review", step 5; `/spec` three: "The spec writer", "The spec review" steps 2 and 4) and none contains `room.sh`, `room.ps1` or `roomMin`.
- The README contains `room.sh`, `room.ps1` and the five key names.
- Both smoke tests contain `NIGHTMILL_LOAD_FIXTURE`; `tests/check.sh` and `.github/workflows/ci.yml` contain
  `smoke-room`.

CI runs shellcheck at warning level on `scripts/*.sh`, `scripts/lib/*.sh` and `tests/*.sh`: write quoted words in
assignments (`result="gave-up"`, `state="room"`).

The existing sections cover the rest: "config validates" (the example with the new keys, the first boolean), "schema
keywords are supported", "bash files do not use jq" and "shell". `bash tests/check.sh` stays green.

## Verification

The skills change, so the manual check applies (`verification.manualCheckText`: run the changed skill in a real project
with `claude --plugin-dir <this checkout>`). The issue's own check, as steps, in a test project on its board with an
Approved story and the plugin loaded from this checkout:

1. **Wait and say why.** Read the free memory with `scripts/room.ps1` (or `bash scripts/room.sh`); set
   `"parallel": { "roomMinFreeMB": <that value + 4000>, "roomPauseSeconds": 30, "roomMaxWaitMinutes": 5 }`. Run
   `/next`. Before the take it prints a `room: waiting for memory: free memory <F> MB, limit at least <X> MB ...` line
   and checks again every 30 s; no slot is taken and no agent starts.
2. **Start when there is room.** While it waits, lower `roomMinFreeMB` to 1000. At the next check it takes the slot and
   goes on; each later launch (tester, implementer, code reviewer) passes the check without a waiting line.
3. **The longest wait.** Set the floor high again, run `/next` with `roomMaxWaitMinutes` 1: after about a minute it
   prints `Stopped: no room on this machine to start the slot after 1 min: ...`; the story stays In progress, no slot
   is taken, nothing is pushed.
4. **Off.** With `"roomCheck": false` and the high floor, `/next` starts as before, with no room line.
5. **Nothing changed**: `slot --capacity` shows the same numbers before and after every step.

Steps 1 and 3 are also run once with `/fix` on a Ready bug, and step 1 with `/spec` on a Ready story (the wait comes
before the spec writer). The PR's "How verified" lists the results and says that auto-merge is off because the change is
a story trigger (new config keys).

## Not done

- No change to the agent limit or the slot count, by hand or automatically (#78, the automatic adjustment story); the
  check only holds a start back.
- No pausing, throttling or stopping of an agent that is already running; no check inside a running agent (the
  implementer's or fixer's own runs of the check are not checked).
- No background process, hook or timer that watches the machine; the check runs only at a start.
- No limit from the model provider (rate limits, token budget); no GPU, disk or network measure.
- No new report step and no change to `/status`, the slot scripts, the slot marker, `capacity.json` or
  `scripts/load.*`'s output.
- No room check in `/story`, `/status`, `/init`, `/check` or the `worker` launches outside `/next`, `/spec` and `/fix`.
- No room check before the check that `/fix all` finds red on a clean base branch ("The whole run stops"): batch mode
  names no step that runs it, so there is no launch to point to; it is not counted today either.
- No change to the status flow or to who sets a status; no decision record.
