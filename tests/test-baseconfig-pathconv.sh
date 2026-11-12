#!/usr/bin/env bash
# tests/test-baseconfig-pathconv.sh - bug 300: in Git Bash on Windows an argument of the form <ref>:<path> is taken for
# a list of paths and rewritten before git.exe starts, so "git show origin/HEAD:.claude/nightmill.json" exits 128 and
# base_config (scripts/lib/baseconfig.sh) takes that for "the file is not on the base branch": it falls back to the
# working tree with a note on standard error.
# The test makes the bug visible in every shell: a git shim first on PATH exits 128 for an argument of the form
# <ref>:<path> (a prefix of more than one character, a colon, a path; the value of -C is not one) unless the
# conversion is off for that call (MSYS_NO_PATHCONV set, or MSYS2_ARG_CONV_EXCL holding *), as Git Bash itself does;
# any other call goes to the real git. base_config must then find .claude/nightmill.json on origin/HEAD without a
# note, also when git.baseBranch of that file names another branch (the second git show of the function).
# Needs bash and git, no network.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nightmill-baseconfig-pathconv.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL  # the default of Git Bash, where the bug is; a caller that set them hides it
real=$(command -v git)
mkdir "$tmp/shim"
cat > "$tmp/shim/git" <<SHIM
#!/usr/bin/env bash
# the argument conversion of Git Bash, as far as it matters here
if [ -z "\${MSYS_NO_PATHCONV:-}" ]; then
  case "\${MSYS2_ARG_CONV_EXCL:-}" in
    *'*'*) ;;
    *)
      skip=""
      for a in "\$@"; do
        if [ -n "\$skip" ]; then skip=""; continue; fi
        if [ "\$a" = -C ]; then skip=1; continue; fi
        if [[ "\$a" =~ ^[A-Za-z0-9_./-]{2,}:[^:]+\$ ]]; then
          echo "fatal: path '\$a' does not exist (argument converted by the shell)" >&2
          exit 128
        fi
      done ;;
  esac
fi
exec "$real" "\$@"
SHIM
chmod +x "$tmp/shim/git"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
: > "$tmp/gitconfig"; export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1

# origin: main holds the configuration; develop holds another one (git.baseBranch main), for the second case
"$real" init -q --bare -b main "$tmp/origin.git"
"$real" clone -q "$tmp/origin.git" "$tmp/seed" 2>/dev/null
mkdir -p "$tmp/seed/.claude"
printf '{"project": {"name": "from-origin"}, "git": {"baseBranch": "main"}}\n' > "$tmp/seed/.claude/nightmill.json"
"$real" -C "$tmp/seed" add -A
"$real" -C "$tmp/seed" commit -q -m "config"
"$real" -C "$tmp/seed" push -q origin HEAD:main
"$real" -C "$tmp/seed" checkout -q -b develop
printf '{"project": {"name": "from-develop"}, "git": {"baseBranch": "main"}}\n' > "$tmp/seed/.claude/nightmill.json"
"$real" -C "$tmp/seed" commit -q -am "develop config"
"$real" -C "$tmp/seed" push -q origin develop

"$real" clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
"$real" -C "$tmp/work" remote set-head origin --auto >/dev/null
mkdir -p "$tmp/work/.claude"
printf '{"project": {"name": "from-working-tree"}}\n' > "$tmp/work/.claude/nightmill.json"

run() { # run <main checkout>: prints note, from, stop and the file's text, each tagged
  PATH="$tmp/shim:$PATH" bash -c '
    set -uo pipefail
    . "$1/scripts/lib/json.sh"; . "$1/scripts/lib/baseconfig.sh"
    rc=0; base_config "$2" || rc=$?
    echo "rc=$rc"; echo "note=$base_cfg_note"; echo "from=$base_cfg_from"; echo "stop=$base_cfg_stop"
    if [ -f "$base_cfg_file" ]; then echo "text=$(tr -d "\n" < "$base_cfg_file")"; fi
    [ -z "$base_cfg_tmp" ] || rm -f "$base_cfg_tmp"
  ' _ "$here" "$1" 2>&1
}

echo "== the shim refuses the shape that Git Bash rewrites"
rc=0; (cd "$tmp/work" && PATH="$tmp/shim:$PATH" git show origin/HEAD:.claude/nightmill.json >/dev/null 2>&1) || rc=$?
[ "$rc" = 128 ] || fail "the shim does not refuse origin/HEAD:.claude/nightmill.json (exit $rc)"
rc=0; (cd "$tmp/work" && MSYS_NO_PATHCONV=1 PATH="$tmp/shim:$PATH" git show origin/HEAD:.claude/nightmill.json >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "the shim refuses the shape with the conversion off (exit $rc)"

echo "== base_config finds the file on origin/HEAD, without a note, when git converts <ref>:<path>"
out=$(run "$tmp/work")
case "$out" in *"note=nightmill: origin/HEAD has no .claude/nightmill.json"*) fail "the lookup fell back to the working tree with a note: $out" ;; esac
case "$out" in *"rc=0"*) ;; *) fail "base_config did not return 0: $out" ;; esac
case "$out" in *"note="$'\n'*) ;; *) fail "base_config left a note: $out" ;; esac
case "$out" in *"from=origin/HEAD:.claude/nightmill.json"*) ;; *) fail "base_cfg_from does not name origin/HEAD:.claude/nightmill.json: $out" ;; esac
case "$out" in *from-origin*) ;; *) fail "the text is not the one on origin/HEAD: $out" ;; esac
case "$out" in *from-working-tree*) fail "the working tree's file was read: $out" ;; esac

echo "== the same when git.baseBranch names a branch other than origin/HEAD's (the second git show)"
"$real" -C "$tmp/work" remote set-head origin develop >/dev/null
out=$(run "$tmp/work")
case "$out" in *"rc=0"*) ;; *) fail "baseBranch case: base_config did not return 0: $out" ;; esac
case "$out" in *"stop=origin/"*) fail "baseBranch case: a stop on the second lookup: $out" ;; esac
case "$out" in *"from=origin/main:.claude/nightmill.json"*) ;; *) fail "baseBranch case: base_cfg_from does not name origin/main:.claude/nightmill.json: $out" ;; esac
case "$out" in *from-origin*) ;; *) fail "baseBranch case: the text is not the one on origin/main: $out" ;; esac

echo "test-baseconfig-pathconv: ok"
