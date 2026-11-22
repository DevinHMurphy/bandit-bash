# P11 decisions: Co-op combat

The questions of the [co-op combat plan](../2026-11-20-coop-combat.md). Numbers are stable: steps,
markers and reports cite them. To read one question: `grep -n "^| 34 |" P11-coop-combat.md`.

The plan's Work Breakdown says which questions each step needs answered before it starts.

## Questions

### Boundaries with P10

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | Who makes the battle and campaign map screens work for a client's own seat and removes the battle screen's co-op placeholder (`battle_screen.gd:74`, `:106`, `:151`; `campaign_map_screen.gd:89-196` use `seats[0]`) | (a) P10 NT5, since P10 question 1 says a client plays its own map and NT5's Done-when runs map, battle, results and map again; (b) P11 CO13 | **(a)**: NT5 can't pass without it. P11 then adds only co-op rules and panels | **Answered** (user, November 21, 2026): as recommended. |
| 2 | Where a screen gets its own seat | (a) CO10 adds `CampaignService.local_seat()` now: the host seat in solo and on the host; NT5 makes it return a client's seat from the `SeatDirectory`; every screen switches to it now; (b) NT5 adds it, and CO10 and CO12 wait for NT5 | **(a)**: the campaign and event screens can then be made co-op-ready with no NT gate | **Answered** (user, November 20, 2026): as recommended. |
| 3 | How a screen learns a command settled, on host and client alike | (a) P10 amendment: a client's mirror `CampaignSession` emits `campaign_batch_resolved` for every batch it applies, and `command_rejected` for the local seat's settled rejections, as the host's session does now; screens rebuild from those signals, never from `submit_command()`'s return; (b) screens learn a separate client path after NT4 | **(a)**: one code path; CO10 and CO12 build now and work on a client from NT5 | **Answered** (user, November 20, 2026): as recommended. |
| 4 | Who fills the host-side objects (streams, event pool, id allocator) into a campaign command that arrived over the wire (design items, P11 / P10 row; today `EventNode` fills them for local commands) | (a) P10 NT4: its host route calls `complete_on_host(session)` on every campaign command after `from_wire()`, and each command fills its own; (b) a P11 step after NT4 | **(a)**: NT4's Done-when ("a client's commands resolve on the host") needs it for the event commands | **Answered** (user, November 21, 2026): as recommended. |

### Every map must be completed (CO1)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 5 | What a frozen map stops (L4: "a map with no player units left freezes until help arrives") | (a) the phase in progress finishes as it does now; the map then stops at its next player Phase Start: no player phase, enemy phase or darkness phase, and its turn counter stays; arrivals land at that Phase Start and the map goes on; a `TODO` marks where a later rule could let the darkness keep rising; (b) the enemies and the darkness keep acting on an empty map (the options doc's "possible later rule") | **(a)**: the vision says "freezes"; (b) is named as a later rule | **Answered** (user, November 20, 2026): as recommended. |
| 6 | When the run is lost (L4: "a map still being fought has no player units and no teammate has units left to send") | (a) checked whenever a map freezes or ends: lost when a map is frozen, no unit is on its way to it, and no map still being fought or won holds a unit that could yet be sent (a map still being fought counts as possible help, so the run waits for it); (b) lost as soon as a map freezes while no winner has units to send at that moment | **(a)**: a teammate still fighting may win and send; (b) would end runs the rules can still save | **Answered** (user, November 20, 2026): as recommended. |
| 7 | The commander rule on a map with units of several seats (P04 question 21: "any commander's fall loses a map shared by several seats", `objectives.gd:131`) | (a) in co-op a commander's fall never loses a map, shared or not (L4 (1)); the rule becomes solo only and the design item closes; (b) keep it for later shared battles | **(a)**: L4 already says the player keeps their units; shared battles are post-MVP and can reopen it | **Answered** (user, November 20, 2026): as recommended. |

