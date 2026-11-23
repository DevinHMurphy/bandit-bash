# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_send_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Co-op sends and calls for aid for tests/sessions/run_all.gd, in 2-, 3- and 4-seat encounters:
## each refusal of [SendUnitsCommand]; the battle clock; a send to a frozen map restarting it and
## the visitor's seat ending the turn there; units sent back when their target ends first, sendable
## again; the senders a map records; [CallForAidCommand] raised and lowered; a mirror following
## every new fact hash for hash; version 3 data loading; a save and Continue mid-transfer; the save
## points on any map; the wire forms; and solo refusing both.
##
## Each map is its seat's fixture map with a Drengr at (0, 3) and a Brute at (3, 2), turn 1 open;
## seat 0's map also has an Archer at (2, 3). Maps end and units fall through fixture commands.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

const PLAYER_TILE: Vector2i = Vector2i(0, 3)
const ENEMY_TILE: Vector2i = Vector2i(3, 2)
const SECOND_TILE: Vector2i = Vector2i(2, 3)

# The co-op seat counts every core case runs in.
const SEAT_COUNTS: Array[int] = [2, 3, 4]


func run() -> void:
	for seat_count: int in SEAT_COUNTS:
		_run(_test_refusals.bind(seat_count))
		_run(_test_battle_clock.bind(seat_count))
		_run(_test_frozen_restart.bind(seat_count))
		_run(_test_returns.bind(seat_count))
		_run(_test_senders.bind(seat_count))
		_run(_test_call_for_aid.bind(seat_count))
	_run(_test_frozen_rules)
	_run(_test_sent_again_after_return)
	_run(_test_mirror_follows_every_fact)
	_run(_test_version_3_loads)
	_run(_test_continue_mid_transfer)
	_run(_test_save_points)
	_run(_test_wire_forms)
	_run(_test_solo_refuses)


# Every refusal of a send while no map is frozen, each a rejected batch on the map it was submitted
# on that only its seat hears; a map's own queue refuses one too.
func _test_refusals(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var winner: CombatSession = battle.encounter.get_session(0)
	var drengr: String = _player_of(winner)
	var archer: String = winner.state.units_of(PLAYER)[1]
	var other: String = _player_of(battle.encounter.get_session(last))
	var label: String = "refusal %d seats" % [seat_count]
	_open(battle)
	_check("%s: a map still being fought sends no one" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), last), 0
	) == "s0 is still being fought")
	var heard: Array[String] = []
	winner.command_rejected.connect(func(seat: int, _arrival: int, reason: String) -> void:
		heard.append("%d %s" % [seat, reason])
	)
	_resolve(battle, EndMapFixture.new(), 0)
	_check("%s: another seat's unit" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([other]), last), 0
	) == "%s isn't a surviving unit of seat 0 on s0" % [other])
	_check("%s: a unit named twice" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr, drengr]), last), 0
	) == "%s is named twice" % [drengr])
	_check("%s: its own map" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), 0), 0
	) == "no map s0 to send to")
	_check("%s: no such map" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), seat_count), 0
	) == "no map s%d to send to" % [seat_count])
	if seat_count > 2:
		_resolve(battle, EndMapFixture.new(ENEMY), 1)
		_check("%s: a map that has finished" % [label], _reason_of(
				battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), 1), 0
		) == "s1 has finished")
		_check("%s: a lost map sends no one" % [label], _reason_of(
				battle, SendUnitsCommand.new(1, PackedStringArray([]), last), 1
		) == "s1 was lost")
	# On a map still being fought, so the map's own end check doesn't answer first.
	var queued_alone: CombatSession.FactBatch = _resolve(
			battle, SendUnitsCommand.new(last, PackedStringArray([other]), 0), last, true
	)
	_check("%s: a map's own queue refuses it" % [label], (
			queued_alone.rejected_reason == "a send goes through the encounter"
	), queued_alone.rejected_reason)
	_check("%s: a send goes through" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([archer]), last), 0
	).is_empty())
	_check("%s: once per seat" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), last), 0
	) == "seat 0 has sent already")
	_check("%s: only the seat hears each refusal" % [label], (
			heard.size() >= 5 and heard[0].begins_with("0 ")
	), str(heard))
	return true


