# Plan: Content Catalog
**Date:** October 29, 2026
**Status:** Draft — awaiting approval. Orchestrator ID **P03**
([game-orchestrator.md](game-orchestrator.md)). Questions 1–14 answered October 29, 2026; 15 and
16 open (raised by the answers to 2 and 12).

The game's content as data: unit types and the commander, prefixes, factions, weapons and staves,
equipment, trinkets, consumables, ingredients, runes, heirlooms and curses. This plan defines the
definition resources, the `res://data/` layout the catalog loads (P01 EB5), the unit and item
instances that carry per-run state, and the loadout step that turns them into a battle's combat
records. It then enters the content in stages, the M1 subset first.

## Problem

Every content kind exists only in the design docs. The code runs on stopgaps that name P03:

- Weapon numbers are hand-built records in the combat state:
  `combat_state.gd:71-72` (`# ASSUMPTION`, `TODO(TOD-002)`); weapon types are plain names
  (`combat_state.gd:392`); an area staff carries its own `Area` selector (`combat_state.gd:421`).
- Unit types and tags are unchecked strings (`combat_unit_state.gd:40`, `:45`).
- Auto-deployment finds the Shover by the Ward's type name (`auto_deploy.gd:TOD-001`).
- A rune cast naming a second unit is assumed to be Recall (`cast_rune_command.gd:33`); Spark is
  found by an effect id (`map_objects.gd:TOD-004`).
- Lock pickers are a `"Lockpicker"` tag (`map_objects.gd:99-100`, `TOD-003`), and chest and
  house loot has a category and rarity but no item (`map_objects.gd:398`, `TOD-001`).
