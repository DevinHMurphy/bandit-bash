# Effects System

How every rule-changing thing in Bandit Bash works: weapon and equipment abilities, Pouch items,
unit-type traits, status effects, heirlooms and runes. Read this before building any of them, and
before adding a new kind of effect.

**Status:** designed October 15, 2026; not built yet. The game rules it serves (damage stages, turn
phases, Block, Stance) are in [game-vision.md](game-vision.md#combat), which wins where the two
differ.

## The short version

- There is **one** effect model. A relic, a shield, a status and a unit trait are all the same kind
  of data and go through the same code.
- An effect is **trigger → condition → operation**, with optional **state** (a counter, charges or
  stacks).
- Anything that changes damage is a **modifier on a named damage stage**. Within a stage, flat
  values add and percent values multiply, so the order in which sources were gained never matters.
- Resolution is **pure**: units and an RNG in, a list of events out. Effects never touch nodes, UI,
  audio or disk.
- Counters run in two lanes, **this combat** and **this campaign** (like Slay the Spire's Pen
  Nib), stated in the effect text. One effect can have a counter in each.
- Every trigger has a **scope**: This unit, Your Unit, Any Ally Unit or Any Unit. That keeps
  effects meaningful in co-op.
- Duplicates **stack**, but the game avoids **offering** what a player already has (like Balatro).
- Every modifier carries its **source**, so the forecast can explain every number.
- New content is data. A new relic should normally be a resource file, not a new script.

## Why this shape

`Godot_FE/` used an enum of special effects, and combat code checked for each one where it
mattered (`Godot_FE/docs/systems/05_items_and_special_effects.md`). The result:

- Half the declared effects were never wired in, and nothing flagged it.
- The activation check (`always_active`, chance, stat thresholds) had no callers, so every effect
  behaved as always on.
- Effect rules were spread across combat, UI and inventory code.

This design makes every effect a handler on a known hook, so an unhandled effect fails a content
test instead of silently doing nothing.

## Anatomy of an effect

| Part | What it is | Examples |
|------|------------|----------|
| Trigger | When the effect is checked, and whose events count (its scope) | A [turn phase](game-vision.md#combat) or combat event, scoped to This unit, Your Unit, Any Ally Unit or Any Unit; or always on |
| Condition | Optional test that must pass | "every 10th hit taken this combat", "while Exposed", "25% chance" |
| Operation | What it does | Add a damage-stage modifier, gain Block or Stance, apply a status, heal, change a stat |
| State | Optional data kept between checks | Counters (one per lane), charges, stacks |

Triggers, scopes, counter lanes and conditions, with exact definitions and the wording effect text
uses, are catalogued in [effect-triggers.md](effect-triggers.md). Add new ones there.

**Damage-stage modifiers.** An operation that changes damage names one stage from the damage stage
table in [game-vision.md](game-vision.md#combat) (Attack, Mitigation, Critical, Multipliers) and
gives a flat or percent value. The pipeline gathers all modifiers from both units, sums the flat
ones and multiplies the percent ones for each stage, and applies the stages in order.

| Effect text | Trigger | Condition | Operation |
|-------------|---------|-----------|-----------|
| "Take 5 less damage" | always on | — | Mitigation +5 |
| "Every 10th Hit taken this combat: take half damage" | Hit taken, This unit | combat counter reaches 10, then resets | Multipliers ×0.5 on that hit |
| Fortified (status) | always on while active | — | Multipliers ×0.75 on incoming damage |
| "Before Combat: +2 Block" | Before Combat | — | gain 2 Block |
| "Excess healing becomes Block" | on heal | healing exceeds max HP | gain Block equal to the excess |

The last row shows how "overheal" fits without a separate mechanic: it is one operation, not a new
stat.

## Owners and sources

Every effect instance has an owner. The owner holds the effect's state; the counter lane decides
how long a counter lasts.

| Source | Owner | Counter lanes |
|--------|-------|---------------|
| Weapon, Equipment, Pouch item | The item instance; its state moves with the item to a new unit or the convoy | Combat and campaign |
| Unit-type trait | The unit | Combat and campaign |
| Heirloom | The player's army | Combat and campaign |
| Status effect | The unit | Combat only; statuses never outlast the battle |
| Rune | None; resolves once and is consumed | None |

Item instances need a stable id, separate from their definition, so state, saves and network
messages can refer to them.

## Duplicates

- **Copies stack.** Two copies of an effect both apply under the normal stage rules (flat values
  add, percent values multiply), and each copy keeps its own counters.
- **Heirloom offers avoid duplicates.** Shops, rewards, treasure and events don't offer a player a
  heirloom they already own, like Balatro's jokers. A specific effect can be allowed to break the
  rule (Balatro's Showman), and that is the only way to get a second copy.
- **Items can duplicate.** Named-effect weapons, equipment and Pouch items are offered freely, even
  if the player already owns one. Each copy is tied to the unit holding it, which limits how far
  copies can stack. Revisit this if duplicate items cause a balance problem.
- **Unique heirlooms in co-op.** Normally only your own heirlooms block an offer; a partner owning
  the same heirloom doesn't. Heirlooms tagged **unique** are the exception: once any player in the
  campaign owns one, it is never offered to anyone else. Tag a heirloom unique when it affects more
  than one player's units, e.g. anything scoped Any Ally Unit or Any Unit. If a unique heirloom is
  offered to two players at once, the first to claim it gets it, and the host replaces the other
  player's offer with a different heirloom of the same rarity.
- Statuses keep their own stacking rules (duration, weight or both); see game-vision.md.

## Determinism and multiplayer

- The host resolves; clients replay the resulting events. Clients never roll and never evaluate
  effects for real.
- Chance conditions draw from the seeded combat RNG stream, never the global RNG.
- The forecast runs the same pipeline without consuming RNG or advancing any counter. It shows
  whether the next hit would trigger a counter effect.
- Effects reference units, items and other effects by id, never by object, so events can cross
  the network.
- Scopes are evaluated relative to the effect's owner: Your Unit means units controlled by the
  owner's seat. A co-op partner's units are Any Ally Unit, never Your Unit.

## Readability

- Every modifier records its source effect, so the forecast can show a breakdown, e.g.
  "8 dmg − 5 Iron Skin × 0.5 Bulwark (10th hit) = 2".
- Effect text is generated from the effect's data, so text and behavior can't drift.
- Counters show their progress and lane on the item, unit or heirloom card (e.g. "Bulwark 7/10
  this combat").

## Save impact

Per [save-system.md](save-system.md):

- Campaign-lane counters and other run-long state (charges) are saved with their owner: item
  instances and unit traits with the player's roster or convoy, heirlooms with the player's army.
  These are per-player data, so they belong in `PlayerSaveSection`s in the `CAMPAIGN` block.
- During a battle, all effect state lives in the `COMBAT` block: combat-lane counters, statuses and
  the in-battle values of campaign-lane counters. Before `end_battle()`, campaign-lane values are
  written back to the campaign sections; combat-lane counters and statuses are dropped.
- State is plain JSON: definition ids as strings, counters as integers, converted in `restore()`.
- Section keys and versions are chosen when the system is built.

## Open questions

None. Decided October 23, 2026:

- **Checking the unique tag:** a content test warns (not errors) when a heirloom scoped Any Ally
  Unit or Any Unit is not tagged unique, so exceptions stay possible.
- **Caps on flat values:** no cap on stacked flat mitigation. Pure damage, splash and the darkness
  already get through it.