### Sending units and calling for aid (CO2)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 8 | The battle clock against a frozen map: a frozen map's turn doesn't advance, so "arrive at its first player phase after its turn N" may never come | (a) units sent to a frozen map arrive at its next player Phase Start, the clock waived; (b) a frozen map's turn jumps to N so the clock holds; (c) keep the clock (they never arrive) | **(a)**: stalling gains nothing there, since the frozen map's player has no units to act with; (b) changes turn par and the darkness | **Answered** (user, November 20, 2026): as recommended. |
| 9 | When a winner sends, and how often | (a) a winner sends once, any time until the battle ends; "send none" is also final; but while a teammate's map is frozen, any winner with units left on their won map may send again, to the frozen map only; (b) once only, frozen map or not; (c) only right after winning | **(a)**: with (b) a winner holding units could not save a frozen map, so the run would be lost while "a teammate has units left to send" | **Answered** (user, November 20, 2026): as recommended. |
| 10 | What "a winner must send units to a teammate's frozen map" makes them do | (a) while any map is frozen, a winner who can send can't skip, and must send at least one unit, chosen by them, to a frozen map; (b) every surviving unit; (c) at least one, to any map | **(a)**: the least forced choice that still answers the freeze | **Answered** (user, November 20, 2026): as recommended. |
| 11 | Where units go when their target map ends before they arrive ("they return unharmed") | (a) back onto the sender's won map, as they left it, where they count as units left to send (question 9); (b) straight back to the army after the combat, out of play | **(a)**: under question 9 (a) they may still be needed for a frozen map | **Answered** (user, November 20, 2026): as recommended. |
| 12 | Arrivals with no free tile at all (vision, Still open; P04 question 24 b recommended a wait) | (a) confirm the built behavior: they stay on their way and try again at each player Phase Start (`combat_encounter.gd:381`); if the map ends first, question 11 applies; (b) other | **(a)**: built and matches the enemy waves | **Answered** (user, November 22, 2026): as recommended. |
| 13 | What a call for aid is | (a) a combat command on the caller's own map, raised and lowered by that map's player, recorded as a fact and saved with the map, so a rejoining or resumed peer still sees it; (b) a presentation notice only (P10 N8), lost on a rejoin or resume | **(a)**: it is shown on every sender's status panel and should survive a rejoin | **Answered** (user, November 20, 2026): as recommended. |
| 14 | How sends and calls for aid reach the host | (a) as combat commands through NT4's `submit_combat(command, session_id)`: a send on the sender's won map, a call on the caller's map; the encounter takes a send off its source map before that map's queue; no new RPC; (b) a new encounter route on `NetRelay` | **(a)**: no new RPC, and NT4's seat checks apply as they are | **Answered** (user, November 20, 2026): as recommended. |
| 15 | How the battle save grows | (a) one `combat_state` bump, 3 → 4, in CO2, holding every new co-op battle field (each winner's send, each transfer's clock turn, each map's senders and call for aid, and forfeited maps, empty until CO14); a no-op migration; (b) a bump per step that adds a field | **(a)**: one migration instead of three | **Answered** (user, November 20, 2026): as recommended. |

### Units on a partner's map (CO3)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 16 | Timed modifiers (Momentum and the like) on a sent unit (P01 question 49; today a transfer drops them) | (a) they travel with the unit and keep the phases they have left, counted on the receiving map from arrival; (b) dropped, as built | **(a)**: design items asks to carry them | **Answered** (user, November 22, 2026): as recommended. |
| 17 | The owner's "Your Unit" heirlooms on a unit on a partner's map (P01 question 49) | (a) they follow the unit: the owner's heirloom effects act on their units on every map, for sent units and swap visitors alike; (b) they don't, as built, and the unit detail says so | **(a)**: players will expect their heirlooms to keep working (design items) | **Answered** (user, November 22, 2026): as recommended. |
| 18 | Commander's Standard (allies within 2 of its owner's commander gain Block) on a map with a teammate's unit (P03 question 28) | (a) limit it to Your Units; (b) keep any ally, so partners' units gain its Block too | **(a)**: an heirloom that affects another player's units must be tagged unique (game-vision.md, Run-wide resources), and it isn't; (b) needs that content change | **Answered** (user, November 22, 2026): as recommended. |
| 19 | The cross-map forwarding hook (P01 question 44) | (a) still deferred: question 17's approach registers the owner's effects on each map that holds their units, and no MVP content needs forwarding; (b) build it now | **(a)** | **Answered** (user, November 22, 2026): as recommended. |

