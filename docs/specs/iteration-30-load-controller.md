# Iteration 30: an opt-in controller adjusts the agent limit from the measured load

Status: delivered in iteration 30 (PR #106)

Story: #82, epic #47 (Unattended runs). Adds one controller pass, `scripts/control.sh` and `scripts/control.ps1`, that
measures CPU load and free memory with the library of iteration 24 (`scripts/lib/load.*`), takes that library's
suggested agent limit as its target, applies its own rules (bounds, one step up per cooldown, straight down when memory
is short) and changes the live agent limit, and the slot count when it must keep up, only by calling
`slot --capacity` of iteration 22. It is off by default; `report` prints what it would change and changes nothing;
`apply` changes. One pass is one script call; a small skill, `/nightmill:control`, runs one pass so that
`/loop 5m /nightmill:control` runs it in a session. Adds five config keys under `parallel`. Changes
`scripts/lib/load.sh`, `scripts/lib/load.ps1` (one settings function each), `schema/nightmill.schema.json`,
`templates/nightmill.example.json`, `README.md`, `CHANGELOG.md`, `tests/lint.sh`, `tests/check.sh` and
`.github/workflows/ci.yml`; adds `scripts/control.sh`, `scripts/control.ps1`, `skills/control/SKILL.md`,
`tests/smoke-control.sh` and `tests/smoke-control.ps1`. No agent, no hook, no change to the slot scripts, the slot
marker, the format of `capacity.json`, `scripts/load.*`, `scripts/room.*`, `/status`, the workflow skill or the status
flow.

**This is a story trigger**: five new config keys ("a new, renamed or removed config key"). The status flow and who
sets a status do not change, and neither does the slot marker. The pull request therefore does **not** auto-merge; it
says so. A skill is added (`skills` is in `verification.manualCheckPaths`), so the manual check applies (see
Verification).

**Order.** #78 (iteration 22, `slot --capacity`), #67 (iteration 23, `NIGHTMILL_NOW`, the porcelain fields) and #80
(iteration 24, the measurement library) are merged and on `main`. #81 (iteration 28, the room check) is being
implemented now; its code is not on `main`. It changes `scripts/lib/load.*` (the prefix argument of the settings
reader that this iteration uses), the schema (five `room` keys after `loadWindowSeconds`, where this iteration's keys
follow), the example template, the README's tables and "Why slots", the lint and the workflow skill. The schema is in
`parallel.hotFiles` and `parallel.doNotPair` forbids two tasks that both change it, so this iteration is implemented
**after #81 has merged**, rebased on it, and never in parallel with it. It builds on #81's spec text as written
(`docs/specs/iteration-28-machine-room.md`, "The library"); if #81 merges the prefix argument in another form, the
settings functions below use that form and the warning texts below stay as given. The controller does not call the
room check and does not depend on its code: between two passes the room check keeps holding back each start while the
machine has no room, which is why a pass every few minutes is enough. #45 (iteration 29, spec merged) changes the
code reviewer, `skills/next`, `skills/fix` and the workflow skill; this iteration changes none of those and no hot
file other than the schema, so it may run beside #45 (the CHANGELOG entries are kept in iteration order on a conflict).

## Goal

An opt-in controller adjusts the agent limit (and the slot count, if it must keep up) within bounds the maintainer
sets, based on the machine's measured load, without ever stopping a running agent.

## Facts this rests on

- `slot.sh --capacity [--slot-count N] [--agent-limit M] [--porcelain]` / `slot.ps1 -Capacity [-SlotCount N]
  [-AgentLimit M] [-Porcelain]` (iteration 22) validates every value (a whole number from 1 to 99) before it writes,
  writes `<worktrees.root>/.slots/capacity.json` through a temporary file in the same folder moved over the old one,
  keeps only the keys that were set and writes `since`, the local wall-clock time of the last change
  (`YYYY-MM-DDTHH:MM:SS`: bash `date +%Y-%m-%dT%H:%M:%S`, PowerShell `(Get-Date).ToString("s")`). `--clear` removes the
  file. The live value wins over `WORKER_SLOTS` and the configuration. With `--porcelain` it prints `slots TAB <n> TAB
  <source> TAB <config>` and `agents TAB <m> TAB <source> TAB <config>`; with values and `--porcelain` it sets first
  and prints the new state. It never edits `.claude/nightmill.json`, never touches a marker or a worktree, and a
  lowered agent limit stops no running agent (iteration 22, decisions 5 and 6). An unusable `capacity.json` is ignored
  with the note `slot: capacity.json: <reason>; using the configuration` on standard error. Every run of the slot
  script creates the worktrees root folder when it is missing (`mkdir -p`); `scripts/load.*` live with that.
- `slot --status --porcelain` prints one line per listed slot whose second field is `busy` or `free`; a retiring busy
  slot is listed too (iterations 22 and 23).
- The library of iteration 24, sourced after `scripts/lib/json.sh` with the config loaded (bash) or dot-sourced
  (PowerShell): `load_settings` / `Get-LoadSettings` (window, ceiling, memory per agent; warnings begin `load:`),
  `load_measure SAMPLES` / `Measure-Load -Samples <n>` (mean CPU, lowest free memory, total; empty or `$null` with a
  reason when unavailable; return code 2 / a thrown message for an unusable fixture), `load_suggest BUSY` /
  `Get-LoadSuggestion` (`P`, the reason key `ceiling`, `memory-short`, `memory-total`, `memory-free`, `cpu-other` or
  `cpu`, and the `why` text; empty when a measurement is unavailable). `P` is never below 1 nor above
  `parallel.maxSuggestedAgents` (default 4). `NIGHTMILL_LOAD_FIXTURE` replaces the readings by a file of samples and
  nothing sleeps. `scripts/load.*` source the library the same way and are pinned read-only by the lint, which forbids
  `--agent-limit`, `--slot-count`, `-AgentLimit`, `-SlotCount` in them and in the library.
- After #81: `_load_setting KEY LOW HIGH DEFAULT [PREFIX]` / `Get-LoadSetting ... [-Prefix]` print
  `<prefix>: parallel.<key> must be a whole number from <low> to <high>; using <default>`; the bash form accepts at most
  six digits.
- `NIGHTMILL_NOW` (iteration 23): seconds since 1970 with the local time taken as UTC; when set it is "now" in the slot
  scripts and `/status`, which turn a local `YYYY-MM-DDTHH:MM:SS` into seconds with the arithmetic of `stamp` in
  `lib/status.awk` (`epoch_of` in `slot.sh`, `Get-Stamp` in `slot.ps1`), so both shells agree to the second. Under
  PowerShell 7 `ConvertFrom-Json` turns such a text into a date; `slot.ps1` formats it back with `ToString("s")`.
- The bash JSON reader gives a string the kind `string`. Both validators support `enum` (`scripts/lib/validate.awk`,
  `scripts/validate-config.ps1`), case-sensitive; the lint section "schema keywords are supported" allows it. The schema
  has no `enum` yet and no `maximum` is allowed.
- `/loop` runs a prompt or a slash command again and again in the session, at a given interval (`/loop 5m /foo`) or
  self-paced when the interval is left out; it belongs to the session and ends with it. The skills name the plugin's
  scripts with `${CLAUDE_PLUGIN_ROOT}` (`/status`, `/models`); a prompt typed into `/loop` has no name for the folder of
  the installed plugin.
- Claude Code runs one shell call of a skill with a time limit of 2 minutes unless the call asks for more (iteration 28,
  Facts). A pass measures `parallel.loadWindowSeconds` seconds, at most 60.

## Decisions

**1. A new script, `scripts/control.sh` / `scripts/control.ps1`, not a mode of `scripts/load.*` or of `slot`.** The
load command is pinned read-only by the lint (it may not even contain `--agent-limit`); the slot scripts are hot files
and own the numbers, not a policy about them. The controller is policy: it reads the numbers and the load, decides, and
changes the numbers only by running the slot script of the same plugin as a child (`bash "$here/slot.sh" --capacity
...`; `& (Join-Path $PSScriptRoot "slot.ps1") -Capacity ...`, as `scripts/load.*` call it). It never writes any file
in the project, `capacity.json`, the config or a marker itself. `control.sh` may capture the slot script's standard
error in a temporary directory outside the project made with `mktemp -d` and removed on exit, as `scripts/load.sh`
does. `control.ps1` makes no file at all: it keeps the slot script's standard error in memory as `Invoke-Slot` of
`scripts/load.ps1` does (a `StringWriter` set with `[Console]::SetError` and restored in a `finally`), so the lint's
bans on `New-Item`, `Remove-Item` and `IO.File]::` in `control.ps1` hold.

**2. One pass is one call, and the call is the same for a `/loop` and for an orchestrator.** No argument, no
background process, no timer, no hook. The script measures, decides, changes or does not, prints, and ends. The mode
comes from the config, not from a flag, so a `/loop` and an orchestrator cannot run the same project in two modes.

**3. The target is #80's suggestion; nothing is measured twice.** The script sources the library as `scripts/load.*`
do and calls `load_settings`, `load_measure "$LOAD_WINDOW"` and `load_suggest <busy slots>` (PowerShell:
`Get-LoadSettings`, `Measure-Load -Samples $settings.Window`, `Get-LoadSuggestion`). The window is
`parallel.loadWindowSeconds` (default 10 one-second samples), the window of the load command, not the 3 samples of the
room check: a pass runs every few minutes, not before every start, and a longer window sees through a build's short
peaks. The controller adds only its own rules: bounds, step, cooldown, and fast lowering on memory.

**4. No state file: the time of the last change is `since` of `capacity.json`.** The slot script already writes the
time of every change there, atomically, beside the markers, and the previous version reads it as it does today. The
alternative, a `controller.json` of the controller's own, would be a second record of the same moment, a file the
controller writes (against decision 1), and a file that `report` mode would have to write or not (either way the two
modes would drift apart). With `since`: a value set by hand is the starting point and restarts the cooldown, which is
what a maintainer who just set it wants. `since` is rewritten by every `slot --capacity` set, including a set that
changes nothing and a `--slot-count`-only set, and each such set restarts the agent-limit cooldown. `--clear` removes the file, so after it the controller starts from the
configuration's numbers and the cooldown does not hold. A file that is missing, unusable, without `since` or with a
`since` that is not of the form is "no last change known": the cooldown does not hold. A `since` in the future counts
as age 0 (in the cooldown), as iteration 23 counts a negative age.

**5. "Room for a full window" is the whole pass window, not one reading.** The suggestion is computed from the lowest
free memory and the mean CPU of all samples of the window, and one failed sample makes the measurement unavailable
(iteration 24, decision 3): memory is judged at its lowest sample, CPU at the window's mean, as the library does. So
`P` is above the limit only when the whole window had room in that sense. The controller then raises
by one step, and only when the cooldown since the last change has run out: at most one step up per cooldown.

**6. Lowering is fast on memory and slow on CPU.** Memory that runs out fails badly; a busy CPU only makes work slower.
When the target is below the limit and the reason is a memory reason (`memory-short`, `memory-total`, `memory-free`),
the limit goes to the target at once, any number of steps, in the cooldown too. When the reason is the CPU (`cpu`,
`cpu-other`) or the ceiling (`ceiling`), it goes down one step and only outside the cooldown, like a raise. A burst
therefore lowers the limit at once, and the next raise waits a full cooldown after that lowering: no flapping faster
than one cooldown.

**7. The bounds always hold and act at once.** A limit below `controlMinAgents` is raised to it, a limit above
`controlMaxAgents` is lowered to it (or lower, when memory asks), in the cooldown too, because the maintainer set them.
A lowering to the minimum is never below it, also when memory is short. A minimum above the maximum is unusable: the
maximum is used for both, with a warning.

**8. The slot count is raised only with the agent limit, never lowered.** `S` is the slot script's effective slot
count (`slots` of `--capacity --porcelain`). Only a pass that changes the agent limit to a new `N` may touch the slot
count: when `N > S` the call is `--agent-limit N --slot-count N` (the slot count is raised to `N`); otherwise it is
`--agent-limit N` alone. A pass that keeps the limit (`N = L`) does not call the slot script at all, so it never changes
the slot count, even when `L` already exceeds `S` (for example `parallel.maxAgents` 4 with `worktrees.slots` 2, or a
limit set by hand): that mismatch is not the controller's to correct, and the controller does not produce it. The
controller never lowers the slot count: a slot more than the limit costs a warm worktree on disk and runs nothing,
while the agent limit is what holds work back. So the slot count is never below the busy slots because of the
controller. When `WORKER_SLOTS` is set only in the controller's own environment, `S` is that value, so a raise to
`N <= WORKER_SLOTS` writes no live `slots` value and other sessions keep seeing their own count; the README tells the
user to leave `WORKER_SLOTS` unset where the controller runs, or to accept this.

**9. `report` and `apply` decide the same.** Both read the same numbers, measure the same way and run the same rules;
the only difference is that `apply` runs the slot script with the new values and `report` does not. The decision line
is the same text, with another prefix. Because `report` changes nothing, its next pass sees the same limit and says the
same again, while `apply`'s next pass sees the changed limit and a fresh `since`.

**10. A small skill, `/nightmill:control`, runs one pass.** A `/loop` needs a prompt that finds the script; only a
skill has `${CLAUDE_PLUGIN_ROOT}`. The skill runs the script once and shows its lines; it decides nothing and changes
nothing itself. `/loop 5m /nightmill:control` is the session's controller; an orchestrator calls the script directly.
Both run the same pass.

**11. Five config keys under `parallel`, prefixed `control`**, beside the agent limit and the keys of iterations 24
and 28: `controlMode` (a string with an `enum`, the first in the schema), `controlMinAgents`, `controlMaxAgents`,
`controlCooldownMinutes`, `controlIntervalMinutes`. Off by default; minimum 1 and maximum 4 (`/init`'s upper bound and
the default ceiling of the suggestion); a cooldown of 15 minutes, three default passes.

**12. The pass interval is for whoever runs the passes.** The script reads `controlIntervalMinutes` and prints it in a
second line after every measured pass (`control: next pass in <i> min ...`): a self-paced `/loop` and an orchestrator
read it there; a `/loop` with a fixed interval uses the same number by hand (the README says so). The script itself does
not wait and keeps no clock between calls. An interval longer than the cooldown means at most one step up per pass; an
interval longer than the window is the normal case (the window is seconds, the interval minutes); between passes
nothing watches, and the room check (#81) holds back each start while the machine has no room.

**13. The settings are read in the library**, like #81's `room_settings`: `control_settings` / `Get-ControlSettings`
in `scripts/lib/load.*`, with the prefix `control`. The library stays free of any slot call.

## The command

| | bash | PowerShell |
|---|---|---|
| One pass | `scripts/control.sh` | `scripts/control.ps1` |

Run from inside the project (any checkout or worktree), like the load command. Steps, in this order:

1. **Arguments.** Any argument, including `-h` and `--help`, writes `usage: control.sh` (`usage: control.ps1`) to
   standard error and exits 2. `control.ps1` has no `param` block and checks `$args`.
2. **The configuration**, found and read as `scripts/load.*` do (iteration 24, "The command", step 2), with `control:`
   for `load:` and `control.sh` / `control.ps1` for `load.sh` / `load.ps1`: `control: run control.sh from inside a
   checkout of the project`, `control: no <path> (run /nightmill:init)`, an invalid config; each exit 2.
3. **The controller's settings**, `control_settings` / `Get-ControlSettings` (see "The config keys"); each unusable
   value gives one warning on standard error and its default.
4. **Off.** When the mode is `off`: print `control: off (parallel.controlMode is off); nothing measured or changed` and
   exit 0. Nothing else runs: no slot script, no measurement, the fixture is not read, nothing sleeps.
5. **The load settings**, `load_settings` / `Get-LoadSettings` (their own `load:` warnings, unchanged).
6. **The numbers**, from the slot script of the same plugin, as `scripts/load.*` step 4 does: `--capacity --porcelain`
   gives `L` (line `agents`, field 2) and `S` (line `slots`, field 2); `--status --porcelain` gives `A`, the lines whose
   second field is `busy`. Their standard error passes through. A call that exits non-zero ends the pass with
   `control: slot.sh failed: <its standard error on one line>` (`slot.ps1` in PowerShell), exit 2, before anything is
   measured; nothing was changed.
7. **The last change**: `since` of `<root>/.slots/capacity.json`, where `<root>` is `worktrees.root` relative to the
   main checkout, default `../<folder of the main checkout>-wt`, as the slot scripts resolve it. bash reads it in a
   subshell (`( json_load "$cap" && json_get since )`, so the config stays loaded), errors discarded; PowerShell with
   `ConvertFrom-Json`, a date value formatted back with `ToString("s")`. `age` = now − the seconds of `since` (the
   arithmetic of `epoch_of` / `Get-Stamp`, copied into the script), 0 when negative; unknown when the file is missing or
   unusable, `since` is absent, or not `YYYY-MM-DDTHH:MM:SS`. **Now** is `NIGHTMILL_NOW` when it is 1 to 12 digits,
   else the local clock read the same way (`date +%Y-%m-%dT%H:%M:%S`, `(Get-Date).ToString("s")`) through the same
   arithmetic, so `since` and now are on one scale.
8. **The measurement**: `load_measure "$LOAD_WINDOW"`, then `load_suggest "$A"` (PowerShell: `Measure-Load -Samples
   $settings.Window`, `Get-LoadSuggestion -Load ... -Settings ... -Busy $A`). An unusable fixture: the library's message
   on standard error (it begins `load:`), nothing on standard output, exit 2.
9. **Unavailable.** When the CPU load or the free memory is unavailable, the pass changes nothing (not even the bounds
   of decision 7): it prints the unavailable line and the next-pass line (see "What it prints") and exits 1.
10. **The decision**, see "The rule". It gives `N`, the new agent limit, and the rule word.
11. **Apply.** When the mode is `apply` and `N ≠ L`: run the slot script with `--capacity --agent-limit N`, plus
    `--slot-count N` when `N > S` (PowerShell `-Capacity -AgentLimit N [-SlotCount N]`); the slot count is never
    lowered. Its standard output is not shown; its standard error passes through. When it exits non-zero: `control:
    slot.sh failed: <its standard error on one line>`, exit 2, and no decision line. In `report` mode, and whenever
    `N = L` (a kept pass, also when `L > S`), the slot script is not called again and the slot count is not changed.
12. **Print** the decision line and the next-pass line, exit 0.

**Exit codes:** 0 a pass that decided (a change, a would-be change, a limit kept) or the controller is off; 1 the CPU
load or the free memory is unavailable, nothing changed; 2 a usage error, no checkout, no or invalid config, an unusable
fixture, or a failed slot script (nothing changed by the controller). A warning about a config value does not change
the exit code. Every exit leaves the slot markers, the busy slots, their agents and the config as they were; only exit
0 in `apply` mode can have changed the live numbers, and then the decision line says how.

## The rule

With `L` the agent limit, `S` the slot count, `A` the busy slots, `P`, `R` (the reason key) and `why` from the
suggestion, `m` = `controlMinAgents`, `M` = `controlMaxAgents`, `c` = `controlCooldownMinutes`, `age` from step 7:

```
target  = min(M, max(m, P))                         (the suggestion, inside the bounds)
memory  = R is memory-short, memory-total or memory-free
cooling = age is known and age < c × 60
```

The first that applies:

| # | When | New limit `N` | Rule word |
|---|---|---|---|
| 1 | `L < m` | `m` | `minimum` |
| 2 | `memory` and `target < L` | `target` | `memory` |
| 3 | `L > M` | `M` | `maximum` |
| 4 | `target = L` | `L` (kept) | `at the maximum` when `L = M` and `P > M`; `at the minimum` when `L = m` and `P < m`; else `steady` |
| 5 | `cooling` | `L` (kept) | `cooldown <r> of <c> min left`, `r` = `⌊(c × 60 − age + 59) / 60⌋` |
| 6 | `target > L` | `L + 1` | `room` |
| 7 | `target < L` | `L − 1` | `cpu` when `R` is `cpu` or `cpu-other`; `ceiling` when `R` is `ceiling` |

The step is 1 for rows 6 and 7. Rows 1 to 3 act in the cooldown; rows 6 and 7 do not. The slot count changes only in
a pass that writes a new limit (rows 1, 2, 3, 6 and 7 with `N ≠ L`): it is raised to `N` when `N > S`, and never
lowered. A kept pass (rows 4 and 5) calls no slot script and leaves the slot count as it is, also when `L > S`. Nothing
else is changed: no marker, no worktree, no agent.

## What it prints

Standard output only, these lines and nothing else. `<pre>` is `control: ` in `apply` and
`control (report only, nothing changed): ` in `report`; the rest of a decision line is the same in both modes.

```
<measure> = CPU <C>%, free memory <F> of <T> MB, busy slots <A>, suggested <P>: <why>
```

| Case | Lines |
|---|---|
| a change | `<pre>agent limit <L> -> <N> (<rule>; <measure>)`, with `, slots <S> -> <N>` after `<N>` when the slot count is raised |
| kept | `<pre>agent limit <L> kept (<rule>; <measure>)`, never with a slots part (a kept pass does not change the slot count) |
| unavailable | `<pre>agent limit <L> kept (unavailable; <what>)`, `<what>` being `the CPU load is unavailable (<reason>)`, `the free memory is unavailable (<reason>)` or `the CPU load (<reason>) and the free memory (<reason>) are unavailable` |
| off | `control: off (parallel.controlMode is off); nothing measured or changed` |

After a change, a kept line or an unavailable line, a second line: `control: next pass in <i> min
(parallel.controlIntervalMinutes)`, `<i>` = `controlIntervalMinutes`. The off line stands alone.

Examples (fixtures of "Tests"; defaults `m` 1, `M` 4, `c` 15, interval 5):

```
control: agent limit 2 -> 3, slots 2 -> 3 (room; CPU 10%, free memory 60000 of 64000 MB, busy slots 1, suggested 4: the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more)
control: next pass in 5 min (parallel.controlIntervalMinutes)
control: agent limit 3 -> 1 (memory; CPU 30%, free memory 1000 of 16000 MB, busy slots 2, suggested 1: memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 2 in the slots)
control: agent limit 3 kept (cooldown 14 of 15 min left; CPU 90%, free memory 50000 of 64000 MB, busy slots 2, suggested 1: CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%)
control (report only, nothing changed): agent limit 3 -> 2 (cpu; CPU 90%, free memory 50000 of 64000 MB, busy slots 2, suggested 1: CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%)
control: agent limit 2 kept (unavailable; the CPU load is unavailable (sample 2 has no CPU reading))
```

## The config keys

Five keys under `parallel`, each optional:

| Key | Type | Default | Used when | Schema |
|---|---|---|---|---|
| `parallel.controlMode` | string | `"off"` | `"off"`, `"report"` or `"apply"` | `"enum": ["off", "report", "apply"]` |
| `parallel.controlMinAgents` | integer | 1 | 1 to 99 | `"minimum": 1` |
| `parallel.controlMaxAgents` | integer | 4 | 1 to 99 | `"minimum": 1` |
| `parallel.controlCooldownMinutes` | integer | 15 | 1 to 1440 | `"minimum": 1` |
| `parallel.controlIntervalMinutes` | integer | 5 | 1 to 1440 | `"minimum": 1` |

- **Schema**, in `properties.parallel.properties` after `roomMaxWaitMinutes` (#81's last key), no `maximum`:
  - `"controlMode": { "type": "string", "enum": ["off", "report", "apply"], "default": "off", "description": "The load
    controller (scripts/control.*, /nightmill:control): off does nothing; report measures and prints what it would
    change, changing nothing; apply raises or lowers the live agent limit (and raises the slot count when needed) with
    slot --capacity, within controlMinAgents and controlMaxAgents. It never stops an agent." }`
  - `"controlMinAgents": { "type": "integer", "minimum": 1, "default": 1, "description": "The lowest agent limit the
    load controller sets (1 to 99)." }`
  - `"controlMaxAgents": { "type": "integer", "minimum": 1, "default": 4, "description": "The highest agent limit the
    load controller sets (1 to 99). Its target never exceeds maxSuggestedAgents either." }`
  - `"controlCooldownMinutes": { "type": "integer", "minimum": 1, "default": 15, "description": "Minutes after the
    last change of the live numbers before the load controller raises the agent limit by one more step or lowers it for
    CPU (1 to 1440). Short memory lowers it at once." }`
  - `"controlIntervalMinutes": { "type": "integer", "minimum": 1, "default": 5, "description": "How often the load
    controller should run, in minutes (1 to 1440): the interval for /loop and for an orchestrator. Each pass prints
    it." }`
- **Example template**: in `parallel` of `templates/nightmill.example.json`, after `roomMaxWaitMinutes`:
  `"controlMode": "off"`, `"controlMinAgents": 1`, `"controlMaxAgents": 4`, `"controlCooldownMinutes": 15`,
  `"controlIntervalMinutes": 5`. This repository's own `.claude/nightmill.json` is not changed (the defaults apply: off).
- **README**, the configuration table (see README).
- **Read by** the library only, for the control script. An integer key is used as in iteration 24 ("The config keys":
  a whole number without sign, fraction or exponent, within the range); otherwise the default and one line on standard
  error, `control: parallel.<key> must be a whole number from <low> to <high>; using <default>`. `controlMode` is used
  when it is a JSON string exactly `off`, `report` or `apply` (bash: kind `string`; PowerShell: a `[string]`, compared
  with `-ceq`); otherwise (`"Apply"`, `"on"`, `1`, `true`) `off` and `control: parallel.controlMode must be "off",
  "report" or "apply"; using "off"`. Absent or `null`, or no `parallel`: the default, nothing said. The warnings come in
  the order of the table; then, when the minimum in force is above the maximum in force, `control:
  parallel.controlMinAgents <m> is above parallel.controlMaxAgents <M>; using <M> for both`.
- The previous version ignores the keys; its validator warns `unknown key` for them (not an error). The slot scripts,
  `scripts/load.*`, `scripts/room.*`, `/status`, `/init` and the other skills do not read them.

## The library

Both files keep their header and gain these lines in it.

**`scripts/lib/load.sh`**, new:

| Function | Sets |
|---|---|
| `control_settings` | `CONTROL_MODE` (`off`, `report` or `apply`), `CONTROL_MIN`, `CONTROL_MAX`, `CONTROL_COOLDOWN`, `CONTROL_INTERVAL` (warnings on standard error, prefix `control`) |

**`scripts/lib/load.ps1`**, new:

| Function | Returns |
|---|---|
| `Get-ControlSettings $Config` | an object with `Mode`, `Min`, `Max`, `Cooldown`, `Interval` |

They use `_load_setting ... control` / `Get-LoadSetting ... -Prefix control` for the four integers. Nothing else in the
library changes; `scripts/load.*` and `scripts/room.*` print what they printed (their smoke tests are unchanged and stay
green).

## The skill

`skills/control/SKILL.md`, new, in exactly these words. Each pinned phrase (`scripts/control.ps1`,
`scripts/control.sh`, `control: next pass in`) stays on one line:

```markdown
---
name: control
description: Run one pass of the opt-in load controller - measure CPU and memory, then raise or lower the agent limit within the configured bounds, or only say what it would change. Use in a loop (/loop 5m /nightmill:control) or when asked to adjust the agent limit to the machine's load.
---

Run one pass of the load controller. This skill changes nothing itself: only the script changes the agent limit and
the slot count, and only when `parallel.controlMode` is `apply`.

Run the script of the shell in use, from inside the project (any checkout or worktree), and wait for it (it measures
for `parallel.loadWindowSeconds` seconds, 10 by default):

- PowerShell (Windows): `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/control.ps1"`
- bash: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/control.sh"`

Show the lines it printed, and any warning on standard error, as they are, and add nothing. Exit 0 or 1 ends the pass
(1: it could not measure and changed nothing). Exit 2: show its standard error and end this pass; a loop goes on with
its next pass.

When this runs in a `/loop` without an interval, run the next pass after the minutes of its `control: next pass in`
line.

Do not change the numbers by hand (`slot --capacity`), do not edit the config or a file under `.slots`, do not stop an
agent or free a slot, and do not turn the controller on or off: the maintainer sets `parallel.controlMode`.
```

The skill does not name the config file (the lint would require it to inject it) and reads no config itself.

## README

- "What is in the plugin": a row after `/nightmill:models`, `/nightmill:control` | One pass of the opt-in load
  controller: measures the load and, in `apply` mode, raises or lowers the agent limit within the configured bounds;
  `/loop 5m /nightmill:control` runs it in a session. And a row after the room scripts of #81, `scripts/control.ps1`,
  `scripts/control.sh` | One controller pass: measures like the load command and changes the live agent limit (and
  slot count) only through `slot --capacity`, only in `apply` mode. Stops nothing.
- Configuration table, the `parallel` row, at the end: "; and for the load controller (`scripts/control.*`,
  `/nightmill:control`) its mode (`controlMode`: `off` by default, `report`, `apply`), its bounds (`controlMinAgents`,
  default 1; `controlMaxAgents`, default 4), its cooldown (`controlCooldownMinutes`, default 15) and how often it runs
  (`controlIntervalMinutes`, default 5)".
- "Why slots" gains, after #81's "Room for one more agent", a subsection **"Adjusting the limit to the load"**: the
  three modes (`off` by default: nothing measured or changed; `report`: says what it would change and changes nothing;
  `apply`: changes the live agent limit with `slot --capacity`, like a hand-set value, shown `live` by `slot --status`
  and `/status`); how to run it (`/loop 5m /nightmill:control`, the 5 being `controlIntervalMinutes`, or
  `/loop /nightmill:control`, which paces itself by the `next pass in` line; an orchestrator runs
  `scripts/control.ps1` or `bash scripts/control.sh`); what a pass does (measures over `loadWindowSeconds` like the
  load command, takes its suggestion as the target, keeps it between `controlMinAgents` and `controlMaxAgents`); the
  rules (up one step only after a full window with room and only after `controlCooldownMinutes` since the last change;
  down at once to the target when memory is short; down one step per cooldown when the CPU or the ceiling is the
  limit; the slot count raised to the new limit by any pass that sets the agent limit above the slot count, also when
  that pass lowers the limit but the new limit is still above the slot count, never touched by a pass that keeps the
  limit, and never lowered); that the last change is the time in `capacity.json`, rewritten by every
  `slot --capacity` set (also one that changes nothing or sets only the slot count), so any such set, by hand or not,
  restarts the cooldown and `-Clear` hands the start back to the configuration; to leave `WORKER_SLOTS` unset where the
  controller runs, or to accept that a raise up to that value writes no live slot count; the one-line
  report (old value, new value, the rule and the measure) and the unavailable case (nothing changed, exit 1); that it
  never stops an agent, frees a slot or edits the config, and that busy slots stay busy; that it leaves nothing running
  (the loop ends with the session; the last live values stay until `-Clear`, as for a hand-set value); and, on one line,
  `The controller does not see the API's rate limits, the token budget, or agents outside the slots`, followed by what
  the load command does not see.
- "Developing nightmill": `bash tests/smoke-control.sh # control.sh against fixtures of readings and a fixed clock` and
  `powershell -ExecutionPolicy Bypass -File tests/smoke-control.ps1`.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 30 (#82): an opt-in controller adjusts the agent
limit from the measured load. ...` naming `scripts/control.sh` / `scripts/control.ps1` and `/nightmill:control` (with
`/loop 5m /nightmill:control`), the three modes (off by default, report, apply), the target (the suggestion of the load
command, over its window), the rules (bounds, one step up per cooldown after a full window with room, at once down to
the target when memory is short, one step down per cooldown for CPU or the ceiling, the slot count raised to the new
limit by a pass that sets the agent limit above the slot count, also when that pass lowers the limit, not touched by a
kept pass, and never lowered), the last change read from `since` of `capacity.json`, that it changes the numbers only through `slot
--capacity` and never stops an agent, the one-line report, exit 1 when it cannot measure, the five keys with their
defaults, and that the keys are ignored by the previous version.

## Tests

Each acceptance criterion of #82 is a test or a manual scenario. Names are the behaviour protected.

**`tests/smoke-control.sh` and `tests/smoke-control.ps1`**, the same cases and the same expected lines in both. Every
call that measures sets `NIGHTMILL_LOAD_FIXTURE`; nothing sleeps. The file builds a throwaway repository (`git init`, a
`.claude/nightmill.json` with `github`, `maintainer`, `verification`, `worktrees` with `"root": "../wt"` and
`"slots": 2`, and `"parallel": { "controlMode": "apply" }` unless a case says otherwise), creates `../wt/.slots`, writes
markers (the three-key form) by hand for the busy slots a case names, and writes `capacity.json` by hand with a helper
`cap <agents> <slots> <since>` (keys `slots`, `maxAgents`, `since`). `B` = 1793966400, the seconds of
`2026-11-06T12:00:00` read as UTC; "at `B+n`" means `NIGHTMILL_NOW=B+n` and `since` `2026-11-06T12:00:00`. Fixtures of
three samples, named with their base samples (the scenarios of iteration 24, "The suggestion"):
**roomy** (CPU 5, 10, 15; free 61000, 60000, 62000 of 64000; scenario a: with one busy slot `P` 4, `ceiling`),
**steady** (CPU 20; free 9000 of 16000, three equal; scenario b: with one busy slot `P` 2, `memory-total`),
**short** (CPU 30; free 1000 of 16000, three equal; scenario d: with two busy slots `P` 1, `memory-short`),
**cpu-high** (CPU 90; free 50000 of 64000, three equal; scenario e: with two busy slots `P` 1, `cpu`), and, each on the
samples of **roomy** (CPU 5, 10, 15; free 61000, 60000, 62000 of 64000), **cpu-gone** (sample 2 CPU `-`), **mem-gone**
(sample 1 free `-`), **all-gone** (both).

1. **Off by default**: a config without `controlMode`, and one with `"off"`, each with `NIGHTMILL_LOAD_FIXTURE` naming a
   missing file: exit 0, exactly `control: off (parallel.controlMode is off); nothing measured or changed`, nothing on
   standard error; in a second throwaway repository whose worktrees root does not exist, the root is still not there
   afterwards (no slot script ran).
2. **Raise one step, the slot count keeps up**: one busy slot, no `capacity.json`, roomy: exit 0, exactly the first two
   example lines of "What it prints"; then `slot --capacity --porcelain` prints `slots TAB 3 TAB live TAB 2` and
   `agents TAB 3 TAB live TAB 2`.
3. **Hold in the cooldown**: right after case 2, roomy again without `NIGHTMILL_NOW`: `control: agent limit 3 kept
   (cooldown 15 of 15 min left; ...)` and `capacity.json` byte for byte as case 2 left it. With `cap 2 2`, roomy: at
   `B+60` `cooldown 14 of 15 min left`; at `B+899` `cooldown 1 of 15 min left`; at `B+900` `agent limit 2 -> 3, slots
   2 -> 3 (room; ...)`; at `B−60` (a `since` in the future) `cooldown 15 of 15 min left`. **One step per pass**: `cap 2
   2` at `B+3600`, roomy (`P` 4): `2 -> 3`, not 4. With `"controlCooldownMinutes": 1` at `B+60`: `2 -> 3`.
4. **Lower at once when memory is short**: two busy slots, `cap 3 3` at `B+60` (in the cooldown), short: exactly the
   third example line; `capacity.json` has `maxAgents` 1 and `slots` 3; both markers byte for byte as written. One busy
   slot, `cap 3 3` at `B+60`, steady: `agent limit 3 -> 2 (memory; CPU 20%, free memory 9000 of 16000 MB, busy slots 1,
   suggested 2: memory is the limit: 16000 MB in all holds 2 agents at 8 GB each)`.
5. **Lower slowly for the CPU**: two busy slots, `cap 3 3`, cpu-high: at `B+60` exactly the fourth example line (kept,
   `capacity.json` unchanged); at `B+900` `control: agent limit 3 -> 2 (cpu; ...)`, one step, not 1.
   **The ceiling**: `"controlMaxAgents": 6`, one busy slot, `cap 5 5` at `B+3600`, roomy: `agent limit 5 -> 4 (ceiling;
   ...)`.
6. **Bounds**: `"controlMaxAgents": 3`, one busy slot, `cap 3 3` at `B+3600`, roomy: `agent limit 3 kept (at the
   maximum; ...)`. Default maximum, `cap 5 5` at `B+60`, steady with one busy slot: `agent limit 5 -> 2 (memory; ...)`;
   with roomy instead: `agent limit 5 -> 4 (maximum; ...)`, `slots` stays 5. `"controlMinAgents": 2`, two busy slots,
   short: `cap 3 3` at `B+60` gives `agent limit 3 -> 2 (memory; ...)`; `cap 2 3` gives `agent limit 2 kept (at the
   minimum; ...)`; one busy slot, `cap 1 1` at `B+60`, steady: `agent limit 1 -> 2, slots 1 -> 2 (minimum; ...)`.
   `"controlMinAgents": 5, "controlMaxAgents": 3`: the warning `control: parallel.controlMinAgents 5 is above
   parallel.controlMaxAgents 3; using 3 for both`, and roomy with no `capacity.json` gives `agent limit 2 -> 3, slots
   2 -> 3 (minimum; ...)`.
7. **Steady**: one busy slot, no `capacity.json`, steady: `control: agent limit 2 kept (steady; CPU 20%, free memory
   9000 of 16000 MB, busy slots 1, suggested 2: memory is the limit: 16000 MB in all holds 2 agents at 8 GB each)`,
   exit 0, and no `capacity.json` is created.
   **The slot count is raised only by a new limit above it**: one busy slot, `cap 2 1` at `B+3600`, steady: `agent limit 2 kept
   (steady; ...)` with no slots part and `capacity.json` byte for byte (a kept pass with `L > S` calls nothing); one
   busy slot, `cap 3 2` at `B+60`, roomy: `agent limit 3 kept (cooldown 14 of 15 min left; ...)` with no slots part and
   `capacity.json` byte for byte. One busy slot, `cap 2 1` at `B+3600`, roomy: `agent limit 2 -> 3, slots 1 -> 3 (room;
   ...)`, and `capacity.json` has `maxAgents` 3 and `slots` 3; `cap 2 3` at `B+3600`, roomy: `agent limit 2 -> 3 (room;
   ...)` with no slots part, `slots` stays 3. Two busy slots, `cap 3 2` at `B+60`, short: `agent limit 3 -> 1 (memory;
   ...)` with no slots part, `slots` stays 2. A lowering pass whose new limit is still above the slot count: four busy
   slots (markers for slots 1 to 4; slots 3 and 4 are listed as retiring busy slots), `cap 5 2` at `B+60`, short:
   `agent limit 5 -> 3, slots 2 -> 3 (memory; CPU 30%, free memory 1000 of 16000 MB, busy slots 4, suggested 3: memory
   is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 4 in the slots)`, and `capacity.json` has
   `maxAgents` 3 and `slots` 3.
8. **A pass that cannot measure changes nothing and says so**: cpu-gone gives exit 1 and exactly the last example line
   and the next-pass line; mem-gone `the free memory is unavailable (sample 1 has no memory reading)`; all-gone `the CPU
   load (sample 2 has no CPU reading) and the free memory (sample 1 has no memory reading) are unavailable`. With
   `cap 6 6` (above the maximum) and cpu-gone: `agent limit 6 kept (unavailable; ...)` and `capacity.json` byte for byte.
9. **Report only decides the same and changes nothing**: for the inputs of case 2, the first pass of case 4, case 5 at
   `B+900`, the maximum and minimum rows of case 6 and case 8 (cpu-gone), with `"controlMode": "report"`: the same exit
   code, the decision line equal to `control (report only, nothing changed): ` followed by the apply line without its
   `control: ` prefix, the same next-pass line, and `capacity.json` byte for byte as before (or still absent).
10. **The last change unknown**: roomy, one busy slot, `cap 2 2` written without `since`: `2 -> 3` at once (no
    cooldown); `since` `"yesterday"`: the same; `capacity.json` that is not JSON: the slot script's note
    `slot: capacity.json: not valid JSON; using the configuration` on standard error, `agent limit 2 -> 3, slots 2 -> 3
    (room; ...)`, exit 0.
11. **The interval**: `"controlIntervalMinutes": 10` gives `control: next pass in 10 min
    (parallel.controlIntervalMinutes)`.
12. **Unusable config values fall back**, each on steady with one busy slot and no `capacity.json` (kept, so the
    defaults show in the line or do not matter): `"Apply"`, `"on"`, `1` and `true` for `controlMode`: the warning and
    the off line; `0` and `100` for `controlMinAgents` and `controlMaxAgents`; `0`, `1441`, `1.5` and `"15"` for
    `controlCooldownMinutes`; `0`, `1441` and `"5"` for `controlIntervalMinutes` (the next-pass line says 5): the warning
    line on standard error, exit 0. For `controlCooldownMinutes` also `cap 2 2` at `B+60` with roomy: `cooldown 14 of 15
    min left`. `null` and an absent key: no warning.
13. **Errors**: an argument (`--apply`, `-h`) exits 2 with the usage line; outside a git checkout exits 2; a repository
    without `.claude/nightmill.json` exits 2 with `run /nightmill:init`; an unusable fixture (a missing file, one
    sample) exits 2 with the library's message and nothing on standard output; `WORKER_SLOTS=x` exits 2 with
    `control: slot.sh failed: WORKER_SLOTS must be a number from 1 to 99` (`slot.ps1` and its own text in PowerShell).
    Each leaves `capacity.json` as it was.
14. **Nothing else is changed**: after all cases the config is byte for byte as each case wrote it, every marker is
    byte for byte as written, `.slots` holds only the markers and `capacity.json` (no temporary file), and
    `git status --porcelain --untracked-files=all` of the throwaway repository is the same as before the first case.

`tests/smoke-load.*`, `tests/smoke-room.*` and `tests/smoke-slot.*` are unchanged and stay green.

**`tests/check.sh`** runs `smoke-control.sh` with the bash smoke tests and `smoke-control.ps1` with the PowerShell
ones; **`.github/workflows/ci.yml`** gets `bash tests/smoke-control.sh` in the bash job (after jq is hidden) and
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-control.ps1` in the PowerShell job.

**`tests/lint.sh`**, new section "== control is wired":

- `scripts/control.sh`, `scripts/control.ps1`, `skills/control/SKILL.md`, `tests/smoke-control.sh` and
  `tests/smoke-control.ps1` exist.
- The two control scripts change the numbers only through the slot script and stop nothing: outside comment lines
  (lines whose first non-blank character is `#`, in both scripts and for every word list of this item)
  neither contains `Set-Content`, `Out-File`, `Add-Content`, `Remove-Item`, `New-Item`, `Move-Item`, `Copy-Item`,
  `WriteAll`, `IO.File]::`, `json_marker`, `--clear`, `--take`, `--release`, `--abandon`, `--reap`, `--report`,
  `Stop-Process`, `taskkill`, a `gh` call (`(^|[^A-Za-z0-9_-])gh +[a-z]`, the pattern of the load lint), a `kill`
  command (`(^|[^A-Za-z0-9_-])kill( |$)`) or a `mv`, `cp`, `tee` or `mkdir` command
  (`(^|[^A-Za-z0-9_-])(mv|cp|tee|mkdir) `); `control.ps1` contains none of the whole, case-sensitive words `Clear`,
  `Take`, `Release`, `Abandon`, `Reap`, `Report` (a splatted slot call names its parameters without a dash).
- `control.sh` contains `--capacity`, `--agent-limit`, `--slot-count`, `load_measure`, `load_suggest`,
  `control_settings` and `NIGHTMILL_NOW`; `control.ps1` contains `Capacity`, `AgentLimit`, `SlotCount`, `Measure-Load`,
  `Get-LoadSuggestion`, `Get-ControlSettings` and `NIGHTMILL_NOW`.
- `scripts/lib/load.sh` contains `control_settings` and `controlMode`; `scripts/lib/load.ps1` contains
  `Get-ControlSettings` and `controlMode`; neither contains `--agent-limit` (the load pin already holds).
- The schema has `parallel.controlMode` of type `string` with the `enum` `off`, `report`, `apply` in that order, default
  `off` and a description; `controlMinAgents`, `controlMaxAgents`, `controlCooldownMinutes`, `controlIntervalMinutes` of
  type `integer` with a description, defaults 1, 4, 15, 5 and minimum 1; `templates/nightmill.example.json` has the five
  with the schema defaults.
- `skills/control/SKILL.md` contains `scripts/control.ps1`, `scripts/control.sh` and `control: next pass in`, and
  contains none of `nightmill.json`, `--agent-limit`, `-AgentLimit`, `--slot-count`, `-SlotCount`.
- The README contains `/nightmill:control`, `control.sh`, `control.ps1`, `/loop`, the five key names and
  `The controller does not see`.
- Both smoke tests contain `NIGHTMILL_LOAD_FIXTURE` and `NIGHTMILL_NOW`; `tests/check.sh` and
  `.github/workflows/ci.yml` contain `smoke-control`.

CI runs shellcheck at warning level on `scripts/*.sh`, `scripts/lib/*.sh` and `tests/*.sh`: quote hyphenated words in
assignments (`rule="at the maximum"`, `mode="report"`), never leave a bare word such as `done` where shellcheck reads a
keyword, and quote every expansion.

The existing sections cover the rest: "skills" (the new skill's frontmatter), "config validates" (the example with the
new keys, the first `enum`), "schema keywords are supported", "bash files do not use jq" and "shell".
`bash tests/check.sh` stays green.

## Verification

A skill is added, so the manual check applies (`verification.manualCheckText`: run the changed skill in a real project
with `claude --plugin-dir <this checkout>`). The issue's own check, as steps, in a test project with worktrees and the
plugin loaded from this checkout, on Windows (PowerShell and Git Bash) at least:

1. **Report only during two builds.** Set `"parallel": { "controlMode": "report", "controlIntervalMinutes": 2 }`. Start
   `/loop 2m /nightmill:control`. Start two builds at once (two runs of `bash tests/check.sh` in two checkouts, as in
   iteration 24). Each pass prints one `control (report only, nothing changed): ...` line and the next-pass line; its
   CPU is within 15 points and its free memory within 5% of the task manager over the same seconds. `slot --capacity`
   shows the same numbers before and after; `capacity.json` is unchanged or absent.
2. **Apply, and watch the limit move inside its bounds.** Set `"controlMode": "apply"`, `"controlMinAgents": 1`,
   `"controlMaxAgents": 3`, `"controlCooldownMinutes": 2`. With the machine idle the limit rises one step per cooldown
   until 3 and stays (`at the maximum`); `slot --capacity` and `/status` show it `live`, and the slot count rises with
   it. Start the two builds again, or lower free memory with a large build: when memory is short the limit drops at once
   to the target, never below 1. Busy slots stay busy and their agents run on.
3. **Self-paced.** `/loop /nightmill:control` without an interval: the PR says how far apart the passes came, against
   the `next pass in` line.
4. **Nothing left running.** End the session: no process of the controller remains; `slot --capacity` shows the last
   live values; `slot --capacity --clear` returns to the configuration.
5. **Off.** With `controlMode` removed, a pass prints only the off line and changes nothing.

The PR's "How verified" lists the results per shell and says that auto-merge is off because the change is a story
trigger (new config keys).

## Not done

- No orchestrator; this iteration gives it a script to call.
- No stopping, pausing or restarting of an agent, no release or abandon of a slot, no removal of a worktree; the slot
  count is never lowered.
- No limits from the model provider (rate limits, token budget), no GPU, disk or network measure, no count of agents
  outside the slots.
- No learning of thresholds from history and no record of earlier passes; no state file of the controller.
- No background process, hook or timer; no change to `/init`'s questions, to `/status`, to the slot scripts, the slot
  marker, the format of `capacity.json`, `scripts/load.*`, `scripts/room.*` or the workflow skill.
- No command-line flag for the mode and no porcelain output of the controller.
- No change to the status flow or to who sets a status; no decision record.
