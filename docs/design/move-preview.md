# The Move Preview

When a player hovers a tile for a selected unit, the board shows what moving there would do before
any action: the darkness damage the unit would take there in this turn's darkness phase (after the
enemy phase, before the creep; [ui-lift.md](ui-lift.md#darkness-phase)), and every enemy's intent
re-planned with the unit on that tile. The intents are what the enemies would do, not an estimate,
so the preview must give exactly what a full re-plan gives.

**Status:** adopted November 12, 2026 (decisions at the end). This doc covers the
re-architecture of `Intents.preview` (`scripts/enemies/intents.gd`, `TOD-001`) and of the
`MovePreview.Queue` around it (`ui/battle/board/move_preview.gd`). It changes no rule and no
result. It responds to P07 question 16 (a): "a data structure with caching, or another process",
starting from `Godot_FE`'s absolute-range check.

## Where it stands

- **The target** is 50 ms per hover at p95 in a debug build (P05 question 10; decision 4 below).
- **The benchmark** (`tests/bench/preview_bench.tscn`, release through
  `tests/bench/release_bench.sh`) hovers every move tile of every acting unit through the threaded
  `MovePreview.Queue` on four boards: M1 turn 1, M1 engaged, a 9-enemy 6-unit key board on the
  Hall, and the Powder Keep engaged. Real key maps field fewer: a key pack is the step's standard
  count of escorts (at most 5) plus its mini-boss (game-vision.md, Run structure; enemy-packs.md).
  The key board adds a Brute, a Crossbowman and a Hedge Healer to reach move-preview's benchmark
  size (P05 question 47). The Powder Keep is the real 9-enemy board.
- **Measured** on one machine (Ryzen 7 9800X3D), Godot 4.7.1, times in milliseconds. "Before" is
  EN13's code, measured at the start of EN14; "after" is EN14 (layer 2, the lighter sandbox),
  November 20, 2026. A sweep is all of one unit's tiles in turn.

| Board | Build | Hover median | Hover p95 | Sweep median | Sweep p95 |
|---|---|---|---|---|---|
| M1 turn 1 | debug | 18 → 18 | 41 → 29 | 520 → 461 | 942 → 770 |
| M1 turn 1 | release | 14 → 13 | 28 → 25 | 382 → 363 | 690 → 601 |
| M1 engaged | debug | 82 → **28** | 107 → **46** | 2,051 → 694 | 2,783 → 971 |
| M1 engaged | release | 58 → 24 | 74 → 40 | 1,484 → 587 | 1,964 → 830 |
| Key, 9 enemies | debug | 362 → 205 | 503 → 300 | 12,590 → 7,289 | 21,926 → 12,731 |
| Key, 9 enemies | release | 251 → 156 | 359 → 226 | 8,688 → 5,544 | 15,673 → 9,760 |
| Boss, 9 enemies | debug | 1,609 → 618 | 1,860 → 970 | 61,825 → 25,196 | 98,829 → 35,291 |
| Boss, 9 enemies | release | 1,097 → 449 | 1,275 → 707 | 42,432 → 18,513 | 67,473 → 25,942 |

- **The target now holds** on both M1 boards, and is missed on the 9-enemy boards.
- **Why one forecast slowed on big boards** (EN13: 1.9 ms on M1, 4.6 ms on the boss board): the
  sandbox copy. Every `StatSheet.copy_for` rebuilt its copy through `set_base` and
  `add_modifier`, each dropping 16 cache slots from an empty cache, for every base sheet and every
  cached sheet: about 1.35 ms of a 1.56 ms engine copy on the key board in debug. Instances
  (copying and re-registering about 32) took 0.24 ms. The copy now takes the dictionaries whole,
  with each sheet's static answers. One forecast in debug: 1.8 → 1.1 ms (M1), 3.1 → 1.7 ms (key),
  3.3 → 1.9 ms (boss). What still grows with the board is the engine copy's instances (0.15 →
  0.54 ms) and the exchange's dispatch over them (0.76 → 0.98 ms).