# "Send none" is final while no map is frozen; while one is, a send must take at least one unit to
# a frozen map, and a seat that sent may send again, but a unit on its way can't go twice.
func _test_frozen_rules() -> bool:
	var battle: Battle = _coop(3)
	var winner: CombatSession = battle.encounter.get_session(0)
	var drengr: String = _player_of(winner)
	var archer: String = winner.state.units_of(PLAYER)[1]
	_open(battle)
	_resolve(battle, EndMapFixture.new(), 0)
	_check("frozen rules: send none resolves", _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray(), -1), 0
	).is_empty())
	_check("frozen rules: send none is final", (
			battle.encounter.has_sent(0)
			and _reason_of(
					battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), 1), 0
			) == "seat 0 has sent already"
	))
	_resolve(battle, FellFixture.new(2, [_player_of(battle.encounter.get_session(2))]), 2)
	_fill_map(battle, 2)
	_check("frozen rules: none is refused while a map is frozen", _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray(), -1), 0
	) == "a map is frozen: send at least one unit")
	_check("frozen rules: only to a frozen map", _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), 1), 0
	) == "a map is frozen: send to a frozen map")
	_check("frozen rules: a seat that sent may send again to it", _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr]), 2), 0
	).is_empty())
	_check("frozen rules: no free tile, so it waits and the map stays frozen", (
			battle.encounter.units_in_transit() == PackedStringArray([drengr])
			and battle.encounter.is_frozen(2)
	))
	_check("frozen rules: a unit on its way can't go twice", _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([drengr, archer]), 2), 0
	) == "%s is already on its way" % [drengr])
	return true


