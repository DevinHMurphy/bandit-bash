# Heirlooms

The heirloom pool for Bandit Bash: army-wide passives in one shared collection, with no per-unit
assignment. It expands the heirloom bullet under
[Run-wide resources](game-vision.md#run-wide-resources), which wins where the two differ. Effects
are written in the [trigger vocabulary](effect-triggers.md) and follow the
[effects system](effects-system.md).

**Status:** first pass, October 23, 2026. Every heirloom and number is a starting point to tune in
playtesting.

## The short version

- **Four tiers:** Common, Uncommon and Rare make up the main pool; a small **Shop** tier of economy
  heirlooms is sold only at the Armory.
- **No cap.** A typical run gains about 7 heirlooms; a path through every extra key combat about 12.
- **Offers never duplicate** an heirloom the player owns (effects-system.md). Copies gained anyway
  stack.
- **Starting heirlooms** (run start only), **Commander Heirlooms** (one per commander,
  [unit-roster.md](unit-roster.md#commander)) and **curses** (negative heirlooms,
  [events.md](events.md#curses)) sit outside this pool.
- Heirlooms use the Your Unit scope or wider, never This unit. One that reaches other players' units
  is tagged **unique** (one owner per co-op campaign).

## Tiers and sources

| Tier | Armory price | Treasure chest |
|------|--------------|----------------|
| Common | 150 | Small (50% of chests) |
| Uncommon | 200 | Medium (33%) |
| Rare | 250 | Large (17%) |
| Shop | 150 | — (sold only at the Armory) |

- **Treasure:** the chest's size is its rarity, rolled with Slay the Spire's chest-size odds above,
  so the chest shows what's inside. Half of chests also add 20–60 gold (game-vision.md). A Large
  chest has a 10% chance to hold a Legendary item instead of its heirloom
  ([weapons.md](weapons.md#rarity)).
- **Events:** the revive shrine, the Black Altar and other "rare heirloom" options draw from Rare.
- **Key combats:** one random heirloom, rolled Common 50 / Uncommon 33 / Rare 17.
- **Armory:** two heirlooms per visit: one from the pool (rolled 50 / 33 / 17) and one Shop tier.
- **Co-op only:** heirlooms marked *co-op* are offered only in co-op campaigns, since they do
  nothing in solo.

## Common (14)

| Heirloom | Kind | Effect |
|----------|------|--------|
| Grandfather's Whetstone | Profile | Your Units with a Power weapon: +2 damage |
| Dueling Manual | Profile | Your Units with a Nimble weapon: +2 Attack Speed |
| Drillmaster's Baton | Profile | Your Units with a Balance weapon: +1 damage, +1 Defense |
| Fletcher's Kit | Profile | Hit dealt by Your Unit at range 2 or more: +1 damage |
| Hammerhead Charm | Behavior | Your Units deal +3 damage against Armored units |
| Horsebane Charm | Behavior | Your Units deal +3 damage against Mounted units |
| Bloodied Banner | Behavior | Defeated an enemy, by Your Unit: that unit's next attack this combat gains +3 damage |
| Iron Rations | Behavior | First Phase Start this combat: Your Units gain 3 Block |
| Hunter's Horn | Behavior | Before Combat, while Your Unit is the initiator: +5 Hit |
| Shoving Pole | Behavior | Shoved a unit, by Your Unit: the shover gains 2 Block |
| Sapper's Fuse | Behavior | Object used, by Your Unit: that unit gains 3 Block |
| Lantern Oil | Behavior | Darkness damage taken by Your Unit: take 50% less |
| Bounty Ledger | Economy | Every combat won pays +8 gold |
| Scrapper's Tongs | Economy | Scrapping pays 40% of an item's buy price instead of 20% |

## Uncommon (10)

| Heirloom | Kind | Effect |
|----------|------|--------|
| Executioner's Brand | Behavior | Hit dealt by Your Unit while the target is Exposed: +3 damage |
| Breaker's Maul | Behavior | Every 5th Hit dealt by Your Unit this combat: the target loses 1 extra Stance |
| War Ledger | Behavior | Every 10th Attack made by Your Unit this campaign: that attack deals double damage |
| Overflowing Cup | Behavior | Healed, Your Unit: healing beyond max HP becomes Block |
| Tactical Map | Behavior | First Phase Start this combat: Your Units gain +1 Movement until Phase End |
| Grave Candle | Behavior | Defeated, Your Unit: every other one of Your Units gains 4 Block |
| Warlord's Spoils | Behavior | Defeated an enemy, by Your Unit: that unit heals 3 HP |
| Burglar's Roll | Economy | Once per combat, Your Unit can open a chest or door without a lockpick (still its action) |
| Veteran's Medal | Economy | Your Units earn +20% shared XP from combat |
| Brothers in Arms | Behavior | *Unique, co-op.* Phase Start: Any Ally Unit adjacent to a unit of another player gains 2 Block |

## Rare (7)

| Heirloom | Kind | Effect |
|----------|------|--------|
| Muster Roll | Army | +1 max army size (never past the ceiling of 8) |
| Warhorse Lineage | Behavior | Always: Your Units have +1 Movement |
| Ancestral Mail | Behavior | Always: Your Units have +1 Stance |
| Bloodhound's Collar | Behavior | Defeated an enemy, by Your Unit: that unit may use its remaining movement |
| Champion's Belt | Behavior | Defeated an enemy, by Your Unit: that unit deals +1 damage for the rest of this combat (stacks) |
| Commander's Standard | Behavior | Phase Start: Your Units within 2 tiles of your commander gain 2 Block |
| Gilded Purse | Economy | Grade bonuses pay +50% instead of +25% |

## Shop (4)

| Heirloom | Effect |
|----------|--------|
| Merchant's Ledger | The Armory offers one more item |
| Guild Charter | The Guildhall offers one more recruit |
| Membership Seal | Armory and Guildhall prices −20% |
| Tinker's Token | The first prefix re-roll at each Guildhall is free |

## Starting heirlooms

Offered only at run start, after the faction and commander. The player picks **1 of 3**, drawn
from this pool of 7 by the run seed. They add variety without forcing a build.

| Starting heirloom | Effect |
|-------------------|--------|
| Abundance | +1 max army size (Mercenary: 4 → 5), and recruit 1 of 2 offered units with no prefix |
| Ancestral Weapon | Pick 1 of 3 Rare weapons. Each offered weapon is usable by at least one unit in the army, and the three are of different weapon types where the army allows |
| Tactician's Manual | In every exchange involving Your Unit, the weapon profile triangle is doubled in both directions: Advantage +30 Hit and +2 × WPTAE damage, Disadvantage the reverse |
| War Chest | +100 gold |
| Veteran Company | Upgrade one starting unit (not the commander) for free, as a Camp's Train |
| Family Relic | Gain a random Uncommon heirloom |
| Mercenary Contract | Recruit 1 of 3 units with a guaranteed +1 or +2 prefix. The army starts full, so the recruit replaces a starting unit (not the commander) |

## Design notes

- **Proactive by default.** Most behavior heirlooms pay off for attacking, initiating, defeating
  enemies, breaking Stance or moving, never for standing still (see the
  [design pillars](game-vision.md#design-pillars)).
- **Tags get answers.** Hammerhead and Horsebane Charm give the Armored and Mounted tags a use
  until effective weapons exist.
- **Damage over Might.** Stacking bonuses (Champion's Belt) add flat damage, not Might, so the
  forecast shows exactly what each stack added, as with Fighter+.
- **No extra lives.** No heirloom revives a unit or prevents a death; permadeath stays absolute.
- **No darkness rewards yet.** Lantern Oil answers the darkness; heirlooms that reward standing in
  it wait until its damage model settles ([the-darkness.md](the-darkness.md)).
- **Commander's Standard** pulls the army toward the commander, whose Vanguard trait wants it in
  front, so the army moves forward together.

## Save impact

Owned heirlooms and their campaign-lane counters (War Ledger) are per-player run state, saved with
the player's army in the `CAMPAIGN` block (effects-system.md). Section key and version are chosen
when the system is built.

## Open questions

- **Balance:** every value above is untested.
