# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_cases.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

extends RefCounted
## Turn loop and command cases for tests/combat/run_all.gd: Phase Start and Phase End order, the
## full hook order, terrain healing, the enemy phase as one command, the unit-turn, end-turn and
## rune commands with their rejections, the second move, a range-0 staff, a scripted two-side fight
## that runs to a defeat and repeats exactly, and battle start: the opening swap window, its swaps
## and Start commands, and the setting off.
##
## Each case runs a real [CombatSession] on a small hand-built map (plain, with a fort at (1, 1)
## for terrain healing), so commands go through the session's queue as they do in a battle. Every
## case also asserts that the engine reported no diagnostics, unless it provokes one.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const WAIT: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK

# The seed of every case's stream; the fight case compares two runs, never golden numbers.
const SEED: int = 20261028

# 6 × 4, plain with a fort (heals 20% of maximum HP) at (1, 1).
const ROWS: Array[String] = [
	"plain plain plain plain plain plain",
	"plain fort plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
]

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_phase_start_order()
	_test_terrain_healing_hook()
	_test_hook_order()
	_test_phase_end_heal_before_darkness()
	_test_enemies_wait_by_default()
	_test_move_and_attack()
	_test_unit_turn_rejections()
	_test_ended_seat_and_two_seats()
	_test_second_move()
	_test_range_zero_staff()
	_test_rune_command()
	_test_enemy_command_rejected()
	_test_scripted_fight()
	_test_opening_swap_then_start()
	_test_window_rejects_other_commands()
	_test_swap_rejections()
	_test_two_seats_wait_for_start()
	_test_swap_setting_off()


# Phase Start: refresh, terrain healing, PHASE_START with the turn, then Unit Turn Start per unit in
# placement order at its tile; the enemy side untouched.
func _test_phase_start_order() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1))
	world.add_unit("p2", PLAYER, 0, Vector2i(2, 1))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 3))
	world.state().set_hp("p1", 10)
	world.state().set_block("p2", 3)
	world.state().set_stance("p2", 0)
	var start: int = world.log_size()
	world.session.open_battle()
	_same("phase start: order", world.lines(start), [
		"s0#4 BLOCK_STANCE_REFRESHED p1",
		"s0#5 BLOCK_STANCE_REFRESHED p2",
		"s0#6 HEALED p1 amount 4 (hp 4, block 0)",
		"s0#7 PHASE_START side player amount 1",
		"s0#8 UNIT_TURN_START p1 tile (1, 1)",
		"s0#9 UNIT_TURN_START p2 tile (2, 1)",
	])
	_ok("phase start: Block cleared, Stance full", (
			world.state().get_block("p2") == 0 and world.state().get_stance("p2") == 2
	))
	_ok("phase start: turn 1, the player's phase", (
			world.state().turn == 1 and world.state().phase_side == PLAYER
	))
	_quiet(world)


# A TERRAIN_HEALING_ALLOWED registration that says no stops the heal (P06's flooded tiles).
func _test_terrain_healing_hook() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1))
	world.state().set_hp("p1", 10)
	var asked: Array[String] = []
	world.session.hooks.add(
			CombatHooks.Hook.TERRAIN_HEALING_ALLOWED,
			func(_session: CombatSession, unit_id: String) -> bool:
				asked.append(unit_id)
				return false
	)
	world.session.open_battle()
	_ok("terrain healing: asked per unit", asked == ["p1"], str(asked))
	_ok("terrain healing: refused", world.state().get_hp("p1") == 10)
	_ok("terrain healing: no fact", not world.kinds().contains("HEALED"))
	_quiet(world)


