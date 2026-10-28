# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     objective_cases.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

extends RefCounted
## Objective cases for tests/map/run_all.gd: each objective's win, Defend's loss, the common losses
## (a commander's fall, no player unit left), a loss beating a win in one step, Rout ignoring
## pending waves, Survive's early end with its speed bonus, [constant CombatFact.Kind.COMBAT_ENDED]
## recorded once, and a scripted two-side fight that runs to a win and to a loss.
##
## Each case runs a real [CombatSession] with [Objectives] registered, on a small hand-built map
## (6 × 4 plain) carrying the markers the case needs, so steps end through the session's queue and
## the turn loop as they do in a battle. Defeats come from a fixture command, so a case never
## depends on a roll; the scripted fight uses real attacks and a fixed seed.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const WAIT: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK

# A reinforcement point marker, for the cases that need one.
const POINT: Array = [MapLayout.MarkerKind.REINFORCEMENT_POINT, Vector2i(5, 3)]

# The seed of every case's stream; the fight compares two runs, never golden numbers.
const SEED: int = 20261028

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_nothing_before_turn_one()
	_test_rout()
	_test_rout_ignores_pending_waves()
	_test_defeat_leader()
	_test_defeat_boss()
	_test_seize()
	_test_survive()
	_test_survive_early_end()
	_test_survive_waits_for_waves()
	_test_defend_lost()
	_test_defend_held()
	_test_commander_falls()
	_test_no_player_unit_left()
	_test_loss_beats_win()
	_test_fight_to_a_win()
	_test_fight_to_a_loss()


# Before turn 1 nothing is fought: a map with no enemy doesn't end until its Phase Start.
func _test_nothing_before_turn_one() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.ROUT)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	Objectives.check(world.session)
	_ok("turn 0: no check before the battle opens", not world.session.is_finished)
	world.session.open_battle()
	_ok("turn 0: the Phase Start's step ends it", world.ended_count() == 1)


# Rout: won when the last enemy falls, inside that command's batch; the end is recorded once and
# every later command is rejected.
func _test_rout() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.ROUT)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.add_unit("e2", ENEMY, Vector2i(5, 1))
	world.session.open_battle()
	world.send(DefeatFixture.new(["e1"], "p1"))
	_ok("rout: one enemy left, still fought", not world.session.is_finished)
	var batch: CombatSession.FactBatch = world.send(DefeatFixture.new(["e2"], "p1"))
	var last: CombatFact = batch.facts[batch.facts.size() - 1]
	_ok("rout: won in the last defeat's batch", (
			last.kind == CombatFact.Kind.COMBAT_ENDED
			and last.side == PLAYER
			and last.amount == 1
			and last.key == 0
	), last.to_log_line())
	_ok("rout: the session reads the win", world.session.is_finished and world.session.is_won)
	var after: CombatSession.FactBatch = world.send(EndTurnCommand.new(0))
	_same(
			"rout: later commands rejected",
			after.rejected_reason,
			"the combat on this map has ended"
	)
	_same("rout: COMBAT_ENDED once", world.ended_count(), 1)
	_quiet(world)


# Rout doesn't wait for waves still to come: they are cancelled.
func _test_rout_ignores_pending_waves() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			CombatMapDefinition.Objective.ROUT, 0, [POINT]
	)
	world.set_waves({"0": [{"turn": 3}]})
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	_same("rout waves: a wave is still to come", Objectives.waves_left(world.session, 0), 1)
	world.send(DefeatFixture.new(["e1"], "p1"))
	_ok("rout waves: won anyway", world.session.is_won)
	_quiet(world)


# Defeat the Leader: only the enemy that appeared on the leader slot counts.
func _test_defeat_leader() -> void:
	_marked_enemy_case("leader", CombatMapDefinition.Objective.DEFEAT_LEADER)


# Defeat the Boss: the boss is the enemy placed on the leader slot.
func _test_defeat_boss() -> void:
	_marked_enemy_case("boss", CombatMapDefinition.Objective.DEFEAT_BOSS)


