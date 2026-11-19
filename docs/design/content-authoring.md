# Content Authoring

How to add a unit, an item, a heirloom, a curse, a rune, a prefix, a shape or an enemy: where its
file goes, what it must be called, which fields it has, and what tests check it. It describes the
code on `dev`; the design is in the [content catalog plan](../plans/2026-10-29-content-catalog.md)
and the [enemies and AI plan](../plans/2026-10-30-enemies-and-ai.md). The design docs own the
numbers: [unit-roster.md](unit-roster.md), [weapons.md](weapons.md), [items.md](items.md),
[heirlooms.md](heirlooms.md), [events.md](events.md) (curses), [enemy-roster.md](enemy-roster.md)
and [enemy-packs.md](enemy-packs.md). Maps are in [map-authoring.md](map-authoring.md).

Paths are relative to `bandit-bash/`.

## How content loads

Every definition is a `.tres` Resource under `data/`. [EffectCatalog](../../bandit-bash/scripts/effects/effect_catalog.gd)
walks `data/` once at startup and indexes every file by id; nothing is registered by hand. A
file's kind comes from its script class, never its folder, but the content test checks that each
file sits in its kind's folder.

- **The id is the file name** (`simple_sword.tres` has `id = "simple_sword"`), unique across the
  whole catalog. Other content names it by that id.
- **Definitions are read-only at runtime.** What changes on one unit or item (deltas, a granted
  effect, counters) lives on its instance.
- **Effects** are `EffectDefinition`s inside the carrier's `effects` array, built from blocks in the
  inspector: a trigger, a scope, conditions, operations. The vocabulary is in
  [effect-triggers.md](effect-triggers.md); how they run is in [event-bus.md](event-bus.md). Every
  effect inside one carrier needs an `id` unique within it, since saves name it by that id. Effect
  text is generated from the blocks, so it can't drift from what the effect does.
- **String ids** (weapon types, tags, roles, staff kinds, tiers, target rules, shape kinds) come
  from the fixed lists in [ContentIds](../../bandit-bash/scripts/content/content_ids.gd); the
  inspector offers them as hints.
- **Stats** are dictionaries keyed by `CombatValue.Stat`: HP 0, MGT 1, SPD 2, DEF 3, RES 4, CON 5,
  MOV 6.

Every carrier ([EffectCarrierDefinition](../../bandit-bash/scripts/effects/effect_carrier_definition.gd))
has `id`, `display_name` and `effects`.

## Units

`data/units/<id>.tres`, a [UnitTypeDefinition](../../bandit-bash/scripts/content/unit_type_definition.gd);
a commander goes in `data/units/commanders/` with `is_commander` on, and only there.

| Field | Means |
|-------|-------|
| `trait_name`, `effects` | The trait's name and effects (Volley) |
| `role` | From `ContentIds.ROLES`; sets its place in automatic deployment |
| `weapon_types`, `starting_weapon_id` | What it may wield, and what it starts with |
| `movement_type`, `tags`, `stance` | Default, Heavy, Mobile, Mounted or Flier; `armored`, `mounted`, `flier`, `terror`; its Stance maximum |
| `innate_effects` | Always-on effects that aren't trait text, such as the Thief's lock-picking permission |
| `base_stats`, `growths` | The seven stats, and growth % for HP, MGT, SPD, DEF and RES |
| `upgraded_effects`, `upgrade_stat_gains`, `upgrade_weapon_types`, `upgrade_movement_type`, `upgrade_tags` | The upgrade: the "+" trait replaces the trait, plus its stat gains and the big change |
| `is_commander`, `commander_heirloom_id` | A commander keeps its stats every run, never rolls a prefix and is never upgraded |

A faction ([FactionDefinition](../../bandit-bash/scripts/content/faction_definition.gd),
`data/factions/`) names its commander, its starting unit types with their gear, its max army size
and its starting gold.

