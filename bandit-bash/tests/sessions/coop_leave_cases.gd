# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_leave_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## A forfeiting seat's units leaving a teammate's map in play ([method CombatEncounter.forfeit]),
## for tests/sessions/run_all.gd: a landed send and a swap's visitor leave with their effects and
## their owner's that followed them, a unit on its way leaves unseen, and the seat's cross-map army
## effects leave every other map; the teammate's phase stops waiting (the forfeiter's End Turn
## done or not, the teammate's done or not, and the opening swap window); a map left empty
## freezes and the run is lost when nothing can help, a unit left on an ended map counting for
## nothing; a snapshot round trip; a mirror at 2 and 4 seats matching the host hash for hash after
## every Start, End Turn and the leave (BUG-043 too); solo unchanged.
##
## Each map is its seat's fixture map with a Drengr at (0, 3) and a Brute at (3, 2). A visitor is
## seat 1's Drengr at (2, 3) on seat 0's map, placed before the battle opens.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

const PLAYER_TILE: Vector2i = Vector2i(0, 3)
const ENEMY_TILE: Vector2i = Vector2i(3, 2)
const VISITOR_TILE: Vector2i = Vector2i(2, 3)

# The seat that forfeits in every case, and the teammate whose map it stands on.
const LEAVER: int = 1
const TEAMMATE: int = 0

# The cases' own effect definitions, by id, which no catalog holds: snapshots name them by id and
# loads find them here.
var _definitions: Dictionary[String, EffectDefinition] = {}


func run() -> void:
	for seat_count: int in [2, 4]:
		_run(_test_landed_send.bind(seat_count))
		_run(_test_visitor.bind(seat_count))
		_run(_test_mirror.bind(seat_count))
	_run(_test_on_its_way)
	_run(_test_phase_timing)
	_run(_test_opening_window)
	_run(_test_emptied_map_freezes)
	_run(_test_ended_map_counts_for_nothing)
	_run(_test_snapshot_round_trip)
	_run(_test_solo_unchanged)


# A unit the leaver sent, landed on the teammate's map, leaves it at the forfeit: one UNIT_LEFT for
# the seat, one for the unit, and no current record anywhere.
func _test_landed_send(seat_count: int) -> bool:
	var label: String = "leave a landed send, %d seats" % [seat_count]
	var battle: Battle = _coop(seat_count, false)
	_open(battle)
	var target: CombatSession = battle.encounter.get_session(TEAMMATE)
	var sent: String = _land_send(battle, LEAVER, TEAMMATE)
	var landed: bool = target.state.has_unit(sent)
	var first: int = battle.encounter.fact_log.size()
	var went: bool = battle.encounter.forfeit(LEAVER)
	var facts: Array[CombatFact] = battle.encounter.fact_log.slice(first)
	_check("%s: it leaves the map with no current record" % [label], (
			landed and went
			and target.state.unit(sent) == null
			and battle.encounter.session_of_unit(sent) == null
			and PhaseRunner.seats_with_units(target) == PackedInt32Array([TEAMMATE])
			and battle.encounter.senders_of(TEAMMATE) == PackedInt32Array([LEAVER])
	))
	_check("%s: the seat's fact first, then its unit's" % [label], (
			facts.size() == 2
			and facts[0].kind == CombatFact.Kind.UNIT_LEFT and facts[0].actor_id.is_empty()
			and facts[0].amount == LEAVER and facts[0].session_id == LEAVER
			and facts[1].kind == CombatFact.Kind.UNIT_LEFT and facts[1].actor_id == sent
			and facts[1].session_id == TEAMMATE and facts[1].tile != CombatFact.NO_TILE
	), _kinds_of(facts))
	_check("%s: a second forfeit is refused" % [label], (
			not battle.encounter.forfeit(LEAVER)
			and battle.encounter.forfeit_problem(LEAVER) == "seat 1 has already left the battle"
	))
	_check("%s: no diagnostics" % [label], _diagnostics(battle).is_empty(), _diagnostics(battle))
	return true


