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
