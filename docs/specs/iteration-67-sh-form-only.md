# Iteration 67: the skills, the agents and the README name the bash form of every script only

Status: draft, awaiting approval (#364)

Story #364, epic #337 (fast verification loop): step 3 of the migration outline of decision record 0004 (step 1 was
iteration 64, #361; step 2 is iteration 65, #363; step 4 is #365). Every line of a skill and of the README that
tells a user or the model how to run a plugin script names the bash form only: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"`,
`--long` flags, no `powershell -NoProfile ...` alternative, no `.ps1` name, no PowerShell-style parameter.
`/nightmill:init` writes the allow rules of its five scripts in the bash form only (5 rules instead of 10). Every
`.ps1` file, `hooks/hooks.json`, `hooks/panel.tsx` and every file under `scripts/` stay byte for byte, so a project's
`.ps1` allow rules and hand-wired `.ps1` hooks keep working in this release. The lint gets a rule that keeps the `.sh`
form the only one named. Changes `skills/check/SKILL.md`, `skills/control/SKILL.md`, `skills/fix/SKILL.md`,
`skills/init/SKILL.md`, `skills/models/SKILL.md`, `skills/next/SKILL.md`, `skills/spec/SKILL.md`,
`skills/status/SKILL.md`, `skills/story/SKILL.md`, `skills/workflow/SKILL.md`, `README.md`, `CHANGELOG.md`,
`tests/lint.sh`, `tests/smoke-check.sh` and the bash tests that pin the old wording (Tests). No file under `agents/`
changes (Facts).

## Story trigger and manual check

**Not a story trigger.** *Status flow*: no status and no decision record changes. *Config key*: none is added, renamed
or removed; `verification.platform` keeps the meaning iteration 65 gives it (question 8 of `/nightmill:init` only
says it). *Slot marker*: no script changes, so no marker changes. **Compatible** holds: no config key or marker
changes, and the previous version's `.ps1` allow rules stay in a project's settings and still match the shipped
`.ps1` files.

**The manual check applies**: `verification.manualCheckPaths` is `skills`, `agents`, `hooks`, and ten files under
`skills/` change (none under `agents/` or `hooks/`). Its steps are under Tests.

**Shells.** No script changes. The changed tests are bash only (`tests/lint.sh`, `tests/smoke-check.sh` and the
`tests/test-*.sh` of Tests); no `.ps1` file changes (iteration 65 freezes them). The PowerShell smoke tests keep
running in CI's PowerShell parts unchanged, which is the evidence that the `.ps1` scripts and hooks still work.

**Depends on #363.** The new question 8 text (decision 4) states iteration 65's meaning of `windows`. Before step 1 of
`/next`, the implementer checks that `schema/nightmill.schema.json` on `origin/main` contains
`windows runs the bash tests in Git Bash` (iteration 65 decision 4). When it does not, it changes nothing and returns
`failed` with the line `#363's meaning of verification.platform is not on main; #364 waits for it.`

**Auto-merge.** The pull request changes no path under `.claude/` or `.github/` and is no story trigger, so it is
auto-merged once the manual check is done in full (both platforms). When the Linux/macOS step cannot be run by the
session (no Linux or macOS machine and no WSL), the pull request says so in "How verified", the step is left to the
maintainer, and auto-merge is withheld ("skipped a required manual check").

## Facts this rests on

Measured on `spec/67-sh-form-only` at 5da00ec (equal to `main`) on 2026-11-25, with `grep -rnE` over `skills`,
`agents`, `README.md`, `hooks/hooks.json`, and a scratch copy of the tree (outside the repository) in which every
PowerShell form of the skills and of the README before `## Developing nightmill` was replaced by sed with its bash
form and `tests/lint.sh` was run; it was stopped after `== the PowerShell job runs in parts` (the later sections
read CI and the check, not the skills), and the doc tests were found by
`grep -nE '\.ps1|owershell|-Take|-Capacity|-Report|-Base' tests/test-*.sh` instead of being run. Tests lists the
pins found.

- **`.ps1` lines**: 35 lines of `skills/*/SKILL.md` name a `.ps1` (record 0004's number holds): check 1, control 2,
  fix 8, init 6, models 1, next 7, spec 3, status 1, story 1, workflow 5. `agents/*.md`: 0. `README.md`: 60 lines,
  38 of them before `## Developing nightmill` (line 1085).
- **Lines that change in the skills** (any of `.ps1`, `PowerShell`/`powershell`, a PowerShell-style parameter
  matched case-sensitively by ``(^|[ `(/])-[A-Z][a-z]+``, "of the shell in use", "either shell"): 71 lines: check 1,
  control 3, fix 15, init 14, models 2, next 17, spec 4, status 4, story 1, workflow 10. The parameter pattern has no
  other hit in `skills/` or `agents/` (`git -C` and `-label:` do not match it).
- **Agents**: the only hit is `agents/worker.md` line 5, `tools: Read, Grep, Glob, Write, Edit, Bash, PowerShell`,
  the PowerShell *tool*, not a script form; README line 363 and `tests/lint.sh` pin that line. It stays.
- **README, before `## Developing nightmill`**: 63 lines with a `.ps1`, `powershell -` or a PowerShell-style parameter
  (the "What is in the plugin" table rows 49 to 64, "The run permissions" line 155, "The guard" line 198 and 217,
  "The template board" line 236, "Why slots" and its subsections, "Changing the numbers", "Is the machine used
  well?", "Room for one more agent", "Adjusting the limit", "Running unattended", "The driver" line 960, "Limits and
  the kill switch" line 998, the `validate-config` line 492, and the hook paragraph lines 92 to 99). Prose that names
  PowerShell without a script form: lines 97, 199, 358, 363 (Claude Code's PowerShell tool and hook shell), 530, 537,
  717, 998 (a `.ps1` behaviour or a PowerShell command), and line 679, which says the pane runs `scripts/panel.ps1` on
  Windows: true, because `hooks/panel.tsx` line 125 starts `powershell ... panel.ps1` on Windows.
- **README, `## Developing nightmill`**: the 19 `powershell -ExecutionPolicy Bypass -File tests/smoke-*.ps1` lines,
  the PowerShell CI parts and `check.ps1 -Summary` describe tests that still run until #365 (and `tests/check.ps1`
  stays after it, record 0004 step 4). Script forms there: "Releasing" lines 1179, 1182, 1183
  (`scripts/release.ps1 -Version X.Y.Z`, `-Publish`, `-DryRun`).
- **`/nightmill:init` Run permissions** (`skills/init/SKILL.md` lines 267 to 271): "D. The scripts, 10 rules", for
  `slot`, `room`, `gate`, `validate-config`, `status`, `Bash(bash "<P>/scripts/<name>.sh" *)` and
  `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/<name>.ps1" *)`; "Count. `26 + 21 ×
  worktrees.slots` rules ... 68 rules for 2 slots, 110 for 4" (line 275); README line 157 says the same (68 for 2
  slots). Detect: a line is **exists** when all rules are present (string equality); entries are never removed.
- **Hooks**: `hooks/hooks.json` runs only `bash ".../session-start.sh"` and `bash ".../guard.sh"`; its matcher
  `Bash|PowerShell` is the tool name. README lines 97 to 99 and 217 to 218 document wiring `session-start.ps1` and
  `guard.ps1` by hand.
- **Templates outside the story**: `templates/CLAUDE.snippet.md` line 7 (`slot.ps1` / `slot.sh`) and
  `templates/workflows/nightmill-drive.yml` (runs `drive.ps1` on Windows) also name `.ps1` (Left).

## Decisions

**1. One rule per kind of line in the skills.** Every flag becomes its bash spelling (`--take`, `--release`,
`--abandon`, `--status`, `--report`, `--slot`, `--skill`, `--role`, `--capacity`, `--porcelain`, `--slot-count`,
`--since`, `--issue`, `--turns`, `--base`, `--config`, `--force`, `--all`, `--json`), as the bash form already
written beside it says.

| Kind | Today (example) | Becomes |
|---|---|---|
| K1 a call given in both shells | `` `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"` or `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/gate.ps1"` `` (either order, with or without `(PowerShell)`/`(bash)`/`(bash: ...)`) | the bash call alone, without a shell label: `` `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"` `` |
| K2 a two-bullet list "PowerShell (Windows): ... / bash: ..." (control, models, status) | `Run the script of the shell in use, ... and wait for it:` plus two bullets | `Run the script from inside the project (any checkout or worktree), and wait for it:` plus one line `` `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"` `` (control keeps "(it measures for ...)") |
| K3 a short form in both shells | `` `slot.ps1 -Capacity -Porcelain` or `slot.sh --capacity --porcelain` ``; `` `slot.ps1 -Take` / `slot.sh --take` `` | the `.sh` form alone: `` `slot.sh --capacity --porcelain` ``, `` `slot.sh --take` `` |
| K4 a PowerShell parameter in prose | `` `--take <branch>` (`-Take <branch>`) ``, `(PowerShell: -Slot, -Skill, -Role)`, `--report / -Report`, `` `-Release N` ``, `slot --abandon <s> (-Abandon <s>)`, `` (`-Force` / `--force`) ``, ``(`-Since <n>`, `--since <n>`)`` | the bash flag alone; a sentence that named only the PowerShell flag (workflow lines 376 to 378, 380, 392; next line 74; fix line 47) takes the bash flag |
| K5 "of the shell in use" | `Run validate-config of the shell in use`, `A report is one call of the shell in use`, `<the report command of the shell in use, ...>` | the words "of the shell in use" go; `A report is one call`, `<the report command, ...>` |
| K6 prose that compares the shells | `(git alone, the same in bash and PowerShell; its exit code` and `no shell redirection is used, so the bytes are the same in bash and PowerShell.` (next 515, 545; fix 548, 578) | `(git alone; its exit code` and `no shell redirection is used, so the bytes do not depend on the shell.` |
| K7 a file pair | `` `scripts/render-templates.ps1` / `.sh` ``, `` (`scripts/gate.sh`, `scripts/gate.ps1`) ``, ``scripts are at `.../slot.ps1` and `.../slot.sh` `` | `` `scripts/render-templates.sh` ``, `` (`scripts/gate.sh`) ``, ``the script is at `${CLAUDE_PLUGIN_ROOT}/scripts/slot.sh` `` |
| K8 a PowerShell command for detection (init lines 40, 42) | `(PowerShell: (Get-CimInstance ...).TotalPhysicalMemory; bash: /proc/meminfo or sysctl hw.memsize)`; `..., or $env:OS -eq 'Windows_NT' in PowerShell` | `(/proc/meminfo, also in Git Bash, or sysctl hw.memsize)`; the PowerShell clause goes |

`skills/init/SKILL.md` line 21: "Every step uses `gh` and `git` alone, so it works in either shell." becomes "Every
step uses `gh`, `git` and the plugin's bash scripts." The words of the skills' other rules stay.

**2. `/nightmill:init`'s Run permissions write the bash form only.** In `skills/init/SKILL.md`:

- D becomes: `- **D. The scripts**, 5 rules, for <name> in slot, room, gate, validate-config, status:`
  `` `Bash(bash "<P>/scripts/<name>.sh" *)`. `` followed by the rest of the bullet unchanged ("Other scripts get no
  rule. The folder holds the version, ...", the `kept: <k> script rules for another plugin folder` line).
- Count becomes: ``- **Count.** `21 + 21 × worktrees.slots` rules and one directory: 63 rules for 2 slots, 105 for 4.``
- `<R>` is "resolved the way the slot script does it" and "in the form the script prints (`/c/...` under Git Bash,
  `/...` elsewhere)"; the `PowerShell: C:\...` alternative goes; "a backslash (in the bash form)" becomes "a
  backslash".
- **A project that already has `.ps1` rules keeps working**: Detect is unchanged (string equality, `exists` when all
  rules of A to E are present), and the `.ps1` rules are not among them, so a project with both forms reports
  `exists` and nothing is added or removed; its `.ps1` rules stay and still match the shipped `.ps1` files. After an
  upgrade the rules of the old folder, `.ps1` ones included, are kept and counted in `kept: <k> script rules for
  another plugin folder`, as today. `/nightmill:init` never removes a rule.
- README "The run permissions": "in the bash and the PowerShell form," becomes "in the bash form,", and
  ``That makes `26 + 21 × worktrees.slots` rules (68 for 2 slots)`` becomes ``That makes `21 + 21 × worktrees.slots`
  rules (63 for 2 slots)``.

**3. The README.** Before `## Developing nightmill`:

- Every `.ps1` name, `powershell` call line and PowerShell-style parameter goes by the kinds of decision 1: each row
  of "What is in the plugin" names `scripts/<x>.sh` only, with bash flags (the slot row: `--take <branch>`,
  `--release N`, `--abandon N`, `--reap`, `--status`, `--capacity`, `--report <step>`); a code block with a `.ps1`
  line and a bash line keeps only the bash line (lines 595, 632, 687 to 689, 707, 738, 758, 960); a pair of a bash
  and a PowerShell form keeps the bash one (`-Abandon N` (`--abandon N`) becomes `--abandon N`; `slot -Status`
  becomes `slot --status`; the template-board pair of line 236 becomes `scripts/template-board.sh --config <file>`).
- Line 76 ("The bash scripts need nothing beyond bash ...") becomes: "The scripts are bash and need nothing beyond bash
  and the tools a POSIX shell has (awk, sed, grep); on Windows that is Git Bash, from Git for Windows."
- **The hook wiring**: lines 97 to 99 end "the hook does nothing and says nothing; install Git for Windows to run it."
  (the sentence on `scripts/session-start.ps1` goes); line 217 to 218 "A PowerShell-only machine has the deny rules
  only; install Git for Windows to run the guard." (the sentence on `scripts/guard.ps1` goes); line 198
  "`scripts/guard.sh` (twin `scripts/guard.ps1`)" becomes "`scripts/guard.sh`". The `.ps1` hooks keep working where
  they were wired (decision 5) but are no longer documented as a way.
- Prose on a `.ps1` behaviour goes: line 530 "(its number was reused, or it is the PowerShell console a stopped take
  ran in)" becomes "(its number was reused)"; lines 536 to 538 keep only the bash wording, ending "(exit 130, or 143
  for TERM)"; line 717 drops "`Win32_PerfRawData_PerfOS_Processor` and `Win32_OperatingSystem` in PowerShell on
  Windows,"; line 998 drops "(PowerShell: `New-Item .git/nightmill-stop`)".
- Stay: lines 199, 358, 363 (the PowerShell tool), 97's "where Claude Code runs hooks through PowerShell only", and
  line 679 ("On Windows the pane runs `scripts/panel.ps1` with Windows PowerShell, ..."), which stays true while
  `hooks/panel.tsx` is unchanged (Not done).

In `## Developing nightmill`: "Releasing" drops the parentheses "(or `scripts/release.ps1 -Version X.Y.Z`)",
"(`-Publish`)" and "(`-DryRun`)". The PowerShell test lines, the CI parts and `check.ps1 -Summary` stay (they describe tests that still
run). Iteration 65's `verification.platform` sentences stay as #363 leaves them.

**4. Question 8 of `/nightmill:init`** (line 56) becomes exactly:

```
8. **platform** (`verification.platform`): `windows` (the check runs the bash tests in Git Bash, from Git for Windows) or `unix` for Linux and macOS (the bash tests); `all` runs the bash and the PowerShell tests, for a project worked on from both; read only by a check command that reads it. An empty answer deletes the key, and the check then runs both families
```

It agrees with iteration 65 decision 4 (the schema description). Line 42's detection loses only its PowerShell clause
(decision 1, K8); the values it proposes are unchanged.

**5. What stays shipped and working.** No file under `scripts/` or `hooks/`, and no `.ps1` file anywhere, changes or is
removed. A project's `.ps1` allow rules match the same `.ps1` paths; a hand-wired
`powershell ... session-start.ps1` or `guard.ps1` hook runs the same file. This is the release before #365.

**6. The lint keeps the `.sh` form the only one named.** A new section of `tests/lint.sh`,
`== the skills, the agents and the README name the .sh form only (#364)`, reads each line `<n>` of:

- every `skills/*/SKILL.md` and `agents/*.md`: a line fails when it contains `.ps1`, or `powershell` (lower case,
  the command), or the word `PowerShell` other than in `PowerShell tests` (question 8, decision 4) and other than on
  an `agents/*.md` frontmatter line that begins `tools:`, or a match of the extended regex ``(^|[ `(/])-[A-Z][a-z]+``
  (case-sensitive);
- `README.md`, the lines before the first line `## Developing nightmill`: a line fails when it contains `.ps1` or
  `powershell -` or a match of that regex; the one line that begins ``On Windows the pane runs `scripts/panel.ps1` ``
  is exempt (until #365);
- `README.md`, the lines from `## Developing nightmill` on: a line fails when it contains `scripts/<x>.ps1` or a bare
  `<x>.ps1` (preceded by a space, a backtick or `(`) for which `scripts/<x>.ps1` exists in the tree.

Each failure prints exactly
`FAIL: <file>:<n> names the PowerShell form of a script (<the first match>); name the .sh form only (#364)`.
Plus, in `== init installs the run permissions`: `skills/init/SKILL.md` contains no `Bash(powershell`, else
`FAIL: skills/init/SKILL.md writes a PowerShell allow rule; init writes the bash form only (#364)`. The existing
check "every script call is one of the two forms the rules match" accepts only `bash "...sh"` (its PowerShell case
goes; a `powershell ... .ps1"` match prints the existing `is not the one script form` line), and its comment says
"the one form".

**7. Tests that pin the old wording change with it** (measured, Tests "Pinned wording"): each pin of a PowerShell form
in a skill or the README is replaced by the pin of its bash form, or dropped where the bash form is already pinned
beside it. Pins of `.ps1` files themselves (`scripts/*.ps1`, `tests/*.ps1`, `hooks/panel.tsx`, `ci.yml`,
`tests/check.sh`) stay.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | The skills, the agents and the README name the `.sh` form only | Decisions 1, 3, 6, 7; Facts (agents) |
| 2 | `/nightmill:init` writes allow rules for the bash form only | Decision 2 (and 4 for its question 8) |
| 3 | The `.ps1` files still ship, and a project's existing `.ps1` allow rules and hand-wired `.ps1` hooks keep working | Decisions 2 (Detect) and 5 |
| 4 | The changelog says that a Windows session without Git Bash must install Git for Windows, and that this release comes before the removal of the `.ps1` files | Files touched (the bullet) |
| 5 | The check stays green, and the manual check for skills is done | Tests (manual check); Story trigger and manual check |

## Tests

- Criterion 1: **`tests/lint.sh`**, the section of decision 6, passes on the branch. **`tests/smoke-check.sh`** gains
  four `lint_break` lines (bash only):
  - `lint_break shskill skills/status/SKILL.md 's#bash "\${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"#powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/status.ps1"#' 'names the PowerShell form of a script'`
  - `lint_break shflag skills/workflow/SKILL.md 's/--capacity --porcelain/-Capacity -Porcelain/' 'names the PowerShell form of a script (-Capacity'`
  - `lint_break shreadme README.md 's#bash scripts/load.sh \[--porcelain\]#scripts/load.ps1 [-Porcelain]#' 'README.md:'` (and its output contains `names the PowerShell form of a script`)
  - `lint_break shdev README.md 's#^`main` only takes pull requests, so a release has two steps.#& Or `scripts/release.ps1`.#' 'names the PowerShell form of a script (scripts/release.ps1)'`

  and one that passes: `agents/worker.md` with its `tools:` line unchanged and README with the pane line give no
  `FAIL` (the repository as it is). The code reviewer checks the prose of decision 3 that the lint does not see.
- Criterion 2: **`tests/lint.sh`** `== init installs the run permissions`: the item list holds
  `Bash(bash "<P>/scripts/<name>.sh" *)`, `5 rules` and `21 + 21`, and not the PowerShell rule (decision 6);
  **`tests/test-limits-docs.sh`** line 140 pins `21 + 21` instead of `26 + 21`. `tests/smoke-check.sh` gains
  `lint_break initps skills/init/SKILL.md 's#`Bash(bash "<P>/scripts/<name>.sh" \*)`\.#&\n    `Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/<name>.ps1" *)`#' 'writes a PowerShell allow rule'`.
  The rules init actually writes are seen in the manual check.
- Criterion 3: the code reviewer checks that `git diff --name-only origin/main...` lists no `.ps1` file and nothing
  under `scripts/` or `hooks/`; the PowerShell CI parts (`smoke-hook.ps1`, `smoke-guard.ps1`, `smoke-slot.ps1` and the
  rest) stay green on the pull request's run, unchanged; Detect's text is unchanged (the existing lint words
  `**exists** when all are present`, `string equality`).
- Criterion 4: the code reviewer checks the bullet word for word against Files touched.
- Criterion 5: `bash tests/check.sh` is green on the branch (its last line, the `Times:` total and the `SKIPPED:`
  lines in "How verified"), and the manual check below.
- **Pinned wording** (they fail when the PowerShell forms go, and change by decision 7; the implementer re-runs the
  scratch probe of Facts to confirm the list is complete, and any further pin it finds changes the same way):
  - `tests/lint.sh` (each failed in the probe): the run permissions item list (line 487); README `-Reap` (686, keep
    `--reap`); `-Capacity -Porcelain` in the workflow skill (699 to 704, keep `--capacity --porcelain`); README
    `-Capacity` (710); `-Report` in next and fix (731); `-Json` in the status skill (786, keep `--json`);
    `scripts/room.ps1` in the workflow skill (1086); `scripts/control.ps1` in the control skill (1157). Also the
    one-form check (531, decision 6). The README pins of `history.ps1`, `load.ps1`, `room.ps1`, `control.ps1`,
    `dashboard.ps1` (783, 1040, 1097, 1164, 1208) did not fail: the `tests/smoke-<x>.ps1` lines of Developing
    nightmill satisfy them; they stay. README `panel.ps1` (1254) stays (the pane line).
  - `tests/test-script-modes.sh` (b): only `bash "` may stand before a quoted plugin script; its message becomes
    `runs a plugin script without bash " in front`.
  - `tests/test-config-from-base.sh` line 79: `validate-config.sh" --base` instead of `validate-config.ps1" -Base`.
  - `tests/test-limits-docs.sh`: line 116 drops `scripts/gate.ps1`; line 131 (`no PowerShell call of gate.ps1`)
    becomes the absence check `skills/$sk/SKILL.md: still names gate.ps1`; line 166 pins
    ``| `scripts/gate.sh` |``; line 140 as above. Line 168 (`tests/smoke-gate.ps1` in Developing) stays.
  - `tests/test-docs-low-gaps.sh` (a), line 44: each script row of "What is in the plugin" names `scripts/<s>.sh`
    (`does not name scripts/$s.sh`).
  - `tests/test-drive-docs.sh` line 127 pins ``| `scripts/drive.sh` |``; line 119's README words drop
    `scripts/drive.ps1`. Line 94 (the workflow template) stays.
  - `tests/test-interrupt-docs.sh` lines 52 and 53 pin the README sentences in their bash form
    (`... it leaves the claim, and --abandon N frees it.`, `... leaves a claim that slot --status shows as ended;
    --abandon N frees it.`); its pins of `scripts/slot.ps1`'s header stay.
  - `tests/test-unattended-docs.sh` line 157 drops `-Abandon N`.
- **The manual check** (the session, step 4 of `/next`), with a separate checkout of the branch loaded by
  `claude --plugin-dir <checkout>` in a test project that is not this repository (never `--plugin-dir .`):
  1. Windows with Git for Windows: run `/nightmill:status`, `/nightmill:models`, `/nightmill:control` (in `off` or
     `suggest` mode, so it changes nothing) and `/nightmill:check`; each tool call runs `bash ".../scripts/<x>.sh"`
     and none runs `powershell`.
  2. Windows: `/nightmill:init` in a project without `.claude/nightmill.json`, up to the plan, and decline at the
     confirmation: the Run permissions text holds 5 script rules, all `Bash(bash "<P>/scripts/<name>.sh" *)`, and the
     count 63 for 2 slots; question 8 reads as decision 4.
  3. Windows: in a project whose `.claude/settings.local.json` holds both forms of the five script rules of this
     folder (and all of A to E), `/nightmill:init`'s Run permissions line says `exists`; with a hand-wired
     `SessionStart` hook `powershell -NoProfile -ExecutionPolicy Bypass -File "<P>/scripts/session-start.ps1"` in a
     project without a config, a new session prints the hint.
  4. Linux or macOS (or WSL): steps 1 and 2 (the plan shows `/...` paths).
  The steps and what each showed go into "How verified"; a step that could not be run is named there (Story trigger
  and manual check, auto-merge).

## Files touched

- `skills/check/SKILL.md`, `skills/control/SKILL.md`, `skills/fix/SKILL.md`, `skills/models/SKILL.md`,
  `skills/next/SKILL.md`, `skills/spec/SKILL.md`, `skills/status/SKILL.md`, `skills/story/SKILL.md`,
  `skills/workflow/SKILL.md`: the lines of Facts, by decision 1.
- `skills/init/SKILL.md`: decision 1 (lines 16, 17, 21, 40, 42, 70, 155, 156, 160, 164), decision 2 (D, Count, `<R>`),
  decision 4 (question 8).
- `README.md`: decisions 2 and 3.
- `tests/lint.sh`: the section of decision 6 and the pins of decision 7.
- `tests/smoke-check.sh`: the five `lint_break` lines.
- `tests/test-script-modes.sh`, `tests/test-config-from-base.sh`, `tests/test-limits-docs.sh`,
  `tests/test-docs-low-gaps.sh`, `tests/test-drive-docs.sh`, `tests/test-interrupt-docs.sh`,
  `tests/test-unattended-docs.sh`: the pins of Tests.
- `CHANGELOG.md`, one bullet under `Unreleased`:

  ```
  - Iteration 67 (#364): the skills and the README name the bash form of every script only (decision record 0004,
    step 3), and /nightmill:init writes the allow rules of its five scripts in the bash form only (21 + 21 ×
    worktrees.slots rules). The .ps1 files still ship and work in this release: a project's existing .ps1 allow rules
    stay and still match, and a hand-wired session-start.ps1 or guard.ps1 hook keeps running. A Windows session
    without Git Bash can no longer run the skills' scripts and must install Git for Windows (which brings Git Bash).
    This release comes before the one that removes the .ps1 files (#365): move a hand-wired .ps1 hook to the .sh form,
    or pin this release until you have. No config key.
  ```

Not touched: `agents/`, `hooks/`, `scripts/`, every `.ps1` file, `templates/`, `schema/`, `.claude/`, `.github/`,
`docs/decisions/`.

## Risks

- **Parallel work.** `skills/workflow/SKILL.md` is in `parallel.hotFiles` and changes here, so this task stays alone
  on it; `schema/nightmill.schema.json` and `scripts/slot.*` do not change. `parallel.doNotPair` forbids pairing with
  a task that changes the slot scripts or the schema; this one changes neither, but its PR conflicts with any other
  open change to the skills' call lines.
- **Iteration 65 not merged in full.** Question 8 would state a meaning the check does not have; the precondition of
  Story trigger and manual check stops the run before any change.
- **A Windows session without Git Bash** loses the scripts the skills call (the `.ps1` forms are no longer offered).
  The changelog says so; such a session already lacked the hooks and the injected config.
- **A missed pin or a missed line.** The lint rule fails on any form left in the skills or the user part of the
  README; the scratch probe finds pins in tests.
- **Wording drift in long skills** (`next`, `fix` are about 1000 lines): only the lines of Facts change; the code
  reviewer compares `git diff` line by line against decision 1.

## Size estimate

`M`: about 230 changed lines. Skills 71 lines, README about 75, `tests/lint.sh` about 45, the other tests about 25,
`tests/smoke-check.sh` 6, CHANGELOG 8.

## Not done

- Removing any `.ps1` file, PowerShell test, check step or CI part (#365); `tests/check.ps1` stays.
- Changing `hooks/hooks.json`, `hooks/panel.tsx` (it still runs `panel.ps1` on Windows, so README line 679 stays),
  any script, a config key, the schema, or `verification.platform`.
- Removing `.ps1` allow rules from a project's settings, or any init step that removes a rule.
- The PowerShell tool in `agents/worker.md` and the hook matcher `Bash|PowerShell`.
- `templates/CLAUDE.snippet.md`, `templates/workflows/nightmill-drive.yml`, `.claude/CLAUDE.md`, `CONTRIBUTING.md`.

## Left

1. **`.claude/CLAUDE.md`'s Commands block.** Iteration 65 decision 2 says its `.ps1` call lines stay "(#364)", but
   #364 names only the skills, the agents and the README, and a change under `.claude/` would withhold auto-merge.
   This spec leaves it (its `scripts/render-templates.ps1` line and the `release.ps1` mention of "CHANGELOG by
   version"); the maintainer adds it here or to #365.
2. **Two templates name `.ps1`**: `templates/CLAUDE.snippet.md` (copied into a project's CLAUDE.md by
   `/nightmill:init`: "`slot.ps1` / `slot.sh`") and `templates/workflows/nightmill-drive.yml` (runs `drive.ps1` on a
   Windows runner). Out of the story's three places; #365 must change both when it removes the files. The maintainer
   may add the snippet line here.
