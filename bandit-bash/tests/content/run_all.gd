# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the content definitions: one fixture per kind loads with its fields and
## effect text, [method TargetShape.tiles] for every kind at sizes 0 to 3, the [Prices] tables,
## the [ContentIds] lists and their inspector hints, and the [code]res://data/[/code] folders.
## [EffectCatalog] and the content test, its rules over all of [code]res://data/[/code] and the
## rule fixtures, live in catalog_cases.gd. Every catalog definition is hashed before the first
## case and after the last, and the run fails if any changed.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/content/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. The fixtures live in
## [code]tests/content/fixtures/[/code], never under [code]data/[/code], which the catalog loads.
## The cases run in [code]_init[/code]; nothing here uses an autoload.

# A preloaded script used as a type (gdscript.md, Naming): the cases script has no class name.
const CatalogCases = preload("res://tests/content/catalog_cases.gd")

const FIXTURE_DIR: String = "res://tests/content/fixtures/"

const COMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON
const UNCOMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.UNCOMMON
const RARE: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE

# items.md's price table, transcribed independently of prices.gd: kind, then Common, Uncommon and
# Rare gold.
const PRICE_TABLE: Array[Array] = [
	["weapon", 40, 60, 200],
	["equipment", 60, 100, 200],
	["trinket", 30, 50, 80],
	["consumable", 25, 50, 100],
]

# heirlooms.md's Armory prices, transcribed independently: tier, gold (-1: never sold).
const HEIRLOOM_TABLE: Array[Array] = [
	["common", 150],
	["uncommon", 200],
	["rare", 250],
	["shop", 150],
	["starting", -1],
	["commander", -1],
]

# The content catalog plan's Data layout table; the weapon type folders are added from the list.
const DATA_FOLDERS: Array[String] = [
	"units",
	"units/commanders",
	"prefixes/units",
	"prefixes/weapons/all",
	"prefixes/runes",
	"factions",
	"items/equipment",
	"items/trinkets",
	"items/consumables",
	"runes",
	"shapes",
	"heirlooms",
	"curses",
	"enemies",
	"effects",
	"terrain",
]

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Content definition tests ---")
	# Hashed before any case loads a definition, so the check covers the whole run.
	var before: Dictionary[String, String] = CatalogCases.hash_catalog()

	_test_unit_type_fixture()
	_test_commander_fixture()
	_test_prefix_fixtures()
	_test_faction_fixture()
	_test_weapon_fixtures()
	_test_other_item_fixtures()
	_test_rune_fixture()
	_test_heirloom_fixtures()
	_test_shape_fixture()
	_test_shape_counts()
	_test_shape_exact_tiles()
	_test_shape_edges()
	_test_item_prices()
	_test_unsold_rarities()
	_test_rune_and_heirloom_prices()
	_test_scrap_values()
	_test_id_lists_have_no_duplicates()
	_test_id_lists_contents()
	_test_inspector_hints()
	_test_data_layout()
	CatalogCases.new(_check).run()
	_test_definitions_unchanged(before)

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_unit_type_fixture() -> void:
	var unit: UnitTypeDefinition = _load("unit_type") as UnitTypeDefinition
	_check("fixture unit_type: loads as a UnitTypeDefinition", unit != null)
	if unit == null:
		return
	_check_carrier("unit_type", unit, 1)
	_check("fixture unit_type: role and weapon types", (
			unit.role == "dagger" and unit.weapon_types == PackedStringArray(["dagger"])
	))
	_check(
			"fixture unit_type: movement type",
			unit.movement_type == CombatGrid.MovementType.MOBILE
	)
	_check("fixture unit_type: seven base stats by Stat", (
			unit.base_stats.size() == 7
			and unit.base_stats[CombatValue.Stat.SPD] == 9
			and unit.base_stats[CombatValue.Stat.MOV] == 6
	), str(unit.base_stats))
	_check("fixture unit_type: five growths by Stat", (
			unit.growths.size() == 5 and unit.growths[CombatValue.Stat.HP] == 65
	), str(unit.growths))
	_check("fixture unit_type: the upgraded trait has text", _texts_filled(
			unit.upgraded_effects, _describe_all(unit.upgraded_effects)
	))
	_check("fixture unit_type: an added weapon type grants Sidearm", unit.grants_sidearm())
	_check("fixture unit_type: the upgrade keeps the movement type", (
			not unit.upgrade_changes_movement()
			and unit.upgrade_movement_type == UnitTypeDefinition.KEEP_MOVEMENT
	))
	_check("fixture unit_type: not a commander", not unit.is_commander)


