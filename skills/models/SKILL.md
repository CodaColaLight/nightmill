---
name: models
description: Show which model every agent role runs on, where the value comes from (the config or the default), its rank and whether any reviewer ranks below the role it reviews - one table. Read-only. Use when asked which models the roles use, what the defaults are, or whether the reviewer pairings hold.
---

Show which model every agent role runs on. This skill reads and changes nothing.

Run the script of the shell in use, from inside the project (any checkout or worktree), and wait for it:

- PowerShell (Windows): `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/models.ps1"`
- bash: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/models.sh"`

If it exits with 2, show its message and stop: it is a missing or unreadable config, a config that is not a JSON
object, or a call outside a git checkout of the project.

Show the table and the lines below it as the script printed them, then add at most two lines:

1. What is flagged and who fixes it: a `BELOW` row means the owner sets that role's model, or `models.ranking`, in
   the config; a `NOT RANKED` row means the model is missing from `models.ranking`; an invalid ranking is fixed in
   the config too. The validator (`validate-config`, also run by `/nightmill:init`) reports the same.
2. That nothing was changed.

Do not edit the config or change a model yourself: say what would fix it and let the owner decide. If a line says
that these are the defaults of the schema, say so: the roles run on those models until the config sets them.
