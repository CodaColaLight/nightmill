# nightmill

A lights-out development workflow for [Claude Code](https://code.claude.com): the maintainer reviews
issues and approves specs on a GitHub project board; agents do everything in between, in parallel,
in permanent worktree slots, and every step leaves the board showing the real state.

nightmill is a Claude Code plugin. It carries the process; a project carries its own values in one
file, `.claude/nightmill.json`.

## The flow

```
Backlog > Ready > Spec > Spec review > Approved > In progress > Review > Done
```

| Status | Meaning | Who sets it |
|---|---|---|
| Backlog | Filed, not reviewed | `/story`, the maintainer |
| Ready | Acceptance criteria reviewed; an agent may start the spec (or, for a bug, the fix) | **only the maintainer** |
| Spec | An agent is writing the spec | the agent |
| Spec review | The spec is merged as a docs PR; waiting for the maintainer | the agent |
| Approved | The spec is approved; **any** worker may implement it | **only the maintainer** |
| In progress | Being implemented or fixed | the agent |
| Review | A PR is open | the agent |
| Done | Merged or closed | the PR's `Closes #N` |

Bugs skip the spec: Ready > In progress > Review > Done.

Two gates belong to the maintainer, Ready and Approved. Everything else is an agent's job, and a
different agent can pick a story up at any stage because the board and the repository hold the state,
not a conversation.

## What is in the plugin

| Piece | What it does |
|---|---|
| `/nightmill:spec [N]` | Takes a Ready story and writes its spec as its own PR, sets Spec review and stops. |
| `/nightmill:next [N]` | Takes an Approved story and implements it: slot, tests, code, check, PR, auto-merge. With nothing Approved it lists the Ready stories and points to `/spec`. |
| `/nightmill:fix [N\|all]` | Fixes a bug: failing test first, smallest fix, one PR. `all` works through every Ready bug. |
| `/nightmill:story <idea>` | Turns a one-line idea into a story issue under the right epic, in Backlog. |
| `/nightmill:status` | One table of what waits for the maintainer and what is stuck: board items with their PR and CI state, every slot with what its agent is doing (running, stalled), stale states flagged. Read-only. |
| `/nightmill:models` | One table of each agent role's model, where it comes from (the config or the default), its rank and whether the reviewer pairings hold. Read-only. |
| `/nightmill-slots [off]` | Opens a read-only pane beside the chat with every slot and its agent (running, stalled, unknown), rereading them every `panelRefreshSeconds`; `off` closes it. Needs Claude Code 2.1.287 or later (see "Watching the run beside the chat"). |
| `/nightmill:control` | One pass of the opt-in load controller: measures the load and, in `apply` mode, raises or lowers the agent limit within the configured bounds; `/loop 5m /nightmill:control` runs it in a session. |
| `/nightmill:check` | Runs the project's check command and fixes the cause of a failure. |
| `/nightmill:init` | The install chat: detects what `gh` and the repository can tell, asks the rest one question at a time, shows one plan and, after one confirmation, creates the board with its columns view, the labels, the config, the issue forms, the CLAUDE.md snippet and the permission rules. |
| `workflow` skill | The process rules. Claude loads it when it touches an issue, a spec, a slot or a PR. |
| `worker` agent | A cheap subagent for mechanical, fully specified jobs. |
| `scripts/slot.ps1`, `scripts/slot.sh` | Permanent worktree slots: `-Take <branch>`, `-Release N`, `-Abandon N`, `-Reap`, `-Status`, `-Capacity`, `-Report <step>`. |
| `scripts/stages.ps1`, `scripts/stages.sh` | Read-only: the time a story spent in each stage, from the slots' record `ledger.tsv`, for one issue (`-Issue N`) or the last N takes (`-Last N`). |
| `scripts/load.ps1`, `scripts/load.sh` | Read-only: measures CPU load and free memory over a short window, shows the agent limit and the slots in use, and suggests an agent limit with the reason. Changes nothing. |
| `scripts/panel.ps1`, `scripts/panel.sh` | Read-only: the slot lines the pane draws, from `slot --status --porcelain`. |
| `scripts/dashboard.ps1`, `scripts/dashboard.sh` | Read-only: a page in the browser with every slot and its agent (running, stalled), and what waits at Spec review and Approved, rewritten every `dashboardRefreshSeconds`. Changes nothing. |
| `scripts/room.ps1`, `scripts/room.sh` | Before `/next`, `/spec` and `/fix` start an agent: checks free memory and CPU load, and pauses while the machine has no room. Changes nothing. |
| `scripts/control.ps1`, `scripts/control.sh` | One controller pass: measures like the load command and changes the live agent limit (and slot count) only through `slot --capacity`, only in `apply` mode. Stops nothing. |
| `scripts/new-worktree.*` | An ad-hoc extra checkout outside the slot system. |
| `scripts/render-templates.*` | Writes the project's issue forms from `areas` and `invariants`. |
| `scripts/template-board.*` | Read-only check of whether `/init` can copy nightmill's template board for a config; prints one line. |
| `schema/nightmill.schema.json` | Every configuration key, described. |

Bare `/spec`, `/next`, `/fix`, `/story`, `/check` also work unless another plugin or the project defines them.

## Install

You need Claude Code, `git`, and `gh` signed in with `gh auth login` and the `project` scope
(`gh auth refresh -s project`). The bash scripts need nothing beyond bash and the tools a POSIX shell has (awk, sed, grep).

```
/plugin marketplace add CodaColaLight/nightmill
/plugin install nightmill@nightmill
/nightmill:init
```

Hooks, permissions and
environment variables stay in the project's own `.claude/settings.json` (or the personal
`.claude/settings.local.json`); a plugin cannot set them.

