# Dev environment setup

How to get a working Bandit Bash checkout on a new machine (Windows or macOS), with every folder the
project rules and tools expect.

## What you end up with

```
Bandit_Bash/                    this repo (DevinHMurphy/bandit-bash), on dev
├── bandit-bash/                the Godot 4.7.1 project: all game code, scenes and resources
├── docs/                       design, plans and standards (start at docs/README.md)
├── CLAUDE.md, .claude/rules/   coding rules, loaded automatically by Claude Code
├── Godot_FE/                   pellincr/Godot_FE on bus/track-b-scaffold: the old build (read-only)
└── steam_multiplayer_kit/      devinhmurphy/steam-multiplayer-kit on main: Steam reference (read-only)
```

`Godot_FE/` and `steam_multiplayer_kit/` are separate repos cloned inside this one. This repo's
`.gitignore` excludes them, so their changes never show up here. Treat both as read-only reference:
behavior and patterns are ported from them, code is never copied.

## Prerequisites

- **Git.** Windows: [Git for Windows](https://gitforwindows.org/), which includes Git Bash. macOS:
  `xcode-select --install`.
- Read access to the three GitHub repos above.
- **Godot 4.7.1** (standard build, not .NET). Don't upgrade it; the project stays on 4.7.1.
- For multiplayer testing over Steam: the Steam client running and logged in. The GodotSteam addon
  is already committed in `bandit-bash/addons/godotsteam/`.

## Setup

```sh
git clone --branch dev https://github.com/DevinHMurphy/bandit-bash.git Bandit_Bash
cd Bandit_Bash
sh setup.sh
```

On Windows you can double-click `setup.cmd` instead of running the last line.

`setup.sh` does three things:

1. Clones `Godot_FE/` and `steam_multiplayer_kit/` on the branches shown above.
2. Creates `bandit-bash/steam_appid.txt` containing `480`, Valve's public test App ID. The file is
   gitignored and every machine needs its own copy.
3. Prints a summary. Problems are marked `!` and set exit code 1.

On Windows, Godot_FE has paths longer than the 260-character limit. The script clones with
`core.longpaths` on, so this is handled. If you clone it by hand, add `-c core.longpaths=true`.

Run it again any time to update the two reference repos. It fast-forwards a repo only when that
repo is clean and on its expected branch. Otherwise it reports the repo and leaves it untouched, so
it never overwrites local work.

## Point the tools at Godot

The scripts in `bandit-bash/tools/` (`run_tests.sh`, `run_captures.sh`, `run_enet_pair.sh`) look
for Godot in this order: `$GODOT`, then `godot` or `godot4` on PATH, then one specific Windows
install path. On a new machine, set `GODOT` in your shell profile (`~/.bashrc` for Git Bash,
`~/.zshrc` on macOS):

```sh
# Windows (Git Bash). Use the console build so headless output shows in the terminal.
export GODOT="/c/path/to/Godot_v4.7.1-stable_win64_console.exe"
# macOS
export GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
```

## Check it works

1. Open `bandit-bash/project.godot` in Godot 4.7.1. The first import takes a while.
2. Run the test suites: `sh bandit-bash/tools/run_tests.sh --open`. On Windows you can also
   double-click `bandit-bash/tools/run_tests.cmd`. Every suite should print PASS.
3. To try co-op on one machine without Steam, run `sh bandit-bash/tools/run_enet_pair.sh`.

## Working in the repo

- Branch features off `dev` as `feature/<name>` and merge them back into `dev`.
- Before touching code, read `CLAUDE.md` and `.claude/rules/gdscript.md`. They apply to people and
  to Claude Code alike.

### Claude Code

`CLAUDE.md` and `.claude/rules/` come with the repo and load automatically. `.claude/settings.json`
holds each person's own permissions and isn't shared. It's worth creating your own with deny rules
for the two read-only folders:

```json
{
  "permissions": {
    "deny": [
      "Edit(/Godot_FE/**)",
      "Edit(/steam_multiplayer_kit/**)"
    ]
  }
}
```
