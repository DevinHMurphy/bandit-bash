# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_loss_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Co-op loss cases for tests/sessions/run_all.gd, in 2-, 3- and 4-seat encounters: a fallen
## commander's map plays on; an empty map freezes once the phase in progress finishes (emptied in
## the player phase or the enemy phase), runs no phase and keeps its turn; a unit sent there lands
## at once and the map resumes, its batch sent on [signal CombatSession.batch_resolved] and
## followed by a mirror; a Defend loss ends only that map, also on an emptied map, where a Survive
## win reached as the phase finishes stands; each case of
## [method CombatEncounter.is_run_lost]; and solo's commander and empty-map losses unchanged.
##
## Each map is its seat's fixture map with a Drengr at (0, 3) and a Brute at (3, 2), turn 1 open.
## Defeats come from fixture commands, so no case depends on a roll.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# Each map's own player unit and enemy, and where a sent unit is aimed.
const PLAYER_TILE: Vector2i = Vector2i(0, 3)
const ENEMY_TILE: Vector2i = Vector2i(3, 2)
const ARRIVAL_TILE: Vector2i = Vector2i(1, 3)

# The fixture map's size, for filling every tile.
const MAP_SIZE: Vector2i = Vector2i(5, 4)

# The co-op seat counts every core case runs in.
const SEAT_COUNTS: Array[int] = [2, 3, 4]


func run() -> void:
	for seat_count: int in SEAT_COUNTS:
		_run(_test_commander_plays_on.bind(seat_count))
		_run(_test_freeze_after_player_phase.bind(seat_count))
		_run(_test_freeze_after_enemy_phase.bind(seat_count))
		_run(_test_arrivals_resume.bind(seat_count))
		_run(_test_defend_loss_ends_one_map.bind(seat_count))
	_run(_test_emptied_map_still_loses_defend)
	_run(_test_emptied_map_still_wins_survive)
	_run(_test_resume_batch_reaches_mirror)
	_run(_test_run_waits_for_a_teammate)
	_run(_test_run_lost_without_help)
	_run(_test_sent_unit_counts_once)
	_run(_test_units_in_transit)
	_run(_test_solo_unchanged)


