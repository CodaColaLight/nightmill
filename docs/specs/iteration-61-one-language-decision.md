# Iteration 61: a decision record on keeping the scripts in two shells or moving them to one language

Status: draft, awaiting approval (#342)

Story #342, epic #337 (fast verification loop). Every script in `scripts/` exists as `.sh` and `.ps1`, and every
smoke test twice, because the invariant **Both shells** asks for it. This iteration writes one decision record,
`docs/decisions/0004-scripts-in-one-language.md`, that compares three options (keep both; bash only, with Git Bash on
Windows; one implementation in a runtime Claude Code already brings) by what users must install, what breaks for
existing projects and the lines of code and tests each keeps, says how each stands to the Git Bash problems #300,
#302, #303 and #304, and ends with a recommendation and a migration outline. The maintainer accepts or declines it on
the pull request. Only when the accepted option changes **Both shells** are the follow-up stories filed under #337.
No script, test, skill, config or invariant text changes. Changes `docs/decisions/0004-scripts-in-one-language.md`
(new) and `CHANGELOG.md`.

**Never auto-merged** (decision 4): the implementer opens the pull request without `--auto`; the maintainer's answer
on it is the decision, and the maintainer merges it.

## Story trigger and manual check

**Not a story trigger.** No status or who sets it changes, no config key is added, renamed or removed, and the slot
marker format does not change: the change is one Markdown file under `docs/decisions/` and one changelog bullet.
**Compatible** holds trivially. **No manual check**: nothing under `skills/`, `agents/` or `hooks/` changes. **No
shell, no smoke step**: no script changes, so **Both shells** holds in this iteration whatever the record recommends.
Under iteration 59's `--affected` a change under `docs/` runs the lint alone; `CHANGELOG.md` is outside `docs/`, so
whatever the map gives for it runs.

## Facts this rests on

Measured on `main` at 1509b29 on 2026-11-21 with `find ... | xargs cat | wc -l` and `gh` (read only).

- **Scripts.** `scripts/` and `scripts/lib/`: 23 `.sh` files, 4395 lines; 7 `.awk` files, 2045 lines, used only by
  the bash side (the `.ps1` files name them in comments only); 23 `.ps1` files, 6445 lines. 19 scripts at the top of
  `scripts/` each exist in both shells. `hooks/`: `hooks.json`, `panel.tsx` (269 lines), `panel.test.tsx` (395 lines),
  no shell script.
- **Tests.** 20 `tests/smoke-*.sh` and 19 `tests/smoke-*.ps1`: 19 pairs (7701 lines bash, 8160 PowerShell) and
  `smoke-json.sh` alone. 47 `tests/test-*.sh` (4589 lines) and 9 `tests/test-*.ps1` (852 lines). `tests/lint.sh` 1831,
  `tests/check.sh` 640, `tests/check.ps1` 23 (it calls `bash tests/check.sh`). The step list of `tests/check.sh` has
  48 `bash` steps, 27 `ps` steps, the lint and two `claude` steps.
- **CI** run 44952977845 on `main`: the bash job 5 min 20 s on one Ubuntu runner; the four PowerShell parts 11 min
  34 s, 11 min 28 s, 16 min 45 s and 5 min 4 s on Windows runners (44 min 51 s of runner time); 17 min from start to
  the end of the final job.
- **bash is already needed on Windows.** `hooks/hooks.json` runs `bash .../session-start.sh` and `bash .../guard.sh`
  (README: on a PowerShell-only machine the hook does nothing; the `.ps1` twins are wired by hand). `slot.ps1` and
  `new-worktree.ps1` run warm-up commands in Git for Windows' bash and throw `bash not found` without one.
  `tests/check.ps1`, the lint and this repository's `verification.check` (`bash tests/check.sh`) are bash. The six
  skills that inject the base config do it through the Bash tool (`MSYS_NO_PATHCONV=1 git show ...`, PR #313).
- **PowerShell is named in the plugin's text.** 35 lines of `skills/*/SKILL.md` and `agents/*.md` name a `.ps1`;
  `README.md` 60 lines. `/nightmill:init` writes allow rules for five scripts (`slot`, `room`, `gate`,
  `validate-config`, `status`) in both forms (README, "Five scripts"). CI runs the PowerShell tests with Windows
  PowerShell 5.1 (`--powershell powershell`).
- **Runtimes.** Claude Code here is the native install (`~/.local/bin/claude`, 2.1.330); `node` v22 is on the PATH but
  was installed separately. `hooks/panel.tsx` is a mod that runs inside Claude Code, not a process a script or hook
  starts. This spec found no documented interpreter that Claude Code gives a plugin's scripts.
- **The four Git Bash problems are closed**, each by a local workaround: #300 (MSYS path conversion of
  `origin/HEAD:<path>` in `scripts/lib/baseconfig.sh`, PR #301, `MSYS_NO_PATHCONV=1` and
  `tests/test-baseconfig-pathconv.sh`); #302 (the same conversion in the skills' injected line, PR #313); #303 (`git` is
  not in `/usr/bin` in Git for Windows, so a restricted PATH in `smoke-history.sh` lost it, PR #305,
  `tests/test-restricted-path-git.sh`); #304 (GNU tar from Git Bash read `C:` as a host in `smoke-slot.ps1`, PR #308,
  `tests/test-smoke-slot-tar.ps1`). Epic #306 names them as the cause of `verification.platform` (iteration 56).

