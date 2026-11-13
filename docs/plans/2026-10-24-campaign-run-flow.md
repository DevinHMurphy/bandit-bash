# Plan: Campaign and Run Flow
**Date:** October 24, 2026; drafted November 9, 2026
**Status:** **Approved** November 12, 2026 (user). Orchestrator ID **P08**

## Problem

A run today is one battle. `battle_screen.gd` builds the faction's starting army itself and passes a single map (lines 112–122), and a finished battle goes straight to Results (line 183). Nothing owns the run between battles: there is no campaign map, node, reward, XP, gold or saved roster. `CampaignSession.receive_grant` records grants and applies none (TOD-001). M3 needs all of it.

## Open Questions

None open. Questions 1–13 are answered in [decisions/P08-campaign-run-flow.md](decisions/P08-campaign-run-flow.md).

## Scope

**In:** the run from pressing Start to its end, for solo: run start, the campaign map and route, every node's rules and functional screen, rewards, gold, XP, the Standout, level-ups, permadeath bookkeeping, the battle bridge's real inputs and outputs, and all of it saved and resumable. Per-seat state and headless-tested co-op rules (question 11).

**Out:** event content and curses' offers (P09; this plan resolves Unknown nodes and hands events off); the co-op screens and transport (P10, P11); statistics and the Waystation (P12); the screens' final look (the user designs them later); enemy and item content (M2).

## Design Basis

game-vision.md: Run structure, Army, Units (Experience, Upgrades, Inventory), Run-wide resources, Co-op ownership. master-ideation.md: the matching sections. heirlooms.md (Tiers and sources, Starting heirlooms). items.md (Scrapping, Ingredients). unit-roster.md (Upgrades, Recruiting and item transfer). multiplayer-combat-options.md. save-system.md.

Nothing this plan needs is under "Still open". The economy, map weights and XP amounts are under "Tune in playtesting" and safe to build as written.

**For the vision (ideation thread):**

- "Army management and battle prep" (Army, Inventory, No trading in combat) becomes placement when an item is gained, plus re-gearing at Camps (question 6).
- Camp's "choose one" no longer covers re-gearing.
- The map's every-path minimums become targets that guide generation rather than guarantees (question 5).
- "Never directly connected" means the same kind (question 4).
- Item picks are one slot kind each (question 7). Key combats roll better item odds than Standard, and picks carry a rising Rare chance (question 13); the vision gives both the Standard odds.

## Legacy Behavior

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---|---|---|---|
| `campaign_map/map_generator.gd` | Grid, non-crossing walks from up to 6 starts, boss funnel | **Keep** | The vision ports it, at 18 floors × 7 columns |
| `map_generator.gd` | Room types by weight, global RNG | **Change** | The vision's weights and rules; its own seeded stream |
| `scripts/Unit/unit.gd:214` | A growth of G% gives floor(G/100) plus one roll of the remainder | **Keep** | The vision is silent on the roll |
| `unit_experience_manager.gd` | XP over 100 carries to the next level | **Keep** | The vision's 100 per level |
| `unit_experience_manager.gd` | Level-up pop-ups in combat, level caps | **Drop** | After combat, on results; no cap |
| `treasure.gd:131` | Uniform item pick (a bug) | **Drop** | The vision's chest odds |
| `campaign_map.gd` | Choosing a room locks its floor; the graph is saved | **Keep** | The vision's route rule |

Tuning values carried over: 7 columns and 6 paths (`map_generator.gd`), 100 XP per level (`unit_experience_manager.gd`). All others come from the vision.

## Approach

**Shape.** Pure rules in `scripts/campaign/`, with one functional screen per node in `ui/campaign/`. `CampaignSession` gains a `RunState`; screens read it and issue commands.

| Piece | Job |
|---|---|
| `CampaignGraph`, `CampaignMapGenerator` | The saved node graph and how it's made |
| `RunState`, `SeatRun` | Floor and node; each seat's gold, roster, fallen units, convoy, heirlooms and runes |
| `RunFlow` | Where the run is: on the map, or which stage of which node |
| `CombatGrades`, `XpAward`, `LevelUp` | What a finished combat pays |
| `Offers` | Rolled and saved stock for rewards, Armory, Guildhall and Treasure |
| Campaign commands | Validated, first arrival wins, a rejection costs nothing (P01), emitting `CampaignFact`s |

**Map.** Follows the vision's shape and fixed rows, rolled floor by floor from the `MAP_GENERATION` stream.

