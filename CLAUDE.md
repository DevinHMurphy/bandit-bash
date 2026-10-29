## GDScript workflow — Bandit Bash

These rules govern every task that creates or changes a `.gd`, `.tscn`, `.tres` or `project.godot`
file. They live in `CLAUDE.md` so they apply from the first message, before any file is opened.

**Before writing or editing any of those files, read `.claude/rules/gdscript.md` in full.** It holds
the code standards. If it is missing, stop and say so.

### Project facts

- Project: Bandit Bash · Copyright holder: Derc Development · License: MIT · the `Author:` line in
  file headers stays blank.
- Engine: Godot 4.7.1. If `config/features` in `project.godot` disagrees, stop and ask.
- Godot binary: `godot` is not on PATH. Use
  `"C:\Users\demur\OneDrive\Desktop\Godot_v4.7.1-stable_win64.exe"` (Bash:
  `"/c/Users/demur/OneDrive/Desktop/Godot_v4.7.1-stable_win64.exe"`) wherever these rules say
  `godot`.
- Dates: never from memory. Run `date "+%B %-d, %Y"`.

### Repository layout

Claude Code runs from the repo root (`Bandit_Bash/`). Every path in these rules is relative to it.

| Folder | Role | Write to it? |
|--------|------|--------------|
| `bandit-bash/` | The new Godot 4.7.1 project. All game code, scenes and resources go here. | Yes |
| `Godot_FE/` | The old, outdated build being rebuilt. Reference for behavior, values and intent. | **Never** |
| `steam_multiplayer_kit/` | Reference for Steam and multiplayer integration. | **Never** |
| `docs/` | Plans (`docs/plans/`), design notes (`docs/design/`), standards (`docs/standards/`). The game vision is `docs/design/game-vision.md`. | Yes |
| `.claude/` | Claude Code rules. | Only when asked |

- "`project.godot`" in these rules always means `bandit-bash/project.godot`.
- Inside Godot, `res://` is `bandit-bash/`. Code in `bandit-bash/` never references files outside it;
  Godot can't load them.
- If a task seems to need a change in a read-only folder, stop and ask.

### Design vision

Bandit Bash is not a straight port. `docs/design/game-vision.md` is the master design document.
It grew out of the Living Labyrinth design document, the redesign that came out of rethinking
`Godot_FE/`. That source is frozen in `docs/design/living-labyrinth/master-ideation.md`; where the
two differ, `game-vision.md` wins.

- Before building or changing any gameplay feature (run flow, army, units, items, combat, economy,
  meta), read its section in `game-vision.md`, then the matching section of `master-ideation.md`,
  then the `Godot_FE/` implementation (next section). Every feature checks both references.
- Where the vision and `Godot_FE/` disagree on rules, formulas or values, the vision wins. List both
  values with their sources in the plan or summary.
- Where the vision is silent, `Godot_FE/` is the basis, as before.
- A blank section, a `WIP` or `PLACEHOLDER` tag, a `?` in a value, or anything under "Open and
  unfinished" in `game-vision.md` is not a basis for a value. Ask (§1).
- If a change alters behavior the vision describes, say so in the estimate. Do not edit the vision
  to match code unless asked.

### Porting from `Godot_FE/`

Bandit Bash rebuilds `Godot_FE/` as a modern project, reshaped by the design vision above. Port
**behavior**, never code.

- Before rebuilding a system, read its full implementation in `Godot_FE/`, including the scenes that
  use it.
- Check the engine version in `Godot_FE/project.godot`. Treat its syntax, APIs and patterns as
  outdated: nothing is copied; everything is rewritten to `gdscript.md`.
- Tuning values found in `Godot_FE/` (speeds, radii, timings) count as an existing basis under §1.
  Carry them over unchanged unless asked or the design vision sets a different value, and list each
  with its source file in the summary.
- Ask (§1) when old behavior looks like a bug, depends on something `bandit-bash/` doesn't have, or
  the request implies changing it. Never silently port a bug, and never silently fix one.
- Old comments are a source of facts, not text to copy: salvage what's durable per `gdscript.md` §3.7.
- The summary of any port lists: vision sections read · `Godot_FE/` files read · behaviors
  preserved · behaviors changed or dropped, and why (including "changed to match the vision").

### Multiplayer and `steam_multiplayer_kit/`

- Before writing or changing anything networked (RPCs, authority, replication, lobbies, Steam
  integration), read the relevant parts of `steam_multiplayer_kit/` and follow its API and patterns
  for Steam and peer setup. Check its engine version before trusting version-specific details.
- It's a reference, not a style guide: code in `bandit-bash/` follows `gdscript.md` even where the
  kit's code doesn't.
- If the kit and `gdscript.md` §10 disagree, or using the kit means copying any of it into
  `bandit-bash/` (an addon or autoload), stop and ask.

### 1. Ask before you infer

This is the most important rule. If implementing something requires guessing at intent, stop and
ask. A wrong guess that compiles is worse than a question, because it looks finished.

Ask when:

- the desired behavior is ambiguous and more than one reading is defensible
- a change could alter gameplay feel, timing or balance
- you would invent a value (threshold, radius, rate, tolerance) with no basis in `bandit-bash/`,
  `docs/design/game-vision.md` or `Godot_FE/`
- the request contradicts the design vision, or the vision is blank or marked unfinished for it
- a change touches a public interface, signal, RPC contract or save format, or makes a structural
  scene/resource change (defined in `gdscript.md` §7)
- existing code contradicts the request, or two files disagree about the same concept
- the request depends on a system you haven't read (spawners, terrain, autoloads, `Hook`) — read it
  first, then ask if it is still unclear