### The darkness on mirrors (CO4)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 20 | A client's darkness waves stay at reach 0, so its next-deepening preview differs from the host's (P06 question 15 e; save-system.md, Darkness, Mirrors) | (a) an appended fact kind records each wave's reach and newly entered tiles when it creeps, so mirrors follow it and `state_hash()` covers reach; (b) the client asks the host for the preview; (c) each darkness phase sends the map's darkness part of the snapshot | **(a)**: one small fact, the same mirror path as every other state | **Answered** (user, November 20, 2026): as recommended. |

### Unit swaps (CO5)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 21 | Which combat a swap applies to. coop-unit-swaps.md says "the next combat" and also "the next node is already chosen", but choosing a node enters it at once (`choose_node_command.gd`), so there is no gap between the route and the battle | (a) the next combat the team fights, kept across non-combat nodes, a surprise combat included; (b) the next node only, lapsing if it isn't a combat | **(a)**: closest to "for the next combat only" | **Answered** (user, November 20, 2026): as recommended. |
| 22 | Swap details the doc leaves to the build | (a) open proposals live in the host's memory only (not saved, swaps decision 7); an accepted swap ends if either named unit leaves the army or falls before the combat; on each map, each seat's own opening-swap setting decides its window there; a proposal can't name a unit already in an accepted swap; (b) other | **(a)** | **Answered** (user, November 22, 2026): as recommended. |

### Route votes (CO6)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 23 | Route vote rules (vision: vote, weighted draw, the host draws; Godot_FE notes: majority, host breaks ties) | (a) as events' team votes: voting again replaces a vote, a vote can't be withdrawn, the last vote draws from the floor's `ROUTE_DRAW` stream, votes are saved until the next floor's vote; solo chooses directly; in co-op a seat's `ChooseNodeCommand` is refused and the draw records the choice; (b) Godot_FE's majority with a host tie-break | **(a)**: the vision's rule, and the same shape as EV5 | **Answered** (user, November 20, 2026): as recommended. |

### Unique heirloom claims (CO7)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 24 | A unique heirloom offered to two seats at once outside the Armory (vision: the first claim wins; the other's offer is replaced by another of the same rarity; today only the Armory applies it, `armory_stock.gd:261`) | (a) every offer that can show one (Treasure, the key combat's heirloom, an event's rare heirloom, the starting offer): the first take wins, and every other open offer of it is replaced at once by another of the same tier, from that seat's stream the offer came from; (b) never offer a unique heirloom another seat is being offered (prevent it at the roll) | **(a)**: the vision's wording | **Answered** (user, November 20, 2026): as recommended. |

### Co-op battle end and rewards (CO8)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 25 | XP, the Standout and grades for units on a partner's map. Vision (sent units): personal XP there toward the same cap, no shared XP a second time, "the Standout stays on each player's own map". Swaps (visitors): personal XP, the shared XP of the map it fought on, "its Standout and grades count for its owner" | (a) one rule: a unit's actions anywhere count toward its owner's Standout and its own personal XP cap; the owner's grades come from the owner's map, plus their units lost anywhere; shared XP comes from the map the unit fought on (a sent unit gets its won map's only, never twice); a map's Standout is picked among its owner's units only; (b) sent units count only their own map's actions for the Standout; visitors as the swaps doc | **(a)**: it fits both texts and is one rule | **Answered** (user, November 22, 2026): as recommended. |
| 26 | A co-op battle with a failed map. Today the run reaches its results only when every map was won (`campaign_run_state.gd:282`), and every seat's `COMBAT_ENDED` records the team's result (`:277`) | (a) the run reaches its results when every map has ended; each seat's `COMBAT_ENDED` records its own map; a failed seat's results show the loss with no gold, XP, pick or Standout; (b) other | **(a)**: L4 | **Answered** (user, November 22, 2026): as recommended. |

