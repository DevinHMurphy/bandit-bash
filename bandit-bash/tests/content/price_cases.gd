# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     price_cases.gd
# Author:
# Created:  November 16, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The modified-item price cases for tests/content/run_all.gd: each kind's step value, the point
## of every priced delta key, the three event examples on a Common and a Basic weapon (Infuse,
## Upgrade Gear, Forge Resonance), a net-negative change held at the unmodified value, Legendary,
## Unique and Basic bases, halves rounding up, a prefix or a missing granted effect adding nothing,
## and every catalog item's value and scrap value unchanged while unmodified. Reports each case
## through the check callable it is given.
##
## The expected values are transcribed from the design docs and P03 question 8, never read from
## prices.gd. The examples run on an in-memory catalog, so no data file moves them.
##
## @tutorial(Items, Modified items): docs/design/items.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "content"

const COMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON
const UNCOMMON: ItemDefinition.Rarity = ItemDefinition.Rarity.UNCOMMON
const RARE: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE
const BASIC: ItemDefinition.Rarity = ItemDefinition.Rarity.BASIC
const LEGENDARY: ItemDefinition.Rarity = ItemDefinition.Rarity.LEGENDARY
const UNIQUE: ItemDefinition.Rarity = ItemDefinition.Rarity.UNIQUE

# Question 8's step values: each kind's Common-to-Uncommon gap.
const STEPS: Dictionary[String, int] = {
	"weapon": 20,
	"equipment": 40,
	"trinket": 20,
	"consumable": 25,
}

# Question 8's points for +1 of each key; HP, Hit, crit and avoid from unit-roster.md's scale.
const POINTS: Dictionary[int, float] = {
	DamageStage.Key.ATTACK: 1.0,
	CombatValue.Key.MGT: 1.0,
	CombatValue.Key.SPD: 1.0,
	CombatValue.Key.DEF: 1.0,
	CombatValue.Key.RES: 1.0,
	CombatValue.Key.HP: 0.5,
	CombatValue.Key.HIT: 0.1,
	CombatValue.Key.CRIT_CHANCE: 0.1,
	CombatValue.Key.AVOID: 0.1,
	CombatValue.Key.ATK_X: 3.0,
	CombatValue.Key.RANGE_MAX: 2.0,
	CombatValue.Key.NET_WEIGHT: -0.25,
}

# Keys the vision gives no point value.
const UNPRICED_KEYS: Array[int] = [
	CombatValue.Key.MOVEMENT,
	CombatValue.Key.STANCE_MAX,
	CombatValue.Key.PARRY,
	CombatValue.Key.CRIT_X,
	CombatValue.Key.RANGE_MIN,
	CombatValue.Key.CON,
]

# The in-memory catalog's ids.
const HEAL_ON_HIT: String = "price_heal_on_hit"
const COMMON_WEAPON: String = "price_common_weapon"
const BASIC_WEAPON: String = "price_basic_weapon"
const LEGENDARY_WEAPON: String = "price_legendary_weapon"
const UNIQUE_TRINKET: String = "price_unique_trinket"
const COMMON_EQUIPMENT: String = "price_common_equipment"
const COMMON_CONSUMABLE: String = "price_common_consumable"
const UNCOMMON_CONSUMABLE: String = "price_uncommon_consumable"

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _next_id: int = 0


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = _build_catalog()
	_check("prices: the in-memory catalog builds cleanly", _catalog.problems.is_empty(), (
			"; ".join(_catalog.problems)
	))
	_test_step_values()
	_test_delta_points()
	_test_event_examples()
	_test_floor()
	_test_bases()
	_test_rounding()
	_test_unpriced_parts()
	_test_catalog_unchanged()


func _test_step_values() -> void:
	for kind: String in STEPS:
		_check("prices: a %s's step value is %d" % [kind, STEPS[kind]], (
				Prices.step_value(kind) == STEPS[kind]
		), str(Prices.step_value(kind)))
	_check("prices: an unknown kind's step value is 0", Prices.step_value("ingredient") == 0)


