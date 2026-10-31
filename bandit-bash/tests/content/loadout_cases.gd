# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loadout_cases.gd
# Author:
# Created:  October 29, 2026
# Modified: October 30, 2026
# ==============================================================================

extends RefCounted
## The instance and loadout cases for tests/content/run_all.gd: [ItemInstance] and [UnitInstance]
## round trips through JSON; unit stats against unit-roster.md with and without a prefix, an
## upgrade and a permanent delta; [Loadout]'s combat state, bases, weapon records and effects on a
## real [CombatState] and [EffectEngine]; a weapon prefix sleeping with a stowed weapon; the
## lock-picking permission; campaign-lane write-back; bad data reported, not guessed at; and the
## enemy side: an enemy class is no unit type, its stats by level with the level named, and its
## weapons' and staves' uses unlimited while a player's run out; and a consumable's total uses
## kept on its item across battles. Reports each case through the check callable it is given.
##
## The fixture tree [constant TREE] is a data root with the roster's numbers for the Archer, the
## Thief (with [constant CombatValue.Permission.CAN_PICK_LOCKS] in its innate effects; no real
## Thief exists until CT13) and the Drengr, enemy-roster.md's for the Brute and the Hedge Healer,
## a Minor Heal with 3 uses per map, and a Medic to hold it on the player side. Bad-data messages
## are pushed as errors on purpose.

# Preloaded scripts used as types (gdscript.md, Naming): neither has a class name.
const ContentRules = preload("res://tests/content/content_rules.gd")
const StubCombatGrid = preload("res://tests/combat/stub_combat_grid.gd")

## The loadout fixture tree, loaded the way the catalog loads res://data/.
const TREE: String = "res://tests/content/fixtures/loadout/"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _check: Callable
var _index: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_index = EffectCatalog.load_tree(TREE)


## Runs every case.
func run() -> void:
	_test_fixture_tree_passes()
	_test_item_round_trip()
	_test_unit_round_trip()
	_test_restore_rejects_bad_data()
	_test_roster_stats()
	_test_prefix_and_upgrade_stats()
	_test_deltas_and_floors()
	_test_commander_ignores_prefix()
	_test_loaded_unit()
	_test_weapon_prefix_sleeps_when_stowed()
	_test_equipment_and_item_deltas()
	_test_lock_picking_permission()
	_test_write_back()
	_test_bad_data_reported()
	_test_heirloom_effects()
	_test_enemy_class_is_no_unit_type()
	_test_enemy_stats_by_level()
	_test_staff_uses_by_side()
	_test_enemy_weapon_effects_unlimited()
	_test_total_uses_across_battles()
	_test_definitions_unchanged()


func _test_fixture_tree_passes() -> void:
	var findings: Array[ContentRules.Finding] = ContentRules.new(_index).check()
	var lines: PackedStringArray = []
	for finding: ContentRules.Finding in findings:
		lines.append(str(finding))
	_check.call("loadout tree: loads and breaks no content rule", (
			_index.problems.is_empty() and findings.is_empty()
	), " | ".join(lines) + " | ".join(_index.problems))


func _test_item_round_trip() -> void:
	var item: ItemInstance = ItemInstance.new("item:7", "loadout_simple_bow")
	item.prefix_id = "loadout_keen_edge"
	item.granted_effect_ids = PackedStringArray(["infuse"])
	item.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.ATK_X, 1.0, "cavern_of_echoing_steel", "Cavern of Echoing Steel"
	))
	item.charges["key_use"] = 1
	item.counters["infuse"] = 4
	var text: String = JSON.stringify(item.capture())
	var back: ItemInstance = ItemInstance.restore(JSON.parse_string(text) as Dictionary)
	_check.call("item: survives a JSON round trip", (
			back != null and JSON.stringify(back.capture()) == text
	), text)
	if back == null:
		return
	_check.call("item: counts come back as ints", (
			typeof(back.counters["infuse"]) == TYPE_INT and back.charges["key_use"] == 1
	), "")
	_check.call("item: deltas keep their source", (
			back.stat_deltas.size() == 1
			and back.stat_deltas[0].key == CombatValue.Key.ATK_X
			and back.stat_deltas[0].label == "Cavern of Echoing Steel"
	), "")
	_check.call("item: modified by its granted effects and deltas, not its prefix", (
			back.is_modified()
			and not ItemInstance.new("item:8", "loadout_simple_bow").is_modified()
	), "")
	var captured: Dictionary = item.capture()
	_check.call("item: captures plain data only", _is_plain(captured), str(captured))