# A swap's visitor leaves with its own effects and its owner's that followed it; its owner's map
# keeps them, and the seat's cross-map effect leaves every other map.
func _test_visitor(seat_count: int) -> bool:
	var label: String = "leave a visitor, %d seats" % [seat_count]
	var battle: Battle = _coop(seat_count, true)
	var own: CombatSession = battle.encounter.get_session(TEAMMATE)
	var home: CombatSession = battle.encounter.get_session(LEAVER)
	var visitor: String = _units_of(own, LEAVER)[0]
	var cross: EffectInstance = _add_cross_map(battle)
	_open(battle)
	var followed: String = _owner_effect_id(home)
	var held: String = _held_effect_id(own, visitor)
	var before: bool = (
			own.engine.get_instance(followed) != null and own.engine.get_instance(held) != null
	)
	battle.encounter.forfeit(LEAVER)
	var cross_gone: bool = true
	for session: CombatSession in battle.encounter.get_sessions():
		var has_cross: bool = session.engine.get_instance(cross.instance_id) != null
		cross_gone = cross_gone and has_cross == (session == home)
	_check("%s: it leaves, its owner's map keeping their effects" % [label], (
			before
			and own.state.unit(visitor) == null
			and own.engine.get_instance(followed) == null
			and own.engine.get_instance(held) == null
			and home.engine.get_instance(followed) != null
			and battle.encounter.session_of_unit(visitor) == null
	))
	_check("%s: its cross-map effect leaves every other map" % [label], (
			cross_gone and battle.encounter.get_cross_map_instances().is_empty()
	))
	return true


# A unit on its way when its seat forfeits leaves with it: no UNIT_LEFT names it, nothing lands.
func _test_on_its_way() -> bool:
	var battle: Battle = _coop(3, false)
	_open(battle)
	var winner: CombatSession = battle.encounter.get_session(LEAVER)
	_resolve(battle, EndMapFixture.new(), LEAVER)
	var sent: String = _units_of(winner, LEAVER)[0]
	battle.encounter.send_unit(sent, LEAVER, TEAMMATE, CombatFact.NO_TILE)
	var first: int = battle.encounter.fact_log.size()
	var was_on_way: bool = battle.encounter.units_in_transit().has(sent)
	battle.encounter.forfeit(LEAVER)
	var facts: Array[CombatFact] = battle.encounter.fact_log.slice(first)
	_resolve(battle, EndTurnCommand.new(TEAMMATE), TEAMMATE)
	_check("leave on its way: it leaves unseen and never lands", (
			was_on_way
			and battle.encounter.units_in_transit().is_empty()
			and facts.size() == 1 and facts[0].actor_id.is_empty()
			and battle.encounter.get_session(TEAMMATE).state.unit(sent) == null
	), _kinds_of(facts))
	return true


# The teammate's player phase on a shared map once the leaver's visitor leaves: after the leaver
# ended its turn, the teammate still ends; mid the leaver's own turn with the teammate ended, the
# rest of the turn runs at once; with neither ended, nothing runs.
func _test_phase_timing() -> bool:
	for case_index: int in 3:
		var label: String = [
			"leave after its own End Turn",
			"leave mid its own turn, the teammate ended",
			"leave before either ended",
		][case_index]
		var battle: Battle = _coop(2, true)
		_open(battle)
		var map: CombatSession = battle.encounter.get_session(TEAMMATE)
		var visitor: String = _units_of(map, LEAVER)[0]
		if case_index == 0:
			_resolve(battle, EndTurnCommand.new(LEAVER), TEAMMATE)
		elif case_index == 1:
			_resolve(battle, UnitTurnCommand.new(LEAVER, visitor, UnitTurnCommand.Action.WAIT), 0)
			_resolve(battle, EndTurnCommand.new(TEAMMATE), TEAMMATE)
		var turn: int = map.state.turn
		var batches: Array[CombatSession.FactBatch] = _batches_of(map, func() -> void:
			battle.encounter.forfeit(LEAVER)
		)
		if case_index == 1:
			_check("%s: the turn runs on at once, a save point" % [label], (
					map.state.turn == turn + 1
					and map.state.phase_side == PLAYER
					and batches.size() == 1
					and CombatEncounter.is_save_point(batches[0])
			), "%d batches" % [batches.size()])
			continue
		var still: bool = (
				map.state.turn == turn and batches.is_empty()
				and PhaseRunner.seats_to_end(map) == PackedInt32Array([TEAMMATE])
				and not map.state.ended_seats.has(LEAVER)
		)
		_resolve(battle, EndTurnCommand.new(TEAMMATE), TEAMMATE)
		_check("%s: the teammate's End Turn alone ends the phase" % [label], (
				still and map.state.turn == turn + 1
		), "turn %d" % [map.state.turn])
	return true


