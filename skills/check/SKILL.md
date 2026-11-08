---
name: check
description: Run the project's configured check command (the local equivalent of CI) and fix the cause of any failure. Use before every commit and whenever asked to run the checks.
---

Project configuration (`.claude/nightmill.json`):

!`cat .claude/nightmill.json`

Run `verification.check` from the repository root (in a slot worktree: from that worktree's root), as
one command, and wait for it to finish.

If anything fails, fix the cause (not the test) and re-run until it passes. Report the final summary
line. Never commit red.

`/nightmill:check quick` runs `<verification.check> --quick` instead (the quick check: for the check command this
repository ships, the lint and the bash smoke tests only) and reports its last line with the words "quick check: not
the check before a commit". When its first line does not start with `check: QUICK`, say
`the check command has no quick mode; running the check` and run `verification.check` as above. The quick check
never stands for the check before a commit or a pull request.
