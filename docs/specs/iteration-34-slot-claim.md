# Iteration 34: a take claims its slot atomically and a failed take leaves no half-taken slot

Status: draft, awaiting approval (#186)

Story: #186, epic #107 (Hardening from the code review). Supersedes bug #113 (finding HI-5 of the code review of
0.2.0). A take now claims its slot before it does any work: it writes a complete marker in a new **taking** state and
publishes it under the slot's marker path in one operation that fails when the marker already exists. Only after that
does it fetch, switch the worktree and warm up. When it finishes it replaces the claim with the finished marker of
today. When the fetch, the switch or the warm-up fails, it puts the slot back as it was, removes its claim and names
the failing step and its exit code. A claim whose take died is recognised by its process id. `--abandon` frees it,
and nothing else does. Changes `scripts/slot.sh`, `scripts/slot.ps1`, `scripts/lib/json.sh` (one helper),
`tests/smoke-slot.sh`, `tests/smoke-slot.ps1`, `tests/smoke-json.sh` (one step), `README.md` and `CHANGELOG.md`. No
change to `scripts/status.*`, `scripts/lib/status.awk`, `scripts/dashboard.*`, `scripts/lib/dashboard.awk`,
`scripts/panel.*`, `hooks/panel.tsx`, `scripts/load.*`, `scripts/control.*`, `scripts/room.*`, any skill, any agent, the
schema, the config or the status flow.

**This is a story trigger**: a change to the slot marker format ("a change to the slot marker format"). The marker of
a slot that is still being taken has two more keys, `state` and `pid`. The finished marker does not change. No config
key is added, renamed or removed, and the status flow and who sets a status do not change. The pull request therefore
does **not** auto-merge, and it says so. No path in `verification.manualCheckPaths` (`skills`, `agents`, `hooks`)
changes, so **the manual check does not apply**. The smoke tests in both shells verify everything (see Tests).