# The opening swap window waiting for the leaver's Start closes into turn 1 at the leave, and the
# map's snapshot loads (its window agrees with its seats to start).
func _test_opening_window() -> bool:
	var battle: Battle = _coop(2, true)
	_open(battle, PackedInt32Array([TEAMMATE, LEAVER]))
	var map: CombatSession = battle.encounter.get_session(TEAMMATE)
	_resolve(battle, StartCommand.new(TEAMMATE), TEAMMATE)
	var waiting: bool = (
			map.state.map.opening_swap_open
			and map.state.seats_to_start == PackedInt32Array([LEAVER])
	)
	battle.encounter.forfeit(LEAVER)
	var copy: Battle = _coop(2, true)
	var loaded: Error = copy.encounter.load_snapshot(
			WireCases.Kit.through_json(battle.encounter.snapshot(_by_id)) as Dictionary,
			_definition_of,
	)
	_check("leave in the opening window: turn 1 starts, and the battle saves", (
			waiting
			and not map.state.map.opening_swap_open
			and map.state.seats_to_start.is_empty()
			and map.state.turn == 1 and map.state.phase_side == PLAYER
			and loaded == OK
	), error_string(loaded))
	return true


# A map whose own units fell, held by the leaver's visitor, runs the rest of its turn at the leave
# and freezes; with no map left to help, the run is lost, and with a map still fought it isn't.
func _test_emptied_map_freezes() -> bool:
	for seat_count: int in [2, 3]:
		var label: String = "leave empties a map, %d seats" % [seat_count]
		var battle: Battle = _coop(seat_count, true)
		_open(battle)
		var map: CombatSession = battle.encounter.get_session(TEAMMATE)
		_resolve(battle, FallFixture.new(TEAMMATE, _units_of(map, TEAMMATE)), TEAMMATE)
		var held_by_visitor: bool = (
				not battle.encounter.is_frozen(TEAMMATE) and map.state.phase_side == PLAYER
		)
		var turn: int = map.state.turn
		battle.encounter.forfeit(LEAVER)
		_check("%s: it runs its turn and freezes" % [label], (
				held_by_visitor
				and battle.encounter.is_frozen(TEAMMATE)
				and map.state.turn == turn
				and map.state.units_of(PLAYER).is_empty()
		))
		_check("%s: the run is lost only with no map left to help" % [label], (
				battle.encounter.is_run_lost() == (seat_count == 2)
		))
	return true


# The leaver's unit standing on a teammate's map that has ended stays there as it stood, with no
# fact, and no longer counts as help for a frozen map.
func _test_ended_map_counts_for_nothing() -> bool:
	var battle: Battle = _coop(3, false)
	_open(battle)
	var won: CombatSession = battle.encounter.get_session(2)
	var sent: String = _land_send(battle, LEAVER, 2)
	_resolve(battle, FallFixture.new(2, _units_of(won, 2)), 2)
	_resolve(battle, EndMapFixture.new(), 2)
	var frozen: CombatSession = battle.encounter.get_session(TEAMMATE)
	_resolve(battle, FallFixture.new(TEAMMATE, _units_of(frozen, TEAMMATE)), TEAMMATE)
	var could_help: bool = (
			battle.encounter.is_frozen(TEAMMATE) and not battle.encounter.is_run_lost()
	)
	var first: int = battle.encounter.fact_log.size()
	battle.encounter.forfeit(LEAVER)
	_check("leave from an ended map: it stays as it stood and counts for nothing", (
			could_help
			and won.state.has_unit(sent)
			and battle.encounter.fact_log.size() == first + 1
			and battle.encounter.is_run_lost()
	))
	return true


