# Co-op Unit Swaps

A planning doc for letting two co-op players trade units during a run, each swap needing both
players' approval (the user's request, November 19, 2026). It works out the options against what
[game-vision.md](game-vision.md#army) and [unit-roster.md](unit-roster.md#recruiting-and-item-transfer)
already decide. Nothing here is decided until it is in [Decisions](#decisions).

**Status:** open, November 19, 2026. Not blocking M2 or M3; it lands with co-op (P11) or the
first step that builds co-op gifting.

## Where it stands

- **Units are per player.** Co-op ownership: "Everything is per player unless stated" (gold,
  convoy, runes, heirlooms, item picks). A player's army is theirs from start to end; the only
  shared things are the shops' stock.
- **Items can already move between players:** "Players can give items convoy-to-convoy at any
  Camp or shop, where the whole team is together" (unit-roster.md, Co-op gifting).
- **Units move between maps, not owners,** in battle: a player who wins their map sends units to a
  teammate's map (multiplayer-combat-options.md, H1 Reinforce); the units stay their owner's.
- **Army size:** each player has a max army size (Mercenary 4, hard ceiling 8). A replacement at
  max size goes through the one hand-over screen (unit-roster.md).
- **"Your Unit" heirlooms** follow ownership: a unit's heirloom effects come from its owner's
  heirlooms, so a swapped unit gains its new owner's and loses its old owner's.

## Options

### 1. Where a swap can happen

| Option | Fits | Cost |
|--------|------|------|
| **A. Camps and shops** (with gifting) | The existing "where the whole team is together" rule; Camps already re-gear, so a swapped unit can be re-geared at once | Swaps wait for those nodes |
| B. Any time on the campaign map, between nodes | Most flexible | Players may not be at the same node; breaks "together" |
| C. A new co-op node or event ("Crossroads") | A moment designed for it | New content and map weight |
| D. After a combat, at the victory sequence | Right after a unit shone or struggled | Adds a step to every combat's end |

**Recommended: A**, the same places as gifting, so co-op has one rule for moving things between
players.

### 2. What a swap moves

- **One for one** (recommended): each player gives one unit and gets one, so army sizes don't
  change and no one can be stripped. A one-way gift of a unit (when the receiver has room) could
  come later.
- **The unit travels with:** its level, XP, growths, prefix, upgrade, its equipped weapon and
  equipment and its Pouch (recommended: its gear is its own), or bare, with its gear going to the
  old owner's convoy.

### 3. Who can be swapped

- Never the commander (recommended).
- Never a fallen unit; only living units in the army, not in the convoy's temporary recruit slot.

### 4. Approval

- One player proposes: "my unit X for your unit Y".
- The other sees both units in full (stats, gear, prefix) and accepts or declines.
- Recommended: **accept completes the swap**, with no second confirmation, since the proposer
  already confirmed by proposing. Either player can withdraw before acceptance.
- One proposal per pair at a time; a new one replaces the old.
- With 3–4 players, only the two players named take part; the others aren't asked.

### 5. Limits

- Recommended: no count limit, since a swap is one-for-one and needs both players. Optional guard:
  a unit received can't be swapped again in the same visit, so a swap can't be bounced back and
  forth.

### 6. Effects and bookkeeping

- The unit's "Your Unit" heirloom effects switch to its new owner's at once.
- Run statistics (the Waystation war table, P12): kills and damage stay with the player who
  owned the unit when they happened.
- The Standout and personal XP stay with the unit.

### 7. Save and network

- Recommended: a pending proposal is **not saved**. A quit, a drop or leaving the node cancels it.
  A completed swap is one campaign command (`SwapUnitsCommand`), resolved by the host, recording a
  fact, and saved like any other.
- It needs P10's campaign wire (NT3) to reach the other player.

## Where it lands

- **Rules, headless:** with whichever step builds co-op gifting at Camps and shops (P08 keeps
  co-op rules headless-tested; P08 question 11). P08 RN7 (Camp) is the natural first home.
- **The proposal screen and its live use:** P11, once P10's campaign wire exists.

## Open questions

1. Where (option A, B, C or D)?
2. One for one only, or also one-way gifts?
3. Does gear travel with the unit?
4. Accept completes the swap, or both confirm a final screen?
5. The no-bounce guard: yes or no?
6. Built with gifting (RN7, headless) and finished in P11, as above?

## Decisions

None yet.
