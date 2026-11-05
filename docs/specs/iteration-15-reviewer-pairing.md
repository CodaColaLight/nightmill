# Iteration 15: the validator rejects a reviewer ranked below its producer

Status: draft, awaiting approval (#32)

Story: #32, epic #28 (Agent roles and models). Adds one rule to `scripts/validate-config.ps1` and
`scripts/validate-config.sh` (in the bash one, to `scripts/lib/validate.awk`): a reviewer role must rank at least as
high as each role it reviews, judged by `models.ranking`. Adds smoke cases in both shells and a lint section, one
sentence in the README and a wording fix in one schema description. No config key is added, renamed or removed, no
script flag, no change to the status flow or the slot marker: none of `escalation.storyTriggers` applies, so the PR
may auto-merge. The change touches no path in `verification.manualCheckPaths` (`skills`, `agents`, `hooks`), so no
manual check applies; the PR runs both validators on a deliberately wrong copy of the example instead.

## Goal

A config that puts a reviewer on a weaker model than the role it reviews is rejected by a command, as the other
config mistakes are, instead of by a night of weak reviews. `/init` and the lint reject it because both already run
the validator.

## Facts this rests on

- Iteration 10 put `roles.<role>.model`, `models.ranking` and `review.maxFixRounds` in the schema with defaults, and
  recorded the pairing it left to this story: `specReviewer` reviews `specWriter`; `codeReviewer` reviews
  `implementer` and `fixer`. `tester` and `worker` review nothing and are reviewed by nothing in that table.
- Iteration 11 put the rule for the effective model of a role in the workflow skill: `roles.<role>.model` when it
  is a non-empty string, else the `default` of `properties.roles.properties.<role>.properties.model` in the schema.
  The validator uses the same rule, so what it checks is the model a launch would use.
- `models.ranking` lists models weakest first; a model's rank is the position of the entry that names it; names of
  one level share an entry, joined by `=` with no spaces (`"opus=claude-opus-5-5"`). Its schema default is
  `["haiku", "sonnet", "opus", "fable"]`. Iteration 10 only described the format; nothing parses it yet.
- The validator is a generic walk of the schema (iteration 6): it supports `type`, `properties`, `required`,
  `items`, `minimum`, `minItems`, `additionalProperties` and `enum`, and the lint fails on any other schema keyword.
  A rule across two keys cannot be written in those keywords, so it is code in the validator, run after the walk.
- A finding is a record `path TAB rank TAB line`, sorted ordinally by both shells (`LC_ALL=C sort`,
  `[Array]::Sort` with `StringComparer.Ordinal`), so the same findings print in the same order. Errors have rank 0,
  warnings rank 1. The rule adds records of the same shape and changes nothing about sorting, the summary or the
  exit code: an error exits 1, a warning exits 1 only with `--strict`.
- The bash validator needs no `jq` any more (iteration 7), so both validators run on this machine and the smoke
  tests of both shells run locally.
- `tests/lint.sh`, section "config validates", already validates the example and this repository's own config with
  `--strict`; with the rule in the validator that section covers "the lint validates both with the rule".
- `/init` writes a candidate config to a temporary file, runs the validator on it, fixes an error and runs it again
  before the plan is shown. An error from the new rule is therefore handled by `/init` as every other error;
  `skills/init/SKILL.md` needs no change.

## Decisions

**1. The pairs are fixed in the validator.** The three pairs (`specReviewer` over `specWriter`, `codeReviewer` over
`implementer`, `codeReviewer` over `fixer`) are nightmill's own rule, stated in the workflow skill, not a value of a
project, so they are not a config key. Each shell lists them once.

**2. The rule always runs, on the effective models.** With the keys absent the effective models are the schema
defaults (`opus` for all five roles in the pairs) and the effective ranking is the schema default, so the defaults
pair at the same level and nothing is reported: "a config without the keys is unaffected" holds without a special
case. The rule has one exception, the next decision.

**3. The rule is silent when it has nothing to compare against.** It runs only when the schema has a `roles`
object, so a validation against a schema of its own (the tests do that) is untouched. It is skipped when
`models.ranking` is present but is not a non-empty array: the walk already reports that as an error, and a second
message about the pairs would only be noise. It is also skipped when the config root is not an object. A role whose model is neither configured nor defaulted in the
schema is not compared.

**4. Same level is allowed.** The rule is "at least as high": a reviewer whose model is in the same ranking entry as
its producer's, or is the same name, passes. The defaults rely on it.

**5. A model that is not in the ranking is a warning, once per role in a pair, never an error.** It cannot be
compared, so no pair that contains it is judged. `tester` and `worker` are in no pair, so they are never compared
and never warned about: they may be on any model, ranked or not.

**6. Names are matched exactly.** Case-sensitive, no trimming; `Opus` is not `opus`. The first entry that names a
model gives its rank (a name listed twice takes the weaker position; the duplicate is not reported, see "Not done").
A non-string item in the ranking names nothing and keeps its position.

## The rule

After the walk, when the config root is an object and the schema has `properties.roles`:

1. **Effective models.** For each of the five roles in the pairs, the model is `roles.<role>.model` when that value
   is a string that is not empty, else the `default` of that role's `model` in the schema. A role entry that is not an
   object, or whose `model` is not a string, counts as not configured (the walk already reported the type). A role
   with no model after that is left out.
2. **Effective ranking.** `models.ranking` of the config, else the `default` of `models.ranking` in the schema. The
   rule is skipped when the ranking of the config is present and is not a non-empty array. Each string item is split
   on `=`; the rank of a name is the 0-based index of the first item that has it as a part; empty parts name nothing.
3. **Per pair** (reviewer, producer), when both have a model and both models have a rank: if the reviewer's rank is
   lower than the producer's, an **error**.
4. **Per role in a pair** whose model has no rank: a **warning**, once, whatever the number of pairs it is in.

### Texts

Both shells print exactly these lines (the path is the reviewer's, or the unranked role's, `model` key; a model is
printed as JSON text, in double quotes):

| Finding | Severity | Path | Text after the path |
|---|---|---|---|
| reviewer ranks below producer | error | `roles.<reviewer>.model` | `<reviewer> on "<m1>" ranks below <producer> on "<m2>"` |
| model not in the ranking | warning | `roles.<role>.model` | `model "<m>" is not in models.ranking, so <role> cannot be compared` |

Examples, as printed:

```
error: roles.specReviewer.model: specReviewer on "sonnet" ranks below specWriter on "opus"
warning: roles.implementer.model: model "mystery" is not in models.ranking, so implementer cannot be compared
```

`codeReviewer` ranked below both `implementer` and `fixer` gives two errors on the same path; they sort by their
text, so the one naming `fixer` prints before the one naming `implementer`, in both shells.

### Where

`scripts/lib/validate.awk` gets one function that is called after `vnode(croot, sroot, "")`, and
`scripts/validate-config.ps1` one function called after `Test-Node`. No new file, no new option. The header comments
of both scripts say the rule exists.

## README and schema

- README, the paragraph that says how to check a config with the validator: one sentence, "It also rejects a config
  that puts a reviewer on a model ranked below the role it reviews (`specReviewer` below `specWriter`, `codeReviewer`
  below `implementer` or `fixer`, judged by `models.ranking`) and warns about a model that is not in the ranking."
- README, "Agent roles and models", after "A reviewer should rank at least as high as each role it reviews": the
  validator checks it.
- `schema/nightmill.schema.json`, the description of `roles`: "(checked by the validator once models.ranking is
  set)" becomes "(checked by the validator against models.ranking, or its default when it is not set)". A description
  only: no key, type, default or constraint changes, so this is not a config-key change.

