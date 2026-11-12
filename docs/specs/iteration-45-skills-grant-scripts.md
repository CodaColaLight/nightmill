# Iteration 45: the skills grant their own plugin scripts, so an upgrade needs no /init run

Status: draft, awaiting approval (#213)

Story: #213, epic #107 (Hardening from the code review). Builds on iteration 43 (#109, PR #216, merged) and iteration
53 (#165, merged). Each skill that runs one of the five scripts group D of `/init` writes rules for today (`slot`,
`room`, `gate`, `validate-config`, `status`) grants them in its own `allowed-tools` frontmatter with
`${CLAUDE_PLUGIN_ROOT}`. Claude Code expands that variable to the installed version's folder, so the grant follows
every upgrade. `/init` no longer writes group D of **Run permissions**. It names the script rules an earlier version
wrote and keeps them. A lint rule fails when a skill runs one of the five scripts without granting it. Implementation
step 1 is a real run that settles the two questions the documentation leaves open, and its outcome either selects the
change below or ends the run `partial` with no file changed (decision 1). The change touches `skills/spec/SKILL.md`,
`skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/workflow/SKILL.md`, `skills/check/SKILL.md`,
`skills/story/SKILL.md`, `skills/control/SKILL.md`, `skills/status/SKILL.md`, `skills/init/SKILL.md`, `README.md`,
`tests/lint.sh`, `tests/fixtures/lint-grants/` (new), `tests/test-limits-docs.sh`, `tests/test-config-from-base.sh`
and `CHANGELOG.md`. It does not change `scripts/`, any agent, any hook, the schema or a template, and it adds no
`bin/` file.

## Story trigger and manual check

**Not a story trigger.** Of `escalation.storyTriggers`:

- *A change to the status flow or who sets a status*: no. No status, no board call and no actor changes.
- *A new, renamed or removed config key*: no. `allowed-tools` is a key of a skill's frontmatter. `permissions.allow` is
  a key of Claude Code's settings file, not of `.claude/nightmill.json`. The config stays readable by the previous
  version.
- *A change to the slot marker format*: no. No script in `scripts/` changes, and the reports keep their commands, so
  `slot-N.json`, `capacity.json` and `ledger.tsv` are written exactly as today.

No decision record. Decisions 0001 to 0003 say nothing about permissions. The manual check below follows 0003: the
plugin is installed from the marketplace, and the upgrade is to a release branch installed as a preview.

**The manual check applies.** `skills` is in `verification.manualCheckPaths`, and nine skills change. Its steps are
under Tests. No script in `scripts/` changes, so no smoke step is added. `tests/lint.sh` has no PowerShell twin
(iteration 40), so the new lint section exists in bash only.

## Facts this rests on

Read on `main` at 9000bf8 (0.5.0 with iterations 43 and #217 merged, not released); the script calls, the
`allowed-tools` lines, group D, the count and the tests below read again on `main` at 01d9c07 (0.6.0 released, with
iteration 43; iteration 53 merged, not released). Claude Code's documentation read
again on 2026-11-08 with WebFetch: `https://code.claude.com/docs/en/skills`, `.../permissions`, `.../sub-agents` and
`.../plugins-reference`.

**What the code does today (01d9c07).**

- `skills/init/SKILL.md` **Run permissions** group D writes 10 rules to `.claude/settings.local.json`:
  `Bash(bash "<P>/scripts/<name>.sh" *)` and
  `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/<name>.ps1" *)` for `<name>` in `slot`,
  `room`, `gate`, `validate-config` and `status` (iteration 53 added `gate`; 0.6.0 writes the other eight). `<P>` is
  `${CLAUDE_PLUGIN_ROOT}` as it expands in `/init`, for example `~/.claude/plugins/cache/nightmill/nightmill/0.6.0`.
  The count is `26 + 21 × worktrees.slots`, "68 rules for 2 slots, 110 for 4" (15 in A, 21 per slot in B, 1 in C, 10
  in D; it was `24 + 21` at 9000bf8). The plan says `kept: <k> script rules for another plugin folder`. The sentence
  above the exact text names "the five scripts of nightmill `<version>`" and says "the plugin's scripts change folder
  with each version". The bullet's lead names "the scripts at the plugin's folder", **Unmatchable root** says "A and D
  are still written", **Show the exact text** orders the rules "A, B by slot then by rule, C, D", and the report says
  the rules follow "the plugin version" and that `/init` must run again after an upgrade.
- The `allowed-tools` lines. The six skills that inject the base branch's configuration (`workflow`, `spec`, `next`,
  `fix`, `story`, `check`) all have one line of five comma-separated rules:
  `allowed-tools: Bash(git symbolic-ref -q --short refs/remotes/origin/HEAD *), Bash(git for-each-ref --count=1 *),
  Bash(git show origin/*:.claude/nightmill.json *), Bash(echo "NO BASE CONFIG*"), Bash(cat .claude/nightmill.json *)`
  (one line in the file). `init` has `allowed-tools: Bash(cat .claude/nightmill.json *), Bash(echo "*no
  .claude/nightmill.json yet*")` (one line). `status`, `models` and `control` have no `allowed-tools`. `init`, `next`,
  `fix` and `spec` have `disable-model-invocation: true` (`story` had it too until bug #119 removed it, so that `/next`
  and the workflow can file the rest of a partial story with it).
- **Who runs which of the five scripts**, as the skill text writes it (every full call already has one of the two
  forms of iteration 43's decision 5), found with decision 2's "runs" text over `skills/*/SKILL.md`:
  - `spec`: `validate-config` and `gate` in full form; `slot` through the short reference
    `slot.sh --capacity --porcelain`; `room` through "check the room on the machine (**Parallel work** in the
    `workflow` skill)".
  - `next` and `fix`: `slot` in full form (`--take`, `--report`, `--abandon`) and as short references;
    `validate-config` and `gate` in full form; `room` through the same sentence.
  - `workflow`: `slot` (`--capacity --porcelain`), `room` and `gate` in full form (**The pause and the limits**).
  - `check`: `gate` in full form, before each run of the check. `/check` runs no other plugin script; besides the
    gate it runs `verification.check` and `<verification.check> --quick`, which iteration 43's rule A15 covers with no
    plugin path.
  - `story`: `gate` in full form, "right before step 4", the step that creates the issue. Step 3 ends "Show the draft
    to the maintainer and adjust", so in a run with the maintainer the gate runs after the maintainer has answered.
  - `control`: `gate` in full form, before the pass, besides scripts the issue puts out of scope.
  - `status`: `status` in full form. `init`: `validate-config` in full form, plus `template-board` and
    `render-templates` (out of scope). `models`: none of the five (`tests/test-limits-docs.sh` fails when `status` or
    `models` contains `gate.sh`).
  - Agents: no file in `agents/` names a script. The implementer (a fresh agent) and the fixer report their own
    steps. Their prompts carry the report command "with the absolute path of the script, as `${CLAUDE_PLUGIN_ROOT}`
    expands in the session" (`next` "Reporting the steps" and the implementer's prompt, `fix` likewise). The tester's
    prompt has no report command, and the reviewers cannot run a script. The gate is run by the skill's own session
    (`--role <role> --turns <t>` "after a launch returns"), not by a subagent.
- The lint section `== init installs the run permissions` requires the two D rule texts, `26 + 21` and the `kept:`
  text in `skills/init/SKILL.md`. It also requires every `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>.<ext>"` in a skill to
  have one of the two script forms.
- `tests/test-limits-docs.sh` (lines 139 to 141) fails when `skills/init/SKILL.md` lacks `` `gate` `` ("group D does
  not name gate") or `26 + 21`, or contains `24 + 21`.
- `tests/test-config-from-base.sh` requires the five-rule line above in `workflow`, `spec`, `next`, `fix`, `story`
  and `check` as a whole line (`grep -qxF`), so any rule added to that line fails it.
  `tests/test-skill-config-fallback.sh` splits the line at commas and needs a rule for every part of the injection.
- `README.md` `### The run permissions`: the bullet `**Five scripts** at the plugin's folder, `slot`, `room`, `gate`,
  `validate-config` and `status`, in the bash and the PowerShell form, and the quick check`; the sentence "That makes
  `26 + 21 × worktrees.slots` rules (68 for 2 slots) and one directory"; **What it leaves out** ends "and the other
  scripts"; **Re-running** says "the plugin's folder, which holds its version. Run `/init` again after an upgrade".

**What the documentation says (2026-11-08).**

- Skills, frontmatter reference: `allowed-tools` grants the listed tools "during the turn that invokes this skill. The
  grant clears when you send your next message. Accepts a space- or comma-separated string, or a YAML list". In a
  plugin skill, Claude Code substitutes `${CLAUDE_PLUGIN_ROOT}` in "the skill's markdown content, and Bash rules in the
  `allowed-tools` frontmatter. Using the same variable in both places lets a skill run a bundled script without a
  permission prompt." Deny and ask rules still override `allowed-tools`. With `allowManagedPermissionRulesOnly` in
  managed settings, Claude Code ignores `allowed-tools`.
- Plugins reference: `${CLAUDE_PLUGIN_ROOT}` is "Absolute path of the plugin's installed version" and "changes when
  the plugin updates". The variables "aren't present in the environment of commands Claude runs through the Bash
  tool, in the main session or in a subagent". On Windows most substituted paths use forward slashes
  (`C:/Users/...`). Files in a plugin's `bin/` "are on the Bash tool's `PATH` while the plugin is enabled, so Claude
  runs them as bare commands". claude.ai and Cowork do not install a plugin that has a `bin/` directory.
- Sub-agents: each subagent has "independent permissions" and "inherits the parent conversation's permission
  rules". Background subagents surface every permission prompt in the main session. "A background subagent's
  results reach Claude as a completion notification in a later turn", which is "marked as an automated event rather
  than a message from you". With fork mode on (the default), Claude cannot wait for a subagent in an interactive
  session.
- Permissions: an allow rule does not match past a leading assignment of an unknown variable. A `*` in a Bash rule
  matches any text, `..` included. Paths in Bash rules are not normalised.

**Still not settled by the documentation**, so step 1 settles them by a run:

- **Q1:** whether a skill's `allowed-tools` grant reaches a subagent launched in that turn, in the foreground or in
  the background. The pages say neither yes nor no.
- **Q2:** whether the grant survives a background subagent's completion notification. "Clears when you send your next
  message" and "an automated event rather than a message from you" suggest it does, but no page says so.

## Decisions

**1. Step 1: the probe, before any file changes.** The implementer runs it and puts its result file, verbatim, in
"How verified". The probe runs in a new folder `T=$(mktemp -d)`, outside the slot and outside every checkout. Nothing
from it is committed.

*The probe plugin* `$T/probe`:

- `$T/probe/.claude-plugin/plugin.json`: `{ "name": "grantprobe", "version": "0.0.1", "description": "throwaway permission probe" }`
- `$T/probe/scripts/mark.sh`: `#!/usr/bin/env bash` and `printf '%s\n' "$1" >> "$PWD/marks.txt"`
- `$T/probe/skills/grant/SKILL.md`:

  ```markdown
  ---
  name: grant
  description: Throwaway permission probe.
  disable-model-invocation: true
  allowed-tools: Bash(cat .claude/nightmill.json *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/mark.sh" *)
  ---

  Do exactly these steps, in order, and nothing else. Never retry a command; if one is denied, go on.

  1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mark.sh" session`.
  2. Launch one fresh general-purpose subagent (not a fork), in the foreground if you can, with the prompt:
     "Run exactly `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mark.sh" subagent-fg` with the Bash tool, once, and report
     its exit code." Wait for its result if you can.
  3. Launch one fresh general-purpose subagent in the background with the same prompt, the argument `subagent-bg`.
     Wait for its completion notice; do not poll.
  4. After that notice arrives, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mark.sh" after-notice`.
  5. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/mark.sh" end`.
  ```

  The `cat` rule is there so that the probe's `allowed-tools` line has the same shape as the skills' line after this
  story: one line, several comma-separated rules. The probe so tests the form the skills ship.

*The control plugin* `$T/control`: a copy of `$T/probe` whose `allowed-tools` line keeps only
`Bash(cat .claude/nightmill.json *)`.

*The project folder* `$T/proj`: `git init`, and no `.claude/settings.local.json`.

*The runs.* Each run is an interactive session. A headless `-p` run waits for every subagent, so it cannot show a
completion notice. Each run is started inside `tmux` from `$T/proj`:
`tmux new-session -d -s <run> -x 200 -y 50 "env -u CLAUDECODE claude --plugin-dir $T/<plugin> --permission-mode default"`.
The implementer accepts the workspace trust dialog with `Enter` and then sends `/grantprobe:grant` and `Enter`. It
then polls `$T/proj/marks.txt` and `tmux capture-pane -p -t <run>` every 5 s:

- When the pane shows a permission prompt, the implementer appends `prompt: <the step's argument>` to
  `$T/<run>-result.txt`, as read from the pane, and sends `Escape` to deny that one call.
- After `end` is in `marks.txt`, or after 600 s, it copies `marks.txt` below the prompt lines, removes `marks.txt` so the next run
  starts empty, kills the session and goes on.

The control run comes first, then the probe run.

*Validity.* The control run must show a prompt for `session`. If it does not, the machine allows the script without
any grant: user settings, a mode or a hook. The probe then proves nothing. The implementer changes no file, reports
`partial` and names the rule or the mode that allowed it. The probe plugin's `mark.sh` writes its marks to
`$PWD/marks.txt`, the folder `claude` starts in (`$T/proj`), not the plugin folder. The control run must show that
prompt for `session` with the sandbox's auto-allow of Bash commands turned off: a sandboxed session runs Bash commands
without a prompt, so with it on the control proves nothing.

*Outcomes of the probe run* and what the implementation does (the first row that matches applies):

| `session` | `subagent-fg` and `subagent-bg` | `after-notice` | Then |
|---|---|---|---|
| prompt | any | any | The frontmatter cannot grant the scripts in the form the skills use. Retry once with the grant as a YAML list (`allowed-tools:` followed by `  - 'Bash(...)'` lines), only to tell the maintainer whether the list form would work. **Stop `partial`**: change no file, report both results. A list form that works would be a new story, since the lint and three tests read the single `allowed-tools:` line |
| no prompt | no prompt (both) | no prompt | **The change** (decisions 2 to 6) |
| no prompt | a prompt for either | no prompt | **Stop `partial`**: the grant does not reach the subagents, so their step reports would need a rule in the settings (decision 3). Change no file. Report the result |
| no prompt | any | prompt | **Stop `partial`**: the grant ends when a background agent ends, so a long `/next` run would prompt for its scripts after its first subagent. Change no file. Report the result |

When a fork mode or a missing feature keeps step 2 from running in the foreground, `subagent-fg` is read like
`subagent-bg`. The skills' subagents are not forks, and with fork mode on they run in the background. A step that
did not run at all (no mark, no prompt) counts as a prompt and is named in "How verified".

**2. The five scripts are granted in the skill that runs them.** A skill *runs* `<name>`, for `<name>` in `slot`,
`room`, `gate`, `validate-config` and `status`, when its body contains `scripts/<name>.sh`, `scripts/<name>.ps1`,
`<name>.sh --` or `<name>.ps1 -` (fixed strings), or, for `room` only, the words `check the room on the machine`. That
sentence points at the room call in the `workflow` skill. For each name it runs, the skill's single `allowed-tools:`
line carries both forms:

- `Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh" *)`
- `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.ps1" *)`

These are the forms iteration 43's decision 5 made the only ones. They are appended to the skill's existing line after
its last rule, each joined with `, ` as the existing rules are, in the order `slot`, `room`, `gate`,
`validate-config`, `status`; the existing rules stay first and unchanged. A skill without a line gets a new one with
only its script rules. The resulting lines (the rule text of `main` at 01d9c07 read with the "runs" text above):

| Skill | Scripts granted | Rules on the line |
|---|---|---|
| `spec` | slot, room, gate, validate-config | 5 + 8 |
| `next` | slot, room, gate, validate-config | 5 + 8 |
| `fix` | slot, room, gate, validate-config | 5 + 8 |
| `workflow` | slot, room, gate | 5 + 6 |
| `check` | gate | 5 + 2 |
| `story` | gate | 5 + 2 |
| `init` | validate-config | 2 + 2 |
| `status` | status | 2 (new line) |
| `control` | gate | 2 (new line) |

`models` gets no script grant: it runs only a script the issue puts out of scope. `control`'s other scripts and
`init`'s `template-board` and `render-templates` are out of scope as well and get no grant (Not done). Why `workflow`
grants too: the model may load it inside a `/spec`, `/next` or `/fix` run, and whether loading a second skill replaces
the first skill's grant is not documented. With the same grants in both skills, either way is covered. No rule is
broader than these: none is `Bash(bash *)` or `Bash(powershell *)`, and none has a `*` before `/scripts/`.

The grant of `/story` covers its gate call only while the turn that invoked `/story` lasts. In a run with the
maintainer the gate runs after the maintainer has answered the draft (Facts), and the documentation says that message
clears the grant (decision 5). This spec adds no other cover for it (Left).

**3. What covers the subagents.** The implementer's and the fixer's report commands are covered by the grant of the
skill that launched them; decision 1 selects the change only when the probe shows that. Their prompts stay as they
are. They still carry the absolute path as it expands in the session, which is the same text the grant expands to.

When the grant does not reach a subagent, the run stops `partial` (decision 1, row 3) instead of taking a second
plan, because every cover found breaks a criterion or an invariant:

- *Iteration 43's versioned rule for `--report` alone* holds the plugin's version, so the next upgrade prompts again
  until `/init` runs (criterion 1, the Goal).
- *A version-free `bin/` command* (`bin/nightmill-report`, on the Bash tool's `PATH`, with one settings rule
  `Bash(nightmill-report *)`) needs that rule in the settings. No earlier release writes it, so the first upgrade to
  this release needs one `/init` run before the subagents stop prompting (criterion 1, the Goal). It also has no
  PowerShell form a version-free rule can name: `powershell -File` does not search `PATH`, and a
  `powershell -Command nightmill-report.ps1 *` rule lets any PowerShell text run, so a twin of the Both-shells
  invariant cannot be covered. And claude.ai and Cowork do not install a plugin with `bin/`.
- *No report from the subagents* changes the report steps of iteration 23, which this story leaves alone (Not done).

Which of these, if any, the maintainer accepts is the maintainer's choice (Left).

**4. `/init` and the old script rules.** Group D is removed from **Run permissions**, all 10 rules. With it go: the
sentence "the five scripts of nightmill `<version>`" and "the plugin's scripts change folder with each version" in the
sentence above the exact text, "the scripts at the plugin's folder" in the bullet's lead, `D` in **Unmatchable root**
("A is still written") and in the order of **Show the exact text** ("A, B by slot then by rule, C"), and the report
sentence that the rules follow "the plugin version" and that `/init` runs again after it changes. The text says
instead that the skills grant their own scripts. The count becomes `16 + 21 × worktrees.slots` rules (15 + 1 + 21 per
slot: 58 for 2 slots, 100 for 4). The README and the lint follow it.

*An old script rule* is an entry of `permissions.allow`, in `.claude/settings.local.json` or `.claude/settings.json`,
that equals one of these two patterns, with any folder `<any folder>` without a `"`:

- `Bash(bash "<any folder>/scripts/<name>.sh" *)`
- `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<any folder>/scripts/<name>.ps1" *)`

`<name>` is one of the five names (`slot`, `room`, `gate`, `validate-config`, `status`). The rules of the folder
`/init` runs from count too.

- **Detect** counts them per file as `k`. They do not count toward the line being present or missing.
- **Plan and report.** When `k` is above 0, the **Run permissions** row of the plan, and the row of the report, end
  with `; kept: <k> script rules with a versioned plugin path in <file> (the skills grant their scripts now; delete
  them by hand if you like)`. This holds also when the line is otherwise **exists**.
- **Removal.** `/init` never removes them, never offers to, and changes no byte of them. The line still merges
  "without removing or reordering an entry".
- **The old `kept:` text.** `kept: <k> script rules for another plugin folder` is replaced by the text above.

**5. How long a grant lasts.** A grant holds from the skill's invocation until the maintainer's next message. The
README says so, and says that a message typed during a `/next` or `/fix` run can make that run's later script calls
prompt. It also says that when managed settings set `allowManagedPermissionRulesOnly`, Claude Code ignores
`allowed-tools`, and the scripts prompt. That case needs a managed rule, not `/init`. This is also why "without a
prompt" (iteration 43, decision 9) means a run that the maintainer starts and does not type into.

**6. README.** In `### The run permissions`, the **Five scripts** bullet is replaced by a paragraph that says which
rules live where:

- **In the skills:** the `slot`, `room`, `gate`, `validate-config` and `status` scripts, granted in each skill's
  `allowed-tools` with `${CLAUDE_PLUGIN_ROOT}`, which follows the installed version. An upgrade needs no `/init` run
  for them.
- **In the settings:** the git commands, the slot root, the slot edit rule and the quick check
  (`<verification.check> --quick`), written by `/init`.

The count sentence changes to `16 + 21 × worktrees.slots` rules (58 for 2 slots, 100 for 4) and one directory. In
**What it leaves out**, "and the other scripts" becomes "and the plugin's scripts (the skills grant those)". In the
**Re-running** bullet, "the plugin's folder, which holds its version" and "Run `/init` again after an upgrade" are
removed. A sentence is added: the script rules an older `/init` wrote stay in the file, `/init` names them as kept,
and they can be deleted by hand. The limits of decision 5 are a new bullet **How long the script grants last**. The
rest of the section stays.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | After an upgrade, `/next`, `/fix`, `/spec`, `/check` and `/status` run the plugin's scripts without a prompt and without `/init` | Decisions 1, 2, 5. `/next`, `/fix` and `/spec` grant `slot`, `room`, `gate` and `validate-config`; `/status` grants `status`; `/check` grants `gate`, the only plugin script it runs (its check commands are iteration 43's rule A15, no plugin path); `/story`, `/control` and `workflow` grant `gate` too, and `/init` `validate-config` (decision 2; for `/story` see Left). Tests (lint, manual check 3 to 5) |
| 2 | The subagents that run plugin scripts do not prompt, or the spec says why not and what covers them | Decisions 1, 3; Tests (manual check 3, 4) |
| 3 | `/init` writes no versioned script rules when the frontmatter covers them; old ones are named and kept, never removed without confirmation | Decision 4; Tests (lint, manual check 2, 6) |
| 4 | The README says which rules live in the skills and which in the settings, and that an upgrade needs no `/init` run for them | Decisions 5, 6; Tests (lint) |
| 5 | A lint rule fails when a skill runs a plugin script that its `allowed-tools` does not grant | Decision 2; Tests (lint, its own test) |

## Tests

**`tests/lint.sh`**, a new section `== skills grant the scripts they run`, directly after
`== init installs the run permissions`. Each miss prints a `FAIL:` line and sets `fail=1`.

- *The rule* (criterion 5) is a function `check_script_grants <file>`. It reads the first `allowed-tools:` line
  inside the file's frontmatter, and the body after the frontmatter. For each `<name>` in `slot room gate
  validate-config status` that the body runs (decision 2's text matches, fixed strings), and for each of the two forms
  that is not on that line as a fixed string, it prints
  `FAIL: <file> runs scripts/<name> but its allowed-tools does not grant <the missing rule>` and returns non-zero. A
  line with a rule that is `Bash(bash *)` or `Bash(powershell *)`, or a rule with a `*` before `/scripts/`, prints
  `FAIL: <file>: allowed-tools grants more than the five scripts' two forms`. The section calls the function on every
  `skills/*/SKILL.md`.
- *Its own test* is two fixtures in `tests/fixtures/lint-grants/`:
  - `ungranted/SKILL.md`: frontmatter with `allowed-tools: Bash(cat .claude/nightmill.json *)`; body with the line
    ``Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/room.sh"`.``
  - `granted/SKILL.md`: the same body, with both `room` forms added to the line.

  The section runs the function on both. `ungranted` must print exactly the two lines for the two `room` forms and
  return non-zero. `granted` must print nothing and return 0. Otherwise:
  `FAIL: tests/lint.sh: the script-grant rule did not <fail on|pass> tests/fixtures/lint-grants/<fixture>`. The
  fixture lines are never printed as failures of the lint itself.
- *`/init`* (criterion 3), in `== init installs the run permissions`:
  - Removed from the required words: the two D rule texts, `26 + 21` and `kept: <k> script rules for another plugin
    folder`.
  - Added: `16 + 21`, `58 rules for 2 slots, 100 for 4`, `kept: <k> script rules with a versioned plugin path`,
    `Bash(bash "<any folder>/scripts/<name>.sh" *)`, and the `powershell` pattern of decision 4.
  - New failures: `skills/init/SKILL.md` contains `"<P>/scripts/`
    (`FAIL: skills/init/SKILL.md still writes script rules with the plugin path`), `the five scripts of nightmill`,
    `**D. The scripts**` or `26 + 21`, or the **Run permissions** bullet contains `remove` next to `kept` (on one
    line).
- *README* (criterion 4): it contains `allowed-tools`, `${CLAUDE_PLUGIN_ROOT}`, `an upgrade needs no`, `/init` run,
  `16 + 21 × worktrees.slots`, `58 for 2 slots`, `allowManagedPermissionRulesOnly` and `your next message`. Matching
  is on the README joined into one line. It no longer contains `Run \`/init\` again after an upgrade`,
  `**Five scripts**`, `26 + 21 × worktrees.slots` or `68 for 2 slots`. These replace the run-permissions README words
  of iteration 43 that this story changes.
- *`tests/test-limits-docs.sh`* changes with the count, or it fails: it no longer requires `` `gate` `` in
  `skills/init/SKILL.md` (that check named group D) nor `26 + 21`; it requires `16 + 21` instead, still fails on
  `24 + 21`, and now also fails on `26 + 21`. Its checks of the gate calls in `next`, `fix`, `spec`, `check`, `story`
  and `control` stay.
- *`tests/test-config-from-base.sh`* changes with the longer lines, or it fails: for `workflow`, `spec`, `next`,
  `fix`, `story` and `check`, the first `allowed-tools:` line must equal the five-rule line of Facts or start with it
  followed by `, ` (instead of `grep -qxF` on the whole line). The failure message stays.
- The existing sections keep passing, among them the one-script-form check of iteration 43, the injection check and
  `tests/test-skill-config-fallback.sh` (the added rules are comma-separated like the others). A `status` or
  `control` line without a `cat` rule is allowed, because neither injects anything. `bash tests/check.sh` stays green,
  and `claude plugin validate . --strict` accepts the longer `allowed-tools` lines.

The tester writes these tests before step 1 runs. When step 1 ends the run `partial`, the implementer changes no
file outside the tests and reports them as `unmet:` under Left, which `/next` step 5 sets aside as for any `partial`
result.

What the lint cannot check: that Claude Code expands and matches the grants, that they reach the subagents, and that
an upgrade really needs no `/init`. Step 1 and the manual check settle those.

**Manual check by the maintainer.** In a throwaway repository: a board, the default `worktrees` (2 slots), a check
command, one small Approved story with its spec merged and one small Ready bug. Every session runs in the default mode,
with no `defaultMode` and no `--dangerously-skip-permissions`, and nothing is typed during a run. Each prompt is written
down with its command.

1. Install the newest published release from the marketplace (decision 0003): 0.6.0, or a later one that already has
   iteration 43.
2. Run `/nightmill:init` with "apply all". Then make sure `.claude/settings.local.json` holds exactly the ten old
   script rules of decision 4 for that release's folder `<F>`, the absolute path of the installed version (for
   example `/Users/<you>/.claude/plugins/cache/nightmill/nightmill/0.6.0`, no `~`): `Bash(bash "<F>/scripts/<name>.sh" *)`
   and `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<F>/scripts/<name>.ps1" *)` for `<name>` in `slot`,
   `room`, `gate`, `validate-config` and `status` (five scripts, two forms each). A release with iterations 43 and 53
   has written all ten already. A release with iteration 43 but not 53 (0.6.0) writes eight: add the two `gate`
   entries by hand to `permissions.allow`. On a release without iteration 43 (0.5.0), add all ten by hand. Either way
   step 6 has old rules to name and keep. `grep -cF '/scripts/' .claude/settings.local.json` counts 10 lines, and
   `grep -F '/scripts/' .claude/settings.local.json | shasum` is written down as the hash before.
