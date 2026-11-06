# Iteration 31: a page in the browser shows the slots and what waits for the maintainer

Status: draft, awaiting approval (#68)

Story: #68, epic #47 (Unattended runs). Adds one read-only command, `scripts/dashboard.sh` and `scripts/dashboard.ps1`,
that renders one self-contained HTML page from the data `/status` already gathers: every slot with its agent state
(running, stalled, unknown, free), branch, skill and step, the age of the last report, the pull request and CI, the
`stale:` flag, and the board items at Spec review and Approved with their pull requests and CI. Run as a loop in a
terminal, it rewrites the page every `worktrees.dashboardRefreshSeconds` seconds until it is stopped with Ctrl-C, and the
page reloads itself; `--once` renders once. Adds a machine-readable form to `/status`'s scripts,
`status.sh --porcelain` / `status.ps1 -Porcelain`, which the page reads (the text form is unchanged). Adds one config
key under `worktrees`. Changes `scripts/status.sh`, `scripts/status.ps1`, `scripts/lib/status.awk`,
`schema/nightmill.schema.json`, `templates/nightmill.example.json`, `README.md`, `CHANGELOG.md`, `tests/lint.sh`,
`tests/check.sh`, `.github/workflows/ci.yml`, `tests/smoke-status.sh`, `tests/smoke-status.ps1` and the fixtures of
`tests/fixtures/status/`; adds `scripts/dashboard.sh`, `scripts/dashboard.ps1`, `scripts/lib/dashboard.awk`,
`tests/smoke-dashboard.sh`, `tests/smoke-dashboard.ps1` and `tests/fixtures/dashboard/`. No skill, no agent, no hook, no
change to the slot scripts, the slot marker, `capacity.json`, `skills/status/SKILL.md` or the status flow.

**This is a story trigger**: a new config key ("a new, renamed or removed config key"). The status flow and who sets a
status do not change, and neither does the slot marker. The pull request therefore does **not** auto-merge; it says so.
No path in `verification.manualCheckPaths` (`skills`, `agents`, `hooks`) changes, so the manual check of a skill does
not apply; the issue's own check of a real run does (see Verification).

**Order.** #67 (iteration 23: the ten porcelain fields, the agent states, `NIGHTMILL_NOW`, the Slots section of
`/status`) and #60 (iteration 17) are merged and on `main`; this iteration builds on that code. #81 (iteration 28, the
room check) is being implemented now; it changes the schema (a hot file: `parallel.doNotPair` forbids two tasks that
both change it), the example template, the README's configuration table, the lint, `tests/check.sh`, `ci.yml` and the
CHANGELOG. #82 (iteration 30, the load controller, spec in review) changes the schema too. So this iteration is
implemented **after #81 has merged**, rebased on it, and **never at the same time as #82** (if #82 is Approved first,
after it has merged). Its key goes under `worktrees`, theirs under `parallel`, so the keys do not collide; on a conflict
in the README table, the lint, `check.sh`, `ci.yml` or the CHANGELOG both sides are kept (CHANGELOG in iteration order).
Neither #81 nor #82 changes `scripts/status.*`.

## Goal

The maintainer opens one local page in a browser and sees the slots, the agent in each busy slot, whether it is running
or stalled, and what waits for the maintainer, and the page keeps up with the run.

## Facts this rests on

- `slot --status --porcelain` prints `<n> TAB free` for a free slot and ten fields for a busy one: `<n> busy <branch>
  <since> <retiring> <agent> <skill> <role> <step> <reported>`; field 6 is `running`, `stalled` or `unknown`, decided by
  the slot script alone from `worktrees.stalledAfterMinutes` (iteration 23, decision 4). It needs no `gh` and no
  network. It honours `NIGHTMILL_NOW`. A marker that is not valid JSON is listed busy with empty fields and `unknown` by
  `slot.sh`; `slot.ps1` fails on it (its `ConvertFrom-Json` throws), so `status.ps1` exits 2 with `slot.ps1 failed`.
  Neither lists it as free. This iteration does not change that difference.
- `status.sh` / `status.ps1` read the board, the pull requests and the slots with one fixed set of calls (`gh project
  item-list`, `gh pr list`, `gh project view`, `gh api graphql` with a query, `slot --status --porcelain`,
  `slot --capacity`) and print two tables: the board items (columns `#`, `Title`, `Status`, `Who`, `PR`, `Age`, `Flag`;
  Spec review first, then Approved, ...) and, when the project has `worktrees`, the Slots section (columns `slot`,
  `State`, `Agent`, `Branch`, `Skill`, `Step`, `Report`, `Since`, `PR`, `Flag`) and the `capacity:` line. The PR cell
  is `#<n> open, ci <pass|fail|pending|none>`, `#<n> draft`, `#<n> merged`, `#<n> closed` or `-`. Exit code 0 when the
  table was printed; 2 for a usage error, a missing or unreadable config, `gh` missing, or a failed `gh` call or slot
  call, with one message on standard error (`status.sh: <reason>`, `status.ps1: <reason>`) and nothing useful on
  standard output. The note of an unusable `stalledAfterMinutes` reaches their standard error on success.
- The text table cuts titles to 36 characters and pads columns with spaces, so it cannot be split back into fields
  reliably (a title holds spaces; right-aligned columns have no fixed start).
- Titles, branch names, steps and error messages are text from outside: a git branch name may contain `<`, `>`, `&`,
  `'` and `"` (`git check-ref-format` forbids none of them); an issue title may contain anything.
- `status.ps1` decodes `gh`'s output with `[Console]::OutputEncoding`, which in Windows PowerShell 5.1 is the console's
  code page, not UTF-8; a non-ASCII title is then garbled. The text form of `/status` lives with that today.
