# Iteration 35: a take retries its own marker changes while a reader holds the marker open

Status: draft, awaiting approval (#189)

Story: #189, epic #107 (Hardening from the code review). Split off from #186. A take tries each of its own marker
changes up to 21 times, 0.25 s apart: the move of the finished marker over its claim, the rewrite of a claim it leaves
behind without `pid`, and the removal of its claim. So a reader that holds the marker open for a moment on Windows no
longer leaves a ready slot behind as a dead claim. The publish of the claim is still tried once. Changes
`scripts/slot.sh`, `scripts/slot.ps1`, `tests/smoke-slot.sh`, `tests/smoke-slot.ps1`, `README.md` and `CHANGELOG.md`.
Nothing else.

**Written against iteration 34, not against `main`.** Iteration 34 (#186, `docs/specs/iteration-34-slot-claim.md`) is
Approved and is being implemented. Its take (the claim, the finishing move, the restore, the rewrite without `pid`)
is not on `main` yet. This spec changes the behaviour that spec defines, and it is implemented only after iteration
34 has merged. `scripts/slot.*` are hot files (`parallel.doNotPair`), so it is never implemented at the same time as
#128, #129 or #190 either. Whichever is Approved first is merged first, and the next rebases on it.

**Not a story trigger.** The marker format does not change (the same files with the same text), no config key is
added, renamed or removed, and the status flow and who sets a status do not change. No path in
`verification.manualCheckPaths` (`skills`, `agents`, `hooks`) changes, so **the manual check does not apply**.

## Goal

A take finishes, rewrites or removes its own marker even when a reader holds the file open for a short time.

## Facts this rests on

- Iteration 34 tries each of the take's own marker changes once (its decision 14). They are: the finishing move
  (decision 3: `mv -f` / `File.Replace` of `slot-N.take.tmp` over `slot-N.json`), the rewrite of a claim left behind
  (decision 5: `slot-N.left.<pid>.tmp` moved over the marker the same way), and the removal of the claim (`rm -f` /
  `Remove-Item` of `slot-N.json`: step 3 on a slot with uncommitted files, and item 5 of the restore). When one of them
  fails, decisions 3 and 5 say what follows: the error's own text, then one line, and a claim that stays (rewritten
  without `pid`, so it is dead and `--abandon N` frees it).
- On Windows, a reader that opens the marker without `FILE_SHARE_DELETE` makes a replace or a delete of it fail while
  the file is open (iteration 34, the facts). Checked for this spec on Windows 11 with a PowerShell process holding
  `[System.IO.File]::Open(<m>, 'Open', 'Read', 'Read')`:
  - Git for Windows: `mv -f <src> <m>` prints `mv: cannot move '<src>' to '<m>': Device or resource busy` and exits
    1, and `<src>` stays. `rm -f <m>` prints `rm: cannot remove '<m>': Device or resource busy` and exits 1.
  - Windows PowerShell 5.1: `File.Replace(<src>, <m>, [NullString]::Value)` throws, and so does `Remove-Item
    -LiteralPath <m> -ErrorAction Stop`. Both messages are in the language of the system (checked: German, "Der
    Prozess kann nicht auf die Datei zugreifen ..."). `<src>` stays.
  - Once the reader closes the file, the same `mv -f` and `File.Replace` succeed with the full new content.
- On Linux and macOS a file can be renamed over or removed while it is open, so no reader there blocks these
  operations.
- Every reader of a marker (`--status`, the porcelain readers, the panel and the dashboard through it, the reap of
  another take, `last_slot` / `Get-LastSlot`) opens `slot-N.json` by name for milliseconds. None opens a `*.tmp` file
  in `.slots`.
- No other command changes a live claim: `--release`, `--abandon` and `--report` refuse it, and the reap skips it
  (iteration 34, decision 7). While the take runs, its claim is live (its `pid` is the running take; the claim is
  rewritten without `pid` only at its end). So during the take's tries, only the take itself changes its marker.
- `sleep 0.25` waits at least 0.25 s (about 0.3 s in Git for Windows, where starting `sleep` costs time).
  `Start-Sleep -Milliseconds 250` waits at least 250 ms (about 260 ms measured).

## Decisions

**1. Three marker changes retry, and only these.** The take retries:

1. the finishing move over the claim (iteration 34, decision 3);
2. the rewrite of a claim left behind without `pid` (decision 5, "A claim left behind");
3. every removal of its own claim: step 3's (a slot with uncommitted files, decision 4) and item 5 of the restore
   (decision 5).

Each is the same command as in iteration 34 (`mv -f`, `rm -f`, `File.Replace` with `[NullString]::Value`,
`Remove-Item -LiteralPath`), run again with the same source and target. Nothing about them changes but the number of
tries.

**Never retried:**

- **The publish of the claim** (`ln`, `File.Move`; iteration 34, decision 1). A publish that fails because a marker
  exists means busy, and the take goes on with the next slot or stops with `slot N is busy`. Retrying it would only
  hold a take on a slot another take has won. A publish that fails without a marker (`could not claim`) has no reader
  to wait for: the file it would create does not exist yet.
- **The writes of the temporary files** (`slot-N.claim.<pid>.tmp`, `slot-N.take.tmp`, `slot-N.left.<pid>.tmp`). No
  reader opens them (the facts), so a failure there is a full disk or a missing permission, which waiting does not cure.
- **The removal of the temporary files** (`rm -f` / `Remove-Item -ErrorAction SilentlyContinue` of `slot-N.take.tmp`
  and `slot-N.left.<pid>.tmp` after a failed move, and the claim's temporary file). No reader opens those files. The
  bash claim's temporary name after a successful `ln` is a second name of the marker. Its removal stays as iteration
  34, decision 1 defines it: one attempt, a failure is not an error, and the leftover name stays. Retrying it would hold
  every take behind a reader only to remove a name that no command reads.
- The marker writes of `--report`, `--release`, `--abandon` and the reap, and the reap's fetch (out of scope).

**2. 21 tries, 0.25 s apart: at most 20 waits, 5 s of waiting per change.** A change is tried, and when it fails the
take waits 0.25 s and tries it again, at most 21 tries in all. So there are at most 20 waits, 20 × 0.25 s = 5.00 s,
plus the time of the 21 tries themselves (the facts: each wait is at least 0.25 s, and a bash wait about 0.3 s). The
change counts as failed only when the 21st try fails. One take does at most two retried changes in a row (the finish
or a removal, then the rewrite), so a reader that never lets go adds at most 40 waits, 10 s, to a take. 21 and 0.25
are numbers in both scripts, in one place each (bash `marker_tries=21`, `marker_pause=0.25`; PowerShell
`$markerTries = 21`, `$markerPauseMs = 250`). No config key.

Why these numbers: a reader holds a marker for milliseconds, so the next try a quarter second later finds it closed,
and a slot whose reader has let go is finished within 0.25 s. 5 s covers a burst of readers (`/status`, the panel and
the dashboard polling together, another take's reap) many times over. A reader that holds the file for more than 5 s
is not a short collision. It is left to iteration 34's way out (`--abandon`), and the take does not hang on it. #186
first proposed 20 tries 0.25 s apart, which is 19 waits, 4.75 s. 21 tries make the total exactly 5 s.

Why no config key: the numbers depend on how Windows opens files, not on the project. "Config-driven" is about
project-specific values, and a key would be a story trigger with nothing to set it for. Left lists the case in which a
key would be needed.

**3. Every failure retries; a sharing violation is not singled out.** The take does not tell a sharing violation from
another failure. Any failed try (bash: an exit status other than 0; PowerShell: an exception) is followed by a wait and
another try, up to the bound. Why:

- It cannot be told the same way in both shells. bash only has `mv`'s and `rm`'s text and exit status 1, and
  PowerShell's message is in the system's language (the facts). Testing the `HResult` in PowerShell alone would make
  the shells differ.
- Retrying is safe. Each try is one rename or one unlink, which either happens whole or not at all, and a failed try
  leaves the source and the marker as they were (the facts). No other command changes a live claim while the take
  tries (the facts), so a later try cannot overwrite someone else's change. A try that succeeds after earlier failures
  leaves the same state a first try would have.
- The only cost of a failure that does not pass (a read-only `.slots`, a missing source) is 5 s more before the take
  ends exactly as iteration 34 ends it.

**4. Nothing between tries; after the last, exactly iteration 34's output.** A failed try prints nothing. Its error
text is kept, not shown. bash runs each try as `err=$(mv -f "$src" "$mk" 2>&1)` (or `rm -f`), with the exit status
read explicitly, so `set -e` never ends the take. PowerShell catches the exception. When a later try succeeds, the
take goes on as if the first try had succeeded, and the kept text is dropped. When the 21st try fails, the take
writes that try's error text (bash: the captured text as `mv` or `rm` printed it; PowerShell: the first line of the
exception's message, as iteration 34 does) and then goes on exactly as iteration 34 does after its one failed attempt.
`<code>` in iteration 34's lines is the exit status of the 21st try (bash), or 1 (PowerShell). No message text of
iteration 34 changes, and no new line is added.

The retry is one helper in each script, used by the three changes of decision 1 and by nothing else: bash
`retry_marker <command> <args...>` (returns the last try's status, and on failure writes the last try's text to
standard error), PowerShell `Invoke-MarkerRetry { <command> }` (returns `$null`, or the last exception).

**5. The states of iteration 34, with the retries.**

| Change | A try succeeds (the first or a later one) | All 21 tries fail |
|---|---|---|
| finishing move | the finished marker, the hints, exit 0 (decision 3) | decision 3, steps 1 to 4: `slot-N.take.tmp` removed (once), the claim rewritten without `pid` (retried, below), the move's error text, `write marker failed (exit <code>); slot <n> stays claimed: free it with --abandon <n>`, exit 1 |
| removal, restore item 5 | `<step> failed (exit <code>); slot <n> is free again`, exit 1 | a failed restore command (decision 5): the removal's error text, the claim rewritten without `pid` (retried), `<step> failed (exit <code>); slot <n> could not be put back and stays claimed: free it with --abandon <n>`, exit 1 |
| removal, step 3 | today's `slot N has uncommitted files; deal with them first: <dir>`, no marker, exit 1 | the removal's error text, the claim rewritten without `pid` (retried), the same line, exit 1 |
| rewrite without `pid` | the claim without `pid`: dead at once, `--abandon N` frees it | the claim keeps its `pid` (dead once the take has ended), `slot-N.left.<pid>.tmp` removed (once), the line of the row above it unchanged; `--abandon N` frees it after the take has ended |

PowerShell writes `-Abandon <n>` in place of `--abandon <n>`, as in iteration 34. A reader that never lets go
therefore leaves exactly the state and the message of one failed attempt in iteration 34. The only difference is
that the take ends up to 10 s later.

## The scripts: `scripts/slot.sh` and `scripts/slot.ps1`

- The constants and the helper of decisions 2 and 4. The three changes of decision 1 go through it. The publish, the
  temporary files and every other command do not.
- The header comment gets a paragraph directly after the "Claim (iteration 34)" paragraph:
  `# Retries (iteration 35): the take's own marker changes (the move of the finished marker over its claim, the`
  `# rewrite of a claim it leaves behind and the removal of its claim) are tried up to 21 times, 0.25 s apart (at most`
  `# 5 s of waiting), because on Windows a reader that holds the marker open makes them fail for a moment. Nothing is`
  `# printed between tries; only the last try's error is. The publish of the claim is tried once. Same behaviour as`
  `# slot.ps1.` (in `slot.ps1`: `slot.sh`).

## README

In "Why slots", at the end of the paragraph iteration 34 adds on the claim, one more sentence:
`On Windows, a program that reads the marker at the same moment (/nightmill:status, the panel, the dashboard, another
take) can make the take's last write to it fail for a moment. The take tries its own marker changes up to 21 times,
0.25 s apart, so such a collision does not leave the slot claimed; a reader that holds the marker for longer than
that ends the take as described above.`

## CHANGELOG

One bullet under `Unreleased`: `- Iteration 35 (#189): a take retries its own marker changes while a reader holds the
marker open.` It names the three changes, 21 tries 0.25 s apart (at most 5 s of waiting each), that only the last
try's error is printed and that messages and states are those of iteration 34, and that the publish of the claim is
still tried once.

## Tests

**`tests/smoke-slot.sh` and `tests/smoke-slot.ps1`**: one new section `== marker retries (iteration 35)`, directly
after `== claim (iteration 34)`, with the same cases in both. The header comment of each test names the retries. It
uses iteration 34's helpers and setup: the gate warm-up (it waits for `<tmp>/go`), `waitfor <n> <state>`, takes
started in the background, all slots free and the count 2 at the start, and the config restored at the end.

**The reader.** `hold <file>` opens the file for reading with `FileShare.Read` (no delete sharing) and keeps it open
until `letgo`:

- PowerShell: in the test's own process, `$held = [System.IO.File]::Open(<file>, [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)`. `letgo` is `$held.Dispose()`.
- bash: a background `powershell -NoProfile -Command` that opens `cygpath -w <file>` the same way, then creates
  `<tmp>/held`, polls every 0.1 s for `<tmp>/let-go` (at most 120 s) and closes the file. `hold` returns once
  `<tmp>/held` exists (polled every 0.1 s, at most 60 s, else fail). `letgo` creates `<tmp>/let-go` and waits for that
  process. `<tmp>/held` and `<tmp>/let-go` are removed before each `hold`.

Such a reader exists only on Windows: in bash when `powershell` and `cygpath` are on the `PATH` (Git for Windows, as
iteration 34 finds the other shell), in PowerShell when `$env:OS` is `Windows_NT`. Elsewhere each of cases 1 to 4
prints `skipped: no reader that holds the marker open (needs Windows)` and the test goes on. CI runs them in the
PowerShell job on Windows. Case 5 runs everywhere.

**At the move.** "1 s at the move" means: poll every 0.1 s (at most 60 s, else fail) until the named sign that the take
has reached the retried change. Then wait 1 s (4 waits of the take, well inside its 20) and check that the take
process is still running and that slot 1's marker is byte for byte as it was before `<tmp>/go` was created. A take
that tries once has ended with exit 1 by then, and the case fails.

**A reference run.** Each of cases 1 to 3 first runs the same take once without a reader and records its exit code,
the last line of its standard error and the number of lines of its standard error (L). The held run must give the
same exit code, the same last line and exactly L lines. That shows that the take printed nothing for its failed tries,
whatever language the system's messages are in. After the reference run, the slot is put back: in case 3 `rw.txt` is
checked out first; a slot that is still marked is abandoned; a branch the take created is deleted (`feat/r1`; case 3's
`feat/rw` existed before and stays); slot 1 is detached at X again; and `<tmp>/go` is removed.

1. **The finishing move.** Gate warm-up. In the background, `--take feat/r1 --slot 1`. `waitfor 1 taking`, then
   `hold` slot 1's marker and create `<tmp>/go`. 1 s at the move, with the sign that `.slots/slot-1.take.tmp` exists.
   `letgo`, and wait for the take. It exits 0, and its output has `Slot 1 is yours`. Standard error is as in the
   reference run. Slot 1's marker is the finished marker of `feat/r1` (keys as in iteration 34's claim case 1), slot
   1 is on `feat/r1`, and no `slot-1.take.tmp` is left. `--status --porcelain` line 1 starts with `1 TAB busy TAB
   feat/r1`. The slot is usable: `--report check --slot 1 --skill next --role implementer` exits 0, and `--abandon 1`
   exits 0 with today's line. Delete `feat/r1`.
2. **The removal of the claim (restore item 5).** A warm-up of one command that waits like the gate warm-up and then
   fails with code 7 (bash: the gate loop, then `exit 7`; PowerShell: the gate loop, then `cmd /c exit 7`). Slot 1 is
   detached at X (its commit). In the background, `--take feat/r2 --slot 1`. `waitfor 1 taking`, and poll until
   `refs/heads/feat/r2` exists (the take has switched and waits in the warm-up). `hold` the marker and create
   `<tmp>/go`. 1 s at the move, with the sign that `refs/heads/feat/r2` no longer exists (the restore has deleted the
   branch, item 4, and is at item 5). `letgo`, and wait. The take exits 1, and the last line of standard error is
   exactly `warm-up 1 failed (exit 7); slot 1 is free again`. Standard error is as in the reference run. `slot-1.json`
   does not exist, slot 1 is detached at X, and porcelain line 1 is `1 TAB free`.
3. **The rewrite without `pid`.** Create `feat/rw` with one commit that adds `rw.txt`, not checked out anywhere. A
   warm-up of one command that waits like the gate warm-up, then changes `rw.txt` and fails with code 7 (as iteration
   34's "a changed file keeps a dead claim", after the gate loop). In the background, `--take feat/rw --slot 1`.
   `waitfor 1 taking`, `hold` the marker, create `<tmp>/go`. 1 s at the move, with the sign that a file
   `.slots/slot-1.left.*.tmp` exists. `letgo`, and wait. The take exits 1, and the last line of standard error is
   exactly `warm-up 1 failed (exit 7); slot 1 could not be put back and stays claimed: free it with --abandon 1`
   (PowerShell `-Abandon 1`). Standard error is as in the reference run. Slot 1's marker is byte for byte iteration
   34's decision 2 text for slot 1, `feat/rw` and its `since`, without the `pid` line, and no `slot-1.left.*.tmp` is
   left. Porcelain field 9 of slot 1 is `take-died`. `git -C <slot 1> checkout -- rw.txt`, `--abandon 1` exits 0, and
   `feat/rw` is deleted.
4. **A reader that never lets go.** As case 1, with `feat/r4`, but without the `letgo` until the take has ended
   (wait for it at most 60 s, else fail). Measure from creating `<tmp>/go` to the take's end (PowerShell a
   `Stopwatch`; bash `$SECONDS`). Then `letgo`. Checks:
   - the take exits 1 after at least 9 s (two retried changes, 40 waits of at least 0.25 s: 10 s, less 1 s for bash's
     whole seconds) and within the 60 s;
   - the last line of standard error is exactly `write marker failed (exit 1); slot 1 stays claimed: free it with
     --abandon 1` (PowerShell `-Abandon 1`), and standard error has at most L + 3 lines, with L from case 1's
     reference run: the move's error, the rewrite's error and the line, not one line per try;
   - slot 1's marker is byte for byte the claim as it was before `<tmp>/go` (with the `pid` of the take: the rewrite
     failed as well), and neither `slot-1.take.tmp` nor `slot-1.left.*.tmp` is left. Slot 1 is on `feat/r4`;
   - after `letgo`, the take has ended, so the claim is dead: `--status` has `taking: feat/r4 since <since> (process
     <pid> has ended; free it with --abandon 1)` (PowerShell `-Abandon 1`), and `--abandon 1` exits 0 with `Slot 1 is
     free (was feat/r4, a take that did not finish; the local branch is kept, delete it yourself if unwanted).`.
     Delete `feat/r4`.
5. **The publish is tried once.** Iteration 34's claim case 7 passes unchanged (two takes held at the publish, exactly
   one gets slot 1). In addition, with `NIGHTMILL_CLAIM_GATE=<tmp>/claim-go` in the takes' environment, start
   `--take feat/p5a --slot 1 --skip-warmup` and `--take feat/p5b --slot 1 --skip-warmup` in the background, poll until
   `.slots` holds two `slot-1.claim.*.tmp`, and create `<tmp>/claim-go`. Poll every 0.1 s (at most 60 s) until both
   takes have ended, noting for each how long after `<tmp>/claim-go` it was first seen ended (PowerShell a
   `Stopwatch`; bash `$SECONDS`). Exactly one exits 0. The one that exits 1, with `slot 1 is busy` as the last line of
   standard error, was seen ended at most 4 s after `<tmp>/claim-go` (a publish retried 21 times would take at least
   5 s). Abandon slot 1, delete the winner's branch and remove `<tmp>/claim-go`.

The existing cases, iteration 34's among them, still pass unchanged (no reader holds a marker there, so every change
succeeds at the first try). `bash tests/check.sh` stays green and runs both shells where the machine can.