- **Reuse, as built** (layer 2): on the key board a hover makes 46 attack forecasts and reuses 32;
  on the boss board it makes 259 and reuses 199. Three things limit it:
  - an army effect counting every attack (Iron Heart, every 7th attack by your units; the
    Mercenary army's heirloom) is read by nearly every forecast, and its counter moves at almost
    every enemy step, so steps within one preview rarely reuse each other's forecasts. Most reuse
    comes from earlier hovers on the same board;
  - engaged boards cluster: most options lie within the margin of the unit moved or of an earlier
    step's action;
  - previews keep at most 2,000 forecasts in the store (Threads and memory).
- **What dominates now** on the 9-enemy boards is the decisions themselves, not their forecasts:
  45 decisions per hover, each with its floods, Support's safety floods (the Warcaller's about
  13 ms per decision in debug) and an advance's whole-map flood. Layers 3 and 4 bound those;
  layer 5 hides the rest.

## How a preview works now

1. **On the main thread** (`Intents.prepare_preview`):
   - copy the session into a sandbox;
   - walk the unit to the tile;
   - rebuild the danger zone from the latest one (layer 4);
   - cross the player Phase End and the enemy Phase Start (every Phase End effect; darkness damage
     comes later, in the darkness phase).
2. **On a worker** (`PreviewJob.run`), play the enemy phase step by step. At each step every enemy
   yet to act decides, and the best one acts.
3. **Reuse.** An enemy keeps its decision from the latest intents while no touched tile can change
   it (layer 3, as built), until a different enemy acts first; its attack forecasts are reused by
   key (layer 2). The effect margin is the largest positional reach of any effect on the map.

Before EN14 and EN15, the reuse missed in four ways:

- **It works per decision.** One touched option re-decides the whole enemy, every end tile × target
  × weapon, though most of those forecasts didn't change.
- **Some decisions count as touched by any move:** an advance, a regroup, a Support enemy, and a
  Wait with a class. On M1 turn 1 every enemy advances, so nothing is ever reused there.
- **It stops at the first change.** Once a different enemy acts first than in the latest intents,
  every later step re-decides every enemy, even those far from anything that changed.
- **It repeats fixed costs on every hover:** the sandbox copy, the full danger zone, the phase
  crossing, and two floods per enemy decision (one for its reach, one for its zone).

## Starting point: `Godot_FE`'s absolute range

`Godot_FE/scripts/combat/controllers/CombatUnitRangeManager.gd` kept two ranges per unit:

- its **absolute range**: the tiles within its movement on an empty, terrain-free grid, plus its
  longest attack range from their edge;
- its **effective range**: the same with terrain and units counted.

It also kept a reverse index from each tile to the units whose absolute range covers it. When a unit
moved or died, only the units indexed at its old and new tiles recomputed their effective range.
The absolute range never depends on other units, so the index stays valid until the indexed unit
itself moves.

`Godot_FE` used this for the danger zone, not for re-planning AI decisions. The design below uses
its two ideas, a range that is a safe upper bound and an index from tiles to the units it covers,
at the level of single options rather than whole units.

## The design

The layers are independent. Each is built and measured on its own, and each keeps results identical
to a full re-plan.

### 1. Find what changed by comparing, not by margins

After the preview sandbox crosses the phase boundary, compare it with the latest intents' sandbox at
the same point, unit by unit. Each unit gets a signature: tile, HP, Block, Stance, modifiers and
effect instances with their counters.

The changed set is the moved unit plus every unit whose signature differs. For example, a Phase End
heal for standing next to an ally. Their old and new tiles are the touched tiles.

This replaces "the moved unit's two tiles", which misses a Phase End effect that changes a third
unit. The effect margin still widens each zone, because an effect can read a unit's position without
changing it.

### 2. Memoize options, not decisions

Cache each forecast an enemy's decision makes. The key holds:
- the attacker, its weapon, its end tile and its path;
- the target;
- the signatures of every unit within the effect margin of the end tile, the target's tile and the
  path.

A decision then rebuilds its option list from the cache and forecasts only the misses. The cheap
steps (rating, the dry-tile rule, the target rule) run on every option as they do now.

The key also holds the darkness layers and map objects within the margin.

- **Shared:** one cache per battle, filled by every intents computation and reused by every preview
  and every step of the phase.
- **Survives facts:** a fact changes the signatures it touches, so only the entries keyed on those
  units stop matching. A forecast far from an action stays valid after it. This matters most when
  several players act on one map (Scaling below).
- **Cleared:** at each turn's end, so turn-dependent effects ("on the first turn") never match a
  stale entry, and the cache stays small.

