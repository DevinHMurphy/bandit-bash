# Game Orchestrator

Where the project is, what's next and what's out of scope. Start here.

**Last updated:** November 24, 2026.

| Need | File |
|---|---|
| What a step needs before it starts; the graphs | [orchestrator/dependencies.md](orchestrator/dependencies.md) |
| Design items to settle when a plan is drafted | [orchestrator/design-items.md](orchestrator/design-items.md) |
| Bugs | [bug-tracker.md](bug-tracker.md) |
| A plan's answered questions | `decisions/Pxx-*.md`, by question number |
| History before November 9, 2026 | [orchestrator/change-log-archive.md](orchestrator/change-log-archive.md); after that, `git log` |

## How to use this file

**On every merge or plan change,** update Where we are, the Milestones status, the registry row and Next actions here, and the gates and both graphs in `orchestrator/dependencies.md`. Commit messages are the change log.

**Before a plan is approved:**

1. Every plan it depends on is at least **Approved**, or the exact contract it uses is named in it.
2. Its design basis has nothing it needs under "Still open" in [game-vision.md](../design/game-vision.md#open-and-unfinished).
3. Every unowned dependency it touches has an owner.
4. It stays inside [MVP scope](#scope-guardrails), or the user has explicitly pulled the item in.

**Before a step starts,** check its row in Gates.

**Plan one step ahead:** draft a plan while the step before it is being built, not all at once and never after the code that needs it.

**Writing plans:** plans hold the current design and only open questions. Answered questions move to `decisions/`. Keep table cells short; a long question becomes a heading with bullets.

**Branches:** build tracks branch from `dev` as `feature/<step>` and merge back into `dev`. Plan and orchestrator commits go to `dev`. `main` holds released state.

## Where we are

- **Milestones:** M0 and M1 are complete. M2, M3 and M4 are built or nearly built and wait on playtests: M2 and M3 on the user's full-run playtest, M4 on P18 and the live two-machine check. M5 is not started.
- **What runs today:** a seeded solo run plays from the start screen through the campaign map, every node kind and events to the Powder Baron, and resumes at every stop. Co-op plays the same run in the harness and over ENet on one machine; the live two-machine test reached the first hand-off (BUG-052, fixed by P18 RC1).
- **Now:** P18 co-op ready checks (RC1 and RC5 merged), then NT8 and CO21, the live check, then the engine list. The Movement and map rework (CT15 built, MP13 waiting on the user's maps) is on `map_gameplay_rework` for the user's playtest.
- **Tests:** 9,063 cases in 31 suites, all passing, and a clean headless launch (`sh bandit-bash/tools/run_tests.sh`).
- **Not started:** P12 (statistics and the war table, M5). P17 is parked.

## Milestones

The MVP is **one full run, start screen to boss, solo and co-op, on Normal** (game-vision.md).

| Milestone | Goal | Plans | Status |
|---|---|---|---|
| **M0 Foundations** | The engine every system plugs into | P00, P01 | **Complete** October 30, 2026 |
| **M1 First playable fight** | One greybox combat, start to finish | P02–P07 (subsets) | **Complete** November 5, 2026; its tuning pass is deferred |
| **M2 Combat complete** | Every MVP combat feature and piece of content, with a functional UI | P02–P07 | **In progress.** Every build is in (BF3 merged November 19, 2026). Left: the exit playtest, folded into M3's full-run playtest (user, November 22, 2026) (BF4 merged November 20, 2026; BF6, the end-of-phase battle save, merged November 20, 2026). RB1 moved to M3 (user, November 20, 2026): balancing needs events and every node working |
| **M3 Solo run** | Start screen → campaign → boss, saved and resumable; 60–80 minutes | P08, P09 | **In progress.** P08 and P09 built (RN12 merged November 21, 2026): a seeded solo run plays from the start to the Boss and resumes at every stop. Left: the full-run playtest, which also closes M2's exit playtest (user, November 22, 2026), then RB1 (user, November 20, 2026) and TX2. CT12 (weapon modifications) is not part of M3's exit (user, November 22, 2026): game-vision.md still lists its design as open |
| **M4 Co-op run** | The same run for 2–4 players, tested live on two machines | P10, P11 | **In progress** alongside M3: P10 NT1–NT7 and P11 CO1–CO20, CO22 and CO23 merged by November 23, 2026 (NT7: two instances on one machine play a battle over ENet; CO16: clients play the campaign and events in the harness; CO13: the co-op battle screen); BUG-046 closed by CO23 (the ENet test's driver, not the engine); BF11 (the two-instance launcher `tools/run_enet_pair.sh`, the ENet lobby text, BUG-042, BUG-044) merged; CO19 (the co-op pause menu: the tree never pauses, the host's Save & Quit ends the match for every client through `NetRelay._match_ended`, a client's Forfeit, the forfeiter cut off after 1 s) merged; BF13 (BUG-050: the pair test's driver didn't end a lost run; BUG-051 logged) merged; then P18 (co-op ready checks: the live two-machine test failed at the first hand-off, BUG-052) and NT8 (setup NT8a after BF15, then the live check NT8b, Windows against the user's Mac, after P18 RC6) |
| **M5 MVP** | Statistics, the Waystation war table, the MVP checklist | P12, polish | Not started |
| Post-MVP | Meta progression and beyond | P20–P24 | Not planned |

**M2's exit:** the UI lift (P15, [ui-lift.md](../design/ui-lift.md), scoped November 18, 2026) and the audio layer (P16 AU1, [audio.md](../design/audio.md), scoped November 19, 2026) built; every entry targeted at M2 in [rebalance-and-features.md](../design/rebalance-and-features.md) built (the playtest feedback log, opened November 18, 2026); every objective and map object, the 10 enemy classes, 4 mini-bosses, the Powder Baron map, and all MVP units, weapons, staves, items, heirlooms and runes as data.

## Plan registry

Statuses: **Not started** · **Stub** · **Draft** · **Approved** · **In progress** · **Implemented** · **Superseded**.

| ID | Plan | Status | Left | Depends on |
|---|---|---|---|---|
| P00 | [Save system](2026-10-13-save-system.md) | **Implemented** | Multiplayer paths untested live | — |
| P01 | [Event bus and effects](2026-10-23-event-bus-and-effects.md) | **Implemented** (EB8 docs merged November 19, 2026: [event-bus.md](../design/event-bus.md)) | — | P00 |
| P02 | [Combat core](2026-10-26-combat-core.md) | **Implemented** (CC9 docs merged November 19, 2026; vision question 4 checked against `BonusTurns`, N1–N10 recorded as built, BUG-003 fixed) | — | P01 |
| P03 | [Content catalog](2026-10-29-content-catalog.md) | **In progress** | CT12 weapon modifications, after an ideation pass on their design (out of M3's exit, user November 22, 2026; CT11 docs merged November 19, 2026: [content-authoring.md](../design/content-authoring.md)) (question 33) | P01 |
| P04 | [Combat map](2026-10-27-combat-map.md) | **In progress** | MP11 map authoring toolkit (future; MP9 docs merged November 19, 2026: [map-authoring.md](../design/map-authoring.md)) | P01, P02 |
| P05 | [Enemies and AI](2026-10-30-enemies-and-ai.md) | **In progress** | EN17 (the cancel) merged November 23, 2026; EN20 plan next (the intents refresh on the worker, P05 question 53 (a); named EN18 in earlier records, a clash with the built Shieldbearer rework); P05 questions 56–57 open (EN16 merged November 22, 2026; EN15 merged November 21, 2026; EN13 and EN14, the forecast cache, merged November 20, 2026; EN11 merged November 18, 2026; EN12 docs merged November 19, 2026, in content-authoring.md) | P02, P04 |
| P06 | [The darkness](2026-11-03-the-darkness.md) | **Implemented** (DK6 docs merged November 19, 2026) | — | P02, P04 |
| P07 | [Combat UI](2026-11-04-combat-ui.md) | **In progress** | Nothing for M2 | P02, P04, P05, P06 |
| P08 | [Campaign and run flow](2026-10-24-campaign-run-flow.md) | **Implemented** (RN12 docs merged November 21, 2026: [campaign-run.md](../design/campaign-run.md), save-system.md's run state) | P08 question 71 (the placeholder copy) to confirm | P01, P03 |
| P09 | [Narrative events and curses](2026-11-12-events-and-curses.md) | **Done**: EV1, EV2, EV3 and EV5 merged November 19, 2026; EV1F, EV1G, EV4 and EV6 November 20; EV7 (the hand-over at events, RF-033) November 23 | — | P01, P03, P08 |
| P10 | [Net transport](2026-11-19-net-transport.md) | **In progress**: NT1 and NT2 merged November 19, 2026; NT3 (every campaign and event command on the wire) November 21; NT4 (the relay), NT5 (client mirrors) NT6 (drop, pause, rejoin) and NT7 (size, packing, the ENet dev transport) November 23 | NT8 the live check (Lane E), after CO13 and CO16; untested live until NT8 | P00, P01 |
| P11 | [Co-op combat](2026-11-20-coop-combat.md) | **In progress** (approved November 20, 2026; CO6 to Lane C): CO9 merged November 21, 2026; CO10 (screens for the local seat) merged November 22, 2026; CO1 (co-op loss rules) merged November 22, 2026; CO6 (route votes) merged November 22, 2026; CO12 (the co-op event screen) merged November 22, 2026; CO2 (sends and aid, `combat_state` v4) and CO7 (unique heirloom claims) and CO5 (unit swaps, `run_flow` v2) merged November 22, 2026; CO11 (the co-op campaign map) CO4 (the darkness on mirrors) and CO8 (the co-op battle's end) CO3 (units on a partner's map), CO14 (forfeit) and CO15 (settings and fast-forward), CO16 (clients in the harness: campaign and events; BUG-034), CO13 (the co-op battle screen) and CO22 (resuming a battle a seat left) , CO23 (a unit leaving a map in play; BUG-043) , CO18 (forfeits and removals on the network; BUG-047), CO17 (co-op battles with clients in the harness), CO19 (the co-op pause menu) and CO20 (the docs pass; BUG-033) November 23; the rest answered in [decisions](decisions/P11-coop-combat.md) | CO21 (the live check, after NT8b) | P01, P02, P04, P08, P10 |
| P12 | Statistics and the Waystation war table (meta-progression.md) | **Not started** | — | P01, P08 |
| P13 | [RNG streams](2026-10-26-rng-streams.md) | **Implemented** | — | P00 |
| P15 | UI lift ([ui-lift.md](../design/ui-lift.md); its scope doc is the plan) | **Implemented** November 19, 2026: UL0–UL8 and UL1F merged | — | P07, P08 |
| P14 | [Project organization](2026-11-09-project-organization.md) | **In progress** | TL1 capture guard and `run_captures.sh` merged November 23, 2026; O8 concurrency tooling **merged** November 19, 2026 (every case file declares `const SUITE`, `tests/case_files.gd` finds it; `--quick` skips the map_set parts); O8b **merged** November 19, 2026 (`capture_screens.gd` is a runner over `tools/captures/<number>_<name>.gd` groups); O5 (deferred) | — |
| P16 | Audio ([audio.md](../design/audio.md); its scope doc is the plan) | **In progress**: AU1 the audio layer merged November 19, 2026 | AU1 done; AU2+ sound design (M5, after the audio direction) | P07, P15 |
| P17 | Localization: written, translatable descriptions; every string through Godot's translation; layouts that survive longer text and other scripts | **Parked** (user, November 22, 2026: very low priority; not offered until the user raises it) | — | P03, P07, P08, P09, P15 |
| P18 | [Co-op ready checks](2026-11-24-coop-ready-checks.md) | **Approved** (user, November 24, 2026; all 10 questions answered): every co-op hand-off waits for every seat's Ready and every machine's load; one routing authority (RC1 fixes BUG-052) | RC1 (one routing authority; BUG-052 and BUG-058 fixed) merged November 24, 2026; RC5 (the waiting UI and loading screen) merged November 25, 2026; RC2 (the gate) next; then RC3, RC4, RC6, RC7 | P10, P11 |
| P20–P24 | Meta progression, tutorials, dev console, status effects, shared co-op battles | Post-MVP | — | — |

## Next actions

**Build prompts resumed** November 12, 2026 (user), two at a time, once planning caught up. **From November 19, 2026: up to four builds, one per lane, plus docs and planning sessions** ([concurrency lanes](orchestrator/dependencies.md#concurrency-lanes)).

**Sequencing (user, November 23, 2026): networking and engine first, then reworks.** No gameplay
rework (map fixes, new enemies, pack changes, balance, CT12, RF features, TX2) runs until M4's
steps (CO17, CO18, CO19, NT8a, NT8b, CO20, CO21) and the engine list (EN20 the intents refresh
on the worker with BUG-035, SaveService's messages under the relay's size guard, Lane A's
BUG-049, the HUD rune bar as an EffectText and the event log per viewed map, the event option's
expected-heirloom field, BUG-012; confirmed by the user, November 23, 2026; MP11 the map toolkit goes with the reworks, just before the map fixes) are done. Then the full-run playtest (its notes can come any
time, into the Inbox) and RB1 over every M3 entry in rebalance-and-features.md, then content
reworks and M5.

**Exception (user, November 24, 2026):** RF-054, Movement by type (CT15), and the map and enemy
placement rework it needs (MP13) go now, ahead of the engine list. **Also brought forward**
(user, November 25, 2026): RF-055 terrain costs (CT16, on the rework branch), and RF-052's Monster
weapon type with RF-056's Stonelet (EN21, on dev; BF16 merged November 25, 2026). Every other rework stays held.

1. **P14 (priority, user, November 16, 2026):** O6 faster suites (merged November 16, 2026: every suite in parallel, enemies in three parts, BUG-011 fixed; a full run 248 s → 140 s before MP10b, 215 s after it, with `map_set/key` at 201 s), then O7 the live test report (merged November 16, 2026: `report.html` in each run's log folder, refreshed live; `tools/run_tests.cmd` or `--open` opens it; history in `%LOCALAPPDATA%BanditBash	estshistory.tsv`; a full run 159–166 s, set by `map_set/standard`); both change `run_tests.sh`, so one at a time. O1–O4 done (O4 merged November 12, 2026). O5 waits until a step needs those files.
2. **Plans:** P08 approved November 12, 2026; RN1 (the map) merged November 12, 2026; RN2 (run state as `CampaignRunState`) merged November 13, 2026; RN3 (the battle bridge, with BUG-009 and BUG-010) merged November 13, 2026; RN4 (rewards, plus a fallen commander kept at critical health, P08 question 19) merged November 14, 2026 (P08 question 20); RN5 (the loop screens: the campaign map, Results, new-item placement, the run's end) merged November 15, 2026 (P08 question 21). P09 approved November 12, 2026; EV1 is open now that RN2 is in. The move-preview re-architecture is adopted ([move-preview.md](../design/move-preview.md)) as P05 EN13–EN16. **Planning is caught up.**
3. **Then M2's content, two prompts at a time:**
   - **Wave A (ready):** CT6 target shapes (merged November 12, 2026) with EN6 enemy roster (merged November 14, 2026: 10 classes, the shared Javelin, killing blows splash; P05 question 39); then CT13 unit roster (merged November 14, 2026: 11 types; P03 question 27; its Skirmisher+ Block half is CT13F, before RN7) with CT5 equipment and consumables (merged November 13, 2026; the Short Quiver moved to CT4 and the Resonant Ore to RN4). EN13 (preview benchmarks and equality suite) is ready, after splitting the enemies suite (design items, P14 / P05); EN14–EN16 follow EN13.
   - **Wave B:** CT4 weapons and staves (merged November 15, 2026: all 70, Everbloom's full heal, the Short Quiver, one range read; `combat_state` v2), CT13F Skirmisher+ Block and the Haunted redesign (merged November 15, 2026; P03 question 29), CT9 heirlooms and curses (merged November 15, 2026: 35 pool heirlooms, 10 curses; follow-ups in P03 question 28), EN10 reinforcement groups and the Hunted extra enemy (merged November 15, 2026; P05 question 40), EN9 map-object AI (merged November 15, 2026: kegs, levers, Braziers, Cutthroat looting through `CAN_LOOT`; P05 question 41).
   - **Wave C:** MP10 the M2 map set (count and mix: P04 question 27; MP10a, the six standard maps, merged November 16, 2026; MP10b, the four key maps, merged November 16, 2026 (the generator is `tools/gen_maps.gd`); the Leader and mini-boss maps join the pools with EN7 and EN8), P07 UI14 runes at any time (merged November 18, 2026: a three-slot rune bar usable any time in the player phase, with discard; P07 questions 39–40; BUG-014 found), P04 MP12 reachable maps (merged November 18, 2026: every map object drawn on the board, the map check proves reachability without a key; BUG-013; P04 question 28), CT7 runes (merged November 15, 2026: seven runes by target kind, `CombatForecast.rune()`, the cast wire gains a tile; P03 question 32), P07 UI13 rune casting (merged November 16, 2026; P07 question 38), CT8 unit prefixes and pools (merged November 15, 2026: 12 prefixes, `ItemPools`, container items from the pools; P03 question 31), CT10 modified prices (merged November 16, 2026: P03 question 8; the Armory calls `held_scrap_value`), P07 UI12 curse display, trigger wording and the object intent (merged November 15, 2026; P07 question 37).
   - **Wave D:** EN17 pack pools (merged November 15, 2026: basic, hard and key pools by step; P05 question 42), then EN7 elites and bosses (merged November 17, 2026: leaders on the leader slot as elites with a positive prefix, War Horn shown as a SIGNATURE intent; P05 question 43); EN8 mini-bosses (merged November 18, 2026: four mini-bosses on the key maps' leader slot, a seeded no-repeat order, the Hall in the key pools; P05 question 44), EN18 Shieldbearer rework (merged November 18, 2026: Braced, the Shieldmace; P05 question 45; RF-010), P06 DK7 darkness phase (merged November 18, 2026: darkness damage moved into its own phase before the creep, with a banner and the spread played tile by tile; P06 question 16; RF-014), and EN11 is ready (marks leaders on the HUD; adds `bandit_camp` and `watch_post` to the standard pools, P04 question 27), EN8 mini-bosses (adds the mini-boss key map to the key pools), EN11 the Powder Baron and its map, CT12 weapon prefixes (waits on the vision's weapon-prefix rules).
   - **Docs:** EB8, CC9, MP9, DK6, CT11 and EN12 as one batched step at the end of M2; **merged** November 19, 2026.
4. **Bugs** ([tracker](bug-tracker.md)), fix step **BF1**, merged November 19, 2026 (668da72) (BUG-002, BUG-006, BUG-008, the confirmed markers below, and splitting `map_set/key` and `map_set/boss` under the 300 s limit):
   - BUG-002 (S2): the forecast's crit ignores Stance; **fixed** in BF1.
   - BUG-004 (S2): an enemy with an attack intent moves and doesn't attack; tabled by the user November 18, 2026, so not in BF1.
   - BUG-005 (S4): unit detail shows the type id; moved to **UL3**, which rebuilds the unit detail pop-up (November 19, 2026).
   - BUG-006 (S3): NetLog raises an engine error once the peer is cleared; **fixed** in BF1 (a NetLog guard).
   - BUG-008 (S2): a client mirror keeps a used-up consumable; **fixed** in BF1.
   - BUG-016 (S4, latent): `SteamNetwork.local_peer_id()` errors once the peer is cleared (BF1 report); fix in P10.
   - BUG-009 (S2) and BUG-010 (S4): **fixed** in RN3, merged November 13, 2026.
   - BUG-011 (S3): **fixed** in P14 O6, merged November 16, 2026 (no `override.cfg` at all).
   - BUG-012 (S4): loading the map pools inside a board-suite test leaves resources in use at exit; worked around in the test.
   - BUG-013 (S2, user, November 18, 2026): a map can put a required route behind a door no one can open; **fixed** in **P04 MP12**, merged November 18, 2026 (the board drew no map objects, so doors looked open and levers were invisible; two trap rooms got an inside lever; the map check now proves reachability; P04 question 28). Verify in the next playtest.
   - BUG-014 (S2, latent): a run's runes never reach the battle, nor casts and discards the run; found by UI14, fixed in **P08 RN9** (the Guildhall, runes' first source).
   - BUG-015 (S2, user, November 18, 2026): the unit panel's Details button can't be clicked (the panel follows hover); fixed in the UI lift's **UL3**.
   - BUG-007 (S3), shared test user folder: **fixed** in BF2, merged November 12, 2026. Each run now has its own folder.
   - BF1 also removed (done) the confirmed `# ASSUMPTION` markers of UI11 (P07 question 36) and RN1 (P08 questions 14 and 15: `effect_catalog.gd`, `campaign_map_rules.gd`, the `;` comment in `campaign_map_rules.tres`) and RN3 and RN4 (P08 questions 19 (2) and 20: `campaign_run_state.gd`'s `COMBAT_ENDED` amount and fallen-list order; `item_pick_command.gd`'s skipped pick with no fact), RN5's (P08 question 21: `campaign_map_view.gd`, `map_node_button.gd`, `item_placement.gd`), and settles CT5's `HIT_STAT = 100` marker in `combat_value.gd`. It also moves the `# ASSUMPTION` line in `battle_screen.gd` that sits between `end_banner_time`'s doc and its declaration (Godot drops the doc), and brings `pause_menu.gd`'s and `battle_controller.gd`'s class docs to budget (found by RN5), plus CT4's (P03 question 30): the `"staff"` literal at `content_rules.gd:215`, `WeaponDefinition`'s gauntlet CritX doc, and the confirmed staff-Magic markers in `shelter.tres` and `minor_heal.tres`, and CT8's confirmed weapon-rack marker in `MapObjects.roll` (P03 question 31), and updates the old wording quoted in `tests/sessions/encounter_cases.gd:395` and `sessions_case_base.gd:95` (P07 question 37), and wraps `content_rules.gd:29`'s 122-character line (P03 question 32), and fixes the `wire_cases.gd` comment that says setup draws from every pack (P05 question 42).
5. **M2's exit:** playtest a full M2 map set, folding in the deferred M1 tuning pass. Playtest notes go in the Inbox of [rebalance-and-features.md](../design/rebalance-and-features.md); the orchestrator triages them. Rebalance passes (RB1, RB2...) run in M3, after RN10, over full runs (user, November 20, 2026): balancing needs events and every node working.
6. **Later:** P04 MP11, a map authoring toolkit so the user can build maps by hand in the editor as in `Godot_FE` (after MP10 and MP9; P04 question 26); one public `Pathing.path_to` (P07 question 15 d); vision updates for the ideation thread.

**Open questions for the user:** none.

## Scope guardrails

**In the MVP** (game-vision.md): one act, one faction (Mercenary), one commander (the Drengr), Normal only, the 14 MVP unit types, 10 enemy classes, 4 mini-bosses, the Powder Baron, the full item, weapon, heirloom, rune and event pools, the darkness, solo and co-op on parallel maps, statistics recording and the Waystation war table.

**Out of the MVP** (stop and ask before any plan touches these): meta progression (unlocks, the difficulty ladder, almanac, Hall of Heroes, run history, achievements, the other Waystation stations), endless runs and later acts, more bosses, the Mage Tower and Kingdom factions and the other commanders, status effects and status staves, the Ballista and War Drum, darkness extras beyond the Brazier, support weapons beyond staves, one- and two-handed weapons, unique equipment, more enemy factions, units with convoy access, shared and hybrid co-op battles, the dev console, rune prefixes (P03 reserves `data/prefixes/runes/`), directional target shapes (line, cone).

**Focus rules**

- A plan that grows past its row's scope splits into a new row here, not a bigger plan.
- A gameplay value with no basis in the design docs or `Godot_FE/` is a design question, not an implementation choice (CLAUDE.md §1).
- **Every new UI and feature works on keyboard and mouse and on a controller from the start** (user, November 7, 2026): pad bindings, focus navigation and glyph hints in the same step.
- **Every UI element is its own `.tscn`** with documented `@export`s, so it can be edited by hand; every prompt says so.
