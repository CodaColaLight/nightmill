# Iteration 24: a command shows CPU and memory load and suggests an agent limit

Status: draft, awaiting approval (#80)

Story: #80, epic #47 (Unattended runs). Adds one read-only command, `scripts/load.sh` and `scripts/load.ps1`, that
measures the machine's CPU load and free memory over a short window, shows the effective agent limit, the slots in use
and the agents running, and prints a suggested agent limit with one line saying why. The measurement and the
suggestion live in one library per shell, `scripts/lib/load.sh` and `scripts/lib/load.ps1`, for the sibling stories
(admission, automatic adjustment) to reuse. Adds three config keys under `parallel`. Changes
`schema/nightmill.schema.json`, `templates/nightmill.example.json`, `README.md`, `CHANGELOG.md`, `tests/lint.sh`,
`tests/check.sh` and `.github/workflows/ci.yml`; adds `tests/smoke-load.sh` and `tests/smoke-load.ps1`. No skill, no
agent, no hook, no change to the slot scripts, the slot marker, `capacity.json` or the status flow.

**This is a story trigger**: three new config keys ("a new, renamed or removed config key"). The status flow and who
sets a status do not change. The pull request therefore does **not** auto-merge; it says so. No path in
`verification.manualCheckPaths` (`skills`, `agents`, `hooks`) changes, so the manual check of a skill does not apply;
the check on a real machine of the issue's Verification does (see Verification).

**Order.** This iteration is implemented after #67 (iteration 23) has merged. #67 changes the schema (a hot file, and
`parallel.doNotPair` forbids two tasks that both change the schema), the example template, the README's plugin and
configuration tables (the `worktrees` row is the line under the `parallel` row this iteration changes), the lint and
the CHANGELOG. This iteration does not use anything #67 adds: it reads only field 2 (`busy` or `free`) of
`slot --status --porcelain`, which is the same before and after #67, and the `--capacity --porcelain` lines of #78
(iteration 22, merged). It does not change `scripts/slot.*`.

## Goal

One command shows the machine's current CPU load and free memory, how many agents and slots are in use, and a suggested
agent limit, so the maintainer can see when the machine is underused or overloaded.

## Facts this rests on

- The agent limit is the live value of `capacity.json`, else `parallel.maxAgents`, else 2; the slot count is the live
  value, else `WORKER_SLOTS`, else `worktrees.slots`, else 2 (iteration 22, decision 3). `slot.sh --capacity
  --porcelain` / `slot.ps1 -Capacity -Porcelain` prints exactly two lines, `slots TAB <n> TAB <source> TAB <config>` and
  `agents TAB <m> TAB <source> TAB <config>`, source `live`, `WORKER_SLOTS`, `config` or `default`. The human form
  writes the source in brackets: `live; config <c>`, `WORKER_SLOTS; config <c>`, `config` or `default`.
- `slot --status --porcelain` prints one line per listed slot whose second field is `busy` or `free`; a busy slot above
  the slot count (retiring) is listed too. #67 adds fields after the fourth; field 2 stays. Both commands need the
  project's `.claude/nightmill.json` (main checkout) and work without a `worktrees` section (defaults).
- What a script can know about agents: a busy slot marker. A busy slot normally holds one `/next` or `/fix` run, but
  it stays busy after the run ends until it is freed. Subagents launched outside a slot (`/spec`'s writer and reviewer,
  the code reviewer, the worker), the session's own builds and any other Claude session on the machine leave no trace a
  script can read.
- `/init` sets `worktrees.slots` and `parallel.maxAgents` from physical memory: "one per 8 GB, at least 1 and at most 4"
  (`skills/init/SKILL.md`, the Detect table). The schema's description of `parallel.maxAgents` says the same rule.
- Readings checked on a Windows 11 machine (build 26200, 4 logical processors, 16 GB) at the time of writing:
  `Win32_Processor.LoadPercentage` read `0` three times while the machine was about 50% busy; the raw counter
  `Win32_PerfRawData_PerfOS_Processor` (`Name='_Total'`), read twice 3 s apart, gave 50.2% busy as
  `100 × (1 − ΔPercentProcessorTime / ΔTimestamp_Sys100NS)`; Git Bash's `/proc/stat` (`cpu` line with four counters:
  user, nice, system, idle) read twice 3 s apart gave 52.3%. Git Bash's `/proc/meminfo` has `MemTotal` and `MemFree`
  but no `MemAvailable`; its `MemFree` (6150320 kB) matched `FreePhysicalMemory` of `Win32_OperatingSystem`
  (6142368 KB) read a moment apart, both in KiB. `Get-Counter` paths are translated with the Windows display language,
  so a counter path written in English fails on another language.
