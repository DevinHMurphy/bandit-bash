# Plan: Combat Map
**Date:** October 27, 2026
**Status:** **Approved** October 27, 2026; MP1–MP3 (with fix-ups) and MP4 (with P02 CC6)
implemented October 28, 2026; MP5, MP6 and MP7 implemented October 29, 2026 (461 headless map tests pass). After review (questions 12–13 answered; "within N
movable tiles" cut; no prep screen in any combat). Orchestrator ID **P04**
([game-orchestrator.md](game-orchestrator.md)). Its approval opens P01 EB6 (sessions).

The battlefield: how a map is authored and loaded, terrain, movement and pathing, deployment,
objectives and the end of a combat, reinforcement points, map objects, enemy placement slots and
the authoring checks. P02 (combat core) owns the rules of a fight and defines the `CombatGrid`
interface this plan implements; P05 fills the enemy slots and runs the AI; P06 owns the darkness;
P07 draws all of it.

## Problem

- **No maps exist.** The combat rules run only on `StubCombatGrid`
  (`bandit-bash/tests/combat/stub_combat_grid.gd`), an open rectangle. There is no terrain, no
  pathing, no deployment, no objective and no way for a combat to end, so the turn loop (P02 CC6)
  and the sessions that host it (P01 EB6) have nothing to run on.
- **The grid can't see units.** `CombatGrid` is pure and shared by every sandbox
  (`scripts/combat/combat_grid.gd:20-23`), but `validate_path(unit_id, path)` (`:112`) must reject
  enemy tiles and occupied destinations; the stub charges 1 per step and never looks at units
  (`stub_combat_grid.gd:103-115`). Object state (a door opened, debris broken) has the same
  problem: it changes during resolution, so it can't live in a shared grid.
- **Contracts are waiting on this plan:** `CombatGrid` (P02 question 1), the `AFTER_STEP`,
  `AFTER_ENEMY_PHASE` and `OBJECT_OPERATIONS` hooks (P02, Turn and phase loop), a stable index per
  chest, house and shelf for `MAP_LOOT` (P13 need R-N5), tile coordinates never negative (P01
  question 37). "Within N movable tiles" (P01 question 38, P02 question 13) was cut in this plan's
  review (question 12): every "within N tiles" is grid distance.
- **`Godot_FE` defects to avoid** (`Godot_FE/docs/systems/08_grid_pathing_ai.md` §6): a
  reinforcement wave stalls forever when its spawn tile is occupied; A* is rebuilt for the whole
  map per unit and per cursor move; tiles are keyed by `str(Vector2i)`; four near-identical range
  searches; object state is cleared through four manual calls that drift; Seize and Defend were
  declared (`Godot_FE/combat/Combat.gd:143`) but never worked.

## Open Questions

Questions 1–11 were asked before drafting and answered October 27, 2026 (4, 6 and 7 changed by the
user). Question 12 was found while drafting.

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | How maps are authored | Scene + rules resource, converted to pure data / scene read live / data files only | **A scene per map** (terrain and marker layers painted in the editor) **plus a `CombatMapDefinition` resource**, converted at battle start into a pure `MapLayout`; the authoring check runs on the layout | **Answered October 27, 2026:** as recommended. |
| 2 | Movement rules | Carry over `Godot_FE` / change | **Carry over:** four directions, cost per movement type, own side (teammates' units included) passable, enemies solid, no ending on an occupied tile; a closed door blocks everyone, debris and kegs everyone but fliers | **Answered October 27, 2026:** as recommended. |
| 3 | What "within N movable tiles" measures | The source's movement / steps ignoring units and cost | **The source's movement:** reachable with N movement points, terrain cost counted, enemies blocking, allies not | **Answered October 27, 2026:** as recommended; **superseded the same day by question 12: the term is cut.** |
| 4 | Deployment | Prep screen every combat / automatic | Prep screen with swaps, from roster order | **Answered October 27, 2026 (user, changed):** **automatic deployment, on by default**, placing units by their role; an **opening swap** on the map until the first unit acts on turn 1; the **prep screen only for key and boss combats**; an Options setting turns automatic deployment off (prep screen everywhere). **Changed in review (user):** **no prep screen in any combat**; re-gearing moves to Camps (a campaign rule, P08), and the map before the boss has a Camp, so no combat needs prep. The Options setting is dropped with it: with no prep screen, the opening swap is the manual path. |
| 5 | Objective rules | — | Rout: no enemy on the map (waves not yet arrived are cancelled). Leader: the marked enemy falls. Seize: any player unit ends its turn on the tile. Survive N: the end of turn N's enemy phase, or early once no enemy is left and every point is closed. Defend: lost when an enemy ends its turn on the tile, else as Survive. Lost everywhere: the commander falls in solo, or every player unit is defeated | **Answered October 27, 2026:** as recommended. |
| 6 | Reinforcements | Turn list / turn list + zone triggers | **Authored arrival turns per point** (zone triggers dropped); waves drawn at battle start (P13); arrive after the enemy phase; a point closes for good when a player unit ends its turn on it; arrivals stop once the darkness arrives; an occupied arrival tile uses the nearest free tile | **Answered October 27, 2026 (user, extended):** as recommended, plus **distinct, always-visible arrival markers** and **warnings**: every open point shows the turns until its next wave; the player phase before a wave shows its classes and count; a banner announces the arrival. |
| 7 | Attacking a map object | Carry over `Godot_FE` / change | **No hit roll, the object never counters, the attacker's normal turns** (object Attack Speed 5 by default); Attack and Mitigation against its DEF or RES, multipliers, floor; no crit, Block or Stance | **Answered October 27, 2026 (user, extended):** as recommended, **through the same exchange flow and facts as an attack on a unit** (Before and After Combat, `ATTACK_MADE`, `HIT_DEALT`, `DAMAGE_DEALT`, with the object as target), so effects, logs and UI see one flow. |
| 8 | Which objects P04 builds | — | Chest, door, lever, the four searchables, wooden and stone debris, passage, powder keg, brazier (its darkness effect is P06's). "Debris, Barrel" in unit-roster.md's terrain table is read as an object row. A Cutthroat's loot goes to the seat whose unit defeats it | **Answered October 27, 2026:** as recommended. |
| 9 | Who places enemies | P04 slots + P05 contents / P05 all | **P04 authors enemy slots** (tile, position variance, group slot); P05 owns classes, groups and prefixes; setup draws from `ENCOUNTER_SETUP` | **Answered October 27, 2026:** as recommended. |
| 10 | Save sections | — | P04 takes the reserved combat section `entities` (object state) and adds `combat_map` (map id, setup choices, reinforcement points, objective progress); `enemy_units` goes to P05 | **Answered October 27, 2026:** as recommended. |
| 11 | Who owns terrain data | P04 / P03 | **P04:** terrain definitions and the movement-type enum; P03's unit data refers to them; terrain healing through `tile_bonus` | **Answered October 27, 2026:** as recommended. |
| 12 | Where questions that need units or object state are answered (found drafting: the shared grid sees neither) | Move them to `CombatState`, which holds P04's map state / give the grid methods a state parameter / let the grid hold a live state reference | **Move them to `CombatState`.** `CombatGrid` stays terrain-only and shared. `CombatState` gains one P04-owned member, `map: MapState` (objects, reinforcement points, objective progress), copied by `copy_for_sandbox()`. `validate_path` and `walking_distance` move from `CombatGrid` to `CombatState`, which calls P04's pathing with itself; `CombatState.can_stand()` and `blocker_at()` fold in object state, and P02's resolvers call those instead of the grid's (`rune_resolver.gd:80-81`, `shove_resolver.gd:145`). A live reference is rejected: sandboxes share the grid (`combat_grid.gd:20-23`). | **Answered October 27, 2026 (user):** **cut "within N movable tiles"**; every "within N tiles" is grid distance (absolute). That removes `walking_distance` everywhere (P01 fix F9's `MOVABLE` mode, `SandboxState.walking_distance`, `CombatGrid.walking_distance`). What remains is unavoidable for movement itself and stays small: `CombatState` holds `map: MapState` and checks paths against units and objects (below, Grid, state and pathing). |
| 13 | Survive and Defend end early "with every reinforcement point closed" (vision): does a point with no waves left count as closed? | Yes / only when a player closes it | **Yes:** a point with no waves left can send nothing, so requiring a unit to stand on it only adds a chore. | **Answered October 27, 2026:** as recommended. |
| 14 | Front vs striker (found building MP3) | Front = Armored, Heavy, Shover only / every non-mounted melee unit | **Front = Armored, Heavy and the Shover** (ranked by HP + DEF); other melee are strikers. **Ranged** = the equipped weapon can't attack at 1 **or deals magic damage** (a Mage's 1–2 tome is ranged; 1–2 physical weapons stay melee) | **Answered October 28, 2026:** as recommended. |
| 15 | Edge tiles for Mounted and Flier strikers (MP3) | — | An edge tile has at most 2 neighboring deployment tiles; such a striker takes the nearest row with a free tile and prefers an edge within it | **Answered October 28, 2026:** as built. |
| 16 | The commander ends up front-most when an army has no front or striker units (MP3) | Accept / push it back | **Accept:** rare (the Drengr is melee itself); the opening swap fixes it | **Answered October 28, 2026:** as recommended. |
| 17 | How the opening-swap window closes (MP3) | A `MapState` flag / derive from history | **`MapState.opening_swap_open`** (default true), cleared when the first player command on turn 1 resolves, whatever its outcome (P02 CC6 clears it); saved in `combat_map` | **Answered October 28, 2026:** a `MapState` flag, saved in `combat_map`. **Amended the same day by P02 question 17 (user):** the window comes before turn 1 and only when the seat's opening-swap setting is on; CC6 opens it at battle start and the seat's Start command closes it. The flag defaults to false. |
| 18 | Authoring format for markers with parameters: reinforcement arrival turns, door and lever groups, passage pairs, multi-tile doors, enemy-slot variance and group (MP1–MP3) | `MapMarker` nodes in the scene / a table on `CombatMapDefinition` keyed by tile | **`MapMarker` nodes**, snapped to the grid, with exported kind, group id, arrival turns, pair id, variance tiles and group slot; plain markers stay tile layers; built with MP5, extended by MP6–MP7 | **Answered October 28, 2026:** as recommended. |
| 19 | `CombatState.validate_path` takes the engine (MP2) | Accept / look up | **Accept:** the unit's movement is an engine value, as in `place_unit` and `load_bases` | **Answered October 28, 2026:** as recommended. |
| 20 | Four MP1/MP2 assumptions (found reviewing the MP3 fix-ups) | Accept / change each | **Accept:** a pool is a name string (this plan gives pools no type); every `MAP_LOOT` giver is a container, weapon racks included (P01 questions 40 and 46); the Door and "Debris, Barrel" terrain rows are objects (question 8); the nearest-free-tile search crosses units of either side, since an arrival is placed, not walked (question 6), so a boxed-in wave still lands on the nearest open tile | **Answered October 28, 2026 (user):** as recommended. MP5 removes the markers in `combat_map_definition.gd`, `map_loader.gd` and `pathing.gd`; MP6 the one in `map_layout.gd`. |
| 21 | MP4's assumptions (found reviewing CC6 + MP4) | Accept / change each | **Accept:** a loss beats a win reached in the same step; the speed bonus counts the whole turns not finished under par (P08 sets what each is worth); any commander's fall loses a map shared by several seats (shared battles are post-MVP; P11); the boss or mini-boss is the enemy on a leader slot until P05 marks bosses; the waves' shape stands until MP7 draws them (MP7 may add fields, never drop "turn") | **Answered October 28, 2026 (user):** as recommended. MP5 removes the three settled markers in `objectives.gd` and turns the two stopgaps (boss slot, waves' shape) into `TODO` markers for P05 and MP7. |
| 22 | MP5's marker fields and assumptions (found reviewing MP5) | Accept / change each | **Accept:** keep `group_id` and `pair_id` on `MapLayout.Marker` (additive; MP6 builds on them); M1's turn par is 5, provisional until playtesting; enemy-slot variance is grid distance (question 12), not `Godot_FE`'s movement-cost range; a group slot is a letter name ("A", "B"; empty means none), as in `Godot_FE`; a reinforcement point must be standable by every movement type, since waves are drawn at battle start; a door without a group opens with a key or lockpick, a door in a group needs a lever in it, and every lever needs a door | **Answered October 29, 2026 (user):** as recommended. |
| 23 | MP6's escalation and assumptions (found reviewing MP6) | Accept / change each | **Accept:** (a) **who picks locks:** a `CAN_PICK_LOCKS` permission, default denied (P01 amendment F15), built by the first P03 content step that grants it to a unit type, which also decides which units have it; until then MP6's `"Lockpicker"` tag stays inside `MapObjects.can_pick_locks()` (`map_objects.gd:TOD-003`). (b) A house gives gold or a consumable at even odds, provisional until P03's pools. (c) A lever opens its whole group unless every door in it is open, then closes them; a door with a unit in it stays open. (d) Loot a Cutthroat drops with no player unit to take it is lost. (e) Objects take no terrain DEF or RES. (f) "Floodable" means a ground unit can stand there, so walls block the darkness (P06 confirms). (g) Every candidate object spot is placed until a count has a basis (`map_objects.gd:TOD-005`). Also recorded: the user's decision while MP6 was built: a **key** opens a chest or a door for any unit and is used up; a **lockpick** is kept and usable only by lock pickers (vision update queued) | **Answered October 29, 2026 (user):** as recommended. |
| 24 | MP7's behavior change, assumption and follow-ups (found reviewing MP7) | Accept / change each | **Accept:** (a) Survive and Defend check their early end right after a wave arrives (after that turn's enemy phase), not at the next player Phase Start; the rule is unchanged (no enemy on the map and no open point; game-vision.md), only when it is checked, and the turns early it reports are unchanged. (b) A wave unit with no free tile anywhere it could stand is lost, with a diagnostic, rather than held for a later turn (`MapCheck` already requires every point on a standable tile). (c) The real game sends no waves until P05 fills `Reinforcements.GroupSource` (`campaign_session.gd:TOD-002`). (d) Closing a point records `OBJECT_STATE_CHANGED` with `POINT_CLOSED`, and only a point that can still send counts for XP (P08). (e) The wire contract grows by `REINFORCEMENT_INCOMING` (44), `REINFORCEMENT_ARRIVED` (45) and `CombatFact.unit_types` (slot 18). **Follow-ups:** MP8 removes the `# ASSUMPTION` above `map_check.gd`'s point rule (question 22 accepted it); P02 CC8 adds MP7's steps to `combat_hooks.gd`'s docs (warnings on `INTENTS`, closing on `PHASE_END_EFFECTS`, arrival on `AFTER_ENEMY_PHASE`) | **Partly answered October 29, 2026 (user):** (a), (c), (d), (e) and the follow-ups as recommended. **(b) reopened:** the search for a free tile is bounded by walls, closed doors and terrain the unit cannot enter (it floods by movement cost from the point, passing units), so a wave can overflow a walled pocket on a map that still has room; losing the overflow is open. |

## Scope

**In scope**
- Map authoring: the map scene, `CombatMapDefinition`, conversion to `MapLayout`, map pools per
  combat type (standard, key, boss) as data, and the authoring check.
- Terrain definitions (unit-roster.md's table) and terrain healing values.
- `MapGrid`, the real `CombatGrid`; pathing: reach, path validation with cost, nearest free tile.
- Removing "within N movable tiles" (question 12): P01 fix F9's `MOVABLE` mode,
  `SandboxState.walking_distance` and `CombatGrid.walking_distance`.
- `CombatState` checking paths and blockers against units and objects, with P02's call sites.
- Deployment: automatic deployment and the opening swap's rules.
- Objectives, win and loss checks (`AFTER_STEP`), `COMBAT_ENDED`.
- Reinforcement points: arrival turns, closing, arrival placement, warnings as facts
  (`AFTER_ENEMY_PHASE`).
- Map objects: chest, door, lever, searchables, debris, passage, powder keg, brazier (the object);
  using, breaking and exploding them; the `OBJECT_OPERATIONS` hook (Spark); Cutthroat loot carry
  and drop.
- Enemy slots (placement data only).
- The `entities` and `combat_map` save sections.
- One greybox standard map (Rout) for M1.

**Out of scope**
- Enemy classes, groups, prefixes and the AI, including how enemies choose objects (P05).
- The darkness: flow, damage, erosion timing, the Brazier's effect and the source-candidate check
  (P06). P04 exposes what P06 needs (below).
- Every visual: tiles, arrival markers, banners, the opening-swap interaction, hover previews
  (P07).
- Re-gearing at Camps (P08; question 4).
- Units sent between co-op maps (P11); P04 supplies the nearest-free-tile query it uses.
- Choosing a map from a pool for a node (the encounter draws it from `ENCOUNTER_SETUP`, P01 EB6
  and P13); P04 supplies the pools.
- Maps beyond M1's greybox map (content work, per milestone).
- After the MVP: Ballista, War Drum, shared co-op deployment zones, the terrain candidates
  (watchtower, healing spring, rope bridge).

## Design Basis

- **game-vision.md, Combat maps:** hand-authored maps in pools per combat type, randomized enemy
  groups, spawns and loot from the run's seed; sizes (standard 8×6 to 10×8, key about 12×10, boss
  larger); at least 8 deployment tiles; objectives per combat type; turn par; Survive and Defend
  end early; the interactables table; map objects are neutral; terrain is the only source of avoid;
  the darkness (P06); parallel co-op maps with per-seat copies and reinforcing allies arriving "on
  dry tiles next to the receiving player's commander".
- **game-vision.md, Combat:** move then one action; using an object is the action; closing a
  reinforcement point is free (ending the turn on it); Shove's terrain rules; "No trading in combat.
  Gear moves only in army management and battle prep" (affected by question 4, below).
- **game-vision.md, Enemies:** enemy groups, spawns and loot randomized per run on authored maps;
  reinforcement points players can close; when the darkness arrives, reinforcements stop.
- **game-vision.md, Units / Experience:** +5 personal XP for looting and closing reinforcement
  routes.
- **map-objects.md** (all): the objects, their rules, values and AI notes.
- **unit-roster.md, Movement and tags:** movement types, tags and the terrain table.
- **the-darkness.md:** sources (authored candidates, at least 2), the drain per objective,
  floodable tiles, what blocks the darkness, Brazier, authoring guidelines; consumed by P06.
- **multiplayer-combat-options.md:** parallel maps, per-player additions.
- **save-system.md:** reserved combat keys `enemy_units`, `entities`, `rng`; battle state lives in
  `COMBAT` sections.
- **master-ideation.md:** Map Structure → Combat Map (standard 2–5 minutes, 3–5 enemies; key
  5–10 minutes with mini-bosses; boss maps that the boss changes). Its Terrain, Interactables and
  Objectives sections are empty, so they add nothing here.

**Gaps and conflicts in the vision**
- **Turn par** (user, October 27, 2026): set by hand on each map, with no target range; small
  combats should sit well below the vision's figures, which also disagree with each other (Combat
  maps: boss "about 14–18", ladder level 6 −1; the October 23 decision log: boss "10–14", "Hard −1").
  The vision update is pending for the ideation thread.