# Every hook at its place, in registration order, over turn 1 and the enemy phase into turn 2.
func _test_hook_order() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(1, 1))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 3))
	world.state().set_hp("p1", 10)
	var trace: Array[String] = []
	var hooks: CombatHooks = world.session.hooks
	hooks.add(CombatHooks.Hook.ARRIVALS, func(_session: CombatSession) -> void:
		trace.append("ARRIVALS")
	)
	hooks.add(
			CombatHooks.Hook.TERRAIN_HEALING_ALLOWED,
			func(_session: CombatSession, unit_id: String) -> bool:
				trace.append("HEALING %s" % [unit_id])
				return true
	)
	hooks.add(CombatHooks.Hook.INTENTS, func(_session: CombatSession) -> void:
		trace.append("INTENTS")
	)
	hooks.add(CombatHooks.Hook.AFTER_STEP, func(_session: CombatSession) -> void:
		trace.append("AFTER_STEP")
	)
	hooks.add(CombatHooks.Hook.AFTER_STEP, func(_session: CombatSession) -> void:
		trace.append("AFTER_STEP 2")
	)
	hooks.add(
			CombatHooks.Hook.PHASE_END_EFFECTS,
			func(_session: CombatSession, side: CombatFact.CombatSide) -> void:
				trace.append("PHASE_END_EFFECTS %s" % [CombatFact.CombatSide.find_key(side)])
	)
	hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(session: CombatSession) -> Command:
		trace.append("ENEMY_COMMANDS")
		if session.state.unit("e1").has_acted:
			return null
		return UnitTurnCommand.new(-1, "e1", WAIT)
	)
	hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, func(_session: CombatSession) -> void:
		trace.append("DARKNESS")
	)
	hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, func(_session: CombatSession) -> void:
		trace.append("REINFORCEMENTS")
	)
	world.session.open_battle()
	trace.append("-- open")
	world.send(UnitTurnCommand.new(0, "p1", WAIT))
	trace.append("-- wait")
	world.state().set_hp("p1", 10)
	world.send(EndTurnCommand.new(0))
	_same("hooks: the full order", trace, [
		"ARRIVALS", "HEALING p1", "INTENTS", "AFTER_STEP", "AFTER_STEP 2", "-- open",
		"AFTER_STEP", "AFTER_STEP 2", "-- wait",
		"PHASE_END_EFFECTS PLAYER", "AFTER_STEP", "AFTER_STEP 2",
		"AFTER_STEP", "AFTER_STEP 2",
		"ENEMY_COMMANDS", "AFTER_STEP", "AFTER_STEP 2", "ENEMY_COMMANDS",
		"PHASE_END_EFFECTS ENEMY", "AFTER_STEP", "AFTER_STEP 2",
		"DARKNESS", "AFTER_STEP", "AFTER_STEP 2",
		"REINFORCEMENTS", "AFTER_STEP", "AFTER_STEP 2",
		"ARRIVALS", "HEALING p1", "INTENTS", "AFTER_STEP", "AFTER_STEP 2",
	])
	_ok("hooks: turn 2, the player's phase", (
			world.state().turn == 2 and world.state().phase_side == PLAYER
	))
	_quiet(world)


# Phase End: PHASE_END, Unit Turn End per unit (the idle one too), the drain, then the darkness
# hook. A Phase End heal saves a unit the darkness alone would defeat (question 12).
func _test_phase_end_heal_before_darkness() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, 0, Vector2i(3, 0))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 3))
	world.add_effect("effect:band", "p1", _definition(
			EffectDefinition.Trigger.UNIT_TURN_END,
			[_gain(GainResource.Pool.HP, _constant(5.0))]
	))
	world.session.hooks.add(
			CombatHooks.Hook.PHASE_END_EFFECTS,
			func(session: CombatSession, side: CombatFact.CombatSide) -> void:
				if side == CombatFact.CombatSide.PLAYER:
					session.engine.deal_splash("", "p1", 5.0)
	)
	world.session.open_battle()
	world.state().set_hp("p1", 3)
	world.send(UnitTurnCommand.new(0, "p1", WAIT))
	var start: int = world.log_size()
	world.send(EndTurnCommand.new(0))
	_same("phase end: order", world.lines(start).slice(0, 7), [
		"s0#%d PHASE_END side player" % [start + 1],
		"s0#%d UNIT_TURN_END p1 tile (0, 0)" % [start + 2],
		"s0#%d EFFECT_ACTIVATED p1 effect effect:band" % [start + 3],
		"s0#%d UNIT_TURN_END p2 tile (3, 0)" % [start + 4],
		"s0#%d HEALED p1 amount 5 (hp 5, block 0) source effect effect effect:band" % [start + 5],
		"s0#%d DAMAGE_TAKEN p1 amount 5 (hp 5, block 0) source splash" % [start + 6],
		"s0#%d BLOCK_STANCE_REFRESHED e1" % [start + 7],
	])
	_ok("phase end: the heal saved p1", world.state().has_unit("p1"))
	_quiet(world)


