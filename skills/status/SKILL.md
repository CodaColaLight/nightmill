---
name: status
description: Show one table of what waits for the maintainer and what is stuck - board items, their pull requests and CI, the slots and what their agents do, stale states flagged. Read-only. Use when asked for the status, what is waiting, what is stuck, or where things stand.
---

Show where the work stands. This skill reads and changes nothing.

Run the script of the shell in use, from inside the project (any checkout or worktree), and wait for it:

- PowerShell (Windows): `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/status.ps1"`
- bash: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"`

Add `-All` (PowerShell) or `--all` (bash) to include the items at Backlog and Done. If it exits with 2, show
its message and stop: it is a missing config, a missing or logged-out `gh`, or a failed `gh` call.

When the maintainer asks for JSON (or passes `json`), add `-Json` (PowerShell) or `--json` (bash), combinable with
the option for all items: the script prints one JSON object on one line. Show that output exactly as printed and add
none of the three lines below.

Show the table as the script printed it, then add at most three lines:

1. What waits for the maintainer: the issue numbers at **Spec review** (spec to read and approve) and
   **Approved** (waiting for a worker; `/next` takes it).
2. What is flagged (`stale: ...`) and who fixes it: Review with a merged PR is board automation or the
   maintainer; a busy slot with a merged PR is `slot --release N`, a dropped one `slot --abandon N`;
   a story at Spec, Spec review, In progress or Review with a branch, a slot or a pull request behind it is continued
   by `/spec N` (Spec, Spec review) or `/next N` (In progress, Review); with nothing behind it the maintainer moves
   it back to Ready or Approved. A `stalled` slot is one whose
   agent has not reported for `worktrees.stalledAfterMinutes` (the session may have ended or crashed; with the step
   `done` the run is over and the slot waits for its merge): a `/next` run left there is continued by `/next N` (the
   issue of the slot's iteration), or the maintainer looks at it and, if it was dropped, frees
   it with `slot --abandon N`; a merged one is freed by `slot --release N`, `--reap` or the next take.
3. That nothing was changed.

Do not fix a flag yourself, do not move a card, do not release a slot: say what would fix it and let the
maintainer decide. If the table is empty, say that nothing is waiting.