- **Question 4 changes described behavior:** no combat has a battle-prep step, and re-gearing moves
  to Camps, so the vision's "gear moves only in army management and battle prep" and Camp's
  "choose one" need updating (pending for the ideation thread; P08 owns the Camp rule).
- The vision's terrain list includes "house, door and chest tiles"; map-objects.md makes houses,
  doors and chests objects. Here they are objects standing on terrain (a house object on House
  terrain), which keeps both readings true.

## Legacy Behavior (ports from Godot_FE only)

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `scripts/combat/grid/combat_map_grid.gd`, `docs/systems/08_grid_pathing_ai.md` FR-GRID-1 | Terrain per tile from TileMap custom data; an active entity overrides terrain for movement | Keep | Same idea: terrain layers in the map scene; objects answer movement through `CombatState` |
| `08` FR-GRID-2 | 4-directional moves, cost per movement type, own faction passable, enemies solid, no ending on an occupied tile | Keep | Question 2 |
| `combat_map_grid.gd` `update_astar_points` | Rebuilds A* for the whole map, per unit, before every path | Change | One cost-bounded flood per query on these small maps; nothing cached that a sandbox would share |
| `combat_map_grid.gd` (four DFS variants) | Separate range searches | Change | One flood function (`08` §7) |
| `combat_map_grid.gd` | Tiles keyed by `str(Vector2i)` | Change | `Vector2i` keys |
| `combat/Combat.gd:176`, `:340-348`, `combat/CController.gd:2015-2029` | Player units fill `ally_spawn_tiles` in party order; battle prep swaps units between spawn tiles | Change | Question 4: automatic deployment by role and an opening swap; no prep screen |
| `combat/Combat.gd:143-146` | `victory_condition` with Seize and Defend declared, never working; `turns_to_survive` | Change | Built (question 5) |
| `scripts/combat/reinforcements/combat_map_reinforcement_manager.gd`, `08` FR-REIN-1 | Waves on listed turns (`TURN_COUNT_<n>`) or when a player unit first enters a zone; spawned one by one with a camera pan | Keep turns; drop zones and the camera pan in the logic | Question 6; the vision says "on a timer"; presentation is P07's |
| `08` §6 | A wave whose spawn tile is occupied never completes, stalling the turn | Drop (bug) | The nearest free tile is used (question 6) |
| `combat/CController.gd:1010-1015`, `:195` | Reinforcements are checked after the enemy phase ends | Keep | P02's `AFTER_ENEMY_PHASE` hook, after P06's darkness step |
| `08` FR-ENT-1, `scripts/combat/entities/*` | Chest, door, lever (opens a door group by `group_index`), search, breakable terrain, debris; keys from a whitelist | Change | map-objects.md: lockpicks open chests and doors; levers toggle; four searchables; breakable walls fold into debris; kegs, passages and braziers added |
| `08` FR-ENT-2 | Entity contents rolled at load | Change | Rolled from `MAP_LOOT` by stable container index (P13), the same on every co-op copy's index |
| `combat/Combat.gd` `perform_attack_entity`, the exchange's `enact_combat_exchange_entity` | Attacking an entity: every attack of the attacker's turns lands, no hit roll, no counter | Keep; change the flow | Question 7: through P02's exchange resolver with the same facts as any attack |
| `08` §9 | Entity ids = authored index; group index from authoring order | Keep | Stable object ids per map |
| `RandomCombatUnitData` (`08` §4) | Authored enemies with `position_variance` and a group letter | Keep, as enemy slots | Question 9 |
| `combat/Combat.gd:201` `heal_on_win` | Heal after a win | Out of scope | Campaign flow (P08) |