# With no ENEMY_COMMANDS registration, every enemy Waits, one step each, and turn 2 begins.
func _test_enemies_wait_by_default() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 3))
	world.add_unit("e2", ENEMY, -1, Vector2i(4, 3))
	world.session.open_battle()
	var start: int = world.log_size()
	var batch: CombatSession.FactBatch = world.send(EndTurnCommand.new(0))
	_same("enemy phase: one command", world.kinds(start), " ".join([
		"PHASE_END UNIT_TURN_END",
		"BLOCK_STANCE_REFRESHED BLOCK_STANCE_REFRESHED PHASE_START UNIT_TURN_START UNIT_TURN_START",
		"UNIT_WAITED UNIT_WAITED",
		"PHASE_END UNIT_TURN_END UNIT_TURN_END",
		"BLOCK_STANCE_REFRESHED PHASE_START UNIT_TURN_START",
	]))
	_ok("enemy phase: all in the end turn's batch", (
			batch.facts.size() == world.log_size() - start
	))
	_quiet(world)


# Move and attack in one command; the attack is checked from the path's end, so an attack out of
# range from there changes nothing.
func _test_move_and_attack() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0), "sword")
	world.add_unit("e1", ENEMY, -1, Vector2i(3, 0), "sword")
	world.session.open_battle()
	var short_walk: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var far: CombatSession.FactBatch = world.send(
			UnitTurnCommand.new(0, "p1", ATTACK, "e1", short_walk)
	)
	_same("attack: out of range from the path's end", far.rejected_reason, "out of range")
	_ok("attack: a rejected turn moves nothing", (
			world.state().tile_of("p1") == Vector2i(0, 0)
			and not world.state().unit("p1").has_acted
	))
	var walk: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var start: int = world.log_size()
	var batch: CombatSession.FactBatch = world.send(
			UnitTurnCommand.new(0, "p1", ATTACK, "e1", walk)
	)
	_ok("attack: move+attack resolves", not batch.is_rejected(), batch.rejected_reason)
	_same("attack: label", batch.label, "move+attack")
	_ok("attack: moved first, then the exchange", world.kinds(start).begins_with(
			"UNIT_MOVED BEFORE_COMBAT BEFORE_COMBAT ATTACK_MADE"
	), world.kinds(start))
	var unit: CombatUnitState = world.state().unit("p1")
	_ok("attack: tiles and cost counted", unit.tiles_moved == 2 and unit.movement_spent == 2)
	_quiet(world)


func _test_unit_turn_rejections() -> void:
	var world: TurnWorld = TurnWorld.new(PackedInt32Array([0, 1]))
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0), "sword")
	world.add_unit("q1", PLAYER, 1, Vector2i(0, 2), "sword")
	world.add_unit("e1", ENEMY, -1, Vector2i(1, 0), "sword")
	_same(
			"reject: before the battle opens",
			world.send(UnitTurnCommand.new(0, "p1", WAIT)).rejected_reason,
			"not the player phase"
	)
	world.session.open_battle()
	_same(
			"reject: another seat's unit",
			world.send(UnitTurnCommand.new(0, "q1", WAIT)).rejected_reason,
			"q1 isn't seat 0's unit"
	)
	_same(
			"reject: an enemy in the player phase",
			world.send(UnitTurnCommand.new(-1, "e1", WAIT)).rejected_reason,
			"not the enemy phase"
	)
	_same(
			"reject: an attack on itself",
			world.send(UnitTurnCommand.new(0, "p1", ATTACK, "p1")).rejected_reason,
			"an attack needs a target at range 1 or more"
	)
	_same(
			"reject: an attack with no target",
			world.send(UnitTurnCommand.new(0, "p1", ATTACK)).rejected_reason,
			"an attack needs a target at range 1 or more"
	)
	var diagonal: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1)]
	_same(
			"reject: a path that isn't a walk",
			world.send(UnitTurnCommand.new(0, "p1", WAIT, "", diagonal)).rejected_reason,
			"path: not a walk of single steps"
	)
	var forecast: int = world.session.last_seq()
	world.send(UnitTurnCommand.new(1, "q1", WAIT))
	world.engine().deal_splash("", "e1", 1.0)
	var stale: UnitTurnCommand = UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	stale.based_on_seq = forecast
	_ok("reject: a stale forecast", world.send(stale).rejected_reason.begins_with(
			"stale forecast"
	))
	world.send(UnitTurnCommand.new(0, "p1", WAIT))
	_same(
			"reject: a unit that has acted",
			world.send(UnitTurnCommand.new(0, "p1", WAIT)).rejected_reason,
			"p1 has acted"
	)
	_quiet(world)