### Team choices (CO9)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 27 | Applying a drawn team option over the network (P09 questions 24 and 33: today one seat applies it for every seat with every seat's picks in `team_choices`) | (a) each seat applies the drawn option to its own army with its own picks; the team's choice is done when every seat has applied, and a surprise combat starts then; (b) the host applies it for everyone | **(a)**: no seat ever picks for a teammate's army | **Answered** (user, November 20, 2026): as recommended. |
| 50 | `EventOptionCommand.team_choices` (a public member) after CO9: nothing reads it, since each seat applies a team choice with its own command; NT3 already keeps it off the wire | (a) remove it in a Lane C follow-up, with its line in `tests/net/campaign_wire_cases.gd` (`TOD-001` in `event_option_command.gd`); Breaking Changes: the member goes, no caller in production sets it; (b) keep it, ignored | **(a)**: an ignored public member invites a caller to think it works | **Answered** (user, November 22, 2026): as recommended. |
| 51 | `EventRunState.drawn_option()` once a seat has applied (CO9 needs the draw to hold between seats' applies, but an applied seat's `choosing` is -1 and can't stay set, since `restore()` refuses a seat both choosing and chosen) | (a) read each seat's `chosen` once it has applied, else its `choosing`; it then returns the drawn option until the next event opens, where it returned -1 after the team applied; (b) a separate method for "drawn, applied or not", leaving `drawn_option()` as it was | **(a)**: one meaning for every reader; without it a seat's vote after a teammate applied would draw again. `EventView.drawn` already showed the applied option, so the screen is unchanged | **Answered** (user, November 22, 2026): (a), as built in CO9. |
| 52 | How the event view says who has applied a team choice, for CO12 | (a) `EventView.choices` (by seat: the option chosen, or -1 while choosing; every seat of the event a key) and `EventView.seats_still_choosing()` (ascending); it covers individual events' teammates' choices too; (b) a team-only list of applied seats | **(a)**: one shape for both kinds of event, and CO12 also shows teammates' individual choices | **Answered** (user, November 22, 2026): (a), as built in CO9. |

### Settings and presentation (CO15)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 28 | How a seat's settings reach the host (TOD-003, the opening swap) | (a) a client sends its settings to the host through `NetRelay` when it joins and when it applies Options; the host keeps them per seat, unsaved; (b) a campaign command saved in the run | **(a)**: settings belong to each player's save file, not the run | **Answered** (user, November 22, 2026): as recommended. |
| 29 | Fast-forward votes (vision: players with units on a map vote to fast-forward its enemy phase) | (a) every player with units on the map must agree; a player alone decides alone; sent as presentation notices (P10 N8), unsaved; it pauses for boss combats and any player unit's death, as the vision says; (b) any one player | **(a)**: nobody's view is sped up against their wish | **Answered** (user, November 22, 2026): as recommended. |
| 30 | Game speed as a host lobby setting (vision): no game-speed option exists, even in solo | (a) wait for a solo game-speed option (P07 or P15); P11 then sends the host's value with the lobby; (b) P11 adds one now, which needs its values | **(a)**: there is no basis for the values | **Answered** (user, November 22, 2026): as recommended. |

### Forfeits (CO14, CO18)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 31 | A forfeit mid-battle ("their army and map leave the match at once") | (a) the map leaves every peer's view at once and nobody acts there; the save keeps it, marked forfeited, until the battle ends, so the battle's shape still matches its rebuild; the campaign's `players` loses the seat at once, so a resume no longer needs them; the seat's run sections go when the battle ends; (b) the map and its session leave the battle and its save at once | **(a)**: a resumed battle rebuilds from Begin's sections, which hold every seat (save-system.md, Battles) | **Answered** (user, November 22, 2026): as recommended. |
| 32 | Units across maps at a forfeit | (a) the forfeiter's units leave with them, wherever they are; teammates' units on the forfeiter's map return to their owners after the combat as they stood, like units whose target map ended; (b) teammates' units there count as fallen | **(a)**: permadeath should come from play, not from a teammate leaving | **Answered** (user, November 22, 2026): as recommended. |
| 33 | A forfeit on the campaign layer | (a) the seat's votes, proposals and swaps go; a vote that is complete without it draws; an heirloom only it held is free to be offered again; a shop's shared stock stays as rolled, and the next shop rolls for the seats left; (b) other | **(a)** | **Answered** (user, November 22, 2026): as recommended. |
| 34 | How the archive records a forfeit (vision: "archived for them as lost ('forfeited')") | (a) `won` stays false and a new `forfeited` field is true; `ArchiveRecord` schema 1 → 2, no-op migration (P12 also plans an archive bump: whichever lands first takes 2); (b) a third outcome, `"forfeited"` | **(a)**: `won` is a bool readers already use | **Answered** (user, November 22, 2026): as recommended. |
| 35 | Archiving a player the host removed after a drop: their machine never held the campaign | (a) only a connected player's machine archives: a voluntary forfeit sends the record before the seat goes; a removed player gets no record (a known gap); (b) each client keeps an unfinished co-op run stub in its profile, archived as forfeited at its next launch once the campaign has gone on without it | **(a)**: (b) needs a way for a client to learn it was removed | **Answered** (user, November 22, 2026): as recommended. |

### Screens (CO13, CO19)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 36 | The co-op pause menu (design items: it doesn't pause the tree, so the hint bar never shows PAUSED hints) | (a) the tree never pauses in co-op; the hint bar shows a "the game goes on" set; host: Resume, Options, Save & Quit (ends the match for everyone, after a confirm); client: Resume, Options, Leave Match (a drop: everyone waits, and they can rejoin), Forfeit (confirm; non-host only); (b) the menu pauses everyone | **(a)**: the vision pauses everyone only for a drop | **Answered** (user, November 22, 2026): as recommended. |
| 37 | A turn timer on a map two players share (a visitor's or sender's owner can stall its player phase) | (a) none in the MVP; revisit at the M4 playtest; (b) add one now (needs a value) | **(a)** | **Answered** (user, November 22, 2026): as recommended. |

### Scope and records

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 38 | Light links beyond runes on a teammate's map (design items) | (a) none in the MVP; the reinforcement-delay and team-counter ideas stay post-MVP; (b) add one | **(a)** | **Answered** (user, November 22, 2026): as recommended. |
| 39 | The end-of-player-phase battle save isn't wired in real play, solo included: only Begin and Save & Quit write a battle (`pause_menu.gd:171`; nothing else calls `save_checkpoint()` during a battle), against save-system.md's checkpoint table | (a) a bug-fix step now for solo, which CO2 extends to "any map's player phase end saves the whole battle"; (b) P11 builds it for both | **(a)**: solo players lose a battle's progress on a crash today | **Answered** (user, November 20, 2026): as recommended. |
| 40 | `CombatData`'s core `turn` and `phase` (one value; the lowest seat's map) | (a) unchanged, display only; each map's turn and phase stay in `combat_state`; no `CombatData` schema bump; (b) per-map lists in the core (schema 2) | **(a)**: nothing reads the core for rules | **Answered** (user, November 22, 2026): as recommended. |
| 41 | Design items' row "battle-end gold, falls, a skipped pick and the rune write-back record no fact" | (a) closed by P10 question 2 (every campaign batch carries the run's capture); P11 adds no fact kinds for them; (b) add facts anyway, for presentation | **(a)** | **Answered** (user, November 22, 2026): as recommended. |
