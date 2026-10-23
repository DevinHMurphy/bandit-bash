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
- The army is led by a **commander**. If the commander falls in solo, the run is lost; in co-op it
  returns after the combat at critical health. Every other unit has permadeath; the only way back is
  a rare event. The whole army deploys in every combat.
- Army size works like card draw and mana in Slay the Spire: more units mean more actions and
  more storage. The Mercenary starts at 4 (full); the ceiling is 8, reached only in edge cases.
- Builds are shaped by **heirlooms** (army-wide passives), weapon **profiles** (Nimble, Balance,
  Power) and a three-slot unit inventory (Weapon, Equipment, Pouch).
- **MVP goal:** one complete, playable run, solo and co-op. Meta progression and other between-run
  systems wait until that works.
- Combat adds **Block** (damage absorbed before HP) and **Stance** (hits of margin before a unit is
  **Exposed** and can be crit) to Fire Emblem–style exchanges.

## Design pillars

**Gameplay goal:** an experience that lets the player make high-stakes tactical decisions in short
sessions, with an army they care about and can lose.

| Pillar | Intent |
|--------|--------|
| Reduce player cognitive burden | Playtesters found the old game's options and information tiring. Fewer, clearer decisions. |
| Decrease run length | Shorter runs make losses less punishing and encourage risk-taking. **Target: a typical solo run takes 60–75 minutes.** `Godot_FE` runs took 4–8 hours, and players who lost didn't want to start again. If runs come in long, cut node count or combat length before adding content. |
| Incentivize proactive players | Reward calculated, aggressive trades and map control over slow, safe turtling. |
| Remove "hurry up and wait" decisions | No tactic should be "get into position, then pass turns"; no map should be won by passing turns; and in co-op no player should sit idle for long. |

## Run structure

**Start of a run.** The player picks a faction and commander, then a starting heirloom.

| Faction | Commander unit type | Max army size | Funds | Starting army |
|---------|---------------------|---------------|-------|---------------|
| Mercenary | Drengr | 4 | 100 G | Hakkapel, Archer, Battle Medic |
| Mage Tower (stub, not in the MVP) | Mage Knight | 4 | 250 G | Tower Guard, rest unspecified |

