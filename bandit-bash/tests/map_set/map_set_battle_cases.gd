# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_set_battle_cases.gd
# Author:
# Created:  November 16, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Headless battles on the M2 map set and the boss map, for every map_set part's battles (combat
## map plan, MP10 row; Powder Baron plan): on each map of one combat
## type, the Mercenary army at its step's expected level against setup's pack from the real
## catalog, seeded, the AI playing the enemies, through [method M1BattleCases.play]: standard maps
## at steps 1 and 3, key maps at step 3, the boss map at floor 18 against its fixed garrison. Each
## runs to [constant CombatFact.Kind.COMBAT_ENDED] with no command rejected; at step 3 and on the
## boss map the same seed gives the same fact log twice (the boss's in its own part, to turn
## [constant REPEAT_PHASES]). Each map is timed as a test group.[br]
## [b]Either side may win:[/b] the driver is simple. A Leader map's leader stands on its leader
## slot and counts toward the pack; a key map's mini-boss stands on its leader slot on top of its
## escort, and on the mini-boss map its fall ends the battle.

## Which plays of each map a part runs.
enum Plays {
	## The battle, then on [constant REPEAT_FLOORS] the same seed again to compare fact logs.
	ALL = 0,
	## The battle once: its pack and its end, with no comparison.
	FIRST = 1,
	## Only the comparison, on [constant REPEAT_FLOORS]: the same seed twice, each play stopped
	## after [constant REPEAT_PHASES] player phases.
	REPEAT = 2,
}

# Preloaded scripts used as types (gdscript.md, Naming): the cases have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const MapSetCases = preload("res://tests/map_set/map_set_cases.gd")

# The first floor of each step a map is played at (game-vision.md, Run structure); the boss's.
const STANDARD_FLOORS: Array[int] = [1, 12]
const KEY_FLOORS: Array[int] = [12]
const BOSS_FLOORS: Array[int] = [18]

# The floors whose battle is played twice to compare fact logs.
const REPEAT_FLOORS: Array[int] = [12, 18]

# Key maps whose battles have a part of their own (map_set/key_gatehouse), so no part of the key
# battles nears the runner's per-suite limit; map_set/key plays the others.
const OWN_PART_KEY_MAPS: PackedStringArray = ["gatehouse"]

# ASSUMPTION: about half the boss battle as the driver plays it now (it ends after turn 6), so
# map_set/boss_repeat's two plays take about one full play's time.
# Player phases each play of Plays.REPEAT runs before it stops.
const REPEAT_PHASES: int = 3

# The one boss map and its fixed garrison's size: 8 guards and the Powder Baron.
const BOSS_MAP: String = "res://maps/boss/powder_keep.tres"
const BOSS_ENEMIES: int = 9

const STARTING_ARMY_SIZE: int = 4

var _check: Callable
var _battles: M1BattleCases = null
var _combat_type: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD
var _only_map: String = ""
var _plays: Plays = Plays.ALL


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param combat_type]: whose maps to play, standard, key or boss; each type is its own suite, as
## a battle per map takes minutes and the runner limits each suite's time.
## [param only_map]: for key maps, the one map to play (one of [constant OWN_PART_KEY_MAPS]);
## empty plays every key map but those. [param plays]: which plays of each map to run.
func _init(
		check: Callable,
		combat_type: CombatMapDefinition.CombatType,
		only_map: String = "",
		plays: Plays = Plays.ALL
) -> void:
	_check = check
	_combat_type = combat_type
	_only_map = only_map
	_plays = plays
	_battles = M1BattleCases.new(check, EffectCatalog.index())


## Runs every case.
func run() -> void:
	if _combat_type == CombatMapDefinition.CombatType.BOSS:
		_test_map(BOSS_MAP, BOSS_FLOORS)
		return
	if _combat_type == CombatMapDefinition.CombatType.KEY:
		for map_id: String in MapSetCases.KEY_MAPS:
			var is_played: bool = (
					map_id == _only_map if not _only_map.is_empty()
					else not OWN_PART_KEY_MAPS.has(map_id)
			)
			if not is_played:
				continue
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
	if _plays == Plays.REPEAT:
		if REPEAT_FLOORS.has(floor_number):
			_test_repeat(map, floor_number, level, label)
		return
	var played: M1BattleCases.Battle = _battles.play(map, 0, floor_number, level)
	# A key pack's escorts number the step's count, and its mini-boss stands on the leader slot.
	var size: int = PackDefinition.STEP_SIZES[EnemySetup.step_of(floor_number) - 1]
	if map.combat_type == CombatMapDefinition.CombatType.KEY:
		size += 1
	elif map.combat_type == CombatMapDefinition.CombatType.BOSS:
		size = BOSS_ENEMIES
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
	if _plays == Plays.FIRST or not REPEAT_FLOORS.has(floor_number):
		return
	var again: M1BattleCases.Battle = _battles.play(map, 0, floor_number, level)
	_check.call("%s: the same seed gives the same fact log twice" % [label], (
			played.facts.size() > 0 and played.facts == again.facts
	), "%d / %d facts" % [played.facts.size(), again.facts.size()])


# Plays.REPEAT's one case: the same seed played twice, each play stopped after REPEAT_PHASES player
# phases, gives the same fact log, the AI's choices included.
func _test_repeat(
		map: CombatMapDefinition, floor_number: int, level: int, label: String
) -> void:
	var played: M1BattleCases.Battle = _battles.play(map, 0, floor_number, level, REPEAT_PHASES)
	var again: M1BattleCases.Battle = _battles.play(map, 0, floor_number, level, REPEAT_PHASES)
	_check.call("%s: the same seed gives the same fact log twice, to turn %d" % [
		label, REPEAT_PHASES,
	], (
			played.problems.is_empty()
			and played.facts.size() > 0
			and played.facts == again.facts
	), "%s; %d / %d facts" % [played.problems, played.facts.size(), again.facts.size()])
	print("      %s: stopped after turn %d, %d facts, %d enemy actions" % [
		label, played.turns, played.facts.size(), played.enemy_actions,
	])
