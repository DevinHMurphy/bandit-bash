# Unit Roster

The unit types in Bandit Bash, their traits, and how individual units are generated. It expands
the Army and Units sections of [game-vision.md](game-vision.md), which wins where the two differ.

**Status:** MVP roster chosen October 15, 2026. Stats are carried over from `Godot_FE/` as a
starting point and have not been rebalanced for the new combat rules.

## The short version

- The MVP has **13 unit types**, one per weapon role plus one of each movement type. Units have no
  tiers: each is **unupgraded or upgraded**, like a Slay the Spire card (see game-vision.md).
  "Tier" in this file only ever means a prefix's quality tier. All 13 upgrades are written.
- Every unit type has a **trait**: effect text that gives the type its identity (see
  [effects-system.md](effects-system.md)). Bulky, shield-style roles get their bulk from traits,
  not from a shield weapon type. All 13 MVP traits and Stance values are written.
- Each recruited unit rolls a **prefix**, Terraria-style ("Sturdy Lancer", "Frail Archer"), that
  shifts its stat spread. The prefix's tier tells the player at a glance whether a unit is good.
- Commanders keep fixed stats and names across runs (game-vision.md) and are not generated.

## MVP roster

Old stats from `Godot_FE/resources/definitions/unit_types/units/<key>/`, mapped to the new stat
list ([game-vision.md](game-vision.md#units)). Might (MGT) is the old Strength, except for Mage,
Shaman and Suncaster, where it is the old Magic, their attack stat. Old Skill, Luck and the other
units' Magic are dropped.

| Role | Unit (`Godot_FE` key) | Weapons | Movement | Tags | Base HP/MGT/SPD/DEF/RES/MOV/CON | Growths % HP/MGT/SPD/DEF/RES |
|------|-----------------------|---------|----------|------|---------------------------------|------------------------------|
| Sword | Sellsword (`sellsword`) | Sword | Default | — | 22/5/7/4/1/5/11 | 110/42/34/18/20 |
| Axe | Fighter (`fighter`) | Axe | Default | — | 22/6/4/3/2/5/12 | 85/55/35/32/15 |
| Lance | Lancer (`lancer`) | Lance | Default | — | 19/3/6/3/2/5/8 | 85/42/55/15/17 |
| Bow | Archer (`archer`) | Bow | Default | — | 13/5/8/0/0/5/6 | 55/38/58/8/17 |
| Fist | Brawler (`brawler`) | Gauntlets | Default | — | 25/6/4/1/3/5/7 | 65/50/22/22/15 |
| Dagger | Thief (`thief`) | Dagger | Mobile | — | 14/3/9/2/1/6/6 | 65/30/65/25/20 |
| Support | Battle Medic (`field_medic`) | Dagger, staff | Mobile | — | 16/4/5/1/1/6/7 | 65/35/35/18/18 |
| Mounted | Hakkapel (`hakkapel`) | Lance, sword | Mounted | Mounted | 22/4/5/4/0/7/10 | 70/30/40/20/12 |
| Flier | Freewing (`freewing`) | Sword | Flier | Flier, Mounted | 17/3/7/2/2/7/5 | 60/40/48/9/27 |
| Armored | Lance Armor (`lance_armor`) | Lance | Heavy | Armored | 23/7/2/7/1/4/14 | 75/47/15/48/20 |
| Anima | Mage (`mage`) | Anima | Default | — | 16/3/7/1/3/5/5 | 55/45/45/8/30 |
| Dark | Shaman (`shaman`) | Dark | Default | — | 17/8/3/3/4/5/12 | 75/65/22/18/30 |
| Holy | Suncaster (`suncaster`) | Holy | Default | — | 18/1/7/1/4/5/6 | 55/37/55/10/35 |

Movement types and tags are defined under [Movement and tags](#movement-and-tags).

- Archer, Battle Medic and Hakkapel are the Mercenary starting army in game-vision.md. Battle
  Medic is the vision's name for `Godot_FE`'s Field Medic.
- The old Anima, Dark and Holy units used Nature, Dark and Light tomes.
- Not ported: `Godot_FE`'s Lancer growths are identical to Lance Skeleton's (likely a copy-paste)
  and need fresh values. The Thief's broken tag is covered under
  [Movement and tags](#movement-and-tags).

## Movement and tags

Two classifications every unit type carries, separate from its trait.

**Tags** say what a unit *is*. Weapon effectiveness (×3 weapon damage, see game-vision.md),
heirlooms and traits refer to them, e.g. "effective against Armored", "Mounted units gain +1
Movement". `Godot_FE` called these "traits" (`unitConstants.TRAITS`); they are renamed **tags**
because "trait" now means a unit type's effect text.

| Tag | Meaning | MVP units |
|-----|---------|-----------|
| Armored | Heavily armored | Lance Armor |
| Mounted | Rides a mount (horse or flying mount) | Hakkapel, Freewing, Lancer+ |
| Flier | Flies | Freewing |
| Terror | Monstrous or undead (`Godot_FE`'s skeletons and monsters) | None; enemies only |

**Movement types** say how a unit crosses terrain. Costs are carried over unchanged from
`Godot_FE/resources/definitions/terrians/` (cost per movement type; "—" means it cannot enter).
Avoid, Defense and Resistance are the terrain's bonuses to a unit standing on it; avoid now
comes only from terrain and effects, so these matter more than before.

| Terrain | Default | Heavy | Mobile | Mounted | Flier | Avoid | DEF/RES | Other |
|---------|---------|-------|--------|---------|-------|-------|---------|-------|
| Plain, Short Grass | 1 | 1 | 1 | 1 | 1 | 5 | 0/0 | |
| Road, Floor, Bridge, Broken Wall | 1 | 1 | 1 | 1 | 1 | 0 | 0/0 | |
| Stairs | 1 | 1 | 1 | 1 | 1 | 5 | 0/0 | |
| Ruins | 1 | 1 | 1 | 1 | 1 | 15 | 0/0 | |
| House | 1 | 1 | 1 | 2 | 1 | 10 | 0/0 | |
| Forest | 2 | 2 | 2 | 2 | 1 | 20 | 1/1 | |
| Thicket | 2 | 3 | 2 | 3 | 1 | 15 | 1/1 | |
| Knoll | 2 | 3 | 1 | 2 | 1 | 15 | 1/1 | |
| Wooded Knoll | 3 | 4 | 2 | 3 | 1 | 25 | 1/1 | |
| Pillar | 2 | 2 | 2 | 3 | 1 | 20 | 1/1 | |
| Camp | 2 | 2 | 3 | 3 | 1 | 15 | 1/1 | Heals 2 HP |
| Fort | 2 | 2 | 2 | 2 | 2 | 20 | 2/2 | Heals 20% HP |
| Castle Gate, Throne | 2 | 2 | 3 | 3 | 1 | 30 | 3/0 | Heals 4 HP |
| Mountain | 4 | — | 3 | — | 1 | 30 | 1/1 | |
| Peak | — | — | 4 | — | 1 | 40 | 2/2 | |
| River | — | — | 2 | — | 1 | 15 | 0/0 | |
| Ocean, Waterfall | — | — | — | — | 1 | 10 | 0/0 | |
| Wall, Cracked Wall, Cliff, Debris, Barrel | — | — | — | — | 1 | 0 | 0/0 | |
| Pit | — | — | — | — | 1 | −5 | 0/0 | |
| Door | — | — | — | — | — | 0 | 0/0 | Until opened |

In short: **Mobile** units (thieves, medics) climb mountains and peaks and ford rivers; **Mounted**
units are fast on open ground but slowed by rough terrain and stopped by mountains and rivers;
**Heavy** units are slowed most in rough terrain; **Fliers** cross everything except doors.

Bugs fixed from `Godot_FE`, not ported:

- **Wooded Knoll** blocked Default units while letting Heavy units in at cost 4. Default now costs
  3.
- **Mounted movement.** `Godot_FE` gave its cavaliers and the Hakkapel the Default movement type
  with the Mounted tag. Every ground unit with the Mounted tag uses Mounted movement.
- **Thief tag.** `Godot_FE`'s Thief carried a tag value outside the tag list, meant for lockpicking.
  There is no lockpicking tag: lockpicks are Pouch consumables any unit can carry, so a unit
  hunting for loot gives up its potion or trinket.

## Traits

A trait is effect text on a unit type, written with the [trigger vocabulary](effect-triggers.md).
It is the type's identity, separate from the random prefix on each unit. MVP traits avoid status
effects for now.

**MVP traits and Stance.** First pass; every number is a starting point to tune in playtesting.
Stance runs 1 (fragile or evasive), 2 (standard), 3 (bulky).

| Unit | Stance | Trait | Effect text | Identity |
|------|--------|-------|-------------|----------|
| Sellsword | 2 | Professional | Before Combat, while this unit has triangle Advantage: gain 3 Block | Picks good matchups |
| Fighter | 3 | Momentum | Missed: this unit's next attack this combat gains +15 Hit | Softens, but keeps, the axe's miss risk |
| Lancer | 2 | Phalanx | Unit Turn Start: gain 1 Block per adjacent ally | Holds a line with friends |
| Archer | 1 | Volley | Hit dealt while at maximum range: +2 damage | Rewards positioning |
| Brawler | 2 | Breaker | First Hit dealt this combat: the target loses 1 extra Stance | Doubles down on breaking Stance |
| Thief | 1 | Opportunist | Always: +15 crit chance | Punishes Exposed foes |
| Battle Medic | 1 | Triage | Healed an ally: that ally gains 2 Block | Support that feeds Block |
| Hakkapel | 2 | Charge | While this unit moved 4+ tiles this turn: +2 damage | Mounted aggression |
| Freewing | 1 | Skirmisher | After Combat: may use its remaining movement | Flier hit-and-run |
| Lance Armor | 3 | Bulwark | Always: +1 Parry | Built-in bulk (the shield-role pattern) |
| Mage | 2 | Flow | Every 3rd Attack made this combat: +3 damage | Steady Balance caster |
| Shaman | 2 | Overwhelm | While this unit's AS is higher than its opponent's: +2 damage | Glass cannon |
| Suncaster | 1 | Radiance | Unit Turn End: adjacent allies gain 1 Block | Nimble support caster |

**Shaman.** Overwhelm starts mostly off: Shaman is slow (Speed 3, growth 22%) and Dark tomes are
typically Power-profile, so the player turns it on by choosing speed over bulk (a speed prefix,
speed gear, a lighter tome, slow targets). A fast Shaman can blow an enemy away at the cost of
being fragile (HP 17, DEF 3). Bonus turns need an AS gap of 4 or more, so it rarely gets both
bonus turns and Overwhelm. If it does overperform, the fix is to limit Overwhelm to gaps without
bonus turns, not to add conditions.

No MVP unit has convoy access yet.

## Upgrades

An upgraded unit is shown with a "+" ("Archer+"), like a Slay the Spire card. Rules in
[game-vision.md](game-vision.md#units); this is the first pass for the MVP units.

- **Standard upgrade:** the "+" trait and 3 stat points (the +1 prefix budget; 2 HP = 1 point).
- **Big upgrade:** the "+" trait, 1 stat point and a new weapon type or movement type. The new
  option is the main reward.
- Upgrades never change growths.

| Unit+ | Trait+ | Stat gains | Big change |
|-------|--------|-----------|------------|
| Sellsword+ | Professional+: Before Combat, while this unit has triangle Advantage: gain 5 Block | +1 MGT | Gains Axe (`Godot_FE`'s Man-at-Arms promotion was sword + axe), so it can choose its triangle matchup |
| Fighter+ | Momentum+: Missed: this unit's next attack this combat gains +25 Hit, and this unit gains +1 damage for the rest of the combat (stacks) | +2 MGT, +2 HP | — |
| Lancer+ | Phalanx+: Unit Turn Start: gain 2 Block per adjacent ally | +1 DEF | Becomes Mounted: gains the Mounted tag and movement type, Movement 5 → 7 (Hakkapel's), to reach allies and hold the line |
| Archer+ | Volley+: Hit dealt while at maximum range: +4 damage | +2 MGT, +1 SPD | — |
| Brawler+ | Breaker+: First Hit dealt this combat: the target loses 2 extra Stance | +4 HP, +1 MGT | — |
| Thief+ | Opportunist+: Always: +25 crit chance | +1 SPD | Gains Sword (`Godot_FE`'s Cutthroat promoted to Bladehand, sword + dagger), for foes that aren't Exposed |
| Battle Medic+ | Triage+: Healed an ally: that ally gains 4 Block | +1 MGT, +1 DEF, +1 RES | — |
| Hakkapel+ | Charge+: While this unit moved 4+ tiles this turn: +4 damage | +2 MGT, +1 DEF | — |
| Freewing+ | Skirmisher+: After Combat: may use its remaining movement, and gains 2 Block if it moves | +2 SPD, +1 RES | — |
| Lance Armor+ | Bulwark+: Always: +1 Parry, +1 Stance | +4 HP, +1 DEF | — |
| Mage+ | Flow+: Every 3rd Attack made this combat: +5 damage | +1 MGT | Gains Dark (`Godot_FE`'s Sea Witch promotion used all magic), so it can switch between Balance and Power |
| Shaman+ | Overwhelm+: While this unit's AS is higher than its opponent's: +3 damage | +2 MGT, +1 SPD | — |
| Suncaster+ | Radiance+: Unit Turn End: adjacent allies gain 2 Block | +1 MGT, +1 SPD, +1 RES | — |

- **Fighter+** stacks flat damage, not Might, so the forecast shows exactly what each miss added.
  It is self-limiting: after a miss, the next attack has +25 Hit, so stacks build slowly
  (typically +1 or +2 a combat) and reset every combat. Uncapped for now; cap it if it overperforms.
- **Lance Armor+** keeps Parry at 1 and adds Stance, rather than Parry 2, which would cut every
  AtkX-2 weapon to one attack and hard-counter the Brawler.
- **Shaman+** gets Speed on purpose, nudging it toward turning Overwhelm on.

**Shield roles.** `Godot_FE`'s shield-weapon units (Ward, Bulwark, Squire, Penitent, Shield
Runner) caused major balance problems, and shields are now equipment. Bulky roles get their bulk
from traits instead. Three patterns, all expressed as effect text:

| Pattern | Example trait |
|---------|---------------|
| Reward defensive builds | "Unit Turn Start: +1 Block for each point of Parry" |
| Reward carrying a shield | "While Equipment is a shield: +2 Defense, +1 Stance" |
| Built-in bulk | "Always: +3 Defense" |

No MVP unit is a shield unit; these patterns are for when one is added.

## Prefixes

Modeled on Terraria's item modifiers (prefixes): each recruited unit rolls one prefix that
permanently shifts its stats, shown before its name. This replaces `Godot_FE`'s hidden random
noise on every stat, so a unit's quality is readable at a glance.

| Terraria | Bandit Bash |
|----------|-------------|
| Prefix shown before the item name ("Demonic Minishark") | Prefix shown before the unit type ("Sturdy Lancer") |
| Tier +2 to −2, from strongest to weakest | Same scale; the UI colors the name by tier |
| Value changes with the prefix | A unit's recruit price changes with its prefix |
| Universal prefixes plus category prefixes (melee, ranged, magic, accessory) | Universal prefixes for every unit; role prefixes can come later |
| Mixed prefixes (Ruthless: more damage, less knockback) | Trade-off prefixes (e.g. more Might, less Defense) |
| Mercy rule: bad weapon prefixes are often voided | Bad prefixes can be made rarer the same way |
| Reforging at the Goblin Tinkerer for ⅓ of the item's current value | A Shop re-roll priced from the unit's value |

**Rules**

- **What it changes:** a prefix shifts a few base stats and their growths in the same direction,
  so one word describes the unit now and as it levels. For example, "Swift": more Speed and a
  higher Speed growth.
- **No prefix is the baseline.** A unit with no prefix ("Lancer") is the unit type in its pure
  form. Prefixes are tiered +2 to −2 around that.
- **Rolls lean positive.** Recruits are more likely to roll a positive prefix than a negative one,
  to reward the player and keep runs fun. Bad prefixes exist and can be fixed by re-rolling. A
  re-roll can land on a worse prefix or none, but never on the same prefix again.
- **Re-rolling:** a Guildhall service re-rolls a unit's prefix for gold, priced like Terraria's Goblin
  Tinkerer, whose reforge costs one-third of the item's current value:
  - **Base price** = ⅓ × the unit's value, where value = its unit type's recruit price × its
    current prefix's value multiplier (below). Fixing a bad prefix is cheap; fishing for a better
    one on an already good unit is expensive.
  - **Escalation:** each further re-roll in the same Guildhall costs +50% of the base price. The count
    resets at the next Guildhall.
  - Events can also offer a free re-roll.

| Current prefix | Value multiplier |
|----------------|------------------|
| −2 | ×0.5 |
| −1 | ×0.75 |
| None | ×1.0 |
| +1 | ×1.3 |
| +2 | ×1.8 |

The multipliers loosely follow Terraria's spread (Broken −69% to Godly +112%), compressed to five
tiers. The same multiplier sets a recruit's price (40 gold × the multiplier). First pass, to
retune in playtesting.
- **Enemies:** depend on difficulty. On Normal, only elites (key-combat mini-bosses) and bosses roll
  prefixes. Other difficulties and run settings can change this.
- **Commanders** never roll prefixes; their stats are fixed.

**Budget by tier.** Each tier has a budget matched to `Godot_FE`'s draft rolls
(`unit_draft_selector.gd`: a bell curve per stat, mean +0.25, spread 1.75 for stats, 3 for HP and
10% for growths). A simulation of 200,000 old rolls over the kept stats placed each tier at the
same rarity of old roll:

| Tier | Stat points | Growth points | Same as an old roll at about |
|------|-------------|---------------|------------------------------|
| +2 | +5 | +35% | the top 5% |
| +1 | +3 | +25% | the top 16% |
| None | 0 | 0 | the median |
| −1 | −2 | −10% | the bottom 16% |
| −2 | −4 | −25% | the bottom 5% |

- 2 HP counts as 1 stat point; old HP rolls were about 1.7 times as spread out as other stats.
- A prefix can spend budget on Hit, which is not a stat: 10 Hit counts as 1 stat point. This rate
  is a starting guess with no `Godot_FE` basis; tune it in playtesting.
- No single stat moves more than 5, the old per-stat maximum.
- Trade-off prefixes net out to their tier: +4 Might and −1 Defense is a +1 prefix.
- Negatives are smaller than positives because the old rolls leaned slightly upward.
- Prefixes touch HP, Might, Speed, Defense, Resistance and Hit. Movement and Constitution are
  never changed, as in `Godot_FE`. No stat or growth can go below 0.

**Prefix list (first pass).** Twelve prefixes; every number is a starting point to tune.

| Tier | Prefix | Stats | Growths | Points (stats / growths) |
|------|--------|-------|---------|--------------------------|
| +2 | Heroic | +2 MGT, +2 SPD, +2 HP | +15% MGT, +10% SPD, +10% HP | 5 / 35 |
| +2 | Stalwart | +3 DEF, +2 RES | +20% DEF, +15% RES | 5 / 35 |
| +1 | Mighty | +3 MGT | +25% MGT | 3 / 25 |
| +1 | Swift | +3 SPD | +25% SPD | 3 / 25 |
| +1 | Sturdy | +4 HP, +1 DEF | +15% HP, +10% DEF | 3 / 25 |
| +1 | Warded | +3 RES | +25% RES | 3 / 25 |
| +1 | Keen | +20 Hit, +1 SPD | +15% SPD, +10% MGT | 3 / 25 |
| +1 | Reckless | +4 MGT, −1 DEF | +30% MGT, −5% DEF | 3 / 25 (trade-off) |
| +1 | Hasty | +4 SPD, −2 HP | +30% SPD, −5% HP | 3 / 25 (trade-off) |
| −1 | Frail | −4 HP | −10% HP | −2 / −10 |
| −1 | Sluggish | −2 SPD | −10% SPD | −2 / −10 |
| −2 | Feeble | −2 MGT, −2 SPD | −15% MGT, −10% SPD | −4 / −25 |

**Odds (first pass).** Roll the tier first, then pick a prefix within the tier with equal odds,
as Terraria's reforge gives every eligible prefix equal odds.

| Result | Chance |
|--------|--------|
| No prefix | 30% |
| +2 | 10% |
| +1 | 35% |
| −1 | 18% |
| −2 | 7% |

That gives 45% positive against 25% negative, leaning positive as decided. Prefixes can be read
against traits: a Swift or Hasty Shaman turns Overwhelm on, and a Keen Fighter covers the axe's
low Hit.

## Recruiting and item transfer (stub)

How a bought unit joins the army and how gear moves onto it. To be designed; this records what is
already decided elsewhere and what is still open.

**Already decided**

- Recruits are bought at the Guildhall and are cheap, so permadeath losses can be replaced
  (game-vision.md). Events can also give units.
- A recruit joins at the army's average level, rounded down, with its prefix already rolled
  ([Prefixes](#prefixes)).
- Recruiting past max army size replaces an existing unit; the replaced unit's items go to the
  convoy, which gains temporary space for them (game-vision.md, Army). The commander can never be
  replaced; losing it ends the run.
- Dead units keep their items, which can be taken in army management and battle prep.
- Unwanted items are scrapped, never sold ([items.md](items.md#scrapping)).

**To design**

- **Preview:** what the player sees before buying: type, prefix, trait, stats, starting gear.
- **Starting gear:** what a recruit arrives with. `Godot_FE` gave a starting weapon for each of the
  unit's weapon types; the vision wants starting gear to be weak and meant to be replaced.
- **Hand-over on replacement:** whether the leaving unit's gear can go straight onto the recruit
  in one step (where the recruit can use it), instead of always passing through the convoy.
- **Weapon compatibility:** a replaced unit's weapon may be a type the recruit can't use; where it
  goes, and how the screen makes that clear.
- **Convoy overflow:** what happens when the leaving unit's items exceed even the temporary space
  (scrap prompt at once, or temporary space for that many items).
- **Offers:** how many recruits a Guildhall shows, how they're chosen, and whether they can be
  refreshed.
- **Co-op:** each player recruits for their own army; whether partners can hand items to each
  other.

## Open questions

- **Prefix tuning:** the first-pass list and odds above need playtesting.
- **Re-roll details:** tune prices in playtesting.
- **Difficulty:** the difficulty levels themselves and which enemies roll prefixes on each.
- **Mage Tower (stub, not in the MVP):** whether it gets its own units (the vision names Mage
  Knight and Tower Guard) or draws from the magic units above. The MVP is built around Mercenary.
- **Convoy access:** which future unit types can reach the convoy, and how.
- **Recruiting and item transfer:** see the stub above.