The cache also covers the third miss. After a different enemy acts first, a later enemy far from
both changes still finds its forecasts cached.

**Fallback:** if any effect reads the whole map (a margin of −1, as with "no ally closer to the
enemy"), the key holds every unit's signature. Nothing is reused, which is today's behavior.

**As built (EN14, P05 question 48):** `EnemyAI.ForecastStore` and `EnemyAI.Forecasts`, handed to
`EnemyAI.decide` through an optional `forecasts` argument.

- **The key:** the attacker, the weapon, the path and the target; the margin; the signature of
  each unit on the path or within the margin of the attacker's tile, the end tile and the
  target's tile; and what the whole board shares (turn, phase, the darkness layers, map objects,
  and the counters of effects with no holder, such as heirlooms). Units beside the path aren't in
  it: a walk reads only its own tiles, and a move before acting fires nothing.
- **A signature** is the unit's whole state (`CombatUnitState.capture`), the counters and charges
  of the effects it holds, its timed modifiers, and its stat changes in the sandbox's fact log.
  An effect that fires only at Phase Start or Phase End is left out: a forecast crosses no phase,
  and only an effect's own instance reads its counters.
- **Whole-board effects:** an effect that can fire in an exchange and selects a whole scope (Grave
  Candle's Block for all your units on a defeat), runs a custom script (a keg's blast aside,
  which the margin counts) or reaches other units by scope from a unit puts every unit's
  signature in the key.
- **Lifetime:** one store per computation of the intents, not per battle; it is dropped at the
  next fact. Surviving facts needs the turn-dependent parts and the cross-generation sharing
  worked out first, and is left for later.

The board diff of layer 1 is the signatures: two boards differ, for a forecast, exactly where its
key's signatures differ. For decisions, the diff compares facts (layer 3, as built).

### 3. Bounded zones for the decisions that are global today

Each zone below is a safe upper bound. A tile outside it can't change the decision. All three use
terrain-free distances, the absolute range in `Godot_FE`'s sense, which never underestimate a path.

- **Advance.** The nearest foe is the one with the lowest path cost to a tile it could be attacked
  from. A move keeps the decision when all of these hold:
  - the moved unit isn't the advance's target;
  - the moved unit's new tile is farther than that cost by terrain-free distance, so it can't become
    nearer;
  - neither touched tile lies within that cost of the enemy, or within the largest remaining cost of
    the target's stand tiles, so it can't block or free a cheaper path.
- **Regroup and Support.** These read each end tile's safety, meaning how many player units could
  attack it. Keep `Godot_FE`'s reverse index from each tile to the player units whose absolute range
  covers it. A move changes only the safety of tiles within the moved unit's absolute range from its
  old or new tile, plus the walk zone as today.
- **Wait with a class.** The enemy had no foe in reach. The decision changes only if a touched tile
  lies within the enemy's absolute range.

**As built (EN15):** `EnemyAI.Footprint`, filled by `EnemyAI.decide` through an optional
`footprint` argument (null records nothing) with what the decision read, as it read it. Every
decision has one; none counts as touched by any move any more. A touched tile can change the
decision when one of these readings covers it. Distances are terrain-free: impassable terrain is
the only cost-0 tile, so every step costs at least 1 and a route never costs less than its grid
distance.

- **The walk:** every tile it can walk through, and the units within its longest attack or staff
  range of them (at least 1, since a unit beside the walk can block it), plus the margin. This is
  the attack zone of before, now tested on the touched tiles against the board's own flood
  instead of built as a set from a second flood per decision.
- **Units it reads:** each option's target-rule subject, and a Shieldbearer's candidate allies
  (their ranges), within the margin; the Hexer's subjects within 2 more (its rule counts the foes
  around them).
- **An advance** on a foe whose nearest stand tile costs C: a foe within C plus its range of the
  enemy (it could be as near), or for a Hound within K of a pack ally (K: the target's distance
  to the pack); and every route from an end tile r to the target's stand tiles costing no more
  than r's cost left: a tile x with dist(r, x) + max(0, dist(x, target) − range) ≤ left(r) can
  block a cheapest route or open a cheaper one.
- **A Shieldbearer short of a post:** the same routes to the tiles beside its ally, each bound by
  the least cost left of any end tile.
