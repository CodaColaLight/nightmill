# Iteration 10: a model for each agent role, and the model ranking

Status: delivered in iteration 10 (PR #49)

Story: #31, epic #28 (Agent roles and models). Adds three optional config keys (`roles`, `models`, `review`)
to `schema/nightmill.schema.json`, `templates/nightmill.example.json` and the README, puts them in this
repository's own config, and adds lint and validator-smoke steps that protect them. It adds **new config
keys**, which is one of `escalation.storyTriggers`: the implementation PR is **not** auto-merged. No change to
the status flow, the slot marker or any script.

## Goal

The factory owner sets, in one block of `.claude/nightmill.json`, the model of every agent role, the order of
the models from weakest to strongest, and how many fix rounds a producer gets after a review. A project that
sets none of it works exactly as before.

## Facts this rests on

- Models are chosen in scattered places today: `agents/worker.md` has `model: haiku` in its frontmatter, the
  workflow skill says "a strong model for specs and implementation" (Parallel work), and every other agent
  runs on the model of the session. There is no config key for any of it.
- The Agent tool takes the model aliases `haiku`, `sonnet`, `opus` and `fable`; a full model id is also a
  model name. Which of them a machine can use is not known to nightmill and is not checked here.
- `scripts/validate-config.*` walks the schema and supports `type`, `properties`, `required`, `items`,
  `minimum`, `minItems`, `additionalProperties` and `enum`; the lint fails on any other keyword. Everything
  below is expressed with those, so the validator checks the new keys without a change to its code. An unknown
  key under an object is a warning with a "did you mean" hint, an error under `--strict`.
- The schema's `default` values are documentation and the source of defaults for the scripts that read the
  schema (`template-board.*` does); a `default` constrains nothing.
- Nothing reads the new keys when this iteration ships. The stories that follow (#32 the pairing rule, #33 how
  a skill picks a model, #34 `/models`, and the review epics) use them. That is why a project without the keys
  cannot behave differently.

## The keys

All three top-level keys are optional, and so is every key inside them. `required` of the root is unchanged
(`github`, `maintainer`, `verification`).

### `roles`

An object with one optional entry per role. Each entry is an object with one key, `model`, a string: a model
alias or a full model id. The entry is an object, not a bare string, so that a later story can add a key to a
role without renaming anything.

| Role key | Does | Reviews | Default model |
|---|---|---|---|
| `specWriter` | writes the spec of a Ready story | | `opus` |
| `specReviewer` | reviews a spec before it goes to Spec review | `specWriter` | `opus` |
| `tester` | writes the failing tests from the approved spec, before the implementer | | `sonnet` |
| `implementer` | writes the code of an Approved story | | `opus` |
| `codeReviewer` | reviews the change before the pull request opens | `implementer`, `fixer` | `opus` |
| `fixer` | fixes a bug | | `opus` |
| `worker` | does mechanical, fully specified jobs (the `worker` agent) | | `haiku` |

A role whose entry is missing, or whose `model` is missing or an empty string, takes the default of the table.
The defaults are in the schema as the `default` of each `model`. The "Reviews" column is the pairing that the
validator will enforce in #32 (a reviewer must rank at least as high as each role it reviews); this iteration
only records it, in the schema's description of the reviewers. The defaults satisfy it (a reviewer on `opus`
reviews a producer on `opus`) and are the same level, not a higher one, so that the defaults cost no more than
the strongest model nightmill already asks for. `worker` stays `haiku`, the model in `agents/worker.md`.

Schema, under `properties`:

```json
"roles": {
  "type": "object",
  "description": "The model each agent role runs on. A role that is absent, or whose model is empty, takes the default shown. specReviewer must rank at least as high as specWriter, and codeReviewer at least as high as implementer and fixer (checked by the validator once models.ranking is set).",
  "properties": {
    "specWriter": { "type": "object", "description": "Writes the spec of a Ready story.", "properties": { "model": { "type": "string", "default": "opus", "description": "Model alias or full model id." } } },
    "specReviewer": { "type": "object", "description": "Reviews a spec before it goes to Spec review. Reviews specWriter.", "properties": { "model": { "type": "string", "default": "opus", "description": "Model alias or full model id." } } },
    "tester": { "type": "object", "description": "Writes the failing tests from the approved spec, before the implementer. Not compared with any other role.", "properties": { "model": { "type": "string", "default": "sonnet", "description": "Model alias or full model id." } } },
    "implementer": { "type": "object", "description": "Writes the code of an Approved story.", "properties": { "model": { "type": "string", "default": "opus", "description": "Model alias or full model id." } } },
    "codeReviewer": { "type": "object", "description": "Reviews the change before the pull request opens. Reviews implementer and fixer.", "properties": { "model": { "type": "string", "default": "opus", "description": "Model alias or full model id." } } },
    "fixer": { "type": "object", "description": "Fixes a bug.", "properties": { "model": { "type": "string", "default": "opus", "description": "Model alias or full model id." } } },
    "worker": { "type": "object", "description": "Does mechanical, fully specified jobs (the worker agent).", "properties": { "model": { "type": "string", "default": "haiku", "description": "Model alias or full model id." } } }
  }
}
```

### `models`

```json
"models": {
  "type": "object",
  "description": "What nightmill needs to know about models.",
  "properties": {
    "ranking": {
      "type": "array",
      "items": { "type": "string" },
      "minItems": 1,
      "default": ["haiku", "sonnet", "opus", "fable"],
      "description": "Models from weakest to strongest; a model's rank is its position. Name models of the same level in one entry, joined by =, for example \"opus=claude-opus-5-5\". List the aliases and the full model ids that roles use."
    }
  }
}
```

An entry is one model name, or several names of the same level joined by `=` with no spaces. A name never
contains `=`, so the split is unambiguous. Two roles are on the same level when their models are in the same
entry (or are the same name). The default lists the four aliases. A model that a role uses and that no entry
names has no rank; the validator (#32) reports it as a warning. This iteration only describes the format; it
does not parse it.

### `review`

```json
"review": {
  "type": "object",
  "description": "How the internal reviews work.",
  "properties": {
    "maxFixRounds": { "type": "integer", "minimum": 0, "default": 2, "description": "How many times a producer may fix what its reviewer found before the work is handed to the maintainer. 0 hands over after the first review." }
  }
}
```

The key is `maxFixRounds`. Its default, 2, is the maintainer's decision recorded in #28.

### Where they go

In `schema/nightmill.schema.json`, `roles`, `models` and `review` come after `escalation` and before `git`.
In the example and in this repository's config, in the same place.

## `templates/nightmill.example.json`

After the `escalation` block and before `git`:

```json
  "roles": {
    "specWriter": { "model": "opus" },
    "specReviewer": { "model": "opus" },
    "tester": { "model": "sonnet" },
    "implementer": { "model": "opus" },
    "codeReviewer": { "model": "opus" },
    "fixer": { "model": "opus" },
    "worker": { "model": "haiku" }
  },
  "models": { "ranking": ["haiku", "sonnet", "opus", "fable"] },
  "review": { "maxFixRounds": 2 },
```

## This repository's config

`.claude/nightmill.json` gets the same block in the same place, so that the lint's validation of the
repository's own config covers the keys present and the factory owner of nightmill sees the models in use.

## README

In the configuration table, three rows after `escalation.storyTriggers`:

| Key | What it holds |
|---|---|
| `roles` | The model of each agent role (`roles.<role>.model`): `specWriter`, `specReviewer`, `tester`, `implementer`, `codeReviewer`, `fixer`, `worker` |
| `models.ranking` | The models from weakest to strongest, for judging that a reviewer is at least as strong as the role it reviews |
| `review.maxFixRounds` | How many fix rounds a producer gets after a review |

Under the table, a short paragraph "Agent roles and models": the seven roles with what each does and its
default (the table of this spec without the "Reviews" column), which roles review which, that an absent role
takes its default, that models of the same level share a `ranking` entry joined by `=`, and that the keys are
all optional. It says nothing about which skills use them yet.

## Tests

Each acceptance criterion of #31 is a test. Names are the behaviour protected.

**`tests/lint.sh`**, new section "== roles and models are described", reading the schema, the example, this
repository's config and the README with `scripts/lib/json.sh`:

- the schema has `roles`, `models` and `review`, and every one of the seven roles has `roles.<role>.model`
  with a `type` of `string`, a `default` equal to the table above, and a `description`;
- `models.ranking` is an array with a `default` equal to `["haiku", "sonnet", "opus", "fable"]`;
  `review.maxFixRounds` is an integer with `minimum` 0 and `default` 2; every new object and key has a
  `description` or sits under one that has;
- none of the three keys is in the root `required` list, and no `required` was added anywhere under them
  (a project without the keys is valid);
- the example and `.claude/nightmill.json` each have the seven roles, `models.ranking` and
  `review.maxFixRounds`, and the example's values equal the schema defaults;
- the README mentions `roles`, `models.ranking`, `review.maxFixRounds` and every role key.

The existing "config validates" section already validates the example and the repository's own config with
`--strict`; with the keys present it covers the rule that they validate.

**`tests/smoke-validate.sh` and `tests/smoke-validate.ps1`**, the same cases in both, written like the
existing ones (an edit of the example, expected lines, exit code). New section "== roles, models and review":

| Case | Edit of the example | Expected |
|---|---|---|
| example with the new keys is clean | none | exit 0, `0 errors, 0 warnings`, also with `--strict` |
| a project without the keys is valid | the config reduced to `github`, `maintainer` and `verification.check` | exit 0, `0 errors, 0 warnings` |
| model not a string | `"implementer": { "model": "opus" }` becomes `"implementer": { "model": 3 }` | exit 1, `error: roles.implementer.model: expected string, got integer` |
| roles not an object | `roles` becomes `[]` | exit 1, `error: roles: expected object, got array` |
| ranking not an array | `"ranking": [...]` becomes `"ranking": "opus"` | exit 1, `error: models.ranking: expected array, got string` |
| ranking empty | `"ranking": []` | exit 1, `error: models.ranking: needs at least 1 items, got 0` |
| ranking entry not a string | the second entry becomes `3` | exit 1, `error: models.ranking[1]: expected string, got integer` |
| fix rounds negative | `"maxFixRounds": 2` becomes `-1` | exit 1, `error: review.maxFixRounds: must be at least 0, got -1` |
| fix rounds a string | `"maxFixRounds": "two"` | exit 1, `error: review.maxFixRounds: expected integer, got string` |
| zero fix rounds is allowed | `"maxFixRounds": 0` | exit 0, `0 errors, 0 warnings` |
| role key in the wrong case | `"codeReviewer"` becomes `"codereviewer"` | exit 0, `warning: roles.codereviewer: unknown key (did you mean "codeReviewer"?)`; with `--strict` exit 1 |
| unknown key inside a role | `"implementer": { "model": "opus", "effort": "high" }` | exit 0, `warning: roles.implementer.effort: unknown key` |

`bash tests/check.sh` stays green.

## Verification

The change touches no path in `verification.manualCheckPaths` (`skills`, `agents`, `hooks`), so no manual
check applies. The PR's "How verified" says so, lists the lint and smoke cases, and runs
`scripts/validate-config.sh --strict` on the example and on this repository's config.

## Not done

- No skill, agent or script reads the new keys. How a skill picks a role's model is #33; `/models` is #34.
- No check that a reviewer ranks at least as high as its producer, and no parsing of a `ranking` entry
  (the `=` form is only described here): #32.
- No check that a model name exists or that this machine can use it.
- `agents/worker.md` keeps its `model: haiku`; making it follow `roles.worker.model` is #33.
- `/init` does not ask for the models; the defaults are enough to start.
- No per-story model override, no cost budget, no change to the status flow.
- No new key inside a role other than `model`.