# After a leave (a landed send and a visitor), the battle's snapshot loads through JSON into a
# battle built the same way, every hash equal and the leavers still gone.
func _test_snapshot_round_trip() -> bool:
	var battle: Battle = _coop(4, true)
	_add_cross_map(battle)
	_open(battle)
	var sent: String = _land_send(battle, LEAVER, 3)
	battle.encounter.forfeit(LEAVER)
	var copy: Battle = _coop(4, true)
	_add_cross_map(copy)
	var loaded: Error = copy.encounter.load_snapshot(
			WireCases.Kit.through_json(battle.encounter.snapshot(_by_id)) as Dictionary,
			_definition_of,
	)
	_check("leave: a snapshot round trip keeps it", (
			loaded == OK
			and _maps_match(battle, copy)
			and copy.encounter.state_hash() == battle.encounter.state_hash()
			and copy.encounter.forfeited_seats() == PackedInt32Array([LEAVER])
			and copy.encounter.session_of_unit(sent) == null
			and copy.encounter.get_session(TEAMMATE).state.units_of(PLAYER).size() == 1
	), error_string(loaded))
	return true


# A client's mirror loaded at battle start follows the host's batches in order, every map's and
# the encounter's hash equal after each Start, each End Turn on the shared maps and the leave.
func _test_mirror(seat_count: int) -> bool:
	var label: String = "leave mirror %d seats" % [seat_count]
	var host: Battle = _coop(seat_count, true)
	var mirror: Battle = _coop(seat_count, true)
	_add_cross_map(host)
	_add_cross_map(mirror)
	_open(host, PackedInt32Array([TEAMMATE, LEAVER]))
	var loaded: Error = mirror.encounter.load_snapshot(
			WireCases.Kit.through_json(host.encounter.snapshot(_by_id)) as Dictionary,
			_definition_of,
	)
	var feed: MirrorFeed = MirrorFeed.new(host, mirror)
	# Arrays, not packed arrays: the lambda below captures them by reference.
	var steps: Array[String] = []
	var failed: Array[String] = []
	var step: Callable = func(name: String, action: Callable) -> void:
		action.call()
		steps.append(name)
		if not feed.drain_matches():
			failed.append(name)
	step.call("start seat 0", _resolve.bind(host, StartCommand.new(TEAMMATE), TEAMMATE))
	step.call("start seat 1", _resolve.bind(host, StartCommand.new(LEAVER), TEAMMATE))
	step.call("end turn seat 1", _resolve.bind(host, EndTurnCommand.new(LEAVER), TEAMMATE))
	step.call("end turn seat 0", _resolve.bind(host, EndTurnCommand.new(TEAMMATE), TEAMMATE))
	if seat_count == 4:
		step.call("send 2 to 3", func() -> void: _land_send(host, 2, 3))
		step.call("end turn seat 2 on s3", _resolve.bind(host, EndTurnCommand.new(2), 3))
		step.call("end turn seat 3 on s3", _resolve.bind(host, EndTurnCommand.new(3), 3))
	step.call("end turn seat 0 again", _resolve.bind(host, EndTurnCommand.new(TEAMMATE), 0))
	step.call("seat 1 leaves", func() -> void: host.encounter.forfeit(LEAVER))
	var shared: CombatSession = mirror.encounter.get_session(TEAMMATE)
	_check("%s: every batch applies, every hash equal after each step" % [label], (
			loaded == OK and failed.is_empty() and feed.results.count(OK) == feed.results.size()
			and feed.results.size() > steps.size()
	), "failed %s; %s" % [failed, feed.results])
	_check("%s: the mirror has the leave as the host has it" % [label], (
			mirror.encounter.forfeited_seats() == PackedInt32Array([LEAVER])
			and shared.state.units_of(PLAYER).size() == 1
			and shared.state.turn == host.encounter.get_session(TEAMMATE).state.turn
			and mirror.encounter.get_cross_map_instances().is_empty()
			and not mirror.encounter.forfeit(LEAVER)
	))
	return true


