# Save System

The living contract for persistence in Bandit Bash. Read this before adding anything that must
survive a restart, a quit, a crash or a multiplayer resume. The history of how it was decided is in
`docs/plans/2026-10-13-save-system.md`; this file describes how it works now.

## The short version

- Never touch disk for save data. `SaveService` (autoload) decides when to save; `SaveFile` is the
  only code that reads or writes save files.
- To persist a system's data, implement `SaveSection` (once per file) or `PlayerSaveSection` (once
  per player) and register it from an autoload's `_ready()`. That is the whole integration.
- Store plain JSON values only. No Objects, no Resources, no `PackedScene`; refer to things by
  stable string id.
- Bump your section's version whenever its data shape changes, and write `migrate()`.

## Layout

```
user://saves/
├── last_selected.json                 which save file was opened last
└── save_N/                            N = 1..3, one per save file
    ├── profile.json                   Steam name cache, play time, cross-run sections
    ├── settings.json                  per save file; the only player-editable file
    ├── campaign_solo.json             the solo run, while one is in progress
    ├── combat_solo.json               the solo battle, only while one is in progress
    ├── campaign_multi.json            a multiplayer campaign this save file hosts
    ├── combat_multi.json              its battle, only while one is in progress
    └── archive/<mode>_<ended_at>.json one record per ended run
```

A save file is always chosen on Save Select before the Main Menu. Settings belong to the save file;
before one is chosen, the last selected file's settings apply.

## The envelope

Every file has the same shape:

```json
{
  "schema_version": 1,
  "game_version": "0.1.0",
  "saved_at": 1760000000,
  "checkpoint_seq": 42,
  "core": { },
  "sections": { "<key>": { "version": 1, "data": { } } }
}
```

| Field | Meaning |
|-------|---------|
| `schema_version` | Version of the block's `core` fields. Owned by the data class (`ProfileData`, `CampaignData`, ...). |
| `game_version` | `application/config/version` of the build that wrote it. A newer one is refused, never guessed at. |
| `saved_at` | Unix seconds, UTC. |
| `checkpoint_seq` | Campaign and combat files only; pairs a combat file with its campaign. `-1` elsewhere. |
| `core` | Fields the block's data class owns. |
| `sections` | Data owned by registered systems. Unknown keys are kept on re-save. |

## Writing and recovery

`SaveFile.write()` writes `X.json.tmp`, reads it back, moves the old `X.json` to `X.json.bak`, then
renames the `.tmp` into place. `SaveFile.read()` parses all three, uses the newest complete copy
(by `checkpoint_seq`, then `saved_at`) and repairs `X.json` from it. A crash at any point leaves a
readable copy. Never write save files any other way.

## Adding a save-aware system

1. Pick the block. `PROFILE`: progress across runs (unlocks, statistics). `CAMPAIGN`: the run in
   progress. `COMBAT`: the battle in progress. Data that exists per player in a run is a
   `PlayerSaveSection`.
2. Implement the contract:

```gdscript
class_name UnlockTracker
extends SaveSection
## Which units the player has unlocked.
##
## @tutorial(Save system design): docs/design/save-system.md

var _unlocked: PackedStringArray = []


func get_key() -> String:
	return "unlocks"            # never change it: it is how saved data finds its owner


func get_version() -> int:
	return 1


func capture() -> Dictionary:
	return {"units": Array(_unlocked)}


func restore(data: Dictionary) -> Error:
	_unlocked = PackedStringArray(data.get("units", []))
	return OK


func reset() -> void:
	_unlocked = PackedStringArray()
```

3. Register it before any save file opens, from an autoload's `_ready()`:
   `SaveService.register_section(SaveSection.Block.PROFILE, unlock_tracker)`. A section registered
   later misses that file's load.
4. Reserved keys are already held by a placeholder until their system arrives; registering under
   the same key takes the slot over and reads whatever was saved there at version 1. Reserved now:
   profile `unlocks`, `achievements`, `statistics`, `hall_of_heroes`; campaign `rng`; combat
   `enemy_units`, `entities`, `rng`. The archive copies the per-player section named `roster`.
5. In your class doc, add `@tutorial(Save system design): docs/design/save-system.md` and say which
   block and key you own.

`PlayerSaveSection` is the same with a seat on every call: `capture(seat)`, `restore(seat, data)`,
`reset(seat)`, plus `clear()` to forget every seat. One instance holds every player's data; on the
host that is how all players are saved. Seats are stable for a campaign's life; solo is seat 0.

## Data rules

