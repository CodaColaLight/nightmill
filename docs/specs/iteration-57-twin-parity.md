# Iteration 57: the bash and PowerShell twins give the same result where they differ today

Status: draft, awaiting approval (#329)

Story #329, epic #107 (hardening from the code review). #141 listed six places, read from the code of 0.3.0, where a
`.sh` script and its `.ps1` twin give different results. The story folds the malformed `since` (first filed as bug
#330) into the slot criteria, decides it as tolerant but visible, and asks for one rule per case, the same in both
shells, each proven by a smoke step in both shells. This spec first records what each twin does today (on `main` at
d6181da), then settles each case: an empty label, status name or `verification.manualCheckText` takes its default in
both shells; the issue forms render only invariants that are non-empty strings, newlines kept; `slot --release` frees
the slot when the local branch cannot be deleted, and `--release` and `--abandon` exit 1 with one plain line on a
failed `git` or `gh` call; `slot --status` shows a marker that is not a JSON object as a busy slot and exits 0;
`/status` shows a slot whose `since` is not a time with the Since cell `?` and the flag `stale: busy, since
unreadable`, exit 0; the PowerShell scripts match config keys by their exact spelling, as bash, the schema and the
validator do; `release.sh` keeps CRLF line ends in `CHANGELOG.md`, as `release.ps1` does. Changes `scripts/lib/json.sh`,
a new `scripts/lib/exactkeys.ps1`, `scripts/render-templates.sh`, `scripts/render-templates.ps1`, `scripts/status.sh`,
`scripts/status.ps1`, `scripts/lib/status.awk`, `scripts/slot.sh`, `scripts/slot.ps1`, `scripts/release.sh`,
`scripts/drive.sh`, `scripts/dashboard.sh`, `scripts/history.sh`, `scripts/guard.sh`, `scripts/template-board.sh`, the
PowerShell scripts that read the config (one line each, listed under Files touched), `tests/smoke-render.sh` and
`.ps1`, `tests/smoke-status.sh` and `.ps1`, a new fixture folder `tests/fixtures/status/e/`, `tests/smoke-slot.sh` and
`.ps1`, `tests/smoke-release.sh` and `.ps1`, `tests/smoke-panel.sh` and `.ps1` (the slots pane now lists a slot
with a corrupt marker in both shells, which amends iteration 32's test 5), `tests/smoke-dashboard.sh` and `.ps1`
(the dashboard page shows that slot as a busy row in both shells, which amends iteration 31's test 7),
`tests/lint.sh`, `README.md` and `CHANGELOG.md`.

## Story trigger and manual check

**None of the three story triggers.**

- *A change to the status flow or who sets a status*: no. No status, no board call and no decision record changes;
  `docs/decisions/` 0001 to 0003 stay as they are. Only the default that a script uses for an empty status *name*
  changes (decision 1), not the flow.
- *A new, renamed or removed config key*: no. No key is added, renamed or removed, and no type or default changes;
  `schema/nightmill.schema.json`, `templates/nightmill.example.json` and the README's configuration table keep their
  keys. The agent notes say the case of keys that differ only by case "may count as a config-key change": it does
  not here (decision 7), because the documented spelling of every key stays the only one, and only the PowerShell
  twin stops reading a misspelled key that the schema, `scripts/validate-config.*` (an "unknown key (did you mean
  ...?)" warning) and bash never accepted. That is a visible change for a PowerShell project with such a key, so the
  CHANGELOG names it. The maintainer may still judge it a trigger; it is listed under Decisions for that.
- *A change to the slot marker format*: no. No script writes a marker differently: the keys, their order, the
  indent and the line ends of `json_marker`, `json_marker_report` and `json_marker_taking` (and their PowerShell
  writers) are untouched, and a marker written by this version is read by the previous one unchanged
  (**Compatible**). What changes is how `--status` and `/status` *read* a marker that is broken or holds a `since`
  that is not a time. `slot --status --porcelain` keeps its ten fields per busy line (iteration 23); the only new
  text is on standard error and in the human `--status` line. Nothing needs to be split off as its own story.

**The manual check does not apply**: `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and no file under
them changes (`hooks/panel.tsx` reads `status --json` and gets the same keys).

**Both shells** (invariant ticked): every change to a script in `scripts/` is made in the `.sh` and the `.ps1` (or,
where one twin already does what the rule says, only in the other, named under Files touched), and every case has a
smoke step in `tests/smoke-*.sh` and in `tests/smoke-*.ps1`, listed under Tests. PowerShell is not installed on the
machine this spec was written on: the PowerShell steps run in CI (`ci.yml`, the PowerShell smoke job on Windows).

**Hot files.** `scripts/slot.sh` and `scripts/slot.ps1` are in `parallel.hotFiles`; `parallel.doNotPair` forbids
pairing this story with any other task that changes the slot scripts. The schema is not touched.

## Facts this rests on

Read on `main` at d6181da on 2026-11-18. The bash side was run (the commands below, in throwaway repositories under
`$TMPDIR`, with the fake `gh` and the fixed clock of `tests/smoke-status.sh`). **PowerShell is not installed here:
every PowerShell finding below was confirmed by reading the PowerShell code only, never by running it.**

**Finding 1, an empty-string config value: still holds.**

- bash: `json_get PATH DEFAULT` (`scripts/lib/json.sh` lines 39 to 49) returns DEFAULT only when the path is absent,
  `null`, an object or an array; `""` is a string and is returned as `""`. Run: `render-templates.sh` with
  `labels.epic: ""` writes `labels: [""]` into `epic.yml`, and with `verification.manualCheckText: ""` writes the
  line `        - ` into `story.yml`. `status.sh` passes `ST_EPIC=""` (line 112), so `status.awk` filters no epic.
- PowerShell (read only): `status.ps1` `Cfg` (lines 54 to 63) returns the default when the value is `$null` or
  `"$obj" -eq ""`; `drive.ps1` (line 110), `dashboard.ps1` (line 33), `history.ps1` (line 94) and
  `template-board.ps1` (line 48) have the same rule; `render-templates.ps1` takes the default for a label that is
  falsy (line 41) and for an empty `manualCheckText` (lines 58 and 60). So PowerShell writes `labels: ["epic"]` and
  `- Manual check as the story describes`. `guard.ps1` `Get-Val` (line 19) is the exception: it keeps `""`, as
  `guard.sh` does.
- Readers of the three named groups: `labels.*` in `render-templates.*`, `status.*`, `drive.*`, `history.*`;
  `board.statuses.*` in `status.*`, `drive.*`, `dashboard.*`, `history.*` (bash's `history.awk` line 171 already
  takes the default for `""`), `guard.*`, `template-board.*`; `verification.manualCheckText` in `render-templates.*`.

**Finding 2, invariants: still holds.**

- bash (run): `render-templates.sh` (lines 39 to 43) writes one `- label: <json_quote>` per array item, so `null` and
  `""` both become `- label: ""`, a number `5` becomes `"5"` and `true` becomes `"true"`; the value comes through a
  command substitution, which drops trailing newlines: `"ends\n"` is written `"ends"`. A newline inside a value is
  kept (`"one\ntwo"`). The begin/end block is removed only when `json_len invariants` is 0.
- PowerShell (read only): `render-templates.ps1` line 47 drops `$null` and `""` items; every other item goes through
  `[string]`, so `true` becomes `"True"` and an object becomes `"@{...}"`; a trailing newline is kept (`"ends\n"`).
  The block is removed when no item is left.

**Finding 3, a slot script's failures.**

- *The warm-up failure message: no longer holds for the slot scripts.* At 0.3.0 `slot.ps1` threw
  `warm-up '<command>' failed` and `slot.sh` printed nothing of its own. Since iteration 34 both put the slot back and
  print `warm-up N failed (exit C); slot N is free again` (`slot.sh` `restore_take`, `slot.ps1` `Undo-Take`), exit 1,
  and `tests/smoke-slot.sh` "claim 3" (lines 861 to 908) and `tests/smoke-slot.ps1` (lines 959 to 1006) assert the
  same lines. The pair still exists in `new-worktree.*` (bash: the command's own code and no line; PowerShell:
  `throw "warm-up '<command>' failed"`, line 95), which is not a slot script; see Left.
- *`--release` when deleting the branch fails: still holds.* bash (run): with the branch checked out in another
  worktree, `slot.sh --release 1` switches the slot to a detached `origin/main`, then `git branch -D` (line 799)
  fails under `set -e`: exit 1, `error: cannot delete branch 'feat/x' used by worktree at ...`, and the marker
  `slot-1.json` stays, so the slot stays busy on a detached checkout and every further `--release` fails the same
  way. PowerShell (read only): `git branch -D $m.branch` (line 956) is a native command, its failure does not stop
  the script, the marker is removed, the ledger record is written and `Slot 1 is free (was feat/x, PR #7).` is
  printed, exit 0.
- *A corrupt marker in the status: still holds, and in more places.* bash (run), marker `{ "slot": 2, "branch": `:
  `slot.sh --status --porcelain` prints `2 TAB busy TAB TAB TAB TAB unknown TAB TAB TAB TAB` (`marker_fields`,
  line 219, gives empty fields) and json.awk's own error line on standard error, exit 0; `status.sh` shows the row with
  an empty Branch, Since `740322d` and the flag `stale: busy, no open PR`, exit 0. `slot.sh --status` (the human form)
  prints the json error twice and **exits 1** after slot 1, because `busy="busy: $(marker_field ...)"` (line 531)
  fails under `set -e`. PowerShell (read only): `Read-Marker` (line 226) pipes the file into `ConvertFrom-Json` under
  `$ErrorActionPreference = "Stop"`, so `slot.ps1 -Status` and `-Status -Porcelain` stop at the first corrupt marker
  (exit 1), and `status.ps1` catches it and dies with `status.ps1: slot.ps1 failed: ...`, **exit 2**. A marker file
  whose content is `null` is busy in bash (`has_marker` tests the file) and free in PowerShell (`if ($m)`).
- *The slots pane on a corrupt marker: a documented difference.* `scripts/panel.sh` and `scripts/panel.ps1` run
  `slot --status --porcelain` once: on exit 0 they print one `slot` record per line of it and every non-empty line of
  its standard error as a `note` record; on any other exit they print one `unknown<TAB><first error line>` record and
  no `slot` record (`panel.sh` lines 117 to 133, `panel.ps1` lines 121 to 154); `hooks/panel.tsx` draws either form.
  So, with slot 2's marker `{ not json`, bash's pane lists `slot<TAB>2<TAB>busy<TAB>unknown<TAB><TAB>?<TAB>?<TAB>-`
  (and json.awk's error as a note), and PowerShell's shows only the `unknown` record. `docs/specs/iteration-32-panel.md`
  records this as wanted: its test 5 (lines 441 to 443) expects that bash line and, for PowerShell, "an `unknown`
  record and no `slot` record (slot.ps1 fails on it, Facts)", and its Not done (line 571) says "the PowerShell/bash
  difference on a marker that is not valid JSON stays". `tests/smoke-panel.sh` (lines 157 to 164) and
  `tests/smoke-panel.ps1` (lines 197 to 206), step `== an unreadable marker is never free`, assert exactly that; the
  PowerShell step fails once `slot.ps1 -Status -Porcelain` exits 0 on such a marker (decision 4).
- *The dashboard on a corrupt marker: a documented difference.* `scripts/dashboard.sh` and `scripts/dashboard.ps1`
  run `status --porcelain` once and, only when it fails, `slot --status --porcelain` (`dashboard.sh` lines 101 to
  105, `dashboard.ps1` lines 6 to 7, 187 and 209); `scripts/lib/dashboard.awk` and `dashboard.ps1` turn the status
  child's `slot` records into rows and every non-empty line of its standard error into an `<li>` of a Notes section.
  So, with slot 2's marker `{ not json` in the fixture `tests/fixtures/dashboard/run-stall-old-free`, bash's page
  shows slot 2 as a busy `unknown` row (`status.sh` succeeds, with the cells of the bullet above that one) and
  json.awk's error as a note, and PowerShell's page holds `unknown: the slots could not be read (` and `unknown: the
  board could not be read (` (`status.ps1` and the fallback both fail). `docs/specs/iteration-31-dashboard.md` records
  this as wanted: its Facts (lines 44 to 46: "`slot.ps1` fails on it ..., so `status.ps1` exits 2 ... This iteration
  does not change that difference"), its test 7 (lines 563 to 566, for PowerShell "the board and the slots
  paragraphs both say `unknown`") and its Not done (line 662: "the PowerShell/bash difference on a marker that is not
  valid JSON stays"). `tests/smoke-dashboard.sh` (lines 191 to 197) and `tests/smoke-dashboard.ps1` (lines 242 to
  249), step `== an unreadable marker is never free`, assert exactly that; the PowerShell step fails once
  `status.ps1 -Porcelain` exits 0 on such a marker (decision 4). `docs/specs/iteration-32-panel.md` says the same of
  PowerShell in its Facts (lines 107 to 108: "`slot.ps1` throws on it and exits non-zero") and in its manual check 4
  (lines 539 to 541: "or the line `unknown: the slots could not be read (...)` (PowerShell)").
- *The other readers of the slot status.* `drive.*` (`drive.sh` line 523, `drive.ps1` line 563), `load.*`
  (`load.sh` line 53, `load.ps1` line 57) and `control.*` (`control.sh` line 56, `control.ps1` line 68) run `slot
  --status --porcelain` and count or list its `busy` lines. `load` and `control` pass the slot script's standard
  error through when it exits 0 and stop with exit 2 (`load: slot.ps1 failed: ...`, `control: slot.ps1 failed:
  ...`) when it does not; `drive` writes `drive: slot -Status failed: ...` and then skips its free-slot check. So,
  on a corrupt marker today, bash's three count the slot busy (`load` and `control` pass json.awk's error through),
  PowerShell's `load` and `control` exit 2 and PowerShell's `drive` starts its step without the free-slot check. No
  smoke step and no earlier spec asserts that case for them (iterations 24, 30 and 52 state only the general rule
  for a failing slot script). `skills/next` and `skills/fix` read `slot --status` as text and are given a busy line.
  Only the slot scripts read marker files; `room`, `gate`, `stages`, `history`, `session-start`, `guard`,
  `template-board`, `new-worktree`, `models`, `validate-config`, `render-templates` and `release` neither read a
  marker nor run `slot --status` or `status`, so decision 4 does not reach them.
- *The exit codes (128 against 1): still holds.* bash (run): `slot.sh --release 1` with an unreachable origin exits
  **128** (the `git fetch` on line 791 under `set -e`) and `--abandon 1 --base origin/nope` exits **128** (`git switch`,
  line 829); a failing `gh pr list` (line 792) exits with `gh`'s code, 127 when `gh` is missing. None prints a line of
  its own. PowerShell (read only): the same failures `throw "git fetch failed"` / `"git switch failed"` (lines 945,
  955, 978, 989), exit 1, written as an error record (several lines); a failing `gh` is not checked and ends in
  `no merged PR for ...`.

**Finding 4, keys that differ only by case: still holds.** bash: every lookup compares the whole path with `==`
(`json_get`, `json_has`, `json_len` in `scripts/lib/json.sh`), so `worktrees.Slots` is not `worktrees.slots`.
PowerShell (read only): property access (`$cfg.worktrees.slots`) and `PSObject.Properties[$k]` are case-insensitive in
every script that reads the config, so a config with `"Slots": 3` gives 3 slots in `slot.ps1` and 2 in `slot.sh`.
`scripts/validate-config.*` match keys case-sensitively and warn `unknown key (did you mean "slots"?)`
(`docs/specs/iteration-6-config-validator.md`, line 70).

**Finding 5, a malformed `since`: still holds.** Marker of slot 2 with `"since": "yesterday"`, slot 4 normal, fixture
`c` of `tests/fixtures/status`, `NIGHTMILL_NOW=1793880000`:

- `slot.sh --status --porcelain` copies `since` as written (`2 TAB busy TAB feat/odd TAB yesterday TAB ...`), exit 0.
- `status.sh` (run) prints the row `   2  busy   running  feat/odd  next/implementer  check      5m  740322d  -   stale:
  busy, no open PR` and exits 0; slot 4 is unaffected. `stamp()` in `scripts/lib/status.awk` (line 22, used on line
  418) reads a text that is not a time as day 0 of year 0, so the age is nonsense; `--porcelain` and `--json` carry
  the same `740322d`. With `since` `2026-13-45T99:00:00` the Since cell is `0m` and there is no flag (a time in the
  future is clamped to 0); with `since` missing it is `740322d` again.
- `status.ps1` (read only) parses the cell with `[datetime]::ParseExact($f[3], "yyyy-MM-ddTHH:mm:ss", ...)` (line
  180) inside the loop over the slot lines; the exception is not caught (the surrounding `try` has only a `finally`),
  so the script stops before it prints anything on standard output, writes PowerShell's error record ("String was
  not recognized as a valid DateTime") on standard error and **exits 1** under `powershell -File`. No slot is shown.
  Neither script documents exit 2 for it: their headers give 2 only for a usage error, the config or `gh`.

**Finding 6, the CHANGELOG line ends: still holds.** `release.ps1` (lines 240 to 247) splits the file on `\r?\n` and
joins it again with CRLF when the file contains a CRLF anywhere, else with LF, and keeps a missing final line end
missing. `release.sh` (line 219) runs awk over the file: the existing lines keep their CR, the two inserted lines
(the empty line and `## X.Y.Z (date)`) end with LF only, and awk adds a final LF when the file had none.
`docs/specs/iteration-5-release-script.md` line 38: "line endings stay as they are."

**The marker format** (`docs/specs/iteration-23-slot-reports.md` lines 35 to 44 and 123 to 127,
`docs/specs/iteration-34-slot-claim.md`): `slot`, `branch`, `since` (local wall-clock `YYYY-MM-DDTHH:MM:SS`), then
`skill`, `role`, `step`, `reported` after a report, or `state` and `pid` for a claim. Nothing in this spec writes it.

## Decisions

1. **An empty string is not set, for the three named groups.** For `labels.epic`, `labels.story`, `labels.bug`,
   `labels.needsSpec`, every `board.statuses.<key>` and `verification.manualCheckText`, a value that is the empty
   string counts as absent: the script uses the same default it uses for a missing key (the schema's default; for
   `manualCheckText`, `Manual check as the story describes`), in both shells. The PowerShell twin is right. Reasons:
   the project already has this rule for `roles.<role>.model` (iterations 10, 11, 15, 16: "when it is a non-empty
   string, else the default"); an empty label is no GitHub label (`labels: [""]` in an issue form), an empty status
   name matches no board option, and an empty manual-check text writes an empty checkbox line, so the default is the
   safer reading and loses nothing a project could have meant. A value of only spaces is not empty and is used as
   written. Other keys keep their current handling (see Left). bash gets one function in `scripts/lib/json.sh`:
   `json_text PATH [DEFAULT]`: "the string value at PATH, decoded; DEFAULT (empty when not given) when the path is
   absent, null, an object, an array or the empty string", and every bash read of the named keys uses it.
   `guard.ps1` and `guard.sh` both change for `board.statuses.ready` and `board.statuses.approved`.
2. **Invariants: only non-empty strings are rendered, as written.** An item of `invariants` is rendered when it is a
   string with at least one character; any other item (`null`, `""`, a number, a boolean, an object, an array) is
   left out, in both shells. A rendered item is its text exactly, every character kept, a trailing newline too
   (`"ends\n"` is written `"ends\n"`), escaped as `json_quote` does. When no item is rendered, the begin/end block is
   removed exactly as for a config without `invariants`. Neither twin was fully right: PowerShell was right to drop
   `null` and `""` and to keep the trailing newline, bash to write `true` as `true`. Reasons: the schema says `items:
   { "type": "string" }` (anything else is already a validator error), an issue form checkbox needs a label, and the
   text must not change on the way (the newline is data). Leaving an item out keeps the forms valid; the validator
   still names the bad item.
3. **A malformed `since`: shown, age unknown, flagged, exit 0.** A busy slot's `since`, as `slot --status
   --porcelain` prints it, is well formed when it matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$`
   (ASCII digits, nothing before or after), the test the Report column already applies to `reported`
   (`status.awk` line 428, `status.ps1` `-cmatch ... \z`) and `slot.*` apply in `is_stamp` / `Test-Stamp`; a well
   formed text is turned into seconds by the existing arithmetic (`stamp` in awk, `StampOf` in PowerShell, which
   agree), and no calendar check is added (a form-correct `2026-13-45T99:00:00` gives the same number in both shells,
   as `reported` does today). Anything else, the empty string included, is malformed. For a malformed `since`, in
   both shells:
   - the slot row is shown with every other cell as today;
   - the **Since cell is `?`** (the mark the Skill and Step cells already use for "not known");
   - the **Flag cell** is, in this order: `stale: busy, PR merged (slot --release N)` or `stale: busy, PR closed (slot
     --abandon N)` when the branch's pull request is merged or closed (the existing flags, unchanged), else
     **`stale: busy, since unreadable`** (the "no open PR after 2 hours" flag needs the age and is not judged);
   - `--porcelain` carries the same two cells (`?` in the Since field, the flag in the Flag field), and `--json`
     the same strings: `"since":"?"` and `"flag":"stale: busy, since unreadable"`;
   - the exit code is 0, nothing extra is printed, and every other row, the item table and the capacity line are
     what they would be without that slot.
   `status.ps1` drops `ParseExact` and uses the regex and `StampOf`; `status.awk` checks the form before `stamp`.
   The flag text follows the `stale: busy, ...` wording of the other slot flags; `unreadable` says what is wrong
   without suggesting a command, because the slot may be in use.
4. **A marker that is not a JSON object is a busy slot in `--status`.** A marker file that exists marks its slot busy,
   whatever it holds (bash's `has_marker` rule; PowerShell's `null` case changes). When its content is not valid
   JSON, or is valid JSON whose top level is not an object, both shells, in `--status --porcelain`, print the busy
   line with empty branch, since, skill, role, step and reported, the agent `unknown` and the retiring field as for
   any busy slot (`2 TAB busy TAB TAB TAB TAB unknown TAB TAB TAB TAB`, bash's line today), and write exactly one line
   on standard error: `slot N: the marker is not a JSON object` (json.awk's own error and PowerShell's exception text
   are not shown). In `--status` the slot's line reads `slot N  <where>  busy: (the marker is not a JSON object)`
   (the existing `printf 'slot %s  %-15s %s%s'` layout, the retiring and dirty suffixes as for any busy slot), with
   nothing on standard error. Both exit 0, and the other slots are listed as without it. `/status` passes the note on
   (both twins already let the slot script's standard error through) and, because the `since` is empty, shows the
   row by decision 3: Branch empty, Skill `?`, Step `?`, Report `-`, Since `?`, Flag `stale: busy, since unreadable`,
   exit 0. bash's text was the tolerant one and is kept; the visible note is added so that the cause is named. The
   marker is never changed or removed by a status command.
   **The slots pane follows, and this amends iteration 32.** `panel.sh` and `panel.ps1` do not change: because the
   slot script now exits 0, both print, for slot 2's marker `{ not json` in the fixture `run-stall-old-free`, exactly
   the records of `expected.txt` with slot 2's line replaced by `slot<TAB>2<TAB>busy<TAB>unknown<TAB><TAB>?<TAB>?<TAB>-`,
   followed by the one line `note<TAB>slot 2: the marker is not a JSON object`, exit 0, nothing on standard error;
   `hooks/panel.tsx` draws that as a busy `unknown` row with an empty branch and the note, as it draws any note. The
   PowerShell half of iteration 32's test 5 (lines 441 to 443: "an `unknown` record and no `slot` record"), the
   PowerShell sentence of its Facts (lines 107 to 108), the PowerShell half of its manual check 4 (lines 539 to 541;
   the pane now shows that slot `unknown` in both shells) and the sentence of its Not done (line 571) "the
   PowerShell/bash difference on a marker that is not valid JSON stays" are superseded by this decision; iteration
   32's other rule, "an unreadable marker is never free", holds in both shells. The step `== an unreadable marker is
   never free` of `tests/smoke-panel.sh` and `tests/smoke-panel.ps1` is changed to that expected output (Tests). An
   exit other than 0 of the slot script still gives the pane's `unknown` record.
   **The dashboard follows, and this amends iteration 31.** `dashboard.sh`, `lib/dashboard.awk` and `dashboard.ps1`
   do not change for this decision: because `status --porcelain` now exits 0 on such a marker in both shells, the
   fallback is not run, and both write, for slot 2's marker `{ not json` in the fixture
   `tests/fixtures/dashboard/run-stall-old-free`, the page of its `expected.html` with exactly two changes: slot 2's
   row (line 28) is
   `<tr><td class="num">2</td><td>busy</td><td class="unknown">unknown</td><td></td><td>?</td><td>?</td><td class="num">-</td><td class="num">?</td><td>-</td><td class="flagged">stale: busy, since unreadable</td></tr>`
   (the `/status` cells above: no branch, so no pull request and the PR cell `-`), and the four lines
   `<h2>Notes</h2>`, `<ul>`, `<li>slot 2: the marker is not a JSON object</li>`, `</ul>` stand directly before the
   line `<h2>What the words mean</h2>` (the note that `status` passes on from the slot script, as a note of the
   status child). Exit 0; the page holds no `<td class="num">2</td><td class="free">free</td>`, no `unknown: the slots
   could not be read`, no `unknown: the board could not be read` and no `unknown: the pull requests, CI and flags of
   the slots could not be read`. Iteration 31's Facts (lines 44 to 46), the PowerShell half of its test 7 (lines 563
   to 566: "the board and the slots paragraphs both say `unknown`") and the sentence of its Not done (line 662) "the
   PowerShell/bash difference on a marker that is not valid JSON stays" are superseded by this decision; its rule
   "an unreadable marker is never free" holds in both shells. The step `== an unreadable marker is never free` of
   `tests/smoke-dashboard.sh` and `tests/smoke-dashboard.ps1` is changed to that expected output (Tests). The
   fallback still runs when `status` fails for another reason, and for such a marker it now lists the slot busy in
   both shells.
   **The other readers follow without a change.** `drive.*`, `load.*` and `control.*` do not change for this
   decision (Facts): in both shells they now count the slot busy; `load` and `control` pass the one line `slot N: the
   marker is not a JSON object` through on standard error and go on (PowerShell no longer exits 2); `drive` runs its
   free-slot check in PowerShell too and, when no slot is free, names that slot `N: ` (its empty branch) in its `no
   free slot: ...` stop, as bash does. A marker whose content is `null` counts busy in their PowerShell twins too. No
   step and no earlier spec asserts the old case for them, so no step changes; the slot step of criterion 3 proves
   the lines they read.
5. **`--release` frees the slot when the local branch cannot be deleted.** When `git branch -D <branch>` fails,
   `--release` still removes the marker, writes its ledger record and prints `Slot N is free (was <branch>, PR
   #<n>).`, exit 0; git's own error stays on standard error, so the kept branch is visible. The PowerShell twin is
   right: `docs/specs/iteration-17-slot-auto-release.md` (lines 72 to 75) says of freeing, "which is what --release
   does", that "a failing git branch -D ... does not stop the run: the slot is still freed", and the reap already does
   it (`slot.sh` line 331). Keeping the marker leaves a slot that is detached, busy and can never be released.
6. **`--release` and `--abandon` exit 1 with one plain line on a failed `git` or `gh` call.** In both shells, the
   failures of `--release` and `--abandon` exit **1**, after git's or gh's own text, with exactly one line of the
   script's own as the last line of standard error: `git fetch failed`, `gh pr list failed` (a non-zero exit of `gh`,
   or `gh` not found), `git switch failed`; and the existing refusals keep their text and exit 1: `slot N is not in
   use`, `slot N has uncommitted files: <dir>` (with `(commit, stash or discard them first)` for `--abandon`), `no
   merged PR for <branch>. Merge it first, or free the slot with --abandon N.` (`-Abandon N` in PowerShell, as today).
   Nothing changes when one of them fails before the marker is removed: the marker stays. In PowerShell these lines
   are written with `Exit-Line` (one plain line, no error record) instead of `throw`. The PowerShell twin is right
   about the code: every other failure of the slot scripts exits 1 (usage, refusals, the take, iteration 34), and
   bash's 130 and 143 for an interrupted take (iteration 36) stay as they are. bash's lines get the PowerShell
   texts, which exist already.
7. **Config keys are matched by their exact spelling.** In both shells a config key is found only by its exact,
   case-sensitive spelling. The bash twin is right: JSON keys are case-sensitive, the schema names one spelling,
   `validate-config.*` match exactly and warn about a near miss, and bash never matched otherwise. PowerShell gets
   one function, `Select-ExactKeys <config object>`, in a new `scripts/lib/exactkeys.ps1`, called on the config
   object right after each `ConvertFrom-Json` of the project config: it reads `schema/nightmill.schema.json` of the
   plugin and, in every config object whose schema lists `properties` (recursing into the properties that match
   exactly, and into array items through `items`), removes each key that is not one of those properties exactly but
   equals one of them ignoring case. After that, PowerShell's case-insensitive property access can only find the
   exact key. Keys of an object without listed `properties` (`worktrees.ports`) and keys the schema does not know at
   all are left alone (no script reads them by a fixed name). When the schema cannot be read, the config is used as
   it is. `validate-config.ps1` does not call it (it must see the misspelled key to warn). This is the rule; the one
   mechanism keeps the change to one line per script.
8. **`release.sh` writes the line ends `release.ps1` writes.** When `CHANGELOG.md` contains at least one CRLF, every
   line of the file it writes ends with CRLF, the two inserted lines included; otherwise every line ends with LF; the
   file ends with a line end exactly when it did before. That is `release.ps1`'s rule, and it is what
   `docs/specs/iteration-5-release-script.md` asks ("line endings stay as they are") for a file with one kind of line
   end; a file with both kinds comes out all CRLF in both shells. `plugin.json` and `README.md` are not part of the
   criterion and keep their current handling.
9. **The warm-up failure message needs no change in the slot scripts.** Finding 3's first part no longer holds
   there (iteration 34 made both print `warm-up N failed (exit C); slot N is free again`, exit 1); the existing smoke
   steps "claim 3" in both shells are this case's steps. The remaining pair in `new-worktree.*` is under Left.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | An empty-string config value (labels, `manualCheckText`, statuses) is handled the same in both shells | Decision 1 |
| 2 | Invariants are rendered the same in both shells: empty or null entries, and a value with a newline | Decision 2 |
| 3 | A slot script's failures behave the same in both shells: the warm-up failure message, `--release` when deleting the branch fails, a corrupt marker in the status, and the exit codes | Decisions 9 (warm-up), 5 (`--release`), 4 (corrupt marker), 6 (exit codes) |
| 4 | A slot marker with a malformed `since` is shown in the status table with its age marked as unknown and flagged, exit code 0, and the other slots are unaffected, the same in both shells | Decision 3 |
| 5 | Config keys that differ only by case are matched the same way in both shells | Decision 7 |
| 6 | `release.ps1` and `release.sh` write the same line endings into the changelog | Decision 8 |
| 7 | Every case has a smoke step in both `tests/smoke-*.ps1` and `tests/smoke-*.sh` | Tests (one or more named steps per case, the same name in both shells) |

## Tests

Each step has the same name and the same expected text in the `.sh` and the `.ps1` (PowerShell spells the options
`-Release`, `-Abandon`, `-Status`, `-Porcelain`, `-Json`, `-Project`, `-Force` as each script does today). The bash
steps run in `bash tests/check.sh` on a unix machine and in CI; the PowerShell steps run in CI (PowerShell on
Windows) and on any machine with PowerShell; they cannot run where this spec was written.

- Criterion 1:
  - `tests/smoke-render.sh` and `.ps1`, step `== twins (#329): an empty label or manualCheckText takes the default`:
    config with `areas` `["a"]`, `labels` `{"epic": "", "story": "", "bug": "", "needsSpec": ""}` and
    `verification` `{"check": "x", "manualCheckText": ""}`; after a render, line 4 of `epic.yml` is exactly
    `labels: ["epic"]`, of `story.yml` `labels: ["story", "needs-spec"]`, of `bug.yml` `labels: ["bug"]`, and
    `story.yml` has the line `        - Manual check as the story describes` and no line `        - ` alone.
  - `tests/smoke-status.sh` and `.ps1`, step `== twins (#329): an empty status name or epic label takes the default`:
    the config of the test with `"board": {"statuses": {"review": "", "inProgress": ""}}` and `"labels": {"epic": ""}`,
    scenario `a`; exit 0 and the output equals `tests/fixtures/status/a/expected.txt` byte for byte (the epic item is
    still hidden, the Review and In progress items still listed and flagged).
- Criterion 2: `tests/smoke-render.sh` and `.ps1`, step `== twins (#329): invariants: only non-empty strings,
  newlines kept`:
  - config `invariants` `["one\ntwo", "ends\n", null, "", 5, true, {"k": "v"}, ["x"], "  last  "]`: the invariants
    block of `story.yml` and of `bug.yml` is exactly these six lines (JSON escapes as written in the file):
    `        - label: "one\ntwo"`, `          required: false`, `        - label: "ends\n"`, `          required:
    false`, `        - label: "  last  "`, `          required: false`;
  - config `invariants` `[null, ""]`: `story.yml` and `bug.yml` equal byte for byte the files rendered from the same
    config without `invariants` (the block is removed).
- Criterion 3:
  - warm-up message: the existing steps "claim 3" of `tests/smoke-slot.sh` (`c_restored ... "warm-up 1 failed (exit
    7); slot 1 is free again"`, exit 1) and `tests/smoke-slot.ps1` (`Test-Restored ... "warm-up 1 failed (exit 7);
    slot 1 is free again"`) stay and are this case's steps; no new step.
  - `tests/smoke-slot.sh` and `.ps1`, step `== twins (#329): --release frees the slot when the branch cannot be
    deleted`: slot 1 busy on `feat/rd` with a merged pull request in the fake gh (the "automatic release" setup),
    `feat/rd` checked out in a second worktree outside the slots; `--release 1` exits 0, the last line of standard
    output is `Slot 1 is free (was feat/rd, PR #<n>).`, standard error contains `cannot delete branch 'feat/rd'`, the
    marker `slot-1.json` is gone, `refs/heads/feat/rd` still exists, slot 1 is detached at `origin/main`, the ledger's
    last line is a `free` record with `released`, and `--status --porcelain` shows `1 TAB free`.
  - `tests/smoke-slot.sh` and `.ps1`, step `== twins (#329): --release and --abandon exit 1 with one line on a failed
    git or gh call`: (a) slot 1 busy, origin set to a path that does not exist: `--release 1` exits 1, the last line
    of standard error is exactly `git fetch failed`, the marker is unchanged byte for byte; (b) the fake gh made to
    fail for `pr list` (exit 1): `--release 1` exits 1, last line `gh pr list failed`, marker unchanged; (c) `--abandon
    1 --base origin/nope` (`-Abandon 1 -Base origin/nope`): exit 1, last line `git switch failed`, marker unchanged.
  - `tests/smoke-slot.sh` and `.ps1`, step `== twins (#329): a marker that is not a JSON object is a busy slot in
    --status`: slot 1 busy from a normal take, slot 2's marker written as `{ "slot": 2, "branch": ` (no line end);
    `--status --porcelain` exits 0, its line 2 is exactly `2 TAB busy TAB TAB TAB TAB unknown TAB TAB TAB TAB`, line 1
    is slot 1's busy line as before, standard error is exactly the one line `slot 2: the marker is not a JSON object`;
    `--status` exits 0 and has the line `slot 2  <where>  busy: (the marker is not a JSON object)` (the `%-15s`
    layout) and slot 1's line as before, with nothing on standard error; then the marker written as `null`: the same
    two outputs (busy, not free).
  - `tests/smoke-status.sh` and `.ps1`, step `== twins (#329): a marker that is not a JSON object`: scenario `c`,
    slot 2's marker replaced by `{ "slot": 2, "branch": `; exit 0; the `--porcelain` record of slot 2 is exactly
    `slot TAB 2 TAB busy TAB unknown TAB TAB ? TAB ? TAB - TAB ? TAB - TAB stale: busy, since unreadable`; the records
    of slots 1, 3 and 4 equal those of `tests/fixtures/status/c/expected-porcelain.txt`; standard error contains the
    line `slot 2: the marker is not a JSON object`.
  - `tests/smoke-panel.sh` and `.ps1`, the existing step `== an unreadable marker is never free` (iteration 32's test
    5), changed, not added: slot 2's marker replaced by the text `{ not json` (restored afterwards, as today); exit 0,
    standard error empty, and standard output equals byte for byte `tests/fixtures/panel/run-stall-old-free/expected.txt`
    with its line `slot<TAB>2<TAB>busy<TAB>stalled<TAB>feat/stall<TAB>fix/fixer<TAB>test<TAB>2h` replaced by
    `slot<TAB>2<TAB>busy<TAB>unknown<TAB><TAB>?<TAB>?<TAB>-` and the line `note<TAB>slot 2: the marker is not a JSON
    object` appended (so no `slot<TAB>2<TAB>free` line and no `unknown` record). In `smoke-panel.ps1` the two
    assertions "an `unknown` record" and "no `slot` record after a failed slot script" are removed, and the comment
    "slot.ps1 fails on a marker that is not valid JSON" with them; in `smoke-panel.sh` the `grep` checks are replaced by
    the same byte-for-byte comparison (its `same` helper). The fixture files do not change.
  - `tests/smoke-dashboard.sh` and `.ps1`, the existing step `== an unreadable marker is never free` (iteration 31's
    test 7), changed, not added: slot 2's marker replaced by the text `{ not json` (the fixture's markers written back
    afterwards, as today); `--once` (`-Once`) exits 0, and the page equals byte for byte
    `tests/fixtures/dashboard/run-stall-old-free/expected.html` with its line
    `<tr><td class="num">2</td><td>busy</td><td class="stalled">stalled</td><td>feat/&lt;b&gt;&amp;&#39;x</td><td>fix/fixer</td><td>test</td><td class="num">2h</td><td class="num">4h</td><td>-</td><td class="flagged">stale: busy, no open PR</td></tr>`
    replaced by
    `<tr><td class="num">2</td><td>busy</td><td class="unknown">unknown</td><td></td><td>?</td><td>?</td><td class="num">-</td><td class="num">?</td><td>-</td><td class="flagged">stale: busy, since unreadable</td></tr>`
    and the four lines `<h2>Notes</h2>`, `<ul>`, `<li>slot 2: the marker is not a JSON object</li>`, `</ul>` inserted
    directly before its line `<h2>What the words mean</h2>` (the expected text is built from `expected.html` in the
    step; the fixture files do not change). The existing check that the page holds no
    `<td class="num">2</td><td class="free">free</td>` stays in both shells, and both check that the page holds
    neither `unknown: the slots could not be read` nor `unknown: the board could not be read`. In `smoke-dashboard.sh`
    the `has` check of the row start is replaced by the comparison; in `smoke-dashboard.ps1` the two `Has` checks of
    `unknown: the slots could not be read (` and `unknown: the board could not be read (` are removed, and the
    comment "slot.ps1 fails on the marker, so status.ps1 and the fallback both fail: both parts say unknown" with
    them.
- Criterion 4: `tests/smoke-status.sh` and `.ps1`, step `== twins (#329): a since that is not a time`: a new
  scenario `tests/fixtures/status/e/` with `items.json`, `prs.json` and `ages.json` copied from `c` and this
  `markers.txt` (tab separated, as in `c`):
  `1 feat/merged yesterday next session done 2026-11-04T09:00:00`, `2 feat/odd 2026-11-05 10:00:00` (a space for the
  `T`, a three-key marker), `3 feat/stale 2026-11-02T12:00:00 next implementer check 2026-11-02T13:00:00`, `4 feat/new
  2026-11-05T11:50:00 fix fixer test 2026-11-05T11:55:00`. Exit 0 for the text form, `--porcelain` and `--json`;
  the slots section of `expected.txt` is:

  ```
  slot  State  Agent    Branch       Skill             Step   Report  Since  PR          Flag
     1  busy   stalled  feat/merged  next/session      done       1d      ?  #60 merged  stale: busy, PR merged (slot --release 1)
     2  busy   unknown  feat/odd     ?                 ?           -      ?  -           stale: busy, since unreadable
     3  busy   stalled  feat/stale   next/implementer  check      2d     3d  -           stale: busy, no open PR
     4  busy   running  feat/new     fix/fixer         test       5m    10m  -
  ```

  (rows 3 and 4 and the item table and capacity line as in `c/expected.txt`); in `expected.json` the slot 2 object is
  `{"slot":2,"state":"busy","agent":"unknown","branch":"feat/odd","skill":"?","step":"?","report":"-","since":"?","pr":"-","flag":"stale: busy, since unreadable"}`
  and slot 1's has `"since":"?"` and `"flag":"stale: busy, PR merged (slot --release 1)"`; `expected-porcelain.txt`
  holds the same cells. The expected files are written with `UPDATE_STATUS_FIXTURES=1` by the bash step and read
  before they are committed; the PowerShell step compares against the same files, which is the parity check.
  Standard error is empty.
- Criterion 5:
  - `tests/smoke-render.sh` and `.ps1`, step `== twins (#329): config keys are matched by their exact spelling`:
    config `labels` `{"Epic": "big", "story": "tale"}`; line 4 of `epic.yml` is `labels: ["epic"]` and of
    `story.yml` `labels: ["tale", "needs-spec"]`.
  - `tests/smoke-slot.sh` and `.ps1`, step `== twins (#329): worktrees.Slots is not worktrees.slots`: the test's
    config with `worktrees.slots` removed and `"Slots": 3` added, published to origin as the test does; the first
    line of `--status` is `slots = 2  root = <the test's root>` and `--status --porcelain` lists slots 1 and 2 only.
  - `tests/lint.sh`, section `the PowerShell scripts read the config with exact keys (#329)`: every file in
    `scripts/*.ps1` and `scripts/lib/*.ps1` that contains both `nightmill.json` and `ConvertFrom-Json`, other than
    `validate-config.ps1`, contains `Select-ExactKeys`; a file that does not is named in a `FAIL:` line.
- Criterion 6: `tests/smoke-release.sh` and `.ps1`, step `== twins (#329): prepare keeps CRLF line ends in
  CHANGELOG.md`: `setup`, then a commit that rewrites `CHANGELOG.md` with every LF replaced by CRLF; prepare with
  `--version 0.2.0 --no-pr` (`-Version 0.2.0 -NoPr`) exits 0; `CHANGELOG.md` on `release/v0.2.0` equals byte for byte
  the expected text of the existing prepare step with every line end CRLF (the empty line and the `## 0.2.0 (<today>)`
  line included, and a final CRLF); it holds no LF that is not preceded by CR. The existing prepare step also asserts
  that its LF file comes out with no CR byte.
- Criterion 7: the steps above, each present in both shells under the same name.

No manual check (see Story trigger and manual check).

## Files touched

- `scripts/lib/json.sh`: `json_text PATH [DEFAULT]` (decision 1), and its line in the header list.
- `scripts/lib/exactkeys.ps1` (new): `Select-ExactKeys` (decision 7), with a header saying what it removes and why.
- `scripts/render-templates.sh`: `json_text` for the four labels and `manualCheckText`; invariants by decision 2 (only
  string items with at least one character, the value read without losing trailing newlines, the block removed when
  none is rendered).
- `scripts/render-templates.ps1`: invariants by decision 2 (only `[string]` items that are not empty; under
  PowerShell 7 a date-like string converted by `ConvertFrom-Json` is formatted back with `ToString("s")`, the rule of
  `slot.ps1`'s `Get-Text`); `Select-ExactKeys`.
- `scripts/status.sh`: `json_text` for `board.statuses.*` and `labels.epic`; the header gets one sentence on the Since
  cell `?` and the `stale: busy, since unreadable` flag.
- `scripts/lib/status.awk`: the form check of decision 3 before `stamp`, the `?` cell and the flag order.
- `scripts/status.ps1`: decision 3 (the regex and `StampOf` instead of `ParseExact`, the `?` cell, the flag order);
  `Select-ExactKeys`; the header sentence as in `status.sh`.
- `scripts/slot.sh`: `--status --porcelain` and `--status` by decision 4 (one read of the marker per slot, json.awk's
  error kept off standard error, the root-kind check); `--release` by decisions 5 and 6 (`git branch -D` may fail;
  `git fetch`, `gh pr list` and `git switch` checked, each with its line and exit 1); `--abandon` by decision 6; the
  header gets one sentence on the exit codes and one on the unreadable marker.
- `scripts/slot.ps1`: `Read-Marker` that does not throw in the two status forms and a busy slot for every marker file
  (decision 4); `--release` and `--abandon` lines with `Exit-Line` and the `gh` check (decision 6); `Select-ExactKeys`;
  the same header sentences.
- `scripts/release.sh`: the changelog cut by decision 8. `scripts/release.ps1` does not change.
- `scripts/drive.sh`, `scripts/dashboard.sh`, `scripts/history.sh`, `scripts/template-board.sh`: `json_text` for the
  `board.statuses.*` and `labels.*` reads (`template-board.sh`'s `cfg` helper, which also serves `statusField`,
  `priorityField` and `areaField`, as `template-board.ps1`'s `Cfg` already does).
- `scripts/guard.sh`: `json_text` for `board.statuses.ready` and `board.statuses.approved`.
- `scripts/guard.ps1`: the same two reads take the default for `""`; `Select-ExactKeys`.
- One line each, `Select-ExactKeys` after the config is parsed (and the dot-source of `lib/exactkeys.ps1`):
  `scripts/control.ps1`, `scripts/dashboard.ps1`, `scripts/drive.ps1`, `scripts/gate.ps1`, `scripts/history.ps1`,
  `scripts/load.ps1`, `scripts/models.ps1`, `scripts/new-worktree.ps1`, `scripts/panel.ps1`, `scripts/room.ps1`,
  `scripts/stages.ps1`, `scripts/template-board.ps1`, `scripts/lib/baseconfig.ps1` (its read of `git.baseBranch`).
- `tests/smoke-render.sh`, `tests/smoke-render.ps1`, `tests/smoke-status.sh`, `tests/smoke-status.ps1`,
  `tests/smoke-slot.sh`, `tests/smoke-slot.ps1`, `tests/smoke-release.sh`, `tests/smoke-release.ps1`: the steps under
  Tests.
- `tests/smoke-panel.sh`, `tests/smoke-panel.ps1`: the step `== an unreadable marker is never free` gets the expected
  output of decision 4 (Tests). `scripts/panel.sh`, `scripts/panel.ps1` (other than its `Select-ExactKeys` line),
  `hooks/panel.tsx`, `hooks/panel.test.tsx` and `tests/fixtures/panel/` do not change.
- `tests/smoke-dashboard.sh`, `tests/smoke-dashboard.ps1`: the step `== an unreadable marker is never free` gets the
  expected page of decision 4 (Tests). `scripts/lib/dashboard.awk` and `tests/fixtures/dashboard/` do not change;
  `scripts/dashboard.sh` and `scripts/dashboard.ps1` change only as listed above (decisions 1 and 7), and `drive.*`,
  `load.*` and `control.*` change only as listed above, none of them for decision 4.
- `tests/fixtures/status/e/` (new): `markers.txt`, `items.json`, `prs.json`, `ages.json`, `expected.txt`,
  `expected-porcelain.txt`, `expected.json`.
- `tests/lint.sh`: the section of criterion 5.
- `README.md`: one sentence after the configuration table: "Keys are matched by their exact spelling in both shells
  (`Slots` is not `slots`; `validate-config` warns about it), and an empty string for a label, a status name or
  `verification.manualCheckText` counts as not set."
- `CHANGELOG.md`, under `Unreleased`:
  `- Iteration 57 (#329): the bash and PowerShell twins give the same result where they differed. An empty label,
  status name or verification.manualCheckText takes its default in both shells; the issue forms render only
  invariants that are non-empty strings, with their newlines kept; slot --release frees the slot when the local branch
  cannot be deleted, and --release and --abandon exit 1 with one line on a failed git or gh call; slot --status shows a
  marker that is not a JSON object as a busy slot and /status shows a slot whose since is not a time with Since ? and
  the flag "stale: busy, since unreadable", exit 0 in both shells; the PowerShell scripts match config keys by their
  exact spelling, as bash does (a misspelled key such as worktrees.Slots is no longer read); release.sh keeps CRLF
  line ends in CHANGELOG.md, as release.ps1 does.`

## Risks

- **The PowerShell side is unverified here.** Every PowerShell finding was read, not run, and the PowerShell steps
  run only in CI. If CI shows a finding to be different from what is recorded (for example the exit code of
  `status.ps1` on a malformed `since`), the rule of the decision still holds; only the description of today changes.
- **`Select-ExactKeys` changes what a PowerShell project with a misspelled key gets**: the value it read so far is
  ignored and the default is used, as in bash. `validate-config` already warns about the key. Limited by naming it in
  the CHANGELOG and the README.
- **`guard.ps1` runs on every tool call**: reading and walking the schema adds the parse of one small JSON file per
  call. Limited by doing it once per run; the schema is about 20 KB.
- **`json_text` changes bash for a project that set a label or status to `""`**: `/status` in bash then hides epics
  again and the forms get the default label, which is what PowerShell did all along.
- **A date-like invariant under PowerShell 7** is turned into a date by `ConvertFrom-Json`; formatting it back with
  `ToString("s")` gives the text only when it was written in that form. Limited: an invariant is a sentence, not a
  time; the risk is named so that a reviewer can check it.
- **Hot files**: the slot scripts must not be changed by a paired task (`parallel.doNotPair`).

## Size estimate

L (more than 400 changed lines). About 15 lines in `json.sh` and the bash readers, 50 in `exactkeys.ps1` and its 17
call sites, 30 in `render-templates.*`, 30 in `status.awk` and `status.ps1`, 60 in `slot.sh` and `slot.ps1`, 15 in
`release.sh`, 20 in headers, the README and the CHANGELOG, about 280 in the smoke steps of both shells, the fixture
folder and the lint section: about 500.

## Not done

- Rejecting a malformed `since` with exit 2 (out of scope by the story: the status stays readable).
- No new, renamed or removed config key; the schema, the example config and the README table keep their keys.
- No calendar check of `since` or `reported` (a form-correct but impossible time is computed by the same arithmetic in
  both shells, as `reported` is today).
- No repair, rewrite or removal of a broken marker; `--take`, its reap, `--release`, `--abandon` and `--report` on a
  marker that is not a JSON object keep today's behaviour (each refuses or stops; only the status forms change).
- The empty-string rule covers only the keys the issue names; `git.specPrefix`, `github.*`, `labels.areaPrefix`,
  `labels.priorityPrefix` and the other string keys keep their current handling in each twin (see Left).
- `areas` and the labels keep losing a trailing newline in bash; a newline in `manualCheckText`, which is written as
  plain YAML, still breaks the form in both shells. Only invariants are in the criterion.
- `new-worktree.*` is not changed (see Left).
- The legend of `/nightmill:status`'s dashboard page (`scripts/lib/dashboard.awk`, "stale: ...: flagged as /status
  flags it: ...") does not list the new flag.
- The specs of earlier iterations are not edited; where this spec changes what one says (decision 4: iteration 32's
  Facts lines 107 to 108, its test 5, its manual check 4 and its line 571; iteration 31's Facts lines 44 to 46, its
  test 7 and its line 662), this spec supersedes that sentence.

## Left

- **`new-worktree.*` still differ on a failure.** A failing warm-up command: bash exits with the command's code and
  prints no line of its own; PowerShell throws `warm-up '<command>' failed` and exits 1. A failing `git fetch` or
  `git worktree add`: bash exits with git's code (128), PowerShell throws and exits 1. It is the same pair as finding 3,
  but `new-worktree` is not a slot script, so this spec leaves it; the maintainer can add it here (a line
  `warm-up N failed (exit C)` and exit 1 in both) or file it as its own bug.
- **Empty strings in keys the issue does not name.** `git.specPrefix: ""` gives no spec prefix in `status.sh` and
  `spec/` in `status.ps1` (its `Cfg`); `drive.*`, `dashboard.*`, `history.*` and `template-board.*` have the same
  pattern for any key they read through `Cfg`. A rule for all keys needs a decision on keys where `""` may be meant
  (`labels.areaPrefix`, `labels.priorityPrefix`).
- **The same key in two spellings in one config** (`"slots"` and `"Slots"`): bash reads the exact one; whether
  PowerShell's `ConvertFrom-Json` accepts such a document at all (Windows PowerShell 5.1 is believed to refuse keys
  that differ only by case) could not be checked here. Not specified; CI or a machine with PowerShell can show it.
- **A `since` with a time zone suffix** (`2026-11-05T10:00:00Z`, never written by a slot script): under PowerShell 7,
  `ConvertFrom-Json` turns it into a date and `Get-Text` formats it back as `2026-11-05T10:00:00`, a well-formed time,
  while bash sees a malformed `since`. Making that identical needs reading the marker's raw text in PowerShell 7; this
  spec does not, and its smoke step does not use such a value.
