# Iteration 22: change the slot count and the agent limit during a session

Status: draft, awaiting approval (#78)

Story: #78, epic #47 (Unattended runs). Adds one command to the slot scripts, `slot.sh --capacity` and
`slot.ps1 -Capacity`, that shows and sets the number of slots and the number of agents that may run at once, keeps
the set values in an untracked state file next to the slot markers, and makes the slot scripts, `/status` and the
skills read the effective numbers each time they need them. Changes `scripts/slot.ps1`, `scripts/slot.sh`,
`scripts/status.ps1`, `scripts/status.sh`, `skills/workflow/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`,
`skills/spec/SKILL.md`, the smoke tests of the slots and of `/status`, the lint and the README. No config key, no
change to the slot marker, the status flow or who sets a status: none of `escalation.storyTriggers` applies, so the
PR may auto-merge. The skills change, so the manual check applies. The slot scripts and the workflow skill are in
`parallel.hotFiles`: no other task may change them while this one is in flight (#67 changes the slot scripts too; run
it after this one).

## Goal

During a session the maintainer, or a program, can raise or lower the slot count and the agent limit with one command,
and the running skills pick the new numbers up without a restart.

## Facts this rests on

- The slot count is `worktrees.slots` (default 2), overridden for one shell by `WORKER_SLOTS` (a whole number from 1
  to 99; anything else is an error). `slot.sh` and `slot.ps1` read it into `count` once per run: `--status` lists slots
  1 to `count`, `--take` picks the first slot without a marker in that range (`--slot N` outside it is `slot must be
  1..<count>`), `--reap` (iteration 17) looks at 1 to `count`, and `all <count> slots are busy` is the refusal.
  `--release` and `--abandon` work on any slot that has a marker.
- The agent limit is `parallel.maxAgents` (a whole number, at least 1, schema default 2). Nothing in a script reads
  it: the skills read it from the configuration they print at the top (`skills/next`, `skills/fix` and `skills/spec`
  in their "Count" steps, `skills/next` step 2.2, and `skills/workflow`, "Parallel work": "At most
  `parallel.maxAgents` agents ... Before launching one, count the running ones").
- A slot is busy while `<worktrees.root>/.slots/slot-N.json` exists (keys `slot`, `branch`, `since`). The same folder
  holds `slot-N.warmup-<i>` stamps. It is outside every repository, shared by every worktree of the project, and not
  tracked. The previous version of the scripts reads only the markers and the stamps, so an extra file there is
  ignored by it.
- `/status` joins the board with `slot.sh --status --porcelain`, whose lines are `<n> TAB busy TAB <branch> TAB <since>`
  or `<n> TAB free`; `lib/status.awk` reads the first four fields only, so a fifth field on a line is ignored. It prints
  the slots as a second table, or `slots: none busy`, and nothing about slots when the project has no `worktrees`.
- Both shells already share one set of flags and texts per script, with a smoke test each (`tests/smoke-slot.*`,
  `tests/smoke-status.*`); the fake `gh` of iteration 17 makes `--take` and `--reap` testable without a network.

## Decisions

**1. A subcommand of `slot`, `--capacity`.** It is the shortest path, needs no new file in the plugin and keeps the state
and the slot logic in one script. The skills call it by its shell's name, as they call `--take`. A skill for it
(`/nightmill:capacity`) is not part of this story.

**2. The live values live in `<worktrees.root>/.slots/capacity.json`.** Beside the markers, untracked, shared by every
worktree, and the previous version ignores it, so the state is additive and a downgrade loses only the feature. Format
(LF, 2-space indent, only the keys that were set; `since` is the time of the last change, like the marker's):

```json
{
  "slots": 3,
  "maxAgents": 3,
  "since": "2026-11-06T09:12:00"
}
```

It is written to a temporary file in the same folder and moved over the old one, so a reader never sees half a file.

**3. Precedence.** Slot count: the live value, then `WORKER_SLOTS`, then `worktrees.slots`, then 2. Agent limit: the
live value, then `parallel.maxAgents`, then 2. A value set on purpose during the session beats the shell's
environment, which the maintainer set earlier and may have forgotten, and beats the committed file.

**4. The live values do not expire.** A script cannot tell where a Claude session ends. The values stay until
`--capacity --clear` or until set again, across new sessions, and they are shown whenever they are in force
(`slot --status`, `/status`) so they cannot be forgotten. The tracked config file is never edited.

**5. Retiring slots.** Lowering the slot count changes a number and nothing else: no worktree, no marker and no branch
is touched. A busy slot above the new count is **retiring**: it is no longer handed out (`--take` picks within the new
count only), `--status` shows it as `retiring`, and it goes on being released, reaped and abandoned like any other.
Once released it has no marker and is above the count, so it is no longer listed; its worktree stays on disk (a slot is
never removed) and is reused, warm, when the count is raised again.

**6. The agent limit is only a number a skill reads.** Lowering it stops nothing: a running agent runs on, and a skill
that wants to start another waits until fewer are running than the limit says, at the moment it decides.

**7. One source of text.** `/status` prints the capacity line by calling `slot --capacity`, so the two commands cannot
disagree.

## The command

| | bash | PowerShell |
|---|---|---|
| Show the numbers | `slot.sh --capacity` | `slot.ps1 -Capacity` |
| Set the slot count | `--capacity --slot-count N` | `-Capacity -SlotCount N` |
| Set the agent limit | `--capacity --agent-limit M` | `-Capacity -AgentLimit M` |
| Both at once | `--capacity --slot-count N --agent-limit M` | `-Capacity -SlotCount N -AgentLimit M` |
| Back to the config | `--capacity --clear` | `-Capacity -Clear` |
| For a program | `--capacity --porcelain` | `-Capacity -Porcelain` |

The names are not `--slots`/`--agents` because `slot.ps1` already has `-Slot`, and the two shells use one set.

**Show** (no value, no `--clear`) prints two lines:

```
slots: 3 (live; config 2)
agents: 3 (live; config 2)
```

The part in brackets is the source of the effective value: `live; config <c>` when `capacity.json` sets it,
`WORKER_SLOTS; config <c>` for the slot count when the environment sets it, `config` when `worktrees.slots` /
`parallel.maxAgents` is in the configuration, `default` otherwise; `<c>` is the value the configuration alone would give
(its own, or the default). Examples: `slots: 2 (config)`, `agents: 2 (default)`, `slots: 4 (WORKER_SLOTS; config 2)`.

**Set** validates every given value before it writes anything. A value is valid when it is a whole number from 1 to 99
(the rule `WORKER_SLOTS` already has; text such as `0`, `-1`, `2.5`, `x`, an empty value or `100` is not). An invalid
value changes nothing, not even a valid value given with it, writes to standard error
`capacity: --slot-count must be a whole number from 1 to 99, got "<text>"` (or `--agent-limit`) and exits 1. A valid set
prints one line and exits 0:

```
capacity: slots 2 -> 3, agents 2 -> 3
```

listing only the values that were given, each as effective-before `->` effective-after; a value that does not change is
`slots 3 (unchanged)`. `--clear` removes the file and prints `capacity: cleared (slots 3 -> 2, agents 3 -> 2)`, or
`capacity: nothing to clear` when there was none. `--clear` together with a value, a value given twice or an unknown
option is a usage error (exit 1, the usage line).

**Porcelain** prints one tab-separated line per number, in this order, and nothing else:

```
slots<TAB>3<TAB>live<TAB>2
agents<TAB>3<TAB>live<TAB>2
```

(name, effective value, source `live`, `WORKER_SLOTS`, `config` or `default`, and the value of the configuration
alone). `--capacity --porcelain` with values sets them first and then prints the new state.

**An unusable `capacity.json`** (not valid JSON, not an object, a value that is not a whole number from 1 to 99) is
ignored, key by key for a wrong value, with one note on standard error, `slot: capacity.json: <reason>; using the
configuration`, and never fails a take, a status or a reap.

## The slot scripts

- `count` is the effective slot count of decision 3 in every command (`--status`, `--take`, `--reap`, the refusal and
  the range check of `--slot`).
- `--status` prints the header it prints today (`slots = <count>  root = <root>`), then the capacity line
  `capacity: slots <n> (<source>), agents <m> (<source>)` (the same brackets as above), then one line per slot from 1 to
  the highest of `count` and the highest slot that has a marker. A busy slot above `count` reads
  `busy: <branch> since <since> (retiring)`.
- `--status --porcelain` prints the same slots; a busy slot above `count` gets a fifth field, `retiring`
  (`<n> TAB busy TAB <branch> TAB <since> TAB retiring`). Free slots above `count` are not listed.
- `--take`: unchanged except for the effective count. `--reap` and `--release` and `--abandon` work on retiring slots.
- `--capacity` needs the same configuration the other flags need (`.claude/nightmill.json` of the main checkout) and
  works with no `worktrees` section (defaults).

## `/status`

When the project has `worktrees`, `/status` prints, as its last line after the slots table (or after `slots: none busy`),
`capacity: slots <n> (<source>), agents <m> (<source>)` with the text of `slot --capacity`. Without `worktrees` it prints
nothing new. The two shells print the same. The fixtures of the smoke tests of `/status` get the line.

## The skills

The agent limit is read **each time** a skill decides whether to start an agent, by the command, not from the
configuration printed at the start of the session:

- `skills/workflow/SKILL.md`, "Parallel work", the bullet "At most `parallel.maxAgents` agents ..." becomes: at most the
  agent limit agents (subagents, slot builds, your own builds) at the same time; the limit is the live value set during
  the session, else `parallel.maxAgents`, and a skill reads it at every decision to start an agent, never once per
  session, with `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Capacity -Porcelain` or
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --capacity --porcelain` (the line `agents`, second field). When the command
  fails, use `parallel.maxAgents` of the configuration and say so.
- `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/spec/SKILL.md`: in the "Count" step, "At `parallel.maxAgents`
  wait for one to end ..." becomes "At the agent limit (read it now, as the workflow skill says) wait for one to end ...";
  in `skills/next`, step 2.2, "Respect `parallel.maxAgents` and `parallel.hotFiles`" becomes "Respect the agent limit and
  `parallel.hotFiles`".

The skills' behaviour is otherwise unchanged. A lowered limit never stops a running agent; a raised slot count is used by
the next `--take`.

## README

A subsection "Changing the numbers during a session" under "Why slots": the command in both shells, the precedence (live
value, then `WORKER_SLOTS`, then the configuration), that the values are kept until cleared and not in the tracked file,
what happens to busy slots when the count is lowered (retiring, never touched), that a lowered agent limit stops
nothing, and that `slot --status` and `/status` show the numbers and say when they are live.

## Tests

Each acceptance criterion of #78 is a test or a manual scenario. Names are the behaviour protected.

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**, the same cases in both, new section "== capacity", in the
throwaway repository the file builds (two slots, no `maxAgents` in its config):

1. **No value prints the numbers**: `slots: 2 (config)` and `agents: 2 (default)`; with `WORKER_SLOTS=4`,
   `slots: 4 (WORKER_SLOTS; config 2)`.
2. **Set prints one line and keeps the file**: setting both prints `capacity: slots 2 -> 3, agents 2 -> 3`; the file
   `capacity.json` has `slots` 3 and `maxAgents` 3; the tracked config file is byte for byte the same; showing prints
   `slots: 3 (live; config 2)` and `agents: 3 (live; config 2)`; setting only the agent limit keeps the slot count.
3. **Raising makes the slot available**: with the limit raised to 3, three takes get slots 1, 2 and 3; the worktree of
   slot 3 is created by the take (it did not exist before).
4. **Lowering never touches a busy slot**: three slots busy, count lowered to 1: the markers and worktrees of 2 and 3
   are the same; `--status` shows them `retiring`, `--status --porcelain` has the fifth field; a take fails with
   `all 1 slots are busy`; releasing slot 3 removes it from the list while slot 2 stays; releasing slot 2 leaves only
   slot 1; the worktree directories of 2 and 3 are still on disk.
5. **A raised count brings a retired slot back**: after 4, raising to 3 makes slots 2 and 3 free and takeable again.
6. **`--reap` frees a retiring slot** whose pull request has merged (the fake `gh` of iteration 17).
7. **Invalid values change nothing and say why**: `0`, `-1`, `2.5`, `x`, an empty value and `100` for each option exit 1
   with the message on standard error and leave `capacity.json` (or its absence) byte for byte as it was; a valid value
   given together with an invalid one is not written either.
8. **`--clear`**: removes the file and prints the line; a second `--clear` prints `capacity: nothing to clear`;
   `--clear` with a value is a usage error.
9. **Precedence**: live over `WORKER_SLOTS` over the configuration for the slot count; live over the configuration
   (`parallel.maxAgents` set to 5 in a copy of the config) over the default for the agent limit.
10. **Porcelain** prints exactly the two lines, with sources `live`, `WORKER_SLOTS`, `config` and `default` in the
    cases above.
11. **An unusable `capacity.json`** (not JSON, an array, `"slots": "x"`, `"slots": 0`) is ignored with the note on
    standard error and the configuration's numbers; a take still works.
12. **Nothing else changed**: the marker of a taken slot has the keys it had; `--release`, `--abandon` and the earlier
    cases pass unchanged.

**`tests/smoke-status.sh` and `tests/smoke-status.ps1`**: the expected outputs of the scenarios with `worktrees` gain the
line `capacity: slots 2 (config), agents 2 (default)` (or the numbers of the fixture's config); a new case with a
`capacity.json` in force expects `capacity: slots 3 (live; config 2), agents 3 (live; config 2)`; a project without
`worktrees` prints no capacity line.

**`tests/lint.sh`**, new section "== capacity is wired": both slot scripts contain `capacity.json` and
`--capacity` / `-Capacity`; the workflow skill, `skills/next`, `skills/fix` and `skills/spec` each contain
`--capacity --porcelain` or `-Capacity -Porcelain` (the workflow skill both) and none of the three skills still says
"At `parallel.maxAgents` wait"; the README mentions `--capacity`, `-Capacity` and `WORKER_SLOTS`.

`bash tests/check.sh` stays green.

## Verification

The skills change, so the manual check applies. In a throwaway project with nightmill installed from this checkout
(`claude --plugin-dir <checkout>`), a board and several Approved throwaway stories:

1. **Raise during a run.** Start `/next` with 2 slots busy. From a second terminal run `slot --capacity --slot-count 3
   --agent-limit 3`. The next task takes slot 3 without a restart, and the session started a third agent where it had
   waited before.
2. **Lower during a run.** With two tasks busy run `slot --capacity --slot-count 1 --agent-limit 1`. Both finish, slot 2
   is shown as retiring until it is released, and no new task or agent starts until the number running is below the limit.
3. **Nothing is stopped or removed.** The running agents and the worktrees are untouched by the command.
4. **`/status` and `slot --status`** show the numbers, say `live`, and say `config 2` while the live values are in force.
5. **`--clear`** returns the session to the configuration's numbers and the skills use them at the next decision.
6. **The config file is the same** (`git status` is clean) after all of it.

The PR's "How verified" lists the six results and the check.

## Not done

- No choice of the numbers from measured CPU or memory: the orchestration that comes later calls this command.
- No removal of a worktree from disk, no stop of a running agent, no rewrite of `.claude/nightmill.json`.
- No page or panel (#68, #69, which read what #67 records); no skill `/nightmill:capacity`.
- No `retiring` mark in the table of `/status` (only in `slot --status`); `/status` shows the capacity line.
- No upper bound above 99 and no environment variable for the agent limit.
- No change to the slot marker, to the warm-up, to the ports, to `/init`'s questions, to the status flow or to any config key.
