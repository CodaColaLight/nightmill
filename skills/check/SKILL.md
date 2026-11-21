---
name: check
description: Run the project's configured check command (the local equivalent of CI) and fix the cause of any failure. Use before every commit and whenever asked to run the checks.
allowed-tools: Bash(git symbolic-ref -q --short refs/remotes/origin/HEAD *), Bash(git for-each-ref --count=1 *), Bash(MSYS_NO_PATHCONV=1 git show origin/*:.claude/nightmill.json *), Bash(echo "NO BASE CONFIG*"), Bash(cat .claude/nightmill.json *)
---

Project configuration on the base branch (`origin/HEAD:.claude/nightmill.json`; the first line names the base ref; see **The configuration** in the `workflow` skill):

!`git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || git for-each-ref --count=1 --format="NO origin/HEAD, but %(refname)" refs/remotes/origin; MSYS_NO_PATHCONV=1 git show origin/HEAD:.claude/nightmill.json 2>/dev/null || echo "NO BASE CONFIG: read .claude/nightmill.json of the working tree (cat .claude/nightmill.json); without it, run /nightmill:init first"`

**The pause and the limits** (the `workflow` skill): before each run of the check (at most three, as below) run the
gate, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"` or `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/gate.ps1"`
(with `--issue <n>` and `--slot <s>` when the check runs for an issue in a slot). Exit 0: go on. Exit 1, 2 or 4: stop
with its `Stopped:` line and run nothing. Exit 3: stop with `Stopped: limit: <reason>.` and leave the breach to the
skill that runs the check (in a run of its own, run nothing more).

Run `verification.check` from the repository root (in a slot worktree:
`cd <absolute slot path> && <verification.check>`, `cd <absolute slot path> && <verification.check> --quick` for
the quick check, and `cd <absolute slot path> && <verification.check> --affected` for the affected check), as one
command, and wait for it to finish.

If anything fails, first tell an environmental failure from a code failure. An environmental failure is not caused by
the code: no network, a missing tool, a service that is down. Do not change code for it; stop and report what is
missing. A code failure is a cause in the code: fix that cause, not a test that is right; a test written in this task
may be fixed when the test itself is wrong. Re-run the check after each fix, at most three attempts in all; when the
third attempt still fails, stop and report the failing step and what was tried. Report the final summary line. Never
commit red.

`/nightmill:check quick` runs `<verification.check> --quick` instead (the quick check: for the check command this
repository ships, the lint and the bash smoke tests only) and reports its last line with the words "quick check: not
the check before a commit". When its first line does not start with `check: QUICK`, say
`the check command has no quick mode; running the check` and run `verification.check` as above. The quick check
never stands for the check before a commit or a pull request.

`/nightmill:check affected` runs `<verification.check> --affected` (the affected check: the lint and the tests of the
changed paths) and reports its last line. A last line `AFFECTED CHECK PASSED` is enough before a commit and in a fix
round, never before a release. When its first line does not start with `check: AFFECTED`, say
`the check command has no affected mode; running the check` and run `verification.check` as above. The fixing rules
above (at most three runs, an environmental failure versus a code failure) apply to it unchanged.
