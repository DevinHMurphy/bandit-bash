# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ai_cases.gd
# Author:
# Created:  October 30, 2026
# Modified: October 31, 2026
# ==============================================================================

extends RefCounted
## The enemy AI cases for tests/enemies/run_all.gd ([EnemyAI], [EnemyPlan]): each rating step
## deciding for the behavior that shows it (kill first, the target rule, the damage share, terrain,
## the fixed order), Hold standing to shoot and moving only for a kill or with nothing in range,
## a Cleave splash kill counted and splash on an ally ignored, Support healing
## the ally missing the most HP from the tile fewest player units can attack and regrouping with
## nobody hurt, the darkness switch, the dry rule, the same board giving the same plan (on a
## sandbox too), re-deciding after a kill, an enemy with no class Waiting, and a headless enemy
## phase whose commands are never rejected. Reports each case through the check callable it is
## given.
##
## Boards are plain unless a case says otherwise. The fixtures' numbers (level 1): the Brute's
## Simple Axe hits for 10 + 7 Might less DEF at Hit 65; the Crossbowman's Simple Bow for 6 + 6
## less DEF at Hit 100, range 2–3, so a sword can't answer it. Player bows can't counter at
## range 1.

# A preloaded script used as a type (gdscript.md, Naming): the world has no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

const BRUTE: String = "loadout_brute"
const CROSSBOWMAN: String = "loadout_crossbowman"
const HEALER: String = "loadout_hedge_healer"

const PLAIN_6X4: Array[String] = [
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
]

const PLAIN_8X8: Array[String] = [
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
]

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param catalog]: the loadout fixture tree.
func _init(check: Callable, catalog: EffectCatalog.Index) -> void:
	_check = check
	_catalog = catalog


## Runs every case.
func run() -> void:
	_test_fixtures_load()
	_test_kill_first()
	_test_nearest_foe_rule()
	_test_hold_lowest_defense()
	_test_hold_kill_first()
	_test_hold_moves_only_when_nothing_in_range()
	_test_hold_moves_to_kill()
	_test_cleave_splash_kill()
	_test_splash_on_ally_ignored()
	_test_value_share()
	_test_terrain()
	_test_fixed_order()
	_test_dry_tile()
	_test_dry_advance()
	_test_heal_most_wounded()
	_test_heal_safest_tile()
	_test_regroup()
	_test_darkness()
	_test_same_board_same_plan()
	_test_redecide_after_kill()
	_test_no_class_waits()
	_test_register()
	_test_headless_phase()


func _test_fixtures_load() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(1, 0))
	world.add_enemy("e3", HEALER, Vector2i(2, 0))
	_check.call("fixtures: the three classes load cleanly", (
			world.problems.is_empty() and world.state().units_of(AiWorld.ENEMY).size() == 3
	), str(world.problems))


# (a) Aggressive: a foe it can defeat if its hits land beats the nearer foe its rule prefers.
func _test_kill_first() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p_near", Vector2i(2, 0), "bow")
	world.add_player("p_far", Vector2i(0, 5), "bow")
	world.wound("p_far", 3)
	var plan: EnemyPlan = world.decide("e1")
	_check.call("kill first: the farther foe it can defeat", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == "p_far"
			and plan.is_kill
			and plan.decided_by == EnemyPlan.Step.KILL
			and plan.tile == Vector2i(0, 4)
	), _describe(plan))
	_check.call("kill first: its chance is its one hit's", (
			plan.kill_chance > 0.0 and plan.kill_chance < 1.0
	), str(plan.kill_chance))


# (b) Aggressive's nearest foe beats a farther foe worth more damage.
func _test_nearest_foe_rule() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p_near", Vector2i(2, 0), "bow")
	world.add_player("p_far", Vector2i(0, 5), "bow", {CombatValue.Key.DEF: 0.0})
	var plan: EnemyPlan = world.decide("e1")
	var far: EnemyPlan = _option_on(world, "e1", "p_far")
	_check.call("target rule: the nearest foe it can hit", (
			plan.target_id == "p_near"
			and not plan.is_kill
			and plan.decided_by == EnemyPlan.Step.TARGET_RULE
			and plan.target_rule_key == 1.0
	), _describe(plan))
	_check.call("target rule: the farther foe was worth more", (
			far != null and far.value > plan.value
	), "%s vs %s" % [_describe(far), _describe(plan)])