## Tests

Each acceptance criterion of #32 is a test. Names are the behaviour protected.

**`tests/smoke-validate.sh` and `tests/smoke-validate.ps1`**, the same cases in both, written like the existing ones
(an edit of the example, the expected lines, the exit code), new section "== the reviewer pairing":

| Case | Edit of the example | Expected |
|---|---|---|
| valid: reviewer stronger | `specWriter` becomes `"sonnet"` | exit 0, `0 errors, 0 warnings` |
| valid: code reviewer stronger | `codeReviewer` becomes `"fable"` | exit 0, `0 errors, 0 warnings` |
| valid: same level in one entry | `ranking` gets `"opus=claude-opus-5-5"`, `specWriter` becomes `"claude-opus-5-5"` | exit 0, `0 errors, 0 warnings` |
| violation: spec reviewer | `specReviewer` becomes `"sonnet"` | exit 1, the `specReviewer` error line above, `1 error, 0 warnings` |
| violation: code reviewer, two producers | `codeReviewer` becomes `"haiku"` | exit 1, the errors naming `fixer` then `implementer`, `2 errors, 0 warnings` |
| unranked reviewer | `specReviewer` becomes `"mystery"` | exit 0, `warning: roles.specReviewer.model: model "mystery" is not in models.ranking, so specReviewer cannot be compared`, no error; with `--strict` exit 1 |
| unranked producer | `implementer` becomes `"mystery"` | exit 0, the warning for `roles.implementer.model`, no error |
| tester and worker are not compared | `tester` becomes `"haiku"`, `worker` becomes `"mystery"` | exit 0, `0 errors, 0 warnings` |
| defaults fill a missing role | the `roles` block reduced to `specReviewer` on `"sonnet"` | exit 1, the `specReviewer` error naming `specWriter on "opus"` |
| an empty model takes the default | `specReviewer` becomes `""` | exit 0, `0 errors, 0 warnings` |
| the keys are absent | the config reduced to `github`, `maintainer` and `verification.check` | exit 0, `0 errors, 0 warnings` |
| a ranking without the default models | `ranking` becomes `["haiku", "fable"]` | exit 0, five warnings (`specWriter`, `specReviewer`, `implementer`, `codeReviewer`, `fixer`), no error, `0 errors, 5 warnings` |
| a bad ranking gives only its own error | `ranking` becomes `"opus"` | exit 1, exactly `1 error, 0 warnings` |
| a schema of its own is untouched | the existing `--schema` case with the small schema | still passes, no pair finding |