# The phase ends only when every seat with units has ended; an ended seat can't act; a seat with
# no units can't end.
func _test_ended_seat_and_two_seats() -> void:
	var world: TurnWorld = TurnWorld.new(PackedInt32Array([0, 1, 2]))
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	world.add_unit("q1", PLAYER, 1, Vector2i(0, 2))
	world.session.open_battle()
	var first: CombatSession.FactBatch = world.send(EndTurnCommand.new(0))
	_ok("end turn: the first seat records nothing", (
			not first.is_rejected() and first.facts.is_empty()
	))
	_ok("end turn: still the player phase", world.state().phase_side == PLAYER)
	_same(
			"end turn: an ended seat can't act",
			world.send(UnitTurnCommand.new(0, "p1", WAIT)).rejected_reason,
			"seat 0 has ended its turn"
	)
	_same(
			"end turn: not twice",
			world.send(EndTurnCommand.new(0)).rejected_reason,
			"seat 0 has ended its turn"
	)
	_same(
			"end turn: a seat with no units here",
			world.send(EndTurnCommand.new(2)).rejected_reason,
			"seat 2 has no units on this map"
	)
	world.send(EndTurnCommand.new(1))
	_ok("end turn: the last seat runs the enemy phase into turn 2", (
			world.state().turn == 2 and world.state().ended_seats.is_empty()
	))
	_quiet(world)


# Skirmisher (MAY_MOVE_AFTER_ACTING): after acting, one more move with the movement left.
func _test_second_move() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	var skirmisher: SetPermission = SetPermission.new()
	skirmisher.permission = CombatValue.Permission.MAY_MOVE_AFTER_ACTING
	skirmisher.allow = true
	world.add_effect("effect:skirmisher", "p1", _definition(
			EffectDefinition.Trigger.ALWAYS, [skirmisher]
	))
	world.session.open_battle()
	var walk: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	world.send(UnitTurnCommand.new(0, "p1", WAIT, "", walk))
	_ok("second move: pending after acting", world.state().unit("p1").is_second_move_pending)
	var too_far: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(5, 1),
	]
	_same(
			"second move: only the movement left (5 - 2)",
			world.send(
					UnitTurnCommand.new(0, "p1", UnitTurnCommand.Action.MOVE, "", too_far)
			).rejected_reason,
			"path: too far"
	)
	var back: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]
	var batch: CombatSession.FactBatch = world.send(
			UnitTurnCommand.new(0, "p1", UnitTurnCommand.Action.MOVE, "", back)
	)
	_ok("second move: resolves", not batch.is_rejected(), batch.rejected_reason)
	_ok("second move: spent", (
			not world.state().unit("p1").is_second_move_pending
			and world.state().tile_of("p1") == Vector2i(2, 2)
	))
	_same(
			"second move: only once",
			world.send(UnitTurnCommand.new(0, "p1", UnitTurnCommand.Action.MOVE)).rejected_reason,
			"p1 has no move left after acting"
	)
	_quiet(world)


# Everwall at range 0 (question 14): the command names no target and the user is filled in;
# Used staff on ally names the user. Every attack needs a target at range 1 or more.
func _test_range_zero_staff() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, 0, Vector2i(1, 0), "everwall")
	world.add_unit("e1", ENEMY, -1, Vector2i(2, 0))
	world.session.open_battle()
	_same(
			"range 0: no ally but the user",
			world.send(
					UnitTurnCommand.new(0, "p2", UnitTurnCommand.Action.STAFF, "p1")
			).rejected_reason,
			"out of range"
	)
	var start: int = world.log_size()
	var batch: CombatSession.FactBatch = world.send(
			UnitTurnCommand.new(0, "p2", UnitTurnCommand.Action.STAFF)
	)
	_ok("range 0: resolves with no target", not batch.is_rejected(), batch.rejected_reason)
	_same("range 0: the user is the target", world.lines(start), [
		"s0#%d BLOCK_GAINED p1 <- p2 amount 8 (hp 0, block 8)" % [start + 1],
		"s0#%d BLOCK_GAINED p2 amount 8 (hp 0, block 8)" % [start + 2],
		"s0#%d USED_STAFF_ON_ALLY p2 -> p2" % [start + 3],
	])
	_same("range 0: the batch's target", batch.target_id, "p2")
	_quiet(world)