- The schema keywords the validators understand are `type`, `properties`, `required`, `items`, `minimum`, `minItems`,
  `additionalProperties` and `enum`; there is no `maximum`. An unknown key is a warning of the validator, not an error.
- The bash scripts read JSON with `scripts/lib/json.sh` and never with jq (iteration 7); CI hides jq before the bash
  smoke tests.

## Decisions

**1. A new script, `scripts/load.sh` / `scripts/load.ps1`, not a subcommand of `slot`.** The slot scripts are hot
files that #67 is changing, the measurement takes seconds and has nothing to do with worktrees, and the story asks for
a library the sibling stories reuse. The command reads the slot numbers by calling the slot script (`--status
--porcelain`, `--capacity --porcelain`), as `/status` does, so the two cannot disagree (iteration 22, decision 7). The
name is `load`, not `capacity`, because `--capacity` already means the live numbers of #78.

**2. The measurement is in one library per shell.** `scripts/lib/load.sh` (sourced by bash) and `scripts/lib/load.ps1`
(dot-sourced by PowerShell) hold the settings, the measurement, the fixture override and the suggestion rule. The
command only gathers the slot numbers, calls the library and prints. The interface is fixed under "The library".

**3. A window of one-second samples.** The window is `parallel.loadWindowSeconds` samples (default 10), one a second.
The CPU load is the mean of the samples; the free memory is the lowest sample, because a build's memory comes and goes
and the suggestion must hold at the worst moment of the window. One failed sample makes that measurement unavailable:
no partial window, nothing made up.

**4. The CPU reading comes from cumulative counters, not from a "load percentage".** On Linux and in Git Bash,
`/proc/stat`; on Windows, `Win32_PerfRawData_PerfOS_Processor`; both give busy time between two reads. Not
`Win32_Processor.LoadPercentage` (it read 0 on a busy Windows 11 machine), not `Get-Counter` (its paths depend on the
display language), not `/proc/loadavg` (a run-queue length, not a share of the processors, and a fixed `8.00` in Git
Bash). On macOS, `top`.

