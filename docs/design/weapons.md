# Weapons

Every weapon in the Bandit Bash MVP, by rarity. The weapon rules (types, profiles, the Simple
weapons, damage and Hit formulas) are in
[game-vision.md](game-vision.md#weapons-and-equipment), which wins where the two differ. Effects are
written in the [trigger vocabulary](effect-triggers.md).

**Status:** first pass, October 23, 2026, converted from `Godot_FE/resources/definitions/items/weapons/`.
Every number is a starting point to tune in playtesting.

## The short version

- **Five rarities**, shared with all items: Basic, Common, Uncommon, Rare and Legendary.
- **Weight is the price of power.** Higher tiers hit harder and weigh more; they never lose Hit
  below their type's Simple weapon, because accuracy comes only from the weapon and leveling never
  raises it.
- **Scaling:** every MVP weapon adds Might one-for-one (scaling modifier 1).
- **Every bow is effective against Fliers** (×3 weapon damage), as in `Godot_FE`.
- **No durability**, except heal staves (see [Staves](#staves)).
- **Fresh names.** `Godot_FE`'s Iron / Steel / Silver / Killer / Valor ladders are renamed; the
  rarity colour tells the player a weapon's tier, so the name can carry flavour.

## Rarity

| Rarity | Weapons | Armory price | Where it comes from |
|--------|---------|--------------|---------------------|
| Basic | The Simple weapons and Shelter | — | Starting gear and recruits only; never loot or stock |
| Common | 10 (Minor Heal included) | 40 | Armory, rewards, chests |
| Uncommon | 16 | 60 | Armory, rewards, chests |
| Rare | 17 | 150 (250 for `Godot_FE`'s Mythical weapons) | Armory, events, Ancestral Weapon, rare rewards |
| Legendary | 9 (plus the Eye Greatshield) | Never sold | A Large Treasure chest has a 10% chance to hold a Legendary item, one a unit in the army can use, instead of its heirloom: about 3% of runs |

`Godot_FE`'s seven rarities map as Standard → Basic, Common → Common, Uncommon → Uncommon, Rare and
Mythical → Rare, Legendary → Legendary. Its Unique tier (commander signature weapons) is not ported.

Legendary items are deliberately close to unbalanced, like Balatro's legendary jokers: finding one
should change a run.

## Converting from Godot_FE

The vision already reshaped each Simple weapon (e.g. Simple Sword 80 Hit, weight 8, against
`Godot_FE`'s Iron Sword 100 Hit, weight 5). Every other weapon keeps its distance from `Godot_FE`'s
Iron weapon of the same type:

- **Damage, crit, CritX and weight:** `Godot_FE` value + (vision Simple − `Godot_FE` Iron) for that
  type. Crit and weight never go below 0.
- **Hit:** the type's Simple Hit, plus however much the `Godot_FE` weapon out-hit its Iron weapon
  (never less than the Simple Hit).
- **Range:** `Godot_FE`'s, except bows with range 2 become 2–3, like the Simple Bow.
- **Skill and Luck bonuses:** Skill becomes Hit at 5 Hit per point ([items.md](items.md)); Luck is
  dropped. Strength and Magic bonuses become Might.
- **Durability** is dropped.

| Type | Damage | Hit (Simple) | Crit | CritX | Weight |
|------|--------|--------------|------|-------|--------|
| Sword | +0 | 80 | +0 | +0 | +3 |
| Axe | +2 | 65 | +0 | +0 | +5 |
| Lance | +0 | 80 | +0 | +0 | +4 |
| Bow | +0 | 100 | +0 | +0 | +0 |
| Dagger | −1 | 100 | −10 | +1 | +0 |
| Gauntlets | +0 | 100 | +0 | +0 | −2 |
| Anima | +0 | 80 | +0 | +0 | +0 |
| Holy | +0 | 100 | −5 | +0 | +0 |
| Dark | +0 | 80 | +0 | +0 | +0 |

Profiles follow each weapon's flavour (game-vision.md); daggers are spread to fill triangle gaps.

## Basic

The nine Simple weapons and the Shelter staff, as listed in
[game-vision.md](game-vision.md#weapons-and-equipment). The Simple Bow is effective against
Fliers, like every bow.

## Staves

Staves never attack. Using one is the unit's action, on an ally in range.

| Staff | Rarity | Kind | Effect | Range | Uses | Weight |
|-------|--------|------|--------|-------|------|--------|
| Shelter | Basic | Block | Target ally gains 3 + Might Block | 1 | Unlimited | 0 |
| Minor Heal (`Godot_FE` Minor Heal) | Common | Heal | Target ally heals 5 + Might HP | 1 | 3 per map | 0 |

- **Block staves** are the everyday support tool, so they have unlimited uses. Block given on the
  player phase lasts until that unit's side refreshes at its next Phase Start.
- **Heal staves** are limited because HP carries over between combats; uses refresh at the start of
  every combat. `Godot_FE`'s Minor Heal was unbreakable; limiting it stops stalling the last enemy to
  heal everyone for free.

## Common

| Weapon (`Godot_FE`) | Type | Profile | Dmg | AtkX | Range | Hit | Crit | CritX | Weight | Effect |
|---------------------|------|---------|-----|------|-------|-----|------|-------|--------|--------|
| Gladius (Short Sword) | Sword | Nimble | 3 | 1 | 1 | 100 | 15 | 3 | 8 | — |
| Woodsman's Axe (Slim Axe) | Axe | Nimble | 8 | 1 | 1 | 80 | 5 | 3 | 12 | — |
| Throwing Hatchet (Hatchet) | Axe | Power | 6 | 1 | 1–2 | 70 | 0 | 3 | 10 | — |
| Ash Spear (Slim Lance) | Lance | Nimble | 4 | 1 | 1 | 85 | 0 | 3 | 8 | — |
| Pilum | Lance | Balance | 5 | 1 | 1–2 | 80 | 0 | 3 | 9 | — |
| Hunter's Bow (Reinforced Bow) | Bow | None | 9 | 1 | 2–3 | 100 | 0 | 3 | 5 | Effective vs Flier |
| Butcher's Knife (Knife) | Dagger | Power | 6 | 1 | 1 | 100 | 0 | 5 | 9 | — |
| Brass Knuckles | Gauntlets | None | 1 | 3 | 1 | 120 | 15 | 3 | 6 | — |
| Earthsplitter (Earth Split) | Anima | Balance | 13 | 1 | 1–2 | 90 | 0 | 3 | 12 | — |

## Uncommon

| Weapon (`Godot_FE`) | Type | Profile | Dmg | AtkX | Range | Hit | Crit | CritX | Weight | Effect |
|---------------------|------|---------|-----|------|-------|-----|------|-------|--------|--------|
| Arming Sword (Steel Sword) | Sword | Nimble | 8 | 1 | 1 | 80 | 0 | 3 | 13 | — |
| Rapier | Sword | Nimble | 6 | 1 | 1 | 80 | 10 | 3 | 8 | Effective vs Armored |
| Sabre | Sword | Balance | 9 | 1 | 1 | 80 | 0 | 3 | 14 | Effective vs Mounted |
| Bearded Axe (Steel Axe) | Axe | Power | 15 | 1 | 1 | 65 | 0 | 3 | 20 | — |
| Halberd | Axe | Balance | 12 | 1 | 1 | 65 | 0 | 3 | 20 | Effective vs Mounted |
| Hand Axe | Axe | Power | 9 | 1 | 1–2 | 65 | 0 | 3 | 17 | — |
| Boar Spear (Steel Lance) | Lance | Balance | 11 | 1 | 1 | 80 | 0 | 3 | 17 | — |
| Heavy Lance | Lance | Power | 11 | 1 | 1 | 80 | 0 | 3 | 18 | Effective vs Armored |
| Recurve Bow (Steel Bow) | Bow | None | 12 | 1 | 2–3 | 100 | 0 | 3 | 10 | Effective vs Flier |
| Short Bow | Bow | None | 5 | 1 | 1–2 | 100 | 15 | 3.5 | 3 | Effective vs Flier |
| Rondel (Steel Dagger) | Dagger | Balance | 5 | 1 | 1–2 | 100 | 0 | 5 | 5 | — |
| Armorbreaker | Dagger | Power | 4 | 1 | 1–2 | 100 | 0 | 5 | 8 | Effective vs Armored |
| Cestus (Steel Fist) | Gauntlets | None | 4 | 2 | 1 | 100 | 0 | 3 | 4 | — |
| Wind | Anima | Balance | 1 | 2 | 1–2 | 90 | 0 | 3 | 3 | Effective vs Flier |
| Mandate | Holy | Nimble | 1 | 2 | 1–2 | 100 | 5 | 5 | 4 | — |
| Fiend Fire | Dark | Power | 8 | 1 | 1–2 | 80 | 0 | 3 | 7 | — |

## Rare

`Godot_FE`'s Mythical weapons are marked **M** and cost 250; the rest cost 150.

| Weapon (`Godot_FE`) | Type | Profile | Dmg | AtkX | Range | Hit | Crit | CritX | Weight | Effect |
|---------------------|------|---------|-----|------|-------|-----|------|-------|--------|--------|
| Starforged Blade (Silver Sword) | Sword | Nimble | 13 | 1 | 1 | 80 | 0 | 3 | 11 | — |
| Heartseeker (Killer Sword) | Sword | Nimble | 8 | 1 | 1 | 80 | 30 | 3 | 8 | — |
| Twin Fang (Valor Blade) **M** | Sword | Nimble | 9 | 2 | 1 | 80 | 0 | 3 | 15 | — |
| Dark Sword **M** | Sword | Power | 12 | 1 | 1–2 | 80 | 0 | 3 | 15 | Deals Magic damage. Hit dealt: heals the attacker for half the damage it deals to HP |
| Headsman's Axe (Silver Axe) | Axe | Power | 17 | 1 | 1 | 65 | 0 | 3 | 17 | — |
| Tomahawk **M** | Axe | Power | 15 | 1 | 1–2 | 65 | 5 | 3 | 19 | — |
| Wyvern Pike (Silver Lance) | Lance | Balance | 15 | 1 | 1 | 80 | 0 | 3 | 14 | — |
| Spear **M** | Lance | Balance | 13 | 1 | 1–2 | 80 | 5 | 3 | 14 | — |
| Steppe Hornbow (Silver Bow) | Bow | None | 15 | 1 | 2–3 | 100 | 0 | 3 | 6 | Effective vs Flier |
| Dragonslayer Bow **M** | Bow | None | 18 | 1 | 3–5 | 100 | 0 | 3 | 15 | Effective vs Flier |
| Whisperknife (Silver Dagger) | Dagger | Nimble | 11 | 1 | 1–2 | 100 | 5 | 5 | 6 | — |
| Stiletto (Killer Dagger) | Dagger | Nimble | 7 | 1 | 1–2 | 100 | 30 | 5 | 9 | — |
| Kukri **M** | Dagger | Power | 1 | 1 | 1–2 | 105 | 25 | 6 | 9 | Crit dealt: that hit skips Mitigation |
| Ogre Knuckles (Silver Fist) | Gauntlets | None | 6 | 2 | 1 | 100 | 5 | 3 | 4 | — |
| Torrent | Anima | Balance | 10 | 1 | 1–3 | 90 | 30 | 3 | 10 | — |
| Lumen **M** | Holy | Nimble | 15 | 1 | 1–2 | 100 | 25 | 3 | 14 | — |
| Life Tap | Dark | Power | 10 | 1 | 1–2 | 80 | 0 | 3 | 14 | Hit dealt: heals the attacker for the damage it deals to HP |

Life Tap's `Godot_FE` data is ambiguous: its `specials` list says lifesteal (`VAMPYRIC`), but its
attached effect (value 6, weight 100) reads as "can only attack once" in the other effect enum. It
is ported as full lifesteal, matching its name and its `VAMPYRIC` flag.

## Legendary

Nearly unbalanced on purpose. Never sold, never a reward; see [Rarity](#rarity).

| Weapon | Type | Profile | Dmg | AtkX | Range | Hit | Crit | CritX | Weight | Effect |
|--------|------|---------|-----|------|-------|-----|------|-------|--------|--------|
| Colossus | Axe | Power | 27 | 1 | 1 | 65 | 20 | 3 | 25 | Equipped: +20 HP, +5 DEF, +5 CON |
| Zweihander | Sword | Power | 22 | 1 | 1 | 100 | 20 | 3 | 16 | Equipped: +4 MGT, +2 SPD (its old +4 Skill is the +20 Hit) |
| Titan's Will | Lance | Balance | 12 | 1 | 1–2 | 100 | 5 | 3 | 24 | Equipped: +17 HP, +5 MGT, +9 SPD, +4 DEF, +14 RES |
| Ebonflight | Bow | None | 12 | 2 | 2–3 | 100 | 30 | 3 | 10 | Equipped: +5 SPD. Effective vs Flier |
| Sanguis | Dagger | Nimble | 9 | 2 | 1–2 | 105 | 40 | 6 | 7 | — |
| All-Seeing Hands | Gauntlets | None | 4 | 5 | 1 | 100 | 0 | 3 | 4 | — |
| Mage Blade | Anima | Balance | 16 | 2 | 1 | 80 | 15 | 3 | 20 | — |
| Deliverance | Holy | Nimble | 12 | 1 | 1–2 | 115 | 45 | 5 | 14 | — |
| Abyss Typhoon | Dark | Power | 8 | 3 | 1–2 | 85 | 25 | 3 | 14 | Equipped: +5 MGT |

The Eye Greatshield ([items.md](items.md#equipment)) is the Legendary equipment piece.

## Not ported

Left for later, with their themes free to reuse: the Sword Reaver, Tri-Edge, Tri-Axe and Tri-Pike
(they reversed or tripled the old weapon-type triangle, which no longer exists), Sword Breaker and
Shotel (effective against weapon types), Devil Knuckles (Luck-based backfire), Soul Rip and
Annihilate (defence-negating and no-counter specials), Bolting (siege range), the remaining
Killer and Valor weapons, Great Sword, Great Axe, Great Lance, Great Bow, Long Bow, Heavy Knife,
Kunai, Tanto, Spirit Dagger, Jousting Lance, Warpick, Javelin (now an enemy weapon), Evil Eye,
Dark Pulse, Ray, Holy Fire, Enchanted Bow and the monster claws. Commander signature weapons
(Dawnbreak and the other four) are not ported.

## Open questions

- **More staves:** stronger Block and heal staves for higher rarities.
- **Weight against Constitution:** Uncommon axes and lances weigh 17–20 against Constitution 8–14,
  so their wielders lose a lot of Attack Speed. That is the intended trade-off, but check the Fighter
  and Lancer in playtesting.
- **Balance:** none of these values has been tested.