func _test_rune_command() -> void:
	var world: TurnWorld = TurnWorld.new(PackedInt32Array([0, 1]))
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	world.add_unit("q1", PLAYER, 1, Vector2i(0, 2))
	world.state().rune_slots[0] = PackedStringArray(["rune:mend", "rune:recall"])
	var mend: GainResource = _gain(GainResource.Pool.HP, _constant(10.0))
	mend.target = CommandTarget.new()
	world.engine().register(EffectInstance.new(
			"effect:mend",
			_definition(EffectDefinition.Trigger.ALWAYS, [mend]),
			EffectOwner.for_rune("rune:mend", 0),
			Modifier.SourceKind.RUNE
	))
	world.state().set_hp("q1", 5)
	_same(
			"rune: player phase only",
			world.send(CastRuneCommand.new(0, "rune:mend", "q1")).rejected_reason,
			"not the player phase"
	)
	world.session.open_battle()
	var batch: CombatSession.FactBatch = world.send(CastRuneCommand.new(0, "rune:mend", "q1"))
	_ok("rune: on a teammate's unit", not batch.is_rejected(), batch.rejected_reason)
	_ok("rune: Mend heals 10", world.state().get_hp("q1") == 15)
	_same(
			"rune: Recall needs the seat's own units",
			world.send(CastRuneCommand.new(0, "rune:recall", "p1", "q1")).rejected_reason,
			"not two of the seat's units"
	)
	_same(
			"rune: not from a seat's empty slots",
			world.send(CastRuneCommand.new(1, "rune:mend", "q1")).rejected_reason,
			"not in the seat's rune slots"
	)
	world.send(EndTurnCommand.new(0))
	world.state().rune_slots[0] = PackedStringArray(["rune:recall"])
	_same(
			"rune: not after the seat ended",
			world.send(CastRuneCommand.new(0, "rune:recall", "p1", "p1")).rejected_reason,
			"seat 0 has ended its turn"
	)
	_quiet(world)


# An AI command that fails its checks is reported, costs nothing, and the phase goes on.
func _test_enemy_command_rejected() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 3), "sword")
	var asked: Array[int] = [0]
	var hooks: CombatHooks = world.session.hooks
	hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(_session: CombatSession) -> Command:
		asked[0] += 1
		return UnitTurnCommand.new(-1, "e1", ATTACK, "p1") if asked[0] == 1 else null
	)
	world.session.open_battle()
	var batch: CombatSession.FactBatch = world.send(EndTurnCommand.new(0))
	_same("enemy: a bad AI command is reported", batch.diagnostics, PackedStringArray([
		"PhaseRunner: enemy attack e1 rejected - out of range",
	]))
	_ok("enemy: the phase still ends", world.state().turn == 2)


# A scripted fight: a swordfighter and a Brute trade attacks each turn until one is defeated;
# the same seed gives the same fact log.
func _test_scripted_fight() -> void:
	var first: PackedStringArray = _fight()
	var second: PackedStringArray = _fight()
	_ok("fight: runs to a defeat", "\n".join(first).contains("DEFEATED"), str(first.size()))
	_ok("fight: the same seed, the same log", first == second)


func _fight() -> PackedStringArray:
	var world: TurnWorld = TurnWorld.new()
	world.add_unit("p1", PLAYER, 0, Vector2i(2, 1), "sword")
	world.add_unit("e1", ENEMY, -1, Vector2i(3, 1), "axe")
	var hooks: CombatHooks = world.session.hooks
	hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(session: CombatSession) -> Command:
		if not session.state.has_unit("p1") or session.state.unit("e1").has_acted:
			return null
		return UnitTurnCommand.new(-1, "e1", ATTACK, "p1")
	)
	world.session.open_battle()
	for turn: int in 10:
		if not world.state().has_unit("p1") or not world.state().has_unit("e1"):
			break
		world.send(UnitTurnCommand.new(0, "p1", ATTACK, "e1"))
		if world.state().has_unit("p1"):
			world.send(EndTurnCommand.new(0))
	_quiet(world)
	var lines: PackedStringArray = []
	lines.append_array(world.lines(0))
	return lines


