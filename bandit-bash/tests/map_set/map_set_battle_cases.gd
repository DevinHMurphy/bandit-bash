# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_set_battle_cases.gd
# Author:
# Created:  November 16, 2026
# Modified: November 18, 2026
# ==============================================================================

extends RefCounted
## Headless battles on the M2 map set, for the map_set/standard and map_set/key suites (combat map
## plan, MP10 row): on each map of one combat type, the Mercenary army at its step's expected
## level (the step's enemy level, 1, 3 or 5) against a pack setup draws from the real catalog,
## with seeded rolls and the AI playing the enemies, through m1_battle_cases.gd's driver
## ([method M1BattleCases.play]): standard maps at steps 1 and 3, key maps at step 3 only, since
## a key battle takes minutes. Each fields its step's full pack and runs to
## [constant CombatFact.Kind.COMBAT_ENDED] with no command rejected; at step 3 the same seed gives
## the same fact log twice. Reports each case through the check callable it is given, and times
## each map as a test group.[br]
## [b]Either side may win:[/b] the driver is simple. A Leader map's leader stands on its leader
## slot and counts toward the pack; a key map's mini-boss stands on its leader slot on top of its
## escort, and on the mini-boss map its fall ends the battle.

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const MapSetCases = preload("res://tests/map_set/map_set_cases.gd")

# The first floor of each step a map is played at (game-vision.md, Run structure).
const STANDARD_FLOORS: Array[int] = [1, 12]
const KEY_FLOORS: Array[int] = [12]

# The floor whose battle is played twice to compare fact logs.
const REPEAT_FLOOR: int = 12

const STARTING_ARMY_SIZE: int = 4

var _check: Callable
var _battles: M1BattleCases = null
var _combat_type: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param combat_type]: whose maps to play, standard or key; each type is its own suite, as a
## battle per map takes minutes and the runner limits each suite's time.
func _init(check: Callable, combat_type: CombatMapDefinition.CombatType) -> void:
	_check = check
	_combat_type = combat_type
	_battles = M1BattleCases.new(check, EffectCatalog.index())


## Runs every case.
func run() -> void:
	if _combat_type == CombatMapDefinition.CombatType.KEY:
		for map_id: String in MapSetCases.KEY_MAPS:
			_test_map("res://maps/key/%s.tres" % [map_id], KEY_FLOORS)
		return
	for map_id: String in MapSetCases.STANDARD_MAPS:
		_test_map("res://maps/standard/%s.tres" % [map_id], STANDARD_FLOORS)


func _test_map(path: String, floors: Array[int]) -> void:
	GroupClock.lap("map battle %s" % [path.get_file().get_basename()])
	var map: CombatMapDefinition = load(path) as CombatMapDefinition
	if map == null:
		_check.call("map battle: the definition loads", false, path)
		return
	for floor_number: int in floors:
		_test_battle(map, floor_number)


func _test_battle(map: CombatMapDefinition, floor_number: int) -> void:
	var level: int = EnemySetup.level_for(floor_number, false)
	var label: String = "map battle %s, floor %d, army level %d" % [map.id, floor_number, level]
	var played: M1BattleCases.Battle = _battles.play(map, 0, floor_number, level)
	# A key pack's escorts number the step's count, and its mini-boss stands on the leader slot.
	var size: int = PackDefinition.STEP_SIZES[EnemySetup.step_of(floor_number) - 1]
	if map.combat_type == CombatMapDefinition.CombatType.KEY:
		size += 1
	_check.call("%s: the army against its step's full pack" % [label], (
			played.problems.is_empty()
			and played.players == STARTING_ARMY_SIZE
			and played.enemies == size
	), "%s; %d player units, %d enemies of %s" % [
		played.problems, played.players, played.enemies, played.pack_id,
	])
	_check.call("%s: runs to COMBAT_ENDED, no command rejected" % [label], (
			played.has_ended and played.rejected.is_empty()
	), "%s after turn %d; rejected %s" % [played.outcome, played.turns, played.rejected])
	print("      %s: %s %s after turn %d, %d facts, %d enemy actions" % [
		label, played.pack_id, played.outcome, played.turns, played.facts.size(),
		played.enemy_actions,
	])
	if floor_number != REPEAT_FLOOR:
		return
	var again: M1BattleCases.Battle = _battles.play(map, 0, floor_number, level)
	_check.call("%s: the same seed gives the same fact log twice" % [label], (
			played.facts.size() > 0 and played.facts == again.facts
	), "%d / %d facts" % [played.facts.size(), again.facts.size()])
