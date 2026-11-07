# Iteration 34: a take claims its slot atomically and a failed take leaves no half-taken slot

Status: delivered in iteration 34 (PR #194)

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
  class `unknown`), `scripts/load.*` (count the lines whose field 2 is `busy`), and `scripts/control.*` (also counts
  the lines whose field 2 is `busy`: `control.sh` with `awk -F '\t' '$2 == "busy"'`, `control.ps1` by splitting each
  line at tabs). Each script reads the porcelain of the slot script of its own version.
- The skills read only `Slot N is yours` from a take (`/next`, `/fix`). They report after the take (iteration 23,
  decision 3).
- `link(2)` fails with `EEXIST` when the target exists, and so does `CreateHardLinkW` on Windows (Git for Windows
  `ln`, checked: `ln: failed to create hard link '<m>': File exists`, exit 1). On Windows,
  `[System.IO.File]::Move(src, dst)` without an overwrite flag is `MoveFileEx` without `MOVEFILE_REPLACE_EXISTING`
  and fails with an `IOException` when `dst` exists. Each of these creates the target only if it is absent,
  atomically, and with the full content of the source. (On Linux and macOS, .NET's `File.Move` is `link` and `unlink`,
  and where the file system has no hard links it falls back to a check for `dst` followed by `rename`, which is not
  atomic. `slot.ps1` is run with Windows PowerShell, on Windows, as CI runs it.)
- In Git for Windows bash, `/proc/$$/winpid` holds the Windows process id of the shell. `/usr/bin/kill -0 -W <pid>`
  exits 0 while a Windows process with that id runs, also one started by PowerShell, and exits 1 (`No such process`)
  once it has ended (both checked). On Linux, `/proc/<pid>` is a directory exactly while a process with that id
  exists, for any owner unless `/proc` is mounted with `hidepid`; that holds for BusyBox systems too, whose `ps` has no
  `-p` option (it prints its usage and exits 1). On macOS, which has no `/proc`, `ps -p <pid>` exits 0 exactly while
  the process exists, for any owner. In PowerShell, `Get-Process -Id <pid>` finds any process on the machine; its
  `-Id` is an `Int32`, so a number above 2147483647 makes it throw instead of finding nothing.
- On Windows, a file that a reader has opened without `FILE_SHARE_DELETE` (PowerShell's `Get-Content` and
  `[System.IO.File]::ReadAllText` open it that way) cannot be replaced or deleted while it is open: `MoveFileEx` with
  replace (the `mv -f` of Git for Windows), `File.Replace`, `Remove-Item` and the `rm` of Git for Windows fail with a
  sharing violation, also when they act on another hard link of the same file. A reader holds a marker for
  milliseconds.
- `git fetch` updates `refs/remotes/origin/<base>` under a lock and checks the old value it read. Two fetches that run
  at the same time after origin has moved both try to update it, and the one that loses fails (`cannot lock ref
  'refs/remotes/origin/<base>': is at <new> but expected <old>`, or `Unable to create '...lock': File exists`), exit
  1 or 128. A fetch that starts after the other has finished succeeds.
- Git on Linux and macOS runs a hook only when the file has the execute bit (otherwise it warns `hook was ignored
  because it's not set as executable` and goes on). Git for Windows runs a hook file whose first line starts with
  `#!`, whatever its mode.

## Decisions

**1. The claim is the marker itself, published with an exclusive create. No lock directory.** To claim slot N, a take
writes the complete taking marker (decision 2) to a temporary file in `.slots`. It then publishes the file under
`slot-N.json` with an operation that creates the target only when it does not exist:

- bash: `ln "$state/slot-N.claim.<pid>.tmp" "$state/slot-N.json"` (a hard link), then `rm -f` of the temporary file,
  whether the link succeeded or not (the removal after a successful link: below);
- PowerShell: `[System.IO.File]::Move("<state>\slot-N.claim.<pid>.tmp", "<state>\slot-N.json")`. On failure, the
  temporary file is removed.

What is atomic: either the take's complete marker appears at `slot-N.json` in one step, or nothing changes because a
marker is already there. So of any number of takes, in either shell, that try the same slot at the same moment,
exactly one gets it. A reader never sees a half-written claim, because the file is complete before it gets its name.
The two shells are the same in effect because they act on the same path with the same "create only if absent" rule. A
bash take and a PowerShell take therefore also exclude each other. That holds for bash on Linux, macOS and Git for
Windows, and for `slot.ps1` on Windows (the facts above); it is not claimed for `slot.ps1` under PowerShell 7 on a
Linux or macOS file system without hard links (see Left). `<pid>` in the temporary name (the claim's `pid`, decision
2) keeps two takes from sharing a temporary file. The name does not end in `.json`, so `last_slot` / `Get-LastSlot`
never sees it. The publish is not retried: a publish that fails because a marker exists means busy. For the tests
only, an environment variable `NIGHTMILL_CLAIM_GATE` holds the take at the publish (decision 15).

**After a successful `ln` (bash only; `File.Move` leaves no second name).** The temporary name is a second name of the
marker, so its `rm -f` can fail on Windows while a reader holds the marker open (the facts). That failure is not an
error: the take reads `rm`'s exit code explicitly (no `set -e` exit), leaves `rm`'s own message on standard error,
prints nothing else and goes on with step 2; the leftover name, which no command reads, stays in `.slots`. No write goes
through it: the take never writes to `slot-N.claim.<pid>.tmp` again (the rewrite of decision 5 uses
`slot-N.left.<pid>.tmp`), and bash writes the claim's and the rewrite's temporary files with `noclobber` (`set -C`), so
an existing file of that name makes the write fail (handled below, or as a failed rewrite) instead of writing into it.

When the publish fails and `slot-N.json` exists, another take won the race. The slot is skipped as busy (see the
take, below). When it fails and `slot-N.json` does not exist (for example, a file system without hard links), the take
writes `slot N: could not claim (<first line of the error>)` to standard error, takes no other slot and exits 1.

