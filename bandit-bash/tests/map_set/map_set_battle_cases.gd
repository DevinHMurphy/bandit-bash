# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_set_battle_cases.gd
# Author:
# Created:  November 16, 2026
# Modified: November 16, 2026
# ==============================================================================

extends RefCounted
## Headless battles on the M2 map set for tests/map_set/run_all.gd (combat map plan, MP10 row): on
## each map, the Mercenary army against a pack setup draws from the real catalog, at step 1 and
## step 3, with seeded rolls and the AI playing the enemies, through m1_battle_cases.gd's player
## driver ([method M1BattleCases.play]). Each fields its step's full pack and runs to
## [constant CombatFact.Kind.COMBAT_ENDED] with no command rejected; at step 3 the same seed gives
## the same fact log twice. Reports each case through the check callable it is given.[br]
## [b]Either side may win:[/b] the driver's level-1 army often loses at step 3, and a Defeat the
## Leader map can't be won until P05 EN7 fills its leader slot, so there the darkness ends it.

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const MapSetCases = preload("res://tests/map_set/map_set_cases.gd")

# The first floor of step 1 and of step 3 (game-vision.md, Run structure), and each step's pack
# size (enemy-packs.md, Pack lists).
const STEP_1_FLOOR: int = 1
const STEP_3_FLOOR: int = 12
const STEP_SIZES: Dictionary[int, int] = {STEP_1_FLOOR: 3, STEP_3_FLOOR: 5}

const STARTING_ARMY_SIZE: int = 4

var _check: Callable
var _battles: M1BattleCases = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_battles = M1BattleCases.new(check, EffectCatalog.index())


## Runs every case.
func run() -> void:
	for map_id: String in MapSetCases.STANDARD_MAPS:
		var path: String = "res://maps/standard/%s.tres" % [map_id]
		var map: CombatMapDefinition = load(path) as CombatMapDefinition
		if map == null:
			_check.call("map battle %s: the definition loads" % [map_id], false, path)
			continue
		for floor_number: int in [STEP_1_FLOOR, STEP_3_FLOOR]:
			_test_battle(map, floor_number)


func _test_battle(map: CombatMapDefinition, floor_number: int) -> void:
	var label: String = "map battle %s, floor %d" % [map.id, floor_number]
	var played: M1BattleCases.Battle = _battles.play(map, 0, floor_number)
	var size: int = STEP_SIZES[floor_number]
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
	if floor_number != STEP_3_FLOOR:
		return
	var again: M1BattleCases.Battle = _battles.play(map, 0, floor_number)
	_check.call("%s: the same seed gives the same fact log twice" % [label], (
			played.facts.size() > 0 and played.facts == again.facts
	), "%d / %d facts" % [played.facts.size(), again.facts.size()])