- **A lit Brazier beside an end tile:** the units within its light.
- **No foe reachable** (an advancing class's Wait): its whole-map flood, within its range. The
  absolute range above fits a Guard's Wait (the walk reading); an advancing enemy waits only when
  no foe is reachable anywhere.
- **Support's threats** (Godot_FE's absolute range): the moved unit's movement plus range from
  where it stood (its stats then) and where it stands (its stats now), and every other player
  unit's range around each touched tile (a tile it can now end on, or no longer can). A player
  unit whose MOVEMENT or range differs on the preview's board changes them anywhere: those are
  compared on that board.
- **Every move:** a lever that can seal the objective (its seal reads every route), and an end
  tile with no route at all (one of any length can open).

**The touched tiles** come from layer 1, applied to decisions: the preview compares the facts of
its walk and phase crossing with those of the latest intents' crossing. Each fact one recorded
and the other didn't adds its tile and the tiles, on both boards, of the units and objects it
names: the moved unit's two tiles, a Phase End heal reaching a third unit, a Powder Baron's keg
landing elsewhere because the move changed its best tile. Rules code records a fact for every
change, so an untouched tile holds the same unit in the same state on both boards. A fact naming
anything else (an effect with no holder) re-decides every enemy.

A kept decision that acts is carried out afresh, and its second move (the Bloodhound's) is decided
afresh. When that second move goes elsewhere than the latest intents', the boards differ past the
touched tiles, so the later steps decide afresh.

### 4. An incremental danger zone

Keep the danger zone per enemy, with `Godot_FE`'s index from tiles to the enemies whose absolute
range covers them. A preview recomputes only the enemies indexed at the touched tiles and merges the
result.

**As built (EN15):** `DangerZone.compute` takes the latest zone, the touched tiles and the margin
as optional trailing arguments. An enemy's tiles depend only on who stands within its MOVEMENT (its
walk) and on its own stats, so each enemy keeps its tiles from the latest zone unless its MOVEMENT
or the margin, from its tile, reaches a touched tile. The index from tiles to enemies is built
once per zone, on the first preview. The preview builds its zone on the main thread from the walk's
facts. A walk fact naming a map object (a keg's blast reaches past any walk), a negative margin or
a different set of enemies rebuilds every enemy. The result equals a full rebuild, the merged tiles
in the same order.

### 5. Precompute during playback, so a hover is a lookup

The rules resolve before the presentation plays them. End Turn runs the whole enemy phase and the
next player Phase Start in one call (`PhaseRunner`), and each player action resolves before its
animation. So while the enemy phase or an attack plays back, the board the player will hover next is
already final.

- **When:** as soon as the latest intents are computed, the worker starts a sweep. It previews every
  tile each unit that hasn't acted can end on. Enemy phase playback and each action's playback give
  it seconds of idle time.
- **Order:** the selected unit first, then the unit under the cursor, then the rest, nearest tiles
  first. A hover on a tile not yet done jumps it to the front.
- **Cache:** results are keyed by the board (`last_seq`), the unit and the tile.
- **Dropped:** when a new fact makes them stale. The next sweep restarts at once, and layer 2's cache
  makes it mostly lookups.
- **A hover** on a done tile shows on the next frame, with no work at all. On-demand work happens
  only when a player hovers before the sweep reaches the tile, and then it is one cached preview.

Layers 2–4 make the whole sweep cheap, because neighbouring tiles and units share nearly every
forecast. The sweep runs one preview at a time on one worker thread, as the queue already allows.

### Scaling to shared co-op maps

Shared battles, where 2–4 players fight on one map at once, are post-MVP (P24). The design is meant
to carry over to them:

- **Each machine previews only its own player's units,** on its own mirror of the board. The work per
  machine grows with the size of the map, not with the number of players.
- **Other players' moves arrive as facts.** Each one restarts the sweep, but layer 2's cache survives
  it: only forecasts near that move are redone. Layers 3 and 4 limit the re-planning to enemies whose
  absolute range covers the move.
- **Moves at the same time.** A preview shows the board with committed moves only. A teammate's unit
  that is still being moved isn't part of it until its command resolves. Then the preview updates,
  as it does after any fact.
- **The boss-map benchmark decides.** A shared boss map could field 16–24 player units and many
  enemies. When P24 is planned, it adds that benchmark. If GDScript can't meet the target there, the
  rejected native-code option is reopened.

### Fixed-cost trims

- One flood per enemy decision, shared by its reach and its zone.
- Measure the sandbox copy and the phase crossing. If either dominates, the preview copies once per
  selected unit and undoes the walk between tiles, if the profile justifies the complexity.

## Correctness

The preview must equal a full re-plan, so every layer ships with checks that compare the two.

- **A checking mode,** like the engine's `verify`: each cache hit and each kept decision is
  recomputed and compared, in tests and debug runs only.
- **An equality suite:** seeded random boards, every reachable tile of every player unit, each
  previewed through the new path and through a full `Intents.compute` on a moved copy. Every
  intent's kind, target, tile, order and forecast must match.
- **Content coverage:** the suite runs again whenever content adds an effect with a new positional
  reach. CT6's target shapes, EN6's behaviors and EN8's mini-bosses all trigger it.

## Threads and memory

- **Threads.** The main thread fills the store when it computes intents. A preview, on the worker,
  reads the store and keeps its new forecasts in its own overlay, then adds them to the store as
  it ends, on the worker. One preview runs at a time, but the store takes a lock on every read
  and write anyway, so a dropped job finishing while the main thread works stays safe. The rules
  code stays pure, and the worker still never logs.
- **Memory, measured.** A kept forecast holds 25–43 KB in debug (its facts, rolls and outcomes are
  objects). Unbounded, a sweep of every tile of one board state kept 10,225 forecasts on the key
  board (480 MB) and 58,793 on the boss board. So previews add at most 2,000 to a store, the oldest
  previews' dropped first (a hover's neighbours share most forecasts); the computation's own are
  kept besides. After a full sweep the store held 89 MB on the key board and 64 MB on the boss
  board, in debug. It goes at the next fact.

