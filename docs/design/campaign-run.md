# The Campaign Layer

How a run works in code, from the new run to its end: the map, each kind of node, how screens are
chosen, the commands and facts, playback, and saving. Read this before you change anything
between battles. The rules themselves are in [game-vision.md](game-vision.md) (Run structure,
Campaign nodes). The save format is in [save-system.md](save-system.md#run-state). Facts and
commands in general are in [event-bus.md](event-bus.md).

## The pieces

| Piece | What it is | Code |
|---|---|---|
| `CampaignService` | Autoload. Holds the run's session, saves after every command, wraps each battle's Begin and end | [campaign_service.gd](../../bandit-bash/scripts/autoload/campaign_service.gd) |
| `CampaignSession` | One run on the host: its streams, id allocator, bus, run state and the bridge into battles | [campaign_session.gd](../../bandit-bash/scripts/sessions/campaign_session.gd) |
| `CampaignRunState` | The run's rules state: map, route, flow, each seat's part, the fact log. Changes only through commands and a battle's end | [campaign_run_state.gd](../../bandit-bash/scripts/campaign/campaign_run_state.gd) |
| `RunFlow` | Where the run is (map, node, results) and what every seat shares: Unknown odds and outcome, used maps, shop stock | [run_flow.gd](../../bandit-bash/scripts/campaign/run_flow.gd) |
| `SeatRun` | One seat's part: roster, heirlooms, runes, gold and pending offers | [seat_run.gd](../../bandit-bash/scripts/campaign/seat_run.gd) |
| `RunOperations` | The changes many rules share: recruit, dismiss, upgrade, grant, scrap, and reads of the seat's campaign values | [run_operations.gd](../../bandit-bash/scripts/campaign/run_operations.gd) |
| `RunScreen` | Decides which screen the run belongs on | [run_screen.gd](../../bandit-bash/ui/campaign/run_screen.gd) |
| `CampaignPlayback` | Plays the run's facts on the campaign bus when a screen shows them | [campaign_playback.gd](../../bandit-bash/ui/campaign/campaign_playback.gd) |
| `RunSaveSections` | The six save sections of the run state | [run_save_sections.gd](../../bandit-bash/scripts/campaign/run_save_sections.gd) |

Everything in `scripts/campaign/` is rules code: pure, never awaits, never touches nodes or
autoloads, and draws randomness only from the streams it is given. Screens in `ui/campaign/` send
commands and show the results.

## How a run flows

1. **New run.** `SaveService.start_new_solo_run()` writes the run's first save and emits
   `campaign_activated`. `CampaignService` builds a `CampaignSession`, then `RunStart` builds the
   run: the map, each seat's army, starting gold, Commander Heirloom, three empty rune slots and
   its starting heirloom offer. The run is saved at once.
2. **Starting heirloom.** The run starts on the map stage, but `RunScreen` sends it to the
   starting heirloom screen while the offer is open. `StartingHeirloomCommand` takes one heirloom
   and its sub-choice together. No node can be chosen until every seat has picked.
3. **The map.** `ChooseNodeCommand` enters a node on the next floor that the current node leads
   to (any floor 1 node at the start). The floor locks and the stage becomes `node`.
4. **Inside a node.** `RunScreen.go()` routes to the node's screen. The screen opens the node
   (rolling its offer if it has one), the player acts, and `LeaveNodeCommand` returns the run to
   the map. The node stays visited.
5. **A combat.** A won battle moves the stage to `results`. The seat takes or skips its item pick
   and, after a Key combat, its heirloom; then Continue leaves the node.
6. **The end.** After the Boss's results, End run calls `CampaignService.end_won_run()`, which
   archives the run as won. A solo battle lost ends the run at once.

## The map

`CampaignMapGenerator` builds a `CampaignGraph` from `CampaignMapRules`
(`data/campaign/campaign_map_rules.tres`) and the run's `MAP_GENERATION` stream. The same seed
always gives the same map. Floors count from 1 to the Boss. Edges join only adjacent floors.
`CampaignRunState.next_nodes()` lists what can be entered next. The map rules also hold the
Unknown node's base odds. See [map-authoring.md](map-authoring.md) for combat maps, which are a
different thing.

## Each kind of node

| Node | Screen | Opens with | Then | Leaving needs |
|---|---|---|---|---|
| Standard, Key, Boss | Battle (`GAMEPLAY`), then the victory sequence | `CampaignRunState.battle_request()`, Begin | `ItemPickCommand`, `KeyHeirloomCommand` at results | The pick, and a Key combat's heirloom, resolved |
| Treasure | `TREASURE` | `OpenTreasureCommand`: every seat's chest | `TreasureCommand` takes or gives up the chest | Every seat's chest resolved |
| Camp | `CAMP` | Nothing to roll | `FeastCommand` or `TrainCommand`; `RegearCommand` and `GiftItemCommand` before or after | Every seat's choice made |
| Armory | `ARMORY` | `OpenArmoryCommand`: the shared stock | `ArmoryPurchaseCommand`, `GiftItemCommand` | Nothing: leave any time |
| Guildhall | `GUILDHALL` | `OpenGuildhallCommand`: the shared stock | `GuildhallPurchaseCommand`, `PrefixRerollCommand`, `GiftItemCommand` | Nothing: leave any time |
| Unknown | What it became | `ResolveUnknownCommand`, then for an event `OpenEventCommand` | That node's rules | That node's |

- **Combat.** `battle_request()` builds the battle from the node's map pool
  (`data/campaign/combat_map_pools.tres`), leaving out maps used since the pool last refilled, and
  each seat's living army, items, heirlooms and runes. The battle screen begins it through
  `CampaignService.begin_battle()`. At the end, `CampaignService.end_battle()` collects the result,
  applies it to a copy of the run with its rewards rolled (`CombatRewardRules`), saves, then drops
  the battle ([save-system.md, Battles](save-system.md#battles)). A won battle shows the victory
  sequence over the board; a run continued at its results shows it on `COMBAT_RESULTS`.
- **Unknown.** `UnknownResolution` rolls one d100 against the combat, shop and treasure chances;
  below none of them it is an event. A shop is an Armory or a Guildhall, evenly. The node then
  plays as that type (`CampaignRunState.node_type()`), with that type's rules and streams; the map
  still shows `?`. An event opens through `EventNode.open()` and plays on the event screen
  ([events.md](events.md)). Its Fight option makes the node a Standard combat.
- **The quiet road.** If an Unknown rolls an event but no event can be drawn there, the event
  can't open and the run stays on the placeholder screen (`NODE_PLACEHOLDER`). It says nothing
  happens here, and Continue leaves the node. With the game's events this doesn't happen in play.
- **Scrapping** a convoy item (`ScrapItemCommand`) works anywhere outside a battle, from the army
  view on the map or at a Camp.

## Routing

`RunScreen` is the one place that decides where the run belongs, so every screen routes alike
and a continued run reopens where it was saved. Solo and a co-op host route alike, by the local
seat (`CampaignService.local_seat()`).

- `RunScreen.of(session)` reads the stage. On the map: the starting heirloom screen while the local
  seat's offer is open, else the campaign map. At results: `COMBAT_RESULTS`. Inside a node: the screen for the
  type it plays as. An Unknown goes to the event screen with an event open, the battle screen once
  the event chose a fight, and the placeholder with no event.
- `RunScreen.go()` first settles an Unknown's entry (`enter_unknown()`: rolls it, then opens an
  event's event, each saved), then changes screen for everyone.
- Every campaign screen checks `of()` in `_ready()`. If the run belongs elsewhere it calls `go()`
  at once. A screen moves on when a batch it follows moves the run (see Screens and seats).
- With no run, `of()` returns the battle screen. A co-op combat node also goes there, to its co-op
  placeholder until the co-op battle screen comes (P10 NT5, P11 CO13).

## Screens and seats

Every campaign screen and the victory sequence act for `CampaignService.local_seat()`: the host
seat in solo and on the host; a test can set another (`set_local_seat()`), and P10 NT5 makes a
client's its own. No screen reads `session.seats[0]`; the ui/campaign suite scans for it.

- **A `CampaignLink`** ([campaign_link.gd](../../bandit-bash/ui/campaign/campaign_link.gd)) ties a
  screen to the session. `send()` submits the seat's command and ignores the return. What happened
  comes back from the session's signals: `batch_resolved` for every seat's batch, and `refused` for
  the seat's own refusals. A screen rebuilds from the run whenever a batch arrives. This works the
  same when a client's answer arrives later (P11 question 3).
- **Order.** What settles during a send is held until the submit, and its save, return. A
  follow-up send never runs inside the session's own `submit()`.
- **Which batches move a screen.** A screen follows the run to another screen for an answer to one
  of its own sends, or for a teammate's batch (a teammate's Leave takes everyone to the map). The
  seat's own commands sent from elsewhere (the host's rolls, a capture group staging the run)
  rebuild the screen but never move it.
- **Refusals** name seats as players in co-op ("Player 2 hasn't chosen Feast or Train"). A shop
  entry a teammate bought reads "bought by Player 2", on its card and when a purchase loses the
  race. Players are named "Player N" until Steam names reach the UI (TOD-001).
- **Teammates.** In co-op a Team button (on the map, inside the army view) opens the `TeamPanel`:
  each teammate's gold, army and heirloom bar. A Camp lists each teammate's choice
  (`CampTeamStatus`).

## Commands and facts

Every change between battles is a `CampaignCommand`
([campaign_command.gd](../../bandit-bash/scripts/campaign/campaign_command.gd)).

1. A screen builds the command for its seat and sends it to `CampaignService.submit_command()`.
2. `CampaignSession.submit()` stamps its arrival. `CampaignRunState.resolve()` checks it against
   the run as it is now (`validate()`), then resolves it (`resolve()`).
3. A rejected command changes nothing and costs nothing; its batch carries the reason, which the
   screen shows. Two seats acting on the same thing: the first arrival wins.
4. A resolved command records a `CampaignFact` for every change, returns them in a
   `CampaignBatch`, and is saved at once.

Commands are refused during a battle. The "Open" commands (`OpenTreasureCommand`,
`OpenArmoryCommand`, `OpenGuildhallCommand`) and `ResolveUnknownCommand` are valid only while
nothing is rolled yet, so a continued run never rolls twice. They record no fact, except
`ResolveUnknownCommand`'s `UNKNOWN_RESOLVED`.

Some facts come from no command: the run's start, a battle's end and its level-ups. The full list of
kinds, and what records each, is in [event-bus.md, Facts](event-bus.md#facts).

## Playback

The run keeps every fact in `CampaignRunState.fact_log`, numbered by `seq`. `CampaignPlayback`
plays the facts past `CampaignSession.played_seq` on the campaign bus, in order, each once. The
campaign sounds listen to that bus. The map plays what is waiting when it opens and after each
command. Every node screen plays after its commands. The victory sequence plays each level-up
as its card shows. The fact log and `played_seq` aren't saved, so a continued run plays nothing
from before the quit.

## Randomness

Every roll comes from a stream in the run's `RngStreams`, keyed by purpose, floor, node and seat.
Each node has its own streams (`SHOP_STOCK`, `UNKNOWN_RESOLUTION`, each seat's `REWARD` and
`PREFIX_REROLL`), so one node's rolls never move another's. Only the stream positions are saved
([save-system.md, RNG streams](save-system.md#rng-streams)).

## Saving and Continue

- **When.** After every resolved command. At a battle's Begin, at the end of each player phase,
  and at its end. On Save & Quit.
- **What.** The six run sections ([save-system.md, Run state](save-system.md#run-state)) and the
  events section. Each offer is rolled and saved before it shows, so a quit and Continue shows the
  same offer.
- **During a battle**, campaign writes keep the sections captured at Begin. The battle's changes
  live in the `COMBAT` sections until its end applies them.
- **Heirloom and curse carriers are never saved.** Each Begin makes them from the run's saved
  heirloom lanes, and the battle's end drops them. A continued run then mints the same ids as one
  never quit, so heirlooms react in the same order.
- **Continue.** Main Menu's Continue Run loads the save and sets `SaveService.resume_point`. The
  loading gate calls `RunScreen.go()`, which reopens the run on its map, in its node or at its
  results. A run saved mid-battle resumes the battle from its last save, or restarts it from
  Begin when the combat file can't be used.

## Co-op

Every seat has its own `SeatRun`; the map, flow and shop stock are shared. The rules handle
several seats, and the campaign tests cover them headless. On the host, the campaign screens serve
a co-op run for the local seat (Screens and seats). Route votes, swaps, the event screen's co-op
views and the co-op battle screen come with the co-op plan (P11); clients' screens come with
transport (P10 NT5).

## Tests

- `tests/campaign/`: the rules, headless. Map generation, run state, the battle bridge, rewards,
  placement, each node's rules, the Unknown's odds.
- `tests/sessions/`: the session and battle bridge, resuming included (`resume_cases.gd`).
- `tests/ui/campaign/`: the screens by keyboard, mouse and pad, a walk through a real run, and a
  whole seeded run with a quit and Continue at every stop (`full_run_cases.gd`).

Run them with `sh bandit-bash/tools/run_tests.sh campaign sessions ui/campaign`.
