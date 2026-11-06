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
| `/nightmill:check` | Runs the project's check command and fixes the cause of a failure. |
| `/nightmill:init` | The install chat: detects what `gh` and the repository can tell, asks the rest one question at a time, shows one plan and, after one confirmation, creates the board with its columns view, the labels, the config, the issue forms, the CLAUDE.md snippet and the permission rules. |
| `workflow` skill | The process rules. Claude loads it when it touches an issue, a spec, a slot or a PR. |
| `worker` agent | A cheap subagent for mechanical, fully specified jobs. |
| `scripts/slot.ps1`, `scripts/slot.sh` | Permanent worktree slots: `-Take <branch>`, `-Release N`, `-Abandon N`, `-Reap`, `-Status`, `-Capacity`, `-Report <step>`. |
| `scripts/load.ps1`, `scripts/load.sh` | Read-only: measures CPU load and free memory over a short window, shows the agent limit and the slots in use, and suggests an agent limit with the reason. Changes nothing. |
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
| `parallel` | Agent cap, hot files, task pairs to avoid, and for `scripts/load.*` the ceiling of its suggestion (`maxSuggestedAgents`, default 4), the memory one agent needs (`memoryPerAgentGB`, default 8) and the measurement window (`loadWindowSeconds`, default 10) |
| `worktrees` | Slot root, count, port bases, warm-up commands, run hints, and `stalledAfterMinutes` (default 30): the minutes without a report after which a busy slot's agent counts as stalled |

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

### What a slot's agent is doing

`/next` and `/fix`, and the implementer and fixer they launch, record their skill, role and current step in the
slot's marker at each step (`-Report <step>` / `--report <step>`). `/nightmill:status` lists every slot with its agent
state: **running** while the last report is at most `worktrees.stalledAfterMinutes` minutes old (default 30),
**stalled** when it is older (the session may have ended, crashed or been abandoned; look at it, and free the slot with
`-Abandon` if it was dropped), **unknown** when the slot has no report (taken by hand or by an older version). A slot
whose run is over (step `done`) and that waits for its merge also shows stalled once the threshold has passed;
`-Release`, `-Reap` or the next take frees it. Nothing is stopped or freed because a slot is stalled, and a step longer
than the threshold (a long code review or check) shows stalled while it runs; `/spec` takes no slot and is not shown.

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
claude plugin validate . --strict
```

CI runs all of them. The lint fails on any word from the private word list (`tests/forbidden-words.local.txt`): nightmill was
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

Version 0.3.0. Apache License 2.0, see `LICENSE`.