# (b) Hold: the lowest DEF in range, shot from where it stands.
func _test_hold_lowest_defense() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p_tough", Vector2i(2, 0), "sword", {CombatValue.Key.DEF: 3.0})
	world.add_player("p_soft", Vector2i(0, 3), "sword", {CombatValue.Key.DEF: 1.0})
	var plan: EnemyPlan = world.decide("e1")
	_check.call("hold: the lowest Defense, from its own tile", (
			plan.target_id == "p_soft"
			and plan.path.is_empty()
			and plan.tile == Vector2i(0, 0)
			and plan.decided_by == EnemyPlan.Step.TARGET_RULE
	), _describe(plan))


# (a) Hold: a kill in range beats the lowest Defense.
func _test_hold_kill_first() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p_weak", Vector2i(2, 0), "sword", {CombatValue.Key.DEF: 3.0})
	world.add_player("p_soft", Vector2i(0, 3), "sword", {CombatValue.Key.DEF: 1.0})
	world.wound("p_weak", 5)
	var plan: EnemyPlan = world.decide("e1")
	_check.call("hold: a kill beats the lowest Defense", (
			plan.target_id == "p_weak" and plan.is_kill and plan.decided_by == EnemyPlan.Step.KILL
	), _describe(plan))


# Hold moves only when no foe is in range from where it stands, and then attacks.
func _test_hold_moves_only_when_nothing_in_range() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p1", Vector2i(7, 0), "sword")
	var plan: EnemyPlan = world.decide("e1")
	_check.call("hold: moves to shoot when nothing is in range", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and plan.target_id == "p1"
			and not plan.path.is_empty()
			and plan.path[0] == Vector2i(0, 0)
			and plan.tile == plan.path[plan.path.size() - 1]
	), _describe(plan))


# (c) With the target rule tied (equal DEF), the bigger share of maximum HP wins; neither foe can
# answer the bow, so both shares carry the +50.
func _test_value_share() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p_big", Vector2i(2, 0), "sword", {
		CombatValue.Key.DEF: 3.0, CombatValue.Key.HP: 30.0,
	})
	world.add_player("p_small", Vector2i(0, 2), "sword", {
		CombatValue.Key.DEF: 3.0, CombatValue.Key.HP: 12.0,
	})
	var plan: EnemyPlan = world.decide("e1")
	var big: EnemyPlan = _option_on(world, "e1", "p_big")
	_check.call("value: the bigger share of maximum HP", (
			plan.target_id == "p_small"
			and not plan.is_kill
			and plan.decided_by == EnemyPlan.Step.VALUE
			and big != null
			and big.value < plan.value
	), "%s vs %s" % [_describe(plan), _describe(big)])
	# 9 damage at the 2RN chance of Hit 95 (the bow's 100 less plain's avoid 5), × 150.
	var expected: float = 9.0 / 12.0 * 150.0 * RollSource.hit_2rn_probability(95)
	_check.call("value: 9 of 12 HP at Hit 95, × 150 for no damage back", (
			is_equal_approx(plan.value, expected)
	), "%f vs %f" % [plan.value, expected])


# (d) Two tiles to strike the same foe from with the same value: the forest's avoid 20, DEF 1 and
# RES 1 (2.4) beat plain's avoid 5 (0.1), though the forest costs more to enter.
func _test_terrain() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain plain plain",
		"plain plain forest plain plain plain",
		"plain plain plain plain plain plain",
		"plain plain plain plain plain plain",
	])
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 2), "bow")
	var plan: EnemyPlan = world.decide("e1")
	_check.call("terrain: the forest tile", (
			plan.tile == Vector2i(2, 1)
			and plan.decided_by == EnemyPlan.Step.TERRAIN
			and is_equal_approx(plan.terrain, 2.4)
	), _describe(plan))
	_check.call("terrain: plain rates avoid ÷ 50", (
			is_equal_approx(EnemyAI.terrain_rating(world.state().grid, Vector2i(1, 2)), 0.1)
	))


