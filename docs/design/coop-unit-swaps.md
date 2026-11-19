# Co-op Unit Swaps

A planning doc for co-op **unit swaps**: two players agree that a unit of each starts the next
battle on the other's map. **Each player keeps control of their own unit**, as with sending units
later in a battle; only where it deploys changes. Every swap needs both players' approval (the
user's request and vision, November 19, 2026). Nothing here is decided until it is in
[Decisions](#decisions).

**Status:** open, November 19, 2026. Not blocking M2 or M3; it lands with co-op (P11).

## Where it stands

- **Parallel maps** (game-vision.md, Combat maps; [multiplayer-combat-options.md](multiplayer-combat-options.md)):
  in co-op each player fights their own map at once.
- **H1 Reinforce** already puts a player's units on a teammate's map: a player who wins their map
  sends surviving units, which arrive at the next player phase on the deployment edge or a
  reinforcement point, **and their owner controls them there**. A swap is the same idea, decided
  before the battle instead of after a win.
- **Phases are per map:** every unit on a map shares its phases, and a map's player phase ends
  when every player with units on it has ended their turn (effect-triggers.md; P01 question 11).
  So a player with a swapped unit acts on two maps each round.
- **Every map must be completed** (L4): a map with no player units left freezes until help comes.
- **No battle prep:** the army deploys automatically by role, with an optional opening swap
  window that rearranges a player's own units (game-vision.md, October 27, 2026).
- **Known gaps for units on a partner's map** (design items, P11; P01 question 49): a sent unit
  loses its timed modifiers, and its owner's "Your Unit" heirlooms don't follow it. Swaps share
  both gaps, and both should be settled once, for sending and swapping alike.
- **Units stay per player** (Co-op ownership): a swap never changes who owns a unit.

## Options

### 1. When a swap is agreed

| Option | How it works | Cost |
|--------|--------------|------|
| **A. On the campaign map, for the next combat** | Between nodes, a player proposes; the partner accepts; it applies to the next combat only, then lapses | Players set it before they see the map they'll fight |
| B. At the start of a combat, before deployment | A short exchange step once both maps are known | Adds a wait before every co-op battle, against "no battle prep" |
| C. A standing arrangement | Stays in place for every combat until either player cancels | Easy to forget; a unit is quietly away every battle |

**Recommended: A.** It keeps battles starting at once, needs no new pre-battle screen, and the
next node is already chosen, so players know what kind of fight is coming.

### 2. What is exchanged

- **One for one** (recommended): each player sends one unit and receives one, so every map keeps
  its unit count, and enemy counts (which never scale with army size) stay fair.
- **Or also one-way loans:** a player lends a unit and fights one short. Closer to H1, but it
  weakens the lender's map; could come later.
- **Several pairs:** recommended at most one swap per pair of players per combat, so each map has
  at most one visitor per teammate.

### 3. Who can be swapped

- Never the commander: a map with no commander is lost under the commander rules, and its owner's
  defeat condition would sit on another player's map (recommended).
- Only living units in the army.

### 4. Deployment and control

- The visiting unit deploys with the host map's army in its deployment zone, placed by role like
  the rest (recommended), rather than on the edge as H1's latecomers do.
- Its owner controls it and ends their turn on that map; the map's player phase waits for both
  players, as the per-map phase rule already says.
- The opening swap window, if on, lets the map's owner rearrange the visitor too, or only the
  visitor's owner (to decide).

### 5. Rewards and risk

- **Permadeath stays:** a visiting unit that falls is its owner's loss.
- **XP:** the visitor earns personal XP for what it does and the shared XP of the map it fought on
  (recommended), as H1 recommends for sent units. The Standout and grades: counted on the map it
  fought on, for its owner (as H1 recommends), or not at all (to decide).
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
wire.

## Open questions

1. When: A (campaign map, next combat), B (pre-battle step) or C (standing)?
2. One for one only, or also one-way loans?
3. Where the visitor deploys: with the host army by role, or on the edge as H1's units do?
4. XP, the Standout and grades for a visiting unit?
5. In the opening swap window, who may move the visitor?
6. Settle "Your Unit" heirlooms and timed modifiers on a partner's map once, for swaps and H1?

## Decisions

None yet.