A plugin cannot run anything when it is installed, so nightmill ships a `SessionStart` hook for the
first session after: in a project that has the plugin enabled but no `.claude/nightmill.json`, it prints one
line and Claude offers to run `/nightmill:init`. In a configured project the hook is silent. If you enabled
the plugin at user scope and open projects that do not use it, set `NIGHTMILL_HINT=off` in `env` in your
user `settings.json` to silence it everywhere. The hook runs `scripts/session-start.sh`, so it needs bash:
that is `sh` on macOS and Linux and Git Bash on Windows, which Claude Code uses whenever Git for Windows is
installed. On a Windows machine where Claude Code runs hooks through PowerShell only, the hook does nothing
and says nothing; `scripts/session-start.ps1` does the same job and can be wired by hand as a `SessionStart`
command hook in the project's `.claude/settings.json`.

`/nightmill:init` is an install chat. It detects what `gh` and the repository can tell (owner, repo, an
existing board, the check command, areas), asks one question at a time for the rest with a proposed
default, shows one plan table and, after one confirmation, creates or completes the board (the eight
Status options, Priority and Area, four saved views with filters, the repository link), the
labels, `.claude/nightmill.json`, `.github/ISSUE_TEMPLATE/`, the CLAUDE.md snippet, the permission
rules in `.claude/settings.json` and the edit permission in `.claude/settings.local.json`. Re-running it on a
configured project changes nothing. The board's
workflows (ten, among them item added > Backlog, item closed and pull request merged > Done, pull request
linked > Review, item reopened > In progress, auto-archive of closed items) are the one thing the API cannot
set: `/init` reads whether they are enabled and ends every run with the exact table to set once in the
board's Workflows settings in the browser, unless the board came from the template (next section).

### The edit permission

Without a rule for edits, `/spec`, `/next` and `/fix` prompt on every file they write, which defeats an
unattended run. So `/init` has a plan line **Edit permission** that adds one rule, `Edit(**)`, to
`permissions.allow` in `.claude/settings.local.json`, and shows the exact text it will write before the one
confirmation.

- **What it grants:** edits and writes (the Edit and Write tools) to files inside the project directory, which
  is what the three skills do. Not Bash, not any other directory. A write under `.claude/` still prompts.
- **Where it is written:** the personal `.claude/settings.local.json`, not the committed `.claude/settings.json`.
  Letting an unattended run edit is the choice of whoever runs it; in the committed file the rule would also
  silence the prompts of every collaborator's interactive session. A fresh clone therefore has no local file,
  and `/init` adds the line again there (one run, one confirmation). `/init` tells you when the file is not
  ignored by git; it never edits `.gitignore`.
- **Declining and re-running:** a declined line leaves both settings files untouched and is reported as
  declined (edits will prompt). Re-running `/init` changes nothing and reports the line as exists, also when
  the project already covers it with `permissions.defaultMode` set to `acceptEdits` or `bypassPermissions`.
  No entry already in the file is removed or reordered.
- **Taking it back:** delete the `Edit(**)` line from `.claude/settings.local.json`.
- **Limits:** the slots under `worktrees.root` are outside the project directory and are not covered, so the
  edits `/next` and `/fix` make in a slot still prompt. A project's allow rules apply only after the
  workspace is trusted, so a headless run (`claude -p`) needs one interactive session in the project first.

### The template board

A view's grouping and sorting and a board's workflows cannot be set through the API, but a copy of a
configured board carries them. So when a project has no board, `/init` first checks nightmill's template
board and, if it is usable, copies it (`gh project copy`), links the repository and replaces only the Area
options (and Priority when `board.priorities` differs); the Status options and their ids stay, because the
workflows point at them. The plan says which way the board is made: `create (copy of <owner>/<number>)` or
`create (field by field: <reason>)`. The reason is one of: no template published yet, the template is not
reachable from this account, your config renames a field or a status. The fallback is the field-by-field board
`/init` has always built, with the by-hand list in the report. A copy ends with a read back of the views and
workflows, and only what differs is listed.