# Setting on: the battle opens in the swap window with nothing recorded; a swap trades tiles,
# records UNIT_MOVED for both and ends no turn; Start runs turn 1's Phase Start, where Phalanx
# (Block per adjacent ally) reads the tile after the swap.
func _test_opening_swap_then_start() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.mark_deployment([Vector2i(0, 3), Vector2i(2, 3), Vector2i(3, 3)])
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 3))
	world.add_unit("p2", PLAYER, 0, Vector2i(3, 3))
	world.add_unit("p3", PLAYER, 0, Vector2i(2, 3))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 0))
	world.add_effect("effect:ph", "p1", _phalanx())
	world.session.flush("deployment")
	var start: int = world.log_size()
	var opened: CombatSession.FactBatch = world.session.open_battle(PackedInt32Array([0]))
	_ok("swap: the window opens with nothing recorded", (
			opened == null
			and world.log_size() == start
			and world.state().map.opening_swap_open
			and world.state().turn == 0
	))
	var swap: CombatSession.FactBatch = world.send(_swap(0, "p1", "p3"))
	_ok("swap: resolves", not swap.is_rejected(), swap.rejected_reason)
	_same("swap: UNIT_MOVED for both", world.lines(start), [
		"s0#%d UNIT_MOVED p1 tile (2, 3)" % [start + 1],
		"s0#%d UNIT_MOVED p3 tile (0, 3)" % [start + 2],
	])
	_ok("swap: ends no turn", (
			not world.state().unit("p1").has_acted and not world.state().unit("p3").has_acted
	))
	var started: CombatSession.FactBatch = world.send(StartCommand.new(0))
	_ok("start: resolves", not started.is_rejected(), started.rejected_reason)
	_ok("start: closes the window and runs turn 1", (
			not world.state().map.opening_swap_open
			and world.state().turn == 1
			and world.kinds(start + 2).contains("PHASE_START")
	), world.kinds(start + 2))
	_same("start: Phalanx counts the ally next to p1's new tile", world.state().get_block("p1"), 1)
	_quiet(world)


# In the window only swaps and Start are taken.
func _test_window_rejects_other_commands() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.mark_deployment([Vector2i(0, 3), Vector2i(1, 3)])
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 3), "sword")
	world.add_unit("p2", PLAYER, 0, Vector2i(1, 3))
	world.add_unit("e1", ENEMY, -1, Vector2i(0, 2))
	world.session.open_battle(PackedInt32Array([0]))
	var start: int = world.log_size()
	var reason: String = "only swaps and Start before turn 1"
	_same(
			"window: a wait is rejected",
			world.send(UnitTurnCommand.new(0, "p2", WAIT)).rejected_reason,
			reason
	)
	_same(
			"window: an attack is rejected",
			world.send(UnitTurnCommand.new(0, "p1", ATTACK, "e1")).rejected_reason,
			reason
	)
	_same("window: end turn is rejected", world.send(EndTurnCommand.new(0)).rejected_reason, reason)
	_same(
			"window: a rune is rejected",
			world.send(CastRuneCommand.new(0, "rune:mend", "p1")).rejected_reason,
			reason
	)
	_same("window: nothing was recorded", world.log_size(), start)
	_quiet(world)


# A swap needs both units on deployment tiles and no path; after the last Start, swaps and Start
# are rejected.
func _test_swap_rejections() -> void:
	var world: TurnWorld = TurnWorld.new()
	world.mark_deployment([Vector2i(0, 3), Vector2i(1, 3)])
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 3))
	world.add_unit("p2", PLAYER, 0, Vector2i(1, 3))
	world.add_unit("p3", PLAYER, 0, Vector2i(3, 3))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 0))
	world.session.open_battle(PackedInt32Array([0]))
	_same(
			"swap: off the deployment tiles",
			world.send(_swap(0, "p1", "p3")).rejected_reason,
			"not on a deployment tile"
	)
	var walk: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, 2)]
	var walking: UnitTurnCommand = _swap(0, "p1", "p2")
	walking.path = walk
	_same("swap: with a path", world.send(walking).rejected_reason, "a swap takes no path")
	world.send(StartCommand.new(0))
	_same(
			"swap: after Start",
			world.send(_swap(0, "p1", "p2")).rejected_reason,
			"the opening swap is closed"
	)
	_same(
			"start: twice",
			world.send(StartCommand.new(0)).rejected_reason,
			"the opening swap is closed"
	)
	_quiet(world)