**Tuning values carried over**
- Terrain costs, avoid, DEF/RES and healing: unit-roster.md's table, from
  `Godot_FE/resources/definitions/terrians/` (with its two documented fixes: Wooded Knoll costs 3
  for Default; Mounted-tagged ground units use Mounted movement).
- Wooden debris 25 HP, 0 DEF/RES; stone debris 35 HP, 5 DEF/RES: map-objects.md, from
  `Godot_FE`'s entity data.
- Object Attack Speed 5: `Godot_FE/resources/definitions/entities/*.tres` (`attack_speed = 5` in
  every example definition).
- Powder keg 10 HP, 0 DEF/RES, 5 splash within 1 tile; at most 3 per map (map-objects.md, new).

## Approach

### Shape

```
CombatMapDefinition (.tres)      rules data: objective, par, survive length, pool, size
map scene (.tscn)                terrain layers + marker layers, painted in the editor
        │  MapLoader.load(definition) at battle start
        ▼
MapLayout (RefCounted, pure)     terrain per tile, markers, object spots, enemy slots, sources
        ├── MapGrid extends CombatGrid    terrain-only, shared by every sandbox
        └── MapState (in CombatState)     objects, reinforcement points, objective progress
Pathing (static)                 flood, path check, reach, nearest free tile
AutoDeploy (static)              units → deployment tiles
Objectives (static)              win / loss checks (AFTER_STEP)
Reinforcements (static)          warnings and arrivals (AFTER_ENEMY_PHASE)
MapObjects (static)              use, break, explode, toggle, carry
MapCheck (static)                the authoring check
```