The template lives in `templates/board-template.json` (`{ "owner": ..., "number": ... }`): a public board of the
maintainer that holds no items, only structure. It belongs to the plugin and is not a config key; a `null`
number means none is published and `/init` falls back. `scripts/template-board.ps1 -Config <file>` (or
`scripts/template-board.sh --config <file>`) prints `template: usable (<owner>/<number>)` or
`template: not usable: <none published | not reachable | fields differ | statuses differ>`; it only reads.

The maintainer refreshes the template from a configured board: `gh project copy <n> --source-owner <owner>
--target-owner <owner> --title "nightmill template"`, check that it has no items and that the ten workflows are
enabled with their targets, make it public with `gh project edit <new n> --owner <owner> --visibility PUBLIC`,
change the number in `templates/board-template.json` in a pull request, and delete the old template board.

## Configuration

One file in the project, `.claude/nightmill.json`. The schema documents every key; the short version:

| Key | What it holds |
|---|---|
| `github` | `owner`, `repo`, `projectNumber` of the board |
| `maintainer.name` | Who sets Ready and Approved |
| `board` | Field names, status names, priority order |
| `labels`, `areas`, `invariants` | Label scheme, area options, the project's rules (rendered into the issue forms) |
| `iterations` | Spec directory and name pattern, CHANGELOG path, milestone pattern, decisions directory |
| `verification` | The check command, which paths also need a manual check and what that check is, an optional bench rule |
| `escalation.storyTriggers` | Kinds of change that make a bug a story and block auto-merge |
| `roles` | The model of each agent role (`roles.<role>.model`): `specWriter`, `specReviewer`, `tester`, `implementer`, `codeReviewer`, `fixer`, `worker` |
| `models.ranking` | The models from weakest to strongest, for judging that a reviewer is at least as strong as the role it reviews |
| `review.maxFixRounds` | How many fix rounds a producer gets after a review |
| `git` | Base branch, branch prefixes, merge flags |
| `parallel` | Agent cap, hot files, task pairs to avoid, and for `scripts/load.*` the ceiling of its suggestion (`maxSuggestedAgents`, default 4), the memory one agent needs (`memoryPerAgentGB`, default 8) and the measurement window (`loadWindowSeconds`, default 10); and for the room check before each start (`scripts/room.*`) whether it runs (`roomCheck`, default true), the free memory it needs (`roomMinFreeMB`, default 2000), the highest CPU load (`roomMaxCpuPercent`, default 90), the pause between checks (`roomPauseSeconds`, default 60) and the longest wait (`roomMaxWaitMinutes`, default 30); and for the load controller (`scripts/control.*`, `/nightmill:control`) its mode (`controlMode`: `off` by default, `report`, `apply`), its bounds (`controlMinAgents`, default 1; `controlMaxAgents`, default 4), its cooldown (`controlCooldownMinutes`, default 15) and how often it runs (`controlIntervalMinutes`, default 5) |
| `worktrees` | Slot root, count, port bases, warm-up commands, run hints, and `stalledAfterMinutes` (default 30): the minutes without a report after which a busy slot's agent counts as stalled, and `dashboardRefreshSeconds` (default 60): how often `scripts/dashboard.*` rewrites the page in the browser, and `panelRefreshSeconds` (default 15): how often the slots pane beside the chat reads the slots again |

`templates/nightmill.example.json` is a complete example.

### Agent roles and models

Seven agent roles each run on a model the config names. All of `roles`, `models` and `review` are optional, and
so is every key inside them: a role that is absent, or whose `model` is empty, takes its default.

| Role | Does | Default model |
|---|---|---|
| `specWriter` | Writes the spec of a Ready story | `opus` |
| `specReviewer` | Reviews a spec before it goes to Spec review | `opus` |
| `tester` | Writes the failing tests from the approved spec, before the implementer, and a bug's regression test from the report, before the fixer | `sonnet` |
| `implementer` | Writes the code of an Approved story | `opus` |
| `codeReviewer` | Reviews the change before the pull request opens | `opus` |
| `fixer` | Fixes a bug | `opus` |
| `worker` | Does mechanical, fully specified jobs (the `worker` agent) | `haiku` |

`specReviewer` reviews `specWriter`; `codeReviewer` reviews `implementer` and `fixer`. A reviewer should rank at
least as high as each role it reviews. The rank comes from `models.ranking`, the models from weakest to
strongest (aliases and full model ids); models of the same level share one entry, joined by `=`, for example
`"opus=claude-opus-5-5"`. The validator checks the pairing (see below). `review.maxFixRounds` (default 2) is how
many fix rounds a producer gets after a review.

