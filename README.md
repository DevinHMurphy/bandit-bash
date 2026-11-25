# Bandit Bash

A Godot 4.7.1 game by Derc Development, a rebuild and redesign of an earlier project.

## Get set up

```sh
git clone --branch dev https://github.com/DevinHMurphy/bandit-bash.git Bandit_Bash
cd Bandit_Bash
sh setup.sh          # on Windows you can double-click setup.cmd instead
```

`setup.sh` clones the two reference repos (`Godot_FE/`, `steam_multiplayer_kit/`) into place and
creates the machine-local Steam App ID file. It's safe to rerun. Prerequisites, pointing the tools
at Godot, and a first test run are covered in **[docs/dev-setup.md](docs/dev-setup.md)**.

## Where things are

| Folder | What it is |
|---|---|
| [`bandit-bash/`](bandit-bash/) | The Godot project: all game code, scenes and resources |
| [`docs/`](docs/) | Design, plans and standards. Start at [docs/README.md](docs/README.md); the game vision is [docs/design/game-vision.md](docs/design/game-vision.md) |
| `Godot_FE/` | The old build being rebuilt. Read-only reference, cloned by `setup.sh` |
| `steam_multiplayer_kit/` | Steam and multiplayer reference. Read-only, cloned by `setup.sh` |
| [`CLAUDE.md`](CLAUDE.md), [`.claude/rules/`](.claude/rules/) | Coding rules for contributors and Claude Code |

Run the tests with `sh bandit-bash/tools/run_tests.sh`.