func _test_delta_points() -> void:
	for key: int in POINTS:
		_check("prices: +1 of key %d is %.2f points" % [key, POINTS[key]], (
				is_equal_approx(Prices.delta_points(key, 1.0), POINTS[key])
		), str(Prices.delta_points(key, 1.0)))
	_check("prices: the point table prices exactly question 8's keys", (
			Prices.DELTA_POINTS.size() == POINTS.size()
	), str(Prices.DELTA_POINTS.keys()))
	# delta_points on these logs an error, which fails the runner, so the table is checked instead.
	for key: int in UNPRICED_KEYS:
		_check("prices: key %d has no point value yet" % [key], not Prices.DELTA_POINTS.has(key))
	_check("prices: 10 Hit, 10 crit and 10 avoid are 1 point each", (
			is_equal_approx(Prices.delta_points(CombatValue.Key.HIT, 10.0), 1.0)
			and is_equal_approx(Prices.delta_points(CombatValue.Key.CRIT_CHANCE, 10.0), 1.0)
			and is_equal_approx(Prices.delta_points(CombatValue.Key.AVOID, 10.0), 1.0)
	))


func _test_event_examples() -> void:
	# Name, deltas as [key, amount] pairs, granted effects, points, Common value, Basic value.
	var examples: Array[Array] = [
		["Infuse", [[CombatValue.Key.NET_WEIGHT, 2.0]], [HEAL_ON_HIT], 0.5, 50, 10],
		["Upgrade Gear", [
			[DamageStage.Key.ATTACK, 1.0],
			[CombatValue.Key.CRIT_CHANCE, 5.0],
			[CombatValue.Key.NET_WEIGHT, 1.0],
		], [], 1.25, 65, 25],
		["Forge Resonance", [
			[CombatValue.Key.ATK_X, 1.0], [CombatValue.Key.NET_WEIGHT, 4.0],
		], [], 2.0, 80, 40],
	]
	for example: Array in examples:
		var event: String = example[0]
		var deltas: Array = example[1]
		var granted: Array = example[2]
		var points: float = example[3]
		var common: ItemInstance = _modified(COMMON_WEAPON, deltas, granted)
		var basic: ItemInstance = _modified(BASIC_WEAPON, deltas, granted)
		var common_value: int = example[4]
		var basic_value: int = example[5]
		_check("prices: %s is %.2f points" % [event, points], (
				is_equal_approx(Prices.modification_points(common, _catalog), points)
		), str(Prices.modification_points(common, _catalog)))
		_check("prices: %s on a Common weapon is worth %d, scraps for %d" % [
			event, common_value, roundi(common_value * 0.2),
		], (
				Prices.item_value(common, _catalog) == common_value
				and _scrap(common) == roundi(common_value * 0.2)
		), "%d / %d" % [Prices.item_value(common, _catalog), _scrap(common)])
		_check("prices: %s on a Basic weapon is worth %d, scraps for %d" % [
			event, basic_value, roundi(basic_value * 0.2),
		], (
				Prices.item_value(basic, _catalog) == basic_value
				and _scrap(basic) == roundi(basic_value * 0.2)
		), "%d / %d" % [Prices.item_value(basic, _catalog), _scrap(basic)])


func _test_floor() -> void:
	var heavy: Array = [[CombatValue.Key.NET_WEIGHT, 4.0]]
	var common: ItemInstance = _modified(COMMON_WEAPON, heavy, [])
	var basic: ItemInstance = _modified(BASIC_WEAPON, heavy, [])
	_check("prices: a net-negative change (+4 weight) keeps a Common weapon at 40, scrap 8", (
			is_equal_approx(Prices.modification_points(common, _catalog), -1.0)
			and Prices.item_value(common, _catalog) == 40
			and _scrap(common) == 8
	), "%d / %d" % [Prices.item_value(common, _catalog), _scrap(common)])
	_check("prices: a net-negative change keeps a Basic weapon at 0", (
			Prices.item_value(basic, _catalog) == 0 and _scrap(basic) == 0
	), str(Prices.item_value(basic, _catalog)))
	var trade: ItemInstance = _modified(COMMON_WEAPON, [
		[DamageStage.Key.ATTACK, 1.0], [CombatValue.Key.NET_WEIGHT, 8.0],
	], [])
	_check("prices: a gain outweighed by its cost (+1 damage, +8 weight) stays at 40", (
			Prices.item_value(trade, _catalog) == 40
	), str(Prices.item_value(trade, _catalog)))


