# Contributing to nightmill

Thank you for looking. nightmill is a Claude Code plugin that runs a lights-out development workflow from a
GitHub project board; `README.md` explains what it does. This file explains how to report a problem, how
changes are decided here, and what a pull request has to satisfy.

## Reporting a problem or an idea

Use the forms under **Issues > New issue**: *Report a problem with nightmill* for something that does not
work as documented, *Suggest an idea for nightmill* for a change you would like.

A security problem is not filed as an issue. Report it privately, as described in `SECURITY.md`.

## How work is decided here

nightmill develops itself with its own workflow. Work is tracked on a project board, and the status of an
issue on that board is the only thing that starts work:

- **Ready** and **Approved** are set by the maintainer and nobody else. A story is only specified when it is
  Ready and only implemented when it is Approved, whether the worker is a person or an agent.
- An issue from outside is triaged by the maintainer. It is closed, answered, or turned into a story.
- Pull requests for a **bug fix** or a **documentation fix** are welcome directly.
- A **new feature or a change of behaviour** needs an idea issue first and a story that is Ready, because the
  spec is written before the code. A pull request for a feature nobody asked for may be closed.

## Setting up

1. Fork the repository and clone your fork.
2. Start Claude Code in the clone with the released plugin installed (`/plugin install nightmill@nightmill`).
   To try a skill you changed, start a session in another folder with `claude --plugin-dir <path to your
   clone>`. Avoid `claude --plugin-dir .` in the folder you edit: a folder loaded that way is a protected
   path, so Claude Code does not auto-approve writes to it. Do not load the same skills twice (installed and
   `--plugin-dir`) in one session: they shadow each other.
3. Set a git identity for the clone. GitHub's no-reply address is fine if you would rather not publish your
   email.

## Before you open a pull request

Run the check:

```
bash tests/check.sh
```

The full check runs the lint, the bash smoke tests, the PowerShell smoke tests (when PowerShell is installed),
`claude plugin validate` and `claude plugin test` (when `claude` is installed and has them). It runs up to
`verification.checkJobs` steps at once (default 4, never more than the processors; `--jobs 1` runs them one after
another) and lists what it skipped. `bash tests/check.sh --quick` runs the lint and the bash smoke tests only: it is
for the loop while you write code and is never the check before a commit or a pull request. CI runs all of them, the
bash ones on Ubuntu and the PowerShell ones on Windows, so a skipped test is not a reason to leave a change untested.

The rules a change has to keep:

- **Two shells.** Every script exists in PowerShell and in bash and behaves the same, with a smoke step in
  both test families.
- **Config keys are a contract.** A new key goes into the schema with a description and a default, into the
  example file and into the README's configuration table. Renaming or removing a key is a story of its own.
- **The status flow is fixed.** The eight statuses and who sets them change only with a decision record in
  `docs/decisions/`.
- **Changelog.** Add a bullet under `Unreleased` in `CHANGELOG.md`.
- **Generic.** nightmill must not know any project, person or local path. Keep them out of every file, issue
  and comment. The check for this uses a private word list and does not run on pull requests from forks, so
  the maintainer checks it in review.

## License

nightmill is licensed under the Apache License 2.0, see `LICENSE`. A contribution is licensed under the same
terms.