# (e) Two plain tiles at the same path cost: the earlier row wins.
func _test_fixed_order() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 2), "bow")
	var plan: EnemyPlan = world.decide("e1")
	_check.call("fixed order: the same cost, the earlier row", (
			plan.tile == Vector2i(2, 1)
			and plan.path_cost == 3
			and plan.decided_by == EnemyPlan.Step.TILE_ORDER
	), _describe(plan))
	_check.call("fixed order: the plan's path is its command's", (
			plan.to_command().path == plan.path
			and plan.path == [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
	), str(plan.path))


# The dry rule: a flooded tile is dropped when a dry one serves the same attack on the same foe,
# and kept when none does.
func _test_dry_tile() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 2), "bow")
	var flooded: Dictionary[Vector2i, bool] = {Vector2i(2, 1): true}
	var plan: EnemyPlan = world.decide("e1", flooded)
	_check.call("dry: a dry tile that serves the same attack", (
			plan.target_id == "p1" and plan.tile == Vector2i(1, 2) and not plan.is_flooded
	), _describe(plan))
	var all_around: Dictionary[Vector2i, bool] = {
		Vector2i(2, 1): true, Vector2i(1, 2): true, Vector2i(3, 2): true, Vector2i(2, 3): true,
	}
	var only: EnemyPlan = world.decide("e1", all_around)
	_check.call("dry: a flooded tile when no dry one serves", (
			only.kind == EnemyPlan.Kind.ATTACK
			and only.tile == Vector2i(2, 1)
			and only.is_flooded
	), _describe(only))


# The dry rule while advancing: the flooded tile closest to the foe is passed over.
func _test_dry_advance() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain plain plain plain plain plain plain",
	])
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(9, 0), "bow")
	var plan: EnemyPlan = world.decide("e1")
	_check.call("advance: as far toward the nearest foe as it can", (
			plan.kind == EnemyPlan.Kind.ADVANCE
			and plan.target_id == "p1"
			and plan.tile == Vector2i(5, 0)
			and plan.progress == 3
			and plan.decided_by == EnemyPlan.Step.PROGRESS
	), _describe(plan))
	var flooded: Dictionary[Vector2i, bool] = {Vector2i(5, 0): true}
	var dry: EnemyPlan = world.decide("e1", flooded)
	_check.call("advance: never ends on a flooded tile when a dry one serves", (
			dry.tile == Vector2i(4, 0) and not dry.is_flooded
	), _describe(dry))
	_check.call("advance: its command walks and waits", (
			dry.to_command().action == UnitTurnCommand.Action.WAIT
			and dry.to_command().path.size() == 5
	))


# Support: the ally missing the most HP.
func _test_heal_most_wounded() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("h1", HEALER, Vector2i(2, 2))
	world.add_enemy("b1", BRUTE, Vector2i(2, 0))
	world.add_enemy("b2", BRUTE, Vector2i(2, 4))
	world.wound("b1", 18)
	world.wound("b2", 13)
	var plan: EnemyPlan = world.decide("h1")
	_check.call("heal: the ally missing the most HP", (
			plan.kind == EnemyPlan.Kind.STAFF
			and plan.target_id == "b2"
			and plan.decided_by == EnemyPlan.Step.TARGET_RULE
			and plan.target_rule_key == -10.0
	), _describe(plan))
	_check.call("heal: its command uses the staff on that ally", (
			plan.to_command().action == UnitTurnCommand.Action.STAFF
			and plan.to_command().target_id == "b2"
	))


# Support: of the tiles it can heal from, the one no player unit can attack next phase. p1 (sword,
# movement 2) reaches every tile within 3 of (2, 5); (3, 1) is the one heal tile beyond it.
func _test_heal_safest_tile() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("h1", HEALER, Vector2i(0, 2))
	world.add_enemy("b1", BRUTE, Vector2i(3, 2))
	world.add_enemy("b2", BRUTE, Vector2i(4, 2))
	world.add_player("p1", Vector2i(2, 5), "sword", {CombatValue.Key.MOVEMENT: 2.0})
	world.wound("b1", 10)
	var plan: EnemyPlan = world.decide("h1")
	_check.call("heal: from the tile fewest player units can attack", (
			plan.target_id == "b1"
			and plan.tile == Vector2i(3, 1)
			and plan.safety == 0
			and plan.decided_by == EnemyPlan.Step.SAFETY
	), _describe(plan))


# Support with nobody hurt: a tile no player unit can attack, beside its ally. (3, 1) and (4, 2)
# both qualify at path cost 4; the earlier row wins.
func _test_regroup() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("h1", HEALER, Vector2i(0, 2))
	world.add_enemy("b1", BRUTE, Vector2i(3, 2))
	world.add_player("p1", Vector2i(2, 5), "sword", {CombatValue.Key.MOVEMENT: 2.0})
	var plan: EnemyPlan = world.decide("h1")
	_check.call("regroup: nobody hurt, a safe tile beside its ally", (
			plan.kind == EnemyPlan.Kind.REGROUP
			and plan.safety == 0
			and plan.pack == 1
			and plan.tile == Vector2i(3, 1)
	), _describe(plan))