# A transfer lands at the target's first player Phase Start after the turn its sender's map was
# won on: a target behind waits a turn, then the unit lands near the receiving commander.
func _test_battle_clock(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var target: CombatSession = battle.encounter.get_session(last)
	var commander: String = _player_of(target)
	target.commander_ids[last] = commander
	target.state.commander_ids = target.commander_ids.duplicate()
	var sent: String = battle.encounter.get_session(0).state.units_of(PLAYER)[1]
	var label: String = "clock %d seats" % [seat_count]
	_open(battle)
	_resolve(battle, EndTurnCommand.new(0), 0)
	_resolve(battle, EndMapFixture.new(), 0)
	_check("%s: the sender's map was won on turn 2, the target is on turn 1" % [label], (
			battle.encounter.get_session(0).state.turn == 2 and target.state.turn == 1
	))
	_check("%s: sent" % [label], _reason_of(
			battle, SendUnitsCommand.new(0, PackedStringArray([sent]), last), 0
	).is_empty())
	_resolve(battle, EndTurnCommand.new(last), last)
	_check("%s: not at turn 2's Phase Start" % [label], (
			target.state.turn == 2
			and not target.state.has_unit(sent)
			and battle.encounter.units_in_transit() == PackedStringArray([sent])
	), "turn %d" % [target.state.turn])
	var batch: CombatSession.FactBatch = _resolve(battle, EndTurnCommand.new(last), last)
	var spawned: CombatFact = _first_of(batch.facts, CombatFact.Kind.UNIT_SPAWNED)
	var started: CombatFact = _first_of(batch.facts, CombatFact.Kind.PHASE_START)
	_check("%s: lands at turn 3's player Phase Start, before it starts" % [label], (
			target.state.turn == 3
			and target.state.has_unit(sent)
			and spawned.actor_id == sent
			and spawned.seq < _first_player_start(batch).seq
			and started.side == ENEMY
			and battle.encounter.units_in_transit().is_empty()
	), _kinds_of(batch.facts))
	var distance: int = _distance(target.state.tile_of(sent), target.state.tile_of(commander))
	_check("%s: next to the receiving commander" % [label], distance == 1, str(distance))
	return true


# A send to a frozen map lands at once and restarts it as its own batch, a save point; the
# visitor's seat takes its turn there and ends it (BUG-036), while the map's own seat has no unit.
func _test_frozen_restart(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var target: CombatSession = battle.encounter.get_session(last)
	var sent: String = _player_of(battle.encounter.get_session(0))
	var label: String = "restart %d seats" % [seat_count]
	_open(battle)
	_resolve(battle, FellFixture.new(last, [_player_of(target)]), last)
	_resolve(battle, EndTurnCommand.new(0), 0)
	_resolve(battle, EndTurnCommand.new(0), 0)
	_resolve(battle, EndMapFixture.new(), 0)
	_check("%s: frozen, the sender won on a later turn" % [label], (
			battle.encounter.is_frozen(last)
			and battle.encounter.get_session(0).state.turn > target.state.turn
	))
	var restart: Array[CombatSession.FactBatch] = []
	battle.encounter.submit(SendUnitsCommand.new(0, PackedStringArray([sent]), last), 0)
	restart = battle.encounter.resolve_queued()
	_check("%s: lands at once, the clock waived, and restarts the map" % [label], (
			restart.size() == 1
			and restart[0].label == "frozen map resumed"
			and restart[0].session_id == last
			and target.state.has_unit(sent)
			and not battle.encounter.is_frozen(last)
			and target.state.turn == 2
			and target.state.phase_side == PLAYER
	), "%d batches" % [restart.size()])
	_check("%s: the restart is a save point" % [label], (
			restart.size() == 1 and CombatEncounter.is_save_point(restart[0])
	))
	_check("%s: the visitor's seat must end the turn there" % [label], (
			PhaseRunner.seats_to_end(target) == PackedInt32Array([0])
			and target.seats == PackedInt32Array([last])
	), str(PhaseRunner.seats_to_end(target)))
	_check("%s: the map's own seat has no unit to end with" % [label], (
			_resolve(battle, EndTurnCommand.new(last), last).rejected_reason
			== "seat %d has no units on this map" % [last]
	))
	_check("%s: the visitor acts there" % [label], (
			_resolve(battle, UnitTurnCommand.new(0, sent, UnitTurnCommand.Action.WAIT), last)
			.rejected_reason.is_empty()
	))
	var ended: CombatSession.FactBatch = _resolve(battle, EndTurnCommand.new(0), last)
	_check("%s: the visitor's End Turn runs the enemy phase into turn 3" % [label], (
			ended.rejected_reason.is_empty()
			and target.state.turn == 3
			and CombatEncounter.is_save_point(ended)
	), ended.rejected_reason)
	_check("%s: no diagnostics" % [label], target.engine.diagnostics.is_empty())
	return true


# A target that ends before its units land sends them back onto the won map they left, unharmed:
# its record as it was, its effects registered there again with their counters.
func _test_returns(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var winner: CombatSession = battle.encounter.get_session(0)
	var sent: String = winner.state.units_of(PLAYER)[1]
	var resolve: EffectInstance = EffectInstance.new(
			battle.ids.next_effect_id(),
			_hit_dealt_block("resolve", 1.0, 5),
			EffectOwner.for_unit(sent, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT
	)
	winner.engine.register(resolve)
	resolve.set_counter(EffectTerms.Lane.COMBAT, 3)
	var label: String = "return %d seats" % [seat_count]
	var facts: Array[CombatFact] = []
	battle.encounter.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		facts.append_array(batch.facts)
	)
	_open(battle)
	_resolve(battle, EndTurnCommand.new(0), 0)
	_resolve(battle, EndMapFixture.new(), 0)
	var before: Dictionary = winner.state.unit(sent).capture()
	_reason_of(battle, SendUnitsCommand.new(0, PackedStringArray([sent]), last), 0)
	_check("%s: on its way, its effects off the won map" % [label], (
			battle.encounter.units_in_transit() == PackedStringArray([sent])
			and winner.engine.get_instance(resolve.instance_id) == null
	))
	_resolve(battle, EndMapFixture.new(), last)
	var returned: CombatFact = _first_of(facts, CombatFact.Kind.UNIT_RETURNED)
	_check("%s: its target ended first, so it went back" % [label], (
			battle.encounter.units_in_transit().is_empty()
			and returned.actor_id == sent
			and returned.session_id == last
			and returned.key == 0
			and returned.amount == 0
	), _kinds_of(facts))
	_check("%s: unharmed, its effects back with their counters" % [label], (
			JSON.stringify(winner.state.unit(sent).capture()) == JSON.stringify(before)
			and winner.engine.get_instance(resolve.instance_id) == resolve
			and resolve.get_counter(EffectTerms.Lane.COMBAT) == 3
			and battle.encounter.session_of_unit(sent) == winner
	))
	_check("%s: it never reached the target, which counts no sender" % [label], (
			not battle.encounter.get_session(last).state.has_unit(sent)
			and battle.encounter.senders_of(last).is_empty()
	))
	return true


# A returned unit counts as a unit left to send: a map that freezes later still has help, and the
# seat that sent may send it there.
func _test_sent_again_after_return() -> bool:
	var battle: Battle = _coop(3)
	var winner: CombatSession = battle.encounter.get_session(0)
	var sent: String = winner.state.units_of(PLAYER)[1]
	_open(battle)
	_resolve(battle, EndMapFixture.new(), 0)
	_reason_of(battle, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	_resolve(battle, EndMapFixture.new(), 1)
	_resolve(battle, FellFixture.new(2, [_player_of(battle.encounter.get_session(2))]), 2)
	_check("returned: a frozen map still has help", (
			battle.encounter.is_frozen(2) and not battle.encounter.is_run_lost()
	))
	_check("returned: sent again, to the frozen map", (
			_reason_of(battle, SendUnitsCommand.new(0, PackedStringArray([sent]), 2), 0).is_empty()
			and battle.encounter.get_session(2).state.has_unit(sent)
			and not battle.encounter.is_frozen(2)
	))
	return true


# The receiving map records each sender's seat once a unit lands, never before, so it loses its
# speed bonus; two seats sending to one map both count.
func _test_senders(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var label: String = "senders %d seats" % [seat_count]
	_open(battle)
	_resolve(battle, FellFixture.new(last, [_player_of(battle.encounter.get_session(last))]), last)
	_resolve(battle, EndMapFixture.new(), 0)
	_fill_map(battle, last)
	var first: String = _player_of(battle.encounter.get_session(0))
	_reason_of(battle, SendUnitsCommand.new(0, PackedStringArray([first]), last), 0)
	_check("%s: none while it is on its way" % [label], (
			battle.encounter.units_in_transit() == PackedStringArray([first])
			and battle.encounter.senders_of(last).is_empty()
	))
	# Two tiles freed, one for each sender.
	var receiving: CombatSession = battle.encounter.get_session(last)
	for freed: int in 2:
		receiving.state.defeat(receiving.engine, _enemy_of(receiving), "")
	battle.encounter.deliver_arrivals(last)
	var expected: PackedInt32Array = [0]
	if seat_count > 2:
		var second: String = _player_of(battle.encounter.get_session(1))
		_resolve(battle, EndMapFixture.new(), 1)
		_reason_of(battle, SendUnitsCommand.new(1, PackedStringArray([second]), last), 1)
		battle.encounter.deliver_arrivals(last)
		expected.append(1)
	_check("%s: each seat that landed a unit" % [label], (
			battle.encounter.senders_of(last) == expected
			and battle.encounter.senders_of(0).is_empty()
	), str(battle.encounter.senders_of(last)))
	return true


# The call for aid: the map's own seat raises and lowers it, each an AID_CALLED; asking for the
# flag as it is, another seat, and an ended map are refused; it stays raised as the map ends.
func _test_call_for_aid(seat_count: int) -> bool:
	var battle: Battle = _coop(seat_count)
	var last: int = seat_count - 1
	var label: String = "aid %d seats" % [seat_count]
	var facts: Array[CombatFact] = []
	battle.encounter.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		facts.append_array(batch.facts)
	)
	_open(battle)
	_check("%s: lowering an unraised call is refused" % [label], _reason_of(
			battle, CallForAidCommand.new(last, false), last
	) == "the call for aid is already lowered")
	_check("%s: another seat can't call on the map" % [label], _reason_of(
			battle, CallForAidCommand.new(0, true), last
	) == "seat 0 doesn't own s%d" % [last])
	_check("%s: raised" % [label], (
			_reason_of(battle, CallForAidCommand.new(last, true), last).is_empty()
			and battle.encounter.is_aid_called(last)
			and not battle.encounter.is_aid_called(0)
	))
	var called: CombatFact = _first_of(facts, CombatFact.Kind.AID_CALLED)
	_check("%s: one AID_CALLED naming the map and seat" % [label], (
			facts.size() == 1
			and called.session_id == last
			and called.amount == last
			and called.key == 1
	), _kinds_of(facts))
	_check("%s: raising twice is refused" % [label], _reason_of(
			battle, CallForAidCommand.new(last, true), last
	) == "the call for aid is already raised")
	_check("%s: lowered" % [label], (
			_reason_of(battle, CallForAidCommand.new(last, false), last).is_empty()
			and not battle.encounter.is_aid_called(last)
			and facts[facts.size() - 1].key == 0
	))
	_reason_of(battle, CallForAidCommand.new(last, true), last)
	_resolve(battle, EndMapFixture.new(), last)
	_check("%s: kept as it was when the map ends, and no call after" % [label], (
			battle.encounter.is_aid_called(last)
			and _reason_of(battle, CallForAidCommand.new(last, false), last)
			== "the combat on this map has ended"
	))
	return true


# A client's mirror, loaded at battle start, follows every batch in the host's order: each new
# fact (sent, sent none, returned, aid called), a restart and a landing by the clock, every map's
# and the encounter's hash matching after each.
func _test_mirror_follows_every_fact() -> bool:
	var host: Battle = _coop(4)
	var mirror: Battle = _coop(4)
	_open(host)
	var loaded: Error = mirror.encounter.load_snapshot(
			WireCases.Kit.through_json(host.encounter.snapshot()) as Dictionary
	)
	var sent: Array[CombatSession.FactBatch] = []
	var is_encounter: Array[bool] = []
	host.encounter.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		sent.append(batch)
		is_encounter.append(true)
	)
	for session: CombatSession in host.encounter.get_sessions():
		session.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
			sent.append(batch)
			is_encounter.append(false)
		)
	var drengr: String = _player_of(host.encounter.get_session(0))
	var archer: String = host.encounter.get_session(0).state.units_of(PLAYER)[1]
	_resolve(host, FellFixture.new(2, [_player_of(host.encounter.get_session(2))]), 2)
	_resolve(host, EndMapFixture.new(), 0)
	_resolve(host, EndMapFixture.new(), 3)
	_reason_of(host, CallForAidCommand.new(1, true), 1)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([drengr]), 2), 0)
	_reason_of(host, SendUnitsCommand.new(3, PackedStringArray([_player_of(
			host.encounter.get_session(3)
	)]), 1), 3)
	_resolve(host, EndMapFixture.new(), 1)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([archer]), 2), 0)
	_resolve(host, UnitTurnCommand.new(0, drengr, UnitTurnCommand.Action.WAIT), 2)
	_resolve(host, EndTurnCommand.new(0), 2)

	var results: Array[Error] = []
	for index: int in sent.size():
		var batch: CombatSession.FactBatch = WireCases.Kit.batch_through_json(sent[index])
		if is_encounter[index]:
			results.append(mirror.encounter.apply_batch(batch))
		else:
			results.append(mirror.encounter.get_session(batch.session_id).apply_batch(batch))
	var kinds: String = _kinds_of(mirror.encounter.fact_log)
	_check("mirror: every new kind reaches it", (
			loaded == OK
			and kinds.contains("UNIT_SENT")
			and kinds.contains("UNIT_RETURNED")
			and kinds.contains("AID_CALLED")
	), "%s; %s" % [error_string(loaded), kinds])
	_check("mirror: every batch applies, every hash matching", (
			results.count(OK) == results.size()
	), str(results))
	var maps_match: bool = true
	for session: CombatSession in host.encounter.get_sessions():
		var copy: CombatSession = mirror.encounter.get_session(session.session_id)
		maps_match = maps_match and copy.state_hash() == session.state_hash()
	_check("mirror: the battle as the host has it", (
			maps_match
			and mirror.encounter.state_hash() == host.encounter.state_hash()
			and mirror.encounter.units_in_transit() == host.encounter.units_in_transit()
			and mirror.encounter.senders_of(2) == PackedInt32Array([0])
			and mirror.encounter.is_aid_called(1)
			and mirror.encounter.has_sent(3)
			and mirror.encounter.session_of_unit(drengr) == mirror.encounter.get_session(2)
	))
	return true