The workflow skill defines how a skill picks a role's model: the configured model, else the default of the schema,
passed explicitly; a model that cannot be used stops the run and is reported, never replaced. `/next` and `/fix`
hand the coding to an `implementer` or `fixer` subagent on the configured model, and the pull request says which
model it ran on; the session keeps the board, the slot, the CHANGELOG and the pull request. `/spec` hands the
writing of the spec to a `specWriter` subagent the same way, and the spec pull request says which model it ran
on; the session keeps the board, the branch and the pull request. A `specReviewer` subagent on its configured model
reviews the spec before it goes to Spec review (`agents/spec-reviewer.md`, read-only), and the blocking findings go
back to the writer for at most `review.maxFixRounds` rounds. The spec pull request has the same Review section as a
code pull request, and a blocking finding that is still open keeps auto-merge off and is said on the issue.
`/nightmill:models` prints the table of every
role, its model, where the model comes from, its rank and whether its pairing holds; it only reads.

Before the implementer starts, `/next` has a `tester` subagent on its configured model (`agents/tester.md`) write at
least one test for every acceptance criterion from the approved spec into the slot, uncommitted, and run them to see
them fail for the missing behaviour; it writes only test files and fixtures, and the session stops when it leaves
anything else. The implementer then makes those tests pass and commits them with the code once the check is green. The
pull request's How verified names the tester's model and which test covers which criterion.

`/fix` does the same before the fixer: the `tester` writes a regression test from the bug report into the slot,
uncommitted, and runs it to see it fail for the reason the report gives. A bug it cannot reproduce stops the run before
any fixer starts (in `/fix all` the bug is skipped). The fixer then makes the test pass and commits it with the fix once
the check is green; the pull request's How verified names the tester's model and shows the test.

The implementer and the fixer may not edit or delete the tester's files; they add tests of their own only in other
files. After each of their results the session compares every tester file with what the tester left
(`git hash-object`) and undoes a change as a failed round. A test the implementer or the fixer believes is wrong goes
back to the tester as a dispute: the tester revises it or says why it stands. A dispute and an undone round each use
one of `review.maxFixRounds`; a dispute still open when the rounds are used up is listed in the pull request under
Disputed tests and keeps auto-merge off, and How verified names the tests the tester revised.

Before a pull request opens, `/next` and `/fix` have a `codeReviewer` subagent on its configured model review the
change, as a separate agent that never sees the implementer's own account, and send the blocking findings back to the
implementer or fixer for at most `review.maxFixRounds` rounds. The findings format and the rounds are in the workflow
skill; the reviewer is `agents/code-reviewer.md` and can only read. The pull request has a Review section with the
reviewer's and the author's model, the rounds used and the findings fixed and still open, and a blocking finding that
is still open keeps auto-merge off.

The code reviewer also judges the tests: for every acceptance criterion a test that would fail for a wrong
implementation, no test of the tester's removed, skipped, loosened or made conditional (compared with what the tester
first wrote, from the copies `git hash-object` kept), and no assertion that is always true, test that never fails or
test of only a mock that a criterion relies on. It sees the tester's files and the tester's own revisions, never the
implementer's or the tester's account. A blocking finding on a missing or weak test, or on the tester's tests, begins
with `test: ` and is a test finding: it goes back to the tester, the other findings to the implementer or fixer, in the
same fix round. A tester that says why its test stands is shown in How verified, and the finding stays open for the
maintainer.

Check a config with `scripts/validate-config.ps1` (or `scripts/validate-config.sh`). It reads the
schema, prints one line per finding that names the key (`error: worktrees.slots: expected integer, got string`),
and warns about keys it does not know, with a hint for a likely typo. It also rejects a config that puts a
reviewer on a model ranked below the role it reviews (`specReviewer` below `specWriter`, `codeReviewer` below
`implementer` or `fixer`, judged by `models.ranking`) and warns about a model that is not in the ranking.
`/nightmill:init` runs it for you.

## Why slots

A slot is a worktree that is never removed. A new task switches it to a new branch from the base
branch, so build output and installed dependencies stay warm and builds are incremental instead of
cold. A slot is busy from `-Take` to `-Release` (after the PR merged), `-Abandon` or an automatic release. Slot N
gets `base + N` for every configured port, so two servers run side by side. The number of slots follows
`worktrees.slots` or `WORKER_SLOTS`, or a value set during the session (below); one per 8 GB of RAM is a sound default.

A take (`-Take` / `--take`) first frees every busy slot whose pull request has merged, so the next `/next` or
`/fix` finds a free slot without a person running `-Release`; `-Reap` (`--reap`) does only that. A slot is freed
only when its worktree is clean and `gh` lists a merged pull request for its branch whose last commit is the tip of
the local branch, so a reused branch name or work after the merge keeps the slot busy and nothing is deleted. A slot
that cannot be judged (`gh` missing, logged out or failing, no fetch) stays busy, with a note on standard error, and
never makes a take fail. A slot whose pull request is open, closed without a merge or moved by "update branch" stays
busy until `-Release` or `-Abandon`. Each freed slot is reported in one line:
`Slot 1 is free (was feat/a, PR #12), released automatically.`

