# Events

What an Unknown (`?`) node holds when it turns out to be an event (see
[game-vision.md](game-vision.md#run-structure) for how Unknown nodes roll). game-vision.md wins
where the two differ.

**Status:** first pass, October 22, 2026. Eight events are reworked from
`Godot_FE/resources/definitions/events/`; the rest are new. Every number is to be tuned in
playtesting.

## The short version

- An event is a short scene with **2–3 options**, each a clear trade-off, in the Slay the Spire
  mould. Some options need something (gold, a unit type, an item, the commander) and are greyed out
  without it.
- Effects use only vocabulary the game already has: gold, healing and damage, heirlooms, items,
  ingredients, runes, a free upgrade, a prefix re-roll, a recruit, a surprise combat, a revive, and
  **curses**.
- Stat changes are always **guaranteed and visible** (+1 MGT now, or "next level-up: +1 SPD"),
  never growth percentages, which are worth almost nothing in a 4–6 level run.
- A run never sees the same event twice.
- **Curses** are permanent negative heirlooms, grouped into three tiers matched to the reward, and
  always named before the player chooses.
- **Co-op:** most events are each player's own choice for their own army; some, including every
  event with a combat option, are a team choice, voted like the route.

## Curses

A curse is a **negative heirloom**: an army-wide passive in the heirloom collection that hurts.
Events charge curses as the price of strong rewards. Curses are meant to be a deliberate,
informed trade, never a surprise:

- **Permanent:** a curse lasts the rest of the run. Nothing removes it.
- **Always named up front:** an option that gives a curse names the exact curse and shows its effect
  and tier before the player chooses. There are no random curses.
- **Grouped by power level:** curses come in three tiers, and an option's curse tier matches the
  size of its reward, so a small reward never costs a crippling curse.
- **Never the economy:** no curse reduces gold, prices or rewards; they all act on combat.
- **Generation:** when an event is generated, each cursed option draws its curse from the right
  tier, among curses the player doesn't already hold (from the run's seeded stream). Curses don't
  count toward the heirloom cap. In co-op, a curse belongs to the player who took it.

| Tier | Paired with | Curse (first pass) | Effect |
|------|-------------|--------------------|--------|
| Minor | Modest rewards (a trinket, a small stat gain, about 40 gold) | **Haunted** | Phase Start: a random unit in this army loses 2 Block |
| Minor | | **Short Wick** | [The darkness](the-darkness.md) arrives one turn before turn par on this player's maps (the grade bonus still uses the real par) |
| Minor | | **Shaken Footing** | On the first turn of each combat, this army's units have −1 Stance |
| Minor | | **Heavy Pack** | Pouch items in this army weigh 2 each, counting toward Attack Speed |
| Major | Strong rewards (a rare weapon, a free recruit, about 80 gold) | **Leaden Boots** | Every unit in this army has −1 Speed |
| Major | | **Brittle Guard** | Every time a unit in this army gains Block, it gains 1 less (minimum 0) |
| Major | | **Clouded Sight** | Enemy intent icons are hidden on this player's maps; the danger zone still shows |
| Major | | **Ill Omen** | This army's commander has −1 Stance |
| Severe | Exceptional rewards (a rare heirloom and more) | **Hunted** | Every combat adds one extra enemy (a standard class at the army's level) on this player's maps |
| Severe | | **Cursed Blood** | Healing received by this army is halved (Feasts, staves, potions, terrain) |

## Events (first pass)

### Reworked from Godot_FE

**Dark Goblet** (`dark_goblet`): a crimson goblet on a pedestal.
- *Drink Deep:* a chosen unit gains +2 MGT and loses 4 max HP, permanently.
- *Infuse:* a chosen weapon gains "Hit dealt: heal 2" and +2 weight.
- *Pour It Away:* gain the Cleansed Goblet trinket.

**Cavern of Echoing Steel** (`cavern_of_echoing_steel`): walls that hum with metal.
- *Forge Resonance:* a chosen weapon gains +1 AtkX and +4 weight.
- *Listen Carefully:* a chosen unit gains +2 SPD.
- *Harvest Ore:* gain the Resonant Ore trinket.

**The Clockwork Hermit** (`clockwork_hermit`): a tinkerer's workshop.
- *Upgrade Gear:* a chosen weapon gains +1 damage, +5 crit and +1 weight.
- *Augment Unit:* pay 40 gold: upgrade a chosen unit, as a Camp's Train. *(Requires 40 gold.)*
- *Analyze the Mechanisms:* a chosen unit gains +10 Hit, permanently.

**Festival of Embers** (`festival_of_embers`): a lantern-lit square.
- *Be Merry:* every unit gains +2 max HP.
- *Collect Embers:* gain the Emberglass Vial, a consumable that heals 25 HP and refills after each
  combat (`Godot_FE`'s event item).
- *Perform for the Crowd:* gain 40 gold.

**Frozen Armory** (`frozen_armory`): a frost-bound vault.
- *Break the Ice:* gain a random rare weapon; every unit takes damage equal to 20% of its max HP
  from the cold.
- *Channel the Chill:* a chosen unit gains +2 RES.
- *Stay Warm:* every unit heals 20% of its max HP.

**Ghastly Library** (`ghastly_library`): voices in the stacks.
- *Answer the Voices:* the commander gains +2 MGT and loses 1 DEF and 1 RES. *(Requires the
  commander.)*
- *Take a Tome:* gain a random rare magic tome.
- *Ethereal Infusion:* gain a random rune.

**The Whispering Oak** (`whispering_oak`): an ancient, murmuring tree.
- *Drink the Sap:* a chosen unit loses 2 max HP; its next two level-ups each gain +1 MGT.
- *Carve a Token:* gain the Oak Wood Charm trinket.
- *Bow in Reverence:* every unit heals 20% of its max HP.

**Mirror of Doubt** (`mirror_of_doubt`): a mirror of warped reflections.
- *Face Yourself:* re-roll a chosen unit's prefix for free (it can come out worse, never the same).
- *Shatter the Mirror:* gain a random trinket and a **minor** curse (named before choosing).
- *Walk Away:* nothing.

### New

**Broken Shrine of Valor:** the **revive shrine** (settled in game-vision.md), using `Godot_FE`'s
shrine theme (`broken_shrine_of_valor`). Appears only if at least one unit in the army has fallen,
so it is never a free heirloom.
- *Offer a Prayer:* one fallen unit returns at critical health (10% of max HP, at least 1).
- *Claim the Relic:* gain a rare heirloom.

**Bandit Toll** *(team choice)*: brigands block the road. Built on `Godot_FE`'s scripted bandit
outcomes (bribe, fight, intimidate). In solo, "each player" is just you.
- *Pay the Toll:* each player loses 30 gold. *(Requires every player to have 30 gold.)*
- *Fight:* a surprise standard combat for the whole team, on parallel maps, with normal rewards.
- *Intimidate:* the bandits flee and leave their loot: each player gains 40 gold and a **minor**
  curse (named before choosing).

**Cursed Hoard:** a chest of gold on a bed of bones.
- *Take It All:* gain 80 gold and a **major** curse (named before choosing).
- *Take a Little:* gain 20 gold.
- *Leave It:* nothing.

**Mercenary Camp:** a band of sellswords for hire.
- *Hire the Best:* pay 50 gold: recruit a unit with a guaranteed +1 or +2 prefix, at the army's
  average level. *(Requires 50 gold.)*
- *Take a Volunteer:* recruit a unit with no prefix, for free, and take a **minor** curse (named
  before choosing).
- *Move On:* nothing.

**The Black Altar:** a pact offered in the dark. The one event with a severe curse.
- *Accept the Pact:* gain two rare heirlooms and a **severe** curse (named before choosing).
- *Take a Token:* gain one rare heirloom and a **major** curse (named before choosing).
- *Refuse:* nothing.

## Rules

- **Choosing a unit or weapon:** options that say "a chosen unit" or "a chosen weapon" let the
  player pick after choosing the option. Dead units can't be chosen, except by the shrine.
- **Requirements** grey an option out, with the reason shown, as in `Godot_FE`.
- **Recruits** from events follow the normal recruiting rules: they join at the army's average
  level, and past max army size they replace a unit ([unit-roster.md](unit-roster.md#recruiting-and-item-transfer)).
- **Surprise combats** are standard combats on the run's standard map pool, with normal gold and XP.
- **Pool:** an Unknown that rolls an event draws one this run hasn't seen yet, from the run's
  seeded stream.

## Co-op

As in Slay the Spire's co-op, some events are each player's own choice and some are decided by the
team. Each event is marked; events without a mark are individual.

- **Individual** (the default): everyone sees the same event, and each player picks their own option
  for their own army and gold.
- **Team choice:** one option for the whole team, decided **the same way as the route**: each player
  votes, and the option is drawn at random weighted by votes (2 votes against 1 gives a 2-in-3
  chance); the host draws. The chosen option applies to every player: each gets its reward, its
  curse, or its cost. An option is only available if every player meets its requirement.
- **Combat options are always team choices.** If the team picks a surprise combat, everyone fights
  it, each on their own parallel map, so nobody waits while a teammate fights alone.

## Not ported from Godot_FE

The other eleven `Godot_FE` events (Ancient Battlefield, Fountain of Quiet Flame, Sacred Grove
Trial, Hall of Ancestry, Moonlit Armory, Runed Obelisk, Shadowed Passage, Shattered Bridges,
Stormbound Keep, Wind Carved Archway, and the bandit scripts folded into Bandit Toll) are left for
later. Most of their options raised Luck, Skill, Magic or growth percentages, which no longer exist
or no longer matter; their themes are free to reuse.

## Open questions

- **More team events:** only Bandit Toll is a team choice so far.
- **Rarity:** how often the revive shrine appears once it is eligible.
- **Values:** every gold amount, stat change and curse is first pass.
- **More curses and events** once the MVP pool has been played.