# Version 3 data (no sends, senders, calls or forfeits, no clock turns) migrates and loads: its
# unit on its way lands at the target's next player Phase Start, as it did.
func _test_version_3_loads() -> bool:
	var host: Battle = _coop(2)
	var sent: String = host.encounter.get_session(0).state.units_of(PLAYER)[1]
	_open(host)
	_resolve(host, EndTurnCommand.new(0), 0)
	_resolve(host, EndMapFixture.new(), 0)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([sent]), 1), 0)
	var saved: Array[Dictionary] = _save(host)
	var state_data: Dictionary = saved[0]
	var encounter_part: Dictionary = state_data["encounter"]
	for key: String in ["sends", "senders", "aid", "forfeited"]:
		encounter_part.erase(key)
	for entry: Variant in encounter_part["in_transit"]:
		(entry as Dictionary).erase("clock_turn")
	var copy: Battle = _coop(2)
	var section: CombatStateSection = CombatStateSection.new()
	var migrated: Error = section.migrate(state_data, 3)
	var restored: Error = section.restore(state_data)
	var effects_restored: Error = section.effects.restore(saved[1])
	var load_error: Error = section.load_into(copy.encounter)
	_check("version 3: migrates and loads", (
			migrated == OK
			and restored == OK
			and effects_restored == OK
			and load_error == OK
			and copy.encounter.units_in_transit() == PackedStringArray([sent])
			and not copy.encounter.has_sent(0)
	), "%s %s %s" % [error_string(migrated), error_string(restored), error_string(load_error)])
	_resolve(copy, EndTurnCommand.new(1), 1)
	_check("version 3: due at the next player Phase Start", (
			copy.encounter.get_session(1).state.has_unit(sent)
			and copy.encounter.get_session(1).state.turn == 2
	))
	return true