A take claims its slot before it does any work: it writes the slot's marker in the state `taking`, with the take's
process id, and creates it only if the slot has none, so two takes started together get different slots. A take whose
fetch, switch or warm-up fails puts the slot back as it was, frees it and says `<step> failed (exit N)`; when the
failed warm-up left changed or new files in the slot, the slot keeps the claim instead, so that nothing is lost, and
`-Abandon N` (`--abandon N`) frees it once the files are dealt with. A take that died or was stopped without finishing
leaves a claim that `slot -Status` shows with `has ended` (or `no process recorded`, for a take that could not put its
slot back) and `/nightmill:status` with the step `take-died`. Nothing frees it automatically, and `-Abandon N`
(`--abandon N`) frees it once its files are dealt with, keeping the branch. If `-Abandon` says the process is still
running but no take is (its number was reused, or it is the PowerShell console a stopped take ran in), end or close
that process, or remove the marker `<worktrees.root>/.slots/slot-N.json` by hand.

### What a slot's agent is doing

`/next` and `/fix`, and the implementer and fixer they launch, record their skill, role and current step in the
slot's marker at each step (`-Report <step>` / `--report <step>`). `/nightmill:status` lists every slot with its agent
state: **running** while the last report is at most `worktrees.stalledAfterMinutes` minutes old (default 30),
**stalled** when it is older (the session may have ended, crashed or been abandoned; look at it, and free the slot with
`-Abandon` if it was dropped), **unknown** when the slot has no report (taken by hand or by an older version). A slot
still being taken shows unknown with the step taking; one whose take died shows the step take-died. A slot
whose run is over (step `done`) and that waits for its merge also shows stalled once the threshold has passed;
`-Release`, `-Reap` or the next take frees it. Nothing is stopped or freed because a slot is stalled, and a step longer
than the threshold (a long code review or check) shows stalled while it runs; `/spec` takes no slot and is not shown.

### Where a story's time went

The slot scripts keep a record of every take: `<worktrees.root>/.slots/ledger.tsv`, beside the slot markers. It is
untracked and append-only, shared by every worktree, and kept after a release, an abandon, an automatic release and
the deletion of the branch (delete it by hand to start over). Only `slot.ps1` and `slot.sh` write it, in the commands
that already run, so no skill or agent does anything extra: the take appends a `take` line (the claim and the end of
the take), every report a `step` line (the step name and when it was reported), every freeing a `free` line
(`released`, `reaped` or `abandoned`, with the merged pull request's number, open and merge time and closing issues).
One line per event, eleven tab-separated fields, times in UTC; readers skip a line kind they do not know.

`scripts/stages.sh --issue N` (`stages.ps1 -Issue N`) prints the takes that ended in a merged pull request closing
issue N; `--last N` (`-Last N`, default 5) the last N takes. Read-only, no network. Per take, a header
(`#<issue>  <branch>  slot <n>  <state>`, the state `merged <time>`, `released`/`reaped`/`abandoned <time>`, `running`
or `not freed`) and one row per stage:

- `take`: from the claim to the end of the take (fetch, worktree, warm-up);
- `not-reported`: from the end of the take to the first report;
- each reported step name, exactly as the slots reported it (`write-tests`, `implement`, `check`, `code-review`,
  `pull-request`, ...): from its report to the next one; a step reported after the pull request opened is not counted;
- `ci-and-merge`: from the pull request's open to its merge, the wait for CI and the merge (and for the maintainer when
  the auto-merge waits), never added to an agent's step.

`runs` is how many reports (or stretches) gave time to the row, so two runs of `check` or three fix rounds show there;
`time` is the summed duration; `share` the row's part of the total. The total runs from the claim to the merge. A time
that cannot be known is **unknown**, never `0s`, and its share `-`: a take by an older version (no take line) has an
unknown `not-reported` row and an unknown total. An issue no slot took, or that an older version freed, prints
`#N: no record`. `/spec` takes no slot and is not recorded. `tests/check.sh` prints the time of each of its steps and
a `Times:` block with the total.

### Watching the run in a browser

To keep the slots in view during a run, start the dashboard in a terminal, from inside the project:

```
scripts/dashboard.ps1
bash scripts/dashboard.sh
```

It prints a `file://` address; open it once in a browser (the script opens none itself). The page is a file in the
temporary folder (`nightmill-dashboard-<owner>-<repo>.html`), never in the project. It shows the Slots section of
`/nightmill:status` (every slot, its agent state, branch, skill and step, the age of the last report, the pull request
and CI, the `stale:` flag) and the items at Spec review and Approved with their pull requests and CI. The script
rewrites it every `worktrees.dashboardRefreshSeconds` seconds (default 60; each rewrite calls `gh` as `/status` does)
and the page reloads itself as often. No server runs and nothing listens.