func _test_unit_round_trip() -> void:
	var unit: UnitInstance = _unit("unit:3", "loadout_thief", "item:4")
	unit.prefix_id = "loadout_swift"
	unit.level = 4
	unit.is_upgraded = true
	unit.equipment_id = "item:5"
	unit.pouch_id = "item:6"
	unit.xp = 70
	unit.hp = 9
	unit.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.MGT, 1.0, "dark_goblet", "Dark Goblet"
	))
	unit.growth_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Stat.RES, 5.0, "cave_carrot", "Cave Carrot"
	))
	var gain: UnitInstance.PendingGain = UnitInstance.PendingGain.new()
	gain.stat = CombatValue.Stat.MGT
	gain.amount = 1
	gain.remaining = 2
	gain.label = "Drink the Sap"
	unit.pending_gains.append(gain)
	unit.counters["loadout_thief_trait"] = 3
	var text: String = JSON.stringify(unit.capture())
	var back: UnitInstance = UnitInstance.restore(JSON.parse_string(text) as Dictionary)
	_check.call("unit: survives a JSON round trip", (
			back != null and JSON.stringify(back.capture()) == text
	), text)
	if back == null:
		return
	_check.call("unit: numbers come back as ints", (
			typeof(back.level) == TYPE_INT
			and back.hp == 9
			and back.pending_gains[0].remaining == 2
			and typeof(back.counters["loadout_thief_trait"]) == TYPE_INT
	), "")
	_check.call("unit: a new unit is at full HP", UnitInstance.new().hp == UnitInstance.FULL_HP, "")
	_check.call("unit: captures plain data only", _is_plain(unit.capture()), "")
	_check.call("unit: its slots in order", (
			unit.item_ids() == PackedStringArray(["item:4", "item:5", "item:6"])
	), str(unit.item_ids()))


func _test_restore_rejects_bad_data() -> void:
	_check.call("restore: not an item's data is null", (
			ItemInstance.restore({"definition_id": "loadout_simple_bow"}) == null
	), "")
	_check.call("restore: not a unit's data is null", (
			UnitInstance.restore({"instance_id": 5}) == null
	), "")


# unit-roster.md, MVP roster: Archer 13/5/8/0/0/5/6, growths 55/38/58/8/17, Stance 1.
func _test_roster_stats() -> void:
	var archer: StatSheet = _unit("unit:1", "loadout_archer").stats(_index)
	_check.call("roster: Archer's base stats", _stats(archer) == "13/5/8/0/0/5/6", _stats(archer))
	_check.call("roster: Archer's Stance", (
			archer.get_int(CombatValue.Key.STANCE_MAX) == 1
	), "")
	var growths: PackedStringArray = []
	for stat: int in [0, 1, 2, 3, 4]:
		growths.append(str(_unit("unit:1", "loadout_archer").growth(_index, stat)))
	_check.call("roster: Archer's growths", "/".join(growths) == "55/38/58/8/17", "/".join(growths))
	var thief: StatSheet = _unit("unit:2", "loadout_thief").stats(_index)
	_check.call("roster: Thief's base stats", _stats(thief) == "14/3/9/2/1/6/6", _stats(thief))
	var drengr: StatSheet = _unit("unit:3", "loadout_drengr").stats(_index)
	_check.call("roster: Drengr's base stats", _stats(drengr) == "24/5/6/3/2/5/13", _stats(drengr))