# A save mid-transfer, Continued into a rebuilt battle: the unit on its way with its clock turn,
# the send, the call for aid; it then plays out the same as the host.
func _test_continue_mid_transfer() -> bool:
	var host: Battle = _coop(3)
	var sent: String = host.encounter.get_session(0).state.units_of(PLAYER)[1]
	_open(host)
	_resolve(host, EndTurnCommand.new(0), 0)
	_resolve(host, EndMapFixture.new(), 0)
	_reason_of(host, SendUnitsCommand.new(0, PackedStringArray([sent]), 2), 0)
	_reason_of(host, CallForAidCommand.new(2, true), 2)
	var saved: Array[Dictionary] = _save(host)
	var copy: Battle = _coop(3)
	var section: CombatStateSection = CombatStateSection.new()
	section.restore(saved[0])
	section.effects.restore(saved[1])
	var load_error: Error = section.load_into(copy.encounter)
	_check("continue: the battle loads mid-transfer as saved", (
			load_error == OK
			and copy.encounter.state_hash() == host.encounter.state_hash()
			and copy.encounter.units_in_transit() == PackedStringArray([sent])
			and copy.encounter.has_sent(0)
			and copy.encounter.is_aid_called(2)
			and _maps_match(host, copy)
	), error_string(load_error))
	for battle: Battle in [host, copy]:
		_resolve(battle, EndTurnCommand.new(2), 2)
		_resolve(battle, EndTurnCommand.new(2), 2)
	var host_map: CombatSession = host.encounter.get_session(2)
	var copy_map: CombatSession = copy.encounter.get_session(2)
	_check("continue: it lands by the clock, the same as on the host", (
			host_map.state.has_unit(sent)
			and copy_map.state.tile_of(sent) == host_map.state.tile_of(sent)
			and copy.encounter.state_hash() == host.encounter.state_hash()
			and _maps_match(host, copy)
			and copy.encounter.senders_of(2) == PackedInt32Array([0])
	))
	return true