# Two seats on one map: Phase Start waits for both Starts; a seat that started can't swap, and no
# seat swaps another's units.
func _test_two_seats_wait_for_start() -> void:
	var world: TurnWorld = TurnWorld.new(PackedInt32Array([0, 1]))
	world.mark_deployment([Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)])
	world.add_unit("p1", PLAYER, 0, Vector2i(0, 3))
	world.add_unit("p2", PLAYER, 0, Vector2i(1, 3))
	world.add_unit("q1", PLAYER, 1, Vector2i(2, 3))
	world.add_unit("q2", PLAYER, 1, Vector2i(3, 3))
	world.add_unit("e1", ENEMY, -1, Vector2i(5, 0))
	world.session.open_battle(PackedInt32Array([0, 1]))
	var start: int = world.log_size()
	world.send(StartCommand.new(0))
	_ok("two seats: one Start runs nothing", (
			world.state().turn == 0
			and world.state().map.opening_swap_open
			and world.log_size() == start
	))
	_same(
			"two seats: a seat that started can't swap",
			world.send(_swap(0, "p1", "p2")).rejected_reason,
			"seat 0 has started"
	)
	_same(
			"two seats: not another seat's unit",
			world.send(_swap(0, "q1", "q2")).rejected_reason,
			"q1 isn't seat 0's unit"
	)
	_same(
			"two seats: not with another seat's unit",
			world.send(_swap(1, "q1", "p2")).rejected_reason,
			"not two of the seat's units"
	)
	var swap: CombatSession.FactBatch = world.send(_swap(1, "q1", "q2"))
	_ok("two seats: the other seat still swaps", not swap.is_rejected(), swap.rejected_reason)
	world.send(StartCommand.new(1))
	_ok("two seats: the last Start runs turn 1", (
			world.state().turn == 1
			and not world.state().map.opening_swap_open
			and world.kinds(start).contains("PHASE_START")
	))
	_quiet(world)


# Setting off (or on only for a seat with no units here): no window, turn 1 runs as the battle
# opens, and swaps and Start are rejected.
func _test_swap_setting_off() -> void:
	for swap_seats: PackedInt32Array in [PackedInt32Array(), PackedInt32Array([1])]:
		var world: TurnWorld = TurnWorld.new()
		world.mark_deployment([Vector2i(0, 3), Vector2i(1, 3)])
		world.add_unit("p1", PLAYER, 0, Vector2i(0, 3))
		world.add_unit("p2", PLAYER, 0, Vector2i(1, 3))
		world.add_unit("e1", ENEMY, -1, Vector2i(5, 0))
		var opened: CombatSession.FactBatch = world.session.open_battle(swap_seats)
		var label: String = "swap off %s" % [swap_seats]
		_ok("%s: turn 1 at once" % [label], (
				opened != null
				and world.state().turn == 1
				and not world.state().map.opening_swap_open
		))
		_same(
				"%s: a swap is rejected" % [label],
				world.send(_swap(0, "p1", "p2")).rejected_reason,
				"the opening swap is closed"
		)
		_same(
				"%s: Start is rejected" % [label],
				world.send(StartCommand.new(0)).rejected_reason,
				"the opening swap is closed"
		)
		_quiet(world)


func _swap(sender: int, unit_id: String, other_id: String) -> UnitTurnCommand:
	return UnitTurnCommand.new(sender, unit_id, UnitTurnCommand.Action.OPENING_SWAP, other_id)


# Phalanx (unit-roster.md, Lancer): Unit Turn Start, gain 1 Block per adjacent ally.
func _phalanx() -> EffectDefinition:
	var adjacent: Area = Area.new()
	adjacent.center = Area.Center.OWNER
	adjacent.radius = 1
	adjacent.side = EffectDefinition.UnitSide.ALLY
	adjacent.include_center = false
	var count: CountOf = CountOf.new()
	count.selector = adjacent
	return _definition(
			EffectDefinition.Trigger.UNIT_TURN_START, [_gain(GainResource.Pool.BLOCK, count)]
	)


func _definition(trigger: EffectDefinition.Trigger, operations: Array) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = trigger
	definition.operations.assign(operations)
	return definition


func _gain(pool: GainResource.Pool, amount: ValueSource) -> GainResource:
	var gain: GainResource = GainResource.new()
	gain.pool = pool
	gain.amount = amount
	return gain


func _constant(value: float) -> Constant:
	var constant: Constant = Constant.new()
	constant.value = value
	return constant


# Untyped: compares strings, arrays and packed arrays alike.
func _same(case_name: String, actual: Variant, expected: Variant) -> void:
	var is_same: bool = actual == expected
	_ok(case_name, is_same, "got %s" % [actual])


