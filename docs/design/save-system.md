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
| Battle: end of each player phase (multiplayer: phases are per map, so each map checkpoints at the end of its own player phase, once every player with units on it has ended their turn; the format change this needs belongs to the multiplayer-combat plan) | `save_checkpoint()` |
| Battle ends | `end_battle()` |
| Save & Quit (pause menu) | `save_checkpoint()` |
| Run won, lost or abandoned | `end_run()` / `abandon_run()` |
| Options: Apply | `save_settings()`, writes only `settings.json` |

Apply your system's changes to its section state **before** the call; the call captures it.

## Settings

`settings.json` is `SettingsData`'s block, with no sections. Players can edit it, so a bad value
is repaired to its default on load and the file never fails for one; a file from a newer build is
refused and the defaults apply (with a warning). Options edits a copy; only Apply writes it.

| `core` key | Type | Default | Read by |
|------------|------|---------|---------|
| `master_volume`, `music_volume`, `sfx_volume` | int 0–10, clamped | 5 | `SettingsData.apply()`: the Master, Music and SFX buses (UI follows SFX); 0 mutes |
| `opening_swap` | bool (anything else is repaired) | `true` | The battle screen, as a solo battle begins (`BattleRequest.opening_swap`) |

- **Schema version 2.** Step 1 → 2 adds `opening_swap: true`, keeping a hand-written value for
  the load to read or repair.
- **Co-op:** the opening swap is read for the solo seat only. A co-op seat's setting would have to
  reach the host; until P11 sends it, every co-op seat opens in the swap window.

## Battles

`begin_battle()` captures the campaign's sections, marks the campaign `combat_in_progress`, then
writes the combat file and the campaign with the same `checkpoint_seq`. While a battle runs,
campaign writes keep the sections captured at Begin: everything the battle changes lives only in
`COMBAT` sections. That is what lets a battle restart from Begin if its combat file is lost.

**The end of each player phase** is saved by the battle screen (`BattleScreen`) as the phase's
last End Turn resolves, before its playback plays. That one command resolves the player Phase End,
the whole enemy phase, the hooks after it (the darkness phase, reinforcements) and the next player
Phase Start, intents included, so the save holds the start of the next player phase. A resume
re-runs none of it: no Phase Start fires twice, and the enemy phase's playback isn't shown again.
A phase end that finishes the battle writes no checkpoint; the battle's end saves it. A failed
save is logged and play goes on, the previous save kept. Solo only for now: P11 extends it so any
map's player phase end saves the whole battle (P11 question 39).

On continue, `SaveService.resume_point` says where to pick up:

| Campaign | Combat file | `resume_point` |
|----------|-------------|----------------|
| not in battle | none, or a stale one (deleted) | `CAMPAIGN` |
| in battle | same `checkpoint_seq`, or one ahead | `BATTLE` (combat loaded) |
| in battle | missing, unreadable, any other seq | `BATTLE_RETRY` (restart from Begin) |

A combat system must therefore keep battle-changed state (unit HP, items used, deaths) in its
`COMBAT` section, and apply the results to `CAMPAIGN`/player sections only before `end_battle()`.
A resumed battle's rolls continue where they were saved (next section).

**The end of a battle** (`CampaignService.end_battle()`) runs in this order, so a crash at any
point loses and repeats nothing:

1. **Collect.** `CampaignSession.collect_battle()` writes campaign-lane values back and gathers the
   result: each unit's HP, falls, permanent deltas (Hit included) and growth changes, each heirloom
   copy's campaign lane, the grants received ([Battle tally](#battle-tally)), the map, won or lost.
   The battle stays in progress.
2. **Apply.** `CampaignRunState.apply_battle()` applies it to a *copy* of the run, which replaces
   the session's run. The old run is kept in memory.
3. **Save.** `SaveService.end_battle()` writes the campaign with the copy's sections and deletes the
   combat file. If the write fails, the old run comes back and the battle stays in progress, so
   trying again applies the result once. A solo battle lost calls `end_run(false)` here instead.
