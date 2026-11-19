# Map Authoring

How to make a combat map today: the files, the layers and markers, how ids are numbered, the
generator, the map check, darkness sources and the pools. It describes the code on `dev`; the
design is in the [combat map plan](../plans/2026-10-27-combat-map.md), the objects' rules in
[map-objects.md](map-objects.md), the darkness's in [the-darkness.md](the-darkness.md).

Every map so far is generated from text by `tools/gen_maps.gd`. An editor toolkit for building maps
by hand (a template scene, painting, the check and a "play this map" launch) is later work, P04
MP11. Paths are relative to `bandit-bash/`.

## A map is two files

| File | Holds |
|------|-------|
| `maps/<type>/<id>.tscn` | The scene: the painted terrain, the marker layer and the marker nodes |
| `maps/<type>/<id>.tres` | Its [CombatMapDefinition](../../bandit-bash/scripts/map/combat_map_definition.gd): the rules data that isn't painted |

`<type>` is `standard`, `key` or `boss`. The definition's fields:

| Field | Means |
|-------|-------|
| `id` | The map's id in saves and logs, the file name, unique across every map |
| `scene` | The scene above. Unset: the map can't load |
| `combat_type` | `STANDARD`, `KEY` or `BOSS` |
| `objective` | `ROUT`, `DEFEAT_LEADER`, `DEFEAT_BOSS`, `SEIZE`, `SURVIVE` or `DEFEND` |
| `turn_par` | Turns a good clear takes, set by hand per map; the grade's speed bonus and the darkness's arrival read it. 0 is unset |
| `survive_turns` | Survive and Defend: the turn whose enemy phase ends the combat |
| `pool` | Not read by the map draw (see [Pools](#pools)); leave it empty |
| `fixed_pack_id`, `fixed_enemy_level`, `fixed_leader_level`, `fixed_leader_prefix_id` | A scripted map's own enemies, placed undrawn, as the Powder Baron's keep does. Empty or 0: setup draws a pack |

[MapLoader](../../bandit-bash/scripts/map/map_loader.gd) turns the pair into a pure
[MapLayout](../../bandit-bash/scripts/map/map_layout.gd) at battle start; nothing in a battle holds
the scene.

## The scene

- **`Terrain`**, a `TileMapLayer` with that exact name. Each tile's `terrain` custom data is a
  terrain id, a file in `data/terrain/<id>.tres`
  ([TerrainDefinition](../../bandit-bash/scripts/map/terrain_definition.gd): movement costs, avoid,
  DEF and RES, healing, shove blockers, slick). A tile with terrain is a tile on the map; the map's
  size is the terrain's rectangle.
- **Marker layers:** every other `TileMapLayer`. Each tile's `marker` custom data names a plain
  marker (below). The generator names its one layer `Markers`.
- **`MapMarker` nodes** ([scripts/map/map_marker.gd](../../bandit-bash/scripts/map/map_marker.gd))
  for markers with parameters, at any depth under `Node2D` parents. Each sits on the terrain cell
  under it and snaps to its center in the editor. The generator groups them under `EnemySlots`,
  `Objects`, `ReinforcementPoints` and `DarknessSources`.
- Layers and nodes may overlap: one tile can hold several markers, and a marker gives the same
  layout entry and the same id whichever way it was authored.
- **The tile set** is `maps/greybox_tile_set.tres`: 32 × 32 cells with the `terrain` and `marker`
  custom data layers, one cell per terrain and one per marker name. Since P15 UL2 its texture is
  `assets/sprites/terrain/terrain_atlas.png`, one tile per terrain cut from Godot_FE's sheets (the
  sources are in [art-sources.md](art-sources.md#terrain)); maps kept their cells, so none was
  repainted. In play the board hides the marker layers and nodes; `BattleView.show_markers`
  shows them, to check a map's authoring.

### Markers

Plain markers, as `marker` custom data on a marker layer:

| Name | Marks |
|------|-------|
| `deployment` | A player deployment tile. At least 8 |
| `seize`, `defend` | The Seize or Defend objective's tile |
| `leader_slot` | Where a Defeat the Leader map's leader, a key map's mini-boss or the boss stands |
| `reinforcement_point`, `enemy_slot`, `darkness_source` | As the node kinds below, without parameters: a point with no arrival turns (never sends), a slot with no variance or group, a source candidate of its own |
| `chest`, `house`, `food_shelf`, `book_shelf`, `weapon_rack` | A container (one search or one opening) |
| `wooden_debris`, `stone_debris`, `powder_keg` | A breakable. At most 3 kegs |
| `brazier` | A Brazier the darkness reads |
| `door`, `lever`, `passage` | Accepted, but these need a group or pair, so author them as nodes |

`MapMarker` kinds and the exports each reads:

| Kind | Exports |
|------|---------|
| `ENEMY_SLOT` | `variance_tiles` (how far setup may shift its enemy, grid distance), `group_slot` (a name such as `A`; slots sharing it fill from one group) |
| `DOOR` | `group_id` (its lever group; -1 opens only with a Key or Lockpick), `door_size` (tiles right and down; the tiles open and close as one) |
| `LEVER` | `group_id` (the doors it toggles) |
| `PASSAGE` | `pair_id` (exactly two ends share one) |
| `REINFORCEMENT_POINT` | `arrival_turns` (one wave after each listed turn's enemy phase) |
| `DARKNESS_SOURCE` | `group_id` (nodes sharing an id form one candidate; -1 is a one-tile candidate) |

What each object does is in [map-objects.md](map-objects.md); how many enemy slots a map needs is
in [enemy-packs.md](enemy-packs.md) ("What this means for maps").

### Ids

`MapLayout.index_markers()` sorts the markers row-major by tile, then by `MapLayout.MarkerKind`, and
numbers object spots, containers and reinforcement points in that order. The numbers are the object
ids in facts and saves and each container's `MAP_LOOT` index, so every load and every co-op copy of
a map agrees. Moving, adding or removing a marker renumbers the ones after it, which breaks a save
made mid-battle on that map (the combat map section refuses it, and the battle restarts from
Begin). Changing the order rule or the `MarkerKind` values would renumber every map.

## Making a map with the generator

[tools/gen_maps.gd](../../bandit-bash/tools/gen_maps.gd) builds every M2 map from text:

1. Add a `MapSpec` in `_standard_maps()`, `_key_maps()` or `_boss_maps()`:
   `MapSpec.standard(id, node_name, objective, turn_par, par_note)` (or `.key()`, `.boss()`).
2. Give it `terrain` rows, one character per tile (`TERRAIN_CHARS`: `.` plain, `F` forest, `W`
   wall, `~` river and so on), and `markers` rows of the same size (`MARKER_CHARS`: `d` deployment,
   `c` chest, `k` powder keg, `L` leader slot, `Z` seize, `X` defend; `.` none).
3. Add the node markers: `slots([[x, y, group], …])`, `sources([[x, y, group], …])`,
   `door(tile, lever_group, size)`, `lever(tile, lever_group)`, `passage(tile, pair)`,
   `point(tile, turns)`, and `hold_for(turns, note)` for Survive and Defend.
4. Run it from the repo root:
   `godot --headless --path bandit-bash --script res://tools/gen_maps.gd -- <map id>`.

It writes the scene and the definition, writes each value's reasoning as a `;` comment above it
in the `.tres` (the `# ASSUMPTION` notes on turn par), runs the map check on the saved files and
prints one line per map: its size, enemy slots, deployment tiles and `check PASS` or the failures.
It exits with 1 if any map fails. Rebuilding updates the files in place, so node and resource ids
stay and unchanged data writes the same bytes; marker nodes the data no longer lists are removed.
Every slot gets a variance of 2 (`SLOT_VARIANCE`).

The M1 map (`maps/standard/m1_greybox`) predates the generator and was built by hand; tests use it
and no pool draws it.

## The map check

[MapCheck](../../bandit-bash/scripts/map/map_check.gd) runs on the loaded layout and the
definition. Each failure names its rule and, for a rule about one tile, the tile:

| Rule | Fails when |
|------|-----------|
| `LOAD_PROBLEM` | The loader couldn't read a tile or a marker: an unknown terrain or marker name, a marker off the map |
| `NEGATIVE_TILE` | A tile or marker has a negative coordinate |
| `DEPLOYMENT_TILES` | Fewer than 8 deployment tiles |
| `POWDER_KEGS` | More than 3 powder kegs (the Powder Baron's arena can't waive it yet: TOD-001) |
| `CONTAINER_INDEX` | A container shares its index with another, or has none |
| `OBJECTIVE_TILE` | Seize without a seize tile, Defend without a defend tile, Defeat the Leader or the Boss without a leader slot |
| `REINFORCEMENT_POINT` | A point on a tile some movement type can't stand on |
| `DOOR_GROUP` | A door in a lever group no lever pulls |
| `LEVER_GROUP` | A lever in no group, or in a group with no door |
| `PASSAGE_PAIR` | A passage end in no pair, or a pair without exactly two ends |
| `DARKNESS_SOURCES` | A map with the darkness has fewer than 2 source candidates, or a candidate with no floodable tile ([Darkness sources](#darkness-sources)) |
| `REACHABILITY` | A required tile, or a lever of a lever door, can't be reached from the deployment zone without a key, or an area behind a lever door has no lever of its group to get out by. The full rule is in [map-objects.md](map-objects.md#reachable-maps) |

It runs in the generator, in `tests/map/` (`check_cases.gd`: one bad fixture per rule) and in the
`map_set/standard` suite, which also checks each shipped map against game-vision.md: its size
(standard 8 × 6 to 10 × 8, key 12 × 10), its objective and turn par, cover near the deployment zone,
its leader slot, and enough enemy slots for its largest pack plus two for Hunted. That suite lists
the maps by id (`STANDARD_MAPS`, `LEADER_MAPS`, `KEY_MAPS` in `tests/map_set/map_set_cases.gd`), so
a new map is added there too. Run `sh bandit-bash/tools/run_tests.sh map map_set`.

## Darkness sources

A map gets the darkness when it has a turn par and an objective with a drain: every objective but
Survive and Defend ([DarknessSetup.has_darkness](../../bandit-bash/scripts/map/darkness_setup.gd)).
Such a map needs source candidates.

- **A candidate** is one or more `darkness_source` markers. `DARKNESS_SOURCE` nodes sharing a
  `group_id` of 0 or more form one candidate; a node with -1, or a plain marker tile, is a
  candidate of its own. Candidates are numbered in the order their first marker comes in the
  layout.
- **At least 2 candidates**, each with at least one floodable tile as the battle starts (doors
  closed, breakables standing): the map check's `DARKNESS_SOURCES` rule. A floodable tile is on
  the map, standable by some movement type other than Flier, and not a closed door or an unbroken
  breakable; units never block it.
- **At battle start** setup step 3 picks the active candidates with the shared `ENCOUNTER_SETUP`
  stream: 1 on a standard map, 2 on a key or boss map, all of them when there are no more. The
  rest are ordinary terrain for that battle.
- **The drain**, where the darkness flows toward: on Rout, the floodable tile farthest by walking
  distance from every active source tile, a tie drawn from the same stream; on Defeat the Leader
  and Defeat the Boss, the leader slot; on Seize, the seize tile. Every tile's height is its
  walking distance to the drain over floodable tiles, which sets the step costs (downhill 1, level
  2, uphill 3; [DarknessFlow](../../bandit-bash/scripts/map/darkness_flow.gd)).
- **The first wave** is released in the darkness phase of turn par − 1, later with Short Wick.

Where to put candidates, and what to look for, is in
[the-darkness.md's authoring guidelines](the-darkness.md#authoring-guidelines). The map check proves
the candidates exist and can flood; it doesn't judge the flow. To see it, play the map past turn
par, where the board plays the spread tile by tile, or build the map's state in a test as
`tests/darkness/` does (`flow_cases.gd` for heights and flow costs, `setup_cases.gd` for the pick
and the drain).

## Pools

A battle's map is drawn from `data/campaign/combat_map_pools.tres`
([CombatMapPools](../../bandit-bash/scripts/campaign/combat_map_pools.gd)): one
[CombatMapPool](../../bandit-bash/scripts/campaign/combat_map_pool.gd) per node type and floor
range, each listing its maps. No map repeats until its pool is used up, counted across the run. As
it stands, every standard pool (floors 1–5, 6–11, 12–17) holds the same six maps, both key pools
(6–11, 12–17) the same four, and the boss pool (18) the Powder Baron's keep. Adding a map to a pool
is a data change: add it to the pool's `maps`. The definition's `pool` field plays no part in it.

## Checklist

1. Write its `MapSpec` and run the generator until the check passes.
2. Set the turn par by hand and say why in its note.
3. Leave room for the packs its pools draw, plus two enemy slots for Hunted.
4. Give it at least two darkness source candidates unless it is Survive or Defend.
5. Add it to its pools and to the map set's test lists.
6. Run `sh bandit-bash/tools/run_tests.sh map map_set`, then play it.
