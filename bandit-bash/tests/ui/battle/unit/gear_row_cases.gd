# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     gear_row_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The unit detail pop-up's Weapon row for the ui/input suite (BUG-028): a Shaman holding Life
## Tap (a lifesteal weapon) shows its profile, AtkX included, and under it Life Tap's effect line;
## an Archer holding Ebonflight (2 strikes, +5 SPD) shows "AtkX 2" and its line. Each unit is
## loaded alone onto a plain row through [Loadout], so the row reads only that weapon; the
## [UnitDetailPanel] scene draws the [UnitDetailViewModel] on the root viewport.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/input"

const DETAIL_SCENE: PackedScene = preload("res://ui/battle/unit/unit_detail_panel.tscn")

# Any fixed seed: nothing here rolls.
const SEED: int = 0x7E_0001

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the panel is added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_weapon("shaman", "life_tap", 1)
	_test_weapon("archer", "ebonflight", 2)


# type_id holding weapon_id: its Weapon row names the weapon, its profile shows AtkX strikes,
# and its every effect line follows, as the weapon's own text reads.
func _test_weapon(type_id: String, weapon_id: String, strikes: int) -> void:
	var weapon: WeaponDefinition = _catalog.weapon(weapon_id)
	var session: CombatSession = _session()
	var unit_id: String = _place(session, type_id, weapon_id)
	if weapon == null or unit_id.is_empty():
		_check.call("gear row %s: the unit loads with it" % [weapon_id], false, type_id)
		return
	var view: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	_root.add_child(panel)
	panel.show_detail(view)
	var row: DetailGearRow = panel.get_node(^"%WeaponRow") as DetailGearRow
	var texts: PackedStringArray = PackedStringArray() if row == null else row.get_texts()
	var detail: PackedStringArray = []
	if texts.size() == 3:
		detail = texts[2].split("\n")
	var expected: PackedStringArray = []
	for line: String in weapon.describe():
		expected.append("%s: %s" % [weapon.display_name, line])
	_check.call("gear row %s: its name, then its profile with AtkX %d" % [weapon_id, strikes], (
			texts.size() == 3 and texts[1] == weapon.display_name
			and not detail.is_empty() and detail[0].contains("AtkX %d" % [strikes])
	), " / ".join(texts))
	_check.call("gear row %s: its effect lines under the profile" % [weapon_id], (
			not expected.is_empty()
			and detail.size() == expected.size() + 1
			and detail.slice(1) == expected
	), "got %s, expected %s" % [str(detail.slice(1)), str(expected)])
	panel.free()


func _session() -> CombatSession:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "gear_row"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	for x: int in 4:
		layout.set_terrain(Vector2i(x, 0), plain)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	return CombatSession.new(
			0, PackedInt32Array([0]), MapGrid.new(layout), LiveRolls.new(RngStream.new(SEED)), ids
	)


# A new player unit of type_id holding weapon_id at (0, 0); its id, or empty when it didn't load
# cleanly.
func _place(session: CombatSession, type_id: String, weapon_id: String) -> String:
	var ids: InstanceIdAllocator = session.ids
	var unit_id: String = ids.next_unit_id(type_id)
	var unit: UnitInstance = UnitInstance.new(unit_id, type_id)
	var weapon: WeaponDefinition = _catalog.weapon(weapon_id)
	if weapon == null:
		return ""
	# Labelled by its name, as a run's items are, so the row names it.
	var item: ItemInstance = ItemInstance.new(ids.next_item_id(weapon.display_name), weapon_id)
	var items: Dictionary[String, ItemInstance] = {item.instance_id: item}
	unit.weapon_id = item.instance_id
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(_catalog, unit, items, PLAYER, 0, ids)
	if not loaded.is_loaded() or not loaded.problems.is_empty():
		return ""
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = Vector2i(0, 0)
	return unit_id if session.add_unit(loaded.state, loaded.bases) else ""