# A commander's fall loses no co-op map: its other units play on and nothing freezes.
func _test_commander_plays_on(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var session: CombatSession = battle.encounter.get_session(last)
	var other: String = battle.add_unit(last, "Archer", PLAYER, last, Vector2i(2, 3))
	var commander: String = _player_of(session)
	session.commander_ids[last] = commander
	session.state.commander_ids = session.commander_ids.duplicate()
	_open(battle)
	battle.encounter.submit(FellFixture.new(last, [commander]), last)
	battle.encounter.resolve_queued()
	_check("commander %d seats: its fall loses no map" % [seat_count], (
			not session.is_finished
			and session.state.has_unit(other)
			and not battle.encounter.is_frozen(last)
			and _ended_count(session) == 0
	), _kinds_of(session.engine.fact_log))
	_check("commander %d seats: its seat plays on" % [seat_count], (
			_resolve(battle, UnitTurnCommand.new(last, other, UnitTurnCommand.Action.WAIT), last)
			.rejected_reason.is_empty()
	))
	return true


# The last unit falling in the player phase: the turn finishes at once (enemy phase and the
# darkness's hook included), then the map holds at the next player Phase Start with its turn kept.
func _test_freeze_after_player_phase(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var session: CombatSession = battle.encounter.get_session(last)
	var darkness: Array[int] = _count_after_enemy_phase(session)
	_open(battle)
	var start: int = session.engine.fact_log.size()
	battle.encounter.submit(FellFixture.new(last, [_player_of(session)]), last)
	battle.encounter.resolve_queued()
	var kinds: String = _kinds_of(session.engine.fact_log.slice(start))
	_check("freeze %d seats: the player phase finishes, then the enemy phase" % [seat_count], (
			kinds.ends_with(
					"DEFEATED PHASE_END BLOCK_STANCE_REFRESHED PHASE_START UNIT_TURN_START"
					+ " UNIT_WAITED PHASE_END UNIT_TURN_END"
			)
			and darkness[0] == 1
	), kinds)
	_check("freeze %d seats: held at the next player Phase Start, turn kept" % [seat_count], (
			battle.encounter.is_frozen(last)
			and not session.is_finished
			and session.state.turn == 1
			and session.state.phase_side == ENEMY
	), "turn %d" % [session.state.turn])
	_check_inert(battle, last, darkness, "freeze %d seats" % [seat_count])
	_check("freeze %d seats: the other maps go on" % [seat_count], _others_go_on(battle, last))
	return true


# The last unit falling to an enemy in the enemy phase: the enemy phase and the darkness's hook
# finish, then the map holds.
func _test_freeze_after_enemy_phase(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var session: CombatSession = battle.encounter.get_session(last)
	var darkness: Array[int] = _count_after_enemy_phase(session)
	_enemy_fells(session, _enemy_of(session), _player_of(session))
	_open(battle)
	var start: int = session.engine.fact_log.size()
	_resolve(battle, EndTurnCommand.new(last), last)
	var kinds: String = _kinds_of(session.engine.fact_log.slice(start))
	_check("enemy phase %d seats: it finishes, then the map holds" % [seat_count], (
			kinds.ends_with("UNIT_TURN_START DEFEATED DEFEATED_AN_ENEMY PHASE_END UNIT_TURN_END")
			and darkness[0] == 1
			and battle.encounter.is_frozen(last)
			and session.state.turn == 1
	), kinds)
	_check_inert(battle, last, darkness, "enemy phase %d seats" % [seat_count])
	_check("enemy phase %d seats: the other maps go on" % [seat_count], (
			_others_go_on(battle, last)
	))
	return true


# A unit sent to a frozen map lands at its held Phase Start at once, and the map goes on at the
# next turn; the batch goes out on batch_resolved like any other.
func _test_arrivals_resume(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var session: CombatSession = battle.encounter.get_session(last)
	var sender: CombatSession = battle.encounter.get_session(0)
	var sent: String = _player_of(sender)
	_open(battle)
	_resolve(battle, FellFixture.new(last, [_player_of(session)]), last)
	_resolve(battle, EndMapFixture.new(), 0)
	var batches: Array[CombatSession.FactBatch] = []
	session.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)
	)
	var reason: String = battle.encounter.send_unit(sent, 0, last, ARRIVAL_TILE)
	var kinds: String = "" if batches.is_empty() else _kinds_of(batches[0].facts)
	_check("resume %d seats: the unit lands at the held Phase Start" % [seat_count], (
			reason.is_empty()
			and session.state.has_unit(sent)
			and battle.encounter.units_in_transit().is_empty()
			and kinds.begins_with("UNIT_SPAWNED BLOCK_STANCE_REFRESHED")
	), "%s; %s" % [reason, kinds])
	_check("resume %d seats: the map goes on at the next turn" % [seat_count], (
			not battle.encounter.is_frozen(last)
			and session.state.turn == 2
			and session.state.phase_side == PLAYER
			and _first_of(batches[0].facts, CombatFact.Kind.PHASE_START).amount == 2
	) if batches.size() == 1 else false, "%d batches" % [batches.size()])
	_check("resume %d seats: one batch, sent as every batch is" % [seat_count], (
			batches.size() == 1
			and batches[0].label == "frozen map resumed"
			and batches[0].session_id == last
			and batches[0].spawned.size() == 1
			and not batches[0].is_rejected()
	))
	_check("resume %d seats: the unit acts there" % [seat_count], (
			_resolve(battle, UnitTurnCommand.new(0, sent, UnitTurnCommand.Action.WAIT), last)
			.rejected_reason.is_empty()
	))
	_check("resume %d seats: no diagnostics" % [seat_count], session.engine.diagnostics.is_empty())
	return true


# A failed Defend tile ends only that map, as in solo; the rest play on.
func _test_defend_loss_ends_one_map(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count, true)
	var session: CombatSession = battle.encounter.get_session(0)
	session.state.move_unit(_enemy_of(session), _defend_tile())
	_open(battle)
	_resolve(battle, EndTurnCommand.new(0), 0)
	_check("defend %d seats: the taken tile loses that map" % [seat_count], (
			session.is_finished and not session.is_won
	))
	_check("defend %d seats: only that map" % [seat_count], (
			_others_go_on(battle, 0)
			and not battle.encounter.is_finished()
			and not battle.encounter.is_run_lost()
	))
	return true


# An emptied map's finishing enemy phase can still take a Defend tile: lost, not frozen.
func _test_emptied_map_still_loses_defend() -> bool:
	var battle: Battle = _coop(2, true)
	var session: CombatSession = battle.encounter.get_session(1)
	session.state.move_unit(_enemy_of(session), _defend_tile())
	_open(battle)
	_resolve(battle, FellFixture.new(1, [_player_of(session)]), 1)
	_check("defend emptied: lost at the enemy Phase End, not frozen", (
			session.is_finished
			and not session.is_won
			and not battle.encounter.is_frozen(1)
	))
	return true


# A win the finishing phase reaches on an emptied map stands: Survive's last enemy Phase End.
func _test_emptied_map_still_wins_survive() -> bool:
	var battle: Battle = _coop(2)
	battle.encounter.setup.map.objective = CombatMapDefinition.Objective.SURVIVE
	battle.encounter.setup.map.survive_turns = 1
	var session: CombatSession = battle.encounter.get_session(1)
	_open(battle)
	_resolve(battle, FellFixture.new(1, [_player_of(session)]), 1)
	_check("survive emptied: won at turn 1's enemy Phase End, not frozen", (
			session.is_won and not battle.encounter.is_frozen(1)
	))
	return true


# A mirror loaded at battle start derives the freeze from the batches and follows the resume batch
# hash for hash.
func _test_resume_batch_reaches_mirror() -> bool:
	var battle: Battle = _coop(2)
	var session: CombatSession = battle.encounter.get_session(1)
	var mirror_battle: Battle = _coop(2)
	var mirror: CombatSession = mirror_battle.encounter.get_session(1)
	var loaded: Error = mirror.load_snapshot(
			WireCases.Kit.through_json(session.snapshot()) as Dictionary
	)
	var batches: Array[CombatSession.FactBatch] = []
	session.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)
	)
	var sent: String = _player_of(battle.encounter.get_session(0))
	_open(battle)
	_resolve(battle, FellFixture.new(1, [_player_of(session)]), 1)
	_resolve(battle, EndMapFixture.new(), 0)
	var results: Array[Error] = []
	for batch: CombatSession.FactBatch in batches:
		results.append(mirror.apply_batch(WireCases.Kit.batch_through_json(batch)))
	_check("mirror: frozen as the host is, from the facts alone", (
			loaded == OK
			and results.count(OK) == results.size()
			and mirror_battle.encounter.is_frozen(1)
			and mirror.state_hash() == session.state_hash()
	), "%s, %s" % [error_string(loaded), results])
	var before: int = batches.size()
	battle.encounter.send_unit(sent, 0, 1, ARRIVAL_TILE)
	var resumed: Error = (
			mirror.apply_batch(WireCases.Kit.batch_through_json(batches[before]))
			if batches.size() == before + 1 else FAILED
	)
	_check("mirror: follows the resume batch and goes on", (
			resumed == OK
			and not mirror_battle.encounter.is_frozen(1)
			and mirror.state.has_unit(sent)
			and mirror.state_hash() == session.state_hash()
	), error_string(resumed))
	return true


