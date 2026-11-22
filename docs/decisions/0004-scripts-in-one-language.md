# 0004: the scripts in two shells or in one language

Date: 2026-11-22

Status: accepted 2026-11-22 (#361)

## Question

The invariant **Both shells** asks that every script exists in PowerShell and bash and behaves the same. Today that
is 23 `.sh` and 23 `.ps1` files in `scripts/`, 19 pairs of smoke tests, 27 PowerShell steps in the check beside 48
bash steps, and four PowerShell CI parts that take 44 min 51 s of runner time against 5 min 20 s for the bash job;
stories such as iteration 57 (#329) exist only to keep the twins equal. This record compares keeping both shells with
two ways of having one implementation, and recommends one. The migration is left to follow-up stories.

## Facts

Measured on the base commit `8f4bd9f` (`git rev-parse HEAD`: 8f4bd9f6f92e260153a96bb639a1a4d89e68e002, "docs: iteration
61 spec (#342) (#355)") on 2026-11-22. Lines with `find scripts -name '*.sh' | xargs cat | wc -l` (and `*.awk`,
`*.ps1`), `cat tests/smoke-*.sh | wc -l` and the like, `wc -l` for single files, `grep -c '\.ps1'` for lines that name a
`.ps1`, the step list between `# steps: begin` and `# steps: end` of `tests/check.sh` counted with `grep -c '^add bash'`
and `grep -c '^add ps'`, and `gh run list` / `gh run view <id> --json jobs` (read only). A number that differs from the
spec of iteration 61 (measured at 1509b29) says so.

- **Scripts.** `scripts/` and `scripts/lib/`: 23 `.sh` files, 4395 lines; 7 `.awk` files, 2045 lines, used only by the
  bash side; 23 `.ps1` files, 6445 lines. 19 scripts at the top of `scripts/` each exist in both shells. `hooks/`:
  `hooks.json`, `panel.tsx` (269 lines), `panel.test.tsx` (395 lines), no shell script.
- **Tests.** 20 `tests/smoke-*.sh` and 19 `tests/smoke-*.ps1`: 19 pairs, 7827 lines bash (was 7701) and 8285
  PowerShell (was 8160), and `smoke-json.sh` alone (all 20 bash smoke files: 7988 lines). 47 `tests/test-*.sh` (4589
  lines) and 9 `tests/test-*.ps1` (852 lines). `tests/lint.sh` 1874 (was 1831), `tests/check.sh` 709 (was 640),
  `tests/check.ps1` 26 (was 23; it calls `bash tests/check.sh`). The step list of `tests/check.sh` has 48 `bash` steps,
  27 `ps` steps, the lint and two `claude` steps. In all: bash tests 12577 lines, PowerShell tests 9137 lines.
- **CI.** The newest green run of `ci.yml` on `main` in which every job ran is 44952977845 (on 1509b29, 2026-11-21).
  The run on 91da238 (iteration 60) failed, and the run on the base commit, 45020727310, was still in progress when
  this was measured. In 44952977845: the bash job 5 min 20 s on one Ubuntu runner; the four PowerShell parts 11 min
  34 s, 11 min 28 s, 16 min 45 s and 5 min 4 s on Windows runners (44 min 51 s of runner time); 16 min 59 s from the
  first job's start to the end of the final job (`PowerShell scripts smoke tests`, 21:43:06 to 22:00:05).
- **bash is already needed on Windows.** `hooks/hooks.json` runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"`
  and `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh"` (README: where Claude Code runs hooks through PowerShell only the
  hook does nothing; `session-start.ps1` and `guard.ps1` can be wired by hand). `slot.ps1` and `new-worktree.ps1` run
  warm-up commands in bash and throw `bash not found` without one. `tests/check.ps1`, the lint and this repository's
  `verification.check` (`bash tests/check.sh`) are bash. Six skills inject the base config through the Bash tool
  (`MSYS_NO_PATHCONV=1 git show ...`, PR #313).
- **PowerShell is named in the plugin's text.** 35 lines of `skills/*/SKILL.md` and `agents/*.md` name a `.ps1`;
  `README.md` 60 lines. `/nightmill:init` writes allow rules for five scripts (`slot`, `room`, `gate`,
  `validate-config`, `status`) in the bash and the PowerShell form (README, "Five scripts"). CI runs the PowerShell
  tests with Windows PowerShell 5.1 (`bash tests/check.sh --powershell powershell`).
- **Runtimes.** Claude Code here is the native install (`~/.local/bin/claude`, 2.1.330); `node` v22.23.4 is on the PATH
  but was installed separately. `hooks/panel.tsx` is a mod that runs inside Claude Code, not a process a script or hook
  starts. Claude Code's documentation names no interpreter it gives a plugin's scripts:
  - [Advanced setup](https://code.claude.com/docs/en/setup): "Git: optional."; on native Windows "Installing Git for
    Windows is optional. It provides Git Bash, which the Bash tool and the Monitor tool need.", and "Git for Windows is
    recommended on native Windows so Claude Code can use the Bash tool. If Git for Windows is not installed, Claude
    Code uses PowerShell as the shell tool instead." Node: "The npm package requires Node.js 22 or later" and "The
    installed `claude` binary does not itself invoke Node."
  - [Hooks](https://code.claude.com/docs/en/hooks): a shell-form command runs in "`sh -c` on macOS and Linux, Git Bash
    on Windows, or PowerShell when Git Bash isn't installed"; "The `node` plus script-path pattern works on every
    platform because `node.exe` is a real binary." The page does not say that Claude Code supplies Node.
- **The four Git Bash problems are closed**, each by a local workaround: #300 (MSYS path conversion of
  `origin/HEAD:<path>` in `scripts/lib/baseconfig.sh`, PR #301, `MSYS_NO_PATHCONV=1` and
  `tests/test-baseconfig-pathconv.sh`); #302 (the same conversion in the skills' injected line, PR #313); #303 (`git`
  is not in `/usr/bin` in Git for Windows, so a restricted PATH in `smoke-history.sh` lost it, PR #305,
  `tests/test-restricted-path-git.sh`); #304 (GNU tar from Git Bash read `C:` as a host in `smoke-slot.ps1`, PR #308,
  `tests/test-smoke-slot-tar.ps1`). Epic #306 names them as the cause of `verification.platform` (iteration 56).

## Options

### Keep both

**Install**: Windows: nothing for the scripts (Windows PowerShell 5.1 ships with Windows), but Git for Windows for the
hooks, the warm-up commands, the skills' injected config and the check, as today. Linux/macOS: bash, which they have;
PowerShell only to run the PowerShell tests.

**Breaks**: nothing. The `.ps1` allow rules `/nightmill:init` wrote, the `.ps1` hooks wired by hand, the meaning of
`verification.platform` and the skills' call lines all stay.

**Keeps**: all of it: 12885 lines of script code (6440 bash and awk, 6445 PowerShell) and 21714 lines of tests (12577
bash, 9137 PowerShell), 75 shell steps in the check, and the four Windows CI parts (44 min 51 s of runner time). Every
script change is still made twice.

### Bash only, with Git Bash on Windows

**Install**: Windows: Git for Windows (the git build that brings Git Bash), which the hooks, the warm-ups, the
injected config and the check need already and which Claude Code's setup page recommends for the Bash tool; a user
whose `git` comes from another build adds it. Linux/macOS: nothing new.

**Breaks**: the `.ps1` allow rules `/nightmill:init` wrote match nothing once the skills stop calling `.ps1` (harmless,
dead; the bash rules are already there); the `.ps1` hooks wired by hand (`session-start.ps1`, `guard.ps1`) stop working
when the `.ps1` files go and must be removed from the project's settings; `verification.platform` changes meaning
(`windows` would run the bash tests in Git Bash instead of the PowerShell tests, so the key becomes nearly moot); the
35 skill and agent lines that name a `.ps1` become the `.sh` form only. A Windows session without Git Bash, which today
gets the `.ps1` scripts through the PowerShell tool, can no longer run them.

**Keeps**: 6440 lines of script code (4395 bash, 2045 awk) and 12577 lines of bash tests; drops 6445 lines of
PowerShell code, 9137 lines of PowerShell tests and 27 check steps. The four Windows CI parts give way to one job that
runs the bash tests in Git Bash on a Windows runner; its time is not measured (iteration 56 records 2 to 3 hours for
the local check in Git Bash on Windows, so it is likely the slowest job).

### One implementation in a runtime Claude Code brings

Claude Code's documentation names no runtime that it installs or requires on every platform (see `## Facts`): the
native binary "does not itself invoke Node", and Git is optional. The nearest candidate is **Node**: needed only for
an npm install of Claude Code (Node.js 22 or later), and the hooks page shows `node` plus a script path as the form
that "works on every platform". This option is therefore one implementation in Node, as an extra install.

**Install**: Windows and Linux/macOS: Node.js 22 or later, unless Claude Code was installed with npm. Git for Windows
stays optional for the scripts, but this repository's check and the skills' injected line still need bash until they
are rewritten too.

**Breaks**: every allow rule `/nightmill:init` wrote for the five scripts, in both forms (new rules for `node .../*.js`
are needed); the `.ps1` hooks wired by hand, and `hooks/hooks.json` changes to `node` commands; `verification.platform`
loses its reason (one test suite on every platform); every skill and agent call line, bash and PowerShell, changes.

**Keeps**: none of the current script code or tests. Estimate (an estimate, not a measurement): about 6000 to 6500
lines of script code, on the basis of the PowerShell twin (6445 lines), a language that, like JavaScript, parses JSON
itself where bash needs 2045 lines of awk; and about 9000 to 12500 lines of tests, between the PowerShell tests (9137)
and the bash tests (12577). Both current suites stay until the new one covers every script.

## Git Bash problems on Windows

| Issue | Cause | Fixed by | Keep both | Bash only, with Git Bash on Windows | One implementation in a runtime Claude Code brings |
|---|---|---|---|---|---|
| #300 | MSYS converts `origin/HEAD:<path>` to a Windows path in `scripts/lib/baseconfig.sh` | PR #301, `MSYS_NO_PATHCONV=1`, `tests/test-baseconfig-pathconv.sh` | stays: the bash script and its workaround stay | stays, wider: every script runs in MSYS on Windows, so any new `x:y` argument can be converted | gone: Node starts `git` directly, without MSYS |
| #302 | the same conversion in the line the skills inject through the Bash tool | PR #313, `MSYS_NO_PATHCONV=1` in the skills | stays: the injected line is bash in every option today | stays: the line stays bash | stays, unless the injected line is rewritten to call a `node` script |
| #303 | Git for Windows keeps `git` outside `/usr/bin`, so a restricted PATH in a bash test lost it | PR #305, `tests/test-restricted-path-git.sh` | stays: the bash tests stay | stays, wider: the whole bash suite runs in Git Bash on Windows CI, so every PATH trick there meets it | gone: the bash tests go |
| #304 | GNU tar from Git Bash reads `C:` as a host, in `smoke-slot.ps1` | PR #308, `tests/test-smoke-slot-tar.ps1` | stays: the PowerShell test stays | gone in that test (the `.ps1` tests go); a `tar` with a Windows path in bash would meet the same cause | gone: no Git Bash tool in the tests |

## Recommendation

**Bash only, with Git Bash on Windows.** By install it costs nothing new on Linux/macOS, and on Windows it asks for the
Git for Windows that the hooks, the warm-ups, the injected config and the check need already and that Claude Code
recommends for its Bash tool; the runtime option adds Node for every user who did not install Claude Code with npm. By
breakage it removes the `.ps1` forms (dead allow rules, hand-wired `.ps1` hooks, the `windows` value of
`verification.platform`), which the runtime option removes too, along with every bash rule and call line. By lines kept
it halves the scripts (6440 of 12885) and keeps 12577 of 21714 test lines with no rewrite, where the runtime option
rewrites about 15000 to 19000 lines from nothing. Against the table it keeps three of the four Git Bash problems (#304 goes with the `.ps1` tests) and widens two,
because all Windows code then runs in Git Bash; the workarounds and their regression tests exist, and the runtime option
would not remove #302 without further rewriting. The cost to weigh is the Windows CI job in Git Bash, which is likely
slower than the four PowerShell parts together. This is a proposal; the maintainer decides.

## Migration outline

Each step is one story under epic #337 and leaves the plugin working on Windows (with Git for Windows) and on
Linux/macOS with the check green.

1. **Windows CI runs the bash tests in Git Bash.** A new CI job on a Windows runner runs the bash steps; the PowerShell
   parts stay. Nothing changes for a project. The plugin keeps working: only CI grows.
2. **The invariant becomes one shell.** The text of **Both shells** changes to a bash-only invariant (bash on
   Linux/macOS, Git Bash on Windows) in `.claude/nightmill.json` `invariants`, the "Two shells" rule of
   `.claude/CLAUDE.md` and the issue forms; `verification.platform` gets its new meaning (`windows` runs the bash tests
   in Git Bash), which is a story trigger, with the schema, the example config and the README table. The `.ps1` scripts
   are frozen (no new PowerShell twin), not removed. A project with `verification.platform: windows` now runs the bash
   tests; it needs Git for Windows, which its hooks already do.
3. **The skills, the agents and the README name the `.sh` form only.** The 35 skill and agent lines and the README's
   60 lines drop the `.ps1` call; `/nightmill:init` writes allow rules for the bash form only. The `.ps1` files still
   ship, so a project's `.ps1` rules and hand-wired `.ps1` hooks still work; a Windows session without Git Bash loses
   the scripts here and must install Git for Windows (said in the changelog). One release carries this step before
   step 4.
4. **The PowerShell scripts and tests go.** The 23 `.ps1` scripts, the 19 `smoke-*.ps1` and 9 `test-*.ps1` files, the
   `ps` steps of `tests/check.sh` and the four PowerShell CI parts are removed; `tests/check.ps1` stays as the wrapper
   for a PowerShell prompt. This breaks a project's hand-wired `session-start.ps1` or `guard.ps1` hooks, which it removes
   from its settings; its `.ps1` allow rules become dead and can be deleted. A project pins the release before this one
   until it has done so.

## Decision

Accepted on 2026-11-22 by the maintainer in story #361: **Bash only, with Git Bash on Windows**, the option this record
recommends. Why: nightmill is to be developed and tested in one shell, with no second PowerShell track to keep in step;
bash is already needed on Windows for the hooks, the warm-up commands, the skills' injected config and the check, so
Git for Windows is no new requirement for a Windows project. The migration takes the four steps above, in that order,
each leaving the plugin working, each one story under epic #337: step 1 is iteration 64 (#361); the follow-up
stories are #363 (step 2), #364 (step 3) and #365 (step 4).