## Decisions

1. **The record's file and headings.** File `docs/decisions/0004-scripts-in-one-language.md` (0004 is the next free
   number; if another record takes it first, the next free one, and the CHANGELOG bullet names the file). Title
   `# 0004: the scripts in two shells or in one language`, then `Date: <the day it is written>` and
   `Status: proposed (#342)`. Headings, in this order, each with what it must contain:
   - `## Question`: two to four sentences: what **Both shells** asks today, what it costs (the numbers of
     `## Facts`), and that the record leaves the migration to follow-up stories.
   - `## Facts`: every number of this spec's **Facts this rests on**, measured again on the record's own base commit,
     which it names with the commands used; a number that changed is stated with its new value. The CI times come
     from the newest green run on `main` (`gh run view <id> --json jobs`), with its id.
   - `## Options`: one `###` subsection per option, in this order: `Keep both`, `Bash only, with Git Bash on Windows`,
     `One implementation in a runtime Claude Code brings`. Each states, in three bold-labelled lines: **Install**
     (what a user on Windows and on Linux/macOS must install beyond Claude Code, `git` and `gh`); **Breaks** (what an
     existing project must change or loses: at least the allow rules `/nightmill:init` wrote for the `.ps1` scripts,
     the `.ps1` hooks wired by hand, the meaning of `verification.platform`, and the skills' call lines); **Keeps**
     (lines of script code and of tests, from `## Facts`; for a rewrite in a new runtime, an estimate marked as one,
     with its basis). The third option names the runtime: one Claude Code's own documentation says it installs or
     requires on every platform, quoted with its link; when none exists, the subsection says so, names the nearest
     candidate (for example Node, needed only for an npm install of Claude Code) and treats it as an extra install.
   - `## Git Bash problems on Windows`: a table, one row per issue #300, #302, #303, #304, with the cause in one line,
     the fix that closed it, and one column per option: `gone`, `stays` or `stays, wider` (the cause reaches more
     code), each with a short reason.
   - `## Recommendation`: one option, named exactly as its subsection, and why, in terms of the three measures and the
     table. It does not claim the maintainer has decided.
   - `## Migration outline`: for the recommended option, numbered steps; each step is one story, says what changes,
     and leaves the plugin working on Windows and on Linux/macOS with the check green. It names the step that changes
     the text of **Both shells** (`.claude/nightmill.json` `invariants` and the "Two shells" rule of
     `.claude/CLAUDE.md`), every step that is a story trigger (for example a changed meaning of
     `verification.platform`), and what an existing project does at each step that breaks it. For `Keep both` the
     outline is the single line `No migration.`
   - `## Decision`: written only after the maintainer's answer (decision 4): accepted (which option) or declined, the
     date, and, when follow-up stories were filed, their numbers.
2. **The numbers live in the record, not in the issue.** The record is written from facts it measured; it does not
   copy a number from this spec without measuring it again.
3. **Not deciding for the maintainer.** The spec fixes the comparison, not its outcome: the implementer chooses the
   recommendation from the facts and the maintainer accepts or declines it.
4. **How the maintainer answers.** The implementer opens the pull request without `--auto` and writes in it
   `Auto-merge is not enabled: decision record 0004 waits for the maintainer to accept or decline it (#342).`, sets
   **Review** and stops. The maintainer answers on the pull request. Then the implementer, named by number on the story
   at Review, finishes in one of two ways:
   - **Accepted, and the accepted option is not `Keep both`**: sets `Status: accepted <date>` and writes
     `## Decision`; if the accepted option is not the recommended one, writes its `## Migration outline` first; files
     one follow-up story per migration step with `/nightmill:story` under epic #337 (Backlog, as that skill files it),
     each naming the record and its step, and lists their numbers under `## Decision`.
   - **Declined, or `Keep both` accepted**: sets `Status: declined <date>` or `Status: accepted <date>`, writes
     `## Decision`, files no story; **Both shells** stays.
   In both cases it pushes the change, and the maintainer merges the pull request (or closes it).
5. **No invariant text changes here.** `.claude/nightmill.json`, `.claude/CLAUDE.md` and the issue forms keep **Both
   shells** in this iteration; the outline names the step that changes them.

## Criteria and rules

| # | Acceptance criterion | Rule (decision or section) |
|---|---|---|
| 1 | A decision record compares the options by what users must install, what breaks for existing projects, and the lines of code and tests each keeps | Decision 1 (`## Facts`, `## Options`), decision 2 |
| 2 | It names the known Git Bash problems on Windows (#300, #302, #303, #304) and how each option stands to them | Decision 1 (`## Git Bash problems on Windows`) |
| 3 | It ends with a recommendation and a migration outline in steps that each leave the plugin working | Decision 1 (`## Recommendation`, `## Migration outline`), decision 3 |
| 4 | When the decision changes the "Both shells" invariant, follow-up stories are filed under this epic; no script is changed in this story | Decisions 4 and 5; Files touched |

## Tests

No automated test reads the record; the code reviewer checks it against decision 1 heading by heading.

- Criterion 1: review: the three `###` subsections exist in the order of decision 1, each with **Install**,
  **Breaks** and **Keeps**; every number of **Facts this rests on** appears in `## Facts` with the commit it was
  measured on.
- Criterion 2: review: the table has four rows (#300, #302, #303, #304) and one column per option, no cell empty.
- Criterion 3: review: `## Recommendation` names one option; every outline step says what changes and that the plugin
  keeps working, and one step changes the **Both shells** text (or the outline is `No migration.`).
- Criterion 4: `git diff --name-only origin/main...` lists only the record and `CHANGELOG.md`; after the maintainer's
  answer, the filed stories (if any) are sub-issues of #337 and listed under `## Decision`.
- All: the lint (`== generic words` and the rest) passes on the branch.

## Files touched

- `docs/decisions/0004-scripts-in-one-language.md` (new): the record of decision 1.
- `CHANGELOG.md`: one bullet under `Unreleased`, written after the maintainer's answer:
  `- Iteration 61 (#342): decision record 0004 compares keeping the scripts in bash and PowerShell, bash only with Git
  Bash on Windows, and one implementation in a runtime Claude Code brings, by install, breakage and lines kept, and
  recommends <option>; the maintainer <accepted it | accepted <option> | declined it>. <N follow-up stories under #337
  | No follow-up story.> No script changes.`

## Risks

- The numbers drift while iterations 59 and 60 merge (both add steps and lines). Decision 2 limits it: the record
  measures on its own base commit and names it.
- The runtime option rests on what Claude Code documents, which can change; the record quotes and links its source.
- The pull request waits on the maintainer and holds no hot file, so it blocks no other story.

## Size estimate

S to M: the record about 120 to 160 lines, the changelog bullet 4 lines.

## Not done

- No migration step, no script, test, skill, hook, CI or config change (the issue's out of scope).
- No edit of the **Both shells** text in `.claude/nightmill.json`, `.claude/CLAUDE.md` or the issue forms (decision 5).
- No new measurement of the Windows local check time in Git Bash (iteration 56 records 2 to 3 hours).
- No stories filed when the record is declined or `Keep both` is accepted.

## Left

- Decision 4 withholds auto-merge for a reason that the closed list in step 7 of `/next` does not name (story
  trigger, partial, skipped manual check, blocking findings, open dispute). Approving this spec is the maintainer's
  word for this pull request; if the maintainer prefers the list unchanged, the alternative is to merge the record as
  `Status: proposed` and record the answer in a second change, which this spec does not plan.