# Once the darkness has arrived, Support and Hold play Aggressive on the nearest foe: the healer
# advances instead of healing, and the Crossbowman leaves its plain tile for the forest one it can
# shoot the same foe from (terrain), which Hold's own-tile rule kept it from.
func _test_darkness() -> void:
	var rows: Array[String] = PLAIN_8X8.duplicate()
	rows[0] = "plain forest plain plain plain plain plain plain"
	var world: AiWorld = AiWorld.new(_catalog, rows)
	world.add_enemy("h1", HEALER, Vector2i(7, 7))
	world.add_enemy("b1", BRUTE, Vector2i(6, 7))
	world.add_enemy("c1", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p_tough", Vector2i(3, 0), "sword", {CombatValue.Key.DEF: 3.0})
	world.wound("b1", 10)
	var heal: EnemyPlan = world.decide("h1")
	var stand: EnemyPlan = world.decide("c1")
	_check.call("darkness: before it, the healer heals", heal.kind == EnemyPlan.Kind.STAFF)
	_check.call("darkness: before it, Hold shoots from its tile", (
			stand.target_id == "p_tough" and stand.path.is_empty() and not stand.is_kill
	), _describe(stand))
	world.state().map.has_darkness_arrived = true
	var advance: EnemyPlan = world.decide("h1")
	_check.call("darkness: the healer turns Aggressive and advances", (
			advance.kind == EnemyPlan.Kind.ADVANCE
			and advance.behavior == EnemyClassDefinition.Behavior.AGGRESSIVE
			and advance.target_rule_id == ContentIds.TARGET_NEAREST_FOE
	), _describe(advance))
	var roam: EnemyPlan = world.decide("c1")
	_check.call("darkness: the Crossbowman leaves its tile for better ground", (
			roam.target_id == "p_tough"
			and roam.tile == Vector2i(1, 0)
			and roam.behavior == EnemyClassDefinition.Behavior.AGGRESSIVE
			and roam.decided_by == EnemyPlan.Step.TERRAIN
	), _describe(roam))


# (a) before Hold: a kill it can reach by moving beats shooting the foe in range from its tile.
func _test_hold_moves_to_kill() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", CROSSBOWMAN, Vector2i(0, 0))
	world.add_player("p_tough", Vector2i(2, 0), "sword", {CombatValue.Key.DEF: 3.0})
	world.add_player("p_weak", Vector2i(0, 6), "sword", {CombatValue.Key.DEF: 0.0})
	world.wound("p_weak", 4)
	var plan: EnemyPlan = world.decide("e1")
	_check.call("hold: moves to kill a foe it can reach", (
			plan.target_id == "p_weak"
			and plan.is_kill
			and not plan.path.is_empty()
			and plan.decided_by == EnemyPlan.Step.KILL
	), _describe(plan))


# (a) by splash: p_b (2 HP, on forest: Hit 45) stands beside (1, 2), a tile the Brute can strike
# p_a (plain: Hit 60) from. Every unit Cleave can splash the Brute can also strike, so striking
# p_b is a kill too; the splash kill wins on the higher chance its hit lands.
func _test_cleave_splash_kill() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain plain plain",
		"plain plain plain plain plain plain",
		"forest plain plain plain plain plain",
		"plain plain plain plain plain plain",
	])
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_cleave("e1")
	world.add_player("p_a", Vector2i(2, 2), "bow")
	world.add_player("p_b", Vector2i(0, 2), "bow")
	world.wound("p_b", 2)
	var plan: EnemyPlan = world.decide("e1")
	var fallen: CombatForecast.UnitOutcome = (
			null if plan.forecast == null else plan.forecast.unit("p_b")
	)
	_check.call("splash: strikes p_a where Cleave finishes p_b", (
			plan.target_id == "p_a"
			and plan.tile == Vector2i(1, 2)
			and plan.is_kill
			and fallen != null
			and fallen.is_defeated
	), _describe(plan))
	_check.call("splash: decided by the kill's chance", (
			plan.decided_by == EnemyPlan.Step.KILL_CHANCE
			and is_equal_approx(plan.kill_chance, RollSource.hit_2rn_probability(60))
	), _describe(plan))