# Solo: an End Turn runs the turn as before, its only new fact its own end first; nothing leaves.
func _test_solo_unchanged() -> bool:
	var battle: Battle = _coop(1, false)
	_open(battle)
	var map: CombatSession = battle.encounter.get_session(0)
	var ended: CombatSession.FactBatch = _resolve(battle, EndTurnCommand.new(0), 0)
	_check("leave: solo's End Turn runs the turn, its own end first", (
			map.state.turn == 2
			and ended.facts[0].kind == CombatFact.Kind.TURN_ENDED
			and ended.facts[1].kind == CombatFact.Kind.PHASE_END
			and not _kinds_of(battle.encounter.fact_log).contains("UNIT_LEFT")
			and not battle.encounter.is_run_lost()
	), _kinds_of(ended.facts))
	return true


# A battle of seat_count seats on the fixture map, each map with its seat's Drengr and a Brute.
# With visitor, seat 1's second Drengr stands on seat 0's map with a trait, and seat 1's army
# holds a Your Unit heirloom that follows it there.
func _coop(seat_count: int, visitor: bool) -> Battle:
	var seats: PackedInt32Array = []
	for seat: int in seat_count:
		seats.append(seat)
	var battle: Battle = Battle.new(seats)
	battle.set_up()
	battle.open()
	for seat: int in seat_count:
		battle.add_unit(seat, "Drengr", PLAYER, seat, PLAYER_TILE)
		battle.add_unit(seat, "Brute", ENEMY, -1, ENEMY_TILE)
	if visitor and seat_count > 1:
		var visiting: String = battle.add_unit(TEAMMATE, "Drengr", PLAYER, LEAVER, VISITOR_TILE)
		var map: CombatSession = battle.encounter.get_session(TEAMMATE)
		map.engine.register(EffectInstance.new(
				battle.ids.next_effect_id(),
				_define(_hit_dealt_block("visitor_trait", 1.0)),
				EffectOwner.for_unit(visiting, LEAVER, PLAYER),
				Modifier.SourceKind.UNIT_TRAIT
		))
		var heirloom: EffectDefinition = _define(_hit_dealt_block("followed_heirloom", 2.0))
		heirloom.scope = EffectTerms.Scope.YOUR_UNIT
		battle.encounter.get_session(LEAVER).engine.register(battle.army_effect(LEAVER, heirloom))
		battle.encounter.add_owner_effects(TEAMMATE, LEAVER)
	for session: CombatSession in battle.encounter.get_sessions():
		session.engine.verify = true
	return battle


# Adds the leaver's cross-map army effect (Any Ally Unit, as Brothers in Arms) to battle.
func _add_cross_map(battle: Battle) -> EffectInstance:
	var instance: EffectInstance = battle.army_effect(LEAVER, _define(_every_hit_by_allies(1)))
	battle.encounter.add_cross_map(instance)
	return instance


# Opens every map; swap_seats open seat 0's map's opening swap window.
func _open(battle: Battle, swap_seats: PackedInt32Array = PackedInt32Array()) -> void:
	for session: CombatSession in battle.encounter.get_sessions():
		session.open_battle(swap_seats if session.session_id == TEAMMATE else PackedInt32Array())


# Submits command to session_id through the encounter and resolves; returns the last map batch,
# or an empty one when there was none.
func _resolve(battle: Battle, command: Command, session_id: int) -> CombatSession.FactBatch:
	battle.encounter.submit(command, session_id)
	var batches: Array[CombatSession.FactBatch] = battle.encounter.resolve_queued()
	return CombatSession.FactBatch.new() if batches.is_empty() else batches[batches.size() - 1]


# Wins from_seat's map, sends its Drengr to the map to_session_id and lands it there at once, its
# landing sent as that map's batch. Returns the unit's id.
func _land_send(battle: Battle, from_seat: int, to_session_id: int) -> String:
	var source: CombatSession = battle.encounter.session_of_seat(from_seat)
	_resolve(battle, EndMapFixture.new(), source.session_id)
	var sent: String = _units_of(source, from_seat)[0]
	battle.encounter.send_unit(sent, source.session_id, to_session_id, CombatFact.NO_TILE)
	battle.encounter.deliver_arrivals(to_session_id)
	battle.encounter.get_session(to_session_id).flush("arrived")
	return sent


# The map batches session sends while action runs.
func _batches_of(session: CombatSession, action: Callable) -> Array[CombatSession.FactBatch]:
	var sent: Array[CombatSession.FactBatch] = []
	var listen: Callable = func(batch: CombatSession.FactBatch) -> void:
		sent.append(batch)
	session.batch_resolved.connect(listen)
	action.call()
	session.batch_resolved.disconnect(listen)
	return sent


