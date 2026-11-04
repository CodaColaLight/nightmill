# Iteration 7: the bash scripts read JSON without jq

Status: draft, awaiting approval (#7)

Story: #7, epic #2 (Scripts without extra tools). Adds two files under `scripts/lib/`, changes four bash
scripts and the tests around them, and updates the documentation. No config key, no change to the status
flow, no change to the slot marker (it stays byte for byte what it is today): none of
`escalation.storyTriggers` applies, so the PR may auto-merge.

## Goal

The bash scripts and their smoke tests run on a machine that has only `git`, `gh` and bash, plus the tools
every POSIX shell comes with (`awk`, `sed`, `grep`, `sort`, `cut`, `tr`, `date`, `mktemp`).

## Facts this rests on

- Four bash scripts need `jq` today: `slot.sh`, `new-worktree.sh`, `render-templates.sh` and
  `validate-config.sh`. `tests/smoke-render.sh` uses it once, `tests/lint.sh` uses it or `python3` to check
  that every JSON file parses, and `tests/check.sh` skips the bash smoke tests when it is missing.
- What the scripts do with JSON, all of it: read a scalar with a default (`git.baseBranch`, `worktrees.root`,
  `worktrees.slots`, `verification.check`, `verification.manualCheckText`, `labels.epic`, `labels.story`,
  `labels.bug`, `labels.needsSpec`); read an array of strings (`areas`, `invariants`, `worktrees.runHints`);
  read an array of objects (`worktrees.warmup` with `dir`, `command`, `lockfile`); read an object in file
  order (`worktrees.ports`); quote a string as JSON (the invariants in the issue forms); read and write the
  slot marker; and, in the validator, walk the config against the schema.
- `python3` is not a way out. The story is about a machine with only git, gh and bash, and on Windows
  Git Bash `python3` is missing or a Store stub. `awk` is on every such machine: Git for Windows ships GNU
  awk (this machine has 5.4), Ubuntu's default is mawk, macOS has the BSD one.
- The slot marker today is what `jq -n` prints: two-space indentation, the keys `slot` (a number), `branch`
  and `since` in that order, and a final newline. The previous version of nightmill reads it with `jq`, so
  any valid JSON is readable, and the new version keeps the exact bytes anyway.

## What is built

### `scripts/lib/json.awk`: a strict JSON parser in POSIX awk

A recursive-descent parser for JSON as RFC 8259 defines it, written in the POSIX subset of awk: no
`gensub`, no `switch`, no arrays of arrays, no `length(array)`, no regular-expression `RS`, no regex
intervals. It is always run as `LC_ALL=C awk`, so every character is one byte and `printf "%c"` writes
bytes. It rejects: an empty file, trailing commas, comments, single quotes, leading zeros, a bare `+`,
control characters inside a string, bad escapes, an unterminated string, object or array, text after the
value, and nesting deeper than 64 levels. An error is one line on standard error,
`json: <file>: <reason> at byte <n>`, and exit code 1. `\uXXXX` is decoded to UTF-8 (a surrogate pair gives
one four-byte character); raw UTF-8 passes through unchanged.

It builds a node table (kind, value, children in document order) and has two uses:

- **flat mode** prints one record per node, parent before children, in document order:
  `<path>` TAB `<kind>` TAB `<value>`. The path is the keys joined with dots and `[i]` for an array item
  (`worktrees.warmup[0].command`); the root has the empty path. `kind` is `object`, `array`, `string`,
  `number`, `boolean` or `null`. For an object or array the value is the number of children. A string is
  decoded, then `\`, newline, tab and carriage return are written as `\\`, `\n`, `\t`, `\r`, so a record
  is always one line. A number or boolean is printed as written; `null` has an empty value.
- **library mode** (`validate.awk`, below) calls the parser's functions on the node table directly.

A key that contains a dot, a bracket, a tab or a newline cannot be addressed by path in flat mode. Nothing
in nightmill's schema has such a key.

### `scripts/lib/json.sh`: the functions the scripts source

| Function | Result |
|---|---|
| `json_load FILE` | parses FILE and keeps the records in `JSON_FLAT`; prints the parser's error and returns 1 for an unreadable or invalid file |
| `json_get PATH [DEFAULT]` | the string value at PATH, decoded; DEFAULT (empty when not given) when the path is absent, null, or an object or array |
| `json_len PATH` | the number of items of the array or object at PATH; 0 when absent |
| `json_keys PATH` | the keys of the object at PATH, one per line, in file order; PATH empty is the root |
| `json_has PATH` | exit code 0 when the path exists, also when its value is null |
| `json_quote STRING` | the string as a JSON string literal, like `jq`'s `tojson`: quotes around it, `"` and `\` escaped, control characters as `\n`, `\t`, `\r`, `\b`, `\f` or `\u00XX`, raw UTF-8 unchanged |
| `json_marker SLOT BRANCH SINCE` | prints the slot marker: `{`, then `  "slot": N,`, `  "branch": "…",`, `  "since": "…"` on lines of their own, then `}` and a newline |

### Script changes

- `slot.sh`, `new-worktree.sh`: the `jq` check and its message are gone. The scalar reads use `json_get` with
  the defaults they have today (`main`, `../<checkout>-wt`, 2). The warm-up loop runs over
  `json_len worktrees.warmup` items. The ports come from `json_keys worktrees.ports`, printed as `key=value`
  in file order. The run hints come from `worktrees.runHints[i]`. The marker is written with `json_marker`
  and read with `json_load` and `json_get`.
- `render-templates.sh`: `areas` becomes `[a, b]` with `, ` between items; each invariant becomes
  `        - label: <json_quote>` and `          required: false`, joined by newlines; the other values use
  `json_get` with today's defaults. An empty `areas` still stops the script with today's message.
- `validate-config.sh`: the jq program is replaced by `scripts/lib/validate.awk`, which includes `json.awk`,
  parses the config and the schema and walks the schema exactly as the PowerShell and the old jq version did,
  printing the same records (`path`, rank, line) that the script sorts with `LC_ALL=C sort`. Findings,
  messages, order, summary and exit codes are unchanged, so `tests/smoke-validate.sh` and
  `tests/smoke-validate.ps1` keep their expectations.

## Tests

- **`tests/smoke-json.sh`** (new, no `jq` needed):
  1. *Parser*: scalars and containers of every kind; nested objects and arrays; empty `{}` and `[]`; numbers
     (`0`, `-1`, `2.5`, `1e3`, `-0.5E-2`); strings with every escape, a `é`, a surrogate pair and a raw
     em dash; the exact flat records for a small fixture.
  2. *Library*: `json_get` with and without a default, on a null, on an object and on a missing path;
     `json_len`; `json_keys` in file order; `json_has` on a null; `json_quote` of a string with a quote, a
     backslash, a newline, a tab and an em dash; `json_marker` against the exact expected text.
  3. *Errors*, each exit code 1 with a message that names the file and the reason: trailing comma,
     single-quoted string, comment, leading zero, unterminated string, unterminated object, text after the
     value, empty file, a raw tab inside a string, a bad escape, nesting of 65 levels.
  4. *Cross-check against jq*, only when `jq` is installed (CI): for every key the scripts read, on
     `templates/nightmill.example.json` and on a fixture with escapes and non-ASCII text, `json_get` equals
     `jq -r '<path> // empty'`, `json_len` equals `jq 'length'`, `json_keys` equals `jq -r 'keys_unsorted[]'`
     and `json_quote` equals `jq -n --arg s '<value>' '$s | tojson'`. Without `jq` the section prints that it was skipped.
- `tests/smoke-slot.sh`, `tests/smoke-render.sh`, `tests/smoke-validate.sh` keep their cases. In
  `smoke-render.sh` the one `jq` call (dropping `invariants`) becomes a second fixture written with a here
  document. All three must pass on a machine without `jq`.
- `tests/lint.sh`: the JSON check uses `json.awk` instead of `jq` or `python3`; `config validates` always uses
  the bash validator; a new check `bash files do not use jq`: no file in `scripts/*.sh`, `scripts/lib/*`
  and `tests/*.sh` other than `tests/smoke-json.sh` mentions `jq` outside a comment line, and no file in them
  contains `command -v jq`.
- `tests/check.sh`: the bash smoke tests run always; the "jq is not installed" skip notice is gone.
- **CI**, bash job: `tests/smoke-json.sh` first (the runner has `jq`, so the cross-check runs), then a step
  that moves `jq` out of the `PATH` and asserts `command -v jq` fails, then the other bash smoke tests.
  They run under mawk, Ubuntu's default awk; this machine runs them under GNU awk 5.4. The lint job needs no
  `jq` either.

The existing lint checks, the PowerShell smoke tests and `claude plugin validate --strict` keep passing.

## Documentation

`README.md`: the sentence "the bash scripts also need `jq`" becomes "the bash scripts need nothing beyond
bash and the tools a POSIX shell has (awk, sed, grep)"; "which needs `jq`" and the "(needs jq)" remarks in the
command list go. `.claude/CLAUDE.md` and `skills/init/SKILL.md` lose their "needs jq" remarks.
`CHANGELOG.md`: a bullet under `Unreleased` for iteration 7 (#7). No decision record: no flow or status
change.

Manual check: on this machine, which has no `jq`, `bash tests/check.sh` runs every bash smoke test (nothing is
skipped for `jq`), and `bash scripts/slot.sh --status` in a clone prints the slot list. The PR describes what
was seen.

## Not done

- Changing any PowerShell script (none uses `jq`).
- A general-purpose `jq` replacement: the reader reads, quotes and writes only what the scripts need.
- Keys with dots or brackets in flat paths, `\u0000`, numbers beyond what awk can hold (numbers are passed
  through as text, so only comparisons in the validator are affected), awk flavours other than GNU awk and
  mawk (BSD awk on macOS should work and is untested).
- Speed work: the scripts start a few awk processes where they started `jq` before.

## Decisions for the maintainer

1. **A JSON parser in awk instead of a `python3` fallback.** `python3` is not there on the machine the story
   describes. The cost is about 300 lines of awk to maintain, plus the library functions.
2. **The validator moves to awk too, and the jq program is deleted.** Otherwise the README could not drop the
   `jq` requirement. The validator then exists twice, in PowerShell and in awk, with the smoke cases shared.
3. **CI hides `jq` for the bash smoke tests** after the cross-check, so a script that starts using `jq` again
   fails there and in the lint.
4. **The parser is strict**: a trailing comma or a comment in a config file is an error, as it is for `jq`.