func _test_commander_fixture() -> void:
	var commander: UnitTypeDefinition = _load("commander") as UnitTypeDefinition
	_check("fixture commander: loads as a UnitTypeDefinition", commander != null)
	if commander == null:
		return
	_check_carrier("commander", commander, 1)
	_check("fixture commander: commander flag and heirloom id", (
			commander.is_commander and commander.commander_heirloom_id == "iron_heart"
	))
	_check("fixture commander: no upgrade, so no Sidearm", (
			commander.upgraded_effects.is_empty() and not commander.grants_sidearm()
	))


func _test_prefix_fixtures() -> void:
	var unit_prefix: UnitPrefixDefinition = _load("unit_prefix") as UnitPrefixDefinition
	_check("fixture unit_prefix: loads as a UnitPrefixDefinition", unit_prefix != null)
	if unit_prefix != null:
		_check_carrier("unit_prefix", unit_prefix, 0)
		_check("fixture unit_prefix: tier and deltas", (
				unit_prefix.tier == 1
				and unit_prefix.stat_deltas[CombatValue.Stat.HP] == 4
				and unit_prefix.growth_deltas[CombatValue.Stat.DEF] == 10
				and unit_prefix.hit_delta == 0
		))

	var weapon_prefix: WeaponPrefixDefinition = _load("weapon_prefix") as WeaponPrefixDefinition
	_check("fixture weapon_prefix: loads as a WeaponPrefixDefinition", weapon_prefix != null)
	if weapon_prefix != null:
		_check_carrier("weapon_prefix", weapon_prefix, 0)
		_check("fixture weapon_prefix: types and deltas", (
				weapon_prefix.weapon_types == PackedStringArray(["bow"])
				and weapon_prefix.staff_kinds.is_empty()
				and weapon_prefix.hit_delta == 10
				and weapon_prefix.range_max_delta == 1
				and weapon_prefix.damage_delta == 0
		))


func _test_faction_fixture() -> void:
	var faction: FactionDefinition = _load("faction") as FactionDefinition
	_check("fixture faction: loads as a FactionDefinition", faction != null)
	if faction == null:
		return
	_check_carrier("faction", faction, 0)
	_check("fixture faction: commander, army and size", (
			faction.commander_id == "commander"
			and faction.starting_unit_type_ids.size() == 3
			and faction.max_army_size == 4
	))
	_check("fixture faction: gear per starting unit", (
			faction.starting_gear.size() == 2
			and faction.starting_gear[1] == PackedStringArray(["simple_bow", "", "potion"])
	), str(faction.starting_gear))