# seat's living player units on session's map, in placement order.
func _units_of(session: CombatSession, seat: int) -> Array[String]:
	var found: Array[String] = []
	for unit_id: String in session.state.units_of(PLAYER):
		if session.state.seat_of(unit_id) == seat:
			found.append(unit_id)
	return found


# The id of the leaver's followed heirloom on its own map.
func _owner_effect_id(home: CombatSession) -> String:
	for instance: EffectInstance in home.engine.get_instances():
		if instance.definition.id == "followed_heirloom":
			return instance.instance_id
	return ""


# The id of the effect unit_id holds on session's map.
func _held_effect_id(session: CombatSession, unit_id: String) -> String:
	for instance: EffectInstance in session.engine.get_instances():
		if instance.owner.holder_id == unit_id:
			return instance.instance_id
	return ""


# Keeps definition for loads (_definition_of) and returns it.
func _define(definition: EffectDefinition) -> EffectDefinition:
	_definitions[definition.id] = definition
	return definition


# A snapshot's name for definition: its id.
func _by_id(definition: EffectDefinition) -> String:
	return definition.id


# The definition a snapshot named reference: the cases' own, else the catalog's.
func _definition_of(reference: String) -> EffectDefinition:
	if _definitions.has(reference):
		return _definitions[reference]
	return EffectInstance.catalog_definition(reference)


# Every map engine's diagnostics, joined.
func _diagnostics(battle: Battle) -> String:
	var found: PackedStringArray = []
	for session: CombatSession in battle.encounter.get_sessions():
		found.append_array(session.engine.diagnostics)
	return "; ".join(found)


func _maps_match(one: Battle, other: Battle) -> bool:
	for session: CombatSession in one.encounter.get_sessions():
		if other.encounter.get_session(session.session_id).state_hash() != session.state_hash():
			return false
	return true


# Defeats each unit through CombatState.defeat: a step that may empty a map.
class FallFixture:
	extends Command

	var unit_ids: Array[String] = []

	func _init(sender: int, defeated: Array[String]) -> void:
		seat = sender
		unit_ids = defeated

	func get_label() -> String:
		return "fall"

	func resolve(session: CombatSession) -> void:
		for unit_id: String in unit_ids:
			session.state.defeat(session.engine, unit_id, "")


# The host's batches, encounter and maps alike, in the order sent, each applied to the mirror by
# drain_matches(), which then compares every map's and the encounter's hash.
class MirrorFeed:
	extends RefCounted

	## What each apply_batch returned, in order.
	var results: Array[Error] = []

	var _host: Battle = null
	var _mirror: Battle = null
	var _sent: Array[CombatSession.FactBatch] = []
	var _is_encounter: Array[bool] = []

	func _init(host: Battle, mirror: Battle) -> void:
		_host = host
		_mirror = mirror
		host.encounter.batch_resolved.connect(_on_batch.bind(true))
		for session: CombatSession in host.encounter.get_sessions():
			session.batch_resolved.connect(_on_batch.bind(false))

	## Applies every batch sent since the last call; whether every hash then equals the host's.
	func drain_matches() -> bool:
		for index: int in _sent.size():
			var batch: CombatSession.FactBatch = WireCases.Kit.batch_through_json(_sent[index])
			if _is_encounter[index]:
				results.append(_mirror.encounter.apply_batch(batch))
			else:
				results.append(
						_mirror.encounter.get_session(batch.session_id).apply_batch(batch)
				)
		_sent.clear()
		_is_encounter.clear()
		var matches: bool = (
				_mirror.encounter.state_hash() == _host.encounter.state_hash()
		)
		for session: CombatSession in _host.encounter.get_sessions():
			var copy: CombatSession = _mirror.encounter.get_session(session.session_id)
			matches = matches and copy.state_hash() == session.state_hash()
		return matches

	func _on_batch(batch: CombatSession.FactBatch, is_encounter: bool) -> void:
		if batch.is_rejected():
			return
		_sent.append(batch)
		_is_encounter.append(is_encounter)