# A player phase's end on any map is a save point, and the save holds the whole battle; a move, a
# rejected command, the battle's opening and encounter facts aren't.
func _test_save_points() -> bool:
	var battle: Battle = _coop(3)
	var opening: Array[CombatSession.FactBatch] = []
	battle.encounter.get_session(0).batch_resolved.connect(
			func(batch: CombatSession.FactBatch) -> void: opening.append(batch)
	)
	_open(battle)
	# Counted as the screen counts them; the save is taken after the queue, as nothing follows the
	# batch. A handler holding the battle would make a reference cycle.
	var points: Array[int] = [0]
	for session: CombatSession in battle.encounter.get_sessions():
		session.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
			if CombatEncounter.is_save_point(batch):
				points[0] += 1
		)
	var waited: CombatSession.FactBatch = _resolve(battle, UnitTurnCommand.new(
			2, _player_of(battle.encounter.get_session(2)), UnitTurnCommand.Action.WAIT
	), 2)
	var refused: CombatSession.FactBatch = _resolve(battle, EndTurnCommand.new(0), 2)
	_check("save points: not a move, a refusal or the opening", (
			not CombatEncounter.is_save_point(waited)
			and not CombatEncounter.is_save_point(refused)
			and opening.size() == 1
			and not CombatEncounter.is_save_point(opening[0])
			and points[0] == 0
	))
	var ended: CombatSession.FactBatch = _resolve(battle, EndTurnCommand.new(2), 2)
	_check("save points: the last map's player phase end", (
			CombatEncounter.is_save_point(ended) and points[0] == 1
	), str(points[0]))
	var saved: Array[Dictionary] = _save(battle)
	var copy: Battle = _coop(3)
	var section: CombatStateSection = CombatStateSection.new()
	section.restore(saved[0] if saved.size() == 2 else {})
	section.effects.restore(saved[1] if saved.size() == 2 else {})
	var load_error: Error = section.load_into(copy.encounter)
	_check("save points: the save holds every map", (
			load_error == OK and _maps_match(battle, copy)
	), error_string(load_error))
	return true