The words are those of the section above: **running** while the last report is at most
`worktrees.stalledAfterMinutes` minutes old, **stalled** after that, **unknown** without a report. The page shows each
state as a word as well as a colour. A part it cannot read (no `gh`, logged out, no network) is shown as `unknown` with
the reason, never as free or as nothing waiting; the slot states, which need no network, stay.

To stop it, press Ctrl-C in that terminal or close the terminal; nothing keeps running. The page stays as last written
and, after three intervals without a rewrite, says it is out of date. The page has no buttons or links and changes
nothing. `--once` (`-Once`) renders it once. The data comes from `status.sh --porcelain` (`status.ps1 -Porcelain`),
which prints the tables of `/status` tab-separated for programs (the record kinds `item`, `note`, `slot`, `capacity`).

### Watching the run beside the chat

The plugin also carries a pane for the Claude chat itself (a Claude Code mod, `hooks/panel.tsx`). It shows every slot,
free or busy, the agent state, the branch, the skill and step and the age of the last report: the Slots section of
`/nightmill:status` without the pull request, CI and flag columns. While the pane is open it reads them again every
`worktrees.panelRefreshSeconds` seconds (default 15) and shows the time of the last read. **running**, **stalled** and
**unknown** mean what they mean in "What a slot's agent is doing".

`/nightmill-slots` opens it, also while a run is going in that session. `/nightmill-slots off` or the pane's close
mark closes it and stops the reading. Nothing opens it by itself, and nothing runs until it is opened. To keep the
plugin's mod from loading at all, the only switches are Claude Code's own: `"disableAllHooks": true` in the user
settings (which also silences the `SessionStart` hint) or `--safe-mode`. The skills, `/nightmill:status` and the page
in the browser work without it.

The pane changes nothing: it has no buttons or links, it runs only `scripts/panel.*`, and that runs only
`slot --status --porcelain` (no `gh`, no network). A slot that cannot be read is shown as `unknown` with the reason,
never as free; when the slots cannot be read at all, the pane says so and shows no rows rather than the last ones.

Where it works: Claude Code 2.1.287 or later in a terminal (also an editor's integrated terminal and the JetBrains
plugin), the Code tab of the Desktop app from 2.1.286, and the VS Code extension's chat panel from extension 2.1.299
(2.1.304 where the session does not fetch feature flags, such as on Bedrock). It is not drawn in `claude -p`, the
Agent SDK, cloud sessions, the Desktop app's WSL sessions, or on claude.ai and the mobile app (Remote Control draws it
in the terminal on the machine); there the command says it cannot show the pane, or is not offered. Claude Code before
2.1.287 does not show the pane. An organization can turn installed mods off, and mods are early access in Claude Code
and may change between its releases.

On Windows the pane runs `scripts/panel.ps1` with Windows PowerShell, elsewhere `scripts/panel.sh` with bash.

### Changing the numbers during a session

The slot count and the agent limit (how many agents run at once) can be raised or lowered while a session runs,
without a restart:

```sh
scripts/slot.ps1 -Capacity                              # show the numbers and where they come from
scripts/slot.ps1 -Capacity -SlotCount 3 -AgentLimit 3   # set one or both
scripts/slot.ps1 -Capacity -Clear                       # back to the configuration
bash scripts/slot.sh --capacity [--slot-count N] [--agent-limit M] [--clear] [--porcelain]
```

A value is a whole number from 1 to 99; an invalid one changes nothing and says why. A set value wins over
`WORKER_SLOTS`, which wins over the configuration (`worktrees.slots`, `parallel.maxAgents`; 2 when absent). The values
are kept in `<worktrees.root>/.slots/capacity.json`, beside the slot markers and outside the repository, until
`-Clear` or until set again; the tracked `.claude/nightmill.json` is never edited. A raised slot count is used by the
next take (the new worktrees are created on first use). Lowering it never touches a busy slot: a busy slot above the
new count is shown as retiring, is no longer handed out, and drops out of the list once it is released (its worktree
stays on disk for when the count goes up again). A lowered agent limit stops no running agent: `/next`, `/spec` and
`/fix` read the limit each time they decide whether to start another agent and wait until fewer run than it allows.
`slot -Status` and `/nightmill:status` show the effective numbers in a `capacity:` line and say `live; config <n>`
while a set value is in force.

### Is the machine used well?

```sh
scripts/load.ps1 [-Porcelain]
bash scripts/load.sh [--porcelain]
```

