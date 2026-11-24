# Plan: Co-op Combat
**Date:** November 20, 2026
**Status:** Approved (user, November 20, 2026), with CO6 moved to Lane C. Orchestrator ID **P11**.
Built: CO1–CO19, CO22 and CO23 merged (November 21–23, 2026); CO20, this docs pass, on
`feature/CO20`; CO21, the live co-op check, not run. Network paths untested live until CO21.

## Problem

P10 moves any command and any fact between machines, and keeps every mirror equal to the host. It
decides no co-op rule. The co-op rules the vision sets for parallel maps are mostly not built, and
some built rules contradict them.

- **A map is lost when its commander falls.** `Objectives._is_lost()` loses a map on any
  commander's fall (`scripts/map/objectives.gd:131-135`) and when no player unit is left
  (`:136-137`). L4 says a co-op player keeps their surviving units, and an empty map freezes until
  help comes.
- **Units can move between maps, but nothing sends them.** `CombatEncounter.send_unit()` and
  `deliver_arrivals()` exist (`scripts/sessions/combat_encounter.gd:327-393`), but no command
  calls them, there is no battle clock (they arrive at the next Phase Start), no call for aid, and
  a send records no fact. `SeatOutcome.has_received_units` is "always false until co-op sends
  units" (`campaign_session.gd:1093-1095`), though grades already read it
  (`combat_grades.gd:124`).
- **A co-op battle with a lost map never reaches its results.** `apply_battle()` moves the run to
  its results only when every map was won (`campaign_run_state.gd:282`), and every seat's
  `COMBAT_ENDED` records the team's result, not its own (`:277`). Only a solo loss ends a run
  (`campaign_service.gd:188`); nothing loses a co-op run.
- **No route vote.** `ChooseNodeCommand` "carries the route the host drew from the votes"
  (`choose_node_command.gd:21`), but no vote command exists; with P10 alone the first choice to
  arrive wins (P10 question 10).
- **No swaps, no forfeit.** coop-unit-swaps.md is decided and unbuilt. A forfeit needs a save
  change: the player count is fixed for a campaign's life today (save-system.md, Multiplayer).
- **Every screen acts for `seats[0]`.** The campaign, event and battle screens take the first seat
  (`armory_screen.gd:66`, `camp_screen.gd:81`, `guildhall_screen.gd:66`, `treasure_screen.gd:70`,
  `starting_heirloom_screen.gd:63`, `campaign_map_screen.gd:89-196`, `event_screen.gd:82-151`,
  `combat_results_screen.gd:31`, `battle_screen.gd:74-196`), and a co-op battle shows a placeholder
  (`battle_screen.gd:151`).
- **Gaps for units on a partner's map** (P01 question 49): a transfer drops timed modifiers, and
  the owner's "Your Unit" heirlooms don't follow the unit.
- **Unique heirlooms** are kept to one owner only in the Armory (`armory_stock.gd:261-273`); the
  vision's "first claim wins, the other's offer is replaced" covers every offer.
- **A team choice applies for every seat from one seat** (`event_option_command.gd:18-34`), with
  every seat's picks; over the network a seat can only send its own (P09 question 33).
- **A client's darkness waves stay at reach 0** (save-system.md, Darkness, Mirrors), so its
  next-deepening preview differs from the host's.
- **Smaller gaps:** co-op seats' opening-swap setting never reaches the host
  (`campaign_session.gd:30`, TOD-003); the pause menu doesn't pause in multiplayer, so the hint bar
  never shows its PAUSED set (design items); fast-forward votes and game speed aren't built.