4. **Drop.** `CampaignSession.end_battle()` closes the encounter and drops the heirloom and curse
   carriers, whose lanes the run now holds ([Run state](#run-state), `heirlooms`).

A crash before step 3's write leaves the campaign in battle, so Continue resumes the battle from its
last save (or restarts it from Begin) and plays to the same end; nothing applied in memory was
saved. A crash after it leaves a campaign out of battle and a stale combat file, which the next load
deletes.

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
  counter wins. **`BATTLE_RETRY`** resets the combat block, so a restarted battle mints on from
  the counter the campaign file holds. Begin captured that counter after it minted the army and
  the setup, so the restarted battle gets **new ids**; only its rolls repeat
  ([RNG streams](#rng-streams)). Nothing reads an id for meaning, so new ids change nothing
  that plays.
- A save from before these sections resumes with a fresh counter. Nothing saved before them holds
  an instance id, so nothing can collide.

## Run state

The run's campaign state (`CampaignRunState`: the map, the route, the run flow and each seat's
`SeatRun`) is six `CAMPAIGN` sections, all `RunSaveSections`, which `CampaignService` registers
after `instance_ids`, the map before the flow
([campaign and run flow plan](../plans/2026-10-24-campaign-run-flow.md), Save Impact). How a run
uses them is in the [campaign layer guide](campaign-run.md).

| Key | Per player | Version | Holds |
|-----|------------|---------|-------|
| `campaign_map` | No | 2 | The map, the route taken and the co-op route votes |
| `run_flow` | No | 2 | The stage within a node, the Unknown odds and outcome, the maps used, the shared shop stock, the accepted co-op unit swaps |
| `roster` | Yes | 1 | The army, the fallen, the convoy and every item the seat holds |
| `heirlooms` | Yes | 2 | Owned heirlooms and curses with their campaign lanes, and the seat's value changes |
| `runes` | Yes | 1 | The 3 rune slots |
| `economy` | Yes | 2 | Gold, the rare offset and the seat's pending offers |

Each section is written by its class's `capture*()` and read back by the matching `restore*()`.
Their keys are listed below.

**`campaign_map`** (`CampaignRunState.capture_map()`):

- `graph`: the whole map, `CampaignGraph.to_dict()`, so a continued run walks the same map.
- `visited`: the node ids entered, one per floor from floor 1.
- `floor`: the floor of the current node; 0 before the first.
- `node`: the current node's id; -1 before the first.
- `votes`: each co-op seat's route vote (`RouteVoteCommand`), by seat as a decimal string: a node
  id. All are choices of one move: the next one while the vote is open, or the one just made,
  since the votes stay after the draw until the next floor's first vote. Empty in solo and before
  the first vote. A quit mid-vote keeps them.

**`run_flow`** (`RunFlow.capture()`):

- `stage`: `"map"` (between nodes), `"node"` (inside one) or `"results"` (a won combat's rewards
  waiting).
- `unknown_odds`: the current chance of each thing an Unknown can become, in percent, by
  `UnknownResolution`'s odds keys `combat`, `shop` and `treasure`; an event takes the rest. Empty
  means every type at its base chance. The odds carry from one Unknown to the next.
- `unknown`: what the Unknown node the run is in became: `"combat"`, `"armory"`, `"guildhall"`,
  `"treasure"` or `"event"`. Empty means not rolled yet, or not in an Unknown. It is rolled on entry
  (`ResolveUnknownCommand`) and cleared when the node is left. A run saved before the key existed
  has none, which reads as not rolled.
- `used_maps`: the combat map ids used since their pool last refilled, oldest first.
- `shop_stock`: stock every seat shares, by shop. Empty means nothing rolled. Both shops roll on
  entry, from the node's shared `SHOP_STOCK` stream, and are cleared when the node is left:
  - `armory` (`ArmoryStock`): `entries`, each `{category, definition_id, instance_id,
    is_shop_slot, buyer}`. `category` is `"weapon"`, `"equipment"`, `"trinket"`, `"consumable"`
    or `"heirloom"`; `instance_id` is empty for an heirloom; `buyer` is the seat that bought it,
    -1 while it is for sale.
  - `guildhall` (`GuildhallStock`): `entries`, each `{category, buyer}` plus, for a `"recruit"`,
    `recruit` (`{unit, items}` as `roster` writes them, at level 1: the buyer's level is applied
    on purchase) or, for a `"rune"`, `definition_id` and `instance_id`; and `rerolls`, each seat's
    prefix re-rolls this visit (`{free, paid}`), by seat.
- `swaps`: the co-op unit swaps accepted for the next combat the team fights (`UnitSwap`), in the
  order accepted, each `{seat_a, unit_a, seat_b, unit_b}`: seat A proposed, its `unit_a` starts
  that combat on seat B's map and seat B's `unit_b` on seat A's. They stay through non-combat
  nodes and during the battle (a resume rebuilds the same request), and end when the combat ends,
  a named unit leaves its army, or either seat withdraws. Empty in solo. Open proposals are never
  saved: a quit loses them (coop-unit-swaps.md, decision 7). A run saved before the key existed
  has none.

**`roster`** (`SeatRun.capture_roster()`):

- `faction_id` and `commander_id` (the commander is one of `army`).
- `army`: the living units in roster order, the commander first (`UnitInstance.capture()`).
- `fallen`: the units that fell, in the order they fell, each still holding its items.
- `convoy`: the ids of the items in the convoy, in the order they arrived.
- `items`: every item the seat holds, by id, whether in a unit's slot or in the convoy. Each item
  is in exactly one place.
- **The convoy's size isn't saved.** It is always the seat's max army size
  (`ItemPlacement.convoy_capacity()`, read through `RunOperations.max_army_size()`), so heirlooms,
  curses and value changes that change the army size change it too. It is a hard cap: an item
  enters a full convoy only after one is scrapped. A convoy left above the cap counts as full.

**`heirlooms`** (`SeatRun.capture_heirlooms()`):

- `entries`, in gain order: `heirloom_id`, `counters` and `charges` (the campaign lane). A second
  copy (a repeated curse) is a second entry.
- `value_changes`, in the order made: the seat's own campaign value changes that no heirloom
  carries, each `{key, amount, source_id, label}`. `key` is a `campaign.` key as
  `Modifier.key_id()` names it, and `amount` is added to the value, such as an event's
  `campaign.MAX_ARMY_SIZE` +1 (the Company Charter). `RunOperations` adds them to the seat's reads.
- **Carriers are never saved.** A held heirloom's or curse's effect carriers exist only during a
  battle. Each Begin makes them from these lanes (`CampaignSession.begin_battle()`), and the
  battle's end drops them (`abandon_battle()`, which `end_battle()` ends through), after
  collecting each copy's lane for the run to save. So a continued run mints the same instance ids
  as one never quit, and same-rank heirloom reactions keep their order. Outside a battle,
  `CampaignSession.heirloom_copies()` is empty. A resumed battle adopts the copies its save holds
  as carriers instead ([Combat map](#combat-map)).

**`runes`** (`SeatRun.capture_runes()`):

- `slots`: exactly 3, each `{}` or `{instance_id, definition_id}`. A battle carries them in
  (`CombatState.rune_slots`, saved with the battle's own state) and its end empties the slot of
  every rune cast or discarded.

**`economy`** (`SeatRun.capture_economy()`):

- `gold`: 0 or more.
- `rare_offset`: whole percentage points, -5 to +40, starting at -5.
- `pending_offers`: this seat's rolled offers waiting for a choice, by key. Each is rolled before
  it shows, so a quit and Continue shows the same offer:
  - `starting_heirloom`: from run start. `options` of `{heirloom_id, recruits, weapons,
    drawn_heirloom_id}` (each recruit `{unit, items}` as `roster` writes them, each weapon
    `{definition_id, instance_id}`), `is_resolved`, and `taken` (-1 while open or after a skip).
    Kept after it is taken or skipped.
  - `combat`: a won combat's report, at its results. `grades`, `xp` per unit, `level_ups`, and
    `stats` (each seat unit that fought, fallen ones too, by id, as `battle_stats` names them).
  - `item_pick`: at a combat's results. `slot`, `offers` of `{definition_id, instance_id}`,
    `is_resolved` and `taken`.
  - `key_heirloom`: after a Key combat. `heirloom_id`, `is_resolved` and `is_taken`.
  - `treasure`: inside a Treasure, rolled on entry. `tier`, `gold` (0, or 20 to 60),
    `heirloom_id`, `item` (`{definition_id, instance_id}` or `{}`), `is_resolved` and `is_taken`.
  - `camp`: inside a Camp. `choice`: `""`, `"feast"` or `"train"`.
  - Every key but `starting_heirloom` is cleared when the node is left (`LeaveNodeCommand`).
  - In co-op, a teammate's first claim of a unique heirloom replaces it where it is offered, in
    place: `treasure`'s and `key_heirloom`'s `heirloom_id`, a `starting_heirloom` option's
    `drawn_heirloom_id`, and an open event's pick in `events` (`UniqueClaims`, P11 CO7). No shape
    or version changes; the draw moves that offer's saved stream (`rng`).

The stock and the pending offers are free-form JSON in the shape each rule defines, so adding a
shop or an offer key changes no version, and an optional key read as missing changes none either.

- **A part with no run is `{}`.** A new run's first save comes before its session exists, so it
  writes `{}` everywhere; `CampaignService` then builds the run (`RunStart`: the map from the
  `MAP_GENERATION` stream, each seat's army, gold and Commander Heirloom from its faction) and saves
  again. A continued save that holds no run (a crash between those writes, or a save from before
  these sections) gets the same new run built from its seed.
- **Load order.** Like the `rng` sections, each section only checks and holds its data while the
  file loads (the flow against the held map); `RunSaveSections.attach()` builds the session's run
  from it. A file holding only some parts loads no run and is written back unchanged.
- **Versions.** `economy` is at 2: version 2 added the combat report's `stats`. Its migration from
  1 changes nothing, since a report without `stats` reads as one with no numbers (the recap shows
  "—"). `heirlooms` is at 2: version 2 added `value_changes`. Its migration from 1 changes
  nothing, since a section without them reads as a seat with none. `campaign_map` is at 2:
  version 2 added `votes`. Its migration from 1 changes nothing, since a map without them reads
  as one with no votes. `run_flow` is at 2: version 2 added `swaps`. Its migration from 1 changes
  nothing, since a flow without them reads as one with no swaps. The other two are at 1.
- **Validated:** a route that skips a floor or leaves the graph's edges, a stage inside a node
  before any node, an unknown stage, Unknown odds that aren't whole numbers, an Unknown outcome
  that isn't one of the five, an item in two places or in none, a commander outside the army, a
  repeated unit or rune, out-of-range gold or offset, and a value change whose key isn't a campaign
  value, whose amount isn't a number, or whose `source_id` or `label` isn't a string, and a swap
  naming one seat twice, an empty unit or a unit or pair of seats another swap names, each refuse
  the section and stop the load. The shop stock and pending offers are checked by the rules that
  read them, not on load; a swap's units are checked against the armies when the battle request
  is built, which leaves out a swap naming a unit its army doesn't hold, with an error.
- **Saved when:** every resolved campaign command (`CampaignService.submit_command()`) saves at
  once; a rejected one saves nothing. A failed save is logged and the change stays in memory for
  the next checkpoint to write. A battle's end saves its result applied
  ([Battles](#battles)): HP, fallen units in `fallen` with their items (a fallen commander stays in
  `army` at critical HP), deltas, heirloom counters, grants, the map in `used_maps` and, after a
  win, the rewards (gold, XP, level-ups, the item pick, the moved `rare_offset`, the `REWARD` and
  `LEVEL_UPS` streams' positions) with the stage at `"results"`. Rewards are rolled once, before
  that save; a failed save puts the run, its campaign streams and its id counter back, so a retry
  rolls the same. Taking or skipping the pick and leaving the node are commands, each saved.
- **The core follows:** every save `CampaignService` makes sets `CampaignData.floors_climbed`, which
  Save Select and the archive show, to the run's `floor`.

## Events

The run's events (`CampaignRunState.events`, an `EventRunState`) are one more `CAMPAIGN` section,
`EventSaveSection`, which `CampaignService` registers after the run sections
([events and curses plan](../plans/2026-11-12-events-and-curses.md), Save Impact):

| Block | Key | Per player | Version | Holds |
|-------|-----|------------|---------|-------|
| `CAMPAIGN` | `events` | No | 1 | `seen` event ids since the pool last refilled, in draw order; `current`, the event open at a node (`{}` with none): `event`, `floor`, `node`, `seats` (by seat as a decimal string: `rolls`, one per option, each with `picks`, the content id each block drew by block index as a decimal string, `""` for a block whose pool was empty, and `curse`, the tier's curse or `""`, and for an option with a recruit an optional `prefixes`, the unit prefix id each recruit block drew by block index as a decimal string (absent reads as none, so a save without it draws the recruit when the option applies); `choosing`, the option whose chooser is open, or in a team choice the option the votes drew, -1 for none; `chosen`, -1 for none), `votes` (by seat, an option index; empty until the team vote), `combat_pending` |

```json
"events": { "version": 1, "data": { "seen": ["dark_goblet"], "current": { "event": "dark_goblet", "floor": 3, "node": 7, "seats": { "0": { "rolls": [ { "picks": {}, "curse": "" }, { "picks": { "0": "frost_blade" }, "curse": "haunted" } ], "choosing": -1, "chosen": -1 } }, "votes": {}, "combat_pending": false } } }
```

- **Rolled before shown:** opening an event draws it and every seat's random parts (items, runes,
  heirlooms, tier curses) in one command, saved at once, so a quit and Continue shows the same
  event, curses and items; a node never draws a second event. The prefix re-roll and a random
  recruit's type and prefix draw when their option applies, from the seat's `EVENT_OUTCOME`
  stream, saved in `rng`.
- **The chooser stage is saved;** the unit that leaves a full army, item placements and a rune to
  discard are not, since they come with the choice itself. A quit during those steps resumes at
  the chooser or the options.
- **Team choices** add no key: the votes go in `votes`, and the option they draw is every seat's
  `choosing` until the team's choice applies it. Votes stay saved after that, until the next event
  opens, so the tally still shows.
- **After every seat has chosen,** the event stays saved until the next one opens, so Continue
  shows the same outcome.
- **What an option changes** lands in the run sections: curses and heirlooms in `heirlooms`, a max
  army size change in its `value_changes`; units (stat changes, pending level-up gains, recruits,
  revives, upgrades, dismissals) and items in `roster`; gold in `economy`. A pending surprise combat
  makes the node's battle a Standard one (`CampaignRunState.battle_request()`), saved like any
  battle from Begin.
- **Load order.** Like the run sections, it only checks and holds its data while the file loads;
  once the run is built, `CampaignService` puts it into the run, and the section reads the run from
  then on, the copy a battle's end swaps in included.
- **Refused:** a missing field, an empty id, a seat key or number that isn't whole, a block index
  that isn't a whole number from 0, a pick or curse that isn't a string, a choice or vote outside
  the seat's options, a vote for a seat not in the event, and a seat both choosing and chosen. A
  saved event id the event pool doesn't hold loads, and the event screen reports it.

## Combat state

The battle itself is two `COMBAT` sections, one `CombatStateSection` and its partner, which
`CampaignService` registers in this order ([combat core plan](../plans/2026-10-26-combat-core.md),
Save Impact):

| Block | Key | Version | Holds |
|-------|-----|---------|-------|
| `COMBAT` | `combat_state` | 4 | Each map's units (`CombatUnitState`: tile, HP, Block, Stance, what it did this turn and phase, movement spent, a pending second move, slots, growth changes, and the prefix and level the unit detail shows; version 1 and 2 units migrate with no prefix and level 1), weapon records (an area staff's shape by its id and a heal staff's full heal included; version 1 records migrate with neither), turn, phase side, ended and not-yet-started seats, rune slots, and the session part (seq, commanders, bases, finished and won); the encounter's seq, arrivals and units on their way between maps; from version 4, each unit on its way's clock turn (the turn the map it left was won on), each seat's latest send (`sends`: target map or -1 for none, and that turn), each map's senders (`senders`: seats whose units landed there) and raised calls for aid (`aid`), and forfeited seats (`forfeited`, empty until CO14); version 1 to 3 data migrates with none sent, received, called or forfeited and clock turn 0, due at the next player Phase Start as before |
| `COMBAT` | `effects` | 1 | Each map's effect engine (instances with counters and charges, timed modifiers, bases and deltas, phase and attack counts) and the encounter's cross-map instances |

```json
"combat_state": { "version": 4, "data": { "encounter": { }, "sessions": [ { "session": { }, "combat_state": { } } ] } },
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
  1. If `CombatStateSection.is_holding()`, `CombatMapSection.is_holding()` or
     `DarknessSaveSection.is_holding()` is false, restart from Begin (`BATTLE_RETRY`).
  2. `CombatMapSection.load_into(battle)`: each map's `MapState` is replaced, its darkness left as
     the rebuild placed it.
  3. `DarknessSaveSection.load_into(battle)`: each map's darkness is replaced
     ([Darkness](#darkness)).
  4. `CombatStateSection.load_into(battle)`: its reload carries those maps and their darkness, and
     refuses a map that disagrees with its units (the swap window, a breakable).
  5. Set the run's id counter from the combat `instance_ids` section, as the session was given it
     when built: the rebuild minted throwaway ids, which the resumed battle mints again.
  Then the write-back copies are re-linked by instance id: each carrier's copy, the request's unit
  and item instances the battle holds, and each heirloom's saved copy, which becomes its carrier
  (a resumed run holds none, since carriers aren't saved). Any error: `SaveService.drop_battle()`
  deletes the combat file and sets `BATTLE_RETRY`, and the battle begins again from Begin, minting
  on from the run's counter.
- **Missing or old data.** A combat file without these sections, or with one only, holds no maps,
  so `load_into()` returns `ERR_UNCONFIGURED`. Version 0 is malformed and a newer version is
  refused, like any section; either stops the load and gives `BATTLE_RETRY`.
- **Mirrors** follow the objects and the points' closing and waves sent; the units waiting for
  room are in no fact, so a mirror's points are left out of `CombatSession.state_hash()`.

## Darkness

Each map's darkness is one more `COMBAT` section, `DarknessSaveSection`, which `CampaignService`
registers after the combat map pair ([darkness plan](../plans/2026-11-03-the-darkness.md), Save
Impact):

| Block | Key | Version | Holds |
|-------|-----|---------|-------|
| `COMBAT` | `darkness` | 1 | Each map's active sources, drain, waves (source index, reach, the tiles each has entered), each flooded tile's layer, each breakable's turns of contact, and whether the darkness has arrived |

```json
"darkness": { "version": 1, "data": { "sessions": [ { "sources": [["0,2", "0,3"]], "drain": "7,7", "waves": [ { "source": 0, "reach": 2, "entered": ["0,2", "0,3", "1,2"] } ], "layers": { "0,2": "DUSK" }, "contacts": { "object:4": 2 }, "arrived": true } ] } }
```

- **Built from snapshots.** Each capture keeps the `darkness` part of each map's `map`
  (`MapState.capture()`, from `DarknessState.capture()`), the part a rejoining client's snapshot
  carries, without its first release.
- **Tiles as `"x,y"` strings**, layers by name (`DUSK`, `GLOOM`, `ABYSS`; a dry tile is absent),
  contacts by object id, `drain` `""` for none. Tiles are written row-major and ids in order, so
  equal states write equal text.
- **Never saved:** heights and flow costs (derived from the map each time), and the first
  release. The sources, drain and first release are setup results the rebuilt battle places again
  (`DarknessSetup.place()`, Short Wick included); the saved sources and drain are checked against
  them, and `arrived` against `combat_map`'s `has_darkness_arrived`.
- **Entered tiles are saved:** a wave enters each tile once, ever, so a wave restored without them
  would deepen tiles again once a door that closed on them opens (darkness plan, question 11 c).
- **Load order.** The section only checks and holds its data while the file loads. On a `BATTLE`
  resume it loads after the maps and before the units ([Combat map](#combat-map), step 3), so a
  battle resumed after arrival has the saved layers, waves and contacts and goes on as if never
  quit.
- **Missing or old data.** A combat file without the section (from before it) holds no darkness,
  so the battle restarts from Begin (`BATTLE_RETRY`), as for any missing combat section. Version 0
  is malformed and a newer version is refused; so are other sources or drain, an arrival
  `combat_map` disagrees with, and a contact with an object the map doesn't have. Each stops the
  load and gives `BATTLE_RETRY`.
- **Mirrors** follow the darkness's facts (`CombatState.follow()`): each release adds a wave from
  its source and the first sets `has_darkness_arrived`, each tile deepened takes its layer, each
  contact and erosion its count. A wave's reach and entered tiles are in no fact, so a mirror's
  stay 0 and empty, and `CombatSession.state_hash()` covers the darkness's arrival, wave sources,
  layers and contacts only.

## Battle tally

The battle's XP actions, the grants it has received and how each unit fought are three more
`COMBAT` sections, one `BattleTallySection` and its two partners, which `CampaignService`
registers after the darkness ([campaign and run flow plan](../plans/2026-10-24-campaign-run-flow.md)
and [UL5 plan](../plans/2026-11-19-ul5-victory-sequence.md), Save Impact):

| Block | Key | Per player | Version | Holds |
|-------|-----|------------|---------|-------|
| `COMBAT` | `battle_tally` | No | 1 | Each player unit's XP actions so far (`BattleTally`), counted from the battle's facts |
| `COMBAT` | `battle_grants` | No | 1 | The grants the battle has received, in order, for the run to apply at its end |
| `COMBAT` | `battle_stats` | No | 1 | Each player unit's kills, damage dealt and taken, and HP healed so far (`BattleStats`), for the victory recap |

```json
"battle_tally": { "version": 1, "data": { "units": { "unit:57": { "hit": 3, "defeat": 1, "heal": 0, "block": 1, "non_combat": 1 } } } },
"battle_grants": { "version": 1, "data": { "grants": [ { "seat": 0, "grant": "gold", "amount": 50, "definition_id": "", "source_effect_id": "effect:12" } ] } },
"battle_stats": { "version": 1, "data": { "units": { "unit:57": { "kills": 1, "damage_dealt": 14, "damage_taken": 6, "healed": 0 } } } }
```

- **Saved, not rebuilt:** a resumed battle's fact log starts empty, so none could be rebuilt
  from it. A unit with no action (or no stat above 0) is left out; a listed unit names all five
  actions (all four stats).
- **Actions** by name: `hit`, `defeat` (against enemy-side units only; breakables don't count),
  `heal`, `block` (given to another player unit, above 0), `non_combat` (closing a reinforcement
  point, searching, opening a chest). Grants by name: `gold`, `heirloom`, `recruit`, `rune`.
- **Stats** by name: `kills` and `damage_dealt` (on enemy-side units only; a fact's whole amount,
  Block and HP), `damage_taken` (every source, the darkness's own fact included), `healed` (HP
  given to another player unit, overhealing included). They earn no XP.
- **Load order.** All three only check and hold their data while the file loads. On a `BATTLE`
  resume they load into the session last, after the combat checkpoint's id counter. A combat file
  without one (from before it) resumes with it empty. Begin, the battle's end and `BATTLE_RETRY`
  reset them, so a battle restarted from Begin counts from nothing.
- **Refused:** an unknown action, grant or stat, a number below 0, or a number that isn't whole.
  Like any combat section, that stops the load and gives `BATTLE_RETRY`.

## Multiplayer

- Only the host saves a campaign, in its multiplayer slot, with every player's data in the
  `players` array. Clients never write campaign or combat files.
- On every host checkpoint, clients receive the campaign as `SaveService.multiplayer_replica` (never
  saved) and write only their own `profile.json`. When the run ends, each client writes the host's
  archive record into its own archive.
- Resume goes through the lobby: the host loads the campaign from the Main Menu, hosts, and only
  the campaign's players (by Steam id from the Steam connection, never from a message) and only the
  same game version and build (`NetContract.fingerprint()`) are admitted. Resume needs every
  player present and Ready.
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