**Order.** `scripts/slot.sh` and `scripts/slot.ps1` are hot files, and `parallel.doNotPair` forbids two tasks that both
change them. So this iteration is never implemented at the same time as #128 (slot numbers that are not plain
integers) or #129 (a broken slot directory). Whichever is Approved first is merged first, and the other rebases on it.
Iteration 33 (#182, `/fix all` in parallel) says that it is implemented after this story. It changes no slot script.
It adds one smoke case "at the end, before `SMOKE OK`", which then comes after this iteration's new section. Neither
spec's text changes because of that.

## Goal

A take claims its slot before it does any work, so two takes never get the same slot, and a take that fails leaves
no half-taken slot behind.

## Facts this rests on

- `--take` (both shells) first runs the reap (iteration 17). It then picks the lowest slot from 1 to the count that has
  no marker (`has_marker` / `Read-Marker`), or takes the slot given with `--slot N`. It runs `git fetch origin
  <git.baseBranch>`, adds the worktree (`git worktree add --detach <dir> <base>`) when the slot directory does not
  exist, and otherwise refuses a slot with uncommitted files. It switches to the branch (`git switch <branch>` when
  `refs/heads/<branch>` exists, else `git switch -c <branch> --no-track <base>`) and runs the warm-up. Only then does it
  write the marker. There is no lock, so two takes in that window pick the same slot (#113).
- A failure in that window leaves no marker behind. A warm-up that fails leaves the worktree on the new branch, and
  `--status` shows the slot free. In bash, `set -e` then ends the script silently with the command's exit code. In
  PowerShell, `Invoke-Warmup` throws `warm-up '<command>' failed`, and the fetch and switch throw `git fetch failed` and
  `git switch failed`, all with exit code 1.
- The marker is `<worktrees.root>/.slots/slot-N.json`. bash writes it with `json_marker` (keys `slot`, `branch`, `since`,
  LF, 2-space indent). PowerShell writes it with `ConvertTo-Json` of a hashtable, so the same three keys come in no
  fixed order (the PowerShell smoke test sorts them). After a report it has seven keys (iteration 23). Every reader
  reads it by key: `json_get` in bash, `ConvertFrom-Json` in PowerShell. A marker that exists means busy to every
  command: take, status, reap, release, abandon, report and `last_slot` / `Get-LastSlot` (retiring slots, iteration
  22).
- `--status --porcelain` prints `<n> TAB free` for a free slot, and for a busy one ten fields: `<n> busy <branch>
  <since> <retiring> <agent> <skill> <role> <step> <reported>`. `<agent>` is `running`, `stalled` or `unknown`. It is
  `unknown` for "a take with no report yet" (iteration 23, decision 5).
- The readers of that porcelain: `scripts/lib/status.awk` and `status.ps1` (a `busy` line, fields 3, 4 and 6 to 10;
  `status.ps1` parses field 4 with `ParseExact("yyyy-MM-ddTHH:mm:ss")`), `scripts/panel.*` (it accepts only `NF == 2`
  free or `NF == 10` busy lines, else the whole read is unknown), `hooks/panel.tsx` (an agent outside `running`,
  `stalled`, `unknown` is shown as `unknown`), `scripts/lib/dashboard.awk` (any other agent value is escaped, with
  class `unknown`), and `scripts/load.*` (count the lines whose field 2 is `busy`). Each script reads the porcelain of
  the slot script of its own version.
- The skills read only `Slot N is yours` from a take (`/next`, `/fix`). They report after the take (iteration 23,
  decision 3).
- `link(2)` fails with `EEXIST` when the target exists, and so does `CreateHardLinkW` on Windows (Git for Windows
  `ln`, checked: `ln: failed to create hard link '<m>': File exists`, exit 1). `[System.IO.File]::Move(src, dst)`
  without an overwrite flag fails with an `IOException` when `dst` exists (on Windows, `MoveFileEx` without
  `MOVEFILE_REPLACE_EXISTING`). Each creates the target only if it is absent, atomically, and with the full content
  of the source.
- In Git for Windows bash, `/proc/$$/winpid` holds the Windows process id of the shell. `/usr/bin/kill -0 -W <pid>`
  exits 0 while a Windows process with that id runs, also one started by PowerShell, and exits 1 (`No such process`)
  once it has ended (both checked). On Linux and macOS, `ps -p <pid>` exits 0 exactly while the process exists, for
  any owner. In PowerShell, `Get-Process -Id <pid>` finds any process on the machine.

## Decisions

**1. The claim is the marker itself, published with an exclusive create. No lock directory.** To claim slot N, a take
writes the complete taking marker (decision 2) to a temporary file in `.slots`. It then publishes the file under
`slot-N.json` with an operation that creates the target only when it does not exist:

- bash: `ln "$state/slot-N.claim.<pid>.tmp" "$state/slot-N.json"` (a hard link), then `rm -f` of the temporary file,
  whether the link succeeded or not;
- PowerShell: `[System.IO.File]::Move("<state>\slot-N.claim.<pid>.tmp", "<state>\slot-N.json")`. On failure, the
  temporary file is removed.

What is atomic: either the take's complete marker appears at `slot-N.json` in one step, or nothing changes because a
marker is already there. So of any number of takes, in either shell, that try the same slot at the same moment,
exactly one gets it. A reader never sees a half-written claim, because the file is complete before it gets its name.
The two shells are the same in effect because they act on the same path with the same "create only if absent" rule. A
bash take and a PowerShell take therefore also exclude each other. `<pid>` in the temporary name (the claim's
`pid`, decision 2) keeps two takes from sharing a temporary file. The name does not end in `.json`, so `last_slot` /
`Get-LastSlot` never sees it.

When the publish fails and `slot-N.json` exists, another take won the race. The slot is skipped as busy (see the
take, below). When it fails and `slot-N.json` does not exist (for example, a file system without hard links), the take
writes `slot N: could not claim (<first line of the error>)` to standard error, takes no other slot and exits 1.

Why not a lock directory beside the marker (#113's proposal: `mkdir` in bash, `CreateNew` in PowerShell): the
previous version reads only the marker. A claim in the marker is respected by the previous version's take, which skips
a slot that has a marker. A lock directory would be invisible to it. It would also be a second object that a killed
take can leave behind and that every command would have to read. A `mkdir` in bash and a file `CreateNew` in
PowerShell would also be two different objects, not the same in effect.

**2. The taking marker: two more keys, `state` and `pid`, after the three of today.** The claim is written once, at
the claim. Its text, LF, 2-space indent, in this order:

```
{
  "slot": 2,
  "branch": "feat/foo",
  "since": "2026-11-07T10:15:00",
  "state": "taking",
  "pid": 4242
}
```

- `slot`, `branch`, `since`: as in the finished marker. `since` is the time of the claim (local time,
  `YYYY-MM-DDTHH:MM:SS`, as today).
- `state`: the string `taking`. It is the only value written. A marker without `state` is finished, and so is a
  marker with any other value of `state` (so that a later version can add values). Those are read as today.
- `pid`: a JSON number, the operating system's process id of the take. In bash it is `$$`, or the content of
  `/proc/$$/winpid` when that file is readable (Git for Windows, MSYS2, Cygwin), so that both shells record and check
  the same kind of id on Windows. In PowerShell it is `$PID`.

bash writes it with a new helper in `scripts/lib/json.sh`, `json_marker_taking SLOT BRANCH SINCE PID`. Without PID it
writes the same text without the `pid` line, for a claim left behind (decision 5). Its header
line follows the one for `json_marker`. PowerShell writes the same bytes from explicit lines with `ConvertTo-JsonString`,
as `-Report` does. The finished marker (decision 3) is unchanged.

**3. The finished marker is today's, written over the claim in one step.** After the warm-up, the take writes the
finished marker to `slot-N.take.tmp` in `.slots` and moves it over the claim: bash `mv -f`, PowerShell
`[System.IO.File]::Replace(<tmp>, <marker>, $null)`, as `--report` does. Its content is exactly what each shell
writes today: bash `json_marker N <branch> <now>` (keys `slot`, `branch`, `since`, in that order), and PowerShell
`ConvertTo-Json` of the same three keys, as today. `since` is the time of this write, as today. So the finished marker
has neither `state` nor `pid`. Then the take prints the hints, starting with `Slot N is yours: <dir>  (branch
<branch>)`, unchanged. If the move fails, the take exits 1. The claim stays, rewritten without its `pid`
(decision 5, "A claim left behind"), so it is dead at once (decision 6), and `--abandon` frees it.

**4. The take, step by step.** After the reap (unchanged):

1. **Pick and claim.** Without `--slot`, for i from 1 to the count: skip i when it has a marker (finished or taking).
   Otherwise try to claim i (decision 1). If another take won i, go on with i + 1. The first claim that succeeds is the
   slot. When none succeeds: `all <count> slots are busy; see slot.sh --status` (PowerShell `see slot.ps1 -Status`),
   exit 1, as today. With `--slot N`: the range check as today (`slot must be 1..<count>`). A marker, or a race lost on
   N, gives `slot N is busy`, exit 1, as today.
2. **Fetch**: `git fetch origin <git.baseBranch>`.
3. **Worktree**: when the slot directory does not exist, `git worktree add --detach <dir> <base>`. The take remembers
   that it created it. When the directory exists and `git status --porcelain` is not empty, the take refuses with
   today's text, `slot N has uncommitted files; deal with them first: <dir>`. It removes its claim and exits 1.
4. **Before the switch**, the take records what it must restore: the slot's `HEAD` commit (`git rev-parse HEAD`), its
   branch if it is on one (`git symbolic-ref -q --short HEAD`, empty when detached), and whether `refs/heads/<branch>`
   existed. When it did not exist, it also records the commit `<base>` resolves to (`git rev-parse <base>^{commit}`).
   Step 4 prepares the switch, so a failure of any of its commands counts as a failure of the switch: `<step>` is
   `git switch` and `<code>` is that command's exit code (`git rev-parse` of a base that does not resolve exits 128).
   The `git symbolic-ref -q` exit 1 on a detached `HEAD` is not a failure. Nothing has been switched yet, so the
   restore (decision 5) undoes only what steps 1 to 3 did: the worktree when the take created it, and the claim.
5. **Switch** as today.
6. **Warm-up** as today: the stamps, the skip by the lockfile hash, the line `warm-up <i> in <where>: <command>`.
7. **Finish** (decision 3).

Every step from 2 to 7 runs with the claim in place. A step's exit code is read explicitly, so in bash `set -e` never
ends the take silently.

**5. A failed step puts the slot back and frees the claim.** When step 2, 3 (the `git worktree add`), 4, 5 or 6 fails, the
take restores in this order and stops at the first restore command that fails:

1. When the take created the worktree in step 3: `git worktree remove --force <dir>`. It holds nothing but the
   checkout of `<base>` and the output of the failed warm-up, so nothing is lost, and the slot is "not created yet" as
   before.
2. Otherwise, when `HEAD` or the branch differs from step 4: `git -C <dir> switch <old branch>`, or, when the slot was
   detached, `git -C <dir> switch --detach <old commit>`. There is no `--force` and no discard: changes in the tree
   that the warm-up made are carried along or make the switch fail. They are never thrown away.
3. When `refs/heads/<branch>` did not exist before and now points at the commit recorded in step 4:
   `git branch -D <branch>`. A branch that existed before is never deleted. Neither is one that has moved.
4. Remove the claim (`slot-N.json`).

Then one line on standard error, and exit 1 in both shells:

- every restore command succeeded: `<step> failed (exit <code>); slot <n> is free again`
- a restore command failed: `<step> failed (exit <code>); slot <n> could not be put back and stays claimed: free it with --abandon <n>`
  (PowerShell `-Abandon <n>`). The failed command's own error text comes before it. The claim stays, rewritten without
  its `pid` (below).

**A claim left behind is rewritten without `pid`, in both shells.** A take that exits while its claim stays (a restore
command failed, here or in the trap or `finally`, or the final move of decision 3 failed) first rewrites the claim as
decision 2's text without the `pid` line: `slot`, `branch`, `since` as in the claim, then `"state": "taking"` as the
last key (no comma after it), LF, 2-space indent. bash writes it with `json_marker_taking SLOT BRANCH SINCE` (no
fourth argument: the helper then omits the `pid` line), PowerShell from the same explicit lines. It is written to
`slot-N.claim.<pid>.tmp` and moved over the marker (bash `mv -f`, PowerShell `File.Replace`). A taking marker without
`pid` is dead (decision 6), so the claim is dead at once, whatever process stays running. That matters in PowerShell,
where `$PID` is the console's process when `slot.ps1` runs in an open session and would keep the claim live; bash
does the same so that both shells leave the same claim. If this rewrite fails as well, the claim keeps its `pid`, the
line above is printed unchanged, and the README's way out (remove the marker by hand) applies.

`<step>` is exactly one of `git fetch`, `git worktree add`, `git switch`, or `warm-up <i>`, with `<i>` the 1-based
number of the warm-up command, as in the `warm-up <i> in` line. `<code>` is the failed command's exit code. In
PowerShell, a warm-up command is run with `$global:LASTEXITCODE = 0` set first. Its code is `$LASTEXITCODE` after it,
or 1 when it threw. Examples: `git fetch failed (exit 128); slot 1 is free again`, `warm-up 1 failed (exit 7); slot 2
is free again`. These lines replace PowerShell's `git fetch failed`, `git worktree add failed`, `git switch failed` and
`warm-up '<command>' failed`, and bash's silent exit. The take's exit code on a failed step becomes 1 in bash as well
(today it is the command's code). It is the code of every other failed take, and the step's own code is in the line.

Interruption: bash traps `INT` and `TERM` and runs the same restore (`<step>` is the step running), then exits 130 or
143. PowerShell runs the restore in the `finally` of the take, which PowerShell runs on Ctrl+C. A take killed without
a chance to run either (a killed process, a closed window, a power cut) leaves its claim, which is then dead
(decision 6). The smoke tests do not test interruption.

**6. A dead claim: a taking marker whose process has ended.** A taking marker is **live** while a process with its
`pid` runs on this machine, and **dead** otherwise. The check:

- bash: when `/proc/$$/winpid` is readable, `/usr/bin/kill -0 -W <pid>`. Otherwise, `ps -p <pid>`. Exit 0 means live.
- PowerShell: `Get-Process -Id <pid> -ErrorAction SilentlyContinue` returns a process.

A `pid` that is missing, or that is not a whole number from 1 to 9999999999, means dead. No age threshold is used, so
no config key is needed. A take that hangs is ended by the person (its process). Its claim is then dead. A dead claim
is never freed automatically: the take, the reap, the release and the report leave it alone. Only `--abandon N` frees
it (decision 7), after the same checks that keep work safe today.

**7. What every command does with a taking slot (live or dead).**

| Command | Live claim | Dead claim |
|---|---|---|
| `--take` | skipped as busy; `--slot N` on it gives `slot N is busy` | the same |
| `--reap`, the reap of every take | skipped silently: never freed, never switched, no `gh` call for it | the same |
| `--release N` | refuses before any fetch or `gh` call (claim lines below), exit 1 | refuses (claim lines below), exit 1 |
| `--abandon N` | refuses (claim lines below), exit 1 | frees it (below) |
| `--report ... --slot N` | refuses (claim lines below), exit 1, marker unchanged | the same |
| `--status`, `--status --porcelain` | shown as taking (decision 8), read-only | shown as dead (decision 8) |
| capacity (`last_slot`, `Get-LastSlot`) | counts as a busy slot. Above a lowered count it is retiring: listed, never handed out, never touched. Its take goes on and finishes it as a retiring busy slot | the same |

The claim lines on standard error (PowerShell writes `-Abandon` for `--abandon`):

- live: `slot N is being taken (process <pid> is still running); wait for the take to end`
- dead: `slot N has a take that did not finish (process <pid> has ended); free it with --abandon N`

Every refusal leaves the marker byte for byte as it was.

`--abandon N` on a dead claim: when the slot directory does not exist, it removes the marker. Otherwise it checks the
tree exactly as today (`slot N has uncommitted files: <dir> (commit, stash or discard them first)`, exit 1), runs
`git -C <dir> switch --detach <base>` and removes the marker. The local branch is kept, as `--abandon` always keeps it.
Output: `Slot N is free (was <branch>, a take that did not finish; the local branch is kept, delete it yourself if
unwanted).` Nothing is lost: uncommitted files stop it, and no branch is deleted.

**8. How a taking slot looks to the readers.** The porcelain stays a ten-field `busy` line, so every reader of this
version and the previous one keeps working without change. The claim shows in field 9 (step), which is free text to
every reader:

```
<n> TAB busy TAB <branch> TAB <since of the claim> TAB <retiring or empty> TAB unknown TAB TAB TAB taking TAB
<n> TAB busy TAB <branch> TAB <since of the claim> TAB <retiring or empty> TAB unknown TAB TAB TAB take-died TAB
```

`taking` is for a live claim, and `take-died` for a dead one. **This changes iteration 23's rule for field 9**
(`docs/specs/iteration-23-slot-reports.md`, the porcelain table: "`step` as written, or empty when the key is
absent"). A marker whose `state` is `taking` has no `step` key, and field 9 reports `taking` or `take-died` for it in
place of empty. It is the one deliberate exception: every other marker (no `state`, or any other value of `state`)
keeps iteration 23's rule unchanged. Every reader of the porcelain (the list in "Facts this rests on") still passes
field 9 through as free text, so none of them changes. Field 6 is `unknown`, as iteration 23 defines it for "a
take with no report yet", so the set of agent states stays `running`, `stalled`, `unknown`. Fields 7, 8 and 10 are
empty (a claim has no report, since `--report` refuses it). The line has ten fields, and field 4 is a valid stamp for
`ParseExact`. What the others then show, unchanged code:

- `/status` (`status.sh`, `status.ps1`): the slot row `busy`, Agent `unknown`, Skill `?`, Step `taking` or
  `take-died`, Report `-`, Since the age of the claim, and its usual PR cell and flag. The `Who` column of the items
  names the slot for the branch, as for any busy slot.
- the dashboard: Agent `unknown` in its grey style, Step `taking` / `take-died`.
- the panel: `busy`, `unknown`, Step `taking` / `take-died`.
- `load`: the slot counts as busy (in use).

`--status` (text) prints, in place of `busy: <branch> since <since>`, for a live claim
`taking: <branch> since <since> (process <pid>)`, and for a dead one
`taking: <branch> since <since> (process <pid> has ended; free it with --abandon <n>)` (PowerShell `-Abandon`).
` (retiring)` follows as today. A finished marker's line is unchanged.

**9. The previous version and the new one read each other's markers.**

- New reads old: a marker of the previous version has no `state`, so it is finished and is read exactly as today. That
  covers the three-key and the seven-key markers.
- Old reads new: a finished marker is the same as before. A taking marker is valid JSON whose `slot`, `branch` and
  `since` are where and what the previous version reads by key. It ignores `state` and `pid`. So the previous
  version's `--status` shows the slot `busy: <branch> since <since>`, its porcelain shows a `busy` line with agent
  `unknown`, and its `--take` skips the slot. Running the two versions on one worktree root at the same moment is not
  protected beyond that (see Left).

## The scripts: `scripts/slot.sh` and `scripts/slot.ps1`

The same in both, with the messages verbatim:

- `marker_fields` (bash) also returns `state` and `pid`. A helper `claim_of N` / `Get-Claim N` gives `none` (no marker,
  or a finished one), `live` or `dead` (decision 6), and the pid.
- The take: decisions 1 to 5. The claim and finish helpers are `claim_slot` / `Invoke-Claim` and `finish_take` /
  `Complete-Take`. The restore is `restore_take` / `Undo-Take`, run from the failure paths and the trap (bash) or the
  `finally` (PowerShell).
- `reap_all` / `Invoke-Reap`: `continue` on any taking marker before the dirty check.
- `--release`, `--abandon`, `--report`: decision 7, checked right after "slot N is not in use".
- `--status`, `--status --porcelain`: decision 8. The comment above the porcelain loop names the two step values.
- `Invoke-Warmup` returns the failing index and code in place of throwing.
- The header comment of each script gets a paragraph after "Reports":
  `# Claim (iteration 34): a take claims its slot before it fetches, switches or warms up: it writes a marker with`
  `# "state": "taking" and its process id ("pid") and gives it the marker's name only if no marker exists (bash ln,`
  `# PowerShell File.Move), so two takes never get the same slot; the finished take replaces it with the marker above.`
  `# A failed fetch, switch or warm-up puts the slot back, removes the claim and prints "<step> failed (exit N)". A`
  `# claim whose process has ended is dead: --status shows take-died, and only --abandon frees it. Same behaviour as`
  `# slot.ps1.` (in `slot.ps1`: `-Abandon` and `slot.sh`). The sentence "A slot is busy from --take to --release ..."
  gains `(a take's claim counts as busy)`.

## README

- "Why slots", after the paragraph on the automatic release, a new paragraph: a take claims its slot before it does any
  work (a marker in the state `taking`, with the take's process id, created only if the slot has none), so two takes
  started together get different slots. A take whose fetch, switch or warm-up fails puts the slot back as it was,
  frees it and says `<step> failed (exit N)`. A take that died without finishing leaves a claim that `slot -Status`
  shows with `has ended` and `/nightmill:status` with the step `take-died`. Nothing frees it automatically, and
  `-Abandon N` (`--abandon N`) frees it once its files are dealt with, keeping the branch. If `-Abandon` says the
  process is still running but no take is (its number was reused), end that process, or remove the marker
  `<worktrees.root>/.slots/slot-N.json` by hand.
- "What a slot's agent is doing": after the sentence on **unknown**, add: `A slot still being taken shows unknown with
  the step taking; one whose take died shows the step take-died.`

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 34 (#186): a take claims its slot atomically
and a failed take leaves no half-taken slot. ...`. It names: the claim before the fetch (a marker with `"state":
"taking"` and `"pid"`, published only if absent: `ln` in bash, `File.Move` in PowerShell); the finished marker
unchanged; `<step> failed (exit N)` and the slot put back in both shells, with exit 1 in bash too; a dead claim shown
as `take-died` and freed only by `--abandon`; the readers unchanged (the porcelain step field); the previous version
reads the taking marker as busy; supersedes #113.

## Tests

**`tests/smoke-json.sh`**, one step after the `json_marker` one: `json_marker_taking 2 feat/x 2026-11-05T01:02:03 42`
is byte for byte the text of decision 2 with those values, and `json_marker_taking 2 feat/x 2026-11-05T01:02:03` is
the same text without the `pid` line and with no comma after `"state": "taking"`.

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**, one new section `== claim (iteration 34)` after `== reports`
and before `SMOKE OK`, the same cases in both. The header comment of each test names the claim.

Setup. All slots are free (abandon what the reports section left), the gh log is reset, and the count is 2. A **gate
warm-up** replaces `worktrees.warmup` in a copy of the config: one command with no `lockfile` (so it always runs) that
waits until the file `<tmp>/go` exists, polling every 0.1 s, and exits 9 after 120 s without it. bash:
`i=0; while [ ! -e '<tmp>/go' ]; do i=$((i+1)); [ $i -lt 1200 ] || exit 9; sleep 0.1; done`. PowerShell: the same with
`Test-Path` and `Start-Sleep -Milliseconds 100`, with paths written with `/`, and with `throw` in place of `exit 9`
(an `exit` inside `Invoke-Expression` would end `slot.ps1` itself). A **failing warm-up** is one command that
exits 7: bash `exit 7`, PowerShell `cmd /c exit 7`. `waitfor <n> <state>` polls every 0.1 s, for at most 60 s, until
`--status --porcelain` shows field 9 of slot n as `<state>`, and fails the test otherwise. Takes run "in the
background" are child processes started one right after the other without waiting (bash `&` with output to files,
then `wait <pid>`; PowerShell two `System.Diagnostics.Process` started before either is read). A **dead pid** is the
pid of a child process that has ended: bash `bash -c 'if [ -r /proc/$$/winpid ]; then cat /proc/$$/winpid; else echo
$$; fi'`, PowerShell `Start-Process -PassThru` of `powershell -NoProfile -Command exit`, then `WaitForExit()`. A **live
pid** is the test's own shell (bash by the same rule as the script, PowerShell `$PID`). The config is restored at the
end of the section.

1. **Two takes at the same time get different slots.** Gate warm-up. Start `--take feat/p1` and `--take feat/p2` in the
   background. `waitfor 1 taking` and `waitfor 2 taking` (both claims exist at the same time). Create `<tmp>/go` and
   wait for both. Both exit 0. Exactly one output has `Slot 1 is yours` and the other `Slot 2 is yours`. The slot
   named in each output is on that output's branch (`git branch --show-current`), and its marker has that branch.
   Both markers are finished: bash keys exactly `"slot":"branch":"since":` in that order, PowerShell the sorted keys
   `branch,since,slot`. Remove `<tmp>/go` and abandon both.
2. **A take still working is shown as taken and kept.** Gate warm-up. In the background, `--take feat/s2 --slot 2`.
   `waitfor 2 taking`. Then:
   - the marker of slot 2 is exactly decision 2's text with slot 2, `feat/s2`, its `since`, and the pid of the
     background take (bash: by the winpid rule; PowerShell: the `Id` of its process);
   - `--status` has the line `slot 2  ready           taking: feat/s2 since <since> (process <pid>)`, and has no line
     with `slot 2 ` and `free`;
   - `--status --porcelain` line 2 is exactly `2 TAB busy TAB feat/s2 TAB <since> TAB TAB unknown TAB TAB TAB taking
     TAB` (ten fields);
   - `--take feat/s1 --skip-warmup` exits 0 with `Slot 1 is yours` (the second take does not use slot 2). Abandon
     slot 1;
   - `--take feat/s9 --slot 2 --skip-warmup` exits 1 with `slot 2 is busy`;
   - `--release 2`, `--abandon 2` and `--report check --slot 2 --skill next --role implementer` each exit 1 with the
     live claim line of decision 7 (with this pid; `--abandon` in bash, `-Abandon` in PowerShell) as all of standard
     error. The gh log is empty after the release;
   - with `merged feat/s2 41 <the commit origin/main points at>` (the tip of the new branch), `--reap` prints
     `No slot freed.`;
   - `--capacity --slot-count 1`: `--status` shows `taking: feat/s2 since <since> (process <pid>) (retiring)`, and the
     porcelain field 5 of slot 2 is `retiring`;
   - after each of these, the marker of slot 2 is byte for byte the same.
   Then create `<tmp>/go` and wait. The take exits 0 with `Slot 2 is yours`. Slot 2's marker is finished (keys as in
   case 1) with `feat/s2`, and slot 2 is a retiring busy slot (porcelain `2 TAB busy TAB feat/s2`, field 5
   `retiring`). `--capacity --clear`, reset gh, abandon slot 2, remove `<tmp>/go`.
3. **A failed step puts the slot back and frees the claim.** Each sub-case checks afterwards: exit 1; standard error
   ends with exactly the line given; `slot-N.json` does not exist; no `slot-N.claim.*.tmp` and no `slot-N.take.tmp` is
   left in `.slots`; `--status` shows `slot N  ready           free` (or `not created yet free`); porcelain `N TAB free`.
   - **warm-up, existing slot, new branch.** Failing warm-up. Slot 1 exists and is detached at commit X. `--take
     feat/f1`: `warm-up 1 failed (exit 7); slot 1 is free again`. Slot 1 is detached (`branch --show-current` empty)
     at X, and `refs/heads/feat/f1` does not exist.
   - **warm-up, existing branch.** Create `feat/f2` with one commit, tip Y, not checked out anywhere. `--take feat/f2
     --slot 1`: the same line. Slot 1 is detached at X, and `refs/heads/feat/f2` is still Y.
   - **warm-up, slot not created yet.** With `WORKER_SLOTS=4` and no directory `slot-4`, `--take feat/f4 --slot 4`:
     `warm-up 1 failed (exit 7); slot 4 is free again`. The directory `slot-4` does not exist, `git worktree list`
     does not name it, and `refs/heads/feat/f4` does not exist.
   - **switch.** Normal config. `--take feat/f5 --slot 1 --base origin/nope`: `git switch failed (exit 128); slot 1 is
     free again`. Slot 1 is detached at X, and `refs/heads/feat/f5` does not exist. (The failure comes in step 4,
     `git rev-parse origin/nope^{commit}`, which counts as the switch, decision 4.)
   - **fetch.** `git remote set-url origin <tmp>/no-such.git`, then `--take feat/f6`: `git fetch failed (exit 128);
     slot 1 is free again`, and slot 1 is detached at X. Set the URL back.
   - **uncommitted files.** An untracked file in slot 1, then `--take feat/f7 --slot 1`: today's line `slot 1 has
     uncommitted files; deal with them first: <dir>`, and no marker. Remove the file.
   - **a restore that fails leaves a dead claim** (its own checks, in place of the ones above). Create `feat/f8` with
     one commit that adds the file `f8.txt`, not checked out anywhere. A warm-up of one command that changes `f8.txt`
     and exits 7 (bash `echo changed > f8.txt; exit 7`, PowerShell `Set-Content f8.txt changed; cmd /c exit 7`).
     `--take feat/f8 --slot 1`: exit 1, and standard error ends with `warm-up 1 failed (exit 7); slot 1 could not be
     put back and stays claimed: free it with --abandon 1` (PowerShell `-Abandon 1`), because the switch back to X
     would overwrite the changed `f8.txt`. Slot 1's marker is byte for byte decision 2's text for slot 1, `feat/f8`,
     its `since`, without the `pid` line. No `slot-1.claim.*.tmp` is left. Porcelain field 9 of slot 1 is `take-died`
     and `--status` names `has ended`, although the test's shell is still running (in PowerShell, the process whose
     `$PID` a claim of `slot.ps1` run in this session would carry). `--abandon 1` exits 1 with `slot 1 has uncommitted
     files:`. After `git -C <slot 1> checkout -- f8.txt`, `--abandon 1` exits 0 with `Slot 1 is free (was feat/f8, a
     take that did not finish; the local branch is kept, delete it yourself if unwanted).`. Delete `feat/f8`.
4. **A dead claim is recognised and freed only by abandon, without losing work.** `--take feat/d1 --slot 1
   --skip-warmup`, then overwrite slot 1's marker with a taking marker for `feat/d1` with a dead pid (the take died
   after its switch). Then:
   - `--status` has `taking: feat/d1 since <since> (process <pid> has ended; free it with --abandon 1)` (PowerShell
     `-Abandon 1`). Porcelain field 9 of slot 1 is `take-died` and field 6 is `unknown`;
   - `--take feat/d2 --skip-warmup` gets `Slot 2 is yours`. Abandon slot 2;
   - `--release 1` and `--report check --slot 1 --skill next --role implementer` exit 1 with the dead claim line as
     all of standard error. `--reap` with `merged feat/d1 42 <tip of feat/d1>` prints `No slot freed.`. Each leaves the
     marker byte for byte;
   - with an untracked file in slot 1, `--abandon 1` exits 1 with `slot 1 has uncommitted files:`, and the marker and
     the file stay. Remove the file;
   - `--abandon 1` exits 0 and prints exactly `Slot 1 is free (was feat/d1, a take that did not finish; the local
     branch is kept, delete it yourself if unwanted).`. The marker is gone, slot 1 is detached at `origin/main`, and
     `refs/heads/feat/d1` is still its tip;
   - a taking marker for slot 1 with the **live** pid: `--abandon 1` exits 1 with the live claim line, and the marker
     stays. Then the same marker without the `pid` line: `--status --porcelain` field 9 is `take-died`. Remove it;
   - a dead taking marker for slot 4 with `WORKER_SLOTS=4`, and no directory `slot-4` (case 3 removed it):
     `--abandon 4` exits 0 with `Slot 4 is free (was feat/d4, a take that did not finish; the local branch is kept,
     delete it yourself if unwanted).`, and the marker is gone.
5. **Markers across versions.**
   - The taking marker of case 2, read the way the previous version reads it (bash `json_load` + `json_get`,
     PowerShell `ConvertFrom-Json`), gives `slot` 2, `branch` `feat/s2` and its `since`. A busy line of the previous
     version's form comes from it: `--status --porcelain` field 2 is `busy`.
   - Markers of the previous version are not claims: a three-key marker (`json_marker 1 feat/v1
     2026-11-05T09:00:00`) and a seven-key one (`hand` of the reports section) each give porcelain field 9 empty or the
     reported step (never `taking` or `take-died`), are skipped by a take, and are abandoned with today's line `Slot 1
     is free (was <branch>; the local branch is kept, delete it yourself if unwanted).`. A marker with `"state":
     "done"` is read as finished.
   - When the clone of nightmill has a release tag (`git -C <here> tag --list 'v*' --sort=-v:refname`, the first),
     the test writes that version's `scripts/slot.sh` (and `lib/json.sh`, `lib/json.awk`) or `scripts/slot.ps1` to
     `<tmp>/prev` with `git show <tag>:<path>`. Against a taking marker for slot 1 (live pid), its `--status` shows
     `busy: feat/v1 since`, and its `--take feat/v2 --skip-warmup` gets `Slot 2 is yours`. Without a tag (a shallow CI
     clone), the test prints `skipped: no release tag to run the previous version` and goes on.

The existing cases still pass unchanged. That includes "10 the marker format is unchanged" and "12 nothing else
changed: the marker keys", because the finished marker is today's, and every refusal and output text of the other
sections. `bash tests/check.sh` stays green and runs both shells where the machine can.

**What each criterion is checked by.** All in both smoke tests, unless named.

| Criterion | Cases |
|---|---|
| 1 two takes at nearly the same time get different slots, both shells | claim 1 |
| 2 claimed atomically before fetch, switch, warm-up; the same in effect in both shells | claim 1 (both claims seen during the warm-up), claim 3 fetch (a claim existed: none is left after the failure); decision 1 |
| 3 while working, `--status` shows it taken and a second take does not use it | claim 2 |
| 4 finished marker as today; the take prints the caller's slot | claim 1, claim 2 (the end); the existing cases 10 and 12 |
| 5 a failed fetch, switch or warm-up frees the claim, puts the slot back, names the step and code | claim 3 |
| 6 a dead claim is recognised and can be freed, a live one is not, no work lost | claim 4, claim 3 (a restore that fails leaves a dead claim) |
| 7 release, abandon, reap, report, capacity treat a taking slot as defined | claim 2 (live), claim 4 (dead) |
| 8 the previous version reads the new markers, and the new reads the old | claim 5; smoke-json step |
| 9 README and the header comments describe the claim and the state | review of the diff (the header paragraph and README text above) |

## Verification

`bash tests/check.sh` on the branch, with both smoke tests (bash, and PowerShell where the machine has it; CI runs
both). The manual check does not apply: no skill, agent or hook changes. The PR's "How verified" names the check, its
skipped list (and whether claim case 5's previous-version run was skipped), and says that auto-merge is off because
the change is a story trigger (the slot marker format).

## Not done

- No lock between a person's own checkout and a slot, or between machines (the pid is checked on this machine only).
- No automatic freeing of a dead claim (no age threshold, no config key). Only `--abandon` frees it.
- No change to what `--reap` judges or how a slot is released after a merge (iteration 17), beyond skipping taking
  markers.
- No change to which slot a take prefers (the lowest free one), to slot numbers that are not plain integers (#128) or
  to a broken slot directory (#129). A `git worktree add` that fails part-way is only followed by removing the claim.
- No change to the finished marker, `--report`'s marker, `capacity.json`, the warm-up stamps or the ports.
- No change to `status`, the dashboard, the panel, `load`, `control` or `room`, and no new agent state. The claim shows
  through the porcelain step field.
- No new flag, no config key, no change to any skill or agent, to the status flow or to who sets a status. No decision
  record.

## Left

- **A reused process id.** A dead take's pid that the system has given to another process makes the claim look live,
  so `--abandon` refuses. This errs on the safe side (a working slot is never freed). The way out is in the README: end
  that process, or remove the marker by hand. A check of the process's start time would close the gap. It is left out
  because no form of it works the same on Linux, macOS, Git for Windows and PowerShell without more code than the
  rest of the claim. The maintainer confirms at Spec review that this limit is acceptable.
- **Two versions at once.** The previous version respects a claim only by skipping it in `--take`. Its `--abandon`,
  `--release` and `--report`, run against a slot that a new take is still claiming, act on it as on any busy slot.
  Its reap could free such a slot only if the branch being taken already exists at the head of a merged pull request.
  This needs both versions running against one worktree root at the same moment, which an upgrade does not do on its
  own. It is not guarded further.
- **File systems without hard links** (for example exFAT, some network shares) under `worktrees.root`: the bash take
  fails with `slot N: could not claim (...)` and never claims silently twice. PowerShell's `File.Move` works there. If
  this matters to a project, it is a separate bug.