When writing the temporary file itself fails (before the publish: for example `.slots` is read-only or the disk is
full), the take writes to standard error, after the error's own text (bash: the shell's message for the failed
redirection; PowerShell: the take writes the first line of the exception's message), the line
`claim failed (exit <code>); slot <n> was not claimed`. `<code>` is the write's exit status in bash (1 for a failed
redirection) and 1 in PowerShell (the write threw). It removes `slot-N.claim.<pid>.tmp` when it exists (`rm -f`, or
`Remove-Item -ErrorAction SilentlyContinue`), touches no marker, tries no other slot, runs no fetch and exits 1, in
both shells. Example: `claim failed (exit 1); slot 1 was not claimed`.

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
writes the same text without the `pid` line, for a claim left behind (decision 5). Its header line follows the one for
`json_marker`. PowerShell writes the same bytes from explicit lines with `ConvertTo-JsonString`, as `-Report` does.
The finished marker (decision 3) is unchanged.

**3. The finished marker is today's, written over the claim in one step.** After the warm-up, the take writes the
finished marker to `slot-N.take.tmp` in `.slots` and moves it over the claim: bash `mv -f`, PowerShell
`[System.IO.File]::Replace(<tmp>, <marker>, [NullString]::Value)`, as `--report` does (a literal `$null` would be
passed as an empty string, which `File.Replace` rejects as a backup path). The move is tried once (retries: #189).
Its content is exactly what each shell writes today: bash `json_marker N <branch> <now>` (keys `slot`, `branch`,
`since`, in that order), and PowerShell `ConvertTo-Json` of the same three keys, as today. `since` is the time of this
write, as today. So the finished marker has neither `state` nor `pid`. Then the take prints the hints, starting with
`Slot N is yours: <dir>  (branch <branch>)`, unchanged.

When writing `slot-N.take.tmp` fails, or the move over the claim fails, the take does not undo the switch or the
warm-up (they succeeded; the slot is ready, only its marker is not finished). In both shells it then:

1. removes `slot-N.take.tmp` when it exists (`rm -f`, or `Remove-Item -ErrorAction SilentlyContinue`);
2. leaves the claim in place, rewritten without its `pid` (decision 5, "A claim left behind"), so it is dead at once
   (decision 6) and `--abandon` frees it; the worktree and the branch stay as they are;
3. writes to standard error, after the error's own text (as for the claim's temporary file, decision 1), the line
   `write marker failed (exit <code>); slot <n> stays claimed: free it with --abandon <n>` (PowerShell
   `-Abandon <n>`). `<code>` is the failed command's exit status in bash (`mv -f`, or 1 for a failed redirection)
   and 1 in PowerShell (the write or `File.Replace` threw);
4. prints no hints and exits 1.

**4. The take, step by step.** After the reap (unchanged):

1. **Pick and claim.** Without `--slot`, for i from 1 to the count: skip i when it has a marker (finished or taking).
   Otherwise try to claim i (decision 1). If another take won i, go on with i + 1. The first claim that succeeds is the
   slot. When none succeeds: `all <count> slots are busy; see slot.sh --status` (PowerShell `see slot.ps1 -Status`),
   exit 1, as today. With `--slot N`: the range check as today (`slot must be 1..<count>`). A marker, or a race lost on
   N, gives `slot N is busy`, exit 1, as today.
2. **Fetch**: `git fetch origin <git.baseBranch>`, at most 3 attempts, 1 s apart (decision 11).
3. **Worktree**: when the slot directory does not exist, `git worktree add --detach <dir> <base>`. The take remembers
   that it created it. When the directory exists and `git status --porcelain` is not empty, the take refuses with
   today's text, `slot N has uncommitted files; deal with them first: <dir>`. It removes its claim (one attempt) and
   exits 1. When that removal fails, the removal's own error text comes before the line, and the claim stays,
   rewritten without its `pid` (decision 5, "A claim left behind"), so `--abandon` frees it.
4. **Before the switch**, the take records what it must restore, with these commands (all `git -C <dir>`):
   - the slot's `HEAD` commit: `git rev-parse HEAD`;
   - its branch if it is on one: `git symbolic-ref -q --short HEAD` (exit 0 and the name; exit 1 and nothing when
     `HEAD` is detached);
   - whether `refs/heads/<branch>` existed: `git show-ref --verify --quiet refs/heads/<branch>` (exit 0: it existed;
     exit 1: it did not);
   - when it did not exist, the commit `<base>` resolves to: `git rev-parse <base>^{commit}`.

   Step 4 prepares the switch, so a failure of any of its commands counts as a failure of the switch: `<step>` is
   `git switch` and `<code>` is that command's exit code (`git rev-parse` of a base that does not resolve exits 128).
   A failure is an exit code other than 0 for the two `git rev-parse`, and a code other than 0 or 1 for
   `git symbolic-ref -q` and `git show-ref --verify --quiet`, whose exit 1 is an answer (detached; no such branch),
   not a failure. Nothing has been switched yet, so the restore (decision 5) undoes only what steps 1 to 3 did: the
   worktree when the take created it, and the claim.
5. **Switch** as today.
6. **Warm-up** as today: the stamps, the skip by the lockfile hash, the line `warm-up <i> in <where>: <command>`.
   The hash of the lockfile (bash `sha256`, PowerShell `Get-FileHash`), the read of the stamp and the write of the
   stamp belong to warm-up command `<i>`: when one of them fails, step 6 fails as `warm-up <i>`, with that command's
   exit code in bash (the status of `sha256sum` or `shasum`, of `cat`, or 1 for a failed redirection) and 1 in
   PowerShell (it threw). PowerShell reads the stamp only when it is a file (`Test-Path -LiteralPath <stamp> -PathType
   Leaf`), as bash's `[ -f ]` does, so that both shells run the command and then fail at the same write.
7. **Finish** (decision 3).