# A teammate still fighting may win and send, so the run waits; a won teammate with a unit to send
# is help too.
func _test_run_waits_for_a_teammate() -> bool:
	var battle: Battle = _coop(2)
	_open(battle)
	_resolve(battle, FellFixture.new(1, [_player_of(battle.encounter.get_session(1))]), 1)
	_check("run: a teammate still fighting keeps it going", (
			battle.encounter.is_frozen(1) and not battle.encounter.is_run_lost()
	))
	_resolve(battle, EndMapFixture.new(), 0)
	_check("run: a won teammate with a unit to send keeps it going", (
			battle.encounter.get_session(0).is_won and not battle.encounter.is_run_lost()
	))
	return true


# A frozen map with no teammate fighting or able to send: lost. A lost map's units never help.
func _test_run_lost_without_help() -> bool:
	var battle: Battle = _coop(3)
	_open(battle)
	_resolve(battle, EndMapFixture.new(ENEMY), 0)
	_resolve(battle, FellFixture.new(2, [_player_of(battle.encounter.get_session(2))]), 2)
	_check("run: a teammate on map 1 still fighting", not battle.encounter.is_run_lost())
	_resolve(battle, EndMapFixture.new(ENEMY), 1)
	_check("run: lost once only a lost map and a frozen one are left", (
			battle.encounter.is_frozen(2) and battle.encounter.is_run_lost()
	))
	_check("run: the encounter ends nothing itself", (
			not battle.encounter.is_finished() and not battle.encounter.get_session(2).is_finished
	))
	return true


