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
   the same key takes the slot over and reads whatever was saved there at version 1. A section
   that takes a reserved slot over keeps that slot's place in the restore order, ahead of every
   section registered later, so never rely on restoring after one. Reserved now: profile
   `unlocks`, `achievements`, `statistics`, `hall_of_heroes`. The combat key `enemy_units` is no
   longer reserved: enemies are saved in `combat_state`, and a file that holds the key keeps it as
   an unknown section. `CampaignService` has taken over the campaign and combat `rng` keys
   ([RNG streams](#rng-streams)) and the combat `entities` key ([Combat map](#combat-map)). The
   archive copies the per-player section named `roster`.
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
A resumed battle's rolls continue where they were saved (next section).

## RNG streams

Every gameplay random result comes from a stream in the run's `RngStreams`, which the
`CampaignSession` holds ([RNG streams plan](../plans/2026-10-26-rng-streams.md)). A stream's seed
is re-derived from the run seed (`CampaignData.run_seed`, in `core`) and the stream's key, so a
save holds only where each live stream has got to. `CampaignService` registers two sections, both
`RngSaveSection`:

| Block | Key | Version | Holds |
|-------|-----|---------|-------|
| `CAMPAIGN` | `rng` | 1 | Every live stream of a campaign purpose: map, routes, `?` nodes, events, starting offer, shop, prefix re-rolls, rewards, level-ups |
| `COMBAT` | `rng` | 1 | The battle's live `COMBAT_ROLLS` streams, one per seat |

Both have the same shape, `{save_key: state}`:

```json
"rng": { "version": 1, "data": { "9:2:5:0:-1": "62431fcec4f6c10e" } }
```

- **`save_key`** is the stream's key as numbers, `purpose:floor:node:seat:index` (`-1` for an
  unused part). Numbers, not names, so renaming a purpose changes no save.
- **`state`** is 16 hex digits. It is a string because it is a 64-bit integer, above JSON's 2^53.
- **Every seat's streams are in the one section.** They live in one registry on the host, so these
  are `SaveSection`s, not `PlayerSaveSection`s.
- **Never saved:** seeds (re-derived from the key), and the `ENCOUNTER_SETUP` and `MAP_LOOT`
  streams. A battle's setup draws those two in full at Begin; what they decide (the map, enemies,
  container contents) is battle state, saved in `combat_state`, `combat_map` and `entities`.
- **Restore is all or nothing.** An unknown key, a key whose purpose belongs to the other block
  or is never saved, or a state that isn't a valid string fails the whole section. That stops the
  load; for the combat block it means the battle restarts from Begin.
- **Load order.** Sections restore while a file loads, before the run's session exists. The section
  checks the data and holds it; `CampaignService` applies it to the new session before
  `session_started`, so nothing can draw from a stream about to be replaced.
- **`BATTLE`** continues each `COMBAT_ROLLS` stream from the last battle save. **`BATTLE_RETRY`**
  uses nothing from the combat section: the battle's streams start fresh from their keys, so the
  restarted battle replays the Begin rolls.
- **A campaign stream drawn during a battle** is saved only by `end_battle()`, since campaign
  writes keep the sections captured at Begin. A resumed battle would draw it again from its Begin
  position.

Rolling back to an older build is safe: one without `RngSaveSection` holds `rng` as a reserved
placeholder (or as an unknown section) and writes the data back unchanged.

## Instance ids

Every instance id of a run (`unit:57`, `item:412`, `effect:12`) comes from one counter in the
run's `InstanceIdAllocator`, which the `CampaignSession` holds. Ids are never reused, so the
counter is saved; a resumed enemy phase then mints the ids the first run minted.
`CampaignService` registers two sections, both `InstanceIdSaveSection`:

| Block | Key | Version | Holds |
|-------|-----|---------|-------|
| `CAMPAIGN` | `instance_ids` | 1 | The counter and labels as Begin (or the last campaign checkpoint) left them |
| `COMBAT` | `instance_ids` | 1 | The counter and labels at the last battle save |

```json
"instance_ids": { "version": 1, "data": { "next": 58, "labels": { "unit:57": "Hakkapel" } } }
```