Every step from 2 to 7 runs with the claim in place. A step's exit code is read explicitly, so in bash `set -e` never
ends the take silently. In PowerShell, every refusal of the take (texts as today, today `throw`s), every line of
decisions 1, 3 and 5 and the claim lines of decision 7 are one plain line on standard error
(`[Console]::Error.WriteLine`) and then `exit 1`, never a `throw`, so standard error ends with that line and no error
record, as in bash. Step 1's refusals come before any claim exists, so nothing is restored for them.

**5. A failed step puts the slot back and frees the claim.** When step 2, 3 (the `git worktree add`), 4, 5 or 6 fails, the
take restores in this order and stops at the first restore command that fails. Items 2 to 4 apply only once step 4
has run to its end; after a failure in step 2, 3 or 4 only items 1 and 5 run (decision 4):

1. When the take created the worktree in step 3: `git worktree remove --force <dir>`. It holds nothing but the
   checkout of `<base>` and the output of the failed warm-up, so nothing is lost, and the slot is "not created yet" as
   before.
2. Otherwise, when the take passed step 3 on a slot that existed and `git -C <dir> status --porcelain` is not empty
   now: the restore switches nothing and stops here, as at a failed restore command (decision 10). In place of a
   command's error text, it writes `slot <n> has uncommitted files: <dir> (commit, stash or discard them first)`
   before the outcome line below.
3. Otherwise, when `HEAD` or the branch differs from step 4: `git -C <dir> switch <old branch>`, or, when the slot was
   detached, `git -C <dir> switch --detach <old commit>`. There is no `--force` and no discard. The tree is clean at
   this point (item 2), so the switch carries nothing into the slot it frees.
4. When `refs/heads/<branch>` did not exist before and now points at the commit recorded in step 4:
   `git branch -D <branch>`. A branch that existed before is never deleted. Neither is one that has moved.