# unit-roster.md: Swift +3 SPD, +25% SPD growth; Archer+ +2 MGT, +1 SPD; Thief+ +1 SPD and Sidearm.
func _test_prefix_and_upgrade_stats() -> void:
	var swift: UnitInstance = _unit("unit:1", "loadout_archer")
	swift.prefix_id = "loadout_swift"
	_check.call("prefix: Swift Archer", _stats(swift.stats(_index)) == "13/5/11/0/0/5/6", (
			_stats(swift.stats(_index))
	))
	_check.call("prefix: Swift raises the SPD growth", (
			swift.growth(_index, CombatValue.Stat.SPD) == 83
	), "")
	var upgraded: UnitInstance = _unit("unit:2", "loadout_archer")
	upgraded.is_upgraded = true
	_check.call("upgrade: Archer+", _stats(upgraded.stats(_index)) == "13/7/9/0/0/5/6", (
			_stats(upgraded.stats(_index))
	))
	_check.call("upgrade: never changes growths", (
			upgraded.growth(_index, CombatValue.Stat.MGT) == 38
	), "")
	var both: UnitInstance = _unit("unit:3", "loadout_archer")
	both.prefix_id = "loadout_swift"
	both.is_upgraded = true
	var sheet: StatSheet = both.stats(_index)
	_check.call("both: Swift Archer+", _stats(sheet) == "13/7/12/0/0/5/6", _stats(sheet))
	var speed: String = sheet.explain(CombatValue.Key.SPD).to_text()
	_check.call("both: the SPD breakdown names the type, the prefix and the upgrade", (
			speed.contains("Archer") and speed.contains("Swift") and speed.contains("Archer+")
	), speed)
	var thief: UnitInstance = _unit("unit:4", "loadout_thief")
	_check.call("sidearm: not before the upgrade", not thief.stats(_index).is_allowed(
			CombatValue.Permission.FREE_WEAPON_SWAP
	), "")
	thief.is_upgraded = true
	_check.call("sidearm: Thief+ swaps for free", thief.stats(_index).is_allowed(
			CombatValue.Permission.FREE_WEAPON_SWAP
	), "")
	_check.call("upgrade: Thief+ has the + trait", (
			thief.trait_effects(_index.unit_type("loadout_thief"))[0].id
			== "loadout_thief_trait_plus"
	), "")
	_check.call("upgrade: the trait's name gains a +", (
			_index.unit_type("loadout_thief").trait_label(true) == "Opportunist+"
			and _index.unit_type("loadout_thief").trait_label(false) == "Opportunist"
	), "")


func _test_deltas_and_floors() -> void:
	var unit: UnitInstance = _unit("unit:1", "loadout_archer")
	unit.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.MGT, 1.0, "dark_goblet", "Dark Goblet"
	))
	unit.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.MGT, 2.0, "boosters", "Strength Tonic"
	))
	var might: ValueBreakdown = unit.stats(_index).explain(CombatValue.Key.MGT)
	_check.call("delta: permanent deltas add, each named", (
			might.get_int() == 8
			and might.to_text().contains("Dark Goblet")
			and might.to_text().contains("Strength Tonic")
	), might.to_text())
	unit.growth_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Stat.RES, 5.0, "cave_carrot", "Cave Carrot"
	))
	_check.call("delta: a growth delta adds to the growth", (
			unit.growth(_index, CombatValue.Stat.RES) == 22
	), "")
	var brittle: UnitInstance = _unit("unit:2", "loadout_archer")
	brittle.prefix_id = "loadout_brittle"
	_check.call("floor: a prefix takes no stat below 0", (
			brittle.stats(_index).get_int(CombatValue.Key.DEF) == 0
	), "")
	_check.call("floor: a prefix takes no growth below 0", (
			brittle.growth(_index, CombatValue.Stat.DEF) == 0
	), "")


func _test_commander_ignores_prefix() -> void:
	var drengr: UnitInstance = _unit("unit:1", "loadout_drengr", "item:1")
	drengr.prefix_id = "loadout_swift"
	drengr.is_upgraded = true
	_check.call("commander: no prefix or upgrade counts", (
			_stats(drengr.stats(_index)) == "24/5/6/3/2/5/13"
	), _stats(drengr.stats(_index)))
	var loaded: Loadout.LoadedUnit = _load(
			drengr, {"item:1": _item("item:1", "loadout_simple_axe")}
	)
	_check.call("commander: the loadout reports them", (
			loaded.is_loaded() and loaded.problems.size() == 1
	), str(loaded.problems))


func _test_loaded_unit() -> void:
	var thief: UnitInstance = _unit("unit:9", "loadout_thief", "item:1")
	thief.hp = 10
	var loaded: Loadout.LoadedUnit = _load(
			thief, {"item:1": _item("item:1", "loadout_simple_dagger")}, ENEMY, -1
	)
	_check.call("loadout: no problems", loaded.problems.is_empty(), str(loaded.problems))
	var state: CombatUnitState = loaded.state
	_check.call("loadout: the combat state", (
			state.id == "unit:9"
			and state.side == ENEMY
			and state.seat == -1
			and state.unit_type == "loadout_thief"
			and state.role == "dagger"
			and state.movement_type == CombatGrid.MovementType.MOBILE
			and state.hp == 10
			and state.equipped_weapon_id == "item:1"
	), "")
	_check.call("loadout: the bases are the type's stats and Stance", (
			loaded.bases[CombatValue.Key.SPD] == 9.0
			and loaded.bases[CombatValue.Key.MOVEMENT] == 6.0
			and loaded.bases[CombatValue.Key.STANCE_MAX] == 1.0
	), str(loaded.bases))
	var record: CombatState.WeaponStats = loaded.weapons[0]
	_check.call("loadout: the weapon record is the definition's", (
			record.id == "item:1"
			and record.weapon_type == "dagger"
			and record.damage == 2
			and record.range_min == 1
			and record.range_max == 2
			and record.crit_x == 5.0
			and record.profile == WeaponTriangle.Profile.NIMBLE
	), "")
	var full: UnitInstance = _unit("unit:10", "loadout_thief")
	_check.call("loadout: full HP is the maximum", _load(full, {}).state.hp == 14, "")
	var upgraded: UnitInstance = _unit("unit:11", "loadout_thief")
	upgraded.is_upgraded = true
	var world: World = World.new(_load(upgraded, {}))
	_check.call("loadout: the + trait in battle", (
			world.engine.stats("unit:11").get_int(CombatValue.Key.CRIT_CHANCE) == 25
	), "")
	_check.call("loadout: Stance at placement counts its effects", (
			world.state.unit("unit:11").stance == 1
	), "")


