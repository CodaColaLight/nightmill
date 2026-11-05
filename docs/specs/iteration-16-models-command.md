# Iteration 16: /nightmill:models, one table of each role's model

Status: delivered in iteration 16 (PR #72)

Story: #34, epic #28 (Agent roles and models). Adds the skill `/nightmill:models` and the scripts behind it,
`scripts/models.ps1` and `scripts/models.sh`, which print one table: every agent role, what it does, the model it
runs on, whether that model comes from the config or from the schema default, its rank, and whether its pairing
holds. Adds a smoke test per shell, a lint section, the CI and `tests/check` wiring, a README row and a CHANGELOG
entry. No config key, no change to the status flow or the slot marker, and nothing in the workflow skill or the
schema (both hot files): none of `escalation.storyTriggers` applies, so the PR may auto-merge. The change adds a
skill, a path in `verification.manualCheckPaths`, so the manual check applies.

**Depends on #32 (iteration 15), the pairing rule of the validator.** This story prints the same verdict as that
rule and a smoke step compares the two, so it is implemented after #32 has merged.

## Goal

One command shows which model every role runs on, where the value comes from, and whether any reviewer ranks below
its producer, without reading the config and the schema defaults side by side.

## Facts this rests on

- The effective model of a role is `roles.<role>.model` when that is a non-empty string, else the `default` of
  `properties.roles.properties.<role>.properties.model` in the schema (workflow skill, "Agent roles and models",
  iteration 11). The effective ranking is `models.ranking`, else the default of the schema key. A ranking entry holds
  one model name or several joined by `=`; the rank of a name is the position of the first entry that names it
  (iterations 10 and 15).
- Iteration 15 defines the verdict: `specReviewer` over `specWriter`, `codeReviewer` over `implementer` and over
  `fixer`; an error when a reviewer's rank is lower than a producer's, a warning for a model of one of those five
  roles that is not in the ranking; `tester` and `worker` are never compared; the rule is skipped when
  `models.ranking` is present and not a non-empty array. This story shows that verdict, it does not redefine it.
- `/status` (iteration 8) is the model for a read-only table: a skill that runs the script of the shell in use,
  shows its output and adds at most three lines; the scripts exist as `.ps1` and `.sh` with a smoke test each, and
  exit 0 whenever the table was printed. `status.sh` finds the config in the main checkout through
  `git rev-parse --git-common-dir`, so it works from any worktree. This script does the same.
- The bash scripts read JSON with `scripts/lib/json.sh` and `json.awk`, no `jq`; CI hides `jq` before the bash smoke
  tests. The PowerShell script uses `ConvertFrom-Json`. Both read the schema and the config as UTF-8.
- A skill that names `nightmill.json` must inject the config (the lint's "skills" check). The new skill needs only
  the table, so it does not name the file and injects nothing.
- Today the only place that shows a role's model is the config, and only if the key is set; a missing key means a
  default that is written in the schema. Nothing prints the two together.

## Decisions

**1. A script, not a skill that computes.** The table must be the same every time and testable, and the verdict must
not depend on a session reading a schema correctly. So the work is in scripts, in both shells, with a smoke test in
each; the skill only runs the script and comments, as `/status` does.

**2. The script has its own small computation, checked against the validator.** It resolves the effective model and
the rank itself (about thirty lines in each shell) instead of extracting a library out of the validator, which would
change the unmerged work of #32 and tie two stories together. To keep the two from drifting, a smoke step runs both
the script and `validate-config` on the same configs and requires the counts to agree (see "Tests").

**3. The verdict is a column and a summary line, and never an exit code.** Like `/status`, the script exits 0 when it
printed the table, whatever the flags say. Stopping a bad config is the validator's job (and `/init`'s, and the
lint's); this command is a view.

**4. Rank is a 1-based position.** The weakest entry is 1; models of one level share a number; `-` means unranked.
It is shown for every role, `tester` and `worker` included, because it is information, but those two are never
flagged.

**5. The text of "does" is fixed in the script**, one short line per role, not read from the schema descriptions
(which carry extra sentences). The lint checks that the roles of the script are the roles of the schema, so a role
added to the schema fails the lint until the script knows it.

## The scripts

`scripts/models.ps1` and `scripts/models.sh`, the same output.

| | PowerShell | bash |
|---|---|---|
| Print the table | `models.ps1` | `models.sh` |
| Another config (tests) | `-Config path` | `--config path` |
| Another schema (tests) | `-Schema path` | `--schema path` |

The default config is `.claude/nightmill.json` of the main checkout (found with `git rev-parse --git-common-dir`,
so it works from a slot), the default schema is `schema/nightmill.schema.json` of the plugin the script lives in.
Needs git only to find the default config; with `--config` it needs nothing but bash and awk (PowerShell for the
other). The script only reads: it writes no file, runs no `gh`, changes no repository.

Exit code: 0 when the table was printed (flags do not change it); 2 for a usage error, an unknown option, a missing
or unreadable config or schema, a config that is not a JSON object, or a call outside a git checkout without
`--config`. The message for 2 names the file and goes to standard error; a missing default config says
`run /nightmill:init`.

### The roles and their texts

In this order, which is the order of the schema:

| Role | does |
|---|---|
| `specWriter` | `writes the spec of a Ready story` |
| `specReviewer` | `reviews specWriter` |
| `tester` | `writes the failing tests before the code` |
| `implementer` | `writes the code of an Approved story` |
| `codeReviewer` | `reviews implementer and fixer` |
| `fixer` | `fixes a bug` |
| `worker` | `does mechanical, fully specified jobs` |

### The table

Columns `role`, `does`, `model`, `from`, `rank`, `check`. Every column but the last is left-aligned and padded to
its widest cell (header included), columns are separated by two spaces, the last column is not padded, there is no
rule line and no trailing space, only ASCII, LF line endings. The cells:

- `model`: the effective model; `-` when neither the config nor the schema has one.
- `from`: `config` when `roles.<role>.model` is a non-empty string, else `default`. A value of the wrong type counts
  as not set (the validator reports the type).
- `rank`: the 1-based position of the first ranking entry that names the model; `-` when none does or when the
  ranking is invalid (below).
- `check`, by role:
  - `specReviewer`, `codeReviewer`: `ok` when no pair of the role is below; `BELOW <producers>` when its rank is lower
    than a producer's, the producers in the order of the table (`BELOW implementer, fixer`); `NOT RANKED` when its
    own model has no rank. A producer that has no rank is not a reason for `BELOW` or `NOT RANKED` here: it is
    flagged on its own row.
  - `specWriter`, `implementer`, `fixer`: `NOT RANKED` when the model has no rank, else `-`.
  - `tester`, `worker`: always `-`, ranked or not.

### The lines below the table

After one empty line, in this order:

1. `ranking: <entries joined by " < "> (config)` or `(default)`, the entries as written, weakest first, `=` kept:
   `ranking: haiku < sonnet < opus=claude-opus-5-5 < fable (config)`. When `models.ranking` is present and is not a
   non-empty array: `ranking: invalid (needs a non-empty list; run validate-config)`; then every `rank` is `-`, every
   `check` is `-` and the next line is `pairings: not checked`.
2. `pairings: ok` when no row is `BELOW` and none is `NOT RANKED`; otherwise `pairings: <B> below, <U> not ranked`
   with `B` the number of (reviewer, producer) pairs that are below (up to three) and `U` the number of the five
   roles of the pairs whose model has no rank. These are the counts of errors and of warnings that
   `validate-config` gives for the pairing rule.
3. Only when no role takes its model from the config and `models.ranking` is absent:
   `No role model and no ranking in the config: these are the defaults of the schema.`

Example: no keys in the config.

```
role          does                                      model   from     rank  check
specWriter    writes the spec of a Ready story          opus    default  3     -
specReviewer  reviews specWriter                        opus    default  3     ok
tester        writes the failing tests before the code  sonnet  default  2     -
implementer   writes the code of an Approved story      opus    default  3     -
codeReviewer  reviews implementer and fixer             opus    default  3     ok
fixer         fixes a bug                               opus    default  3     -
worker        does mechanical, fully specified jobs     haiku   default  1     -

ranking: haiku < sonnet < opus < fable (default)
pairings: ok
No role model and no ranking in the config: these are the defaults of the schema.
```

Example: `roles.specReviewer.model` is `"sonnet"` and `roles.specWriter.model` is `"opus"`.

```
role          does                                      model   from     rank  check
specWriter    writes the spec of a Ready story          opus    config   3     -
specReviewer  reviews specWriter                        sonnet  config   2     BELOW specWriter
tester        writes the failing tests before the code  sonnet  default  2     -
implementer   writes the code of an Approved story      opus    default  3     -
codeReviewer  reviews implementer and fixer             opus    default  3     ok
fixer         fixes a bug                               opus    default  3     -
worker        does mechanical, fully specified jobs     haiku   default  1     -

ranking: haiku < sonnet < opus < fable (default)
pairings: 1 below, 0 not ranked
```

## The skill

`skills/models/SKILL.md`, name `models`, description: shows which model every agent role runs on, where the value
comes from, its rank and whether any reviewer ranks below its producer, as one table; read-only; for questions about
the role models or the pairings. Like `/status` it has no config injection and does not name the config file. Its
body:

- run the script of the shell in use (`models.ps1` or `models.sh` under `${CLAUDE_PLUGIN_ROOT}/scripts/`) from inside
  the project and wait for it; if it exits with 2, show its message and stop;
- show the table and the lines below it as the script printed them, then at most two lines: (1) what is flagged and
  who fixes it: a `BELOW` row means the owner sets that role's model or `models.ranking` in the config, a
  `NOT RANKED` row means the model is missing from `models.ranking`; `/nightmill:init` or `validate-config` report the
  same; (2) that nothing was changed;
- never edit the config, never change a model: the owner does.

## README

- The skills table gets a row `/nightmill:models`: one table of each agent role's model, where it comes from, its
  rank and whether the reviewer pairings hold; read-only.
- "Agent roles and models": one sentence naming the command.
- The command list under "Developing nightmill" gets `bash tests/smoke-models.sh` and the PowerShell line.

## Other wiring

- `tests/check.sh` and `tests/check.ps1` run `smoke-models`; `.github/workflows/ci.yml` runs it in the bash job (with
  `jq` hidden) and in the PowerShell job.
- `CHANGELOG.md`: an entry for iteration 16 (#34) under Unreleased.

## Tests

Each acceptance criterion of #34 is a test or a manual scenario. Names are the behaviour protected.

**`tests/smoke-models.sh` and `tests/smoke-models.ps1`**, the same cases in both, each writing configs into a
temporary folder and comparing the whole output (all lines, in order) with the expected text:

1. **No keys prints the defaults and says so**: the config reduced to `github`, `maintainer` and
   `verification.check` gives exactly the first example above, exit 0.
2. **A fully configured config**: the example (`templates/nightmill.example.json`): every `from` is `config`, the
   ranking line says `(config)`, `pairings: ok`, no defaults sentence.
3. **A reviewer below its producer is flagged**: the second example above; `pairings: 1 below, 0 not ranked`.
4. **The code reviewer below both producers**: `codeReviewer` on `haiku` gives `BELOW implementer, fixer` and
   `pairings: 2 below, 0 not ranked`.
5. **A model that is not in the ranking is flagged**: `specReviewer` on `mystery` gives rank `-` and `NOT RANKED`;
   `implementer` on `mystery` flags the `implementer` row and leaves `codeReviewer` at `ok`; the summary counts them
   (`pairings: 0 below, 1 not ranked`).
6. **`tester` and `worker` are never flagged**: `tester` on `haiku` and `worker` on `mystery` give `-` in `check`
   and `pairings: ok`; the worker's rank is `-`.
7. **Same level**: a ranking with `"opus=claude-opus-5-5"` and `specWriter` on `claude-opus-5-5`: both rows show the
   same rank, `check` is `ok`, the ranking line keeps the `=`.
8. **An empty model takes the default**: `specReviewer` set to `""` shows `default`.
9. **An invalid ranking**: `"ranking": "opus"` prints `ranking: invalid ...`, `-` in every `rank` and `check`, and
   `pairings: not checked`, exit 0.
10. **Usage errors exit 2**: a missing config names the path on standard error; a config that is not JSON, or not an
    object, exits 2; an unknown option exits 2.
11. **It changes nothing**: the config file's bytes and the list of files in the temporary folder are the same
    before and after a run.
12. **It agrees with the validator**: for the configs of cases 3, 4 and 5 (and the two clean ones), run
    `validate-config` of the same shell; the number of its `error:` lines equals `B` and the number of its `warning:`
    lines equals `U`.
13. **It finds the config from a worktree**: in a temporary git repository with `.claude/nightmill.json`, run the
    script without `--config` from a subfolder and from a second worktree of that repository; both print the table.

**`tests/lint.sh`**, new section "== models is wired": `skills/models/SKILL.md`, `scripts/models.sh`,
`scripts/models.ps1`, `tests/smoke-models.sh` and `tests/smoke-models.ps1` exist; the README names
`/nightmill:models`; neither script contains a word that writes or calls out (`gh `, `curl`, `Set-Content`,
`Out-File`, `Add-Content`, `Remove-Item`, `New-Item`, or a `git` call other than `rev-parse`, outside comment
lines); every role key of the schema's `roles` appears in both scripts; the skill does not contain `nightmill.json`;
`tests/check.sh`, `tests/check.ps1` and `ci.yml` mention `smoke-models`.

`bash tests/check.sh` stays green.

## Verification

The change adds a skill, so the manual check applies: run `/nightmill:models` in a project with
`claude --plugin-dir <checkout>`:

1. **In this repository** (all roles set): the table of the second case, `pairings: ok`, no defaults sentence.
2. **In a project without the keys**: the first example and the defaults sentence.
3. **With a deliberately wrong config** (`specReviewer` on `haiku`): the `BELOW specWriter` row, the summary, and the
   skill's lines say who fixes it and that nothing was changed.
4. **Nothing is changed**: `git status` is clean afterwards and the board is untouched.
5. **From a slot**: the same table.

The PR's "How verified" lists the five results, the smoke cases of both shells, and the check.

## Not done

- No change of a model from the command; the owner edits the config.
- No cost report.
- No check that a model exists or that this machine can use it.
- No change to the validator, the schema, the workflow skill or any other skill.
- No extraction of a shared library from the validator; the cross-check step keeps the two in step.
- The table is not translated and not coloured; flags are plain text so the table survives a log file.
- No change to the status flow, to who sets a status, to the slot marker or to any config key.
