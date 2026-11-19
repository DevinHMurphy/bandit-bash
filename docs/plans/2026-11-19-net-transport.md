# Plan: Net Transport
**Date:** November 19, 2026
**Status:** Approved November 19, 2026. Orchestrator ID **P10**

## Problem

Co-op can open a lobby and start a run, and nothing after that crosses the network. The rules
layer is ready for it (one host resolves, clients mirror), but nothing carries its traffic.

- **Nothing sends commands or facts.** `Command.to_wire()` / `from_wire()`
  (`scripts/sessions/command.gd:93-140`) and `FactBatch.to_wire()` / `from_wire()`
  (`combat_session.gd:1291-1355`) exist and are tested (`tests/sessions/wire_cases.gd`), but the
  only RPCs in the project are the lobby's (`steam_network.gd:399-451`), the screen change
  (`scene_router.gd:215`) and the campaign replica pushes (`save_service.gd:912-928`).
- **The battle resolves on whatever machine presses the button.** `battle_controller.gd:2182-2183`
  calls `_encounter.submit()` and `_encounter.resolve_queued()` directly. On a client that would
  resolve rules locally; today it can't happen only because a client has no session at all.
- **Clients have no session.** `campaign_service.gd:382-384` gives a client a null
  `CampaignSession`, so every campaign and battle screen on a client has nothing to read (the
  empty heirloom bar in design items, UL8 report). A client only has
  `SaveService.multiplayer_replica`, refreshed at checkpoints.
- **Campaign commands have no wire form** (`campaign_command.gd`, design items P11 row), and the
  encounter's own facts have no batch signal: `CombatEncounter` appends mirrored cross-map facts to
  its log (`combat_encounter.gd:663`) without announcing them.
- **A drop forgets the player.** `steam_network.gd:539-548` removes a disconnected member from the
  admitted list, so a rejoin looks like a new join, and nothing pauses. The vision says a
  disconnect pauses everyone and the player rejoins from a snapshot.
- **Admission checks only the version string** (`lobby_admission.gd:57`). Two dev builds on
  different commits both report `0.1.0`, pass, and then misread each other: RPC methods are
  indexed, not named (kit pitfall 8), and fact readers refuse unknown kinds.
- **The wire contract's wording and its readers disagree.** `FactBatch.to_wire()` says "append
  new fields at the end only", but `from_wire()` refuses any length but 12
  (`combat_session.gd:1315`); `CombatFact` and `CampaignFact` refuse unknown kinds. Appending is
  safe for saves and repro dumps, not between live builds.
- **BUG-016:** `SteamNetwork.local_peer_id()` (`steam_network.gd:147`) raises an engine error once
  `leave_lobby()` cleared the peer, and returns 0 where its doc says 1.
- save-system.md's multiplayer paths are **untested live** (P00 row).

## Open Questions

None open. Questions 1–14 are answered in
[decisions/P10-net-transport.md](decisions/P10-net-transport.md), all as recommended; each place
an answer decides is marked **(Q n)**.

## Scope

**In (P10, transport):**

- The lobby as built, plus a build-contract check at admission and BUG-016.
- Peers and seats: which connection is which seat, kept stable through a drop.
- Authority: the host resolves everything; one gate for "may this machine decide".
- Sending: every combat and campaign command from a client to the host, every fact batch (each
  map's and the encounter's) and every campaign batch to every client, and rejections to their
  sender only.
- Client mirrors: a mirror `CampaignSession` and battle on each client, built from host
  snapshots, fed by batches, read by the existing screens unchanged **(Q 1, Q 2)**.
- Join, leave, drop and rejoin: pause for everyone on a drop, automatic reconnect, rejoin from a
  fresh snapshot, gap repair by catch-up, host quit ends the match.
- Resync from a snapshot: at battle open, on rejoin, on a mirror gap, and on a hash mismatch in
  debug builds.
- Network contract versioning, a headless two-peer test harness, and the live two-machine check of
  the transport.

