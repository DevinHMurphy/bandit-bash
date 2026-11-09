# Plan: Campaign and Run Flow
**Date:** October 24, 2026; drafted November 9, 2026
**Status:** Draft, awaiting the answers below. Orchestrator ID **P08**

## Problem

A run today is one battle. `battle_screen.gd` builds the faction's starting army itself and passes a single map (lines 112–122), and a finished battle goes straight to Results (line 183). Nothing owns the run between battles: there is no campaign map, node, reward, XP, gold or saved roster. `CampaignSession.receive_grant` records grants and applies none (TOD-001). M3 needs all of it.

## Open Questions

Questions 1–3 are answered in [decisions/P08-campaign-run-flow.md](decisions/P08-campaign-run-flow.md).

### 4. What "never directly connected" covers on the campaign map

The vision says "Key combat, Shops (Armory or Guildhall) and Camp are never directly connected by a path."

- **A, same kind only (recommended):** two Key combats, two Shops or two Camps can't be neighbours; a Shop may follow a Camp. This is Slay the Spire's rule, and the vision's generator is modelled on it.
- **B, all as one group:** none of the three may follow any other. A path could then hold at most 7 of them, but the vision's typical path has 8, so B can't produce it.

### 5. How the every-path minimums are met

"A roll that breaks one is rerolled" works for rules about one node. It can't guarantee rules about every path (an Armory, a Guildhall, 2 Treasures, 2 Camps). Simulated with a throwaway script, full-map rerolls met them in 0 of 4,000 tries.

- **A, roll, repair, retry (recommended):** roll as the vision says, convert Standard or Unknown nodes on any path short of a minimum, then validate and start again if it still fails. Each attempt succeeded about 30% of the time, so a few attempts are enough, and the same seed still gives the same map.
- **B, loosen the minimums:** for example, require only one Shop of either kind per path.
- **What A costs:** the same simulation averaged Armory 1.7, Guildhall 1.7 and Treasure 3.1 on a path (vision target 1, 1 and 2), and about 7.5 combats against the target 9, so less XP and gold. Raising Standard's weight from 4 to 7 moved that by under one node. The vision files all of this under "tune in playtesting", so the recommendation is to build A with weights in a data file and tune after real runs.

### 6. Where gear can change

There is no battle prep (user, October 27, 2026), and the vision's other references assume there is. A weapon won on floor 2 would wait for a Camp on floor 8 or later unless it can be equipped when won.

- **A (recommended):** a new item can go straight onto a unit where it's gained (combat pick, Treasure), with the Armory's before/after comparison. All gear rearranges freely at **Camps**, on top of Feast or Train rather than replacing them. Elsewhere the army can be viewed and convoy items scrapped, nothing more. This keeps each decision where the player already is.
- **B:** full army management any time on the campaign map. Simplest, but it invites re-gearing before every node, which works against less menuing.
- **C:** Camps only, with new items going to the convoy until then.

### 7. What a combat's item pick offers

The vision gives the rarity odds and says weapons are "weighted to the army's weapon types", with no number and no split between item kinds.

- **Recommended, first pass:** each of the 3 offers rolls its kind in the Armory's ratio (weapon 3, equipment 2, trinket 1, consumable 2). A weapon offer is from a type the army can use 75% of the time, any type otherwise.
- **Alternative:** weapons only from usable types, as the Armory does. Safer offers, but no reason to change a unit's role.

### 8–11. Shorter questions

| # | Question | Recommendation |
|---|----------|----------------|
| 8 | Boss win: award XP and level-ups first? | **No.** The run ends, so go straight to Results. Units then reach 4.1–5.7 levels, inside the 4–6 target |
| 9 | Small rule readings | **Accept all of (a)–(e)** below |
| 10 | May a run repeat a map? | **Not until its pool is used up,** then the pool refills |
| 11 | Who builds co-op's campaign layer? | **Split:** P08 keeps state per seat and tests the vote and shared-stock rules headless; P11 adds the screens and transport |
| 12 | Who builds the run-start screens? | **P08,** functional, with the Mercenary preselected; P12's war table later becomes the way in |

**Question 9's readings:**

- (a) A killing blow earns both Hit dealt and Defeated (+7), and counts as two actions for the Standout.
- (b) A Feast heals 35% of **max** HP, rounded to the nearest whole number, halves up, as gold does.
- (c) The speed bonus is the flat +25% grade. A turn under par has no separate value. Survive and Defend earn it by ending early.
- (d) A level-up's HP gain raises current HP as well as max.
- (e) Recruit offers draw evenly from the faction's recruitable types, with no type twice in one visit.

