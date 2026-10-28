# Game Orchestrator

The living map of every implementation plan for Bandit Bash: what exists, what each plan depends on,
what may start next, and what stays out of scope. It keeps the project on the MVP and makes sure no
plan reaches implementation with a missing dependency.

**Created:** October 25, 2026. **Last updated:** October 26, 2026.

This is not an implementation plan (those use the template in
`docs/standards/gdscript-reference.md`). It has no work of its own; it tracks the plans that do.

## How to use this file

**Update it whenever** a plan is created, approved, started, finishes a step, or completes; a gate
opens; an unowned dependency gets an owner; or scope changes. Each update edits the
[Plan registry](#plan-registry), [Gates](#gates), [Next actions](#next-actions) and adds a line to the
[Change log](#change-log).

**Before a plan is approved**, check:

1. Every plan in its *Depends on* column is at least **Approved**, or the exact contract it uses is
   named in that plan's contracts section.
2. Its design basis has nothing it needs under "Still open" in
   [game-vision.md](../design/game-vision.md#open-and-unfinished).
3. Every [unowned dependency](#unowned-and-cross-cutting-dependencies) it touches has an owner.
4. It stays inside [MVP scope](#scope-guardrails), or the user has explicitly pulled the item in.

**Before an implementation step starts**, check its row in [Gates](#gates).

**Plan one step ahead.** A plan is drafted while the step before it is being built, never all at
once (plans written far ahead go stale) and never after the code that needs it (interfaces built
before their consumers are checked are the costliest to fix).

**Branches:** build tracks branch from `dev` as `feature/<step>` (e.g. `feature/EB9`) and merge back
into `dev`; plan and orchestrator commits go to `dev`; `main` holds released state (since October 27,
2026).

## Where we are

- **Design:** ideation closed for the MVP (design reviews of October 23–24, 2026). Remaining design
  items are content or tuning; see [Design items by plan](#design-items-by-plan).
- **Code:** the save system is built. P01 EB1–EB4, P02 CC1–CC5 and P13 R1–R4 are built, tested headless and merged into `dev` (the save system is on `main`) (combat 428, effects 532, RNG 154, save 196 tests pass).
  The combat rules (exchange, splash, Shove, staves, Pouch items, swaps, runes) run in tests; no turn loop or map yet.
- **Current milestone:** [M0 Foundations](#milestones).
- **Current focus:** P02 CC2–CC5 are built (with P01 fixes F9–F12, two-sided damage stages). The turn loop (CC6) needs P01 EB6,
  which needs the P04 draft (P08 question 1 is answered): planning is now the critical path. Builds meanwhile: EB9, a warnings fix-up.

## Milestones

The MVP is **one full run working, from the start screen to the boss, solo and co-op, on Normal**
(game-vision.md). Milestones build toward it so the first-pass numbers get playtested early.

| Milestone | Goal | Plans | Exit criteria |
|-----------|------|-------|---------------|
| **M0 Foundations** | The engine every gameplay system plugs into | P00, P01 | P00 implemented ✅; P01 EB1–EB7 implemented and verified headless |
| **M1 First playable fight** | One greybox standard combat, played start to finish, to test the core numbers | P02, P03 (starting army subset), P04 (one map), P05 (2–3 classes), P06, P07 (minimal) | A solo standard combat (Rout) with the Mercenary starting army vs a small Brigand pack, darkness included, playable with debug-grade UI; first tuning pass of Block, Stance, darkness, weight and turn par |
| **M2 Combat complete** | Every MVP combat feature and piece of combat content | P02–P07 complete | All objectives, map objects, the 10 enemy classes, 4 mini-bosses, the scripted Powder Baron map; all MVP units, weapons, staves, items, heirlooms and runes as data |
| **M3 Solo run** | A full solo run | P08, P09 | Start screen → campaign map → nodes → boss, solo, on Normal, saved and resumable; run length measured against 60–80 minutes |
| **M4 Co-op run** | The same run in co-op | P10, P11 | 2–4 players, parallel maps, reinforcements, disconnect and forfeit, per-map battle saves; tested live on two machines |
| **M5 MVP** | MVP complete | P12, polish | Statistics recording on; Waystation war table; MVP checklist in [Scope guardrails](#scope-guardrails) met |
| Post-MVP | Meta progression and beyond | P20–P24 | Not planned yet |

## Plan registry

Statuses: **Not started** · **Stub** · **Draft** · **Approved** · **In progress** (step shown) ·
**Implemented** · **Superseded**.

| ID | Plan | File | Status | Depends on | Unblocks | Design basis |
|----|------|------|--------|-----------|----------|--------------|
| P00 | Save system | [2026-10-13-save-system.md](2026-10-13-save-system.md) | **Implemented** October 14, 2026 (multiplayer paths untested live) | — | All | save-system.md |
| P01 | Event bus and effects | [2026-10-23-event-bus-and-effects.md](2026-10-23-event-bus-and-effects.md) | **In progress** (approved October 26, 2026; amended with P02's and P13's needs the same day): EB1–EB4 implemented with fixes F1–F12 (532 headless tests pass); EB9 implemented (results in P01); EB5 waits on P03, EB6 on P04 | P00 | Every gameplay plan | effects-system.md, effect-triggers.md |
| P02 | Combat core: turns and phases, action economy, the exchange, damage stages, Block, Stance, triangle, crits, Parry, Shove, staves, Pouch items, weapon swaps, runes, forecast, `CombatGrid` interface | [2026-10-26-combat-core.md](2026-10-26-combat-core.md) | **Approved** October 26, 2026 (reviewed: questions 9–12 answered, seven fixes). **In progress:** CC1–CC5 built (428 headless combat tests pass); CC6 waits on EB6; open questions 14 (CC6) and 16 | P01 (EB2–EB4, plus amendments N1–N10) | P04, P05, P06, P07 | game-vision.md Combat |
| P03 | Content catalog: unit types, traits and upgrades, the Drengr, prefixes, weapons, staves, items, ingredients, runes, heirlooms, curses | — | **Not started** (sketch before EB5; may split into units / items / heirlooms) | P01 (EB3, EB5) | M1 content, P08, P09 | unit-roster.md, weapons.md, items.md, heirlooms.md, events.md (curses) |
| P04 | Combat map: grid, terrain, pathing, deployment, objectives, reinforcement points, map objects, map authoring and its checks | [2026-10-27-combat-map.md](2026-10-27-combat-map.md) | **Approved** October 27, 2026 (13 questions answered; "within N movable tiles" cut; no prep screen); MP1–MP3 ready, MP4 wiring with P02 CC6, MP8 after EB7 | P01 (EB6), P02 | P05, P06, P07, M1 | game-vision.md Combat maps, map-objects.md |
| P05 | Enemies and AI: classes, intents, danger zone, ruthless AI, signature moves, elites, mini-bosses, the Powder Baron | — | **Not started** | P02, P04 | M1, M2 | enemy-roster.md |
| P06 | The darkness | — | **Not started** | P02, P04 | M1 | the-darkness.md |
| P07 | Combat UI and forecast: forecast panel, move preview (darkness damage), danger zone and intent display, HUD | — | **Not started** (minimal version for M1) | P02, P04, P05 | M1, M2 | game-vision.md Combat, Enemy intentions |
| P08 | Campaign and run flow: `CampaignSession` ownership, campaign map generation, nodes, rewards, Armory, Guildhall, Camp, Treasure, gold, XP and level-ups, recruiting, run end | [2026-10-24-campaign-run-flow.md](2026-10-24-campaign-run-flow.md) | **Stub** (questions 1–2 gate EB6) | P01, P03 | M3, P09, P12 | game-vision.md Run structure, Army, Units |
| P09 | Narrative events and curses | — | **Not started** | P01, P03, P08 | M3 | events.md |
| P10 | Net transport: `Net` autoload, RPCs, command validation, Steam lobby integration | — | **Not started** | P00, P01 | P11 | multiplayer-combat-options.md, `steam_multiplayer_kit/` (read first) |
| P11 | Co-op combat: parallel maps, reinforcements, rune routing, spectating, fast-forward votes, disconnects and forfeits, per-map battle saves | — | **Not started** | P01 (EB6–EB7), P02, P04, P08, P10 | M4 | game-vision.md Multiplayer maps, multiplayer-combat-options.md |
| P12 | Statistics recording and the Waystation war table | — | **Not started** | P01, P08 | M5 | meta-progression.md (MVP parts) |
| P13 | RNG streams: run seed, named streams and their derivation, co-op stream layout, save and resume in the reserved `rng` sections, determinism rules | [2026-10-26-rng-streams.md](2026-10-26-rng-streams.md) | **In progress** (approved October 26, 2026): R1–R4 built and merged (154 headless tests pass); R5 registers from `CampaignService`, so it follows P01 EB6; R6 is built with P01 EB6 | P00 | P01 EB4/EB6, P02, P04, P05, P06, P08, P09, P11 | save-system.md (`rng` sections), P01 roll sources |
| P20 | Meta progression: unlocks, difficulty ladder, almanac, Hall of Heroes, run history, achievements, Waystation stations | — | Post-MVP | P12 | — | meta-progression.md |
| P21 | Training yard and tutorials | — | Post-MVP | P07 | — | meta-progression.md |
| P22 | Dev console | — | Post-MVP (scoped when needed) | P01 | — | meta-progression.md Developer tools |
| P23 | Status effects | — | Post-MVP | P01, P02 | — | game-vision.md Status effects |
| P24 | Shared and hybrid co-op battles (Option D) | — | Post-MVP | P11 | — | multiplayer-combat-options.md |

## Dependency graph

```mermaid
flowchart LR
  P00[P00 Save ✅] --> P01[P01 Event bus]
  P01 --> P02[P02 Combat core]
  P01 --> P03[P03 Content catalog]
  P02 --> P04[P04 Combat map]
  P01 --> P04
  P02 --> P05[P05 Enemies + AI]
  P04 --> P05
  P02 --> P06[P06 Darkness]
  P04 --> P06
  P02 --> P07[P07 Combat UI]
  P04 --> P07
  P05 --> P07
  P01 --> P08[P08 Campaign + run flow]
  P03 --> P08
  P08 --> P09[P09 Events + curses]
  P03 --> P09
  P00 --> P10[P10 Net transport]
  P01 --> P10
  P10 --> P11[P11 Co-op combat]
  P04 --> P11
  P08 --> P11
  P08 --> P12[P12 Stats + war table]
  P00 --> P13[P13 RNG streams]
  P13 --> P01
  P13 --> P02
  P13 --> P08
```

## Gates

Implementation steps that must wait for another plan. A gate opens when its condition is met;
mark it **Open** here.

| Step | Waits for | Why | Status |
|------|-----------|-----|--------|
| P01 EB1 Facts and buses | P01 approved | — | **Open** October 26, 2026; implemented |
| P01 EB2–EB4 Values, blocks, engine | P02 drafted and approved ✅ (October 26, 2026); P01 amended with P02's needs N1–N10 ([combat core plan](2026-10-26-combat-core.md#what-p02-needs-from-p01-eb2eb4)): exact float values, `EffectContext` fields, inline flags, permissions, expiry boundaries, per-map charges, 2RN and one-roll methods on roll sources, a sandbox hook for `CombatState`. The phase-side gap is settled by P02 step CC1. P01 amended ✅ (October 26, 2026; [Amendments from P02 and P13](2026-10-23-event-bus-and-effects.md#amendments-from-p02-and-p13), P01 questions 17–18) | Damage stages, stat sheets, forecasts, rolls and AI simulation sit on both sides | **Open** October 26, 2026 (EB2 and EB3 built; EB4 also needed the live-rolls row below, now open) |
| P01 EB5 Catalog and content tests | P03 sketched (content kinds, `res://data/` layout) | The catalog's typed lookups and layout follow the content kinds | Closed |
| P01 EB4 live rolls (within EB2–EB4) | P13 approved ✅ (October 26, 2026); P13 R1–R3 implemented ✅ (`RngStream` is what `LiveRolls` wraps); P01 amended with P13's needs R-N1 and R-N2 ✅ (October 26, 2026) ([RNG plan](2026-10-26-rng-streams.md#what-p13-needs-from-other-plans)) | Real resolution and P02's golden-log tests need seeded streams | **Open** October 26, 2026 (R1–R3 built) |
| P01 EB6 Sessions, encounter, bridge | P04 approved ✅ (October 27, 2026; including P13 need R-N5: stable container indices); P08 question 1 (`CampaignSession` owner) answered ✅ (October 27, 2026: `CampaignService`); P13 approved and P01 amended with R-N3 ✅ (the encounter draws the whole setup once; sessions get their own streams) | Sessions carry turns, deployment, commands and the RNG injection point | **Open** October 27, 2026 |
| P01 EB7 Serialization, rejoin | EB6; P01 amended with P13 need R-N4 ✅ (run seed, build and live stream states in snapshots and repro dumps) | — | Closed |
| P02 implementation (CC2–CC5; CC6 waits on EB6) | P01 EB4 implemented ✅ (October 26, 2026) | Combat rules are effect-engine consumers | **Open** October 26, 2026; CC2–CC5 built October 27, 2026 |
| P01 EB9 Benchmark | P02 CC3 (a real `CombatState` and exchange to measure) | Sandbox creation cost means little on the fake test state; the numbers decide copy on write and the AI's branch budget | **Open** October 27, 2026 (CC3 built); implemented October 27, 2026 |
| P03 implementation | P01 EB5 implemented | Content is catalog data | Closed |
| P04 implementation | P01 EB6, P02 core turn loop | Maps run inside sessions | Closed |
| P11 implementation | P10 implemented, P01 EB7, the per-map battle save format | Co-op needs transport, snapshots and saves | Closed |

## Unowned and cross-cutting dependencies

Things more than one plan needs that no plan clearly owns yet. Each needs an owner before the first
plan that depends on it is approved.

| Dependency | Needed by | Candidate owner | Status |
|------------|-----------|-----------------|--------|
| `CampaignSession` ownership and lifecycle | P01 EB6, P08, P11, P12 | P08 (question 1): the `CampaignService` autoload, built in P01 EB6 | **Owned** October 27, 2026 |
| RNG streams manager (reserved `rng` save keys in campaign and combat) | P01 EB4/EB6, P02, P04–P06, P08, P09, P11 | **P13** (its own plan; answers P08 question 2) | Owned October 26, 2026, not started |
| Modified-item price and scrap formula (from deltas) | P03, P08, P09 | P03 (items) or P08 (question 3) | **Open** |
| Per-map battle save format (one battle state per map) | P11 | P11 | Owned, not started |
| Forfeit save change (a campaign's player count can shrink) | P10, P11 | P11 | Owned, not started |
| Archive record gains run score and ladder level (schema bump and migration) | P12, P20 | P12 (score), P20 (ladder) | Owned, not started |
| Map authoring checks (≥ 8 deployment tiles, ≥ 2 darkness source candidates, ≤ 3 powder kegs) | P04, P06 | P04 (P06 adds its check) | Owned, not started |
| Design-doc updates from P01 (EB8: Campaign triggers, Block gained, inline windows) | P01 | P01 EB8 | Owned (per-map phases already written into the design docs October 24, 2026) |

## Design items by plan

Open design items that will need an answer when their plan is drafted. None blocks the MVP plans
from starting; each is asked inside its plan's Open Questions.

| Plan | Item | Source |
|------|------|--------|
| P03 | The Ring of Favor needs a Legendary-sized effect; Heavy Brick is Unique with no source; the Lancer's growths are a `Godot_FE` copy-paste; item effects may sit outside their ported rarity's budget; Brothers in Arms needs a selector filter ("adjacent to a unit of another player") the engine doesn't have (P01 question 30) | items.md, unit-roster.md, heirlooms.md |
| P08 | Personal XP for "gave Block" ignores `BLOCK_GAINED` facts with amount 0 (P01 question 24) | P01 |
| P08 | Re-gearing at Camps (user, October 27, 2026: no combat has a prep screen; the map before the boss has a Camp); decide whether army management stays available anywhere else on the campaign map, given the goal of less menuing | P04 question 4 |
| P04 / P06 | Turn par and reinforcement timers per map are set when maps are authored; darkness values on small maps need M1 playtesting | game-vision.md, the-darkness.md |
| P07 / P08 | Show the run seed on the pause screen (P07) and the results screen (P08), formatted by `RunSeed.format()` (P13 R4 follow-up) | P13 |
| P12 | Whether runs abandoned by the save debug panel's "New Solo Run From Seed" count as lost runs in statistics | P13 R4 |
| P04 | Tile coordinates are never negative (P01 question 37, `CombatFact.NO_TILE`); implement `CombatGrid.walking_distance(a, b, movement_type)` for "within N movable tiles" (P02 question 13), and settle whether other units block it and whether terrain cost counts (recommended: units don't block, each step counts 1) | P01, P02, effect-triggers.md |
| P05 | The Brigands' real name and theme (flavor only) | enemy-roster.md |
| P05 | The AI's branch budget and whether sandboxes become copy on write or lazy, from P01 EB9's results (exact `ExchangeOutcome` is about 2 ms per branch; one exchange reads 2–3 of 11 units); measure a release build first | P01 EB9 |
| P07 | `Godot_FE`'s ranged multi-tile forecast defect (FR-GRID-6) to investigate | P01 contracts |
| P11 | Light links beyond runes on a teammate's map | multiplayer-combat-options.md |
| Vision (ideation thread) | Pending updates from the October 27 orchestrator decisions: turn par is set by hand per map with no target range, small combats well below the current figures (which also disagree: boss "14–18" vs "10–14", ladder −1 vs "Hard −1"); no battle prep in any combat, automatic deployment with an opening swap; Camps allow re-gearing ("gear moves only in army management and battle prep" and Camp's "choose one" change); "within N movable tiles" cut | P04 questions 4 and 12 |

## Scope guardrails

**In the MVP** (game-vision.md): one act, one faction (Mercenary), one commander (the Drengr), Normal
only, the 14 MVP unit types, 10 enemy classes, 4 mini-bosses, the Powder Baron, the full item,
weapon, heirloom, rune and event pools, the darkness, solo and co-op on parallel maps, statistics
recording and the Waystation war table.

**Out of the MVP** (stop and ask before any plan touches these): meta progression (unlocks, the
difficulty ladder, almanac, Hall of Heroes, run history, achievements, the other Waystation
stations), endless runs and later acts, more bosses, the Mage Tower and Kingdom factions and the
other commanders, status effects and status staves, the Ballista and War Drum, darkness extras
beyond the Brazier, support weapons beyond staves, one- and two-handed weapons, unique equipment,
more enemy factions, units with convoy access, shared and hybrid co-op battles, the dev console.

**Focus rules**

- A plan that grows past its row's scope splits into a new row here, not a bigger plan.
- A gameplay value with no basis in the design docs or `Godot_FE/` is a design question, not an
  implementation choice: it goes back to the design docs first (CLAUDE.md §1).
- M1 comes before breadth: content beyond the M1 subset waits until the first playable fight has
  been tuned once.

## Next actions

1. Build P04 MP1–MP3 (terrain and layout; grid, state and pathing, removing `walking_distance` and
   `MOVABLE`; automatic deployment) on `feature/P04-MP1-MP3`, then MP5 (the M1 greybox map and the check).
2. Build P01 EB6 (sessions, encounter, bridge, `CampaignService`), now open; then P02 CC6 (turn loop)
   and P13 R5–R6. EB6 and MP1–MP3 touch different files and can run side by side.
3. Sketch P03 (content catalog), which opens EB5.
4. Vision updates pending for the ideation thread (Design items by plan).

## Change log

| Date | Change |
|------|--------|
| October 25, 2026 | Created. Registered P00–P12 and post-MVP P20–P24, milestones M0–M5, step gates for P01, unowned dependencies and scope guardrails. |
| October 26, 2026 | P01 approved; EB1 gate opened and EB1 implemented (51 headless tests pass). Fact contract settled: paired triggers as two facts, `CombatFact.DamageType`, effect-instance ids in `source_effect_id`, minimal `CampaignFact`. Phase-side gap handed to P02. |
| October 26, 2026 | P02 Combat core drafted, 8 questions answered (bonus turns uncapped, exact-then-round-once damage, one-roll crits, `Godot_FE` counter rule, shove only if it does something; grid interface, all non-map actions, ordered turn-loop hooks). Its 10 needs from P01 added as the EB2 gate condition. Vision updated (bonus turns, terrain DEF/RES in mitigation). |
| October 26, 2026 | P13 RNG streams registered (the unowned RNG manager); gates EB4 (stream interface) and EB6 (injection); answers P08 question 2. |
| October 26, 2026 | P13 RNG streams drafted: keyed per node and running within, shared world with per-seat rewards and event outcomes (chest loot per seat), Godot PCG32 with our SplitMix64 key derivation, 52-bit run seed shown and debug-enterable, same-build determinism. Its save sections wait on P08 question 1. |
| October 26, 2026 | P13 readiness check: fixed a co-op divergence (shared streams are drawn once at setup, reinforcement waves pre-drawn), corrected the `BATTLE_RETRY` mechanism (streams re-derived from keys), and listed P13's needs from P01, P04 and P08 (R-N1–R-N6); EB4 and EB6 gates now include them. |
| October 26, 2026 | P02 review: Unit Turn Start moved into the Phase Start window (per unit, after refresh and Phase Start effects, before control, as `Godot_FE`'s beginning phase); Breaker's extra Stance loss only when damage gets through. Fixes: units start with full Stance when placed; movement cost for "remaining movement" and a `MOVEMENT` key; Spark through a P04 `OBJECT_OPERATIONS` hook and Recall as a P02 operation; Attack Speed and Pouch weight stated; mid-phase save fields; `ExchangeOutcome` owned by P01 only; `BLOCK_LOST` fact kind; RNG ownership pointed at P13. Question 11 (Unit Turn End) open. Vision and effect-triggers.md updated. |
| October 26, 2026 | P02 question 11 answered: Unit Turn End fires per unit in the Phase End window, mirroring Unit Turn Start. P02 has no open questions and is ready for approval. |
| October 26, 2026 | **P02 Combat core approved.** CC1 (fact amendments) may start now; the rest of P02 waits on P01 EB4. Next: amend P01 with N1–N10 and R-N1–R-N4 to open EB2–EB4. |
| October 26, 2026 | P02 approval verified against the orchestrator checklist (dependencies, design basis, unowned dependencies, scope): approval holds. Question 12 added: Phase End and Unit Turn End effects resolve before darkness damage (vision, the-darkness.md and the plan updated). |
| October 26, 2026 | **P13 RNG streams approved** after review fixes: `TEAM_CHOICE` purpose for team-vote draws, per-seat `ENCOUNTER_SETUP` for per-player additions (Hunted), SplitMix64 in 16-bit limbs with masked shifts, integer weights, starting-heirloom follow-up draws. Rule added to `.claude/rules/gdscript.md` §8.5 (gameplay randomness only from an `RngStream`). R1–R3 may start now. |
| October 26, 2026 | **P01 amended** with P02's N1–N10 and P13's R-N1–R-N4 (new section "Amendments from P02 and P13"; EB2, EB4, EB6 and EB7 rows updated). P01 questions 17–18 answered: values exact, rounding once per key (default halves up); a "next attack" modifier is spent by any attack, counters and misses included. Timed modifiers got ends, uses and a boundary call; roll sources got `roll_hit_2rn` / `roll_percent` / `pick_index` on `Godot_FE`'s 0–99 d100; `SandboxState` hook. **EB2–EB3 gate open**; EB4 waits on P13 R1–R3. |
| October 26, 2026 | **Track A built** on `build/p01-eb2-eb3-cc1`: P01 EB2, EB3 and P02 CC1 (217 headless tests pass). The build found four gaps, answered as P01 questions 19–22: Unshovable becomes a denial of `CAN_BE_SHOVED` (F1); `CombatFact.item_id` appended, rune caster's seat in `amount`, runes get instance ids (F2); base stat keys and a `Stat` enum in EB4 (F3); `CommandTarget`, extra Stance loss and `WhileMatchupCondition` blocks in EB4 (F4). Corrected the amendment's stat list (Luck was cut). F1–F2 are fix-ups before merge. |
| October 26, 2026 | **Track B built**: P13 R1–R3 (126 headless tests pass), on `build/p13-r1-r3` after Track A and its F1–F2 fix-up (229 pass). Reviewed the build's decisions and recorded them in P13: the mixer's chaining rule, numeric save keys, purposes 0–13, the section split, all-or-nothing restores, `floor_number`, the added constructors and `from_save_key()`. Stream-creation logging and the "shared purpose drawn once" test move to their owners (R6: P01 EB6 and P08). **EB4 gates open.** |
| October 26, 2026 | **P01 EB4 parts 1–2 built** on `build/p01-eb4` (engine core, block runtime, F3–F4, golden fact logs for the 15 fixtures). Reviewed the build and recorded P01 questions 23–33 and fixes F5–F8: authored condition order; a 0 Block gain is still a fact; `STAT_CHANGED` and a `key` field (lane, stat); Vanguard passes with no enemy; map-object reactions exempt from both caps by owner kind; Momentum lands at the After Combat drain and stacks; one heal path with `HEALING_RECEIVED_PERCENT`; effects fire once per fact; the session reports engine diagnostics (EB6); `CampaignValue.DEFAULT_BASES`; dormant carriers (defeated units, stowed weapons); `SandboxState`'s 17 methods as the contract with P02's `CombatState`. P02 updated (splash and Momentum timing, heal path, `CombatState` contract, stowed weapons). Sandbox cost is unmeasured until EB9; copy on write only if EB9 misses its budget. |
| October 26, 2026 | **P01 EB4 implemented** and merged into `feature/save-system` (parts 3–5: roll sources, the sandbox and `ExchangeOutcome`; cached stat sheets with fact-driven invalidation and verify mode; the `rng_key.gd` markers; F8 dormant carriers). Effects 490, RNG 126 and save 196 headless tests pass. P02 CC2–CC5 gate opened; new gate: EB9 waits on CC3. P01 questions 34–37 opened for the assumptions left in code. |
| October 27, 2026 | P01 questions 34–37 answered as recommended (conditional expected damage before defeat; forecast random picks marked random; sampled-roll encoding as built; the four EB1–EB2 assumptions confirmed, P04 owns non-negative tiles). Preparing CC2 found that `CombatGrid` has no walking distance although "within N" uses one: P02 question 13 opened with a recommendation (`CombatGrid.walking_distance`). CC2–CC5 and R4 build prompts issued. |
| October 27, 2026 | P02 question 13 and P01 question 38 answered by the user: two distance terms the effect picks, "within N tiles" (grid distance, ignoring walls) and "within N movable tiles" (`CombatGrid.walking_distance` with the source's movement type). effect-triggers.md updated; P01 fix F9 (a distance mode on `Area` and `WhilePositionCondition`) goes into CC2's cleanup step. P04 settles whether units block movable distance. |
| October 27, 2026 | **P02 CC2–CC5 built** on `build/p02-cc2-cc5` with three fix-ups (P01 fixes F10–F12: area staves through `Area.Center.COMMAND_TARGET`, growth changes and `GROWTH_CHANGED`, two-sided damage stages with `INCOMING_MULTIPLIERS` and `WhileAttackCondition`; `SandboxState` now 21 methods). Verified headless: combat 428, effects 532, RNG 126, save 196. User decision (P01 question 39, P02 question 15): defenders can change the damage they take, for future content. Opened P02 questions 14 (staff with no range, CC6) and 16 (rule bases in a default table). EB9 gate opened. |
| October 27, 2026 | **P13 R4 built** (run seed: `RunSeed` generate, format and parse; typed and command-line debug seeds; the save debug panel's seed field) with its four questions confirmed as built. Merged: `feature/save-system` fast-forwarded to Track C (P02 CC2–CC5) and R4 merged on top; combat 428, effects 532, RNG 154, save 196 headless tests pass, and the debug panel loads headless cleanly. CLAUDE.md §3 now says how to check scripts that use autoloads (`--check-only` can't). Design items added for P07/P08 (seed display) and P12 (debug restarts in statistics). |
| October 27, 2026 | Branching changed by the user: `feature/save-system` merged to `main`; `dev` is the integration branch, and every track branches from it as `feature/<step>` and merges back into it. |
| October 27, 2026 | P08 question 1 answered: a new `CampaignService` autoload owns `CampaignSession` (host session, client mirror), `RngStreams`, the id allocator and their save sections, and builds the session on a new `SaveService.campaign_activated` signal; built in P01 EB6, so P13 R5 follows EB6. P02 question 16 answered: combat rule bases move to a constants table (warnings fix-up). EB6 now waits only on the P04 draft. |
| October 27, 2026 | **GDScript warnings fix-up and P01 EB9 merged into `dev`** (verified merged: combat 434, effects 532, RNG 154, save 204; the bench passes its checks). The six warning settings are Error in `project.godot`; combat rule bases live in default tables (P02 question 16). EB9: sandbox 0.9 ms, player forecast 1.9–2.6 ms, exact `ExchangeOutcome` 7 ms / 32 ms / 1.45 s for 2 / 4 / 8 attacks (debug build); the branch budget and copy on write go to P05. Next: the P04 draft. |
| October 27, 2026 | **P04 Combat map drafted** ([2026-10-27-combat-map.md](2026-10-27-combat-map.md)). Answers before drafting: scene + definition converted to a pure layout; `Godot_FE` movement rules; "within N movable tiles" follows the source's movement; **automatic deployment by role, on by default, with an opening swap; the prep screen only for key and boss combats** (user); objective rules; timed reinforcement points with **distinct arrival markers and warnings** (user, two new fact kinds); object attacks **through the normal exchange flow and facts** (user); objects, enemy slots, `entities` + new `combat_map` sections, terrain owned by P04. Found drafting: the shared grid can't see units or object state (question 12, recommended: move those queries into `CombatState`, a P02 interface change). Flagged, not edited: the vision's two turn-par values, and question 4 narrowing "gear moves in battle prep". EB6 now waits on P04's approval. |
| October 27, 2026 | **P04 Combat map approved** after review. User decisions: "within N movable tiles" is **cut** (every "within N tiles" is grid distance; P04 MP2 removes `walking_distance` and P01 F9's `MOVABLE`; P01 question 38 and P02 question 13 reversed; effect-triggers.md updated); a reinforcement point with no waves left counts as closed; turn par set by hand per map; **no prep screen in any combat**, re-gearing at Camps (P08), the automatic-deployment setting dropped. `CombatState` still takes `validate_path` and object-aware blockers (needed for movement). **P01 EB6 gate opened.** Vision updates queued for the ideation thread. |