**5. Memory is "available" memory, in MB of 10^6 bytes.** What the operating system can hand out without swapping:
`MemAvailable` on Linux, `FreePhysicalMemory` on Windows (Git Bash's `MemFree` carries the same number), free plus
inactive plus speculative pages on macOS. MB and GB are decimal (10^6 and 10^9 bytes), so a machine sold with 16 GB,
which reports a little under 16 GiB, still counts as two agents at 8 GB.

**6. The suggestion is the smaller of a memory bound and a CPU bound, between 1 and a ceiling.** The memory bound is
`/init`'s rule of thumb (total memory over the memory per agent), cut down when the free memory does not hold more,
and one less than the agents in the slots when memory is short. The CPU bound scales the agents in the slots to a CPU
load of 80%. The exact rule is under "The suggestion". The constants of the method (80% CPU, 10% free memory, one
second between samples) are not project values and are not config keys; the three project values are.

**7. "Agents running" is the number of busy slots, and says so.** It is the only count a script can read (see
Facts). The command prints it with the words `counted from the busy slots`, and the README lists what it does not see.
It is not a count of processes; no process list is read.

**8. Three config keys under `parallel`**, beside `maxAgents`, which the suggestion is about. Not under `worktrees`,
which #67 changes and which is about slots, and not a new top-level object. The memory per agent defaults to 8 (GB),
`/init`'s rule of thumb, and the ceiling to 4, `/init`'s upper bound, so on an idle machine with no slot in use the
suggestion is `/init`'s rule applied to the memory that is free. `/init` itself is not changed (no skill changes); the
lint keeps the number in its text equal to the schema default.

**9. The override for the tests is a fixture file named by `NIGHTMILL_LOAD_FIXTURE`.** When it is set, the library
reads the samples from that file and takes no real reading and does not sleep. The smoke tests set it in every call,
so their result does not depend on the machine that runs them.

**10. Read-only.** The command never writes a file, never calls `slot --capacity` with a value, and never changes the
agent limit or the slot count. To apply a suggestion the maintainer runs `slot --capacity --agent-limit N` (#78).

## The command

| | bash | PowerShell |
|---|---|---|
| Show the load and the suggestion | `scripts/load.sh` | `scripts/load.ps1` |
| For a program | `scripts/load.sh --porcelain` | `scripts/load.ps1 -Porcelain` |

Run from inside the project (any checkout or worktree of it), like the slot scripts. It takes about
`parallel.loadWindowSeconds` seconds (default 10) and then prints. Steps, in this order:

1. Arguments. Anything other than `--porcelain` (`-Porcelain`), including `-h` / `--help`, writes
   `usage: load.sh [--porcelain]` (`usage: load.ps1 [-Porcelain]`) to standard error and exits 2.
2. The configuration: `.claude/nightmill.json` of the main checkout, found with `git rev-parse --path-format=absolute
   --git-common-dir`. Outside a git checkout: `load: run load.sh from inside a checkout of the project` (`load.ps1` in
   PowerShell), exit 2. No config file: `load: no <path> (run /nightmill:init)`, exit 2. A config that is not valid JSON:
   the parser's error, exit 2.
3. The settings (see "The config keys"); a wrong value gives a warning on standard error and the default.
4. The slot numbers: `slot --capacity --porcelain` and `slot --status --porcelain` of the same plugin
   (`bash "$here/slot.sh" ...` in bash; `& (Join-Path $PSScriptRoot "slot.ps1") ...` in PowerShell). Their standard
   error passes through to the command's standard error (for example the note about an unusable `capacity.json`). A
   call that exits non-zero ends the command with `load: slot.sh failed: <its standard error on one line>`
   (`slot.ps1` in PowerShell), exit 2, before anything is measured. From the output: the agent limit `L`, its source
   and its config value (line `agents`, fields 2, 3, 4); the slot count (line `slots`, field 2); `A`, the number of
   lines of `--status --porcelain` whose second field is `busy`.
5. The measurement (see "The measurement"), then the suggestion (see "The suggestion"), then the output.

**Exit codes:** 0 when everything was measured and a suggestion was printed; 1 when the CPU load or the free memory is
unavailable (the output is printed, without a suggestion); 2 for a usage error, no checkout, no or invalid config, a
failed slot script, or an unusable fixture file. A warning about a config value does not change the exit code.

### The human form

Seven lines, in this order (the example: fixture of three samples, CPU 5, 10 and 15, free memory 61000, 60000 and
62000 MB of 64000 MB, one busy slot of two, no live values, no `parallel` keys in the config):

```
cpu: 10% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)
memory: 60000 MB free of 64000 MB (lowest of 3 samples)
agent limit: 2 (default)
slots: 1 of 2 in use
agents running: 1 (counted from the busy slots)
suggested agent limit: 4 (now 2: raise)
why: the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more
```

- `cpu`: `<C>% busy (mean of <S> samples, 1 s apart)` for a real measurement, `(mean of <S> samples from
  NIGHTMILL_LOAD_FIXTURE)` for a fixture.
- `memory`: `<F> MB free of <T> MB (lowest of <S> samples)`.
- `agent limit`: `L` and the bracket of #78 (`live; config <c>`, `config`, `default`; the agent limit has no
  `WORKER_SLOTS` source).
- `slots`: `<A> of <slot count> in use` (a retiring busy slot counts, so `A` can be above the count).
- `agents running`: `A` and the fixed words `(counted from the busy slots)`.
- `suggested agent limit`: `<P> (now <L>: <raise|keep|lower>)`; `raise` when `P > L`, `keep` when equal, `lower` when
  `P < L`.
- `why`: the text of the reason (see "The suggestion").

**A measurement that is unavailable** replaces its value: `cpu: unavailable (<reason>)`,
`memory: unavailable (<reason>)`. The suggestion line is then `suggested agent limit: none (the CPU load is
unavailable)`, `none (the free memory is unavailable)` or `none (the CPU load and the free memory are unavailable)`,
and there is no `why` line. The other lines are printed as usual. Exit 1.

### The porcelain form

Eleven lines, tab-separated, in this order, and nothing else on standard output. For the example above:

```
cpu	10
memory-free	60000
memory-total	64000
window	3	fixture
agent-limit	2	default
slot-count	2
slots-busy	1
agents-running	1
memory-per-agent	8
ceiling	4
suggested	4	raise	ceiling
```

| Line | Fields after the name |
|---|---|
| `cpu` | `C` (whole percent), or `unavailable` and the reason |
| `memory-free` | `F` (MB), or `unavailable` and the reason |
| `memory-total` | `T` (MB), or `unavailable` and the reason (the reason of the memory measurement) |
| `window` | the number of samples `S`, and `measured` or `fixture` |
| `agent-limit` | `L` and its source (`live`, `config`, `default`), from `--capacity --porcelain` |
| `slot-count` | the effective slot count |
| `slots-busy` | `A` |
| `agents-running` | `A` (decision 7; a later story may count otherwise, the line stays) |
| `memory-per-agent` | `G`, the setting in GB |
| `ceiling` | `K`, the setting |
| `suggested` | `P`, the direction (`raise`, `keep`, `lower`) and the reason key; or `none` and `unavailable` |

A reason never contains a tab or a newline. A later story reads the lines by name, never by position.

## The measurement

`S` = `parallel.loadWindowSeconds` (default 10). Each sample has a CPU value (a percentage, clamped to 0..100) and a
memory value (free and total MB). The result: `C` = the mean of the `S` CPU values, rounded half up to a whole number
(`floor(mean + 0.5)`); `F` = the lowest free value; `T` = the total of the first sample. If any sample has no CPU value,
the CPU load is unavailable with the reason of the first failed sample; the same, independently, for memory.

**Which reader.** bash by `uname -s`: `Linux` is Linux; `Darwin` is macOS; a name that starts with `MINGW`, `MSYS` or
`CYGWIN` is Git Bash; anything else has no reader. PowerShell: `$IsLinux` is Linux, `$IsMacOS` is macOS, otherwise
(Windows PowerShell 5.1 has neither variable, so it is read in a way that works when they do not exist) Windows. The
same operating system has the same reader in both shells, except Windows, where bash runs in Git Bash.

| Reader | CPU | Memory |
|---|---|---|
| Linux (bash, and `pwsh` on Linux) | the first line of `/proc/stat` (`cpu` and its counters) read once before the window and once after each 1-second sleep; a sample is `100 × (Δtotal − Δidle) / Δtotal` between two reads, `total` the sum of the first eight counters present (user, nice, system, idle, iowait, irq, softirq, steal), `idle` = idle + iowait | `/proc/meminfo` read with each CPU read after the first: free = `MemAvailable`, total = `MemTotal`, both kB = KiB, MB = `floor(kB × 1024 / 1000000)` |
| Git Bash (MSYS, Cygwin) | the same `/proc/stat` rule (four counters there) | the same file, free = `MemFree` (it carries Windows' available memory; there is no `MemAvailable`), total = `MemTotal` |
| Windows (PowerShell) | `Get-CimInstance Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'"` read before the window and after each 1-second sleep; a sample is `100 × (1 − ΔPercentProcessorTime / ΔTimestamp_Sys100NS)` | `Get-CimInstance Win32_OperatingSystem`, read with each CPU read after the first: free = `FreePhysicalMemory`, total = `TotalVisibleMemorySize`, both KiB, MB as above |
| macOS (bash, and `pwsh` on macOS) | for each sample `top -l 2 -s 1 -n 0`; the second `CPU usage:` line; a sample is `100 − <idle>%` (this call takes the second; no extra sleep) | after each `top`: `vm_stat` (page size from its first line, `page size of <n> bytes`), free = (`Pages free` + `Pages inactive` + `Pages speculative`) × page size; total = `sysctl -n hw.memsize`; MB = `floor(bytes / 1000000)` |

So a real window takes `S` seconds plus the time of the reads.

**Unavailable**, with these reasons (exact texts, the same in both shells for the same reader):

| Case | Reason |
|---|---|
| `/proc/stat` missing, unreadable, or its first line not `cpu` followed by at least four numbers | `/proc/stat cannot be read` |
| the raw processor counter cannot be read or lacks a property | `Win32_PerfRawData_PerfOS_Processor cannot be read` |
| `Δtotal` (Linux, Git Bash) or `ΔTimestamp_Sys100NS` (Windows) is 0 or negative between two reads | `the CPU counters did not move` |
| `top` fails or has no second `CPU usage:` line with an idle percentage | `top gave no CPU usage` |
| `/proc/meminfo` missing or unreadable, or no `MemTotal` | `/proc/meminfo cannot be read` |
| Linux, `/proc/meminfo` without `MemAvailable` (kernels before 3.14) | `/proc/meminfo has no MemAvailable` |
| Git Bash, no `MemFree` | `/proc/meminfo cannot be read` |
| `Win32_OperatingSystem` cannot be read, or a property is missing | `Win32_OperatingSystem cannot be read` |
| `vm_stat` or `sysctl -n hw.memsize` fails or gives no number | `vm_stat or sysctl hw.memsize gave no reading` |
| no reader for the system (bash) | `no reading for this system (<uname -s>)`, for both |
| fixture, sample `i` has `-` for the CPU | `sample <i> has no CPU reading` |
| fixture, sample `i` has `-` for the free or the total memory | `sample <i> has no memory reading` |

A reader that fails at the first read still lets the other measurement run its full window.

### The fixture

`NIGHTMILL_LOAD_FIXTURE`, when set and not empty, names a text file. Each line that is not empty and does not start
with `#` is one sample: three fields separated by spaces or tabs, `<cpu percent> <free MB> <total MB>`. The CPU is a
number from 0 to 100 (digits, optionally a `.` and digits; read with the invariant culture in PowerShell); free is a
whole number from 0; total is a whole number from 1; `-` in a field means that reading failed in that sample. Nothing
sleeps and nothing is read from the system. `window` is `<number of samples> fixture`; `parallel.loadWindowSeconds` is
ignored (still checked, so its warning appears).

Unusable, exit 2, nothing printed on standard output, one line on standard error:

| Case | Message |
|---|---|
| the file is missing or unreadable | `load: cannot read NIGHTMILL_LOAD_FIXTURE: <path>` |
| fewer than 2 samples | `load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples` |
| a line with other than three fields, or a field that is not `-` and not of its form above | `load: NIGHTMILL_LOAD_FIXTURE line <n> is not "<cpu> <free MB> <total MB>"` (`n` counts every line of the file from 1) |

## The suggestion

With `G` = `parallel.memoryPerAgentGB`, `M = G × 1000` (MB per agent), `K` = `parallel.maxSuggestedAgents`, `A` the busy
slots, `C`, `F`, `T` as measured, and integer division `⌊ ⌋`:

```
short    = F × 10 < T                          (less than 10% of the memory is free)
byTotal  = ⌊T / M⌋                             (/init's rule of thumb)
byFree   = A + ⌊F / M⌋                         (the agents in the slots, plus what the free memory holds)
memory   = short ? A − 1 : min(byTotal, byFree)
cpu      = A = 0 ? (C < 80 ? K : 1)            (no agent in a slot: CPU sets no bound unless the machine is busy)
         : C = 0 ? K
         : ⌊A × 80 / C⌋                        (the agents in the slots scaled to 80% CPU)
raw      = min(memory, cpu)
P        = max(1, min(K, raw))
```

The reason, the first that applies:

| Key | When | `why:` text |
|---|---|---|
| `ceiling` | `raw > K` | `the ceiling is the limit (parallel.maxSuggestedAgents = <K>); CPU and memory have room for more` |
| `memory-short` | `memory ≤ cpu` and `short` | `memory is short: <F> MB free is under 10% of <T> MB, one agent fewer than the <A> in the slots` |
| `memory-total` | `memory ≤ cpu` and `byTotal ≤ byFree` | `memory is the limit: <T> MB in all holds <byTotal> agents at <G> GB each` |
| `memory-free` | `memory ≤ cpu` otherwise | `memory is the limit: <F> MB free holds <⌊F/M⌋> more agents at <G> GB each beside the <A> in the slots` |
| `cpu-other` | `cpu < memory` and `A = 0` | `CPU is the limit: <C>% busy with no slot in use` |
| `cpu` | `cpu < memory` and `A > 0` | `CPU is the limit: <C>% busy with <A> agents in the slots, aiming at 80%` |

A tie between memory and CPU names memory. The floor of 1 changes the number, not the reason. Worked cases (these are
the smoke tests' scenarios; `K` = 4, `G` = 8, `L` = 2 unless the row says otherwise):

| | T | F | A | C | memory | cpu | P | direction | reason |
|---|---|---|---|---|---|---|---|---|---|
| a | 64000 | 60000 | 1 | 10 | 8 | 8 | 4 | raise | `ceiling` |
| b | 16000 | 9000 | 1 | 20 | 2 | 4 | 2 | keep | `memory-total` |
| c | 32000 | 9000 | 1 | 20 | 2 | 4 | 2 | keep | `memory-free` |
| d | 16000 | 1000 | 2 | 30 | 1 | 5 | 1 | lower | `memory-short` |
| e | 64000 | 50000 | 2 | 90 | 8 | 1 | 1 | lower | `cpu` |
| f | 64000 | 50000 | 0 | 85 | 6 | 1 | 1 | lower | `cpu-other` |
| g | 64000 | 50000 | 1 | 100 | 7 | 0 | 1 | lower | `cpu` (floor) |
| h | 64000 | 60000 | 1 | 10 | 16 | 8 | 6 | raise | `ceiling`, with `G` = 4, `K` = 6 |
| i | 16000 | 12000 | 0 | 5 | 1 | 4 | 1 | lower | `memory-free` |

The suggestion never sees the API's rate limits, the token budget, GPU, disk or network, agents outside the slots,
or memory a build will take but has not taken yet during the window; CPU used by other programs counts as if the
agents used it. The README says so.

## The config keys

Three keys under `parallel`, each optional:

| Key | Type | Default | Used when | Schema |
|---|---|---|---|---|
| `parallel.maxSuggestedAgents` | integer | 4 | 1 to 99 | `"minimum": 1` |
| `parallel.memoryPerAgentGB` | integer | 8 | 1 to 1024 | `"minimum": 1` |
| `parallel.loadWindowSeconds` | integer | 10 | 2 to 60 | `"minimum": 2` |

- **Schema**, in `properties.parallel.properties` after `doNotPair`, no `maximum` (the validators do not support it):
  - `"maxSuggestedAgents": { "type": "integer", "minimum": 1, "default": 4, "description": "The highest agent limit
    scripts/load.* suggests (it uses 1 to 99; the suggestion is never below 1). It bounds the suggestion only, not
    maxAgents or a value set with slot --capacity." }`
  - `"memoryPerAgentGB": { "type": "integer", "minimum": 1, "default": 8, "description": "Memory one agent's work needs,
    in GB of 10^9 bytes (1 to 1024), for the memory part of the suggestion of scripts/load.*. The default is the rule
    of thumb /nightmill:init uses: one agent per 8 GB." }`
  - `"loadWindowSeconds": { "type": "integer", "minimum": 2, "default": 10, "description": "How long scripts/load.*
    measures, in seconds (2 to 60): one CPU and memory sample a second." }`
- **Example template**: in `parallel` of `templates/nightmill.example.json`, after `doNotPair`:
  `"maxSuggestedAgents": 4`, `"memoryPerAgentGB": 8`, `"loadWindowSeconds": 10`. This repository's own
  `.claude/nightmill.json` is not changed (the defaults apply).
- **README**, the configuration table (see README).
- **Read by** the library only. A value is used when it is a JSON number written as a whole number without sign,
  fraction or exponent and within the "Used when" range (bash: kind `number` in the parsed records and the text
  `^[1-9][0-9]*$`; PowerShell: an `[int]` or `[long]`). Absent or `null`, or no `parallel`: the default, nothing said.
  Any other value (`0`, `-1`, `8.5`, `8.0`, `"8"`, `true`, above the range): the default and one line on standard
  error, `load: parallel.<key> must be a whole number from <low> to <high>; using <default>`, in the order of the table.
- The previous version ignores the keys; its validator warns `unknown key` for them (not an error). The keys are not
  read by the slot scripts, `/status`, `/init` or any skill.

## The library

Both files start with a header comment that names this spec and the other shell's file. Neither runs anything when it
is loaded.

**`scripts/lib/load.sh`**, sourced after `scripts/lib/json.sh` with the config already loaded (`json_load`):

| Function | Sets |
|---|---|
| `load_settings` | `LOAD_CEILING`, `LOAD_GB`, `LOAD_WINDOW` (warnings on standard error) |
| `load_measure SAMPLES` | `LOAD_CPU`, `LOAD_CPU_WHY`, `LOAD_FREE`, `LOAD_TOTAL`, `LOAD_MEM_WHY`, `LOAD_SAMPLES`, `LOAD_FROM` (`measured` or `fixture`); a value is empty when unavailable and its `_WHY` holds the reason. Returns 2 (message on standard error) for an unusable fixture, else 0 |
| `load_suggest BUSY` | from the measured values and the settings: `LOAD_SUGGEST`, `LOAD_REASON` (the key), `LOAD_WHY` (the text); all empty when a measurement is unavailable |

The arithmetic runs in bash integers and in awk (the CPU mean, the `/proc/stat` deltas); no `bc`, no jq.

**`scripts/lib/load.ps1`**, dot-sourced:

| Function | Returns |
|---|---|
| `Get-LoadSettings $Config` (the parsed config) | an object with `Ceiling`, `GB`, `Window` |
| `Measure-Load -Samples <n>` | an object with `Cpu`, `CpuWhy`, `Free`, `Total`, `MemWhy`, `Samples`, `From`; throws with the message of "The fixture" for an unusable fixture |
| `Get-LoadSuggestion -Load <measure> -Settings <settings> -Busy <n>` | an object with `Suggest`, `Reason`, `Why` (`$null` when a measurement is unavailable) |

The two libraries give the same numbers and texts for the same inputs.

## README

- "What is in the plugin": a row after the slot scripts, `scripts/load.ps1`, `scripts/load.sh` | Read-only: measures
  CPU load and free memory over a short window, shows the agent limit and the slots in use, and suggests an agent
  limit with the reason. Changes nothing.
- Configuration table, the `parallel` row: "Agent cap, hot files, task pairs to avoid, and for `scripts/load.*` the
  ceiling of its suggestion (`maxSuggestedAgents`, default 4), the memory one agent needs (`memoryPerAgentGB`, default
  8) and the measurement window (`loadWindowSeconds`, default 10)".
- "Why slots" gains, after "Changing the numbers during a session", a subsection **"Is the machine used well?"**: the
  two commands (`scripts/load.ps1 [-Porcelain]`, `bash scripts/load.sh [--porcelain]`); what is measured (CPU busy
  share, the mean of one sample a second; available memory, the lowest sample; the sources per system in one sentence)
  and over what window (`loadWindowSeconds`, default 10 s, so the command takes that long); how the suggestion is made
  (the formula of "The suggestion" in words: the smaller of a memory bound, one agent per `memoryPerAgentGB` of the
  total and of the free memory, one fewer when under 10% is free, and a CPU bound, the agents in the slots scaled to
  80% busy; at least 1, at most `maxSuggestedAgents`; the `why` line names which one decided); that "agents running"
  is the busy slots; what it does not see (the API's rate limits, the token budget, GPU, disk and network, agents
  outside the slots such as `/spec`'s writer and the reviewers, other programs' CPU counted as the agents', memory a
  build has not taken yet); that a measurement it cannot take is shown as unavailable with no suggestion (exit 1);
  that it changes nothing, and that `slot -Capacity -AgentLimit N` applies a suggestion; and the porcelain line names.
- "Developing nightmill": `bash tests/smoke-load.sh  # load.sh against a fixture of readings` and
  `powershell -ExecutionPolicy Bypass -File tests/smoke-load.ps1`.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 24 (#80): a command shows CPU and memory load
and suggests an agent limit. ...` naming `scripts/load.sh` / `scripts/load.ps1` and `--porcelain` / `-Porcelain`, the
libraries `scripts/lib/load.*`, the window (one sample a second, mean CPU, lowest free memory), the sources per system,
the suggestion (memory and CPU bounds, floor 1, ceiling), the unavailable case (exit 1, no suggestion), the override
`NIGHTMILL_LOAD_FIXTURE`, the three keys with their defaults, that the command changes nothing, and that the keys are
ignored by the previous version.

## Tests

Each acceptance criterion of #80 is a test or a manual scenario. Names are the behaviour protected.

**`tests/smoke-load.sh` and `tests/smoke-load.ps1`**, the same cases in both. Every call of the command sets
`NIGHTMILL_LOAD_FIXTURE`; the real measurement is never run. The file builds a throwaway repository (`git init`, a
`.claude/nightmill.json` with `github`, `maintainer`, `verification` and `worktrees` with `root` and `"slots": 2`, no
`parallel` keys), writes the fixture files into its temporary folder, and writes slot markers (the three-key form) and
`capacity.json` by hand into `<root>/.slots` where a case needs them. The scenarios a to i are those of "The
suggestion".

1. **Every value is printed**: scenario a gives exactly the seven lines of "The human form", exit 0.
2. **Porcelain**: scenario a with `--porcelain` gives exactly the eleven lines of "The porcelain form", exit 0, nothing
   on standard error.
3. **The window is used, not one reading**: CPU samples 5, 10, 15 give `10`; free 61000, 60000, 62000 give `60000`;
   a fixture whose last sample alone would give another suggestion gives the window's.
4. **The suggestion and its reason**: scenarios b to g and i, each in both forms: `P`, the direction, the reason key
   and the exact `why:` line.
5. **Floor and ceiling**: scenario g gives 1 with `raw` 0; scenario a gives 4 with `raw` 8; scenario h (a copy of the
   config with `"memoryPerAgentGB": 4` and `"maxSuggestedAgents": 6`) gives 6 and `ceiling` with `= 6` in the text.
6. **Unusable config values fall back**: each of `0`, `-1`, `8.5`, `8.0`, `"8"`, `true` for `memoryPerAgentGB`; `0`
   and `100` for `maxSuggestedAgents`; `1` and `61` for `loadWindowSeconds`: the warning line on standard error, the
   default in the output, exit 0. `null` and an absent key: no warning.
7. **The agent limit and the slots come from the slot script**: a `capacity.json` with `"maxAgents": 3` gives
   `agent limit: 3 (live; config 2)`, `agent-limit	3	live` and the direction against 3; a config with
   `"maxAgents": 5` gives `(config)`; a `capacity.json` with `"slots": 1` and markers for slots 1 and 2 gives
   `slots: 2 of 1 in use`, `slots-busy	2`, `agents-running	2`.
8. **An unavailable CPU is reported, never guessed**: a fixture whose sample 2 has `-` for the CPU gives
   `cpu: unavailable (sample 2 has no CPU reading)`, the memory line as usual, `suggested agent limit: none (the CPU
   load is unavailable)`, no `why:` line, exit 1; in porcelain `cpu	unavailable	sample 2 has no CPU reading` and
   `suggested	none	unavailable`, the other nine lines as usual, exit 1.
9. **An unavailable memory reading, and both**: the same with `-` for the free memory of sample 1 (`sample 1 has no
   memory reading`, both memory lines in porcelain), and with both, the suggestion text of each case.
10. **An unusable fixture stops the command**: a missing file, a file with one sample, a line with two fields, a CPU of
    `x` and of `101`, a free of `-5`, a total of `0`: each exits 2 with its message on standard error and nothing on
    standard output. A comment line and an empty line are skipped.
11. **Usage and project errors**: an unknown option exits 2 with the usage line; outside a git checkout exits 2; a
    repository without `.claude/nightmill.json` exits 2 with `run /nightmill:init`.
12. **Nothing is changed**: after all cases the config, every marker and `capacity.json` are byte for byte as written,
    and `.slots` holds no other file.

**`tests/check.sh`** runs `smoke-load.sh` with the bash smoke tests and `smoke-load.ps1` with the PowerShell ones;
**`.github/workflows/ci.yml`** gets `bash tests/smoke-load.sh` in the bash job (after jq is hidden) and
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-load.ps1` in the PowerShell job.

**`tests/lint.sh`**, new section "== load is wired":

- `scripts/load.sh`, `scripts/load.ps1`, `scripts/lib/load.sh`, `scripts/lib/load.ps1`, `tests/smoke-load.sh` and
  `tests/smoke-load.ps1` exist.
- The four script files only read: outside comment lines none contains `Set-Content`, `Out-File`, `Add-Content`,
  `Remove-Item`, `New-Item`, `Move-Item`, `--slot-count`, `--agent-limit`, `-SlotCount`, `-AgentLimit`, `--clear`,
  `-Clear`, `--take`, `--release`, `--abandon`, `--reap`, or a `gh` call.
- Both libraries contain `NIGHTMILL_LOAD_FIXTURE`, `/proc/stat`, `/proc/meminfo`, `MemAvailable`, `vm_stat` and
  `hw.memsize`; `scripts/lib/load.ps1` contains `Win32_PerfRawData_PerfOS_Processor` and `Win32_OperatingSystem` and
  not `LoadPercentage` or `Get-Counter`.
- The schema has `parallel.maxSuggestedAgents`, `parallel.memoryPerAgentGB` and `parallel.loadWindowSeconds`, each of
  type `integer` with a description, defaults 4, 8, 10 and minima 1, 1, 2; `templates/nightmill.example.json` has the
  three with the schema defaults.
- `skills/init/SKILL.md` contains `one per <d> GB` where `<d>` is the schema default of `memoryPerAgentGB` (one number
  for the rule of thumb).
- The README contains `load.sh`, `load.ps1`, `maxSuggestedAgents`, `memoryPerAgentGB`, `loadWindowSeconds`,
  `rate limits` and `token budget`.
- Both smoke tests contain `NIGHTMILL_LOAD_FIXTURE`; `tests/check.sh` and `.github/workflows/ci.yml` contain
  `smoke-load`.

The existing sections cover the rest: "config validates" (the example with the new keys), "schema keywords are
supported", "bash files do not use jq" and "shell" (`bash -n` and shellcheck on `scripts/*.sh` and
`scripts/lib/*.sh`).

`bash tests/check.sh` stays green.

## Verification

No skill, agent or hook changes, so the manual check of a skill does not apply. The issue's check on a real machine
does; on each system available (at least Windows with both PowerShell and Git Bash, and Linux or WSL with bash; macOS
when a machine is at hand, else the PR says it was not run there):

1. **Idle.** With nothing building, run the command in each shell. It takes about 10 s, prints every value, exit 0.
   The CPU is within 15 points of the task manager (Task Manager, `top`) over the same seconds, and the free memory
   within 5% of its "available" figure. On Windows, PowerShell and Git Bash agree within the same tolerance.
2. **Loaded.** Start two builds at once (two runs of `bash tests/check.sh` in two checkouts, or two CPU-heavy builds in
   two slots) and run the command while they run. The CPU is higher than idle, and the suggestion is not higher than
   in step 1; with the default settings and two busy slots it moves down (or stays at 1) and the `why:` line names the
   CPU or memory.
3. **Porcelain** prints the eleven lines in each shell.
4. **Nothing changed**: `slot --capacity` shows the same numbers before and after, and `git status` is clean.

The PR's "How verified" lists the results per system and shell and the check, and says that auto-merge is off because
the change is a story trigger (new config keys).

## Not done

- No change to the slot count or the agent limit, by hand or automatically: the command only suggests (#78 sets them;
  the automatic adjustment story builds on this command).
- No holding back of an agent when the machine is loaded (the admission story).
- No skill (`/nightmill:load`), no change to `/next`, `/fix`, `/spec`, `/status`, `/init` or the workflow skill; `/init`
  keeps its rule of thumb in its own text, and the schema's description of `parallel.maxAgents` is unchanged.
- No GPU, disk, network, API rate limit or token budget measurement; no count of agent processes; agents outside the
  slots are not seen.
- No history of readings; nothing is written to disk.
- No test of the platform readers in CI (the smoke tests use the fixture only); they are checked on real machines in
  Verification.
- No change to the slot scripts, the slot marker, `capacity.json`, the status flow or who sets a status; no decision
  record.