5. Remove the claim (`slot-N.json`), one attempt (retries: #189). A failed removal is a failed restore command.

Then one line on standard error, and exit 1 in both shells:

- every restore command succeeded: `<step> failed (exit <code>); slot <n> is free again`
- a restore command failed: `<step> failed (exit <code>); slot <n> could not be put back and stays claimed: free it with --abandon <n>`
  (PowerShell `-Abandon <n>`). The failed command's own error text comes before it. The claim stays, rewritten without
  its `pid` (below).

**A claim left behind is rewritten without `pid`, in both shells.** A take that exits while its claim stays (a restore
command failed, the removal of step 3 failed, or the write or the move of decision 3 failed) first rewrites the claim as
decision 2's text without the `pid` line: `slot`, `branch`, `since` as in the claim, then `"state": "taking"` as the
last key (no comma after it), LF, 2-space indent. bash writes it with `json_marker_taking SLOT BRANCH SINCE` (no
fourth argument: the helper then omits the `pid` line), PowerShell from the same explicit lines. It is written to
`slot-N.left.<pid>.tmp` (bash with `noclobber`, decision 1) and moved over the marker (bash `mv -f`, PowerShell
`File.Replace` with `[NullString]::Value`, as in decision 3), one attempt; when the move fails, `slot-N.left.<pid>.tmp`
is removed (`rm -f`, `Remove-Item -ErrorAction SilentlyContinue`). A taking marker without
`pid` is dead (decision 6), so the claim is dead at once, whatever process stays running. That matters in PowerShell,
where `$PID` is the console's process when `slot.ps1` runs in an open session and would keep the claim live; bash
does the same so that both shells leave the same claim. If this rewrite fails as well, the claim keeps its `pid`, the
line above is printed unchanged, and the README's way out (remove the marker by hand) applies.

`<step>` is exactly one of `git fetch`, `git worktree add`, `git switch`, or `warm-up <i>`, with `<i>` the 1-based
number of the warm-up command, as in the `warm-up <i> in` line. (Step 1 and step 7 have their own lines with the
step names `claim` and `write marker`: decisions 1 and 3.) `<code>` is the failed command's exit code. In
PowerShell, a warm-up command is run with `$global:LASTEXITCODE = 0` set first. Its code is `$LASTEXITCODE` after it,
or 1 when it threw. Examples: `git fetch failed (exit 128); slot 1 is free again`, `warm-up 1 failed (exit 7); slot 2
is free again`. These lines replace PowerShell's `git fetch failed`, `git worktree add failed`, `git switch failed` and
`warm-up '<command>' failed`, and bash's silent exit. The take's exit code on a failed step becomes 1 in bash as well
(today it is the command's code). It is the code of every other failed take, and the step's own code is in the line.

**An interrupted take is not cleaned up by the scripts** (#190: no trap, no `finally`). A take stopped after its claim
(Ctrl+C, a signal, a closed window, a killed process) restores nothing and leaves its claim with its `pid`. Once its
process has ended, that is a dead claim (decision 6), shown as `take-died` and freed by `--abandon N` without losing
work (criterion 6). A `slot.ps1` take stopped in an open console carries the console's `$PID`, so its claim stays live
until the console closes (the README's way out applies).

**6. A dead claim: a taking marker whose process has ended.** A taking marker is **live** while a process with its
`pid` runs on this machine, and **dead** otherwise. The check:

- bash, the first rule that applies (decision 12):
  1. when `/proc/$$/winpid` is readable (Git for Windows, MSYS2, Cygwin): live when `/usr/bin/kill -0 -W <pid>` exits 0;
  2. otherwise, when `/proc/self` is a directory (Linux, BusyBox included): live while `/proc/<pid>` is a directory;
  3. otherwise, when `ps` is on the `PATH` (macOS, the BSDs): live when `ps -p <pid>` exits 0;
  4. otherwise: live, because nothing can tell (the safe side).
- PowerShell: live when `Get-Process -Id <pid> -ErrorAction SilentlyContinue` returns a process.

A `pid` that is missing, or that is not a whole number from 1 to 2147483647 (decision 13), means dead, and no process
check runs for it. bash tests the text of `pid` against `^[1-9][0-9]{0,9}$` and then `-le 2147483647`; PowerShell
reads it with `Get-Text`, tests it against `^[1-9][0-9]{0,9}\z` and `[long]<text> -le 2147483647`, and only then
calls `Get-Process -Id ([int]<text>)`. Such a claim has no process to name, so its texts say `no process recorded`
where a dead claim with a `pid` says `process <pid> has ended` (decisions 7 and 8 give each text). Every claim left
behind is one (decision 5). No age threshold is used, so no config key is needed. A take that hangs is ended by the
person (its process). Its claim is then dead. A dead claim is never freed automatically: the take, the reap, the
release and the report leave it alone. Only `--abandon N` frees it (decision 7), after the same checks that keep work
safe today.

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
- dead, without a usable `pid` (missing or not a whole number, decision 6; every claim left behind):
  `slot N has a take that did not finish (no process recorded); free it with --abandon N`

A live claim always has a `pid`, so the live line always names one. Every refusal leaves the marker byte for byte as
it was. PowerShell writes them as plain lines (decision 4).

`--abandon N` on a dead claim: when the slot directory does not exist, it removes the marker. Otherwise it checks the
tree exactly as today (`slot N has uncommitted files: <dir> (commit, stash or discard them first)`, exit 1), runs
`git -C <dir> switch --detach <base>` and removes the marker. The local branch is kept, as `--abandon` always keeps it.
Output: `Slot N is free (was <branch>, a take that did not finish; the local branch is kept, delete it yourself if
unwanted).` The same text with or without a `pid`: it names no process. Nothing is lost: uncommitted files stop it,
and no branch is deleted.

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
place of empty. It is deliberate and listed with the other deviations in "Deviations from earlier specs": every
other marker (no `state`, or any other value of `state`) keeps iteration 23's rule unchanged. Every reader of the porcelain (the list in "Facts this rests on") still passes
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
- `control`: the slot counts among the busy slots it measures (field 2 is `busy`).

`--status` (text) prints, in place of `busy: <branch> since <since>`, for a live claim
`taking: <branch> since <since> (process <pid>)`, and for a dead one
`taking: <branch> since <since> (process <pid> has ended; free it with --abandon <n>)`, and for a dead one without
a usable `pid` (decision 6) `taking: <branch> since <since> (no process recorded; free it with --abandon <n>)`
(PowerShell `-Abandon` in both). ` (retiring)` follows as today, so a taking slot above the count reads `taking:
<branch> since <since> (process <pid>) (retiring)`: this changes iteration 22's text for a retiring busy slot and is
listed in "Deviations from earlier specs". A finished marker's line is unchanged. The porcelain
does not name the process: a dead claim gives `take-died` in field 9 with or without a `pid`.

**9. The previous version and the new one read each other's markers.**

- New reads old: a marker of the previous version has no `state`, so it is finished and is read exactly as today. That
  covers the three-key and the seven-key markers.
- Old reads new: a finished marker is the same as before. A taking marker is valid JSON whose `slot`, `branch` and
  `since` are where and what the previous version reads by key. It ignores `state` and `pid`. So the previous
  version's `--status` shows the slot `busy: <branch> since <since>`, its porcelain shows a `busy` line with agent
  `unknown`, and its `--take` skips the slot. Running the two versions on one worktree root at the same moment is not
  protected beyond that (see Left).

**10. A tree that the failed take left with changes is not switched back; the claim stays.** Step 3 lets a take go on
in an existing slot only when its tree is clean, so every change found after a failed step 4, 5 or 6 was made by the
take (its switch or its warm-up): a changed tracked file, or a new file that is not ignored. The restore then does not
switch (decision 5, item 2): the slot stays on the take's branch with the files as they are, the branch is not
deleted, the claim stays rewritten without its `pid` (dead at once), and the lines are
`slot <n> has uncommitted files: <dir> (commit, stash or discard them first)` and then `<step> failed (exit <code>);
slot <n> could not be put back and stays claimed: free it with --abandon <n>`. Files that `.gitignore` covers do not
count (`git status --porcelain` does not list them), so a warm-up that fails after writing build output into ignored
paths is put back and freed as before. A slot the take created in step 3 is removed whole (decision 5, item 1).

Why: a switch back would carry the changes or untracked files into a slot it reports free. The next take refuses
that slot (`slot N has uncommitted files`), and `--abandon` refuses it (`slot N is not in use`, no marker), so
nothing could free it, and the slot would not be as it was. Discarding them (`git reset --hard`, `git clean`) would
put the slot back but throw away files, which the story forbids, and they may be what the person needs to see why the
warm-up failed. A dead claim keeps the slot out of use and names the way out: deal with the files, then `--abandon N`,
which checks the tree again and keeps the branch.

**11. The take's fetch is tried up to 3 times.** Step 2 runs `git fetch origin <git.baseBranch>`. When it fails, the
take waits 1 s and runs it again, at most 3 attempts in all, so at most 2 waits, 2 s in all. The step fails only when the third attempt fails, with that
attempt's exit code in the line. Git's own error text of each failed attempt goes to standard error as it comes, and
nothing else is printed between attempts. 3 and 1 s are numbers in the scripts, not config keys.

Why: two takes that overlap fetch at the same time, and when origin has moved, the one that loses the lock on
`refs/remotes/origin/<base>` fails (the facts). The lock is held for milliseconds, so the next attempt a second later
succeeds. A fetch that fails for another reason (a wrong URL, no network) fails 2 s later than today, with the claim
held, which no other take needs (it skips the slot). The reap's own fetch (iteration 17) is unchanged: when it fails
it only leaves a slot unjudged and never fails a take.

**12. Liveness without `ps -p`.** bash checks a `pid` by the first rule of decision 6 that applies: the Windows id
through `kill -W` where there is a `winpid`, then `/proc/<pid>` where there is a `/proc`, then `ps -p`, and when none
is there the claim counts as live. Why: BusyBox's `ps` has no `-p`, so `ps -p` would read every claim dead there and
`--abandon` would free a slot whose take is still working. `/proc/<pid>` exists on every Linux, BusyBox included, and
for every owner. macOS has no `/proc` and its `ps -p` works. When nothing can tell, live is the safe side: `--abandon`
refuses, and the way out is the one for a reused process id (README: end the process or remove the marker by hand).

**13. A `pid` is usable from 1 to 2147483647.** Why: `Get-Process -Id` takes an `Int32` and throws for a larger
number, which would end `slot.ps1` in the middle of a refusal instead of reading the claim dead. Every `pid` a take
writes (`$$`, a `winpid`, `$PID`) is in that range: Linux's `pid_max` is at most 4194304, and Windows process ids are
far below 2^31. Both shells use the same range, so a marker reads the same in both. A `pid` outside it means dead with
`no process recorded`.

**14. The take's own marker changes are tried once** (the finish, decision 3; the rewrite and the removal, decision 5).
A reader holding the marker on Windows can make one fail; decisions 3 and 5 say what follows. Retries are #189.

**15. A gate for the tests at the publish: `NIGHTMILL_CLAIM_GATE`.** When the environment variable
`NIGHTMILL_CLAIM_GATE` is set and not empty, every publish of decision 1 waits, after the temporary file is written
and before the `ln` or `File.Move`, until a file at that path exists, polling every 0.1 s, at most 60 s, and then
publishes either way. Unset (always, outside the tests) it changes nothing. It is an environment variable used only by
the tests, as `NIGHTMILL_NOW` is for the clock of `--status --porcelain`: not a config key, not in the schema and not
in the README. Why: two takes that start together reach the publish microseconds apart at best, so no test could hold
them at the moment between "no marker" and "marker". The gate holds both there, so that claim case 7 fails for a
take that checks and then writes, or that publishes by replacing, in the same shell and across the two shells.

## Deviations from earlier specs

This iteration deliberately changes five rules of earlier specs, each only for a marker whose `state` is `taking`
(decision 2). For every other marker, and in every other respect, all rules of iterations 17, 22 and 23 stay as
they are. Those specs' text is not edited; this list is the record of the change.

| Spec | The rule there, verbatim | The rule from this iteration on |
|---|---|---|
| `docs/specs/iteration-17-slot-auto-release.md`, "The rule" | "`slot.sh --reap` and `slot.ps1 -Reap`, and the first step of every take, look at each busy slot (a marker exists, in slot order) and free it when **all** of these hold; otherwise they leave it exactly as it is:" | The reap looks at each busy slot whose marker is not a taking marker. A slot with a taking marker (live or dead) is skipped before rule 1: not judged, never freed, never switched, no `gh` call for it (decision 7). |
| `docs/specs/iteration-22-capacity.md`, decision 5 | "it goes on being released, reaped and abandoned like any other." | A retiring slot whose marker is finished goes on being released, reaped and abandoned like any other. A retiring slot with a taking marker is treated as any taking slot (decision 7): `--release` refuses it, the reap skips it, `--abandon` refuses a live claim and frees a dead one. Its take goes on and finishes it as a retiring busy slot. |
| `docs/specs/iteration-22-capacity.md`, "The slot scripts" | "A busy slot above `count` reads `busy: <branch> since <since> (retiring)`." | A busy slot above `count` whose marker is finished reads that. One with a taking marker reads `taking: <branch> since <since> (process <pid>) (retiring)`, or the dead claim's text of decision 8 followed by ` (retiring)`. |
| `docs/specs/iteration-23-slot-reports.md`, "Report a step" | "It works on any slot that has a marker, also a retiring one (#78)." | `--report` works on any slot that has a finished marker, also a retiring one. On a slot with a taking marker it refuses with the claim line of decision 7, exit 1, the marker byte for byte unchanged. |
| `docs/specs/iteration-23-slot-reports.md`, the porcelain table, fields 7, 8, 9 | "`skill`, `role`, `step` as written, or empty when the key is absent" | Unchanged for every marker without `state: taking`. For a taking marker, field 9 is `taking` (live) or `take-died` (dead), and fields 7 and 8 are empty (decision 8). |

## The scripts: `scripts/slot.sh` and `scripts/slot.ps1`

The same in both, with the messages verbatim:

- `marker_fields` (bash) also returns `state` and `pid`. A helper `claim_of N` / `Get-Claim N` gives `none` (no marker,
  or a finished one), `live` or `dead` (decision 6), and the pid.
- The take: decisions 1 to 5. The claim and finish helpers are `claim_slot` / `Invoke-Claim` and `finish_take` /
  `Complete-Take`. The restore is `restore_take` / `Undo-Take`, run from the failure paths.
- `reap_all` / `Invoke-Reap`: `continue` on any taking marker before the dirty check.
- `--release`, `--abandon`, `--report`: decision 7, checked right after "slot N is not in use".
- `--status`, `--status --porcelain`: decision 8. The comment above the porcelain loop names the two step values.
- `Invoke-Warmup` returns the failing index and code in place of throwing; `warmup` (bash) does the same, with the hash
  and the stamp as part of the command (decision 4, step 6).
- The fetch of the take: decision 11. The gate: decision 15. The liveness check: decisions 6, 12 and 13, in `claim_of` / `Get-Claim`.
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
  frees it and says `<step> failed (exit N)`; when the failed warm-up left changed or new files in the slot, the
  slot keeps the claim instead, so that nothing is lost, and `-Abandon N` (`--abandon N`) frees it once the files are
  dealt with. A take that died or was stopped without finishing leaves a claim that `slot -Status` shows with `has
  ended` (or `no process recorded`, for a take that could not put its slot back) and `/nightmill:status` with the step
  `take-died`. Nothing frees it automatically, and `-Abandon N` (`--abandon N`) frees it once its files are dealt
  with, keeping the branch. If `-Abandon` says the process is still running but no take is (its number was reused, or
  it is the PowerShell console a stopped take ran in), end or close that process, or remove the marker
  `<worktrees.root>/.slots/slot-N.json` by hand.
- "What a slot's agent is doing": after the sentence on **unknown**, add: `A slot still being taken shows unknown with
  the step taking; one whose take died shows the step take-died.`

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 34 (#186): a take claims its slot atomically
and a failed take leaves no half-taken slot. ...`. It names: the claim before the fetch (a marker with `"state":
"taking"` and `"pid"`, published only if absent: `ln` in bash, `File.Move` in PowerShell); the finished marker
unchanged; the fetch tried up to 3 times; `<step> failed (exit N)` and the slot put back in both shells, with exit 1
in bash too, or kept claimed when the failed warm-up left files in it; a dead claim shown as `take-died` and freed
only by `--abandon`; the readers unchanged (the porcelain step field); the previous version
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

Scripts in `<tmp>/hooks` (cases 1 and 6) are written with LF line ends and paths with `/` (PowerShell too). Git runs
them with its own `sh` in both shells: through `sh '<file>'` in `remote.origin.uploadpack`, or as a hook. A hook file
starts with `#!/bin/sh`, and the bash test makes it executable with `chmod +x` (git on Linux and macOS ignores a hook
without the execute bit; Git for Windows runs it because of the `#!`, so the PowerShell test, which runs on Windows,
needs no `chmod`). The **other shell** (case 7): the PowerShell test runs `slot.sh` with the `bash.exe` of Git
for Windows, found as `<three folders above git --exec-path>/bin/bash.exe`; the bash test runs `slot.ps1` with
`powershell -NoProfile -ExecutionPolicy Bypass -File`, with paths from `cygpath -w`, when `powershell` and `cygpath`
are on the `PATH` (Git for Windows). Where the other shell is missing (the bash test on Linux and macOS), a case that
needs it prints `skipped: no <PowerShell or bash> for <what>` and the test goes on; CI runs those cases in the
PowerShell job on Windows.

1. **Two takes at the same time get different slots, also when origin has moved.** Gate warm-up. Origin moves first:
   in a separate clone `<tmp>/other` of `<tmp>/origin.git`, one commit on `main` is pushed, its commit is N, and the
   main checkout's `origin/main` is still the old commit (the push did not come from it). A **fetch barrier** in
   `<tmp>/hooks/upload-pack-barrier`: `echo x >> '<tmp>/barrier'; i=0; while [ "$(wc -l < '<tmp>/barrier')" -lt 2 ];
   do i=$((i+1)); [ $i -lt 300 ] || break; sleep 0.1; done; exec git upload-pack "$@"`, set with `git -C <main> config
   remote.origin.uploadpack "sh '<tmp>/hooks/upload-pack-barrier'"`, holds each fetch until two have started (at most
   30 s), so that both takes fetch the moved origin at the same moment and race for `refs/remotes/origin/main`
   (decision 11). Start `--take feat/p1` and `--take feat/p2` in the background. `waitfor 1 taking` and `waitfor 2
   taking` (both claims exist at the same time). Create `<tmp>/go` and wait for both. `<tmp>/barrier` has at least two
   lines (the fetches overlapped). Both exit 0. Exactly one output has `Slot 1 is yours` and the other `Slot 2 is
   yours`. The slot named in each output is on that output's branch (`git branch --show-current`), and its marker has
   that branch. Both branches start at N (`git merge-base --is-ancestor N <branch>` exits 0). Both markers are
   finished: bash keys exactly `"slot":"branch":"since":` in that order, PowerShell the sorted keys
   `branch,since,slot`. `git config --unset remote.origin.uploadpack`, remove `<tmp>/go` and `<tmp>/barrier`, and
   abandon both.
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
   - with `merged feat/s2 41 <the commit origin/main points at>` (the tip of the new branch) and the gh log reset,
     `--reap` prints `No slot freed.`, and the gh log is still empty (no `gh` call for a taking slot, decision 7);
   - `--capacity --slot-count 1`: `--status` shows `taking: feat/s2 since <since> (process <pid>) (retiring)`, and the
     porcelain field 5 of slot 2 is `retiring`;
   - after each of these, the marker of slot 2 is byte for byte the same.
   Then create `<tmp>/go` and wait. The take exits 0 with `Slot 2 is yours`. Slot 2's marker is finished (keys as in
   case 1) with `feat/s2`, and slot 2 is a retiring busy slot (porcelain `2 TAB busy TAB feat/s2`, field 5
   `retiring`). `--capacity --clear`, reset gh, abandon slot 2, remove `<tmp>/go`.
3. **A failed step puts the slot back and frees the claim.** Each sub-case checks afterwards: exit 1; standard error
   ends with exactly the line given, with nothing after it (in PowerShell too: decision 4, no error record);
   `slot-N.json` does not exist; no `slot-N.claim.*.tmp`, `slot-N.left.*.tmp` or `slot-N.take.tmp` is left in `.slots`
   (no reader holds the marker in the tests, decision 1); `--status` shows `slot N  ready           free` (or `not created yet free`); porcelain `N TAB free`.
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
     slot 1 is free again`, and slot 1 is detached at X. Standard error holds git's error three times (decision 11:
     three attempts). Set the URL back.
   - **the stamp cannot be written** (decision 4, step 6). Normal config. Remove slot 1's stamp
     `.slots/slot-1.warmup-1` and create a directory of that name. `--take feat/f11 --slot 1`: `warm-up 1 failed
     (exit 1); slot 1 is free again`. Slot 1 is detached at X, and `refs/heads/feat/f11` does not exist. (The
     warm-up's `warmed.txt` is ignored, so the tree counts as clean and is switched back, decision 10.) Remove the
     directory.
   - **uncommitted files.** An untracked file in slot 1, then `--take feat/f7 --slot 1`: today's line `slot 1 has
     uncommitted files; deal with them first: <dir>`, and no marker. Remove the file.
   - **a changed file keeps a dead claim** (decision 10; its own checks, in place of the ones above). Create `feat/f8`
     with one commit that adds the file `f8.txt`, not checked out anywhere. A warm-up of one command that changes
     `f8.txt` and exits 7 (bash `echo changed > f8.txt; exit 7`, PowerShell `Set-Content f8.txt changed; cmd /c exit
     7`). `--take feat/f8 --slot 1`: exit 1, and the last two lines of standard error are exactly `slot 1 has
     uncommitted files: <slot 1> (commit, stash or discard them first)` and `warm-up 1 failed (exit 7); slot 1 could
     not be put back and stays claimed: free it with --abandon 1` (PowerShell `-Abandon 1`). Slot 1 is still on
     `feat/f8` with the changed `f8.txt`. Slot 1's marker is byte for byte decision 2's text for slot 1, `feat/f8`,
     its `since`, without the `pid` line. No `slot-1.claim.*.tmp` and no `slot-1.left.*.tmp` is left. Porcelain field
     9 of slot 1 is `take-died` and `--status` has the line `slot 1  ready           taking: feat/f8 since <since>
     (no process recorded; free it with --abandon 1)` (PowerShell `-Abandon 1`), although the test's shell is still running (in PowerShell, the process whose
     `$PID` a claim of `slot.ps1` run in this session would carry). `--abandon 1` exits 1 with `slot 1 has uncommitted
     files:`. After `git -C <slot 1> checkout -- f8.txt`, `--abandon 1` exits 0 with `Slot 1 is free (was feat/f8, a
     take that did not finish; the local branch is kept, delete it yourself if unwanted).`. Delete `feat/f8`.
   - **an untracked file keeps a dead claim** (decision 10; its own checks). A warm-up of one command that creates a
     file that is not ignored and exits 7 (bash `echo x > junk.txt; exit 7`, PowerShell `Set-Content junk.txt x; cmd
     /c exit 7`). `--take feat/f9 --slot 1` (a new branch, slot 1 detached at X): exit 1, and the last two lines of
     standard error are the two lines of the sub-case above with `warm-up 1 failed (exit 7)`. Slot 1 is still on
     `feat/f9`, `junk.txt` is there, and slot 1's marker is decision 2's text for slot 1, `feat/f9`, its `since`,
     without the `pid` line. A take with the switch back of the old text would have reported `slot 1 is free again`
     and left `junk.txt` in a free slot; here `--status --porcelain` field 9 of slot 1 is `take-died`, and `--take
     feat/f10 --slot 1 --skip-warmup` exits 1 with `slot 1 is busy`. `--abandon 1` exits 1 with `slot 1 has
     uncommitted files:`. After removing `junk.txt`, `--abandon 1` exits 0 with `Slot 1 is free (was feat/f9, a take
     that did not finish; the local branch is kept, delete it yourself if unwanted).`, and slot 1 is detached and
     clean. Delete `feat/f9`.
4. **A dead claim is recognised and freed only by abandon, without losing work.** `--take feat/d1 --slot 1
   --skip-warmup`, then overwrite slot 1's marker with a taking marker for `feat/d1` with a dead pid (the take died
   after its switch). Then:
   - `--status` has `taking: feat/d1 since <since> (process <pid> has ended; free it with --abandon 1)` (PowerShell
     `-Abandon 1`). Porcelain field 9 of slot 1 is `take-died` and field 6 is `unknown`;
   - `--take feat/d2 --skip-warmup` gets `Slot 2 is yours`. Abandon slot 2;
   - `--release 1` and `--report check --slot 1 --skill next --role implementer` exit 1 with the dead claim line as
     all of standard error. With the gh log reset, `--reap` with `merged feat/d1 42 <tip of feat/d1>` prints `No slot
     freed.`, and the gh log is still empty. Each leaves the marker byte for byte;
   - with an untracked file in slot 1, `--abandon 1` exits 1 with `slot 1 has uncommitted files:`, and the marker and
     the file stay. Remove the file;
   - `--abandon 1` exits 0 and prints exactly `Slot 1 is free (was feat/d1, a take that did not finish; the local
     branch is kept, delete it yourself if unwanted).`. The marker is gone, slot 1 is detached at `origin/main`, and
     `refs/heads/feat/d1` is still its tip;
   - a taking marker for slot 1 with the **live** pid: `--abandon 1` exits 1 with the live claim line, and the marker
     stays. Then the same marker without the `pid` line: `--status --porcelain` field 9 is `take-died`, `--status`
     has `taking: feat/d1 since <since> (no process recorded; free it with --abandon 1)`, and `--release 1` exits 1
     with exactly `slot 1 has a take that did not finish (no process recorded); free it with --abandon 1` as all of
     standard error (PowerShell `-Abandon 1` in both), the marker byte for byte unchanged. The same holds, with the
     same line, for the marker with `"pid": 2147483648` and with `"pid": 0` in place of the live pid (decision 13: out
     of range is dead, and PowerShell does not throw). Remove it;
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
6. **The claim exists before the fetch, the worktree add and the switch.** Git itself reports, at the moment each of
   these commands runs, whether the claim is there, so a take that claims after any of them fails this case. All
   slots are free (abandon what case 5 left), `WORKER_SLOTS=4`, and there is no directory `slot-4` (cases 3 and 4
   left none). The test writes three files in `<tmp>/hooks`, as the setup says (LF, paths with `/`, run by git's own
   `sh` in both shells, so the probe is the same in both; the bash test runs `chmod +x '<tmp>/hooks/post-checkout'`,
   without which git on Ubuntu CI would ignore the hook and the log would lack both `checkout` lines):
   - `record`: `m='<worktrees.root>/.slots/slot-4.json'; if [ -e "$m" ] && grep -q '"state": "taking"' "$m"; then
     c=claimed; else c=unclaimed; fi; echo "$1 $c" >> '<tmp>/spy.log'`;
   - `post-checkout` (git runs it at the end of `git worktree add` and of `git switch`, before the command returns):
     `#!/bin/sh` and `sh '<tmp>/hooks/record' checkout`;
   - `upload-pack` (git runs it for `git fetch` from the local `origin`, before any object is sent): `#!/bin/sh`,
     `sh '<tmp>/hooks/record' fetch` and `exec git upload-pack "$@"`.

   Then `git -C <main> config core.hooksPath '<tmp>/hooks'` and `git -C <main> config remote.origin.uploadpack "sh
   '<tmp>/hooks/upload-pack'"` (the worktrees share this config), an empty `<tmp>/spy.log`, and `--take feat/c6
   --slot 4 --skip-warmup`. It exits 0 with `Slot 4 is yours`, and `<tmp>/spy.log` is exactly the three lines
   `fetch claimed`, `checkout claimed` (the worktree add), `checkout claimed` (the switch), in that order. The
   warm-up's side is checked by cases 1 and 2 (`waitfor ... taking` while the gate warm-up runs).

   Control, so that the probe is known to tell the two apart: with the hooks still set and slot 4's marker now
   finished, `git -C <main> fetch origin` adds `fetch unclaimed` and `git -C <slot 4> switch -c feat/c6b` adds
   `checkout unclaimed`. Then `git config --unset core.hooksPath` and `git config --unset remote.origin.uploadpack`,
   abandon slot 4, and delete `feat/c6` and `feat/c6b`.
7. **The publish is exclusive, in one shell and across the two.** With `NIGHTMILL_CLAIM_GATE=<tmp>/claim-go` (decision
   15) in the environment of the takes only, and all slots free:
   - **same shell.** Start `--take feat/x1 --slot 1 --skip-warmup` and `--take feat/x2 --slot 1 --skip-warmup` in the
     background. Poll (0.1 s, at most 60 s, else fail) until `.slots` holds two files `slot-1.claim.*.tmp`: both takes
     have found no marker on slot 1 and wait at the publish. Create `<tmp>/claim-go` and wait for both. Exactly one
     exits 0 with `Slot 1 is yours`; the other exits 1 with `slot 1 is busy` as the last line of standard error (a
     plain line in PowerShell too, decision 4). Slot
     1's marker is finished with the winner's branch, slot 1 is on that branch, the loser's branch does not exist (it
     never fetched or switched), and no `slot-1.claim.*.tmp` is left. A take that checks for the marker and then
     writes it, or that publishes by moving over an existing marker, gets both exits 0 and fails here. Abandon slot 1,
     delete the winner's branch, remove `<tmp>/claim-go`.
   - **across the shells.** The same with one take in each shell: `--take feat/y1 --slot 1 --skip-warmup` in the
     test's shell and `feat/y2` in the other shell (bash `--take`, PowerShell `-Take ... -Slot 1 -SkipWarmup`), with
     the same checks. The winner's marker has the key order of its own shell. Without the other shell:
     `skipped: no <PowerShell or bash> for the cross-shell claim`.
The existing cases still pass unchanged. That includes "10 the marker format is unchanged" and "12 nothing else
changed: the marker keys", because the finished marker is today's, and every refusal and output text of the other
sections. `bash tests/check.sh` stays green and runs both shells where the machine can.

**What each criterion is checked by.** All in both smoke tests, unless named.

| Criterion | Cases |
|---|---|
| 1 two takes at nearly the same time get different slots, both shells | claim 1 (with origin moved and the two fetches held together by the barrier, decision 11), claim 7 (the same slot tried by two takes, in one shell and across the two) |
| 2 claimed atomically before fetch, switch, warm-up; the same in effect in both shells | claim 7 (atomically: two takes held at the publish, one wins; a check-then-write or a replacing publish fails it, in one shell and across the two; decisions 1 and 15), claim 6 (git's hooks see the claim at the fetch, the worktree add and the switch; a late claim gives `unclaimed`), claim 1 and claim 2 (the claim seen during the warm-up); decision 1 |
| 3 while working, `--status` shows it taken and a second take does not use it | claim 2 |
| 4 finished marker as today; the take prints the caller's slot | claim 1, claim 2 (the end); the existing cases 10 and 12 |
| 5 a failed fetch, switch or warm-up frees the claim, puts the slot back, names the step and code | claim 3 (with the fetch's three attempts, the stamp write, and a warm-up that leaves files, decision 10) |
| 6 a dead claim is recognised and can be freed, a live one is not, no work lost | claim 4 (with the pid range, decision 13; a take that died or was interrupted leaves such a claim, decision 5), claim 3 (a warm-up that leaves files keeps a dead claim) |
| 7 release, abandon, reap, report, capacity treat a taking slot as defined | claim 2 (live; the reap makes no `gh` call), claim 4 (dead; the same) |
| 8 the previous version reads the new markers, and the new reads the old | claim 5 (its real run of the previous version only locally: CI clones have no tag, so CI prints the skip); smoke-json step |
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
- #189 "A take retries its own marker changes while a reader holds the marker open": the finishing move, the rewrite
  without `pid` and the removal of the claim are tried once (decision 14). No retry either for the marker changes of
  `--report`, `--release`, `--abandon` and the reap, or for the reap's fetch (iteration 17).
- #190 "A take that is interrupted frees its claim and puts its slot back": no trap in bash, no `finally` in
  PowerShell, no interruption messages or exit codes; the claim is dead once the process ends (decision 5).
- No new flag, no config key, no change to any skill or agent, to the status flow or to who sets a status. No decision
  record. `NIGHTMILL_CLAIM_GATE` (decision 15) is a test hook, like `NIGHTMILL_NOW`, not a flag or a key.

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
  fails with `slot N: could not claim (...)` and never claims silently twice. `slot.ps1` on Windows claims there
  atomically, because `File.Move` is `MoveFileEx`, which needs no hard links. `slot.ps1` under PowerShell 7 on Linux
  or macOS on such a file system would not: .NET then checks for the target and renames, which two takes can both
  pass. `slot.ps1` is run with Windows PowerShell, on Windows, so this is not guarded. If either matters to a
  project, it is a separate bug.
- **`/proc` mounted with `hidepid`** on Linux hides the processes of other users, so a take run by another user on the
  same worktree root would read dead, and `--abandon` could free it once its tree is clean. Takes of one worktree root
  run as one user, so this is not guarded.