# A won map's unit counts once: after it is sent and falls on the frozen map it went to, the won
# map has nothing left to send.
func _test_sent_unit_counts_once() -> bool:
	var battle: Battle = _coop(3)
	var winner: CombatSession = battle.encounter.get_session(0)
	var sent: String = _player_of(winner)
	_open(battle)
	_resolve(battle, FellFixture.new(1, [_player_of(battle.encounter.get_session(1))]), 1)
	_resolve(battle, FellFixture.new(2, [_player_of(battle.encounter.get_session(2))]), 2)
	_resolve(battle, EndMapFixture.new(), 0)
	_check("run: two frozen maps and a winner with a unit", not battle.encounter.is_run_lost())
	battle.encounter.send_unit(sent, 0, 1, ARRIVAL_TILE)
	_check("run: the map it lands on is fought again", (
			not battle.encounter.is_frozen(1) and not battle.encounter.is_run_lost()
	))
	_resolve(battle, FellFixture.new(0, [sent]), 1)
	_check("run: lost once it falls there, its record on the won map no help", (
			winner.state.has_unit(sent)
			and battle.encounter.is_frozen(1)
			and battle.encounter.is_frozen(2)
			and battle.encounter.is_run_lost()
	))
	return true


# A unit on its way to a frozen map (no free tile there, so it waits): the run waits for it, and a
# frozen map it is on its way to helps another frozen one.
func _test_units_in_transit() -> bool:
	var battle: Battle = _coop(3)
	var full: CombatSession = battle.encounter.get_session(1)
	var sent: String = _player_of(battle.encounter.get_session(0))
	_open(battle)
	_resolve(battle, FellFixture.new(1, [_player_of(full)]), 1)
	_resolve(battle, FellFixture.new(2, [_player_of(battle.encounter.get_session(2))]), 2)
	_resolve(battle, EndMapFixture.new(), 0)
	_fill_map(battle, 1)
	var reason: String = battle.encounter.send_unit(sent, 0, 1, ARRIVAL_TILE)
	_check("transit: no free tile, so it waits and the map stays frozen", (
			reason.is_empty()
			and battle.encounter.units_in_transit() == PackedStringArray([sent])
			and battle.encounter.is_frozen(1)
	), reason)
	_check("transit: the run waits for it", not battle.encounter.is_run_lost())
	return true


# Solo: a commander's fall and an empty map still lose; nothing freezes or loses the run.
func _test_solo_unchanged() -> bool:
	var commander_battle: Battle = _coop(1)
	var session: CombatSession = commander_battle.encounter.get_session(0)
	var commander: String = _player_of(session)
	commander_battle.add_unit(0, "Archer", PLAYER, 0, Vector2i(2, 3))
	session.commander_ids[0] = commander
	_open(commander_battle)
	_resolve(commander_battle, FellFixture.new(0, [commander]), 0)
	_check("solo: a commander's fall loses the map", session.is_finished and not session.is_won)

	var empty_battle: Battle = _coop(1)
	var empty: CombatSession = empty_battle.encounter.get_session(0)
	_open(empty_battle)
	_resolve(empty_battle, FellFixture.new(0, [_player_of(empty)]), 0)
	_check("solo: an empty map loses at once, never frozen", (
			empty.is_finished
			and not empty.is_won
			and empty.state.phase_side == PLAYER
			and not empty_battle.encounter.is_frozen(0)
			and not empty_battle.encounter.is_run_lost()
	))
	return true


# A frozen map takes no command, runs no phase and keeps its turn and fact log.
func _check_inert(battle: Battle, session_id: int, darkness: Array[int], label: String) -> void:
	var session: CombatSession = battle.encounter.get_session(session_id)
	var facts: int = session.engine.fact_log.size()
	var batch: CombatSession.FactBatch = _resolve(
			battle, EndTurnCommand.new(session_id), session_id
	)
	_check("%s: no phase runs while frozen" % [label], (
			batch.is_rejected()
			and session.engine.fact_log.size() == facts
			and session.state.turn == 1
			and darkness[0] == 1
			and battle.encounter.is_frozen(session_id)
	), batch.rejected_reason)


# Whether every map but session_id is still being fought, unfrozen, past turn 1 when ended.
func _others_go_on(battle: Battle, session_id: int) -> bool:
	for other: CombatSession in battle.encounter.get_sessions():
		if other.session_id == session_id:
			continue
		if other.is_finished or battle.encounter.is_frozen(other.session_id):
			return false
		var seat: int = battle.encounter.seats[other.session_id]
		var ended: CombatSession.FactBatch = _resolve(
				battle, EndTurnCommand.new(seat), other.session_id
		)
		if ended.is_rejected() or other.state.turn != 2:
			return false
	return true