3. Upgrade to the preview of the release that has this story: `claude plugin marketplace remove nightmill`, then
   `claude plugin marketplace add CodaColaLight/nightmill#release/vX.Y.Z`, then `claude plugin install
   nightmill@nightmill`. **Do not run `/init`.** Check that neither settings file names the preview's folder
   (`grep -F '/X.Y.Z/' .claude/settings*.json` finds nothing). In a new session, run `/nightmill:next <story>` until
   its pull request is open. There is no prompt for a command that starts with `bash "<preview folder>/scripts/` or
   `powershell ... -File "<preview folder>/scripts/`, the gate included, in the session or in the implementer
   (criteria 1, 2). On 0.5.0, the git prompts of the missing iteration-43 rules are listed apart and do not fail this
   step.
4. `/nightmill:fix <bug>` until its pull request is open: the same, the fixer included.
5. `/nightmill:spec` on a Ready story until the spec pull request is open, then `/nightmill:status` and
   `/nightmill:check quick`: no prompt for a plugin script, the gate of `/spec` and `/check` included.
6. Now run `/nightmill:init` (criterion 3). The plan's **Run permissions** row names `kept: 10 script rules with a
   versioned plugin path in .claude/settings.local.json`, the ten rules of step 2. It writes no rule that names the
   preview's folder. After the run, `grep -cF '/scripts/' .claude/settings.local.json` still counts 10 and the same
   `shasum` line equals the hash of step 2. A second run reports **exists**.
7. On Windows (Git Bash as the Bash tool), run steps 3 and 4 once more.

## Files touched

- `skills/spec/SKILL.md`, `skills/next/SKILL.md`, `skills/fix/SKILL.md`, `skills/workflow/SKILL.md`,
  `skills/check/SKILL.md`, `skills/story/SKILL.md`, `skills/init/SKILL.md`: the longer `allowed-tools` line of
  decision 2. The implementer's and the fixer's report paragraphs stay as they are (decision 3).
- `skills/status/SKILL.md`, `skills/control/SKILL.md`: a new `allowed-tools` line (decision 2).
- `skills/init/SKILL.md`: **Run permissions** as in decision 4: D removed, the count, the bullet's lead, the
  unmatchable-root and exact-text orders, the sentence above the exact text, the report sentence, the old-rule
  detection and the `kept:` text.
- `README.md`: decisions 5 and 6.
- `tests/lint.sh` and `tests/fixtures/lint-grants/{ungranted,granted}/SKILL.md` (new): the Tests above.
- `tests/test-limits-docs.sh`: the count check and the `gate`-in-group-D check of the Tests above.
- `tests/test-config-from-base.sh`: the `allowed-tools` line check of the Tests above.
- `CHANGELOG.md`, under `Unreleased`: `- Iteration 45 (#213): the skills grant the slot, room, gate, validate-config
  and status scripts in their own allowed-tools, with ${CLAUDE_PLUGIN_ROOT}, so a plugin upgrade needs no /init run
  for them; /init no longer writes those rules, names the ones an earlier version wrote and keeps them, and a lint
  rule fails when a skill runs one of the five scripts without granting it. No config key.` Paths, keys and commands
  go in backticks.

Not touched: `scripts/`, `bin/` (none is added), `agents/`, `hooks/`, the schema, the templates, `.github/`,
`skills/models/SKILL.md`, groups A, B, C and E of **Run permissions**, **Permissions**, **Edit permission**, and this
repository's own settings files.

## Risks

- **A message during a run clears the grant** (decision 5). A run that asks the maintainer something, or one the
  maintainer types into, prompts for its later script calls. Answering "don't ask again" writes a versioned rule into
  the settings. The README names the limit; the manual check types nothing.
- **`/story`'s gate runs after the maintainer's answer** (decision 2). With group D gone, a `/story` run with the
  maintainer prompts for the gate, not only after an upgrade, unless the grant outlives the answer, which the
  documentation says it does not (Left).
- **Managed settings** with `allowManagedPermissionRulesOnly` ignore every `allowed-tools`. In such an organisation,
  the scripts prompt and the injections of iteration 43 may abort. `/init` cannot fix that.
- **A longer frontmatter line.** Thirteen rules on one line (`spec`, `next`, `fix`) are hard to read. The lint checks
  them, and `claude plugin validate --strict` parses them.
- **The probe is one run on one version of Claude Code.** A later version may change how grants reach subagents. The
  manual check of every release (decision 0003's preview) is where that shows.
- **Old rules stay** (decision 4): `.claude/settings.local.json` keeps one set per release installed before this
  story, until the maintainer deletes them. The plan names them on every run.

## Size estimate

`M`, about 170 changed lines: about 40 in `skills/init/SKILL.md`, 9 frontmatter lines, 25 in the README, 70 in
`tests/lint.sh`, 14 in the two fixtures, 4 in `tests/test-limits-docs.sh`, 3 in `tests/test-config-from-base.sh` and
3 in `CHANGELOG.md`, in sixteen files.

## Not done

- No grant and no rule for `models`, `control`'s own controller script, `dashboard`, `panel`, `load`, `stages`,
  `template-board`, `render-templates` or `release` (out of scope). The lint rule checks only the five scripts.
- No change to iteration 43's git, edit and quick-check rules (groups A, B, C, E), and no deny rule or hook (#110).
- `/init` removes no rule and offers no removal. The old script rules are named, not deleted.
- No `PowerShell(...)` rules for Claude Code's PowerShell tool, as in iteration 43.
- No change to `scripts/slot.*`, `scripts/gate.*`, the report steps, the marker format or `/status`'s reading of the
  reports.
- No change to where `/story` runs the gate, and no settings rule for it (Left).
- No grant to the tester or the reviewers. They run no plugin script.
- No second plan for the subagents' reports: no `bin/` command, no version-free settings rule, no versioned rule for
  `--report` alone (decision 3). When the grant does not reach the subagents, the run stops `partial`.

## Left

- **Q1 and Q2 are open until step 1 runs.** The documentation read on 2026-11-08 does not settle whether a grant
  reaches a subagent or survives a completion notice. Decision 1 makes the outcome select the change, or end the run
  `partial` for the maintainer: when the frontmatter cannot grant at all, when the grant does not reach the
  subagents, or when the grant ends at a notice.
- **The subagents' reports when the grant does not reach them** are not settled here. Criterion 2 allows a cover other
  than the grant, but each one decision 3 names breaks something the issue asks for: a versioned rule needs `/init`
  after every upgrade; a `bin/` command needs one `/init` run after the first upgrade (against criterion 1 and the
  Goal), has no PowerShell form a version-free rule can cover (Both shells), and keeps claude.ai and Cowork from
  installing the plugin; no report changes iteration 23's steps. If step 1 stops there, the maintainer chooses one,
  or accepts the prompts, in a new story or a revised spec.
- **The tests are written before step 1 runs.** The maintainer may prefer step 1 to run before the story is
  Approved, so that a `partial` outcome is known before the tester's work.
- **`/story`'s gate after the draft.** `/story` runs the gate right before it creates the issue, after the
  maintainer has answered the draft, and the documentation says that answer clears the grant. So `/story` prompts for
  the gate in a run with the maintainer, with or without an upgrade, once group D is gone (a `/story` run with no
  message between its start and the gate, as inside a `/next` turn, is covered by the grant). Criterion 1 does not name `/story`, but the Goal says no skill
  prompts for its own scripts. Moving the gate call before the draft, keeping a settings rule for it, or accepting
  the prompt changes `/story` or this spec's scope; the maintainer chooses.