# Cleave on its own ally changes nothing: with a 1-HP ally beside its best tile, the Brute strikes
# from there as it does with no ally, the ally's fall neither a kill nor a reason to move.
func _test_splash_on_ally_ignored() -> void:
	var alone: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	alone.add_enemy("e1", BRUTE, Vector2i(0, 0))
	alone.add_cleave("e1")
	alone.add_player("p1", Vector2i(2, 2), "bow")
	var without: EnemyPlan = alone.decide("e1")
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_cleave("e1")
	world.add_enemy("e2", BRUTE, Vector2i(3, 1))
	world.wound("e2", 1)
	world.add_player("p1", Vector2i(2, 2), "bow")
	var plan: EnemyPlan = world.decide("e1")
	var ally: CombatForecast.UnitOutcome = (
			null if plan.forecast == null else plan.forecast.unit("e2")
	)
	_check.call("splash: its own ally beside the tile changes nothing", (
			without.tile == Vector2i(2, 1)
			and plan.tile == without.tile
			and plan.target_id == "p1"
			and not plan.is_kill
			and plan.decided_by == without.decided_by
	), "%s / %s" % [_describe(without), _describe(plan)])
	_check.call("splash: the ally falls in the forecast all the same", (
			ally != null and ally.is_defeated
	))


# The same board gives the same plan, twice and on a sandbox copy of the engine.
func _test_same_board_same_plan() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(5, 5))
	world.add_enemy("e3", HEALER, Vector2i(6, 6))
	world.add_player("p1", Vector2i(2, 2), "bow")
	world.add_player("p2", Vector2i(3, 5), "sword", {CombatValue.Key.DEF: 1.0})
	world.wound("e1", 15)
	var before: int = world.engine().fact_log.size()
	var first: String = _describe(EnemyAI.next_plan(world.engine(), _catalog))
	var second: String = _describe(EnemyAI.next_plan(world.engine(), _catalog))
	var sandbox: EffectEngine = world.engine().copy_for_sandbox(ForecastRolls.new())
	var copied: String = _describe(EnemyAI.next_plan(sandbox, _catalog))
	_check.call("determinism: the same plan twice", first == second, "%s / %s" % [first, second])
	_check.call("determinism: the same plan on a sandbox", first == copied, copied)
	_check.call("determinism: deciding recorded nothing", (
			world.engine().fact_log.size() == before and world.engine().diagnostics.is_empty()
	))
	var plans: PackedStringArray = []
	for unit_id: String in ["e1", "e2", "e3"]:
		plans.append(_describe(world.decide(unit_id)))
	var again: PackedStringArray = []
	for unit_id: String in ["e1", "e2", "e3"]:
		again.append(_describe(world.decide(unit_id)))
	_check.call("determinism: every enemy's plan, twice", plans == again, "\n".join(plans))


# Two Brutes can both defeat p1. With every hit landing, the first takes the kill; the second
# re-decides on the board it left and goes for p2.
func _test_redecide_after_kill() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_8X8, ForecastRolls.new())
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_enemy("e2", BRUTE, Vector2i(0, 4))
	world.add_player("p1", Vector2i(0, 2), "bow")
	world.add_player("p2", Vector2i(3, 4), "bow")
	world.wound("p1", 3)
	var first: EnemyPlan = EnemyAI.next_plan(world.engine(), _catalog)
	_check.call("re-decide: the first kill goes first", (
			first.actor_id == "e1" and first.target_id == "p1" and first.is_kill
	), _describe(first))
	var engine: EffectEngine = world.engine()
	engine.begin_step()
	first.to_command().resolve(world.session)
	engine.drain()
	var second: EnemyPlan = EnemyAI.next_plan(engine, _catalog)
	_check.call("re-decide: p1 is gone and e1 has acted", (
			not world.state().has_unit("p1") and world.state().unit("e1").has_acted
	))
	_check.call("re-decide: the other Brute turns to p2", (
			second.actor_id == "e2" and second.target_id == "p2"
	), _describe(second))


# An enemy whose unit type is no enemy class Waits where it stands, as before the AI.
func _test_no_class_waits() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = "e1"
	unit.side = AiWorld.ENEMY
	unit.unit_type = "no_such_class"
	unit.tile = Vector2i(3, 3)
	unit.hp = 10
	world.session.add_unit(unit, {CombatValue.Key.HP: 10.0, CombatValue.Key.MOVEMENT: 5.0})
	world.add_player("p1", Vector2i(3, 2))
	var plan: EnemyPlan = world.decide("e1")
	_check.call("no class: it waits where it stands", (
			plan.kind == EnemyPlan.Kind.WAIT
			and plan.path.is_empty()
			and plan.to_command().action == UnitTurnCommand.Action.WAIT
	), _describe(plan))


