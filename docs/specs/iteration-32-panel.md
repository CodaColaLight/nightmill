# Iteration 32: a pane beside the Claude chat shows the slots and the agents in them

Status: draft, awaiting approval (#69)

Story: #69, epic #47 (Unattended runs). Ships a mod inside the nightmill plugin: a hooks module, `hooks/panel.tsx`,
named in `hooks/hooks.json` under `modules` next to the existing `SessionStart` hook. It adds one slash command,
`/nightmill-slots`, that opens a pane beside the chat. While the pane is open it shows every slot, free or busy, the
agent state (running, stalled, unknown), the branch, the skill and step, and the age of the last report, and reads them
again every `worktrees.panelRefreshSeconds` seconds. The data comes from one new read-only script,
`scripts/panel.sh` / `scripts/panel.ps1`, which calls `slot --status --porcelain` and prints its lines in the form
the pane draws. Adds one config key under `worktrees`. Changes `hooks/hooks.json`, `schema/nightmill.schema.json`,
`templates/nightmill.example.json`, `README.md`, `CHANGELOG.md`, `tests/lint.sh`, `tests/check.sh` and
`.github/workflows/ci.yml`; adds `hooks/panel.tsx`, `hooks/panel.test.tsx`, `scripts/panel.sh`, `scripts/panel.ps1`,
`tests/smoke-panel.sh`, `tests/smoke-panel.ps1` and `tests/fixtures/panel/`. No skill, no agent, no change to the slot
scripts, the slot marker, `capacity.json`, `/status` or the status flow.

**This is a story trigger**: a new config key ("a new, renamed or removed config key"). The status flow and who sets a
status do not change, and neither does the slot marker. The pull request therefore does **not** auto-merge; it says so.
`hooks` is in `verification.manualCheckPaths`, so **the manual check applies** (see Verification): a mod changes what a
real session shows, and only a real session proves it.

**Order.** #67 (iteration 23: the ten porcelain fields, the agent states, `NIGHTMILL_NOW`) is merged and on `main`;
this iteration builds on that code. #81 (iteration 28), #82 (iteration 30) and #68 (iteration 31, the page in the
browser, spec in review) each change the schema, a hot file: `parallel.doNotPair` forbids two tasks that both change
it. This iteration is therefore implemented **after #81 has merged** and **never at the same time as #82 or #68**
(whichever of them is Approved first is implemented first and merged before this one starts). The new key goes under
`worktrees` after `stalledAfterMinutes`, or after `dashboardRefreshSeconds` when #68 has merged; on a conflict in the
README table, the lint, `check.sh`, `ci.yml` or the CHANGELOG both sides are kept (CHANGELOG in iteration order).

## Goal

A person working in the Claude chat sees the slots, the agent in each busy slot and whether it is running or stalled in
a pane beside the chat, and the pane keeps up with the run without being asked again.

## Can a plugin ship a pane? What was found

The issue asks to settle this first. Sources, read on 2026-11-06: the `plugin-authoring` skill of Claude Code 2.1.319
(its `SKILL.md`, `reference.md`, the example `pane.tsx` and `pane.test.tsx`, and the API declarations
`types/claude-code.d.ts` that the engine writes for this build), the official pages "Mods overview", "Mods reference",
"Troubleshoot a mod" and "Plugin manifest reference" on code.claude.com, and two probes in a scratch copy of this
repository (not committed): `claude plugin validate . --strict` and `claude plugin test .` on a draft of the module.

**Confirmed:**

- **A plugin can ship one.** A "mod" is an ordinary plugin whose `hooks/hooks.json` names one hooks module under
  `modules` (one path, relative to that file); the module is a `.ts`/`.tsx`/`.js` ES module exporting
  `register(on, options)`. The same `hooks.json` may also hold settings hooks under `hooks` ("Mods reference", Files:
  "Can also hold settings hooks under `hooks`"). So nightmill keeps its `SessionStart` hook and adds
  `"modules": ["./panel.tsx"]`. `plugin.json` needs no new field (a `types` file is needed only for `$.state`, which the
  module does not use). The probe with this layout passed `claude plugin validate . --strict` ("Validation passed";
  the directory checks found nothing) and listed the hooks and calls.
- **Installing it.** A mod installs as a plugin, from a marketplace, with no extra step: the existing
  `/plugin install nightmill@nightmill` brings it. The installed copy of this plugin holds the whole repository at the
  version folder (`~/.claude/plugins/cache/nightmill/nightmill/<version>/`), so `$.plugin.root` reaches `scripts/`.
- **A pane.** `$.ui.open({ id, title })` opens a framed region the surface places beside the transcript (`dock`) or
  above the prompt (`inline`); a `ui.render` hook on `{ component: 'Pane', requestId: id }` draws it from the surface's
  element table (`$.ui.resolve(e)`: `Box`, `Text`, ...). An open that answers the person's own command is placed at any
  width; one the plugin makes on its own waits undrawn below 144 terminal columns. `$.ui.close({ id })` closes it, the
  person's close mark raises `ui.close` with `origin.kind` `person`, and `$.ui.panes()` lists the plugin's open panes.
- **Refreshing.** Nothing refreshes a pane by itself. `$.clock.every(ms, fn)` calls `fn` until `cancel()` or until the
  module reloads; `$.ui.invalidate('ui.render')` redraws (at most 10 a second, 30 in the terminal). `$.process.run(argv,
  { cwd, timeoutMs })` runs a host command by argument vector, no shell, 30 s by default, and resolves
  `{ exitCode, stdout, stderr }`; it rejects when the command cannot start or runs past the timeout. `$.plugin.root` is
  the plugin's folder. `$.env.get('OS')` reads an environment variable named literally in the source.
- **A slash command.** `$.command.register({ name, description, argumentHint, immediate })` in `session.start`,
  answered by a `command.run` hook returning `{ text }`. The name is not namespaced (`/<name>`), letters, digits, `_`,
  `-`, up to 64. `immediate: true` runs it while a turn is in flight.