func _test_weapon_prefix_sleeps_when_stowed() -> void:
	var keen: ItemInstance = _item("item:1", "loadout_simple_dagger")
	keen.prefix_id = "loadout_keen_edge"
	var thief: UnitInstance = _unit("unit:1", "loadout_thief", "item:1")
	thief.pouch_id = "item:2"
	var items: Dictionary[String, ItemInstance] = {
		"item:1": keen,
		"item:2": _item("item:2", "loadout_simple_sword"),
	}
	var world: World = World.new(_load(thief, items))
	var hit: ValueBreakdown = world.engine.stats("unit:1").explain(CombatValue.Key.HIT)
	_check.call("weapon prefix: applies to the equipped weapon, named", (
			hit.get_int() == 110 and hit.to_text().contains("Keen")
	), hit.to_text())
	_check.call("weapon prefix: a range change reaches the longest range only", (
			world.engine.stats("unit:1").get_int(CombatValue.Key.RANGE_MIN) == 1
			and world.engine.stats("unit:1").get_int(CombatValue.Key.RANGE_MAX) == 3
	), "")
	var unit: CombatUnitState = world.state.unit("unit:1")
	unit.equipped_weapon_id = "item:2"
	unit.stowed_weapon_id = "item:1"
	world.state.load_bases(world.engine, "unit:1")
	_check.call("weapon prefix: sleeps once stowed", (
			world.engine.stats("unit:1").get_int(CombatValue.Key.HIT) == 80
			and world.engine.stats("unit:1").get_int(CombatValue.Key.RANGE_MAX) == 1
	), "")


func _test_equipment_and_item_deltas() -> void:
	var bow: ItemInstance = _item("item:1", "loadout_simple_bow")
	bow.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.ATK_X, 1.0, "cavern_of_echoing_steel", "Cavern of Echoing Steel"
	))
	var archer: UnitInstance = _unit("unit:1", "loadout_archer", "item:1")
	archer.equipment_id = "item:2"
	var world: World = World.new(_load(archer, {
		"item:1": bow,
		"item:2": _item("item:2", "loadout_buckler"),
	}))
	var sheet: StatSheet = world.engine.stats("unit:1")
	var attacks: ValueBreakdown = sheet.explain(CombatValue.Key.ATK_X)
	_check.call("item delta: AtkX +1, named", (
			attacks.get_int() == 2 and attacks.to_text().contains("Cavern of Echoing Steel")
	), attacks.to_text())
	_check.call("equipment: its effects apply", sheet.get_int(CombatValue.Key.DEF) == 1, "")
	_check.call("equipment: its weight counts", (
			sheet.get_int(CombatValue.Key.NET_WEIGHT) == 9
	), sheet.explain(CombatValue.Key.NET_WEIGHT).to_text())
	_check.call("equipment: it fills the Equipment slot", (
			world.state.unit("unit:1").equipment_id == "item:2"
	), "")


func _test_lock_picking_permission() -> void:
	var thief: World = World.new(_load(_unit("unit:1", "loadout_thief"), {}))
	_check.call("lockpicking: the Thief's innate grant allows it", (
			MapObjects.can_pick_locks(thief.engine, "unit:1")
	), "")
	var archer: World = World.new(_load(_unit("unit:2", "loadout_archer"), {}))
	_check.call("lockpicking: denied by default", (
			not MapObjects.can_pick_locks(archer.engine, "unit:2")
	), "")
	_check.call("lockpicking: the default is denied", (
			not CombatValue.PERMISSION_DEFAULTS[CombatValue.Permission.CAN_PICK_LOCKS]
	), "")