- **Plain JSON values only.** Dictionaries, arrays, strings, numbers, bools. No Objects or
  Resources: a `.tres` can carry script references, and saves must be safe to load.
- **Refer to things by stable string id**, never by object, enum int or scene path. Enums are saved
  as string ids (see `CampaignData` modes, `CombatData` phases).
- **Numbers come back as floats.** `JSON.parse` returns every number as a float and every key as a
  string. Convert explicitly in `restore()`: `int(data.get("gold", 0))`.
- **Never compare restored containers to literals.** Godot compares arrays and dictionaries by
  element type, so `{"version": 1} != {"version": 1.0}`. Convert fields, then compare.
- **Integers above 2^53 must be strings.** Steam ids lose precision as JSON numbers.
- **Validate on restore.** Return an `Error` for data you can't use; the load stops cleanly before
  any system holds half-loaded state. Settings are the one exception: they are player-editable, so
  bad values are repaired, not refused.

## Versioning

- A section's data shape changes → raise `get_version()` and implement `migrate(data, from_version)`
  editing `data` in place. The default `migrate()` fails loudly on purpose.
- A data class's `core` changes → raise its `SCHEMA_VERSION` and add one step to its
  `_migration_steps()`; `SaveMigrations.run()` applies them in order.
- Never rename a section key, a `core` key or a saved string id without a migration: the old value
  would silently become a default.
- A file or section from a newer build is refused, not partly loaded.

## When the game saves

Saves happen at checkpoints only, never on a timer:

| Moment | Call |
|--------|------|
| New run: player presses Start | `start_new_solo_run()` / `start_new_multiplayer_run()` |
| Room entered, other campaign progress | `save_checkpoint()` |
| Battle: player presses Begin after prep | `begin_battle()` |
| Battle: end of each player phase (multiplayer: once every player has ended their turn) | `save_checkpoint()` |
| Battle ends | `end_battle()` |
| Save & Quit (pause menu) | `save_checkpoint()` |
| Run won, lost or abandoned | `end_run()` / `abandon_run()` |
| Options: Apply | `save_settings()`, writes only `settings.json` |

Apply your system's changes to its section state **before** the call; the call captures it.

## Battles

`begin_battle()` captures the campaign's sections, marks the campaign `combat_in_progress`, then
writes the combat file and the campaign with the same `checkpoint_seq`. While a battle runs,
campaign writes keep the sections captured at Begin: everything the battle changes lives only in
`COMBAT` sections. That is what lets a battle restart from Begin if its combat file is lost.

On continue, `SaveService.resume_point` says where to pick up:

| Campaign | Combat file | `resume_point` |
|----------|-------------|----------------|
| not in battle | none, or a stale one (deleted) | `CAMPAIGN` |
| in battle | same `checkpoint_seq`, or one ahead | `BATTLE` (combat loaded) |
| in battle | missing, unreadable, any other seq | `BATTLE_RETRY` (restart from Begin) |

A combat system must therefore keep battle-changed state (unit HP, items used, deaths) in its
`COMBAT` section, and apply the results to `CAMPAIGN`/player sections only before `end_battle()`.
A resumed enemy phase replays identically only once the RNG manager saves its state in `rng`.

## Multiplayer

- Only the host saves a campaign, in its multiplayer slot, with every player's data in the
  `players` array. Clients never write campaign or combat files.
- On every host checkpoint, clients receive the campaign as `SaveService.multiplayer_replica` (never
  saved) and write only their own `profile.json`. When the run ends, each client writes the host's
  archive record into its own archive.
- Resume goes through the lobby: the host loads the campaign from the Main Menu, hosts, and only
  the campaign's players (by Steam id from the Steam connection, never from a message) and only the
  same game version are admitted. Resume needs every player present and Ready.
- The player count is fixed when a campaign starts.
- Never send a Resource over the network; send envelopes or ids.

## Testing

- Headless suite (no autoloads, no Steam):
  `godot --headless --path bandit-bash --script res://tests/save/run_all.gd`. Add cases there for any
  new data class or rule. Autoloads don't exist in `--script` mode, so test data classes and
  `SaveSectionRegistry` directly.
- To drive `SaveService` itself, run a scene headless with a temporary `bandit-bash/override.cfg`
  setting `application/config/use_custom_user_dir=true` and a test `custom_user_dir_name`, so real
  saves are untouched. Delete the `override.cfg` afterwards; never commit it.
- Multiplayer behavior needs two machines or two Steam accounts. Until that run happens, mark the
  change untested live.
