# Plan: Campaign and Run Flow
**Date:** October 24, 2026
**Status:** Stub — not started. Created from the event bus plan's question 15 so the contracts it
inherits aren't lost. Fill in every section below before asking for approval.

## What this plan owns

The run from Start to its end: who owns `CampaignSession` and how long it lives, the campaign map
and route, the nodes (combat, shops, Camp, Treasure, Unknown events), rewards, gold, XP and
level-ups after combat, and the hand-off into and out of battles.

## Contracts inherited from the event bus plan

From [2026-10-23-event-bus-and-effects.md](2026-10-23-event-bus-and-effects.md). These are decided;
this plan builds on them rather than reopening them.

- **Ownership (question 15).** This plan decides what owns `CampaignSession` (most likely a run
  autoload of its own, or part of an existing one) and its lifecycle against `SaveService`
  (`start_new_solo_run()`, `start_new_multiplayer_run()`, resume, `end_run()`, `abandon_run()`) and
  `SceneRouter`.
- **Discovery.** Observers find sessions through `CampaignSession.combat_encounter_opened` /
  `combat_encounter_closed` and `CombatEncounter.session_opened`; no "current session" global.
- **Battle bridge.** At battle start `CampaignSession` builds the `CombatEncounter` and one
  `CombatSession` per map, registers each seat's carriers (in the encounter for cross-map scopes),
  and copies campaign-lane counters in. Before `end_battle()` it writes campaign-lane values back
  and drops combat-lane state.
- **Instance ids.** `CampaignSession` owns the `InstanceIdAllocator`; its counter is saved in the
  campaign (`instance_ids`) and in every `COMBAT` checkpoint.
- **Campaign hooks.** Triggers Gained, Combat ended, Leveled up; campaign value keys
  (`COMBAT_GOLD`, `GRADE_BONUS_PERCENT`, XP percents, `SCRAP_PERCENT`, shop stock and prices,
  `FREE_REROLLS`, `MAX_ARMY_SIZE`, `EXTRA_ENEMIES`, `HEALING_RECEIVED_PERCENT`), all per player.
- **Level-up resolver order.** Roll growths allowed by `STAT_CAN_GROW`, add
  `LEVEL_UP_GUARANTEED_GAINS`, fill to `LEVEL_UP_MIN_STATS`; random picks from the campaign stream.
- **Observers.** XP tally, Standout and grade bonuses ("lost no units", turn par) are host-side
  observers on combat facts, applied after combat.
- **Commands.** Campaign actions (purchases, route votes, event choices) go through the same
  validated command path: first arrival wins (shared shops), `command_rejected` costs nothing.
- **Events.** Narrative event outcomes reuse the effect operation blocks (`CampaignGrant`,
  granting effects or deltas to an item or unit, adding a curse).

## Open Questions

TBD. Known so far:

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | What owns `CampaignSession`? | New run autoload / inside `SaveService` / other | TBD | |
| 2 | The RNG manager (reserved `rng` keys in campaign and combat): this plan or its own? | — | Its own plan | **Answered October 26, 2026:** its own plan, P13 [2026-10-26-rng-streams.md](2026-10-26-rng-streams.md). This plan holds `RngStreams` in `CampaignSession` and registers its save sections from the autoload chosen in question 1. |
| 3 | Price and scrap value of modified items (deltas): here or the items plan? | — | TBD | |

## Scope

TBD.

## Design Basis

To read before writing this plan: game-vision.md (Run structure, Army, Units: Experience and
Standout, Run-wide resources, Co-op ownership, Open and unfinished); master-ideation.md (matching
sections); heirlooms.md; items.md (Scrapping, Consumables, ingredients and Feast); events.md;
unit-roster.md (Recruiting and item transfer, Upgrades); multiplayer-combat-options.md (route
votes, shared shops); save-system.md.

## Legacy Behavior (ports from Godot_FE only)

TBD. To read: `Godot_FE/docs/systems/10_campaign_and_run_loop.md`,
`Godot_FE/campaign_map/map_generator.gd`, `Godot_FE/campaign_map/campaign_map.gd`,
`Godot_FE/overworld_new/player_overworld_data.gd`, `Godot_FE/campaign_map/events/event_selection.gd`.

## Approach

TBD.

## Save Impact

TBD. Starts from `CampaignData` / `PlayerRun` in `bandit-bash/scripts/save/` and the event bus
plan's Save Impact table.

## Work Breakdown

TBD.

## Breaking Changes

TBD.

## Verification

TBD.

## Rollback

TBD.