# A battle of seat_count seats on the fixture map, each map with its seat's Drengr and a Brute.
# With defend, the objective is Defend for 5 turns with a defend tile at _defend_tile().
func _coop(seat_count: int, defend: bool = false) -> Battle:
	var seats: PackedInt32Array = []
	for seat: int in seat_count:
		seats.append(seat)
	var battle: Battle = Battle.new(seats)
	battle.set_up()
	if defend:
		var setup: CombatEncounter.EncounterSetup = battle.encounter.setup
		setup.map.objective = CombatMapDefinition.Objective.DEFEND
		setup.map.survive_turns = 5
		setup.layout.add_marker(MapLayout.MarkerKind.DEFEND, _defend_tile())
		setup.layout.index_markers()
	battle.open()
	for seat: int in seat_count:
		battle.add_unit(seat, "Drengr", PLAYER, seat, PLAYER_TILE)
		battle.add_unit(seat, "Brute", ENEMY, -1, ENEMY_TILE)
	return battle


# Opens turn 1 on every map.
func _open(battle: Battle) -> void:
	for session: CombatSession in battle.encounter.get_sessions():
		session.open_battle()


# Submits command to session_id and resolves the queue; returns that command's batch.
func _resolve(battle: Battle, command: Command, session_id: int) -> CombatSession.FactBatch:
	battle.encounter.submit(command, session_id)
	var batches: Array[CombatSession.FactBatch] = battle.encounter.resolve_queued()
	return batches[batches.size() - 1]


# A one-element counter of session's AFTER_ENEMY_PHASE runs, where the darkness phase runs.
func _count_after_enemy_phase(session: CombatSession) -> Array[int]:
	var runs: Array[int] = [0]
	session.hooks.add(CombatHooks.Hook.AFTER_ENEMY_PHASE, func(_on: CombatSession) -> void:
		runs[0] += 1
	)
	return runs


# The enemy enemy_id defeats target_id at its first enemy turn, then acts no more.
func _enemy_fells(session: CombatSession, enemy_id: String, target_id: String) -> void:
	var done: Array[bool] = [false]
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, func(on: CombatSession) -> Command:
		if done[0] or not on.state.has_unit(target_id):
			return null
		done[0] = true
		return EnemyFellFixture.new(enemy_id, target_id)
	)


# Puts an enemy on every free tile of session_id's map, so a sent unit has nowhere to land.
func _fill_map(battle: Battle, session_id: int) -> void:
	var state: CombatState = battle.encounter.get_session(session_id).state
	for y: int in MAP_SIZE.y:
		for x: int in MAP_SIZE.x:
			var tile: Vector2i = Vector2i(x, y)
			if state.occupant_at(tile).is_empty() and state.can_stand(
					tile, CombatGrid.MovementType.DEFAULT
			):
				battle.add_unit(session_id, "Brute", ENEMY, -1, tile)


func _player_of(session: CombatSession) -> String:
	return session.state.units_of(PLAYER)[0]


func _enemy_of(session: CombatSession) -> String:
	return session.state.units_of(ENEMY)[0]


func _ended_count(session: CombatSession) -> int:
	var count: int = 0
	for fact: CombatFact in session.engine.fact_log:
		if fact.kind == CombatFact.Kind.COMBAT_ENDED:
			count += 1
	return count


static func _defend_tile() -> Vector2i:
	return Vector2i(4, 0)


# Defeats each unit through CombatState.defeat for seat [member seat]: a step that empties a map.
class FellFixture:
	extends Command

	var unit_ids: PackedStringArray = []

	func _init(sender: int, defeated: Array[String]) -> void:
		seat = sender
		unit_ids = PackedStringArray(defeated)

	func get_label() -> String:
		return "fell"

	func resolve(session: CombatSession) -> void:
		for unit_id: String in unit_ids:
			session.state.defeat(session.engine, unit_id, "")


# An enemy's turn that defeats its target outright and ends the enemy's turn.
class EnemyFellFixture:
	extends Command

	var target_id: String = ""

	func _init(enemy_id: String, defeated_id: String) -> void:
		actor_id = enemy_id
		target_id = defeated_id

	func get_label() -> String:
		return "enemy fells"

	func resolve(session: CombatSession) -> void:
		session.state.unit(actor_id).has_acted = true
		session.state.defeat(session.engine, target_id, actor_id)
