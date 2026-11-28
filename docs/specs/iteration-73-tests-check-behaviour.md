# Iteration 73: the lint and the tests it starts check contracts and behaviour, not the wording of skills and docs

Status: draft, awaiting approval (#344)

Story #344, epic #337 (fast verification loop). Many sections of `tests/lint.sh` and many tests it starts search a
skill, an agent, the README or a spec for an exact sentence. After this iteration a check that searches such text is
kept only when what it finds is a contract (decision 1); every other such check is removed. The tester, the code
reviewer and the spec reviewer are told that a test of a skill's wording is not a test of a criterion. The pull
request lists every check it kept and every check it removed, and shows the lint's time before and after. This
iteration covers the lint and the files it starts, plus `tests/test-interrupt-docs.sh`; the other check steps are a
proposed follow-up (decision 2, Left). Changes `tests/lint.sh`, `tests/test-config-from-base.sh`,
`tests/test-docs-low-gaps.sh`, `tests/test-drive-docs.sh`, `tests/test-extra-round.sh`, `tests/test-fast-lane.sh`,
`tests/test-limits-docs.sh`, `tests/test-security-model.sh`, `tests/test-skills-low-gaps.sh`,
`tests/test-spec-size-limit.sh`, `tests/test-unattended-docs.sh`, `tests/check.sh` (one step line, two map entries),
`agents/tester.md`, `agents/code-reviewer.md`, `agents/spec-reviewer.md` and `CHANGELOG.md`. It deletes
`tests/test-ci-job-name-rule.sh` and `tests/test-interrupt-docs.sh`. Where decision 3 removes a check, the
`lint_break` case in `tests/smoke-check.sh` or the case in another test that breaks only that check goes with it.

## Story trigger and manual check

**Not a story trigger.** No status, and no rule on who sets one, changes, and no decision record changes. No config key
is added, renamed or removed: the checks of the schema, the example and the README configuration table are kept
(decision 1 a). No script under `scripts/` changes, so the slot marker format does not change. **Compatible** holds: a
project reads nothing that changes. **Config-driven**: no project value is added.

**The manual check applies.** `agents/tester.md`, `agents/code-reviewer.md` and `agents/spec-reviewer.md` change
(path `agents`); its steps are under Tests. **Shells**: bash only (decision record 0004). No file under `scripts/` and
no `.ps1` file is added or changed. The steps involved are the lint (which starts every changed test file),
`tests/smoke-check.sh` (its lint copies) and `tests/check.sh` (its step list loses `test-interrupt-docs.sh`).

## Facts this rests on

Read and run on `spec/73-tests-check-behaviour` at 563ee99 (equal to `main`) on 2026-11-28, on Linux with 4 cores. The
local awk is mawk 1.3.4. With it the lint exits 1 with 5 `FAIL:` lines from `tests/test-guard-gql-keyword.sh`, which
are mawk's and not this story's. With busybox awk first on the PATH and `LC_ALL=C`, the lint passes.

- `tests/lint.sh` has 1965 lines and 74 lines `echo "== ..."` (sections). 167 of its lines use `grep -F` or `grep -qF`,
  and 170 lines name a skill, an agent, `README.md`, `CONTRIBUTING.md` or `CHANGELOG.md`. It starts 25 `tests/test-*.sh`
  files (listed in decision 3). Their headers say what they pin, for example "Pins on the text; the spec's 11 pins"
  (`tests/test-unattended-docs.sh`).
- **Lint time**: `/usr/bin/time -f %e bash tests/lint.sh`, two runs: 21.37 s and 20.76 s wall. One run with a timestamp
  on every output line gives 20.81 s. The slowest parts are the started CI tests: `the CI parts are well formed`
  4.24 s, `bug #374` 2.27 s, the CRLF case 1.64 s and `the final CI job writes the job times` 1.51 s, all kept. The
  sections and files that decision 3 thins or removes took 4.98 s in all, and that includes the contract checks they
  keep. So the gain is at most 5 s and most likely 1 to 3 s.
- `tests/smoke-check.sh` runs 38 `lint_break` cases. Each runs one section of the lint on a copy, not the whole lint.
  None of the cases breaks a check that decision 3 removes. The cases on `README.md` and the skills (`platformreadme`,
  `platforminit`, `mapskill`, `shskill`, `shflag`, `shreadme`, `initps`) all break kept items: a key, `check: AFFECTED`,
  or a script call form.
- `tests/test-ci-job-name-rule.sh` checks only that `docs/specs/iteration-55-ci-parallel-powershell.md` says "begins
  with" and that the lint holds that FAIL text. The rule itself is pinned by the `lint_break` case `cibegins`.
  `tests/test-interrupt-docs.sh` (step and map entries in `tests/check.sh` lines 140, 194 and 219) checks only sentences
  of the README and of the header comment of `scripts/slot.sh`.
- Readers that parse lines: `scripts/drive.sh` line 272 reads `^Stopped:`. `skills/spec/SKILL.md` line 112 matches a
  pull request whose body starts `Spec for #<issue>.`. `skills/next/SKILL.md` reads the maintainer's
  `Waiting for approval.` comment. `tests/check.sh` prints `check: QUICK` and `check: AFFECTED`, which the skills read.
  `scripts/control.sh` prints `control: next pass in`.
- Iteration 71 (`docs/specs/iteration-71-spec-size-limit.md`) put its pins in `tests/test-spec-size-limit.sh`. Its
  schema, example and validator cases are behaviour and contracts and are kept. Its sentence pins are removed here. No
  decision record requires a pin on wording.

## Decisions

1. **The rule.** A check *matches prose* when it searches the text of a skill (`skills/*/SKILL.md`), an agent
   (`agents/*.md`), `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `.claude/CLAUDE.md`, a file under
   `docs/`, or a description in `schema/nightmill.schema.json`. The search can look for a string (present or absent),
   count it, or look for it in a named section. Checks on the code of scripts and hooks, on `.github/workflows/`, on
   JSON values and on `tests/` are not prose checks; this iteration leaves them as they are. A prose check is **kept**
   only when the string it finds is one of these:
   - (a) **a config key** or key path, or a value the schema defines (an enum value, a default, the invariant text of
     `.claude/nightmill.json`), including a row of the README's configuration table;
   - (b) **a command**: a script, CLI or API call with the flags or arguments it runs with (`gh pr merge`,
     `--capacity --porcelain`, `createProjectV2View`, `/nightmill:status`). Also counted here: a permission rule
     (`Bash(git add *)`, `Edit(**)`), a frontmatter field that Claude Code reads (`name`, `tools`, `model`,
     `allowed-tools`, `disable-model-invocation`), an agent type (`nightmill:tester`) and an environment variable
     (`WORKER_SLOTS`);
   - (c) **a file name** or path (`agents/tester.md`, `.claude/settings.local.json`, `ledger.tsv`);
   - (d) **a parsed line**: a line, a line prefix or a block format that a script, a skill, Claude Code or GitHub reads
     from output, a file, an issue or a pull request. Examples: the result blocks of the agents
     (`Result: complete | partial | failed` and its field names), the findings block, `Test paths:`, `check: QUICK`,
     `Spec for #<issue>.`, `Waiting for approval.`, `Split proposed for #<issue>:`, the `test: ` prefix, a step name
     passed to `--report`, `Closes #`, and the `id:` of an issue form field. For a `Stopped:` line only the prefix
     `Stopped: ` is parsed; the text after it is prose.

   Everything else is prose, and its check is **removed**: a sentence, phrase, word or heading that no reader parses;
   the order or numbering of steps or questions; how often a phrase occurs; the absence of an old sentence; a number
   written in prose (`one per 8 GB`, `21 + 21`); the wording of a spec, a decision record or a CHANGELOG bullet. A kept
   item searches the whole file, not a named section, unless a reader parses that section. A kept item of kind (d)
   names its reader as `<file>:<line>` in the list of decision 6. An item whose reader cannot be named is prose.
2. **What this iteration covers.** All 74 sections of `tests/lint.sh`, the 25 files it starts, and
   `tests/test-interrupt-docs.sh` (a check step, named by the story's pattern `tests/test-*-docs.sh`). Two other groups
   are left to the stories proposed under Left: the other check steps that read skills or docs, and the checks on the
   code of scripts. **Criteria 1 and 2 are therefore met only in part**, as decision 11 of iteration 70 handled its
   criterion 3: the 14 check steps and the smoke reads named in the last row of decision 3 are in the list, marked
   `deferred`, with no verdict. Whether that part may wait for the follow-up story is for the maintainer to accept or
   refuse at the approval of this spec; this spec does not claim it accepted. Refused, the deferred row is judged by
   decisions 1 and 3 in this iteration instead.
3. **The verdicts.** K: kept as it is. S: the contract items named stay, the other prose items go. R: removed. A
   section or file whose checks all go is deleted with its `echo`, its comment, its start line in the lint, and its step
   line and map entries in `tests/check.sh`. A comment of the form "the lint pins the wording ...; the manual check does
   the behaviour" goes with its pins.

   | # | Lint section or file | Protects | Verdict: what stays |
   |---|---|---|---|
   | 1 | specs follow the template | spec form | K |
   | 2-4 | forbidden words, json, skills | Generic, JSON, frontmatter | K |
   | 5 | spec and next stay split | /spec and /next split | R |
   | 6 | init skill keeps the install-chat steps | /init steps | S: `validate-config`, `createProjectV2View`, `updateProjectV2View`, `BOARD_LAYOUT`, `updateProjectV2Field`, `gh label create`, `gh project link`, `workflows(first`, `projects/<n>/workflows` |
   | 7 | session-start hook is wired | hooks.json | K |
   | 8 | contributor files are wired | CONTRIBUTING, forms | S: CONTRIBUTING's `tests/check.sh`, `--plugin-dir`, `SECURITY.md`; the forms' `name:`, `body:`, field ids; the PR template |
   | 9-13 | release metadata, config validates, reviewer pairing, schema keywords, roles and models | versions, validator, schema, key names in README | K |
   | 14 | agent roles are defined in the workflow skill | roles section | S: each schema role as `` `<role>` ``, `roles.<role>.model`, `properties.roles.properties.R.properties.model`, `schema/nightmill.schema.json`, the worker's model |
   | 15 | status is wired | /status read-only | K |
   | 16 | template board is wired | template board | S: all but `field by field` and `The template board` |
   | 17 | models is wired | /models | K |
   | 18 | init installs the edit permission | Edit rule | S: `Edit(**)`, `.claude/settings.local.json`, `git check-ignore`, no `Edit(/**)`, README `Edit(**)` and the file |
   | 19 | init installs the run permissions | run rules | S: every `Bash(...)` and `Edit(//` rule, `/slot-*/**`, `additionalDirectories`, `permissions.additionalDirectories`, `.claude/settings.json`, the `git rev-parse` command, no broad or PowerShell rule, the slot git cross-check, the one script form, the command forms of spec/next/fix, the injections' `allowed-tools`, README `additionalDirectories` |
   | 20 | /next and /fix hand the coding to a subagent | producer launch | S: `roles.<role>.model`, `parallel.maxAgents`, `Result: complete \| partial \| failed`, `gh pr merge`, `Cause:`, `Fix:`, `Test:`, the agent-file list, lines with a reader (1 d) |
   | 21 | /spec hands the writing to a subagent | writer launch | S: `roles.specWriter.model`, `parallel.maxAgents`, `Result: ...`, `gh pr merge`, `Spec for #`, no `Closes #` |
   | 22 | a separate code reviewer reviews the change | reviewer | S: name, tools, model, the findings format in the three files, `review.maxFixRounds`, `validate-config`, `nightmill:code-reviewer`, `roles.codeReviewer.model` |
   | 23 | the review is recorded in the pull request | Review section | S: the lines of the `## Review` format that have a reader (1 d) |
   | 24, 28 | slots free themselves, history is wired | slot reap, history | K |
   | 25 | capacity is wired | live limit | S: all but the absence of ``At `parallel.maxAgents` wait`` |
   | 26 | slots report what their agent does | report | S: all but README `**running**`, `**stalled**`, `**unknown**` |
   | 27 | the stage record is wired | ledger | S: all but README `ci-and-merge`, `not-reported` |
   | 29 | a tester writes the failing tests first | tester in /next | S: name, tools, model, the result-block fields, the `Test paths:` equality, `nightmill:tester`, `roles.tester.model`, `verification.benchRule`, the git commands and `-m` messages, README `agents/tester.md` |
   | 30 | a tester reproduces the bug before /fix | tester in /fix | S: the `Test paths:` equality, `nightmill:tester`, `roles.tester.model`, `verification.benchRule`, the git commands, `write-tests` |
   | 31 | the tester's tests are guarded | tester files guard | S: the git commands, `dispute-<k>`, `Disputes:`, `Answers:`, `revised:`, `stands:`, the `-m` messages |
   | 32 | the code reviewer reviews the tests | test review | S: `` `test: ` ``, `test-finding-<k>` |
   | 33 | a separate spec reviewer reviews the spec | spec reviewer | S: name, tools, model, the findings format, `nightmill:spec-reviewer`, `roles.specReviewer.model`, `validate-config` |
   | 34 | the spec review is recorded in the spec pull request | spec Review section | S: `Waiting for approval.`, the `## Review` lines with a reader |
   | 35 | load is wired | load | S: all but init `one per <n> GB`, README `rate limits`, `token budget` |
   | 36 | room is wired | room | S: all but the workflow's `Stopped: no room...` text beyond the prefix and `never changes the agent limit...`, and the counts of `check the room on the machine` |
   | 37 | control is wired | control | S: all but README `The controller does not see` |
   | 38 | dashboard is wired | dashboard | S: all but README `Ctrl-C` |
   | 39 | slots pane is wired | pane | S: all but README `2.1.287` |
   | 40-45, 47-49 | temp files, longest first, every smoke script, the map, CI parts, job times, CI selects, README smoke files, agreement cost | check and CI | K |
   | 46 | the job-name rule says begins with | spec 55's wording | R: `tests/test-ci-job-name-rule.sh` is deleted; `cibegins` stays |
   | 50 | the .sh form only (#364) | script call form | S: the scan of skills, agents and README; the CHANGELOG phrases go |
   | 51 | text from issues is data | data rule | S: the `gh issue view ... --json` read step, no `comments` field, `gh api user --jq .login`, `lastEditedAt`, `Waiting for approval.` |
   | 52 | `tests/test-security-model.sh` | Security model docs | S: file names and links; the sentences go |
   | 53, 57, 60, 62 | `tests/test-guard-gql-keyword.sh`, `tests/test-story-invocable.sh`, `tests/test-warmup-interpreter.sh`, `tests/test-ci-smoke-bash-timeout.sh` | guard, frontmatter, warm-up, CI timeout | K; in section 62 the pin on the Facts of `docs/specs/iteration-48-config-from-base.md` goes |
   | 54 | `tests/test-unattended-docs.sh` | Running unattended | S: commands, flags and keys; the headings, their order and the sentences go |
   | 55 | `tests/test-drive-docs.sh` | driver docs | S: flags, keys, `templates/workflows/nightmill-drive.yml`, the README table rows of keys |
   | 56 | `tests/test-limits-docs.sh` | limits | S: keys, schema, example, gate commands, driver flags |
   | 58 | `tests/test-skills-low-gaps.sh` | #142 | S: (a), (b), (d); (c) goes |
   | 59 | `tests/test-docs-low-gaps.sh` | #143 | S: (a), (b), (c), (f); (d) and (e) go |
   | 61 | `tests/test-config-from-base.sh` | base config | S: the injection lines, `git.mergeFlags` rules, the `.claude/`/`.github/` rule as commands; the README sentences go |
   | 63-65 | least privilege, `/fix all` (64), bash files do not use jq | CI, /fix all, jq | 63 and 65 K; 64 S: `parallel.fixAllMaxBugs`, `parallel.hotFiles`, `parallel.doNotPair`, `git.mergeFlags`, `--abandon`, `--json headRefOid`, `--untracked-files=all`, schema, example, README `fixAllMaxBugs` |
   | 66-68 | `tests/test-extra-round.sh`, `tests/test-fast-lane.sh`, `tests/test-spec-size-limit.sh` | iterations 58, 63, 71 | S: schema, example, validator runs, README table rows, keys, commands, lines with a reader; the sentences go |
   | 69-71 | killed take, jq CRLF, driver leftover | bugs #373, #372, #374 | K |
   | 72 | the invariant is Bash only (#363) | invariant text | S: the config invariant and the two forms' label; the `**Bash only.**` and `**Two shells.**` checks of `.claude/CLAUDE.md` and `CONTRIBUTING.md` go |
   | 73 | no PowerShell script is left (#365) | no `.ps1` | S: `tests/test-no-powershell.sh`; the CHANGELOG bullet phrases go |
   | 74 | shell | syntax | K |
   | - | `tests/test-ci-job-times.sh`, `test-ci-parts.sh`, `test-ci-run-steps.sh`, `test-drive-leftover.sh`, `test-lint-agreement*.sh`, `test-slot-killed-take.sh`, `test-smoke-json-jq-crlf.sh`, `test-no-powershell.sh` | CI, behaviour, file names | K (a check in them that reads a spec's text goes by decision 1) |
   | - | `tests/test-interrupt-docs.sh` | interruption docs | R: deleted, with `add bash test-interrupt-docs.sh` and its two map entries |
   | - | the check steps `tests/test-board-listing.sh`, `test-changelog-coverage.sh`, `test-changelog-refs.sh`, `test-check-skill.sh`, `test-fix-pick.sh`, `test-guard-rules.sh`, `test-release-low-defects.sh`, `test-release-resume.sh`, `test-resume-stuck.sh`, `test-skill-config-fallback.sh`, `test-spec-template.sh`, `test-story-dedup.sh`, `test-watch-checks.sh`, `test-worker-merge.sh`; the skill and README reads in `tests/smoke-check.sh`, `tests/smoke-release.sh`, `tests/smoke-validate.sh` | board listing, changelog, /check, /fix pick, guard, release, resume, config fallback, spec template, story dedup, watch, worker merge, smoke inputs | deferred (decision 2, Left): unchanged |

   A row's "S: all but ..." keeps every other check of the section. When the table and decision 1 disagree on an
   item, decision 1 wins and the list says so.
4. **The agents' text**, exactly as below (line breaks follow the file's width).
   `agents/tester.md`, rule 2, directly after the sentence `A test checks the behaviour the criterion promises.`:

   ```
   A test that searches the text of a skill, an agent, the README or another document for a sentence, a phrase or a
   heading is not a test of a criterion: it breaks when the text is reworded and passes when the behaviour is wrong.
   Such a search tests only a contract: a config key, a command, a file name, or a line that a script or a skill
   parses. A criterion that only the text of a skill can show is reported as `not tested: only the manual check shows it`.
   ```

   `agents/code-reviewer.md`, at the end of rule 1:

   ```
   A test that only finds a sentence, a phrase or a heading in a skill, an agent or a document does not cover a
   criterion, unless what it finds is a contract (a config key, a command, a file name, or a line that a script or a
   skill parses).
   ```

   `agents/spec-reviewer.md`, point 1 becomes:

   ```
   1. every acceptance criterion of the issue is covered by a rule of the spec and is testable: the spec names the test or
      the manual scenario that protects it; a test that searches the wording of a skill, an agent or a document is not
      such a test unless what it finds is a contract (a config key, a command, a file name, or a line that a script or
      a skill parses);
   ```
5. **No new automated test.** A test that the three agents say these sentences would itself pin wording. The criteria
   are shown by the list (decision 6), the lint time (decision 7), a green check and the manual check.
6. **The list in the pull request.** The body has a section `## Prose checks` with two sub-sections,
   `### Kept as contract checks` and `### Removed`. Each has one line per item:
   `- <file> "<section or check>": <the pinned text, or what the check searches> — protects <what>; <kind a|b|c|d, and for d the reader <file>:<line>>`
   under Kept, and `... — protects <what>; prose: <why, one phrase>` under Removed. A third sub-section,
   `### Deferred`, has one line per file of the deferred row: `- <file> — protects <what>; deferred (#<follow-up>)`.
   Every row of decision 3 has at least one line. The implementer writes `## Prose checks` and `## Lint time` in its
   last message above its result block; the `/next` session puts them in the pull request body only, never in the code
   reviewer's prompt (iteration 18 decision 2: facts, not the implementer's account). The reviewer derives the kept and
   removed groups itself from the diff of `tests/lint.sh` and the test files against decision 3.
7. **The lint time.** On one machine, with the same awk both times: 5 runs of `bash tests/lint.sh` on the base commit
   and 5 on the branch's last commit, run one after another, with nothing else running. Each run's wall time is
   measured with `/usr/bin/time -f %e` (or bash `time`). The section `## Lint time` of the pull request gives the
   machine (OS, cores, awk), the two commits, the 10 times and the two medians. After the implementer returns, the
   `/next` session makes this measurement itself in the slot and adds it to that section as the session's; it gives the
   reviewer its 10 times and two medians as a fact. The criterion is met when the session's branch median is lower than
   its base median.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | A list names every test and lint section that matches prose, with what it protects | Decisions 1, 2, 3 (column Protects), 6. **Met in part** (decision 2): the deferred row is listed without a verdict, for the maintainer to accept at approval |
| 2 | Each is either kept as a contract check or removed; the pull request lists both groups | Decisions 1, 3, 6. **Met in part** (decision 2): the deferred row is neither kept nor removed here |
| 3 | The tester's and the reviewers' instructions say that a test of a skill's wording is not a test of a criterion | Decision 4 |
| 4 | The lint is faster after the change, shown by its time before and after | Decision 7 |

## Tests

No new test file (decision 5). No criterion has an automatic test; how each is carried through `/next`:

- **The tester** writes no file and reports `Result: partial` with every `Criteria` line `not tested`, which `/next`
  accepts: `1. ... -> not tested: a list in the pull request (decision 6)`, `2. ... -> not tested: a list in the pull
  request (decision 6)`, `3. ... -> not tested: only the manual check shows it`, `4. ... -> not tested: a measurement
  (decision 7)`.
- **The implementer** writes no test for them, although `skills/next/SKILL.md` line 452 asks for one: a test of agent
  wording or of the list would itself pin wording (decision 5). Its `Criteria` lines: `1 met in part (decision 2: the
  deferred row), no test (decision 5)`, `2 met in part (decision 2: the deferred row), no test (decision 5)`,
  `3 met, no test (decision 5; manual check)`, `4 met, no test (decision 7: medians <base> s and <branch> s)` (or
  `4 not met` when the branch's median is not lower). It reports `Result: partial`, with `Left:` naming the deferred
  row as the follow-up story of Left, no `unmet:` path and `Disputes: none`.
- **The code reviewer** would report a criterion with no test as blocking (`agents/code-reviewer.md` line 27). The
  `/next` session puts this paragraph at the end of the review prompt, with its own lint measurement (decision 7):

  ```
  Criteria 1 to 4 of this iteration have no automatic test by decision 5 of the spec, because a test of them would
  pin wording; do not report that under rule 1. Check criteria 1 and 2 against the diff of tests/lint.sh and the test
  files and decisions 1, 2 and 3: a check removed that decision 3 keeps, or a prose check kept that it removes, is a
  blocking finding. Check criterion 3 against decision 4 in the diff, and criterion 4 against this measurement by the
  session (decision 7): <machine; base and branch commits; the 10 times; the two medians>. A median that is not lower
  is a blocking finding.
  ```

  This paragraph, the session's lint measurement, and the departure from `skills/next/SKILL.md` line 452 above are
  one-off overrides by this spec for this iteration; no skill changes.
- **Auto-merge is off**: the result is `partial` and `agents/` changes need the manual check (step 7 of
  `skills/next/SKILL.md`). Criteria 1 and 2 are not ticked; step 8 files the deferred row as the follow-up story of
  Left, unless the maintainer has filed it. The lint and `bash tests/check.sh` stay green on the branch, which shows
  that every kept check still holds and that the remaining `lint_break` cases of `tests/smoke-check.sh` still fail on
  their broken copies.

**The manual check**, as `verification.manualCheckText` says. In a scratch project with a board, start
`claude --plugin-dir <a separate checkout of the feature branch>` (never `--plugin-dir .` in this repository).

1. Put an Approved story whose spec has the criterion "`/status` names a stalled slot" and whose Tests section names
   only a search of `skills/status/SKILL.md` for that sentence. Run `/next <n>`. The tester tests the behaviour (the
   script's output) or reports `not tested: only the manual check shows it`. It does not write a search of the skill's
   text.
2. In the same story's spec, Files touched gives the implementer `tests/test-status-stalled.sh`, whose only check is
   `grep -qF "<the criterion's sentence>" skills/status/SKILL.md`. The code review reports a blocking `test: `
   finding under rule 1.
3. Run `/spec <n>` on a Ready story whose criterion is about a skill's behaviour, after editing the spec in its fix
   round so that its Tests name only a search of the skill's wording. The spec reviewer reports point 1 as blocking.

## Files touched

- `tests/lint.sh`: the sections of decision 3 thinned or removed; the start line of `tests/test-ci-job-name-rule.sh`
  and its comment go. Implementer.
- `tests/test-config-from-base.sh`, `tests/test-docs-low-gaps.sh`, `tests/test-drive-docs.sh`,
  `tests/test-extra-round.sh`, `tests/test-fast-lane.sh`, `tests/test-limits-docs.sh`, `tests/test-security-model.sh`,
  `tests/test-skills-low-gaps.sh`, `tests/test-spec-size-limit.sh`, `tests/test-unattended-docs.sh`: the prose checks
  go and the header says what is still pinned. Implementer.
- `tests/test-ci-job-name-rule.sh`, `tests/test-interrupt-docs.sh`: deleted. Implementer.
- `tests/check.sh`: the step line `add bash test-interrupt-docs.sh` and its two map entries (lines 194 and 219) go.
  Implementer.
- `tests/smoke-check.sh` and other tests: a case that breaks only a removed check goes. Implementer.
- `agents/tester.md`, `agents/code-reviewer.md`, `agents/spec-reviewer.md`: decision 4. Implementer.
- `CHANGELOG.md`, under `Unreleased`, added by the `/next` session, exactly:

  ```
  - Iteration 73 (#344): tests check behaviour, not wording: the lint and the tests it starts no longer pin sentences of the skills, the agents and the docs, only contracts (a config key, a command, a file name, a line a script or a skill parses); the tester, the code reviewer and the spec reviewer are told that a test of a skill's wording is not a test of a criterion.
  ```

The tester owns no file in this iteration, so no file of the implementer's is the tester's.

## Risks

- A removed pin held a rule that matters. The data-rule sentence of row 51 and the Security model sentences of row 52
  are the main cases. They are prose by decision 1, so the reviewers and the manual check guard them from now on, not
  the lint. The list shows every removal, so the maintainer can ask for one back at review.
- An item is wrongly called a contract and kept, or wrongly called prose and removed. A kind (d) item must name its
  reader (decision 1), and the code review checks the list.
- The time gain is small (Facts: at most about 5 s of about 21 s) and can fall within the noise between runs. Decision
  7 takes the median of 5 runs. If the median is not lower, criterion 4 is not met and the result is `partial`.
- `/next` asks the implementer to write a test for each criterion the tester marked `not tested`. Decision 5 and the
  Tests section say why there is none.

## Size estimate

L: about 250 lines go from `tests/lint.sh` and about 600 from the ten thinned test files and the two deleted ones.
About 10 lines change in the agents, 3 in `tests/check.sh` and 1 in the CHANGELOG. In all about 860 changed lines,
nearly all of them deletions. This spec has 321 lines.

## Not done

- The check steps that read skills or docs (Left) and checks on the code of scripts keep their pins.
- No skill changes. `/next`'s rule that the implementer tests a `not tested` criterion stays as it is.
- No scripted pass of a skill with a fake `gh` (#153).
- No new test, no new config key, and no committed inventory file beside this spec and the pull request's list.
- No section is made faster except by removing checks.

## Left

- **Proposed follow-up stories** (the story's agent note allows a split by area):
  - "The check steps check behaviour, not wording": the same rule for the check steps that read skills or docs.
    These are `tests/test-board-listing.sh`, `test-changelog-coverage.sh`, `test-changelog-refs.sh`,
    `test-check-skill.sh`, `test-fix-pick.sh`, `test-guard-rules.sh`, `test-release-low-defects.sh`,
    `test-release-resume.sh`, `test-resume-stuck.sh`, `test-skill-config-fallback.sh`, `test-spec-template.sh`,
    `test-story-dedup.sh`, `test-watch-checks.sh` and `test-worker-merge.sh`, and the skill and README reads in
    `tests/smoke-check.sh`, `tests/smoke-release.sh` and `tests/smoke-validate.sh`.
  - "The lint checks scripts by running them, not by their source text": the source greps of `scripts/` in the lint
    (for example `released automatically` in `scripts/slot.sh`).
- The maintainer decides whether the data rule (row 51) stays pinned as an exception. The story allows only "kept as a
  contract" or "removed", so this spec removes it.