func _marked_enemy_case(label: String, objective: CombatMapDefinition.Objective) -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			objective, 0, [[MapLayout.MarkerKind.LEADER_SLOT, Vector2i(5, 2)]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.add_unit("e2", ENEMY, Vector2i(5, 2))
	world.add_unit("e3", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	world.send(DefeatFixture.new(["e1"], "p1"))
	_ok("%s: another enemy's fall doesn't win" % [label], not world.session.is_finished)
	world.send(DefeatFixture.new(["e2"], "p1"))
	_ok("%s: the marked enemy's fall wins with enemies left" % [label], (
			world.session.is_won and world.state().has_unit("e3")
	))
	_quiet(world)


# Seize: a player unit on the tile wins at the player Phase End, before any enemy phase.
func _test_seize() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			CombatMapDefinition.Objective.SEIZE, 0, [[MapLayout.MarkerKind.SEIZE, Vector2i(2, 0)]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	var walk: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	world.send(UnitTurnCommand.new(0, "p1", WAIT, "", walk))
	_ok("seize: standing there isn't the end of its turn", not world.session.is_finished)
	var start: int = world.log_size()
	world.send(EndTurnCommand.new(0))
	_ok("seize: won at the player Phase End", world.session.is_won)
	_same(
			"seize: no enemy phase after it",
			world.kinds(start),
			"PHASE_END UNIT_TURN_END COMBAT_ENDED"
	)
	_quiet(world)


# Survive N: the end of turn N's enemy phase wins, with no speed bonus, before
# AFTER_ENEMY_PHASE; turn N - 1's doesn't.
func _test_survive() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.SURVIVE, 2)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	var after_enemy_phase: Array[int] = [0]
	world.session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, func(_s: CombatSession) -> void:
		after_enemy_phase[0] += 1
	)
	world.session.open_battle()
	world.send(EndTurnCommand.new(0))
	_ok("survive: turn 1 ends, still fought", (
			not world.session.is_finished and world.state().turn == 2
	))
	world.send(EndTurnCommand.new(0))
	var ended: CombatFact = world.ended()
	_ok("survive: won at turn 2's enemy Phase End", (
			world.session.is_won and ended.amount == 2 and ended.key == 0
	), ended.to_log_line() if ended != null else "no end")
	_same("survive: the after-enemy-phase step ran on turn 1 only", after_enemy_phase[0], 1)
	_quiet(world)


# Survive's early end: no enemy and no point with a wave left. The bonus counts the turns not
# finished, the current one included.
func _test_survive_early_end() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			CombatMapDefinition.Objective.SURVIVE, 5, [POINT]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	world.send(DefeatFixture.new(["e1"], "p1"))
	var ended: CombatFact = world.ended()
	_ok("survive early: a point with no waves is closed, so it ends", (
			world.session.is_won and ended.amount == 1 and ended.key == 5
	), ended.to_log_line() if ended != null else "no end")
	_quiet(world)


# A point with a wave still to come keeps Survive going until the wave's turn has passed.
func _test_survive_waits_for_waves() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			CombatMapDefinition.Objective.SURVIVE, 5, [POINT]
	)
	world.set_waves({"0": [{"turn": 2}]})
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.session.open_battle()
	world.send(DefeatFixture.new(["e1"], "p1"))
	_ok("survive waves: an open point keeps it going", not world.session.is_finished)
	world.send(EndTurnCommand.new(0))
	_ok("survive waves: still going on the wave's turn", (
			not world.session.is_finished and world.state().turn == 2
	))
	world.send(EndTurnCommand.new(0))
	var ended: CombatFact = world.ended()
	_ok("survive waves: ends early once it has passed", (
			world.session.is_won and ended.amount == 3 and ended.key == 3
	), ended.to_log_line() if ended != null else "no end")
	_quiet(world)