- you are about to add a dependency, autoload or new file
- the change adds state that must survive a restart, quit, crash or multiplayer resume (roster,
  inventory, progress, unlocks, stats, settings): read `docs/design/save-system.md` first and state
  the save impact (block, section key, version) in the estimate

How to ask:

- Batch every question into one message.
- Give your recommended answer and why, so a "yes" is one word.
- State what you will assume if the user doesn't care.

**Assumptions:** mark each one with `# ASSUMPTION: ...` on the line it affects and list all of them in
the summary. Never state an assumption in a `##` doc comment, where it reads as fact. Remove the
marker once the user confirms or corrects it.

**Unattended runs** (headless, scheduled, or a question already unanswered): don't block. Take the
most conservative reading, mark it `# ASSUMPTION:`, and finish only local, reversible work. Stop and
report before any public-API change, save-format change, network-contract change, structural scene
change, new autoload or new file.

**Don't expand scope.** If you spot a second bug while fixing the first, report it; don't fix it
uninvited. Updating a changed file's `Modified:` date and bringing the docs of members you change up
to standard are part of the task. Nothing outside the members you change is touched.

### 2. Estimate first, plan only on request

Never write a plan document unprompted. Open every task with an estimate:

```
Effort:    Medium — 3 files, ~150 lines changed
Risk:      🟡 touches the replication path
Questions: 2 open (below)
Plan doc:  Offered
```

A Trivial task needs only `Effort: Trivial`. `Plan doc:` is `Not needed`, `Offered` or `Recommended`.

| Level | Shape | Default |
|-------|-------|---------|
| Trivial | 1 file, < 30 lines changed, no public API change, no open questions | Just do it |
| Small | ≤ 2 files, no public API change, ≤ 1 open question | Do it, ask inline |
| Medium | 3 files, no public API change, ≤ 2 open questions | Offer a plan |
| Large | any trigger below | Recommend a plan |

**Large triggers:** 4 or more files · any new, renamed or re-signatured public member (signal,
`class_name`, autoload, RPC, public method or variable, `@export`) · any structural scene/resource
change · 3 or more open questions · a new manager, registry, pooling layer or replication scheme.

**Risk:** 🟢 local and easily reverted · 🟡 crosses files or touches scenes/resources · 🔴 public
API, save format or network contract.

Then state your recommendation and stop: "This is Large — 5 files including the spawner and the RPC
contract. I suggest a plan doc first. Want one, or straight to code?" Respect the answer. If the user
declines a plan on a Large task, ask the §1 questions, flag the risk once, and proceed.

**Plan, only after approval:** ask the §1 questions, fold in the answers, write
`docs/plans/YYYY-MM-DD-<slug>.md` from the template in `docs/standards/gdscript-reference.md`, and
stop for review. No code until the plan is approved.

### 3. Verify before reporting done

1. After adding, renaming or removing a `class_name`, or adding or moving a script, refresh the
   global class cache: `godot --headless --path bandit-bash --import`
2. For every `.gd` file you changed:
   `godot --headless --path bandit-bash --check-only --script res://<path inside bandit-bash>.gd`
   `--check-only` doesn't load autoloads, so a script that uses one fails with "Identifier not
   found". For those, load a scene that uses the script headless, or run the test suite that
   covers it, and say which in the summary.
3. Fix every error and every warning your change introduced. An error naming a global class or
   autoload you didn't touch usually means a stale cache: rerun step 1.
4. If Godot can't be run, say so in the summary. Never claim code parses without running the check.

**The runner:** `sh bandit-bash/tools/run_tests.sh` does steps 1 and 2 and runs every suite (with
the sessions tests' temporary `override.cfg`) plus a headless launch, printing one verdict line
each; `--check <git ref>` parse-checks every `.gd` changed since that ref. Report its lines in the
summary. It judges runs by their output, because an engine crash at exit (exit 139) can follow a
passing or a failing run. It finds suites itself: each `tests/<name>/run_all.gd` must print
`--- N passed, M failed ---`. When a change adds a suite, or changes how runs report results or
how tests must be launched, update the runner in the same change.

### 4. Definition of done

- [ ] Estimate given up front; plan offered, not assumed
- [ ] Every assumption marked in code and listed in the summary
- [ ] Every declaration explicitly typed; no `:=` outside the exceptions in `gdscript.md` §4
- [ ] No Godot 3 syntax (`gdscript.md` §5)
- [ ] Every `@export` documented with units and edge-case meanings
- [ ] File header present; `Modified:` updated on every changed file
- [ ] New markers carry IDs and are mirrored into the class doc
- [ ] Docs updated where behavior changed and brought to budget; no dated changelog entries in source
- [ ] State machine and input map blocks updated if a state, transition or binding changed; input
      map checked against `project.godot`
- [ ] Renames grepped across `.gd`, `.tscn`, `.tres` and `project.godot`; `.uid` files moved with
      their scripts
- [ ] Nothing written outside `bandit-bash/` and `docs/`; ports list vision sections and files read
      and behaviors preserved, changed or dropped
- [ ] Verification (§3) run and clean, or its absence stated
- [ ] Performance claims measured, or labelled unmeasured
- [ ] Save impact stated: persisted state registered as a `SaveSection` / `PlayerSaveSection` per
      `docs/design/save-system.md`, or explicitly "not saved"

### 5. Summary format

End every task with: files changed · assumptions · markers added or encountered · verification
result · **Breaking Changes** (table format in `gdscript.md` §6.4, or the line `No breaking changes.`).
