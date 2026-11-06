---
name: control
description: Run one pass of the opt-in load controller - measure CPU and memory, then raise or lower the agent limit within the configured bounds, or only say what it would change. Use in a loop (/loop 5m /nightmill:control) or when asked to adjust the agent limit to the machine's load.
---

Run one pass of the load controller. This skill changes nothing itself: only the script changes the agent limit and
the slot count, and only when `parallel.controlMode` is `apply`.

Run the script of the shell in use, from inside the project (any checkout or worktree), and wait for it (it measures
for `parallel.loadWindowSeconds` seconds, 10 by default):

- PowerShell (Windows): `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/control.ps1"`
- bash: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/control.sh"`

Show the lines it printed, and any warning on standard error, as they are, and add nothing. Exit 0 or 1 ends the pass
(1: it could not measure and changed nothing). Exit 2: show its standard error and end this pass; a loop goes on with
its next pass.

When this runs in a `/loop` without an interval, run the next pass after the minutes of its `control: next pass in`
line.

Do not change the numbers by hand (`slot --capacity`), do not edit the config or a file under `.slots`, do not stop an
agent or free a slot, and do not turn the controller on or off: the maintainer sets `parallel.controlMode`.