- **Found while reading (not P11's to fix uninvited):** the end-of-player-phase battle save isn't
  wired in real play, solo included. Only Begin and Save & Quit write a battle
  (`pause_menu.gd:171`); save-system.md's checkpoint table lists it. Question 39.

## Open Questions

All of them are in [decisions/P11-coop-combat.md](decisions/P11-coop-combat.md), each with options and
a recommendation. Every question up to 182 is answered (user, November 20–23, 2026); 183–185
(CO19) are built on the recommendation and pending confirmation, and 190 (CO20) is open. Each
step below names the questions it needs. Where the
Approach states a rule a question decides, it takes the recommendation and cites it as
**(Q n)**; nothing is built on it until the question is answered.

The questions that block the first steps: 2, 3 (CO10, CO12); 5, 6, 7 (CO1); 8–15 and 39 (CO2);
20 (CO4); 21, 22 (CO5); 23 (CO6); 24 (CO7); 27 (CO9). Questions 1–4 also amend P10's boundary.

## Scope

**In (P11):**

- Every map must be completed (L4): a fallen co-op commander's map goes on; an empty map freezes;
  a failed objective loses only that map; when the run is lost.
- Sending units (H1): the send command, the battle clock, all of a sender's units to one map, the
  must-send rule for a frozen map, units returning when their map ends, the lost speed bonus.
- Call for aid (R2) and the senders' map status (R1).
- Units on a partner's map: timed modifiers and "Your Unit" heirlooms, for sent units and swap
  visitors alike (coop-unit-swaps.md, decision 8); Commander's Standard; the cross-map hook.
- Unit swaps (coop-unit-swaps.md, all eight decisions).
- Route votes and the weighted draw.
- Unique heirloom claims outside the Armory.
- The co-op battle's end: per-seat results, rewards for units that fought on a partner's map, a
  co-op run lost.
- Team-choice events applied per seat.
- The darkness's reach on client mirrors.
- The per-map battle save: what the existing per-map `combat_state` still lacks for co-op.
- Forfeit and removal: the save change (a campaign's player count can shrink), the battle and
  campaign cleanup, and the host's Remove (P10 N6).
- Screens: every campaign and event screen for its own seat on host and client, the co-op
  campaign map (votes, swaps, teammates), the co-op battle screen (send, aid, spectate, frozen,
  waiting), the co-op pause menu.
- Per-seat settings reaching the host, and fast-forward votes.
- The headless co-op cases on P10's harness, and the live co-op rows that M4 runs after P10 NT8.

**Already built, not redone:** EV5's team votes and weighted draw (events.md Co-op); RN7's Camp
gifting and the stacking Feast; RN8's and RN9's shared Armory and Guildhall stock, +1 per extra
player and the first purchase; the Armory's unique-heirloom rule; the co-op commander's return at
critical health (`fallen_commander_hp_percent`, P08 question 19); MP4's per-map objectives;
`send_unit()`, `deliver_arrivals()` and the units in transit in the save (EB6, EB7, CC8); per-map
phases with ended seats (CC6); runes cast on a teammate's map through `CombatEncounter.submit()`;
per-seat streams (P13); `combat_state` holding every map's units, turn and phase (CC8).

**Out of P11:**

- Shared and hybrid battles (Option D, post-MVP), and how two players deploy onto one shared map.
- Light links beyond runes on a teammate's map **(Q 38)**.
- Game speed as a lobby setting until a solo game-speed option exists **(Q 30)**.
- A turn timer **(Q 37)**; host migration; joining a campaign one isn't part of (P10, Out of both).
- The solo end-of-player-phase save, if question 39 makes it a bug fix.

## Design Basis

- **game-vision.md, Combat maps, Multiplayer maps** (all of it): parallel maps; Reinforce with
  the battle clock; Every map must be completed; Permadeath as in solo; the co-op commander's
  return; frozen maps; own turns per map; Everyone stays involved (runes on a teammate's map,
  spectating, game speed, fast-forward); Disconnects and forfeits. **Co-op ownership:** everything
  per player except shop stock; the unique heirloom's first claim.
- **game-vision.md, Run structure:** the co-op route (vote, weighted draw, the host draws); events
  (most are each player's own; team events and every combat option are voted). **Army:**
  permadeath in co-op; the commander exception. **Units:** "in multiplayer the host awards XP once";
  one Standout per player. **Run-wide resources:** unique heirlooms (one owner per campaign).
  **Open and unfinished:** the Multiplayer and Multiplayer arrivals items are this plan's.
- **multiplayer-combat-options.md** (all): decided B for the MVP; H1 + L4; C4; R1 + R2;
  deployment and arrival; no recovery; disconnects and forfeits; the questions any option raises.
- **coop-unit-swaps.md:** the eight decisions of November 19, 2026.
- **events.md, Co-op:** individual and team choices; combat options are team choices.
- **effect-triggers.md:** per-map phases (P01 question 11); Any Ally Unit includes partners.
- **save-system.md:** Multiplayer, Run state, Events, Combat state, Battles.
- **master-ideation.md** is silent on multiplayer. Its "the commander falling in battle prompts an
  instant loss" (line 230) is superseded by the vision for co-op.

**Where the sources disagree** (the vision wins; listed with sources):

| Topic | One source | The other | Here |
|---|---|---|---|
| A fallen commander | master-ideation.md:230: instant loss | game-vision.md:731-734: co-op returns at critical health, the map goes on | Vision |
| When the run is lost | game-vision.md:1083 (October 20 row): "only if every commander falls in the same combat" | game-vision.md:735-737 and :1135 (October 29, L4) | L4. The October 20 row isn't marked superseded; reported for the ideation thread |
| Where sent units land | multiplayer-combat-options.md:134 (H1 text): the deployment edge or a reinforcement point | :219-224 and game-vision.md:719-720: next to the receiving commander, by the battle clock | Decided rule |
| The route | `Godot_FE/docs/systems/14_multiplayer_integration.md` §7: majority, or the leader decides | game-vision.md:142-144: weighted draw, the host draws | Vision **(Q 23)** |
| Standout and grades on a partner's map | game-vision.md:722-723 (sent units): "the Standout stays on each player's own map" | coop-unit-swaps.md, decision 6 (visitors): "its Standout and grades count for its owner" | One rule that fits both **(Q 25)** |
| A swap's combat | coop-unit-swaps.md, option A: "the next combat"; "the next node is already chosen" | `choose_node_command.gd`: choosing a node enters it at once | **(Q 21)** |

## Legacy Behavior

`Godot_FE/` (Godot 4.7) has no multiplayer code (P10, Legacy Behavior). Its
`docs/systems/14_multiplayer_integration.md` is an unbuilt design.

| Godot_FE source | Behavior | Keep / Change / Drop | Reason |
|---|---|---|---|
| Doc 14 §2, Co-op campaign | All peers act on one map in a shared player turn | **Drop** for the MVP | Parallel maps (vision); shared battles are post-MVP |
| Doc 14 §7, Map | `CMD_VOTE_ROOM`; majority or leader decides | **Change** | Weighted draw, the host draws (vision) **(Q 23)** |
| Doc 14 §7, Treasure / Recruit | First valid claim wins, by seq | **Keep** | The vision's first claim and first purchase |
| Doc 14 §6, §12 | Disconnect policy: pause, AI takeover or forfeit | **Change** | Pause, rejoin, host removal, non-host forfeit (vision; P10 builds the pause) |
| Doc 14 §12 (2) | Each peer owns a subset of units | **Keep** | Each player controls their own units, on every map |

**Tuning values:** none from `Godot_FE/`. Values used come from the vision and are built already:
the fallen commander's 10% of max HP, at least 1 (`fallen_commander_hp_percent`); the shops' +1 per
category per extra player; the 2-minute removal wait (P10). No new value is set here.

## Approach

### The systems P11 adds

| System | Where | Steps |
|---|---|---|
| Every map must be completed (L4) | `Objectives`, `CombatEncounter` | CO1 |
| Sending units, the battle clock, call for aid | `CombatEncounter`, two new combat commands, `combat_state` v4 | CO2 |
| Units on a partner's map | `CombatEncounter`'s transfers, the loadout's heirloom registration | CO3 |
| The darkness on mirrors | An appended darkness fact | CO4 |
| Unit swaps | Three campaign commands, `run_flow` v2, the battle request | CO5 |
| Route votes | A campaign command, `campaign_map` v2 | CO6 |
| Unique heirloom claims | Treasure, key heirloom, events, starting offer | CO7 |
| The co-op battle's end and rewards | `CampaignRunState.apply_battle()`, `CampaignService.end_battle()` | CO8 |
| Team choices per seat | `EventOptionCommand` | CO9 |
| Screens for their own seat; co-op campaign map; event screen | `ui/campaign/`, `ui/campaign/events/` | CO10–CO12 |
| The co-op battle screen | `ui/battle/` | CO13 |
| Forfeit: rules and save | `CampaignData`, `CampaignRunState`, `CombatEncounter`, `ArchiveRecord` | CO14 |
| Co-op commands and facts on P10's wire; settings; fast-forward | `NetRelay` messages and notices | CO15–CO17 |
| Forfeits from N6; the co-op pause menu | `NetRelay`, `SeatWaitOverlay`, `pause_menu.gd` | CO18, CO19 |

### Boundaries with P10

P10's [Where P10 ends and P11 begins](2026-11-19-net-transport.md#where-p10-ends-and-p11-begins)
stands. Four lines need settling, each a proposed P10 amendment:

- **A client plays its own map in NT5** **(Q 1)**: NT5 binds the battle and campaign map screens
  to the local seat and removes the co-op placeholder. P11 adds the co-op panels.
- **`CampaignService.local_seat()` comes in CO10** **(Q 2)**: the host seat in solo and on the
  host; NT5 makes it return a client's seat.
- **Mirrors emit the host's signals** **(Q 3)**: a client's mirror `CampaignSession` emits
  `campaign_batch_resolved` for each batch it applies and `command_rejected` for the local seat's
  settled rejections. Screens rebuild from those signals in both roles.
- **NT4 completes remote commands on the host** **(Q 4)**: `complete_on_host(session)` after
  `from_wire()`, each command filling its own host-side objects.

With these, the campaign and event screens (CO10–CO12) need no NT step to build and work on a
client from NT5; CO16 checks them in NT5's harness.

### Every map must be completed (CO1)

- **Co-op means more than one seat in the encounter** (`CombatEncounter.seats.size() > 1`). Solo
  rules don't change.
- **In co-op a commander's fall never loses a map** **(Q 7)**. The commander still returns at
  critical health after the combat, as built.
- **A map with no player units freezes** **(Q 5)**: the phase in progress finishes, then the map
  stops at its next player Phase Start. It runs no phase and its turn stays until arrivals land.
  A `TODO` marks where a later rule could let the darkness keep rising there.
- **A failed objective** (a Defend tile taken) still ends that map as lost.
- **The run is lost** when a map is frozen, no unit is on its way to it, and no map still being
  fought or won holds a unit that could yet be sent **(Q 6)**. The encounter answers
  `is_run_lost()`; CO8 acts on it.
- Frozen is derived from the map's state, so it isn't saved.

### Sending units and calling for aid (CO2)

- **`SendUnitsCommand`** (unit ids, the target map) is submitted on the sender's won map
  **(Q 14)**. The encounter takes it off that map's queue and validates it at resolve time: the
  map is won; the target is still being fought; every unit is a surviving player unit of the
  sender on the won map; one target for the whole send **(Q 9)**; while any map is frozen the
  target must be a frozen map and the send can't be empty **(Q 10)**. "Send none" is the same
  command with no units.
- **The battle clock.** A transfer records the turn the sender's map was won on. It is delivered
  at the target's first player Phase Start after that turn, or at once to a frozen map **(Q 8)**.
  No free tile: it waits, as built **(Q 12)**.
- **A map that ends first** sends its waiting units back onto their sender's won map, unharmed;
  they count as units left to send **(Q 11)**.
- **The receiving map** records each sender, so `SeatOutcome.has_received_units` is set and that
  map loses its speed bonus (built in grades).
- **`CallForAidCommand`** on the caller's own map raises or lowers its flag **(Q 13)**.
- **The senders' status** (each map's turn, units and enemies left, flag) is read from the mirrors
  every client holds (P10 N3); it adds no state.
- **Facts**, appended to `CombatFact.Kind` on the encounter's log: units sent, units returned,
  aid called; arrivals already record `UNIT_SPAWNED`.
- **Saved** in `combat_state` v4 **(Q 15)**. If question 39 makes the phase-end save a bug fix,
  CO2 extends it: any map's player phase end saves the whole battle.

### Units on a partner's map (CO3)

One rule set for sent units and swap visitors (coop-unit-swaps.md, decision 8):

- **Timed modifiers travel** with the unit and keep the phases they have left **(Q 16)**.
- **"Your Unit" heirlooms follow** the unit: the owner's heirloom effects are registered on each
  map that holds one of their units, for those units only; their Any Ally Unit parts stay asleep
  there, as P01 question 12 designed **(Q 17)**.
- **Commander's Standard** counts Your Units only **(Q 18)**.
- **No forwarding hook** yet **(Q 19)**.

### The darkness on mirrors (CO4)

An appended fact records each wave's reach and newly entered tiles when it creeps. Mirrors follow
it, so `Darkness.next_deepening()` agrees with the host's, and `state_hash()` covers reach
**(Q 20)**. The save's `darkness` section doesn't change.

### Unit swaps (CO5)

- **Commands:** `ProposeSwapCommand` (my unit, your seat, your unit), `AnswerSwapCommand` (accept
  or decline), `WithdrawSwapCommand`. Valid only on the campaign map, for living non-commander
  units, at most one swap per pair of seats, and only the two seats named take part.
- **Open proposals** live in the host's `CampaignSession` memory and are lost on a quit; an
  accepted swap is saved in `run_flow.swaps` **(Q 22)**.
- **It applies to the next combat the team fights** **(Q 21)**. `battle_request()` lists the
  visitor with the host map's army, still owned by its seat; it deploys by role in that map's
  zone. Its owner controls it there, moves it in the opening swap window, and ends their turn on
  that map; the per-map phase already waits for every seat with units on it.
- **It ends** when that combat ends, when a named unit leaves the army or falls, or on a withdraw.
- Rewards: CO8.

### Route votes (CO6)

`RouteVoteCommand` (a node on the next floor), as EV5's team votes: voting again replaces a vote;
the last vote draws the node from the floor's `ROUTE_DRAW` stream and records it as
`NODE_CHOSEN`; votes are saved in `campaign_map.votes` until the next vote. Solo chooses directly.
In co-op a seat's own `ChooseNodeCommand` is refused **(Q 23)**.

### Unique heirloom claims (CO7)

Every offer that can show a unique heirloom (Treasure, the key combat's heirloom, an event's rare
heirloom, the starting offer): the first take wins, and every other open offer of it is replaced
at once by another of the same tier, from that seat's stream the offer came from **(Q 24)**.
`ArmoryStock.unique_owner()` is the one test of "unique and owned". The replaced offer is saved
where the offer already is.

### The co-op battle's end and rewards (CO8)

- **The run reaches its results when every map has ended.** Each seat's `COMBAT_ENDED` records its
  own map. A failed seat's results show the loss: no gold, XP, pick or Standout **(Q 26)**.
- **Units on a partner's map** **(Q 25)**: a unit's actions anywhere count toward its owner's
  Standout and its own personal XP cap; shared XP comes from the map it fought on, never twice; a
  map's Standout is picked among its owner's units; the owner's grades come from the owner's map,
  plus their units lost anywhere. Loot stays with the map's owner.
- **A co-op run lost** (CO1's `is_run_lost()`) ends the run for every seat through
  `SaveService.end_run(false)`, as a solo loss does.
- **Swaps lapse** here.

### Team choices per seat (CO9)

Each seat applies the drawn team option to its own army with its own picks. The team's choice is
done when every seat has applied, and a surprise combat starts then **(Q 27)**. The `events`
section already holds a `chosen` per seat; the step confirms its shape stays.

### Screens (CO10–CO13)

- **Every campaign and event screen** reads `CampaignService.local_seat()` and rebuilds from the
  session's signals, never from `submit_command()`'s return **(Q 2, Q 3)**. A refusal because a
  teammate was first ("bought by …") shows its reason.
- **Teammates are visible:** their heirloom bars on request, who bought each shop item, each
  teammate's Camp choice and event choice, and the route and event votes.
- **The co-op campaign map** (CO11) shows each seat's route vote and the draw, and the swap
  proposal, answer and withdraw flow.
- **The co-op battle screen** (CO13), each part its own `.tscn`, keyboard, mouse and controller
  from the start: the send panel after a win (each ongoing map's status and flag; pick units and
  one map; the frozen-map rule shown); call for aid; spectate any map read-only; a frozen map's
  banner; "waiting for the other maps" until the battle ends; the results then.

### Settings and fast-forward (CO15)

- A client sends its settings (the opening swap) through `NetRelay` on joining and on Apply; the
  host keeps them per seat, unsaved, and `begin_battle()` reads them. TOD-003 closes **(Q 28)**.
- Fast-forward: every player with units on a map must agree; one player alone decides alone. It
  travels as N8 notices, unsaved, and pauses for boss combats and player units' deaths **(Q 29)**.

### Forfeits (CO14, CO18)

- **Who:** any non-host player at any time; the host removes a dropped player after the wait. The
  host abandons a run as today; a host drop ends the match (P10).
- **The campaign** loses the seat's `players` entry at once, so a resume no longer needs them.
  Seats are never renumbered. The seat's run sections, votes, proposals and swaps go; a vote now
  complete draws; an heirloom only it held can be offered again; a shop's stock stays as rolled
  **(Q 33)**.
- **Mid-battle,** the map leaves every peer's view and nobody acts there, but the save keeps it,
  marked forfeited, until the battle ends, since a resumed battle rebuilds from Begin's sections
  **(Q 31)**. The forfeiter's units leave with them; teammates' units on its map return to their
  owners after the combat as they stood **(Q 32)**.
- **The archive:** `won` false and `forfeited` true, schema 2 **(Q 34)**. A voluntary forfeit
  sends the record to the leaving machine first; a removed player gets none **(Q 35)**.
- **Network (CO18):** a client's `ForfeitCommand` and the host's Remove on `SeatWaitOverlay` both
  end in CO14's operations, then `remove_seat()` (P10 N6).

### The co-op pause menu (CO19)

The tree never pauses in co-op, and the hint bar shows its own set for that. Host: Resume,
Options, Save & Quit (ends the match for everyone, after a confirm). Client: Resume, Options,
Leave Match (a drop: everyone waits; they can rejoin), Forfeit (a confirm) **(Q 36)**.

### Rejected alternatives

| Alternative | Why not |
|---|---|
| A new encounter RPC for sends | NT4's combat route already carries a command to a map with the seat checked **(Q 14)** |
| Save the frozen flag | It is derived from the map's state |
| Remove a forfeiter's map from the battle and save at once | A resume rebuilds every seat from Begin's sections, so the shapes would disagree **(Q 31)** |
| Fact kinds for battle-end gold, falls and skipped picks | P10 question 2 already sends the run's capture with every campaign batch **(Q 41)** |
| One seat applies a team choice for everyone | Over the network a seat can't pick for a teammate's army **(Q 27)** |
| Screens that read `submit_command()`'s return | A client gets no batch back (P10 NT4); signals work in both roles **(Q 3)** |

## Save Impact

| Block | Key | Per player | Version | Change | Step |
|---|---|---|---|---|---|
| `CAMPAIGN` | `campaign_map` | No | 1 → 2 | `votes`: by seat, a node id; empty before the first vote and in solo, and kept after the draw until the next floor's first vote. Migration: none voted | CO6 |
| `CAMPAIGN` | `run_flow` | No | 1 → 2 | `swaps`: the accepted swaps for the next combat, each two seats and their two unit ids. Migration: none | CO5 |
| `COMBAT` | `combat_state` | No | 3 → 4 | The encounter's `sends` (by seat: target map and winning turn, or none); each transfer's clock turn; each map's senders and call for aid; forfeited seats (empty until CO14). Migration: none sent, no flag, none forfeited; a v3 transfer is due at the next Phase Start, as built **(Q 15)** | CO2 |
| `CAMPAIGN` | core `players` | — | schema 1 (no change) | A forfeit removes the seat's entry; seats keep their numbers. The rule "the player count is fixed for a campaign's life" goes | CO14 |
| `CAMPAIGN` | `runes`, `roster`, `heirlooms`, `economy`; `events`' `current.seats` and `votes` | Yes / No | no change | A forfeited seat's entries removed | CO14 |
| Archive | record core | — | schema 1 → 2 | `forfeited` (bool). Migration: false. P12 plans another archive bump; whichever lands first takes 2 **(Q 34)** | CO14 |

- **Not saved:** open swap proposals (coop-unit-swaps.md, decision 7), a map's frozen state, the
  run-loss check, seat settings on the host, fast-forward votes, who spectates what.
- **No change:** `events` (each seat's `chosen` already exists, CO9); `darkness` (CO4 changes only
  what mirrors follow); `CombatData`'s core, whose `turn` and `phase` stay the lowest seat's map
  for display **(Q 40)**; `settings.json`.
- **Only the host saves,** as today. save-system.md gains one row per change, append-only, in the
  step that makes it.

## Network Contract

Every addition is picked up by `NetContract.fingerprint()` with no hand edit (P10 N5). Wire enums
stay append-only and readers strict. Every row below is built; the values as built are listed in
[event-bus.md, Facts](../design/event-bus.md#facts) (`CombatFact` 47–53, `CampaignFact` 33–38),
including CO23's `UNIT_LEFT = 51`, `TURN_ENDED = 52` and `SEAT_STARTED = 53` (CO23's row
below). "Route drawn" is `NODE_CHOSEN` for no seat, not a kind of its own (question 60).

| Addition | Kind | Step |
|---|---|---|
| `SendUnitsCommand`, `CallForAidCommand` | Combat commands (wire types) | CO2 |
| Units sent, units returned, aid called | `CombatFact.Kind`, appended | CO2 |
| A wave's reach and entered tiles | `CombatFact.Kind`, appended | CO4 (`DARKNESS_WAVE_SPREAD = 50`) |
| A unit leaving a map in play, a turn's end, a seat's start | `CombatFact.Kind`, appended (`UNIT_LEFT = 51`, `TURN_ENDED = 52`, `SEAT_STARTED = 53`) | CO23 |
| `ProposeSwapCommand`, `AnswerSwapCommand`, `WithdrawSwapCommand` | Campaign commands | CO5 |
| `RouteVoteCommand` | Campaign command | CO6 |
| Route voted, route drawn; swap proposed, accepted, ended; heirloom offer replaced; seat forfeited | `CampaignFact.Kind`, appended | CO5–CO7, CO14 |
| Expected-heirloom slot on `TreasureCommand` and `KeyHeirloomCommand` (appended field) | Campaign commands, wire fields | CO7 |
| `EventOptionCommand` on a team choice | Changed meaning: one seat's own part | CO9 |
| `ForfeitCommand` | Campaign command | CO14 |
| `NetRelay._seat_settings(settings: Dictionary)` | `any_peer`, `call_remote`, to the host | CO15 |
| A fast-forward vote | N8 notice kind | CO15 |
| `NetRelay._forfeit_record(envelope: Dictionary)`: the leaving client's archive record, then its seat `REMOVED` | `authority`, `call_remote`, `reliable`, host to that client alone | CO18 |
| A client's `ForfeitCommand` runs `CampaignService.forfeit_seat()` on the host; `seat_removed` now also means a forfeit | Changed meaning | CO18 |
| `NetRelay._match_ended()`: the host's Save & Quit, before it leaves; a lobby client goes to its main menu **(Q 181)** | `authority`, `call_remote`, `reliable`, host to every seated client | CO19 |
| The host cuts a let-go forfeiter's connection after `LET_GO_WAIT`; SaveService's run messages go only to members playing a seat **(Q 183)** | Changed behaviour, no new message | CO19 |

A command merged before NT3 gets its wire form in NT3; one merged after adds its own (N5).

## Work Breakdown

Each step is one build session, merged on its own. "Needs" lists other steps, NT steps and plans;
"Questions" must be answered first. Every step runs its suites, `--check-only` on every changed
`.gd`, and the full runner before merge.

| Step | What | Risk | Needs | Questions | Lane (other lanes' files) | Done when |
|---|---|---|---|---|---|---|
| **CO1** Every map must be completed | Co-op loss rules in `Objectives`; frozen maps; `CombatEncounter.is_run_lost()`; the darkness `TODO` | 🟡 rules, co-op only | — | 5, 6, 7 | D (`scripts/map/objectives.gd`, `scripts/sessions/combat_encounter.gd`) | 2–4-seat encounters: a fallen commander's map plays on; an empty map freezes and its turn stops; a Defend loss ends only that map; each run-loss case of question 6; every solo case and golden log unchanged |
| **CO2** Sending units and calling for aid | `SendUnitsCommand`, `CallForAidCommand`; the battle clock; one target per send; the frozen-map rule; returns; senders recorded; facts; `combat_state` v4; the phase-end save if question 39 says so | 🔴 save, wire | CO1 (and question 39's bug fix, if (a)) | 8–15, 39 | D (`combat_encounter.gd`, `combat_state_section.gd`, `campaign_session.gd` for `has_received_units`: B) | Sends refused for each rule, accepted otherwise; arrivals by the clock, at once on a frozen map; returns when a map ends; v3 data loads; save and resume mid-transit; mirrors follow every new fact |
| **CO3** Units on a partner's map | Timed modifiers on transfers; the owner's Your Unit heirlooms registered for their units on each map; Commander's Standard scope | 🟡 effects | CO2 | 16–19 | D (`scripts/effects/`, `combat_encounter.gd`, `campaign_session.gd`'s heirloom registration: B; Standard's data) | A sent unit keeps Momentum's phases left; a Your Unit heirloom acts on a sent unit and a visitor and on nobody else there; Any Ally parts stay asleep; save and resume keep both |
| **CO4** The darkness on mirrors | The appended wave fact; mirrors follow reach and entered tiles; the hash covers reach | 🔴 wire (append) | — | 20 | D (`scripts/map/darkness*.gd`) | A mirror's `next_deepening()` equals the host's after every darkness phase in the darkness cases; hashes cover reach |
| **CO5** Unit swaps | Propose, answer, withdraw; the host's open proposals; `run_flow` v2; the visitor in `battle_request()` and deployment by role; ends on a unit leaving | 🔴 save | — | 21, 22 | B (`scripts/campaign/`, `campaign_session.gd`) | Every refusal of swaps decisions 2, 3 and 7; a visitor deploys by role on the partner's map, owned and controlled by its seat; the swap survives a quit and lapses after the combat; v1 data loads |
| **CO6** Route votes | `RouteVoteCommand`; the weighted draw from `ROUTE_DRAW`; `campaign_map` v2; co-op refuses a seat's `ChooseNodeCommand` | 🔴 save | — | 23 | B | 2–4-seat votes draw by weight from the seeded stream (golden); a re-vote replaces; quit mid-vote keeps votes; solo unchanged; v1 data loads |
| **CO7** Unique heirloom claims | The first take wins at Treasure, key heirloom, events, starting offer; replacement offers | 🟡 | — | 24 | B (`scripts/events/` offers: C) | Two seats offered one unique heirloom: the first take wins, the other's offer is replaced from its own stream, saved; non-unique heirlooms unchanged |
| **CO8** The co-op battle's end | Results when every map ended; per-seat `COMBAT_ENDED`; a failed seat's empty results; XP, Standout and grades for units on a partner's map; a co-op run lost; swaps lapse | 🟡 rewards, run end | CO1, CO2, CO5 | 25, 26 | B (`campaign_service.gd`) | 2- and 3-seat battles with a failed map, a sent unit, a visitor and a fallen commander: each seat's rewards as questions 25 and 26 say; a lost co-op run archives for every seat; solo unchanged |
| **CO9** Team choices per seat | Each seat applies the drawn option with its own picks; done when every seat has; the surprise combat then | 🟡 | — | 27 | C | Bandit Toll and a test team event with picks in 2–4 seats; a seat's picks for a teammate refused; quit between seats' applies keeps both |
| **CO10** Campaign screens for their own seat | `CampaignService.local_seat()`; every campaign screen and the victory overlay read it and rebuild from signals; refusals shown; teammates' heirloom bars, buyers, Camp choices | 🟡 crosses screens | — (works on a client from NT5) | 2, 3 | B (`campaign_service.gd`) | Solo and a 2-seat host run look as before in the captures; a test that sets the local seat to 1 acts for seat 1 on every screen; no screen reads `seats[0]` |
| **CO11** The co-op campaign map | Route votes and the draw; the swap flow; teammates' status | 🟡 | CO5, CO6, CO10 | — | B | Captures of each vote and swap state in 2 and 4 seats; keyboard, mouse and controller paths |
| **CO12** The event screen for co-op | Local seat; teammates' votes and choices; per-seat team apply | 🟡 | CO9, CO10's `local_seat()` (works on a client from NT5) | 2, 3 | C | Captures of individual and team events in 2 seats for seat 0 and seat 1; the 450 and 455 capture groups pass |
| **CO13** The co-op battle screen | Send panel, call for aid, spectate, frozen banner, waiting, results after the whole battle; each a `.tscn` | 🟡 | CO1, CO2; NT5 removed the placeholder (question 1) or this step does | 1, 13 | A | On a 2-seat host battle: send, aid, spectate and freeze by keyboard, mouse and controller; captures; solo unchanged |
| **CO14** Forfeit: rules and save | `ForfeitCommand`; the seat leaves `players`; run sections, votes, proposals and swaps cleaned; the forfeited map in battle; archive v2 | 🔴 save | CO2, CO5, CO6, CO8 | 31–35 | B (`scripts/save/`, `save_service.gd`, `combat_encounter.gd`: D) | Forfeits at the map, in a shop, in an event vote and mid-battle (with sent and visiting units): the rest play on, a resume no longer needs the seat, every section validates; archive v1 loads |
| **CO15** Settings and fast-forward on the wire | `_seat_settings`; the host's per-seat settings in `begin_battle()`; the fast-forward notice | 🔴 network contract | **NT4** | 28, 29, 30 | E (`campaign_session.gd`: B; `battle_controller.gd`: A) | In the harness: seat 1's opening swap reaches the host's battle; a fast-forward needs every player on that map; TOD-003 gone |
| **CO16** Clients in the harness: campaign and events | 2- and 4-seat harness runs through every node type, route votes, swaps, team events and gifting from clients; fixes | 🔴 | **NT5**; CO6, CO7, CO9–CO12 | — | E (`ui/campaign/`: B; `scripts/events/`, `ui/campaign/events/`: C) | Every client's mirror hash equals the host's after every batch; a refused purchase settles to its sender only |
| **CO17** Clients in the harness: co-op battles | Sends, aid, swaps and freezes from clients; spectating a mirror | 🔴 | **NT5**; CO2, CO3, CO5, CO8, CO13 | — | E (`battle_controller.gd`, `ui/battle/`: A) | 2- and 4-seat harness battles with a send, a freeze, a visitor and a fallen commander: equal hashes after every batch; results on every client |
| **CO18** Forfeit and removal on the network | `ForfeitCommand` from a client; the host's Remove on `SeatWaitOverlay`; both run CO14 then `remove_seat()`; the archive sent first | 🔴 network, save | **NT6**; CO14 | — | E (`scene_router.gd`, `campaign_session.gd`: B) | In the harness: a client forfeits mid-battle and on the map; the host removes a dropped seat after the wait; the rest play on; the leaving client archives |
| **CO19** The co-op pause menu | Question 36's menu; the hint bar's co-op set | 🟡 | **NT6**; CO18 | 36 | B (`ui/common/pause_menu.gd`; the hint bar: A) | Host and client menus by keyboard, mouse and controller; Leave drops and rejoins; Forfeit runs CO18 |
| **CO20** Docs | multiplayer-combat-options.md, coop-unit-swaps.md and save-system.md marked built; the vision's Multiplayer items through the ideation thread | 🟢 | the answers; final pass after CO19 | — | F | No doc says a P11 rule is undecided or unbuilt once it is |
| **CO21** Live co-op check | The co-op rows below on two machines, with the user; fix what it finds | 🔴 | **NT8**; CO16–CO19 | — | E | Every row passes with both logs attached; M4 |

### Before NT6, and which NT step each needs

| Step | NT step needed | Why |
|---|---|---|
| CO1–CO9, CO13, CO14 | None | Headless rules and host-side screens, tested on local 2–4-seat sessions |
| CO10 campaign screens, CO11, CO12 event screen | **None to build** (questions 2 and 3 (a)); they work on a client from **NT5** | With question 3 (b) they need **NT4** to build and NT5 to finish |
| CO15 | **NT4** | The relay and the notice kinds |
| CO16, CO17 | **NT5** | Client mirrors |
| CO18, CO19 | **NT6** | `remove_seat()`, the overlay, drop and rejoin |
| CO21 | **NT8** | After P10's live check, as the gate says |

### Order

```
Lane D:  CO1 -> CO2 -> CO3        CO4 (any time)
Lane B:  CO10 -> CO6 -> CO5 -> CO7 -> CO8 (after CO2) -> CO11 -> CO14 -> CO19 (after CO18)
Lane C:  CO9 -> CO12 (after CO10)
Lane A:  CO13 (after CO2)
Lane E:  P10 NT3..NT6, with CO15 after NT4; CO16, CO17 after NT5; CO18 after NT6; CO21 after NT8
Lane F:  CO20 (after the answers; final pass at the end)
```

Parallel: CO1, CO4 (Lane D, one at a time), CO10, CO9 and the P10 steps can all run at once. CO10
first in Lane B, since CO11 and CO12 wait on it. CO13 starts once CO2 merges.

## Breaking Changes

| Change | Kind | Current | Accepted | Status | Places to check | Risk |
|---|---|---|---|---|---|---|
| A co-op map's loss | Behavior | Lost on a commander's fall or no player unit | Plays on; an empty map freezes | Built, CO1 (Q 5, 7) | `objectives.gd`, map and objective suites | 🟡 |
| `apply_battle()` with a failed map | Behavior | Stays at the node; `COMBAT_ENDED` is the team's | Results when every map ended; each seat its own | Built, CO8 (Q 26) | `campaign_run_state.gd`, results screen | 🟡 |
| `CombatEncounter.send_unit()` | Public method | Arrives at the next Phase Start | Gains the clock turn; called by the command | Built, CO2 (Q 8) | Encounter cases | 🟡 |
| `ChooseNodeCommand` in co-op | Behavior | Any seat, first arrival wins | Refused from a seat; votes decide | Built, CO6 (Q 23) | `campaign_map_screen.gd` | 🔴 |
| `EventOptionCommand` on a team choice | Network contract | One seat applies for all | Each seat its own part | Built, CO9 (Q 27) | `event_panel.gd`, event suites | 🔴 |
| `combat_state` 3 → 4, `campaign_map` 1 → 2, `run_flow` 1 → 2, archive 1 → 2 | Save format | — | New fields, no-op migrations | Built, CO2, CO5, CO6, CO14 (Q 15, 34) | save-system.md rows | 🔴 |
| A campaign's player count | Save rule | Fixed for its life | Can shrink on a forfeit | Built, CO14, CO22 (Q 31, 115) | `campaign_data.gd`, admission | 🔴 |
| New commands, facts, `_seat_settings`, a notice kind | Network contract | — | Appended | Built, CO2–CO7, CO14, CO15, CO18, CO19, CO23 | Fingerprint (automatic) | 🔴 |
| `CampaignService.local_seat()` | New public method | Screens use `seats[0]` | Every screen reads it | Built, CO10 (Q 2) | Every campaign and event screen | 🟡 |
| Mirror signals | P10 amendment | — | Mirrors emit `campaign_batch_resolved`, `command_rejected` | Built, P10 NT5 (Q 3) | NT5 | 🟡 |

## Verification

- **Headless, every step:** its suites (sessions, combat, map, campaign, events, save, ui; `net`
  from CO15), `--check-only` on every changed `.gd`, the full runner before merge. Every solo
  suite, golden log and capture stays as it was; co-op rules switch on only with more than one
  seat.
- **Harness (CO15–CO18):** P10's two-peer harness with 2 and 4 seats, hashes compared after every
  batch, drops and rejoins mid-send and mid-vote.
- **Live (CO21),** after NT8's matrix, two machines, two Steam accounts, debug builds:

| # | Scenario | Pass when |
|---|---|---|
| C1 | A 2-player standard combat; the first winner sends 2 units | They arrive by the battle clock next to the receiving commander, controlled by their owner |
| C2 | A map loses every unit | It freezes; the winner must send; the map goes on when they land |
| C3 | Both maps lose every unit | The run is lost for both |
| C4 | A commander falls | Its player plays on; it returns at critical health |
| C5 | A swap agreed on the map | Each visitor deploys on the partner's map; each owner controls theirs |
| C6 | Route vote, 2 against 1 (3 players, if a third machine is available) | The draw follows the weights; every screen shows it |
| C7 | Bandit Toll as a team choice | Votes, the draw, each seat's own picks, the surprise combat |
| C8 | The client forfeits mid-battle | Its map leaves; the host plays on; the client archives a forfeit |
| C9 | The client drops; the host removes it after 2 minutes | The host plays on; a resume doesn't ask for the client |
| C10 | Pause menus on both | Neither pauses the game; Leave drops and rejoins |

Until CO21 passes, every P11 step that touches the network is marked **untested live**.

**What only CO21 can confirm** (noted by CO20; none of it is claimed as built and working live):

- Every co-op command, fact and capture over Steam between Windows and the Mac, with the mirrors'
  hashes equal on real machines; the harness runs two headless peers on one machine.
- The message sizes of four maps with sent units (NT7's limits; CO17 recorded what it saw).
- A forfeit and the host's Remove over Steam; the leaving client's archive write and its move to
  the main menu (CO18).
- `NetRelay._match_ended()` reaching clients before the host's leave closes the connection, and
  the lobby client landing on its main menu (CO19, question 181).
- The forfeiter cut-off over Steam, the member list after it, and whether `LET_GO_WAIT` (1 s) is
  enough (question 183, pending confirmation).
- Leave Match, then rejoining from the friends list; a reconnecting client's menu not pausing
  (question 185, pending confirmation); the rejoined client's screen move (NT6).
- Feel, which no test judges: freezing, the clock against a frozen map and the run-loss check
  (questions 5, 6, 8); runes on a teammate's map, own map only for now (question 136, revisit at
  CO21); a turn timer (question 37, revisit at the M4 playtest).

## Risks

- **Lane load.** Lane B holds 9 steps and still has RN10 and RN11; Lane D runs EN14–EN16. The
  orchestrator places CO1–CO4 around EN14–EN16 and the B steps after RN11, or moves some.
- **Shared files.** `combat_encounter.gd` (CO1–CO3, CO14; NT4's `batch_resolved`) and
  `campaign_service.gd` (CO8, CO10; NT4's route) are edited by both plans: one at a time.
- **Save bumps.** Four versions change; the archive bump must be ordered with P12's.
- **Rules nobody has played.** Freezing, the clock against a frozen map and the run-loss check
  (questions 5, 6, 8) are reasoned, not playtested; M4 may change them.
- **Message size.** Four maps with sent units make the largest snapshots; NT7's limits apply, and
  CO17 records the sizes it sees.
- **Untested live** until CO21.

## Rollback

Each step is its own merge; revert it. A reverted save step leaves newer section versions that the
older build refuses (same-build rule), so dev saves made with it are deleted. Network steps follow
P10's rule: both machines run the same revision.
