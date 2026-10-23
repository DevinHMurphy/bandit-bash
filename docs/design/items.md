# Items

Equipment, Pouch trinkets and consumables in Bandit Bash. Weapons and the inventory slots are in
[game-vision.md](game-vision.md#weapons-and-equipment), which wins where the two differ. Effects are
written in the [trigger vocabulary](effect-triggers.md).

**Status:** first pass October 15, 2026, converted from `Godot_FE/resources/definitions/items/`.
Every number is a starting point to tune in playtesting.

## The short version

- **Pouch items must beat a stowed weapon.** Any unit can carry a second weapon in its Pouch
  ([unit-roster.md](unit-roster.md#upgrades)), so potions, stat boosters and trinkets must be strong
  enough that stowing a weapon is an intentional choice, reinforced by a trait such as Sidearm.
- **Equipment is much better than trinkets.** Equipment is build-defining; a trinket is a small
  edge that competes with a consumable for the Pouch slot.
- `Godot_FE`'s 27 "equipment" items are split by what they are: wearable gear (cloaks, robes,
  bands, boots, weights) becomes Equipment, small charms (rings, coins, dice, tokens) become Pouch
  trinkets. Their effects are reduced for balance.
- **Every `Godot_FE` consumable stays.** Potions, keys and stat boosters go in the Pouch; the old
  growth boosters become **ingredients**, kept in the convoy and cooked at a Camp Feast for the
  whole army.
- Simple (basic) weapons carry no Block. Named weapons may.

## Budgets

Items use the prefix point scale from [unit-roster.md](unit-roster.md#prefixes): 1 point = 1 Might,
Speed, Defense or Resistance = 2 HP = 10 Hit = 10 crit chance = 10 avoid.

| Kind | Budget |
|------|--------|
| Trinket | About 1 point, or one small effect. Rare trinkets up to 2 |
| Equipment | About 3 points, or 2 points plus an effect |

Movement, Stance and Parry are premium: worth more than one point each, so they appear alone or with
a cost.

## Equipment

`Godot_FE`'s wearable items, sorted into the vision's categories, plus its shield weapons
converted to shield Equipment. Quivers and coatings are new (no `Godot_FE` basis).

**Weights.** Equipment weight adds to the weapon's in the Attack Speed formula, so heavy gear costs
Speed once it passes the unit's Constitution. Most pieces weigh 0–2; heavy armor and shields more.
`Godot_FE` equipment had no weight; these are first-pass values.

| Category | Item | `Godot_FE` effect | New effect | Weight |
|----------|------|-------------------|------------|--------|
| Cloak | Fancy Cloak | +12 HP | +6 HP | 1 |
| Cloak | Vitality Cloak | +5 HP | +4 HP; Phase Start: heal 1 | 1 |
| Cloak | Enshrouding Sash | +20 avoid, −1 DEF | +20 avoid, +1 SPD, −1 DEF | 0 |
| Armor | Magi Robes | +2 Magic | +2 MGT, +1 RES | 2 |
| Armor | Tungsten Ooze | +4 DEF, −1 MOV, counts as Armored | +4 DEF, −1 MOV, gains the Armored tag | 5 |
| Band | Power Band | +2 damage | +2 damage | 1 |
| Band | Old Soldier's Band | +1 Str, +1 Skl, −2 Lck | +1 MGT, +1 DEF, +10 Hit | 1 |
| Band | Sunshard Band | +10 HP; heals 20% at turn end | +4 HP; Phase End: heal 10% HP | 1 |
| Band | Training Weights | −2 SPD; growths +35% Str and Mag, +10% HP, −10% SPD | −2 SPD, and Speed can't grow while worn; every level-up: +1 MGT guaranteed | 0 (its Speed cost is the weight) |
| Band | Quick Soles | +1 MOV | +1 MOV | 0 |
| Quiver | Simple Quiver | — (no `Godot_FE` basis) | Hit dealt at range 2 or more: +1 damage | 1 |
| Quiver | Short Quiver | — | This unit's bows reach 1–2 instead of 2–3, so it can strike and counter at close range | 1 |
| Coating | Simple Coating | — | +2 damage against Exposed foes | 0 |
| Coating | Spirit Coating | — | This unit's attacks deal Magic damage, mitigated by Resistance instead of Defense | 0 |

**Shields.** `Godot_FE`'s 9 shield *weapons* become shield Equipment: they lose their damage and
durability, keep their defensive identity, and gain the Stance and Block the vision gives shields.
Their weights are halved from `Godot_FE` because they now stack with a weapon's weight instead of
replacing it. Higher-rarity shields exceed the 3-point budget, pending a rarity decision.

| Shield | `Godot_FE` (as a weapon) | New effect | Weight (`Godot_FE`) |
|--------|--------------------------|------------|---------------------|
| Iron Shield | +2 DEF, unbreakable | +2 DEF; Before Combat: gain 1 Block | 4 (8) |
| Buckler | +2 SPD, +2 DEF, +2 RES | +1 DEF, +1 RES; Before Combat: gain 1 Block | 4 (8) |
| Steel Shield | +4 DEF | +3 DEF; Before Combat: gain 1 Block | 5 (10) |
| Iron Greatshield | +3 DEF | +2 DEF, +1 Stance | 6 (12) |
| Knight Shield | +3 SPD, +3 DEF, +3 RES | +2 DEF, +2 RES; Before Combat: gain 1 Block | 7 (14) |
| Steel Greatshield | +6 DEF | +3 DEF, +1 Stance | 9 (18) |
| Silver Greatshield | +7 DEF, +2 RES | +4 DEF, +1 RES, +1 Stance | 8 (16) |
| Silver Shield | +5 DEF, +1 RES | +4 DEF; Before Combat: gain 2 Block | 10 (20) |
| Eye Shield (legendary) | +10 HP, −3 SPD, +5 DEF, +3 RES; foes can attack only once | +4 HP, −3 SPD, +4 DEF, +2 RES, +1 Parry | 12 (25) |

The Eye Shield's "foes can attack only once" becomes Parry, its direct equivalent in the new rules.

## Trinkets

`Godot_FE`'s small charms, now Pouch items. A unit carrying one has no room for a consumable.

| Trinket | `Godot_FE` effect | New effect |
|---------|-------------------|------------|
| Lucky Coin | +8 crit | +10 crit |
| Band of Fortune | +10 crit, +1 Skl, +2 Lck | +5 crit, +5 Hit |
| Loaded Die | +40 crit, −1 CritX | +30 crit, −1 CritX |
| Jester Mask | Crits ignore the target's Defense | Crits ignore the target's Defense |
| Null Sigil | Cannot be crit | +1 Stance |
| Oak Wood Charm | +10 avoid | +10 avoid |
| Mystifying Incense | +8 avoid | +5 avoid |
| Old Pendant | +1 RES | +1 RES |
| Traveler's Ring | +1 SPD, +1 Lck, −1 DEF | +2 SPD, −1 DEF |
| Scholar's Optics | −1 Str, +1 Mag | +10 Hit |
| Knight's Token | +2 HP, +2 Str, −3 SPD, +2 DEF | +1 MGT, +1 DEF, −1 SPD |
| Heavy Brick | +2 CON; heals 1 at turn end | +2 CON |
| Cleansed Goblet | +20% healing received, +4 Lck | +20% healing received |
| Family Ring | +4% all growths (+8% HP) | This unit earns +25% XP (about one extra level a run) |
| Royal Crest (rare) | +15% all growths | Every level-up gains at least 3 stats |
| Resonant Ore | −2 SPD; +10% all growths | −2 SPD; every level-up: +1 to a random stat other than Speed |
| Ring of Favor | +12 HP, +2 Str, Mag, DEF, RES, +1 Skl, SPD, +2 CON | +2 HP, +1 DEF, +1 RES |

Notes on the conversion:

- Strength and Magic bonuses become Might; Skill and Luck bonuses are dropped or turned into Hit
  and crit, since those stats are cut.
- **Null Sigil** no longer grants crit immunity: crits already need an Exposed target, and immunity
  would erase the Stance system for that unit. It adds Stance instead.
- **Growth trinkets** no longer raise growth percentages, which are worth almost nothing over a
  4–6 level run. Family Ring speeds leveling (+25% XP); Royal Crest sets a floor of 3 stats per
  level-up (a level-up averages about 2, so roughly +1 per level, about +5 over a run, slowly);
  Resonant Ore gives a guaranteed random stat each level-up.
- **Scholar's Optics** swapped Strength for Magic, which means nothing once both are Might.

## Consumables

Every `Godot_FE` consumable stays. Potions and keys are carried in the Pouch. Using one is the
unit's action for the turn, on itself or on an adjacent ally (there is no trading in combat, so this
is how a potion reaches a teammate):

| Consumable | Effect | Uses |
|------------|--------|------|
| Potion | Heal 15 HP | 3 |
| Potion+ | Heal 25 HP | 3 |
| Large Potion | Heal 15 HP | 5 |
| Large Potion+ | Heal 25 HP | 5 |
| Elixir | Heal to full | 1 |
| Refillable Potion | Heal 15 HP; refills after each combat | 2 |
| Chest Key | Opens chests | 3 |
| Door Key | Opens doors | 1 |
| Skeleton Key | Opens chests and doors | 5 |

Keys are the vision's lockpicks: any unit can carry one, at the cost of its Pouch.

`Godot_FE` had 35 stat boosters, five per stat: two that raised a stat permanently and three that
raised a growth. They split into two kinds of item.

**Stat boosters** are single-use Pouch items that permanently raise one unit's stat: the holder's,
or an adjacent ally's.

| Stat | Stat boosters |
|------|---------------|
| HP | Vermillion Tonic +3, Godseed Oil +7 |
| Might (old Strength) | Power Rune +1, Giant's Brew +2 |
| Might (old Magic) | Spirit Ink +1, Soul Dust +2 |
| Speed | Tempo Tonic +1, Wyvern Wingdust +2 |
| Defense | Infused Obsidian +1, Stonedragon Tail +2 |
| Resistance | Warding Worm +1, Ancient Anchor +2 |
| Hit (old Skill) | Adept Anchovy +5 Hit, Martial Scroll +10 Hit |
| All | Boost Bread: +1 Might, Speed, Defense and Resistance |

- The old Magic boosters become Might boosters too; both lines stay as flavor variants.
- Skill is cut, so Skill boosters give permanent Hit, at 5 Hit per old Skill point.
- Boost Bread's Skill, Luck and second Might point are dropped.

**Ingredients** are the old growth boosters. A growth bonus is worth almost nothing in a 4–6 level
run (+5% over 5 levels is a quarter of a point, and usually invisible), so they are reworked into
army-wide, guaranteed gains:

- Ingredients are stored in the **convoy**, one slot each, not the Pouch.
- At a Camp, the **Feast** choice heals every unit 35% of its HP and can cook **one** ingredient.
- A cooked ingredient gives every living unit in the army a guaranteed gain on its **next
  level-up**, shown on the unit card until it lands. Hit ingredients apply at once, since Hit has
  no growth. Units recruited after the Feast don't get it.
- In co-op, each player makes their own Camp choice. A Feast's heal reaches every player's units,
  and heals from several Feasts at one Camp stack. Its ingredient buffs only the cook's own army;
  a future heirloom could make an ingredient feed the whole team (it would be tagged unique, since it
  affects other players' units).

| Stat | Small ingredients (old 3–5%): every unit's next level-up | Large ingredients (old 7–20%): every unit's next level-up |
|------|--------------------------------------|---------------------------------------|
| HP | Heartbeet: +2 HP | Titan Trout, Century Cheese: +4 HP |
| Might | Brutvine Sap, Runewart, Wisdom Wine: +1 MGT | Brawn Prawn, Brutvine Heartroot, Moonclam Pearl: +2 MGT |
| Speed | Rushraddish: +1 SPD | Swift Shellfish, Hastehawk Feather: +2 SPD |
| Defense | Stonebark Blossom, Bastion Crab: +1 DEF | Stonebark Essence: +2 DEF |
| Resistance | Cave Carrot, Sanctuary Shell: +1 RES | Sanctree Branch: +2 RES |
| Hit (applies now) | Hawkweed, Precise Pepper: +5 Hit | Finesse Filet: +10 Hit |

For a 5-unit army a small ingredient is worth about 5 points and a large one about 10, against
Train's roughly 4–5 points plus a "+" trait on one unit: breadth against depth. Large ingredients
are the ones to watch in playtesting.

**Save impact:** a pending Feast gain is unit state; it is saved with the unit in the player's
roster section of the campaign block, and cleared when its level-up lands.

## Scrapping

There is no selling. Any item a player doesn't want is **scrapped** for gold: a single decision, made
where the player already is, so shopping stays short and the convoy never fills with junk.

- **Scrap value:** 20% of the item's buy price, Terraria's sell rate. First pass; tune in
  playtesting so scrapping stays a release valve, not a source of income.
- **At pickup:** when loot arrives and the convoy is full, keep it by scrapping something in the
  convoy, or scrap the new item.
- **At the Armory:** buying an item onto a unit either trades in the item it replaces (its scrap
  value comes off the price) or sends it to the convoy.
- **Anytime:** army management can scrap any convoy item in one step, showing the gold it gives.
- **Treasure items** (`Godot_FE`'s Gold Coins, Gold Ring, Spices, Vintage Wine) existed to be sold;
  they turn into their full gold value the moment they are picked up and never take a convoy slot.

## Open questions

- **Support weapons beyond staves** (whips, instruments, banners): stubs until a unit uses them.
- **Shield and armor weights against Constitution:** most MVP units have Constitution 5–14, so a
  shield plus a weapon often passes it. Check in playtesting that shields stay worth carrying.
- **Uniques:** the vision's "uniques" equipment category has no items yet.
- **Item rarity:** `Godot_FE` used 7 rarities (Standard, Unique, Common to Legendary); whether
  budgets scale with rarity is open.