func _test_write_back() -> void:
	var index: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	var use: EffectDefinition = EffectDefinition.new()
	use.id = "fixture_key_use"
	use.trigger = EffectTerms.Trigger.UNIT_TURN_START
	use.charges = 2
	use.charge_lane = EffectTerms.Lane.CAMPAIGN
	var key: ConsumableDefinition = ConsumableDefinition.new()
	key.id = "fixture_key"
	key.effects = [use]
	index.add(TREE + "items/consumables/fixture_key.tres", key)
	index.finish()
	var item: ItemInstance = _item("item:1", "fixture_key")
	item.charges["fixture_key_use"] = 1
	var thief: UnitInstance = _unit("unit:1", "loadout_thief")
	thief.pouch_id = "item:1"
	thief.counters["loadout_thief_trait"] = 3
	var items: Dictionary[String, ItemInstance] = {"item:1": item}
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			index, thief, items, PLAYER, 0, InstanceIdAllocator.new()
	)
	var trait_effect: EffectInstance = _effect_of(loaded, "loadout_thief_trait")
	var key_effect: EffectInstance = _effect_of(loaded, "fixture_key_use")
	_check.call("write back: campaign lanes are copied in", (
			trait_effect.get_counter(EffectTerms.Lane.CAMPAIGN) == 3
			and key_effect.charges_left == 1
	), "")
	trait_effect.set_counter(EffectTerms.Lane.CAMPAIGN, 5)
	trait_effect.set_counter(EffectTerms.Lane.COMBAT, 9)
	key_effect.spend_charge()
	loaded.write_back()
	loaded.write_back()
	_check.call("write back: campaign lanes go back to the instances", (
			thief.counters["loadout_thief_trait"] == 5 and item.charges["fixture_key_use"] == 0
	), "%s %s" % [thief.counters, item.charges])
	_check.call("write back: the combat lane stays behind", thief.counters.size() == 1, "")
	_check.call("write back: the Pouch item is the Pouch's", (
			loaded.state.pouch_item_id == "item:1" and loaded.state.stowed_weapon_id.is_empty()
	), "")


func _test_bad_data_reported() -> void:
	var unknown: Loadout.LoadedUnit = _load(_unit("unit:1", "no_such_type"), {})
	_check.call("bad data: an unknown type doesn't load", (
			not unknown.is_loaded() and unknown.problems.size() == 1
	), str(unknown.problems))
	var misplaced: UnitInstance = _unit("unit:2", "loadout_archer", "item:1")
	misplaced.equipment_id = "item:2"
	misplaced.pouch_id = "item:3"
	var loaded: Loadout.LoadedUnit = _load(misplaced, {
		"item:1": _item("item:1", "loadout_buckler"),
		"item:2": _item("item:2", "loadout_simple_bow"),
	})
	_check.call("bad data: gear in the wrong slot and a missing item are reported", (
			loaded.is_loaded()
			and loaded.problems.size() == 3
			and loaded.state.equipped_weapon_id.is_empty()
			and loaded.state.equipment_id.is_empty()
			and loaded.weapons.is_empty()
	), str(loaded.problems))
	var wrong_type: Loadout.LoadedUnit = _load(
			_unit("unit:3", "loadout_archer", "item:1"),
			{"item:1": _item("item:1", "loadout_simple_sword")}
	)
	_check.call("bad data: a weapon it can't wield is reported, still carried", (
			wrong_type.problems.size() == 1 and wrong_type.state.equipped_weapon_id == "item:1"
	), str(wrong_type.problems))


func _test_heirloom_effects() -> void:
	var valid: EffectCatalog.Index = EffectCatalog.load_tree(
			"res://tests/content/fixtures/rules/valid/"
	)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var heart: Array[EffectInstance] = Loadout.heirloom_effects(valid, "fixture_iron_heart", 1, ids)
	var curse: Array[EffectInstance] = Loadout.heirloom_effects(
			valid, "fixture_brittle_guard", 1, ids
	)
	_check.call("heirlooms: owned by the seat's army", (
			heart.size() == 1
			and heart[0].owner.kind == EffectOwner.Kind.ARMY
			and heart[0].owner.seat == 1
			and heart[0].source_kind == Modifier.SourceKind.HEIRLOOM
	), "")
	_check.call("heirlooms: a curse is sourced as a curse", (
			curse.size() == 1 and curse[0].source_kind == Modifier.SourceKind.CURSE
	), "")
	_check.call("heirlooms: an unknown id gives nothing", (
			Loadout.heirloom_effects(valid, "no_such_heirloom", 1, ids).is_empty()
	), "")


