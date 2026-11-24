# Co-op Unit Swaps

A planning doc for co-op **unit swaps**: two players agree that a unit of each starts the next
battle on the other's map. **Each player keeps control of their own unit**, as with sending units
later in a battle; only where it deploys changes. Every swap needs both players' approval (the
user's request and vision, November 19, 2026). The [Options](#options) are as they were weighed;
what holds is in [Decisions](#decisions).

**Status:** decided November 19, 2026 (user; see [Decisions](#decisions)). **Built** in P11, the
[co-op combat plan](../plans/2026-11-20-coop-combat.md): the rules in CO5, units on a partner's
map in CO3, rewards in CO8, the map screen's swap flow in CO11, the battle screen's visitor in
CO13, a forfeiter's swaps in CO14, clients in CO16 and CO17. Each decision below names its step
and the [P11 questions](../plans/decisions/P11-coop-combat.md) that settled its details. Untested
live until P11 CO21. The vision update goes through the ideation thread.

## Where it stands

- **Parallel maps** (game-vision.md, Combat maps; [multiplayer-combat-options.md](multiplayer-combat-options.md)):
  in co-op each player fights their own map at once.
- **H1 Reinforce** already puts a player's units on a teammate's map: a player who wins their map
  sends surviving units, which arrive by the battle clock next to the receiving player's commander
  (game-vision.md, Multiplayer maps), **and their owner controls them there**. A swap is the same
  idea, decided before the battle instead of after a win.
- **Phases are per map:** every unit on a map shares its phases, and a map's player phase ends
  when every player with units on it has ended their turn (effect-triggers.md; P01 question 11).
  So a player with a swapped unit acts on two maps each round.
- **Every map must be completed** (L4): a map with no player units left freezes until help comes.
- **No battle prep:** the army deploys automatically by role, with an optional opening swap
  window that rearranges a player's own units (game-vision.md, October 27, 2026).
- **Units on a partner's map** (design items, P11; P01 question 49): a sent unit lost its timed
  modifiers, and its owner's "Your Unit" heirlooms didn't follow it. Both are settled once, for
  sending and swapping alike, and built in P11 CO3 ([decision 8](#decisions)).
- **Units stay per player** (Co-op ownership): a swap never changes who owns a unit.

## Options

### 1. When a swap is agreed

| Option | How it works | Cost |
|--------|--------------|------|
| **A. On the campaign map, for the next combat** | Between nodes, a player proposes; the partner accepts; it applies to the next combat only, then lapses | Players set it before they see the map they'll fight |
| B. At the start of a combat, before deployment | A short exchange step once both maps are known | Adds a wait before every co-op battle, against "no battle prep" |
| C. A standing arrangement | Stays in place for every combat until either player cancels | Easy to forget; a unit is quietly away every battle |

**Recommended: A.** It keeps battles starting at once, needs no new pre-battle screen, and the
next node is already chosen, so players know what kind of fight is coming. (As built, choosing a
node enters it at once, so a swap is agreed before the route vote and holds for the next combat
the team fights: P11 question 21.)

### 2. What is exchanged

- **One for one** (recommended): each player sends one unit and receives one, so every map keeps
  its unit count, and enemy counts (which never scale with army size) stay fair.
- **Or also one-way loans:** a player lends a unit and fights one short. Closer to H1, but it
  weakens the lender's map; could come later.
- **Several pairs:** recommended at most one swap per pair of players per combat, so each map has
  at most one visitor per teammate.

### 3. Who can be swapped

- Never the commander: each player's commander stays on their own map, where they lead the fight
  (recommended). (An earlier reason, that a map with no commander is lost, no longer holds: since
  L4 a co-op commander's fall loses no map.)
- Only living units in the army.

### 4. Deployment and control

- The visiting unit deploys with the host map's army in its deployment zone, placed by role like
  the rest (recommended), rather than on the edge as H1's latecomers do.
- Its owner controls it and ends their turn on that map; the map's player phase waits for both
  players, as the per-map phase rule already says.
- The opening swap window, if on, lets the map's owner rearrange the visitor too, or only the
  visitor's owner (decided: the visitor's owner, decision 5).

### 5. Rewards and risk

- **Permadeath stays:** a visiting unit that falls is its owner's loss.
- **XP:** the visitor earns personal XP for what it does and the shared XP of the map it fought on
  (recommended), as H1 recommends for sent units. The Standout and grades: counted on the map it
  fought on, for its owner (as H1 recommends), or not at all (decided: for its owner, decision 6).
- **Loot** from that map (the item pick, Treasure) stays with the map's owner; the visitor brings
  nothing back but XP.

### 6. Approval

- One player proposes "my unit X to your map, your unit Y to mine". The partner sees both units
  and accepts or declines. Either can withdraw until the combat starts.
- A swap only involves the two players named; with 3–4 players nobody else is asked.

### 7. Save and network

- An accepted swap is saved with the run until the combat starts, so a quit and Continue keeps it.
  An unaccepted proposal isn't saved (recommended).
- The host places each visitor when it builds the maps; the battle save already holds every
  map's units. It needs P10's campaign wire (NT3) for the proposal and P11's merging of two
  players' units onto one map, which H1 needs too.

## Where it lands

**P11**, with H1 Reinforce: both put a player's unit on a teammate's map, so they share the
merging, control, phase and heirloom rules. The proposal itself is a campaign command over P10's
wire. Built as [Status](#co-op-unit-swaps) says.

## Open questions

- **When a swap can be withdrawn** (P11 question 190, open): decision 7 says "until the combat
  starts", but as built a swap is proposed, answered and withdrawn only on the campaign map, so
  inside a node (a Camp, a shop, an event or an Unknown, which can become a combat) it can't be.

## Decisions

Decided by the user, November 19, 2026: the recommendations, with the Standout and grades
counting for the unit's owner.

1. **Agreed on the campaign map, for the next combat only** (option A). Between nodes, one player
   proposes and the partner accepts; the swap applies to the next combat and then lapses.
   *Built (CO5; P11 question 21):* the next combat the team fights, kept through non-combat nodes,
   an event's surprise combat included.
2. **One for one.** Each player sends one unit and receives one, so every map keeps its unit count.
   One-way loans are not in. At most one swap per pair of players per combat. *Built (CO5;
   questions 22, 94):* at most one open proposal or accepted swap per pair (withdraw to change it);
   a unit already in an accepted swap can't be proposed; a unit may be in several open proposals,
   and accepting one ends the others naming either unit.
3. **Who:** only living units in the army; never the commander. *Built (CO5).*
4. **Deployment:** the visiting unit deploys with the host map's army in its deployment zone,
   placed by role like the rest. *Built (CO5):* `battle_request()` lists it with that army, still
   owned by its seat.
5. **Control:** the owner controls the visitor and ends their turn on that map; the map's player
   phase waits for both players. In the opening swap window, **the visitor's owner** moves it,
   since control never changes hands. *Built (CO5, CO13; questions 22, 91, 131):* each seat's own
   opening-swap setting decides its window on each map; with the window open, the visitor's owner
   may move it onto a free deployment tile it can stand on. The battle screen plays the seat's
   units on whichever map it views.
6. **Rewards:** the visitor earns its personal XP and the shared XP of the map it fought on. **Its
   Standout and grades count for its owner** (user). Loot from that map stays with the map's
   owner. A visitor that falls is its owner's loss (permadeath). *Built (CO8; questions 25, 104,
   105):* the owner's own map decides whether the seat is paid at all. A won seat's visitor on a
   failed map earns its personal XP and can be its owner's Standout, but no shared XP; a failed
   seat's visitor earns nothing. Its shared XP uses its owner's percent. A visitor doesn't cost
   its partner's map the speed bonus.
7. **Approval and saving:** a proposal names both units; the partner sees both and accepts or
   declines; either can withdraw until the combat starts. An accepted swap is saved with the run
   until the combat starts; an unaccepted proposal is not saved. Only the two players named take
   part. *Built (CO5, CO11, CO14, CO16; questions 22, 90, 92, 93, 95, 119, 140):* an answer names
   the two units it saw and is refused if the proposal names others; either named seat withdraws
   an open proposal or an accepted swap. Accepted swaps are saved in `run_flow.swaps`; open
   proposals live only in the host's run (`CampaignRunState.swap_proposals`) and reach clients in
   the run capture. A swap or proposal also ends when a named unit leaves its army or falls, and
   every one ends with the combat; facts `SWAP_PROPOSED`, `SWAP_ACCEPTED` and `SWAP_ENDED`. As
   built, proposing, answering and withdrawing work only on the campaign map, not inside a node
   ([Open questions](#open-questions)).
8. **Units on a partner's map share one rule set:** "Your Unit" heirlooms and timed modifiers for
   a unit on a teammate's map are settled once in P11, for swaps and H1 Reinforce alike. *Built
   (CO3; questions 16–18, 110–112):* timed modifiers travel with the phases they have left; the
   owner's Your Unit heirlooms and curses act on the unit there, except those triggered at Phase
   Start or Phase End, which act on the owner's own map only; Commander's Standard counts Your
   Units only.