func _quiet(world: TurnWorld) -> void:
	var diagnostics: PackedStringArray = world.engine().diagnostics
	_ok("diagnostics: none", diagnostics.is_empty(), str(diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


# One map's session on ROWS, with units placed directly and commands sent through its queue.
class TurnWorld:
	extends RefCounted

	# Weapon presets: damage, AtkX, profile, range min, range max, Hit, weight, staff kind, amount,
	# from game-vision.md's Simple weapon table and weapons.md (Everwall: 5 Block, range 0).
	const WEAPONS: Dictionary[String, Array] = {
		"sword": [5, 1, WeaponTriangle.Profile.NIMBLE, 1, 1, 80, 8, 0, 0],
		"axe": [10, 1, WeaponTriangle.Profile.POWER, 1, 1, 65, 15, 0, 0],
		"everwall": [0, 1, WeaponTriangle.Profile.NONE, 0, 0, 0, 0, 1, 5],
	}

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null

	func _init(seats: PackedInt32Array = PackedInt32Array([0])) -> void:
		var layout: MapLayout = MapLayout.new()
		layout.map_id = "turns"
		var cache: Dictionary[String, MapLayout.Terrain] = {}
		for y: int in ROWS.size():
			var terrain_ids: PackedStringArray = ROWS[y].split(" ", false)
			for x: int in terrain_ids.size():
				var terrain_id: String = terrain_ids[x]
				if not cache.has(terrain_id):
					cache[terrain_id] = MapLayout.Terrain.from_definition(
							MapLoader.load_terrain(terrain_id)
					)
				layout.set_terrain(Vector2i(x, y), cache[terrain_id])
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(SEED))
		session = CombatSession.new(0, seats, MapGrid.new(layout), rolls, ids)
		session.engine.verify = true

	func state() -> CombatState:
		return session.state

	func engine() -> EffectEngine:
		return session.engine

	# Marks [param tiles] as deployment tiles on the map, for the opening swap.
	func mark_deployment(tiles: Array[Vector2i]) -> void:
		for tile: Vector2i in tiles:
			session.layout.add_marker(MapLayout.MarkerKind.DEPLOYMENT, tile)
		session.layout.index_markers()

	# Places a unit with HP 20, Stance 2, 5 movement, Might 3, Speed 5, Constitution 20, holding
	# [param weapon] (a WEAPONS preset) when given.
	func add_unit(
			id: String,
			side: CombatFact.CombatSide,
			seat: int,
			tile: Vector2i,
			weapon: String = ""
	) -> void:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.hp = 20
		if not weapon.is_empty():
			unit.equipped_weapon_id = "w:%s:%s" % [weapon, id]
			session.state.add_weapon(_weapon(unit.equipped_weapon_id, weapon))
		session.add_unit(unit, {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
			CombatValue.Key.MGT: 3.0,
			CombatValue.Key.SPD: 5.0,
			CombatValue.Key.CON: 20.0,
		})

	# Registers [param definition] as a trait of [param unit_id].
	func add_effect(instance_id: String, unit_id: String, definition: EffectDefinition) -> void:
		session.engine.register(EffectInstance.new(
				instance_id,
				definition,
				EffectOwner.for_unit(
						unit_id, session.state.seat_of(unit_id), session.state.side_of(unit_id)
				),
				Modifier.SourceKind.UNIT_TRAIT,
				instance_id
		))

	# Submits [param command] and resolves the queue; returns its batch.
	func send(command: Command) -> CombatSession.FactBatch:
		session.submit(command)
		return session.resolve_next()

	func log_size() -> int:
		return session.engine.fact_log.size()

	func lines(start: int = 0) -> Array[String]:
		var found: Array[String] = []
		for i: int in range(start, session.engine.fact_log.size()):
			found.append(session.engine.fact_log[i].to_log_line())
		return found

	func kinds(start: int = 0) -> String:
		var names: PackedStringArray = []
		for i: int in range(start, session.engine.fact_log.size()):
			names.append(CombatFact.Kind.find_key(session.engine.fact_log[i].kind) as String)
		return " ".join(names)

	func _weapon(weapon_id: String, preset: String) -> CombatState.WeaponStats:
		var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
		stats.id = weapon_id
		stats.label = preset.capitalize()
		# Columns: damage, AtkX, profile, range min, range max, Hit, weight, staff kind, amount.
		var columns: Array = WEAPONS[preset]
		stats.damage = columns[0]
		stats.atk_x = columns[1]
		stats.profile = columns[2]
		stats.range_min = columns[3]
		stats.range_max = columns[4]
		stats.hit = columns[5]
		stats.weight = columns[6]
		stats.staff = columns[7]
		stats.staff_amount = columns[8]
		if preset == "everwall":
			var area: Area = Area.new()
			area.center = Area.Center.OWNER
			area.radius = 3
			area.side = EffectDefinition.UnitSide.ALLY
			area.include_center = true
			stats.area = area
		return stats