# Both commands' wire forms, through JSON and back; a malformed field is refused.
func _test_wire_forms() -> bool:
	var send: SendUnitsCommand = SendUnitsCommand.new(1, PackedStringArray(["unit:4", "unit:9"]), 2)
	send.arrival = 7
	var read: Command = Command.from_wire(WireCases.Kit.through_json(send.to_wire()) as Array)
	var send_back: SendUnitsCommand = read as SendUnitsCommand
	_check("wire: a send", (
			send_back != null
			and send_back.seat == 1
			and send_back.arrival == 7
			and send_back.unit_ids == send.unit_ids
			and send_back.to_session_id == 2
			and str(send.to_wire()[0]) == "send_units"
	), str(send.to_wire()))
	var none: Command = Command.from_wire(
			WireCases.Kit.through_json(SendUnitsCommand.new(0).to_wire()) as Array
	)
	_check("wire: a send of none", (
			none is SendUnitsCommand
			and (none as SendUnitsCommand).unit_ids.is_empty()
			and (none as SendUnitsCommand).to_session_id == SendUnitsCommand.NO_TARGET
	))
	var call: Command = Command.from_wire(
			WireCases.Kit.through_json(CallForAidCommand.new(3, false).to_wire()) as Array
	)
	_check("wire: a call for aid", (
			call is CallForAidCommand
			and not (call as CallForAidCommand).is_raised
			and call.seat == 3
			and str(CallForAidCommand.new().to_wire()[0]) == "call_for_aid"
	))
	print("    (warnings about malformed command wire data follow)")
	_check("wire: malformed fields are refused", (
			Command.from_wire(["send_units", 0, "", -1, 0, [4], 1]) == null
			and Command.from_wire(["send_units", 0, "", -1, 0, [], 1.5]) == null
			and Command.from_wire(["call_for_aid", 0, "", -1, 0, 1]) == null
	))
	return true