# Defend: lost when an enemy ends its turn on the tile (enemies Wait by default).
func _test_defend_lost() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			CombatMapDefinition.Objective.DEFEND, 5, [[MapLayout.MarkerKind.DEFEND, Vector2i(5, 3)]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	var start: int = world.log_size()
	world.send(EndTurnCommand.new(0))
	var ended: CombatFact = world.ended()
	_ok("defend: lost at the enemy Phase End", (
			world.session.is_finished
			and not world.session.is_won
			and ended.side == ENEMY
			and ended.key == 0
	), ended.to_log_line() if ended != null else "no end")
	_ok("defend: no player Phase Start after it", world.kinds(start).ends_with(
			"PHASE_END UNIT_TURN_END COMBAT_ENDED"
	), world.kinds(start))
	_quiet(world)


# A player unit on the defend tile loses nothing, and Defend wins as Survive does.
func _test_defend_held() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(
			CombatMapDefinition.Objective.DEFEND, 1, [[MapLayout.MarkerKind.DEFEND, Vector2i(0, 0)]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	world.send(EndTurnCommand.new(0))
	_ok("defend: held through turn 1 wins", world.session.is_won)
	_quiet(world)


# A commander's fall loses the map at once, with other player units still standing.
func _test_commander_falls() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.ROUT)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(1, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.commander_ids[0] = "p1"
	world.session.open_battle()
	world.send(DefeatFixture.new(["p2"], "e1"))
	_ok("commander: another unit's fall goes on", not world.session.is_finished)
	world.send(DefeatFixture.new(["p1"], "e1"))
	var ended: CombatFact = world.ended()
	_ok("commander: its fall loses the map", (
			world.session.is_finished and ended.side == ENEMY and ended.amount == 1
	))
	_quiet(world)


# Every player unit defeated loses the map, with no commander named.
func _test_no_player_unit_left() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.ROUT)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(1, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.open_battle()
	world.send(DefeatFixture.new(["p1", "p2"], "e1"))
	_ok("no player left: lost", (
			world.session.is_finished and not world.session.is_won and world.ended_count() == 1
	))
	_quiet(world)


# The commander and the last enemy falling in one step: the loss wins out.
func _test_loss_beats_win() -> void:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.ROUT)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(1, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.session.commander_ids[0] = "p1"
	world.session.open_battle()
	world.send(DefeatFixture.new(["e1", "p1"], ""))
	_ok("loss beats win: lost", (
			world.session.is_finished and not world.session.is_won and world.ended_count() == 1
	))
	_quiet(world)


# A scripted fight with real attacks, an axe against a weakened enemy, runs to a win, the same way
# twice.
func _test_fight_to_a_win() -> void:
	var first: ObjectiveWorld = _fight("axe", "sword", 20, 8)
	var second: ObjectiveWorld = _fight("axe", "sword", 20, 8)
	_ok("fight: runs to a win", first.session.is_won, first.kinds())
	_same("fight: ended once", first.ended_count(), 1)
	_ok("fight win: the enemy fell to attacks", (
			not first.state().has_unit("e1") and first.kinds().contains("ATTACK_MADE")
	))
	_ok("fight win: the same seed, the same log", first.lines() == second.lines())
	_quiet(first)


# The same fight turned around, a weakened sword against an axe, runs to a loss.
func _test_fight_to_a_loss() -> void:
	var first: ObjectiveWorld = _fight("sword", "axe", 8, 20)
	var second: ObjectiveWorld = _fight("sword", "axe", 8, 20)
	_ok("fight: runs to a loss", (
			first.session.is_finished and not first.session.is_won
	), first.kinds())
	_same("fight: lost once", first.ended_count(), 1)
	_ok("fight loss: the player unit fell to attacks", (
			not first.state().has_unit("p1") and first.kinds().contains("ATTACK_MADE")
	))
	_ok("fight loss: the same seed, the same log", first.lines() == second.lines())
	_quiet(first)


# p1 attacks e1 every player phase and e1 attacks back every enemy phase, until the map ends or
# 20 turns pass.
func _fight(
		player_weapon: String, enemy_weapon: String, player_hp: int, enemy_hp: int
) -> ObjectiveWorld:
	var world: ObjectiveWorld = ObjectiveWorld.new(CombatMapDefinition.Objective.ROUT)
	world.add_unit("p1", PLAYER, Vector2i(2, 1), player_weapon)
	world.add_unit("e1", ENEMY, Vector2i(3, 1), enemy_weapon)
	world.state().set_hp("p1", player_hp)
	world.state().set_hp("e1", enemy_hp)
	world.session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(s: CombatSession) -> Command:
		if not s.state.has_unit("p1") or s.state.unit("e1").has_acted:
			return null
		return UnitTurnCommand.new(-1, "e1", ATTACK, "p1")
	)
	world.session.open_battle()
	for turn: int in 20:
		if world.session.is_finished:
			break
		world.send(UnitTurnCommand.new(0, "p1", ATTACK, "e1"))
		world.send(EndTurnCommand.new(0))
	return world


# Untyped: compares strings, ints and arrays alike.
func _same(case_name: String, actual: Variant, expected: Variant) -> void:
	var is_same: bool = actual == expected
	_ok(case_name, is_same, "got %s" % [actual])


func _quiet(world: ObjectiveWorld) -> void:
	var diagnostics: PackedStringArray = world.session.engine.diagnostics
	_ok("diagnostics: none", diagnostics.is_empty(), str(diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


# One map's session on a 6 × 4 plain map with the given markers, its setup naming the objective,
# and Objectives registered as the encounter does.
class ObjectiveWorld:
	extends RefCounted

	# Weapon presets: damage, AtkX, profile, Hit, weight, from game-vision.md's Simple weapon
	# table; every one has range 1.
	const WEAPONS: Dictionary[String, Array] = {
		"sword": [5, 1, WeaponTriangle.Profile.NIMBLE, 80, 8],
		"axe": [10, 1, WeaponTriangle.Profile.POWER, 65, 15],
	}

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null

	# [param marks]: [MapLayout.MarkerKind, Vector2i] pairs.
	func _init(
			objective: CombatMapDefinition.Objective, survive_turns: int = 0, marks: Array = []
	) -> void:
		var layout: MapLayout = MapLayout.new()
		layout.map_id = "objectives"
		var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
				MapLoader.load_terrain("plain")
		)
		for y: int in 4:
			for x: int in 6:
				layout.set_terrain(Vector2i(x, y), plain)
		# Untyped: each mark is a two-element array literal.
		for mark: Variant in marks:
			var pair: Array = mark
			var kind: MapLayout.MarkerKind = pair[0]
			var tile: Vector2i = pair[1]
			layout.add_marker(kind, tile)
		layout.index_markers()
		var definition: CombatMapDefinition = CombatMapDefinition.new()
		definition.id = "objectives"
		definition.objective = objective
		definition.survive_turns = survive_turns
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(SEED))
		session = CombatSession.new(0, PackedInt32Array([0]), MapGrid.new(layout), rolls, ids)
		session.engine.verify = true
		session.setup = CombatEncounter.EncounterSetup.new()
		session.setup.map = definition
		session.setup.layout = layout
		Objectives.register(session)

	func state() -> CombatState:
		return session.state

	# Sets the setup's reinforcement waves (Objectives.WAVES_KEY).
	func set_waves(waves: Dictionary) -> void:
		session.setup.shared[Objectives.WAVES_KEY] = waves

	# Places a unit with HP 20, Stance 2, 5 movement, Might 3, Speed 5, Constitution 20, holding
	# [param weapon] (a WEAPONS preset) when given. Player units are seat 0's.
	func add_unit(
			id: String, side: CombatFact.CombatSide, tile: Vector2i, weapon: String = ""
	) -> void:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = 0 if side == CombatFact.CombatSide.PLAYER else -1
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

	# Submits [param command] and resolves it; returns its batch.
	func send(command: Command) -> CombatSession.FactBatch:
		session.submit(command)
		return session.resolve_next()

	func log_size() -> int:
		return session.engine.fact_log.size()

	func lines() -> Array[String]:
		var found: Array[String] = []
		for fact: CombatFact in session.engine.fact_log:
			found.append(fact.to_log_line())
		return found

	func kinds(start: int = 0) -> String:
		var names: PackedStringArray = []
		for i: int in range(start, session.engine.fact_log.size()):
			names.append(CombatFact.Kind.find_key(session.engine.fact_log[i].kind) as String)
		return " ".join(names)

	# The COMBAT_ENDED fact; null when none was recorded.
	func ended() -> CombatFact:
		for fact: CombatFact in session.engine.fact_log:
			if fact.kind == CombatFact.Kind.COMBAT_ENDED:
				return fact
		return null

	func ended_count() -> int:
		var count: int = 0
		for fact: CombatFact in session.engine.fact_log:
			if fact.kind == CombatFact.Kind.COMBAT_ENDED:
				count += 1
		return count

	func _weapon(weapon_id: String, preset: String) -> CombatState.WeaponStats:
		var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
		stats.id = weapon_id
		stats.label = preset.capitalize()
		# Columns: damage, AtkX, profile, Hit, weight.
		var columns: Array = WEAPONS[preset]
		stats.damage = columns[0]
		stats.atk_x = columns[1]
		stats.profile = columns[2]
		stats.range_min = 1
		stats.range_max = 1
		stats.hit = columns[3]
		stats.weight = columns[4]
		return stats


# Defeats each unit in order through CombatState.defeat, by [member by_id]; a test command, so a
# case's defeats need no roll.
class DefeatFixture:
	extends Command

	var unit_ids: PackedStringArray = []
	var by_id: String = ""

	func _init(defeated: Array[String], defeated_by: String) -> void:
		unit_ids = PackedStringArray(defeated)
		by_id = defeated_by

	func get_label() -> String:
		return "defeat"

	func resolve(session: CombatSession) -> void:
		for unit_id: String in unit_ids:
			session.state.defeat(session.engine, unit_id, by_id)
