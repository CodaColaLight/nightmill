# Iteration 43: /init writes the permissions that run /spec, /next and /fix to a pull request without a prompt

Status: delivered in iteration 43 (PR #216)

Story: #109, epic #107 (Hardening from the code review), finding CR-2 of the review of 0.2.0. `/nightmill:init` gets a
new plan line, **Run permissions**, that writes to the personal `.claude/settings.local.json`: the slot root under
`permissions.additionalDirectories`, one edit rule for the slots, the git commands the skills run (in the main checkout
and in each slot), the slot, room, validate and status scripts at the resolved plugin path, and the quick check. The
skills write those commands in exactly one form each, so the rules match what the model types, and each skill that
injects the config declares `allowed-tools` for its injection. Changes `skills/init/SKILL.md`, `skills/spec/SKILL.md`,
`skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/workflow/SKILL.md`, `skills/check/SKILL.md`,
`skills/story/SKILL.md`, `README.md`, `tests/lint.sh` and `CHANGELOG.md`. No script, agent, hook, schema or template
changes.

## Story trigger and manual check

**Not a story trigger.** Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. No status, no board call and no actor changes.
- *A new, renamed or removed config key*: no. The rules are built from keys that exist (`worktrees.root`,
  `worktrees.slots`, `git.baseBranch`, `git.featurePrefix`, `git.fixPrefix`, `git.specPrefix`, `verification.check`);
  `permissions.additionalDirectories` is a key of Claude Code's settings file, not of `.claude/nightmill.json`. The
  config stays readable by the previous version (invariant "Compatible").
- *A change to the slot marker format*: no. No script in `scripts/` changes; `slot-N.json`, `capacity.json` and
  `ledger.tsv` are untouched.

No decision record: `docs/decisions/` 0001 to 0003 say nothing about permissions, and nothing here contradicts them.

**The manual check applies**: `skills` is in `verification.manualCheckPaths` and seven skills change. Its steps are
under Tests. No script changes, so no smoke step in either shell; the PowerShell side of the change is the rule text
for the `.ps1` scripts (decision 6), which only the manual check on Windows can show.

**Order.** Iteration 39 (#159, the security model, spec PR #197 open) lists the rules `/init` writes; its lint reads
only the `- **Permissions**:` bullet, which this iteration leaves as it is (decision 1). Whichever of the two merges
second updates the README's list of rules ("What an agent can do") to name the **Run permissions** line. #127 (the
injection fallback) changes the same injection lines as decision 8; see Risks.

## Facts this rests on

Read on `main` at b76b0cd (0.5.0, iterations 41 and 42 merged), read only. Claude Code's documentation read on
2026-11-08: `https://code.claude.com/docs/en/permissions` and `https://code.claude.com/docs/en/skills`. The issues
#110, #127 and #160 read with `gh issue view`.

**The finding still holds.** `skills/init/SKILL.md` **Permissions** writes `Bash(gh project:*)`, `Bash(gh issue:*)`,
`Bash(gh pr:*)`, `Bash(gh api:*)`, `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git log:*)` and
`Bash(<the exact check command>)` to `.claude/settings.json`, and **Edit permission** writes `Edit(**)` to
`.claude/settings.local.json`. Its report says that "the slots under `worktrees.root` are outside the project directory
and still prompt", and the README's "The edit permission" says the same under **Limits**. Nothing else is written. No
skill has `allowed-tools` in its frontmatter.

**What the skills run** (the commands, as the skill text writes them today):

- `/spec`, in the main checkout: `git fetch`, a new branch from `origin/<git.baseBranch>` and a switch to it ("create
  ... and switch to it", no command given), the commit of the spec, the push, `gh pr create` and `gh pr merge`, a
  switch back; `validate-config` (`"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config ...` or
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" ...`); the room and capacity checks of the workflow skill.
- `/next` and `/fix`, the session: the slot take (`"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Take ...` and
  `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --take ...`, the bash form **without** `bash` in `/next` step 2.2, and
  `slot.sh --take ...` in `/fix`), the reports (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --report ...`),
  `-Capacity -Porcelain`, `-Abandon`, `validate-config`, `room`; in the slot: `git -C <slot> status`, `log`, `diff`,
  `stash push`, `stash list`, `stash pop`, `hash-object`, `rev-parse`, `ls-tree`, `merge-base`, `reset --mixed -q`,
  `reset -q --`, `update-index`, `checkout-index`, `symbolic-ref`; the CHANGELOG commit, "Rebase on
  `origin/<git.baseBranch>`" and the push (no command given); edits of `CHANGELOG.md` and the spec's status line in the
  slot. Without slots: `git switch -c` from `origin/<git.baseBranch>`. `/fix` also runs `git ls-tree -r --name-only
  origin/<git.baseBranch>`, `git stash push` in the main checkout and `git pull --ff-only` after a bug's pull request.
- The tester, the implementer and the fixer: "Use that absolute path for every file and `git -C <slot path>` for every
  git command; your working directory is not the slot"; they commit ("commit the work on the branch"), run the check
  (`<verification.check>`) and the quick check (`<verification.check> --quick`, iteration 42) and write files in the
  slot.
- `/check`: `verification.check`, or `<verification.check> --quick`. `/status`:
  `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/status.ps1"` or
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"`.
- The workflow skill writes the capacity and room calls as `"${CLAUDE_PLUGIN_ROOT}/scripts/slot.ps1" -Capacity
  -Porcelain` / `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh" --capacity --porcelain` and
  `"${CLAUDE_PLUGIN_ROOT}/scripts/room.ps1"` / `bash "${CLAUDE_PLUGIN_ROOT}/scripts/room.sh"`.
- Seven skills inject the config, all with `` !`cat .claude/nightmill.json 2>/dev/null || echo ...` `` (`spec`, `next`,
  `fix`, `check` and `story` got the fallback with #127).

**Where the slots are.** `scripts/slot.sh` takes the main checkout as the parent of
`git rev-parse --path-format=absolute --git-common-dir`, the root as `<main>/<worktrees.root>` (default
`../<main folder name>-wt`), resolved with `cd ... && pwd`, and slot N as `<root>/slot-N`; `scripts/slot.ps1` uses
`[System.IO.Path]::GetFullPath((Join-Path $main $rootRel))`. A take prints `Slot N is yours: <dir>  (branch <b>)`.
`--capacity --slot-count` accepts 1 to 99; the schema gives `worktrees.slots` a minimum of 1 and a default of 2. The
markers and the ledger live in `<root>/.slots/`.

**Where the plugin is.** An installed release lives in a folder per version, for example
`~/.claude/plugins/cache/nightmill/nightmill/0.5.0` (0.4.0 and 0.5.0 side by side on this machine). Claude Code
substitutes `${CLAUDE_PLUGIN_ROOT}` in a plugin skill's content and in the Bash rules of its `allowed-tools` (skills
documentation), so the model reads the expanded absolute path, and every skill expands it the same way.

**Claude Code's rules** (permissions documentation, quoted in substance):

- A Bash rule matches the whole command text; `*` matches any text including spaces; `Bash(x *)` with a trailing
  ` *` also matches the bare `x`; the `:*` suffix is the same as a trailing ` *` and is recognised only at the end.
  An allow rule with a `*` before the subcommand gets a startup warning, and `Bash(git * main)` matches
  `git -c core.fsmonitor=<script> diff main`.
- A rule does not match the same program in another form: `Bash(git push *)` does not match `git -C . push`. Quoting
  is not normalised (`git 'push' origin main` is not matched).
- Compound commands are split at `&&`, `||`, `;`, `|`, `|&`, `&` and newlines; every part must be allowed. `cd` into a
  working directory or an additional directory is read-only, but **`cd` followed by `git`** in one command prompts when
  the `cd` changes the directory. A command that cannot be parsed prompts.
- Built-in read-only commands (`ls`, `cat`, `grep`, `cd`, `diff`, read-only forms of `git`, ...) run without a prompt.
  Which `git` forms, and whether `git -C <dir>` counts, is not listed.
- `permissions.additionalDirectories` in a settings file grants file access only: reads without a prompt; "file
  editing permissions follow the current permission mode", so an edit there still needs a mode or an `Edit` rule.
- `Edit` rules use gitignore patterns: `//path` is absolute from the filesystem root, `/path` relative to the settings
  source, `path` relative to the current directory; `*` matches inside one segment, `**` across. On Windows a path is
  matched in POSIX form, `C:\Users\a` as `/c/Users/a`. An `Edit` rule covers every built-in tool that edits files.
- `.claude/settings.local.json` that is not tracked by git applies its allow rules and additional directories without
  the trust step once git has run; a `-p` session counts as trusted for that check. Project `settings.json` allow rules
  wait for the workspace trust dialog. Deny rules from any scope win over allow rules.
- `allowed-tools` in a skill's frontmatter (a space- or comma-separated string, or a YAML list) grants the listed tools
  "during the turn that invokes this skill"; injected `` !` ` `` commands are checked against the permission rules, and
  outside auto mode a check that does not return allow aborts the invocation; `allowed-tools` pre-approves them.

**Not verified by a run** (decision 12 and Left): which rule spelling Claude Code matches for a `git -C` command with an
absolute path on Windows, whether `allowed-tools` reaches a subagent, and whether a write under `<slot>/.claude/` is
still refused as a protected path under an `Edit` rule (iteration 12 saw it refused inside the project).

## Decisions

**1. One new plan line, in the personal file.** A new line **Run permissions**, after **Edit permission** and before
**Board workflows**, writes to `.claude/settings.local.json` only. Reasons: its paths are absolute and differ per machine
(the slot root, the plugin folder under the home directory), and letting an unattended run commit and push is the
choice of whoever runs it, as iteration 12 decided for edits (its decision 2). **Permissions** and **Edit permission**
keep their rules and their files; nothing already in either file is removed or reordered.

**2. The rule list.** Placeholders: `<C>` is `verification.check`, `<B>` `git.baseBranch`, `<Sp>`, `<Fe>`, `<Fx>`
`git.specPrefix`, `git.featurePrefix`, `git.fixPrefix` (defaults `main`, `spec/`, `feat/`, `fix/`); `<R>` the slot root
and `<S>` one slot, `<R>/slot-<n>` (decision 4); `<P>` the plugin folder (decision 6). New rules use the space form of
the documentation (`Bash(git add *)`); a prefix that is glued to a branch name has no space (`Bash(git push -u origin
spec/*)`). The rules already written with `:*` stay as they are.

*A. The main checkout*, 15 rules:

| # | Rule | For |
|---|---|---|
| A1 | `Bash(git fetch origin)` | `/spec`, `/next`, `/fix` before a branch or a rebase |
| A2 | `Bash(git switch *)` | a new branch without a slot, the switch back |
| A3 | `Bash(git add *)` | the spec commit, a commit without a slot |
| A4 | `Bash(git commit *)` | the same |
| A5 | `Bash(git push -u origin <Sp>*)` | the spec branch |
| A6 | `Bash(git push -u origin <Fe>*)` | a story branch without a slot |
| A7 | `Bash(git push -u origin <Fx>*)` | a bug branch without a slot |
| A8 | `Bash(git pull --ff-only)` | `/fix` after a bug's pull request |
| A9 | `Bash(git rebase origin/<B>)` | the rebase without a slot |
| A10 | `Bash(git rebase --continue)` | after a CHANGELOG conflict without a slot |
| A11 | `Bash(git stash push *)` | `/fix`'s tester files in the main checkout |
| A12 | `Bash(git stash list)` | finding that entry |
| A13 | `Bash(git ls-tree *)` | `/fix` |
| A14 | `Bash(git rev-parse *)` | reading a commit |
| A15 | `Bash(<C> --quick)` | the quick check (iteration 42) |

*B. Each slot*, 21 rules per slot `<S>`, for n from 1 to `worktrees.slots`:

| # | Rule |
|---|---|
| B1 to B5 | `Bash(git -C <S> status *)`, `Bash(git -C <S> diff *)`, `Bash(git -C <S> log *)`, `Bash(git -C <S> add *)`, `Bash(git -C <S> commit *)` |
| B6 to B8 | `Bash(git -C <S> stash push *)`, `Bash(git -C <S> stash list)`, `Bash(git -C <S> stash pop *)` |
| B9 to B12 | `Bash(git -C <S> hash-object *)`, `Bash(git -C <S> rev-parse *)`, `Bash(git -C <S> ls-tree *)`, `Bash(git -C <S> merge-base *)` |
| B13, B14 | `Bash(git -C <S> reset --mixed -q *)`, `Bash(git -C <S> reset -q -- *)` |
| B15 to B17 | `Bash(git -C <S> update-index *)`, `Bash(git -C <S> checkout-index *)`, `Bash(git -C <S> symbolic-ref *)` |
| B18, B19 | `Bash(git -C <S> rebase origin/<B>)`, `Bash(git -C <S> rebase --continue)` |
| B20, B21 | `Bash(git -C <S> push -u origin <Fe>*)`, `Bash(git -C <S> push -u origin <Fx>*)` |

*C. Edits in the slots*, one rule: `Edit(//<R as POSIX path, without its leading slash>/slot-*/**)`, for example
`Edit(//Users/a/work/app-wt/slot-*/**)` or, on Windows, `Edit(//c/Users/a/work/app-wt/slot-*/**)`. `slot-*` matches
one path segment, so `<R>/.slots/` (markers, ledger, capacity) is not covered and keeps prompting for the edit tools.

*D. The scripts*, 8 rules, for `<name>` in `slot`, `room`, `validate-config`, `status`:
`Bash(bash "<P>/scripts/<name>.sh" *)` and
`Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/<name>.ps1" *)`.

*E. The directory*: `<R>` once in `permissions.additionalDirectories` (created as an array when missing), so that
files in the slots are read without a prompt and a `cd` into a slot is read-only.

The total is `24 + 21 × worktrees.slots` rules and one directory: 66 rules for the default 2 slots, 108 for 4.

**3. Why these and no broader ones.** Each rule names a subcommand before its first `*`, so none gets the startup
warning and none matches `git -c <option>` or another subcommand. `git push` is allowed only as `-u origin` plus one of
the three branch prefixes, never bare, so a push to `<B>` written `git push origin <B>` stays a prompt. `reset` is
allowed only in the two forms the skills use, never `--hard`. `git stash drop`, `clear`, `git branch -D`, `git clean`,
`git checkout` and `git -C <S> fetch` get no rule: no step on the way to an open pull request runs them (the empty
branch that `/spec` deletes after a stop is on the stop path, see Not done). Refusing what the skills forbid (force
push, a push to the base branch written another way, `gh pr merge --admin`, deletes) is #110's deny rules; the narrow
push rules here add nothing to that list.

**4. The slot root and the slots.** `/init` resolves `<R>` the way the slot script of the shell in use does, without
creating it: the main checkout is the parent of `git rev-parse --path-format=absolute --git-common-dir`; `<R>` is
`<main>/<worktrees.root>` (default `../<main folder name>-wt`) with `.` and `..` resolved as text, in the form the
script prints (bash: `/c/...` style under Git Bash, `/...` elsewhere; PowerShell: `C:\...`). `<S>` is `<R>/slot-<n>`
with the separator of that form. B is written for n = 1 to `worktrees.slots` from the config; a slot added later with
`--capacity --slot-count` has no rules until `/init` runs again after the config is raised (Risks). When `<R>` contains a
space, a quote or a backslash in the bash form, the line is **failed**: `worktrees.root resolves to <R>, which a rule
cannot match unquoted; slot commands will prompt`, and the other parts (A, D) are still written.

**5. The skills write each command in one form.** A rule matches the text the model types, so every command the rules
cover is written once, exactly, in the skills:

- In the main checkout: `git fetch origin`; a new branch `git switch -c <branch> origin/<B>`; the switch back
  `git switch <branch>`; the push `git push -u origin <branch>`; the rebase without a slot `git rebase origin/<B>`.
- In a slot, by the session and by every subagent: `git -C <absolute slot path> <subcommand> ...`, never `cd <slot> &&
  git ...` (that prompts, Facts) and never `git -C` with a relative path. The session's own slot steps of `/next` step 5
  and `/fix` name them: `git fetch origin` in the main checkout, then `git -C <slot path> rebase origin/<B>`,
  `git -C <slot path> add ...`, `git -C <slot path> commit -m "<message>"`, `git -C <slot path> push -u origin
  <branch>`.
- The check in a slot: `cd <absolute slot path> && <C>` and `cd <absolute slot path> && <C> --quick` (a `cd` into an
  additional directory is read-only, and the check is not `git`). The implementer's, the fixer's and the tester's prompts
  say so where they name the check.
- Commit messages are passed with `-m "<message>"` (one or more), never through a command substitution or a heredoc,
  which the parser may not split.
- Scripts: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" <args>` and
  `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.ps1" <args>`, the forms
  `/status` already uses. Every call of a script in `skills/*/SKILL.md` that names `${CLAUDE_PLUGIN_ROOT}` uses one of
  the two, `/init`'s own calls included. Short references such as `slot.sh --capacity --porcelain` that point to the
  workflow skill's full form may stay.

**6. The plugin path.** `<P>` is `${CLAUDE_PLUGIN_ROOT}` as it expands in `/init`'s own text: the same string every other
skill of the same installed version expands to, so the rule and the command the model copies from a skill are the same
text. The folder holds the version, so after an upgrade the D rules of the old version no longer match: the next
`/init` run finds them missing and adds the new ones (one confirmation). Rules of another plugin folder that are already
in the file are kept (nothing is removed), and the plan names them `kept: <k> script rules for another plugin folder`.
D covers the four scripts on the path to a pull request and `/status`; `models`, `control`, `dashboard`, `panel`,
`load`, `stages`, `template-board`, `render-templates` and `release` get no rule.

**7. What `/init` does with the line.**

1. **Detect.** For every rule of decision 2 for the current config, and for `<R>`: present when the rule is in
   `permissions.allow` of `.claude/settings.local.json` or of `.claude/settings.json` (string equality), and `<R>` when
   it is in `permissions.additionalDirectories` of either. The line is **exists** when all are present, or when
   `permissions.defaultMode` is `bypassPermissions` in either file (`exists (defaultMode bypassPermissions)`). Otherwise
   it is **create** (no local file) or **change**. `acceptEdits` covers only C and does not make the line **exists**.
2. **Show the exact text** in the plan message, with the CLAUDE.md, `settings.json` and edit-permission texts: for a
   missing file the whole file (2-space indentation, LF, `permissions.allow` in the order A, B by slot then by row, C,
   D, then `permissions.additionalDirectories`); for a present file the diff (the missing rules appended at the end of
   `permissions.allow` in that order, `<R>` appended to `additionalDirectories`, every other byte unchanged). Above the
   text, one sentence: what it grants (the git commands of the skills in the main checkout and in the slots, edits in
   the slots, the four scripts of nightmill `<version>`, the quick check), and that it does not grant other git
   commands, other directories or other scripts, and that the plugin's scripts change folder with each version.
3. **Git.** The `git check-ignore -q .claude/settings.local.json` line of **Edit permission** covers this file too; it
   is said once.
4. **Apply** with the other settings changes, after **Edit permission**, merging without removing or reordering an
   entry; read the file back; a line whose read-back lacks a rule or `<R>` is **failed**, naming the first missing one.
5. **Declined.** Neither settings file gets any of these entries; the report says
   `Run permissions: declined (the skills' git commands, scripts and slot edits will prompt)`.
6. **Report row**, one of: `added to .claude/settings.local.json (<k> rules, <d> directory)`,
   `exists (<file or defaultMode>)`, `declined (...)`, `failed: <reason>`. After an add the report says that the rules
   follow `worktrees.slots`, the branch prefixes and the plugin version, and that `/init` is run again after any of them
   changes.

**Edit permission**'s report sentence "the slots under `worktrees.root` are outside the project directory and still
prompt" becomes "the slots under `worktrees.root` are covered by **Run permissions**, not by this rule". Its sentence on
headless runs and trust stays.

**8. `allowed-tools` for the injection.** Each of the seven skills that injects the config gets the frontmatter line
`allowed-tools: Bash(cat .claude/nightmill.json *)` (the trailing ` *` matches the bare command and the
`2>/dev/null` form). It grants nothing beyond reading the config file, which `cat` already does as a read-only
command; it keeps the injection from aborting under a stricter permission set or mode. The fallbacks (`|| echo ...`) of
the five skills without one are #127's; when #127 changes a command, its `allowed-tools` changes with it (lint, Tests).

**9. What "without a prompt" covers.** The commands and edits the skills prescribe on the way from Ready (`/spec`) or
Approved (`/next`) or a Ready bug (`/fix`) to an open pull request with auto-merge enabled, plus `/check`, `/check quick`
and `/status`. A command a subagent chooses on its own, such as running one test file with the project's test runner,
is the project's to allow; the manual check lists each such prompt separately and it does not fail the criterion
(Left).

**10. No change to the subagents' tools.** The tester, the implementer, the fixer and the reviewers keep their tools;
subagents use the session's permission rules, so A to E reach them. Whether a skill's `allowed-tools` reaches them is not
relied on (Facts, not verified).

**11. The README.** `### The edit permission`'s **Limits** bullet loses the sentence that the slots are not covered and
points to the new subsection. A new subsection `### The run permissions` after it: what the line adds (the slot root
as an additional directory, the edit rule for `slot-*`, the git commands in the main checkout and in each slot, the four
scripts at the plugin's folder, the quick check), the count `24 + 21 × worktrees.slots`, why in the personal file, what
it leaves out (other git commands and every push not `-u origin <prefix>...`; refusing the forbidden actions is #110),
that `/init` is run again after an upgrade, a change of `worktrees.slots`, `worktrees.root` or a branch prefix, how to
take it back (delete the entries), and that a headless invocation is described in "Running unattended" (#160), not
here. The `/nightmill:init` paragraph names "the run permissions" next to "the edit permission".

**12. Verification of the rule spellings.** The spellings above follow the documentation; the manual check runs them.
When a run shows that a rule does not match (a prompt for a command the skills write in the form of decision 5), the
implementer changes that rule or that command form so that they match, keeps every other decision, and names the change
in "How verified"; a change that needs a broader rule than decision 3 allows (a `*` before a subcommand, a bare
`git push`, `git -C <R>/...` with a wildcard in the path) stops the implementer: it is reported `partial` for the
maintainer.

## Criteria and rules

The issue has no acceptance criteria list (filed as a bug, turned into a story on 2026-11-08); these are derived from
"What should happen" and the fix direction, in that order.

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | After `/init`, `/next` takes an Approved story to an open pull request without a prompt and without `--dangerously-skip-permissions` | Decisions 2, 5, 9; Tests (manual check 2) |
| 2 | The same for `/spec` (Ready to a spec pull request) and `/fix` (a Ready bug to a pull request), and `/check` and `/status` | Decisions 2, 5, 9; Tests (manual check 1, 3, 4) |
| 3 | The slot worktrees under `worktrees.root` are reachable: `permissions.additionalDirectories` and an edit rule | Decisions 2 (C, E), 4 |
| 4 | Rules for the git verbs the skills use | Decisions 2 (A, B), 3, 5 |
| 5 | Rules for the slot, status and validate scripts with the resolved plugin path | Decisions 2 (D), 6 |
| 6 | `allowed-tools` in each skill's frontmatter for its own injection | Decision 8 |
| 7 | Matching deny rules | Not here: #110 (decision 3, Left) |
| 8 | `/init` shows the exact text before the one confirmation, a declined line writes nothing, a second run changes nothing | Decision 7 |
| 9 | The headless invocation is in the README's "Running unattended" | Not here: #160 (decision 11, Not done) |
| 10 | The finding is confirmed against the current code | Facts ("The finding still holds") |

## Tests

`/init` and the skills are prose followed by the model, so the lint pins the wording the behaviour depends on and the
manual check does the behaviour, as iterations 1 and 12 did.

**`tests/lint.sh`**, new section `== init installs the run permissions`, directly after
`== init installs the edit permission`. Each miss prints `FAIL: <file>: <what>` and sets `fail=1`.

- Criteria 3 to 5, 8: `skills/init/SKILL.md` contains `**Run permissions**`, `.claude/settings.local.json`,
  `additionalDirectories`, `Edit(//`, `/slot-*/**`, `git rev-parse --path-format=absolute --git-common-dir`, every
  rule text of decision 2 with its placeholders as written there (A1 to A15, B1 to B21 with `<S>`, the two D forms with
  `<P>` and `<name>`), `24 + 21`, `declined (the skills' git commands, scripts and slot edits will prompt)` and
  `kept: <k> script rules for another plugin folder`. The `- **Run permissions**` bullet (to the next line starting
  `- **`) contains `without removing or reordering an entry`. The `## 4. Confirm once` step names **Run permissions**.
- Decision 3: `skills/init/SKILL.md` contains none of `Bash(git push *)`, `Bash(git push:*)`, `Bash(git *)`,
  `Bash(git:*)`, `Bash(git -C *`, `Bash(git -C:*)`, `slot-* ` inside a `Bash(` rule, `reset --hard`.
- Criterion 4, the rules and the skills in step: every `git -C <slot path> <word>` and `git -C <slot> <word>` in
  `skills/next/SKILL.md`, `skills/fix/SKILL.md` and `agents/tester.md` (with the second word for `stash` and `reset`:
  `stash push`, `reset --mixed`, `reset -q`) names a subcommand that has a B rule in `skills/init/SKILL.md`; else
  `FAIL: <file> runs git -C <slot> <subcommand>, which no Run permissions rule covers`.
- Decision 5: in every `skills/*/SKILL.md`, each occurrence of `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"` is directly
  preceded by `bash ` and each `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.ps1"` by
  `powershell -NoProfile -ExecutionPolicy Bypass -File `; else `FAIL: <file>: <the 40 characters around it> is not the
  one script form`. `skills/spec/SKILL.md` contains `git fetch origin`, `git switch -c` and `git push -u origin`;
  `skills/next/SKILL.md` and `skills/fix/SKILL.md` contain `git fetch origin`, `git -C <slot path> rebase origin/`,
  `git -C <slot path> push -u origin`, `cd <absolute slot path> && <verification.check>` and `-m "<message>"`.
- Criterion 6: each `skills/*/SKILL.md` with a line starting `` !` `` has, inside its frontmatter, a line starting
  `allowed-tools:` that contains `Bash(cat .claude/nightmill.json *)`, and every such injection line starts
  `` !`cat .claude/nightmill.json``; else `FAIL: <file>: the injection has no matching allowed-tools`.
- README (decision 11): contains `### The run permissions`, `additionalDirectories`, `Run permissions`, `#110`, `#160`;
  no longer contains `the edits \`/next\` and \`/fix\` make in a slot still prompt` (the current sentence, matched on
  the README joined into one line).
- The existing sections keep passing: `== init installs the edit permission` (its words stay, `Edit(/**)` appears
  nowhere), `== skills`, `== text from issues is data`. `bash tests/check.sh` stays green; `claude plugin validate .
  --strict` accepts the `allowed-tools` lines.

What the lint cannot check: that Claude Code matches the rules against the commands, that the model types the forms of
decision 5, that the resolved paths are right. That is the manual check.

**Manual check by the maintainer**, with nightmill loaded from a separate checkout of the branch
(`claude --plugin-dir <that checkout>`, started in another folder, decision 0003), in a throwaway repository with a
board, the default `worktrees` (2 slots), a check command, one Ready story, one Approved story with its spec merged and
one Ready bug. The workspace is trusted once in an interactive session. Every session runs in the default mode, without
`--dangerously-skip-permissions` and with no `defaultMode` in either settings file. Each prompt that appears is written
down with its command or path.

1. `/nightmill:init`, "apply all": the plan shows **Run permissions** with the full file text; the local file then
   holds 66 rules from this line (plus `Edit(**)`), `<R>` under `additionalDirectories`, and the report row
   `added to .claude/settings.local.json (66 rules, 1 directory)`. A second run: `exists`, nothing asked, files
   unchanged (hash before and after).
2. A new session: `/nightmill:next <approved story>` until the pull request is open and auto-merge is enabled: **no
   prompt** for a command or edit the skills prescribe (criterion 1). A prompt for a test command a subagent chose is
   listed apart (decision 9).
3. `/nightmill:spec <ready story>` until the spec pull request is open; `/nightmill:fix <bug>` until its pull request is
   open: no prompt (criterion 2).
4. `/nightmill:check`, `/nightmill:check quick` (this repository's check, in a clone of it) and `/nightmill:status`: no
   prompt.
5. A write to `<R>/.slots/x` with the Write tool and `git -C <R>/slot-1 push origin main` typed as a request: both
   prompt (decisions 2 C, 3).
6. Decline: on a fresh clone skip the line; neither settings file holds an entry of it, and the report says
   `declined (the skills' git commands, scripts and slot edits will prompt)`.
7. On Windows (Git Bash as the Bash tool), steps 1 and 2 once more; the rule forms that had to change (decision 12) go
   into "How verified".

## Files touched

- `skills/init/SKILL.md`: the **Run permissions** line of decision 7 with the list of decision 2 and the resolution of
  decision 4; the changed report sentence of **Edit permission**; `## 4. Confirm once` names the run-permissions text
  next to the others; `## 5. Apply` lists it after the edit permission; its own script calls in the forms of decision 5;
  `allowed-tools` (decision 8).
- `skills/spec/SKILL.md`: `git fetch origin`, `git switch -c <branch> origin/<git.baseBranch>`, `git switch <branch>`
  for the switch back, `git push -u origin <branch>`, `-m` for the commit, the `validate-config` calls in the forms of
  decision 5, `allowed-tools`.
- `skills/next/SKILL.md`, `skills/fix/SKILL.md`: the slot take and every script call in the forms of decision 5; the
  session's slot commands of step 5 (and `/fix`'s equivalent) as `git -C <slot path> ...`; the slotless branch and
  push forms; the check as `cd <absolute slot path> && <verification.check>` (and `--quick`) in the implementer's, the
  fixer's and the tester's prompts; `-m "<message>"` for every commit; `allowed-tools`.
- `skills/workflow/SKILL.md`: the capacity and room calls in the forms of decision 5; in **Parallel work** one sentence:
  "In a slot every git command is `git -C <absolute slot path> ...`; `/init`'s **Run permissions** covers exactly the
  forms the skills write"; `allowed-tools`.
- `skills/check/SKILL.md`: "from that worktree's root" becomes `cd <absolute slot path> && <verification.check>`;
  `allowed-tools`.
- `skills/story/SKILL.md`: `allowed-tools` only.
- `README.md`: decision 11.
- `tests/lint.sh`: the section of Tests.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 43 (#109): /init writes the permissions an unattended run needs. A new
  plan line, Run permissions, adds to .claude/settings.local.json the slot root as an additional directory, an edit
  rule for the slots, the git commands the skills run in the main checkout and in each slot, the slot, room,
  validate-config and status scripts at the plugin's folder, and the quick check; the skills write each of those
  commands in one form, and each skill that injects the config declares allowed-tools for it. No config key.` (paths,
  keys and commands in backticks).

Not touched: `scripts/`, `agents/`, `hooks/`, the schema, the example config, the templates, `.claude/settings.json` and
`.claude/settings.local.json` of this repository.

## Risks

- **A spelling that does not match.** Claude Code matches the text the model types; a reworded command (a quoted slot
  path, `git -C` after `cd`, a heredoc commit message) prompts. Decision 5 and the lint keep the skills to one form; the
  model can still deviate. The manual check counts the prompts; decision 12 says what the implementer may change.
- **Slot count and upgrades.** Rules follow `worktrees.slots`, `worktrees.root`, the prefixes and the plugin folder.
  A slot raised during a session (`--capacity --slot-count`), the `WORKER_SLOTS` override or a new version prompts
  until `/init` runs again; the report and the README say so. Old rules stay in the file (never removed) and match only
  a folder or slot that no longer exists or is no longer used.
- **What the rules allow.** `git switch *` can discard changes (`--discard-changes`, `-f`); `git commit *` runs the
  repository's hooks; a push with a refspec such as `<Fe>x:<B>` matches A6 or B20. The pushes still need the token and
  the base branch's ruleset; the refusals belong to #110.
- **Protected paths.** A story that changes `<slot>/.claude/` (this repository's `nightmill.json`) may still prompt
  there; the rules do not lift Claude Code's protected paths (iteration 12 saw `.claude/` refused inside the project).
- **#127 and iteration 39.** #127 rewrites the five injections that have no fallback; the lint of decision 8 fails until
  their `allowed-tools` matches, so neither can drift silently. Iteration 39's README section lists the rules; the one
  merged second adds the other's.
- **A long settings file.** 66 to 108 entries are hard to read by hand; the README's subsection explains the groups.

## Size estimate

`M`: about 90 lines in `skills/init/SKILL.md`, 60 across the six other skills (command forms, prompts, frontmatter), 45
in the README, 90 in `tests/lint.sh`, 3 in `CHANGELOG.md`: about 290 changed lines in ten files.

## Not done

- No deny rules and no `PreToolUse` hook (#110): force push, a push to the base branch, `gh pr merge --admin`, deletes
  and setting Ready or Approved are still refused only by the skills' text.
- No "Running unattended" section and no headless command line (#160); no `defaultMode`, sandbox or container setting
  (#169).
- No injection fallback (#127); only the `allowed-tools` line of decision 8.
- No rule for the stop and clean-up paths (`git branch -D` of an empty spec branch, `git stash drop`), for `models`,
  `control`, `dashboard`, `panel`, `load` and the other scripts, or for running one test file with a project's runner
  (decision 9).
- No `PowerShell(...)` rules for Claude Code's PowerShell tool; the `.ps1` scripts are covered when they are started
  through the Bash tool in the form of decision 5.
- No change to the rules **Permissions** and **Edit permission** write, to their files, or to this repository's own
  settings; no rule is removed from any file; no new config key, script, agent or hook.

## Left

- **Deny rules.** The fix direction asks for "matching deny rules (see the allow-rules bug)". The issue points them to
  #110, and this spec writes none; it keeps its own push and reset rules narrow so that #110's list needs nothing new.
  Whether #110 should land before this story, so that no project gets `git push` and `git commit` rules without the
  denies, is for the maintainer.
- **Tests a subagent runs on its own.** Decision 9 leaves a test command the tester or the implementer chooses (for
  example `bash tests/smoke-slot.sh` in a slot) to the project's rules, so it may prompt. Settling it would take either a
  rule that agents run tests only through the check or the quick check (slow for this repository), or a config key for
  a test command with an init rule (a story trigger). Neither is asked for here.
- **Not verified by a run:** the matching of `git -C <absolute path>` rules on Windows (`/c/...` against `C:\...`);
  whether `additionalDirectories` takes the Git Bash or the Windows form; whether a skill's `allowed-tools` reaches a
  subagent (not relied on); whether Claude Code treats `git -C <dir> status` as read-only (B has rules for it either
  way); protected paths under an `Edit` rule in an additional directory. The manual check settles them; decision 12
  bounds what may change.
- **Script rules in the frontmatter instead.** `allowed-tools` substitutes `${CLAUDE_PLUGIN_ROOT}`, so the D rules
  could live in the skills and survive an upgrade without `/init`. The fix direction asks for the resolved path in the
  settings, and the grant lasts only for the turn and may not reach the subagents that report their steps; the
  maintainer may want it as a follow-up.
- **The quick-check rule** (A15) settles the permission half of iteration 42's Left ("the first quick check may ask for
  permission"), without a config key.