- **`next`** is the value the next id carries, at least 1.
- **`labels`** is the display text of every id minted or named, so log and error text stays
  readable after a resume. Labels are text for people only; never read an id's meaning from them.
- **Load order.** Like the `rng` sections, each holds what it restored until `CampaignService`
  builds the session, then applies it: campaign first, then combat, so a resumed battle's later
  counter wins. **`BATTLE_RETRY`** resets the combat block, so a restarted battle mints from
  Begin's counter and gets the same ids as the first time.
- A save from before these sections resumes with a fresh counter. Nothing saved before them holds
  an instance id, so nothing can collide.

## Combat state

The battle itself is two `COMBAT` sections, one `CombatStateSection` and its partner, which
`CampaignService` registers in this order ([combat core plan](../plans/2026-10-26-combat-core.md),
Save Impact):

| Block | Key | Version | Holds |
|-------|-----|---------|-------|
| `COMBAT` | `combat_state` | 1 | Each map's units (`CombatUnitState`: tile, HP, Block, Stance, what it did this turn and phase, movement spent, a pending second move, slots, growth changes), weapon records, turn, phase side, ended and not-yet-started seats, rune slots, and the session part (seq, commanders, bases, finished and won); the encounter's seq, arrivals and units on their way between maps |
| `COMBAT` | `effects` | 1 | Each map's effect engine (instances with counters and charges, timed modifiers, bases and deltas, phase and attack counts) and the encounter's cross-map instances |

```json
"combat_state": { "version": 1, "data": { "encounter": { }, "sessions": [ { "session": { }, "combat_state": { } } ] } },
"effects": { "version": 1, "data": { "encounter": { "cross_map": [ ] }, "sessions": [ { } ] } }
```

- **Built from snapshots.** Each capture takes the battle's `CombatEncounter.snapshot()` and keeps
  its own parts, so a save and a rejoining client's snapshot can't drift apart. The roll streams
  are the combat `rng` section's, never these.