The command measures the CPU load and the free memory, shows the effective agent limit, the slots in use and the
agents running, and suggests an agent limit with one `why:` line. It takes one sample a second for
`parallel.loadWindowSeconds` seconds (default 10), so it takes that long. The CPU load is the busy share of all
processors, the mean of the samples; the free memory is the memory the system can hand out without swapping, the
lowest sample. The sources: `/proc/stat` and `/proc/meminfo` (`MemAvailable`) on Linux, the same files in Git Bash
(`MemFree`, which carries Windows' available memory), `Win32_PerfRawData_PerfOS_Processor` and
`Win32_OperatingSystem` in PowerShell on Windows, `top`, `vm_stat` and `sysctl hw.memsize` on macOS. MB and GB are
decimal.

The suggestion is the smaller of two bounds, at least 1 and at most `parallel.maxSuggestedAgents` (default 4). The
memory bound is one agent per `parallel.memoryPerAgentGB` (default 8) of the total memory and, beside the agents
already in the slots, of the free memory; when under 10% of the memory is free it is one fewer than the agents in the
slots. The CPU bound is the agents in the slots scaled to 80% busy (with no slot in use, no bound unless the CPU is
already at 80%). The `why:` line names which one decided (the ceiling, memory or CPU). "Agents running" is the number
of busy slots: the only count a script can read.

It does not see the API's rate limits, the token budget, GPU, disk or network, agents outside the slots (`/spec`'s
writer, the reviewers, another session), or memory a build will take but has not taken yet; CPU used by other
programs counts as if the agents used it. A measurement it cannot take is shown as `unavailable` with the reason, and
then there is no suggestion (exit 1). It changes nothing: to apply a suggestion, run `slot -Capacity -AgentLimit N`
(`slot.sh --capacity --agent-limit N`). The porcelain form prints one tab-separated line per value, by name: `cpu`,
`memory-free`, `memory-total`, `window`, `agent-limit`, `slot-count`, `slots-busy`, `agents-running`,
`memory-per-agent`, `ceiling`, `suggested`.

### Room for one more agent

```sh
scripts/room.ps1 [-Since <seconds>]
bash scripts/room.sh [--since <seconds>]
```

Before `/next`, `/spec` and `/fix` start an agent (every subagent, every take of a slot and the manual check), right
after they count the agents, they check that the machine has room for it: the free memory must be at least
`parallel.roomMinFreeMB` (2000 MB by default) and the CPU load at most `parallel.roomMaxCpuPercent` (90% by default),
over 3 one-second samples taken with the readers of the load command. While there is no room the skill says what it
waits for in one line (`room: waiting for memory: free memory 1500 MB, limit at least 2000 MB (waited 0 of 30 min; next
check in 60 s)`), pauses `parallel.roomPauseSeconds` (60 s by default) and checks again, and starts the agent as soon
as there is room. After the longest wait, `parallel.roomMaxWaitMinutes` (30 min by default), it stops that task with a
`Stopped:` line and starts nothing; the story stays where it is, and `/fix all` ends its run. A measure that cannot be
taken is not checked, and the skill says so once; with neither, the skill starts as before. The check only holds a
start back: it never changes the agent limit, stops an agent or frees a slot. A slot whose skill waits longer than
`worktrees.stalledAfterMinutes` shows stalled in `/status` while it waits. To switch the check off:
`"parallel": { "roomCheck": false }`.

### Adjusting the limit to the load

```sh
scripts/control.ps1
bash scripts/control.sh
```

An opt-in controller adjusts the agent limit to the machine's measured load. `parallel.controlMode` sets its mode:
`off` (the default) measures and changes nothing; `report` says what it would change and changes nothing; `apply`
changes the live agent limit with `slot --capacity`, like a hand-set value, shown `live` by `slot --status` and
`/status`.

One pass is one call of the script. In a session, `/loop 5m /nightmill:control` runs a pass every 5 minutes (use the
value of `parallel.controlIntervalMinutes`, default 5), or `/loop /nightmill:control` paces itself by the
`control: next pass in <i> min` line every pass prints. An orchestrator runs `scripts/control.ps1` or
`bash scripts/control.sh` at that interval. A pass measures over `parallel.loadWindowSeconds` like the load command,
takes its suggestion as the target and keeps it between `parallel.controlMinAgents` (default 1) and
`parallel.controlMaxAgents` (default 4).

The rules: the limit goes up one step only after a full window with room and only after
`parallel.controlCooldownMinutes` (default 15) since the last change; it goes down at once to the target when memory is
short; it goes down one step per cooldown when the CPU or the ceiling is the limit; a limit outside the bounds is
brought inside them at once. The slot count is raised to the new limit by any pass that sets the agent limit above the
slot count, also when that pass lowers the limit but the new limit is still above the slot count; a pass that keeps the
limit never touches it, and it is never lowered. The last change is the time in `capacity.json`, rewritten by every
`slot --capacity` set (also one that changes nothing or sets only the slot count), so any such set, by hand or not,
restarts the cooldown, and `-Clear` hands the start back to the configuration. Leave `WORKER_SLOTS` unset where the
controller runs, or accept that a raise up to that value writes no live slot count.

