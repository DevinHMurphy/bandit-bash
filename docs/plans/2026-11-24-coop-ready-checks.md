# Plan: Co-op ready checks (P18)
**Date:** November 24, 2026
**Status:** Approved (user, November 24, 2026)

The user's goal (November 24, 2026): "We need to do ready checks at every asynchronous action within
multiplayer. Continues and transitions should await for all players to be ready." Players can act
on their own (a pick, an upgrade at an event, a purchase), but before the team moves on, every
player's action must be complete and loaded correctly on every machine, at every step: campaign,
map, shops, events, combat, results.

File:line references below come from a read-only pass over `dev` at 1e37508 (November 24, 2026).
RC1 re-checks each one before changing it.

## Problem

The live two-machine test failed at the first hand-off, the starting heirloom (BUG-052). The pass
found that after the lobby, **no move waits for every player**, and nothing tells the host that a
client has applied a batch or loaded a screen.

**How routing works today**

- The host's `RunScreen.go()` (`ui/campaign/run_screen.gd:78-81`) calls
  `SceneRouter.goto_screen_for_everyone(of(session))`, which sends `_networked_goto_screen` to every
  peer at once (`scripts/autoload/scene_router.gd:188-200, 267-269`).
- A client's `RunScreen.go()` sends a `NetRelay.NoticeKind.ROUTE` notice instead
  (`scene_router.gd:192-198`). The host answers every ROUTE with its own `RunScreen.go()`
  (`scene_router.gd:258-262`); ROUTEs are dropped only while the run is paused
  (`scripts/autoload/net_relay.gd:612-617`).
- `RunScreen.of()` chooses by the **local** seat (`run_screen.gd:51-54`, the starting offer), so the
  host routes everyone by its own seat's state.
- A route to the screen already showing reloads it (`scene_router.gd:156-180`): the scene is rebuilt
  and any unsent choice is lost.
- Every campaign screen re-routes from `_ready()` when `of()` disagrees with it (starting heirloom
  `:61`, campaign map `:94`, treasure `:72`, camp `:85`, armory `:69`, guildhall `:71`, event `:92`,
  node placeholder `:61`, combat results `:29`, the host's battle screen `:95`).
- Every screen also routes when a teammate's batch moves the run
  (`CampaignLink.moves_with()`, `scripts/campaign/campaign_link.gd:111-112`), so one Leave makes
  every client send a ROUTE, and the host reloads everyone 1 + N times.

**What follows from it**

1. **Route loops (BUG-052, general).** Whenever a client's `of()` disagrees with the host's, the
   `_ready` re-route and the host's answer loop every frame. Sources: per-seat starting offers
   (both pick orders loop); a client whose mirror isn't built yet at LOADING (`of(null)` is
   GAMEPLAY, `run_screen.gd:47-48`); a mirror that missed a batch.
2. **The first press moves everyone.** The map draw's Continue (`campaign_map_screen.gd:325-329`),
   Loading's Continue (`loading_gate.gd:34-35`), an event's Fight (`event_screen.gd:187-194`) and
   any accepted Leave move the whole team at once, cutting teammates off mid-choice.
3. **Nodes that never wait:** the Armory and Guildhall (`leave_node_command.gd:21`: "never
   waits"), the node placeholder, and the Camp's re-gearing and gifts (only Feast or Train is
   waited on, `leave_node_command.gd:56-57`).
4. **The Boss's end in co-op** checks only that the Boss is beaten
   (`campaign_service.gd:377-384`), routes only the host (`victory_overlay.gd:425-432`), and leaves
   clients on a dead overlay (BUG-056).
5. **A refused Leave on the results overlay** still sends that seat's skip commands first, giving
   up its unclaimed rewards (`victory_overlay.gd:424-440, 462-468`; BUG-057).
6. **The pause doesn't stop the host:** its own `RunScreen.go()` routes everyone while a seat is
   dropped.
7. **No acknowledgement.** Client-to-host messages are `_submit_combat`, `_submit_campaign`,
   `_request_sync`, `_notice` and `_seat_settings` (NetRelay), plus `_request_admission` and
   `_request_ready` (SteamNetwork). None says "applied" or "loaded". P10 rejected "a loading gate
   before every battle" (`2026-11-19-net-transport.md:286`) because mirrors catch up by seq.
