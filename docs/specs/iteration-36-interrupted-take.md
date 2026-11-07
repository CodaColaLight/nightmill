# Iteration 36: a take that is interrupted frees its claim and puts its slot back

Status: draft, awaiting approval (#190)

Story: #190, epic #107 (Hardening from the code review). Split off from #186. A take that is interrupted after it has
claimed its slot runs the same restore as a failed step (iteration 34, decision 5) and says so: bash catches INT and
TERM in a trap and exits 130 or 143, PowerShell runs the restore in a `finally` block. Stopped while it writes its
finished marker, the take leaves its claim without `pid`, which `--abandon` frees. A take that is killed without a chance
to clean up still leaves a dead claim, as in iteration 34. Changes `scripts/slot.sh`, `scripts/slot.ps1`,
`tests/smoke-slot.sh`, `tests/smoke-slot.ps1`, `README.md` and `CHANGELOG.md`. Nothing else.

**Written against iterations 34 and 35, not against `main`.** Iteration 34 (#186,
`docs/specs/iteration-34-slot-claim.md`: the claim, the steps, the restore, the claim left behind without `pid`) is
Approved and being implemented, and iteration 35 (#189, `docs/specs/iteration-35-marker-retries.md`: 21 tries of the
take's own marker changes) is Approved-pending. Neither is on `main` yet, and `scripts/slot.*` on `main` still hold the
old take. This spec changes the take those two specs define. It is implemented only after both have merged, and,
since `scripts/slot.*` are hot files (`parallel.doNotPair`), never at the same time as #128 or #129.

**Not a story trigger.** The marker format does not change: an interrupted take leaves either no marker or the claim
of iteration 34 (with or without `pid`, both defined there). No config key is added, renamed or removed, and the
status flow and who sets a status do not change. No path in `verification.manualCheckPaths` (`skills`, `agents`,
`hooks`) changes, so **the manual check does not apply**.

## Goal

A take that is interrupted by Ctrl+C or a termination signal frees its claim and puts its slot back as it was, as far
as the shell can catch the interruption.

## Facts this rests on

Checked for this spec in Git for Windows bash and Windows PowerShell 5.1 on Windows 11, unless named.

- bash runs a trap only between commands: a signal that arrives while a foreground command runs is handled once that
  command has ended, before the next command. Ctrl+C in a terminal goes to the whole foreground process group, so the
  running command (git, a warm-up) gets it too and normally ends at once. A `kill` sent to the take's bash alone waits
  for the running command (checked: a 10 s loop ran to its end, then the TERM trap ran).
- A command started with `&` by a non-interactive shell without job control has INT ignored, and bash cannot trap a
  signal that was ignored when it started (checked: `kill -INT` did nothing). With `set -m` the job gets its own
  process group, with the job's pid as its id, and INT is not ignored (checked).
- From Git for Windows bash, `kill -<sig> -- -<pgid>` reaches the bash processes of the group (a warm-up `bash -c`,
  `sleep`), but not a native Windows program in it (`git.exe`, `ping.exe`): the take's trap ran only after `ping -n 20`
  had ended, 18 s later. On Linux and macOS the signal reaches every process of the group. Checked for fix round 1,
  with `git fetch` and `git switch` held by a hook (cases 5 and 6): INT reached neither `git.exe` nor the hook; TERM
  ended `git.exe` at once (bash printed `Terminated`), but not the hook's `sh`, which ran on until its gate opened.
- A PowerShell stop of a runspace does not end `git` while a hook git started still runs (checked: the stop took 51 s,
  until the hook gave up); with the hook's gate opened right after `BeginStop()` it ended within 1 s.
- When a foreground child is ended by TERM, bash prints `Terminated` and the command to standard error before the trap
  runs. INT prints nothing.
- In PowerShell, Ctrl+C in a console stops the running pipeline. `[powershell]::Stop()` / `BeginStop()` on a runspace
  does the same. Either runs every `finally` block on the way out, and a `finally` can run cmdlets and native commands
  and write with `[Console]::Error.WriteLine` (checked with `Stop()`: the `finally` ran `git --version` and wrote its
  line, 68 ms after the stop). A native command the pipeline waits for is ended by the stop (checked: `ping` gone before
  the `finally` ran). `catch` blocks do not run for a stop.
- A `finally` block runs for every way out of its `try`: an `exit`, an uncaught terminating error and a stop. It cannot
  tell a stop from an uncaught error. `Stop-Process` (TerminateProcess), `kill -KILL` and a closed console run no trap
  and no `finally`.
- The #186 drafts found that a `finally` cannot set the exit code of a stopped script: `powershell -File` gives 1.

## Decisions

**1. bash catches INT and TERM; nothing else.** The take sets `trap 'on_signal INT' INT` and `trap 'on_signal TERM'
TERM`. Its exit code is 130 for INT and 143 for TERM (128 + the signal number, the code a shell reports for a command
ended by that signal), set by `exit` in the handler, the same on Linux, macOS and Git for Windows. HUP (a closed
terminal) is not caught: the story names Ctrl+C and termination signals, and a closed terminal is in iteration 34's
list of uncaught ends (decision 5); the take may not be able to write any line there. QUIT, KILL and STOP are not
caught (KILL and STOP cannot be).

**2. Armed from the first claim attempt to the finished marker.** The handler (bash trap, PowerShell `try` with a
`finally`) is set right after the reap and before step 1 tries its first slot, so an interruption of the reap stays as
today (out of scope). It is taken away right after the finishing move has succeeded (bash `trap - INT TERM`, PowerShell
a flag that the `finally` reads): a take interrupted while it prints its hints keeps its finished marker, as any taken
slot. The take keeps its current step in a variable, set immediately before the step's first command:

| Step name | Covers |
|---|---|
| `claim` | step 1, until the fetch starts |
| `git fetch` | step 2, with the waits between attempts |
| `git worktree add` | step 3, with the check for uncommitted files |
| `git switch` | steps 4 and 5 |
| `warm-up <i>` | warm-up command `<i>` with its hash and stamp (iteration 34, step 6) |
| `write marker` | step 7, until the move over the claim has succeeded, with iteration 35's retries |

**3. "Its own claim" is decided by the marker's bytes.** The handler treats `slot-N.json` as its own claim when the
file holds byte for byte the claim text this take wrote (bash compares `$(cat <marker>)` with the text it kept;
PowerShell `[System.IO.File]::ReadAllText` with the string it wrote; a read that fails means not its own). Why: the
claim text holds the take's `pid` and `since`, so no other running take can have the same bytes, and the rule also
covers the moment between a successful publish and the next command, where a flag would still say "no claim" (in
PowerShell in a console, that claim would carry the console's `$PID` and stay live).

**4. What the handler does, by where the take is.** Every line goes to standard error as one plain line. `<sig>` is
`interrupted (INT)` or `interrupted (TERM)` in bash and `stopped` in PowerShell; `--abandon <n>` is `-Abandon <n>` in
PowerShell. A row applies only while no normal end has begun: once a claim failure of step 1, a failed step, step 3's
refusal (uncommitted files) or a failed finish has begun its own end (bash: its `trap ':'`; PowerShell: `$takeEnded` set, decision 7), a signal
or a stop selects no row, and that end finishes with iteration 34's line (bash exit 1).

| Where | What it does | Last line |
|---|---|---|
| no own claim (picking, the claim gate, a lost publish) | removes `slot-N.claim.<pid>.tmp` when it exists, touches no marker | `claim <sig>; no slot was claimed` |
| own claim, step `claim` to `warm-up <i>` | the restore of iteration 34, decision 5, for that step (items 2 to 4 only once step 4 has run to its end); a worktree counts as created by the take when `<dir>` did not exist before step 3 and exists now | `<step> <sig>; slot <n> is free again`, or after a failed restore command (its error text first) `<step> <sig>; slot <n> could not be put back and stays claimed: free it with --abandon <n>` with the claim rewritten without `pid` (iteration 34, decision 5; iteration 35's retries) |
| step `write marker`, the marker still its own claim | removes `slot-N.take.tmp` when it exists (once), rewrites the claim without `pid` (retried as in iteration 35); the switch and the warm-up are not undone (they succeeded) | `write marker <sig>; slot <n> stays claimed: free it with --abandon <n>` |
| step `write marker`, the marker no longer its claim (the move had succeeded) | nothing | `write marker <sig>; slot <n> is taken (branch <branch>): free it with --abandon <n> if it is not used` |

Then bash exits 130 or 143 (decision 1). PowerShell sets no exit code (decision 7). Examples: `warm-up 1 interrupted
(INT); slot 1 is free again`, `git fetch stopped; slot 2 is free again`. When the rewrite without `pid` fails after its
21 tries, the claim keeps its `pid` and the line is unchanged, as in iteration 35's table; in bash that claim is dead
as soon as the handler has exited.

**5. A second signal never stops a restore.** Every restore runs to its end: the one started by a failed step
(iteration 34, decision 5, and step 3's removal of the claim), the one started by the handler, and the rewrite without
`pid`. bash sets `trap ':' INT TERM` as the first command of each of them (a no-op trap, not `''`: children get the
default action, so a git command of the restore still ends on Ctrl+C, while an ignored signal would be inherited and
make it unstoppable). PowerShell runs all of them inside the take's `finally`, which a stop does not interrupt: the
restore of a failed step, step 3's removal of the claim (with its rewrite without `pid` when the removal fails), the
failed finish's removal of `slot-N.take.tmp` and rewrite without `pid`, and the handler's restore (decision 7). A
second Ctrl+C can therefore only make a git command of the restore fail; the restore then stops there, rewrites the
claim without `pid` and prints the "could not be put back" line. A restore started by a failed step keeps iteration
34's line and exit code 1. Every restore item checks the slot's current state before it acts (iteration 34), so
nothing is undone twice. Only KILL or `Stop-Process` ends a restore; then decision 8 applies.

**6. A child process is waited for, not signalled by the take.** The take runs git and the warm-up in the foreground
as today, so the handler runs only after the running command has ended (the facts) and nothing the take started is
left running while it restores. Ctrl+C and a signal to the process group reach that command themselves. A signal sent
to the take's process alone waits until the command ends: bash's rule, kept because the take cannot end a warm-up's
whole tree of processes the same way in both shells. In PowerShell, the stop ends the native command it waits for (the
facts). A program a warm-up command started in the background is the warm-up's own (as today).

**7. PowerShell: one `try` / `finally` around the take.** From decision 2's arming point to the end of the take, the
take's body is in one `try`. Every normal end (success, a refusal, step 1's two claim failures, a failed step, step 3's
refusal, a failed finish) sets a flag `$takeEnded` as its first command (with what is left to do: the failed step and
its code, step 3's claim removal, or the failed finish's cleanup) and then exits; nothing of that work runs in the
`try`. Step 1's claim failures (iteration 34, decision 1: the failed write of the temporary file, `claim failed (exit
<code>); slot <n> was not claimed`, and the failed publish, `slot N: could not claim (...)`) have nothing left to do:
they set `$takeEnded` first, keep their removal of `slot-N.claim.<pid>.tmp` and their line where iteration 34 has them,
and exit 1. In bash they set `trap ':' INT TERM` before their removal and their line, as the other normal ends do
(decision 4), and exit 1 without the trap writing a second line. In both shells they print exactly iteration 34's line
and nothing more. The `finally` then:

- does what is left (the restore of a failed step, step 3's claim removal, the failed finish's removal of
  `slot-N.take.tmp` and rewrite without `pid`) and writes iteration 34's line (exit 1 stays the code of the `exit`;
  after a claim failure there is nothing left and no line to add), or
- when `$takeEnded` is not set, does what decision 4 says for a stop, with `stopped` in the line.

It cannot tell Ctrl+C from an uncaught terminating error (a bug); both are "stopped", and PowerShell writes the error
record after the line. It cannot set the exit code of a stopped script: that is PowerShell's (1 for `powershell -File`,
#186 drafts), not 130 or 143. The story accepts the difference. The claim of a stopped take in an open console carries
the console's `$PID`; the handler removes it, or rewrites it without `pid`, so no live claim stays behind.

**8. Uncaught ends stay as iteration 34 defines them.** `kill -KILL`, `Stop-Process`, a closed window, HUP, a crash of
the process, or a signal that bash had ignored on entry (the facts) run no handler: the claim stays with its `pid`, is
dead once the process has ended (iteration 34, decision 6), shows as `take-died` and is freed by `--abandon N`. A
signal that arrives before the handler is set, or after it was taken away, has the shell's default effect. A
`slot.ps1` take killed in a way that leaves the console running keeps iteration 34's README way out.

## Deviations from earlier specs

| Spec | The rule there | From this iteration on |
|---|---|---|
| `docs/specs/iteration-34-slot-claim.md`, decision 5, "An interrupted take is not cleaned up by the scripts" | "A take stopped after its claim (Ctrl+C, a signal, a closed window, a killed process) restores nothing and leaves its claim with its `pid`." | A take stopped by INT or TERM (bash) or a pipeline stop (PowerShell) after its claim restores as decisions 4 and 5 say. A closed window, a killed process and the other ends of decision 8 still restore nothing. |

Iteration 34's and 35's "Not done" items for #190 are fulfilled here; their text is not edited.

## The scripts: `scripts/slot.sh` and `scripts/slot.ps1`

- bash: `on_signal <INT|TERM>` and the step variable (decisions 2 to 5); the claim text kept for decision 3; `trap ':'
  INT TERM` at the start of each restore; `trap - INT TERM` after the finishing move.
- PowerShell: the `try` / `finally` of decision 7 and the same step variable; the restore of a failed step, step 3's
  claim removal and the failed finish's cleanup and rewrite without `pid` move into the `finally`. Its output does not
  change.
- No message of iterations 34 and 35 changes. The new lines are the four of decision 4.
- The header comment gets a paragraph directly after the "Retries (iteration 35)" paragraph. In `slot.sh`:
  `# Interruption (iteration 36): a take stopped by INT (Ctrl+C) or TERM after it has claimed its slot runs the same`
  `# restore as a failed step, prints "<step> interrupted (INT)" or "(TERM)" with the outcome and exits 130 or 143.`
  `# Stopped while it writes its finished marker, it leaves its claim without the process id; --abandon frees it. A`
  `# second signal does not stop a restore. A signal sent with kill to the take alone waits for the running command. A`
  `# take killed without a chance to clean up (KILL, a closed window) leaves a claim that is dead once its process has`
  `# ended. Same behaviour as slot.ps1, which prints "<step> stopped" and cannot set the exit code.`
  In `slot.ps1` the same, with `a take stopped by Ctrl+C after it has claimed its slot runs, in a finally block, the
  same restore ...`, `prints "<step> stopped"`, `-Abandon`, `(Stop-Process, a closed console)`, the sentence on `kill`
  left out, and the last sentence `Same behaviour as slot.sh, which names the signal and exits 130 or 143.`

## README

In "Why slots", after the sentence iteration 35 adds on retries:
`A take that is interrupted after it has claimed its slot (Ctrl+C, or a TERM signal in bash) puts the slot back and
frees it as a failed take does, and names the step: "warm-up 1 interrupted (INT); slot 1 is free again" (bash, exit
130, or 143 for TERM), "warm-up 1 stopped; slot 1 is free again" (PowerShell, which cannot tell why it was stopped and
keeps its own exit code). Interrupted while it writes its finished marker, it leaves the claim, and -Abandon N
(--abandon N) frees it. A take that is killed without a chance to clean up (Stop-Process, kill -KILL, a closed window)
leaves a claim that slot -Status shows as ended; -Abandon N frees it.`

## CHANGELOG

One bullet under `Unreleased`: `- Iteration 36 (#190): a take that is interrupted frees its claim and puts its slot
back.` It names: INT and TERM in bash (exit 130, 143), a `finally` in PowerShell (`stopped`, its own exit code); the
same restore as a failed step and the `<step> interrupted` / `stopped` line; a take stopped while writing its marker
keeps a claim `--abandon` frees; a second signal does not stop a restore; a killed take leaves a dead claim as before.

## Tests

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**: one new section `== interruption (iteration 36)`, directly
after `== marker retries (iteration 35)` and before `SMOKE OK`. The header comment of each test names it. It uses the
helpers of iterations 34 and 35: `waitfor`, `hold` / `letgo`, slot 1 detached at commit X, all slots free and the
count 2 at the start, the config restored at the end. The **pid gate warm-up** is iteration 34's gate warm-up with
one first command that writes `<tmp>/gate.pid` (bash `echo $$ > '<tmp>/gate.pid'`, the pid of the warm-up's own
`bash -c`; PowerShell `Set-Content '<tmp>/gate.pid' x`, its warm-up runs inside the take). `<tmp>/gate.pid` is removed
before each take.

**How a take is interrupted.**

- bash: the take is started as a job of its own: `set -m; bash "$S" --take ... > out 2> err & p=$!; set +m` (the facts:
  without job control INT would be ignored). The signal goes to its process group: `kill -<sig> -- -$p`. Cases 1 to
  4 interrupt during the gate warm-up, a `bash -c` loop that the signal reaches on every platform. Cases 5 and 6
  interrupt inside git, held by the hold hook, and open the hook's gate right after the signal (below). Case 7
  interrupts at the claim gate, a `sleep` loop in the take's own bash.
- PowerShell: the take runs in a runspace of the test's process: `$ps = [powershell]::Create()`, `AddScript("Set-Location
  -LiteralPath '<work>'; & '<S>' -Take ... ")`, `BeginInvoke()`, with the test's `[Console]::Error` redirected to a
  `StringWriter` while it runs (the take's lines; git's go to the real standard error). It is stopped with
  `BeginStop()`, the same pipeline stop as Ctrl+C in a console (the facts). A real Ctrl+C cannot be sent to a child
  process reliably in CI (it needs a shared console), and a signal does not exist on Windows; the runspace has no
  exit code, so none is asserted in PowerShell. The claim of such a take carries the test's `$PID`, which stays
  running, so a claim left with its `pid` would be live: the checks of case 2 show that it is not.

**Bounds, so nothing hangs or is left.** After the interruption the test waits for the take at most 60 s, polling
every 0.1 s (bash `kill -0 $p`; PowerShell the stop's `AsyncWaitHandle.WaitOne`). When it has not ended: bash `kill
-KILL -- -$p` and fail; PowerShell fail (ending the test's process ends the runspace). After cases 1, 2 and 4 (the
pid gate warm-up), bash checks
that the warm-up's process has ended (`kill -0 $(cat '<tmp>/gate.pid')` fails); a PowerShell take has no child at
that point. The gate warm-up ends by itself after 120 s in any case, the hold hook after 300 polls.

**The checks of a free slot** (case 1): `slot-1.json` does not exist; no `slot-1.claim.*.tmp`, `slot-1.left.*.tmp`
or `slot-1.take.tmp`; slot 1 is detached at X; the take's new branch does not exist; `--status --porcelain` line 1 is
`1 TAB free`.

1. **Interrupted in the warm-up: the slot is free and unswitched.** Pid gate warm-up. Start `--take feat/i1 --slot
   1`, `waitfor 1 taking`, poll until `<tmp>/gate.pid` exists, interrupt. Checks: the last line of the take's
   standard error is exactly `warm-up 1 interrupted (INT); slot 1 is free again` (bash, exit code 130) or `warm-up 1
   stopped; slot 1 is free again` (PowerShell, the runspace state `Stopped`), and the checks of a free slot. bash runs
   it a second time with TERM and `feat/i2`: `warm-up 1 interrupted (TERM); slot 1 is free again`, exit 143.
2. **Interrupted after the warm-up changed a file: a dead claim that `--abandon` frees.** Create `feat/i3` with one
   commit that adds `i3.txt`, not checked out anywhere. A warm-up that changes `i3.txt` and then runs the pid gate
   warm-up (bash `echo changed > i3.txt; <pid gate>`, PowerShell `Set-Content i3.txt changed; <pid gate>`). Start
   `--take feat/i3 --slot 1`, poll for `<tmp>/gate.pid`, interrupt (bash INT). The last two lines of standard error
   are exactly `slot 1 has uncommitted files: <slot 1> (commit, stash or discard them first)` and `warm-up 1
   interrupted (INT); slot 1 could not be put back and stays claimed: free it with --abandon 1` (PowerShell `warm-up 1
   stopped; ... -Abandon 1`); bash exit 130. Slot 1 is on `feat/i3` with the changed file. Its marker is byte for byte
   iteration 34's decision 2 text for slot 1, `feat/i3`, its `since`, without `pid`. Porcelain field 9 of slot 1 is
   `take-died`, and `--status` has `taking: feat/i3 since <since> (no process recorded; free it with --abandon 1)`
   (PowerShell `-Abandon 1`), although in PowerShell the claim's process (the test) still runs. `git -C <slot 1> checkout -- i3.txt`, then
   `--abandon 1` exits 0 with `Slot 1 is free (was feat/i3, a take that did not finish; the local branch is kept,
   delete it yourself if unwanted).`. Delete `feat/i3`.
3. **Interrupted while writing the finished marker** (where iteration 35's reader exists; elsewhere it prints
   iteration 35's `skipped: no reader that holds the marker open (needs Windows)`). Iteration 34's gate warm-up. Start
   `--take feat/i4 --slot 1`, `waitfor 1 taking`, `hold` slot 1's marker, create `<tmp>/go`, poll until
   `.slots/slot-1.take.tmp` exists (the take is in its retries of the move), interrupt (bash INT; PowerShell
   `BeginStop()`). Wait 1 s (the handler's rewrite now retries against the reader), `letgo`, and wait for the take.
   Checks: the last line of standard error is exactly `write marker interrupted (INT); slot 1 stays claimed: free it
   with --abandon 1` (bash, exit 130) or `write marker stopped; slot 1 stays claimed: free it with -Abandon 1`
   (PowerShell). The marker is the claim of slot 1 and `feat/i4` without `pid`; no `slot-1.take.tmp` and no
   `slot-1.left.*.tmp` is left. Slot 1 is on `feat/i4`. `--status` has `(no process recorded; free it with --abandon
   1)` (PowerShell `-Abandon 1`), and `--abandon 1` exits 0 with `Slot 1 is free (was feat/i4, a take that did not finish; ...)`. Delete
   `feat/i4`, remove `<tmp>/go`.
4. **Killed without a chance to clean up: a dead claim, as in iteration 34.** Pid gate warm-up. bash: start the take
   as in case 1 with `feat/i5`, poll for `<tmp>/gate.pid`, `kill -KILL -- -$p` (the whole group, so the warm-up dies
   too). PowerShell: start `-Take feat/i5 -Slot 1` as a child `powershell` process (iteration 34's background take),
   poll for `<tmp>/gate.pid`, `Stop-Process -Id <its id> -Force`, `WaitForExit(60000)`. Checks: slot 1's marker is
   byte for byte iteration 34's decision 2 text for slot 1, `feat/i5`, its `since` and the take's pid (bash: the
   winpid rule; PowerShell: the process `Id`), with no line from the take on standard error after the interruption;
   `--status` has `taking: feat/i5 since <since> (process <pid> has ended; free it with --abandon 1)` (PowerShell
   `-Abandon 1`); porcelain field 9 is `take-died`; `--abandon 1` exits 0 with the take-did-not-finish line, the
   marker is gone, and `feat/i5` exists. bash: the warm-up's process has ended. Delete `feat/i5`.

Cases 5 and 6 use the **hold hook** `<tmp>/hooks/hold`, written as iteration 34's hooks (LF, paths with `/`, run by
git's own `sh` in both shells): `echo $$ >> '<tmp>/hold.pid'; if [ -r /proc/$$/winpid ]; then cat /proc/$$/winpid >>
'<tmp>/hold.winpid'; fi; i=0; while [ ! -e '<tmp>/hold-go' ] && [ $i -lt 300 ]; do i=$((i+1)); sleep 0.1; done`.
`<tmp>/hold.pid`, `<tmp>/hold.winpid` and `<tmp>/hold-go` are removed before each case. The take is started with
`--take <branch> --slot 1 --skip-warmup`; the test polls until `<tmp>/hold.pid` exists, interrupts, and creates
`<tmp>/hold-go` at once. Why the gate is opened: on Git for Windows the held git ends only when the hook does (the
facts), with the signal already pending in bash, whose trap then runs for the held step; a PowerShell stop waits for
git the same way. On Linux the signal ends git and the hook itself, and the open gate changes nothing. Checked on this
machine with a model take (the step variable, the trap or `finally`, the held command): bash INT in the fetch 8 of 8
runs, TERM in the fetch and the switch, INT in the switch, PowerShell `BeginStop()` 4 of 4 in each, every run with the
held step's name and the hook's process gone, under 1 s. Not checked: Linux (CI runs it). Both cases end with: every
pid in `<tmp>/hold.pid` (bash, `kill -0` fails) or `<tmp>/hold.winpid` (PowerShell, no `Get-Process -Id`) has ended
within 5 s.

5. **Interrupted in the fetch: the slot is free.** `upload-pack-hold` in `<tmp>/hooks`: `#!/bin/sh`, `sh
   '<tmp>/hooks/hold'` and `exec git upload-pack "$@"`; `git -C <main> config remote.origin.uploadpack "sh
   '<tmp>/hooks/upload-pack-hold'"`. Take `feat/i6`, interrupt (bash INT). Checks: the last line of standard error is
   exactly `git fetch interrupted (INT); slot 1 is free again` (bash, exit 130) or `git fetch stopped; slot 1 is free
   again` (PowerShell, state `Stopped`), and the checks of a free slot. `git config --unset remote.origin.uploadpack`.
6. **Interrupted in the switch: the slot is unswitched and the new branch gone.** `post-checkout` in `<tmp>/hooks`:
   `#!/bin/sh` and `sh '<tmp>/hooks/hold'` (bash `chmod +x`); `git -C <main> config core.hooksPath '<tmp>/hooks'`.
   Slot 1 exists, so the first checkout of the take is the switch's, which has moved slot 1 to the new branch when
   the hook runs; the restore's own switch runs the hook again, past the open gate. Take `feat/i7`, interrupt (bash
   TERM). Checks: the last line is exactly `git switch interrupted (TERM); slot 1 is free again` (bash, exit 143) or
   `git switch stopped; slot 1 is free again` (PowerShell), and the checks of a free slot (detached at X, no
   `feat/i7`). `git config --unset core.hooksPath`.
7. **Interrupted at the publish: no claim and nothing left.** Start `--take feat/i8 --slot 1 --skip-warmup` with
   `NIGHTMILL_CLAIM_GATE=<tmp>/claim-go` (iteration 34, decision 15) in the take's environment only (bash: the
   assignment before `bash "$S"` in the job; PowerShell: `$env:NIGHTMILL_CLAIM_GATE` set before `BeginInvoke()` and
   removed once the take has ended); `<tmp>/claim-go` is not created. Poll until `.slots/slot-1.claim.*.tmp` exists:
   the take has written its temporary file and waits before the `ln` / `File.Move`, so no marker exists and the claim
   is not published. Interrupt (bash INT, then a second run with TERM and `feat/i9`; PowerShell `BeginStop()`).
   Checks: the last line of standard error is exactly `claim interrupted (INT); no slot was claimed` (bash, exit 130;
   with TERM `claim interrupted (TERM); no slot was claimed`, exit 143) or `claim stopped; no slot was claimed`
   (PowerShell, state `Stopped`); the checks of a free slot (no `slot-1.json`, no `slot-1.claim.*.tmp`, `--status
   --porcelain` line 1 `1 TAB free`); bash: no process of the job's group is left (`kill -0 -- -$p` fails), and a
   PowerShell take has no child here. Bounded as the others (60 s); the gate itself publishes after 60 s, so a take the
   interruption missed would claim and fail the checks, never hang. Checked on this machine with a model take (the
   temporary file, the gate's loop, the trap or `finally`): bash INT and TERM to the group 6 of 6, ended in 81 to 165 ms
   with exit 130 or 143, the line, no temporary file and no marker; a signal to the take's bash alone 4 of 4 within
   0.3 s, handled once the running `sleep 0.1` of the gate had ended; PowerShell `BeginStop()` 4 of 4 within 30 ms. Not
   checked: Linux (CI runs it), where the group signal ends the `sleep` too.

The existing cases, iterations 34 and 35 among them, still pass unchanged. `bash tests/check.sh` stays green.

**What each criterion is checked by.** Both smoke tests, unless named.

| Criterion | Cases |
|---|---|
| 1 bash: interrupt or TERM during fetch, switch or warm-up runs the restore, exit code names the signal | interruption 5 (bash, INT 130, in the fetch), 6 (bash, TERM 143, in the switch), 1 (bash, INT 130 and TERM 143, in the warm-up), 2 (bash, the restore that cannot put back) |
| 2 PowerShell: a stopped take runs the same restore and says what it did | interruption 1, 2, 5, 6 and 7 (PowerShell, `stopped` lines) |
| 3 between the claim and the first step, or in the finish: a state `--status` shows and `--abandon` frees | interruption 7 (at the publish, before the first step: decision 4's first row, the slot free), interruption 3 (the finish, with a reader; Windows), interruption 2 (a dead claim shown and freed); the rest of the claim-to-fetch window restores like the fetch (decisions 2 to 4) |
| 4 a take that cannot be caught leaves a dead claim freed by `--abandon` | interruption 4 |
| 5 a smoke case interrupts a take in each shell, checks the slot, cannot hang or leave a process | interruptions 1 to 7, with the bounds above |
| 6 README and header comments describe what an interruption does | review of the diff (the texts above) |

## Verification

`bash tests/check.sh` on the branch, with both smoke tests (bash, and PowerShell where the machine has it; CI runs
both). The manual check does not apply: no skill, agent or hook changes. The PR's "How verified" names the check and
its skipped list, and says whether interruption case 3 ran (only on Windows).

## Not done

- No handling of HUP, QUIT, a closed window, `Stop-Process` or KILL (decision 8): they leave a dead claim.
- No interruption handling for `--report`, `--release`, `--abandon`, `--capacity`, `--status` or the reap.
- The take does not signal or kill its child processes; it waits for them (decision 6).
- No change to the claim, the marker format, the steps, the restore, the dead-claim rule, the failure lines of
  iteration 34 or the retries of iteration 35.
- No exit code for a stopped PowerShell take (decision 7).
- No config key, flag or environment variable; no change to any skill, agent, hook, reader or the status flow.

## Left

- **Cases 5 and 6 were not run on Linux here.** They were checked on Windows with a model take (the tests); CI's
  Ubuntu job is their first run there, where the signal itself ends git and the hook.
- **The exit codes differ.** bash exits 130 or 143; a stopped PowerShell take has PowerShell's own code (1 for
  `powershell -File`, per the #186 drafts, not asserted: the test's runspace has no exit code). The story accepts it.
- **A git command ended without its own cleanup** (a PowerShell stop of a runspace ends `git.exe` with
  TerminateProcess; KILL) can leave a `index.lock` in the repository. The restore's first git command then fails, the
  claim stays without `pid`, and `--abandon` fails with git's message until the lock is removed by hand. A Ctrl+C in
  a console reaches git itself, which removes its lock. A `git worktree add` ended that way can leave a half-made slot
  directory, which is #129's case (a broken slot directory).
- **A second signal is not tested** (decision 5): its timing against the restore cannot be held in a test without a
  gate in the restore, which the story does not ask for. Nor is a signal during step 3's claim removal or a failed
  finish's rewrite (decision 4's first sentence): neither has a point where a test can hold it.