func _test_weapon_fixtures() -> void:
	var weapon: WeaponDefinition = _load("weapon") as WeaponDefinition
	_check("fixture weapon: loads as a WeaponDefinition", weapon != null)
	if weapon != null:
		_check_carrier("weapon", weapon, 0)
		_check("fixture weapon: kind, rarity and type", (
				weapon.kind == ContentIds.ITEM_WEAPON
				and weapon.rarity == ItemDefinition.Rarity.BASIC
				and weapon.weapon_type == "bow"
		))
		_check("fixture weapon: combat numbers and defaults", (
				weapon.damage == 6
				and weapon.range_min == 2
				and weapon.range_max == 3
				and weapon.hit == 100
				and weapon.atk_x == 1
				and is_equal_approx(weapon.crit_x, 3.0)
				and weapon.scaling_stat == CombatValue.Stat.MGT
				and is_equal_approx(weapon.scaling_modifier, 1.0)
				and weapon.damage_type == CombatFact.DamageType.PHYSICAL
				and weapon.effective_against == PackedStringArray(["flier"])
		))

	var staff: StaffDefinition = _load("staff") as StaffDefinition
	_check("fixture staff: loads as a StaffDefinition", staff != null)
	if staff == null:
		return
	_check_carrier("staff", staff, 0)
	_check("fixture staff: a weapon of type staff", (
			staff is WeaponDefinition
			and staff.kind == ContentIds.ITEM_WEAPON
			and staff.weapon_type == "staff"
	))
	_check("fixture staff: kind, amount, shape and uses", (
			staff.staff_kind == "block"
			and staff.base_amount == 3
			and staff.area_shape_id == "target_shape"
			and staff.uses == 2
			and staff.range_max == 2
	))


func _test_other_item_fixtures() -> void:
	var equipment: EquipmentDefinition = _load("equipment") as EquipmentDefinition
	_check("fixture equipment: loads as an EquipmentDefinition", equipment != null)
	if equipment != null:
		_check_carrier("equipment", equipment, 2)
		_check("fixture equipment: kind, category and weight", (
				equipment.kind == ContentIds.ITEM_EQUIPMENT
				and equipment.category == "shield"
				and equipment.weight == 4
		))

	var trinket: TrinketDefinition = _load("trinket") as TrinketDefinition
	_check("fixture trinket: loads as a TrinketDefinition", trinket != null)
	if trinket != null:
		_check_carrier("trinket", trinket, 1)
		_check("fixture trinket: kind and no weight", (
				trinket.kind == ContentIds.ITEM_TRINKET and trinket.weight == 0
		))

	var consumable: ConsumableDefinition = _load("consumable") as ConsumableDefinition
	_check("fixture consumable: loads as a ConsumableDefinition", consumable != null)
	if consumable == null:
		return
	_check_carrier("consumable", consumable, 1)
	_check("fixture consumable: use kind, amount and uses", (
			consumable.kind == ContentIds.ITEM_CONSUMABLE
			and consumable.use_kind == "ingredient"
			and consumable.amount == 5
			and consumable.uses == 1
			and consumable.uses_lane == EffectTerms.Lane.CAMPAIGN
	))
	_check("fixture consumable: cooked gains", (
			consumable.cooked_gains.size() == 1
			and consumable.cooked_gains[CombatValue.Stat.RES] == 1
			and consumable.cooked_hit == 0
	), str(consumable.cooked_gains))


func _test_rune_fixture() -> void:
	var rune: RuneDefinition = _load("rune") as RuneDefinition
	_check("fixture rune: loads as a RuneDefinition", rune != null)
	if rune == null:
		return
	_check_carrier("rune", rune, 1)
	_check("fixture rune: target kind and shape", (
			rune.target_kind == "area" and rune.shape_id == "target_shape"
	))


func _test_heirloom_fixtures() -> void:
	var heirloom: HeirloomDefinition = _load("heirloom") as HeirloomDefinition
	_check("fixture heirloom: loads as a HeirloomDefinition", heirloom != null)
	if heirloom != null:
		_check_carrier("heirloom", heirloom, 1)
		_check("fixture heirloom: tier, kind and tags", (
				heirloom.tier == "common"
				and heirloom.kind == "economy"
				and not heirloom.is_coop_only
				and not heirloom.has_effect_tag(EffectDefinition.Tag.CURSE)
				and not heirloom.has_effect_tag(EffectDefinition.Tag.UNIQUE)
		))

	var curse: CurseDefinition = _load("curse") as CurseDefinition
	_check("fixture curse: loads as a CurseDefinition", curse != null)
	if curse == null:
		return
	_check_carrier("curse", curse, 1)
	_check("fixture curse: an heirloom with a curse tier", (
			curse is HeirloomDefinition
			and ContentIds.CURSE_TIERS.has(curse.tier)
			and curse.kind.is_empty()
	))
	_check("fixture curse: its effect is tagged curse", (
			curse.has_effect_tag(EffectDefinition.Tag.CURSE)
	))