- `ItemInstance` and `UnitInstance`, which P01 specifies as contracts for this plan
  ([P01, Definitions and instances](2026-10-23-event-bus-and-effects.md#effect-data-model-inspector-authored)),
  don't exist.
- `res://data/` holds only `terrain/` (P04). P01 EB5 (the catalog and content tests) is gated on
  this plan's content kinds and layout.

## Open Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | One plan or several (units / items / heirlooms) | One, staged / split | **One plan, staged:** the shared model, then M1's content, then the rest; heirlooms and curses are needed only from M3 | **Answered October 29, 2026 (user):** as recommended. |
| 2 | The `res://data/` layout (EB5's gate) | EB5's list / with subfolders | EB5's list plus `prefixes/` | **Answered October 29, 2026 (user):** plus **`units/commanders/`** for commanders and **one subfolder per weapon type** under `items/weapons/`. Folders don't change the catalog: it indexes by `id` and reads kind and type from fields, so EB5 walks folders recursively and the content test checks each file's folder against its data. **Prefixes are split too:** `prefixes/units/` for unit prefixes, and `prefixes/weapons/` with `all/` (any weapon) and one folder per weapon type, for prefixes only some weapons can roll (a Hit prefix is useless on a Block staff; a range prefix is reasonable on a bow or staff but overpowered on a melee weapon). Weapon prefixes are new design: question 15. See [Data layout](#data-layout). |
| 3 | Ids for weapon types and tags | Enums / string ids | **String ids checked by the content test:** saves and the wire carry plain string ids (P01), and the stopgaps already use strings. Movement types stay P04's enum (P04 question 11) | **Answered October 29, 2026 (user):** as recommended. |
| 4 | Who turns content into combat records | P02 / P03 | **P03:** a loadout step builds each battle's records from definitions plus instance deltas, filling `CombatState`'s weapon records and replacing the stopgap strings; the combat records themselves stay | **Answered October 29, 2026 (user):** as recommended. |
| 5 | Lock pickers, keys and lockpicks (P04 question 23; the vision says no unit picks locks) | — | The Thief picks locks, through a permission on its unit type (not its trait text) | **Answered October 29, 2026 (user):** the **Thief** picks locks (Thief+ too; P05 gives the enemy Cutthroat the same). **Two items in all:** a **Lockpick** (never used up; only lock pickers can use it) and a **Key** (a consumable with **2 uses**, any unit, opens a chest or a door). items.md's Chest, Door and Master Picks are dropped. Vision update queued. |
| 6 | The M1 subset | — | The Mercenary starting army (Drengr, Archer, Battle Medic, Hakkapel) with traits; the nine Simple weapons, Shelter and Minor Heal; Potion and Guard Tonic; no prefixes in M1 | **Answered October 29, 2026 (user):** as recommended. |
| 7 | Content with known problems (Ring of Favor, Heavy Brick, the Lancer's growths, items outside their budget) | Port as written / rework first | **Port as written**, listed under [Content debt](#content-debt) | **Answered October 29, 2026 (user):** as recommended. |
| 8 | Who owns the modified-item price and scrap formula (P08 question 3) | P03 / P08 | **P03**, which owns prices and deltas; the formula comes to the user in step CT9 | **Answered October 29, 2026 (user):** as recommended. |
| 9 | Who saves units and items | P03 / P08 | P03 provides `UnitInstance` and `ItemInstance` with capture and restore helpers; **P08 registers `roster`**; P03 registers no section | **Answered October 29, 2026 (user):** as recommended. |
| 10 | Factions as content (found writing this plan: game-vision.md has the faction set max army size and the starting army) | `data/factions/` in P03 / hard-coded in P08 | **`data/factions/`** with a `FactionDefinition`: commander, starting unit types and gear, max army size (Mercenary: 4). P08 reads it at run start; M1 builds its army from it | **Answered October 29, 2026 (user):** as recommended. |
| 11 | Rarity and price of the Lockpick and the Key (no basis for the Lockpick) | — | **Both Common**, at the Common consumable price (25 gold). The Key takes the old Chest Pick's rarity; the Lockpick has no `Godot_FE` source | **Answered October 29, 2026 (user):** as recommended. |
| 12 | How a rune says what it targets (P02 question 18 stopgap; `map_objects.gd:TOD-004`) | A target kind on the rune / infer from the command | A target kind on `RuneDefinition`: one unit, two of your units (Recall), or a map object (Spark) | **Answered October 29, 2026 (user), changing the design:** **most runes target a place on the map and have an area of effect**, and how to use them is up to the player. Selecting a rune shows a **preview** of its area and every unit it will hit before the cast. A rune whose text names its own targets ("a random enemy", "a random ally") does exactly what it says, with no aiming. The rune pool's areas are new design (vision update queued); the details are question 16. |
| 13 | How auto-deployment finds the Shover (`auto_deploy.gd:TOD-001`; P04 question 14) | A `role` on the unit type / a tag | **A `role` id** from unit-roster.md's Role column (sword, axe, …, support, mounted, flier, armored, shover). Tags stay what a unit *is*; role is what it's for. Auto-deployment reads `shover` | **Answered October 29, 2026 (user):** as recommended. |
| 14 | Enemy classes (P05) | Their own definition / extend the unit type | **`EnemyClassDefinition` extends `UnitTypeDefinition`** (stats, growths, weapons, traits, tags, role), adding P05's fields. `data/enemies/` stays P05's; the loadout step builds enemies and players the same way | **Answered October 29, 2026 (user):** as recommended. |
| 15 | Weapon prefixes (raised by question 2): the vision has prefixes on units only, so which weapons roll them, from which sources (loot, shops, starting gear), with what odds, budgets, price effect and re-roll, and the lists themselves are undecided | Build the model now, content after the vision / wait entirely | **Build the model now, content after the vision:** `WeaponPrefixDefinition` (stat deltas such as damage, Hit, crit, weight and range, applicable weapon types, and for staves the staff kinds it fits), `ItemInstance.prefix_id` (a P01 contract addition, amendment F16), the folders and their content rule, and the loadout applying the deltas. The rules and lists go to the ideation thread; step CT11 enters them once the vision has them. Nothing in M1 rolls a weapon prefix | |
| 16 | Rune targeting details (raised by question 12) | — | **(a)** Kinds: **area** (the player picks any tile; the rune's area shape and radius from there; the preview lists the tiles and every unit it will hit, through the same sandbox run as P02's forecast, so the preview equals the result), **random** (its own selector, such as a random enemy; no aiming), and **pair** for Recall (two of your units; an area doesn't fit a swap). Spark is an area rune that detonates the kegs in its area. **(b)** Until the vision sets each rune's area, area runes use radius 0 (the chosen tile only), which matches today's single-target behavior; marked as a stopgap. **(c)** P02 changes: `CastRuneCommand` carries a tile, not unit ids (a command and wire contract change), and `CombatForecast` gains the rune preview; done in CT6 with the user's approval of those P02 changes here | |

## Scope

**In scope**

- Definition resources for every content kind, their ids and the `res://data/` layout.
- The content rules P03 adds to EB5's content test.
- `UnitInstance` and `ItemInstance` (P01's contracts), with capture and restore helpers and stat
  calculation (base + prefix + upgrade + permanent deltas).
- The loadout step: instances to `CombatUnitState`, stat-sheet bases, weapon and staff records,
  and the effect instances of traits, items and heirlooms.
- The content itself, in stages: M1's subset, then all MVP weapons and staves, equipment,
  trinkets, consumables and ingredients, runes, prefixes, heirlooms and curses.
- Item pools for loot and offers (by kind and rarity), the price table, and the modified-item
  price formula.
- The weapon prefix model (question 15) and rune targeting with its preview (question 16); their
  content waits on the vision.
- `CombatValue.Permission.CAN_PICK_LOCKS` (P01 amendment F15) and the Thief's grant.

**Out of scope**

- The catalog's code and the content test harness (P01 EB5; this plan supplies the kinds, layout
  and rules).
- Recruiting, level-ups, XP, the `roster`, `heirlooms` and `runes` save sections, shops and
  rewards (P08). Events and how curses are offered (P09).
- Enemy classes, their AI and prefix rolls by difficulty (P05; question 14 is the shared
  contract).
- Terrain and movement types (P04). Map objects (P04 MP6; P03 supplies the pools and the
  lock-picker permission).
- Status effects and status staves (post-MVP; Hex, Slumber and Fetter stay stubs). Mage Tower and
  Kingdom content. Meta-progression unlocks.
- Art: icons and sprites are placeholders until the UI plan (P07).

## Design Basis

- **game-vision.md:** [Army](../design/game-vision.md#army) (max army size from the faction,
  permadeath, HP carries over); [Units](../design/game-vision.md#units) (seven stats, Attack Speed,
  upgrades instead of tiers, Sidearm, the three inventory slots); [Weapons and
  equipment](../design/game-vision.md#weapons-and-equipment) (the five data groups, the Simple
  weapons, rarities, staves, equipment categories, Pouch items); [Run-wide
  resources](../design/game-vision.md#run-wide-resources) (heirlooms, runes).
- **master-ideation.md:** Inventory; Weapon Overview §1.1.1–1.1.5 (equippability, combat exchange,
  targeting, block and skills data); Weapon Types; Quivers through Trinkets. Where it differs,
  game-vision.md wins: no Stash (the convoy replaces it), no off-hand, and the per-weapon Block
  fields are superseded by Block through effects.
- **Design docs:** [unit-roster.md](../design/unit-roster.md) (roster, commander, tags, traits,
  upgrades, prefixes, starting weapons), [weapons.md](../design/weapons.md),
  [items.md](../design/items.md), [heirlooms.md](../design/heirlooms.md),
  [events.md](../design/events.md#curses) (curses), [effects-system.md](../design/effects-system.md)
  (owners, duplicates, unique heirlooms).
- **Decisions that change the vision** (queued for the ideation thread; this plan follows them):
  keys and lockpicks (question 5) replace "lockpicks are Pouch consumables any unit can carry; no
  unit type picks locks innately"; Everwall's range "—" is 0 (P02 question 14); runes target a
  place with an area of effect and a preview (question 12), where items.md's runes target units.
- **Not in the vision yet:** weapon prefixes (question 15) and each rune's area (question 16).
  Their rules and values go to the ideation thread; this plan builds the model only.
- **Open in the vision, not a basis for values:** prefix tuning, the Lancer's growths, re-roll
  prices, balance of every listed value (each doc's "Open questions"). They are entered as
  written and tuned in playtesting.

## Legacy Behavior (ports from Godot_FE only)

`Godot_FE` runs on Godot 4.7 too, but its content scripts predate this design: nothing is copied.
The design docs already converted its values; this plan ports the data model's intent.

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `scripts/resources/unit_type/UnitTypeDefinition.gd` | Unit types with base, max, growth and promotion stats, tiers, promotions, traits as enum flags, skills by level | Change | Upgrades replace tiers and promotions; skills become one trait (effects); tags are string ids; max stats dropped (no level cap) |
| `resources/definitions/unit_types/{commanders,units}/` | Commanders stored apart from units | Keep | Question 2 (`units/commanders/`) |
| `scripts/resources/Items/ItemDefinition.gd` | Durability with refresh types, worth and price per item, held bonus stats, `db_key` | Change | Uses only where the vision has them (per map or total); price from the rarity × kind table; bonuses become effects; `id` replaces `db_key` |
| `scripts/resources/Items/WeaponDefinition.gd` | Weapon type, alignment, two triangle enums, mastery and class locks, specials enum, attack range as a list | Change | One profile (the WPT); mastery and class locks dropped (weapon types gate use); specials become effects; range becomes min and max |
| `scripts/resources/Items/ConsumableItemDefinition.gd` | One use-effect enum with a power value; stat and growth boosts | Change | Consumable kinds (heal, Block, key, lockpick, stat booster, ingredient); growth boosts become ingredients (items.md) |
| `resources/definitions/items/weapons/<type>/` | Weapons stored by type | Keep | Question 2 (one subfolder per weapon type) |
| `scripts/resources/rarity/RarityDefinition.gd`, `resources/definitions/rarity/` | Seven rarities as resources | Change | Six rarities as an enum (Mythical folds into Rare; items.md) |
| `combat/databases/*_database.tscn` | Hand-kept dictionaries of definitions, keyed by `db_key` | Drop | EB5's catalog loads `res://data/` by walking folders; nothing is registered by hand |
| `resources/definitions/loot_tables/` | Weighted loot tables per container | Change | Pools are catalog queries by kind and rarity, with the odds the vision sets (P04 MP6 rolls the rarity) |
| `scripts/resources/unit_type/UnitTypeDefaultItemTables.gd` | A default weapon table per unit type | Change | One starting weapon per unit type (unit-roster.md) |

Tuning values: none are taken from `Godot_FE` directly. Every value comes from the design docs
above, which list their own `Godot_FE` sources.

## Approach

### Shape

```
Definitions (Resources in res://data/, read-only)     → EB5 catalog, by id
UnitInstance / ItemInstance (per run, plain data)     → saved by P08 in roster
Loadout (static): instances + definitions → CombatUnitState, stat-sheet bases, weapon and staff
records, effect instances                             → P02's CombatState and P01's engine
```

Every definition extends P01's `EffectCarrierDefinition` (`id`, `display_name`, `effects`), so
traits, item effects, heirlooms and runes are ordinary effect definitions, and their text comes
from `describe()`. Generated text is canonical; the design docs keep their wording.

### Definitions

| Definition | Fields (beyond `id`, `display_name`, `effects`) |
|------------|------------------------------------------------|
| `UnitTypeDefinition` | `role` (question 13), `weapon_types`, `movement_type` (P04's enum), `tags`, `stance`, base stats and growths (the seven stats), `starting_weapon_id`, `innate_effects` (always-on, not trait text: the Thief's `CAN_PICK_LOCKS`), the upgrade (`upgraded_effects`, stat gains, and the big change: added weapon type with Sidearm, new movement type and tags), `is_commander` |
| Commander (a `UnitTypeDefinition` with `is_commander`) | Plus `commander_heirloom_id`; never rolls a prefix, never upgraded |
| `UnitPrefixDefinition` | `tier` (−2 to +2), stat deltas, growth deltas, Hit delta |
| `WeaponPrefixDefinition` (question 15) | `tier`, weapon stat deltas (damage, Hit, crit, CritX, AtkX, weight, range), `weapon_types` (empty means every weapon), `staff_kinds` (for staff prefixes: which staff kinds it fits) |
| `FactionDefinition` (question 10) | Commander id, starting unit type ids with their gear, max army size |
| `ItemDefinition` (base) | `kind`, `rarity`, `weight` (0 for Pouch items, as the vision says), `tags` |
| `WeaponDefinition` | `weapon_type`, profile, damage, damage type, scaling stat and modifier, AtkX, `range_min`/`range_max`, Hit, crit, CritX, `effective_against` (tag ids) |
| `StaffDefinition` (a weapon, type `staff`) | Staff kind (Block, heal, attack, status stub), base amount (+ Might), area, uses and their refresh (per map or unlimited); attack staves use the weapon fields. Range 0 targets the user (P02 question 14) |
| `EquipmentDefinition` | Category: cloak, armor, band, quiver, coating, shield, unique |
| `TrinketDefinition` | Nothing beyond the base; its effects are the trinket |
| `ConsumableDefinition` | Use kind (heal, Block, full heal, key, lockpick, stat booster, ingredient), amount, uses and their refresh (per map, total, never used up); ingredients add their eaten and cooked gains |
| `RuneDefinition` | `target_kind` (questions 12 and 16): **area** (any tile the player picks, plus the rune's `area` shape and radius), **random** (its own selector, such as a random enemy; no aiming) or **pair** (Recall: two of your units) |
| `HeirloomDefinition` | Tier (common, uncommon, rare, shop, starting, commander), kind (profile, behavior, economy), `coop_only`; the `unique` tag as P01 defines it |
| `CurseDefinition` (a heirloom tagged `curse`) | Tier (minor, major, severe) |

- **Rarity** is an enum: Basic, Common, Uncommon, Rare, Legendary, Unique. **Prices** are one table
  by rarity and kind (items.md), never stored per item; runes cost 30 and heirlooms use their tier
  price.
- **Ids** are file names (`simple_sword`), unique across the catalog. Weapon types (`sword`, `axe`,
  `lance`, `bow`, `gauntlets`, `dagger`, `anima`, `holy`, `dark`, `staff`), tags (`armored`,
  `mounted`, `flier`, `terror`), roles and kinds are string ids from fixed lists in one script,
  checked by the content test (question 3).
- **Effectiveness** is by tag only: no MVP weapon is effective against a weapon type or profile
  (master-ideation §1.1.2 lists both; they wait for content that needs them).

### Data layout

| Folder | Holds |
|--------|-------|
| `data/units/` | The 14 MVP unit types |
| `data/units/commanders/` | The Drengr |
| `data/prefixes/units/` | The 12 unit prefixes |
| `data/prefixes/weapons/all/` | Weapon prefixes any weapon can roll (question 15) |
| `data/prefixes/weapons/<type>/` | Weapon prefixes only that weapon type can roll; the same type folders as `items/weapons/` (`staff/` included) |
| `data/factions/` | Mercenary (question 10) |
| `data/items/weapons/<type>/` | One folder per weapon type: `sword/`, `axe/`, `lance/`, `bow/`, `gauntlets/`, `dagger/`, `anima/`, `holy/`, `dark/`, `staff/` |
| `data/items/equipment/` | Equipment, shields included |
| `data/items/trinkets/` | Trinkets |
| `data/items/consumables/` | Potions, Guard Tonics, the Elixir, the Key, the Lockpick, stat boosters, ingredients |
| `data/runes/` | Runes |
| `data/heirlooms/` | Heirlooms, starting and Commander Heirlooms included |
| `data/curses/` | Curses |
| `data/enemies/` | Enemy classes (P05) |
| `data/effects/` | Standalone effects (P01: granted effects such as *Infuse*) |
| `data/terrain/` | Terrain (P04, unchanged) |

**Content rules** P03 adds to EB5's test: the file's folder matches its data (a weapon in
`items/weapons/axe/` has type `axe`; a file in `units/commanders/` has `is_commander`, and only
there; a weapon prefix in `prefixes/weapons/all/` lists no weapon types, and one in
`prefixes/weapons/bow/` lists exactly `bow`); every weapon and staff has a range, and attacks start at 1 (P02 question 14); every
referenced id exists (starting weapons, commander heirlooms, faction units); every string id is
in its fixed list; every sellable item's rarity and kind has a price; Basic, Legendary and Unique
items are never in a sellable pool.

### Instances

- **`ItemInstance`** (P01's contract): `instance_id`, `definition_id`, granted effect ids,
  stat deltas each with its source, uses left, and its effects' counter state; plus `prefix_id`
  for a weapon prefix (question 15; P01 amendment F16). A weapon prefix applies as deltas with the
  prefix as their source, so breakdowns name it.
- **`UnitInstance`** (P01's contract): `instance_id`, unit type id, prefix id, level, upgraded,
  the three slots (weapon, equipment, Pouch) as item instance ids, permanent stat deltas each with
  its source, pending level-up gains with a remaining count, XP and current HP (HP carries over).
- Both capture to plain JSON (ids, deltas, counters; never a `Resource`) and restore from it; P08
  stores them in `roster`. Stats are computed, never stored: base + prefix + upgrade + permanent
  deltas, through the same value queries as every other modifier, so breakdowns name each source.

### Loadout

One static step, called by the encounter's setup for every deployed unit, player and enemy alike
(question 14): it builds the `CombatUnitState` (type, tags, movement type, HP, slots), the
stat-sheet bases, a weapon or staff record for each carried weapon, and registers the effect
instances of the unit's traits, innate effects, items and its seat's heirlooms. It replaces the
hand-built records (`combat_state.gd:TOD-002`), and the stopgap markers in
`combat_unit_state.gd`, `auto_deploy.gd`, `cast_rune_command.gd` and `map_objects.gd` are
resolved by the step that delivers each piece.

### Content debt

Entered as written, revisited in playtesting (question 7): the Ring of Favor (needs a
Legendary-sized effect), Heavy Brick (Unique with no source), the Lancer's growths (a `Godot_FE`
copy-paste), items possibly outside their rarity's budget, Brothers in Arms (needs a selector
filter the engine lacks, P01 question 30).

### Rejected alternatives

- **Separate plans per kind:** the kinds share one base, one catalog and one loadout; three plans
  would triple the coordination (question 1).
- **Enums for weapon types and tags:** enum values in saves and on the wire break when the list
  changes; string ids don't (question 3).
- **Per-item prices:** one table keeps prices consistent and is the shape items.md specifies.

## Save Impact

P03 registers no section (question 9). It defines the shapes P08 saves:

| Data | Block | Section key | Per player | Version |
|------|-------|-------------|------------|---------|
| `UnitInstance` and `ItemInstance` (army, convoy, fallen units' items) | `CAMPAIGN` | `roster` (P08) | Yes | Set by P08 |
| Owned heirlooms and curses with their campaign-lane counters | `CAMPAIGN` | `heirlooms` (P08) | Yes | Set by P08 |
| Rune slots | `CAMPAIGN` | `runes` (P08) | Yes | Set by P08 |

Definitions are never saved: saves carry ids. Renaming a content id is a save-format change and
needs a migration in P08's section.

## Work Breakdown

| Step | Files | Description | Risk | Gate | Verification |
|------|-------|-------------|------|------|--------------|
| CT1 Definitions and layout | `scripts/content/*.gd` (one per definition, the id lists, the price table), `data/` folders | Every definition class, rarity, the fixed id lists and prices; the folder tree; one fixture per kind | 🟡 new classes | Approval | Check-only; each fixture loads and its `describe()` text is non-empty. **Opens P01 EB5** |
| CT2 Instances and loadout | `scripts/content/unit_instance.gd`, `item_instance.gd`, `loadout.gd`; changes in `combat_state.gd`, `combat_unit_state.gd`, `auto_deploy.gd`, `combat_encounter.gd`; `CombatValue.Permission.CAN_PICK_LOCKS` | Instances with capture and restore; stat calculation; the loadout step; the role read (question 13); the permission (F15) and `MapObjects.can_pick_locks()` reading it | 🔴 replaces stopgaps in P02 and P04 code | CT1, EB5 | Round trips; a unit's stats match unit-roster.md with and without a prefix and upgrade; a battle loaded from data equals one built by hand; every existing suite still passes |
| CT3 M1 content | `data/units/`, `data/units/commanders/`, `data/factions/`, Simple weapons, Shelter, Minor Heal, Potion, Guard Tonic, Iron Heart | The Mercenary army and its gear (question 6) | 🟢 | CT2 | The content test passes; the M1 map opens with the Mercenary army loaded from data; trait text snapshots |
| CT4 Weapons and staves | `data/items/weapons/**` | All 70 MVP weapons and staves (weapons.md) | 🟢 | CT3 | Content test; a sample of forecasts against hand-computed values |
| CT5 Equipment, trinkets, consumables | `data/items/{equipment,trinkets,consumables}/` | items.md, with the Key and the Lockpick (question 5) | 🟢 | CT3 | Content test; Training Weights, Spirit Coating and the Short Quiver behave in combat tests |
| CT6 Runes | `data/runes/`, changes in `cast_rune_command.gd`, `rune_resolver.gd`, `combat_forecast.gd`, `map_objects.gd` | The seven runes with their target kinds (questions 12 and 16); `CastRuneCommand` carries a tile; the rune preview (area tiles and every unit hit) through the forecast's sandbox run; area runes at radius 0 until the vision sets each area; retires both rune stopgaps | 🔴 command and wire contract | CT2 | Each rune's golden fact log; the preview equals the result; Recall as a pair, Spark detonating the kegs in its area |
| CT7 Prefixes and pools | `data/prefixes/units/`, `scripts/content/item_pools.gd`; change in `map_objects.gd` | The 12 unit prefixes and the tier odds; loot and offer pools by kind and rarity; MP6's chest and house items (`map_objects.gd:TOD-001`) | 🟡 | CT4, CT5 | Prefix budgets match unit-roster.md's table; a seeded pool draw is stable; a Basic or Legendary item never appears in a sellable pool |
| CT8 Heirlooms and curses | `data/heirlooms/`, `data/curses/` | heirlooms.md and events.md | 🟢 | CT2 | Content test (scopes, unique tags); a golden log per heirloom kind |
| CT9 Modified-item prices | `scripts/content/prices.gd` | The price and scrap formula from deltas, brought to the user first (question 8) | 🟢 | CT5 | Price examples for *Infuse* and *Forge Resonance* |
| CT10 Docs | `docs/design/content-authoring.md` (new) | How to add a unit, item or heirloom: folders, ids, fields, the content test | 🟢 | CT3 | Review |
| CT11 Weapon prefixes | `data/prefixes/weapons/**`, `scripts/content/item_pools.gd` | The weapon prefix lists, odds and sources (question 15) | 🟡 | CT4, CT7, the vision's weapon prefix rules | Content test (folder rule, applicable types); a prefixed weapon's forecast shows the prefix in its breakdown |

M1 needs CT1, EB5, CT2 and CT3. CT4–CT11 can follow in any order their gates allow. The model for
weapon prefixes (the definition, `ItemInstance.prefix_id`, the loadout applying it) is built in
CT1 and CT2; only the content waits for the vision.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| Weapon and staff records built by the loadout | Behavior (P02) | Hand-built in tests and setup | From definitions and instances | Proposed (CT2) | `combat_state.gd`, `combat_encounter.gd`, combat and sessions tests | 🔴 |
| Unit types, tags and weapon types checked against fixed id lists | Behavior | Any string | Ids from the lists | Proposed (CT2) | `combat_unit_state.gd`, every test fixture | 🟡 |
| `CombatValue.Permission.CAN_PICK_LOCKS` appended | Enum (P01) | — | New value, default denied | Proposed (CT2) | `combat_value.gd`, `map_objects.gd` | 🟡 |
| Auto-deployment reads `role` | Behavior (P04) | Ward's type name | `role == "shover"` | Proposed (CT2) | `auto_deploy.gd`, deploy tests | 🟢 |
| Rune target kinds and `CastRuneCommand` carrying a tile | Command and wire contract (P02) | Unit ids, Recall inferred from a second unit | A tile (area), nothing (random) or two units (pair), read from the rune | Proposed (CT6) | `cast_rune_command.gd`, `rune_resolver.gd`, `map_objects.gd`, P07's rune UI, P11 | 🔴 |
| `ItemInstance.prefix_id` | P01 contract addition (F16) | — | New field | Proposed (CT2) | `item_instance.gd`, P08's `roster` | 🟢 |
| `res://data/` layout | Content layout | `terrain/` only | The folders above | Proposed (CT1) | EB5's catalog | 🟢 |

## Verification

- Every changed `.gd`: `godot --headless --path bandit-bash --check-only --script res://<path>.gd`,
  after `--import` whenever a `class_name` is added.
- The content test (EB5) over all of `res://data/`, plus deliberately bad fixtures for each P03
  rule: wrong folder, missing range, dangling id, unknown string id, unpriced item.
- Every suite (sessions with a test user folder, map, combat, effects, rng, save) and a clean
  headless launch after each step.
- M1 check (CT3): the M1 map opens with the Mercenary army loaded from data, and a scripted fight
  runs to a result headless.

## Rollback

Definitions and data are additive: removing a content step's files removes its content. CT2 is the
only step that changes existing code; reverting its merge restores the stopgap strings and the
hand-built records, and every later step depends on it, so they revert with it.