func _test_bases() -> void:
	var damage: Array = [[DamageStage.Key.ATTACK, 1.0]]
	var legendary: ItemInstance = ItemInstance.new(_id(), LEGENDARY_WEAPON)
	_check("prices: an unmodified Legendary weapon is worth the Rare price, 200; scrap 40", (
			Prices.item_value(legendary, _catalog) == 200 and _scrap(legendary) == 40
	), str(Prices.item_value(legendary, _catalog)))
	var modified_legendary: ItemInstance = _modified(LEGENDARY_WEAPON, damage, [])
	_check("prices: +1 damage on a Legendary weapon counts from 200: 220, scrap 44", (
			Prices.item_value(modified_legendary, _catalog) == 220
			and _scrap(modified_legendary) == 44
	), str(Prices.item_value(modified_legendary, _catalog)))
	var unique: ItemInstance = ItemInstance.new(_id(), UNIQUE_TRINKET)
	var modified_unique: ItemInstance = _modified(UNIQUE_TRINKET, [
		[CombatValue.Key.CRIT_CHANCE, 10.0],
	], [])
	_check("prices: a Unique trinket counts from the Rare trinket price: 80, +10 crit 100", (
			Prices.item_value(unique, _catalog) == 80
			and Prices.item_value(modified_unique, _catalog) == 100
			and _scrap(modified_unique) == 20
	), "%d / %d" % [
		Prices.item_value(unique, _catalog), Prices.item_value(modified_unique, _catalog),
	])
	var basic: ItemInstance = ItemInstance.new(_id(), BASIC_WEAPON)
	var modified_basic: ItemInstance = _modified(BASIC_WEAPON, damage, [])
	_check("prices: a Basic weapon counts from 0: unmodified 0, +1 damage 20, scrap 4", (
			Prices.item_value(basic, _catalog) == 0
			and _scrap(basic) == 0
			and Prices.item_value(modified_basic, _catalog) == 20
			and _scrap(modified_basic) == 4
	), str(Prices.item_value(modified_basic, _catalog)))
	var equipment: ItemInstance = _modified(COMMON_EQUIPMENT, [[CombatValue.Key.DEF, 1.0]], [])
	_check("prices: +1 DEF on Common equipment steps by 40: 100", (
			Prices.item_value(equipment, _catalog) == 100
	), str(Prices.item_value(equipment, _catalog)))


func _test_rounding() -> void:
	var half: ItemInstance = _modified(COMMON_CONSUMABLE, [[CombatValue.Key.HIT, 5.0]], [])
	_check("prices: a half gold rounds up (+5 Hit on a Common consumable: 37.5 to 38)", (
			Prices.item_value(half, _catalog) == 38
	), str(Prices.item_value(half, _catalog)))
	var quarters: ItemInstance = _modified(UNCOMMON_CONSUMABLE, [
		[CombatValue.Key.HIT, 5.0], [CombatValue.Key.CRIT_CHANCE, 5.0],
		[CombatValue.Key.NET_WEIGHT, 1.0],
	], [])
	_check("prices: 0.75 points on an Uncommon consumable is 68.75, to 69; scrap 14", (
			Prices.item_value(quarters, _catalog) == 69 and _scrap(quarters) == 14
	), "%d / %d" % [Prices.item_value(quarters, _catalog), _scrap(quarters)])
	var tenths: ItemInstance = _modified(COMMON_CONSUMABLE, [
		[CombatValue.Key.HIT, 1.0], [CombatValue.Key.HIT, 1.0], [CombatValue.Key.HIT, 1.0],
		[CombatValue.Key.AVOID, 1.0], [CombatValue.Key.AVOID, 1.0],
	], [])
	_check("prices: five tenths summed still round as a half (25 + 12.5 to 38)", (
			Prices.item_value(tenths, _catalog) == 38
	), str(Prices.item_value(tenths, _catalog)))


func _test_unpriced_parts() -> void:
	var prefixed: ItemInstance = ItemInstance.new(_id(), COMMON_WEAPON)
	prefixed.prefix_id = "keen_edge"
	_check("prices: a weapon prefix alone doesn't change the value (40)", (
			Prices.item_value(prefixed, _catalog) == 40
	), str(Prices.item_value(prefixed, _catalog)))
	var missing: ItemInstance = _modified(COMMON_WEAPON, [], ["price_not_in_catalog"])
	_check("prices: a granted effect missing from the catalog adds nothing (40)", (
			is_zero_approx(Prices.modification_points(missing, _catalog))
			and Prices.item_value(missing, _catalog) == 40
	), str(Prices.item_value(missing, _catalog)))
	_check("prices: a null item, or one not in the catalog, is worth 0", (
			Prices.item_value(null, _catalog) == 0
			and Prices.item_value(ItemInstance.new(_id(), "price_no_such_item"), _catalog) == 0
			and Prices.item_scrap_value(null, _catalog, 20.0) == 0
	))
	var effect: EffectDefinition = _catalog.effect(HEAL_ON_HIT)
	_check("prices: a granted effect carries its own points (heal 2 on hit: 1)", (
			effect != null and is_equal_approx(effect.item_points, 1.0)
	))