func _test_enemy_class_is_no_unit_type() -> void:
	var type_ids: PackedStringArray = []
	for definition: Resource in _index.all_of(EffectCatalog.Kind.UNIT_TYPE):
		type_ids.append(EffectCatalog.id_of(definition))
	_check.call("enemy class: never among the unit types", (
			_index.unit_type("loadout_brute") == null
			and not type_ids.has("loadout_brute")
			and not type_ids.has("loadout_hedge_healer")
			and type_ids.has("loadout_archer")
	), str(type_ids))
	_check.call("enemy class: a unit instance finds it, and its unit type otherwise", (
			_unit("unit:1", "loadout_brute").definition(_index) is EnemyClassDefinition
			and _unit("unit:2", "loadout_archer").definition(_index) == _index.unit_type(
					"loadout_archer"
			)
	), "")


# enemy-roster.md's Brute: 23/7/4/2/2/5/12, growths 115/60/35/20/15. At level L each stat is
# base + floor(growth x (L - 1) / 100) (game-vision.md, Run structure).
func _test_enemy_stats_by_level() -> void:
	var brute: EnemyClassDefinition = _index.enemy_class("loadout_brute")
	var expected_text: Dictionary[int, String] = {
		1: "23/7/4/2/2/5/12",
		3: "25/8/4/2/2/5/12",
		5: "27/9/5/2/2/5/12",
	}
	for level: int in expected_text:
		var unit: UnitInstance = _unit("unit:%d" % [level], "loadout_brute")
		unit.level = level
		var sheet: StatSheet = unit.stats(_index)
		var formula_holds: bool = true
		for stat: int in brute.base_stats:
			var growth: int = brute.growths.get(stat, 0)
			var gain: int = floori(float(growth * (level - 1)) / 100.0)
			var key: int = CombatValue.STAT_KEYS[stat]
			formula_holds = formula_holds and sheet.get_int(key) == brute.base_stats[stat] + gain
		_check.call("level %d: each stat is base + floor(growth x (L - 1))" % [level], (
				formula_holds and _stats(sheet) == expected_text[level]
		), _stats(sheet))
		var world: World = World.new(_load(unit, {}, ENEMY, -1))
		var hp: ValueBreakdown = world.engine.stats(unit.instance_id).explain(CombatValue.Key.HP)
		_check.call("level %d: the loadout builds the same stats in battle" % [level], (
				_stats(world.engine.stats(unit.instance_id)) == expected_text[level]
				and world.state.unit(unit.instance_id).hp == hp.get_int()
		), _stats(world.engine.stats(unit.instance_id)))
		var names_level: bool = hp.to_text().contains("Level %d" % [level])
		_check.call("level %d: the HP breakdown %s the level" % [
			level, "leaves out" if level == 1 else "names",
		], names_level == (level > 1), hp.to_text())
	var player: UnitInstance = _unit("unit:9", "loadout_archer")
	player.level = 5
	_check.call("level: a player unit's level adds nothing; its level-ups are deltas", (
			_stats(player.stats(_index)) == "13/5/8/0/0/5/6"
	), _stats(player.stats(_index)))


# The same Minor Heal (3 uses per map) on each side: a player's runs out after three heals, an
# enemy's never does (enemies and AI plan, question 13).
func _test_staff_uses_by_side() -> void:
	var player: World = _healer_world(PLAYER, "loadout_medic")
	var enemy: World = _healer_world(ENEMY, "loadout_hedge_healer")
	for side_world: World in [player, enemy]:
		for _i: int in 3:
			side_world.state.set_hp("unit:2", 5)
			side_world.engine.begin_step()
			var result: StaffResolver.Result = StaffResolver.resolve(
					side_world.engine, side_world.state, "unit:1", "unit:2"
			)
			if result.is_legal:
				side_world.heals += 1
	_check.call("staff uses: both sides heal three times", (
			player.heals == 3 and enemy.heals == 3
	), "%d %d" % [player.heals, enemy.heals])
	player.state.set_hp("unit:2", 5)
	var player_reason: String = StaffResolver.check(player.engine, player.state, "unit:1", "unit:2")
	_check.call("staff uses: a player's Minor Heal runs out after its per-map uses", (
			player_reason == "no uses left"
	), player_reason)
	enemy.state.set_hp("unit:2", 5)
	enemy.engine.begin_step()
	var fourth: StaffResolver.Result = StaffResolver.resolve(
			enemy.engine, enemy.state, "unit:1", "unit:2"
	)
	_check.call("staff uses: an enemy's Minor Heal still heals after them", (
			fourth.is_legal and enemy.state.get_hp("unit:2") > 5
	), fourth.reason)