**Its sprite** is not a field. The board draws every unit type and enemy class from one table,
`assets/sprites/units/unit_sprites.tres` ([UnitSpriteTable](../../bandit-bash/ui/battle/unit/unit_sprite_table.gd)),
keyed by content id: add the 32 × 32 picture under `assets/sprites/units/` and an entry for the id.
A type with no entry is drawn with its letters, but the `ui/art` suite fails until it has one.
Record where the picture came from in [art-sources.md](art-sources.md#unit-sprites).

## Items

Every item is an [ItemDefinition](../../bandit-bash/scripts/content/item_definition.gd) with
`rarity` (Basic, Common, Uncommon, Rare, Legendary, Unique), `weight` (0 for Pouch items), `tags`
and `icon`.

| Kind | Folder | Class and its own fields |
|------|--------|--------------------------|
| Weapon | `items/weapons/<weapon type>/` | [WeaponDefinition](../../bandit-bash/scripts/content/weapon_definition.gd): `weapon_type` (must match the folder), `profile`, `damage`, `damage_type`, `scaling_stat`, `scaling_modifier`, `atk_x`, `hit`, `crit`, `crit_x`, `range_min`, `range_max`, `effective_against` |
| Staff | `items/weapons/staff/` | [StaffDefinition](../../bandit-bash/scripts/content/staff_definition.gd), a weapon of type `staff`: `staff_kind`, `base_amount` (+ Might), `full_heal`, `area_shape_id`, `uses` (per map; 0 unlimited) |
| Equipment | `items/equipment/` | [EquipmentDefinition](../../bandit-bash/scripts/content/equipment_definition.gd): `category`, `granted_tags` |
| Trinket | `items/trinkets/` | [TrinketDefinition](../../bandit-bash/scripts/content/trinket_definition.gd): its effects are the trinket |
| Consumable | `items/consumables/` | [ConsumableDefinition](../../bandit-bash/scripts/content/consumable_definition.gd): `use_kind`, `amount`, `uses` and `uses_lane` (per map or for the run), `cooked_gains`, `cooked_hit` |

- **Range** starts at 1 for anything that attacks; range 0 targets the user (a self staff).
- **Prices aren't fields.** One table by kind and rarity sets them
  ([Prices](../../bandit-bash/scripts/content/prices.gd)); Basic, Legendary and Unique items are never
  sold, and every sellable rarity of a kind must have a price.
- **Pools are automatic.** Loot, the item pick and the Armory draw from every item of a kind at a
  rolled rarity ([ItemPools](../../bandit-bash/scripts/content/item_pools.gd)), Common to Rare only.
  A new sellable item joins its pools by existing, which changes what a given seed draws.
- **`icon`** is the item's picture in reward rows, item picks, placement, the unit detail and the
  forecast: painted, about 32 units square, drawn untinted, under `assets/sprites/items/<kind>/`.
  Unset, those places show a "?" mark, and the `ui/art` suite fails. Display names must be unique,
  since the battle finds an icon by its label. Sources go in [art-sources.md](art-sources.md#item-icons).
- **An enemy-only weapon** (the Fangs, the Shieldmace) is a weapon of Basic rarity, so it is never
  loot, stock or sold.
- A **standalone effect** that an event grants to an item (*Infuse*) goes in `data/effects/<id>.tres`
  as a bare `EffectDefinition`.

## Heirlooms and curses

A heirloom is a [HeirloomDefinition](../../bandit-bash/scripts/content/heirloom_definition.gd) in
`data/heirlooms/`, starting and Commander Heirlooms included.

| Field | Means |
|-------|-------|
| `tier` | `common`, `uncommon`, `rare`, `shop`, `starting` or `commander`; sets its price |
| `kind` | `profile`, `behavior`, `economy` or `army`; empty for Shop, starting and commander heirlooms |
| `is_coop_only` | Offered only in co-op, since it does nothing in solo |
| `icon` | Its symbol on the heirloom bar: white on transparent, about 24 units square, tinted by the bar. Unset: the bar's generic mark. The placeholders and candidate art are in [art-sources.md](art-sources.md#for-heirlooms-and-curses-not-used-yet) |
| `effects` | Scoped Your Unit or wider, never This unit. Tag an effect that reaches other players' units `unique` |

An economy, XP or army-size heirloom is an always-on `ModifyValue` on a campaign value key, adding
to its base, so copies stack ([effect-triggers.md](effect-triggers.md#campaign)).

A curse is a [CurseDefinition](../../bandit-bash/scripts/content/curse_definition.gd) in
`data/curses/`: a heirloom whose `tier` is `minor`, `major` or `severe`, whose `kind` stays empty,
and whose effects carry the `curse` tag, so they resolve after every other reaction. It is never
sold, and no curse touches the economy.

## Runes

`data/runes/<id>.tres`, a [RuneDefinition](../../bandit-bash/scripts/content/rune_definition.gd):
`target_kind` (`unit`, `pair` or `object`), `target_side` (`player` or `enemy`, for a unit rune) and
`needs_unacted_target` (Haste). Its effects are what it does to its target, with no trigger. Every
rune carries at least one effect, because combat finds a cast rune's definition by it; a rune whose
work the resolver or the map does (Recall, Spark) holds only its wording in a `CustomOperation`.
Runes cost one flat price. `data/prefixes/runes/` is reserved for rune prefixes, which are
post-MVP: nothing reads it.

## Prefixes

| Kind | Folder | Fields |
|------|--------|--------|
| Unit prefix | `prefixes/units/` | [UnitPrefixDefinition](../../bandit-bash/scripts/content/unit_prefix_definition.gd): `tier` (−2 to +2), `stat_deltas`, `growth_deltas`, `hit_delta` |
| Weapon prefix | `prefixes/weapons/all/` (any weapon) or `prefixes/weapons/<type>/` (that type only) | [WeaponPrefixDefinition](../../bandit-bash/scripts/content/weapon_prefix_definition.gd): `tier`, `weapon_types` (empty in `all/`, exactly the folder's type otherwise), `staff_kinds`, and the damage, Hit, crit, CritX, AtkX, weight and range deltas |

A prefix applies as stat deltas sourced to it, so breakdowns name it.

## Shapes

`data/shapes/<id>.tres`, a [TargetShape](../../bandit-bash/scripts/content/target_shape.gd):
`kind` (`tile`, `radius`, `square`, `cross`), `size` (grid distance) and `includes_center`. Every
`Area` selector, area staff (`area_shape_id`), splash and keg blast names a shape file: the content
test fails an `Area` that builds its own. Reuse an existing shape before adding one.

## Enemies

### A class

`data/enemies/<id>.tres`, an [EnemyClassDefinition](../../bandit-bash/scripts/content/enemy_class_definition.gd):
a unit type on the player's rules (every field above but the upgrade, role and commander, which stay
empty) plus:

| Field | Means |
|-------|-------|
| `behavior` | `AGGRESSIVE`, `GUARD`, `HOLD`, `SUPPORT` or `SKIRMISHER`; sets its intent icon |
| `target_rule_id`, `target_rule_text` | Its AI's target rule from `ContentIds.TARGET_RULES`, and how players read it beside the intent. Both required |
| `starting_weapon_id`, `starting_equipment_id` | Its gear. An enemy's weapons and staves never run out |
| `signature_move`, `signature_name` | One of its `effects` on a telegraphed cooldown, shown as an intent the phase before it fires, and its name ("Command"; empty: the trait name) |
| `base_class_id` | For a mini-boss: the class it is built on |
| `holds_post` | It never leaves its starting tile and keeps its behavior after the darkness arrives (the Powder Baron) |

A unit of the class at level L has its base plus floor(growth % × (L − 1)) in each stat and never
rolls a level-up. It is its own catalog kind, never a player unit type. It needs a sprite in the
unit sprite table, like a unit type.

### A pack

`data/enemies/packs/<id>.tres`, a [PackDefinition](../../bandit-bash/scripts/content/pack_definition.gd):

| Field | Means |
|-------|-------|
| `pool` | `BASIC` (a step's first two standard combats), `HARD` (its later ones), `KEY` (a mini-boss's escort) or `NONE` (never drawn: tests and fixed maps) |
| `step_1_counts`, `step_2_counts`, `step_3_counts` | Units of each class id at each difficulty step, in placement order. A drawn pack fields exactly 3, 4 and 5; every class it names appears at every step |
| `leader_class_id` | A basic or hard pack's leader: one of its own classes, at every step |
| `mini_boss_id` | A key pack's mini-boss; only a key pack names one |

Setup step 4 ([EnemySetup](../../bandit-bash/scripts/enemies/enemy_setup.gd)) draws one pack from
the combat's pool with the shared stream and fills the map's enemy slots in layout order. A new
drawn pack joins its pool by existing. Reinforcement waves draw from the standard pools too.

### An elite

An elite is a pack's leader. On a map with a leader slot (Defeat the Leader), setup places the
leader there at its step's level +2 with a positive prefix it draws (`UnitPrefixDefinition.roll_elite`),
and the objective is to defeat it. Elsewhere the leader's class fights as an ordinary unit of the
pack. To make one, name the class as `leader_class_id`; give the class a signature move if the
elite should have one (enemy-roster.md, Elites).

### A mini-boss

A mini-boss is an enemy class with a `base_class_id`: it carries that class's stats, growths, gear,
behavior and trait, plus its own `signature_move` and `signature_name`. Make it a key pack's
`mini_boss_id`, and never put it in any pack's counts. Every class a key pack names is in the run's
mini-boss draw: a seeded shuffle, each key combat taking the next, none repeating until all have
fought. It stands on the key map's leader slot at its step's level +2 with a positive prefix (the
+2 replaces the key combat's +1, an `# ASSUMPTION` in `enemy_setup.gd`); its escort fills the
enemy slots at the step's level +1.

The boss is scripted per map, not drawn: its map names its pack (pool `NONE`), levels and prefix
([map-authoring.md](map-authoring.md#a-map-is-two-files)).

## The tests

The content test is the `content` suite (`tests/content/`). Over all of `data/` and over fixture
trees with one bad file per rule ([content_rules.gd](../../bandit-bash/tests/content/content_rules.gd)),
it fails on:

- the id isn't the file name, or repeats; a reference to an id that doesn't exist; a string id
  outside its list;
- a file outside its kind's folder (a weapon's folder is its type);
- a block with no text; an effect with no operations (except a key's, lockpick's or Burglar's
  Roll's opener); an effect id repeated inside one carrier;
- a heirloom scoped This unit; an inline operation on a trigger with no inline window; a warning
  for a heirloom scoped Any Ally Unit or wider without `unique`;
- a weapon or staff without a range, or an attack starting below 1;
- a sellable item without a price, or a Basic, Legendary or Unique item with one; an item with
  uses that also has a charged use effect;
- an `Area` that doesn't reuse a shape file;
- a faction listing its commander among its units, or starting gear in the wrong slot;
- an enemy class outside `enemies/`, without target rule text, or with a role or as a commander;
  a pack outside `enemies/packs/`, naming a non-enemy, missing a class at a step, the wrong size,
  without its leader at every step, or a non-key pack naming a mini-boss; a mini-boss that doesn't
  match its base class, has no signature move, or sits in a pack.

The suite also hashes every definition before and after its run, so nothing changes one.

**The listed-content cases** check the real data against the design docs, and each lists what a
folder must hold, so a new file fails until it is listed there too:
`heirloom_content_cases.gd` (heirlooms and curses), `item_content_cases.gd` (equipment, trinkets,
consumables, runes), `weapon_content_cases.gd` (weapons and staves), `roster_unit_cases.gd`,
`roster_enemy_cases.gd` (classes, enemy weapons and packs) and `pool_cases.gd` (unit prefixes).
Each keeps an effect-text snapshot too. Mini-bosses, elites and the boss have their own cases in
`tests/enemies/` (`mini_boss_cases.gd`, `elite_cases.gd`, `boss_cases.gd`).

The `ui/art` suite checks every unit type, enemy class and item for its sprite or icon.

Run `sh bandit-bash/tools/run_tests.sh content ui/art` (add `enemies` for enemy content).

## Checklist

1. Write it into its design doc first; the numbers live there.
2. Make the `.tres` in its folder, named by its id, in the inspector.
3. Give it its picture: an `icon`, or a sprite table entry; record the source in art-sources.md.
4. Add it to its listed-content case and its effect-text snapshot.
5. Run the suites above.