- **Hard rules,** never broken: the fixed rows; the floor limits (no Camp or extra Key before floor 6, no Shop before 3, no Camp on 16); no two of the same kind in a row, with Armory and Guildhall as one kind; a node's children differ, except on fixed rows; at most 4 Key combats and 5 Camps on any path. A roll that breaks one is rolled again. The caps can be checked as each node is rolled, because its parents are already set.
- **Soft targets,** which guide rather than guarantee: on every path an Armory, a Guildhall, 2 Treasures and 2 Camps. While some path through a node is still short of a target, that type's weight rises for the node, so most paths meet the targets and none is forced.
- **Data:** weights, fixed rows, targets and the boost size live in `data/campaign/`. RN1 measures how often a path misses each target across 10,000 seeds, then proposes the boost's first value for the user to approve.

**The loop.** Choosing a node locks its floor and saves. Then:

- **Combat:** `RunState` builds the real `BattleRequest`, with the army from the roster and the map drawn from the pool for the node's combat type and step. On a win, Results shows grades and gold, the item pick (and a Key combat's heirloom), XP, the Standout and level-ups together, then returns to the map.
- **Loss:** in solo, the run ends at once through `end_run(false)`.
- **Treasure, Camp, Armory, Guildhall:** as the vision and question 6 say. Hand-over screens follow unit-roster.md.
- **Unknown:** rolled on entry with the vision's rising odds, kept in `RunState`. An event hands off to P09; until P09 lands, a placeholder continues to the map.
- **Boss:** a win pays the boss's shared XP and personal bonuses, with level-ups shown as after any combat, then the run ends, and Results shows the seed.
- **Maps:** no map repeats in a run until every map in its pool has been used; then the pool refills. With few maps in the MVP, repeats will come sooner.

**A finished battle's order changes.** `CampaignService.end_battle()` saves first and collects the result afterwards, but save-system.md requires results to be applied **before** the save. RN3 collects, applies, then saves, so a crash can't lose or repeat a reward.

**Item picks** (question 7): each pick is one slot kind, so its three offers are all weapons, all equipment or all Pouch items (trinkets or consumables, ingredients included). The kind is rolled per combat in the Armory's ratio (Weapon 3, Equipment 2, Pouch 3) and shown on Results. In a Weapon pick, each weapon is from a type the army can use 75% of the time, any type otherwise (first pass, to tune).