Every pass reports in one line: the old value, the new value (or `kept`), the rule and the measure that caused it,
for example `control: agent limit 2 -> 3, slots 2 -> 3 (room; CPU 10%, free memory 60000 of 64000 MB, busy slots 1,
suggested 4: ...)`. A pass that cannot measure changes nothing, says `kept (unavailable; ...)` and exits 1. The
controller never stops an agent, frees a slot or edits the config: busy slots stay busy, and a lowered limit only
holds back the next start. It leaves nothing running: the loop ends with the session, and the last live values stay
until `-Clear`, as for a hand-set value.

The controller does not see the API's rate limits, the token budget, or agents outside the slots; nor what the load
command does not see (GPU, disk, network, memory a build has not taken yet; CPU used by other programs counts as the
agents').

## Developing nightmill

nightmill develops itself with its own workflow: a board, the eight statuses, specs, one check
command, auto-merge. `.claude/CLAUDE.md` holds the rules for working on it; `docs/decisions/0001` and
`0003` say why.

```
bash tests/check.sh         # everything this machine can run, lists what it skipped
bash tests/lint.sh          # generic words, JSON, skill frontmatter, shell syntax
bash tests/smoke-slot.sh    # slot.sh against a throwaway repository
bash tests/smoke-render.sh  # render-templates.sh
bash tests/smoke-hook.sh    # the SessionStart hook
bash tests/smoke-release.sh # the release script (git only)
bash tests/smoke-validate.sh # the config validator
bash tests/smoke-status.sh  # status.sh against fixtures and a fake gh
bash tests/smoke-template-board.sh # template-board.sh against fixtures and a fake gh
bash tests/smoke-models.sh  # models.sh: the table of the role models
bash tests/smoke-load.sh    # load.sh against a fixture of readings
bash tests/smoke-room.sh   # room.sh against a fixture of readings
bash tests/smoke-control.sh # control.sh against fixtures of readings and a fixed clock
bash tests/smoke-dashboard.sh # dashboard.sh against fixtures and a fake gh
bash tests/smoke-panel.sh   # panel.sh against fixtures
bash tests/smoke-json.sh    # the JSON reader the bash scripts use (checked against jq when it is installed)
powershell -ExecutionPolicy Bypass -File tests/smoke-slot.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-render.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-hook.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-release.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-validate.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-status.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-template-board.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-models.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-load.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-room.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-control.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-dashboard.ps1
powershell -ExecutionPolicy Bypass -File tests/smoke-panel.ps1
claude plugin validate . --strict
claude plugin test .        # the pane's module (hooks/panel.test.tsx)
```

CI runs all of them. `tests/check.sh` runs `claude plugin test .` when `claude` is on the PATH and has the
`plugin test` subcommand, and lists it as skipped otherwise; CI runs it in the `validate` job, which does not block a
merge. The lint fails on any word from the private word list (`tests/forbidden-words.local.txt`): nightmill was
extracted from one project and must not know that project's name, its maintainer's name or its
domain.

To run the plugin from a checkout instead of the installed copy: `claude --plugin-dir /path/to/nightmill`,
started in a project or in another folder, not in the checkout itself (a folder loaded that way is a
protected path, so edits to it are not auto-approved). To try a release before it is published, add its
branch as the marketplace: `claude plugin marketplace add CodaColaLight/nightmill#release/vX.Y.Z`.

### Releasing

`main` only takes pull requests, so a release has two steps. `scripts/release.sh --version X.Y.Z` (or
`scripts/release.ps1 -Version X.Y.Z`) creates the branch `release/vX.Y.Z` with one commit that bumps
`.claude-plugin/plugin.json`, moves the `Unreleased` entries of `CHANGELOG.md` under `## X.Y.Z (date)` and
updates the `Version` line below, then opens the pull request. After you merge it, the same command with
`--publish` (`-Publish`) tags the release commit and creates the GitHub Release from the changelog section.
`--dry-run` (`-DryRun`) shows the plan and changes nothing. The script refuses when the version is not
greater than the current one, when the tree is dirty, when you are not on an up-to-date `main`, when
`Unreleased` is empty, or when the tag or branch exists. The lint fails if `plugin.json`, the newest
changelog heading and the README's `Version` line disagree. Projects pin by the version in `plugin.json`.

## Contributing

Issues and pull requests are welcome. `CONTRIBUTING.md` explains how work is decided here and what a pull
request has to satisfy. Report a security problem privately, as described in `SECURITY.md`.

## Status and license

Version 0.4.0. Apache License 2.0, see `LICENSE`.