**What each criterion is checked by.** All in both smoke tests. Cases 1 to 4 run where the reader exists (bash on Git
for Windows, PowerShell on Windows; CI's PowerShell job), and case 5 runs everywhere.

| Criterion | Cases |
|---|---|
| 1 the finishing move retries; the slot is finished and usable once the reader lets go, both shells | retries 1 |
| 2 the same for the rewrite without `pid` and the removal of the claim | retries 3 (rewrite), retries 2 (removal, restore item 5) |
| 3 bounded; a reader that never lets go gives iteration 34's message and state | retries 4 |
| 4 the publish is not retried; two takes never get the same slot | retries 5, iteration 34's claim case 7 |
| 5 a smoke case holds the marker open from a reader, skipped where none exists | retries 1 to 4 (the reader, the skip line) |
| 6 README and the header comments describe the retries | review of the diff (the texts above) |

## Verification

`bash tests/check.sh` on the branch, with both smoke tests (bash, and PowerShell where the machine has it; CI runs
both). The manual check does not apply: no skill, agent or hook changes. The PR's "How verified" names the check and
its skipped list, and says whether retries cases 1 to 4 ran in bash (only on Git for Windows).

## Not done

- No retries for the publish of the claim, the writes and removals of the temporary files, the marker writes of
  `--report`, `--release`, `--abandon` and the reap, or the reap's fetch.
- No change to any message, to the marker format, to the claim, to the restore or to the states of iteration 34. A
  failed change ends the take as there, only later.
- No config key, no flag, no environment variable. The numbers live in the scripts.
- No telling a sharing violation from other failures (decision 3).
- No handling of an interrupted take (#190). A take stopped while it retries leaves its claim with its `pid`, which is
  dead once the process has ended (iteration 34, decision 5).
- No change to the readers (`status`, the panel, the dashboard, the reap) to open the marker with delete sharing.

## Left

- **A config key for the tries.** None is added (decision 2). One would be needed only if a project's readers held the
  marker for longer than 5 s in normal use, for example a virus scanner that keeps files in `.slots` open. Nothing
  known does. If it happens, the key is its own story.
- **`File.Replace` that fails half-way.** Windows' `ReplaceFile` can fail after it has removed the file it replaces
  (`ERROR_UNABLE_TO_MOVE_REPLACEMENT`). Then the marker is gone and every further try fails, because `File.Replace`
  needs the target. That would leave a ready slot without a marker. It is a property of iteration 34's `File.Replace`
  (and of `--report`'s today), not of the retries. The checks for this spec saw only the clean failure (both files
  kept). It is not guarded here; if it is seen, it is a separate bug.
