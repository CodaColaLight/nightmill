# Iteration 54: /status prints JSON, and a history command computes cycle time per status, fix rounds, cost per issue and slot utilisation as text, JSON and a static page, which the driver's summary uses

Status: draft, awaiting approval (#166)

Story #166, epic #163 (capabilities of comparable tools), gap 3 of the gap analysis of 2026-11-05. Today `/status`
shows where things stand now (iteration 8), as a table or as tab-separated porcelain lines (iteration 31), and
`scripts/stages.*` shows where one take's time went (iteration 41); nothing shows how the work went over a night or a
month. After this iteration `status.sh --json` (`status.ps1 -Json`) prints the cells of `/status` as one JSON object; a
new read-only command, `scripts/history.sh` and `scripts/history.ps1`, computes for a time window, from the run ledger
`<worktrees.root>/.slots/ledger.tsv` and the board's own record of status changes, the time issues stayed at each
status, the fix rounds and check fix rounds per issue, the cost per issue and the slot utilisation, and prints them as
text, as JSON (`--json`) or as one self-contained HTML page in a folder (`--html <dir>`); and the summary of the
unattended driver (iteration 52, with iteration 53's ledger) carries the text of `history --run <its start>`, so the
night report and the command show the same numbers. Changes `scripts/history.sh`, `scripts/history.ps1` and
`scripts/lib/history.awk` (new), `scripts/status.sh`, `scripts/status.ps1`, `scripts/lib/status.awk`,
`scripts/drive.sh` and `scripts/drive.ps1` (from iterations 52 and 53), `skills/status/SKILL.md`, `README.md`,
`tests/smoke-history.sh` and `tests/smoke-history.ps1` (new) with fixtures under `tests/fixtures/history/`,
`tests/smoke-status.sh` and `tests/smoke-status.ps1` with new expected files under `tests/fixtures/status/`,
`tests/smoke-drive.sh` and `tests/smoke-drive.ps1`, `tests/test-drive-docs.sh`, `tests/lint.sh`, `tests/check.sh`,
`.github/workflows/ci.yml` and `CHANGELOG.md`.

## Story trigger and manual check

**Not a story trigger.** None of `escalation.storyTriggers` applies:

- *A change to the status flow or who sets a status*: no. `history.*` and `status.* --json` only read; the driver's
  change adds text to its summary comment. No status is set, added or renamed; the eight statuses are read from
  `board.statuses` as they are. No decision record is needed; `docs/decisions/` 0001 to 0003 (how nightmill develops
  and releases itself) are not touched.
- *A new, renamed or removed config key*: no. The command reads existing keys only (`github.owner`, `github.repo`,
  `github.projectNumber`, `board.statuses`, `labels.epic`, `worktrees.root`, `worktrees.slots`); the window and the
  folder are command-line options, not project values (decision 2). The schema, `templates/nightmill.example.json`
  and the README's configuration table do not change.
- *A change to the slot marker format*: no. No `slot-*.json` and no slot script changes. `ledger.tsv` is only read;
  its kinds (`take`, `step`, `free` of iteration 41, `run` of iteration 53) and fields are unchanged. **Compatible**
  (invariant not ticked, checked anyway): the text form and the porcelain form of `/status` stay byte for byte as
  they are, so `scripts/dashboard.*` and every older reader see no difference.

**The manual check applies**: `skills/status/SKILL.md` changes (`verification.manualCheckPaths` holds `skills`). Its
steps are under Tests.

**Both shells** (invariant ticked): `history.sh` and `history.ps1` take the same options, print the same bytes (LF) and
exit with the same codes; `status.sh --json` and `status.ps1 -Json` print the same bytes. Each has smoke cases in
both `tests/smoke-*.sh` and `tests/smoke-*.ps1` against the same expected files.

**Order with other work.** This spec is **built after iterations 52 (#164) and 53 (#165) are merged**: it reads the
`run` lines that iteration 53 defines and the driver writes, and it changes `scripts/drive.*`, `tests/smoke-drive.*`,
`tests/test-drive-docs.sh` and the README's `### The summary`, which iteration 52 creates. It is written against their
specs on `main` (`docs/specs/iteration-52-unattended-driver.md`, `docs/specs/iteration-53-run-limits.md`); the driver's
code is in review and was not read. Where the merged code differs in a name or a line, the implementer follows the
merged code and keeps the rules below. No file of `parallel.hotFiles` (the workflow skill, the schema, the slot
scripts) changes, so `parallel.doNotPair` does not hold it back. The live slot views (#67 to #69, iterations 23, 31
and 32) are not changed: this story is about history.

## Facts this rests on

Read on `main` at 816206e (iteration 53's spec merged) on 2026-11-10. One read-only `gh api graphql` query was run
against this repository's board (below); nothing was written.

- **`/status` today** (iterations 8 and 31): `status.sh [--all] [--porcelain]`, `status.ps1 [-All] [-Porcelain]`. The
  porcelain form prints the records `item` (`#`, `Status`, `Who`, `PR`, `Age`, `Flag`, `Title`), `note`, `slot` (ten
  cells) and `capacity`, tab-separated, LF, from the same cells as the table, with the whole decoded title and every
  C0 control character and DEL removed (#134). `status.ps1 -Porcelain` writes UTF-8 without a byte order mark with one
  `[Console]::Out.Write`. Exit 0 printed, 2 usage, config, `gh` missing or a failed `gh` call. Iteration 8 listed
  "JSON output" under Not done. `scripts/dashboard.*` read `--porcelain`.
- **The ledger** (iteration 41): `<worktrees.root>/.slots/ledger.tsv`, 11 tab-separated fields, UTF-8, LF,
  append-only; `take` (field 3 slot, field 9 the claim's UTC stamp, field 10 the take's end), `step` (field 5 the step
  name, field 6 the skill, field 7 the role), `free` (field 5 `released`/`reaped`/`abandoned`, field 8 the PR, fields
  9 and 10 the PR's `createdAt` and `mergedAt`, field 11 the closing issues joined by `,`). Its decision 1: "#165 adds
  one, #166 reads all of them". Its decision 6 says which lines form a take and its Not done leaves "cycle time per
  board status, totals across takes or issues, charts, a browser report" to #166. The root is resolved by
  `scripts/stages.sh` lines 35 to 37 (`worktrees.root`, default `../<main folder>-wt`). The helpers `ledger_clock`,
  `ledger_stamp`, `ledger_epoch`, `ledger_duration` (`Get-LedgerClock`, `Get-LedgerStamp`, `Get-LedgerEpoch`,
  `Format-LedgerDuration`) exist in `scripts/lib/ledger.*`; `NIGHTMILL_CLOCK_FILE` moves the clock in the tests.
- **The `run` lines** (iteration 53 decision 7, not yet built): written by the driver only, one per `claude -p`;
  field 3 the driver run's start stamp, field 4 the step number, field 5 the prompt, field 6 the issues joined by `,`,
  field 7 how it ended, field 8 the step's start, fields 9 to 11 `duration_ms`, `total_cost_usd`, `num_turns` as
  given (empty when absent). The gate's spend per issue (its decision 3 step 5) is the sum, over the `run` lines whose
  field 6 lists the issue, of field 10 divided by the number of issues in field 6, an empty field 10 adding 0, printed
  with two decimals.
- **The step names that count fix rounds** (`skills/next/SKILL.md` and `skills/fix/SKILL.md`, "Reporting the steps"):
  `code-review` before each launch of the code reviewer; `fix-round-<k>` before the launch of fix round k;
  `dispute-<k>` and `test-finding-<k>` for the tester's part of round k; `check-fix-<k>` before the producer of check
  fix round k. The workflow skill (**Findings and fix rounds**): the first review is round 0; a dispute and an undone
  round each cost one of `review.maxFixRounds`; check fix rounds are "counted apart from these, per pull request over
  every run". The pull request's `## Review` section holds `Fix rounds used: <r> of <m>`, but only on GitHub.
- **No ledger holds a board status.** The slot lines name steps, not statuses; the `run` lines name prompts and
  issues. The time a status was set is on the issue's timeline (iteration 8 Facts). Checked today with a query of
  the form of decision 6: `repositoryOwner(login:) { ... on ProjectV2Owner { projectV2(number:) { items { nodes {
  createdAt content { ... on Issue { number labels timelineItems(itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) {
  nodes { createdAt previousStatus status project { number } } } } } } } } }` returns, for #199 of this board, eight
  events from `previousStatus` `""` to `Backlog` through `Review` to `Done`, each with its UTC `createdAt` and the
  project's number. `gh` 2.103.3.
- **`/spec` takes no slot and reports no step** (iteration 41 decision 11), so a spec review's rounds are in no ledger.
- **The driver's summary** (iteration 52 decision 10) has, in order: the header, the item table, the count line, the
  step lines and the `Cost:` line (from each step's `total_cost_usd`), the `Not run by the driver` line, the
  `Processes:` line, the `<details>` blocks; at most 60000 characters. Iteration 53 decision 8 lists the driver's
  `gh` calls; `gh api graphql` is among them (through the gate).
- **The dashboard's page** (iteration 31) is one self-contained HTML file in the temporary folder, rewritten every
  refresh, with no link, script, form or external resource, pinned by `== dashboard is wired` in `tests/lint.sh`.
- **The slot count** is `worktrees.slots`, default 2 (`scripts/slot.sh` line 150); the live count of `capacity.json`
  can change it during a session and is not recorded in the ledger.

## Decisions

**1. How this fits iterations 8, 31, 41, 52 and 53.**

| | Shows | Source | This iteration |
|---|---|---|---|
| `/status` (8, 31) | where things stand now | board, PRs, slots | adds `--json`; text and porcelain unchanged |
| `stages.*` (41) | where one take's time went, per step | `ledger.tsv` `take`/`step`/`free` | unchanged |
| `gate.*` (53) | whether a limit is breached | `ledger.tsv` `run`, config | unchanged; `history` computes the cost per issue by the same rule |
| driver summary (52, 53) | what one driver run did and cost | step results | gains the text of `history --run` (decision 9) |
| `history.*` (new) | how the work went over a window | `ledger.tsv` (all four kinds) and the board's status-change events | new |

The ledger stays the single run ledger of iteration 41 decision 1, read, never written, by `history`. The board's
status-change events are a second source for one number only, the time per status, because no ledger holds a status
(Facts; decision 6). Everything else comes from the ledger alone and needs no network.

**2. The command: `scripts/history.sh` / `scripts/history.ps1`, read-only.**

```
history.sh  [--from <t>] [--to <t>] | [--run <stamp>]   [--json | --html <dir>]
history.ps1 [-From <t>] [-To <t>]   | [-Run <stamp>]    [-Json  | -Html <dir>]
```

- `<t>` is `YYYY-MM-DD` (read as `00:00:00Z` of that day) or `YYYY-MM-DDTHH:MM:SSZ`; `<stamp>` is the second form.
  The window is `[from, to]`, both ends included. Defaults: `to` is now (`ledger_clock`); `from` is the earliest
  field 2 of a well-formed line of any kind in the ledger (decision 3), or `to − 7 × 86400` when there is none.
- `--run <stamp>`: the window of one driver run: `from` is the stamp, `to` the latest field 2 of the `run` lines whose
  field 3 equals the stamp (now when there is none, with the note `no run lines for the driver run <stamp>`), and only
  those `run` lines count (decision 7).
- Exactly one output: the text (default, decision 8), `--json` (decision 10) or `--html <dir>` (decision 11).
- Usage errors, exit 2, the usage on stderr: an unknown argument, an option given twice or without its value, a bad
  `<t>` or `<stamp>`, `from` later than `to`, `--run` with `--from` or `--to`, `--json` with `--html`. `-h`/`--help`
  prints the usage on stdout, exit 0.
- It finds the main checkout and `.claude/nightmill.json` as `stages.*` do (the working tree's file of the main
  checkout, the root of decision 3 of iteration 41); outside a checkout or without the config: the message of
  `stages.*`, exit 2. A ledger that exists but cannot be read: `history: cannot read <path>`, exit 1.
- It writes nothing but the page of `--html`, sets nothing on GitHub, and calls exactly one kind of `gh` command, the
  query of decision 6. Exit 0 whenever it printed (or wrote) its output, also when the board could not be read or
  there is no ledger (notes, decision 8).

The bash side keeps the computation in `scripts/lib/history.awk` (as `stages.sh` keeps its in `lib/stages.awk`), reads
the GraphQL answer with `scripts/lib/json.awk` (no `jq`), and uses `lib/ledger.sh`; PowerShell uses `ConvertFrom-Json`
and `lib/ledger.ps1`.

**3. Reading the ledger.** The lines are read top to bottom with the rules of iteration 41 decision 6 for `take`,
`step` and `free` (the same takes, the same "not freed" and "running" states), plus `run` lines with 11 fields and
field 2 and field 3 stamps. Another kind is skipped silently; a malformed line of these four kinds is skipped and
counted, and one note on stderr names the count: `history: skipped <k> malformed lines of <path>`. A take belongs to
the issues of field 11 of its `free` line; a take without a `free` line, or freed without issues, belongs to no issue.
No ledger file: the note `no record yet: <path>`, and every ledger number is empty (decision 8).

**4. Fix rounds per issue** (from the ledger). Over the takes of the issue whose `free` line lies in the window:

- `rounds`: the highest `k` among the step names `fix-round-<k>`, `dispute-<k>` and `test-finding-<k>` (`k` a whole
  number of at least 1); 0 when the takes have at least one `code-review` step and none of these names; `-` (JSON
  `null`) when they have no `code-review` step (no review recorded).
- `checks` (check fix rounds): the highest `k` among `check-fix-<k>`; 0 when there is none; `-` (`null`) when the
  issue has no take in the window.

The highest number, not the count of lines, because a round's step can be reported more than once (a resumed run,
a dispute and a fix in one round) and the numbering is the skills' own count of rounds used. A spec review's rounds
are not recorded (Facts) and are not shown (Not done, Left).

**5. Cost per issue** (from the ledger). Over the `run` lines whose field 2 lies in the window (with `--run`, only
those whose field 3 is the run's stamp): an issue's `cost` is the sum, over the lines whose field 6 lists it, of field
10 divided by the number of issues in field 6, an empty field 10 adding 0 (the rule of the gate, iteration 53 decision
3 step 5, so over the whole ledger the two agree); `runs` is the number of those lines. The totals line counts every
`run` line in the window: the sum of field 10, the number of lines, the lines with an empty field 10, and the sum of
field 10 of lines with an empty field 6 (`on no issue`). Money is printed with two decimals (`$4.00`); sums are kept
unrounded until printed. An issue with `runs` 0 has the cost `-` (`null`).

**6. Time per status** (from the board). One query, paged by 100 items, at most 20 pages (as `status.*`):

```
gh api graphql -f query='query($o: String!, $n: Int!, $after: String) { repositoryOwner(login: $o) { ... on ProjectV2Owner { projectV2(number: $n) { items(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { content { ... on Issue { number labels(first: 50) { nodes { name } } timelineItems(first: 100, itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) { nodes { ... on ProjectV2ItemStatusChangedEvent { createdAt status project { number } } } } } } } } } } } }' -f o=<github.owner> -F n=<github.projectNumber> [-f after=<cursor>]
```

- Items: issues only, without the label `labels.epic`. Events: those whose `project.number` is
  `github.projectNumber`, in the order given (oldest first).
- A **stay** at status S is the time from an event whose `status` is S to the item's next event. A stay is counted
  when its end lies in the window, with its whole length (not clipped): it says how long the issue stayed. The stay
  at an item's current status has no end and is not counted (`/status` shows its age).
- S is matched against the eight values of `board.statuses` (defaults as `status.*`). A stay at another name is not
  counted; the note `<k> stays at a status not in board.statuses were not counted` says how many.
- Per status, in the flow order `backlog`, `ready`, `spec`, `specReview`, `approved`, `inProgress`, `review` (`done`
  has no end in the flow and is left out): `stays` (the count), `median` (of the stays' lengths sorted ascending, the
  element at index `floor((n − 1) / 2)` counting from 0, the lower middle), `max` and `total`; `median` and `max` are
  `-` (`null`) with no stay.
- Per issue: the total of its counted stays at each of `ready`, `spec`, `specReview`, `approved`, `inProgress`,
  `review`; `-` (`null`) where it has none.
- A failed call, no `gh` on the `PATH`, or an answer that is not the expected JSON: the board part is unknown, never
  zero. The note `the board was not read: <gh's stderr, or the reason, on one line>`, every status row and every
  per-issue time `?` (JSON: `"statuses": null` and each issue's `"times": null`), exit 0. A 20th page with
  `hasNextPage` true: the note `the board listing stopped after 2000 items`. An item with more than 100 events: its
  later events are not read, the note `<k> issues have more than 100 status changes; only the first 100 were read`.

This is the only network call. The ledger parts are computed and printed without it.

**7. Slot utilisation** (from the ledger). A take **holds** its slot from its start (field 9 of its `take` line; for a
take without one, its first line, with the note `<k> takes have no take line; their held time starts at their first line`)
to its end (the stamp of its `free` line; for a "not freed" take its last line; for a "running" take `to`), clipped
to the window. Per slot number: `takes` (takes whose held time overlaps the window), `held` (the summed clipped time)
and `share` (`floor(100 × held / (to − from) + 0.5)` percent). The slot count `S` is `worktrees.slots` (`config`), 2
when the key is absent (`default`), raised to the highest slot number among the window's takes (`record`) when that
is higher. The utilisation is `floor(100 × Σheld / (S × (to − from)) + 0.5)` percent. A window of 0 seconds gives `-`
(`null`) for every share and the utilisation. Every slot from 1 to S is listed, also one with no take. Without a
`worktrees` key and without any take in the window the slot part is `slots: none recorded` (JSON `"slots": null`).

**8. The text form** (default). Durations are `ledger_duration` (`Format-LedgerDuration`); stamps are UTC
`YYYY-MM-DDTHH:MM:SSZ`. Exactly, in this order, with one blank line between the blocks:

```
history <from> to <to> (<duration>)[, driver run <stamp>]

status          stays    median       max     total
<name>          <n>      <d>          <d>     <d>
...

issue        ready       spec specReview   approved inProgress     review rounds checks runs     cost
#<n>         <d>         ...                                              <r>    <c>   <k>     $<x>
...
cost: $<sum> in <k> headless runs; $<x> on no issue; <u> runs without a cost

slots: <S> (<config | default | record>), utilisation <p>%
  slot  takes      held  share
  <n>   <t>        <d>   <p>%
...
note: <text>
...
```

- The status rows use `printf '%-14s %6s %9s %9s %9s\n'` with the board's name of the status (`board.statuses`),
  seven rows always (with the board unknown: `?` in the last four columns).
- The issue rows use `printf '%-6s %10s %10s %10s %10s %10s %10s %6s %6s %4s %8s\n'`, one per issue that has a counted
  stay, a take or a `run` line in the window, ordered by number; with none, the single line `no issue in the window`
  replaces the header and the rows.
- The slot rows use `printf '  %4s %6s %9s %6s\n'`, slot 1 first.
- The `note:` lines come last, in the order the notes arose; the note of decision 3 on malformed lines goes to stderr
  only. A cell that holds a name from the configuration has every C0 control character and DEL removed (as #134).

**9. The night report uses the same numbers.** The driver (iteration 52 decision 10, as amended by iteration 53),
after the `run` line of its last step and before it builds the summary, runs `history.sh --run <its start stamp>`
(`history.ps1 -Run <stamp>`) from its own scripts folder, stdout to `<run dir>/history.txt`, stderr to
`<run dir>/history.err`. The summary gains one item between its item 4 (the step lines and `Cost:`) and item 5 (`Not
run by the driver`):

````
History of this run (scripts/history.sh --run <stamp>):

```text
<history.txt, as printed>
```
````

`<history.txt, as printed>` is the file line by line with one change, because the comment carries no local path
(iteration 52 decision 10): a line that starts `note: no record yet: ` is written `note: no record yet`, and a line that
starts `note: the board was not read: ` is written `note: the board was not read (the reason is in history.txt in the
run files)`. No other line of `history` names a path or carries text from another program; `history.txt` itself keeps
the notes as printed.

A run that cannot start (iteration 52 decision 10 item 1: items 2 to 5 are left out) gets no history item either,
and the driver does not run `history` for it: this item belongs to the run's steps like items 2 to 5 and is left out
with them. This is the one change this iteration makes to iteration 52 decision 10 besides adding the item itself, and
no change to its item 1. When `history` exits non-zero, the item is the one line
`History: not computed: <the first line of history.err>.`, where a first line that
ends ` of <path>` (the note of decision 3) is written without that part, and nothing else changes: the
exit code of the driver is not affected. The `Cost:` line stays as iteration 52 has it; it and the history's `cost:`
line both sum `total_cost_usd` of the same steps, so they agree whenever every `run` line was written (Risks). The
item is placed before the `<details>` blocks, so the 60000-character cut of iteration 52 never reaches it. The
driver's `gh` calls (iteration 53 decision 8) gain nothing new: the history's query is a `gh api graphql`, already on
the list; its only GitHub write stays the summary comment, the breach comment and the `blocked` label.

**10. `--json`** (history) and **`status --json`**. Both print one JSON object on one line followed by one LF, built
by the scripts themselves, never by `ConvertTo-Json` (whose escaping differs between PowerShell versions), so both
shells print the same bytes. Strings: `"` and `\` escaped with a backslash, any byte from 0x00 to 0x1F written
`\u00XX` (lower-case hex), everything else, non-ASCII included, written as is in UTF-8. Numbers: whole numbers as
digits; money as a number with exactly two decimals (`4.00`). Keys in the order shown. `status.ps1 -Json` and
`history.ps1 -Json` set UTF-8 output as `-Porcelain` does and write with one `[Console]::Out.Write`.

`history --json`:

```
{"from":"<stamp>","to":"<stamp>","run":"<stamp>"|null,
 "statuses":[{"key":"backlog","name":"Backlog","stays":3,"median":4200,"max":10800,"total":19800},...]|null,
 "issues":[{"number":12,"times":{"ready":600,"spec":null,...,"review":1800}|null,"rounds":2|null,"checks":1|null,"runs":1,"cost":4.00|null},...],
 "cost":{"total":10.00,"runs":3,"withoutCost":0,"noIssue":0.00},
 "slots":{"count":2,"from":"config","utilisation":43|null,"perSlot":[{"slot":1,"takes":3,"held":18600,"share":43|null},...]}|null,
 "notes":["<text>",...]}
```

(shown on several lines here; printed on one, without spaces). Durations are whole seconds. Every number is the one
the text form prints, before formatting.

`status --json` (`status.ps1 -Json`), combinable with `--all`; with `--porcelain` a usage error (exit 2). It makes the
same calls, has the same exit codes and stderr as the text form, and on success prints only:

```
{"items":[{"number":30,"status":"Ready","who":"-","pr":"-","age":"1d","flag":"","title":"Something ready"},...],
 "notes":["<text>",...],
 "slots":[{"slot":1,"state":"busy","agent":"stalled","branch":"feat/merged","skill":"next/session","step":"done","report":"1d","since":"1d","pr":"#60 merged","flag":"stale: busy, PR merged (slot --release 1)"},...]|null,
 "capacity":"slots 4 (config), agents 2 (default)"|null}
```

The values are exactly the porcelain cells of iteration 31 (the whole decoded title with the prefix removed, tabs and
line breaks made spaces, control characters removed); `number` and `slot` are numbers, every other value a string,
an empty cell `""` (a free slot: `"state":"free"` and eight empty strings). `slots` and `capacity` are `null` when the
project has no `worktrees`. The usage lines become `usage: status.sh [--all] [--porcelain | --json]` and
`usage: status.ps1 [-All] [-Porcelain | -Json]`; the header comments name the JSON form.

**11. `--html <dir>`: the static report.** Creates `<dir>` (and its parents) when missing and writes exactly one file,
`<dir>/index.html`, replacing an earlier one: written first to a temporary file in `<dir>` (`mktemp
"<dir>/.index.html.XXXXXX"`; PowerShell a name of the same pattern) and moved over it, so a reader never sees half a
page. Prints `history: wrote <dir>/index.html` on stdout. A `<dir>` that is a file, or a write or move that fails:
`history: cannot write <dir>/index.html (<first line of the error>)`, exit 1, no temporary file left.

The page holds the numbers of the text form and nothing else: a `<title>` and an `<h1>` `nightmill history
<owner>/<repo>`, the window line, a status table (the columns of decision 8 plus a bar: a `<div class="bar">` whose
inline `style="width:<p>%"` is the status's share of the summed totals), the issue table, the cost line, the slot table
(with the same bar for `share`) and the notes as a list. The status bar's `<p>` is a whole number,
`floor(100 × total / T + 0.5)` in integer arithmetic on whole seconds, where `T` is the sum of the `total` column over
all eight statuses; it is `0` for every status when `T` is 0, and when the board was not read (every total `?`) the
status table has no bar `<div>` at all. The slot bar's `<p>` is the slot's `share` as decision 7 computes it, and `0`
where `share` is `-`. The bars are not scaled to sum to 100. One `<style>` block in the page. No `<script>`, no `<link>`,
no `<a>`, no `href`, no `src=`, no `url(`, no `@import`, no `http`, no form or input, no `meta http-equiv="refresh"`:
it needs no network and no server and does not reload. Every text from the configuration or the board is HTML-escaped
(`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`, in that order, the escaping last), as `dashboard.*` do. UTF-8 without a
byte order mark, LF; both shells write the same bytes. Opening it is the maintainer's: the script opens no browser.

**12. `/status` the skill.** `skills/status/SKILL.md` gains one paragraph after the paragraph on `--all`: when the
maintainer asks for JSON (or passes `json`), run the script with `--json` (`-Json`), show its output exactly as
printed and add none of the three lines. Nothing else in the skill changes; it still changes nothing. `/history` is not
a skill: the command is a script the maintainer runs (Not done).

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | `/status` can print its table as JSON | Decisions 10 (`status --json`), 12; Tests, `smoke-status` section `== json`; manual check step 1 |
| 2 | From the run ledger a command computes cycle time per status, fix rounds, cost per issue and slot utilisation | Decisions 1 to 8, 10; Tests, `smoke-history` cases `text`, `json`, `window`, `run`, `gate agrees`, `board fails`, `no ledger` |
| 3 | An optional static HTML report is written to a local folder and needs no network | Decision 11; Tests, `smoke-history` cases `html`, `html not writable`; lint `== history is wired` |
| 4 | The night report of the unattended driver uses the same numbers | Decision 9; Tests, `smoke-drive` cases `history`, `history fails`; `test-drive-docs.sh` part S |

"Cycle time per status" is read as the time an issue stays at each board status; the ledger holds no status, so that
one number comes from the board's status-change events (decision 6; Left).

## Tests

**`tests/smoke-history.sh` and `tests/smoke-history.ps1`** (new, same cases, same expected files). Each builds a
throwaway main checkout under `mktemp -d "${TMPDIR:-/tmp}/nightmill-smoke-history.XXXXXX"` (removed by a trap) with a
committed `.claude/nightmill.json` (owner `acme`, repo `widgets`, project 1, `worktrees.root` `../wt`, `slots` 2, the
default statuses, `labels.epic` `epic`), `NIGHTMILL_CLOCK_FILE` set, and a fake `gh` first on the `PATH` that logs every
call to `$GH_LOG`, answers `api graphql` from `$BOARD_DIR/page-<i>.json` by the `after` value it is given (exit 1 with
a message when `GH_FAIL` is set), and fails on any other call. `tests/fixtures/history/ledger.tsv` is copied to
`<root>/.slots/ledger.tsv`. The fixture holds, at fixed stamps:

- slot 1: a take of `fix/12-x` with steps `slot-taken`, `code-review`, `fix-round-1`, `code-review`, `fix-round-2`,
  `code-review`, `pull-request`, `check-fix-1`, freed `released` with PR 70 closing `12`; then a take of `feat/y` with
  one `code-review`, freed closing `13`;
- slot 2: lines of a take without a `take` line, freed `reaped` closing `14`, with no `code-review`; then a take still
  running at the clock;
- slot 3 (above `worktrees.slots`): one take and its `free` `abandoned`;
- `run` lines of two driver runs: run A (`2026-11-09T01:00:00Z`) with `/nightmill:fix all` for `12,14` cost `6.00` and
  `/nightmill:next 13` cost `2.50`; run B with `/nightmill:next 13` with an empty field 10, and one line with an empty
  field 6 cost `0.40`;
- one line of an unknown kind, and one `step` line with 10 fields.

The board fixture: two pages; issues #12, #13, #14 with events Backlog → Ready → Spec → Spec review → Approved → In
progress → Review → Done at fixed stamps (#14 a bug: Ready → In progress → Review), an epic #5 with events (ignored),
one event of project 2 (ignored), one stay at a status `Parked` (not in the config).

| Case | Run | Expected |
|---|---|---|
| text | no option | `expected-text.txt` byte for byte (asserts: #12 `rounds 2`, `checks 1`; #13 `rounds 0`, `checks 0`; #14 `rounds -`; cost #12 `$3.00`, #13 `$2.50`, #14 `$3.00`; `cost: $8.90 in 4 headless runs; $0.40 on no issue; 1 runs without a cost`; `slots: 3 (record)`; the medians; the notes on `Parked` and on the take without a take line); `skipped 1 malformed lines` on stderr; exit 0 |
| json | `--json` | `expected.json` byte for byte; valid JSON (bash: `json_check`; PowerShell: `ConvertFrom-Json`); its numbers equal the text form's |
| html | `--html <tmp>/report/sub` (missing parents) | exit 0; `history: wrote .../index.html`; the folder holds only `index.html`, byte for byte `expected.html`; it contains none of `<script`, `<link`, `<a `, `href`, `src=`, `url(`, `@import`, `http`, `refresh`; a status name `A&B <x>` in a second config run is escaped `A&amp;B &lt;x&gt;` |
| html not writable | `--html <a file>` | exit 1; `history: cannot write `; no `.index.html.*` left |
| window | `--from` and `--to` around slot 1's second take only | only #13's take and stays ending in the window; the slot shares from the clipped held time |
| run | `--run 2026-11-09T01:00:00Z` | the header names the driver run; cost and runs from run A's two lines only; the window ends at run A's last line |
| run unknown | `--run` a stamp with no `run` line | the note `no run lines for the driver run <stamp>`; exit 0 |
| gate agrees | over `tests/fixtures/gate/ledger.tsv` (iteration 53) with `--from 1970-01-01` | the cost of #21 is `$4.00` and of #12 `$3.00`, the spend `gate.* --issue` prints for them in iteration 53's `cost` case |
| board fails | `GH_FAIL` set; then no `gh` on the `PATH` | the note `the board was not read: ...`; every time cell `?`; the ledger parts as in `text`; exit 0 |
| no ledger | the ledger removed | the note `no record yet: <path>`; the status block from the board; `no issue in the window` is not printed when the board has stays; exit 0 |
| usage | `--json --html x`; `--run S --from 2026-01-01`; `--from 2026-13-01`; `--from 2026-11-09 --to 2026-11-08`; `--html` without a value; `--json --json` | exit 2; the usage on stderr; no `gh` call |

In every case the fake `gh` log holds only `api graphql` calls with `repositoryOwner` and no `mutation`; the ledger
and the checkout are byte for byte as before (`git status --porcelain --untracked-files=all` unchanged). Each test
runs in under 30 seconds.

**`tests/smoke-status.sh` and `tests/smoke-status.ps1`**, new section `== json`, the same cases in both:

1. Scenarios `a`, `b` and `c` with `--json` (`-Json`) give exactly the new files
   `tests/fixtures/status/<scenario>/expected.json`; each is valid JSON and its `items` and `slots` hold the cells of
   that scenario's `expected-porcelain.txt` in the same order (compared field by field).
2. `--all --json` adds the Backlog and Done items.
3. A title with `"`, `\` and a non-ASCII letter (a new item in scenario `a`'s fixture, or a twin of it) comes out as
   `\"`, `\\` and the letter's UTF-8 bytes; `tests/test-status-controls.sh` gains the assertion that `--json` output
   holds no control byte either.
4. `--porcelain --json`: exit 2, the new usage line. A failing `gh` (`GH_FAIL=1`) with `--json`: exit 2, nothing on
   stdout.
5. No carriage return in the `--json` output of the three scenarios (PowerShell included).
6. The text form and `--porcelain` still give their existing expected files (unchanged).

**`tests/smoke-drive.sh` and `tests/smoke-drive.ps1`** (iterations 52 and 53), new cases:

| Case | Setup | Expected |
|---|---|---|
| history | the `loop` case | the comment holds `History of this run (scripts/history.sh --run <the run's field 3>):` and a fenced `text` block whose first line starts `history ` and names that driver run, after the `Cost:` line and before the first `<details>`; the block's `cost: $3.00 in 3 headless runs` matches `Cost: $3.00 in all`; the fake `gh` saw only calls of the driver's list |
| history no path | the `loop` case with the ledger removed after the last step's `run` line, and the fake `gh` failing only the `api graphql` call with `repositoryOwner` (its stderr names a path) | the block holds `note: no record yet` and `note: the board was not read (the reason is in history.txt in the run files)`; the comment contains neither the run directory, the checkout path nor the fake `gh`'s stderr; `history.txt` holds both notes as printed |
| history fails | a copy of `scripts/` whose `history.*` prints `boom` on stderr and exits 1 | the comment holds `History: not computed: boom.`; the exit code and every other line as in `loop` |

**`tests/test-drive-docs.sh`** part S: `scripts/drive.sh` contains `history.sh" --run` and `scripts/drive.ps1`
`history.ps1`; the forbidden words are unchanged.

**`tests/lint.sh`**, a new section `== history is wired` after `== the stage record is wired`: `scripts/history.sh`,
`scripts/history.ps1`, `scripts/lib/history.awk`, both smoke tests and `tests/fixtures/history/expected.html` exist;
the three script files contain no `item-edit`, `item-add`, `item-delete`, `pr merge`, `issue edit`, `issue comment`,
`mutation`, `--take`, `--release`, `--abandon`, `--reap`, `--report`, `--capacity` (or their PowerShell forms),
`Start-Process`, `xdg-open`, `HttpListener` (comment lines excepted), and no `<script`, `<link`, `href`, `src=`,
`url(`, `@import` or `http-equiv`; `README.md` names `history.sh`, `history.ps1`, `--html`, `status.sh --json`;
`skills/status/SKILL.md` contains `--json` and `-Json`; no file in `skills/` names `history.sh`.
The existing `== status is wired` keeps holding for the changed status scripts.

`tests/check.sh`: `add bash smoke-history.sh` after `add bash smoke-gate.sh`, `add ps smoke-history.ps1` after
`add ps smoke-gate.ps1`; `.github/workflows/ci.yml`: both in the matching `--only` list at the same place, nothing
else. Iteration 51's agreement lint (both listed in the README's `## Developing nightmill`, twins present), `== the
check runs every smoke script`, `== temporary files have a template`, `== bash files do not use jq`, `== dashboard is
wired`, `tests/test-unattended-docs.sh`, `tests/test-limits-docs.sh` and the forbidden-words lint keep passing.

**The manual check** (`claude --plugin-dir <a separate checkout>` in a scratch project with a board, slots and a
ledger from a few runs):

1. `/nightmill:status json` (and "show the status as JSON"): the skill runs `status.sh --json` (`-Json`), shows one
   JSON line and no added lines; `/nightmill:status` without it shows the table as before. No board item changed.
2. `bash <checkout>/scripts/history.sh` and `history.ps1` in that project: the same text; the times per status agree
   with the issues' timelines on GitHub, the rounds with the `## Review` sections and the `Check fix round` comments
   of the pull requests, the cost with the driver's summaries.
3. `--html <a folder>`: open `index.html` with the network off; the page shows the same numbers and asks for nothing.
4. One driver run (iteration 52) on that project: its summary holds the history block, and running
   `history.sh --run <its start>` afterwards prints the same block (apart from the two notes decision 9 shortens); the
   comment names no local path.

## Files touched

- `scripts/history.sh` (new, `100755`), `scripts/history.ps1` (new), `scripts/lib/history.awk` (new): decisions 2 to
  8, 10 and 11, with a header comment as `scripts/stages.sh` has (usage, what it reads, the one `gh` query, exit codes,
  `NIGHTMILL_CLOCK_FILE` for the tests, the spec's path).
- `scripts/status.sh`, `scripts/status.ps1`, `scripts/lib/status.awk`: `--json` / `-Json` (decision 10), the usage
  lines and the header comments. The text and porcelain paths unchanged.
- `scripts/drive.sh`, `scripts/drive.ps1`: decision 9.
- `skills/status/SKILL.md`: decision 12.
- `README.md`:
  - `## What is in the plugin`: a row
    `` | `scripts/history.ps1`, `scripts/history.sh` | Read-only: how the work went in a window - time per board status, fix rounds and check fix rounds, cost per issue, slot utilisation - from `ledger.tsv` and the board's status changes, as text, JSON (`-Json`) or one static page (`-Html <dir>`). | ``
    after the row of `scripts/stages.*`; the row of `/nightmill:status` adds "`--json` prints it as JSON".
  - A new subsection `### How the work went`, after `### Where a story's time went`: the command and its options, the
    window defaults, what each number means and where it comes from (decisions 4 to 7: the board for the time per
    status, the ledger for the rest), what `-`, `?` and the notes mean, the JSON form, the static page (one file, no
    network, opened by hand), and that spec review rounds and hand-started headless runs are not in it.
  - `### Where a story's time went`: one sentence pointing to `### How the work went` for totals across issues.
  - `## Running on a schedule` › `### The summary` (iteration 52): one sentence that the summary carries the history
    of the run (decision 9).
  - `## Developing nightmill`: `bash tests/smoke-history.sh  # history.sh: metrics from a fixture ledger and a fake gh`
    after the line of `smoke-gate.sh`, and `powershell -ExecutionPolicy Bypass -File tests/smoke-history.ps1` after
    the line of `smoke-gate.ps1`.
- `tests/smoke-history.sh`, `tests/smoke-history.ps1` (new), `tests/fixtures/history/` (new: `ledger.tsv`, the board
  pages, `expected-text.txt`, `expected.json`, `expected.html` and the expected outputs of the other cases).
- `tests/smoke-status.sh`, `tests/smoke-status.ps1`, `tests/fixtures/status/{a,b,c}/expected.json` (new),
  `tests/test-status-controls.sh` (and its `.ps1`): the cases above.
- `tests/smoke-drive.sh`, `tests/smoke-drive.ps1`, `tests/test-drive-docs.sh`: the cases and pins above.
- `tests/lint.sh`: the section `== history is wired`.
- `tests/check.sh`: the two `add` lines. `.github/workflows/ci.yml`: the two `--only` entries, nothing else.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 54 (#166): history and metrics. status.sh --json (status.ps1 -Json)
  prints the /status cells as one JSON object. scripts/history.sh and history.ps1 compute for a window, read-only, the
  time issues stayed at each board status (from the board's status changes), fix rounds and check fix rounds per issue,
  cost per issue and slot utilisation (from <worktrees.root>/.slots/ledger.tsv), as text, JSON (--json) or one static
  HTML page that needs no network (--html <dir>). The driver's summary carries the history of its run. No config key,
  no marker or ledger change.` (paths, commands and keys in backticks).

Not touched: `scripts/slot.*`, `scripts/stages.*`, `scripts/gate.*`, `scripts/lib/ledger.*`, `scripts/lib/json.*`,
`scripts/dashboard.*`, `scripts/panel.*`, `hooks/`, `agents/`, every skill but `status`, `schema/`, `templates/`,
`.claude/` of this repository, `SECURITY.md`, `CONTRIBUTING.md`.

## Risks

- **Two sources.** The time per status comes from the board, the rest from the ledger; an issue worked without a slot
  has status times and no rounds. The output says where each number comes from (README) and shows `-` or `?`, never 0,
  where a source has nothing.
- **Fix rounds by the highest step number** assume the skills keep numbering rounds per issue across a resumed run, as
  the workflow skill says for check fix rounds. If a resumed run numbers review rounds from 1 again, `rounds` is a
  lower bound; the `## Review` section of the pull request stays the authority.
- **The night report and the summary's `Cost:`** agree only when every `run` line was written; a failed append
  (iteration 53 decision 7 prints a note) makes the history's cost lower; the driver's `drive: the run ledger was not written` line on stderr says when.
- **Money in two shells.** awk's `%.2f` and .NET's `F2` can round an exact half differently; the fixtures avoid exact
  halves, as iteration 53's do.
- **The board query** is one GraphQL call per 100 items with up to 100 events each, well inside GitHub's limits; a
  board past 2000 items or an item past 100 status changes is noted, not guessed.
- **The slot count is today's**, raised to the highest slot in the record; a window across a change of the live slot
  count (`capacity.json`, not recorded) is measured against one count.
- **Size.** Large, but clear of the hot files; it depends on iterations 52 and 53 being merged.

## Size estimate

`L`: about 260 lines in `scripts/history.sh` with `lib/history.awk`, 300 in `scripts/history.ps1`, 60 across the
status scripts, 25 in each driver script, 220 in each `smoke-history.*`, 150 of history fixtures, 60 in each
`smoke-status.*` with 3 expected JSON files, 40 in each `smoke-drive.*`, 6 in `test-drive-docs.sh`, 25 in
`tests/lint.sh`, 8 in the status skill, 50 in the README, 2 in `tests/check.sh`, 2 in `ci.yml`, 8 in `CHANGELOG.md`:
about 1700 changed lines in about twenty-five files.

## Not done

- No new kind or field in `ledger.tsv`, no writer of board statuses into it, no change to `stages.*` or the gate.
- No spec review rounds: `/spec` takes no slot and reports no step (iteration 41 decision 11).
- No ledger line, and so no cost, for a `claude -p` started by hand (iteration 53 decision 7).
- No skill for the history; the maintainer runs the script, the driver runs it for its summary.
- No config key (no default window, no report folder), no automatic writing of the page, no page under the repository.
- No server, no live refresh, no browser opened, no link, no script, no chart library: tables and CSS bars only. The
  dashboard and the pane (#67 to #69) are unchanged.
- No trends per day or per week, no comparison of two windows, no per-role or per-model cost, no turns or durations
  per issue beyond the cost (the `run` lines hold them; not asked).
- No time of the current, unfinished stay at a status (`/status` shows its age), and no `Done` row.
- No audit log, no inline diff review, no web interface (named in the Context, not in the criteria).
- No change to `--porcelain` or to the text form of `/status`, and no JSON for `/models` or `stages`.

## Left

- **"Cycle time per status" from "the run ledger".** No ledger holds a board status (Facts), and iteration 41 recorded
  stages, not statuses. This spec reads the time per status from the board's status-change events with one read-only
  GraphQL query (decision 6) and everything else from the ledger. If the maintainer wants it from the ledger alone,
  something has to write status changes into the ledger (the skills at every status they set, which makes each skill
  longer, or a new line kind), which is its own story; if "status" meant the stages of iteration 41, `stages.*` already
  shows them per take and only totals across takes would be new. Not decided here.
- **Fix rounds** are counted from the reported step names (decision 4), the only source in the ledger. The pull
  request's `## Review` section (`Fix rounds used`) is the exact number but needs a `gh` call per pull request; not
  used. Spec review rounds cannot be computed from any ledger today.
- **"The same numbers" in the night report** is read as: the summary carries the output of the same command for its
  run (decision 9), not a second computation in the driver. If the maintainer wants the numbers merged into the
  summary's table instead, that is a change of decision 9.
- **"Needs no network"** is read as: the page, once written, needs no network to open; writing it reads the board for
  the time per status (decision 6) and still writes the page, with `?` and a note, when the board cannot be read.
- **Not verified by a run:** the driver's code (iterations 52 and 53) is not on `main`; the names of its run folder,
  its summary items and its scripts folder are taken from the specs, and the implementer follows the merged code.
