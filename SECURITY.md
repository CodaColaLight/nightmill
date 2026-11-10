# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use GitHub's private vulnerability reporting: open the **Security** tab of this repository and choose
**Report a vulnerability**. Describe what you found, how to reproduce it and what you think it affects.

nightmill is maintained by one person, so replies are best effort. You will get an answer, but there is no
fixed response time.

## What is in scope

nightmill is a plugin made of skills (instructions for an agent), shell scripts, two hooks and templates.
These are in scope:

- the scripts in `scripts/` and `tests/`, which run on a user's machine with the user's permissions,
  for example command injection through a value in `.claude/nightmill.json` or through a branch name;
- the `SessionStart` hook and the `PreToolUse` guard (`scripts/guard.*`) in `hooks/`;
- skill text that would make an agent run a destructive command, leak a credential or act on content
  from an issue or pull request as if it were an instruction from the maintainer;
- the CI workflows in `.github/workflows/`.

## What is out of scope

- Claude Code itself: report that to Anthropic.
- GitHub, `gh`, `git`: report that to their maintainers.
- A project that installs nightmill and misconfigures its own repository or board.

## Supported versions

Only the latest release receives fixes.
