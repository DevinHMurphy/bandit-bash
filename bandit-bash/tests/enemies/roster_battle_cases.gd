# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     roster_battle_cases.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

extends RefCounted
## The roster's battles for tests/enemies/run_all.gd: the Mercenary army against each of the
## roster's five packs on the M1 greybox, played headless to its end with the M1 battle's driver
## and seed ([code]m1_battle_cases.gd[/code]) on the real catalog with that pack its only pack;
## each runs to [constant CombatFact.Kind.COMBAT_ENDED] with no command rejected, and the same
## seed gives the same fact log twice. Setup's Hunting Party fields 2 or 3 Hounds, both seen within
## a run of seeds, and a seed draws the same count twice. Reports each case through the check
## callable it is given.

# Preloaded scripts used as types (gdscript.md, Naming): the helpers have no class name.
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const PackCatalog = preload("res://tests/enemies/pack_catalog.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# Each roster pack and the units it fields (the Hunting Party at its fewest Hounds).
const PACKS: Dictionary[String, int] = {
	"shield_and_bolt": 3,
	"hex_and_knife": 3,
	"field_hospital": 3,
	"war_band": 4,
	"hunting_party": 3,
}

# The most seeds the Hound count is drawn over: with an even draw, 12 seeds show one count only
# at odds of 2 × 0.5^12. The seeds are fixed, so a run's result never changes.
const COUNT_SEEDS: int = 12

# Floor 1 is step 1 (game-vision.md, Run structure).
const FLOOR: int = 1
const NODE: int = 1

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	var map: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	if map == null:
		_check.call("roster battles: the M1 map definition loads", false, M1_DEFINITION)
		return
	for pack_id: String in PACKS:
		_test_pack_battle(map, pack_id)
	_test_hound_count(map)


# pack_id's battle, twice from the same seed.
func _test_pack_battle(map: CombatMapDefinition, pack_id: String) -> void:
	var cases: M1BattleCases = M1BattleCases.new(_check, PackCatalog.with_only(_catalog, pack_id))
	var first: M1BattleCases.Battle = cases.play(map)
	var second: M1BattleCases.Battle = cases.play(map)
	var fewest: int = PACKS[pack_id]
	var fields_it: bool = (
			first.pack_id == pack_id
			and first.problems.is_empty()
			and first.enemies >= fewest
			and first.enemies <= fewest + 1
	)
	var opened: String = "%s; %s, %d enemies" % [first.problems, first.pack_id, first.enemies]
	_check.call("battle %s: begins against the pack" % [pack_id], fields_it, opened)
	_check.call("battle %s: runs to COMBAT_ENDED, no command rejected" % [pack_id], (
			first.has_ended and first.rejected.is_empty() and first.enemy_actions > 0
	), "%s after turn %d; rejected %s" % [first.outcome, first.turns, first.rejected])
	_check.call("battle %s: the same seed gives the same fact log twice" % [pack_id], (
			first.facts.size() > 0 and first.facts == second.facts
	), "%d / %d facts" % [first.facts.size(), second.facts.size()])
	print("      battle %s: %s after turn %d, %d facts, %d enemy actions" % [
		pack_id, first.outcome, first.turns, first.facts.size(), first.enemy_actions,
	])


# The Hunting Party's Hounds over up to COUNT_SEEDS seeds: 2 and 3 both seen, and seed 0 drawing
# the same count twice.
func _test_hound_count(map: CombatMapDefinition) -> void:
	var catalog: EffectCatalog.Index = PackCatalog.with_only(_catalog, "hunting_party")
	var seen: Dictionary[int, bool] = {}
	var first: int = _hounds(catalog, map, 0)
	var repeats: bool = _hounds(catalog, map, 0) == first
	seen[first] = true
	# Stops once two counts are seen; a third would still fail the check below.
	for run_seed: int in range(1, COUNT_SEEDS):
		if seen.size() > 1:
			break
		seen[_hounds(catalog, map, run_seed)] = true
	var counts: Array[int] = []
	counts.assign(seen.keys())
	counts.sort()
	_check.call("hunting party: fields 2 or 3 Hounds, both drawn", counts == [2, 3], str(counts))
	_check.call("hunting party: a seed draws the same count twice", repeats)


# The Hounds setup places for a new run on run_seed.
func _hounds(catalog: EffectCatalog.Index, map: CombatMapDefinition, run_seed: int) -> int:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = catalog
	var mercenary: StartingArmy = StartingArmy.build(catalog, "mercenary", run.ids)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	request.armies[0] = army
	var battle: CombatEncounter = run.begin_battle(request)
	var count: int = -1
	if battle != null:
		count = 0
		var state: CombatState = battle.get_session(0).state
		for unit_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
			if state.unit_type_of(unit_id) == "hound":
				count += 1
	run.close()
	return count
