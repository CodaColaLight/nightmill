# Iteration 49: the README has a "Running unattended" section: the headless commands for /next and /fix, the settings a run needs, how runs share the slots, and what a stopped run leaves

Status: draft, awaiting approval (#160)

Story #160, epic #107 (Hardening from the code review), finding MD-T13 of the review of 0.2.0. The README promises a
lights-out workflow but never says how to start one without a person. After this iteration it has a section
`## Running unattended` with five sub-sections. They give the exact `claude -p` command lines for `/nightmill:next` and
`/nightmill:fix` (one issue, and `all`), and the settings a headless run needs: the four lines `/init` writes, the
workspace trusted once, the permission mode, and what not to pass. They say how several runs share the slots and the
agent limit, and how to watch them with `/nightmill:status`. They say what a run leaves when it is stopped, and how it
is continued. Two existing sentences that say this is not described yet point to the new section instead. The pins live
in a new `tests/test-unattended-docs.sh`, which `tests/lint.sh` calls, so `tests/check.sh`'s step list and
`.github/workflows/ci.yml` do not change. Changes `README.md`, `tests/test-unattended-docs.sh` (new), `tests/lint.sh`
and `CHANGELOG.md`. No skill, agent, hook, script, schema, template or CI file changes.

## Story trigger and manual check

**Not a story trigger.** Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. The section describes the statuses a stopped run leaves
  (In progress, Review) and that only the maintainer moves an item back to Ready or Approved, as the workflow skill has
  it. No decision record. None of `docs/decisions/` 0001 to 0003 is contradicted: they say how nightmill develops and
  releases itself, not how a project runs it.
- *A new, renamed or removed config key*: no. The section names existing keys (`worktrees.slots`, `worktrees.root`,
  `worktrees.stalledAfterMinutes`, `parallel.maxAgents`, `review.watchChecksMinutes`) and adds none.
  `permissions.allow`, `permissions.deny` and `hasTrustDialogAccepted` are Claude Code's, not keys of
  `.claude/nightmill.json`. Invariant "Compatible" holds.
- *A change to the slot marker format*: no. No script changes.

**The manual check does not apply.** `verification.manualCheckPaths` is `skills`, `agents`, `hooks`. `README.md`,
`tests/lint.sh`, `tests/test-unattended-docs.sh` and `CHANGELOG.md` are outside them, so the pull request may
auto-merge. The truth of the commands is checked by the implementer's headless probe (Tests, "How verified").

**Both shells.** No script in `scripts/` changes, so no smoke step is added in either shell. The new test is a
documentation pin in bash only, as `tests/test-security-model.sh` (iteration 39) is. It is called from `tests/lint.sh`,
so the step list of `tests/check.sh` (`# steps: begin` to `# steps: end`) and the `--only` lists of `ci.yml` stay as
they are. The lint's `== the check runs every smoke script` section requires only `tests/smoke-*` files in that list.

**Order with open specs.**

- *Iteration 48* (#111, draft, implementation in progress in a slot) changes where the skills and the slot script read
  `.claude/nightmill.json`: from the base branch instead of the working tree. This section does not say where the
  config is read. Its rule "start in the main checkout, on the base branch, with a clean tree" (decision 2) holds
  either way: today because the working tree's config governs the run and `/fix all` stops on a dirty tree, after 48
  because of the dirty-tree stop alone. Iteration 48 also withholds auto-merge for a change under `.claude/` or
  `.github/`. This section says only that a write under `.claude/` is refused in a headless run (decision 6), which
  stays true. Whichever of the two merges second reads the sub-section `### Before the first run` once more and
  checks that no sentence says the working tree's config governs the run. Neither iteration's pins read the other's
  text.
- *#213* (iteration 45, draft): the script rules of **Run permissions** follow the plugin's version folder, so today
  an upgrade needs `/init` again before the next headless run (a run whose script rules do not match is refused, not
  asked). The section says so with "until #213". The pull request that delivers #213 changes that sentence; the pin
  reads only `/init` and `#213` (Tests, pin 6), so it is rewritten there, not here.
- *#164* (the trigger) and *#165* (limits, a kill switch) are open. The section names no schedule and no kill switch.
  It links both as not shipped yet.

## Facts this rests on

Read on `main` at 37c029e (0.6.0 with iterations 39, 40, 44, 46 and 47 merged and the iteration 48 spec on `main`),
on 2026-11-10, read only. The issues were read with `gh issue view <n> --json number,state,stateReason,title`. Claude
Code 2.1.321 is installed here; `claude --help` was read and nothing else was run with `claude`. Claude Code's
documentation was read on 2026-11-10: `https://code.claude.com/docs/en/headless`,
`https://code.claude.com/docs/en/permissions` and `https://code.claude.com/docs/en/permission-modes`.

**The finding still holds.** `README.md` has no section on running without a person. `### The run permissions` ends
with `- **Headless runs:** how to start a run without a terminal is described in "Running unattended" (#160), not
here.`, and the Security model ends with "How to run without a person is not described yet ([#160](...))". The only
headless facts in the README are in `### The edit permission` (**Limits**: "a headless run (`claude -p`) needs one
interactive session in the project first") and in "Watching the run beside the chat" (the pane is not drawn in
`claude -p`). There is no command line, no permission mode, nothing on parallel sessions sharing the slots, and nothing
on a stopped run.

**The dependency is met.** The agent notes say the story depends on the permission bug being fixed. #109 (the run
permissions, iteration 43) and #110 (the deny rules and the guard, iteration 47) are closed as completed. #111,
#164, #165, #169, #176 and #213 are open.

**Claude Code's headless mode** (`claude --help` of 2.1.321 and the documentation, in substance):

- `claude -p "<prompt>"` runs one non-interactive session and prints the response. "User-invoked skills and custom
  commands work. Include `/skill-name` in the prompt string and Claude Code expands it before running." `/next` and
  `/fix` are such skills (`disable-model-invocation: true`); `/status` can be invoked either way.
- "Without `--bare`, `claude -p` discovers and loads them as an interactive session would": hooks, skills, subagents,
  installed plugins, CLAUDE.md. `--bare` skips installed plugins, hooks (also a plugin's `hooks/hooks.json` loaded with a
  flag) and CLAUDE.md, and does not use the subscription login. "`--bare` is the recommended mode for scripted and SDK
  calls, and will become the default for `-p` in a future release."
- `--output-format`: `text` (default, the final message), `json` (one object; the text is in `result`, with
  `session_id` and `total_cost_usd`), `stream-json` (one event per line). The exit code is 0 on success and non-zero
  when the run fails; a failure inside the run is printed as the result.
- `--permission-mode` takes, in `claude --help` of 2.1.321: `acceptEdits`, `auto`, `bypassPermissions`, `manual`,
  `dontAsk`, `plan`. The documentation: the mode that reviews every action "is named **Manual** in the CLI ... Its
  config value is `default` ... The CLI accepts `manual` as an alias". "In Claude Code v2.1.302 or later, `claude -p`
  and Agent SDK runs with no permission mode set start in Manual mode"; before that version they could start in auto
  mode. "In a Manual mode `claude -p` run, a call that needs approval is denied unless something approves it", such as
  an allow rule or a hook. "In a `-p` run with no host, these requests are denied either way". `--permission-prompts
  none` (2.1.259 or later) also tells Claude not to retry them.
- `--allowedTools` adds allow rules for the session in the permission rule syntax. Deny rules "block in every mode,
  including `bypassPermissions`"; "Allow rules have no effect in `bypassPermissions`". Writes to protected paths
  (`.git`, `.claude` with exceptions, and others) are prompted in `default` and `acceptEdits`, so a `-p` run in Manual
  mode is refused them.
- **Trust.** "`permissions.allow` rules and `permissions.additionalDirectories` entries in a project's
  `.claude/settings.json` ... Claude Code applies them only after you accept the workspace trust dialog ... `deny` and
  `ask` rules aren't affected." "A `claude -p` run or an SDK session never shows it". In a never-trusted folder a `-p`
  run does not use those allow rules and "prints a `this workspace has not been trusted` warning to stderr". The trust
  is keyed on the git repository root, and in a worktree on the main checkout's root. It can be set by hand:
  "`projects["<path>"].hasTrustDialogAccepted` to `true` in `~/.claude.json`". `.claude/settings.local.json` that git
  does not track is applied without the trust step, and a `-p` session counts as trusted for the git check that tells
  the two apart. A plugin's hooks are not repository content and load in `-p`. Iteration 12 measured the same on
  2026-11-05: a project's `permissions.allow` was ignored by `claude -p` until the workspace was trusted.
- **Stopping.** "If you stop a `claude -p` run with SIGTERM ... Claude Code exits with code 143", "terminates the
  process tree of any Bash command that is still running", runs `SessionEnd` hooks and starts no new tool call or
  model request. "To end the turn instead, send SIGINT". A `-p` run stays open until its background subagents have
  completed. `--continue` and `--resume` reopen a conversation; the interrupted turn is left as it is.
- `--bg` is rejected with `-p`.

**What `/init` writes** (README, `### The edit permission`, `### The run permissions`,
`### The deny rules and the guard`, Security model): **Permissions** (the four `gh` rules, three read-only git rules
and the check's rule) and **Deny rules** (18 rules) in the shared `.claude/settings.json`; **Edit permission**
(`Edit(**)`) and **Run permissions** (`24 + 21 × worktrees.slots` rules and the slot root as an additional directory)
in the personal `.claude/settings.local.json`. The script rules of **Run permissions** name the plugin's version folder.
Iteration 43's manual check was written for "the default mode, without `--dangerously-skip-permissions` and with no
`defaultMode` in either settings file". Iteration 47's guard is wired as a plugin hook. Its refusals in
`bypassPermissions`, in auto mode and for a subagent are not shown (README, `### What is enforced`).

**The skills, as they run headless:**

- *Picking.* `/next` and `/fix` without a number take the highest priority and, on a tie, ask the maintainer which
  (workflow skill, **Picking an issue** rule 2; `/fix` step 1). `/fix all` "Fixes every Ready bug without asking the
  maintainer anything" and has "no ties to ask about". With a number, `/next` also takes In progress and Review to
  finish a story's own work (iteration 44). `/fix` with a number refuses a bug that is not at Ready (`/fix` step 1).
- *The checkout.* `/next` runs `git fetch origin` in the main checkout and works in a slot; `/fix all` stops "if the
  working tree is dirty at the start". Without `worktrees`, `/next` and `/fix` switch the session's own checkout to a
  new branch (`git switch -c`).
- *Order of the first steps.* `/next` sets In progress (step 2.1) before it takes a slot (step 2.2); `/fix` sets In
  progress in step 3 before its take. A take that finds no free slot prints `all <k> slots are busy; see slot.sh
  --status` (`scripts/slot.sh`, `all $count slots are busy`) and exits 1, and the run stops with the take's line.
- *Slots.* All sessions of a project on one machine use the same slots: `<worktrees.root>/slot-<n>` with the markers
  in `<worktrees.root>/.slots/`. Their number is the live value (`slot --capacity`), else `WORKER_SLOTS`, else
  `worktrees.slots` (schema default 2). A `/next` or a single `/fix` holds its slot from the take until it is freed after
  the merge (`-Release`, `-Reap`, or the next take's automatic release). `/fix all` takes one slot per bug and frees
  each once its pull request is open (`-Abandon`).
- *The agent limit.* "At most the agent limit agents (subagents, slot builds, your own builds) at the same time ...
  Before launching one, count the running ones" (workflow skill, **Parallel work**); the limit is the live value, else
  `parallel.maxAgents` (schema default 2). A session counts what it started; `scripts/load.*` "does not see ... agents
  outside the slots (`/spec`'s writer, the reviewers, another session)". The room check measures the whole machine.
- *A claim.* "An agent claims an issue before it changes anything" is not enforced yet (#176), so two sessions that pick
  without a number can pick the same item until the first has set In progress.
- *The watch.* After auto-merge, `/next` and a single `/fix` watch the checks for at most `review.watchChecksMinutes`
  (default 30) per push (iteration 46); `/fix all` watches none. A run therefore ends after the watch, not when the pull
  request opens.
- *Watching.* `/nightmill:status` (`scripts/status.*`, covered by a **Run permissions** script rule) prints the board
  and every slot with **running**, **stalled** or **unknown**, and changes nothing. The dashboard and the pane read the
  same slot markers; the pane is drawn only in an interactive session.
- *A stopped run* (iterations 34, 36, 44 and the README's "Why slots"). A take interrupted after its claim (INT, or
  TERM in bash) puts the slot back and frees it; a take killed without a chance to clean up leaves a claim that
  `slot -Status` shows as ended and `/status` as `take-died`, freed only by `-Abandon N`. After the take, a stopped run's
  slot keeps its marker, branch and files; its last report stays, so `/status` shows **running** until
  `worktrees.stalledAfterMinutes` (default 30) have passed since that report, then **stalled**. `/next N` refuses a slot
  that is **running** ("another run is working on it") and resumes one that is stalled or unknown; the `stopped` step
  is reported only on a skill's own `Stopped:` line. A pull request whose auto-merge is on merges by itself when its
  checks pass, and its `Closes` sets Done.

**Not verified from here** (nothing that starts a session was run): that `claude -p "/nightmill:next"` expands the
plugin skill with its namespaced name and with an argument; that `--permission-mode manual` is accepted by the version
a project runs; that a `-p` run started in a trusted workspace runs `/next` to a pull request without a denial; what a
`-p` run prints when the skill would ask on a tie; whether Ctrl+C on a `-p` run ends it as SIGINT; whether subagents
end with a run stopped by SIGTERM; what a SIGKILL of `claude` leaves of a take's child process. Tests ("How verified")
and Left say how each is handled.

## Decisions

**1. Where and what headings.** A new `## Running unattended` directly after the `### Adjusting the limit to the load`
sub-section of `## Why slots` and before `## Developing nightmill`. It comes after everything it points to: the
permission sub-sections, the Security model, the slots, "What a slot's agent is doing", the dashboard and the pane.
It has exactly five sub-headings, in this order: `### Before the first run`, `### The commands`,
`### Several runs at once`, `### Watching a run`, `### When a run is stopped`. The section starts with one paragraph:
a run started with `claude -p` takes one item (or, with `/fix all`, every Ready bug) to its pull request with nobody at
the terminal. Nothing in nightmill starts runs on a schedule yet ([#164](...)), and no limit or kill switch bounds a run
yet ([#165](...)).

**2. The commands.** Four lines, in one code block, exactly:

```
claude -p "/nightmill:next" --permission-mode manual
claude -p "/nightmill:next 112" --permission-mode manual
claude -p "/nightmill:fix 57" --permission-mode manual
claude -p "/nightmill:fix all" --permission-mode manual
```

`112` and `57` are example issue numbers; the text under the block says so. The plugin's full skill names are used,
because the bare `/next` and `/fix` are shadowed by another plugin or project command of the same name (README, "What
is in the plugin"). `--permission-mode manual` is written out so that the run's mode does not depend on the Claude Code
version (before 2.1.302 a `-p` run could start in auto mode) or on a `defaultMode` in a user's settings. `manual` is the
name `claude --help` lists; the text says that its config value is `default`, and that a version whose `--help` lists
`default` and not `manual` takes `default`. Each run starts in the project's main checkout (the folder where `/init`
ran), on the base branch, with a clean tree, one run per terminal. No `--output-format`: the default `text` prints the
final message (the pull request, the `Stopped:` line, or `/fix all`'s table) when the run ends. One sentence says that
`--output-format json` prints one JSON object with that message in `result`, for a script. One example redirects a run's
output to a file outside the checkout:
`claude -p "/nightmill:fix all" --permission-mode manual > "$HOME/nightmill-fix-all.log" 2>&1`. It is outside because a
file in the checkout makes the tree dirty, which stops `/fix all`. stderr carries the trust warning of decision 4.

**3. Manual mode only.** The section recommends Manual mode with `/init`'s rules, and says why not the others. In
`bypassPermissions` (also `--dangerously-skip-permissions`) the allow rules have no effect and every call runs except
what a deny rule refuses; whether the guard's refusals hold there is not shown (link
[What is enforced](#what-is-enforced)). Auto mode lets a classifier decide where the rules were written for prompts; its
behaviour with the guard is not shown either. `dontAsk` and `acceptEdits` are not needed: in a `-p` run in Manual mode,
a call no rule allows is denied, not waited for, and the run goes on without it. `--bare` must not be passed, because
it skips the installed plugin, its guard hook and CLAUDE.md. No `--allowedTools` either: the rules belong in the files
`/init` writes, where the lint and the README describe them. `--permission-prompts none` is not added to the commands:
a `-p` run with no permission host denies those calls anyway, and the flag needs 2.1.259 or later.

**4. The settings a run needs, and how to set them** (`### Before the first run`), one numbered list:

1. `gh` signed in with the `project` scope, as `## Install` says; a headless run uses the stored login.
2. `/nightmill:init` run once in an interactive session in the main checkout, with its four permission lines applied:
   **Permissions** and **Deny rules** in `.claude/settings.json`, **Edit permission** and **Run permissions** in
   `.claude/settings.local.json`. Each is linked to its sub-section. `.claude/settings.local.json` stays untracked by
   git (`/init` says when it is not ignored). A declined line means the commands it covers are denied in a headless run,
   and the run stops or skips at the first of them.
3. The workspace trusted once. Start `claude` interactively in the main checkout and accept the trust dialog; the
   session of step 2 does this. Or set `projects["<the repository root>"].hasTrustDialogAccepted` to `true` in
   `~/.claude.json`. Without it, a headless run ignores the allow rules of `.claude/settings.json` (all of `gh`), and
   stderr shows `this workspace has not been trusted`. The trust covers the slots, which are worktrees of the same
   repository.
4. `/init` again, in an interactive session, after an upgrade of nightmill (until [#213](...)), and after a change of
   `worktrees.slots`, `worktrees.root` or a branch prefix. The script and slot rules follow them, and a headless run
   whose rule no longer matches is denied the command, not asked.
5. No `permissions.defaultMode` other than `default` (or `manual`) in any settings file the run reads, and the flags of
   decisions 2 and 3.

Then the limits, one short list: in a headless run, a command or edit that no rule covers is denied. That covers a
write under `.claude/` (a protected path, so a story that changes `.claude/` cannot be done headless), a git command
the skills do not write, and a test command an agent chooses on its own (iteration 43 decision 9). A denied call is
reported in the final message, not asked. `/next` and `/fix` without a number ask on a tie of priorities, and nobody
answers a headless run, so a run is given its number or the priorities are distinct. `/fix all` asks nothing.

**5. Several runs at once** (`### Several runs at once`), the rules as the skills have them, no new one:

- Every session of the project on the machine, headless or not, shares the same slots. Their number is
  `worktrees.slots` (default 2), unless `WORKER_SLOTS` or a live value from `slot -Capacity` replaces it; link
  [Changing the numbers during a session](#changing-the-numbers-during-a-session).
- A `/next` or a single `/fix` run holds one slot from its take until the slot is freed after the merge (by the next
  take, `-Reap` or `-Release`), also after the run has ended. `/fix all` holds one slot per bug in flight and frees each
  once its pull request is open. So at most as many `/next` and `/fix` runs work at once as there are slots, counting
  the slots that still wait for a merge.
- A run that finds every slot busy stops with `all <k> slots are busy`. Its story or bug is then at In progress with
  nothing behind it, because the status is set before the take. The maintainer moves it back (Approved for a story,
  Ready for a bug). So start no more runs than there are free slots (`slot -Status`, or `/nightmill:status`).
- The agent limit (`parallel.maxAgents`, default 2, or the live value) is counted by each session for the agents it
  started. Two sessions can run up to twice the limit. The room check before each start measures the whole machine and
  holds a start back when memory or CPU is short (link [Room for one more agent](#room-for-one-more-agent)).
- Two runs without a number can take the same item until the first has set In progress, because no claim exists yet
  ([#176](...)). Give each `/next` its own issue number, run at most one `/next` without a number at a time, and run no
  other `/fix` beside `/fix all`.
- Without `worktrees` (no slots) the runs share one checkout and its branch, so only one run at a time.

**6. Watching a run** (`### Watching a run`). A headless run prints nothing until it ends (decision 2). To see where it
is, from another terminal in the project: `claude -p "/nightmill:status"`, or `/nightmill:status` in an interactive
session. It shows the board items with their pull requests and CI, and every slot with **running**, **stalled** or
**unknown**, the skill and the step; it changes nothing. Link
[What a slot's agent is doing](#what-a-slots-agent-is-doing). The page in the browser and the pane beside the chat show
the same slots (links [Watching the run in a browser](#watching-the-run-in-a-browser) and
[Watching the run beside the chat](#watching-the-run-beside-the-chat)); the pane needs an interactive session, not the
headless one. One sentence: `/next` and a single `/fix` end only after watching their pull request's checks, for at
most `review.watchChecksMinutes` (default 30) per push, so a run lasts that long after its pull request opens. Another:
the exit code says whether Claude Code ran, not what the skill did. A `Stopped:` line is the skill's result; read the
final message and `/nightmill:status`.

**7. When a run is stopped** (`### When a run is stopped`). How to stop: Ctrl+C in its terminal, or SIGTERM
(`kill <pid>`), which ends Claude Code with exit 143, terminates the commands it is running and starts nothing new.
There is no kill switch yet ([#165](...)). Then, as a list:

- **During a take:** an interrupted take frees its slot again ("interrupted ...; slot <n> is free again"). A take
  killed without a chance to clean up (`kill -KILL`, a closed window) leaves a claim that `/nightmill:status` shows
  with the step `take-died`; `-Abandon N` (`--abandon N`) frees it once its files are dealt with. Link
  [Why slots](#why-slots).
- **After the take:** nothing is undone. The board status stays as the run last set it (In progress, or Review once
  the pull request is open). The slot stays taken with its branch, its commits and its uncommitted files. Its last
  report stays, so `/nightmill:status` shows it **running** until `worktrees.stalledAfterMinutes` (default 30) have
  passed since that report, then **stalled**. A pull request with auto-merge on merges by itself when its checks pass,
  and its `Closes` sets Done; the next take frees the slot after that merge.
- **Continuing a story:** `/nightmill:next <N>` (headless too) continues a story at In progress or Review from the first
  step that left nothing behind. It refuses while the slot still shows **running**, so wait until it shows
  **stalled**. A slot with uncommitted files from the stopped run is refused until they are committed, stashed or
  discarded.
- **A bug:** `/fix` continues nothing. A bug stopped in flight stays at In progress with its slot taken; the maintainer
  looks at the slot, frees it with `-Abandon N` and moves the bug back to Ready for a new run.
- **`/fix all`** stopped by a signal prints no final table. Each bug in flight is left as a single run is. A slot it
  already freed stays free, and a bug whose pull request is open is at Review.
- `--continue` or `--resume` reopens the stopped conversation, but the section continues work through the board and
  the slots, as above. Those flags are mentioned only as not needed.

**8. Cross-references.** In `### The run permissions` the bullet `- **Headless runs:** ...` becomes
`- **Headless runs:** how to start a run without a terminal is in [Running unattended](#running-unattended) (#160).`.
The bare `#160` stays, which iteration 43's pin (`== init installs the run permissions`) needs. In the Security model,
the sentence under the table begins
`How to run without a person is in [Running unattended](#running-unattended) ([#160](https://github.com/CodaColaLight/nightmill/issues/160)), `
and goes on as today with #164 and #213. So it keeps the three links that `tests/test-security-model.sh` pin 12
needs, and no longer says "not described yet". Issue links in the new section use iteration 39's form,
`[#<n>](https://github.com/<owner>/<repo>/issues/<n>)`, with the repository of the `/plugin marketplace add` line
(decision 7 of iteration 39). The section's own sentences use the shells' script forms the README already uses
(`slot -Status`, `-Abandon N` / `--abandon N`).

**9. The pins live in a test file of their own.** `tests/test-unattended-docs.sh [<root>]` (default: this checkout),
as `tests/test-security-model.sh` does it, called from a new `tests/lint.sh` section `== running unattended is
documented`, directly after `== the security model is documented`:
`bash tests/test-unattended-docs.sh "$PWD" || fail=1`. Taking a root lets the verification run it against a scratch
copy. It reads the numbers it checks from `schema/nightmill.schema.json`, so they stay in step with the schema.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The README shows the exact headless command for `/next` and `/fix` | Decisions 1, 2, 3; `### The commands`; Tests, pins 1 to 4 |
| 2 | It lists the permission settings a run needs and how to set them | Decisions 3, 4; `### Before the first run`; Tests, pins 5 and 6 |
| 3 | It says how many sessions share slots and how to watch a run (`/status`) | Decisions 5, 6; `### Several runs at once`, `### Watching a run`; Tests, pins 7 and 8 |
| 4 | It says what happens when a run is stopped | Decision 7; `### When a run is stopped`; Tests, pin 9 |

The wording of the section is the implementer's. Each item of decisions 1 to 8 must be in it and true on the day of
writing, and the four command lines and the quoted texts (`all <k> slots are busy`, `this workspace has not been
trusted`, `hasTrustDialogAccepted`, `take-died`) are written exactly. The section claims nothing that the Facts mark as
not verified, unless the probe under Tests shows it. Where the probe shows otherwise, the section follows the probe,
and the change is named in "How verified".

## Tests

A documentation change is tested by pins on its text. **`tests/test-unattended-docs.sh`**: `sec` is the part of
`README.md` from the line `## Running unattended` to the next line that starts with `## `; `flat` is `sec` with
newlines turned to spaces and runs of spaces to one. `<repo>` is the `<owner>/<repo>` of the `/plugin marketplace add`
line. Each miss prints `FAIL: <file>: <what>` on stderr and the script exits 1 after all checks.

- Criterion 1:
  1. `README.md` has exactly one line `## Running unattended`, after the line `### Adjusting the limit to the load` and
     before the line `## Developing nightmill`.
  2. `sec` has the five lines `### Before the first run`, `### The commands`, `### Several runs at once`,
     `### Watching a run`, `### When a run is stopped`, each exactly once, in that order, and no other line starting
     `### `.
  3. The `### The commands` part has a code block that holds, each as a whole line, the four lines of decision 2.
     `skills/next/SKILL.md` and `skills/fix/SKILL.md` have the frontmatter lines `name: next` and `name: fix`,
     `skills/fix/SKILL.md` has `argument-hint:` with `all`, and `.claude-plugin/plugin.json` has the name `nightmill`, so
     that a renamed skill fails the pin.
  4. Every line in `sec` that starts with `claude -p ` contains `--permission-mode manual` and none of `--bare`,
     `--dangerously-skip-permissions`, `--permission-mode bypassPermissions`, `--permission-mode auto`,
     `--allowedTools`. `flat` contains `--bare`, `bypassPermissions`, `--dangerously-skip-permissions`, `default` and
     `--output-format json`.
- Criterion 2:
  5. The `### Before the first run` part contains `**Permissions**`, `**Deny rules**`, `**Edit permission**`,
     `**Run permissions**`, `.claude/settings.json`, `.claude/settings.local.json`, `(#the-edit-permission)`,
     `(#the-run-permissions)`, `(#the-deny-rules-and-the-guard)`, `/nightmill:init`, `hasTrustDialogAccepted`,
     `~/.claude.json`, `this workspace has not been trusted`, `defaultMode` and `.claude/`; each of the three anchors'
     headings exists in `README.md`.
  6. That part contains `/init` and a link to #213, and `flat` contains `(#what-is-enforced)` and links to #164 and
     #165.
- Criterion 3:
  7. The `### Several runs at once` part contains `` `worktrees.slots` (default <d>) `` with `<d>` the schema's default
     of `worktrees.slots`, `` `parallel.maxAgents`, default <a> `` or `` `parallel.maxAgents` (default <a>) `` with `<a>` the
     schema's default of `parallel.maxAgents`, `WORKER_SLOTS`, `all <k> slots are busy`, `In progress`,
     `/fix all`, `(#changing-the-numbers-during-a-session)`, `(#room-for-one-more-agent)` and a link to #176. And
     `scripts/slot.sh` still contains `slots are busy`.
  8. The `### Watching a run` part contains `claude -p "/nightmill:status"`, `/nightmill:status`, `**running**`,
     `**stalled**`, `(#what-a-slots-agent-is-doing)`, `(#watching-the-run-in-a-browser)`,
     `(#watching-the-run-beside-the-chat)`, `review.watchChecksMinutes` with ` (default <w>)` after it, `<w>` the
     schema's default of `review.watchChecksMinutes`, and `exit code`; each anchor's heading exists in `README.md`.
- Criterion 4:
  9. The `### When a run is stopped` part contains `Ctrl+C`, `SIGTERM`, `143`, `take-died`, `-Abandon N`,
     `--abandon N`, `In progress`, `Review`, `auto-merge`, `**running**`, `**stalled**`,
     `` `worktrees.stalledAfterMinutes` (default <s>) `` with `<s>` the schema's default, `/nightmill:next <N>`, `Ready`
     and a link to #165. `skills/next/SKILL.md` still contains `another run is working on it`, and
     `skills/next/SKILL.md` contains `` `stalled` and `unknown` are resumed ``.
- Decision 8:
  10. `README.md` has the line that starts `- **Headless runs:**` and it contains `(#running-unattended)` and `#160`;
      the Security model section (from `## Security model` to the next `## `), joined, contains
      `(#running-unattended)` and no longer contains `is not described yet`.
  11. Every link in `sec` that starts with `[#<digits>](` is `[#<n>](https://github.com/<repo>/issues/<n>)` with the
      same number twice.

`tests/lint.sh` gets the section of decision 9 and nothing else. The existing pins keep passing: iteration 43's README
list (`### The run permissions`, `additionalDirectories`, `Run permissions`, `#110`, `#160`),
`tests/test-security-model.sh` (pin 12 links 160, 164 and 213; pin 11 the link form), `tests/test-guard-rules.sh`
(`base branch still prompts` stays absent; the new section never says it), `tests/test-interrupt-docs.sh` (the
sentences in "Why slots" are not changed) and `== specs follow the template`. `bash tests/check.sh` stays green, and
the forbidden-words lint covers the new text.

**Verification of the pins:** break each once in a scratch copy and see it fail, then restore. Drop the heading, move
it after `## Developing nightmill`, swap two sub-headings, change `manual` to `auto` in one command line, rename `name:
fix` in a copy of the skill, drop `hasTrustDialogAccepted`, change the default of `worktrees.slots` in a copy of the
schema, drop the #176 link, drop `take-died`, write `#999` as a link to `/issues/998`, and restore the old sentence in
the Security model. The pull request's "How verified" lists each result.

**The headless probe** (by the implementer, recorded in "How verified"; it reads only and touches no board): in a
scratch git repository outside this checkout, with no `.claude/nightmill.json` and the installed plugin enabled, run
`claude -p "/nightmill:status" --permission-mode manual` once. It shows whether the namespaced skill expands in `-p`
(the status skill reports the missing config, exit 2 of its script) and whether `manual` is accepted. Then run it once
more with a `.claude/settings.json` holding one allow rule in a folder never opened interactively, and see whether stderr
has `this workspace has not been trusted`. A result that differs from the Facts changes the section's sentence (and the
pin's text) to what was seen.

**What the pins cannot check:** that a headless `/next` reaches its pull request without a denial, what a tie prints
headless, and the effect of Ctrl+C on a `-p` run. They are stated as the documentation and the skills have them, and
the maintainer's first unattended run shows them (Left). No manual check applies (Story trigger and manual check).

## Files touched

- `README.md`: the new `## Running unattended` (decisions 1 to 7), the `- **Headless runs:**` bullet of
  `### The run permissions` and the sentence under the Security model's table (decision 8). No other part changes.
- `tests/test-unattended-docs.sh` (new): pins 1 to 11, with a header comment as `tests/test-security-model.sh` has.
- `tests/lint.sh`: the section `== running unattended is documented` (decision 9).
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 49 (#160): the README has a Running unattended section: the claude -p
  commands for /nightmill:next and /nightmill:fix (one issue, or all) in Manual mode, the settings a headless run needs
  (the four lines /init writes, the workspace trusted once, no --bare and no bypass), how runs share the slots and the
  agent limit and how to watch them with /nightmill:status, and what a stopped run leaves and how it is continued. No
  config key.` (commands, paths and keys in backticks).

Not touched: `skills/`, `agents/`, `hooks/`, `scripts/`, `schema/`, `templates/`, `.github/`, `tests/check.sh`,
`SECURITY.md`, `CONTRIBUTING.md`, this repository's `.claude/` files.

## Risks

- **Claude Code changes.** `--bare` is to become the default for `-p` "in a future release"; then a `-p` run without
  the plugin flag would load neither the skills nor the guard. The `manual` name and the Manual default of `-p` are
  recent (2.1.302). The section names the version it was written for (2.1.321 here, or the one the probe ran) and says
  that a run that does not find `/nightmill:next` is the first thing to check after a Claude Code upgrade. A later
  default change is a bug against this section.
- **Unverified statements.** The slash-command expansion, the mode name and the trust warning rest on the documentation
  and `--help`. The probe checks the first two and the third; a tie and Ctrl+C on `-p` are stated with the skills'
  and the documentation's words only (Left).
- **The take after In progress.** Decision 5 states, without fixing it, that a run which finds no free slot leaves its
  item at In progress with nothing behind it. A reader may take the advice "no more runs than free slots" as a
  guarantee; it is not one when a slot's merge is pending. The `all <k> slots are busy` text and `/status` make it
  visible.
- **Iteration 48 and #213.** Both change facts near this section (where the config is read; whether an upgrade needs
  `/init`). The order notes say who rewrites which sentence.
- **Overstating safety.** The section never calls a headless run safe or bounded. It points to the Security model and
  says that limits and a kill switch (#165) and a sandbox (#169) do not exist yet. The pins hold the #165 link.
- **A longer README.** About 90 more lines. The section links the permission, slot and watching sub-sections rather
  than repeating them.

## Size estimate

`M`: about 90 lines in `README.md` (two of them changed), 130 in `tests/test-unattended-docs.sh`, 4 in `tests/lint.sh`,
6 in `CHANGELOG.md`: about 230 changed lines in four files.

## Not done

- No trigger, schedule, cron line or driver script (#164), and no limits, budget, kill switch or run ledger (#165). The
  section says that none exists yet.
- No headless command for `/spec`, `/story`, `/check` or `/init`. The issue names `/next` and `/fix`, and `/init` needs
  its interactive confirmation.
- No sandbox, container or network setting (#169). No recommendation of `bypassPermissions`, auto mode, `dontAsk`,
  `--allowedTools` or `--permission-prompts none`.
- No claim protocol (#176). Two runs that pick the same item are prevented only by the advice of decision 5.
- No change to the order "In progress, then take" in `/next` and `/fix`, and no change to `/fix` so that it continues
  a bug at In progress.
- No new skill, script, flag, config key, hook or permission rule; `/init` writes nothing new.
- No load controller in a headless run: `/loop` and `/nightmill:control` stay as "Adjusting the limit to the load"
  describes them.
- No change to the pane, the dashboard or `/status`.

## Left

- **A run that finds no free slot.** `/next` and `/fix` set In progress before the take. A run that then finds every
  slot busy leaves the item at In progress with no branch, slot or pull request, and `/next N` refuses it ("nothing to
  continue"). With several headless runs this becomes likely. This spec documents it (decision 5) and does not change
  the skills (out of scope). Whether it is a bug to file is for the maintainer.
- **Not verified by a run:** whether a headless `/nightmill:next` on a trusted workspace reaches its pull request with
  no denial (iteration 43's manual check was interactive); what a `-p` run prints when `/next` or `/fix` would ask on a
  tie (iteration 37's step 9 asked the same for `/story` and no record is on `main`); whether Ctrl+C on a `-p` run in a
  terminal ends it like SIGINT and whether it reaches the take's bash; whether subagents end with a SIGTERM; what a
  SIGKILL of `claude` leaves of a take that runs as its child. The probe settles the expansion, the mode name and the
  trust warning. The rest is the maintainer's first unattended run; its result may change a sentence of
  `### When a run is stopped` in a later pull request.
- **Manual mode as the only recommendation.** Decision 3 follows the setting that iterations 43 and 47 wrote and checked
  for. If the maintainer wants auto mode documented for unattended runs, that needs the guard's behaviour there shown
  first (README, `### What is enforced`).
- **The agent limit across sessions.** The schema describes `parallel.maxAgents` as agents "running at the same time on
  this machine", but each session counts only its own (Facts). Decision 5 states what the skills do. Whether the limit
  should hold across sessions is a design question for the maintainer, not settled here.