- A page opened from a `file://` URL can reload itself with `<meta http-equiv="refresh" content="N">` and can run an
  inline `<script>` without any network access in Chromium-based browsers (Chrome, Edge) and Firefox (unless the user set
  Firefox's `accessibility.blockautorefresh`). This is not checked by the smoke tests; Verification step 1 checks it.
- The schema keywords the validators understand are `type`, `properties`, `required`, `items`, `minimum`, `minItems`,
  `additionalProperties` and `enum`; there is no `maximum`. An unknown key is a warning of the validator, not an error.
- The bash scripts read JSON with `scripts/lib/json.sh`, never with jq (iteration 7); CI hides jq before the bash smoke
  tests and runs shellcheck at warning level on `scripts/*.sh`, `scripts/lib/*.sh` and `tests/*.sh`.

## Decisions

**1. A static file rewritten on a timer, not a server.** The script writes the page to a file and the page reloads
itself with a meta refresh. A server would need a listener in both shells (`HttpListener` in PowerShell; nothing that
ships with bash, so `nc`, `socat` or Python, none of which the plugin may assume), a port (a config key, a port clash,
a firewall prompt on Windows) and a guarantee that it listens on the local machine only. A file has none of these:
nothing listens at all, so nothing is reachable from another machine. The page cannot ask for fresh data, so it is as
fresh as the last rewrite, at most one interval plus one reload old. There is no port and no port key.

**2. A loop in a terminal, with `--once` for one render.** `dashboard.sh` without arguments renders, sleeps the
interval and renders again until it is interrupted (Ctrl-C) or its terminal closes. It runs in the foreground; it starts
nothing in the background and detaches nothing, so nothing is left running when the terminal closes. `--once` /
`-Once` renders once and exits: the smoke tests use it (no real sleeping), and a scheduler may call it. No skill, no
`/loop`, no hook runs the dashboard.

**3. The page lives in the operating system's temporary folder, never in the project.** `<temp>/nightmill-dashboard-
<owner>-<repo>.html`, so it is outside every checkout and every worktree and is never committed; one page per project
(by `github.owner` and `github.repo`), the same file on every start, so a browser tab stays valid across restarts. Not in
`<worktrees.root>/.slots`: that folder's layout belongs to the slot scripts (iteration 8), and a project without
`worktrees` still has a page. No key for the place: the issue names none.

**4. The script does not open a browser.** It prints the `file://` URL; the maintainer opens it once. Opening a
browser from a script differs per system and would open a new tab on every start.

**5. The data comes from `/status`'s scripts through a new porcelain form.** The dashboard calls
`status.sh --porcelain` (`status.ps1 -Porcelain`) once per render and reads its lines; it never calls `gh` itself.
`--porcelain` prints the same cells as the text tables, tab-separated, from the same code, so the page and `/status`
cannot disagree, and the stale rules, the PR choice and the ages are not written a second time. Parsing the text table
was rejected (see Facts). The text form of `/status` does not change.

**6. Unknown is shown, never guessed.** When `status --porcelain` fails (no `gh`, logged out, no network, a failed slot
call), the board part of the page says `unknown` with the reason, never "nothing waits". The slots are then read
directly with `slot --status --porcelain`, which needs no network, so the agent states stay visible; the pull request
and flag cells of a busy slot say `unknown`. When that call fails too, the slots part says `unknown` with the reason.
No slot is shown free unless the slot script listed it free.

**7. One small inline script is allowed; it only reads the clock.** Criterion 1 forbids external files, fonts and
scripts; an inline script is not external. Without a script the page cannot know that it is old: a dead loop leaves a
page that reloads the same file forever and shows `running` slots that are no longer running. The inline script shows
`, <s> s ago` after the time of rendering and reveals an "Out of date" line when the page is older than 3 refresh
intervals. It makes no request, stores nothing and changes nothing; the page works without it (the time of rendering is
in the text). Its exact text is fixed below and pinned by the smoke tests.

**8. The interval is a config key, `worktrees.dashboardRefreshSeconds`, default 60, at least 10.** Each render makes
four or more `gh` calls (the GraphQL API counts them against an hourly limit shared with the agents' own `gh` calls); 60
seconds is fresh enough to watch a run whose stalled threshold is 30 minutes, and 10 is the lowest a project may set.
It is under `worktrees`, beside `stalledAfterMinutes`, because the page is mainly the slot table and explains that key;
`parallel` holds the agent limit and the load and room keys of #80, #81 and #82. A project without `worktrees` gets
the default. The page reloads at the same interval.

**9. No links on the page.** The page shows pull request numbers as text. A link would be harmless, but the issue asks
for none, and a page with no `href`, form, button or input has nothing that can act; the lint pins that.

**10. The colour is never the only signal.** Every state is a word in its own cell (`free` in `State`; `running`,
`stalled`, `unknown` in `Agent`; the `stale: ...` text in `Flag`), and the colour is a class on that cell.

## `status --porcelain`

| | bash | PowerShell |
|---|---|---|
| The tables for a program | `status.sh --porcelain` | `status.ps1 -Porcelain` |

It may be combined with `--all` / `-All`. It makes the same calls in the same order, has the same exit codes and the
same messages on standard error as the text form, and on success prints only these lines on standard output, each a
record kind and tab-separated fields, in this order:

| Line | Fields after the kind |
|---|---|
| `item` | one per row of the board table, in its order: `#`, `Status`, `Who`, `PR`, `Age`, `Flag` (empty when none), `Title` |
| `note` | one per `note:` line of the text form, the text after `note: ` |
| `slot` | one per row of the Slots section, in its order, only when the project has `worktrees`: the ten cells `slot`, `State`, `Agent`, `Branch`, `Skill`, `Step`, `Report`, `Since`, `PR`, `Flag` (a free slot: the number, `free` and eight empty fields) |
| `capacity` | once, after the slot lines, only when the project has `worktrees`: the text of the `capacity:` line after `capacity: ` |

Every `item` line has eight fields and every `slot` line eleven (the kind included); empty fields stay. The cells are
those of the text form, from the same functions, with one difference: `Title` is the whole decoded title with a leading
`[Story] ` or `[Bug] ` removed, not cut, and every tab, carriage return and line feed in it replaced by one space. No
other cell can hold a tab or a newline.

**The title is decoded the same in both shells.** PowerShell has the decoded string from `ConvertFrom-Json`. In bash
the title comes from a flat record of `json.awk`, which decodes every JSON escape (`\uXXXX` included) but writes a
backslash, line feed, tab and carriage return back as the two characters `\\`, `\n`, `\t`, `\r` (`json.awk`, lines
13-14 and `json_escape_flat`); `status.awk` does not undo that today. In the porcelain path only, `status.awk` decodes
these four escapes of the title, reading left to right, so `\\` followed by `t` is one backslash and a `t`, never a
tab. The order, in both shells: decode; remove the prefix, case-sensitively (`sub()` in awk, `-creplace` in
PowerShell, not the case-insensitive `-replace`); replace every tab, carriage return and line feed with one space; on
the page, the HTML escaping comes last. The text form of `/status` stays byte for byte unchanged in both shells. The `not shown:` line and the `nothing to show at these statuses` line have no
porcelain form; with no item there are no `item` lines.

For scenario `c` of the status fixtures (see Tests) the output is:

```
item	30	Ready	-	-	1d		Something ready
slot	1	busy	stalled	feat/merged	next/session	done	1d	1d	#60 merged	stale: busy, PR merged (slot --release 1)
slot	2	busy	unknown	feat/closed	?	?	-	11h	#61 closed	stale: busy, PR closed (slot --abandon 2)
slot	3	busy	stalled	feat/stale	next/implementer	check	2d	3d	-	stale: busy, no open PR
slot	4	busy	running	feat/new	fix/fixer	test	5m	10m	-	
capacity	slots 4 (config), agents 2 (default)
```

**Encoding.** `status.sh` passes bytes through. `status.ps1 -Porcelain` sets `[Console]::OutputEncoding` to UTF-8
without a byte order mark before its first `gh` call, inside a `try` whose failure is ignored, so `gh`'s UTF-8 output is
decoded as UTF-8 and the lines are written as UTF-8; a `finally` puts the previous `[Console]::OutputEncoding` back
after the output is written (or the script fails). Without `-Porcelain` nothing about the encoding changes.

**Line endings.** Every porcelain record ends with one LF, in both shells; no carriage return is written. `status.sh`
prints with `printf '...\n'`. `status.ps1 -Porcelain` builds the whole output as one string with `` "`n" `` after every
record and writes it with `[Console]::Out.Write(...)` once, never with `Write-Output` or `Write-Host`, which end lines
with CRLF on Windows (a CR would stick to the last field, `Title` or `Flag`, and an empty `Flag` would no longer be
empty). The text form keeps its line endings.

**Usage.** The usage lines become `usage: status.sh [--all] [--porcelain]` and `usage: status.ps1 [-All] [-Porcelain]`
(exit 2, as today). The header comments of both scripts name the porcelain form. `skills/status/SKILL.md` does not change
(the skill shows the text form).

## The command

| | bash | PowerShell |
|---|---|---|
| Rewrite the page until stopped | `scripts/dashboard.sh` | `scripts/dashboard.ps1` |
| Render it once | `scripts/dashboard.sh --once` | `scripts/dashboard.ps1 -Once` |

Run from inside the project (any checkout or worktree of it), like `/status`. Steps, in this order:

1. **Arguments.** Nothing, or `--once` (`-Once`) once. Anything else, including `-h` and `--help`, writes
   `usage: dashboard.sh [--once]` (`usage: dashboard.ps1 [-Once]`) to standard error and exits 2. `dashboard.ps1` reads
   its arguments itself (a `[switch]$Once` and a remaining-arguments parameter that must be empty), as `status.ps1` does;
   a repeated `-Once` is rejected by PowerShell's own parameter binding before the script runs, so its exit code and
   message are PowerShell's, not the usage line.
2. **The configuration**: `.claude/nightmill.json` of the main checkout, found with
   `git rev-parse --path-format=absolute --git-common-dir`. Outside a git checkout:
   `dashboard: run dashboard.sh from inside a checkout of the project` (`dashboard.ps1` in PowerShell), exit 2. No config
   file: `dashboard: no <path> (run /nightmill:init)`, exit 2. A config that is not valid JSON: the parser's error,
   exit 2. `github.owner` or `github.repo` missing or empty: `dashboard: github.owner and github.repo are needed in
   <path>`, exit 2. Nothing is written in these cases.
3. **The settings**, read once at the start (a change to the config takes effect at the next start):
   `worktrees.dashboardRefreshSeconds` (see "The config key"; a warning on standard error and the default when
   unusable); `worktrees.stalledAfterMinutes` for the legend only, by the rule of iteration 23 (a whole number from 1 to
   999999, else 30; no warning of its own, the slot script's note reaches the page's Notes); `board.statuses.specReview`
   and `board.statuses.approved` (defaults `Spec review`, `Approved`); whether the config has a `worktrees` section.
4. **The page path.** `<temp>` is `${TMPDIR:-/tmp}` without a trailing `/` in bash and `[IO.Path]::GetTempPath()`
   (which reads `TMP`, `TEMP` on Windows and `TMPDIR` elsewhere) in PowerShell. The file name is
   `nightmill-dashboard-<owner>-<repo>.html`, where every character of `<owner>` and `<repo>` other than `A-Z`, `a-z`,
   `0-9`, `.`, `_` and `-` is replaced by `_`. The URL is `file://` followed by the absolute path with `/` as separator
   and a leading `/`: bash uses the path as it is, or in Git Bash (when `cygpath` is on the PATH) `/` followed by
   `cygpath -m <path>` (`file:///C:/Users/...`); PowerShell uses the full path with every `\` replaced by `/` and a `/`
   put in front when it does not start with one. In that path both shells write every byte of its UTF-8 form outside
   `A-Z`, `a-z`, `0-9`, `-`, `.`, `_`, `~`, `/` and `:` as `%` and two upper-case hex digits (a space as `%20`), so the
   same path gives the same URL in both shells (not `[System.Uri]`, which encodes by other rules).
5. **Render** (see "One render") and **write** (see "Writing the page").
6. **`--once`**: print `dashboard: wrote <path>` and `dashboard: open <url> in a browser` on standard output, exit 0.
   **The loop**: after the first write, print `dashboard: open <url> in a browser` and
   `dashboard: rewriting the page every <N> s; stop with Ctrl-C (the page stays as last written)`; then repeat: sleep
   `<N>` seconds (`sleep`, `Start-Sleep`), render, write. A render prints nothing on success. The interval is counted
   from the end of one render to the start of the next.

**Exit codes:** 0 after `--once` wrote the page (also when parts of it are unknown: the page says so); 1 when the page
could not be written the first time (`--once` or the loop); 2 for a usage error, no checkout, no or invalid config, no
owner or repo. The loop never ends by itself after its first write; a failed child script never ends it.

**Stopping.** Ctrl-C (or closing the terminal) ends the loop. bash sets `trap '<remove the page's temporary file>' EXIT` and
`trap 'exit 130' INT`, `trap 'exit 129' HUP`, `trap 'exit 143' TERM`, so the EXIT trap runs on each; PowerShell runs the
loop in `try { } finally { <remove the page's temporary file> }`, which runs on Ctrl-C. In PowerShell Ctrl-C also ends a
render that waits for its child script (a hung `gh` included) within about a second: the script never blocks in one
.NET call on the child; it reads both streams with `ReadToEndAsync()` and waits with `WaitForExit(500)` in a loop, and
the `finally` kills a child that is still running (on Windows with `taskkill /T /F /PID <id>`, which ends its process
tree; elsewhere with `Kill()`). In bash, Ctrl-C reaches the child and its `gh` in the terminal's foreground process
group. This is best effort: the child is always ended; a `gh` process that it started may outlive it until it ends by
itself, which is not a process of the dashboard. What it leaves: the page file as last
written (complete, see "Writing the page"), nothing else; no process of its own. A process killed outright (`kill -9`, the window
of Windows PowerShell closed) may leave one temporary file beside the page; the next start does not need it and leaves
it. A `status` call that hangs (a network that does not answer) holds the loop; the page then shows "Out of date" after
3 intervals (decision 7).

## One render

1. Run `status --porcelain` of the same plugin, in its own process: `bash "$here/status.sh" --porcelain` in bash; in
   PowerShell a child process of the running PowerShell (`(Get-Process -Id $PID).Path`, arguments
   `-NoProfile -ExecutionPolicy Bypass -File "<status.ps1>" -Porcelain`, `UseShellExecute` false, `CreateNoWindow` true,
   standard output and standard error redirected and read as UTF-8, both with `ReadToEndAsync()` so that neither pipe
   fills and blocks the child (as `smoke-status.ps1` reads them), the wait a loop of `WaitForExit(500)`, the working
   directory the current one). The environment is passed on unchanged (`NIGHTMILL_NOW`, `PATH`). Standard output and
   standard error are kept apart. Both shells split each stream at LF and remove one trailing CR from every line, a
   defence for a child that writes CRLF (`slot.ps1 -Status -Porcelain` in the fallback).
2. **Status succeeded** (exit 0): the `item` lines whose `Status` equals the configured Spec review or Approved name are
   the items, in the order printed (Spec review first); the `slot` lines and the `capacity` line are the slots; the
   `note` lines and every non-empty line of standard error are the notes.
3. **Status failed** (any other exit code, or it could not be started): the board is unknown, with `<reason>` = the first
   non-empty line of its standard error with trailing spaces removed, or `status.sh exited with code <n>`
   (`status.ps1 ...`) when there is none. When the config has `worktrees`, run `slot --status --porcelain` the same way
   (`slot.sh --status --porcelain`, `slot.ps1 -Status -Porcelain`). If it exits 0, its lines are the slots in fallback
   form and every non-empty line of its standard error (the `stalledAfterMinutes` note) is a note, as on the success
   path; otherwise the slots are unknown with its reason, by the same rule (`slot.sh exited with code <n>`). In
   PowerShell this child is started and read like the status child (standard output and standard error redirected and
   decoded as UTF-8, `StandardOutputEncoding` and `StandardErrorEncoding` set to UTF-8 without a byte order mark), and
   `slot.ps1` is run with `-Command` that first sets `[Console]::OutputEncoding` to UTF-8 and then calls
   `& "<slot.ps1>" -Status -Porcelain; exit $LASTEXITCODE`, so a non-ASCII branch reads the same as in bash and a
   failure of `slot.ps1` (an exit code or a thrown error) is a non-zero exit code of the child.
4. Build the page (see "The page") and keep it in memory (a variable). The output of the child scripts is kept in
   memory too (bash: standard output and standard error each in a shell variable, never in a file; PowerShell: the
   strings of `ReadToEndAsync()`). The dashboard creates no temporary file other than the page's own sibling file of
   "Writing the page", so with a temporary folder that does not exist the dashboard fails only at that write, as
   `dashboard: cannot write <path>: <reason>` and exit 1 (a child that fails on the missing folder first makes its
   part `unknown`, which never ends the script).

## Writing the page

The page is written to a temporary file in the same folder and moved over the page, so a reload never reads half a
page: bash `mktemp "<path>.XXXXXX"` (mode 0600, so the page is readable by the user only) and `mv -f <tmp> <path>`;
PowerShell writes `<path>.<PID>.tmp` with `[IO.File]::WriteAllText` (UTF-8 without a byte order mark) and then, as
`slot.ps1` writes `capacity.json`, `[System.IO.File]::Replace($tmp, $path, [NullString]::Value)` when the page exists
(`Test-Path -LiteralPath`), else `[System.IO.File]::Move($tmp, $path)` (the first write). Not `$null` as the third
argument: PowerShell passes it as an empty string, and `Replace` throws on that. Lines end with LF in both shells. When the write or the move fails, the temporary file is
removed and one line goes to standard error, `dashboard: cannot write <path>: <reason>` (the reason on one line); the
first time this ends the script with exit 1, later it is repeated at the next interval while the loop goes on (a browser
or a virus scanner may hold the file a moment on Windows). Nothing else is written anywhere.

## The page

One HTML document, UTF-8, no external resource of any kind: no `<link>`, no `src=`, no `href`, no `@import`, no `url(`,
no web font, no `http://` or `https://` anywhere. The same input gives the same bytes in both shells. In the template
below `{N}` is the interval, `{E}` the time of rendering in seconds since 1970 (`date +%s`,
`[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()`; `NIGHTMILL_NOW` when it is set), `{T}` the local time of rendering as
`YYYY-MM-DD HH:MM:SS` (`date '+%Y-%m-%d %H:%M:%S'`,
`(Get-Date).ToString("yyyy-MM-dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)`; when `NIGHTMILL_NOW`
is set, that value read as UTC: in bash the inverse of `days` in `lib/status.awk` in awk, in PowerShell
`[DateTimeOffset]::FromUnixTimeSeconds(<n>).UtcDateTime` formatted the same way with the invariant culture, so both
shells print the same text), `{3N}` three times the interval, `{M}` the stalled threshold
in minutes, `{O}/{R}` the owner and the repository, `{SR}` and `{AP}` the Spec review and Approved names:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="{N}">
<title>nightmill: {O}/{R}</title>
<style>
body { font-family: system-ui, sans-serif; margin: 1.5em; color: #1f2937; }
table { border-collapse: collapse; margin: 0.5em 0; }
th, td { border: 1px solid #d1d5db; padding: 0.25em 0.6em; text-align: left; white-space: nowrap; }
th { background: #f3f4f6; }
.num { text-align: right; }
.running { background: #dcfce7; color: #14532d; }
.stalled { background: #fef3c7; color: #78350f; font-weight: bold; }
.unknown { background: #e5e7eb; color: #374151; font-style: italic; }
.free { color: #6b7280; }
.flagged { background: #fee2e2; color: #7f1d1d; font-weight: bold; }
</style>
</head>
<body>
<h1>nightmill: {O}/{R}</h1>
<p id="rendered" data-epoch="{E}" data-every="{N}">Rendered at {T}<span id="ago"></span>; the page reloads every {N} s.</p>
<p id="stale" class="flagged" hidden>Out of date: this page has not been rewritten for more than {3N} s. Is the dashboard script still running?</p>
<h2>Slots</h2>
{the slots part}
<h2>Waiting for you</h2>
{the items part}
{the notes part}
<h2>What the words mean</h2>
<ul>
<li><span class="running">running</span>: the agent in a busy slot reported a step within the last {M} minutes (worktrees.stalledAfterMinutes).</li>
<li><span class="stalled">stalled</span>: no report for more than {M} minutes. The session may have ended, crashed or been abandoned, or one step runs long; a slot whose run is over (step done) and that waits for its merge shows it too. Look at it: nothing is stopped or freed.</li>
<li><span class="unknown">unknown</span>: a busy slot without a report (taken by hand or by an older version), or a value this page could not read. It is never taken as free or done.</li>
<li><span class="free">free</span>: no agent works in the slot.</li>
<li><span class="flagged">stale: ...</span>: flagged as /status flags it: a busy slot whose pull request merged or closed, or that has none after 2 hours.</li>
</ul>
<script>
(function () {
  var r = document.getElementById("rendered");
  var t = Number(r.getAttribute("data-epoch")), every = Number(r.getAttribute("data-every"));
  function tick() {
    var ago = Math.max(0, Math.floor(Date.now() / 1000 - t));
    document.getElementById("ago").textContent = ", " + ago + " s ago";
    document.getElementById("stale").hidden = ago <= 3 * every;
  }
  tick();
  setInterval(tick, 1000);
})();
</script>
</body>
</html>
```

The parts (each line of HTML on its own line; a cell holds the escaped value):

**The slots part.**

| Case | HTML |
|---|---|
| no `worktrees` in the config | `<p>No slots: .claude/nightmill.json has no worktrees section.</p>` |
| status succeeded | the slot table, then `<p>capacity: {the capacity text}</p>` |
| status failed, slot script succeeded | `<p class="unknown">unknown: the pull requests, CI and flags of the slots could not be read ({reason})</p>`, the slot table in fallback form, `<p class="unknown">capacity: unknown</p>` |
| both failed | `<p class="unknown">unknown: the slots could not be read ({reason})</p>` |

The slot table: `<table>`, the header row
`<tr><th>slot</th><th>State</th><th>Agent</th><th>Branch</th><th>Skill</th><th>Step</th><th>Report</th><th>Since</th><th>PR</th><th>Flag</th></tr>`,
one `<tr>` per slot line in its order, `</table>`. The cells, in this order, each `<td>` with at most one class:

| Cell | Busy slot | Free slot |
|---|---|---|
| `slot` | `<td class="num">` the number | the same |
| `State` | `<td>busy</td>` | `<td class="free">free</td>` |
| `Agent` | the word with the class of the same name when it is `running`, `stalled` or `unknown`; any other value escaped with class `unknown` | `<td></td>` |
| `Branch`, `Skill`, `Step` | `<td>` the cell | `<td></td>` |
| `Report`, `Since` | `<td class="num">` the cell | `<td></td>` |
| `PR` | `<td>` the cell | `<td></td>` |
| `Flag` | `<td class="flagged">` the text when not empty, else `<td></td>` | `<td></td>` |

The class is chosen by comparing the value with the fixed words; a value from outside never becomes a class or an
attribute. In the fallback form the cells come from the ten fields of `slot --status --porcelain`: `Branch` field 3;
`Skill` `<skill>/<role>` with `?` for a missing part and `?` when both are missing, and `Step` the step or `?` (the rule
of the Slots section, iteration 23); `Report` and `Since` the times `reported` and `since` as written (no age is
computed; `-` when `reported` is empty); `PR` and `Flag` of a busy slot `<td class="unknown">unknown</td>`. A busy line
of the slot script with the text `retiring` in field 5 is a busy row like any other, as in `/status`.

**The items part.**

| Case | HTML |
|---|---|
| status succeeded, at least one item | the item table |
| status succeeded, no item at {SR} or {AP}, all board items read | `<p>Nothing waits for you: no item at {SR} or {AP}.</p>` |
| status succeeded, no item at {SR} or {AP}, not all board items read | `<p class="unknown">unknown: no item at {SR} or {AP} among the items read; not all board items were read.</p>` |
| status failed | `<p class="unknown">unknown: the board could not be read ({reason})</p>` |

Not all board items were read when a `note` line of `status --porcelain` starts with `the board has ` and contains
`, only the first ` (the note `status` prints when the board has more than the 200 items it reads); that note is also
shown in the notes part, as every note is.

The item table: `<table>`, `<tr><th>#</th><th>Title</th><th>Status</th><th>PR</th><th>Age</th></tr>`, one row per
item, `<tr><td class="num">{#}</td><td>{Title}</td><td>{Status}</td><td>{PR}</td><td class="num">{Age}</td></tr>`,
`</table>`.

**The notes part**, only when there is at least one note: `<h2>Notes</h2>`, `<ul>`, one `<li>{note}</li>` per note in
order, `</ul>`. Otherwise nothing (not even an empty line).

**Escaping.** Every value that comes from outside the script (all fields of `status` and `slot` lines, the reasons,
the notes, the owner, the repository, the status names, the capacity text) goes through one function before it is put
into the page, the same in both shells, in this order: `&` to `&amp;`, `<` to `&lt;`, `>` to `&gt;`, `"` to `&quot;`,
`'` to `&#39;`, and every other byte from 0x00 to 0x1F and 0x7F to one space. Other characters, non-ASCII included, are
copied unchanged (bash renders with `LC_ALL=C awk -f scripts/lib/dashboard.awk`, which works on bytes; PowerShell
replaces with `.Replace()` and a regular expression, not `WebUtility.HtmlEncode`, which would encode more). The numbers
`{N}`, `{3N}`, `{M}` and `{E}` are made by the script and are the only values in attributes.

## The config key

`worktrees.dashboardRefreshSeconds`: integer, default 60, used when 10 to 3600.

- **Schema**, in `properties.worktrees.properties` after `stalledAfterMinutes`, no `maximum` (the validators do not
  support it), on one line in the form of its neighbours:
  `"dashboardRefreshSeconds": { "type": "integer", "minimum": 10, "default": 60, "description": "How often scripts/dashboard.* rewrites the page in the browser, in seconds (10 to 3600); the page reloads itself as often. Each rewrite reads the board and the pull requests with gh once." }`
- **Example template**: `"dashboardRefreshSeconds": 60` in `worktrees` of `templates/nightmill.example.json`, after
  `stalledAfterMinutes`. This repository's own `.claude/nightmill.json` is not changed (the default applies).
- **README**, the configuration table (see README).
- **Read by** the dashboard scripts only. A value is used when it is a JSON number written as a whole number without
  sign, fraction or exponent, from 10 to 3600 (bash: kind `number` in the parsed records of `json.sh` and the text
  `^[1-9][0-9]{0,5}$`, then the range; PowerShell: an `[int]` or `[long]` in the range), as iteration 24 reads its keys.
  Absent or `null`, or no `worktrees`: 60, nothing said. Any other value (`0`, `9`, `3601`, `2.5`, `60.0`, `"60"`,
  `true`): 60 and one line on standard error at the start,
  `dashboard: worktrees.dashboardRefreshSeconds must be a whole number from 10 to 3600; using 60`.
- There is no port and no port key (decision 1), and no key for the place of the page (decision 3).
- The previous version ignores the key; its validator warns `unknown key` for it (not an error). The slot scripts and
  `/status` do not read it.

## README

- "What is in the plugin": a row after the load scripts, `scripts/dashboard.ps1`, `scripts/dashboard.sh` | Read-only: a
  page in the browser with every slot and its agent (running, stalled), and what waits at Spec review and Approved,
  rewritten every `dashboardRefreshSeconds`. Changes nothing.
- Configuration table, the `worktrees` row, at the end: ", and `dashboardRefreshSeconds` (default 60): how often
  `scripts/dashboard.*` rewrites the page in the browser".
- "Why slots" gains, after "What a slot's agent is doing", a subsection **"Watching the run in a browser"**:
  - how to start it: `scripts/dashboard.ps1` or `bash scripts/dashboard.sh` in a terminal, from inside the project; it
    prints a `file://` address to open once in a browser (it opens none itself); the page is in the temporary folder
    (`nightmill-dashboard-<owner>-<repo>.html`), never in the project;
  - how to stop it: Ctrl-C in that terminal, or closing the terminal; nothing keeps running; the page stays as last
    written and, after three intervals without a rewrite, says it is out of date;
  - what it shows: the Slots section of `/nightmill:status` (every slot, its agent state, branch, skill and step, the
    age of the last report, the pull request and CI, the `stale:` flag) and the items at Spec review and Approved with
    their pull requests and CI, rewritten every `worktrees.dashboardRefreshSeconds` seconds (default 60; each rewrite
    calls `gh` as `/status` does);
  - what running and stalled mean, in the words of "What a slot's agent is doing" (**running** while the last report is
    at most `worktrees.stalledAfterMinutes` minutes old, **stalled** after that, **unknown** without a report), and
    that the page shows each state as a word as well as a colour;
  - that a part it cannot read (no `gh`, logged out, no network) is shown as `unknown` with the reason, never as free
    or as nothing waiting, while the slot states, which need no network, stay;
  - that the page has no buttons or links and changes nothing; that `--once` (`-Once`) renders once; and that
    `status.sh --porcelain` (`status.ps1 -Porcelain`) prints the tables of `/status` tab-separated for programs (the
    record kinds `item`, `note`, `slot`, `capacity`).
- "Developing nightmill": `bash tests/smoke-dashboard.sh # dashboard.sh against fixtures and a fake gh` and
  `powershell -ExecutionPolicy Bypass -File tests/smoke-dashboard.ps1`.

## CHANGELOG

One bullet under `Unreleased`, in the form of the others: `- Iteration 31 (#68): a page in the browser shows the slots
and what waits for the maintainer. ...` naming `scripts/dashboard.sh` / `scripts/dashboard.ps1` and `--once` / `-Once`,
the page in the temporary folder rewritten on a timer and reloading itself (no server, nothing listens), Ctrl-C to stop,
the out-of-date line after three intervals, the slot table and the Spec review and Approved items with their pull
requests and CI, `unknown` for what cannot be read, the escaping, the new `status.sh --porcelain` /
`status.ps1 -Porcelain` with its record kinds, the key `worktrees.dashboardRefreshSeconds` (default 60), that the page
changes nothing, and that the key is ignored by the previous version.

## Tests

Each acceptance criterion of #68 is a test or a manual scenario. Names are the behaviour protected. CI runs shellcheck
at warning level on the new bash files: quote every expansion, write quoted words in assignments
(`state="unknown"`, `part="no-slots"`), never assign a bare word that is a shell keyword (`done`, `then`), and keep
`trap` strings in single quotes. The PowerShell files run under Windows PowerShell 5.1: no `??`, no ternary, no
`-AsHashtable`, no `&&`.

**`tests/smoke-status.sh` and `tests/smoke-status.ps1`**, new section "== porcelain", the same cases in both:

1. **The same cells as the table**: scenarios `a`, `b` and `c` with `--porcelain` (`-Porcelain`) give exactly the new
   files `tests/fixtures/status/<scenario>/expected-porcelain.txt` (both shells compare against the same files;
   `UPDATE_STATUS_FIXTURES=1` rewrites them like the others). Scenario `c`'s file is the example of
   "`status --porcelain`".
2. **Field counts**: every `item` line has eight fields and every `slot` line eleven; a free slot is
   `slot<TAB>3<TAB>free` followed by eight tabs.
3. **The title is whole**: in scenario `a` the item 2 line ends with
   `Config validator against the schema, run by init and the lint` (its `items.json` title without `[Story] `), not
   the cut one.
4. **Without worktrees** (the existing `no-slots.json` copy): no `slot` and no `capacity` line.
5. **`--all`** with `--porcelain` adds the Backlog and Done items and prints no `not shown` text.
6. **A failing `gh`** (`GH_FAIL=1`) with `--porcelain`: exit 2, the message on standard error, nothing on standard
   output.
7. **No carriage return**: the standard output of scenarios `a`, `b` and `c` with `--porcelain` (`-Porcelain`), read as
   bytes from the child process, holds no CR byte (0x0D) and ends with one LF.
8. **The text form is unchanged**: every existing case and expected file passes as before.

**`tests/smoke-dashboard.sh` and `tests/smoke-dashboard.ps1`**, the same cases in both. They build a throwaway
repository (`git init`, a `.claude/nightmill.json` with `github` `acme`/`widgets`/1, `maintainer`, `labels.epic`
`epic`, `git.specPrefix` `spec/`, `worktrees` with `root` `../wt` and `"slots": 4`, no `dashboardRefreshSeconds`), put a
fake `gh` first on the `PATH` as `smoke-status.*` do (in PowerShell a `gh.cmd` calling a script that writes the fixture
file's bytes unchanged to standard output with `[Console]::OpenStandardOutput()`, so UTF-8 reaches `status.ps1`
unchanged), write the slot markers from `markers.txt` as `smoke-status.*` do, fix the clock with
`NIGHTMILL_NOW=1793880000` (2026-11-05T12:00:00), point the temporary folder at a folder of their own (bash `TMPDIR`;
PowerShell `TMP`, `TEMP` and `TMPDIR` in the child's environment) and run every case with `--once` (`-Once`) in a child
process. Nothing sleeps.

The fixture `tests/fixtures/dashboard/run-stall-old-free/` (`items.json`, `prs.json`, `ages.json`, `markers.txt`,
`expected.html`), named after its four slots:

| Slot | Marker | PR of the branch | On the page |
|---|---|---|---|
| 1 | `feat/run`, since `2026-11-05T10:00:00`, `next`, `implementer`, `check`, reported `2026-11-05T11:55:00` | #33 open, a failing check | `running`, Report `5m`, `#33 open, ci fail`, no flag |
| 2 | `feat/<b>&'x`, since `2026-11-05T08:00:00`, `fix`, `fixer`, `test`, reported `2026-11-05T10:00:00` | none | `stalled`, Report `2h`, `-`, `stale: busy, no open PR` |
| 3 | `feat/old`, since `2026-11-03T12:00:00`, three-key marker | #20 merged | `unknown`, `?`, Report `-`, `stale: busy, PR merged (slot --release 3)` |
| 4 | none | | `free` |

| Item | Title in `items.json` | Status | PR | On the page |
|---|---|---|---|---|
| 2 | `[Story] Read the <b>spec</b> & "approve" — café` | Spec review, set 5h ago | #31 on `spec/2-read`, titled `Spec for #2 (#2)`, open, checks pass | first row: `#31 open, ci pass`, `5h` |
| 3 | `[Story] Approved and waiting` | Approved, set 2d ago | none | second row: `-`, `2d` |
| 4 | `[Story] Busy one` | In progress | #33 | not on the page |
| 5 | `[Story] At review` | Review | #34 open | not on the page |
| 6 | `"[Story] Path C:\\temp\tand more"` (the JSON text in the file: an escaped backslash, then `\t` for a tab) | Approved, set 1d ago, no assignee | none | third row: `Path C:\temp and more`, `-`, `1d` |

1. **The page names every slot**: exit 0; standard output is exactly `dashboard: wrote <temp>/nightmill-dashboard-acme-widgets.html`
   and `dashboard: open file://<...> in a browser`; the file exists there and equals `expected.html` (both shells
   compare against the same file; `UPDATE_DASHBOARD_FIXTURES=1` rewrites it); it holds `<td class="num">1</td>` to
   `<td class="num">4</td>`, one row each.
2. **Each state is a word and a colour**: the page holds `<td class="running">running</td>`,
   `<td class="stalled">stalled</td>`, `<td class="unknown">unknown</td>`, `<td class="free">free</td>`,
   `<td class="flagged">stale: busy, no open PR</td>` and
   `<td class="flagged">stale: busy, PR merged (slot --release 3)</td>`.
3. **What waits**: item 2's row comes before item 3's, and item 3's before item 6's; items 4 and 5 are absent; the PR
   and CI cells of items 2 and 3 are `#31 open, ci pass` and `-`; the capacity paragraph is `<p>capacity: slots 4 (config), agents 2 (default)</p>`.
4. **Hostile text is escaped**: the page holds `feat/&lt;b&gt;&amp;&#39;x` and
   `Read the &lt;b&gt;spec&lt;/b&gt; &amp; &quot;approve&quot; — café` (the dash and `é` as UTF-8, unchanged) and
   holds neither `<b>` nor `feat/<b`.
4a. **A title is decoded before the tab becomes a space**: in the same repository `status --porcelain` (`-Porcelain`)
   prints for item 6 exactly the line `item<TAB>6<TAB>Approved<TAB>-<TAB>-<TAB>1d<TAB><TAB>Path C:\temp and more` (one
   backslash, one space where the tab was, LF at the end), the same bytes in both shells; the page holds exactly
   `<tr><td class="num">6</td><td>Path C:\temp and more</td><td>Approved</td><td>-</td><td class="num">1d</td></tr>`
   (in `expected.html`, so the same bytes in both shells) and holds neither `temp\tand` (the escape left undecoded), `C:\\temp` nor `C:\<TAB>emp` (a decoding that is not
   left to right).
5. **Self-contained and read-only**: the page contains exactly one `<script>` and one
   `<meta http-equiv="refresh" content="60">`, `data-every="60"` and `data-epoch="1793880000"`, `Rendered at
   2026-11-05 12:00:00`, `(worktrees.stalledAfterMinutes)` with `30 minutes`; and none of `<link`, `src=`, `href`,
   `@import`, `url(`, `http://`, `https://`, `<form`, `<button`, `<input`, `<a `, `fetch(`, `XMLHttpRequest`,
   `WebSocket`, `localStorage`, `sessionStorage`. The fake `gh` log has only the four read calls of `/status` and none of
   `item-edit`, `item-add`, `item-archive`, `pr merge`, `issue edit`, `issue comment`, `issue close`, `mutation`.
6. **`gh` cannot be read** (`GH_FAIL=1`, the fake `gh` writing `HTTP 401: bad credentials` to standard error and
   exiting 1, as in `smoke-status.*`): exit 0; the page holds `<p class="unknown">unknown: the board could not be read (`
   followed by the first non-empty line of the child's standard error (step 3 of "One render"): in bash
   `status.sh: gh project item-list failed: HTTP 401: bad credentials)` (`status.sh` folds `gh`'s message into its own
   line), in PowerShell `HTTP 401: bad credentials)` (`gh`'s own line reaches `status.ps1`'s standard error before
   `status.ps1: gh project item-list failed (gh exit code 1)`); both shells check for `HTTP 401: bad credentials)`; the paragraph
   `unknown: the pull requests, CI and flags of the slots could not be read (`, the four slot rows with
   `running`, `stalled`, `unknown` and `free` as in case 2, `<td class="unknown">unknown</td>` in the PR and Flag cells of
   slots 1 to 3, the Report and Since cells of slot 1 `2026-11-05T11:55:00` and `2026-11-05T10:00:00`,
   `<p class="unknown">capacity: unknown</p>`; and it holds neither `Nothing waits` nor `<td class="free">` for slots
   1 to 3. (The reasons differ between the shells, so this case checks pieces, not a whole file.)
7. **An unreadable marker is never free**: slot 2's marker replaced by the text `{ not json` (restored afterwards):
   exit 0, and the page does not hold the row `<td class="num">2</td><td class="free">free</td>` and holds
   `unknown` for slot 2 (bash: a busy row with `unknown`; PowerShell: `status.ps1` and the fallback both fail because
   `slot.ps1` fails on the marker (see Facts), so the board and the slots paragraphs both say `unknown`).
8. **Nothing waits**: the fake `gh` answering from `tests/fixtures/status/c` (only a Ready item) with the markers of
   that scenario: the page holds `<p>Nothing waits for you: no item at Spec review or Approved.</p>` and the four slot
   rows of scenario `c`.
8a. **Not all items read is not "nothing waits"**: the same, with `totalCount` in the fake `gh`'s `items.json` set to
   250: the page holds `<p class="unknown">unknown: no item at Spec review or Approved among the items read; not all board items were read.</p>`
   and `<li>the board has 250 items, only the first 200 were read</li>`, and does not hold `Nothing waits`.
9. **Without worktrees**: a config copy without `worktrees`: the page holds
   `<p>No slots: .claude/nightmill.json has no worktrees section.</p>` and the item rows of case 3, and no `<th>slot</th>`.
10. **The interval is a config value**: `"dashboardRefreshSeconds": 15` gives `content="15"`, `data-every="15"`,
    `reloads every 15 s` and `more than 45 s`, nothing on standard error. Each of `0`, `9`, `3601`, `2.5`, `60.0`,
    `"60"` and `true` gives the warning line on standard error, exit 0 and `content="60"`; `null` and an absent key give
    no warning.
11. **Errors**: an unknown option, `--help` and `--once --once` (PowerShell: `-Once extra`, a remaining argument;
    a repeated `-Once` is PowerShell's binding error, see "The command") exit 2 with the usage line; outside a git checkout exits
    2; a repository without `.claude/nightmill.json` exits 2 with `run /nightmill:init`; a config without
    `github.repo` exits 2 with `github.owner and github.repo are needed`. None of them writes a page.
12. **A page that cannot be written**: the temporary folder pointing at a folder that does not exist: exit 1, one line
    `dashboard: cannot write <path>: ...` on standard error, no file created anywhere under the test folder.
13. **Nothing is written in the project or the slots**: after all cases the output of
    `git status --porcelain --untracked-files=all` of the throwaway repository is the same as before the first case,
    every marker is byte for byte as written, `.slots` holds no other file, and the test's temporary folder holds only
    the page (no temporary file left).

**`tests/check.sh`** runs `smoke-dashboard.sh` with the bash smoke tests and `smoke-dashboard.ps1` with the PowerShell
ones; **`.github/workflows/ci.yml`** gets `bash tests/smoke-dashboard.sh` in the bash job (after jq is hidden) and
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke-dashboard.ps1` in the PowerShell job.

**`tests/lint.sh`**, new section "== dashboard is wired". Each pinned phrase stands on one line of its file (the lint
greps line by line with `grep -F`):

- `scripts/dashboard.sh`, `scripts/dashboard.ps1`, `scripts/lib/dashboard.awk`, `tests/smoke-dashboard.sh`,
  `tests/smoke-dashboard.ps1` and `tests/fixtures/dashboard/run-stall-old-free/expected.html` exist.
- The three dashboard files only read: outside comment lines none contains `--take`, `--release`, `--abandon`,
  `--reap`, `--report`, `--capacity`, `-Take`, `-Release`, `-Abandon`, `-Reap`, `-Report`, `-Capacity`, `item-edit`,
  `pr merge`, `issue edit`, `issue comment`, `mutation`, a `gh` call (`(^|[^A-Za-z0-9_-])gh +[a-z]`), a listener
  (`HttpListener`, `TcpListener`, `socat`, `nc -l`, `http.server`), a browser opener (`Start-Process`, `xdg-open`,
  `open http`, `cmd /c start`), or any of `<form`, `<button`, `<input`, `<a `, `href`, `src=`, `<link`, `@import`, `url(`,
  `fetch(`, `XMLHttpRequest`, `WebSocket`, `localStorage`, `sessionStorage`.
- `scripts/dashboard.ps1` and `scripts/lib/dashboard.awk` each contain `http-equiv="refresh"`, `&amp;`, `&lt;`,
  `&gt;`, `&quot;` and `&#39;`; `scripts/dashboard.sh` and `scripts/dashboard.ps1` each contain `NIGHTMILL_NOW`,
  `dashboardRefreshSeconds` and `stalledAfterMinutes`; `scripts/dashboard.sh` contains `status.sh" --porcelain` and
  `scripts/dashboard.ps1` contains `-Porcelain`.
- `scripts/status.sh` contains `--porcelain)` and `scripts/status.ps1` contains `[switch]$Porcelain`.
- The schema contains
  `"dashboardRefreshSeconds": { "type": "integer", "minimum": 10, "default": 60,`; `templates/nightmill.example.json`
  has `worktrees.dashboardRefreshSeconds` equal to 60.
- The README contains `dashboard.sh`, `dashboard.ps1`, `dashboardRefreshSeconds`, `Ctrl-C` and `--porcelain`.
- `tests/check.sh` and `.github/workflows/ci.yml` contain `smoke-dashboard`.

The existing sections cover the rest: "status is wired" (the status scripts stay read-only), "config validates" (the
example with the new key), "schema keywords are supported", "bash files do not use jq" and "shell" (`bash -n` and
shellcheck). `bash tests/check.sh` stays green.

## Verification

No skill, agent or hook changes, so the manual check of a skill does not apply. The issue's check of a real run does, in
a project with slots and a board (a test project, or this repository), in PowerShell and in Git Bash on Windows, and in
bash on Linux or WSL:

1. **The page opens and reloads.** Set `"dashboardRefreshSeconds": 10` in the config, start `scripts/dashboard.ps1`
   (`bash scripts/dashboard.sh`), open the printed address in Chrome or Edge and in Firefox. The page shows the slots and
   the Spec review and Approved items; the `Rendered at` time moves on about every 10 s without touching the browser,
   and the `s ago` count runs.
2. **Running to stalled.** With `"stalledAfterMinutes": 2`, start two `/next` (or `/fix`) runs in two sessions so that
   two slots are busy and `running`. Kill one session right after a report (read the marker's `reported` time). Within
   2 minutes plus one interval that slot's Agent cell turns from `running` to `stalled`; the other stays `running`.
   Run `/nightmill:status` in a third session: the same slots, states, branches, steps, pull requests and flags as the
   page.
3. **Unknown, not free.** In the dashboard's terminal restart it with `GH_TOKEN=invalid` (or with the network off): the
   board part says `unknown: the board could not be read (...)`, the slots keep their states with `unknown` pull
   requests and flags, no busy slot shows `free`, and no "Nothing waits" line appears. Restart it normally: the page is
   whole again.
4. **Stopping.** Press Ctrl-C, once while it sleeps and once during a render: the script ends within about a second and
   says nothing more; the page stays; after 30 s (3 intervals)
   the page shows the `Out of date` line. Start it again and close its terminal window instead: no dashboard, `sleep` or
   PowerShell process is left (Task Manager, `ps`); a `gh` process started by a render may stay until it ends by itself
   (best effort, see "Stopping"), and the result notes whether one did.
5. **Nothing changed**: the board, the pull requests and every slot marker are the same before and after, `git status`
   is clean in the project and its worktrees, and the page is in the temporary folder only.

The PR's "How verified" lists the results per shell and browser and the check, and says that auto-merge is off because
the change is a story trigger (a new config key).

## Not done

- No server and no port: nothing listens, nothing is reachable from another machine, no hosted view (decision 1).
- No starting, stopping or steering of an agent, and no freeing or abandoning of a slot, from the page; no button,
  form or link on it (decision 9).
- No new information about agents: the page shows what `slot --status --porcelain` and `/status` give (#67 records it).
- No panel beside the Claude chat (#69).
- No browser opened by the script (decision 4); no skill, `/loop` or hook that starts the dashboard; no background or
  detached process.
- No config key for the place of the page, a port or switching the page off; the page always goes to the temporary
  folder.
- No change to the text form of `/status`, to `skills/status/SKILL.md`, to the slot scripts, the slot marker,
  `capacity.json` or the agent states; the PowerShell/bash difference on a marker that is not valid JSON stays (Facts).
- No history of past renders; only the last page is kept.
- No change to the status flow or to who sets a status; no decision record.