- **Where it draws and from which version.** Mods are on by default in the terminal from Claude Code **v2.1.287** and in
  the Code tab of the Desktop app from **v2.1.286**. The `Pane` site is drawn by the terminal, the Desktop app and the
  VS Code extension's chat panel (extension **2.1.299** or later; **2.1.304** for a session that does not fetch
  feature flags, such as one on Bedrock). Hooks run but nothing is drawn in `claude -p` and the Agent SDK, in a cloud
  session, and over Remote Control from claude.ai or the mobile app (there it draws in the terminal on the machine).
  The Desktop app's WSL sessions load no plugins. The `Box` props used here (`flexDirection`, `width`) and the `Text`
  props (`color`, `dimColor`, `wrap`) are drawn by all three surfaces; the props that need v2.1.299 (`weight`, `size`,
  `mono`, `tabular`, spacing step names) are not used.
- **How it is turned off.** The module loads and stays idle until the person runs the command (Decision 2). Mods as a
  whole stop with `"disableAllHooks": true` in the user's settings (which also stops nightmill's `SessionStart` hook),
  with `--safe-mode` or `--bare`, by an organization (`allowManagedModsOnly`, `allowManagedHooksOnly`, managed
  `disableAllHooks`), or when Anthropic turns installed mods off remotely; in each case the rest of the plugin (skills,
  agents, scripts) still loads ("Mods overview": "stop a mod and leave the rest of its plugin in place"). There is no
  per-mod switch inside a plugin other than a `userConfig` field, which would add a screen to every install (not used).
- **Tests.** `claude plugin test <plugin folder>` runs the plugin's `*.test.ts(x)` files against the engine with every
  `$` call mockable by a hook (`on('process.run', ...)`, `on('env.get', ...)`), and mounts the pane on a named surface.
  The probe's test, which mocked `process.run` and drew the pane on `terminal`, `desktop` and `vscode`, passed.
- **The API is early access** ("this surface may change between releases without notice", the declaration file's
  header). The spec uses only calls listed in the public "Mods reference" table.

**Not confirmed** (each is a step of Verification, not a guess in the code):

- What a Claude Code **older than v2.1.287** does with a `hooks.json` that has a `modules` key: whether it ignores the
  key and still runs the `SessionStart` hook and loads the skills, or refuses the file. Neither the docs nor the
  skill say. Verification step 6 checks it with an older build; Decision 9 says what happens if it fails.
- That the pane is actually drawn and refreshed in a live installed session (the probes are a validator and a test kit,
  not a session), and that `/nightmill-slots` is offered in the Desktop app's and the VS Code extension's prompt.
- Whether `claude plugin test` runs without a signed-in account (it ran locally with one). `tests/check.sh` runs it
  only when the subcommand exists and skips it otherwise; CI runs it in the job that does not block a merge (see
  Tests); Decision 9 says what happens if it needs a sign-in.

**Outcome: a plugin can ship the pane, so this story is code, not a decision record.**

## Facts this rests on

- `slot --status --porcelain` prints `<n> TAB free` for a free slot and ten fields for a busy one: `<n> busy <branch>
  <since> <retiring> <agent> <skill> <role> <step> <reported>`; field 6 is `running`, `stalled` or `unknown`, decided by
  the slot script alone from `worktrees.stalledAfterMinutes` (iteration 23, decision 4). It needs no `gh` and no
  network, and honours `NIGHTMILL_NOW` (seconds since 1970, local time taken as UTC). An unusable `stalledAfterMinutes`
  gives one line on its standard error and exit 0. A marker that is not valid JSON is listed busy with empty fields and
  `unknown` by `slot.sh`; `slot.ps1` throws on it and exits non-zero. Neither lists it as free.
- `slot.sh` exits 1 with one line on standard error outside a checkout (`run slot.sh from inside a git checkout of the
  project`), without a config (`no <path> (run /nightmill:init)`) and for a bad `WORKER_SLOTS`
  (`WORKER_SLOTS must be a number from 1 to 99`); `slot.ps1` throws the same texts.
- The Slots section of `/status` (iteration 23) shows `Skill` as `<skill>/<role>` with `?` for a missing part and `?`
  when both are missing, `Step` as the step or `?`, and `Report` as the age of `reported` by the `Age` rule of iteration
  8 (`span` in `lib/status.awk`: under an hour `<m>m`, under a day `<h>h`, else `<d>d`, whole units rounded down, a
  negative age 0), `-` when `reported` is missing or not of the form `YYYY-MM-DDTHH:MM:SS`; it computes seconds with
  `stamp` (days from year, month, day, plus hours, minutes, seconds), not a date parser.
- The validators' schema keywords are `type`, `properties`, `required`, `items`, `minimum`, `minItems`,
  `additionalProperties` and `enum`; there is no `maximum`.
- The bash scripts read JSON with `scripts/lib/json.sh`, never jq (iteration 7); CI hides jq before the bash smoke
  tests and runs shellcheck at warning level on `scripts/*.sh`, `scripts/lib/*.sh` and `tests/*.sh`. The PowerShell
  scripts run under Windows PowerShell 5.1.
- The `SessionStart` hook (iteration 3, as built) runs `bash` through Claude Code's hook shell. `$.process.run` uses no
  shell: on Windows `bash` resolves through the `PATH`, where the default Git for Windows install puts no `bash.exe`
  and `C:\Windows\System32\bash.exe` may be WSL's.

## Decisions

**1. A mod inside the nightmill plugin, not a second plugin.** The module lives in `hooks/` and `hooks.json` names it,
so it ships and updates with the plugin and reaches the scripts through `$.plugin.root`. A second plugin in the same
marketplace (`source: "./panel"`) would need nightmill's scripts outside its own root, which the manifest rules forbid
(`..` in a path is refused) and whose install layout is not documented. This holds unless Verification step 6 finds
that older Claude Code refuses the `modules` key (Decision 9).