func _test_register() -> void:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_6X4)
	EnemyAI.register(world.session, _catalog)
	_check.call("register: on ENEMY_COMMANDS", (
			world.session.hooks.has_registered(CombatHooks.Hook.ENEMY_COMMANDS)
	))


# A seeded battle of all three classes against three player units who only wait: every enemy
# command the AI gives resolves, none is rejected, and the enemies attack, heal and move.
func _test_headless_phase() -> void:
	var world: AiWorld = AiWorld.new(_catalog, [
		"plain plain plain plain forest plain plain plain",
		"plain plain plain plain plain plain plain plain",
		"plain forest plain plain plain plain forest plain",
		"plain plain plain plain plain plain plain plain",
		"plain plain plain forest plain plain plain plain",
		"plain plain plain plain plain plain plain plain",
	])
	world.add_enemy("e1", BRUTE, Vector2i(6, 1))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(7, 4))
	world.add_enemy("e3", HEALER, Vector2i(7, 2))
	world.add_player("p1", Vector2i(1, 1), "sword")
	world.add_player("p2", Vector2i(1, 4), "bow")
	world.add_player("p3", Vector2i(2, 5), "sword", {CombatValue.Key.DEF: 4.0})
	EnemyAI.register(world.session, _catalog)
	world.session.open_battle()
	var diagnostics: PackedStringArray = []
	var rejected: PackedStringArray = []
	for turn: int in 6:
		if world.session.is_finished or world.state().units_of(AiWorld.PLAYER).is_empty():
			break
		for unit_id: String in world.state().units_of(AiWorld.PLAYER):
			_send(world, UnitTurnCommand.new(0, unit_id), rejected, diagnostics)
		_send(world, EndTurnCommand.new(0), rejected, diagnostics)
	var kinds: Dictionary[String, int] = {}
	for fact: CombatFact in world.engine().fact_log:
		if world.state().side_of(fact.actor_id) != AiWorld.ENEMY:
			continue
		var kind_name: String = CombatFact.Kind.find_key(fact.kind) as String
		kinds[kind_name] = kinds.get(kind_name, 0) + 1
	_check.call("phase: no command rejected, no diagnostic", (
			rejected.is_empty() and diagnostics.is_empty()
	), "%s %s" % [rejected, diagnostics])
	_check.call("phase: the enemies move and attack", (
			kinds.get("UNIT_MOVED", 0) > 0 and kinds.get("ATTACK_MADE", 0) > 0
	), str(kinds))
	_check.call("phase: turns went by", world.state().turn > 1, str(world.state().turn))


func _send(
		world: AiWorld,
		command: Command,
		rejected: PackedStringArray,
		diagnostics: PackedStringArray
) -> void:
	world.session.submit(command)
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	if batch == null:
		return
	if batch.is_rejected():
		rejected.append("%s: %s" % [batch.label, batch.rejected_reason])
	diagnostics.append_array(batch.diagnostics)


# The best option of unit_id that targets target_id, rated as decide() rates it: a plan built on
# a board where every other foe is out of the way is not the same, so this reads the options by
# deciding with every other target removed from a sandbox copy.
func _option_on(world: AiWorld, unit_id: String, target_id: String) -> EnemyPlan:
	var sandbox: EffectEngine = world.engine().copy_for_sandbox(ForecastRolls.new())
	var state: CombatState = sandbox.state
	for other: String in state.units_of(AiWorld.PLAYER):
		if other != target_id:
			state.defeat(sandbox, other, "")
	var plan: EnemyPlan = EnemyAI.decide(sandbox, _catalog, unit_id)
	return plan if plan.target_id == target_id else null


func _describe(plan: EnemyPlan) -> String:
	if plan == null:
		return "null"
	var parts: PackedStringArray = [
		"%s %s -> %s at %s" % [
			plan.actor_id, EnemyPlan.Kind.find_key(plan.kind), plan.target_id, plan.tile,
		],
		"path %s cost %d" % [plan.path, plan.path_cost],
		"kill %s chance %.4f rule %.1f value %.3f" % [
			plan.is_kill, plan.kill_chance, plan.target_rule_key, plan.value,
		],
		"safety %d pack %d progress %d terrain %.2f" % [
			plan.safety, plan.pack, plan.progress, plan.terrain,
		],
		"by %s" % [EnemyPlan.Step.find_key(plan.decided_by)],
	]
	return " ".join(parts)
