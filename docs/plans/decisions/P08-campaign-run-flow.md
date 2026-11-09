# P08 decisions: Campaign and run flow

The answered questions of [the plan](../2026-10-24-campaign-run-flow.md), moved here unchanged on November 9, 2026. Numbers are stable.

## Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | What owns `CampaignSession`? | New run autoload / inside `SaveService` / a campaign scene node | **A new autoload `CampaignService`**, after `SaveService` and before `SceneRouter`: the session must outlive every screen change and exist on every peer. | **Answered October 27, 2026:** as recommended. `CampaignService.session` is the live session (authoritative on the host, a fact-fed mirror on clients; null outside a run). It owns `RngStreams`, the `InstanceIdAllocator` and their save sections (both `rng` sections, `instance_ids`), registered in `_ready()`, and the battle bridge (`begin_battle()` / `end_battle()`). `SaveService` gains one signal, `campaign_activated(mode, resumed)`, after a new, continued or resumed run; `CampaignService` builds the session on it and tears it down on `run_ended` or `save_file_closed`, so every start path (the debug seed restart and clients included) gets a session. Combat sessions stay discoverable only through the campaign session's signals. The autoload skeleton and the signal are built in P01 EB6. |
| 2 | The RNG manager (reserved `rng` keys in campaign and combat): this plan or its own? | — | Its own plan | **Answered October 26, 2026:** its own plan, P13 [2026-10-26-rng-streams.md](../2026-10-26-rng-streams.md). This plan holds `RngStreams` in `CampaignSession` and registers its save sections from the autoload chosen in question 1. |
| 3 | Price and scrap value of modified items (deltas): here or the items plan? | — | TBD | **Answered October 29, 2026 (user):** P03 owns it (P03 question 8; step CT10). |

## Contracts inherited from the event bus plan (P01)

Decided in [the event bus plan](../2026-10-23-event-bus-and-effects.md); this plan builds on them.

- **Discovery.** Observers find sessions through `CampaignSession.combat_encounter_opened` / `combat_encounter_closed` and `CombatEncounter.session_opened`; no "current session" global.
- **Battle bridge.** At battle start `CampaignSession` builds the `CombatEncounter` and one `CombatSession` per map, registers each seat's carriers (in the encounter for cross-map scopes), and copies campaign-lane counters in. Before `end_battle()` it writes campaign-lane values back and drops combat-lane state.
- **Instance ids.** `CampaignSession` owns the `InstanceIdAllocator`; its counter is saved in the campaign (`instance_ids`) and in every `COMBAT` checkpoint.
- **Campaign hooks.** Triggers Gained, Combat ended, Leveled up; campaign value keys (`COMBAT_GOLD`, `GRADE_BONUS_PERCENT`, XP percents, `SCRAP_PERCENT`, shop stock and prices, `FREE_REROLLS`, `MAX_ARMY_SIZE`, `EXTRA_ENEMIES`, `HEALING_RECEIVED_PERCENT`), all per player.
- **Level-up resolver order.** Roll growths allowed by `STAT_CAN_GROW`, add `LEVEL_UP_GUARANTEED_GAINS`, fill to `LEVEL_UP_MIN_STATS`; random picks from the campaign stream.
- **Observers.** XP tally, Standout and grade bonuses ("lost no units", turn par) are host-side observers on combat facts, applied after combat.
- **Commands.** Campaign actions (purchases, route votes, event choices) go through the same validated command path: first arrival wins (shared shops), `command_rejected` costs nothing.
- **Events.** Narrative event outcomes reuse the effect operation blocks (`CampaignGrant`, granting effects or deltas to an item or unit, adding a curse).