All rules code is pure: it reads and writes `CombatState` (and its `MapState`) and records facts
through the engine, so a sandbox runs it unchanged (P01, Forecast and AI simulation). No node, scene
or Resource reference survives `MapLoader`.

### Authoring and loading (question 1)

- **A map is a scene plus a definition.** The scene holds a `TileMapLayer` whose tiles carry a
  terrain id (custom data), and marker layers: deployment tiles, objective tiles (seize, defend,
  leader slot), reinforcement points, object spots, enemy slots and darkness source candidates.
  The `CombatMapDefinition` resource names the scene and holds the rules data: combat type, pool,
  objective, turn par, survive length.
- **Stable ids.** Every object spot, container (chest, house, shelf) and reinforcement point gets an
  index from the layout's fixed order (row-major by tile, then marker kind), so ids are the same on
  every co-op copy and every load: the `MAP_LOOT` index (P13 R-N5) and the object ids used in facts
  and saves.
- **Candidates.** Object spots and darkness sources are candidates; the encounter's
  `ENCOUNTER_SETUP` draw picks the active ones (map-objects.md "placed from candidates"; P13).
- **Setup steps** (P01 question 40, October 28, 2026): P04 registers step 2 (objects at candidate
  spots), step 5 (reinforcement waves) and step 7 (each container's contents, per seat, from its
  own `MAP_LOOT` stream by container index). Contents are rolled at battle start and kept in
  `MapState`, so they are saved in `entities` and a Cutthroat or a player finds the same item. MP6
  adds that `MapState` field; until then EB6 keeps the contents in the setup result (P01 question 46).
