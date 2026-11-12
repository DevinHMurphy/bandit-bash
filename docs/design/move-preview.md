# The Move Preview

When a player hovers a tile for a selected unit, the board shows what moving there would do before
any action: the darkness damage the unit would take there, and every enemy's intent re-planned with
the unit on that tile. The intents are what the enemies would do, not an estimate, so the preview
must give exactly what a full re-plan gives.

**Status:** draft, November 12, 2026, with questions for the user at the end. This doc covers the
re-architecture of `Intents.preview` (`scripts/enemies/intents.gd`, `TOD-001`) and of the
`MovePreview.Queue` around it (`ui/battle/board/move_preview.gd`). It changes no rule and no
result. It responds to P07 question 16 (a): "a data structure with caching, or another process",
starting from `Godot_FE`'s absolute-range check.

## Where it stands

- **The target** is 50 ms per hover (P05 question 10).
- **Today**, measured on M1 turn 1 in a debug build on a worker thread, a hover takes 17–18 ms at
  the median and 33–40 ms at p95. A release build on the main thread took 14 ms at the median,
  measured before the worker thread existed.
- **The cost grows** with enemies × attack options. Each attack option is a full
  `CombatForecast.exchange`, about 1.9 ms in debug. M1 has 3 enemies. A key combat fields up to 9
  enemies, its step's standard count plus 1 to 3 plus a mini-boss (game-vision.md, Run structure).
  Boss maps can field more. Before the worker thread, M1 already ran 66 ms at the median and
  214–232 ms at p95.
- **Breakdown unknown.** No profile yet says how a hover's time splits between the fixed costs and
  the decisions. The first build step measures it.

## How a preview works now

1. **On the main thread** (`Intents.prepare_preview`):
   - copy the session into a sandbox;
   - walk the unit to the tile;
   - compute the whole danger zone;
   - cross the player Phase End and the enemy Phase Start (every Phase End effect, darkness damage
     included).
2. **On a worker** (`PreviewJob.run`), play the enemy phase step by step. At each step every enemy
   yet to act decides, and the best one acts.
3. **Reuse.** An enemy keeps its decision from the latest intents while neither the unit's old tile
   nor its new tile lies in that decision's zone. The zone is the tiles the enemy can walk through,
   plus its longest range plus the effect margin (the largest positional reach of any effect on the
   map).

The reuse misses in four ways:

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
heal for standing next to an ally, or darkness damage on the new tile. Their old and new tiles are
the touched tiles.

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

- **Shared:** one cache per board, from the latest intents, filled by their computation, reused by
  every preview and every step of the phase.
- **Cleared:** when any fact makes the latest intents stale.

The cache also covers the third miss. After a different enemy acts first, a later enemy far from
both changes still finds its forecasts cached.

**Fallback:** if any effect reads the whole map (a margin of −1, as with "no ally closer to the
enemy"), the key holds every unit's signature. Nothing is reused, which is today's behavior.

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

### 4. An incremental danger zone

Keep the danger zone per enemy, with `Godot_FE`'s index from tiles to the enemies whose absolute
range covers them. A preview recomputes only the enemies indexed at the touched tiles and merges the
result.

### 5. Precompute the selected unit's tiles

When a unit is selected, queue a preview of every tile it can end on, nearest the cursor first. They
run one at a time on the worker thread, as the queue already allows.

- **Cache:** results are keyed by the board (`last_seq`), the unit and the tile.
- **Dropped:** on any new fact, a deselect or a different unit.
- **A hover on a done tile** shows on the next frame, with no work at all.
- **A hover on a pending tile** jumps to the front of the queue.

Layers 2–4 make the whole sweep cheap, because neighbouring tiles share nearly every forecast.

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

- **Threads.** The main thread fills the option cache when it computes intents. A preview on the
  worker reads the cache and writes its new entries to its own overlay. The main thread merges the
  overlay when it collects the result. Only one preview runs at a time, so nothing needs a lock.
  The rules code stays pure, and the worker still never logs.
- **Memory.** One forecast per enemy × end tile × target in range × weapon. A key combat with
  9 enemies, about 40 end tiles each and 2 targets in range, comes to about 1,500 forecasts. That is
  small, and the cache clears on every fact. The figure is an estimate, not measured.

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
| B Diff and cache | Layers 1 and 2, the shared flood | Equality passes; the benchmark is measured before and after |
| C Zones | Layers 3 and 4 | Same |
| D Precompute | Layer 5 in `MovePreview.Queue` | A hover on a done tile shows on the next frame; the sweep's time is reported |

Steps A–C change only the internals of `intents.gd`, `enemy_ai.gd` and `danger_zone.gd`. Step D
changes the queue inside `move_preview.gd` and the controller's calls into it. No public signature
changes. If layer B alone meets the target, C and D may wait.

## Questions for the user

1. **Owner:** new steps in P05 (EN13–EN16), since the intents are P05's.
   - *Recommended.* The alternative is a new plan row.
2. **When:** after EN6, which adds the Guard and Skirmisher behaviors the zones must cover, and
   before the M2 exit playtest on the larger maps.
   - *Recommended:* build step A sooner, alongside Wave A, so later content gets checked against the
     equality suite.
3. **Benchmark size:** a key combat's upper bound, 9 enemies against 6 player units, engaged.
   - *Recommended.* A boss-map case is added when the Powder Baron map exists (EN11).
4. **The target:** 50 ms at p95 in a debug build, per hover on a tile not yet precomputed, at the
   benchmark size.
   - *Recommended:* p95 rather than the median, since the spikes are what a player feels.
5. **Precompute:** may the preview keep one worker core busy while a unit is selected?
   - *Recommended: yes,* one task at a time, dropped on any action.
