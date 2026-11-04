# Iteration 3: a SessionStart hook offers `/init` where nightmill is not set up

Status: draft, awaiting approval (#12)

Story: #12, epic #4 (Setup and onboarding). Adds `hooks/hooks.json` and one script in each shell. No config
key, no change to the status flow, no change to the slot marker: none of `escalation.storyTriggers`
applies, so the PR may auto-merge.

## Goal

In a project where nightmill is enabled but has no `.claude/nightmill.json`, the first thing a new session
does is offer the setup. In a configured project the hook says nothing.

## Facts this rests on

From the Claude Code hooks and plugin reference (checked 2026-11-04):

- A plugin ships hooks in `hooks/hooks.json`, with the event map under a top-level `"hooks"` key. Command
  paths use `${CLAUDE_PLUGIN_ROOT}`, quoted.
- For `SessionStart`, plain text on stdout is added to the context Claude sees, before the first prompt.
  Exit code 0 is success; any other code is a non-blocking error.
- The `startup` matcher fires when a session starts (the others are `resume`, `clear`, `compact`, `fork`).
- A command hook runs in `sh` on macOS and Linux, in Git Bash on Windows, and in PowerShell on Windows when
  Git Bash is not installed. A hook may set `"shell": "bash"` or `"shell": "powershell"`.
- The hook runs in the session's start directory; `CLAUDE_PROJECT_DIR` is the project root.

## Behaviour

The hook runs once per new session (`matcher: "startup"`) and prints at most one line.

| Situation | Output |
|---|---|
| `<project root>/.claude/nightmill.json` exists | nothing |
| it does not exist, and `NIGHTMILL_HINT` is not `off` | exactly one line (below) |
| it does not exist, and `NIGHTMILL_HINT` is `off` (any case) | nothing |

`<project root>` is `CLAUDE_PROJECT_DIR` when set, else the current directory.

The line, on one line without a trailing blank line:

`nightmill is enabled in this project but not set up (no .claude/nightmill.json). Offer the user to run /nightmill:init, a short install chat that creates the board, labels, config and issue forms. Mention it once; do not run it unless the user agrees.`

The script exits 0 in every case, also when the directory cannot be read.

`NIGHTMILL_HINT=off` is an environment variable, not a configuration key, because it is read before any
configuration exists. It exists for people who enabled the plugin at user scope and open projects that do
not use it; they set it in `env` in their user `settings.json`. The README says so.

## Files

- `hooks/hooks.json`: one `SessionStart` entry with `matcher: "startup"` that runs the script of the shell
  the machine uses (see "Both shells").
- `scripts/session-start.sh` and `scripts/session-start.ps1`: the same behaviour, no `jq`, no `gh`, no
  network. `.ps1` reads nothing as ANSI: the file is written as UTF-8 without a BOM and contains only ASCII.
- `tests/smoke-hook.sh` and `tests/smoke-hook.ps1`.
- `tests/lint.sh`: check `session-start hook is wired`.
- `.github/workflows/ci.yml`, `tests/check.sh`: run the two new smoke tests where the other smoke tests run.
- `README.md`: the Install section gets one paragraph (what the hook does, `NIGHTMILL_HINT=off`);
  `CHANGELOG.md`: a bullet under `Unreleased` for iteration 3 (#12).
- `.claude/nightmill.json`: `hooks` is added to `verification.manualCheckPaths`, because a hook changes
  what a real session does and only a real session proves it.

## Both shells

A machine runs hooks through a POSIX shell (macOS, Linux, Windows with Git for Windows) or, on Windows
without Git for Windows, through PowerShell. `hooks.json` therefore lists **two entries under the same
matcher, one with `"shell": "bash"` and one with `"shell": "powershell"`**, each running its own script.
To keep the output single on a machine that can run both (Windows with Git Bash and PowerShell), the
`.ps1` script prints nothing when `bash` is found on the `PATH`; the `.sh` script has no such guard because
a machine where bash can run it has no reason to defer.

**Check first, before anything else is built.** Whether a hook whose shell is missing on the machine is
silent or shows an error to the user is not documented. The first implementation step runs `claude
--plugin-dir .` here with both entries and records what the user sees when (a) `powershell` is not
resolvable and (b) `bash` is not resolvable, by running with a `PATH` that lacks it. The result decides:

- If a missing shell is silent, both entries stay.
- If it shows an error line on every start, `hooks.json` keeps only the `bash` entry, the `.ps1` script
  stays (parity, the smoke test, and a documented way to wire it by hand), and the README says that on
  Windows without Git for Windows the hint is not shown. nightmill needs `git`, and a Windows machine with
  git installed through Git for Windows has Git Bash, so this loses very few users.

The PR states which of the two applied and why.

## Tests

- `tests/smoke-hook.sh` and `tests/smoke-hook.ps1`, in a temporary directory, each against its own script:
  1. no `.claude/nightmill.json`, `CLAUDE_PROJECT_DIR` set to the directory: exactly one output line,
     containing `/nightmill:init`; exit code 0;
  2. with the file present: empty output; exit code 0;
  3. no file and `NIGHTMILL_HINT=off`: empty output; with `Off` too;
  4. `CLAUDE_PROJECT_DIR` unset and the current directory used instead: same as 1 and 2;
  5. a directory that does not exist: exit code 0, no output.
- `tests/lint.sh` check `session-start hook is wired`: `hooks/hooks.json` has a top-level `hooks` key, a
  `SessionStart` entry with matcher `startup`, every `command` references `${CLAUDE_PLUGIN_ROOT}/scripts/`
  and the script it names exists. The existing JSON check parses the file.
- `claude plugin validate . --strict` accepts the plugin with the hooks file.
- Manual check (`hooks` is now a manual-check path), with `claude --plugin-dir <this checkout>`:
  1. in a throwaway repository without config: ask the session what the SessionStart hook said; the
     answer names `/nightmill:init`;
  2. in this repository (has config): the same question gets "nothing";
  3. in the throwaway repository with `NIGHTMILL_HINT=off` in the environment: nothing;
  4. the missing-shell check above.

  The PR describes what was seen.

## Not done

- Running `/init` automatically; the hook only makes Claude offer it.
- Remembering a "no" per project (a marker file or a setting). `NIGHTMILL_HINT=off` is the only opt-out.
- A hint for any other event (`resume`, `clear`, `compact`) or for a project whose config is invalid
  (that is the validator, #9).
- Detecting that the plugin is enabled at project or user scope; the hook cannot tell.
- Any new configuration key.