**2. Off until asked: the command is the switch.** The module registers `/nightmill-slots` and does nothing else at
the start of a session: no pane, no timer, no process. `/nightmill-slots` opens the pane and starts the reading;
`/nightmill-slots off`, or the pane's own close mark, closes it and stops the reading. Nothing opens the pane unasked,
so a narrow terminal, a session that never wants it and a project that does not use slots lose nothing but one entry
in the command list. No config key switches the pane on or off: the issue asks how to turn it on and off, and a command
does that without a config change; an auto-open key would add scope and opens that wait undrawn below 144 columns.

**3. The command is `/nightmill-slots`, `immediate`.** Mod commands are not namespaced, so the name carries the plugin's
name; `immediate: true` lets the maintainer open the pane while `/next` is running in that session, which is when it is
wanted.

**4. One script between the pane and the slot script.** The module never reads a marker, a config file or the clock to
decide anything. It runs `scripts/panel.sh` (`panel.ps1`), which runs `slot --status --porcelain` once and prints
records in the form the pane draws: the `Skill`, `Step` and `Report` cells of `/status`'s Slots section, the interval,
and notes. So the agent state is decided only by the slot script (iteration 23, decision 4), the cells are tested in
both shells against one fixture with a fixed clock, and the module only splits lines and draws. The age rule (`stamp`,
`span`) is copied into the panel scripts in a few lines rather than moved out of `lib/status.awk`, which this story
does not touch; the fixture pins the same ages as `/status`'s scenario. `status --porcelain` of #68 was not used: it
calls `gh` on every read, and the issue names `slot --status --porcelain`.

**5. PowerShell on Windows, bash elsewhere.** The module decides by `$.env.get('OS') === 'Windows_NT'`: on Windows
`powershell -NoProfile -ExecutionPolicy Bypass -File <root>/scripts/panel.ps1`, elsewhere `bash
<root>/scripts/panel.sh`. Windows PowerShell is present on every Windows machine; `bash` from an argument vector may be
missing or WSL's there (Facts).

**6. The interval is a config key, `worktrees.panelRefreshSeconds`, default 15, used when 5 to 3600.** A read costs one
or two short processes and no network or `gh` call, so it can be more frequent than the page's 60 s; 15 s keeps a
`running` to `stalled` change within a quarter of a minute of the threshold. Under `worktrees` beside
`stalledAfterMinutes` and #68's `dashboardRefreshSeconds`, in their style. The panel script reads it, so the value
and its warning are tested in both shells; the module takes the interval from the script's `every` record. A fixed
15 s would be a project value written into a hooks module, and the Config-driven invariant keeps project values in
`.claude/nightmill.json`; that is why a key is added although the issue names none, and why this change is a story
trigger.

**7. Unknown is shown, never guessed.** Whenever the slots cannot be read (the script cannot start, exits non-zero,
runs past its timeout, prints something the pane cannot parse, or the slot script fails), the pane says `unknown` with
the reason and shows **no** slot rows, not the rows of the last good read: a stale table would show slots as running or
free that may no longer be.

**8. Read-only by construction.** The module draws no `Button`, `Input`, `Select` or link, so nothing in the pane can
be pressed; its only process is the panel script, which runs only `slot --status --porcelain`. The lint pins both.

