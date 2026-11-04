# Plan: The Darkness
**Date:** November 3, 2026
**Status:** **Approved** November 3, 2026 (questions 1–10 answered as recommended). **In progress:** DK1 merged November 4, 2026 (e4ac466; question 11); DK2 next. Orchestrator ID **P06**
([game-orchestrator.md](game-orchestrator.md)).

The turn-par pressure system: from turn par on, darkness flows from authored sources toward a drain
in waves, deepening tiles through Dusk, Gloom and Abyss, and damages any unit that ends its side's
phase on a dark tile. One staged plan: the M1 part (DK1–DK4) first, then its save section and docs.

## Problem

M1 needs "darkness included" (orchestrator, M1 exit criteria), and several built systems wait on it:
`CombatState.darkness_layer()` answers DRY for every tile (`combat_state.gd:TOD-001`), nothing sets
`MapState.has_darkness_arrived` (`reinforcements.gd:TOD-001`, `TOD-003`), the enemy AI never sees a
flooded tile (`enemy_ai.gd:TOD-003`), setup step 3 (`DARKNESS_SOURCES`) has no registration,
`MapCheck` reserves the darkness-source rule, and the M1 greybox map (turn par 5) has no source
markers. The hooks P02 left for it exist: `TERRAIN_HEALING_ALLOWED`, `PHASE_END_EFFECTS`,
`AFTER_ENEMY_PHASE`, and the fact kinds `DARKNESS_DAMAGE_TAKEN` (21) and `DARKNESS_ADVANCED` (29).

