# Plan: The Powder Baron (P05 EN11, with P04 MP10's boss map)
**Date:** November 18, 2026
**Status:** Approved November 18, 2026 (user: "build it"); built on `feature/EN11`

## As built: changes from the approved plan

- **The fuse is a field, not an effect counter** (user, November 18, 2026, at B2's check). Phase
  facts reach only effects owned by that side (`effect_engine.gd:1028`, `_sees_fact`), and a keg
  belongs to neither side, so a keg's own reaction never hears an enemy Phase End.
  `MapState.ObjectState.fuse` counts the enemy Phase Ends left. `MapObjects.burn_fuses`, on
  `PHASE_END_EFFECTS`, burns it down and records `Change.FUSE_BURNED` (appended, 10) so mirrors
  follow. The fuse is saved in the same `entities` version 2 change as `is_thrown`.
- **The Baron stays put through a trait, "Holds the throne" (MOV always 0)**, not by narrowing the
  AI's reach. That way the danger zone and the UI's move previews, which read movement and have no
  catalog, show it held without UI edits. `holds_post` keeps only two jobs: it keeps the Baron's
  behavior after the darkness arrives (TOD-002 closed), and it lets the content rules accept a
  Guard built on the Brute and leading its undrawn pack.
- **A thrown keg's effect ids are derived, not minted:** `InstanceIdAllocator.object_effect_id`.
  An intent sandbox crosses the enemy Phase Start through a stand-in that shares the real
  allocator, so minting there would move the run's id counter for a keg the real phase may never
  throw.

## Problem

The run's last floor has no boss. The boss pool still holds the M1 greybox map as a stand-in
(`data/campaign/combat_map_pools.tres`, `Resource_boss`). The pieces the Powder Baron needs are
missing or only half there:

- **No boss class.** `data/enemies/` has the four mini-bosses but no Powder Baron. No trait sets
  `CombatValue.Permission.CAN_BE_SHOVED` to deny (`scripts/effects/combat_value.gd:96`).
- **Guard leaves its post.** Guard attacks any foe it can reach by moving (`enemy_ai.gd:525`,
  `_guards`), so a Guard boss walks off the throne. `_holds_fixed_tile` always returns false
  (`enemy_ai.gd:931`, TOD-002), so a boss would also turn Aggressive when the darkness arrives.
- **Setup always draws.** Setup step 4 draws a pack from a pool and sets levels by the floor's step
  (`enemy_setup.gd:105`, `:341`). A fully scripted map can't fix its enemies, their levels or the
  boss's prefix.
- **Kegs exist only where a map authors them.** They are placed once, from layout markers, with ids
  derived from the spot index (`map_objects.gd:184`). Nothing creates one mid-battle, and no keg
  has a fuse.
- **A keg created mid-battle can't be resumed.** On resume, the saved battle's object spots must
  equal the rebuilt map's (`combat_map_section.gd:176`). A keg the map didn't author fails that
  check and the battle restarts from Begin.
- **The darkness can't set off a fused keg.** Erosion breaks a breakable after `CONTACT_LIMIT` = 3
  turns of contact (`darkness.gd:48`). The fuse is 2 enemy phases, so erosion always comes too late.
- **No boss map.** `tools/gen_maps.gd` builds only the standard and key maps.

These already work and only need tests:

- Defeat the boss: the leader slot is the mark (`objectives.gd:149`).
- The drain is the boss's starting tile.
- A flooded tile stops terrain healing (`darkness.gd:283`, `TERRAIN_HEALING_ALLOWED`).
- The throne heals 4 HP flat (`data/terrain/throne.tres`).

## Open Questions

None. The twelve estimate questions were answered "all as recommended" on November 18, 2026
(user), recorded as [P05 question 46](decisions/P05-enemies-and-ai.md). One build check could
reopen a question; it is the first item of step B2.

## Scope

**In scope:**
- The Powder Baron.
- Keg Barrage and its intent.
- Thrown kegs, with fuses.
- Resuming a saved boss battle that holds lit kegs.
- The boss map, built through the generator, in the boss pool.
- A headless boss-battle suite.
- Playtest and rebalance notes.

**Out of scope:**
- Scripted beats beyond the barrage and the darkness: reinforcement waves and a second phase at
  half HP go to the rebalance doc as an open design item.
- Showing the fuse count on the board (P07 / RF).
- Bonus XP for the boss (RF-013).
- Variations of the boss map.
- MP11's authoring toolkit.

## Design Basis

- **game-vision.md:**
  - Run structure: the boss is on floor 18, at level 8.
  - Combat maps: boss maps are fully scripted, larger and longer than key maps (about 12×10),
    with a boss par of about 14–18 (the October 24 decision).
  - Enemies → Bosses.
  - The decision rows of October 23 ("Boss and mini-bosses") and October 24.
  - Shove: bosses can be Unshovable.
- **master-ideation.md, Boss Combat:** "a large-scale combat map with a boss unit that directly
  affects the combat map." Nothing more specific.
- **enemy-roster.md, "The boss: the Powder Baron":**
  - The unit and its stats.
  - Keg Barrage: the cadence, the reach, choosing the tile, the fuse.
  - The darkness on the throne.
  - The values are a first pass.
- **map-objects.md:**
  - Powder Keg.
  - Rules: explosions are splash; the darkness and breakables.
  - Reachable maps.
  - Keg chains: the Baron's arena is exempt from the 3-keg cap.
- **the-darkness.md:**
  - The drain: Defeat the boss.
  - Arrival: a boss that holds a fixed tile keeps its behavior.
  - Terrain: healing terrain stops while flooded.
  - Guaranteed end: outlasting the boss is a valid plan.
- **Gap:** the vision gives no level for the boss's guards and no scripted beats. Both are settled
  for the MVP by question 46: guards at level 6, no beats beyond the barrage.

## Legacy Behavior (ports from Godot_FE only)

`Godot_FE/` is untracked, so it isn't in the worktree; it was read from the main checkout. Its
engine is 4.7, but its code is outdated in style and not copied.

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `combat/campaigns/bandit_bash/bandit_bash_8/bandit_bash_8.tscn` | The last level: `victory_condition = 1` (DEFEAT_BOSS), `is_boss_level` | Keep | The boss objective already exists (`CombatMapDefinition.Objective.DEFEAT_BOSS`) |
| `bandit_bash_8_enemy_units.tres` | The boss (`is_boss`, `ai_type = 2`, DEFEND_POINT: "No Move, only attack in weapon attack range") | Keep, as the Baron's held post | Question 46 (6): the Baron never leaves the throne |
| same | 36 fixed enemies on a map about 22 wide, at levels 12–14 | Change | The vision's scale: 16×12, 8 guards at level 6, the Baron at 8 |
| `bandit_bash_8_reinforcements.tres` | Waves on turns 4, 7 and 11 | Drop for EN11 | Question 46 (4): no beats beyond the barrage; logged for the rebalance doc |
| `resources/definitions/terrians/throne_terrain.tres` | Throne: DEF 3, avoid 30, heals 4 | Keep (already ported) | `data/terrain/throne.tres` |
| `combat/CController.gd:154` | Boss music themes | Drop | Audio is outside P05 |

**Tuning values carried over:** the throne heals 4 HP (`throne_terrain.tres`, `effect_weight = 4`;
already in `throne.tres`). No other Godot_FE value applies.

## Approach

### The Powder Baron (`data/enemies/powder_baron.tres`)

- **Its class.** An enemy class on `base_class_id = "brute"`, like the mini-bosses. Its effects:
  - Cleave, the Brute's trait;
  - **Unshovable**, a new trait effect that denies `CAN_BE_SHOVED`;
  - its signature move, Keg Barrage.

  Its behavior is Guard, with target rule text "Guards the throne".
- **It holds its post.** A new `@export var holds_post: bool` on `EnemyClassDefinition`. A class
  that holds its post only acts from its own tile (attack or Wait) and never advances.
  `_holds_fixed_tile` reads this flag, which closes TOD-002, so the Baron keeps Guard after the
  darkness arrives. It then stays on the flooded throne and the darkness wears it down.
  - *Rejected:* a new `Behavior` value. The vision calls the Baron a Guard, and the flag is
    narrower.
- **Its level and prefix come from the map** (next section): level 8, Stalwart (DEF +3, RES +2).
  Nothing is rolled.

### A scripted map's enemies

- **Four new `@export`s on `CombatMapDefinition`:**
  - `fixed_pack_id`: empty for a map that draws;
  - `fixed_enemy_level`;
  - `fixed_leader_level`;
  - `fixed_leader_prefix_id`.
- **When `fixed_pack_id` is set,** `EnemySetup.draw` takes that pack instead of drawing one,
  places its units in the enemy slots in `MapLayout` order, and puts its leader class (the Baron)
  on the leader slot with the fixed level and prefix. The pack uses `PackDefinition.Pool.NONE`
  ("never drawn: kept for tests and fixed maps") and lists the same units at every step.
- **The setup stream is untouched,** so a restart from Begin gives the same board.
- **The guards** (`data/enemies/packs/powder_keep_guard.tres`), 8 units at level 6:
  - 2 Shieldbearers;
  - 2 Crossbowmen;
  - a Hedge Healer;
  - a Brute;
  - 2 Cutthroats.
- *Rejected:* a separate boss definition resource. Fixed data on the map keeps "fully scripted"
  in one place, and the next boss map reuses it.

### Thrown kegs (`map_objects.gd`)

**`MapObjects.throw_keg(session, tile, by_id)`** creates a keg mid-battle:

- **Its object state** (`ObjectState`) is a `POWDER_KEG` with a new `is_thrown` field.
- **Its index** comes from a reserved range, `THROWN_INDEX_BASE` + the number thrown so far, so it
  never collides with an authored spot.
- **Its id** is `InstanceIdAllocator.object_id(index)`.
- **Its breakable unit** gets the authored keg's stats and its two reactions: 10 HP and 5 splash
  within 1, so it chains like any keg.
- **Its fuse** is a third reaction, `powder_keg_fuse`.
- **The facts it records:** `UNIT_SPAWNED` for its unit, then `OBJECT_STATE_CHANGED` with a new
  `Change.LANDED` (appended) carrying the tile. A client mirror creates the object from that fact.
  The battle view already draws a spawned breakable as a token (`battle_view.gd:1214`), so no UI
  file changes.

**Effect ids for its reactions** come from the session's `InstanceIdAllocator` (`session.ids`).
For this reason the throw runs at session level (next section), not inside an effect operation:
the effect engine holds no allocator and no run seed.

### The fuse and the darkness

- **The fuse counts on its reaction's counter,** as question 46 approved: no new save key, and
  mirrors follow it through `COUNTER_CHANGED`. It counts the enemy Phase Ends after landing. The
  landing phase N doesn't count, so the keg explodes at the end of enemy phase N+2. That is
  before the darkness phase, and in the same phase the next keg lands. The constant is
  `FUSE_PHASES = 2`.
- **A hit, splash or Spark sets it off early,** through the keg reactions every keg already has. A
  chain resolves as for authored kegs.
- **The darkness:** a thrown keg's contact limit is 1 (`MapObjects.contact_limit()`, read by
  `Darkness`'s erosion). Its own tile counts as contact when flooded, so a keg that lands on a
  flooded tile explodes at the next darkness phase. Authored kegs keep the limit of 3.

### Keg Barrage (`scripts/enemies/keg_barrage.gd`, new `class_name KegBarrage`)

- **The signature move** is an `EffectDefinition`, `keg_barrage`. It triggers at Phase Start,
  every 2nd time (a `CounterCondition` with count 2, as Fortify). It has no operation of its own:
  its `EFFECT_ACTIVATED` fact is what the intents and the throw read.
- **When it fires:** a new hook, `CombatHooks.Hook.PHASE_START_EFFECTS` (appended, 8), runs after
  each side's Phase Start effects resolve and before that side's turns (`phase_runner.gd`).
  `KegBarrage.throw_hook` throws for each enemy whose `keg_barrage` fired at that Phase Start. The
  throw doesn't use up the Baron's action. The first throw is enemy phase 2, then 4, 6 and so on.
- **Picking the tile:** `KegBarrage.pick_tile(state, baron_id, run_seed) -> Vector2i` is pure.
  - **Legal tiles:** within `REACH = 5` by grid distance, ignoring walls; empty (no unit, no
    object); standable by some movement type. Flooded tiles count.
  - **Score:** player units of any seat within the blast (`MapObjects.KEG_BLAST`) around the
    tile. Enemies are ignored, so its own side's losses never count.
  - **The best score wins.** Ties are broken by a stream made fresh from `RngKey` with a new
    `RngPurpose.KEG_BARRAGE` (appended, 15), keyed by the run seed and the turn. It draws once
    over the tied tiles in tile order. With no player unit in reach, every legal tile ties. No
    legal tile means no throw, reported as a diagnostic.
  - **Why a fresh stream:** the intent and the real throw draw the same tile from the same board,
    and no saved stream position moves.
- **Its intent:** `Intents._signatures_fired` gives the Baron's signature area as the blast tiles
  around `pick_tile` on the board after the sandbox crosses the enemy Phase Start. The barrage
  then shows as the existing SIGNATURE intent, with its area, during the player phase before.
  Intents recompute after every player command, so the shown tile follows the player's moves and
  equals the real throw.

### The boss map (`maps/boss/powder_keep`, built by `tools/gen_maps.gd`)

- **Size and layout.** 16×12:
  - a pillared hall at the top, with the throne (`Y`) at the top centre on the leader slot;
  - a guard line before the throne;
  - two approaches around the sides;
  - 8 deployment tiles at the bottom;
  - 2 authored kegs near the guards;
  - 3 darkness source candidates low on the map, so the darkness flows up to the throne (the
    drain).
- **Objective:** `DEFEAT_BOSS`, shown as "Defeat the Powder Baron".
- **Fixed enemies:** the four new `fixed_*` fields above.
- **Turn par:** 14, the low end of the vision's 14–18, as a `# ASSUMPTION` in the generator's
  notes until playtesting.
- **Checks:** it passes `MapCheck`, reachability included.
- **The generator** gains `_boss_maps()` and `BOSS_FOLDER`. The other maps rebuild byte for byte.
- **The pools:** the boss pool's M1 stand-in is replaced by `powder_keep`, so the BOSS node's
  battle loads it.

## Save Impact

- **Block `COMBAT`, key `entities`, version 1 → 2** (`CombatMapSection.EntitiesSection`):
  - Every object entry adds `"is_thrown"` (bool) and `"fuse"` (int, -1 for none). As built,
    the fuse lives here (see As built).
  - `CombatMapSection.load_into` and `capture` compare only authored spots. On resume, thrown
    entries are restored onto the rebuilt map.
  - `migrate(data, 1)` adds `"is_thrown": false, "fuse": -1` to every object, since no version 1
    file can hold a thrown keg.
  - `combat_map` stays at version 1. Its `object_spots` lists authored spots only, as now.
- **A thrown keg's two reactions** are saved by the existing `effects` section under the authored
  kegs' ids, and resolved through `MapObjects.map_definition` as before. No new key.
- **A thrown keg's HP** is its unit's, in `combat_state` (version 2, unchanged). `_map_mismatch`
  already checks breakables against their units.
- **Not saved:** the barrage's tile choice (re-derived from the board and the seed), and the
  barrage's cadence, which is already on the signature's counter.
- **Not per player.** No profile, campaign or settings change. Dev mid-battle saves from before
  this change still load, as version 1.

## Work Breakdown

Each step is committed on `feature/EN11` once its suites pass. A step that changes only data runs
its suite and the content suite.

| Step | Files | What | Risk | Verification |
|------|-------|------|------|--------------|
| A1 The Baron | `enemy_class_definition.gd` (`holds_post`), `enemy_ai.gd` (own-tile options, `_holds_fixed_tile`, TOD-002 closed), `data/enemies/powder_baron.tres` (Cleave, Unshovable; signature added in C1), the content rules if a boss class needs a rule | The unit | 🟡 | enemies/roster: can't be shoved; never leaves the throne, attacks a foe in range from it, Waits otherwise; keeps Guard after the darkness arrives; content suite |
| A2 Fixed setup | `combat_map_definition.gd` (four `fixed_*` exports), `enemy_setup.gd`, `data/enemies/packs/powder_keep_guard.tres` | A scripted map's enemies | 🟡 | enemies setup: a fixed map places the pack in slot order at level 6, the Baron at 8 with Stalwart; no setup draw; the same twice and on a restart from Begin |
| B1 Thrown kegs | `map_objects.gd` (`throw_keg`, `THROWN_INDEX_BASE`, `Change.LANDED`), `map_state.gd` (`is_thrown`, capture/restore), `combat_state.gd` (`follow` creates a landed keg) | A keg created mid-battle | 🔴 network | map: it has keg stats and reactions; a hit, a splash or Spark explodes it; a chain through an authored keg; a mirror following the batch matches the host's `state_hash` |
| B2 The fuse | `map_objects.gd` (`powder_keg_fuse`, `FUSE_PHASES`, `contact_limit`), `darkness.gd` (erosion reads the limit; own tile for thrown kegs) | The fuse and the darkness | 🟡 | **First, check** that a `PHASE_END` reaction owned by a map object fires at the enemy Phase End; **if not, stop and ask** (the fallback is a `fuse` field in entities version 2). Then: it explodes at the end of phase N+2, not before; the darkness sets it off at first contact and on a flooded landing tile; authored kegs still take 3 contacts |
| B3 Save | `combat_map_section.gd` (entities version 2, `migrate`, authored-only spot check), `combat_session.gd` if `load_snapshot` needs the thrown entries first | Resume with lit kegs | 🔴 save | sessions/saves: a battle saved with a lit keg resumes with its tile, HP and fuse count, and explodes on the same phase as the uninterrupted battle; a version 1 file loads |
| C1 Keg Barrage | `keg_barrage.gd` (new), `combat_hooks.gd` (`PHASE_START_EFFECTS`), `phase_runner.gd`, `rng_key.gd` (`KEG_BARRAGE`), `powder_baron.tres` (signature), session registration | The throw | 🔴 network | enemies: it fires on enemy phases 2, 4 and 6 only; picks the tile catching the most player units, ignoring enemies; ties give the same tile twice with one seed and follow the stream; nothing beyond 5 tiles; no legal tile gives a diagnostic and no throw |
| C2 Intent | `intents.gd` | SIGNATURE, one phase ahead | 🟡 | enemies/intents: in player phase 2 the Baron's intent is SIGNATURE "Keg Barrage" with the blast around the tile it then throws to; it follows a player move; no barrage intent in player phases 1 and 3 |
| D1 The map | `tools/gen_maps.gd`, `maps/boss/powder_keep.tscn` / `.tres` (generated), `combat_map_pools.tres` | The boss map in the boss pool | 🟡 | The generator: every map passes `MapCheck`, and the other maps rebuild unchanged (`git diff` clean); campaign: a BOSS node's battle loads `powder_keep` with the Baron on the throne |
| D2 The battle | `tests/map_set/boss/run_all.gd`, `map_set_boss_cases.gd` (new; runner discovery, no runner change expected) | A headless boss battle | 🟢 | Reaches `COMBAT_ENDED`; the same seed repeats; defeating the Baron wins; a flooded throne stops healing the Baron; its time under the 300 s limit, and `map_set/key` unchanged |
| D3 Docs | `docs/design/rebalance-and-features.md` (Inbox), the EN11 row in the enemies plan | Notes | 🟢 | Review |

D3 logs these first-pass values for the rebalance doc:

- the 2-phase cadence, the 5-tile reach and the 2-phase fuse;
- guard level 6;
- par 14;
- Stalwart;
- 8 guards;
- the lit-keg contact rule;
- no scripted beats.

The lit-keg contact rule differs from map-objects.md's single contact limit, so it is also queued
for the ideation thread. The design docs aren't edited unless asked.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| `MapObjects.Change.LANDED = 9`, `FUSE_BURNED = 10` | Enum, network | — | Appended | Built (B1, B2) | `combat_state.gd` `follow`, `battle_view.gd` (`OBJECT_STATE_CHANGED`), the tile panel | 🔴 |
| `InstanceIdAllocator.object_effect_id()` | New static method | — | Derived ids for a thrown keg's reactions | Built (B1) | `map_objects.gd` | 🟢 |
| Content rules: a post holder may differ from its base class in behavior and lead an undrawn pack | Test rule | Any difference fails | Exempted | Built (A1) | `tests/content/content_rules.gd` | 🟢 |
| `CombatHooks.Hook.PHASE_START_EFFECTS = 8` | Enum | — | Appended | Suggested (C1) | `phase_runner.gd`, every `hooks.add` caller | 🟡 |
| `RngKey.RngPurpose.KEG_BARRAGE = 15` | Enum, save key | — | Appended | Suggested (C1) | `rng_key.gd`, the rng tests | 🟡 |
| `entities` section version 1 → 2 | Save format | No thrown objects | `"thrown"` entries, authored-only spot check | Suggested (B3) | `combat_map_section.gd`, `map_state.gd`, the saves tests | 🔴 |
| `EnemyClassDefinition.holds_post` | `@export` | — | New, false by default | Built (A1) | `enemy_ai.gd`, the content test | 🟡 |
| `CombatMapDefinition.fixed_pack_id`, `fixed_enemy_level`, `fixed_leader_level`, `fixed_leader_prefix_id` | `@export` | — | New, empty or 0 by default | Suggested (A2) | `enemy_setup.gd`, `gen_maps.gd`, `map_check.gd` | 🟡 |
| `class_name KegBarrage` | New class | — | New | Suggested (C1) | Class cache (`--import`) | 🟢 |
| The boss pool's map | Behavior | `m1_greybox` | `powder_keep` | Suggested (D1) | campaign and sessions tests that reach a BOSS node | 🟡 |
| `_holds_fixed_tile` | Behavior | Always false | True for a class that holds its post | Suggested (A1) | enemies tests on darkness arrival | 🟢 |

## Verification

- `sh bandit-bash/tools/run_tests.sh`, without `--open` (build agent), after each step's suites. The
  full runner at the end, with the report path.
- The cases named in each step. The five done-when checks map to C1/C2, B2, A1, D2 and D2.
- **Determinism:** the same seed gives the same throws and the same boss battle twice. The
  mirror's `state_hash` matches the host's through a throw and an explosion.
- **Time:** the boss battle runs in its own part, `map_set/boss`. Its time and `map_set/key`'s are
  reported against the 300 s limit. Performance claims are unmeasured unless timed.

## Rollback

Each step is its own commit; revert in reverse order.

- **Reverting D1** puts M1 back in the boss pool.
- **Reverting C1** removes the hook registration and the signature, so the Baron fights without
  throwing.
- **Reverting B3** returns `entities` to version 1. A dev save written at version 2 is then
  refused (a newer version), and its battle restarts from Begin. No shipped saves exist.
- **Data steps** (A1, A2) remove only content, and no other map names it.