- The faction gates faction-locked heirlooms, weapons and unit types.
- Each commander carries a unique **Commander Heirloom** (e.g. the Drengr's Iron Heart: every 7th
  attack by the army each combat heals the attacker for its damage). Commanders and factions set the
  base army size. The Drengr is defined in [unit-roster.md](unit-roster.md#commander).
- Design intent: the commander's unit type is good and worth building around but doesn't win a run
  alone. Starting units and starting equipment are deliberately weak "strikes and defends", there
  to be replaced.
- **Starting heirlooms** are only offered at run start and add variety without forcing a build. The
  player picks 1 of 3, drawn from a pool of 7 by the run seed, e.g. Abundance (+1 max army size and
  a recruit), Ancestral Weapon (1 of 3 Rare weapons the army can use) and Tactician's Manual
  (doubles the weapon profile triangle). The pool is in [heirlooms.md](heirlooms.md#starting-heirlooms).

**Difficulty and scaling.** Challenge rises in three steps through a run, like Balatro's Antes.
Steps change at the fixed key-combat rows, so the jump is visible on the map.

| Step | Floors | Standard combat enemies | Enemy level (Normal) |
|------|--------|-------------------------|----------------------|
| 1 | 1–5 | 3 | 1 |
| 2 | 6–11 | 4 | 3 |
| 3 | 12–17 | 5 | 5 |
| Boss | 18 | — | 8 (the boss) |

- Enemy levels track the army's expected average level (the starting army is level 1). Key combat
  enemies are +1 level; leaders and mini-bosses +2.
- Enemy count never scales with the player's army size: army size is the player's power, like
  energy in Slay the Spire.
- **Enemy growth is deterministic:** at level L, each stat is its base plus growth % × (L − 1),
  rounded down. The same enemy is identical in every run and on every co-op copy.
- **Two difficulties**, chosen at run start (by the host in co-op) and saved with the run:
  - **Normal:** only elites (leaders, mini-bosses) and the boss roll [prefixes](unit-roster.md#prefixes).
  - **Hard:** every enemy rolls a prefix (with the recruit odds), every enemy is +1 level, and every
    map's turn par is 1 lower, so the darkness arrives a turn earlier and the speed bonus needs one
    turn less.

**Campaign nodes.**

| Node | Purpose | Targets |
|------|---------|---------|
| Standard combat | Small skirmish; main source of XP. Rewards gold and a pick of 1 of 3 items, or skip (items rolled Common 60 / Uncommon 30 / Rare 10; weapons weighted to the army's weapon types). | 2–5 min, 3–5 enemies (always < 10, about the player's count), no bosses |
| Key combat | Small Fire Emblem–style map with mini-bosses. Rewards gold, the standard combat's item pick, and one random heirloom (rolled Common 50 / Uncommon 33 / Rare 17). | 5–10 min, 2–4 per run |
| Boss combat | Large map; the boss directly affects the map. | — |
| Armory (Shop) | Spend gold on weapons, equipment, trinkets, consumables and heirlooms. Items are bought straight onto a unit, with a before/after comparison; the item it replaces is either **traded in** (its [scrap value](items.md#scrapping) comes off the price) or sent to the convoy. No sell screen. Has its own map icon. Stock per visit: 3 weapons (the army's weapon types), 2 equipment, 1 trinket, 2 consumables (items rolled Common 50 / Uncommon 35 / Rare 15) and 2 heirlooms (one from the pool, rolled 50 / 33 / 17, and one Shop tier). | — |
| Guildhall (Shop) | Spend gold on recruits (3 per visit; cheap, so a player can replace units lost to permadeath), runes (2 per visit) and prefix **re-rolls**. A re-roll is priced from the unit's value, like Terraria's Goblin Tinkerer, and rises with each re-roll in the same Guildhall. Has its own map icon. | — |
| Unknown (`?`) | The random slot. Usually an event: a narrative choice with trade-offs (heirlooms, unit upgrades, prefix re-rolls, gold, weapons, unique units, or a rare **revive** of one fallen unit, in exchange for damage, curses or a surprise combat). It can instead turn out to be a standard combat, Shop or Treasure; see the campaign map below. | — |
| Camp | Choose one: **Feast** (heal 35% of each unit's HP, and optionally cook one [ingredient](items.md#consumables) from the convoy to give every unit in the army a guaranteed gain on its next level-up; in co-op the heal reaches every player's units and stacks, while the ingredient stays with the cook's army), or **Train** (upgrade one unit, like a Slay the Spire card; normally once per unit). In co-op, each player chooses for themselves. There is no Revive at a Camp. Not meant to be the main path. | 2–4 per 18-node run, 5 at most |
| Treasure | Guaranteed non-combat chest with a heirloom; size sets rarity (small Common 50%, medium Uncommon 33%, large Rare 17%; see [heirlooms.md](heirlooms.md)); sometimes gold or loot. | At least 2 on every path |

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

**Events.** An Unknown node that turns out to be an event shows a short scene with 2–3 trade-off
options, Slay the Spire–style. First pass in [events.md](events.md): 13 events, eight reworked from
`Godot_FE/` and five new, including the **revive shrine** (revive one fallen unit at critical
health, or take a rare heirloom; it appears only once a unit has fallen). Events can charge
**curses**: permanent negative heirlooms in three tiers (minor, major, severe) matched to the
reward, always named before the player chooses, and never touching gold. In co-op, most events are
each player's own choice; team events, including any with a combat option, are voted like the route.

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
| Common weapon | 40 |
| Uncommon weapon | 60 |
| Rare weapon | 150 (250 for `Godot_FE`'s Mythical weapons) |
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
- Every path passes through at least 2 Treasures and 2–5 Camps (the fixed rows on floors 9 and 17
  count).

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
| Event | The rest | — |

Combat, Shop and Treasure use Slay the Spire's values as remembered from its decompiled code (the
wikis don't list them). As in Slay the Spire, an Unknown never becomes a Camp: Camps are a visible
routing choice.

## Army

- A roster of distinct units, each with its own weapons, equipment, inventory, stats and profile.
  Leveled through combat; classic permadeath.
- Commander stat spreads and names are fixed and persist across runs. Every other non-event unit is
  randomized.
- Max army size starts from the faction (Mercenary: 4) and grows only through the Abundance starting
  heirloom, the Rare heirloom Muster Roll and event options, up to a hard ceiling of 8. It is never
  sold in shops: like max energy in Slay the Spire, it adds actions every turn, so it is very strong
  and allowed, but never simply bought. Meta progression may add sources after the MVP.
- **Recruiting past the max** means replacing an existing unit; the replaced unit's inventory goes
  to the convoy.
- **Permadeath.** A unit that falls is gone for good, in solo or co-op: there is no retreat, Camps
  can't revive, and nothing gives an extra life. The one way back is the **revive shrine**, a
  possible Unknown (`?`) event where reviving one fallen unit costs the rare heirloom offered
  instead (see Events under [Run structure](#run-structure)). Its items can still be taken in army
  management and battle prep. The commander is the exception: its fall ends a solo run, and in
  co-op it returns at critical health (see [Combat maps](#combat-maps)). Losses compound (a weaker
  army is likelier to lose again); that negative feedback loop is accepted as part of the design.
- **HP carries over** between combats. There is no heal after a win (`Godot_FE`'s `heal_on_win` is
  dropped); HP comes back through Feasts, heal staves, potions, healing terrain and events. Block,
  per-map uses and durability reset every combat.

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

**Standout.** The unit with the most XP-earning actions in a combat is named the combat's
**Standout** on the results screen and gets +5 XP on top of the cap. A tie goes to the lower-level
unit, nudging the army toward even levels; if they are also level, to the one that earned more
personal XP. It drives the player's relationship with their units home without letting one unit
run away: armies are small and fights are quick, so every unit acts and the Standout should
rotate. In co-op, each player has their own Standout.

How it plays out: a unit that only survives ends a run at about 5 levels; one that hits the cap
and is the Standout every combat reaches about 6.8, the extreme. Recruits join at the army's average level,
rounded down so a recruit is never ahead of the army.

**Upgrades replace tiers.** Units have no tiers and never promote. A unit is either unupgraded or
upgraded, like Slay the Spire cards: a run starts with average units, replaces them with better
ones, and upgrades the good ones along the way. A Camp's Train choice upgrades a unit, normally once
per unit. Commanders are never upgraded. An upgrade improves the unit's trait to a "+" version (e.g. Volley+) and adds a few stat
points. Some unit types may also gain something bigger, Fire Emblem promotion style: access to
another weapon type, or a new movement type (e.g. becoming mounted). A unit that gains a weapon type
also gains **Sidearm**: any unit can stow a weapon in its Pouch and swap it in as its action, but
Sidearm makes the swap free once per turn, so it can change its triangle matchup mid-combat.

**Inventory.** Three slots. There is no off-hand and no main-hand/two-handed distinction.

| Slot | Holds |
|------|-------|
| Weapon | The unit's weapon or tool. Its weight counts toward Attack Speed. |
| Equipment | One piece of passive gear. Changing it in combat costs the unit's action; set it in army management and prep. Its weight counts toward Attack Speed. |
| Pouch | One trinket or one consumable. Bringing a stat-boosting trinket instead of a potion is a deliberate trade, and the single slot limits potion spam. Any unit can stow a second weapon here instead; swapping it in costs the unit's action, or is free with [Sidearm](unit-roster.md#upgrades). Stowing should be an intentional choice, not the default. |

There is no stash. Reserve items live in the convoy and are swapped in army management and prep.
Some special units can access the convoy; which ones, and how, is defined with unit types.

Future idea, not for v0: tag weapons as one- or two-handed and let random generation combine two
one-handed weapons into a single item.

**Unit types and generation** are in [unit-roster.md](unit-roster.md): the 14-unit MVP roster,
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
| Lance | 7 | 1 | Balance | 1 | 80 | 0 | 3 | 12 | Solid in every situation |
| Bow | 6 | 1 | None | 2–3 | 100 | 0 | 3 | 5 | Damage from range, little defense |
| Gauntlets | 2 | 2 | None | 1 | 100 | 0 | 2 | 1 | Many fast hits to break Stance |
| Dagger | 2 | 1 | Nimble | 1–2 | 100 | 0 | 5 | 3 | Hybrid; punishes Exposed foes |
| Anima (Fire) | 5 | 1 | Balance | 1–2 | 80 | 0 | 3 | 1 | Steady magic (`Godot_FE` Fire) |
| Holy (Smite) | 4 | 1 | Nimble | 1–2 | 100 | 0 | 3 | 6 | Reliable magic (`Godot_FE` Smite) |
| Dark (Shade) | 7 | 1 | Power | 1–2 | 80 | 0 | 3 | 8 | Heavy magic (`Godot_FE` Shade) |
| Shelter (staff) | Target ally gains 3 + Might Block | — | None | 1 | — | — | — | 0 | Unlimited uses: the everyday support tool (new) |

The source's equip-type column (Versatile, Main Hand, TwoHanded, Two) is dropped with the off-hand.
Simple weapons carry no Block effects; named weapons may. Magic deals Magic damage, so it hits
Resistance. Every MVP weapon has a scaling modifier of 1 (Might adds one-for-one), and every bow,
the Simple Bow included, is effective against Fliers, as in `Godot_FE`.

**Item rarity** has five tiers, shared by weapons, equipment and Pouch items: **Basic** (starting
gear and recruits' gear only, never loot or stock), **Common**, **Uncommon**, **Rare** and
**Legendary** (near-unbalanced, found only in about 3% of runs). Higher-tier weapons gain damage
and weight but never lose Hit below their type's Simple weapon, since accuracy comes only from the
weapon. The MVP weapon list (62 weapons and staves) is in [weapons.md](weapons.md).

- A weapon's profile follows its flavor, not its type: a Zweihander is Power, a long sword Nimble,
  a claymore Balance. Every weapon card and the combat forecast show the exact profile. Most types
  have a typical profile; daggers have none, so each dagger is chosen to fill a triangle gap.
- **Magic** comes in three weapon types, each with a typical profile: Anima (Balance), Holy, the
  old Light (Nimble), and Dark (Power). A specific tome can differ, as with daggers. Magic scales
  with Might and deals Magic damage, mitigated by Resistance.
- **Staves** come in two kinds, both scaling with Might. **Block staves** have unlimited uses: the
  Basic staff, Shelter, gives 3 + Might Block. **Heal staves** have limited uses per map: Minor Heal
  (Common) heals 5 + Might, 3 uses per map. Block is the everyday tool; healing is precious. Other
  support weapons (whips, instruments, banners) and misc. weapons have headings only.
- **Durability** exists only on some weapons and is per map (e.g. heal staves). It refreshes at the
  start of every combat and forces prioritization rather than one optimal setup.
- **Equipment** is build-defining, one piece per unit, and can't be swapped mid-combat. Categories:
  quivers (ranged offense), coatings (bonuses against Exposed foes), shields
  (Stance and Block), armor, cloaks, bands, uniques. Equipment is much stronger than a Pouch
  trinket. Items, budgets and `Godot_FE` conversions are in [items.md](items.md).
  Equipment has no hard unit restrictions in the MVP: weight against Constitution limits heavy
  gear, and traits can reward specific gear. Add restriction tags only if playtesting shows a role
  needs protecting.
- **Pouch items** are consumables (limited uses: heal, boost a stat, open doors and chests) or
  trinkets (small passive bonuses to the holder). A unit carries one or the other.
  Every `Godot_FE` consumable carries over: stat boosters go in the Pouch, and the old growth
  boosters become ingredients, kept in the convoy and cooked at a Camp Feast (see [items.md](items.md)).
  Lockpicks are Pouch consumables any unit can carry; no unit type picks locks innately, so going
  after loot costs a unit its potion or trinket.
  Pouch items are weightless. An item that slows its holder does so through an effect that
  subtracts Attack Speed (the `Effect.weight` term), not through a weight value.

## Combat

**Action economy.** Each unit, on its Unit Turn, may **move**, then take **one action**, then it is
done. This is classic Fire Emblem: one decision per unit, and every utility action costs an attack.

| Action | Notes |
|--------|-------|
| Attack | Starts a combat exchange |
| Use a staff | Heal an ally (heal staff) or give it Block (Block staff) |
| Shove | See [Shove](#combat) below |
| Use a map object | Light or douse a Brazier, pull a lever, use a passage ([map-objects.md](map-objects.md)) |
| Open or search | A chest or door (with a lockpick), or a searchable |
| Use a Pouch item | On itself **or an adjacent ally**: a potion, stat booster or other consumable |
| Swap equipment | Swap the Weapon with a weapon stowed in the Pouch (any unit; free with [Sidearm](unit-roster.md#upgrades)), or take gear from the convoy (only with a trait that grants convoy access) |
| Wait | Ends the unit's turn without acting |

- **Free, outside the economy:** runes, and closing a reinforcement point by ending a turn on it.
- **No moving after acting**, unless a trait says so (e.g. the Freewing's Skirmisher). Movement
  can't be split around an action.
- **No trading in combat.** Gear moves only in army management and battle prep. Using a Pouch item
  on an adjacent ally replaces Fire Emblem's "trade a potion over" without a trading screen.

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

**Status effects (after the MVP).** None ship in the MVP: debuffs work through Stance and Block,
and no MVP trait, enemy or item applies a status. When they arrive, they stack by duration, by
effect weight, or both. Examples: Bleed (weight;
cleansed after it deals damage at Phase End), Garrison (duration; while it lasts, a refresh keeps
leftover Block instead of clearing it), Poison (both; deals its stack count each
Phase End, then loses a stack).

**Shove (first pass).** Carried over from `Godot_FE/`: a unit pushes an adjacent unit, ally or enemy,
directly away from itself by its **Shove distance**: 1 tile by default, more with some traits. The
pushed unit moves tile by tile and stops early at anything in the way (below). It makes [map objects](map-objects.md), the darkness and
chokepoints tactical: push a foe next to a powder keg, out of a chokepoint, or off a healing tile.
Fairness rules stop it from becoming a spam tool:

| Rule | What it prevents |
|------|------------------|
| **It costs the unit's action** for the turn (it can move first, but not also attack) | Free repeated shoving; every shove is a lost attack. `Godot_FE` marked Shove as neither a major nor a minor action, effectively free |
| **Only onto tiles the target could legally stand on.** It never enters pits, walls, water or other impassable terrain (`Godot_FE`'s rule); it stops on the last legal tile | Instant kills by pit or water |
| **Only Exposed foes can be shoved** (Stance broken); there is no weight check. A willing ally can always be shoved | Shoving a unit off key terrain or a chokepoint on the first move: its Stance has to be broken first, so a shove is earned. It also gives breaking Stance a second payoff |
| **Once per phase:** a unit can be shoved at most once per phase | Several units chain-pushing one enemy across the map |
| **Not an attack:** no hit roll, no counter, no Stance loss; the only damage comes from bumps and spikes (below) | Shove becoming a free damage source |

What stays possible, on purpose:

- **Into the darkness:** a shoved unit only takes darkness damage if it is still there at the end of
  its own phase, so it gets a turn to step out. Shoving buys tempo, not a kill.
- **Next to an object:** shoving a foe beside a powder keg and then blowing it takes two units'
  actions, a fair combo.
- **Into another unit (bump):** a shoved unit that would move into a tile occupied by another unit,
  friend or foe, stops, and **both units take 2 damage** (first pass). That is the general bump.
- **Into spikes:** a **spiked wall** is a wall tile no unit can enter; a unit shoved toward one stops
  and takes **4 damage** (first pass). Any other wall or impassable tile simply stops the shove,
  with no damage.
- Bump and spike damage use the splash rules: no hit roll, no Mitigation, no crit, no Stance loss;
  Block absorbs it.
- **Across slick tiles:** **spilled oil** is slick terrain. A unit shoved onto oil keeps sliding in
  the same direction until it leaves the oil or is stopped (by a wall, a unit, an object or
  impassable terrain); stopped by a unit or a spiked wall, it takes the bump or spike damage.
  Walking across oil is normal movement, so it adds no rule to everyday play. The whole slide counts
  as the one shove that unit can receive this phase. Later, a keg explosion could set oil alight.
- **Allies too:** a unit can shove a teammate out of danger or into position at any time; the
  Exposed rule applies only to foes.
- **Enemies shove:** the ruthless AI shoves player units off chokepoints, out of brazier light, or
  next to kegs; its intent shows the shove.

Bosses and some elites can have **Unshovable** as a trait.

## Combat maps

**Source.** Maps are hand-authored layouts in a pool per combat type (standard, key, boss), as in
`Godot_FE/`. Each run randomizes what goes on them: enemy groups, spawn positions and loot, from
the run's seeded stream. `Godot_FE/` already supported random unit groups and position variance.

**Size.** Fire Emblem Heroes scale, the vision's reference: standard maps about 8×6 to 10×8, key
maps about 12×10. Boss maps are larger and longer than both. Small maps keep standard combats in
the 2–5 minute target with the whole army (4–6 units) deployed against 3–5 enemies. Every map
authors at least 8 player deployment tiles, the army-size ceiling.

**Objectives by combat type.**

| Combat | Objectives |
|--------|------------|
| Standard | Rout (defeat every enemy), or Defeat the Leader (one marked enemy) for very short fights |
| Key | Defeat the mini-boss, Seize a tile, Survive N turns, or Defend a tile |
| Boss | Defeat the boss; the boss has a mechanic that changes the map |

`Godot_FE/` declared Seize and Defend but never made them work; they are built properly here. Each
map has an authored turn par for the [grade bonus](#run-structure).

- **Setting par:** par = the turns a clean, aggressive clear takes in testing, plus 1. First targets
  to measure: standard 4–6, key 7–10, boss 10–14. Hard lowers every par by 1.
- **Survive and Defend** maps end on a turn count, but defeating every enemy on the map with every
  reinforcement point closed ends them early and earns the speed bonus. Waiting it out still wins;
  attacking wins faster and pays more.

**Interactables (MVP).**

| Interactable | What it does |
|--------------|--------------|
| Chest | Opened with a lockpick (a Pouch consumable); holds one item (weapon, equipment or trinket) rolled Common 50 / Uncommon 35 / Rare 15 from the run's seed |
| Door | Opened with a lockpick, or by a lever that opens a linked group of doors (`Godot_FE/`) |
| House | A unit visits it for 15–25 gold or one consumable (potion, lockpick or stat booster), plus the personal-XP bonus; the vision's "looting houses". Never an heirloom, so the heirloom count per run stays predictable |
| Reinforcement point | Enemy reinforcements arrive from marked points on a timer; a unit closes a point by ending its turn on it, earning the personal-XP bonus; the vision's "closing reinforcement routes" |
| Breakable | Walls and debris a unit can destroy to open a new path (`Godot_FE/`'s Demolish) |

**Map objects** are neutral: any unit, player or enemy, can use them to change the battlefield, and
they are essential to combat. They include the interactables above, carried over from
`Godot_FE/`'s entities (chests, doors and levers, searchables such as houses and shelves, debris,
passages), plus new ones: powder kegs and braziers (the ballista and war drum wait until after the
MVP). Details are in
[map-objects.md](map-objects.md). Objects are separate from terrain.

**Terrain** is carried over from `Godot_FE/` ([unit-roster.md](unit-roster.md#movement-and-tags)).
MVP maps use a core subset: plain, road, forest, thicket, mountain, river, bridge, house, fort,
wall, door and chest tiles. Terrain is the only source of avoid, so every map needs cover for both
sides.

**The darkness** is the turn-par pressure system ([the-darkness.md](the-darkness.md)). At turn par,
darkness flows into the map from authored sources toward a drain set by the objective, in waves that
deepen tiles from Dusk to Gloom to Abyss. A unit that ends its side's phase on a dark tile takes
damage (MVP: 10% / 25% / 50% of max HP by layer, not an attack, so Block, Mitigation and Stance
don't apply); passing through is free. No unit is immune, bosses included. It eventually floods the whole
map, so every map ends, but it never ends a map early: like fatigue in Hearthstone, outlasting it
can be a plan. Players who beat par (and earn the grade bonus) never see it. Survive and Defend maps
have none. Locked doors block it; breakable walls erode and break. The damage model is a first
pass that must be playtested.

**Multiplayer maps.** The MVP uses **parallel maps**: each player fights their own copy of the same
combat (same map, same seed, their own army) at the same time, and the combat ends when everyone has
finished. Every map is authored once at solo size and keeps its solo balance. The target after the
MVP is a **hybrid**: standard combats stay parallel, while key and boss combats become shared
battles. Details are in [multiplayer-combat-options.md](multiplayer-combat-options.md).

When players finish their maps differently:

- **Reinforce.** A player who wins their map can send any of their surviving units, at their
  current HP and including the commander, onto a teammate's map that is still being fought. They
  arrive at the start of that map's next player phase, controlled by their owner, on dry tiles next
  to the receiving player's commander (the nearest dry tiles if those are taken, then the
  darkness's fallback). Sent units can die, so helping is a real risk; a sent commander that falls
  counts toward "every commander fell" as normal. Sent units earn personal bonus XP there, toward
  the same per-combat cap, but not shared XP a second time; the Standout stays on each player's own map. With 3–4 players, the sender picks which map to help, guided by
  each map's status (turn, units and enemies left) and any **call for aid** a struggling player has
  raised. All of a sender's units go to one map; several senders can help the same map; units sent
  to a map that ends before they arrive return unharmed.
- **The team wins if anyone wins.** A player who fails their map's objective (e.g. a Defend tile is
  taken) gets no gold, XP or Standout for it, and their fallen units stay dead.
- **Permadeath as in solo.** No retreat, and permadeath applies to every unit.
- **A fallen commander returns at critical health (co-op only).** That player's map is lost (no
  gold, XP or Standout), their fallen units stay dead, and after the combat their commander comes back at
  critical health (first pass: 10% of max HP, at least 1). There is no other cost. The run is lost
  only if every player's commander falls in the same combat. In solo, a fallen commander still ends
  the run.
- **Each parallel map runs on its own turns.** Players never wait on each other's phases; each map
  has its own turn counter, par and darkness.
- **Everyone stays involved** (the "hurry up and wait" pillar):
  - Any player can use their **runes on a teammate's map** during that map's player phase, whether
    or not their own map is finished.
  - Any player can **spectate** any teammate's map; a player whose map is lost spectates until the
    combat ends.
  - **Game speed** (animation speed) is a lobby setting chosen by the host, the same for everyone,
    so clients never desync.
  - **Fast-forward:** the players with units on a map can vote to fast-forward its enemy phase (on a
    map with one player, that player decides). As in Fire Emblem, the phase still plays out, only
    faster, and fast-forward pauses for key moments: boss combats and any player unit's death.

**Co-op ownership.** Everything is per player unless stated: gold, convoy, runes, heirlooms, the
combat item pick, Treasure and key-combat heirlooms. The exception is **shops**: the team shares one
Armory and one Guildhall stock, the solo stock plus 1 of each category per extra player (e.g. a
two-player Armory has 4 weapons, 3 equipment, 2 trinkets, 3 consumables and 3 heirlooms). The host
processes purchases in the order they arrive: the first confirmed purchase gets the item. If a
**unique** heirloom is offered to two players at once, the first to claim it gets it and the
other's offer is replaced by a different heirloom of the same rarity.

## Enemies

Partly designed. Already decided elsewhere in this file:

- Standard combats field 3–5 enemies, aiming for about the player's number; key combats add a
  mini-boss; boss combats a boss whose mechanic changes the map ([Combat maps](#combat-maps)).
- Enemy groups, spawn positions and loot are randomized per run on authored maps.
- Enemies roll [prefixes](unit-roster.md#prefixes) by difficulty: on Normal, only elites and bosses;
  on Hard, every enemy. Levels by step are under [Run structure](#run-structure).
- Enemy reinforcements arrive from reinforcement points that players can close.
- When [the darkness](the-darkness.md) arrives, enemies turn aggressive, reinforcements stop, and
  enemies follow every darkness rule; no enemy is immune.
- The Terror tag is reserved for monstrous and undead enemies.

### Decided so far

- **Every enemy attack has a profile.** Whatever form enemy attacks take, each one carries a weapon
  profile (Nimble, Balance, Power or None), a damage type and a range, so enemies take part in the
  Weapon Profile Triangle, effectiveness and the damage stages exactly as player units do.
  Otherwise those systems would be useless against half the units on the map. The only exceptions
  are deliberate: a specific enemy whose gimmick is to break this rule (e.g. a profile-less horror),
  written into that enemy's design.
- **Scaling: levels and growths.** Enemies have levels and growth rates, which also suits endless
  runs later. Unlike player units, they grow by average growths, not rolls (see
  [Run structure](#run-structure)).
- **Factions:** enemies belong to their own factions, separate from the player's. Faction themes
  are flavor, decided later. A later event could let the player recruit an enemy unit type.

### Bosses

Bosses get large gimmicks and effects, in the spirit of Slay the Spire's bosses and Balatro's boss
blinds, on top of the map mechanic every boss combat has. The MVP has **1 boss**, the **Powder
Baron** (an elite Brute that holds the throne and throws fused powder kegs every 2nd enemy phase),
and **4 mini-bosses** (Brigand Captain, Bloodhound, Hex Matron, Iron Wall), one per key combat,
drawn by the seed without repeats. All are elites on the normal classes; details in
[enemy-roster.md](enemy-roster.md#mini-bosses-and-the-boss).

### Enemy intentions

Both layers, Fire Emblem's and Slay the Spire's:

- **Danger zone:** every tile an enemy could attack next turn, as in Fire Emblem.
- **Intent icons:** each enemy shows its plan for its next turn as an icon (attack, guard, buff,
  advance) plus its target rule (e.g. "goes for the lowest HP", "guards the throne"), as in Slay the
  Spire. Intents describe behavior, not exact committed tiles: hit rolls and the player's moves can
  still change the outcome. When the darkness arrives, intents switch to aggressive.

Not chosen: Into the Breach–style committed actions (exact tiles and damage), which need
deterministic hits and repositioning tools this game doesn't have.

**Ruthless AI.** Enemies play to kill: an enemy that can defeat a player unit this turn does so
ahead of its normal target rule, and friendly fire never stops it. Some enemy traits are
**side-agnostic** ("friend or foe": auras, splash, Stance stripping), so a player who reads the
intents and danger zone can turn enemy tools against their own pack; that is meant to make
outplaying the AI feel smart. Details are in [enemy-roster.md](enemy-roster.md#ruthless-ai).

### Enemy unit types

**Model 1: separate classes on the same combat rules.** Enemies get their own classes, separate from
the player's unit types, but built the same way and fighting by exactly the same rules.

- **Data:** base stats and growths (HP, MGT, SPD, DEF, RES, MOV, CON), movement type, tags, Stance,
  a trait in effect text, and a **weapon** that sets its profile, damage type, range, Hit, crit and
  weight. Enemy-only weapons can exist alongside the player's.
- **Combat:** identical to player units: the same forecast, damage stages, Attack Speed, Block,
  Stance, Parry, effects and darkness. Player knowledge transfers: an enemy with an axe is an axe.
- **Behavior:** each class has an AI behavior (aggressive, guard, support, skirmisher) that sets its
  intent icon and target rule.
- **Spice:** enemies stand out through what sits on top of the shared rules:
  - **Special traits:** enemy-only effect text, e.g. "Pack: +2 damage per adjacent ally", "Thief:
    flees once it has stolen an item".
  - **Signature moves:** a scripted special on a telegraphed cooldown, shown as the enemy's intent,
    e.g. "every 3rd turn: Rally, +2 Block to adjacent allies". Mostly for elites and mini-bosses.
  - **Gimmicks:** a few unique enemies may break a core rule on purpose (see the profile rule
    above).
- **Why:** one rules engine; levels and growths work unchanged; recruiting an enemy type later needs
  almost no conversion. Enemies don't drop loot of their own in the MVP; loot comes from rewards,
  chests, searchables and shops. The one exception is stolen loot: Cutthroats, the only enemies
  that loot, drop what they took when defeated.

Not chosen: **Model 2, fully separate** (a stat block plus a scripted move rotation, Slay the
Spire–style): more varied everyday enemies, but a second rule set to build and balance, and an
awkward fit with levels and growths.

The MVP enemy classes are in [enemy-roster.md](enemy-roster.md): 10 classes in one working
faction, designed to fight in packs (healers, buffers, debuffers, tanks and strikers covering each
other). Faction themes and later factions are still to design.

## Run-wide resources

- **Runes:** single-use abilities used on the player turn, outside the action economy. They have
  their own inventory of **3 slots**, not tied to a unit; gaining a rune with all slots full means
  discarding one. A rune targets any valid unit or object anywhere on the map. They come from the
  Guildhall (30 gold), events and book shelves (heirlooms and units may grant them later).
  Useful but never required: combats are balanced as if no rune is used. The MVP pool of 7 is in
  [items.md](items.md#runes).
- **Convoy:** shared storage, 1 slot per max army size, hard-capped. Loot decisions happen at pickup,
  and its small size prevents hoarding. Removing a unit from the army adds temporary space. There
  is no selling: unwanted items are [scrapped](items.md#scrapping) for gold, at pickup, as a trade-in
  at the Armory, or from the convoy at any time in army management.
- **Heirlooms** (the source also calls them relics): army-wide passives in one shared collection,
  with no per-unit assignment. Gained about 1 per 2–3 nodes (6–9 per run), with no cap. Tiers are
  Common, Uncommon and Rare, plus a Shop tier sold only at the Armory; the pool is in
  [heirlooms.md](heirlooms.md). Kinds:
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
| Extra strikes | At AS gaps of 4, 6, 8, … (its system doc also lists the cumulative gaps as 5, 11, 19, i.e. "more than"; check the code when porting) | Bonus turns at gaps of 4 or more, 10 or more and 18 or more, capped at 3 |
| XP | Per hit and per defeat, linear formula with tier multiplier; clamps 1–25 / 2–100 | Mostly shared per combat, plus a small capped personal bonus for actions |
| Tiers and levels | Tiers 1, 2 and 4 with promotions; level caps per tier | No tiers: units are upgraded or unupgraded; no level cap |
| Durability | Per use; weapons break | Only some weapons, per map |
| Campaign nodes | Battle, Key battle, Event, Treasure, Recruitment, Boss (Shop and Elite were placeholders) | Standard, Key and Boss combat; Armory and Guildhall shops (the Guildhall sells units); Unknown ("?" random slot); Camp; Treasure. No Recruitment node |
| Death | Graveyard: revive for gold | Permadeath; a rare revive event is the only way back; a fallen commander ends a solo run, or returns at critical health in co-op |
| Run-wide passives | None | Heirlooms and runes |
| Stats | HP, Strength, Magic, Skill, Speed, Luck, Defense, Resistance, Movement, Constitution | HP, Might, Speed, Defense, Resistance, Movement, Constitution |
| Kept | 2RN hit rolls, terrain avoid, effectiveness ×3, commander death loses the run, permadeath | — |

## Open and unfinished

Updated October 23, 2026, after the pre-implementation design review. Nothing here blocks building
the MVP. Ask before building on anything under **Still open**; everything under **Tune in
playtesting** is a first pass that is safe to build as written.

**Still open**

- **Enemies:** the Brigands' real name and theme (flavor), and later factions
  ([enemy-roster.md](enemy-roster.md)).
- **Events:** more team events, curses and events once the MVP pool has been played
  ([events.md](events.md)).
- **Multiplayer:** the save change to one battle state per player (parallel maps run on their own
  turns); light links beyond using runes on a teammate's map; how two players deploy onto one map
  in later shared battles ([multiplayer-combat-options.md](multiplayer-combat-options.md)).
- **Map objects:** the rest of the second pass in [map-objects.md](map-objects.md) is unreviewed.
- **Items:** each equipment piece and trinket still needs a rarity assigned
  ([items.md](items.md)); stronger staves for higher rarities ([weapons.md](weapons.md)).
- **Map content:** each map's turn par value and reinforcement timers, set when maps are authored.

**Tune in playtesting**

- **The darkness:** the damage model (the MVP ships percent of max HP, not an attack) and its values
  on small maps ([the-darkness.md](the-darkness.md)).
- **Economy:** every income, price and the 20% scrap value.
- **Campaign map:** weights, placement rules and Unknown odds.
- **Experience:** the first-pass XP amounts.
- **Units and enemies:** prefix list and odds, the Lancer's growths, and every unit and enemy stat
  (carried over from `Godot_FE`, not yet rebalanced).
- **Content values:** heirlooms, weapons, items, runes, events, curses, mini-bosses and the Powder
  Baron.
- **Watch list:** turtling in Block formations (Block lasts through the enemy phase); Constitution
  against weapon weight; run length against the 60–75 minute target.

**Out of MVP scope**

The MVP goal is **one full run working**, from the start screen to the boss, solo and co-op, on
Normal and Hard. Held until after it:

- Meta progression (unlocks between runs), endless runs, act scaling beyond one act, and bosses
  beyond the Powder Baron.
- The Mage Tower faction (including its starting army), and units with convoy access.
- Status effects, the Ballista and the War Drum.
- Darkness extras: torches beyond the Brazier, and effects that reward standing in the darkness.
- Content extras: support weapons beyond staves (whips, instruments, banners), one- and two-handed
  weapons, unique equipment, and more enemy factions.
- Shared and hybrid co-op battles (Option D, the post-MVP target).

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

Newest last. Each decision is already reflected in the sections above. Decisions later overturned
are moved to [Superseded decisions](#superseded-decisions), so every row here is live.

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
| October 15, 2026 | Effect counters | Two lanes, "this combat" and "this campaign", stated in effect text; one effect can have a counter in each. | Counters lasting the whole run |
| October 15, 2026 | Trigger scopes | This unit, Your Unit, Any Ally Unit (includes co-op partners), Any Unit. See effect-triggers.md. | Unscoped triggers |
| October 15, 2026 | Hit | A hit is any successful hit roll, even if fully countered or absorbed by Block. | Unstated |
| October 15, 2026 | Duplicates | Copies stack, but offers avoid things a player already owns, as in Balatro. | Unstated |
| October 15, 2026 | Duplicate scope | No-duplicate offers apply to each player's heirlooms only. Named-effect items may duplicate; revisit if it causes balance problems. | Unstated |
| October 15, 2026 | Unique heirlooms | Heirlooms tagged unique (affecting more than one player's units) can be owned by only one player per co-op campaign. | Unstated |
| October 15, 2026 | Shield units | No shield weapon type; bulky roles get their bulk from unit-type traits. | Shield-weapon units |
| October 15, 2026 | Unit generation | Each recruited unit rolls a Terraria-style prefix that shifts its stats and is shown before its name. Details open. | Hidden random noise on every stat and growth |
| October 15, 2026 | Prefix rules | Prefixes shift base stats and growths together; no prefix is the pure baseline; rolls lean positive; re-roll at a Camp or through events; enemies roll prefixes by difficulty (Normal: elites and bosses only). | Unstated |
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
| October 17, 2026 | Whom to reinforce | The sender chooses one map, guided by map status and call-for-aid flags; no splitting; several senders can help one map. | Undecided |
| October 20, 2026 | The darkness | Adopted as the turn-par pressure system: waves from authored sources flood toward the objective's drain; lingering hurts; no unit is immune; the map never ends early; locked doors block it, breakable walls erode. Damage model to be playtested. See the-darkness.md. | No turn-par pressure |
| October 20, 2026 | Co-op Feast | Each player chooses at a Camp; a Feast's heal reaches every player's units and heals stack; its ingredient feeds only the cook's army (a future unique heirloom could share it). | Feast feeds only its player's army |
| October 20, 2026 | Revive event | Revival returns only as a rare Unknown event that brings back one fallen unit; Camps still can't revive. | No revival anywhere |
| October 20, 2026 | Co-op commander | A commander that falls in co-op returns after the combat at critical health (first pass 10% of max HP, at least 1), with no other cost; the run is lost only if every commander falls in the same combat. Solo unchanged. | Undecided (eliminated or team loss) |
| October 20, 2026 | Revive shrine | The revive event is a trade-off: revive one fallen unit at critical health, or take a rare heirloom. Events as a whole stay a stub pending a full design pass. | Unstated |
| October 20, 2026 | Recruiting and transfer | 3 recruits per Guildhall visit; full preview; role weapon only; one swap screen on replacement; temporary convoy space until the next combat; co-op gifting at Camps and shops. See unit-roster.md. | Stub |
| October 20, 2026 | Growth items and new gear | Training Weights: −2 SPD, Speed can't grow, +1 MGT every level-up. Resonant Ore: +1 random non-Speed stat every level-up. New: Simple and Short Quiver, Simple and Spirit Coating. Family Ring and Royal Crest still need a new effect. | Growth-percent items; no quivers or coatings |
| October 20, 2026 | Family Ring and Royal Crest | Family Ring: +25% XP for its holder. Royal Crest (rare): every level-up gains at least 3 stats. | +4% and +6% all growths |
| October 22, 2026 | Enemy profiles | Every enemy attack carries a profile, damage type and range, so enemies take part in the triangle, effectiveness and damage stages. | Unstated |
| October 22, 2026 | Enemy scaling | Enemies have levels and growths, like player units (suits endless runs). | Unstated |
| October 22, 2026 | Enemy intentions | Fire Emblem danger zone plus Slay the Spire intent icons with a target rule; no committed actions. | Unstated |
| October 22, 2026 | Enemy factions and bosses | Enemies have their own factions (themes later; a later event may recruit an enemy type). Bosses held; MVP: 1 boss, 2–3 mini-bosses, with large StS/Balatro-style gimmicks. | `Godot_FE`'s shared roster |
| October 22, 2026 | Enemy unit types | Model 1: separate enemy classes on the same combat rules (stats, growths, tags, trait, weapon), spiced with enemy-only traits, telegraphed signature moves and rare rule-breaking gimmicks. Profiles on every attack except a deliberate gimmick. | Model 2 (fully separate move rotations) |
| October 22, 2026 | MVP enemy roster | 10 first-pass enemy classes in one working faction (Brigands), built on `Godot_FE`'s Lawbreakers and support units, with traits, AI behaviors and packs. Elites are classes plus a prefix and signature move. See enemy-roster.md. | No enemy roster |
| October 22, 2026 | Ruthless AI and side-agnostic effects | Enemies take any available kill first and ignore friendly fire. Brute (Cleave), Shieldbearer (Shield Wall), Hexer (Curse), Warcaller (War Horn) and the reworked Raider (Trample) affect every unit in their area, friend or foe. New splash damage rule (no hit roll, Block absorbs). | Ally-only enemy effects; Raider's Hit and Run |
| October 22, 2026 | Shove | Returns from `Godot_FE/` with fairness rules: costs the unit's action; only onto legal tiles (no pit or water kills); only Exposed (Stance-broken) units can be shoved, no weight check; a unit can be shoved once per phase; not an attack. First pass. | `Godot_FE`'s free Shove |
| October 22, 2026 | Slick tiles and ally shoves | Spilled oil is slick terrain: a shoved unit slides on until stopped (spike damage if a spiked wall stops it); walking is normal. A willing ally can always be shoved; the Exposed rule applies to foes only. | Unstated |
| October 22, 2026 | Bump and Shove distance | Shoving a unit into another unit bumps both for 2 (splash rules). New Shove distance value (default 1); longer shoves move tile by tile and stop at obstacles. New MVP unit: the Ward (shove specialist, "Shield Bash: Always: Shove distance +1"), from `Godot_FE`'s Ward. | No general bump; 13-unit roster |
| October 22, 2026 | Action economy | Move, then one action (attack, heal, Shove, use an object, open/search, use a Pouch item, swap equipment, or wait); runes are free. No moving after acting without a trait. No trading in combat; Pouch items can be used on an adjacent ally instead. | `Godot_FE`'s major and minor actions |
| October 22, 2026 | Sidearm | Big upgrades that add a weapon type (Sellsword+, Thief+, Mage+) grant Sidearm: a second weapon may be carried in the Pouch and swapped in for free once per Unit Turn, before acting; the stowed weapon is weightless; the Pouch then holds no potion or trinket. | Second weapon type usable only in battle prep |
| October 22, 2026 | Stowed weapons | Any unit may stow a weapon in its Pouch and swap it in as its action; Sidearm makes the swap free, with `Godot_FE`'s forecast weapon cycling. Pouch items must stay strong enough that stowing a weapon is an intentional choice, reinforced by traits. | Sidearm-only weapon swap |
| October 22, 2026 | Curses and team events | Curses are permanent (no Guildhall removal), grouped minor/major/severe and matched to reward size, always named before choosing, and never affect the economy (Light Purse cut); 10 first-pass curses. Some events are team choices voted like the route; combat options are always team choices. Black Altar added. | Guildhall curse removal; random curses; individual-only co-op events |
| October 23, 2026 | MVP scope | The MVP is one full run working; meta progression is held until then. | Meta progression as an open MVP area |
| October 23, 2026 | Drengr commander | Ported from `Godot_FE` with SPD 6, DEF 3 (was overpowered) and RES 2 (unset); Stance 3; axe and sword, starts with a Simple Axe; trait Vanguard (Phase Start, while no ally is closer to an enemy: +3 Block); Iron Heart heals for the full damage of every 7th army attack each combat. Commanders are never upgraded. Dawnbreak not ported. See unit-roster.md. | Undefined commander |
| October 23, 2026 | Heirloom pool | Tiers Common, Uncommon, Rare (Armory 150 / 200 / 250) plus a Shop tier sold only at the Armory (150); no cap; Treasure chest size is its rarity (50 / 33 / 17%). First-pass pool of 35 (14 / 10 / 7 / 4). See heirlooms.md. | "Capped at 8–12"; no heirloom list |
| October 23, 2026 | Starting heirlooms and army size | Pick 1 of 3 starting heirlooms from a pool of 7 (Abundance, Ancestral Weapon, Tactician's Manual, War Chest, Veteran Company, Family Relic, Mercenary Contract). Mercenary max army size 4 (starts full); hard ceiling 8; army size grows only through Abundance, the Rare heirloom Muster Roll and event options. Maps author at least 8 deployment tiles. | Max army size 6, maximum 10; three example starting heirlooms |
| October 23, 2026 | Weapons and item rarity | Scaling modifier 1 for every weapon; every bow is effective against Fliers. Five item rarities: Basic (starting gear only), Common, Uncommon, Rare, Legendary (a Large chest's 10% chance, about 3% of runs). 61 weapons converted from `Godot_FE` with fresh names: damage, crit and weight keep their distance from `Godot_FE`'s Iron weapon; Hit never drops below the type's Simple weapon, so weight is the price of power. `Godot_FE` Mythical → Rare. Prices: Common 40, Uncommon 60, Rare 150 (Mythical 250). See weapons.md. | Iron / Steel / Silver tiers; no weapon list; item rarity open |
| October 23, 2026 | Combat rewards and Armory stock | Standard combat: gold plus pick 1 of 3 items or skip (Common 60 / Uncommon 30 / Rare 10). Key combat: gold, the same item pick, and one random heirloom (50 / 33 / 17). Armory: 3 weapons, 2 equipment, 1 trinket, 2 consumables (50 / 35 / 15) and 2 heirlooms (one pool, one Shop tier). No enemy drops in the MVP. | "Simple rewards"; enemy weapon drops |
| October 23, 2026 | HP and staves | HP carries over between combats with no heal on win. Staves split: Block staves are unlimited (Basic Shelter: 3 + Might Block; the Battle Medic's starting weapon); heal staves are limited (Minor Heal, Common: 5 + Might, 3 uses per map). Triage becomes "Used a staff on an ally: that ally gains 1 Stance". | Unstated HP carry-over; unbreakable Minor Heal as starting staff |
| October 23, 2026 | Difficulty and scaling | Three steps at the key rows (floors 1–5, 6–11, 12–17): standard combats field 3 / 4 / 5 enemies at level 1 / 3 / 5; key +1, leaders and mini-bosses +2, boss level 8. Enemy count never scales with army size. Enemies grow by average growths (deterministic). Normal and Hard, chosen at run start; Hard: every enemy rolls a prefix, +1 enemy level, turn par −1. | Difficulty stub |
| October 23, 2026 | Boss and mini-bosses | Boss: the Powder Baron, an elite Brute (level 8, +2 prefix, Unshovable) holding the throne; every 2nd enemy phase it throws a telegraphed powder keg with a 2-phase fuse. Mini-bosses: Brigand Captain, Bloodhound, Hex Matron (Hex Storm) and Iron Wall (Fortify), one per key combat, no repeats. See enemy-roster.md. | Bosses held for later |
| October 23, 2026 | Turn par and map loot | Par = a clean, aggressive clear + 1 (targets: standard 4–6, key 7–10, boss 10–14; Hard −1). Survive and Defend maps end early, with the speed bonus, once every enemy is defeated and every reinforcement point closed. Houses: 15–25 gold or a consumable, never an heirloom. Chests: one item at 50 / 35 / 15. | Unset par; houses with an heirloom chance; unspecified chest loot |
| October 23, 2026 | Statuses and runes | No status effects in the MVP ("cure" and "light fog" consumables dropped). Runes: 3 slots (discard past 3), target anything on the map, 30 gold at the Guildhall; pool of 7: Mend, Aegis, Shatter (−2 Stance), Clarity (+20 Hit, +2 damage), Haste, Spark, Recall. See items.md. | Status effects WIP; no rune list or slots |
| October 23, 2026 | Co-op rules | Everything per player except shops: one shared Armory and Guildhall stock, +1 per category per extra player, first confirmed purchase wins. Reinforcements: any survivors at current HP, commander included, arriving next to the receiving commander; personal XP only. Parallel maps run on their own turns. Guildhall sells 2 runes per visit. Unique heirloom offered twice: first claim wins, the other is replaced. | Arrival to-do; ownership undecided |
| October 23, 2026 | Cleanup: map rules, Brazier, lockpicks, Standout | Every path passes at least 2 Treasures and 2–5 Camps; an Unknown never becomes a Camp. The Brazier is the darkness's torch and ships in the MVP. Keys are renamed lockpicks (Chest Pick, Door Pick, Master Pick). The combat MVP award is renamed the **Standout**. | Treasure "2(3?)"; Camp in Unknown 3%; torch stub; Chest/Door/Skeleton Key; "Combat MVP" |
| October 23, 2026 | Pillars | Gameplay goal and "hurry up and wait" rationale written. Run-length target: a typical solo run takes 60–75 minutes (`Godot_FE` took 4–8 hours). Ballista and War Drum held until after the MVP. Constitution against weapon weight accepted as the trade-off, to watch in playtesting. | Blank goal and rationale; no run-length target |
| October 23, 2026 | Co-op involvement, darkness and scope | Any player can use runes on a teammate's map during its player phase; lost players spectate; game speed is a host lobby setting; players on a map vote to fast-forward its enemy phase, which pauses for boss combats and player deaths. The darkness ships as % max HP, not an attack. The revive shrine draws normally once eligible. Keg chains are unlimited, with at most 3 kegs per map (boss arena excepted). Only Cutthroats loot. No flat mitigation cap; a content warning for untagged unique heirlooms. Darkness, content and unit extras are out of MVP scope. | Open questions in those docs |
| October 23, 2026 | Army-size event | Mercenary Camp's third option becomes "Sign a Company Charter": +1 max army size and a major curse. | "Move On" |

### Superseded decisions

Overturned decisions, kept for history. Don't build from these; the decision named in the last
column replaced them.

| Date | Topic | Decision | Superseded by |
|------|-------|----------|---------------|
| October 15, 2026 | Effect counters | Last the whole run, like Slay the Spire's Pen Nib. | October 15, 2026, Effect counters: two lanes, "this combat" and "this campaign" |
| October 15, 2026 | MVP roster | 13 tier-2 unit types, one per weapon role plus each movement type; see unit-roster.md. | October 22, 2026, Bump and Shove distance: the Ward makes 14 |
| October 15, 2026 | Camp re-roll | Camp gains a fourth choice: re-roll one unit's prefix. | October 16, 2026, Prefix re-roll and Re-roll price: re-rolls are a Guildhall service |
| October 16, 2026 | Prefix re-roll | Moved from Camp to a Shop service: once per visit, price rising with each use in a run, like Slay the Spire's card removal (first pass 250 gold, +100 per use). Camp is Feast, Train, Revive. | October 16, 2026, Re-roll price (⅓ of unit value, +50% per repeat); October 20, 2026, Permadeath (no Camp Revive) |
| October 17, 2026 | One player loses | Winners can reinforce a teammate's map; players can retreat; the team wins if anyone wins; in co-op a fallen commander is downed, not killed, and the run ends only if every commander falls. | October 20, 2026, Permadeath (no retreat) and Co-op commander (returns at critical health). Reinforcing and "the team wins if anyone wins" still stand |
| October 20, 2026 | Permadeath | No retreat, revival or extra lives anywhere, in solo or co-op: every unit has permadeath, and a fallen commander ends the run. Camp loses Revive; co-op loses downed commanders and retreat. The negative feedback loop is accepted. | October 20, 2026, Co-op commander and Revive event / Revive shrine. No retreat, no Camp Revive and the accepted feedback loop still stand |
| October 22, 2026 | Spiked walls | Spikes are a wall tile no unit can enter; a unit shoved into one takes 4 damage (splash rules) and stays put. They are the only bump damage; shoving into other walls or units isn't allowed. | October 22, 2026, Bump and Shove distance: shoving into a unit bumps both for 2. Spiked walls themselves still stand |
| October 22, 2026 | Events | First-pass pool of 12 (8 reworked from `Godot_FE`, 4 new, revive shrine included; shrine appears only once a unit has fallen); no repeats per run; guaranteed stat changes only. Curses are negative heirlooms, removed at the Guildhall (50, +25 per removal). Co-op: same event, own choice. See events.md. | October 22, 2026, Curses and team events: curses are permanent; some events are team choices; Black Altar makes 13. The rest still stands |