8. **Missing waiting UI** on the starting heirloom, Treasure and results screens: only refusal
   text shows.
9. **Docs that say otherwise:** `loading_gate.gd:18` ("only the host's press moves everyone") and
   `nav_button.gd:16-17` (a client press "is refused"); both send a ROUTE.
10. **No test drives a co-op run through real screens.** `coop_campaign_cases.gd:476-478` and
    `enet_dev_cases.gd:575-576` delete the starting offers and play every node by command;
    `tests/ui/campaign` walks real screens in solo only.

**What already waits** (kept): the lobby's Ready (`lobby_screen.gd:306-311`); route votes
(`RouteVoteCommand`); event votes and each seat applying a team option (`EventVoteCommand`,
`EventOptionCommand`); Leave at Treasure, Camp (Feast or Train), Event and Results
(`LeaveNodeCommand`); a battle's end on every map (`battle_screen.gd:278-314`, "Waiting for the
other maps"); inside a battle, every seat's opening-swap Start, End Turn and the fast-forward hold;
the drop pause and its overlay.

## Open Questions

None. All ten were answered by the user on November 24, 2026, each as recommended; question 6
adds a loading screen with a progress bar per player. They are in
[decisions/P18-coop-ready-checks.md](decisions/P18-coop-ready-checks.md).

## Scope

**In scope:** every co-op hand-off from the lobby to the run's end: LOADING, STARTING_HEIRLOOM,
CAMPAIGN_MAP (the draw's Continue), every node (Treasure, Camp, Armory, Guildhall, Event and its
Fight, the placeholder), GAMEPLAY's start and end, COMBAT_RESULTS, the Boss's end and a lost run;
one routing authority (the host) with no client ROUTEs and no loops; the waiting UI; a two-machine
test through real screens; the docs.

**Out of scope:** anything inside a battle's turns (each map keeps its own turns, game-vision.md;
End Turn, the opening swap and fast-forward already wait); the lobby's Ready (built); solo play
(unchanged: a one-seat gate opens at once and shows nothing); a host "Continue without" timer
(question 7 (b), later); changing what the rules already refuse.

## Design Basis

- game-vision.md, Co-op route ("the team travels together on one map"), the Multiplayer section
  (disconnects pause for everyone; forfeits; "each parallel map runs on its own turns"), and the
  design pillar "Remove 'hurry up and wait' decisions … in co-op no player should sit idle for
  long" (question 10).
