# Game Vision

The living design document for Bandit Bash, and the master copy of the design. It began as a
condensed version of the **Living Labyrinth Master Ideation Document** (April–May 2026), the
redesign that came out of rethinking `Godot_FE/`. That source is frozen, verbatim, in
[`living-labyrinth/master-ideation.md`](living-labyrinth/master-ideation.md). Read it for detail
and intent, but where the two differ, this file wins.

Design decisions are made here. Each one updates the relevant section, leaves
[Open and unfinished](#open-and-unfinished) and gets a line in [Decisions](#decisions).

## Using this when building features

Every gameplay feature has two references: this vision and the old build in `Godot_FE/`.

1. **Start here.** Find the system below, then read its section in `master-ideation.md`.
2. **Then read `Godot_FE/`.** Its implementation and `Godot_FE/docs/systems/` show how the old
   game did it, what worked, and which bugs to avoid (each system doc has an "As-built notes &
   defects" list).
3. **When they disagree, the vision wins.** That covers rules, formulas and tuning values. Where
   they differ, list both values with their sources in the plan or summary.
4. **When the vision is silent, `Godot_FE/` is the basis.** Map generation, pathing and AI, level
   authoring, UI flow and anything else this file doesn't cover is ported from `Godot_FE/` as
   before.
5. **When the vision is unfinished, ask.** A blank heading, a `WIP` or `PLACEHOLDER` tag, a
   question mark in a value, or anything under [Open and unfinished](#open-and-unfinished) is not a
   basis for a value. Ask before filling it in.

## The short version

- A roguelite tactics game. Each run is one campaign map (one act in v0) of about 18 nodes,
  traversed by a small army of individual, permadeath units on turn-based grid battles.
- Runs are short and battles are small: a standard combat takes 2–5 minutes, with 3–5 enemies.
- The army is led by a **commander**. If the commander falls, the run is lost; in co-op it is
  downed instead (see [Combat maps](#combat-maps)). The whole army deploys in every combat.
- Army size works like card draw and mana in Slay the Spire: more units mean more actions and
  more storage. The maximum is 10; most runs sit at 3–6.
- Builds are shaped by **heirlooms** (army-wide passives), weapon **profiles** (Nimble, Balance,
  Power) and a three-slot unit inventory (Weapon, Equipment, Pouch).
- Combat adds **Block** (damage absorbed before HP) and **Stance** (hits of margin before a unit is
  **Exposed** and can be crit) to Fire Emblem–style exchanges.

## Design pillars

| Pillar | Intent |
|--------|--------|
| Reduce player cognitive burden | Playtesters found the old game's options and information tiring. Fewer, clearer decisions. |
| Decrease run length | Shorter runs make losses less punishing and encourage risk-taking. |
| Incentivize proactive players | Reward calculated, aggressive trades and map control over slow, safe turtling. |
| Remove "hurry up and wait" decisions | Named in the source; its rationale is still blank. |

## Run structure

**Start of a run.** The player picks a faction and commander, then a starting heirloom.

| Faction | Commander unit type | Max army size | Funds | Starting army |
|---------|---------------------|---------------|-------|---------------|
| Mercenary | Drengr | 6 | 100 G | Hakkapel, Archer, Battle Medic |
| Mage Tower (stub, not in the MVP) | Mage Knight | 4 | 250 G | Tower Guard, rest unspecified |

- The faction gates faction-locked heirlooms, weapons and unit types.
- Each commander carries a unique **Commander Heirloom** (e.g. Iron Heart: every 7th attack gains
  lifesteal). Commanders and factions set the base army size.
- Design intent: the commander's unit type is good and worth building around but doesn't win a run
  alone. Starting units and starting equipment are deliberately weak "strikes and defends", there
  to be replaced.
- **Starting heirlooms** are only offered at run start and add variety without forcing a build.
  Examples: Abundance (+1 army size, two common unit picks), Ancestral Weapon (a rare weapon pick),
  Tactician's (doubles the weapon profile triangle).

**Difficulty and scaling (stub).** Challenge should rise in steps through a run, like Balatro's
Antes, with each step making combats harder. Nothing is defined yet: not the steps, what each step
raises (candidates: enemy levels, enemy count, which enemies roll [prefixes](unit-roster.md#prefixes)),
nor the selectable difficulty levels. On Normal, only elites and bosses roll prefixes.

**Campaign nodes.**

| Node | Purpose | Targets |
|------|---------|---------|
| Standard combat | Small skirmish; main source of XP; simple rewards, including gold. | 2–5 min, 3–5 enemies (always < 10, about the player's count), no bosses |
| Key combat | Small Fire Emblem–style map with mini-bosses. Rewards a heirloom. | 5–10 min, 2–4 per run |
| Boss combat | Large map; the boss directly affects the map. | — |
| Armory (Shop) | Spend gold on weapons, equipment, trinkets, consumables and heirlooms. Items are bought straight onto a unit, with a before/after comparison; the item it replaces is either **traded in** (its [scrap value](items.md#scrapping) comes off the price) or sent to the convoy. No sell screen. Has its own map icon. | — |
| Guildhall (Shop) | Spend gold on recruits (cheap, so a player can replace units lost to permadeath), runes and prefix **re-rolls**. A re-roll is priced from the unit's value, like Terraria's Goblin Tinkerer, and rises with each re-roll in the same Guildhall. Has its own map icon. | — |
| Unknown (`?`) | The random slot. Usually an event: a narrative choice with trade-offs (heirlooms, unit upgrades, prefix re-rolls, gold, weapons or unique units, in exchange for damage, curses or a surprise combat). It can instead turn out to be a standard combat, Shop, Camp or Treasure; see the campaign map below. | — |
| Camp | Choose one: **Feast** (heal 35% of each unit's HP, and optionally cook one [ingredient](items.md#consumables) from the convoy to give every unit a guaranteed gain on its next level-up), **Train** (upgrade one unit, like a Slay the Spire card; normally once per unit), or **Revive** (one fallen unit at 30–40% HP). Not meant to be the main path. | 2–4 per 18-node run, 5 at most |
| Treasure | Guaranteed non-combat chest with a heirloom; size sets rarity; sometimes gold or loot. | At least 2 (source says "2(3?)") |

**Campaign map.** Ported from `Godot_FE/`'s Slay the Spire–style generator
(`campaign_map/map_generator.gd`), resized for the vision:

- **Shape:** 18 floors (17, then the boss) × 7 columns. Up to 6 paths start on floor 1 and climb
  without crossing; each node links to the same or an adjacent column on the next floor, and every
  node on floor 17 leads to the single boss. A run visits 18 nodes, one per floor.
- **Visible:** the whole map shows from the start, so players plan a route.
- **Key combats:** two fixed rows every path must cross guarantee the minimum of 2 (first pass:
  floors 6 and 12). Extra key-combat nodes appear by weight elsewhere, so a player who seeks risk
  can route through up to 4 for more heirlooms. Generation never lets a path hold more than 4.
- **Typical path (target mix):**

| Combats (9) | Count | Other nodes (9) | Count |
|-------------|-------|-----------------|-------|
| Standard | 5 | Camp | 3 |
| Key | 3 | Treasure | 2 |
| Boss | 1 | Armory, Guildhall | 1 each |
| | | Unknown (`?`) | 2 |

  This lands inside every range above and gives about 7 heirlooms (starting 1, key 3, treasure 2,
  Unknown events about 1) against the vision's 6–9.
- **Seeded and saved:** the map comes from the run seed on its own RNG stream, and the generated
  graph is saved with the campaign, so a resumed run is identical. `Godot_FE/` drew from the global
  RNG and lost its seed whenever a sound played; that is not ported.
- **Co-op route:** the team travels together on one map. Each player votes for the next node, and
  the node is picked at random weighted by votes: 2 votes left and 1 right gives left a 2-in-3
  chance. The host draws the result.

**Gold.** Combat is the main source of gold. Events can pay or charge gold, as in Slay the Spire.

- **Scale:** gold amounts are a tenth of `Godot_FE`'s (the Mercenary starts with 100, not 1000) so
  prices are easy to compare. Every derived amount (grade bonuses, re-roll and scrap prices) rounds
  to the nearest whole gold, halves up.
- **Grades:** a combat pays +25% for finishing under the map's turn par and +25% for losing no
  units. Maps and combats are meant to be much shorter than `Godot_FE`'s; grades reward that, and
  leave room for later modifiers (e.g. hitless). This simplifies `Godot_FE`'s four-letter grade,
  which also had a bug: a win between 1.2× and 1.5× par got the worst turn grade.
**Economy (first pass; must be retuned in playtesting).** Every number below is a starting point
from `Godot_FE/` values cut to the new scale, Slay the Spire ratios, or a model of a typical path.
Expect to change all of them once real runs are played.

| Income | Gold | Per typical run |
|--------|------|-----------------|
| Starting fund (Mercenary) | 100 | 100 |
| Standard combat | 30 (+8 per grade bonus) | about 190 |
| Key combat | 60 (+15 per grade bonus) | about 225 |
| Boss combat | 0 (the run ends) | 0 |
| Events | Some pay 30–60, some charge 30–50 for a benefit, some none; about +8 on average | about 12 |
| Unknowns that turn into combats | as standard combat | about 10 |
| Treasure | Half the chests add 20–60 | about 40 |
| Scrap | 20% of buy price | about 30 |
| **Total** | | **about 610** (520 with no grade bonuses, 695 with all) |

Combat provides about two-thirds of all gold. Modeled on the typical path, a player has about 210 at
the first shop and 260 at the second, and ends a run with about 150 unspent (40 with no bonuses, 240
with all). Higher combat pay (40 and 75) left about 300 unspent, because two shops can't absorb it.

| Price | Gold |
|-------|------|
| Iron / simple weapon | 40 |
| Steel-tier weapon | 60 |
| Silver-tier weapon | 150–250 |
| Potion | 25 |
| Equipment | 60–200 |
| Trinket | 30–80 |
| Rune | 30 |
| Heirloom | 150–250 |
| Recruit | 40 × its prefix's value multiplier (20–72) |
| Prefix re-roll | ⅓ of the unit's value (about 7–24), +50% of that for each repeat in the same Guildhall |

**Node placement (first pass).** Modeled on Slay the Spire's generator.

| Floor | Node |
|-------|------|
| 1 | Standard combat |
| 6, 12 | Key combat |
| 9 | Treasure |
| 17 | Camp |
| 18 | Boss |
| Every other floor | Rolled by weight: Standard 4, Unknown 2, Armory 1, Guildhall 1, Camp 2, Treasure 1, Key 1 |

Placement rules; a roll that breaks one is rerolled:

- No Camp or extra key combat before floor 6, and no Armory or Guildhall before floor 3.
- Key combat, Shops (Armory or Guildhall) and Camp are never directly connected by a path.
- Every path passes through at least one Armory and one Guildhall.
- A node with two or more paths up leads to nodes of different types.
- No Camp on floor 16, the floor before the fixed Camp row.
- No path holds more than 4 key combats.

Shops (Armory and Guildhall together) are far more common than in Slay the Spire (about 17% of
rolled floors against its 5%) because the Guildhall is where units are recruited. Their separate map
icons let players route toward what their run needs.

**Unknown (`?`) rolls.** What an Unknown node becomes is rolled when the team enters it, from the
run's seeded stream, as in Slay the Spire. When a type comes up, its chance drops back to base;
every type that didn't come up gains its base chance again. The odds reset at the start of each
run.

| Becomes | Base chance | Gain when it doesn't come up |
|---------|-------------|------------------------------|
| Standard combat | 10% | +10% |
| Shop (Armory or Guildhall, even odds) | 3% | +3% |
| Treasure | 2% | +2% |
| Camp | 3% | +3% |
| Event | The rest | — |

Combat, Shop and Treasure use Slay the Spire's values as remembered from its decompiled code (the
wikis don't list them). Slay the Spire never turns an Unknown into a rest site, so Camp has no
basis: it mirrors Shop.

## Army

- A roster of distinct units, each with its own weapons, equipment, inventory, stats and profile.
  Leveled through combat; classic permadeath.
- Commander stat spreads and names are fixed and persist across runs. Every other non-event unit is
  randomized.
- Max army size comes from progression, heirlooms and the starting commander. It is never sold in
  shops: like max energy in Slay the Spire, it adds actions every turn, so it is very strong and
  allowed, but never simply bought.
- **Recruiting past the max** means replacing an existing unit; the replaced unit's inventory goes
  to the convoy.
- **Dead units** stay on the roster but can't fight. Their items can be taken in army management and
  battle prep. Revival is a Camp option.

## Units

**Stats.** Seven: HP, Might (MGT), Speed (SPD), Defense (DEF), Resistance (RES), Movement (MOV)
and Constitution (CON). Might is the single offensive stat; every weapon, magic included, scales
with it unless the weapon names another scaling stat. Skill, Luck and Magic are cut. Stance (a
unit-type stat), Block (base 0) and Parry (from equipment) are combat values on top. Unit
archetypes come from traits and weapon restrictions, not from extra stats.

**Attack Speed** sets how many turns a unit gets in a combat exchange.

```
NetWeight   = Weapon.weight + Equipment.weight + Effect.weight
AttackSpeed = Speed - max(0, NetWeight - Constitution)
```

Speed is a unit's top speed unweighted. Constitution is meant to be large and to define how much a
unit can carry; the more overloaded a unit is, the larger its speed penalty.

**Experience** keeps level-ups exciting and lets the player build a relationship with a unit,
while stopping one unit from carrying the army. It is a hybrid:

- **Shared XP (most of it):** when a combat ends, every deployed, surviving unit gets the same XP,
  set by the combat type (standard, key, boss).
- **Personal bonus (small, capped per combat):** extra XP for a unit's own actions: hits, defeats,
  healing, Block given, and non-combat actions such as looting houses or closing reinforcement
  routes. A unit that carried the fight earns a little more, but the cap stops funneling.

Because most XP comes per combat, not per enemy, levels per run are predictable, which lets combat
be balanced around them, and farming reinforcements earns nothing. This replaces the source's tanh
formula on unit value and its XP decay rule.

- **Target:** a typical unit gains 4–6 levels over a run. Leveling is regular but stays smaller
  than upgrades and replacing units.
- **Timing:** level-ups happen after combat, all together on the results screen. No pop-ups
  interrupt a fight, and in multiplayer the host awards XP once.
- **No level cap:** the XP pace enforces a soft limit, which also leaves room for endless runs
  later.
- **New recruits** join at the army's average level, so replacing a unit is judged on its type,
  prefix and trait, not on catching up.

**XP amounts (first pass).** 100 XP per level at every level, as in `Godot_FE/`; a rising curve
can come later if endless runs need one. Totals assume 9 combats per run (5 standard, 3 key, 1 boss),
the typical path on the [campaign map](#run-structure).

| Shared XP | Per combat | Per run |
|-----------|------------|---------|
| Standard combat | 40 | 200 |
| Key combat | 70 | 210 |
| Boss combat | 100 | 100 |
| **Total** | | **510, about 5 levels** |

| Personal bonus (capped at 15 per combat) | XP |
|------------------------------------------|----|
| Hit dealt | +2 |
| Defeated an enemy | +5 |
| Healed an ally, or gave Block | +3 |
| Non-combat action (looting, closing reinforcement routes) | +5 |

**Combat MVP.** The unit with the most XP-earning actions in a combat is named the combat's MVP on
the results screen and gets +5 XP on top of the cap. A tie goes to the lower-level unit, nudging the
army toward even levels; if they are also level, to the one that earned more personal XP. It drives the player's relationship with
their units home without letting one unit run away: armies are small and fights are quick, so
every unit acts and the MVP should rotate. In co-op, each player has their own MVP.

How it plays out: a unit that only survives ends a run at about 5 levels; one that hits the cap
and is MVP every combat reaches about 6.8, the extreme. Recruits join at the army's average level,
rounded down so a recruit is never ahead of the army.

**Upgrades replace tiers.** Units have no tiers and never promote. A unit is either unupgraded or
upgraded, like Slay the Spire cards: a run starts with average units, replaces them with better
ones, and upgrades the good ones along the way. A Camp's Train choice upgrades a unit, normally once
per unit. An upgrade improves the unit's trait to a "+" version (e.g. Volley+) and adds a few stat
points. Some unit types may also gain something bigger, Fire Emblem promotion style: access to
another weapon type, or a new movement type (e.g. becoming mounted).

**Inventory.** Three slots. There is no off-hand and no main-hand/two-handed distinction.

| Slot | Holds |
|------|-------|
| Weapon | The unit's weapon or tool. Its weight counts toward Attack Speed. |
| Equipment | One piece of passive gear. Changing it in combat costs a full action; set it in army management and prep. Its weight counts toward Attack Speed. |
| Pouch | One trinket or one consumable. Bringing a stat-boosting trinket instead of a potion is a deliberate trade, and the single slot limits potion spam. |

There is no stash. Reserve items live in the convoy and are swapped in army management and prep.
Some special units can access the convoy; which ones, and how, is defined with unit types.

Future idea, not for v0: tag weapons as one- or two-handed and let random generation combine two
one-handed weapons into a single item.

**Unit types and generation** are in [unit-roster.md](unit-roster.md): the 13-unit MVP roster,
unit-type traits (which also carry the bulk shield units used to get from a shield weapon), and
Terraria-style prefixes that shift each recruited unit's stats and show its quality at a glance.
Movement types and tags (Armored, Mounted, Flier, Terror) are defined in [unit-roster.md](unit-roster.md#movement-and-tags), with terrain costs carried over from `Godot_FE/`.

## Weapons and equipment

A weapon's data falls into five groups: **equippability** (weapon type, which units can use it),
**combat exchange** (hit, profile, damage, damage type, scaling type and modifier, crit, CritX,
AtkX, weight, effectiveness vs a unit tag, weapon type or profile), **targeting** (range, target
faction), **block** (superseded by the Block redesign under [Combat](#combat)) and **skills**
(charges, skill).

| Simple weapon | Dmg | AtkX | Profile | Range | Hit | Crit | CritX | Weight | Identity |
|---------------|-----|------|---------|-------|-----|------|-------|--------|----------|
| Sword | 5 | 1 | Nimble | 1 | 80 | 0 | 3 | 8 | Control: consistent, low variance |
| Axe | 10 | 1 | Power | 1 | 65 | 0 | 3 | 15 | Commitment: high damage, misses expose you |
| Lance | 7 | 1 | Balanced | 1 | 80 | 0 | 3 | 12 | Solid in every situation |
| Bow | 6 | 1 | None | 2–3 | 100 | 0 | 3 | 5 | Damage from range, little defense |
| Gauntlets | 2 | 2 | None | 1 | 100 | 0 | 2 | 1 | Many fast hits to break Stance |
| Dagger | 2 | 1 | Nimble | 1–2 | 100 | 0 | 5 | 3 | Hybrid; punishes Exposed foes |
| Anima (Fire) | 5 | 1 | Balance | 1–2 | 80 | 0 | 3 | 1 | Steady magic (`Godot_FE` Fire) |
| Holy (Smite) | 4 | 1 | Nimble | 1–2 | 100 | 0 | 3 | 6 | Reliable magic (`Godot_FE` Smite) |
| Dark (Shade) | 7 | 1 | Power | 1–2 | 80 | 0 | 3 | 8 | Heavy magic (`Godot_FE` Shade) |
| Minor Heal (staff) | Heals 5 + Might scaling | — | None | 1 | — | — | — | 0 | Unbreakable (`Godot_FE` Minor Heal) |

The source's equip-type column (Versatile, Main Hand, TwoHanded, Two) is dropped with the off-hand.
Simple weapons carry no Block effects; named weapons may. Magic deals Magic damage, so it hits
Resistance.

- A weapon's profile follows its flavor, not its type: a Zweihander is Power, a long sword Nimble,
  a claymore Balance. Every weapon card and the combat forecast show the exact profile. Most types
  have a typical profile; daggers have none, so each dagger is chosen to fill a triangle gap.
- **Magic** comes in three weapon types, each with a typical profile: Anima (Balance), Holy, the
  old Light (Nimble), and Dark (Power). A specific tome can differ, as with daggers. Magic scales
  with Might and deals Magic damage, mitigated by Resistance.
- **Staves** heal by an amount that scales with Might. Other support weapons (whips, instruments,
  banners) and misc. weapons have headings only.
- **Durability** exists only on some weapons and is per map (e.g. healing staves). It forces
  prioritization rather than one optimal setup.
- **Equipment** is build-defining, one piece per unit, and can't be swapped mid-combat. Categories:
  quivers (ranged offense), coatings (bonuses against Exposed foes, debuffs on hit), shields
  (Stance and Block), armor, cloaks, bands, uniques. Equipment is much stronger than a Pouch
  trinket. Items, budgets and `Godot_FE` conversions are in [items.md](items.md).
  Equipment has no hard unit restrictions in the MVP: weight against Constitution limits heavy
  gear, and traits can reward specific gear. Add restriction tags only if playtesting shows a role
  needs protecting.
- **Pouch items** are consumables (limited uses: heal, cure, boost, light fog, open doors and
  chests) or trinkets (small passive bonuses to the holder). A unit carries one or the other.
  Every `Godot_FE` consumable carries over: stat boosters go in the Pouch, and the old growth
  boosters become ingredients, kept in the convoy and cooked at a Camp Feast (see [items.md](items.md)).
  Lockpicks are Pouch consumables any unit can carry; no unit type picks locks innately, so going
  after loot costs a unit its potion or trinket.
  Pouch items are weightless. An item that slows its holder does so through an effect that
  subtracts Attack Speed (the `Effect.weight` term), not through a weight value.

## Combat

**Turn phases.** Six named phases. The UI shows them, and every timed effect is written against one
of them (e.g. "Before Combat: +2 Block").

| Phase | When | Happens here |
|-------|------|--------------|
| Phase Start | A side's phase begins (player or enemy) | That side's units refresh Block and Stance, then Phase Start effects apply |
| Unit Turn Start | A unit begins its action | Per-unit start effects |
| Before Combat | A combat exchange begins, before the first attack | Applies to both the initiator and the defender |
| After Combat | A combat exchange resolves | Applies to both participants that survive |
| Unit Turn End | A unit finishes its action | Per-unit end effects |
| Phase End | A side's phase ends | End-of-phase effects (Bleed, Poison) |

**Exchange.** The initiator takes the first turn, the defender the second; extra turns earned
from Attack Speed are added at the end. The exchange ends as soon as either unit is defeated.

The faster unit (initiator or defender) gets bonus turns from the Attack Speed gap. The first
threshold is `ExtraTurnConstant = 4`, and each later one is 2 further apart than the last, the same
spacing `Godot_FE/` used:

| AS gap | Bonus turns |
|--------|-------------|
| 0–3 | 0 |
| 4–9 | 1 |
| 10–17 | 2 |
| 18+ | 3 (maximum) |

**Each turn** the attacker makes a number of attacks:

```
Attacker.AtkX     = Weapon.AtkX + Equipment.AtkX + Heirloom.AtkX + Status.AtkX
Turn.AttackCount  = max(1, Attacker.AtkX - Defender.Parry)
```

**Parry** is the defender's attack reduction. It comes from equipment such as
shields, and from heirlooms and statuses: a shield with Parry 1 means each of the attacker's turns
lands one fewer attack, but never fewer than one. This is the source's `AtkX − Mitigation` term,
which belongs to the defender and is unrelated to damage mitigation.

For each attack, roll to hit (2RN, carried over from `Godot_FE/`):

```
Hit% = clamp(Weapon.hit + Triangle (±15) + effects - Defender.avoid, 0, 100)
Avoid = Terrain.avoid + effects
```

Units have no Hit or avoid stat, and crit avoid no longer exists. Accuracy belongs to the weapon,
which keeps weapon identities intact (the axe's low Hit stays its liability at any level), and
leveling never changes it. Units differ in accuracy only through traits, prefixes, equipment and
statuses. Avoid comes from terrain, a key gameplay feature, and from effects.

On a hit, damage passes through fixed stages, in this order:

| # | Stage | What happens |
|---|-------|--------------|
| 1 | Attack | Weapon damage + scaling + flat attack bonuses, effectiveness and the triangle |
| 2 | Mitigation | Subtract the defender's mitigation (below). Pure damage skips this stage only |
| 3 | Critical | × CritX, only if the defender's Stance was 0 before this hit |
| 4 | Multipliers | × every percent modifier, multiplied together (×0.5 and ×0.75 give ×0.375) |
| 5 | Floor | Round, and never below 0. A hit reduced to 0 is fully countered |
| 6 | Block | The defender's Block absorbs what it can |
| 7 | HP | HP takes the rest |
| 8 | After hit | If real damage got through (to Block or HP), Stance −1; after-hit effects resolve |

Flat changes come before percent ones, so "take 5 less damage" is worth the same whether or not a
halving effect is active. Multipliers never stack to immunity, so they need no cap. Every effect
that changes damage is a modifier on one of these stages; see
[effects-system.md](effects-system.md).

**Damage**

```
Attack     = Weapon.attack + Weapon.scaling_modifier * Unit.scaling_stat + Status.attack + Equipment.attack
             (scaling_stat is Might unless the weapon names another)
Damage     = Attacker.attack - Defender.mitigation
Mitigation = Unit.source_stat + Equipment + Heirloom + Status
Effective  = (EffectiveModifier * Weapon.attack) + scaling + status + equipment,
             EffectiveModifier = 3 + status + equipment + heirloom bonuses
```

Mitigation comes from the unit's own stat for the incoming damage type (table below), plus flat
reductions from equipment, heirlooms and status effects ("take 5 less damage"). The defender's
weapon does not add mitigation.

| Damage type | Source stat |
|-------------|--------------|
| Physical | Defense |
| Magic | Resistance |
| Split | ½ (Defense + Resistance) |
| Pure | Nothing |

**Block.** Block absorbs damage before HP. It lets players trade HP as a resource and removes the
need to heal between fights. It is a stat shown on every unit, and its base value is 0 for every
unit. All Block comes from effect text tied to a [turn phase](#combat), on weapons, equipment,
heirlooms, statuses and unit-type traits (e.g. "Armored — Unit Turn Start: +2 Block"). Weapon types
already give units a soft innate Block identity, so no separate unit stat is needed. Block refreshes
with Stance at its side's Phase Start: a refresh clears it to 0, then Phase Start effects apply.
This replaces the source's four timed Block phases and the weapon "block data" fields. Refreshing
at your own Phase Start means Block gained there absorbs counters during your attacks, rewarding
proactive play; whatever is left protects you on the enemy phase.

**Stance and Exposure.** Stance is a per-unit stat: hits of margin before the unit is Exposed. Its
base value comes from the unit type; equipment such as shields, heirlooms and statuses add to it.
It refreshes with Block at its side's Phase Start. Only Exposed units can be crit. Fully mitigated hits
(0 net damage) don't reduce Stance, so high-Defense tanks still beat many weak hits.
`Crit chance = 25 (ExposureConstant) + weapon + equipment + rune + status effect + unit trait`. A crit
multiplies the attack by the weapon's CritX.

**Weapon Profile Triangle.** Balance beats Nimble, Power beats Balance, Nimble beats Power; the same
profile is a Standoff.

| Outcome | Damage | Hit |
|---------|--------|-----|
| Advantage | + WPTAE | +15 |
| Disadvantage | − WPTAE | −15 |
| Standoff | 0 | 0 |

`WPTAE = round(Weapon.attack × 1/4)`, at least 1. The soft cap is about 10 (the strongest weapon's
damage × ¼).

Weapons with profile **None** (Bow, Gauntlets) never take part in the triangle: they get no
advantage and suffer no disadvantage, and their opponent's triangle result against them is a
Standoff. This is part of their identity: bows win through range, gauntlets through breaking
Stance.

**Status effects (WIP)** stack by duration, by effect weight, or both. Examples: Bleed (weight;
cleansed after it deals damage at Phase End), Garrison (duration; while it lasts, a refresh keeps
leftover Block instead of clearing it), Poison (both; deals its stack count each
Phase End, then loses a stack).

## Combat maps

**Source.** Maps are hand-authored layouts in a pool per combat type (standard, key, boss), as in
`Godot_FE/`. Each run randomizes what goes on them: enemy groups, spawn positions and loot, from
the run's seeded stream. `Godot_FE/` already supported random unit groups and position variance.

**Size.** Fire Emblem Heroes scale, the vision's reference: standard maps about 8×6 to 10×8, key
maps about 12×10. Boss maps are larger and longer than both. Small maps keep standard combats in
the 2–5 minute target with the whole army (3–6 units) deployed against 3–5 enemies.

**Objectives by combat type.**

| Combat | Objectives |
|--------|------------|
| Standard | Rout (defeat every enemy), or Defeat the Leader (one marked enemy) for very short fights |
| Key | Defeat the mini-boss, Seize a tile, Survive N turns, or Defend a tile |
| Boss | Defeat the boss; the boss has a mechanic that changes the map |

`Godot_FE/` declared Seize and Defend but never made them work; they are built properly here. Each
map has an authored turn par for the [grade bonus](#run-structure).

**Interactables (MVP).**

| Interactable | What it does |
|--------------|--------------|
| Chest | Opened with a lockpick (a Pouch consumable); holds loot rolled for the run |
| Door | Opened with a lockpick, or by a lever that opens a linked group of doors (`Godot_FE/`) |
| House | A unit visits it for a reward (gold, an item, or a heirloom chance) and the personal-XP bonus; the vision's "looting houses" |
| Reinforcement point | Enemy reinforcements arrive from marked points on a timer; a unit closes a point by ending its turn on it, earning the personal-XP bonus; the vision's "closing reinforcement routes" |
| Breakable | Walls and debris a unit can destroy to open a new path (`Godot_FE/`'s Demolish) |

**Terrain** is carried over from `Godot_FE/` ([unit-roster.md](unit-roster.md#movement-and-tags)).
MVP maps use a core subset: plain, road, forest, thicket, mountain, river, bridge, house, fort,
wall, door and chest tiles. Terrain is the only source of avoid, so every map needs cover for both
sides.

**Multiplayer maps.** The MVP uses **parallel maps**: each player fights their own copy of the same
combat (same map, same seed, their own army) at the same time, and the combat ends when everyone has
finished. Every map is authored once at solo size and keeps its solo balance. The target after the
MVP is a **hybrid**: standard combats stay parallel, while key and boss combats become shared
battles. Details are in [multiplayer-combat-options.md](multiplayer-combat-options.md).

When players finish their maps differently:

- **Reinforce.** A player who wins their map can send some of their surviving units onto a
  teammate's map that is still being fought. They arrive at the start of that map's next player
  phase, on its deployment edge or a reinforcement point, controlled by their owner. Sent units can
  die, so helping is a real risk. With 3–4 players, the sender picks which map to help, guided by
  each map's status (turn, units and enemies left) and any **call for aid** a struggling player has
  raised. All of a sender's units go to one map; several senders can help the same map; units sent
  to a map that ends before they arrive return unharmed.
- **Retreat.** A player can retreat from their map before losing: surviving units escape, and the
  player forfeits that combat's rewards.
- **The team wins if anyone wins.** A player who lost their map gets no gold, XP or MVP for it,
  and their fallen units stay fallen (revive at a Camp).
- **Downed commanders (co-op only).** A commander that falls in co-op is downed, not killed: that
  player's map is lost, and the commander returns after the combat. The run ends only if every
  player's commander falls in the same combat. In solo, a fallen commander still ends the run. How a
  player who lost a map rebuilds (the commander's HP, any cost, refilling the army) is open: losing
  must not leave a player with no army for the next fight.

A later addition, once shared battles exist: an **overflow** rescue skirmish where the team fights
to free units that fell.

## Run-wide resources

- **Runes:** single-use abilities used on the player turn, outside the action economy. They have
  their own inventory, not tied to a unit. They come from shops, rewards, heirlooms and units.
  Useful but never required: combats are balanced as if no rune is used.
- **Convoy:** shared storage, 1 slot per max army size, hard-capped. Loot decisions happen at pickup,
  and its small size prevents hoarding. Removing a unit from the army adds temporary space. There
  is no selling: unwanted items are [scrapped](items.md#scrapping) for gold, at pickup, as a trade-in
  at the Armory, or from the convoy at any time in army management.
- **Heirlooms** (the source also calls them relics): army-wide passives in one shared collection,
  with no per-unit assignment. Gained about 1 per 2–3 nodes (6–9 per run), capped at 8–12. Kinds:
  profile ("Power weapons deal +2 damage"), behavior ("units that defeat an enemy gain +3 damage
  next attack") and economy ("shops offer one additional item"). The game doesn't offer a heirloom
  the player already owns; if a second copy is gained anyway, both apply. In co-op, heirlooms tagged
  **unique** (those affecting more than one player's units) can be owned by only one player per
  campaign. Items with named effects may duplicate. See
  [effects-system.md](effects-system.md#duplicates).

## Changes from Godot_FE

Read from `Godot_FE/docs/systems/` (04, 07, 10, 11, 12) on October 14, 2026. Check the code before
relying on an old value.

| System | `Godot_FE/` | Vision |
|--------|-------------|--------|
| Run start | 3-stage draft: commander, then archetypes, then units and weapons | Faction and commander with a fixed starting army, then a starting heirloom |
| Deployment | Choose units up to the map's spawn tiles | The whole army deploys every combat |
| Inventory | 4 slots; slot 0 is the equipped weapon | Weapon, Equipment, Pouch; no off-hand, no stash |
| Convoy | Capacity 100 | 1 slot per max army size |
| Weapon triangle | By weapon type; ±20 hit, ±2 damage | By profile (Nimble/Balance/Power); ±15 hit, ±¼ weapon attack (min 1) |
| Crits | `crit − crit_avoid`, any time | Only when Exposed (Stance 0); base 25; no crit avoid |
| Block, Stance | None | Core defensive systems; both are unit stats that refresh each turn |
| Damage types | Physical, Magic, True | Physical, Magic, Split, Pure |
| Extra strikes | At AS gaps of 4, 6, 8, … | Same spacing (4, 10, 18), capped at 3 bonus turns |
| XP | Per hit and per defeat, linear formula with tier multiplier; clamps 1–25 / 2–100 | Mostly shared per combat, plus a small capped personal bonus for actions |
| Tiers and levels | Tiers 1, 2 and 4 with promotions; level caps per tier | No tiers: units are upgraded or unupgraded; no level cap |
| Durability | Per use; weapons break | Only some weapons, per map |
| Campaign nodes | Battle, Key battle, Event, Treasure, Recruitment, Boss (Shop and Elite were placeholders) | Standard, Key and Boss combat; Armory and Guildhall shops (the Guildhall sells units); Unknown ("?" random slot); Camp; Treasure. No Recruitment node |
| Death | Graveyard: revive for gold | Dead stay on the roster; revive at a Camp |
| Run-wide passives | None | Heirlooms and runes |
| Stats | HP, Strength, Magic, Skill, Speed, Luck, Defense, Resistance, Movement, Constitution | HP, Might, Speed, Defense, Resistance, Movement, Constitution |
| Kept | 2RN hit rolls, terrain avoid, effectiveness ×3, commander death loses the run, permadeath | — |

## Open and unfinished

Ask before building on any of these:

- **Multiplayer combat:** recovering from a lost map (a downed player rebuilding an army);
  light links between maps; the save change for one battle state per player; see
  [multiplayer-combat-options.md](multiplayer-combat-options.md).
- **Map content:** turn par per map; reward tables for houses and chests; reinforcement timers; boss
  mechanics.
- **Economy:** every first-pass income, price and the 20% scrap value must be retuned in
  playtesting.
- **Campaign map:** the first-pass weights, placement rules and Unknown odds need playtesting;
  the Camp chance in Unknown rolls has no basis.
- **Blank sections:** difficulty and Ante-style scaling (stub only), act scaling beyond v0,
  support weapons beyond staves, meta progression.
- **Items:** the open questions in [items.md](items.md) (quiver and coating equipment, shield
  weights against Constitution, uniques, item rarity).
- **Units:** the open questions in [unit-roster.md](unit-roster.md) (prefix tuning, Mage Tower
  stub, convoy access).
- **Experience:** the first-pass XP amounts need playtesting once the number of combats per run
  is known.
- **Pending unit types:** which special units can access the convoy, and how.
- **Effects system:** the open questions listed in [effects-system.md](effects-system.md).
- **Inconsistencies:** commander heirlooms use RED and GREEN factions; the faction table uses
  Mercenary and Mage Tower. "Heirloom" and "relic" are used interchangeably. Mage Tower's starting
  army is incomplete.
- **Truncated sentences:** the gameplay goal, the end of the combat-map rewards list, the end of the
  army-deployment paragraph, and the "Remove hurry up and wait" pillar rationale.
- **Placeholder values:** example heirlooms are marked "balance and effects are not final"; the
  treasure minimum is "2(3?)"; the Camp revive is a range (30–40%).

## Images

In `living-labyrinth/images/`.

| File | Shows |
|------|-------|
| `commander-selection-sketch.png` | Sketch of the faction and commander select screen |
| `starting-heirloom-mock.png` | Placeholder mock of starting-heirloom selection |
| `ref-loot-reward-screen.png` | Reference: a roguelite loot reward screen |
| `ref-deck-overview-screen.png` | Reference: a deck-overview screen, used for the army overview |
| `ref-roster-screen.png` | Reference: a tactics game's roster screen, used for the army overview |
| `ref-fe-heroes-map.png` | Reference: a small Fire Emblem Heroes map, the scale for a standard combat |

## Decisions

Newest last. Each decision is already reflected in the sections above.

| Date | Topic | Decision | Replaces |
|------|-------|----------|----------|
| October 14, 2026 | Source of truth | This file is the master design document; `master-ideation.md` is frozen. | The Google Doc as master |
| October 14, 2026 | Bonus turns | +1 at an AS gap of 4, +2 at 10, +3 at 18; maximum 3. | Blank formula |
| October 14, 2026 | Stance | A unit-type stat; equipment, heirlooms and statuses add to it. | No base value given |
| October 14, 2026 | Block | A stat that refreshes with Stance, raised by effect text on items, heirlooms and statuses. | Four timed Block phases and weapon Block fields |
| October 14, 2026 | Refresh timing | Each side refreshes Block and Stance at its own Phase Start. | Stance refreshing at the player turn only |
| October 14, 2026 | Leftover Block | A refresh resets Block to its stat value; Garrison keeps leftover Block while it lasts. | Block expiring at the next player phase |
| October 14, 2026 | Turn phases | Six named phases: Phase Start, Unit Turn Start, Before Combat, After Combat, Unit Turn End, Phase End. | Unnamed timings |
| October 15, 2026 | Attack count | `max(1, AtkX − Defender.Parry)`; Parry comes from equipment such as shields, heirlooms and statuses. | `AtkX − Mitigation` |
| October 15, 2026 | Inventory | Three slots: Weapon, Equipment, Pouch (one trinket or one consumable). No off-hand. | Main-Hand, Equipment, Pouch, Stash |
| October 15, 2026 | Stash | Removed; reserve items live in the convoy. Some special units can access the convoy. | 2-slot per-unit stash |
| October 15, 2026 | Parry | Name of the defender's attack-reduction stat. | "Mitigation" in the attack-count formula |
| October 15, 2026 | Base Block | 0 for every unit; unit-type traits can grant Block through effect text. A refresh clears Block to 0. | Undecided base value |
| October 15, 2026 | Equip types | Dropped (Versatile, Main Hand, TwoHanded). One- and two-handed weapons are a future idea, not v0. | Per-weapon equip type |
| October 15, 2026 | Mitigation sources | Unit stat for the damage type + equipment + heirlooms + statuses. The defender's weapon adds none. | `Weapon.MitigationSource` term |
| October 15, 2026 | Profile None | Never takes part in the triangle; always a Standoff. | Unstated |
| October 15, 2026 | Pouch weight | Pouch items are weightless; slowing effects subtract Attack Speed instead. | Unstated |
| October 15, 2026 | Dagger profile | Profile is per dagger; daggers have no typical profile. Simple Dagger is Nimble. | "Any" |
| October 15, 2026 | Damage stages | Attack → Mitigation → Critical → Multipliers → Floor → Block → HP → After hit. Pure skips Mitigation only. | Six-step attack list |
| October 15, 2026 | Percent stacking | Percent modifiers multiply together; no cap. | Unstated |
| October 15, 2026 | Effect counters | Last the whole run, like Slay the Spire's Pen Nib. | Unstated |
| October 15, 2026 | Effect counters | Two lanes, "this combat" and "this campaign", stated in effect text; one effect can have a counter in each. | Counters lasting the whole run |
| October 15, 2026 | Trigger scopes | This unit, Your Unit, Any Ally Unit (includes co-op partners), Any Unit. See effect-triggers.md. | Unscoped triggers |
| October 15, 2026 | Hit | A hit is any successful hit roll, even if fully countered or absorbed by Block. | Unstated |
| October 15, 2026 | Duplicates | Copies stack, but offers avoid things a player already owns, as in Balatro. | Unstated |
| October 15, 2026 | Duplicate scope | No-duplicate offers apply to each player's heirlooms only. Named-effect items may duplicate; revisit if it causes balance problems. | Unstated |
| October 15, 2026 | Unique heirlooms | Heirlooms tagged unique (affecting more than one player's units) can be owned by only one player per co-op campaign. | Unstated |
| October 15, 2026 | MVP roster | 13 tier-2 unit types, one per weapon role plus each movement type; see unit-roster.md. | `Godot_FE`'s 57 unit types |
| October 15, 2026 | Shield units | No shield weapon type; bulky roles get their bulk from unit-type traits. | Shield-weapon units |
| October 15, 2026 | Unit generation | Each recruited unit rolls a Terraria-style prefix that shifts its stats and is shown before its name. Details open. | Hidden random noise on every stat and growth |
| October 15, 2026 | Prefix rules | Prefixes shift base stats and growths together; no prefix is the pure baseline; rolls lean positive; re-roll at a Camp or through events; enemies roll prefixes by difficulty (Normal: elites and bosses only). | Unstated |
| October 15, 2026 | Camp re-roll | Camp gains a fourth choice: re-roll one unit's prefix. | Rest, Train, Revive |
| October 15, 2026 | Stat list | HP, Might (MGT), Speed, Defense, Resistance, Movement, Constitution. Skill, Luck and Magic cut; Strength renamed Might. | Ten `Godot_FE` stats |
| October 15, 2026 | Magic | Anima, Holy and Dark keep their weapon types, with typical profiles Balance, Nimble and Power. Magic scales with Might. | A separate Magic stat |
| October 15, 2026 | Staff healing | Scales with Might. | Magic (in `Godot_FE`) |
| October 15, 2026 | Avoid | From terrain and effects only; no unit avoid stat, no crit avoid. | Unit avoid and crit avoid |
| October 15, 2026 | Equipment restrictions | None in the MVP; weight against Constitution and traits shape gear choice. | Unstated |
| October 15, 2026 | Prefix budgets | Per tier, matched to `Godot_FE`'s draft rolls: +2 = +5 stats/+35% growths, +1 = +3/+25%, −1 = −2/−10%, −2 = −4/−25%. See unit-roster.md. | Unstated |
| October 15, 2026 | Hit | From the weapon only: weapon Hit ± triangle ± effects − avoid. No unit Hit stat; prefixes may spend budget on Hit at 10 Hit = 1 stat point (to be tuned). | Skill-based hit |
| October 15, 2026 | MVP traits and Stance | One trait per MVP unit, no status effects yet; Stance 1–3 by role. See unit-roster.md. | No traits or Stance values |
| October 15, 2026 | Comparison conditions | While conditions can compare this unit's stats and combat values with its opponent's; ties fail. See effect-triggers.md. | Unstated |
| October 15, 2026 | Prefix list | Twelve first-pass prefixes across tiers +2 to −2, rolled by tier (30% none, 10% +2, 35% +1, 18% −1, 7% −2) then evenly within the tier. See unit-roster.md. | No list |
| October 15, 2026 | Mage Tower | A stub; not in the MVP, which is built around Mercenary. | A second starting faction |
| October 15, 2026 | Experience | Hybrid: mostly shared XP per combat by combat type, plus a small capped personal bonus for actions. | Per-hit and per-defeat tanh formula with XP decay |
| October 15, 2026 | Tiers | Removed. Units are unupgraded or upgraded, like Slay the Spire cards; Camp Train upgrades one. | Tiers and promotions |
| October 15, 2026 | Level cap | None; XP pacing enforces a soft limit and leaves room for endless runs. | Per-tier level caps |
| October 15, 2026 | Levels per run | A typical unit gains 4–6 levels per run; level-ups happen after combat. | Mid-combat level-ups |
| October 15, 2026 | Upgrade content | A "+" trait and a few stat points; some unit types may also gain a weapon type or a movement type. | Promotions |
| October 15, 2026 | Recruit level | New recruits join at the army's average level. | Recruits at level 1 plus padding |
| October 15, 2026 | XP amounts | 100 XP per level; shared 40 / 70 / 100 per standard / key / boss combat; personal bonus +2 hit, +5 defeat, +3 heal or Block, +5 non-combat, capped at 15 per combat. First pass. | Unstated constants |
| October 15, 2026 | Combat MVP | The unit with the most XP-earning actions is the combat's MVP and gets +5 XP above the cap; one MVP per player in co-op. | None |
| October 15, 2026 | MVP ties | A tie goes to the lower-level unit; at equal level, to the one with more personal XP. | Unstated |
| October 15, 2026 | MVP upgrades | All 13 written: standard upgrades give a "+" trait and 3 stat points; Sellsword, Lancer, Thief and Mage get big upgrades (a new weapon or movement type) with 1 stat point. See unit-roster.md. | None |
| October 15, 2026 | Tags and movement | Unit tags (Armored, Mounted, Flier, Terror) and movement types (Default, Heavy, Mobile, Mounted, Flier) carried over with `Godot_FE`'s terrain costs. Tags were `Godot_FE`'s "traits", renamed because traits are now effect text. | Dropped in the first roster pass |
| October 15, 2026 | `Godot_FE` data bugs | Mounted-tagged ground units use Mounted movement; Wooded Knoll costs 3 for Default units. Both fixed, not ported. | `Godot_FE` terrain and unit data |
| October 15, 2026 | Lockpicks | Pouch consumables any unit can carry; no lockpicking tag or unit type. | `Godot_FE`'s Thief tag |
| October 15, 2026 | Campaign map | Port `Godot_FE`'s STS-style generator at 18 floors × 7 columns, 6 non-crossing paths, boss funnel, whole map visible, seeded and saved. | Blank map section; `Godot_FE`'s 15 floors |
| October 15, 2026 | Key combat placement | Two fixed rows (first pass: floors 6 and 12) plus optional weighted extras; at most 4 per path. | `Godot_FE`'s fixed rows (10 per run) |
| October 15, 2026 | Node mix | Typical path: 5 standard, 3 key, 1 boss, 3 camps, 2 treasure, 2 shops, 2 events. | Unstated |
| October 15, 2026 | Co-op route | Players vote; the next node is drawn at random weighted by votes; the host draws. | `Godot_FE` multiplayer notes (vote, host breaks ties) |
| October 15, 2026 | Unknown node | The Event node is the "?" random slot: usually an event, sometimes a standard combat, Shop, Camp or Treasure, rolled on entry with Slay the Spire's rising odds. | Plain Event node |
| October 15, 2026 | Node placement | Fixed rows 1, 6, 9, 12, 17, 18; weighted rolls elsewhere; Slay the Spire's placement rules. First pass. | Unstated |
| October 15, 2026 | Simple magic and staff | Anima (Fire), Holy (Smite), Dark (Shade) and Minor Heal from `Godot_FE` values. | No magic weapon stats |
| October 15, 2026 | Weapon Block | Simple weapons carry no Block; named weapons may. | The source's sword and axe Block timings |
| October 15, 2026 | Equipment and trinkets | `Godot_FE`'s wearable items become Equipment, its charms become Pouch trinkets, effects reduced; Equipment is much stronger than trinkets. See items.md. | `Godot_FE`'s single equipment list |
| October 15, 2026 | Consumables | Every `Godot_FE` consumable stays in the Pouch, stat boosters included. | Unstated |
| October 15, 2026 | Shields, weights, Skill boosters | `Godot_FE`'s 9 shield weapons become shield Equipment (half weight, Stance and Block); Equipment weighs 0–2, heavy armor and shields more; Skill boosters give permanent Hit (5 per old point). First pass. | Shield weapons; no equipment weight; Skill |
| October 16, 2026 | Feast | Camp's Rest becomes Feast: heal 35% and optionally cook one ingredient from the convoy, giving every unit a guaranteed gain on its next level-up. | Rest; growth boosters as Pouch items |
| October 16, 2026 | Ingredients | `Godot_FE`'s growth boosters become ingredients, stored in the convoy; small ones give +1 to a stat (+2 HP), large ones +2 (+4 HP); Hit ones apply at once. | +3% to +20% growth boosters |
| October 16, 2026 | Prefix re-roll | Moved from Camp to a Shop service: once per visit, price rising with each use in a run, like Slay the Spire's card removal (first pass 250 gold, +100 per use). Camp is Feast, Train, Revive. | Camp re-roll choice |
| October 16, 2026 | Re-roll price | ⅓ of the unit's value (type recruit price × prefix value multiplier, ×0.5 to ×1.8), +50% for each further re-roll in the same Shop; resets each Shop. Like Terraria's Goblin Tinkerer. | Flat price rising per run |
| October 16, 2026 | Shop split | Two shop nodes with their own map icons: Armory (weapons, equipment, trinkets, consumables, heirlooms) and Market (recruits, army size, runes, re-rolls). Every path passes through at least one of each. | One Shop node |
| October 16, 2026 | Gold sources | Combat and events reward gold. | Unstated |
| October 16, 2026 | Re-roll outcome | A re-roll can land on a worse prefix or none, never the same prefix. | Unstated |
| October 16, 2026 | Guildhall | The recruit-and-re-roll shop is named the Guildhall. | "Market" |
| October 16, 2026 | Scrapping | No selling. Unwanted items are scrapped for 20% of their buy price (Terraria's sell rate; tune in playtesting): at pickup, as an Armory trade-in, or from the convoy anytime. Treasure items turn into their full gold value on pickup. | Selling convoy items at shops |
| October 16, 2026 | Gold scale | All gold amounts are a tenth of `Godot_FE`'s (Mercenary starts with 100); derived amounts round to the nearest whole gold. | `Godot_FE`'s scale (1000 start) |
| October 16, 2026 | Grades | +25% gold for beating turn par, +25% for losing no units; maps are meant to be short. | `Godot_FE`'s A–D grades (×1.0–2.0) |
| October 16, 2026 | Recruits and army size | Recruits are cheap so permadeath losses can be replaced; army size is never sold in shops. | Army size upgrades in the shop |
| October 16, 2026 | Economy | First pass: start 100, standard 30, key 60, grade bonuses +25% each; prices from `Godot_FE` cut tenfold; typical run earns about 610 and ends with about 150. Must be retuned in playtesting. | Unstated |
| October 16, 2026 | Map source | Hand-authored layouts in pools per combat type, with enemies, positions and loot randomized per run. | `Godot_FE` level pools |
| October 16, 2026 | Objectives | Standard: Rout or Defeat the Leader. Key: mini-boss, Seize, Survive or Defend. Boss: defeat the boss, whose mechanic changes the map. | Defeat all, boss, survive (`Godot_FE`) |
| October 16, 2026 | Map size | Fire Emblem Heroes scale (standard 8×6 to 10×8, key about 12×10); boss maps larger and longer. | `Godot_FE` level sizes |
| October 16, 2026 | Interactables | Chests and doors (lockpicks, levers), houses, reinforcement points, breakables. | `Godot_FE` chests, doors, levers, search points, breakables |
| October 16, 2026 | Multiplayer combat | MVP: parallel maps (each player fights their own copy of the combat). Target: hybrid, with key and boss combats shared. Needs one combat state per player in the save. | One shared battle |
| October 17, 2026 | One player loses | Winners can reinforce a teammate's map; players can retreat; the team wins if anyone wins; in co-op a fallen commander is downed, not killed, and the run ends only if every commander falls. | Undecided |
| October 17, 2026 | Whom to reinforce | The sender chooses one map, guided by map status and call-for-aid flags; no splitting; several senders can help one map. | Undecided |