# Solo has no sends or calls for aid: both are refused, and the battle is untouched.
func _test_solo_refuses() -> bool:
	var battle: Battle = _coop(1)
	var session: CombatSession = battle.encounter.get_session(0)
	_open(battle)
	var facts: int = session.engine.fact_log.size()
	_check("solo: both refused", (
			_reason_of(battle, CallForAidCommand.new(0, true), 0) == "only in co-op"
			and _reason_of(battle, SendUnitsCommand.new(0), 0) == "only in co-op"
			and battle.encounter.fact_log.is_empty()
			and session.engine.fact_log.size() == facts
	))
	return true


# The combat_state and effects sections' data for battle as saving writes it, through JSON.
func _save(battle: Battle) -> Array[Dictionary]:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, battle.encounter.seats
	)
	run.encounter = battle.encounter
	var section: CombatStateSection = CombatStateSection.new()
	section.attach(run)
	var saved: Array[Dictionary] = [
		WireCases.Kit.through_json(section.capture()) as Dictionary,
		WireCases.Kit.through_json(section.effects.capture()) as Dictionary,
	]
	section.detach()
	return saved


func _maps_match(one: Battle, other: Battle) -> bool:
	for session: CombatSession in one.encounter.get_sessions():
		if other.encounter.get_session(session.session_id).state_hash() != session.state_hash():
			return false
	return true


# A battle of seat_count seats on the fixture map, each map with its seat's Drengr and a Brute;
# seat 0's map also has an Archer.
func _coop(seat_count: int) -> Battle:
	var seats: PackedInt32Array = []
	for seat: int in seat_count:
		seats.append(seat)
	var battle: Battle = Battle.new(seats)
	battle.set_up()
	battle.open()
	for seat: int in seat_count:
		battle.add_unit(seat, "Drengr", PLAYER, seat, PLAYER_TILE)
		battle.add_unit(seat, "Brute", ENEMY, -1, ENEMY_TILE)
	battle.add_unit(0, "Archer", PLAYER, 0, SECOND_TILE)
	return battle


func _open(battle: Battle) -> void:
	for session: CombatSession in battle.encounter.get_sessions():
		session.open_battle()


# Submits command to session_id and resolves the queue; returns the last map batch, or an empty
# one when there was none. With on_map, it goes straight to the map's own queue.
func _resolve(
		battle: Battle, command: Command, session_id: int, on_map: bool = false
) -> CombatSession.FactBatch:
	if on_map:
		battle.encounter.get_session(session_id).submit(command)
	else:
		battle.encounter.submit(command, session_id)
	var batches: Array[CombatSession.FactBatch] = battle.encounter.resolve_queued()
	return CombatSession.FactBatch.new() if batches.is_empty() else batches[batches.size() - 1]


# Submits command through the encounter and returns why it was refused; empty when it resolved.
func _reason_of(battle: Battle, command: Command, session_id: int) -> String:
	var arrival: int = battle.encounter.submit(command, session_id)
	for batch: CombatSession.FactBatch in battle.encounter.resolve_queued():
		if batch.arrival == arrival and batch.is_rejected():
			return batch.rejected_reason
	return ""


# Puts an enemy on every free tile of session_id's map, so a sent unit has nowhere to land.
func _fill_map(battle: Battle, session_id: int) -> void:
	var state: CombatState = battle.encounter.get_session(session_id).state
	for y: int in 4:
		for x: int in 5:
			var tile: Vector2i = Vector2i(x, y)
			if state.occupant_at(tile).is_empty() and state.can_stand(
					tile, CombatGrid.MovementType.DEFAULT
			):
				battle.add_unit(session_id, "Brute", ENEMY, -1, tile)


func _first_player_start(batch: CombatSession.FactBatch) -> CombatFact:
	for fact: CombatFact in batch.facts:
		if fact.kind == CombatFact.Kind.PHASE_START and fact.side == PLAYER:
			return fact
	return CombatFact.new(CombatFact.Kind.PHASE_START)


func _player_of(session: CombatSession) -> String:
	return session.state.units_of(PLAYER)[0]


func _enemy_of(session: CombatSession) -> String:
	return session.state.units_of(ENEMY)[0]


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


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