func _test_shape_fixture() -> void:
	var shape: TargetShape = _load("target_shape") as TargetShape
	_check("fixture target_shape: loads as a TargetShape", shape != null)
	if shape == null:
		return
	_check_carrier("target_shape", shape, 0)
	_check("fixture target_shape: the target and its four neighbors", (
			shape.tiles(Vector2i(4, 4)).size() == 5
			and shape.tiles(Vector2i(4, 4)).has(Vector2i(4, 4))
			and shape.distance == TargetShape.Distance.GRID
	))


func _test_shape_counts() -> void:
	# Expected tile counts at sizes 0 to 3, center included.
	var expected: Dictionary[String, PackedInt32Array] = {
		ContentIds.SHAPE_TILE: PackedInt32Array([1, 1, 1, 1]),
		ContentIds.SHAPE_RADIUS: PackedInt32Array([1, 5, 13, 25]),
		ContentIds.SHAPE_SQUARE: PackedInt32Array([1, 9, 25, 49]),
		ContentIds.SHAPE_CROSS: PackedInt32Array([1, 5, 9, 13]),
	}
	_check(
			"shapes: every shape kind has expected counts",
			expected.size() == ContentIds.SHAPE_KINDS.size()
	)
	var center: Vector2i = Vector2i(5, -2)
	for kind: String in ContentIds.SHAPE_KINDS:
		for size: int in 4:
			var with_center: Array[Vector2i] = _shape(kind, size, true).tiles(center)
			var without: Array[Vector2i] = _shape(kind, size, false).tiles(center)
			var want: int = expected[kind][size]
			_check("shapes: %s size %d covers %d tiles" % [kind, size, want], (
					with_center.size() == want and _is_unique(with_center)
			), str(with_center))
			_check("shapes: %s size %d without its center" % [kind, size], (
					without.size() == want - 1 and not without.has(center)
			), str(without))
			_check("shapes: %s size %d stays in its metric" % [kind, size], (
					_fits_metric(kind, size, center, with_center)
			), str(with_center))
			_check("shapes: %s size %d is in row order" % [kind, size], (
					_is_row_ordered(with_center)
			), str(with_center))