func _test_catalog_unchanged() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var percent: float = Prices.default_scrap_percent()
	var kinds: Array[EffectCatalog.Kind] = [
		EffectCatalog.Kind.WEAPON,
		EffectCatalog.Kind.EQUIPMENT,
		EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]
	var count: int = 0
	var wrong: PackedStringArray = []
	for kind: EffectCatalog.Kind in kinds:
		for resource: Resource in catalog.all_of(kind):
			var definition: ItemDefinition = resource as ItemDefinition
			if definition == null:
				continue
			count += 1
			var item: ItemInstance = ItemInstance.new(_id(), definition.id)
			var value: int = Prices.item_value(item, catalog)
			var basis: int = Prices.scrap_basis(definition.kind, definition.rarity)
			var old_scrap: int = Prices.scrap_value(definition.kind, definition.rarity, percent)
			var is_same: bool = (
					value == maxi(basis, 0)
					and Prices.item_scrap_value(item, catalog, percent) == old_scrap
					and ItemPlacement.held_scrap_value(item, catalog)
							== ItemPlacement.scrap_value(definition)
					and (
							not Prices.is_sellable(definition.rarity)
							or value == Prices.item_price(definition)
					)
			)
			if not is_same:
				wrong.append("%s (%d)" % [definition.id, value])
	_check("prices: every unmodified catalog item keeps its price and scrap value (%d items)" % [
		count,
	], count > 0 and wrong.is_empty(), ", ".join(wrong))


# The in-memory catalog: one granted effect worth 1 point and an item per base the cases need.
func _build_catalog() -> EffectCatalog.Index:
	var index: EffectCatalog.Index = EffectCatalog.Index.new()
	var effect: EffectDefinition = EffectDefinition.new()
	effect.id = HEAL_ON_HIT
	effect.item_points = 1.0
	index.add("memory://%s.tres" % [HEAL_ON_HIT], effect)
	var items: Array[ItemDefinition] = [
		_item(WeaponDefinition.new(), COMMON_WEAPON, COMMON),
		_item(WeaponDefinition.new(), BASIC_WEAPON, BASIC),
		_item(WeaponDefinition.new(), LEGENDARY_WEAPON, LEGENDARY),
		_item(TrinketDefinition.new(), UNIQUE_TRINKET, UNIQUE),
		_item(EquipmentDefinition.new(), COMMON_EQUIPMENT, COMMON),
		_item(ConsumableDefinition.new(), COMMON_CONSUMABLE, COMMON),
		_item(ConsumableDefinition.new(), UNCOMMON_CONSUMABLE, UNCOMMON),
	]
	for item: ItemDefinition in items:
		index.add("memory://%s.tres" % [item.id], item)
	index.finish()
	return index


func _item(
		definition: ItemDefinition, id: String, rarity: ItemDefinition.Rarity
) -> ItemDefinition:
	definition.id = id
	definition.rarity = rarity
	return definition


# An item of definition_id with deltas ([key, amount] pairs) and granted effect ids.
func _modified(definition_id: String, deltas: Array, granted: Array) -> ItemInstance:
	var item: ItemInstance = ItemInstance.new(_id(), definition_id)
	for pair: Variant in deltas:
		var delta: Array = pair
		var key: int = delta[0]
		var amount: float = delta[1]
		item.stat_deltas.append(ItemInstance.StatDelta.new(key, amount, "price_event", "Event"))
	for effect_id: Variant in granted:
		item.granted_effect_ids.append(str(effect_id))
	return item


func _scrap(item: ItemInstance) -> int:
	return Prices.item_scrap_value(item, _catalog, Prices.default_scrap_percent())


func _id() -> String:
	_next_id += 1
	return "item:%d" % [_next_id]


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