- **The authoring check** (`MapCheck`) runs on the layout and fails the content test on: fewer than 8
  deployment tiles; more than 3 powder kegs (the Powder Baron's arena may waive it); a duplicate
  container index; a negative tile coordinate; an objective without its tile (Seize, Defend) or
  leader slot; a reinforcement point off a standable tile; a door, lever group or passage pair that
  doesn't match up. P06 adds "at least 2 darkness source candidates".

### Grid, state and pathing (questions 2, 12)

- **One distance for effects:** every "within N tiles" is grid distance, tiles up plus tiles
  across, ignoring walls and terrain (question 12). `walking_distance` is removed from
  `CombatGrid` and `SandboxState`, and P01 fix F9's `MOVABLE` mode from `Area` and
  `WhilePositionCondition` (nothing authored uses it yet).
- **`MapGrid`** implements `CombatGrid` from the layout: `distance`, `neighbors`, `step`,
  `can_stand` and `blocker_at` for terrain alone, `is_slick`, `tile_bonus` (avoid, DEF, RES,
  healing), and the terrain cost of a path for a movement type.
- **`CombatState` checks what depends on units or objects**, because only it knows them: its
  `can_stand` and `blocker_at` add object state to the grid's answer (P02's resolvers call these),
  and `validate_path(unit_id, path)` lives on `CombatState`, calling `Pathing`. That is the whole
  change to P02's code.
- **Pathing** is one cost-bounded flood over the four directions (`08` §7), parameterised by the
  mover (movement type, side): terrain cost per movement type, own-side units passable, enemies and
  impassable objects solid. Uses:
  - **`validate_path`:** each step adjacent and enterable, total cost within the unit's
    `MOVEMENT` (minus cost already spent this turn), destination unoccupied; returns tiles moved and
    cost (`CombatGrid.PathCheck`).
  - **Reach:** every tile a unit can end on this turn (P05's danger zone, P07's move preview).
  - **Nearest free tile:** the closest free tile a given movement type can stand on, by that
    movement's cost, ties in `CombatGrid.DIRECTIONS` order; reinforcement arrivals and P11's
    reinforcing allies.
- No path or reach cache is kept: maps are at most about 12×10 outside boss maps, so a flood is
  small. **Unmeasured**; EB9's bench gains a pathing row if P05's AI calls it heavily.

