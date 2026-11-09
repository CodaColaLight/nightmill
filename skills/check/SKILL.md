---
name: check
description: Run the project's configured check command (the local equivalent of CI) and fix the cause of any failure. Use before every commit and whenever asked to run the checks.
allowed-tools: Bash(cat .claude/nightmill.json *)
---

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json 2>/dev/null || echo "NO CONFIG: run /nightmill:init first"`

Run `verification.check` from the repository root (in a slot worktree:
`cd <absolute slot path> && <verification.check>`, and `cd <absolute slot path> && <verification.check> --quick` for
the quick check), as one command, and wait for it to finish.

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