- The vision says nothing about waiting between screens; the user's rule of November 24, 2026 is
  the basis. P11 question 61 (a seat on the map while a teammate's offer is open) is superseded
  by question 1 (a) if answered so.
- master-ideation.md: no co-op screen flow beyond the route vote.
- P10's rejected loading gate (question 6) and P11's built waits (above) are the starting point.

## Legacy Behavior (ports from Godot_FE only)

Not a port: `Godot_FE` had no co-op campaign.

## Approach

**1. One routing authority.** Only the host routes. A client never routes for the team: its
screens stop calling `goto_screen_for_everyone`, and the ROUTE notice is no longer sent (the enum
value stays, append-only, and a ROUTE the host receives is logged and dropped). A client screen
whose `of()` disagrees with the screen it is on asks for a sync instead of routing. A route to the
screen already showing is a no-op. The host's routes wait while the run is paused. This removes
every loop before any gate exists, and is the cheapest step.

**2. The ready gate.** A host-side `ReadyGate` (sessions layer, not rules) tracks one open gate at
a time: a key (the run's seq when the step opened, plus the screen), the seats it waits for (every
seat still in the run: not forfeited, not removed), each seat's **Ready** (its press) and **Loaded**
(its machine's acknowledgement that it has applied the run up to the key's seq and shown the
screen). When every seat is Ready and Loaded, the host performs the transition with today's
commands (`LeaveNodeCommand`, the draw's entry, `end_battle()`, the run's end) and routes everyone.
A seat that forfeits or is removed leaves the gate, which may open it; a dropped seat pauses the
run as today, and the gate waits.

**3. Messages** (new network contract, covered by the fingerprint):
- client to host: `_seat_ready(key, is_ready)`, `_seat_load_progress(key, fraction)` while its
  screen loads, and `_seat_loaded(key)`;
- host to every client: `_gate_state(key, ready_seats, loaded_seats, progress_by_seat)`, so every
  machine shows who it is waiting for and how far each machine has loaded.

Each carries the gate key; a message for a closed or unknown key is dropped and logged.

**4. Two waits per hand-off.** Before leaving: every seat Ready (its own choices made, then its
press). After arriving: every machine Loaded before the new screen takes input ("Waiting for
Player 2 to load"). The battle's start uses the second wait before the host's first Phase Start
(question 6).

**4a. The loading screen** (question 6). The arrival wait shows a real loading screen, built on
today's LOADING placeholder (`ui/screens/` and `loading_gate.gd`, "a placeholder until loading
waits for every player"): one progress bar per player, each filled from that machine's own load
fraction (threaded scene loading's progress, then the mirror's catch-up to the gate's seq), with
the player's name and Ready, Loading or Done. Every hand-off that changes scene uses it, the
battle's start above all; a hand-off that loads in a frame may skip showing it.

**5. Per screen.**

| Screen | Ready means | Then the host |
|---|---|---|
| LOADING | each seat's Continue | routes to the run's screen |
| STARTING_HEIRLOOM | each seat's pick resolved (Ready is the pick; question 1) | routes everyone to the map |
| CAMPAIGN_MAP | the route vote (as today), then each seat's Continue on the draw | enters the node and routes |
| TREASURE, CAMP | each seat's choices made, then Ready (question 5 for unclaimed) | `LeaveNodeCommand`, routes |
| ARMORY, GUILDHALL | each seat's Done shopping (question 4) | `LeaveNodeCommand`, routes |
| EVENT | each seat's option applied (as today), then Ready; a pending Fight is a Ready to fight | Leave, or routes to battle |
| NODE_PLACEHOLDER | each seat's Continue | Leave, routes |
| GAMEPLAY (start) | every client's battle opened (Loaded) | begins the first Phase Start |
| GAMEPLAY (end) | every map ended (as today) and every machine's board settled (Loaded on the end batch) | `end_battle()`, routes |
| COMBAT_RESULTS | each seat's rewards taken or skipped, then Ready (question 5) | Leave, routes |
| Boss's end | each seat's Ready on End run | ends the run for everyone, routes everyone to RESULTS (BUG-056) |
| Run lost | none (the run is over) | routes everyone to RESULTS, as today |

**6. The waiting UI.** One shared element, `TeamReadyStatus` (its own `.tscn`), on every screen
with a gate: each teammate's name with Ready, Choosing or Loading, built on the existing team
status rows (`camp_team_status.gd`, `event_team_status.gd`, `route_vote_status.gd`). Every
Continue and Leave becomes a Ready toggle (question 3) with its glyph hint; keyboard, mouse and
controller from the start. Read-only panels (the heirloom bar, unit detail, the convoy) stay open
while waiting (question 10).

**Rejected:**
- **Ready as a campaign command** (question 9 (b)): it would put presentation-paced state into the
  pure rules, the save and the fact log, for seconds of state.
- **Keeping client ROUTEs with a guard:** any client-side route can loop when mirrors disagree;
  one authority can't.
- **A loading wait only before battles** (the narrow form of P10's gate): the failures happen
  between campaign screens.
- **Timeouts that move on without a seat:** they skip a player's turn at the shop; the drop pause
  and Remove already cover a player who is gone (question 7).

## Save Impact

Not saved (question 8): a gate's state is transient on the host and its clients, and a resumed run
reloads every screen, so each seat readies again. No section changes. The transitions themselves
are today's commands, saved as today.

## Work Breakdown

Each step merges into `dev` on its own and keeps the full run green.

| Step | Lane | What | Files | Risk | Verification |
|------|------|------|-------|------|--------------|
| **RC1** One routing authority | B | Clients never route; no client ROUTE; a mismatched client screen asks for a sync; a same-screen route is a no-op; the host's routes wait while paused; the two wrong docs. Folds in BF14 | `scene_router.gd`, `run_screen.gd`, every campaign screen's `_ready`/leave path, `loading_gate.gd`, `nav_button.gd`, `campaign_link.gd` | 🟡 | ROUTE and screen-entry counts in the ENet pair: no loop in either pick order at the starting heirloom; solo unchanged |
| **RC2** The gate and its messages | E | `ReadyGate`, `_seat_ready`, `_seat_loaded`, `_gate_state`; forfeit and removal leave the gate; dropped keys; NetLog lines | `scripts/sessions/` (new), `net_relay.gd`, `tests/net/` | 🔴 network contract | Harness cases: open, ready, unready, load, forfeit mid-gate, a stale key, the pause |
| **RC3** Loaded acknowledgements and progress | E | Each client reports its load progress and acknowledges a gate's key once its mirror holds the seq and its screen is ready (threaded loading); the battle's start waits for every client's battle (question 6) | `client_mirror.gd`, `battle_screen.gd`, the screens' ready hook | 🔴 | A client delayed by the harness holds the gate; the host's Phase Start waits |
| **RC4** Screens on the gate | B (and A for the battle) | Every row of the Approach's table; BUG-056 (the Boss's end) and BUG-057 (unclaimed rewards) | `ui/campaign/` screens, `victory_overlay.gd`, `battle_screen.gd`, `campaign_service.gd` | 🟡 | Per-screen cases with two seats; the Boss's end routes every machine |
| **RC5** `TeamReadyStatus`, the Ready toggles and the loading screen | A | The shared element, the toggles and hints on every gated screen, read-only panels while waiting; the loading screen with a progress bar per player (Approach 4a) | `ui/common/` (new element), each gated screen, the hint bar | 🟢 | UI cases by key, pad and mouse; captures at three sizes |
| **RC6** A co-op run through real screens | E | The ENet pair plays starting heirloom → map → a node of each kind → a battle → results → the next node through the real router, both machines, with ready presses; keep the starting offers | `tests/net/enet_dev_cases.gd`, its driver | 🟡 | Passes in full runs (JOBS=8) five times; counts of routes and reloads match the expected per hand-off |
| **RC7** Docs | F | campaign-run.md (the gate per screen), event-bus.md (the messages), multiplayer-combat-options.md, the P10 and P11 decision rows it supersedes | `docs/design/`, `docs/plans/decisions/` | 🟢 | No doc says a client routes or that a node doesn't wait |

**Order:** RC1 first, on its own: it fixes the live failure. RC2 and RC5 can run side by side
(Lanes E and A). RC3 after RC2. RC4 after RC2 and RC5 (RC3 for the battle's start). RC6 after RC4.
RC7 last. NT8b (the live Windows-to-Mac check) runs after RC6.

## Breaking Changes

| Change | Kind | Affected | Migration |
|---|---|---|---|
| Clients no longer send `NoticeKind.ROUTE`; the host drops one | Network contract (changed meaning) | Mixed builds | The fingerprint refuses them at the lobby |
| `NetRelay._seat_ready`, `_seat_load_progress`, `_seat_loaded`, `_gate_state` | Network contract (new RPCs) | Mixed builds | The fingerprint covers RPCs |
| Continue and Leave buttons become Ready toggles on co-op screens | UI behaviour | Players; UI tests that press Continue or Leave in co-op | Tests press Ready on every seat |
| `goto_screen` to the screen already showing does nothing | Public method behaviour | Anything relying on a reload | None found yet; RC1 greps for it |
| A battle's first Phase Start waits for every client (question 6) | Behaviour | Battle timing tests in co-op | Harness acknowledges the battle |

## Verification

- RC6's two-machine run through real screens, five times in full runs, with no route loop, one
  route per hand-off, and every machine on the same screen at each step.
- Per-gate harness cases: every seat must press Ready and acknowledge; unready works; a forfeit or
  removal opens a gate; a drop pauses it; a stale key is dropped.
- Solo: every existing solo test unchanged.
- Live: NT8b (Windows against the Mac) walks a full node cycle; the user's two-Windows test
  repeats the starting heirloom in both pick orders.

## Rollback

Each step is its own merge. RC1 reverts alone to today's routing (with BUG-052). RC2 to RC5 revert
together (the gate's messages and the screens that use them). The fingerprint changes with each,
so a reverted build never meets a newer one in a lobby.
