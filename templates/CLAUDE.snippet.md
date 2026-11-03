## Development process

This project runs on the [nightmill](https://github.com/CodaColaLight/nightmill) workflow plugin.
The rules are in its `workflow` skill (`/nightmill:workflow`); the project's values (board, labels,
areas, check command, slots) are in `.claude/nightmill.json`. `/next` takes a story (writes the spec,
then implements it once the maintainer set Approved), `/fix` fixes a bug, `/story` files a story,
`/check` runs the check. Worktree slots: `slot.ps1` / `slot.sh` in the plugin's `scripts/` folder.
An agent only works on issues whose board status is Ready or Approved; only the maintainer sets those.
Run the check before every commit; never commit red.