func _test_shape_exact_tiles() -> void:
	var origin: Vector2i = Vector2i.ZERO
	var radius_one: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1),
	]
	_check(
			"shapes: radius 1 is the center and its four neighbors",
			_shape(ContentIds.SHAPE_RADIUS, 1, true).tiles(origin) == radius_one
	)
	var cross_two: Array[Vector2i] = [
		Vector2i(0, -2), Vector2i(0, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(0, 2),
	]
	_check(
			"shapes: cross 2 is the row and column, two each way",
			_shape(ContentIds.SHAPE_CROSS, 2, true).tiles(origin) == cross_two
	)
	var square_one: Array[Vector2i] = _shape(ContentIds.SHAPE_SQUARE, 1, true).tiles(origin)
	_check("shapes: square 1 includes the diagonals", (
			square_one.has(Vector2i(-1, -1)) and square_one.has(Vector2i(1, 1))
	))
	var center_only: Array[Vector2i] = [Vector2i(2, 7)]
	_check(
			"shapes: tile ignores its size",
			_shape(ContentIds.SHAPE_TILE, 3, true).tiles(Vector2i(2, 7)) == center_only
	)


func _test_shape_edges() -> void:
	_check(
			"shapes: an unknown kind covers nothing",
			_shape("line", 2, true).tiles(Vector2i.ZERO).is_empty()
	)
	_check(
			"shapes: tile without its center covers nothing",
			_shape(ContentIds.SHAPE_TILE, 0, false).tiles(Vector2i.ZERO).is_empty()
	)
	var fresh: TargetShape = TargetShape.new()
	_check("shapes: defaults are the center tile by grid distance", (
			fresh.kind == ContentIds.SHAPE_TILE
			and fresh.size == 0
			and fresh.distance == TargetShape.Distance.GRID
			and fresh.includes_center
	))


func _test_item_prices() -> void:
	_check("prices: the table covers every item kind", (
			PRICE_TABLE.size() == ContentIds.ITEM_KINDS.size()
			and Prices.ITEM_PRICES.size() == ContentIds.ITEM_KINDS.size()
	))
	for kind: String in Prices.ITEM_PRICES:
		_check("prices: %s is an item kind" % [kind], ContentIds.ITEM_KINDS.has(kind))
	for row: Array in PRICE_TABLE:
		var kind: String = row[0]
		var rarities: Array[ItemDefinition.Rarity] = [COMMON, UNCOMMON, RARE]
		for index: int in rarities.size():
			var rarity: ItemDefinition.Rarity = rarities[index]
			var want: int = row[index + 1]
			var got: int = Prices.buy_price(kind, rarity)
			_check(
					"prices: %s %s costs %d" % [_rarity_name(rarity), kind, want],
					got == want,
					str(got)
			)
	var staff: StaffDefinition = _load("staff") as StaffDefinition
	_check("prices: a Rare staff costs the Rare weapon price", (
			staff != null and Prices.item_price(staff) == 200
	))
	_check("prices: an unknown kind has no price", (
			Prices.buy_price("ingredient", COMMON) == Prices.NO_PRICE
	))
	_check("prices: a null item has no price", Prices.item_price(null) == Prices.NO_PRICE)


func _test_unsold_rarities() -> void:
	var unsold: Array[ItemDefinition.Rarity] = [
		ItemDefinition.Rarity.BASIC,
		ItemDefinition.Rarity.LEGENDARY,
		ItemDefinition.Rarity.UNIQUE,
	]
	for rarity: ItemDefinition.Rarity in ItemDefinition.Rarity.values():
		var sold: bool = Prices.is_sellable(rarity)
		_check("prices: %s is %s" % [_rarity_name(rarity), "sold" if sold else "never sold"], (
				sold != unsold.has(rarity)
		))
	for kind: String in ContentIds.ITEM_KINDS:
		for rarity: ItemDefinition.Rarity in unsold:
			_check("prices: %s %s has no price" % [_rarity_name(rarity), kind], (
					Prices.buy_price(kind, rarity) == Prices.NO_PRICE
			))
	var weapon: WeaponDefinition = _load("weapon") as WeaponDefinition
	_check("prices: a Basic weapon has no price", (
			weapon != null and Prices.item_price(weapon) == Prices.NO_PRICE
	))


func _test_rune_and_heirloom_prices() -> void:
	_check("prices: a rune costs 30", Prices.RUNE_PRICE == 30)
	_check("prices: the heirloom table covers every tier", (
			HEIRLOOM_TABLE.size() == ContentIds.HEIRLOOM_TIERS.size()
	))
	for row: Array in HEIRLOOM_TABLE:
		var tier: String = row[0]
		var want: int = row[1]
		_check(
				"prices: a %s heirloom costs %d" % [tier, want],
				Prices.heirloom_price(tier) == want,
				str(Prices.heirloom_price(tier))
		)
	for tier: String in Prices.HEIRLOOM_PRICES:
		_check("prices: %s is an heirloom tier" % [tier], ContentIds.HEIRLOOM_TIERS.has(tier))
	for tier: String in ContentIds.CURSE_TIERS:
		_check("prices: a %s curse is never sold" % [tier], (
				Prices.heirloom_price(tier) == Prices.NO_PRICE
		))


func _test_scrap_values() -> void:
	var percent: float = Prices.default_scrap_percent()
	_check("scrap: the default rate is 20%", is_equal_approx(percent, 20.0), str(percent))
	_check("scrap: a Common weapon scraps for 8", (
			Prices.scrap_value(ContentIds.ITEM_WEAPON, COMMON, percent) == 8
	))
	_check("scrap: a Rare equipment piece scraps for 40", (
			Prices.scrap_value(ContentIds.ITEM_EQUIPMENT, RARE, percent) == 40
	))
	_check("scrap: a Legendary weapon counts at the Rare price", (
			Prices.scrap_basis(ContentIds.ITEM_WEAPON, ItemDefinition.Rarity.LEGENDARY) == 200
			and Prices.scrap_value(
					ContentIds.ITEM_WEAPON, ItemDefinition.Rarity.LEGENDARY, percent
			) == 40
	))
	_check("scrap: a Unique trinket counts at the Rare price", (
			Prices.scrap_value(ContentIds.ITEM_TRINKET, ItemDefinition.Rarity.UNIQUE, percent)
			== 16
	))
	_check("scrap: a Basic item has no basis and scraps for 0", (
			Prices.scrap_basis(ContentIds.ITEM_WEAPON, ItemDefinition.Rarity.BASIC)
			== Prices.NO_PRICE
			and Prices.scrap_value(ContentIds.ITEM_WEAPON, ItemDefinition.Rarity.BASIC, percent)
			== 0
	))
	_check("scrap: Scrapper's Tongs' 40% doubles it", (
			Prices.scrap_value(ContentIds.ITEM_CONSUMABLE, COMMON, 40.0) == 10
	))
	_check("scrap: halves round up to whole gold", (
			Prices.scrap_value(ContentIds.ITEM_CONSUMABLE, COMMON, 10.0) == 3
	))


func _test_id_lists_have_no_duplicates() -> void:
	var lists: Dictionary[String, PackedStringArray] = _id_lists()
	for list_name: String in lists:
		var ids: PackedStringArray = lists[list_name]
		var seen: Dictionary[String, bool] = {}
		var repeated: PackedStringArray = []
		var malformed: PackedStringArray = []
		var snake: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
		for id: String in ids:
			if seen.has(id):
				repeated.append(id)
			seen[id] = true
			if snake.search(id) == null:
				malformed.append(id)
		_check("ids: %s has no duplicates" % [list_name], repeated.is_empty(), str(repeated))
		_check("ids: %s holds snake_case ids" % [list_name], (
				not ids.is_empty() and malformed.is_empty()
		), str(malformed))


func _test_id_lists_contents() -> void:
	_check("ids: the ten weapon types", ContentIds.WEAPON_TYPES == PackedStringArray([
		"sword", "axe", "lance", "bow", "gauntlets", "dagger", "anima", "holy", "dark", "staff",
	]))
	_check("ids: the four tags", ContentIds.TAGS == PackedStringArray([
		"armored", "mounted", "flier", "terror",
	]))
	_check("ids: one role per roster row, the shover included", (
			ContentIds.ROLES.size() == 14 and ContentIds.ROLES.has("shover")
	))
	_check("ids: rune target kinds", ContentIds.RUNE_TARGET_KINDS == PackedStringArray([
		"area", "random", "pair",
	]))
	_check("ids: shape kinds", ContentIds.SHAPE_KINDS == PackedStringArray([
		"tile", "radius", "square", "cross",
	]))
	var item_kinds: PackedStringArray = [
		WeaponDefinition.new().kind,
		EquipmentDefinition.new().kind,
		TrinketDefinition.new().kind,
		ConsumableDefinition.new().kind,
	]
	_check(
			"ids: every item class names its own kind, in list order",
			item_kinds == ContentIds.ITEM_KINDS,
			str(item_kinds)
	)
	_check("ids: a staff is a weapon", StaffDefinition.new().kind == ContentIds.ITEM_WEAPON)


func _test_inspector_hints() -> void:
	var single: Dictionary = {"name": &"role", "type": TYPE_STRING}
	ContentIds.apply_hint(single, PackedStringArray(["a", "b"]))
	_check("hints: a String export becomes a dropdown", (
			_hint(single) == PROPERTY_HINT_ENUM and _hint_string(single) == "a,b"
	))
	var many: Dictionary = {"name": &"tags", "type": TYPE_PACKED_STRING_ARRAY}
	ContentIds.apply_hint(many, PackedStringArray(["a", "b"]))
	_check("hints: a PackedStringArray export lists dropdowns", (
			_hint(many) == PROPERTY_HINT_TYPE_STRING
			and _hint_string(many) == "%d/%d:a,b" % [TYPE_STRING, PROPERTY_HINT_ENUM]
	), str(many))

	var unit: Dictionary[String, Dictionary] = _properties(UnitTypeDefinition.new())
	_check("hints: a unit type's role lists the roles", (
			_property_hint(unit, "role") == PROPERTY_HINT_ENUM
			and _property_hint_string(unit, "role") == ",".join(ContentIds.ROLES)
	))
	_check("hints: an upgrade can keep the movement type", (
			_property_hint_string(unit, "upgrade_movement_type").begins_with(
					"Unchanged:%d," % [UnitTypeDefinition.KEEP_MOVEMENT]
			)
	))
	var staff: Dictionary[String, Dictionary] = _properties(StaffDefinition.new())
	_check("hints: a staff keeps its weapon hints and adds its own", (
			_property_hint(staff, "weapon_type") == PROPERTY_HINT_ENUM
			and _property_hint_string(staff, "staff_kind") == ",".join(ContentIds.STAFF_KINDS)
	))
	var curse: Dictionary[String, Dictionary] = _properties(CurseDefinition.new())
	_check("hints: a curse's tier lists the curse tiers", (
			_property_hint_string(curse, "tier") == ",".join(ContentIds.CURSE_TIERS)
	))


func _test_data_layout() -> void:
	var folders: Array[String] = DATA_FOLDERS.duplicate()
	for weapon_type: String in ContentIds.WEAPON_TYPES:
		folders.append("items/weapons/%s" % [weapon_type])
		folders.append("prefixes/weapons/%s" % [weapon_type])
	var missing: PackedStringArray = []
	for folder: String in folders:
		if not DirAccess.dir_exists_absolute("res://data/%s" % [folder]):
			missing.append(folder)
	_check(
			"data: every folder in the plan's layout exists (%d)" % [folders.size()],
			missing.is_empty(),
			", ".join(missing)
	)
	var extra: PackedStringArray = []
	for parent: String in ["items/weapons", "prefixes/weapons"]:
		for child: String in DirAccess.get_directories_at("res://data/%s" % [parent]):
			if child != "all" and not ContentIds.WEAPON_TYPES.has(child):
				extra.append("%s/%s" % [parent, child])
	_check("data: no weapon folder outside the weapon types", extra.is_empty(), ", ".join(extra))


# Definitions are read-only (event bus plan, Definitions and instances): [param before] is
# [method CatalogCases.hash_catalog] from the start of the run.
func _test_definitions_unchanged(before: Dictionary[String, String]) -> void:
	var after: Dictionary[String, String] = CatalogCases.hash_catalog()
	var changed: PackedStringArray = []
	for id: String in before:
		if after.get(id, "") != before[id]:
			changed.append(id)
	_check("catalog: no definition changed during the run (%d hashed)" % [before.size()], (
			changed.is_empty() and after.size() == before.size()
	), ", ".join(changed))


# Checks what every fixture shares: its id is its file name, it has a display name, and its effect
# text has one non-empty line per effect.
func _check_carrier(name: String, carrier: EffectCarrierDefinition, effect_count: int) -> void:
	_check("fixture %s: id is the file name" % [name], carrier.id == name, carrier.id)
	_check("fixture %s: has a display name" % [name], not carrier.display_name.is_empty())
	var texts: PackedStringArray = carrier.describe()
	_check(
			"fixture %s: %d effect(s), each with text" % [name, effect_count],
			carrier.effects.size() == effect_count and _texts_filled(carrier.effects, texts),
			" | ".join(texts)
	)


func _load(name: String) -> Resource:
	var path: String = "%s%s.tres" % [FIXTURE_DIR, name]
	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		push_error("content tests: could not load %s" % [path])
	return resource


func _describe_all(effects: Array[EffectDefinition]) -> PackedStringArray:
	var texts: PackedStringArray = []
	for effect: EffectDefinition in effects:
		texts.append(effect.describe())
	return texts


func _texts_filled(effects: Array[EffectDefinition], texts: PackedStringArray) -> bool:
	if texts.size() != effects.size():
		return false
	for text: String in texts:
		if text.strip_edges().is_empty():
			return false
	return true


func _shape(kind: String, size: int, includes_center: bool) -> TargetShape:
	var shape: TargetShape = TargetShape.new()
	shape.kind = kind
	shape.size = size
	shape.includes_center = includes_center
	return shape


func _is_unique(tiles: Array[Vector2i]) -> bool:
	var seen: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in tiles:
		if seen.has(tile):
			return false
		seen[tile] = true
	return true


func _fits_metric(kind: String, size: int, center: Vector2i, tiles: Array[Vector2i]) -> bool:
	for tile: Vector2i in tiles:
		var offset: Vector2i = tile - center
		var across: int = absi(offset.x)
		var up: int = absi(offset.y)
		var fits: bool = false
		match kind:
			ContentIds.SHAPE_TILE:
				fits = offset == Vector2i.ZERO
			ContentIds.SHAPE_RADIUS:
				fits = across + up <= size
			ContentIds.SHAPE_SQUARE:
				fits = across <= size and up <= size
			ContentIds.SHAPE_CROSS:
				fits = (across == 0 or up == 0) and maxi(across, up) <= size
		if not fits:
			return false
	return true


func _is_row_ordered(tiles: Array[Vector2i]) -> bool:
	for index: int in range(1, tiles.size()):
		var before: Vector2i = tiles[index - 1]
		var after: Vector2i = tiles[index]
		if before.y > after.y or (before.y == after.y and before.x >= after.x):
			return false
	return true


func _id_lists() -> Dictionary[String, PackedStringArray]:
	return {
		"WEAPON_TYPES": ContentIds.WEAPON_TYPES,
		"TAGS": ContentIds.TAGS,
		"ROLES": ContentIds.ROLES,
		"ITEM_KINDS": ContentIds.ITEM_KINDS,
		"STAFF_KINDS": ContentIds.STAFF_KINDS,
		"CONSUMABLE_USE_KINDS": ContentIds.CONSUMABLE_USE_KINDS,
		"EQUIPMENT_CATEGORIES": ContentIds.EQUIPMENT_CATEGORIES,
		"HEIRLOOM_TIERS": ContentIds.HEIRLOOM_TIERS,
		"HEIRLOOM_KINDS": ContentIds.HEIRLOOM_KINDS,
		"CURSE_TIERS": ContentIds.CURSE_TIERS,
		"RUNE_TARGET_KINDS": ContentIds.RUNE_TARGET_KINDS,
		"SHAPE_KINDS": ContentIds.SHAPE_KINDS,
	}


# Each property as the inspector sees it, after _validate_property, by property name.
func _properties(object: Object) -> Dictionary[String, Dictionary]:
	var properties: Dictionary[String, Dictionary] = {}
	for property: Dictionary in object.get_property_list():
		var property_name: String = property["name"]
		properties[property_name] = property
	return properties


func _hint(property: Dictionary) -> int:
	var hint: int = property.get("hint", PROPERTY_HINT_NONE)
	return hint


func _hint_string(property: Dictionary) -> String:
	var hint_string: String = property.get("hint_string", "")
	return hint_string


func _property_hint(properties: Dictionary[String, Dictionary], property_name: String) -> int:
	return _hint(properties.get(property_name, {}) as Dictionary)


func _property_hint_string(
		properties: Dictionary[String, Dictionary], property_name: String
) -> String:
	return _hint_string(properties.get(property_name, {}) as Dictionary)


func _rarity_name(rarity: ItemDefinition.Rarity) -> String:
	return (ItemDefinition.Rarity.find_key(rarity) as String).capitalize()


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
