# Bug Tracker

**Created:** November 6, 2026. **Last updated:** November 21, 2026.

Every known defect in `bandit-bash/`, from playtests, build reports and reviews. It works under the
[orchestrator](game-orchestrator.md): the orchestrator session triages new rows, batches them into
fix steps, issues the prompts and closes rows on merge. Missing features and design changes go in
the plans and the orchestrator's Design items, not here.

## How it works

- **Adding a bug:** anyone (the user, the orchestrator, a build agent's report) adds a row to
  [Open bugs](#open-bugs) with status **New** and a details section below it. IDs are `BUG-NNN`,
  the next free number, never reused or renumbered.
- **Triage** (orchestrator): set the severity and the area (plan), check the expected behaviour
  against `game-vision.md` and the plan, and either assign the bug to a fix step or ask the user.
  A bug whose expected behaviour the vision doesn't settle is **Needs decision** until the user
  answers (CLAUDE.md §1: never silently fix, never silently port).
- **Fixing:** a fix step names its bugs (for example *BF1: BUG-002, BUG-004*). Every fixed bug gets
  a regression test that fails before the fix. A build agent that finds a bug outside its step
  reports it ("found, not fixed"); the orchestrator adds the row.
- **Closing:** on merge the orchestrator sets **Fixed** with the merge commit and moves the row to
  [Closed bugs](#closed-bugs). The user may mark a fixed bug **Verified** after a playtest, or reopen
  it.

**Severity**

| Level | Meaning |
|-------|---------|
| S1 | Crash, a soft-lock, a corrupted or lost save, or a rule broken so a fight can't be played fairly |
| S2 | A wrong rule, number or preview the player acts on (the forecast, ranges, intents) |
| S3 | Wrong or missing feedback; a workaround exists |
| S4 | Cosmetic, docs or text |

**Status:** New · Needs decision · Assigned (step) · Fixed (commit) · Verified · Won't fix · Can't reproduce ·
Not a bug.

## Open bugs

| ID | Title | Area | Sev | Status | Found | Fix step |
|----|-------|------|-----|--------|-------|----------|
| [BUG-002](#bug-002-the-forecasts-crit-chance-ignores-current-stance) | The forecast's crit chance ignores current Stance | P02 / P07 | S2 | Fixed (BF1 merge, November 19, 2026) | November 6, 2026, user playtest | BF1 |
| [BUG-003](#bug-003-save-systemmd-says-a-battle-retry-repeats-ids) | save-system.md says a battle retry repeats ids | P00 / P02 | S4 | Fixed (CC9, dfad90b, merged November 19, 2026) | November 5, 2026, CC10 report | CC9 |
| [BUG-004](#bug-004-an-enemy-with-an-attack-intent-moves-and-doesnt-attack) | An enemy with an attack intent moves and doesn't attack; the next enemy hits its target | P05 / P07 | S2 | Tabled (user, November 18, 2026; not in BF1) | November 6, 2026, user playtest | — |
| [BUG-005](#bug-005-unit-detail-shows-the-type-id-not-its-name) | Unit detail shows the type id, not its name | P07 | S4 | Fixed (UL3 merge, November 19, 2026) | November 7, 2026, UI11 report | UL3 |
| [BUG-006](#bug-006-netlog-raises-an-engine-error-once-the-peer-is-cleared) | NetLog raises an engine error once the peer is cleared | P00 / P10 | S3 | Fixed (BF1 merge, November 19, 2026) | November 9, 2026, O3 report | BF1 |
| [BUG-008](#bug-008-a-mirror-keeps-a-used-up-consumable) | A mirror keeps a used-up consumable, so its hash differs from the host's | P02 / P11 | S2 | Fixed (BF1 merge, November 19, 2026) | November 13, 2026, CT5 report | BF1 |
| [BUG-012](#bug-012-loading-the-map-pools-in-a-test-leaks-resources) | Loading `CombatMapPools.load_default()` inside the board suite's route case leaves 74 objects and 58 resources in use at exit | P04 (map pools) / tests | S4 | New | November 16, 2026, MP10a report | — (worked around in the test) |
| [BUG-014](#bug-014-a-runs-runes-never-reach-the-battle) | A run's runes never reach the battle, and a cast or discard never reaches the run | P08 (battle bridge) | S2 (latent: no run grants runes yet) | Fixed (RN9 merge, November 20, 2026) | November 18, 2026, UI14 report | RN9 |
| [BUG-015](#bug-015-the-unit-panels-details-button-cant-be-clicked) | The unit panel's Details button can't be clicked: the panel follows the hovered unit, so moving the mouse to it changes or hides the panel | P07 (unit panel) | S2 | Fixed (UL3 merge, November 19, 2026) | November 18, 2026, user playtest | UL3 (ui-lift.md) |
| [BUG-016](#bug-016-steamnetworklocal_peer_id-errors-once-the-peer-is-cleared) | `SteamNetwork.local_peer_id()` errors once the peer is cleared | P10 | S4 | Fixed (NT1 merge, November 19, 2026) | November 19, 2026, BF1 report | P10 NT1 |
| [BUG-017](#bug-017-choosing-a-map-node-by-keyboard-logs-a-grab_focus-error) | Choosing a map node by keyboard logs `grab_focus: !is_inside_tree()` | P08 (campaign map) | S4 | Fixed (RN7 merge, November 19, 2026) | November 19, 2026, UL7 report | — |
| [BUG-018](#bug-018-fact-playback-holds-the-next-batch-for-the-last-facts-full-wait) | Fact playback holds the next batch for the last fact's full wait | P07 (playback) | S3 | Fixed (BF3 merge, November 19, 2026) | November 19, 2026, UL6 report | BF3 |
| [BUG-019](#bug-019-player-units-cant-attack-breakable-map-objects) | Player units can't attack breakable map objects (debris, powder kegs) | P07 (target list) | S2 | Fixed (BF4 merge, November 20, 2026) | November 19, 2026, user | BF4 |
| [BUG-020](#bug-020-a-broken-breakables-token-stayed-on-the-board) | A broken breakable's token stayed on the board | P07 (board) | S3 | Fixed (BF4 merge, November 20, 2026) | November 19, 2026, BF4 report | BF4 |
| [BUG-021](#bug-021-an-infused-basic-weapon-scraps-for-0-gold) | An Infused Basic weapon scraps (and trades in) for 0 gold | P08 (prices) | S3 | Fixed (EV4 merge, November 20, 2026) | November 20, 2026, RN8 report | EV4 (note sent November 20, 2026) |
| [BUG-022](#bug-022-an-enemys-second-move-ending-in-a-wait-crashes-the-enemy-phase) | An enemy's second move ending in a Wait crashes the enemy phase (the Bloodhound after a kill) | P05 (enemy plans) | S2 | Fixed (BF5 merge, November 20, 2026) | November 20, 2026, EN13 report | BF5 |
| [BUG-023](#bug-023-an-untyped-empty-literal-from-a-ternary-fails-in-a-typed-slot) | An untyped `[]` from a ternary fails at runtime in a typed Array slot (three latent places) | P01 / P08 / tests | S3 (latent) | Fixed (BF8 merge, November 22, 2026) | November 20, 2026, BF5 report | EN14 fixed effect_engine.gd; BF7 fixed the victory test (merged November 22, 2026); BF8 `starting_offer_view.gd` |
| [BUG-024](#bug-024-battles-dont-save-at-the-end-of-a-player-phase) | Battles don't save at the end of a player phase: a crash loses every move since Begin | P00 / P07 (battle checkpoints) | S2 | Fixed (BF6 merge, November 20, 2026) | November 20, 2026, P11 plan report | BF6 |
| [BUG-025](#bug-025-openeventcommand-accepts-an-unknown-that-rolled-a-shop) | `OpenEventCommand` accepts an Unknown that rolled a shop, Treasure or combat | P09 (event commands) | S3 (latent) | Fixed (CO9 merge, November 21, 2026) | November 20, 2026, RN10 report | a Lane C step (CO9) |
| [BUG-026](#bug-026-the-event-panels-deferred-focus-has-no-in-tree-guard) | The event panel's deferred focus has no in-tree guard (BUG-017's pattern) | P09 (event screen) | S4 | Fixed (CO12 merge, November 22, 2026) | November 20, 2026, RN10 report | a Lane C step (CO12) |
| [BUG-027](#bug-027-burglars-roll-shows-no-effect-text) | Burglar's Roll shows no effect text, only "(1 use this combat)" | P03 / P07 (effect text) | S3 | Fixed (TX1 merge, November 20, 2026) | November 20, 2026, user | TX1 |
| [BUG-028](#bug-028-a-weapons-own-effects-dont-show-in-unit-detail) | A weapon's own effects (lifesteal, extra strikes) don't show in unit detail's gear row | P07 (unit detail) | S3 | Can't reproduce (TX1, November 20, 2026: the gear row already shows a weapon's effect lines and AtkX; regression cases added) | November 20, 2026, user | TX1 |
| [BUG-029](#bug-029-the-node-placeholder-says-this-node-isnt-built-yet) | The node placeholder says "This node isn't built yet", but now shows only for an Unknown with no event to draw | P08 (campaign UI) | S4 | Fixed (RN12 merge, November 21, 2026) | November 20, 2026, BF6 report | RN12 |
| [BUG-030](#bug-030-the-save-debug-panels-doc-calls-its-end-player-phase-the-only-battle-save) | The save debug panel's doc calls its End Player Phase the only battle save besides Begin | P00 (debug panel) | S4 | Fixed (BF7 merge, November 22, 2026) | November 20, 2026, BF6 report | BF7 |
| [BUG-031](#bug-031-a-continued-runs-instance-ids-drift-from-an-uninterrupted-ones) | A continued run's instance ids drift from an uninterrupted one's, so heirloom reactions can fire in another order after a quit | P08 / P01 (campaign session) | S2 | Fixed (RN11 merge, November 20, 2026) | November 20, 2026, RN11 | RN11 |
| [BUG-032](#bug-032-the-campaign-maps-class-doc-says-every-non-combat-node-goes-to-the-placeholder) | The campaign map's class doc says a non-combat node goes to the placeholder | P08 (campaign UI) | S4 | Fixed (CO10 merge, November 22, 2026) | November 21, 2026, RN12 report | the next Lane B step touching `ui/campaign/` (CO10) |
| [BUG-033](#bug-033-event-busmd-lists-only-five-campaign-commands) | event-bus.md lists only five campaign commands; about 20 more exist | P01 / P08 (docs) | S4 | Fixed (CO20, November 23, 2026) | November 21, 2026, RN12 report | — |
| [BUG-034](#bug-034-leavenodecommand-doesnt-wait-for-an-open-events-seats) | `LeaveNodeCommand` doesn't wait for an open event's seats to choose; leaving after a pending Fight skips the surprise combat | P08 / P09 (leave rules) | S3 (latent) | Fixed (CO16 merge, November 23, 2026: Leave at an open event is refused until every seat chose and any surprise combat was fought) | November 21, 2026, CO9 report | CO16 (Lane C) |
| [BUG-035](#bug-035-the-intents-refresh-after-each-player-action-blocks-the-main-thread) | The intents refresh after every player action blocks the main thread: 0.78 s (release) and 6.3 s (debug) on the boss board | P05 (intents) | S3 | Part fixed (EN16 merge, November 22, 2026: debug 6.1 → 1.1 s on the boss board) | November 21, 2026, EN15 report | the release part (0.25 s key, 0.83 s boss, main thread): EN18, after CO2 (P05 question 53 (a)) |
| [BUG-036](#bug-036-a-resumed-frozen-maps-turn-cant-end) | A resumed frozen map's turn can't end: `PhaseRunner.seats_with_units` counts only the map's own seats, not a sender's unit on it | P11 (co-op battles) | S2 (latent: only tests send) | Fixed (CO2 merge, November 22, 2026) | November 22, 2026, CO1 report | CO2 (Lane D) |
| [BUG-037](#bug-037-a-map-that-received-units-keeps-its-speed-bonus) | A co-op map that received units keeps its speed bonus: `SeatOutcome.has_received_units` is never set | P11 (co-op rewards) | S3 (latent: co-op battles show the placeholder) | Fixed (CO5 merge, November 22, 2026) | November 22, 2026, CO2 report | CO5 (Lane B, owns `campaign_session.gd`) |
| [BUG-038](#bug-038-a-unit-sent-to-a-frozen-map-with-no-free-tile-never-lands) | A unit sent to a frozen map with no free tile never lands, so the run waits forever | P11 (co-op battles) | S2 (latent) | Fixed (CO3 merge, November 23, 2026); decided (user, November 22, 2026): the unit returns to its sender's map and the frozen map counts as unreachable, so `is_run_lost()` can end the run | November 22, 2026, CO2 report | CO3 (Lane D) |
| [BUG-039](#bug-039-loot-found-on-a-map-never-reaches-the-run) | Loot found on a battle map (`MapState.found`) is never given to the run at the battle's end, and is filed under the looting unit's seat rather than the map owner's | P04 / P08 (map loot, battle end) | S2 (solo too: confirmed by CO14, all map loot was lost) | Fixed (CO14 merge, November 23, 2026) | November 23, 2026, CO8 report | Lane B (with CO14) |
| [BUG-040](#bug-040-a-1-seat-multiplayer-run-that-loses-never-ends) | A 1-seat multiplayer run that loses its battle never ends | P11 (run end) | S4 | Fixed (CO14 merge, November 23, 2026) | November 23, 2026, CO8 report | Lane B (with CO14) |
| [BUG-041](#bug-041-skipping-playback-never-stops-for-key-moments) | Skipping playback never stops for key moments: `FactPlayback.pause_hook` is never set, though `battle_view.gd`'s skip doc says the skip stops for them | P07 (playback) | S3 | Fixed (EN19 merge, November 23, 2026: the controller sets `pause_hook` to CO15's stop rule, shared; skip and hold stop in solo and co-op) | November 23, 2026, CO15 report | EN19 (Lane A) |
| [BUG-042](#bug-042-the-enet-pair-case-times-out-under-full-run-load) | The ENet pair case ("two instances on one machine play a battle to its end") times out at its 150 s step limit during a full run while other builds run on the machine; it passes alone | P10 (tests) | S4 (test only) | Fixed (BF11 merge, November 23, 2026: a 60 s no-progress limit per instance, 270 s in all, a 300 s backstop; a failure names the step, each map's last fact, the seed and both logs' tails) | November 23, 2026, NT7 merge | BF11 (Lane E) |
| [BUG-043](#bug-043-mirrors-diverge-on-a-map-two-seats-share) | Mirrors diverge on a map two seats share (a swap's visitor, a landed send): `PhaseRunner.start()` drops a seat from `seats_to_start` and `end_turn()` adds it to `ended_seats` without recording a fact, so after the first seat's Start or End Turn every mirror's state differs from the host's | P11 / P10 (co-op battles on mirrors) | S2 (latent until clients play co-op battles live) | Fixed (CO23 merge, November 23, 2026: `TURN_ENDED = 52` and `SEAT_STARTED = 53` on every map, solo too; CO16's 4-seat case keeps its swap) | November 23, 2026, CO16 report | CO23 (Lane D) |
| [BUG-044](#bug-044-capture-group-491-fails-every-capture-run) | Capture group 491 (NT6's) logs "No multiplayer peer is assigned" from `net_relay.gd:505` since NT7 and CO15, so every capture run reports FAIL at every size though the shots are fine | P10 / P14 (captures) | S3 (every UI step's capture verdict is FAIL) | Fixed (BF11 merge, November 23, 2026: group 491 gives its calls Godot's offline peer; no game change) | November 23, 2026, CO13 report | BF11 (Lane E) |
| [BUG-045](#bug-045-the-intent-rule-tooltip-draws-off-the-top-edge) | The intent rule tooltip on a unit in the map's top row draws off the screen's top edge | P07 (battle HUD) | S4 | Fixed (EN19 merge, November 23, 2026: flips below, clamped on both axes, re-placed as the camera moves) | November 23, 2026, CO13 report | EN19 (Lane A) |
| [BUG-046](#bug-046-a-co-op-battle-stalls-after-one-map-ends) | A co-op battle can stall after one map ends: the other map's enemy phase ends, the darkness advances, then no player phase starts and the map never finishes | P11 (co-op battles) | S2 (a co-op battle can't finish; about half of BF11's full runs) | Closed, not an engine bug (CO23 merge, November 23, 2026): on both seeds one map was won and the other froze when its last player unit fell, which is correct; the pair's test driver never sent to the frozen map or played units on a teammate's map. CO23 fixed the driver, unpinned the seed and added both seeds as harness cases | November 23, 2026, BF11 report | Lane D (CO23 if noted) |
| [BUG-047](#bug-047-a-client-mirror-loses-its-battle-at-a-forfeit) | Two `ClientMirror` gaps at a forfeit: any accepted campaign batch during a battle closes the mirror's battle, so a forfeit closes every client's battle; after the battle ends a mirror keeps the forfeited seat, so the host's next capture is refused ("a capture for seats") | P10 / P11 (mirrors) | S2 (latent until clients play live) | Fixed (CO18 merge, November 23, 2026: only the battle-end batch closes a mirror's battle; a mirror accepts a capture without a seat that left; no mirror calls `forfeit()`) | November 23, 2026, CO22 report (P11 question 152) | CO18 (Lane E) |
| [BUG-048](#bug-048-a-client-leaving-an-individual-event-is-sometimes-refused) | Intermittent: CO16's "a client leaves the individual event on every mirror" (`tests/net/coop_campaign_cases.gd`) is sometimes refused with "seat 0 hasn't chosen at the event", and the battle-hash case after it then checks nothing | P11 / P10 (events on mirrors) | S3 (a test flake, or a real ordering race in BUG-034's Leave rule) | Fixed (BF12 merge, November 23, 2026): a test bug. A full convoy refused the host seat's event choice, so none was sent; the choice now falls back to scrapping the new item, and a seat with no valid choice fails a check | November 23, 2026, BF11 report | Lane C |
| [BUG-049](#bug-049-a-held-pad-trigger-turns-fast-forward-back-on-after-a-stop) | After a key-moment stop, a pad trigger (RT) held past halfway may turn fast-forward straight back on: `_unhandled_input` counts every non-echo `fast_forward` event with `is_pressed()` as a press, and a held trigger keeps sending motion events | P07 / P11 (fast-forward) | S3 (by reading, not reproduced; in co-op since CO15) | Fixed (UL12 merge, November 23, 2026: a press counts only on the up-to-down edge, for keys, buttons and the trigger) | November 23, 2026, EN19 report | Lane A |
| [BUG-050](#bug-050-the-enet-pair-hosts-battle-stops-moving-in-full-runs) | The ENet pair case's host stops moving for 60 s mid-battle in some full runs (`PAIR FAILED host: nothing moved for 60 s, at step PLAY`); the client then loses the host and fails as "the run's session ended". Passes with `net` alone | P10 (tests, or a real stall) | S2 until shown to be the test | Fixed (BF13, November 23, 2026): the test's driver | November 23, 2026, UL12 report and the UL12 and CO17 merge | — |
| [BUG-051](#bug-051-netlog-calls-get_unique_id-on-a-closed-peer) | When an ENet client loses its host, `NetLog.info` in `steam_network.gd`'s disconnect handler calls `multiplayer.get_unique_id()` on a peer that is set but closed; the engine prints "ERROR: The multiplayer instance isn't currently active" | P10 | S4 | Fixed (BF15, November 24, 2026) | November 23, 2026, BF13 report | — |
| [BUG-052](#bug-052-co-op-starting-heirloom-route-loop-locks-the-host-out) | Co-op starting heirloom: once one player picks, the host's screen reloads every frame and that player is locked out; the client sends a route notice in a loop | P08 / P11 | S1 | Fixed (BF14's loop fix, then P18 RC1, November 24, 2026: one routing authority, the team waits on the offer) | November 23, 2026, the user's live network test | — (live recheck at NT8b) |
| [BUG-053](#bug-053-cleave-splashes-the-unit-it-struck) | Cleave's 2 splash damage also hits the unit the attack struck, so that unit takes the hit plus 2 (Brute, Brigand Captain, Powder Baron) | P01 / P05 (effects, content) | S2 | Fixed (BF16, November 25, 2026) | November 24, 2026, the user's playtest | — |
| [BUG-054](#bug-054-starting-heirloom-tags-cover-the-other-choices) | On the starting heirloom screen, a card's keyword tags cover the other choices | P07 / P08 (UI) | S3 | Open | November 24, 2026, the user's playtest | UL13 (Lane A) |
| [BUG-055](#bug-055-editor-resaves-change-the-build-fingerprint) | An editor resave of a map or data file (an added `uid`, a scene given a random `uid`) or a different line-ending checkout changes the build fingerprint, so two machines running the same commit are refused as a build mismatch | P10 | S2 | Fixed (BF15, November 24, 2026) | November 23–24, 2026, the user's two-machine test | — |
| [BUG-056](#bug-056-the-boss-s-end-in-co-op-strands-clients) | In co-op the Boss's End run checks only that the Boss is beaten, routes only the host, and leaves clients on a dead victory overlay | P08 / P11 | S1 | Open | November 24, 2026, P18 inventory | P18 RC4 |
| [BUG-057](#bug-057-a-refused-leave-gives-up-unclaimed-rewards) | On the co-op results overlay, a Leave the rules refuse still sends that seat's skip commands first, giving up its unclaimed rewards | P08 / P11 | S2 | Open | November 24, 2026, P18 inventory | P18 RC4 |
| [BUG-058](#bug-058-a-co-op-start-can-read-as-a-rejoin) | Over ENet a normal co-op start can read as a rejoin: the run's data can reach a client before the route to Loading, so the client opens its offer alone | P11 | S2 | Fixed (P18 RC1, November 24, 2026) | November 24, 2026, BF14 report (P11 question 193) | — |
| [BUG-059](#bug-059-an-attacker-is-caught-in-its-own-area) | An attacker next to its target is caught in its own target-centered area: a Raider at range 1 takes its own 3 Trample splash, a Hexer or Hex Matron at range 1 loses 1 Stance to its own Curse | P01 / P05 (effects, content) | S2 | Fixed (BF16, November 25, 2026) | November 24, 2026, BF16 report (P01 question 89) | — |

### BUG-001 No Block at the start of combat

- **Reported:** no unit gets any natural Block at the start of combat.
- **What the vision says:** Block's base value is **0 for every unit**; all Block comes from
  phase-tied effect text (traits, weapons, equipment, heirlooms), refreshed at the side's Phase
  Start (game-vision.md, Block). In M1 the only Phase Start source is the Drengr's **Vanguard**
  ("Phase Start, while no ally is closer to an enemy: +3 Block"); the Battle Medic's Shelter staff
  gives Block as an action. So zero Block on turn 1 is the vision's rule unless Vanguard should
  have fired.
- **To check:** whether the first player Phase Start (after the opening swap window and Start)
  applies Phase Start effects at all. UI7's windowed run showed the Drengr's 3 Block only at the
  turn 2 player phase.
- **Decided** (user, November 7, 2026): no base Block. Vanguard fires at the first player Phase
  Start when its condition holds, as at every other. The current playtest doesn't reproduce the
  report, so it is closed as **Can't reproduce**; reopen it if a turn 1 Vanguard is seen missing.

### BUG-002 The forecast's crit chance ignores current Stance

- **Reported:** critical chance in the preview isn't populated dynamically from current Stance.
- **Expected** (game-vision.md, the damage stages and Stance and Exposure): a hit can crit only if
  the defender's Stance was 0 before that hit; a hit that gets real damage through lowers Stance
  by 1. So the forecast's crit line follows each strike: shown for a defender already Exposed,
  shown from the strike that breaks the last Stance onward in a multi-strike exchange, and absent
  while Stance remains.
- **Fixed** in BF1 (668da72, merged November 19, 2026): the Crit cell and each "Hit N" section read that strike's own rolled crit ("25%", "— · 25%", "—"). Regression: forecast cases for an Exposed defender, Stance 1 hit twice and Stance 2 hit once.
- **To check:** `CombatForecast` (`defender_exposed`, the side's `crit_chance`, -1 when not
  rolled) and how `forecast_view_model.gd` shows it.

### BUG-003 save-system.md says a battle retry repeats ids

- **Found:** CC10's report. A `BATTLE_RETRY` restart repeats the rolls but not the instance ids,
  because the campaign file keeps the counter after Begin minted the army and setup. Nothing
  reads ids for meaning.
- **Recommended fix** (P02 question 22): correct the doc in CC9.
- **Fixed** in CC9 (dfad90b, merged November 19, 2026): save-system.md's Instance ids section says a restarted battle mints new ids from the counter Begin saved after minting; only the rolls repeat. `InstanceIdSaveSection`'s class doc and the P01 plan (about line 516) still say "mints from Begin's value", true only read as "after minting".

### BUG-004 An enemy with an attack intent moves and doesn't attack

- **Reported:** the intents showed two enemy attacks. In the enemy phase the first enemy moved but
  didn't attack, and the second enemy attacked the first enemy's intended target.
- **Run:** solo, seed `52FC-D7F9-0BD5-D`, `m1_greybox`, resumed battle (floor 1, node 1); most
  likely the turn 2 enemy phase (`s0#56`–`s0#95`, the only enemy phase with a long run of steps).
- **Log gap:** the log has no line per enemy action, so it shows neither the plans nor a rejection.
  `EnemyAI.next_command` turns a plan that fails `UnitTurnCommand.validate` into a Wait and
  records the diagnostic "*X*'s *kind* plan rejected - *reason*; it waits"; that line isn't in the
  log, so either the plan wasn't rejected or the diagnostic isn't reaching the log.
- **Expected** (game-vision.md, Enemy intentions; `intents.gd` class doc): intents aren't
  committed tiles, and the real phase decides again after each action, so a *miss* can change
  what *later* enemies do. The first enemy to act has had nothing change since the intents were
  computed, so it should carry out the attack its intent showed (a move and attack, hit or miss).
  A move with no attack from the first actor is a bug unless something on its board differed.
- **To check:**
  - whether the first enemy's real plan was rejected and became a Wait (the move then belongs to
    a path the validator refused partway, or the walk and the attack disagree on the end tile or
    range); `EnemyAI.next_command`, `UnitTurnCommand.validate`, `Intents._carry_out`
  - whether the real phase picks the same first actor as `Intents._play` (the NOTE there: same
    enemies, order and tie rule as `EnemyAI.next_plan`); a different first actor with stale
    intents on screen would look like this report
  - whether the board `Intents.compute` reads matches the real enemy phase start (player Phase
    End, darkness, enemy Phase Start effects crossed the same way)
  - why the diagnostic, if raised, isn't in the playtest log
- **Asked the user:** each enemy's class, the second enemy's own intent target, and where the
  first enemy ended (in range of its target or not).

### BUG-005 Unit detail shows the type id, not its name

- **Found:** UI11's report. The unit detail panel shows the type as the id capitalised
  (`unit_detail_view_model.gd`: `unit.unit_type.capitalize()`), on the reading that content has
  no display names.
- **Expected:** every definition carries `display_name` (P01's `EffectCarrierDefinition`), and
  the M1 data fills it ("Battle Medic", "Brute"). The detail looks the type up in the content
  catalog and shows that; the capitalised id is only a fallback for a missing definition.
- **Also check:** the weapon type line (`held.weapon_type.capitalize()`) and any other id shown
  as text in the battle UI.

### BUG-006 NetLog raises an engine error once the peer is cleared

- **Found:** O3's windowed run logs "No multiplayer peer is assigned" from `net_log.gd` on most
  logged events once the menus start. O3 didn't touch that file.
- **Likely cause** (read, not run): `SteamNetwork.leave_lobby()` sets
  `multiplayer.multiplayer_peer = null`, and `NetLog._log` calls `multiplayer.get_unique_id()` on
  every line. Its comment says that returns 1 with no peer, which holds only for the default
  offline peer. `SceneRouter` calls `leave_lobby()` on entering the start, save select and main
  menu screens, so every solo session reaches this.
- **Expected:** logging is silent with no peer and shows peer 1, as in solo play.
- **Fixed** in BF1 (668da72, merged November 19, 2026) by a guard in NetLog (logging only; restoring an offline peer would change `is_server()` and `get_unique_id()` for every caller). Regression: a logging case after `leave_lobby()` reads `[peer 1]` with no engine error.
- **To check:** whether `leave_lobby()` should restore an offline peer rather than null, or NetLog
  should guard the call. `steam_network.gd` guards on `multiplayer_peer != null` elsewhere.

### BUG-008 A mirror keeps a used-up consumable

- **Found:** CT5's report (read, not run in multiplayer). On a client mirror, a consumable whose
  last use is spent stays in the Pouch, so the mirror's state hash differs from the host's.
- **Cause:** `CombatState._is_used_up` (`combat_state.gd:747`) returns false at the first effect
  with no charges; the host's check skips such effects instead. It hits every consumable whose uses
  the loadout counts: the Elixir, stat boosters, ingredients and the Key.
- **Expected:** host and mirror drop the item at the same use, and the hashes match.
- **Fix:** `return false` becomes `continue`, with a regression test comparing the mirror's hash
  after an Elixir's last use (CT5's Hit-booster test compares only Hit).
- **Fixed** in BF1 (668da72, merged November 19, 2026). Regression: the mirror's hash matches the host's after an Elixir's last use; with the fix reverted, the mirror refuses the batch and keeps the Elixir.

### BUG-009 A second copy of a heirloom never reaches the battle

- **Found:** RN2's report (read, not run). `CampaignSession._add_heirlooms` dedups carriers by
  `"seat:content id"`, so a seat holding a curse twice brings only one copy into battle.
- **Expected:** curses may repeat and copies stack (P09 question 3); `SeatRun.heirlooms` already
  saves copies. Each copy becomes its own carrier; how copies stack is CT9's.
- **Fix in RN3,** which rebuilds the battle bridge, with a regression test bringing a curse held
  twice into a battle.
- **Fixed** in RN3 (9e34098, merged November 13, 2026). Each copy becomes its own carrier
  (`seat:id:copy index`), and each copy's campaign-lane counters write back to its own saved
  entry. Regression: "curse twice: two carriers in battle…" and "…each copy's lane is written back
  to its own entry".

### BUG-010 Save Select shows a stale floor

- **Found:** RN2's report. `CampaignData.floors_climbed`, shown on Save Select, doesn't follow
  `CampaignRunState.floor_number`.
- **Expected:** Save Select shows the run's current floor.
- **Fix in RN3,** with a test that choosing a node updates what Save Select reads.
- **Fixed** in RN3 (9e34098, merged November 13, 2026): every save `CampaignService` makes sets
  `floors_climbed` to the run's floor. Regression: "choosing a node moves Save Select's floor to
  the run's (BUG-010)".

### BUG-011 A test run deletes another run's override

- **Found:** merging RN4 in the main checkout. A run cut off at 16:02 left `bandit-bash/override.cfg`
  behind (the next run refused to start, as designed). Once removed, a new run started, and the cut-off
  run, still alive in the background, finished and ran its `end_run()`, which deleted the new run's
  override. The later user-folder suites then had no test folder: ui/display and ui/input skipped 3
  screen cases ("needs a test user folder") and still reported PASS. Rerun alone, both were clean.
- **Cause** (read): `tools/run_tests.sh` `end_run()` does `rm -f "$OVERRIDE"` without checking the
  file names this run's folder (`custom_user_dir_name="$TEST_DIR_NAME"`).
- **Harm seen:** only Godot log files reached the real user folder; saves were untouched. The guards in
  the UI and sessions suites did their job, so this is lost coverage, not lost data.
- **Expected:** a run removes `override.cfg` only when it still names this run's folder; a suite that
  skips because the folder went missing makes the run fail, not pass.
- **Workaround:** one runner per checkout at a time; after an interrupted run, wait for its Godot
  processes to exit before starting another.
- **Priority:** low (user, November 14, 2026): fix when a runner step or a free slot comes up.
- **Fixed** in O6 (`feature/O6`, not yet merged, November 16, 2026). The runner writes no
  `override.cfg` at all: each suite's Godot gets its own user folder through its own `APPDATA`
  (`XDG_DATA_HOME` on Linux, `HOME` on macOS; both unchecked), in the run's log folder, so no run
  can delete or block another's. The ui and sessions guards read the folder Godot resolved
  (`OS.get_user_data_dir()`) instead of the project setting, and the runner fails any suite that
  prints "needs a test user folder". Regression: a copy of the runner with the per-suite folder
  switched off makes `sessions` FAIL on its skipped cases instead of PASS; two full runs at once,
  in one checkout and in two worktrees, both pass.

### BUG-007 Test runs in two worktrees share one user folder

- **Found:** CT6's report. On a clean `dev`, `sessions` failed `_test_service_rng_campaign_streams`
  once while RN1's worktree was also running tests; it passed on a rerun.
- **Cause** (read, not run): `tools/run_tests.sh` writes an `override.cfg` with
  `config/custom_user_dir_name="bandit_bash_tests"`, a fixed name, so every worktree's run uses
  the same `user://` folder. O4 serialised the suites that use it within one run, but two runs at
  once still collide.
- **Expected:** each run gets its own test user folder, removed when the run ends, so parallel
  build agents never interfere.
- **Workaround until fixed:** a `sessions` or `save` failure during another worktree's run is
  rerun once before it counts.
- **Seen again:** RN1's report: `ui/board` failed 3 save cases ("Already exists") while CT6's worktree ran; it passed alone and on a rerun. So any suite that writes to `user://` is affected.
- **Fixed** in BF2 (76774d4, merged November 12, 2026). Each run names its folder
  `bandit_bash_tests_<pid>_<random>` and prints it. It deletes only that folder, at the end and on
  interrupt, after copying its `logs/` into the run's log folder. The ui and sessions guards accept
  the `bandit_bash_tests` prefix. Regression: with the old runner, concurrent runs collided in 2 of 3
  rounds; with the fix, none did. The old folders `%APPDATA%\bandit_bash_tests` and
  `bandit_bash_tests_r5` are left for the user to delete.

## Closed bugs

| ID | Title | Area | Sev | Closed as | Verified |
|----|-------|------|-----|----------|----------|
| [BUG-001](#bug-001-no-block-at-the-start-of-combat) | No unit has Block at the start of combat | P01 / P02 / P03 | S2 | Can't reproduce (November 7, 2026; no base Block, Vanguard fires on turn 1) | — |
| [BUG-007](#bug-007-test-runs-in-two-worktrees-share-one-user-folder) | Test runs in two worktrees share one user folder | P14 (runner) | S3 | Fixed (BF2, 76774d4, November 12, 2026) | — |
| [BUG-009](#bug-009-a-second-copy-of-a-heirloom-never-reaches-the-battle) | A second copy of a heirloom or curse never reaches the battle | P08 / P09 | S2 | Fixed (RN3, 9e34098, November 13, 2026) | — |
| [BUG-011](#bug-011-a-test-run-deletes-another-runs-override) | A test run's cleanup deletes another run's `override.cfg` in the same checkout | P14 (runner) | S3 | Fixed (O6, 57e51eb, November 16, 2026: no `override.cfg` at all; a missing-folder skip fails the suite) | Two runs at once in one checkout, both ALL PASS |
| [BUG-010](#bug-010-save-select-shows-a-stale-floor) | Save Select's floor doesn't follow the run's floor | P08 | S4 | Fixed (RN3, 9e34098, November 13, 2026) | — |
| [BUG-013](#bug-013-a-map-can-need-a-door-no-one-can-open) | A map can put a required route behind a door the army can't open | P04 (maps, map check) | S2 | Fixed (MP12, 419ec4a, November 18, 2026: doors, levers and every map object are drawn on the board; two levers added inside rooms; the map check proves every map reachable) | The user's playtest, pending |

### BUG-012 Loading the map pools in a test leaks resources

- **Found:** MP10a's report. Calling `CombatMapPools.load_default()` inside the ui/board suite's
  route case leaves 74 objects and 58 resources in use at exit. The battle screen's own call to the
  same function doesn't.
- **Cause:** not investigated. MP10a worked around it in the test.
- **Expected:** loading the pools from a test frees everything at exit, as the battle screen does.
- **Harm seen:** an exit warning only; no wrong result.

### BUG-013 A map can need a door no one can open

- **Found:** the user's playtest (November 18, 2026): maps have doors with no lever and no key to
  open them, so the map can't be finished.
- **Read so far:** every door on the M2 maps has a lever in its group except the Hall's (a key
  door to its chest room, which is optional loot): `old_mill`, `watch_post` (the leader behind a
  lever door) and `gatehouse` (two levers). So the likely cause is a lever that can only be
  reached through its own door, or a lever the player can't find. `MapCheck` checks no
  reachability at all, so nothing caught it. Which map the user saw is not yet known.
- **Expected** (the user's rule): every required tile (objectives, the leader slot, the deployment
  zone's way out, every enemy slot an objective needs) is reachable without a key. Only optional
  content, such as shortcuts and loot, sits behind a key-only door. Every lever door's lever is
  reachable from the player's side without passing that door.
- **Fix in P04 MP12:** the map check enforces the rule, every map passes it, and the rule is
  written into map-objects.md.
- **Cause (MP12, November 18, 2026):** no door truly lacked a lever. The battle board drew only terrain: a door looked like an open gap units couldn't enter, and its lever, and every chest, searchable, passage and brazier, was invisible. Two maps also had traps: on `watch_post` and `old_mill` the only lever stood outside its door, so an enemy could shut units in (on a Rout map with every survivor inside, the battle could never end).
- **Fixed in MP12** (merged November 18, 2026): each map object is drawn (`map_object_mark.tscn`, placeholder symbols, dimmed once spent, a tag linking levers to doors and passage ends) and named with its state in the tile panel; a second lever inside each trap room, (4,1) on `watch_post` and (2,3) on `old_mill`; `MapCheck.Rule.REACHABILITY` fails any map whose required tiles or levers can't be reached without a key, or whose lever-door room has no lever inside; map-objects.md's "Reachable maps" states the rule. **Verify:** the user's next playtest.

### BUG-014 A run's runes never reach the battle

- **Found:** UI14's report (November 18, 2026). Nothing copies a run's runes into
  `CombatState.rune_slots` when a battle starts, and nothing writes them back when it ends. In a
  real run the rune bar shows three empty slots, and a cast or discard in battle doesn't reach the
  run's runes. Battles built by tests fill the slots directly, so every case passes.
- **Harm today:** none seen. No node grants runes yet; the Guildhall (P08 RN9) is their first
  source.
- **Expected:** the battle bridge (RN3's `BattleRequest`) carries the player's runes in, and the
  battle's end writes the remaining runes back, in the save order RN3 set.
- **Fix in P08 RN9.**
- **Fixed** in RN9 (merged November 20, 2026): `CampaignSession.Army.rune_slots` carries the run's
  runes into `CombatState.rune_slots` at Begin, and `BattleResult.runes` writes the remaining ones
  back before grants apply; a cast or discarded rune is gone from the run, and a discard survives
  a quit mid-battle (`rune_bridge_cases`, `rune_resume_cases`).

### BUG-015 The unit panel's Details button can't be clicked

- **Found:** the user's playtest (November 18, 2026): the mouse can't reach the Details button on
  the left unit panel, because the panel shows whichever unit the mouse hovers; leaving the unit
  to reach the button changes or hides the panel.
- **Where:** `ui/battle/unit/unit_panel.gd` (the `# ASSUMPTION` at its Details button: Godot_FE had
  no mouse way to its details screen) and the hover path in `battle_controller.gd`. The key and pad
  binding (`unit_detail`) works.
- **Expected:** a mouse user opens a unit's detail. Proposed in
  [ui-lift.md](../design/ui-lift.md#unit-detail-pop-up): right-click a unit opens it, and the panel
  stops following hover while the mouse is over it.
- **Fix in UL3** (the UI lift's HUD and unit detail step).

### BUG-016 SteamNetwork.local_peer_id() errors once the peer is cleared

- **Found:** BF1's report (read, not run). After `leave_lobby()` sets the peer to null,
  `local_peer_id()` returns 0 with an engine error, while its doc says 1 in solo play: the same flaw
  as BUG-006. The kit's NetLog template carries the same wrong comment.
- **Harm today:** none. It is only called inside a lobby.
- **Expected:** 1 with no error when there is no peer, or a guard at the call.
- **Fix in P10 NT1** (net transport's contract and seats step), which owns `SteamNetwork`.
- **Fixed** in P10 NT1 (merged November 19, 2026): the guard is in `local_peer_id()`. Regression: `tests/net/gate_cases.gd`; after `leave_lobby()`, `local_peer_id()` returns 1 with no engine error; with the fix reverted it returns 0 with the error.

### BUG-017 Choosing a map node by keyboard logs a grab_focus error

- **Found:** UL7's report, confirmed on clean `dev` before UL7. The campaign walk logs
  `grab_focus: !is_inside_tree()` once when the keyboard chooses a node.
- **Harm seen:** none: an engine error line; the choice goes through.
- **Likely cause** (not checked): focus is asked of a control that is leaving or not yet in the
  tree as the screen changes.
- **Fix:** with the next campaign-map step (RN7 or RN10), or a bug-fix step.
- **Fixed** in RN7 (merged November 19, 2026): `PauseMenu.open()` queued a focus grab that ran after the scene change had taken the menu out of the tree; the grab now does nothing unless the menu is still open and in the tree. Regression: a logger in the campaign walk fails on any `grab_focus` error. `node_placeholder_screen.gd` has the same deferred pattern (a design item).

### BUG-018 Fact playback holds the next batch for the last fact's full wait

- **Found:** UL6's report (read, outside its lane). `scripts/sessions/fact_playback.gd` counts a
  wait down only while facts are queued, so the wait after a batch's last fact runs only once the
  next batch arrives, and holds that batch's first fact for the full time however long the player
  took.
- **Harm:** playback feels laggy after every command; UL6's 1.0 s strike beats (RF-027) make it
  plain, and it would skew the exit playtest's pacing judgement.
- **Expected:** a wait counts down in real (playback) time whether or not more facts are queued.
- **Fix in BF3,** a small fix step before the M2 exit playtest.
- **Fixed** in BF3 (8a0c59b, merged November 19, 2026): `FactPlayback.advance()` counts the wait down before checking the queue, so the last fact's wait runs out while nothing is queued; a batch arriving mid-wait waits only what is left. Regression: `tests/sessions/playback_wait_cases.gd` (7 cases failed on the old code).

### BUG-019 Player units can't attack breakable map objects

- **Reported** (user, November 19, 2026): kegs and walls aren't targetable.
- **Cause** (read): the rules support it. `ExchangeResolver` takes a map object as the defender
  (no counter, Stance or crit; `MapObjects.broken`), and the validator accepts "the defender an
  enemy or a map object". But `ui/battle/input/turn_input_model.gd` builds the Attack option's
  targets from `state.units_of(ENEMY)` only, so standing debris and powder kegs never appear.
  Enemies attack kegs through EN9's AI. "Walls" here are debris (breakable walls were folded into
  it); spiked walls are terrain and never breakable.
- **Expected** (map-objects.md, Rules): breaking an object is an attack on it; the attacker hits
  its Defense or Resistance, the object never counters, and splash damages it.
- **Fix in BF4,** before the M2 exit playtest.
- **Fixed** in BF4 (merged November 20, 2026), with the user's choice (P07 question 42): breakables have their own **Demolish** action (after Staff in the menu; red tiles; the forecast titled "Demolish <object>", with no counter, crit or Stance, and a keg's blast and splash previewed). Attack lists only enemies. Demolish sends the same attack command, so the rules, save and network are unchanged. Regression: `tests/ui/battle/input/object_attack_cases.gd`.

### BUG-020 A broken breakable's token stayed on the board

- **Found and fixed** in BF4 (merged November 20, 2026): breaking debris or a keg left its token
  drawn on the board after the object was gone from the map. It now fades out with the
  `defeat_time` fade (a marked assumption).

### BUG-021 An Infused Basic weapon scraps for 0 gold

- **Reported** by RN8 (unconfirmed): in the Armory captures, the starting "Infused Simple Sword"
  (Basic) traded in for 0 gold.
- **Expected** (items.md, Rarity and prices): a modified item's price is its base price plus net
  points × the kind's step value, and it scraps at 20% of that. Infuse is 0.5 points, so an
  Infused Basic weapon is priced 10 and scraps for 2.
- **Likely cause** (RN8's guess): the infusion's `item_points` is 0 or unset, in RN7's scrapping
  or the event data, not in the Armory. Confirm with a case on `Prices.item_scrap_value` first.
- **Orchestrator check** (November 20, 2026): `Prices.modification_points` sums stat deltas plus
  each granted effect's `EffectDefinition.item_points`, and no `.tres` in `data/` sets
  `item_points`, so every granted effect counts 0 points. An infusion that grants an effect is
  therefore worth its base price (0 for Basic). Fix in data: each effect an infusion or event can
  grant carries its hand-set points (items.md, Points). EV4 sets them for the effects its events
  grant, where items.md gives a value, and asks for the rest.
- **Fixed** in EV4 (merged November 20, 2026): Infuse's "Hit dealt: heal 2" is now its own effect,
  `data/effects/goblet_infusion.tres`, with `item_points` 1 (items.md). It is the only effect an
  event grants to an item; the other examples are whole-option totals that Prices works out from
  the stat deltas. A case in `tests/events/content_cases.gd` checks an Infused Basic weapon scraps
  for 2, Upgrade Gear for 5 and Forge Resonance for 8.

### BUG-022 An enemy's second move ending in a Wait crashes the enemy phase

- **Found** by EN13 on the Hall key board during an enemy phase: `EnemyPlan.to_command()`
  (`scripts/enemies/enemy_plan.gd`, the `is_second_move` branch) passes an untyped `[]` as the
  path when the second move is a Wait. `UnitTurnCommand.new` expects a typed path, so it raises a
  script error, returns null, and `next_command` crashes.
- **Who hits it:** any enemy with a second move whose second move ends in a Wait; the Bloodhound
  after a kill. The key combat's mini-boss, so it can occur in the M2 exit playtest.
- **Fix in BF5,** before the exit playtest, with a regression case.
- **Fixed** in BF5 (merged November 20, 2026): `to_command()` builds a second move's path as a
  typed `Array[Vector2i]`, filled only for a Move. Before the fix the phase still ended, but the
  enemy never took its Wait: a null command reads as "every enemy has acted". Severity lowered to
  S2 for that reason. Regression: `mini_boss_cases.gd` `_test_blood_scent_wait` and
  `_test_second_move_commands`. BF5 also fixed the same pattern in `boss_cases.gd`.

### BUG-023 An untyped empty literal from a ternary fails in a typed slot

- **Found** by BF5 (tested on 4.7.1): an untyped `[]` or `{}` coming out of a ternary fails at
  runtime when the empty branch is taken and the result goes into a typed Array or Dictionary (a
  typed argument, a typed variable's initial value or a typed return). `PackedStringArray`
  targets convert fine.
- **Latent places,** each behind a null guard:
  - `scripts/effects/effect_engine.gd:1124` (a missing effect instance; Lane D);
  - `ui/campaign/starting_offer_view.gd:210` (no offer; Lane A or B);
  - `tests/ui/victory/victory_cases.gd:96` (a null model shows as a script error, not a failed check).
- **Fix:** a typed local, assigned in an `if`, as BF5 did. `effect_engine.gd` goes in EN14; UL10
  left the other two unchanged, so they go in BF7. EN14 fixed `effect_engine.gd` (merged November
  20, 2026).

### BUG-024 Battles don't save at the end of a player phase

- **Found** by the P11 plan session, confirmed by the orchestrator: save-system.md's checkpoint
  table lists "Battle: end of each player phase" (`save_checkpoint()`), but in real play only
  Begin and Save & Quit (`ui/common/pause_menu.gd`) write a battle. The end-of-phase checkpoint
  is called only from the debug panel (`save_debug_panel.gd`). A crash mid-battle loses every
  move since Begin, solo included.
- **Fix in BF6** before M3 (a solo run must be resumable): save at the end of each player phase.
  P11 CO2 then extends it to co-op, where each map checkpoints at the end of its own player phase
  (P11 question 39).
- **Fixed** in BF6 (merged November 20, 2026): the battle screen saves (`save_checkpoint()`) as
  the batch holding the player side's Phase End resolves, before its playback. That batch also
  holds the enemy phase and the next player Phase Start, so a resume opens at the start of the next
  player phase and re-runs nothing. A phase end that finishes the battle is saved by the battle's
  end instead. Regression: `tests/ui/battle/phase_save_cases.gd`. P00 questions 30–32 hold the
  defaults, to confirm.

### BUG-025 OpenEventCommand accepts an Unknown that rolled a shop

- **Found** by RN10: `OpenEventCommand.validate` (`scripts/events/`) checks only the map's node
  type, not `CampaignRunState.node_type()`, so it would accept an Unknown that rolled an Armory,
  a Guildhall, a Treasure or a combat. Only the routing keeps it from being sent. Latent; on the
  network (NT3 onward) a forged command could reach it.
- **Fix:** validate against `node_type()`, with a case.
- **Fixed** in CO9 (merged November 21, 2026): `OpenEventCommand.validate` also checks
  `CampaignRunState.node_type()`; regression in `tests/events/team_apply_cases.gd`.

### BUG-026 The event panel's deferred focus has no in-tree guard

- **Found** by RN10's walk: `event_panel.gd` calls `focus_first.call_deferred()` without checking
  it is still in the tree (BUG-017's pattern), so leaving in the same frame the outcome shows logs
  a `grab_focus` error. The walk now defers its press. Fix as BUG-017 was.

### BUG-027 Burglar's Roll shows no effect text

- **Reported** by the user (heirloom bar tooltip): "Always: (1 use this combat)", so the player
  can't tell what it does.
- **Cause:** its effect (`burglar`) has charges and no operations; `map_objects.gd` reads it by id
  to open a chest or door without a Key or Lockpick. `describe()` builds text from operations, so
  only the charge note is left.
- **Expected** (heirlooms.md): "Once per combat, Your Unit can open a chest or door without a Key
  or Lockpick (still its action)".
- **Fixed** in TX1 (merged November 20, 2026): `EffectDefinition.written_text` replaces the built
  text when set; Burglar's Roll, the Key and the Lockpick use it (P01 questions 64 and 68).
  Regression: `tests/effects/effect_text_cases.gd` and `tests/content/effect_text_content_cases.gd`.

### BUG-028 A weapon's own effects don't show in unit detail

- **Reported** by the user: a weapon's specials (lifesteal, multiple strikes) aren't on the unit
  detail panel. `DetailGearRow` shows a weapon's profile *or* an item's effect text, so a weapon's
  effects never show. Check that a weapon's strike count (AtkX) is in its profile as well.
- **Can't reproduce** (TX1, November 20, 2026; P01 question 70): `DetailGearRow` already shows a
  weapon's effect lines and its AtkX. Regression: `tests/ui/battle/unit/gear_row_cases.gd` and
  capture 415 (unit detail with Life Tap). Reopen it if a weapon's special is seen missing.

### BUG-029 The node placeholder says "This node isn't built yet"

- **Found** by BF6: since RN10 and RN11 the placeholder (`ui/campaign/`) shows only for an Unknown
  that rolled an event with none to draw, so its copy is stale. It should say what happened (no
  event this time) and let the player go on.
- **Fixed** in RN12 (merged November 21, 2026): the note reads "The road is quiet. Nothing happens
  here." (P08 question 71, to confirm), and Continue goes back to the map. Regression:
  `tests/ui/campaign/unknown_screen_cases.gd` by key, mouse and pad.

### BUG-030 The save debug panel's doc calls its End Player Phase the only battle save

- **Found** by BF6: `save_debug_panel.gd`'s class doc says its End Player Phase is "the only battle
  save point besides Begin". Since BF6 the battle screen saves at every player phase end.

### BUG-031 A continued run's instance ids drift from an uninterrupted one's

- **Found and fixed** by RN11 (merged November 20, 2026): heirloom and curse carriers lived only
  in `CampaignSession`, made at the run's first battle. After Save & Quit and Continue, the new
  session's next battle made them again, so every later instance id was off by one per held
  heirloom effect. The engine breaks ties between same-rank reactions by instance id, so two
  heirlooms could fire in another order after a quit.
- **Fix:** the carriers are made at each Begin from the run's saved heirloom lanes and dropped at
  the battle's end (`campaign_session.gd`). Regression: the 8 resume checks in
  `tests/ui/campaign/full_run_cases.gd` fail without it.

### BUG-032 The campaign map's class doc says every non-combat node goes to the placeholder

- **Found** by RN12: `ui/campaign/campaign_map_screen.gd`'s class doc says choosing sends the run
  to "the battle for a combat node, the placeholder for any other". Since RN7–RN10 every node
  type has its own screen, and the placeholder shows only for an Unknown with no event to draw.

### BUG-033 event-bus.md lists only five campaign commands

- **Found** by RN12: `docs/design/event-bus.md`, Sessions and commands, lists `ChooseNodeCommand`,
  `LeaveNodeCommand`, `ItemPickCommand`, `OpenEventCommand` and the event commands. About 20
  more campaign commands exist; `docs/design/campaign-run.md` lists them all. Link to it or list
  them.

- **Fixed** in CO20 (November 23, 2026): event-bus.md lists all 36 campaign commands and every
  fact kind with what records it. campaign-run.md lists commands by node and isn't a full list.

### BUG-034 LeaveNodeCommand doesn't wait for an open event's seats

- **Found** by CO9: `LeaveNodeCommand` (`scripts/campaign/`) doesn't check that every seat has
  chosen at an open event. Over the network a teammate's Leave would skip a seat that hasn't
  applied, and leaving after a pending Fight puts the run back on the map without the surprise
  combat. Today only the event panel's disabled Leave button prevents it. Latent until clients
  send commands (NT4, NT5).
- **Fix:** refuse Leave at an event until every seat has chosen and any pending combat has run,
  with a case.

### BUG-035 The intents refresh after each player action blocks the main thread

- **Found** by EN15, measured on the bench boards: after every player action the battle
  recomputes the enemy intents on the main thread. That takes 0.33 s on the key board and 0.78 s
  on the boss board in release, and 1.5 s and 6.3 s in debug. The debug time is inflated because
  the refresh's sandbox keeps verify mode on, while previews turn it off.
- **Fix:** EN16 (layer 5) decides whether the refresh moves to the preview worker or is split
  across frames, and whether the refresh's sandbox needs verify mode. Measure the boss board in
  release before and after.

### BUG-036 A resumed frozen map's turn can't end

- **Found** by CO1: after a frozen map resumes on an arrival, the rule that waits for every seat
  to end its turn (`PhaseRunner.seats_with_units`, `scripts/combat/phase_runner.gd`) counts only
  the seats in the map's `session.seats`. A unit sent from another seat isn't in it, so the
  visiting unit can act but no seat can end the turn. Latent: nothing but tests calls
  `send_unit()` until CO2.
- **Fix:** CO2 makes the receiving map count the sender's seat (for its turn and End Turn), with
  a case where a frozen map resumes and the visitor's seat ends the turn.

### BUG-037 A map that received units keeps its speed bonus

- **Found** by CO2: the receiving map records each sender (`CombatEncounter.senders_of()`), but
  `CampaignSession._collect_seat()` never sets `SeatOutcome.has_received_units`, so the map keeps
  its speed bonus. `campaign_session.gd` belonged to CO7 while CO2 built.
- **Fix:** in `_collect_seat()`, set `outcome.has_received_units` to
  `encounter != null and not encounter.senders_of(map.session_id).is_empty()`, update that
  member's doc, and add a case where a received map loses the bonus.

### BUG-038 A unit sent to a frozen map with no free tile never lands

- **Found** by CO2: a unit with no free tile waits for the target's next Phase Start (P11
  question 12), but a frozen map never reaches one, so the unit never lands, the map never
  resumes and the run waits forever. CO1's behaviour, not changed by CO2.
- **Fix** (decided by the user, November 22, 2026): an arrival that finds no free tile on a frozen
  map returns to its sender's won map, and that frozen map counts as one no unit can reach, so
  `is_run_lost()` can end the run instead of waiting; with a case. Lane D, with CO3.

### BUG-039 Loot found on a map never reaches the run

- **Found** by CO8: `map_objects.gd` records what a unit loots from a map object in
  `MapState.found`, under the looting unit's seat, but nothing applies it to the run when the
  battle ends. Co-op rules (P11 question 25) give loot to the map's owner.
- **Fix:** confirm whether solo applies found loot by another path; then apply `MapState.found` at
  the battle's end to the map owner's run state (pouch, convoy or gold as each kind says), with a
  solo and a co-op case.

### BUG-040 A 1-seat multiplayer run that loses never ends

- **Found** by CO8: a multiplayer session with one seat is neither solo nor co-op for the run-end
  path, so a lost battle leaves it on its map. It predates CO8.
- **Fix:** treat a 1-seat multiplayer run's loss as a solo loss (`SaveService.end_run(false)`), with
  a case.

### BUG-041 Skipping playback never stops for key moments

- **Found** by CO15: `FactPlayback.pause_hook` is never set anywhere, so skipping a phase's
  playback never stops for a key moment (a boss combat, a player unit's death), although
  `battle_view.gd`'s skip doc says it does.
- **Fix:** decide which (set the hook for the key moments the vision names, or correct the doc),
  then build it with a case; solo and co-op alike.

### BUG-042 The ENet pair case times out under full-run load

- **Found** at NT7's merge: in the full run (every suite in parallel, with two other builds running
  on the machine), `enet_dev_cases.gd`'s two headless instances reached the PLAY step but neither
  ended within 150 s. The net suite run alone passed, 264 cases. A known flake until fixed: rerun
  `net` alone.
- **Fix:** make the case hold under load (a limit that scales or a longer one, kept under the
  suite's 450 s), and report the step reached when it fails; no change to the game.

### BUG-043 Mirrors diverge on a map two seats share

- **Found** by CO16: in its 4-seat harness run, a battle with an accepted swap's visitor desynced
  every mirror after the first seat's Start. `PhaseRunner.start()` removes the seat from
  `seats_to_start`, and `end_turn()` records the seat in `ended_seats`, with no combat fact, so a
  mirror following facts never learns either. Any map two seats share hits it: a swap's visitor
  or a landed send. CO16's 4-seat case withdraws the swap before the battle (a NOTE in
  `tests/net/coop_campaign_cases.gd`) until the fix.
- **Fix:** record the per-seat Start and End Turn so mirrors follow them (a fact kind or an
  existing one's field, per the network contract), restore the swap in CO16's 4-seat case and
  remove its NOTE; harness cases with a shared map at 2 and 4 seats.

### BUG-044 Capture group 491 fails every capture run

- **Found** by CO13: since NT7 and CO15 merged, group 491 (`tools/captures/491_*`, NT6's) logs
  "No multiplayer peer is assigned" from `net_relay.gd:505`, four errors per size, so
  `run_captures.sh` reports FAIL at every size. Plain `dev` fails the same way; the shots
  themselves are fine and there are 0 layout issues.
- **Fix:** find which send runs with no peer in the capture (guard it in `net_relay.gd`, or give
  the group the peer it needs), so a clean capture run passes again; no game change.

### BUG-045 The intent rule tooltip draws off the top edge

- **Found** by CO13 (pre-existing): the intent rule tooltip on a unit in the map's top row opens
  above the unit and leaves the screen. CO13 stopped a viewed map's cursor from starting there.
- **Fix:** keep the tooltip inside the viewport (flip below, or clamp), with a case.

### BUG-046 A co-op battle stalls after one map ends

- **Found** by BF11's stricter ENet pair case (two instances, a 2-seat Standard battle): in two of
  four full runs one map ended, and the other, down to a Battle Medic that only waits, finished
  its enemy phase, advanced the darkness and changed objects, then started no player phase and
  never ended. Not load: a pinned seed reproduces it with the net suite alone, failing in 22.6 s.
  In both, the other map had already ended; BF11's unconfirmed guess is that the next round
  waits on a finished map.
- **Seeds:** `9456-F0E2-B5D2-6` (s0, the host's map, last fact #905) and `B072-5FA4-D5CB-1` (s1,
  the client's, last fact #1014). Reproduce by adding `"--run-seed=<seed>"` after `flag` in
  `_launch`'s arguments in `tests/net/enet_dev_cases.gd`.
- **Fix:** find why the round doesn't start on the remaining map (the per-map phase loop and how
  it treats an ended map; related to BUG-043's per-seat Start and End Turn), fix it, and add both
  seeds as pinned headless cases; the pair case goes back to random seeds after.

### BUG-047 A client mirror loses its battle at a forfeit

- **Found** by CO22 (P11 question 152), with or without a resume, in `scripts/net/client_mirror.gd`:
  - any accepted campaign batch during a battle closes the mirror's battle, so the
    `SEAT_FORFEITED` batch closes every client's battle;
  - after the battle ends a mirror still holds the forfeited seat, so the host's next capture is
    refused ("a capture for seats") until the mirror resyncs.
  CO22's harness case works around both (mirrors ask for a fresh sync after the forfeit, and new
  mirrors are built after the battle).
- **Fix:** in CO18, with P11 question 122 (a) (`forfeit()` on every mirror): a mid-battle
  campaign batch keeps the mirror's battle, and the mirror drops a departed seat at the battle's
  end; remove CO22's workarounds from `tests/net/forfeit_resume_cases.gd`.

### BUG-048 A client leaving an individual event is sometimes refused

- **Found** by BF11: in one of three net-suite runs, CO16's case "a client leaves the individual
  event on every mirror" was refused with "seat 0 hasn't chosen at the event" (CO16's BUG-034
  rule), and the battle-hash case that follows checked 0 hashes. Both passed in the other runs and
  in BF11's and the merge's full runs.
- **Fix:** find whether the case sends Leave before the host has applied seat 0's choice (a test
  ordering race: wait for the settle) or the host can take a Leave ahead of an earlier choice
  (a real race over the network), fix whichever, and make the follow-on hash case fail rather
  than pass with 0 checked.
- **Cause** (BF12): `_event_choice` returned null when seat 0's convoy was full (seed
  `13DE-42A0-8D33-4`, 2 seats), and `_send` only logged it. Not a network race: the relay
  resolves commands as they arrive, and a client's Leave is enabled only after its copy of the run
  shows every seat chose. The follow-on battle-hash case already failed with 0 checked.

### BUG-049 A held pad trigger turns fast-forward back on after a stop

- **Found** by EN19, by reading `battle_controller.gd`: `_unhandled_input` treats every non-echo
  `fast_forward` event with `is_pressed()` as a press, and RT (axis 5) keeps sending motion
  events while held, so after a key-moment stop lets go of the hold the next motion turns it back
  on. Not reproduced; it has applied in co-op since CO15 and in solo since EN19.
- **Fix:** count a press only on the trigger's released-to-pressed edge, with a case; also bring
  `battle_controller.gd`'s two lines over 100 characters (24 and 313) to budget if touched.

### BUG-050 The ENet pair host's battle stops moving in full runs

- **Found** in UL12's full run and again in the UL12 and CO17 merge run (November 23, 2026), each
  time under a full run while other builds ran. The host reached PLAY at 3.9 s, then nothing moved
  for 60 s with both maps mid-battle (`s0#359`, `s1#307`); its last lines were the client's
  attack accepted (`s1 CMD arrival 23 seat 1 unit:12 ... -> OK`), the batch and settle sent.
  The host then left the lobby, so the client failed as "the run's session ended". Message counts
  matched both ways. `net` alone passed twice right after. Seed `4EC9-C868-1610-B`.
- **Unknown yet:** whether a seed stalls on its own (as BUG-046's did: a driver that waits on
  something it never does), or load starves an instance for 60 s.
- **Fix:** pin `4EC9-C868-1610-B` and see if it stalls alone; if so, find what the host or the
  driver waits on and fix it; if not, make the no-progress limit hold under load. Add the seed as a
  harness case either way.
- **Fixed** in BF13 (November 23, 2026). The cause was the test's driver, not load, the game or
  the network code. On this seed both maps freeze with nothing to send, so the run is lost
  (`CombatEncounter.is_run_lost()`), and the driver waited for every map to end. The host's battle
  screen ends a lost run, but the host reaches it only if the client's campaign map routes
  everyone (21 of 48 earlier pair logs), so whether the run ended was timing. The seed stalled
  4 of 4 times alone. `PairPeer` now treats a lost run as an end (the host's screen or the driver
  calls `CampaignService.end_battle()`); the seed is a harness case in
  `coop_seeded_battle_cases.gd` (`LOST_SEEDS`). P10 question 55.

### BUG-051 NetLog calls get_unique_id() on a closed peer

- **Found** by BF13 (November 23, 2026): when an ENet client loses its host,
  `steam_network.gd`'s disconnect handler calls `leave_lobby()`, whose `NetLog.info` line calls
  `multiplayer.get_unique_id()` on a peer that is set but already closed. The engine prints
  "ERROR: The multiplayer instance isn't currently active". Seen only on the host-dropped path;
  nothing else goes wrong.
- **Fix:** in `NetLog._log`, also check the peer's connection status before asking its id.
- **Fixed** in BF15 (November 24, 2026): NetLog asks for the id only of a peer that isn't
  disconnected; a closed peer's lines read `[peer 1]`. Regression case in `gate_cases.gd`.

### BUG-052 Co-op starting heirloom route loop locks the host out

- **Found** in the user's live network test (November 23, 2026). The client takes its starting
  heirloom; its screen calls `RunScreen.go()`, which sends `NetRelay.NoticeKind.ROUTE`. The host
  answers with `RunScreen.go()` too, but `RunScreen.of()` reads the local seat's offer, and the
  host's is still open, so it routes everyone to `STARTING_HEIRLOOM` (its own screen reloads,
  resetting its choice). The client's screen opens with its offer closed, so its `_ready()` calls
  `RunScreen.go()` again: a ROUTE and a reload every frame ("NetRelay: received notice, 32 B" then
  "Entered screen STARTING_HEIRLOOM", repeating). Either seat picking first can start it.
- **Cause:** the starting heirloom is a per-seat screen (P11 question 61 lets one seat be on the
  map while a teammate's offer is open), but leaving it is a move for everyone, chosen by the
  host's own seat. The harness takes starting heirlooms by command, never through the screen.
- **Wider than the heirloom** (P18 inventory, November 24, 2026): any client screen whose
  `RunScreen.of()` disagrees with the host's re-routes from `_ready()` and loops the same way (a
  mirror not built yet at LOADING, one that missed a batch); every client following a teammate's
  batch sends its own ROUTE, so the host reloads everyone 1 + N times. Fixed by P18 RC1 (one
  routing authority), which takes over BF14.
- **Loop fixed** in BF14 (November 24, 2026). The new ENet offer pairs reproduced it on the old
  code: host first, the host's map reloaded 1046 times and the client sent 1047 route requests;
  client first, 30 requests and 29 entries on each side. BF14 makes leaving the offer a local
  move, has the host route by the run (`RunScreen.go_for_everyone()`), and lands each machine on
  its own seat's screen (`RunScreen.for_local_seat()`). It built the older choice (a seat that
  picked waits on the map); P18 question 1 has the team wait on the offer instead, which RC1
  builds on BF14. P11 questions 191–194.
- **Fixed** by P18 RC1 (merged November 24, 2026). Clients never route: no client sends a ROUTE
  notice, the host routes Loading, the offer and the map once each, and a seat that picks first
  waits on its offer ("Waiting for Player N.") until every offer is taken. RC1 removed BF14's
  `RunScreen.go_for_everyone()` and `RunScreen.for_local_seat()` and kept BF14's ENet offer pairs
  (both pick orders) on the new expectations. The live recheck is NT8b's.

### BUG-053 Cleave splashes the unit it struck

- **Found** in the user's playtest (November 24, 2026): the unit a Cleave attack strikes also
  takes Cleave's 2 splash damage. enemy-roster.md says "every other unit adjacent to the Brute";
  the user confirms the struck unit is meant to be spared.
- **Cause:** each Cleave (`data/enemies/brute.tres`, `brigand_captain.tres`, `powder_baron.tres`)
  selects with `Area` (`scripts/effects/blocks/selectors/area.gd`) centered on its owner over
  `data/shapes/adjacent.tres`, side any; the selector has no way to leave out the hit's target,
  which is always adjacent to a melee attacker.
- **Fixed** in BF16 (November 25, 2026): a new `Area.is_fact_target_excluded` on the three Cleaves
  leaves the struck unit out; the forecast, AI and intent area agree; the text says "every other
  adjacent unit". P01 questions 86–88. Still on the old Cleave, both on purpose or harmless:
  `tests/effects/golden_cases.gd` (its "deepest chain" case needs the struck unit splashed) and
  `tests/bench/forecast_bench.gd`.

### BUG-054 Starting heirloom tags cover the other choices

- **Found** in the user's playtest (November 24, 2026): on the starting heirloom screen
  (`ui/campaign/starting_offer_view.gd`, `heirloom_offer_card.gd`), a card's keyword tags draw
  over the other selections. The captures pass with 0 layout issues, so the layout check misses
  an overlap between siblings or a tooltip-like tag box.

### BUG-055 Editor resaves change the build fingerprint

- **Found** in the user's two-machine test (November 23, 2026): a build mismatch between two
  Windows machines on the same commit. `NetContract.content_digest()` hashes the raw bytes of every
  file under `res://data/` and `res://maps/`. Opening the project in the editor resaves
  `maps/greybox_tile_set.tres` (adds an `ext_resource` uid) and `maps/standard/bandit_camp.tscn`
  (gives the scene a **random** uid, different on each machine). A checkout with other line endings
  (`core.autocrlf`; a Mac) differs too. The user keeps those resaves uncommitted (editor
  configuration), so the digest must not depend on them.
- **Fix (BF15):** hash content that ignores editor-only differences (uid attributes, line
  endings), and log each fingerprint part at boot so a mismatch says which part differs.
- **Fixed** in BF15 (November 24, 2026): `.tres` and `.tscn` files hash with CRLF as LF and without
  `uid="uid://..."` on the header and `ext_resource` lines. A clean checkout, one with the two
  resaves and an all-CRLF copy of 89ada1c all booted with fingerprint -8390548712162848460; before
  the fix the main checkout and a clean one differed. `bandit-bash/.gitattributes` already forces
  LF in every git checkout, so line endings only differ outside git. P10 questions 56–60.

### BUG-056 The Boss's end in co-op strands clients

- **Found** by the P18 inventory (November 24, 2026): `CampaignService.end_won_run()` checks only
  that the Boss is beaten (`campaign_service.gd:377-384`), not every seat's picks; the overlay's End
  run routes only the local machine (`victory_overlay.gd:425-432`). The host's end sends
  `_client_run_ended`, which drops each client's replica and mirror, and the clients stay on the
  overlay until they press End run again. Not yet reproduced live.
- **Fix:** P18 RC4: the Boss's end is a ready gate; the host ends the run and routes everyone.

### BUG-057 A refused Leave gives up unclaimed rewards

- **Found** by the P18 inventory (November 24, 2026): the victory overlay's Leave sends the seat's
  skip commands before `LeaveNodeCommand` (`victory_overlay.gd:424-440`); when Leave is refused
  because a teammate hasn't picked (`:462-468`), the skips have already gone through.
- **Fix:** P18 RC4, with question 5's confirm.

### BUG-058 A co-op start can read as a rejoin

- **Found** by BF14 (November 24, 2026; P11 question 193): `CampaignService` marks a client to
  move on its next sync when its mirror gets a run while it isn't on a run screen
  (`campaign_service.gd:720-731`). Over ENet the run's data can arrive before the host's route to
  Loading, so a normal start takes that path and the client opens its own offer alone. The test
  host avoids it by routing to Loading one frame before starting the run.
- **Fixed** by P18 RC1 (merged November 24, 2026). The host's route to Loading always goes out
  before the host could have heard the client's sync request, so it arrives first. A client that
  started in the lobby and is no longer there when its sync lands was already routed by the host:
  it is a new run, stays put, and logs "A new run: the host's route to LOADING came before its
  state; staying." A real join from the lobby and a reconnect move as before. Nothing new crosses
  the network. The test host no longer routes first, so both offer pairs exercise the race
  (`routing_cases.gd` `_test_new_run`).

### BUG-059 An attacker is caught in its own area

- **Found** by BF16 (November 24, 2026; P01 question 89): an `Area` centered on the hit's target
  includes the attacker when it attacks from an adjacent tile. A Raider (Javelin, range 1–2)
  striking at range 1 takes its own 3 Trample splash; a Hexer or Hex Matron (Simple Dark, range
  1–2) at range 1 loses 1 Stance to its own Curse.
- **Decided** (user, November 25, 2026): spare the attacker. Fix in BF16, beside BUG-053.
- **Fixed** in BF16 (November 25, 2026): a new `Area.is_owner_excluded` on the Raider's Trample,
  the Hexer's Curse and the Hex Matron's Curse and Hex Storm curse; the forecast, AI and intent
  area agree; the text adds ", except this unit". The Warcaller's War Horn ("this unit and units
  within 2 tiles") includes itself on purpose and doesn't set it. P01 question 89.