**Item pick rarity** (question 13; adapted from Slay the Spire's card rewards; first pass, to tune):

| Combat | Common | Uncommon | Rare |
|---|---|---|---|
| Standard | 60% | 30% | 10% |
| Key | 50% | 33% | 17% |

- **Rare offset:** each seat carries an offset added to the Rare chance, taken from Common. It starts at −5%, rises by 1% for every Common offer shown, and returns to −5% when a Rare is shown, capped at +40%. Standard and Key picks share it. Once Common is used up, the offset takes from Uncommon.
- The Armory and Treasure don't read or move the offset.

**Rule readings** (question 9): a killing blow earns both Hit dealt and Defeated (+7) and counts as two Standout actions. A Feast heals 35% of max HP, halves rounding up. The speed bonus is the flat +25%; Survive and Defend earn it by ending early. A level-up's HP gain raises current HP too. Recruit offers draw evenly from the faction's types, with no type twice in one visit.

**XP tally.** A host-side observer counts each unit's XP actions from combat facts. A battle can be quit and resumed, so the tally is saved in the combat block rather than rebuilt. Closing a reinforcement point and looting are the +5 non-combat action. Block given ignores zero-amount facts.

**Grants.** `receive_grant` feeds `RunState`, closing TOD-001.

**Co-op hooks kept now.** Everything is per seat except the map, floor, Unknown odds and shop stock, whose size takes the extra-player count. A map that received sent units earns no speed bonus, as a per-seat flag for P11 to set.

**Rejected:** a `RunState` living in the screens (`Godot_FE`'s defect: rules scattered across UI); rebuilding the XP tally from a resumed battle's log (the log isn't saved).

**UI.** Every screen is its own `.tscn` with documented `@export`s and works on keyboard, mouse and controller from the step that adds it, with glyph hints. SceneRouter gains screens appended to its enum.

## Save Impact

All new sections sit in existing blocks, so no schema version changes; each section starts at version 1. Nothing a battle changes reaches them until the battle ends.

| Section key | Block | Per player | Holds |
|---|---|---|---|
| `campaign_map` | `CAMPAIGN` | No | The graph, visited nodes, current floor and node |
| `run_flow` | `CAMPAIGN` | No | Stage within a node, Unknown odds, used maps, shared shop stock |
| `roster` | `CAMPAIGN` | Yes | Unit and item instances: army, convoy, fallen units' items |
| `heirlooms` | `CAMPAIGN` | Yes | Owned heirlooms and curses with campaign-lane counters |
| `runes` | `CAMPAIGN` | Yes | The 3 rune slots |
| `economy` | `CAMPAIGN` | Yes | Gold, the rare offset; this seat's pending offers (item pick, starting heirloom, Treasure) |
| `battle_tally` | `COMBAT` | No | Each unit's XP actions so far in this battle |

Quitting mid-node resumes at the same stage with the same offers. Purchases are saved as they happen.

## Work Breakdown

Steps through RN5 give a playable loop on M1's data. Later steps need content from M2.

| Step | Work | Risk | After | Needs from M2 | Done when |
|---|---|---|---|---|---|
| RN1 Map | Generator, graph, rules data | 🟢 | Approval | — | 10,000 seeds pass every hard rule; target misses reported; same seed, same map |
| RN2 Run state | `RunState`, `RunFlow`, commands, the campaign sections, the army from the faction; permanent deltas include Hit (P03 question 25) | 🔴 save format | RN1 | — | A new run saves and reloads identically |
| RN3 Bridge | Real `BattleRequest`, the changed end-of-battle order, HP and fallen units, grants, `battle_tally` | 🔴 save order | RN2 | — | Quit at any point loses and repeats nothing |
| RN4 Rewards | Grades, gold, XP, Standout, level-ups (with the Resonant Ore, P03 question 25), item pick | 🟡 | RN3 | — (full pools later) | Vision's tables reproduced; rolls per seat and seeded |
| RN5 Loop screens | Campaign map, Results with rewards and level-ups, new-item placement, loss and win | 🟡 | RN4 | — | A multi-node run plays on all three input devices |
| RN6 Run start | Starting heirloom offer and each one's effect | 🟡 | RN5 | CT9, CT13 | All seven work |
| RN7 Treasure and Camp | Chests, Feast with cooking, Train, re-gear, army view, scrapping | 🟡 | RN5 | CT5, CT9, CT13 | The vision's odds and rules hold |
| RN8 Armory | Stock, buying onto a unit, trade-in | 🟡 | RN5 | CT4, CT5, CT9 | Stock and prices match the vision |
| RN9 Guildhall | Recruits, hand-over, runes, prefix re-rolls | 🟡 | RN5 | CT7, CT8, CT13 | Recruits match the preview |
| RN10 Unknown | Resolution, rising odds, the P09 hand-off | 🟢 | RN7, RN8, RN9 | — | Odds match over many seeds |
| RN11 Full run | Map pools per step and type, the boss, a seeded headless run to the end, the run seed on Results | 🟡 | RN10 | EN7, EN8, EN11, M2's maps | A full run completes solo and resumes after a quit at each kind of node |
| RN12 Docs | save-system.md's sections; the campaign layer's guide | 🟢 | RN11 | — | Docs match the code |

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|---|---|---|---|---|---|---|
| `CampaignService.end_battle()` order | Behaviour | Saves, then collects | Collects, applies, saves | Proposed (RN3) | Sessions tests | 🔴 |
| `battle_screen.gd` army and map | Behaviour | Built on the screen | From `RunState` | Proposed (RN3) | Screen `@export`s, UI tests | 🟡 |
| `SceneRouter.Screen` | Enum, appended | 9 screens | New campaign screens | Proposed (RN5) | `SCREEN_PATHS` | 🟢 |
| `Results` after a battle | Flow | The end of the run | A run's end only | Proposed (RN5) | `battle_screen.gd`, `results_screen.gd` | 🟡 |

## Verification

Each step's Done when column, in `tests/campaign/`, and the full runner. RN1 validates every hard map rule across 10,000 seeds and reports how often each soft target is missed. RN11 runs a seeded whole run headless and compares a mid-run resume with an uninterrupted one. M3's exit is a played solo run inside the 60–80 minute target.

## Rollback

Each step is its own merge; revert it. RN2 and RN3 change saves: a run saved by a reverted build won't load in an earlier one, which is acceptable before release.