# A weapon's own charged use effect, as data could give one, and a charged effect on a trigger.
func _test_enemy_weapon_effects_unlimited() -> void:
	var index: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	var use: EffectDefinition = EffectDefinition.new()
	use.id = "fixture_use"
	use.charges = 2
	var rider: EffectDefinition = EffectDefinition.new()
	rider.id = "fixture_rider"
	rider.trigger = EffectTerms.Trigger.UNIT_TURN_START
	rider.charges = 1
	var staff: StaffDefinition = StaffDefinition.new()
	staff.id = "fixture_charged_staff"
	staff.weapon_type = "staff"
	staff.staff_kind = ContentIds.STAFF_HEAL
	staff.effects = [use, rider]
	index.add(TREE + "items/weapons/staff/fixture_charged_staff.tres", staff)
	index.finish()
	var items: Dictionary[String, ItemInstance] = {
		"item:1": _item("item:1", "fixture_charged_staff"),
	}
	var healer: UnitInstance = _unit("unit:1", "loadout_hedge_healer", "item:1")
	var as_enemy: Loadout.LoadedUnit = Loadout.load_unit(
			index, healer, items, ENEMY, -1, InstanceIdAllocator.new()
	)
	var as_player: Loadout.LoadedUnit = Loadout.load_unit(
			index, healer, items, PLAYER, 0, InstanceIdAllocator.new()
	)
	var enemy_use: EffectInstance = _effect_of(as_enemy, "fixture_use")
	_check.call("enemy weapon: a charged use effect has no limit, on a copy", (
			enemy_use != null
			and enemy_use.definition != use
			and enemy_use.definition.charges == 0
			and enemy_use.has_charge()
			and use.charges == 2
	), "")
	var enemy_rider: EffectInstance = _effect_of(as_enemy, "fixture_rider")
	_check.call("enemy weapon: a charged effect on a trigger keeps its limit", (
			enemy_rider != null and enemy_rider.definition == rider
	), "")
	var player_use: EffectInstance = _effect_of(as_player, "fixture_use")
	_check.call("enemy weapon: a player's keeps the shared definition and its limit", (
			player_use != null and player_use.definition == use and player_use.charges_left == 2
	), "")


# A consumable with 2 total uses and an uncharged use effect, carried by the same Thief through
# three battles: the count lives on the item between them, and the second use spends it and
# empties the Pouch. An enemy's keeps its uses too.
func _test_total_uses_across_battles() -> void:
	var index: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	var use: EffectDefinition = EffectDefinition.new()
	use.id = "fixture_flask_use"
	var flask: ConsumableDefinition = ConsumableDefinition.new()
	flask.id = "fixture_flask"
	flask.uses = 2
	flask.uses_lane = EffectTerms.Lane.CAMPAIGN
	flask.effects = [use]
	index.add(TREE + "items/consumables/fixture_flask.tres", flask)
	index.finish()
	var item: ItemInstance = _item("item:1", "fixture_flask")
	var thief: UnitInstance = _unit("unit:1", "loadout_thief")
	thief.pouch_id = "item:1"
	var items: Dictionary[String, ItemInstance] = {"item:1": item}
	var outcomes: PackedStringArray = []
	for _battle: int in 3:
		var loaded: Loadout.LoadedUnit = Loadout.load_unit(
				index, thief, items, PLAYER, 0, InstanceIdAllocator.new()
		)
		var world: World = World.new(loaded)
		world.engine.begin_step()
		var result: ItemUseResolver.Result = ItemUseResolver.resolve(
				world.engine, world.state, "unit:1", "unit:1", "item:1"
		)
		loaded.write_back()
		outcomes.append("%s %s %s %s" % [
			"used" if result.is_legal else result.reason,
			"consumed" if result.is_consumed else "kept",
			world.state.unit("unit:1").pouch_item_id,
			item.charges.get("uses", "-"),
		])
	_check.call("total uses: counted on the item across battles, spent by the second use", (
			" | ".join(outcomes)
			== "used kept item:1 1 | used consumed  0 | no uses left kept item:1 0"
	), " | ".join(outcomes))

	var healer: UnitInstance = _unit("unit:2", "loadout_hedge_healer")
	healer.pouch_id = "item:2"
	var enemy_items: Dictionary[String, ItemInstance] = {"item:2": _item("item:2", "fixture_flask")}
	var as_enemy: Loadout.LoadedUnit = Loadout.load_unit(
			index, healer, enemy_items, ENEMY, -1, InstanceIdAllocator.new()
	)
	var enemy_uses: EffectInstance = _effect_of(as_enemy, "uses")
	# ASSUMPTION: question 13 leaves an enemy's consumables limited (loadout.gd).
	_check.call("total uses: an enemy's consumable keeps its uses", (
			enemy_uses != null and enemy_uses.charges_left == 2
	), "")


