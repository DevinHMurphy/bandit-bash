# Plan: Content Catalog
**Date:** October 29, 2026
**Status:** **Approved** October 29, 2026 (questions 1–17 answered). Orchestrator ID **P03**
([game-orchestrator.md](game-orchestrator.md)). CT1 implemented October 29, 2026 (question 18 answered); CT2 (instances and the loadout) implemented
October 29, 2026 (question 20 raised); CT3 (the M1 content) merged October 30, 2026 (019c1b3; question 21 answered), CT3F (Triage above the Stance maximum) merged October 31, 2026 (fcc6722; question 22 open), so M1's part of P03 is built.

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

None open. Answered questions, by number: [decisions/P03-content-catalog.md](decisions/P03-content-catalog.md).

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
- Shared target shapes (question 17): the `TargetShape` resource, `data/shapes/`, and moving
  every area in content and code onto it.
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
- Rune prefixes (post-MVP; `prefixes/runes/` is reserved, question 16 (b)), and directional
  shapes (line, cone; question 17).
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
  unit type picks locks innately"; Everwall's range "—" is 0 (P02 question 14). Runes target what
  items.md says, with a preview (question 32 replaces question 16's areas).
- **Not in the vision yet:** weapon prefixes (question 15) and rune prefixes (post-MVP).
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
| `UnitTypeDefinition` | `trait_name` (question 18; the upgraded name adds "+"), `role` (question 13), `weapon_types`, `movement_type` (P04's enum), `tags`, `stance`, base stats and growths (the seven stats), `starting_weapon_id`, `innate_effects` (always-on, not trait text: the Thief's `CAN_PICK_LOCKS`), the upgrade (`upgraded_effects`, stat gains, and the big change: added weapon type with Sidearm, new movement type and tags), `is_commander` |
| Commander (a `UnitTypeDefinition` with `is_commander`) | Plus `commander_heirloom_id`; never rolls a prefix, never upgraded |
| `UnitPrefixDefinition` | `tier` (−2 to +2), stat deltas, growth deltas, Hit delta |
| `WeaponPrefixDefinition` (question 15) | `tier`, weapon stat deltas (damage, Hit, crit, CritX, AtkX, weight, range), `weapon_types` (empty means every weapon), `staff_kinds` (for staff prefixes: which staff kinds it fits) |
| `FactionDefinition` (question 10) | Commander id, starting unit type ids with their gear, max army size, `starting_gold` (question 18; Mercenary 100, game-vision.md's faction table) |
| `ItemDefinition` (base) | `kind`, `rarity`, `weight` (0 for Pouch items, as the vision says), `tags` |
| `WeaponDefinition` | `weapon_type`, profile, damage, damage type, scaling stat and modifier, AtkX, `range_min`/`range_max`, Hit, crit, CritX, `effective_against` (tag ids) |
| `StaffDefinition` (a weapon, type `staff`) | Staff kind (Block, heal, attack, status stub), base amount (+ Might), area (a `TargetShape` id; question 17), uses and their refresh (per map or unlimited); a full-heal setting for heal staves (Everbloom; question 18, added in CT4); attack staves use the weapon fields. Range 0 targets the user (P02 question 14) |
| `EquipmentDefinition` | Category: cloak, armor, band, quiver, coating, shield, unique |
| `TrinketDefinition` | Nothing beyond the base; its effects are the trinket |
| `ConsumableDefinition` | Use kind (heal, Block, full heal, key, lockpick, stat booster, ingredient), amount, uses and their refresh (per map, total, never used up); ingredients add their eaten and cooked gains |
| `RuneDefinition` | `target_kind` (question 32): **unit** (one unit of its `target_side`, player or enemy; `needs_unacted_target` for Haste), **pair** (Recall: two of your units) or **object** (Spark: the object on a tile the player picks). No rune has an area |
| `TargetShape` (question 17) | `kind` (tile, radius, square, cross), `size` (grid distance only; question 18), `includes_center`; `tiles(center)` returns the tiles it covers. Read by P01's `Area` selector (F17), so staves, splash, kegs and runes share it |
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
| `data/shapes/` | Target shapes, reused by id (question 17) |
| `data/prefixes/runes/` | Reserved for rune prefixes (post-MVP stub; question 16 (b)); empty in the MVP |
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
copy-paste), items possibly outside their rarity's budget. From CT9 (question
28): Commander's Standard's area counts allies, so on a map several seats share (P11) partners'
units near the commander gain its Block too; Hunted's `EXTRA_ENEMIES` and Clouded Sight's
`INTENTS_HIDDEN` have no reading step yet; "<trigger> by Your Unit" reads oddly for a unit's own
facts and phase facts (P07's generated text).

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
| CT2 Instances and loadout | `scripts/content/unit_instance.gd`, `item_instance.gd`, `loadout.gd`; changes in `combat_state.gd`, `combat_unit_state.gd`, `auto_deploy.gd`, `combat_encounter.gd`; `CombatValue.Permission.CAN_PICK_LOCKS` | Instances with capture and restore; stat calculation; the loadout step; the role read (question 13); the permission (F15) and `MapObjects.can_pick_locks()` reading it; CT1's definition fixes (question 18: grid-only `TargetShape`, `starting_gold`, `trait_name`) | 🔴 replaces stopgaps in P02 and P04 code | CT1, EB5 | Round trips; a unit's stats match unit-roster.md with and without a prefix and upgrade; a battle loaded from data equals one built by hand; every existing suite still passes |
| CT3 M1 content | `data/units/`, `data/units/commanders/`, `data/factions/`, Simple weapons, Shelter, Minor Heal, Potion, Guard Tonic, Iron Heart | The Mercenary army and its gear (question 6) | 🟢 | CT2 | The content test passes; the M1 map opens with the Mercenary army loaded from data; trait text snapshots |
| CT4 Weapons and staves | `data/items/weapons/**` | All 70 MVP weapons and staves (weapons.md); Sanctuary and Everwall name their shapes; Everbloom's full-heal setting and the staff resolver reading it (question 18); the Short Quiver, with range read outside attacks (question 25); the Javelin (the Pilum renamed) comes from EN6 (P05 question 24) | 🟡 touches P02's staff resolver | CT3, CT6 | Content test; a sample of forecasts against hand-computed values |
| CT5 Equipment, trinkets, consumables | `data/items/{equipment,trinkets,consumables}/` | items.md, with the Key and the Lockpick (question 5); the Short Quiver moves to CT4 and the Resonant Ore to P08 RN4 (question 25) | 🟢 | CT3 | Content test; Training Weights, Spirit Coating and the Simple Quiver behave in combat tests |
| CT6 Target shapes | `scripts/content/target_shape.gd`, `data/shapes/`; changes in P01's `blocks/selectors/area.gd`, `combat_state.gd` (staff area), `map_objects.gd` (keg blast) | `TargetShape` and its kinds (question 17); P01's `Area` reads a shape (amendment F17); the area staves, Cleave's splash and the keg blast move onto shapes; retires `combat_state.gd:421` | 🔴 changes a P01 block every area uses | CT2 | Each kind's tiles at sizes 0–3 (grid distance only, question 18); every existing area test (Cleave, Sanctuary, Everwall, kegs) passes unchanged |
| CT7 Runes | `data/runes/`, changes in `cast_rune_command.gd`, `rune_resolver.gd`, `combat_forecast.gd`, `map_objects.gd` | The seven runes with their target kinds (question 32: unit, pair, object; no area); `CastRuneCommand` carries a tile for an object rune; the rune preview (target tiles and every unit hit) through the forecast's sandbox run; retires both rune stopgaps | 🔴 command and wire contract | CT6 | Each rune's golden fact log; the preview equals the result; Recall as a pair, Spark detonating a keg anywhere and its chain |
| CT8 Unit prefixes and pools | `data/prefixes/units/`, `scripts/content/item_pools.gd`; change in `map_objects.gd` | The 12 unit prefixes and the tier odds; loot and offer pools by kind and rarity; MP6's chest and house items (`map_objects.gd:TOD-001`) | 🟡 | CT4, CT5 | Prefix budgets match unit-roster.md's table; a seeded pool draw is stable; a Basic or Legendary item never appears in a sellable pool |
| CT9 Heirlooms and curses | `data/heirlooms/`, `data/curses/`, `data/shapes/within_2_with_center.tres`; changes in P01's `while_state_condition.gd`, `while_position_condition.gd`, `area.gd`, `all_of_scope.gd`, `sandbox_state.gd`, `effect_definition.gd`; `combat_state.gd`, `combat_session.gd` (deploy), `map_objects.gd` | heirlooms.md's 35 pool heirlooms and events.md's 10 curses; the held-weapon profile and commander states, the commander area center, the scope selector's `where` filter (P01 question 30), Burglar's Roll as a third opener, Heavy Pack read at deployment (question 28) | 🔴 P01 blocks and `SandboxState` (additions only) | CT2 | Content test (tiers, scopes, unique and co-op marks); text snapshots; a battle case per combat-side effect; stacking; a golden log per heirloom kind and a curse |
| CT10 Modified-item prices | `scripts/content/prices.gd` | The price and scrap formula from deltas, brought to the user first (question 8) | 🟢 | CT5 | Price examples for *Infuse* and *Forge Resonance* |
| CT11 Docs | `docs/design/content-authoring.md` (new) | How to add a unit, item, heirloom or shape: folders, ids, fields, the content test | 🟢 | CT3 | Review |
| CT12 Weapon modifications (M3, after P09 EV1) | `data/prefixes/weapons/**`, the P09 outcome that applies one | The weapon prefix list, applied only by events and later run sources, never rolled when a weapon is generated (questions 15 and 33) | 🟡 | CT4, CT8, the vision's weapon prefix rules | Content test (folder rule, applicable types); a prefixed weapon's forecast shows the prefix in its breakdown |
| CT13 Unit roster | `data/units/` | The eleven MVP unit types (question 27) beyond M1 (unit-roster.md) with traits, upgrades and roles; the Thief grants `CAN_PICK_LOCKS` in `innate_effects` (question 19) | 🟢 | CT3 (CT4 for a starting weapon that isn't Simple) | Content test; each type's stats match unit-roster.md; the Thief opens a locked chest with a Lockpick |
| CT13F Skirmisher+ Block | `scripts/effects/effect_terms.gd`, `scripts/bus/combat_fact.gd`, the move path, `data/units/freewing.tres` | Skirmisher+'s "gains 2 Block if it moves": a `MOVED_AFTER_ACTING` trigger fired from a second move's `UNIT_MOVED` fact, flagged `SECOND_MOVE` (question 27) | 🔴 fact flag (append-only) | CT13 | The Freewing+ gains 2 Block only on a move after acting; the Content debt line and the test's TODO go |

M1 needs CT1, EB5, CT2 and CT3. CT4–CT13 can follow in any order their gates allow. The models for
weapon prefixes (the definition, `ItemInstance.prefix_id`, the loadout applying it) and target
shapes (the `TargetShape` class) are built in CT1 and CT2; only the content waits for the vision.
Rune prefixes are post-MVP: `prefixes/runes/` exists and nothing reads it.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| Weapon and staff records built by the loadout | Behavior (P02) | Hand-built in tests and setup | From definitions and instances | Proposed (CT2) | `combat_state.gd`, `combat_encounter.gd`, combat and sessions tests | 🔴 |
| Unit types, tags and weapon types checked against fixed id lists | Behavior | Any string | Ids from the lists | Proposed (CT2) | `combat_unit_state.gd`, every test fixture | 🟡 |
| `CombatValue.Permission.CAN_PICK_LOCKS` appended | Enum (P01) | — | New value, default denied | Proposed (CT2) | `combat_value.gd`, `map_objects.gd` | 🟡 |
| Auto-deployment reads `role` | Behavior (P04) | Ward's type name | `role == "shover"` | Proposed (CT2) | `auto_deploy.gd`, deploy tests | 🟢 |
| `Area` selector reads a `TargetShape` | P01 block (amendment F17) | Its own center and radius | Center plus a shape | Applied (CT6) | `blocks/selectors/area.gd`, every area in content and tests, `combat_state.gd`, `map_objects.gd` | 🔴 |
| Rune target kinds and `CastRuneCommand` carrying a tile | Command and wire contract (P02) | Unit ids, Recall inferred from a second unit | One unit (unit), two units (pair) or a tile (object), read from the rune; wire `[rune, target, second, tile]` | Applied (CT7) | `cast_rune_command.gd`, `rune_resolver.gd`, `map_objects.gd`, P07's rune UI, P11 | 🔴 |
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