### Deployment (question 4)

- **Automatic deployment** (default on) places the whole army deterministically, with no random
  draw:
  1. Rank deployment tiles by grid distance to the nearest enemy starting tile (enemy slots are
     filled at setup).
  2. Sort units into roles from their data: **front** (melee, ranked by HP + DEF; Armored, Heavy and
     the Shover first), **striker** (other melee; Mounted and Flier prefer the zone's edge tiles),
     **ranged** (minimum weapon range 2 or more), **support** (holds a staff).
  3. Fill: front units on the nearest tiles, then strikers, then ranged units on tiles 1–2 behind a
     front unit, then support behind the line next to the most allies.
  4. **The commander takes the second row**: a solo commander's fall ends the run. Traits that want
     the front (the Drengr's Vanguard) are the player's call through the opening swap.
  5. Ties by roster order.
- **The opening swap** (a player setting, P02 question 17): with it on, the battle opens in a swap
  window before turn 1, in which the player may swap any two of their units standing on deployment
  tiles, then presses Start, which runs turn 1's Phase Start. With it off, there is no window and no
  Start press. A swap is a command (the unit-turn command path, P02 CC6), legal only in that window
  and only between that seat's units; it records `UNIT_MOVED` for both.
- **No prep screen** in any combat (question 4). Gear changes happen outside combat; re-gearing at
  Camps is P08's rule, and the map before the boss has a Camp.
- **Co-op:** each seat deploys on its own map copy the same way.

### Objectives and the end of a combat (questions 5, 13)

| Objective | Won when | Lost when (besides the common losses) |
|-----------|----------|---------------------------------------|
| Rout | No enemy is on the map; waves not yet arrived are cancelled | — |
| Defeat the Leader | The marked enemy is defeated | — |
| Defeat the mini-boss / the boss | That enemy is defeated | — |
| Seize | A player unit ends its turn on the seize tile | — |
| Survive N | Turn N's enemy phase ends; or early: no enemy on the map and every reinforcement point closed (question 13) | — |
| Defend | As Survive | An enemy ends its turn on the defend tile |

- **Common losses:** in solo, the commander is defeated (at once, P02); every player unit is
  defeated. In co-op, a commander's fall loses that player's map; the combat ends when every map has
  finished (P01 sessions, P11).
- `Objectives.check(state)` runs on P02's `AFTER_STEP` hook and records `COMBAT_ENDED` (won or lost)
  once, with `side` naming the side that won (`CombatSide.PLAYER` or `ENEMY`); the session stops
  taking commands for that map, and only a won map may send units (P01 question 48).
- **Early-end speed bonus** for Survive and Defend is a grade input for P08 (the vision), carried in
  the `COMBAT_ENDED` fact.

### Reinforcement points (question 6)

- **Authored:** each point has its tile and a list of arrival turns. Its waves' groups are drawn at
  battle start with the rest of the setup (P13, "every reinforcement wave's group"), so the game knows
  every wave in advance.
- **Arrival:** on P02's `AFTER_ENEMY_PHASE` hook, after P06's darkness step. Each arriving unit is
  placed on the point if free, else on the nearest free tile (Pathing), with Block 0 and full Stance
  (P02); `UNIT_SPAWNED` per unit and `REINFORCEMENT_ARRIVED` per wave.
- **Closing:** a player unit that ends its turn on an open point closes it for good: no fact of its
  own beyond `OBJECT_STATE_CHANGED` (point closed), the personal-XP bonus read by P08.
- **The darkness stops arrivals:** once P06 reports the darkness has arrived, no point sends again.
- **Warnings** (facts, so mirrors and the UI read them like anything else):
  - `REINFORCEMENT_INCOMING` at each player Phase Start for every open point with a wave left: the
    point, the turns until its next wave, and during the player phase right before arrival, the
    group's classes and count.
  - P07 draws arrival markers in their own visual language (always visible while open, distinct
    when closed), the countdown, the preview and the arrival banner; the arrival's camera pan is
    presentation only.
- Units a teammate sends from another map (P11) use the same markers and warnings.

### Map objects (questions 7, 8)

| Object | Rules here |
|--------|-----------|
| Chest | Using it with a lockpick in the Pouch (used up) gives one item rolled from `MAP_LOOT` by its container index (Common 50 / Uncommon 35 / Rare 15, vision); a Cutthroat opens it without one |
| Door | Blocks every unit and the darkness while closed; can span several tiles; opened with a lockpick (used up) or by its lever group |
| Lever | Toggles every door in its group, open or closed, for whoever pulls it |
| House, food shelf, book shelf, weapon rack | One search each: 15–25 gold or a consumable plus the personal-XP bonus / an ingredient / a rune / a weapon, from `MAP_LOOT` |
| Debris (wooden, stone) | Breakable: 25 HP 0 DEF/RES or 35 HP 5 DEF/RES; blocks every unit but fliers; destroyed, it restores the terrain beneath |
| Passage | A linked pair: a unit on one end uses it to arrive at the other end, if free |
| Powder keg | Breakable, 10 HP; any hit, any splash or the darkness's erosion explodes it: 5 splash to every unit within 1 tile (grid distance), friend or foe, destroying adjacent breakables; kegs chain with no limit |
| Brazier | Lit or doused by an adjacent unit; P06 reads its lit state |

- **Using** an object is the unit's action after moving (the unit-turn command, P02) and records
  `OBJECT_USED`; state changes record `OBJECT_STATE_CHANGED` (opened, closed, searched, lit, doused,
  destroyed).
- **Breaking** an object is an attack through P02's exchange resolver with the object as defender
  (question 7): Before Combat and After Combat for the attacker; `ATTACK_MADE`, `HIT_DEALT`,
  `DAMAGE_DEALT` with the object as target, `DAMAGE_TAKEN` with the object as actor. No hit roll,
  no counter, no crit, Block or Stance; the attacker's turns against the object's Attack Speed;
  Attack and Mitigation against its DEF or RES, multipliers, floor. Consequences, all accepted:
  attacks on objects advance attack counters (Iron Heart, War Ledger); Cleave splashes off them;
  Momentum never triggers (no miss); the matchup is always a Standoff (no weapon profile); no XP.
- **Explosions** use P02's splash resolver (`SandboxState.deal_splash`); a keg's reactions are
  owned by `EffectOwner.Kind.MAP_OBJECT`, so a chain is exempt from the reaction caps (P01
  question 27).
- **`OBJECT_OPERATIONS`:** P04 registers the hook P02's runes call (Spark detonates a keg).
- **Cutthroat loot:** a Cutthroat that opens or searches carries the loot; when defeated, the loot
  goes to the seat whose unit defeated it (question 8). P05 decides when it loots.
- **For P06:** floodable tiles, what blocks the darkness (walls, closed doors, unbroken
  breakables), an erosion call that damages a breakable, and each Brazier's lit state.
- **Objects are on the map for the engine:** `SandboxState.unit_ids()` already lists map objects;
  their side is `NONE`.

### Enemy slots (question 9)

An enemy slot is a tile, a position variance (the tiles it may shift to, as `Godot_FE`'s
`position_variance`) and a group slot. At setup the encounter fills slots from P05's groups through
`ENCOUNTER_SETUP`; per-seat additions (Hunted's extra enemy) take free slots marked for additions.
P04 places the units; P05 owns what they are.

### New facts

`CombatFact.Kind` appends `REINFORCEMENT_INCOMING` (44) and `REINFORCEMENT_ARRIVED` (45). Everything
else reuses existing kinds: `OBJECT_USED`, `OBJECT_STATE_CHANGED`, `UNIT_SPAWNED`, `UNIT_MOVED`,
`COMBAT_ENDED` and the attack facts. (A dedicated "object destroyed" kind, mentioned while asking
question 7, isn't needed: `OBJECT_STATE_CHANGED` carries it.)

### Rejected alternatives

- **A grid that holds the live state:** sandboxes share the grid, so a forecast would read the real
  map. Question 12.
- **Godot's `AStarGrid2D`:** passability differs per mover and side, which is what made `Godot_FE`
  rebuild it for the whole map per unit; a flood on maps this small is simpler and copies nothing.
- **Zone-triggered reinforcements:** the vision says "on a timer"; zone triggers add an authoring
  concept and a rule the player can't see coming.
- **A prep screen for some or every combat:** the user's call (question 4): re-gearing moves to
  Camps, and heavy menuing was `Godot_FE`'s biggest drag, against the vision's pillar of reducing
  cognitive burden.
- **Map data only in files (no scene):** painting terrain in the editor is the authoring tool; the
  scene is converted to pure data at load, so the rules never see it.

## Save Impact

- **`COMBAT` section `entities`** (the reserved key), version 1, one per session (a `SaveSection` in
  solo; the per-map format is P11's change, as for P02's `combat_state`): every object by stable id
  with its state (HP, open or closed, searched, lit, destroyed) and any loot a Cutthroat carries.
- **New `COMBAT` section `combat_map`**, version 1, one per session: the map definition id, the setup
  results that aren't saved elsewhere (active object spots; active darkness sources unless P06 takes
  them into its own section), each reinforcement point's state (open or closed, the waves left with
  their drawn groups), objective progress (turns survived, Defend tile held), whether the opening
  swap is still allowed, and whether `COMBAT_ENDED` was recorded. Plain JSON, ids as strings, enums as
  string ids (save-system.md data rules). Registered from `CampaignService` (P08 question 1).
- **`enemy_units`** (reserved) is left to P05.
- Nothing in the profile, campaign or settings; map pools are content. (The automatic-deployment
  setting was dropped with the prep screen, question 4.)

## Work Breakdown

| Step | Files | Description | Risk | Gate | Verification |
|------|-------|-------------|------|------|--------------|
| MP1 Terrain and layout | `scripts/map/terrain_definition.gd`, `data/terrain/*.tres`, `scripts/map/combat_map_definition.gd`, `scripts/map/map_layout.gd`, `scripts/map/map_loader.gd`, `tests/map/run_all.gd` | Terrain resources from unit-roster.md's table; the definition resource; scene → `MapLayout`; stable ids | 🟢 | Approval | Every terrain row loads with its costs; a fixture scene converts to the expected layout; ids are stable across two loads |
| MP2 Grid, state and pathing | `scripts/map/map_grid.gd`, `scripts/map/pathing.gd`, `scripts/map/map_state.gd`; changes in `scripts/combat/combat_grid.gd`, `combat_state.gd`, `rune_resolver.gd`, `shove_resolver.gd`, `tests/combat/stub_combat_grid.gd`, `scripts/effects/sandbox_state.gd`, `blocks/selectors/area.gd`, `blocks/conditions/while_position_condition.gd`, the effects test fake | `MapGrid`; the flood, path check, reach and nearest free tile; `validate_path` and object-aware `can_stand` / `blocker_at` on `CombatState`; removing `walking_distance` and the `MOVABLE` mode | 🔴 interface change in P01 and P02 code | MP1 | Golden reach and path tests per movement type × terrain cost; enemy blocks, ally passes, occupied destination rejected, closed and opened door; every existing combat, effects, RNG and save test still passes (those that tested `MOVABLE` are removed, and say so) |
| MP3 Deployment | `scripts/map/auto_deploy.gd` | Automatic deployment; the opening-swap legality rule | 🟢 | MP2 | Each role lands where specified; commander in the second row; ties by roster order; the same army and map give the same layout; swap legal before the first action only |
| MP4 Objectives | `scripts/map/objectives.gd` | Win and loss checks, `COMBAT_ENDED` with the winning `side` | 🟡 | MP2 (hook wiring with P02 CC6) | Each objective's win and loss, Rout cancelling pending waves, Survive's early end, a solo commander's defeat, `COMBAT_ENDED` once |
| MP5 M1 map and the check | `scripts/map/map_check.gd`, `maps/standard/m1_greybox.tscn` + `.tres` | One greybox standard map (Rout, about 8×6 to 10×8, at least 8 deployment tiles, cover for both sides); the authoring check | 🟢 | MP1–MP4 | The M1 map passes the check; deliberately bad fixtures fail it, one rule each |
| MP6 Map objects | `scripts/map/map_objects.gd`, changes in `scripts/combat/exchange_resolver.gd` (object defender) | Every object in the table; breaking through the exchange; explosions and chains; `OBJECT_OPERATIONS`; Cutthroat carry and drop; P06's queries | 🟡 touches the exchange | MP2 | Golden fact logs per object; an attack on debris has the same fact shape as one on a unit; a 3-keg chain; debris restores its terrain; lever toggles both ways; each seat's chest loot from its own `MAP_LOOT` stream by the same container index (per seat, P13 question 3b; corrected October 29, 2026); a sandbox breaking a keg leaves the real map unchanged |
| MP7 Reinforcements | `scripts/map/reinforcements.gd`, `scripts/bus/combat_fact.gd` (two kinds) | Arrival turns, warnings, arrival placement, closing, the darkness stop | 🟡 fact contract | MP2, MP6 | Warnings at the right Phase Starts with the preview the phase before; arrival on an occupied point uses the nearest free tile and the wave completes; a closed point never sends; no arrivals after the darkness; Rout ignores pending waves |
| MP8 Save sections | `scripts/map/map_save_sections.gd` | `entities` and `combat_map` | 🔴 save format | P01 EB7, P02 CC8 | Save, quit and resume mid-phase reproduces the same map state and fact log |
| MP9 Docs | `docs/design/map-authoring.md` (new), orchestrator | How to author a map: layers, markers, ids, the check | 🟢 | MP5 | Review |

MP1–MP3 and MP5 are what M1 and P01 EB6 need first; MP4's logic is built now and wired into the
turn loop with P02 CC6.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| `validate_path` moves from `CombatGrid` to `CombatState`; the grid keeps a terrain-only path cost | Interface | On the shared grid, blind to units | On `CombatState`, through `Pathing` | Approved | `combat_grid.gd`, `combat_state.gd`, `stub_combat_grid.gd`, every caller in `scripts/combat/` and `tests/` | 🔴 |
| `walking_distance` removed from `CombatGrid` and `SandboxState` (21 → 20 methods); `MOVABLE` removed from `Area` and `WhilePositionCondition` | Interface | Grid or movable distance per effect | Grid distance only | Approved (question 12) | `combat_grid.gd`, `sandbox_state.gd`, `combat_state.gd`, `area.gd`, `while_position_condition.gd`, the effects test fake, their tests | 🔴 |
| `CombatState.can_stand` and `blocker_at` include object state; resolvers call them instead of the grid's | Behavior | Grid terrain only | Terrain and objects | Approved | `rune_resolver.gd:80-81`, `shove_resolver.gd:145` | 🟡 |
| `CombatState` gains `map: MapState`, copied by `copy_for_sandbox()` | Interface | — | New member | Approved | `combat_state.gd`, sandbox tests | 🟡 |
| The exchange accepts an object as defender | Behavior | Units only | Units or objects | Approved | `exchange_resolver.gd`, `damage_pipeline.gd` | 🟡 |
| `CombatFact.Kind` appends `REINFORCEMENT_INCOMING` (44), `REINFORCEMENT_ARRIVED` (45) | Enum | 44 kinds | 46 | Approved | `combat_fact.gd`, `combat_bus.gd` routing | 🟢 |
| New combat section `combat_map`; reserved `entities` taken over | Save format | Reserved placeholder | Real sections, version 1 | Approved | `save_service.gd` reserved keys, save tests | 🔴 |

## Verification

- **Pathing golden tests:** reach and path for every movement type over a fixture of every terrain;
  enemies block, allies pass, occupied destinations are rejected; doors closed and opened; debris
  before and after breaking.
- **Deployment fixtures:** the Mercenary starting army (Archer, Battle Medic, Hakkapel, Drengr) and a
  six-unit army on the M1 map land as specified; the same inputs give the same layout.
- **Objectives:** one test per row of the objectives table and per loss.
- **Objects:** a golden fact log per object; an attack on debris produces the same fact kinds in the
  same order as an attack on a unit, with the object as target; a 3-keg chain; Spark detonating a
  keg through `OBJECT_OPERATIONS`.
- **Reinforcements:** warnings and arrivals over several turns; the occupied-tile case completes.
- **Sandbox purity:** a forecast that opens a door or breaks a keg leaves the real `MapState`
  unchanged.
- **Determinism:** the same seed and commands give the same setup, layout and fact log twice, and
  on two co-op copies of the same map.
- **Authoring check:** the M1 map passes; one bad fixture per rule fails.
- **Performance:** pathing is unmeasured until a bench row exists.
- Every existing suite (combat, effects, RNG, save) still passes after MP2.

## Rollback

Every step is its own commit on `feature/P04-<step>` and merges into `dev` separately. MP2 is the
only step that changes existing code (P02's grid interface, two resolvers, and P01's
`walking_distance` and `MOVABLE`); reverting it restores `StubCombatGrid`, the old signatures and
the movable mode, and the later steps depend on it. Every other step is additive.