## Scope

**In:** the run from pressing Start to its end, for solo: run start, the campaign map and route, every node's rules and functional screen, rewards, gold, XP, the Standout, level-ups, permadeath bookkeeping, the battle bridge's real inputs and outputs, and all of it saved and resumable. Per-seat state and headless-tested co-op rules (question 11).

**Out:** event content and curses' offers (P09; this plan resolves Unknown nodes and hands events off); the co-op screens and transport (P10, P11); statistics and the Waystation (P12); the screens' final look (the user designs them later); enemy and item content (M2).

## Design Basis

game-vision.md: Run structure, Army, Units (Experience, Upgrades, Inventory), Run-wide resources, Co-op ownership. master-ideation.md: the matching sections. heirlooms.md (Tiers and sources, Starting heirlooms). items.md (Scrapping, Ingredients). unit-roster.md (Upgrades, Recruiting and item transfer). multiplayer-combat-options.md. save-system.md.

Nothing this plan needs is under "Still open". The economy, map weights and XP amounts are under "Tune in playtesting" and safe to build as written.

**For the vision, once answered (ideation thread):** "army management and battle prep" (Army, Inventory, No trading in combat); Camp's "choose one" against free re-gearing; the map's reroll wording and typical mix.

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

**Map.** Follows the vision's shape, fixed rows and rules, reading questions 4 and 5. Fixed rows are exempt from "a node's children differ". Weights, rows and minimums live in `data/campaign/`. Every attempt draws from the one `MAP_GENERATION` stream, up to 200 attempts.

**The loop.** Choosing a node locks its floor and saves. Then:

- **Combat:** `RunState` builds the real `BattleRequest`, with the army from the roster and the map drawn from the pool for the node's combat type and step. On a win, Results shows grades and gold, the item pick (and a Key combat's heirloom), XP, the Standout and level-ups together, then returns to the map.
- **Loss:** in solo, the run ends at once through `end_run(false)`.
- **Treasure, Camp, Armory, Guildhall:** as the vision and question 6 say. Hand-over screens follow unit-roster.md.
- **Unknown:** rolled on entry with the vision's rising odds, kept in `RunState`. An event hands off to P09; until P09 lands, a placeholder continues to the map.
- **Boss:** a win ends the run, and Results shows the seed.

**A finished battle's order changes.** `CampaignService.end_battle()` saves first and collects the result afterwards, but save-system.md requires results to be applied **before** the save. RN3 collects, applies, then saves, so a crash can't lose or repeat a reward.

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
| `economy` | `CAMPAIGN` | Yes | Gold; this seat's pending offers (item pick, starting heirloom, Treasure) |
| `battle_tally` | `COMBAT` | No | Each unit's XP actions so far in this battle |

Quitting mid-node resumes at the same stage with the same offers. Purchases are saved as they happen.

## Work Breakdown

Steps through RN5 give a playable loop on M1's data. Later steps need content from M2.

| Step | Work | Risk | After | Needs from M2 | Done when |
|---|---|---|---|---|---|
| RN1 Map | Generator, graph, rules data | 🟢 | Questions 4, 5 | — | 10,000 seeds pass every rule; same seed, same map |
| RN2 Run state | `RunState`, `RunFlow`, commands, the campaign sections, the army from the faction | 🔴 save format | RN1 | — | A new run saves and reloads identically |
| RN3 Bridge | Real `BattleRequest`, the changed end-of-battle order, HP and fallen units, grants, `battle_tally` | 🔴 save order | RN2 | — | Quit at any point loses and repeats nothing |
| RN4 Rewards | Grades, gold, XP, Standout, level-ups, item pick | 🟡 | RN3, questions 7–9 | — (full pools later) | Vision's tables reproduced; rolls per seat and seeded |
| RN5 Loop screens | Campaign map, Results with rewards and level-ups, new-item placement, loss and win | 🟡 | RN4, question 6 | — | A multi-node run plays on all three input devices |
| RN6 Run start | Starting heirloom offer and each one's effect | 🟡 | RN5, question 12 | CT9, CT13 | All seven work |
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

Each step's Done when column, in `tests/campaign/`, and the full runner. RN1 validates every map rule across 10,000 seeds. RN11 runs a seeded whole run headless and compares a mid-run resume with an uninterrupted one. M3's exit is a played solo run inside the 60–80 minute target.

## Rollback

Each step is its own merge; revert it. RN2 and RN3 change saves: a run saved by a reverted build won't load in an earlier one, which is acceptable before release.