- **Definitions by reference.** An effect is named by its catalog id, or `<carrier id>#<effect id>`
  inside a carrier (the content test requires an id unique within each carrier). One the loadout
  made at runtime (a staff's uses, a prefix, stat changes) is described in the save and restores
  as itself, and an enemy's charge-free use stays unlimited: nothing is re-resolved from the
  catalog into something else.
- **Enums by name, ids as strings,** tiles as `[x, y]`, growth changes by stat name.
- **Load order.** Both sections only check and hold their data while the file loads; `effects`
  refuses data without `combat_state`, since effects need the battle's units. The held battle
  loads into a battle rebuilt the way Begin set it up (`CombatStateSection.load_into()`), units and
  turn before effects, after the maps. `CampaignService.resume_battle()` does it on a `BATTLE`
  resume ([Combat map](#combat-map) has the order).
- **Missing or old data.** A combat file without these sections (from before them) holds no battle,
  so `load_into()` returns `ERR_UNCONFIGURED` and the battle restarts from Begin. Version 0 is
  malformed and a newer version is refused, like any section; either stops the load and gives
  `BATTLE_RETRY`.
- **The core follows.** Each capture sets `CombatData`'s `turn` and `phase` to the battle's (the
  lowest seat's map; the opening swap window counts as turn 1's player phase).
- **Definitions no catalog holds:** a powder keg's two reactions are built by `MapObjects`, so
  `CampaignService` sets the sections' `resolve` to find them first
  (`MapObjects.map_definition()`), as `CombatSession.load_snapshot()` always does.

## Combat map

Each map's objects and reinforcement points are two more `COMBAT` sections, one
`CombatMapSection` and its partner, which `CampaignService` registers after the combat state pair
([combat map plan](../plans/2026-10-27-combat-map.md), Save Impact):

| Block | Key | Version | Holds |
|-------|-----|---------|-------|
| `COMBAT` | `combat_map` | 1 | Each map's id and active object spots (checked against the rebuilt battle), its reinforcement points (waves with their drawn groups, how many arrived, closed, the units waiting for room), whether the waves are cancelled and the darkness has arrived, whether the opening swap window is open, and the enemies marked as leaders |
| `COMBAT` | `entities` | 1 | Each map's objects by stable id (`object:N`) with their state (open, lit, searched or opened, destroyed), each container's contents, the loot each seat found and each Cutthroat carries |

```json
"combat_map": { "version": 1, "data": { "sessions": [ { "map_id": "m1_greybox", "object_spots": [0, 3], "points": [ ], "leader_ids": [ ], "opening_swap_open": false } ] } },
"entities": { "version": 1, "data": { "sessions": [ { "objects": [ ], "contents": { "0": { } }, "found": { }, "carried": { } } ] } }
```

- **Built from snapshots.** Each capture takes the battle's `CombatEncounter.snapshot()` and keeps
  its part of each map's `map` (`MapState.capture()`), as the combat state pair does.
- **Not repeated here:** a breakable's HP (it is a unit, in `combat_state`), the turns survived,
  whether a Defend tile held and whether `COMBAT_ENDED` was recorded (`combat_state`'s turn, phase
  and finished flag decide them).
- **Leader marks** are saved because Defeat the Leader finds its leaders in the fact log, which a
  loaded battle starts without.
- **Load order.** Both sections only check and hold their data while the file loads, in either
  order (`entities` takes over a reserved slot, which restores first); `is_holding()` pairs them.
  On a `BATTLE` resume, `CampaignService.resume_battle(request)` takes the request Begin had (the
  gameplay screen builds it as for Begin), and `CampaignSession.resume_battle()` rebuilds the
  battle the way Begin set it up, without the loadout, the deployment and the opening, drawing
  nothing from a combat roll stream:
  1. If `CombatStateSection.is_holding()` or `CombatMapSection.is_holding()` is false, restart
     from Begin (`BATTLE_RETRY`).
  2. `CombatMapSection.load_into(battle)`: each map's `MapState` is replaced.
  3. `CombatStateSection.load_into(battle)`: its reload carries those maps and refuses a map that
     disagrees with its units (the swap window, a breakable).
  4. Set the run's id counter from the combat `instance_ids` section, as the session was given it
     when built: the rebuild minted throwaway ids, which the resumed battle mints again.
  Then the write-back copies are re-linked by instance id: each carrier's copy, the request's unit
  and item instances the battle holds, and each heirloom's saved copy, which becomes its carrier
  (a resumed run holds none, since carriers aren't saved). Any error: `SaveService.drop_battle()`
  deletes the combat file and sets `BATTLE_RETRY`, and the battle begins again from Begin, minting
  on from the run's counter.
- **The darkness isn't saved yet** (P06 DK5). A battle resumed before the darkness arrives is
  exact: its sources, drain and first release are setup results, rebuilt with the battle. One
  resumed after arrival keeps `has_darkness_arrived` (so no wave is sent again) and the release
  turns, but loses its layers, waves and contacts: the map is dry until the next release, which
  starts again from the sources and is recorded as the arrival again (`DARKNESS_ARRIVED`, since
  `DarknessState.has_arrived()` reads the waves); no unit takes darkness damage until then, and
  erosion counts start over.
- **Missing or old data.** A combat file without these sections, or with one only, holds no maps,
  so `load_into()` returns `ERR_UNCONFIGURED`. Version 0 is malformed and a newer version is
  refused, like any section; either stops the load and gives `BATTLE_RETRY`.
- **Mirrors** follow the objects and the points' closing and waves sent; the units waiting for
  room are in no fact, so a mirror's points are left out of `CombatSession.state_hash()`.

## Multiplayer

- Only the host saves a campaign, in its multiplayer slot, with every player's data in the
  `players` array. Clients never write campaign or combat files.
- On every host checkpoint, clients receive the campaign as `SaveService.multiplayer_replica` (never
  saved) and write only their own `profile.json`. When the run ends, each client writes the host's
  archive record into its own archive.
- Resume goes through the lobby: the host loads the campaign from the Main Menu, hosts, and only
  the campaign's players (by Steam id from the Steam connection, never from a message) and only the
  same game version are admitted. Resume needs every player present and Ready.
- The player count is set when a campaign starts. **Decided October 24, 2026, not yet built:** a
  non-host player who forfeits (or is removed by the host after a disconnect) leaves the campaign:
  their seat is removed from the save, so resuming no longer needs them, and their run is archived
  for them as lost. See [game-vision.md](game-vision.md#combat-maps).
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