## Open Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | Plan shape and the M1 subset | One staged plan / several | **One staged plan:** DK1–DK4 for M1 (state and flow, setup and the map rule, the darkness step, damage and its readers), DK5 the save section after P04 MP8, DK6 docs. Erosion and the Brazier are in DK3: they are small and the M1 map may carry breakables | **Answered November 3, 2026 (user):** as recommended. |
| 2 | A door that opens or closes (lever, lockpick) | Flow ignores doors after setup / recalculated like a break | **Recalculated both ways, like a break:** an open door is floodable floor, a closed one blocks like a wall (the-darkness.md, Terrain). Closing a door never removes a layer (the darkness never recedes): the tile keeps its layer and stops passing flow | **Answered November 3, 2026 (user):** as recommended. |
| 3 | A Brazier doused after waves entered its tiles | Tiles jump to their true count / the cap is applied as waves enter | **Applied as waves enter:** a wave entering a tile within 2 of a lit Brazier deepens it no further than Dusk, and that entry is spent (a wave enters a tile once). Dousing it later deepens nothing by itself; only later waves deepen those tiles. "Within 2" is grid distance (P04 question 12) | **Answered November 3, 2026 (user):** as recommended. |
| 4 | What the darkness records as facts (mirrors replay them; P07 animates them) | One fact per step / one per tile change | **One `DARKNESS_ADVANCED` per tile that deepens:** `tile`, `amount` the new layer, `key` the source index that released the wave. A wave release and the first release (arrival) are also `DARKNESS_ADVANCED`, told apart by a flag bit. Erosion uses `OBJECT_STATE_CHANGED` with appended `MapObjects.Change` values (contact, broken by the darkness). This fixes a payload meaning: a fact contract change, stated now so it is approved with the plan | **Answered November 3, 2026 (user):** as recommended. |
| 5 | Order on the player Phase End: darkness damage and P04's point closing (both on `PHASE_END_EFFECTS`) | Damage first / closing first | **Closing first:** the unit ended its turn on the point, which is what closes it; the darkness then applies. A unit the darkness defeats still closed the point | **Answered November 3, 2026 (user):** as recommended. |
| 6 | Where darkness state is saved | P04's `combat_map` (it already offers "active darkness sources unless P06 takes them") / its own section | **Its own COMBAT section `darkness`, version 1** (DK5, after P04 MP8): active sources, drain, each wave's source and reach, each tile's layer, each breakable's contact count, whether it has arrived. One state per map, as for `combat_state`; registered from `CampaignService` like CC8's sections; restored by P02 CC10 | **Answered November 3, 2026 (user):** as recommended. |
| 7 | How a source's tiles are grouped, and the M1 map's sources | One marker per tile / markers sharing a candidate id | **Markers with the same `group` form one candidate**, as enemy slots group. The M1 greybox map gets 2 candidates behind and beside the deployment zone (the-darkness.md, Authoring guidelines), shown to the user in the DK2 report | **Answered November 3, 2026 (user):** as recommended. |
| 8 | "Next to" for erosion | 4-directional / 8-directional | **4-directional**, like the flow and walking distance | **Answered November 3, 2026 (user):** as recommended. |
| 9 | Units arriving while the darkness is on the map (co-op sent units now; enemy waves stop at arrival) | Placement ignores the darkness / prefers dry tiles | **Prefers dry tiles, then the lowest layer** (the-darkness.md, Co-op): `CombatEncounter.deliver_arrivals` and the P04 free-tile search take a dry-first order once the darkness has arrived | **Answered November 3, 2026 (user):** as recommended. |
| 10 | What "a tile at least one movement type can stand on" means for floodable tiles (orchestrator design item from P04 MP6, whose `MapObjects.blocks_darkness` already reads it one way, marked `# ASSUMPTION`) | Any movement type / every movement type but Flier | **Every movement type but Flier, as MP6 built it:** fliers can stand on walls, and walls must block the darkness. Erosion matches already: P06 counts contacts and calls `MapObjects.erode` at the limit, which breaks the object (a keg explodes) | **Answered November 3, 2026 (user):** as recommended. |
| 11 | Found building DK1 (November 4, 2026; merged e4ac466): (a) within a step a wave enters tiles nearest first (flow cost), ties row-major; waves oldest first, then by source index (`# ASSUMPTION`; it becomes DK3's fact order); (b) on a 4-directional grid neighbours' heights always differ by 1, so "level" happens only next to a tile with no height and sideways spread costs 3 (uphill): built as written, a tuning note; (c) DK5 must save each wave's entered tiles, not only its source and reach, or a restored wave re-enters tiles after a door closes; (d) two arrival flags: `DarknessState.has_arrived()` (derived) and `MapState.has_darkness_arrived` (read by `Reinforcements`, still never set); (e) a full recalculation on M1 takes 2.3 ms median (debug, measured); (f) the confirmed `# ASSUMPTION` on `MapObjects.blocks_darkness` (question 10) is still in place | Accept / change each | **(a), (b), (e) accept** ((b) to the M1 tuning pass). **(c)** DK5 saves entered tiles. **(d)** DK3 sets `MapState.has_darkness_arrived` at the first release, the one flag `Reinforcements` and the AI read. **(f)** DK3 removes it when it changes `map_objects.gd`. Also from P05's EN4F: `PHASE_END_EFFECTS`, `AFTER_STEP` and `ENEMY_COMMANDS` registrations run on a stand-in session for intents, so the darkness acts only through the session it is handed | Open (asked November 4, 2026); the DK2 prompt builds on the recommendations |

Decided in the design docs, so not asked: the first-pass values (Values, below); percent-of-max-HP
damage that is **not an attack** (no damage stages, no Block, no Stance loss, only the Darkness
damage taken trigger; this differs from splash, which Block absorbs); damage at each side's own
Phase End after Phase End and Unit Turn End effects (combat core plan, question 12); arrival at the
first release turns enemies aggressive (P05 question 15) and stops reinforcement points; no immune
unit; the map never ends because of the darkness; Survive and Defend maps have none.

## Scope

**In:** source candidates and the active pick; the drain per objective; heights, step costs and flow
costs; waves, creep and layers; the darkness step (creep, release, erosion) on
`AFTER_ENEMY_PHASE`; arrival (the flag, AI and reinforcements); damage at Phase End; healing terrain
stopped on flooded tiles; the Brazier's cap; flow recalculated when a breakable breaks or a door
changes; Short Wick (`CampaignValue.DARKNESS_ARRIVAL_OFFSET`); `darkness_layer()` for effects
(`WhileLayerCondition`) and the sandbox; the AI's flooded tiles; dry-first arrival placement;
queries for P07 (the move preview's damage number, the tiles that change at the next step, each
source's counter); the map check's source rule and the M1 map's sources; the save section; docs.

**Out:** drawing any of it (P07); co-op map status screens and sending (P11); bosses and mini-bosses'
drains until they are marked (P05 EN7; until then those objectives use the slot P04 MP4 treats as
the boss); darkness-reward effects and torches beyond the Brazier (future, the-darkness.md); other
damage models (the-darkness.md, Open questions: playtesting decides).

## Design Basis

- **the-darkness.md:** every section; it is the whole design. Values come from its Values table
  (first pass, tune in playtesting).
- **game-vision.md:** Combat (the turn, Phase End, triggers), Combat maps (sources, objectives, turn
  par, reinforcements), Enemies (aggressive after arrival), the change log entries of October 20 and
  23, 2026.
- **effect-triggers.md:** Unit Turn End before darkness damage; Darkness damage taken; While on a
  layer.
- **master-ideation.md:** no darkness section (the darkness was adopted after it froze).
- **Plans:** P02 (Phase End order, question 12; the hooks), P04 (objectives, map objects, the
  Brazier, breakables, reinforcement points, questions 12 and 24), P05 (questions 15 and 21), P13
  (`ENCOUNTER_SETUP`), P01 (`SandboxState.darkness_layer`, `ModifyThat` "that darkness damage").

## Legacy Behavior (ports from Godot_FE only)

None: `Godot_FE/` has no darkness, fog or turn-par pressure system (searched). Everything here is
new, from the-darkness.md.

## Approach

### Shape

```
data: CombatMapDefinition.turn_par, MapLayout DARKNESS_SOURCE markers (group = candidate)
Setup step 3 (ENCOUNTER_SETUP)   → active sources (standard 1, key and boss 2), the Rout drain tie
DarknessFlow (pure, static)      → floodable tiles, heights, flow costs per source
DarknessState (on MapState)      → waves (source, reach), layer per tile, contacts, arrived
AFTER_ENEMY_PHASE (first)        → the darkness step: creep, release, erosion → facts
PHASE_END_EFFECTS                → damage to that side's units on flooded tiles (after point closing)
TERRAIN_HEALING_ALLOWED          → false on a flooded tile
Queries                          → darkness_layer(), flooded tiles (AI), damage_at (P07), next step
```

### Flow

Floodable tiles are those at least one movement type can stand on, minus walls, closed doors and
unbroken breakables. Height is the 4-directional walking distance to the drain over floodable tiles
(none if unreachable). Step costs: downhill 1, level 2 (or either tile without height), uphill 3.
A tile's flow cost for a source is the cheapest total from any of that source's tiles. A wave's
reach starts at 0 and grows by the creep speed each step; it enters each tile within its reach once,
deepening it one layer (to Abyss at most; a lit Brazier caps entries within 2 tiles at Dusk,
question 3). A break or door change recalculates heights and flow costs, and every wave enters the
tiles now within its reach (question 2). Pure, static and deterministic: maps are at most 10×8, so a
full recalculation is cheap (measured in DK1).

### The darkness step

The first registration on `AFTER_ENEMY_PHASE`, before P04's `Reinforcements.arrive`
(`reinforcements.gd:TOD-001`). In order: creep, release (if a wave is due), erosion (each breakable
4-adjacent to a flooded tile gains a contact; at the limit it breaks through `MapObjects`, which
recalculates flow). The first wave is released at the end of the turn before turn par (plus Short
Wick's offset); that release is arrival: `MapState.has_darkness_arrived` is set, so
`Reinforcements` stops sending and the AI turns aggressive. Every change records its facts
(question 4).

### Damage and readers

At each side's Phase End (`PHASE_END_EFFECTS`, after P04's point closing, question 5), each unit of
that side on a flooded tile takes its layer's percent of max HP, rounded down, minimum 1, through
the effect engine as darkness damage (no stages, no Block, no Stance loss; `DARKNESS_DAMAGE_TAKEN`;
"that darkness damage" modifiers apply). Healing terrain doesn't heal on a flooded tile.
`CombatState.darkness_layer()` and the sandbox copy answer from the state, so forecasts and
`WhileLayerCondition` see it. The AI reads flooded tiles (`enemy_ai.gd:TOD-003`). P07 gets
`damage_at(state, unit_id, tile)` for the move preview, the tiles the next step will deepen, and
each source's counter (turns to arrival, then to the next wave).

## Save Impact

New COMBAT section **`darkness`**, version 1, one per map (question 6; DK5, after P04 MP8): active
sources, the drain, each wave's source index and reach, each tile's layer, each breakable's contact
count, and whether the darkness has arrived. Plain JSON, ids and tiles as strings, enums as string
ids (save-system.md data rules). Heights and flow costs are derived, never saved. Setup step 3 is
re-derived from `ENCOUNTER_SETUP` on a restart from Begin. Until DK5, a Save & Quit mid-battle
loses the darkness state (P02 CC10 isn't built either, so nothing resumes a battle yet).

## Work Breakdown

| Step | Files | What | Risk | Needs | Verification |
|------|-------|------|------|-------|--------------|
| DK1 State and flow | `scripts/map/darkness_flow.gd`, `darkness_state.gd`; changes in `map_state.gd`, `combat_state.gd` (`darkness_layer`, TOD-001), the sandbox copy; `tests/darkness/` | Floodable tiles, heights, step and flow costs, waves and layers, the Brazier cap, recalculation; the queries | 🟡 touches P02's state | Approval | Golden heights and flow costs on fixture maps (a corridor, a side room, a wall, a door, a breakable); layers after N steps; a recalculation after a break; `darkness_layer()` in a forecast equals execution |
| DK2 Setup and the map rule | `scripts/map/darkness_setup.gd`; registration in `campaign_session.gd`; `map_check.gd`; `maps/standard/m1_greybox.tscn` | Step 3: active sources (standard 1, key and boss 2), the drain per objective with the Rout tie from `ENCOUNTER_SETUP`, Short Wick; the rule "a map with turn par has at least 2 source candidates"; M1's 2 candidates | 🟡 setup order and a map edit | DK1 | The same seed picks the same sources and drain twice; a restart from Begin picks them again; bad fixtures fail the new rule; the M1 map passes |
| DK3 The darkness step | `scripts/map/darkness.gd`; changes in `reinforcements.gd` (TOD-001, TOD-003), `map_objects.gd` (erosion, door changes), `combat_fact.gd` docs | Creep, release, erosion and breaks; arrival and its flag; facts (question 4) | 🔴 fact contract | DK2 | Golden fact logs: first release at the end of turn par − 1, a wave every 2 turns, creep 2 per turn; erosion breaks a wall after 3 contacts and opens a lane; no reinforcement after arrival; the AI turns aggressive |
| DK4 Damage and readers | `darkness.gd`; changes in `enemy_ai.gd` (TOD-003), `combat_encounter.gd` and P04's free-tile search (question 9) | Phase End damage, healing stopped, the AI's flooded tiles, dry-first arrivals, P07's queries | 🟡 touches P04 and P05 | DK3 | 10/25/50% damage, floor, minimum 1; a Phase End heal lands first; a unit passing through takes none; a commander defeated by it ends the battle as any defeat; "that darkness damage" −50% halves it; an enemy picks a dry tile when one serves; a headless M1 battle past turn par stays deterministic |
| DK5 Save section | `scripts/map/darkness_save_section.gd`; registration in `campaign_service.gd` | `darkness` (question 6) | 🔴 save format | DK4, P04 MP8 | Save & Quit after arrival, then resume: the same layers, waves and fact log; a newer version and version 0 refused |
| DK6 Docs | `docs/design/the-darkness.md` pointers, P04's map-authoring doc (MP9) | How to author sources and check the flow | 🟢 | DK2 | Review |

M1 needs DK1–DK4.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| `DARKNESS_ADVANCED` payload and a flag bit; `MapObjects.Change` values appended | Fact contract | Kind defined, no payload | Question 4 | Proposed | `combat_fact.gd`, mirrors, P07 | 🔴 |
| `CombatState.darkness_layer()` | Behavior | Always DRY | The tile's layer | Proposed | effects (`WhileLayerCondition`), forecasts, the AI | 🟡 |
| Setup step 3 registered | Behavior | Nothing drawn at step 3 | Active sources and the drain from `ENCOUNTER_SETUP` | Proposed | `campaign_session.gd`; shifts later setup draws on the shared stream (intended setup order) | 🟡 |
| Reinforcements stop and the AI turns aggressive at arrival | Behavior | Flag never set | Set at the first release | Proposed | `reinforcements.gd`, `enemy_ai.gd` | 🟡 |
| New COMBAT section `darkness` | Save format | — | Version 1 (DK5) | Proposed | `campaign_service.gd`, save-system.md | 🔴 |

## Verification

Each step's row above, plus: the full runner (`sh bandit-bash/tools/run_tests.sh`) clean after each
step, no exit leak; a new `tests/darkness/` suite found by the runner; every existing suite still
passes (tests that assumed DRY tiles or a never-arriving darkness are listed when changed). The
playtest watch list in the-darkness.md (arrival frequency, crossing speed on small maps) is M1's
tuning pass, not a build check.

## Rollback

DK1–DK4 add new files plus registrations and small changes in P02, P04 and P05 code; reverting the
merges restores the always-dry map. DK5 adds a save section: a file saved with it follows
save-system.md's rule for a section a build doesn't know, and the battle restarts
from Begin.