## Rejected

- **Another process or native code** (a separate OS process, or C++ through GDExtension) would add
  a second language, a build chain on every platform and marshalling of the board. Held back unless
  the layers above can't reach the target in GDScript.
- **An approximate preview** (re-planning only the nearest enemies, or skipping the phase crossing)
  would break the rule that intents are what the enemies will do.
- **A per-decision zone that is merely wider** would keep the four misses above.

## Build steps (proposed)

| Step | Work | Done when |
|---|---|---|
| A Measure | Benchmark boards: M1 turn 1, M1 engaged, a 9-enemy, 6-unit key-combat board. A per-phase profile of a hover. The equality suite and checking mode, run against today's preview | Baseline median and p95, debug and release, per hover and per sweep; equality passes |
| B Diff and cache | Layers 1 and 2, the shared flood (left out: under 2% of a hover) | Equality passes; the benchmark is measured before and after. **Built in EN14** (Where it stands) |
| C Zones | Layers 3 and 4 | Same. **Built in EN15** (Where it stands) |
| D Precompute | Layer 5: the sweep during playback, in `MovePreview.Queue` | A hover on a done tile shows on the next frame; the sweep's time per turn is reported |

Steps A–C change only the internals of `intents.gd`, `enemy_ai.gd` and `danger_zone.gd`. Step D
changes the queue inside `move_preview.gd` and the controller's calls into it. No public signature
changes, except optional trailing arguments: EN14's `forecasts` on `EnemyAI.decide` (P05 question
48), and EN15's `footprint` on it and `base`, `touched` and `margin` on `DangerZone.compute` (P05
question 49). Step D goes ahead whatever B and C measure, because the user wants hover work at a
minimum.

## Decisions

| # | Question | Answer (user, November 12, 2026) |
|---|---|---|
| 1 | Owner | Left to the orchestrator: **P05 steps EN13 (A), EN14 (B), EN15 (C) and EN16 (D)**, since the intents are P05's |
| 2 | When | EN13 alongside Wave A, so later content is checked against the equality suite. EN14–EN16 after EN6 (Guard and Skirmisher) and before the M2 exit playtest |
| 3 | Benchmark size | 9 enemies against 6 player units, engaged, for now. A boss-map case comes with EN11. Shared co-op maps get theirs when P24 is planned (Scaling) |
| 4 | Target | 50 ms at p95 in a debug build, per hover on a tile the sweep hasn't reached, at the benchmark size |
| 5 | Precompute | Compute and cache between turns and during playback, keeping hover work to a minimum (layer 5); one worker thread |
