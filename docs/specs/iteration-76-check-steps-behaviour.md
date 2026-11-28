# Iteration 76: the check steps check behaviour and contracts, not the wording of skills and docs

Status: delivered in iteration 76 (PR #416)

Story #411, epic #337 (fast verification loop), the rest of #344: the 14 check steps and the smoke reads that
iteration 73 (`docs/specs/iteration-73-tests-check-behaviour.md`, decision 2 and the last row of decision 3) left
`deferred`. Each gets a verdict by decision 1 of that spec: a check that searches the text of a skill, an agent, the
README or another prose file is kept only when what it finds is a contract; every other such check is removed. The pull
request lists both groups and the step times before and after. Changes `tests/test-board-listing.sh`,
`tests/test-changelog-refs.sh`, `tests/test-fix-pick.sh`, `tests/test-guard-rules.sh`, `tests/test-resume-stuck.sh`,
`tests/test-spec-template.sh`, `tests/test-story-dedup.sh`, `tests/test-watch-checks.sh`, `tests/test-worker-merge.sh`,
`tests/check.sh` (two step lines, four map lines) and `CHANGELOG.md`. It deletes `tests/test-changelog-coverage.sh`
and `tests/test-check-skill.sh`. `tests/test-release-low-defects.sh`,
`tests/test-release-resume.sh`, `tests/test-skill-config-fallback.sh`, `tests/smoke-check.sh`,
`tests/smoke-release.sh` and `tests/smoke-validate.sh` keep every check.

## Story trigger and manual check

**Not a story trigger.** No status and no rule on who sets one changes; no decision record changes. No config key is
added, renamed or removed. No file under `scripts/` changes, so the slot marker format does not change.
**Compatible**: a project reads nothing that changes. **Config-driven**: no project value is added.

**The manual check does not apply**: no file under `skills/`, `agents/` or `hooks/` changes, only files under `tests/`
and `CHANGELOG.md`. **Shells**: bash only (decision record 0004); no `.ps1` file is added or changed. The steps
involved are the twelve changed or kept test files of the table, the lint (its section "the check runs every smoke
script" reads the step list and the map) and `tests/smoke-check.sh` (its lint copies).

## Facts this rests on

Read and run on `spec/76-check-steps-behaviour` at 4d4a4ac (equal to `main`) on 2026-11-28, on Linux with 4 cores.

- The local awk is mawk 1.3.4. With it, `bash tests/check.sh --only <the 17 steps> --jobs 1` fails
  `test-guard-rules.sh` (`the guard harness is wrong`) and `smoke-release.sh`; with busybox awk first on the PATH and
  `LC_ALL=C` both pass, as iteration 73 found for the lint. Neither failure is this story's.
- **Step times** (Times block, `--jobs 1`, busybox awk, `LC_ALL=C`, one run): `smoke-check.sh` 29 s, `smoke-release.sh` 39 s,
  `smoke-validate.sh` 46 s, `test-guard-rules.sh` 35 s, `test-spec-template.sh` 19 s, `test-release-low-defects.sh`
  2 s, four steps 1 s each, the other seven 0 s; sum 174 s, `total` 2m54s. The two files that decision 3 deletes
  take at most 1 s together; the slow steps (`test-guard-rules.sh`, `smoke-validate.sh`,
  `smoke-check.sh`, `test-spec-template.sh`) spend their time running the guard, the lint and `tests/check.sh` on
  copies, which every verdict keeps. So the gain is about nothing; criterion 3 asks only that it is not slower.
- `tests/smoke-check.sh` reads skills and the README only through 7 `lint_break` cases (`platformreadme`,
  `platforminit`, `mapskill`, `shskill`, `shflag`, `shreadme`, `initps`) and the copies of `mkcopy`; iteration 73
  judged the lint checks they break (a key, `check: AFFECTED`, a script call form). `tests/smoke-validate.sh` line 275
  renames the role `fixer` in a copy of the workflow skill and expects the lint to fail. `tests/smoke-release.sh` reads
  no prose file of the repository: it writes its own `CHANGELOG.md` and `README.md` fixtures for `scripts/release.sh`.
- Readers found in `scripts/` and the skills: `scripts/slot.sh:70` takes the step name of `--report <step>`;
  `scripts/lib/history.awk:260` reads the step names `check-fix-<k>`; `skills/workflow/SKILL.md:544` counts comments
  that start `Check fix round `; `skills/workflow/SKILL.md:573` and `:576` look for an issue comment that starts
  `Checks of PR #<pr> are red` or `Checks of PR #<pr> are not watched`; `skills/spec/SKILL.md:112` matches a pull
  request whose body starts `Spec for #<issue>.`; `skills/story/SKILL.md:55` compares the maintainer's reply with
  `file anyway`, `use #<n>` and `do not file`; `skills/check/SKILL.md:37` reads `check: AFFECTED`;
  `scripts/release.sh:124` and `:224` read `## Unreleased` and the `Version X.Y.Z.` line, `:133` and `:166` the
  version headings `## X.Y.Z (`; `README.md:277` and `:800`
  link the heading `### The deny rules and the guard` (`#the-deny-rules-and-the-guard`). The schema defines the status
  names `Ready`, `Spec`, `Spec review`, `In progress`, `Review` as defaults of `board.statuses`, the key `labels.bug`
  and the role `fixer`. No script
  reads `Resuming #<n> at <step>`, `nothing to continue`, `Not filed:`, `Deny rules: declined` or
  `is running (last report`.
- `scripts/validate-config.sh` accepts a `board.statusField` with a quote (`Owner's prio`: 0 errors), so the
  escape half of the #242 block of `tests/test-board-listing.sh` is the half that passes today.

## Decisions

1. **The rule** is decision 1 of iteration 73, unchanged; where the table below and that decision disagree, the
   decision wins and the list says so. As there: checks on the code of scripts and hooks (`scripts/guard.sh`,
   `hooks/hooks.json`), on JSON values (schema, example) and on files under `tests/` and `templates/` are not prose
   checks and stay; a test that runs a script or a skill's injection line is behaviour and stays. For a parsed line
   whose reader reads only a prefix, only the prefix stays (as `Stopped: ` in #412). A status name or a role name is
   a value the schema defines (kind a) and is searched as the name alone, not inside its sentence.
2. **What this iteration covers**: exactly the 14 files and the three smoke scripts of the last row of decision 3 of
   iteration 73. Nothing is deferred.
3. **The verdicts.** K: kept as it is. S: the contract items named stay, the other prose items go. R: removed; a file
   whose checks all go is deleted with its step line and its map entries in `tests/check.sh`. A thinned file's header
   says what it still pins and that the wording is the reviewers' (iteration 73), as the files of iteration 73 do.

   | Area | File | Protects | Verdict: what stays (kind; reader for d) |
   |---|---|---|---|
   | board | `test-board-listing.sh` | #125, #242 listing | S: the listing is one `gh project item-list <project> ... --jq '...'` command with no pipe, whose filter indexes `<board.statusField ...>` and `<board.priorityField ...>` and names no literal `.status`/`.priority` (b); `board.statusField`, `board.priorityField` in the three skills and the workflow skill (a); the #242 block as "validator refuses (run) or the skills hold `\"`, `\\`, `'\''`" (b, the escapes of the command's argument). Go: `lower`, `warn`, `missing`, `key`/`field name`/`configured`, `escap`, the windows (whole file instead) |
   | changelog | `test-changelog-coverage.sh` | #138 | R: the 0.2.0 bullets, the iteration 65 bullet and the `.claude/CLAUDE.md` rule are prose (CHANGELOG bullet, CLAUDE.md); deleted |
   | changelog | `test-changelog-refs.sh` | #139 | S: a `## X.Y.Z (` version heading exists (d, `scripts/release.sh:133`, `:166`). Go: the issue numbers of the iteration 1, 2, 3 and 9 bullets (CHANGELOG bullet wording) |
   | /check | `test-check-skill.sh` | #124 | R: three attempts, environment, network, code failure, the same task: prose; deleted |
   | /fix | `test-fix-pick.sh` | #118 | S: the status name `Ready` and the key `labels.bug` in `skills/fix/SKILL.md`, each searched as the name alone in the whole file (a). Go: `refus`/`reject`/`declin` next to them, `story`/`epic`, `one line`, `changes nothing`, the refusal inside step 1 (the step window and the order before step 3) |
   | guard | `test-guard-rules.sh` | #110 deny rules, guard | S: everything on `hooks/hooks.json` and `scripts/guard.sh` (code); the 23 `Bash(...)` rules of the Deny rules bullet, their count and fixed prefixes, no `Bash(git -C` rule (b); `permissions.deny`, `.claude/settings.json` (a, c); `gh api graphql -f query='mutation { ... }'`, `git branch -d <branch>` (b); the runs of the rules and the guard against every command and graphql fence the skills write (behaviour); no `gh pr merge --admin` in a skill (b); README: the rules, `permissions.deny`, `scripts/guard.sh`, `docs/decisions/0002` (searched as `0002`) (b, a, c), `### The deny rules and the guard` (d, `README.md:277`), the `issues/253)` link (c). Go: `without removing or reordering an entry`, `Deny rules: declined (...)`, `a board item or field, a label or a release`, the step headings `## 4. Confirm once`/`## 5. Apply`, `A refused command is final`, `deny rules refuse a merge with --admin`, README `Git Bash`, `23 rules`, `18 rules`, `field-delete are not refused`, `base branch still prompts`, the State values of the Security model rows (as iteration 73 removed them from `test-security-model.sh`) |
   | release | `test-release-low-defects.sh`, `test-release-resume.sh` | #321, #130 | K: they run `scripts/release.sh` on fixtures; no prose check |
   | resume | `test-resume-stuck.sh` | #112 resume | S: the status names `Spec`, `Spec review`, `In progress`, `Review` in the workflow skill (a); `<git.specPrefix><N>-*`, `<git.featurePrefix><N>-<slug>`, `closingIssuesReferences`, `--status --porcelain`, `slot --abandon <s>` (b); `Spec for #<issue>.` (d, `skills/spec/SKILL.md:112`); `` | `session` | `resumed` | `` (d, `scripts/slot.sh:70`); `/spec N`, `/next N` in the status skill and the README rows `` `/nightmill:spec [N]` ``, `` `/nightmill:next [N]` `` (b). Go: every other sentence (`also takes ...`, `its own artefacts`, `the first unfinished step`, `Resuming #<n> at <step>`, `nothing to continue`, `another run is working on it`, `is running (last report`, the `resumed by /next` lines, `is not set again ...`, `an open one is reused`, `only when no comment`, `has no entry for iteration N`, ...), the two absence checks and `continues a story` |
   | config | `test-skill-config-fallback.sh` | #127, #111, #241, #302 | K: runs each skill's injection line and checks `allowed-tools` (b) |
   | spec | `test-spec-template.sh` | #150 template | S: all on `templates/spec.md` and the lint runs (not prose); `templates/spec.md` in the spec skill (at least twice), the spec reviewer and the README (c). Go: `keep its headings, with their exact text and in their order`, the absence of `as the model for the form`, `in its order` |
   | /story | `test-story-dedup.sh` | #148 dedup | S: `gh issue list --state all --search`, `in:title`, `--limit 100`, `--json number,title,state,stateReason,labels,url`, the search command without `--label` and `--state open`, `gh issue create` present (b); `` `file anyway` ``, `` `use #<n>` ``, `` `do not file` `` (d, `skills/story/SKILL.md:55`). Go: the order of search and create, `needs-triage`, `at least 2 key words`, `At most 5`, the `Not filed:` and `No similar issue found` lines, `closed as not planned`, `whatever they are`, `no third search`, `at most once per run`, `trimmed and lower-cased`, `Only file anyway files`, the limit paragraph, the README `similar title` |
   | watch | `test-watch-checks.sh` | #145 watch | S: `review.watchChecksMinutes`, `review.maxFixRounds`, `worktrees.stalledAfterMinutes`, the example value and the README row of the first (a), and its schema entry as `"type": "integer"`, `"minimum": 1`, `"default": 30` (a, JSON values); `gh pr checks <pr> --watch --fail-fast --interval 30`, `gh pr checks <pr> --json name,bucket,link,workflow`, `actions/jobs/<job>/logs`, `--allow-escape-sequences`, `startswith("Check fix round ")`, `--add-label blocked`, `git commit -m "docs: iteration <N> spec (#<issue>), check fix round <k>"` (searched as its quoted message), the two push forms, no `gh pr merge --admin`, the four commands without a run permission absent (b); the prefix `Check fix round ` in /next, /fix, /spec (d, `skills/workflow/SKILL.md:544`); `Checks of PR #<pr> are red` and `Checks of PR #<pr> are not watched` (d, `skills/workflow/SKILL.md:573`, `:576`); the rows `` | `session` | `watch-checks` | `` and the step names `check-fix-<k>`, `check-review-<k>`, `handed-over` (d, `scripts/slot.sh:70`; `check-fix-` also `scripts/lib/history.awk:260`); no `--body "Checks of PR #<pr> were still running` (b). Go: the schema description text `"description": "Minutes /next, /fix and` (a description is prose), the rest of the sentences (`10 times in a row`, the warning line, `Watching the checks`, `check fix round`, `is red (check fix round`, the prompt sentences, `not known (resumed run)`, the hand-over reasons, `never ...`, the green line, `Fixed by the <role> role`), and the count of `gh run rerun` against the `never` phrases |
   | worker | `test-worker-merge.sh` | #120 merge | S: no `gh pr merge ... --squash/--rebase/--merge` in `agents/worker.md`, `--auto` in it (b). Go: `merge command`, `prompt gives` |
   | smoke | `smoke-check.sh` | lint copies | K: its 7 `lint_break` cases on skills and the README break kept items: `verification.platform` (a), `check: AFFECTED` (d, `skills/check/SKILL.md:37`), the `.sh` call forms and allow rules (b) |
   | smoke | `smoke-release.sh` | release script | K: no read of the repository's prose; its fixtures hold `## Unreleased` and `Version X.Y.Z.` (d, `scripts/release.sh:124`, `:224`) |
   | smoke | `smoke-validate.sh` | lint on a role | K: the role `fixer` renamed in a copy of the workflow skill (a, a role of the schema) |

4. **`tests/check.sh`**: the two step lines `add bash test-changelog-coverage.sh` and `add bash test-check-skill.sh`
   go, and their names leave the map lines of `CHANGELOG.md`, `scripts/release.*` and `skills/check/*` (which keeps
   `smoke-check.sh`); `skills/fix/*` keeps `test-fix-pick.sh`. The line `map .claude/CLAUDE.md test-changelog-coverage.sh` becomes
   `lintonly .claude/CLAUDE.md`, so that a change to that file runs the lint alone (it reads the file's layout) and
   does not turn `--affected` into the full check by matching no map line. No other step line changes.
5. **No new automated test.** A test of the list would itself pin wording (as iteration 73 decision 5). The criteria
   are shown by the list (decision 6), the step times (decision 7) and a green check.
6. **The list in the pull request**: `## Prose checks` with `### Kept as contract checks` and `### Removed`, one line
   per item in the form of iteration 73 decision 6:
   `- <file> "<check>": <the pinned text> — protects <what>; <kind a|b|c|d, and for d the reader <file>:<line>>` and
   `- <file> "<check>": <the pinned text> — protects <what>; prose: <why, one phrase>`. Every row of decision 3 has at
   least one line; a K file without a prose check gets `- <file>: no prose check — protects <what>; behaviour`. No
   `### Deferred`. The implementer writes it in its last message above its result block; the `/next` session puts it
   in the pull request body only, never in the reviewer's prompt (iteration 18 decision 2).
7. **The step times.** On one machine, with the same awk and locale both times (where mawk fails a step, busybox awk
   first on the PATH and `LC_ALL=C`), with nothing else running: the base commit is checked out with
   `git worktree add --detach /tmp/nightmill-base-76 <base>` (never by switching the slot's branch) and removed after.
   In each tree, 3 runs of `bash tests/check.sh --only <steps> --jobs 1`, where `<steps>` is the 17 names of the table
   on the base and the 15 that remain on the branch. A run's time is the sum of the step times in its `Times:` block
   (not its `total`). `## Check time` in the pull request gives the machine (OS, cores, awk), the two commits, the 6
   sums and the two medians. The `/next` session makes this measurement itself after the implementer returns, as in
   iteration 73 decision 7, and gives it to the reviewer as a fact. Criterion 3 is met when the branch median is not
   higher than the base median.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | A list names every one of these steps and reads that matches prose, with what it protects | Decisions 1, 2, 3 (column Protects), 6 |
| 2 | Each is kept as a contract check (with its reader for a parsed line) or removed; the pull request lists both groups | Decisions 1, 3, 4, 6 |
| 3 | The check is not slower afterwards, shown by its time before and after | Decision 7 |

## Tests

No new test file (decision 5). How each criterion is carried through `/next`:

- **The tester** writes no file and reports `Result: partial` with every `Criteria` line `not tested`:
  `1. ... -> not tested: a list in the pull request (decision 6)`, `2. ... -> not tested: a list in the pull request
  (decision 6)`, `3. ... -> not tested: a measurement (decision 7)`.
- **The implementer** writes no test for them, although `skills/next/SKILL.md` line 452 asks for one (decision 5).
  Its `Criteria` lines: `1 met, no test (decision 5)`, `2 met, no test (decision 5)`, `3 met, no test (decision 7)`.
- **The code reviewer** gets, at the end of its prompt, with the session's measurement:

  ```
  Criteria 1 to 3 of this iteration have no automatic test by decision 5 of the spec, because a test of them would
  pin wording; do not report that under rule 1. Check criteria 1 and 2 against the diff of the test files and
  tests/check.sh and decisions 1, 3 and 4: a check removed that decision 1 keeps, or a prose check kept that it
  removes, is a blocking finding. Check criterion 3 against this measurement by the session (decision 7): <machine;
  base and branch commits; the 6 sums; the two medians>. A branch median above the base median is a blocking finding.
  ```

  This paragraph, the session's measurement and the departure from line 452 are one-off overrides by this spec.
- `bash tests/check.sh` and the lint stay green on the branch: every kept check still holds, the lint's section "the
  check runs every smoke script" accepts the step list and the map, and `tests/smoke-check.sh` still passes.

## Files touched

- `tests/test-board-listing.sh`, `tests/test-changelog-refs.sh`, `tests/test-fix-pick.sh`, `tests/test-guard-rules.sh`,
  `tests/test-resume-stuck.sh`, `tests/test-spec-template.sh`, `tests/test-story-dedup.sh`,
  `tests/test-watch-checks.sh`, `tests/test-worker-merge.sh`: the prose checks of decision 3 go; the header says what
  is still pinned. Implementer.
- `tests/test-changelog-coverage.sh`, `tests/test-check-skill.sh`: deleted. Implementer.
- `tests/check.sh`: decision 4. Implementer.
- `CHANGELOG.md`, under `Unreleased`, added by the `/next` session, exactly:

  ```
  - Iteration 76 (#411): the check steps check behaviour, not wording: the 14 check steps and the smoke reads that iteration 73 left no longer pin sentences of the skills, the agents and the docs, only contracts (a config key, a command, a file name, a line a script or a skill parses).
  ```

The tester owns no file in this iteration.

## Risks

- An item is called prose and removed although something reads it, as the reviewers of iteration 73 found twice.
  Every kind (d) item names its reader, the Facts list the readers searched for in `scripts/` and the skills, and the
  code review checks the list against the diff; the maintainer can ask for a check back at review.
- The `/fix` refusal of a non-Ready issue (#118, only the names `Ready` and `labels.bug` stay pinned), the bounded
  `/check` (#124) and the `/story` question order lose their only automatic guard; they are prose by decision 1, so the reviewers and the maintainer guard them from now on.
- The gain is about nothing and the slow steps vary by a few seconds between runs, so a noisy run could look slower.
  Decision 7 takes the median of 3 runs with `--jobs 1`; if the branch median is higher, criterion 3 is not met and
  the result is `partial`.

## Size estimate

M: 91 lines go with the two deleted files (`test-changelog-coverage.sh` 58, `test-check-skill.sh` 33), about 125 from
the nine thinned files (most in `test-watch-checks.sh`, `test-story-dedup.sh`, `test-resume-stuck.sh` and
`test-guard-rules.sh`), about 22 change in their headers, 6 in `tests/check.sh` (two step lines, four map lines) and 1
in the CHANGELOG: about 245 changed lines, nearly all deletions.

## Not done

- The lint sections and the ten test files of iteration 73 are not judged again.
- Checks on the code of scripts and hooks (for example the refusal lines of `scripts/guard.sh` in
  `test-guard-rules.sh`) stay as they are.
- No scripted pass of a skill with a fake `gh` (#153), no new test, no config key, no change to a skill, an agent or a
  hook, and no committed inventory file beside this spec and the pull request's list.
- No step is made faster except by removing checks.
