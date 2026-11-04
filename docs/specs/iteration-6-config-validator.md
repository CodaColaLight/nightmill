# Iteration 6: a config validator that reads the schema

Status: delivered in iteration 6 (PR #PRNUM)

Story: #8, epic #3 (Scripts without extra tools). Adds `scripts/validate-config.ps1` and
`scripts/validate-config.sh`, their smoke tests, a lint check, and one change to the `/init` skill. No
config key, no change to the status flow, no change to the slot marker: none of `escalation.storyTriggers`
applies, so the PR may auto-merge.

## Goal

A wrong or misspelled config is caught by a command, not by a skill misbehaving later.

## Facts this rests on

- `schema/nightmill.schema.json` describes every key. Nothing runs it: `/init` is told to "check it against
  the schema by reading both", and the lint only checks that JSON parses. A key like `worktree` for
  `worktrees` is silently ignored by every script.
- The schema uses only these keywords that constrain a value: `type` (`object`, `string`, `integer`,
  `array`), `properties`, `required`, `items`, `minimum`, `minItems`, and one `additionalProperties` (a
  schema for the port numbers). `$id`, `$schema`, `title`, `description` and `default` constrain nothing.
  The schema says "Unknown keys are ignored", so an unknown key is a warning, not an error.
- The bash scripts need `jq` today (the README says so). Story #7 is about changing that for all of them.
  This machine has no `jq`, so a bash script that needs it cannot run here; CI on Ubuntu has it.

## The scripts

`scripts/validate-config.ps1` and `scripts/validate-config.sh`, the same behaviour and the same output.

| | PowerShell | bash |
|---|---|---|
| Validate the default file | `validate-config.ps1` | `validate-config.sh` |
| Validate another file | `-Config path` | the path as the only argument |
| Another schema (tests) | `-Schema path` | `--schema path` |
| Warnings fail too | `-Strict` | `--strict` |

The default config is `.claude/nightmill.json` and the default schema is `schema/nightmill.schema.json`, both
relative to the repository the script lives in. The bash version needs `jq` and says so (`missing tool: jq`,
exit code 2) when it is absent. The PowerShell version needs nothing beyond PowerShell. Files are read as
UTF-8.

The validator is generic: it walks the schema, it does not hard-code keys. It supports exactly the keywords
`type`, `properties`, `required`, `items`, `minimum`, `minItems`, `additionalProperties` (a schema, `true`
or `false`) and `enum`, and ignores the keywords that constrain nothing. `integer` accepts a whole number, not
a string and not a boolean. `enum` is not used by the schema today; it is supported so that a future key can
use it, and tested with a small schema of its own.

### Findings and output

Output goes to standard output, one finding per line, then a summary:

```
validating .claude/nightmill.json against schema/nightmill.schema.json
error: worktrees.slots: expected integer, got string
warning: worktree: unknown key (did you mean "worktrees"?)
1 error, 1 warning
```

A path is the keys joined with dots, with `[i]` for an array item: `github.owner`, `areas[1]`,
`worktrees.warmup[0].command`. The finding texts are fixed:

| Finding | Severity | Text after the path |
|---|---|---|
| required key missing | error | `required key is missing` |
| wrong type | error | `expected <type>, got <actual>` with actual one of `string`, `integer`, `number`, `boolean`, `array`, `object`, `null` |
| below `minimum` | error | `must be at least <minimum>, got <value>` |
| fewer than `minItems` | error | `needs at least <n> items, got <m>` |
| not in `enum` | error | `must be one of: <a>, <b>, got <value>` |
| key not allowed (`additionalProperties: false`) | error | `unknown key is not allowed` |
| key not in `properties` (no `additionalProperties`) | warning | `unknown key`, plus ` (did you mean "<key>"?)` when a known key of the same object equals it ignoring case, or equals it with one trailing character added or removed |
| the file is not valid JSON, or not an object | error | path `.`, text `not valid JSON` or `expected object, got <actual>` |

The key `$schema` is never reported. A `description`, `title` or `default` in the schema never produces a
finding. Findings are sorted by path (plain character order), errors before warnings on the same path, so
that both shells print the same lines. The summary is `<E> error(s), <W> warning(s)` with `error` and
`warning` singular for exactly one (`0 errors, 0 warnings`, `1 error, 2 warnings`).

Exit code: 0 when there is no error (and, with `--strict`, no warning); 1 when there is an error, or a
warning under `--strict`; 2 for a usage error, an unknown option, an unreadable file or a missing tool.

## `/init`

In `skills/init/SKILL.md` the **Config** line of the plan no longer says "check it against the schema by
reading both (a validator script is a separate story)". It says: after the file is written, run the
validator (`"${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.ps1" -Config .claude/nightmill.json`, or
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.sh" .claude/nightmill.json`); an error is fixed and the
validator run again before the plan is shown; a warning is listed in the plan. The report's **Config** row
carries the summary line (for example `0 errors, 0 warnings`). The lint's init check gains the file name
`validate-config`.

## The lint

`tests/lint.sh` gains two checks:

- `config validates`: `templates/nightmill.example.json` and this repository's `.claude/nightmill.json` pass
  the validator with `--strict`. It uses the bash validator when `jq` is installed, else the PowerShell one
  when PowerShell is installed, else it prints `skipped (no jq and no PowerShell)`. Any finding in those two
  files is fixed in the same pull request.
- `schema keywords are supported`: the schema contains none of `$ref`, `anyOf`, `oneOf`, `allOf`, `not`, `if`,
  `pattern`, `format`, `const`, `maxItems`, `uniqueItems`, `minLength`, `maxLength`, `maximum`, `dependencies`,
  so a schema change that the validator would silently ignore fails the lint instead.

## Other changes

- `tests/smoke-validate.sh` and `tests/smoke-validate.ps1` (below), added to `tests/check.sh` (the bash one
  with the other jq tests, so it is skipped with a notice where `jq` is missing) and to the bash and
  PowerShell jobs of `.github/workflows/ci.yml`.
- `README.md`: the Configuration section says the file can be checked with the script; both smoke tests in the
  command list. `CHANGELOG.md`: a bullet under `Unreleased` for iteration 6 (#8). No decision record: no flow
  or status changes.

## Tests

`tests/smoke-validate.sh` and `tests/smoke-validate.ps1`, the same cases in both, each writing broken copies
of `templates/nightmill.example.json` into a temporary folder and checking the exit code and the exact
finding line:

1. **The example is clean**: exit 0, `0 errors, 0 warnings`. The same with `--strict`.
2. **Errors name the key** (exit 1): `github.owner` removed → `error: github.owner: required key is missing`;
   `worktrees.slots` set to `"two"` → `error: worktrees.slots: expected integer, got string`;
   `github.projectNumber` set to `0` → `error: github.projectNumber: must be at least 1, got 0`;
   `areas` set to `[]` → `error: areas: needs at least 1 items, got 0`; `areas[1]` set to `3` →
   `error: areas[1]: expected string, got integer`; `worktrees.ports.server` set to `"x"` →
   `error: worktrees.ports.server: expected integer, got string`; `maintainer` removed →
   `error: maintainer: required key is missing`; `verification.check` set to `true` →
   `error: verification.check: expected string, got boolean`; a config that is the text `[1]` → `error: .:
   expected object, got array`; a config with a trailing comma → `error: .: not valid JSON`.
3. **Several findings at once** print in the sorted order and the summary counts them (`2 errors, 1 warning`).
4. **Unknown keys are warnings**: an added top-level `worktree` → `warning: worktree: unknown key (did you mean
   "worktrees"?)`, exit 0; the same with `--strict` exits 1; an added `github.org` →
   `warning: github.org: unknown key`; `$schema` produces nothing.
5. **`enum` and `additionalProperties: false`** with a two-key schema of its own (`--schema`): a value outside
   the enum → `error: mode: must be one of: fast, slow, got "medium"`; an extra key under a closed object →
   `error: extra: unknown key is not allowed`.
6. **Usage**: a missing file → exit 2 and a message that names the path; an unknown option → exit 2.
7. **The real files**: the repository's own `.claude/nightmill.json` passes with `--strict`.
8. The lint check `schema keywords are supported` reports a schema copy that gains a `pattern`.

The existing lint, smoke tests and `claude plugin validate --strict` keep passing.

Manual check (a script that other skills call): run `/init`'s config line by hand on the example and on a copy
with `worktree` misspelled; both shells print the same lines. The PR describes what was seen. The bash smoke
test cannot run on the maintainer's machine without `jq`; CI runs it.

## Not done

- Fixing a config automatically.
- Rules the schema does not express: that a status name is unique, that a path exists, that `gh` can see the
  project, that a port is free.
- Validating a config against a schema other than this one beyond the keywords listed.
- Removing the `jq` dependency of the bash validator (story #7 covers the bash scripts together).
- A JSON Schema validator for anything but `.claude/nightmill.json`.

## Decisions for the maintainer

1. **The bash validator needs `jq`** until #7 lands, like the other bash scripts. If you want it without
   `jq` from the start, do #7 first; this spec then changes only in how the bash version reads JSON.
2. **A warning does not fail the validator** unless `--strict`; the lint uses `--strict` so the example and
   this repository's config stay free of unknown keys.
3. **The `did you mean` rule is deliberately small** (case, one trailing character). It catches `worktree`
   and `area`; it does not catch `worktres`. A real edit-distance rule is more code in two shells for a
   hint.