**Out, to P11 (co-op rules on top):** route votes and the weighted draw; sending units (the
command, the arrival rules, the UI); call for aid; runes on a teammate's map in the UI (the
routing already exists); spectating's UI; frozen maps and L4's loss rules; a fallen co-op
commander; fast-forward votes; game speed as a lobby setting; shared shop stock and first-claim
purchases; unique heirloom claims; team events; per-seat settings reaching the host
(`campaign_session.gd` TOD-003); **forfeit and removal as a save change** (orchestrator:
owned by P11) **(Q 8)**; the per-map battle save format; the co-op pause menu; the client's darkness
reach (design items P11); every other P11 row in design items.

**Out of both:** host migration, joining a campaign one isn't part of, public matchmaking,
dedicated servers, voice or text chat (kit "Known gaps"; the vision's host-disconnect rule).

### Where P10 ends and P11 begins

P10 moves **any** command and **any** fact between machines, keeps every mirror equal to the host,
and survives a drop. It never decides a co-op rule. P11 adds the co-op commands and facts (vote,
send units, call for aid), their rules and their screens, and the save changes. With P10 alone, a
2–4 player run plays as today's rules already allow: parallel maps on their own turns, the first
`ChooseNodeCommand` to arrive picks the route **(Q 10)**, each seat its own rewards.

### What P11 needs from P10

| # | Need | Provided by |
|---|------|-------------|
| N1 | A seat directory: peer ↔ Steam id ↔ seat for the campaign's players, each seat's state (connected, dropped, removed) and signals when it changes | NT1, NT6 |
| N2 | One route for any `Command` (a rune on a teammate's map is a `session_id`) and any `CampaignCommand`, with the seat taken from the connection and the rejection told to the sender only | NT4 |
| N3 | Every map's and the encounter's batches on every client, so every client mirrors every map (the encounter's `ASSUMPTION` at `combat_encounter.gd:562` relies on it; spectating attaches playback to another map) | NT4, NT5 |
| N4 | A client's campaign mirror kept equal to the host's after every campaign batch and battle end, including the changes no fact records (battle-end gold, falls, a skipped pick) **(Q 2)** | NT5 |
| N5 | A rule for adding to the wire: a new command type registers its wire name; a new fact kind is appended; the build contract picks both up with no hand-kept number | NT1, NT3 |
| N6 | A pause and resume hook, `seat_dropped` / `seat_rejoined` / `seat_removed`, and a host-side `remove_seat()` that P11 turns into a forfeit **(Q 8)** | NT6 |
| N7 | The two-peer harness (`tests/net/`) for P11's co-op cases | NT2 |
| N8 | A presentation-only notice relay (selection markers, a call-for-aid flag's display) that carries no rules and changes no state | NT4 |

## Design Basis

- **game-vision.md, Combat maps, Multiplayer maps:** parallel maps on their own turns; runes on a
  teammate's map; spectating; game speed as a host setting "so clients never desync"; disconnects
  (pause for everyone with a timer, rejoin from a snapshot, host removal after a first-pass
  **2 minutes**, non-host forfeit, a host disconnect ends the match and the host resumes from its
  checkpoint). **Co-op ownership:** the host processes purchases in arrival order.
- **game-vision.md, Run structure:** the co-op route, "the host draws the result".
- **multiplayer-combat-options.md:** all of it; Disconnects and forfeits (decided October 24,
  2026) is the part P10 builds.
- **save-system.md, Multiplayer:** only the host saves; clients get `multiplayer_replica` and
  write their own profile and archive; resume admits only the campaign's Steam ids from the
  connection; "never send a Resource". **Testing:** untested live until two machines run it.
- **Event bus plan (P01), Commands, concurrency and rejoin:** resolve then play; commands
  validated at resolve time, first arrival wins; rejections to the sender only; no optimistic
  client changes; snapshots plus catch-up since the last checkpoint; idempotent mirrors; views
  rebuild from mirror state. It names "the net adapter" and "the drop policy" as this plan's.
- **master-ideation.md** is silent on multiplayer.
- **Open items:** game-vision.md's "Still open" multiplayer items (one battle state per player in
  the save, light links, shared-battle deployment, arrivals with no free tile) are all P11's or
  post-MVP; none is a basis P10 needs. The "untested live" mark is what NT8 clears.

## Legacy Behavior

`Godot_FE/` (Godot 4.7, `project.godot`) has **no multiplayer code**: no `@rpc`, no peer;
`steam/steam_controller.gd` calls the Steam API in `_init` without initializing it. Its
`docs/systems/14_multiplayer_integration.md` is a design, unbuilt. `steam_multiplayer_kit/`
(Godot 4.7.1, GodotSteam 4.21; never run as-is on two machines) is the reference for Steam and
peers; `bandit-bash/` already follows it for the lobby.

| Source | Behavior | Keep / Change / Drop | Reason |
|---|---|---|---|
| Kit model | Host is peer 1 and resolves everything; clients request and display; authority stays 1 on every node | **Keep** | Matches P01 and gdscript.md §10 |
| Kit P1 | `SteamNetwork.has_active_session()` / `is_authoritative()` gate every call | **Change** | One static gate that takes a `MultiplayerAPI`, which `SteamNetwork` calls, so a node under a test branch can use its own API **(Q 4)** |
| Kit P2 | Request → host validates → broadcast | **Keep** | Every command, both layers |
| Kit P3, `net_retry.gd` | Client-requested state with retry and ack; 1.0 s interval, 15 attempts | **Keep the pattern and values** | Snapshot requests; written fresh, nothing copied |
| Kit P4 | Live broadcast + catch-up + dedupe | **Keep** | Batches + `facts_since()` + seq-idempotent mirrors |
| Kit P12, P15 | Flow through autoloads; rosters built on the host | **Keep** | `SceneRouter`, the admitted list (already built) |
| Kit P13, `loading_gate.gd` | Nobody enters gameplay until every peer has loaded | **Drop** | Mirrors live in an autoload and catch up by seq; screens rebuild from mirror state |
| Kit P8, P10, P11 | Throttled transforms, owner prediction, input relay | **Drop** | Turn-based: no continuous state |
| Kit "Known gaps" | No reconnect after a drop | **Change** | The vision requires rejoin |
| Kit §6 (06 testing) | Optional ENet dev transport, two instances on one machine | **Keep, debug only** **(Q 11)** | Daily testing without a second machine |
| Godot_FE design §4.5 | State hash by `sha256_text` of a canonical string, not `hash()` | **Drop** | Peers are the same build (NT1), so `String.hash()` of `JSON.stringify(..., true)` is stable between them |
| Godot_FE design §10 | `PROTOCOL_VERSION` and a `data_hash` in the handshake | **Change** | A computed fingerprint, no hand-kept number **(Q 9)** |
| Godot_FE design §10 | A client nonce per command | **Keep, as a token** | Matches a client's pending command to its result |

**Tuning values carried over:** retry 1.0 s × 15 attempts (`steam_multiplayer_kit/templates/
scripts/net/net_retry.gd`); the 2-minute removal wait (game-vision.md, first pass). No value comes
from `Godot_FE/`.

## Approach

### The shape

| Piece | Where | Job |
|---|---|---|
| `NetGate` | `scripts/net/net_gate.gd` | Static `has_session(api)` and `is_authoritative(api)`; `SteamNetwork`'s helpers call them with their own API **(Q 4)** |
| `NetContract` | `scripts/net/net_contract.gd` | The build fingerprint admission compares **(Q 9)** |
| `SeatDirectory` | `scripts/net/seat_directory.gd` | Pure: the campaign's seats by Steam id, each seat's peer and state |
| `NetRelay` | `scripts/autoload/net_relay.gd`, a new autoload after `CampaignService` **(Q 3)** | Every run RPC: commands up, batches and snapshots down, pause, sync |
| Client mirrors | `CampaignService` | A mirror `CampaignSession` and battle on clients, built from host snapshots |
| `SeatWaitOverlay` | `ui/net/seat_wait_overlay.tscn` | "Waiting for <name>", the timer, the host's Remove (shown when P11 lands, **Q 8**) **(Q 13)** |
| Two-peer harness | `tests/net/` | Two to four peers in one process **(Q 5)** |

`SteamNetwork` keeps the lobby, Steam, admission and the member list. `NetRelay` knows nothing about
Steam: it reads its own node's `multiplayer` and the `SeatDirectory`, so the harness can put one
`NetRelay` under each test branch.

### Authority and the command route

- **One route.** `CampaignService.submit_command()` (campaign) and a new
  `CampaignService.submit_combat(command, session_id)` (combat) are the only ways in. On the host
  and in solo they submit and resolve now, as today. On a client they hand the wire array to
  `NetRelay`, which sends it to the host with a client token, and return nothing; the screen
  waits for the token's settle message, then rebuilds from the mirror (P01: no optimistic change).
  `battle_controller.gd:2182-2183` becomes one `submit_combat()` call **(Q 12)**.
- **On the host,** `NetRelay._submit_combat()` / `_submit_campaign()`: return unless server;
  look up the sender's seat in `SeatDirectory` (none, or the run paused: settle with a reason and
  stop); `from_wire()` (null: settle "malformed"); **overwrite `seat` from the connection**; check
  the session id names a map of the open battle; route through the same `CampaignService` call the
  host's own screens use. Every legality check runs at resolve time inside the session, as now.
- **Settle.** The sender gets `_command_settled(token, reason)`: empty when resolved, the
  rejection otherwise. A rejected command's batch goes to its sender only (P01).

### Batches down

- Every `CombatSession.batch_resolved` that isn't a rejection, every encounter batch (a new
  `CombatEncounter.batch_resolved` signal over the facts it mirrors), and every
  `CampaignSession.campaign_batch_resolved` go to **every** client, in the order the host made
  them, on one reliable channel (gdscript.md §10: discrete events are reliable; their order
  matters).
- **Campaign batches carry the run.** Each sends its facts (for presentation) and the run's
  capture (`RunSaveSections`' six parts). A client restores its mirror run from the capture, so
  what no fact records (battle-end gold, falls, a skipped pick) still arrives **(Q 2)**. The
  host also sends the capture after a battle's end applies to the run.
- **Combat batches** are `FactBatch.to_wire()` as they are. Clients apply them with
  `CombatSession.apply_batch()` / `CombatEncounter.apply_batch()`; a batch for a battle the client
  hasn't built is dropped, since the snapshot that follows covers it.
- **Not used:** `MultiplayerSynchronizer` (rules state is `RefCounted`, not node properties, and
  playback needs the facts in order); throttling and phase stagger (one message per resolved
  command, none while idle, so §10's rate rules don't apply). Payloads are Arrays and Dictionaries
  of plain values; object decoding stays off.

### Client mirrors

- **Campaign.** On a client, `CampaignService` builds a mirror `CampaignSession` from the run
  capture (the path `RunSaveSections.attach()` takes), flagged `is_mirror`, which never resolves:
  its `submit()` refuses. The screens read it as they read the host's.
- **Battle.** When the host's battle opens, `NetRelay` sends the encounter's `snapshot()`, taken
  between commands. The client rebuilds the battle the way a resume does
  (`CampaignSession.resume_battle()`: the request from the mirror run, setup from the run seed)
  and loads the host's snapshot instead of a save. It then follows batches. Every client mirrors
  every map (N3).
- **Request with retry.** A client that needs state (battle open, gap, rejoin) asks with
  `_request_sync()` every 1.0 s, at most 15 times (kit P3); the host answers idempotently.
- **Gap repair.** `apply_batch()` returning `ERR_PARAMETER_RANGE_ERROR` sends the client's last
  seq per map; the host answers with `facts_since()` when `can_catch_up()`, else a fresh snapshot.
- **Hash mismatch** (debug builds, where batches carry hashes): the client writes
  `debug_dump()`, logs WARN, and asks for a fresh snapshot **(Q 14)**.

### Drop, pause and rejoin

- **Seats are kept.** On `peer_disconnected` during a run, the host marks the seat **dropped** in
  `SeatDirectory` (the admitted list keeps it with no peer) instead of forgetting it.
- **Pause for everyone** (vision): while any seat is dropped, the host settles every command,
  its own included, with "paused"; batches already resolved still play. Every peer shows
  `SeatWaitOverlay` with the time waited **(Q 7)**.
- **Reconnect.** A client that loses the host mid-run doesn't return to the menu: it shows the
  overlay and calls `join_lobby()` on the same lobby every 1.0 s until it is back or the host
  ends the wait. A client that crashed rejoins through the friends list or an invite. Admission
  admits a campaign Steam id whose seat is dropped (a new `NetContract` check, below, first).
- **Rejoin from a fresh snapshot**: the run capture, the battle snapshot when one is open, and the
  screen to open. No catch-up from memory across a reconnect **(Q 6)**.
- **After 2 minutes** (vision, first pass) the host may remove the seat. P10 builds
  `remove_seat()` and its signal; P11 turns it into a forfeit **(Q 8)**.
- **The host leaves:** clients get `session_ended` (exists), see why, and go to the main menu; the
  host resumes from its last checkpoint (exists).

### Network contract versioning

- **Peers must be the same build.** RPCs are indexed by method, so mixed builds can't talk
  safely. Admission compares the game version **and** `NetContract.fingerprint()`; a mismatch is
  a new `LobbyAdmission.Refusal.BUILD_MISMATCH = 3` (appended) with its own text.
- **The fingerprint is computed, never kept by hand:** a hash of every wire enum's names and values
  (`CombatFact.Kind`, `Source`, `CombatSide`, `DamageType`, `Flag`; `CampaignFact.Kind`;
  `LobbyAdmission.Refusal`; `NetRelay`'s message kinds), the wire patterns, the snapshot format
  constants, every command type's wire name, and `NetRelay`'s and `SteamNetwork`'s
  `get_rpc_config()`. EV1's and EV2's appended `CampaignFact` kinds change it with no edit.
  Recommended: also the MD5 of every file under `res://data/` and `res://maps/`, so a client never
  mirrors with other content **(Q 9)**.
- **Append-only stays the rule** for every wire enum and slot list, because saves and repro dumps
  outlive a build. **Readers stay strict** (exact length, known kinds), so a newer build's data is
  refused, never guessed, as saves do. `FactBatch`'s "append at the end" doc gains that sentence.
- **Snapshot format constants** (`CombatSession._SNAPSHOT_FORMAT` and the encounter's) still bump
  by hand; they guard dumped data. The fingerprint covers them.
- **Campaign commands** get the same wire form as `Command`: `get_wire_type()`, `to_wire()`,
  `from_wire()` with a registry in `CampaignCommand._of_wire_type()`. The class doc says a new
  type adds itself there (N5). EV2's `EventCommand` and `OpenEventCommand` are covered if merged
  before NT3; otherwise Lane C adds theirs **(Q 12)**.

### Every new RPC

All on channel 0, reliable. `any_peer` handlers return unless server, find the sender's seat in
`SeatDirectory`, and range-check every argument.

| RPC | Mode | Why |
|---|---|---|
| `NetRelay._submit_combat(wire: Array, session_id: int, token: int)` | `any_peer`, `call_remote` | Client command; the host has its own route |
| `NetRelay._submit_campaign(wire: Array, token: int)` | `any_peer`, `call_remote` | As above |
| `NetRelay._command_settled(token: int, reason: String)` | `authority`, `call_remote`, to the sender | The sender's pending command is done |
| `NetRelay._combat_batch(wire: Array)` | `authority`, `call_remote` | The host already applied it |
| `NetRelay._encounter_batch(wire: Array)` | `authority`, `call_remote` | As above |
| `NetRelay._campaign_batch(facts: Array, run: Dictionary)` | `authority`, `call_remote` | As above |
| `NetRelay._request_sync(have: Dictionary)` | `any_peer`, `call_remote` | Battle open, gap, rejoin; retried |
| `NetRelay._sync(run: Dictionary, battle: Dictionary, facts: Array, screen: int)` | `authority`, `call_remote`, to one peer | A snapshot or catch-up for one client |
| `NetRelay._seat_changed(seat: int, state: int, waited: float)` | `authority`, `call_local` | Every peer, the host included, updates its overlay the same way |
| `NetRelay._notice(seat: int, kind: int, data: Array)` | `any_peer` up, then `authority` `call_remote` down | N8: presentation only; never read by rules |
| `SteamNetwork._request_admission(game_version: String, contract: int)` | **changed** signature | The build check |

### Rejected alternatives

| Alternative | Why not |
|---|---|
| A client sends a command and also applies it | P01 and kit P2: no optimistic change; the first arrival wins on the host |
| Client mirrors built by replaying every campaign fact | Several changes record no fact (design items P11 row); a capture per batch is small and can't drift **(Q 2)** |
| Tolerant readers (skip unknown slots and kinds) | Peers are the same build anyway; a tolerant reader turns a build mismatch into a silent desync |
| A hand-kept `PROTOCOL_VERSION` | Forgotten bumps are the failure it exists to catch |
| Sending each batch per map only to that map's player | Every client mirrors every map (encounter assumption at `:562`, spectating) |
| A loading gate before every battle | Mirrors live in an autoload and catch up by seq |
| Running the relay's RPCs on `SteamNetwork` | Mixes Steam with run traffic, and the harness can't put Steam under a test branch |

## Save Impact

**Not saved.** Seat states, the pause, tokens, the reconnect target and client mirrors are live
state of one session: a full quit resumes from the host's checkpoint as today, and a client's
mirror is rebuilt from the host on every join. No section, key, version or core field changes.
The existing multiplayer paths (`multiplayer_replica`, client profile and archive writes, resume
admission by campaign Steam id) are kept as they are. `remove_seat()` changes nothing on disk;
P11's forfeit owns that change **(Q 8)**.

## Work Breakdown

All in **Lane E** (the net scripts and `SteamNetwork`). Each step is one build session, merged on
its own. Steps that touch another lane's files say so.

| Step | Work | Risk | After | Other lanes' files | Done when |
|---|---|---|---|---|---|
| NT1 Contract and seats | BUG-016; `NetGate`; `NetContract` (with Q 9's content hash, timed at boot); `Refusal.BUILD_MISMATCH`; admission sends the fingerprint; `SeatDirectory`; `tests/net/` pure cases | 🔴 network contract | Questions answered | — | A changed enum, wire pattern or data file changes the fingerprint; admission refuses it; seats map peers both ways |
| NT2 Two-peer harness | `tests/net/run_all.gd`; a loopback `MultiplayerPeerExtension` pair and branches with their own `SceneMultiplayer`; drop, delay and reorder switches; one ENet localhost case | 🟡 new suite | NT1 | Runner (Lane G) only if discovery needs it | Two to four branches exchange RPCs on the loopback and on ENet; a drop fires `peer_disconnected` |
| NT3 Campaign wire | `CampaignCommand` and `CampaignBatch` wire forms; the three campaign commands (and EV2's if merged) | 🔴 network contract | NT1 | `scripts/campaign/` (Lane B), `scripts/events/` (Lane C) | Every campaign command round-trips through JSON; malformed data is refused |
| NT4 Relay | `NetRelay` autoload; `submit_combat()` / route in `CampaignService`; the encounter's `batch_resolved`; commands up, batches down, settle, notices | 🔴 new autoload, RPCs | NT2, NT3 | `campaign_service.gd`, `combat_encounter.gd` | In the harness: a client's commands resolve on the host, batches reach every client, forged seats and malformed data are settled with a reason and change nothing |
| NT5 Client mirrors | Mirror `CampaignSession`; battle open snapshot; resume-path rebuild; gap repair; hash-mismatch resync; `battle_controller.gd` sends through the route and waits for its settle | 🔴 crosses lanes | NT4 | `battle_controller.gd` (Lane A), `campaign_session.gd` (Lane B) | A 2- and a 4-seat run in the harness: map, battle, results and map again, every mirror's hash equal to the host's after every batch |
| NT6 Drop, pause, rejoin | Seats kept on drop; pause; reconnect loop; rejoin admission; fresh-snapshot rejoin; `remove_seat()` and its signal; `SeatWaitOverlay` (keyboard, mouse, controller) | 🔴 network contract | NT5 | `scene_router.gd` (Lane B) | In the harness: drop mid-campaign and mid-battle, rejoin, equal hashes; commands while paused are refused; the host leaving ends the match |
| NT7 Size and live readiness | Measure the largest messages (4-seat battle snapshot, run capture); compress or chunk any over Steam's per-message limit; the ENet dev transport (Q 11); a `NetLog` line per relay message | 🟡 | NT6 | — | Largest sizes recorded in the step report; every message under the limit; two instances on one machine play a battle over ENet |
| NT8 Live check | The two-machine matrix below with the user; fix what it finds; mark save-system.md's multiplayer paths tested | 🔴 | NT7 | `save-system.md` (append-only row) | Every row passes on two machines with two Steam accounts, both logs attached to the report |

Order: NT1, then NT2 and NT3 in parallel, then NT4 to NT8 in order. P11's build gate opens after
NT6 (its rules need pause and rejoin), and M4's live test runs after P11.

## Breaking Changes

| Change | Kind | Current | Accepted | Status | Places to check | Risk |
|---|---|---|---|---|---|---|
| `LobbyAdmission.decide()` | Public method signature | Version, Steam ids | Gains the joiner's contract fingerprint | Accepted | `steam_network.gd`, `tests/save/multiplayer_cases.gd` | 🔴 |
| `LobbyAdmission.Refusal` | Network enum | 0–2 | Appends `BUILD_MISMATCH = 3` | Accepted | `describe()`, `lobby_screen.gd` | 🟢 |
| `SteamNetwork._request_admission` | RPC contract | `(game_version)` | `(game_version, contract)` | Accepted | Old builds are refused anyway | 🔴 |
| `SteamNetwork.local_peer_id()` | Behavior | 0 and an engine error with no peer | 1, no error (BUG-016) | Accepted | Callers outside a lobby | 🟢 |
| Disconnect during a run | Behavior | Member forgotten; client goes to the menu | Seat kept, game paused, client reconnects | Accepted | `scene_router.gd`, `lobby_screen.gd` | 🔴 |
| `NetRelay` | New autoload | — | After `CampaignService` | Accepted (Q 3) | `project.godot` (append-only) | 🟡 |
| `CombatEncounter.batch_resolved` | New signal | — | Encounter facts as batches | Accepted | — | 🟢 |
| `CampaignCommand` wire methods | New public methods | None | `get_wire_type`, `to_wire`, `from_wire` | Accepted | Every campaign command | 🔴 |
| `CampaignService.submit_combat()`, `CampaignSession.is_mirror` | New public members | — | The one combat route; the mirror flag | Accepted | `battle_controller.gd` | 🟡 |
| `FactBatch` wire doc | Contract wording | "Append at the end" | Plus "readers are strict; peers are one build" | Accepted | — | 🟢 |

## Verification

**Headless (every step):** `tests/net/` runs in the full runner like any suite. Pure cases for the
fingerprint, seats and wire forms; harness cases for every RPC, every refusal (forged seat, unknown
session, malformed wire, paused), 2- and 4-seat runs with hashes compared after every batch, drops
at each stage (map, battle start, mid-command, enemy phase, results), rejoin, gap repair and
mismatch resync. `--check-only` on every changed `.gd`; the sessions, campaign and save suites stay
green.

**Live two-machine matrix (NT8),** adapted from the kit's T1–T15, two machines, two Steam
accounts, byte-identical debug builds, file logging on:

| # | Scenario | Pass when |
|---|---|---|
| L1 | Solo run, Steam closed | Plays as today; no network error |
| L2 | Host a lobby; join by code and by invite | Both lists match; client `is_server=false` |
| L3 | Join from another commit | Refused with the build-mismatch text |
| L4 | Start a 2-player run; choose a node from each side | The first choice wins on both screens |
| L5 | A standard combat, each on their own map | Both maps play; each spectates the other's state; hashes match all battle |
| L6 | Results, item pick, back to the map | Each seat's own rewards; mirrors equal |
| L7 | Client pulls its network cable mid-battle, plugs it back in | Both pause with the timer; the client reconnects and resumes its map |
| L8 | Client force-quits mid-battle and relaunches | It rejoins from the friends list onto the same battle |
| L9 | Host quits mid-battle | The client returns to a usable main menu; the host resumes from its checkpoint with the client through the lobby |
| L10 | A forged command (debug key) for the other seat's unit | Host logs the refusal; nothing changes |
| L11 | Three nodes in a row | No `Node not found`, null-instance or hash-mismatch line in either log |

Until NT8 passes, every P10 step is marked **untested live** in its report.

## Rollback

Each step is its own merge; revert it. Nothing is saved, so no save file depends on any step.
Reverting NT1 also reverts the admission RPC's signature, so both machines must run the same
revision afterwards, as always.