# Every case above loaded the same shared definitions; none may have changed.
func _test_definitions_unchanged() -> void:
	var fresh: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	var changed: PackedStringArray = []
	for id: String in fresh.ids():
		if _index.definition(id) != fresh.definition(id):
			changed.append(id)
	_check.call("loadout tree: definitions are shared, never copied", changed.is_empty(), (
			str(changed)
	))


func _unit(id: String, unit_type: String, weapon_id: String = "") -> UnitInstance:
	var unit: UnitInstance = UnitInstance.new(id, unit_type)
	unit.weapon_id = weapon_id
	return unit


func _item(id: String, definition_id: String) -> ItemInstance:
	return ItemInstance.new(id, definition_id)


func _load(
		unit: UnitInstance,
		items: Dictionary,
		side: CombatFact.CombatSide = PLAYER,
		seat: int = 0
) -> Loadout.LoadedUnit:
	var typed: Dictionary[String, ItemInstance] = {}
	typed.assign(items)
	return Loadout.load_unit(_index, unit, typed, side, seat, InstanceIdAllocator.new())


# A healer of [param healer_type] holding Minor Heal ("unit:1") beside a Thief ally ("unit:2"), both
# on [param side], loaded with one allocator so their effect ids differ.
func _healer_world(side: CombatFact.CombatSide, healer_type: String) -> World:
	var seat: int = -1 if side == ENEMY else 0
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var items: Dictionary[String, ItemInstance] = {"item:1": _item("item:1", "loadout_minor_heal")}
	var healer: Loadout.LoadedUnit = Loadout.load_unit(
			_index, _unit("unit:1", healer_type, "item:1"), items, side, seat, ids
	)
	var no_items: Dictionary[String, ItemInstance] = {}
	var ally: Loadout.LoadedUnit = Loadout.load_unit(
			_index, _unit("unit:2", "loadout_thief"), no_items, side, seat, ids
	)
	var problems: PackedStringArray = healer.problems + ally.problems
	_check.call("staff uses: the %s side loads cleanly" % [
		CombatFact.CombatSide.find_key(side),
	], problems.is_empty(), str(problems))
	var world: World = World.new(healer)
	world.add(ally, Vector2i(1, 2))
	return world


func _effect_of(loaded: Loadout.LoadedUnit, effect_id: String) -> EffectInstance:
	for instance: EffectInstance in loaded.effects:
		if instance.definition.id == effect_id:
			return instance
	return null


# HP/MGT/SPD/DEF/RES/MOV/CON, unit-roster.md's order.
func _stats(sheet: StatSheet) -> String:
	var parts: PackedStringArray = []
	for key: int in [
		CombatValue.Key.HP, CombatValue.Key.MGT, CombatValue.Key.SPD, CombatValue.Key.DEF,
		CombatValue.Key.RES, CombatValue.Key.MOVEMENT, CombatValue.Key.CON,
	]:
		parts.append(str(sheet.get_int(key)))
	return "/".join(parts)


# Whether [param value] holds only JSON's types: no objects.
func _is_plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_OBJECT:
			return false
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			for key: Variant in dictionary:
				if not _is_plain(key) or not _is_plain(dictionary[key]):
					return false
		TYPE_ARRAY:
			for entry: Variant in value as Array:
				if not _is_plain(entry):
					return false
	return true


# Loaded units placed on an open map with a real CombatState and EffectEngine.
class World:
	extends RefCounted

	var state: CombatState = CombatState.new(StubCombatGrid.new())
	var engine: EffectEngine = null
	## Legal staff uses a case counted.
	var heals: int = 0

	func _init(loaded: Loadout.LoadedUnit) -> void:
		engine = EffectEngine.new(state, null)
		add(loaded, Vector2i(1, 1))

	## Places [param loaded] on [param tile], its weapons, effects and bases first.
	func add(loaded: Loadout.LoadedUnit, tile: Vector2i) -> void:
		for weapon: CombatState.WeaponStats in loaded.weapons:
			state.add_weapon(weapon)
		for instance: EffectInstance in loaded.effects:
			engine.register(instance)
		for key: int in loaded.bases:
			engine.set_base(loaded.state.id, key, loaded.bases[key])
		loaded.state.tile = tile
		state.place_unit(engine, loaded.state)