**9. If an older Claude Code refuses `modules`.** Verification step 6 decides. If a build before v2.1.287 still runs
the `SessionStart` hook and loads the skills with the new `hooks.json`, the README names v2.1.287 as the lowest version
that shows the pane and says older versions ignore it. If it refuses the file or the plugin (skills missing, the hint
not shown, an error in `/plugin`), the implementation stops: no pull request is opened, the session ends with a
`Stopped:` line naming the version and what it saw, the branch keeps the work, and the issue goes back to the spec
(the alternative, a second plugin or a documented minimum version for all of nightmill, is the maintainer's decision,
not this spec's).

It is not confirmed whether `claude plugin test` needs a signed-in account. If the implementer finds that it fails
without one, the step moves out of `tests/check.sh` into CI's non-blocking `validate` job only, and the pull request
says so; `tests/check.sh` is never left red on a machine without a sign-in. The lint's `tests/check.sh` pins for
`claude plugin test` and the README's "Developing nightmill" sentence then follow that move.

## The module: `hooks/panel.tsx`

`hooks/hooks.json` keeps its `hooks` object byte for byte and gains, after it, `"modules": ["./panel.tsx"]` (on one
line). The module, in TypeScript with JSX, typed against `Register` from `'claude-code'` (types only, as in the
skill's examples), with module variables (not `$.state`, so no `types` file and no `plugin.json` change):

| Variable | Meaning | At load |
|---|---|---|
| `view` | what the pane draws: `{ kind: 'reading' }`, `{ kind: 'slots', time, every, rows, notes }`, `{ kind: 'noslots', time, every, notes }` or `{ kind: 'unknown', reason, time? }` | `reading` |
| `timer` | the `$.clock.every` handle, or none | none |
| `everySeconds` | the interval of `timer` | 15 |
| `isReading` | a read is running | false |

A reload of the module (`/reload-plugins`, a plugin update) starts these over; the next read fills `view` again.

**Pane id** `nightmill-slots`, **title** `nightmill slots`.

**`session.start`**: when `e.isInteractive` is true, register
`{ name: 'nightmill-slots', description: 'Show the nightmill slots and their agents in a pane beside the chat (read-only)', argumentHint: '[off]', immediate: true }`.
Then, if `$.ui.panes()` lists `nightmill-slots` (the pane stayed open across a reload), start the timer and read once
(below). Return `next(e)`. Nothing else runs at the start; with `isInteractive` false nothing is registered.

**`command.run` on `{ command: 'nightmill-slots' }`**, by its arguments (`e.args` trimmed):

| Arguments | What it does | Its `text` |
|---|---|---|
| empty | `$.ui.open({ id: 'nightmill-slots', title: 'nightmill slots' })`. Placed: start the timer if none, read once at once (not awaited). Not placed: start nothing | placed: `Slots pane opened; it reads the slots every <everySeconds> s while it is open. /nightmill-slots off closes it.`; not placed: `The slots pane cannot be shown here (<reason>). /nightmill:status shows the same slots.` |
| `off` | if the pane is listed by `$.ui.panes()`: stop the timer, `$.ui.close({ id: 'nightmill-slots' })` | `Slots pane closed.`, or `The slots pane is not open.` |
| anything else | nothing | `usage: /nightmill-slots [off]` |

Each exit leaves: a placed pane with a running timer; or no pane and no timer; or the state as it was (usage).

**Starting and stopping the timer.** Start: `timer = $.clock.every(everySeconds * 1000, tick)`. Stop: `timer.cancel()`,
`timer` none. `tick` first checks `$.ui.panes()`: when `nightmill-slots` is not listed (the pane was closed in a way
the `ui.close` hook did not see), it stops the timer and returns; otherwise it reads, unless `isReading`.

**`ui.close` on `{ id: 'nightmill-slots' }`**: stop the timer, return `next(e)`; registered with
`.catch(($, e, next) => next(e))`, so a failure never keeps the pane open. The timer then also stops at its next tick
(above).

**A read.** `isReading` true; run the panel script with `$.process.run(argv, { cwd: await $.session.cwd(), timeoutMs:
20000 })` (`argv` by Decision 5, the path from `$.plugin.root` joined with `/`); `isReading` false in a `finally`. Then:

| Result | `view` |
|---|---|
| rejected (cannot start, timeout) | `unknown`, reason `the panel script did not run: <the error's message, first line>` |
| exit code not 0 | `unknown`, reason the first non-empty line of standard error with trailing spaces removed, or `panel script exited with code <n>` |
| exit 0 | the records parsed (next section) |

After setting `view`: if the parsed `every` differs from `everySeconds` and a timer runs, restart it with the new
interval; then `$.ui.invalidate('ui.render')`.

**Parsing the records** (standard output split on `\n`, a trailing `\r` removed from each line, empty lines skipped,
fields split on every tab). The first record must be `time` with one field of the form `HH:MM:SS` and the second
`every` with a whole number from 5 to 3600; then either one `noslots`, or one `unknown` with one field, or one or more
`slot` records with exactly 7 fields after the kind (field 2 `free` with fields 3 to 7 empty, or `busy`); then zero or
more `note` records with one field. Anything else (an unknown kind, a wrong field count, a missing `time`) makes the
whole read `unknown` with the reason `the panel script printed a line the pane cannot read`. A `busy` record's agent
field that is not `running`, `stalled` or `unknown` is drawn as `unknown`. The script's `unknown` record keeps its
`time`.

**`ui.render` on `{ component: 'Pane', requestId: 'nightmill-slots' }`.** Elements from `$.ui.resolve(e)`: `Box` and
`Text` only. A column of rows, each its own line:

| `view` | Lines, in order |
|---|---|
| `reading` | `reading the slots...` (dim) |
| `slots` | `read at <time>, every <every> s` (dim); the table; each note as `note: <text>` (dim) |
| `noslots` | `read at <time>, every <every> s` (dim); `No slots: .claude/nightmill.json has no worktrees section.`; the notes |
| `unknown` | `read at <time>` (dim) when it has one; `unknown: the slots could not be read (<reason>)` |

The table: a header row `slot`, `State`, `Agent`, `Branch`, `Skill`, `Step`, `Report`, then one row per `slot` record
in its order. Each row is a `Box` with `flexDirection="row"`; each cell a `Box` whose `width` is the column's width
(the longest of the header and the cells of that column, plus 2) holding one `Text` with `wrap="truncate-end"`. Cells:

| Column | Busy | Free |
|---|---|---|
| `slot` | the number | the number |
| `State` | `busy` | `free`, `dimColor` |
| `Agent` | the word; `color` `success` for `running`, `warning` for `stalled`, `inactive` for `unknown` | empty |
| `Branch`, `Skill`, `Step`, `Report` | the cell as printed | empty |

The colour is never the only signal: every state is its word. No other element, prop or handler is drawn.

## The script: `scripts/panel.sh` and `scripts/panel.ps1`

| | bash | PowerShell |
|---|---|---|
| Print the slots for the pane | `scripts/panel.sh` | `scripts/panel.ps1` |

Read-only; needs git, no `gh`, no network. Run from inside the project. Steps, in this order:

1. **Arguments.** None. Any argument writes `usage: panel.sh` (`usage: panel.ps1`) to standard error and exits 2.
   `panel.ps1` takes a remaining-arguments parameter that must be empty.
2. **The configuration**: `.claude/nightmill.json` of the main checkout (`git rev-parse --path-format=absolute
   --git-common-dir`, its parent). Outside a git checkout: `panel: run panel.sh from inside a checkout of the project`
   (`panel.ps1` in PowerShell), exit 2. No file: `panel: no <path> (run /nightmill:init)`, exit 2. Not valid JSON:
   `panel: <path> is not valid JSON`, exit 2. Nothing is printed on standard output in these cases.
3. **The interval**: `worktrees.panelRefreshSeconds` (see "The config key").
4. **The clock of day**: with `NIGHTMILL_NOW` set, `HH:MM:SS` of `NIGHTMILL_NOW mod 86400` (it is local time taken as
   UTC); otherwise `date +%H:%M:%S`, `(Get-Date).ToString("HH:mm:ss")`.
5. **The slots.** Without a `worktrees` section in the config: no slot call. Otherwise run, in its own process, the
   slot script of the same plugin: `bash "$here/slot.sh" --status --porcelain` with standard output and standard error
   captured apart (each into a `mktemp` file removed by an `EXIT` trap); in PowerShell a child process of the running
   PowerShell (`(Get-Process -Id $PID).Path`, arguments `-NoProfile -ExecutionPolicy Bypass -File "<slot.ps1>" -Status
   -Porcelain`, `UseShellExecute` false, `CreateNoWindow` true, both streams redirected, standard error read with
   `ReadToEndAsync()` started before standard output is read to the end so a full error stream cannot block, the
   working directory the current one). The environment passes unchanged (`NIGHTMILL_NOW`, `WORKER_SLOTS`, `PATH`).
   `panel.ps1` removes one trailing carriage return from each line it reads from the slot script (Windows PowerShell
   prints CRLF to a child process), as the module does with the panel script's lines.
6. **Print** the records (next section) and exit 0.

**Exit codes:** 0 when the records were printed (also with an `unknown` record); 2 for a usage error, no checkout, no or
invalid config. The script itself writes nothing but the two temporary files, which are removed on every exit. The
one effect of the slot script it runs is that script's existing behaviour: `slot.sh --status` creates the slot root
folder (`mkdir -p`) when it is missing.

**The records**, one per line, LF, the kind then tab-separated fields, in this order:

| Record | Fields | When |
|---|---|---|
| `time` | `HH:MM:SS` | always, first |
| `every` | the interval in seconds | always, second |
| `noslots` | none | the config has no `worktrees` |
| `slot` | `<n>`, `free`, then five empty fields | a free line of the slot script |
| `slot` | `<n>`, `busy`, agent (field 6), branch (field 3), skill cell, step cell, report cell | a busy line |
| `unknown` | the reason | the slot script failed, or printed a line this script cannot read; then no `slot` record at all |
| `note` | the text | the interval note (below), then every non-empty line of the slot script's standard error when it exited 0, in order |

Cells of a busy line, by the rules of `/status`'s Slots section (Facts): skill cell `<skill>/<role>`, a missing part
`?`, `?` when both are missing; step cell the step or `?`; report cell `span(now - stamp(reported))` with `now` from
`NIGHTMILL_NOW` or the local clock read as `date +%Y-%m-%dT%H:%M:%S` / `(Get-Date).ToString("s")`, `-` when `reported`
is empty or not of the form. Field 5 (`retiring`) is not shown, as in `/status`.

The `unknown` reason: when the slot script could not be started or exited non-zero, the first non-empty line of its
standard error with trailing spaces removed, or `slot.sh exited with code <n>` (`slot.ps1 ...`) when there is none;
when a line of its output is neither `<n> TAB free` (two fields, `<n>` digits) nor ten fields with field 2 `busy` and
`<n>` digits, `slot.sh printed a line the panel cannot read`. Every tab, carriage return or line feed inside a note or
a reason becomes one space. Both shells print the same bytes for the same input, apart from a reason that quotes a
shell's own error.

For the fixture `run-stall-old-free` (see Tests) the output is:

```
time	12:00:00
every	15
slot	1	busy	running	feat/run	next/implementer	check	5m
slot	2	busy	stalled	feat/stall	fix/fixer	test	2h
slot	3	busy	unknown	feat/old	?	?	-
slot	4	free					
```

The header comments of both scripts say what they print, that they only read, and that the pane of `hooks/panel.tsx`
calls them. bash: `set -euo pipefail`, every expansion quoted, words in assignments quoted (`state="unknown"`), no
bare keyword assigned, `trap` strings in single quotes; JSON through `scripts/lib/json.sh`. PowerShell: 5.1 syntax (no
`??`, no ternary, no `-AsHashtable`, no `&&`), the file ASCII and UTF-8 without a byte order mark.

## The config key

`worktrees.panelRefreshSeconds`: integer, default 15, used when 5 to 3600.

- **Schema**, in `properties.worktrees.properties` after `stalledAfterMinutes` (after `dashboardRefreshSeconds` when
  #68 has merged), on one line in the form of its neighbours, no `maximum`:
  `"panelRefreshSeconds": { "type": "integer", "minimum": 5, "default": 15, "description": "How often the slots pane beside the chat (/nightmill-slots) reads the slots again while it is open, in seconds (5 to 3600). Each read runs slot --status --porcelain once; no gh call." }`
- **Example template**: `"panelRefreshSeconds": 15` in `worktrees` of `templates/nightmill.example.json`, after
  `stalledAfterMinutes` (after `dashboardRefreshSeconds` when present). This repository's `.claude/nightmill.json` is
  not changed.
- **README**, the configuration table (see README).
- **Read by** the panel scripts only, on every read. Used when it is a JSON number written as a whole number without
  sign, fraction or exponent, from 5 to 3600 (bash: kind `number` in the parsed records of `json.sh` and the text
  `^[1-9][0-9]{0,5}$`, then the range; PowerShell: an `[int]` or `[long]` in the range), as iteration 24 reads its
  keys. Absent or `null`, or no `worktrees`: 15, nothing said. Any other value (`0`, `4`, `3601`, `2.5`, `15.0`,
  `"15"`, `true`): 15 and the record
  `note	worktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15`. A change takes effect at the
  next read.
- The previous version ignores the key; its validator warns `unknown key` for it (not an error). The slot scripts,
  `/status` and the page of #68 do not read it.

## README

- "What is in the plugin": a row after `/nightmill:models`: `/nightmill-slots [off]` | Opens a read-only pane beside
  the chat with every slot and its agent (running, stalled, unknown), rereading them every `panelRefreshSeconds`;
  `off` closes it. Needs Claude Code 2.1.287 or later (see "Watching the run beside the chat"). And a row after the
  load scripts: `scripts/panel.ps1`, `scripts/panel.sh` | Read-only: the slot lines the pane draws, from
  `slot --status --porcelain`.
- Configuration table, the `worktrees` row, at the end: ", and `panelRefreshSeconds` (default 15): how often the slots
  pane beside the chat reads the slots again".
- "Why slots" gains, after "What a slot's agent is doing" (after #68's "Watching the run in a browser" when present),
  a subsection **"Watching the run beside the chat"**:
  - what it shows: every slot, free or busy, the agent state, branch, skill and step and the age of the last report
    (the Slots section of `/nightmill:status` without the pull request, CI and flag columns), read again every
    `worktrees.panelRefreshSeconds` seconds (default 15) while the pane is open, with the time of the last read;
    running, stalled and unknown in the words of "What a slot's agent is doing";
  - how to turn it on and off: `/nightmill-slots` opens it (also while a run is going in that session);
    `/nightmill-slots off` or the pane's close mark closes it and stops the reading; nothing opens it by itself and
    nothing runs until it is opened; to keep the plugin's mod from loading at all, the only switches are Claude Code's
    own (`"disableAllHooks": true` in the user settings, which also silences the `SessionStart` hint, or
    `--safe-mode`); the skills, `/nightmill:status` and the page in the browser work without it;
  - that it changes nothing: no buttons or links; it runs only `scripts/panel.*`, which runs only
    `slot --status --porcelain`; a slot that cannot be read is shown as `unknown` with the reason, never as free;
  - where it works: Claude Code 2.1.287 or later in a terminal (also an editor's integrated terminal and the JetBrains
    plugin), the Code tab of the Desktop app from 2.1.286, the VS Code extension's chat panel from extension 2.1.299
    (2.1.304 where the session does not fetch feature flags, such as on Bedrock); not in `claude -p`, the Agent SDK,
    cloud sessions, the Desktop app's WSL sessions, or on claude.ai and the mobile app (Remote Control draws it in the
    terminal on the machine); there the command says it cannot show the pane, or is not offered. Older Claude Code
    versions do not load it (the sentence about them follows Verification step 6, Decision 9). An organization can
    turn installed mods off; mods are early access in Claude Code and may change between its releases;
  - on Windows the pane runs `scripts/panel.ps1` with Windows PowerShell, elsewhere `scripts/panel.sh` with bash.
- "Developing nightmill": `bash tests/smoke-panel.sh # panel.sh against fixtures`,
  `powershell -ExecutionPolicy Bypass -File tests/smoke-panel.ps1`, and `claude plugin test . # the pane's module
  (hooks/panel.test.tsx)`, with one sentence: `tests/check.sh` runs it when `claude` is on the PATH and has the
  `plugin test` subcommand, and lists it as skipped otherwise; CI runs it in the `validate` job, which does not block
  a merge.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 32 (#69): a pane beside the Claude chat shows
the slots and the agents in them. ...` naming the mod `hooks/panel.tsx` in `hooks/hooks.json` (`modules`), the command
`/nightmill-slots` and `off`, that it is off until asked and read-only, the columns, `unknown` for what cannot be read,
`scripts/panel.sh` / `scripts/panel.ps1` and their records, the key `worktrees.panelRefreshSeconds` (default 15), the
Claude Code versions and surfaces that draw it, and that the key is ignored by the previous version.

## Tests

Each acceptance criterion of #69 is a test or a manual scenario. Names are the behaviour protected. Nothing sleeps.

**`tests/smoke-panel.sh` and `tests/smoke-panel.ps1`**, the same cases in both. They build a throwaway repository
(`git init`, a `.claude/nightmill.json` with `github` `acme`/`widgets`/1, `worktrees` with `root` `../wt` and
`"slots": 4`, no `panelRefreshSeconds`), write the slot markers from `markers.txt` as `smoke-status.*` do, fix the
clock with `NIGHTMILL_NOW=1793880000` (2026-11-05T12:00:00) and run every case in a child process. No `gh` is needed;
a fake `gh` that logs its calls is first on the `PATH` so case 9 can show it was never called.

The fixture `tests/fixtures/panel/run-stall-old-free/` (`markers.txt`, `expected.txt`), named after its four slots:

| Slot | Marker | Record |
|---|---|---|
| 1 | `feat/run`, since `2026-11-05T10:00:00`, `next`, `implementer`, `check`, reported `2026-11-05T11:55:00` | `running`, `next/implementer`, `check`, `5m` |
| 2 | `feat/stall`, since `2026-11-05T08:00:00`, `fix`, `fixer`, `test`, reported `2026-11-05T10:00:00` | `stalled`, `fix/fixer`, `test`, `2h` |
| 3 | `feat/old`, since `2026-11-03T12:00:00`, three-key marker | `unknown`, `?`, `?`, `-` |
| 4 | none | `free` |

1. **The records of the slots**: exit 0, nothing on standard error, standard output equals `expected.txt` (the example
   in "The records"; both shells compare against the same file; `UPDATE_PANEL_FIXTURES=1` rewrites it). In
   `smoke-panel.ps1` this also checks the carriage return: a CR left on a slot line would make `4 free` unreadable
   and the output an `unknown` record; the case also asserts that no output line holds a carriage return.
2. **Field counts**: every `slot` line has 8 fields; the free line is `slot<TAB>4<TAB>free` followed by five tabs.
3. **The interval is a config value**: `"panelRefreshSeconds": 30` gives `every<TAB>30` and no `note`. Each of `0`,
   `4`, `3601`, `2.5`, `15.0`, `"15"` and `true` gives `every<TAB>15`, the note line, exit 0 and the four slot records;
   `null` and an absent key give `every<TAB>15` and no note.
4. **The slot script's notes pass**: with `"stalledAfterMinutes": 0` the output ends with
   `note<TAB>slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30` and the slot records
   are those of case 1.
5. **An unreadable marker is never free**: slot 2's marker replaced by the text `{ not json` (restored afterwards):
   exit 0 and no line `slot<TAB>2<TAB>free`; bash: `slot<TAB>2<TAB>busy<TAB>unknown<TAB><TAB>?<TAB>?<TAB>-`;
   PowerShell: an `unknown` record and no `slot` record (slot.ps1 fails on it, Facts).
6. **A failing slot script is unknown**: `WORKER_SLOTS=abc`: exit 0, `time`, `every`, then exactly
   `unknown<TAB>WORKER_SLOTS must be a number from 1 to 99`, and no `slot` record.
7. **Without worktrees**: a config copy without `worktrees`: `time`, `every<TAB>15`, `noslots`, nothing else.
8. **Errors**: an argument (`--help`, `x`) exits 2 with the usage line; outside a git checkout exits 2; a repository
   without `.claude/nightmill.json` exits 2 with `run /nightmill:init`; a config that is not valid JSON exits 2. None
   prints on standard output.
9. **Nothing is changed**: after all cases `git status --porcelain --untracked-files=all` of the throwaway repository
   is as before the first case, every marker is byte for byte as written, `.slots` holds no other file, the fake `gh`
   log is empty, and the test's temporary folder holds no file left by the script.

**`hooks/panel.test.tsx`**, run by `claude plugin test .`, with the engine mocked as in the skill's `pane.test.tsx`
(`command.register`, `ui.open`, `ui.panes`, `ui.close`, `session.start`, `session.cwd`, `env.get`, `clock.every`,
`process.run` answered by hooks; the `process.run` hook records the `argv` it got and answers the bytes of
`tests/fixtures/panel/run-stall-old-free/expected.txt` written into the test as a string). Each case mounts the pane on
`terminal`, `desktop` and `vscode`:

1. **The table**: after `/nightmill-slots`, the pane holds `running`, `stalled`, `unknown` and `free` in four rows, the
   cells `feat/run`, `next/implementer`, `check`, `5m`, and `read at 12:00:00, every 15 s`.
2. **The script by system**: with `env.get('OS')` answering `Windows_NT`, `argv` is `powershell`, `-NoProfile`,
   `-ExecutionPolicy`, `Bypass`, `-File`, `<root>/scripts/panel.ps1`; with it unset, `bash`, `<root>/scripts/panel.sh`.
3. **Unknown, never free**: `process.run` answering exit 1 with standard error `panel: no x (run /nightmill:init)`, a
   rejection, and exit 0 with an unparsable line (`slot\t1\tfree`): each pane holds
   `unknown: the slots could not be read (` and no `free` and no `running`.
4. **A failed read drops the old rows**: a good read, then a failing one: the pane holds `unknown` and not `feat/run`.
5. **Off until asked**: after `session.start` alone, no `ui.open`, `clock.every` or `process.run` was called.
6. **Off and usage**: `/nightmill-slots off` with the pane listed closes it and cancels the timer
   (`Slots pane closed.`); without it, `The slots pane is not open.`; `/nightmill-slots x` answers
   `usage: /nightmill-slots [off]` and opens nothing.
7. **Not placed**: `ui.open` answering `{ isPlaced: false, reason: 'no surface' }`: the answer starts
   `The slots pane cannot be shown here` and no timer was started.
8. **The interval follows the script**: an `every\t30` record restarts the timer with 30000 ms.
9. **Read-only**: no drawn element is a `Button`, `Input`, `Select` or `Link` (`find` by type finds none).
10. **It updates without being asked**: with the mocked clock, after `/nightmill-slots` and its first read, firing the
    `clock.every` callback once starts a new `process.run` (two calls recorded) and redraws the pane: with the second
    answer holding `every\t15` and a slot 1 step `test` instead of `check`, the pane holds `test` and not `check`.

**`tests/check.sh`** runs `smoke-panel.sh` with the bash smoke tests and `smoke-panel.ps1` with the PowerShell ones.
After `claude plugin validate . --strict` it runs `claude plugin test .` only when both hold: `claude` is on the PATH
(the same `command -v claude` test as the validate step), and the probe `claude plugin test --help` (output discarded)
exits 0, so the subcommand exists. Otherwise the step is not run and is added to the skipped list as
`claude plugin test not available`, never a failure. A run that then exits non-zero is a failure of the module test,
a real red. `tests/check.ps1` runs no `claude` step today and is not changed.
**`.github/workflows/ci.yml`**: `bash tests/smoke-panel.sh` in the bash job (after jq is hidden),
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-panel.ps1` in the PowerShell job, and
`claude plugin test .` after `claude plugin validate . --strict` in the `validate` job, which does not block a merge
(the ruleset requires the lint and the two smoke jobs only).

**`tests/lint.sh`**, new section "== slots pane is wired". Each pinned phrase stands on one line of its file (the lint
greps line by line with `grep -F`):

- `hooks/panel.tsx`, `hooks/panel.test.tsx`, `scripts/panel.sh`, `scripts/panel.ps1`, `tests/smoke-panel.sh`,
  `tests/smoke-panel.ps1` and `tests/fixtures/panel/run-stall-old-free/expected.txt` exist.
- `hooks/hooks.json` contains `"modules": ["./panel.tsx"]`, and the existing "session-start hook is wired" section
  still passes.
- `hooks/panel.tsx` contains `nightmill-slots`, `Windows_NT`, `scripts/panel.ps1`, `scripts/panel.sh`,
  `$.clock.every(`, `$.ui.open(` and `'unknown'`; outside comment lines (a line that, after optional whitespace,
  starts with `//`, `/*` or `*`) it contains none of `Button`, `Input`,
  `Select`, `Link`, `onPress`, `$.fs.`, `$.store.`, `$.state.`, `$.prompt.`, `$.tool.`, `$.agent.`, `$.http.`,
  `$.model.`, `$.command.run`, `$.session.append`, `slot.sh`, `slot.ps1`, `.slots`. (It does contain the text
  `.claude/nightmill.json` in the `noslots` line; it reads no file, which the absence of `$.fs.` pins.)
- `scripts/panel.sh` contains `slot.sh" --status --porcelain` and `scripts/panel.ps1` contains `-Status -Porcelain`;
  both contain `panelRefreshSeconds` and `NIGHTMILL_NOW`; outside comment lines neither contains `.slots`, `--take`,
  `--release`, `--abandon`, `--reap`, `--report`, `--capacity`, `-Take`, `-Release`, `-Abandon`, `-Reap`, `-Report`,
  `-Capacity`, or a `gh` call (`(^|[^A-Za-z0-9_-])gh +[a-z]`).
- The schema contains `"panelRefreshSeconds": { "type": "integer", "minimum": 5, "default": 15,`;
  `templates/nightmill.example.json` has `worktrees.panelRefreshSeconds` equal to 15.
- The README contains `/nightmill-slots`, `panelRefreshSeconds`, `2.1.287` and `panel.ps1`.
- `tests/check.sh` and `.github/workflows/ci.yml` contain `smoke-panel` and `claude plugin test`; `tests/check.sh`
  also contains `claude plugin test --help` and `claude plugin test not available`.

The existing sections cover the rest: "json" (`hooks.json` parses), "config validates", "schema keywords are
supported", "bash files do not use jq" and "shell" (`bash -n` and shellcheck). `claude plugin validate . --strict`
passes with the module (it lists the hooks and calls; a `gating hook` line is a fact, not a warning). `bash
tests/check.sh` stays green.

## Verification

`hooks` changes, so the manual check applies, and it is the issue's own. In a throwaway project with slots and a board
(not this repository: the `/next` runs of step 2 and 3 happen there), from another folder, with nightmill loaded from
a separate checkout of this branch (`claude --plugin-dir <checkout>`), with the installed release not loaded in that
session (not installed in the throwaway project, or disabled there through `/plugin` and enabled again afterwards), so
the same skills are never loaded twice (decision 0003); `"stalledAfterMinutes": 2` and
`"panelRefreshSeconds": 10` in the config; on Windows in a terminal (PowerShell path) and on Linux or WSL (bash path).
The check (`bash tests/check.sh`) is run on the branch and its skipped list recorded, including whether
`claude plugin test .` ran or was skipped as `claude plugin test not available`:

1. **It is off until asked.** Start a session: no pane appears, and `/nightmill-slots` is offered in the command list.
2. **The pane follows a run.** Start two `/next` (or `/fix`) runs in two other sessions so that two slots are busy and
   `running`. In the first session run `/nightmill-slots`: the pane opens beside the chat with every slot, the two
   busy ones `running` with their branch, skill and step and a report age; the `read at` time moves on every 10 s
   without any input. Kill one run's session right after a report: within 2 minutes plus 10 s its row turns from
   `running` to `stalled`; the other stays `running`. `/nightmill:status` shows the same states, branches, steps and
   ages.
3. **Opened mid-run.** Close the pane with its close mark, start `/next` in this same session and type
   `/nightmill-slots` while it works: the pane opens at once.
4. **Unknown, not free.** Write `{ not json` into a busy slot's marker (keep a copy): within 10 s the pane shows that
   slot `unknown` (bash) or the line `unknown: the slots could not be read (...)` (PowerShell), and no busy slot shows
   `free`. Put the marker back.
5. **Off.** `/nightmill-slots off` closes the pane; no PowerShell or bash process of the panel is started afterwards
   (Task Manager or `ps` over a minute). The board, the pull requests and every marker are as before; `git status`
   is clean.
6. **Without the panel.** (a) Start a session with an older Claude Code, 2.1.285 or any release before 2.1.286 (the
   first Mods version cited above), for example `npx @anthropic-ai/claude-code@2.1.285 --plugin-dir <checkout>`:
   record whether the skills load, the `SessionStart` hint appears in a project without config, and
   `/nightmill:status` works; this decides the README sentence or the stop of Decision 9. (b) With the installed
   release unloaded for this step (decision 0003: one marketplace named `nightmill` at a time), install the plugin from
   this branch's checkout as a folder marketplace and set `"disableAllHooks": true` in the user settings:
   `/nightmill-slots` is not offered, and `/nightmill:status` still shows the slots. Afterwards remove the setting and
   restore the stable marketplace (`claude plugin marketplace remove nightmill`,
   `claude plugin marketplace add CodaColaLight/nightmill`, and reinstall nightmill where it was installed). (c) Where available, open the Desktop app's Code tab and the VS Code extension (2.1.299 or later)
   on the project and run `/nightmill-slots`: record whether the pane appears.

The PR's "How verified" lists each result per system and surface, the Claude Code versions used, the outcome of step 6
(a), the check, and says that auto-merge is off because the change is a story trigger (a new config key).

## Not done

- No pane opened by itself, no auto-open key and no `userConfig` field; the command is the switch (Decision 2).
- No starting, stopping or steering of an agent, no freeing or abandoning of a slot, and no button, field or link in
  the pane (Decision 8).
- No pull request, CI or `stale:` column and no board items in the pane: those need `gh` (`/nightmill:status` and the
  page of #68 show them).
- No new information about agents and nothing from an agent's conversation: the pane shows what
  `slot --status --porcelain` gives (#67 records it).
- No page in the browser (#68), no status line entry, band, toast or notification.
- No reader of the slot markers or of the agent-state rule outside the slot scripts; the module reads no file.
- No change to the slot scripts, the slot marker, `capacity.json`, `/status`, `skills/status/SKILL.md`, the
  `SessionStart` hook or `plugin.json`; the PowerShell/bash difference on a marker that is not valid JSON stays.
- No pane in `claude -p`, the Agent SDK, cloud sessions, WSL sessions of the Desktop app, claude.ai or the mobile app,
  and none in Claude Code before v2.1.287 (VS Code extension before 2.1.299).
- No change to the status flow or to who sets a status; no decision record (the pane is possible, so the story's
  "finding and decision record" outcome does not apply).