The expected lines are compared as whole lines (`grep -qxF` / `-ceq`), so a text that differs between the shells
fails the test of the one that differs.

**`tests/lint.sh`**, new section "== reviewer pairing is checked":

- both `scripts/validate-config.sh` (or its `scripts/lib/validate.awk`) and `scripts/validate-config.ps1` contain the
  texts `ranks below` and `is not in models.ranking`, so a shell that drops the rule fails the lint on a machine that
  can run only the other one;
- the bash validator run on a copy of the example with `specReviewer` set to `haiku` exits non-zero and prints
  `ranks below`; this shows that the validator the lint uses for the example and the repository's own config has
  the rule;
- the existing "config validates" section is unchanged: it validates the example and `.claude/nightmill.json`
  with `--strict`, now including the rule.

`bash tests/check.sh` stays green, and `powershell -File tests/smoke-validate.ps1` passes.

## Verification

No path of `verification.manualCheckPaths` changes, so no manual check applies. The PR's "How verified" lists the
smoke cases and the lint section, the check, and the output of both validators (`validate-config.sh` and
`validate-config.ps1`) on the example and on a copy of it with `specReviewer` set to `haiku`, side by side, to show
the same lines and the same exit code.

## Not done

- No automatic fix of a config.
- No check at run time: the skills do not call the validator; the review stories decide what a skill does with the
  ranking.
- No report of a model listed twice in `models.ranking`, and no check that a ranked name is a real model.
- No pair for `tester` or `worker`, and no new role.
- No `/models` table (#34); it will print the same verdict this rule computes, but it is a separate story.
- No change to `skills/init/SKILL.md` or any other skill, to the workflow skill, to the status flow, to the slot
  marker or to any config key.
