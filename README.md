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
| `/nightmill:next [N]` | Takes a story: Approved ones first (implement), then Ready ones (write the spec as its own PR, set Spec review, stop). |
| `/nightmill:fix [N\|all]` | Fixes a bug: failing test first, smallest fix, one PR. `all` works through every Ready bug. |
| `/nightmill:story <idea>` | Turns a one-line idea into a story issue under the right epic, in Backlog. |
| `/nightmill:check` | Runs the project's check command and fixes the cause of a failure. |
| `/nightmill:init` | Sets a project up: config file, issue forms, board options, CLAUDE.md snippet. |
| `workflow` skill | The process rules. Claude loads it when it touches an issue, a spec, a slot or a PR. |
| `worker` agent | A cheap subagent for mechanical, fully specified jobs. |
| `scripts/slot.ps1`, `scripts/slot.sh` | Permanent worktree slots: `-Take <branch>`, `-Release N`, `-Abandon N`, `-Status`. |
| `scripts/new-worktree.*` | An ad-hoc extra checkout outside the slot system. |
| `scripts/render-templates.*` | Writes the project's issue forms from `areas` and `invariants`. |
| `schema/nightmill.schema.json` | Every configuration key, described. |

Bare `/next`, `/fix`, `/story`, `/check` also work unless another plugin or the project defines them.

## Install

```
/plugin marketplace add CodaColaLight/nightmill
/plugin install nightmill@nightmill
/nightmill:init
```

The repository is private for now; `gh auth login` (or any git credential for GitHub) is enough for
the clone. The scripts need `git` and `gh`; the bash versions also need `jq`. Hooks, permissions and
environment variables stay in the project's own `.claude/settings.json`; a plugin cannot set them.

`/nightmill:init` writes `.claude/nightmill.json` from the real repository (owner, repo, board number,
check command), renders `.github/ISSUE_TEMPLATE/`, compares the board's Status options with the flow
above and prints the GraphQL to add missing ones, and prints a snippet for the project's CLAUDE.md.

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
| `git` | Base branch, branch prefixes, merge flags |
| `parallel` | Agent cap, hot files, task pairs to avoid |
| `worktrees` | Slot root, count, port bases, warm-up commands, run hints |

`templates/nightmill.example.json` is a complete example.

## Why slots

A slot is a worktree that is never removed. A new task switches it to a new branch from the base
branch, so build output and installed dependencies stay warm and builds are incremental instead of
cold. A slot is busy from `-Take` to `-Release` (after the PR merged) or `-Abandon`. Slot N gets
`base + N` for every configured port, so two servers run side by side. The number of slots follows
`worktrees.slots` or `WORKER_SLOTS`; one per 8 GB of RAM is a sound default.

## Developing nightmill

```
bash tests/lint.sh          # generic words, JSON, skill frontmatter, shell syntax
bash tests/smoke-slot.sh    # slot.sh against a throwaway repository
powershell -ExecutionPolicy Bypass -File tests/smoke-slot.ps1
claude plugin validate . --strict
```

CI runs the same four. The lint fails on any word from `tests/forbidden-words.txt`: nightmill was
extracted from one project and must not know that project's name, its maintainer's name or its
domain.

To try a change in a project without publishing it: `claude --plugin-dir /path/to/nightmill`.

## Status and license

0.1.0, first extraction. Apache License 2.0, see `LICENSE`.
