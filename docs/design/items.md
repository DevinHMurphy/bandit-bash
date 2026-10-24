# Items

Equipment, Pouch trinkets, consumables, ingredients and runes in Bandit Bash. Weapons and staves
are in [weapons.md](weapons.md); the inventory slots are in
[game-vision.md](game-vision.md#weapons-and-equipment), which wins where the two differ. Effects
are written in the [trigger vocabulary](effect-triggers.md).

**Status:** first pass October 15, 2026, converted from `Godot_FE/resources/definitions/items/`;
rarities, prices, potions and ingredients reworked October 24, 2026. Every number is a starting
point to tune in playtesting. Porting `Godot_FE`'s rarities may mean rebalancing items against them.

## The short version

- **Pouch items must beat a stowed weapon.** Any unit can carry a second weapon in its Pouch
  ([unit-roster.md](unit-roster.md#upgrades)), so potions, stat boosters and trinkets must be strong
  enough that stowing a weapon is an intentional choice, reinforced by a trait such as Sidearm.
- **Equipment is much better than trinkets.** Equipment is build-defining; a trinket is a small
  edge that competes with a consumable for the Pouch slot.
- **Rarities come from `Godot_FE`**, item by item, and every rarity has **one price per kind**.
- **Healing is scarce.** Potions are reusable but heal little and only once or twice per map;
  **Guard Tonics** give Block instead. Block is the everyday defence, healing the precious one.
- **Ingredients** can be eaten (a small heal and growth) or cooked at a Camp Feast for a bigger,
  army-wide gain.
- `Godot_FE`'s 27 "equipment" items are split by what they are: wearable gear (cloaks, robes,
  bands, boots, weights) becomes Equipment, small charms (rings, coins, dice, tokens) become Pouch
  trinkets. Their effects are reduced for balance.
- Simple (basic) weapons carry no Block. Named weapons may.

## Rarity and prices

Items share the rarities in [game-vision.md](game-vision.md#weapons-and-equipment): **Basic**,
**Common**, **Uncommon**, **Rare**, **Legendary**, plus **Unique**.

- **Ported from `Godot_FE`:** Standard → Basic, Common → Common, Uncommon → Uncommon, Rare and
  Mythical → Rare, Legendary → Legendary, Unique → Unique. Items with no `Godot_FE` basis (quivers,
  coatings, Guard Tonics) are assigned in their tables.
- **Unique** items come only from events or another unique source. They are never in shops, chests,
  combat rewards or Treasure, and never on the unlock track.
- **Legendary** items are never sold; they appear only as the rare Large-chest find
  ([weapons.md](weapons.md#rarity)).

**One price per rarity per kind** (first pass):

| Kind | Common | Uncommon | Rare |
|------|--------|----------|------|
| Weapon or staff | 40 | 60 | 200 |
| Equipment | 60 | 100 | 200 |
| Trinket | 30 | 50 | 80 |
| Consumable or ingredient | 25 | 50 | 100 |

Basic, Legendary and Unique items are never sold. For scrapping, Legendary and Unique items count
at their kind's Rare price. Runes cost a flat 30; heirlooms have their own prices
([heirlooms.md](heirlooms.md#tiers-and-sources)).

## Budgets

Items use the prefix point scale from [unit-roster.md](unit-roster.md#prefixes): 1 point = 1 Might,
Speed, Defense or Resistance = 2 HP = 10 Hit = 10 crit chance = 10 avoid.

| Kind | Common budget |
|------|---------------|
| Trinket | About 1 point, or one small effect |
| Equipment | About 3 points, or 2 points plus an effect |

Each tier above Common adds 1 point (Uncommon +1, Rare +2). Basic gear is starting kit only.
Legendary items have no budget: they are meant to be close to unbalanced. Unique items are budgeted
like Rare. Movement, Stance and Parry are premium: worth more than one point each, so they appear
alone or with a cost.

## Equipment

`Godot_FE`'s wearable items, sorted into the vision's categories, plus its shield weapons
converted to shield Equipment. Quivers and coatings are new (no `Godot_FE` basis).

**Weights.** Equipment weight adds to the weapon's in the Attack Speed formula, so heavy gear costs
Speed once it passes the unit's Constitution. Most pieces weigh 0–2; heavy armor and shields more.
`Godot_FE` equipment had no weight; these are first-pass values.

| Category | Item | Rarity | `Godot_FE` effect | New effect | Weight |
|----------|------|--------|-------------------|------------|--------|
| Cloak | Vitality Cloak | Common | +5 HP | +4 HP; Phase Start: heal 1 | 1 |
| Cloak | Enshrouding Sash | Uncommon | +20 avoid, −1 DEF | +20 avoid, +1 SPD, −1 DEF | 0 |
| Cloak | Fancy Cloak | Rare | +12 HP | +6 HP | 1 |
| Armor | Magi Robes | Uncommon | +2 Magic | +2 MGT, +1 RES | 2 |
| Armor | Tungsten Ooze | Rare | +4 DEF, −1 MOV, counts as Armored | +4 DEF, −1 MOV, gains the Armored tag | 5 |
| Band | Old Soldier's Band | Common | +1 Str, +1 Skl, −2 Lck | +1 MGT, +1 DEF, +10 Hit | 1 |
| Band | Power Band | Uncommon | +2 damage | +2 damage | 1 |
| Band | Training Weights | Uncommon | −2 SPD; growths +35% Str and Mag, +10% HP, −10% SPD | −2 SPD, and Speed can't grow while worn; every level-up: +1 MGT guaranteed | 0 (its Speed cost is the weight) |
| Band | Sunshard Band | Rare (`Godot_FE` Mythical) | +10 HP; heals 20% at turn end | +4 HP; Phase End: heal 10% HP | 1 |
| Band | Quick Soles | Rare (`Godot_FE` Mythical) | +1 MOV | +1 MOV | 0 |
| Quiver | Simple Quiver | Common (new) | — | Hit dealt at range 2 or more: +1 damage | 1 |
| Quiver | Short Quiver | Uncommon (new) | — | This unit's bows reach 1–2 instead of 2–3, so it can strike and counter at close range | 1 |
| Coating | Simple Coating | Common (new) | — | +2 damage against Exposed foes | 0 |
| Coating | Spirit Coating | Uncommon (new) | — | This unit's attacks deal Magic damage, mitigated by Resistance instead of Defense | 0 |

**Shields.** `Godot_FE`'s 9 shield *weapons* become shield Equipment: they lose their damage and
durability, keep their defensive identity, and gain the Stance and Block the vision gives shields.
Their weights are halved from `Godot_FE` because they now stack with a weapon's weight instead of
replacing it.

| Shield | Rarity | `Godot_FE` (as a weapon) | New effect | Weight (`Godot_FE`) |
|--------|--------|--------------------------|------------|---------------------|
| Iron Shield | Common | +2 DEF, unbreakable | +2 DEF; Before Combat: gain 1 Block | 4 (8) |
| Iron Greatshield | Common | +3 DEF | +2 DEF, +1 Stance | 6 (12) |
| Buckler | Uncommon | +2 SPD, +2 DEF, +2 RES | +1 DEF, +1 RES; Before Combat: gain 1 Block | 4 (8) |
| Steel Shield | Uncommon | +4 DEF | +3 DEF; Before Combat: gain 1 Block | 5 (10) |
| Steel Greatshield | Uncommon | +6 DEF | +3 DEF, +1 Stance | 9 (18) |
| Knight Shield | Rare | +3 SPD, +3 DEF, +3 RES | +2 DEF, +2 RES; Before Combat: gain 1 Block | 7 (14) |
| Silver Greatshield | Rare | +7 DEF, +2 RES | +4 DEF, +1 RES, +1 Stance | 8 (16) |
| Silver Shield | Rare | +5 DEF, +1 RES | +4 DEF; Before Combat: gain 2 Block | 10 (20) |
| Eye Shield | Legendary | +10 HP, −3 SPD, +5 DEF, +3 RES; foes can attack only once | +4 HP, −3 SPD, +4 DEF, +2 RES, +1 Parry | 12 (25) |

The Eye Shield's "foes can attack only once" becomes Parry, its direct equivalent in the new rules.
It is the Eye Greatshield of weapons.md and meta-progression.md.

## Trinkets

`Godot_FE`'s small charms, now Pouch items. A unit carrying one has no room for a consumable.

| Trinket | Rarity | `Godot_FE` effect | New effect |
|---------|--------|-------------------|------------|
| Lucky Coin | Common | +8 crit | +10 crit |
| Mystifying Incense | Common | +8 avoid | +5 avoid |
| Old Pendant | Common | +1 RES | +1 RES |
| Traveler's Ring | Common | +1 SPD, +1 Lck, −1 DEF | +2 SPD, −1 DEF |
| Scholar's Optics | Common | −1 Str, +1 Mag | +10 Hit |
| Family Ring | Common | +4% all growths (+8% HP) | This unit earns +25% XP (about one extra level a run) |
| Band of Fortune | Uncommon | +10 crit, +1 Skl, +2 Lck | +5 crit, +5 Hit |
| Knight's Token | Uncommon | +2 HP, +2 Str, −3 SPD, +2 DEF | +1 MGT, +1 DEF, −1 SPD |
| Loaded Die | Rare | +40 crit, −1 CritX | +30 crit, −1 CritX |
| Null Sigil | Rare | Cannot be crit | +1 Stance |
| Jester Mask | Rare (`Godot_FE` Mythical) | Crits ignore the target's Defense | Crits ignore the target's Defense |
| Royal Crest | Rare (`Godot_FE` Mythical) | +15% all growths | Every level-up gains at least 3 stats |
| Ring of Favor | Legendary | +12 HP, +2 Str, Mag, DEF, RES, +1 Skl, SPD, +2 CON | +2 HP, +1 DEF, +1 RES |
| Oak Wood Charm | Unique (Whispering Oak event) | +10 avoid | +10 avoid |
| Cleansed Goblet | Unique (Dark Goblet event) | +20% healing received, +4 Lck | +20% healing received |
| Resonant Ore | Unique (Cavern of Echoing Steel event) | −2 SPD; +10% all growths | −2 SPD; every level-up: +1 to a random stat other than Speed |
| Heavy Brick | Unique (no source yet) | +2 CON; heals 1 at turn end | +2 CON |

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
- **Ring of Favor** is Legendary in `Godot_FE` but its converted effect is small; it needs a
  Legendary-sized rework.

## Consumables

Pouch items. Using one is the unit's action for the turn, on itself or on an adjacent ally (there
is no trading in combat, so this is how a potion reaches a teammate).

**Healing and Block.** HP carries over between combats, so healing is kept scarce: potions are
**reusable but limited per map** (their uses refresh at the start of every combat) and heal little.
Block, which resets every combat anyway, carries more of the defensive load through Guard Tonics.

| Consumable | Rarity | Effect | Uses |
|------------|--------|--------|------|
| Potion | Common | Heal 8 HP | 1 per map |
| Large Potion | Common | Heal 8 HP | 2 per map |
| Potion+ | Uncommon | Heal 12 HP | 1 per map |
| Large Potion+ | Uncommon | Heal 12 HP | 2 per map |
| Elixir | Rare | Heal to full | 1, then it's used up |
| Guard Tonic (new; replaces the Refillable Potion, whose refill every potion now has) | Common | Gain 6 Block | 1 per map |
| Guard Tonic+ (new) | Uncommon | Gain 10 Block | 1 per map |
| Emberglass Vial (Festival of Embers event) | Unique | Heal 12 HP | 2 per map |

**Lockpicks.** Uses are total, not per map.

| Lockpick | Rarity | Opens | Uses |
|----------|--------|-------|------|
| Chest Pick (`Godot_FE` Chest Key) | Common | Chests | 3 |
| Door Pick (`Godot_FE` Door Key) | Common | Doors | 1 |
| Master Pick (`Godot_FE` Skeleton Key) | Rare | Chests and doors | 5 |

These are the vision's **lockpicks**, renamed from `Godot_FE`'s keys to fit the bandit theme: any
unit can carry one, at the cost of its Pouch.

**Stat boosters** are single-use Pouch items that permanently raise one unit's stat: the holder's,
or an adjacent ally's. `Godot_FE` had 35 stat boosters, five per stat: two raised a stat
permanently (these) and three raised a growth (now [ingredients](#ingredients)).

| Stat | Stat boosters (all Rare, `Godot_FE` Rare or Mythical) |
|------|-------------------------------------------------------|
| HP | Vermillion Tonic +3, Godseed Oil +7 |
| Might (old Strength) | Bull's Draught +1 (`Godot_FE` Power Rune), Giant's Brew +2 |
| Might (old Magic) | Spirit Ink +1, Soul Dust +2 |
| Speed | Tempo Tonic +1, Wyvern Wingdust +2 |
| Defense | Infused Obsidian +1, Stonedragon Tail +2 |
| Resistance | Warding Worm +1, Ancient Anchor +2 |
| Hit (old Skill) | Adept Anchovy +5 Hit, Martial Scroll +10 Hit |
| All (Legendary) | Boost Bread: +1 Might, Speed, Defense and Resistance |

- The old Magic boosters become Might boosters too; both lines stay as flavor variants.
- Skill is cut, so Skill boosters give permanent Hit, at 5 Hit per old Skill point.
- Boost Bread's Skill, Luck and second Might point are dropped.
- `Godot_FE`'s Power Rune is renamed **Bull's Draught**: "rune" now names the run-wide ability kind.

## Ingredients

The old growth boosters. They are consumables with two uses for one item:

- **Eat it** (the unit's action, on itself or an adjacent ally, from the Pouch): a small heal and a
  permanent growth bonus for that one unit. Single use.
- **Cook it** at a Camp **Feast** (from the Pouch or the convoy): every living unit in the army gets
  a guaranteed gain on its **next level-up**, shown on the unit card until it lands. Hit
  ingredients apply at once, since Hit has no growth. Units recruited after the Feast don't get it.
  The Feast also heals every unit 35% of its HP, and cooks **one** ingredient.

Cooking is the stronger, army-wide use; eating is a quick, personal one.

| Stat | Ingredient | Rarity | Eaten | Cooked (every unit's next level-up) |
|------|------------|--------|-------|-------------------------------------|
| HP | Heartbeet | Common | Heal 5, +5% HP growth | +2 HP |
| HP | Titan Trout | Uncommon | Heal 10, +10% HP growth | +4 HP |
| HP | Century Cheese | Rare | Heal 10, +10% HP growth | +4 HP |
| Might | Brutvine Sap, Runewart | Common | Heal 5, +5% MGT growth | +1 MGT |
| Might | Wisdom Wine | Uncommon | Heal 5, +5% MGT growth | +1 MGT |
| Might | Brawn Prawn | Uncommon | Heal 10, +10% MGT growth | +2 MGT |
| Might | Brutvine Heartroot, Moonclam Pearl | Rare | Heal 10, +10% MGT growth | +2 MGT |
| Speed | Rushraddish | Common | Heal 5, +5% SPD growth | +1 SPD |
| Speed | Swift Shellfish | Uncommon | Heal 10, +10% SPD growth | +2 SPD |
| Speed | Hastehawk Feather | Rare | Heal 10, +10% SPD growth | +2 SPD |
| Defense | Stonebark Blossom | Common | Heal 5, +5% DEF growth | +1 DEF |
| Defense | Bastion Crab | Uncommon | Heal 5, +5% DEF growth | +1 DEF |
| Defense | Stonebark Essence | Rare | Heal 10, +10% DEF growth | +2 DEF |
| Resistance | Cave Carrot | Common | Heal 5, +5% RES growth | +1 RES |
| Resistance | Sanctuary Shell | Uncommon | Heal 5, +5% RES growth | +1 RES |
| Resistance | Sanctree Branch | Rare | Heal 10, +10% RES growth | +2 RES |
| Hit | Hawkweed | Common | Heal 5, +3 Hit | +5 Hit (at once) |
| Hit | Precise Pepper | Uncommon | Heal 5, +3 Hit | +5 Hit (at once) |
| Hit | Finesse Filet | Rare | Heal 10, +5 Hit | +10 Hit (at once) |

Small ingredients (`Godot_FE` 3–5%) eat for heal 5 and +5%; large ones (`Godot_FE` 7–20%) for
heal 10 and +10%. Rarities are `Godot_FE`'s, so some small ingredients are Uncommon and some large
ones Rare.

- **Sources:** the combat item pick and the Armory's consumable slots (rolled by rarity, like any
  consumable), and food shelves (a searchable).
- **Storage:** an ingredient sits in a unit's Pouch (to eat in combat) or in the convoy (to cook
  later), one slot each.
- **Co-op:** each player makes their own Camp choice. A Feast's heal reaches every player's units,
  and heals from several Feasts at one Camp stack. Its ingredient buffs only the cook's own army;
  a future heirloom could make an ingredient feed the whole team (tagged unique, since it affects
  other players' units).
- **Balance:** for a 5-unit army a cooked small ingredient is worth about 5 points and a large one
  about 10, against Train's roughly 4–5 points plus a "+" trait on one unit: breadth against depth.
  Large ingredients are the ones to watch in playtesting. An eaten ingredient's growth bonus is small
  over a 4–6 level run; its heal is the immediate payoff.

**Save impact:** a pending Feast gain and an eaten growth bonus are unit state; they are saved with
the unit in the player's roster section of the campaign block. A pending Feast gain is cleared when
its level-up lands.

## Runes

Single-use abilities with their own 3-slot inventory, used on the player turn outside the action
economy, targeting anything anywhere on the map (rules in
[game-vision.md](game-vision.md#run-wide-resources)). First-pass pool, decided October 23, 2026:

| Rune | Effect |
|------|--------|
| Mend | A unit heals 10 HP |
| Aegis | A unit gains 6 Block |
| Shatter | An enemy loses 2 Stance |
| Clarity | A unit's next attack this phase gains +20 Hit and +2 damage |
| Haste | A unit that hasn't acted this turn gains +2 Movement until Phase End |
| Spark | A powder keg anywhere on the map explodes |
| Recall | Two of your units swap positions |

Runes cost 30 gold at the Guildhall; the Ghastly Library event and book shelves give a random one.

## Scrapping

There is no selling. Any item a player doesn't want is **scrapped** for gold: a single decision, made
where the player already is, so shopping stays short and the convoy never fills with junk.

- **Scrap value:** 20% of the item's price (Legendary and Unique items count at their kind's Rare
  price), Terraria's sell rate. First pass; tune in playtesting so scrapping stays a release valve,
  not a source of income.
- **At pickup:** when loot arrives and the convoy is full, keep it by scrapping something in the
  convoy, or scrap the new item.
- **At the Armory:** buying an item onto a unit either trades in the item it replaces (its scrap
  value comes off the price) or sends it to the convoy.
- **Anytime:** army management can scrap any convoy item in one step, showing the gold it gives.
- **Treasure items** (`Godot_FE`'s Gold Coins, Gold Ring, Spices, Vintage Wine) existed to be sold;
  they turn into their full gold value the moment they are picked up and never take a convoy slot.

## Modified items

An event can change one item (Dark Goblet's *Infuse*, Cavern of Echoing Steel's *Forge
Resonance*, the Clockwork Hermit's *Upgrade Gear*). A modified item is shown as **"Infused <name>"**
with a marker icon, and its card lists what changed. Its price and scrap value change with its
deltas; the formula belongs to the items implementation plan.

## Open questions

- **Support weapons beyond staves** (whips, instruments, banners): stubs until a unit uses them.
- **Shield and armor weights against Constitution:** most MVP units have Constitution 5–14, so a
  shield plus a weapon often passes it. Check in playtesting that shields stay worth carrying.
- **Uniques:** the vision's "uniques" equipment category has no items yet; Heavy Brick is Unique
  with no source.
- **Ring of Favor:** needs a Legendary-sized effect.
- **Rebalance:** items carried `Godot_FE` rarities over unchanged; some effects may now sit above or
  below their rarity's budget.
