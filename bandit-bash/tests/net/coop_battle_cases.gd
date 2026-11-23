# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_battle_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Co-op battles in the harness for tests/net/run_all.gd, 2 and 4 seats, each client acting
## through its [ClientMirror], each case on its fixed seed (in its name): a fallen commander's map
## playing on, a call for aid, a send landing by the clock and played by its owner there
## ([constant AID_SEED]); a frozen map helped by a client's send ([constant FREEZE_SEED]); swap
## visitors played by their owners, each client's board of a visitor and its owner's heirlooms as
## the host's, profile marks included ([constant VISIT_SEED]); a lost run ([constant LOST_SEED]).
## Every batch's hash matches as each client applies it, and every map and the encounter equal the
## host's after each step; at the end every client's run and every seat's results (a won map's
## rewards, a failed seat's empty results, shared XP) equal the host's. The largest message of
## each kind is printed. Maps end and units fall through the host, outside any seat's command.
## Needs a test user folder.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")
const Fixture = preload("res://tests/campaign/node_fixture.gd")
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")
const M1BattleCases = preload("res://tests/enemies/m1_battle_cases.gd")
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")

const HOST: int = NetHarness.HOST
const HOST_SEAT: int = CampaignData.HOST_SEAT
const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Every relay's name under its branch: the same on each, so RPC paths match.
const RELAY_NAME: StringName = &"NetRelay"

# The campaign's Steam ids are this plus the seat.
const FIRST_STEAM_ID: int = 76561198000000601

const SAVE_NUMBER: int = 1

# Clients per case: 2 and 4 seats.
const CLIENT_COUNTS: Array[int] = [1, 3]

# Each case's run seed. Any fixed seeds: the cases compare peers with each other, never with
# golden numbers; the seed fixes the maps, armies and every enemy phase.
const AID_SEED: String = "C017-0A1D-5E4D-0"
const FREEZE_SEED: String = "C017-F2EE-2E00-1"
const VISIT_SEED: String = "C017-7151-7000-2"
const LOST_SEED: String = "C017-1057-0000-3"

# The aid case's seat that calls for aid, and its sender in 4 seats (the host sends in 2).
const CALLER: int = 1
const FOUR_SEAT_SENDER: int = 2

# The freeze case's helper, the frozen seat in 4 seats (the host's map freezes in 2) and the
# seat whose map fails in 4.
const HELPER: int = 1
const FOUR_SEAT_FROZEN: int = 3
const FOUR_SEAT_FAILED: int = 2

# A Your Unit heirloom that follows its seat's units onto a partner's map (P11 CO3), given to the
# visitor case's last seat, whose visitor stands on the seat below's map.
const FOLLOWING_HEIRLOOM: String = "breakers_maul"

# One frame at 30 frames per second, and the most a bound board may take to settle: a guard, not
# a timing.
const FRAME: float = 1.0 / 30.0
const MAX_SETTLE_FRAMES: int = 1800

# The largest message seen of each kind, by kind, in bytes as it travels.
var _sizes: Dictionary[String, int] = {}

var _driver: M1BattleCases = M1BattleCases.new(_ignore)


func run() -> void:
	if not _has_test_user_dir():
		_skip("coop battle: every case", "needs a test user folder (see run_all.gd)")
		return
	for client_count: int in CLIENT_COUNTS:
		_test_aid_and_send(client_count)
		_test_freeze_and_help(client_count)
		_test_visitors(client_count)
		_test_lost_run(client_count)
	_test_sizes()


# The caller's commander falls and its map plays on; the caller raises its call for aid; the
# sender's map is won and it sends a unit there, which lands by the clock after the caller's End
# Turn, and its owner plays it there; the call is lowered; the caller's map then fails.
func _test_aid_and_send(client_count: int) -> void:
	var seat_count: int = client_count + 1
	var tag: String = "coop battle %d seats, aid and send (seed %s):" % [seat_count, AID_SEED]
	var rig: Rig = _start(client_count, AID_SEED, false)
	if rig == null:
		_check("%s the battle opens on every mirror" % [tag], false)
		return
	var battle: CombatEncounter = rig.session.encounter
	var sender: int = HOST_SEAT if seat_count == 2 else FOUR_SEAT_SENDER
	var called: CombatSession = battle.session_of_seat(CALLER)
	var source: CombatSession = battle.session_of_seat(sender)
	var failed: PackedStringArray = _start_every_seat(rig)

	var commander: String = called.state.commander_of(CALLER)
	var fell: String = _host_acts(rig, FellFixture.new(CALLER, [commander]), called.session_id)
	_note(failed, _difference(rig), "commander falls")
	var played: String = _play_unit(rig, CALLER, called.session_id)
	_note(failed, _difference(rig), "caller plays on")
	_check("%s a fallen commander's map plays on, its player acting through its mirror" % [tag], (
			fell.is_empty() and played.is_empty()
			and not commander.is_empty() and not called.state.has_unit(commander)
			and not called.is_finished and not battle.is_frozen(called.session_id)
	), "fell %s, played %s" % [fell, played])

	var raised: String = _act(rig, CALLER, CallForAidCommand.new(CALLER, true), called.session_id)
	_note(failed, _difference(rig), "aid raised")
	_check("%s a client's call for aid is raised on the host and every mirror" % [tag], (
			raised.is_empty() and _aid_everywhere(rig, called.session_id) == [true]
	), "%s; %s" % [raised, _aid_everywhere(rig, called.session_id)])

	_end_map(rig, source, PLAYER)
	_note(failed, _difference(rig), "sender wins")
	var units: PackedStringArray = _sendable(battle, source, sender)
	var unit_id: String = "" if units.is_empty() else units[0]
	var sent: String = _act(
			rig, sender, SendUnitsCommand.new(sender, [unit_id], called.session_id),
			source.session_id
	)
	_note(failed, _difference(rig), "send")
	var was_on_way: bool = _in_transit_everywhere(rig, unit_id)
	var ended: String = _act(rig, CALLER, EndTurnCommand.new(CALLER), called.session_id)
	_note(failed, _difference(rig), "caller's End Turn")
	_check("%s the send goes on its way and lands by the clock, on every mirror" % [tag], (
			sent.is_empty() and ended.is_empty() and was_on_way
			and _landed_everywhere(rig, unit_id, called.session_id)
			and battle.senders_of(called.session_id) == PackedInt32Array([sender])
	), "sent %s, on its way %s, ended %s, on s%d" % [
		sent, was_on_way, ended,
		-1 if battle.session_of_unit(unit_id) == null
		else battle.session_of_unit(unit_id).session_id,
	])

	var turn: String = _play_unit(rig, sender, called.session_id, unit_id)
	_note(failed, _difference(rig), "sender's unit turn")
	var sender_ended: String = _act(rig, sender, EndTurnCommand.new(sender), called.session_id)
	_note(failed, _difference(rig), "sender's End Turn")
	var lowered: String = _act(
			rig, CALLER, CallForAidCommand.new(CALLER, false), called.session_id
	)
	_note(failed, _difference(rig), "aid lowered")
	_check("%s the sender plays its landed unit there; the call is lowered everywhere" % [tag], (
			turn.is_empty() and sender_ended.is_empty() and lowered.is_empty()
			and _aid_everywhere(rig, called.session_id) == [false]
	), "turn %s, End Turn %s, lowered %s" % [turn, sender_ended, lowered])

	_end_map(rig, called, ENEMY)
	_note(failed, _difference(rig), "caller's map fails")
	_end_battle(rig, failed)
	var lost: CombatResultsModel = CombatResultsModel.build(rig.session, CALLER)
	var award: XpAward = _award_of(rig.session, sender, unit_id)
	_check("%s every client's run and results equal the host's" % [tag], (
			_results_difference(rig).is_empty()
			and lost != null and lost.is_lost
			and award != null and award.shared > 0
	), "%s; caller lost %s, sent unit's award %s" % [
		_results_difference(rig), lost != null and lost.is_lost,
		{} if award == null else award.capture(),
	])
	_check_batches(rig, tag, failed)
	_stop(rig)


# Every player unit on one map falls in its player phase, so it freezes once its turn has run on;
# the helper's map is won and it sends a unit there through its mirror, which lands at once and
# the map goes on; the helper plays it there. In 4 seats another map fails.
func _test_freeze_and_help(client_count: int) -> void:
	var seat_count: int = client_count + 1
	var tag: String = "coop battle %d seats, freeze and help (seed %s):" % [
		seat_count, FREEZE_SEED,
	]
	var rig: Rig = _start(client_count, FREEZE_SEED, false)
	if rig == null:
		_check("%s the battle opens on every mirror" % [tag], false)
		return
	var battle: CombatEncounter = rig.session.encounter
	var frozen_seat: int = HOST_SEAT if seat_count == 2 else FOUR_SEAT_FROZEN
	var cold: CombatSession = battle.session_of_seat(frozen_seat)
	var helped_from: CombatSession = battle.session_of_seat(HELPER)
	var failed: PackedStringArray = _start_every_seat(rig)

	var everyone: Array[String] = []
	everyone.assign(cold.state.units_of(PLAYER))
	var fell: String = _host_acts(rig, FellFixture.new(frozen_seat, everyone), cold.session_id)
	_note(failed, _difference(rig), "map emptied")
	_check("%s an emptied map freezes on every mirror; the run waits for the helper" % [tag], (
			fell.is_empty()
			and _frozen_everywhere(rig, cold.session_id) == [true]
			and _lost_everywhere(rig) == [false]
	), "fell %s, frozen %s, lost %s" % [
		fell, _frozen_everywhere(rig, cold.session_id), _lost_everywhere(rig),
	])

	_end_map(rig, helped_from, PLAYER)
	_note(failed, _difference(rig), "helper wins")
	var units: PackedStringArray = _sendable(battle, helped_from, HELPER)
	var unit_id: String = "" if units.is_empty() else units[0]
	var sent: String = _act(
			rig, HELPER, SendUnitsCommand.new(HELPER, [unit_id], cold.session_id),
			helped_from.session_id
	)
	_note(failed, _difference(rig), "send to the frozen map")
	_check("%s a client's send lands at once and the frozen map goes on, everywhere" % [tag], (
			sent.is_empty()
			and _frozen_everywhere(rig, cold.session_id) == [false]
			and _landed_everywhere(rig, unit_id, cold.session_id)
	), "sent %s, frozen %s" % [sent, _frozen_everywhere(rig, cold.session_id)])

	var turn: String = _play_unit(rig, HELPER, cold.session_id, unit_id)
	_note(failed, _difference(rig), "helper's unit turn")
	var ended: String = _act(rig, HELPER, EndTurnCommand.new(HELPER), cold.session_id)
	_note(failed, _difference(rig), "helper's End Turn")
	_check("%s the helper plays its unit on the helped map through its mirror" % [tag], (
			turn.is_empty() and ended.is_empty()
	), "turn %s, End Turn %s" % [turn, ended])

	if seat_count > 2:
		_end_map(rig, battle.session_of_seat(FOUR_SEAT_FAILED), ENEMY)
		_note(failed, _difference(rig), "a map fails")
	_end_battle(rig, failed)
	var helped: CombatResultsModel = CombatResultsModel.build(rig.session, frozen_seat)
	var lost: CombatResultsModel = (
			null if seat_count == 2 else CombatResultsModel.build(rig.session, FOUR_SEAT_FAILED)
	)
	_check("%s every client's run and results equal the host's" % [tag], (
			_results_difference(rig).is_empty()
			and helped != null and not helped.is_lost
			and (seat_count == 2 or (lost != null and lost.is_lost))
	), "%s; helped seat lost %s" % [
		_results_difference(rig), helped == null or helped.is_lost,
	])
	_check_batches(rig, tag, failed)
	_stop(rig)


# Accepted swaps between seats 0 and 1 (and 2 and 3); the last seat holds a heirloom that follows
# its units. Each client's board of the last seat's visitor equals the host's; then every seat
# plays a unit and ends its turn on every map it has units on. In 4 seats seat 1's map fails, so
# seat 0's visitor there earns no shared XP; the last seat's visitor earns it on a won map.
func _test_visitors(client_count: int) -> void:
	var seat_count: int = client_count + 1
	var tag: String = "coop battle %d seats, visitors (seed %s):" % [seat_count, VISIT_SEED]
	var rig: Rig = _start(client_count, VISIT_SEED, true)
	if rig == null:
		_check("%s the battle opens on every mirror with its visitors" % [tag], false)
		return
	var battle: CombatEncounter = rig.session.encounter
	var owner: int = seat_count - 1
	var partner: CombatSession = battle.session_of_seat(owner - 1)
	var visitor: String = _unit_of_seat(partner, owner)
	var failed: PackedStringArray = _start_every_seat(rig)
	_check_board(rig, tag, partner.session_id, visitor)

	var refusals: PackedStringArray = []
	for map: CombatSession in battle.get_sessions():
		for seat: int in PhaseRunner.seats_with_units(map):
			var turn: String = _play_unit(rig, seat, map.session_id)
			_note(failed, _difference(rig), "s%d seat %d unit turn" % [map.session_id, seat])
			var ended: String = _act(rig, seat, EndTurnCommand.new(seat), map.session_id)
			_note(failed, _difference(rig), "s%d seat %d End Turn" % [map.session_id, seat])
			for reason: String in [turn, ended]:
				if not reason.is_empty():
					refusals.append("s%d seat %d: %s" % [map.session_id, seat, reason])
	_check("%s each seat plays its units on every map, visitors by their owners" % [tag], (
			refusals.is_empty() and PhaseRunner.seats_with_units(partner).has(owner)
	), "; ".join(refusals))

	var away: String = ""
	if seat_count > 2:
		var failing: CombatSession = battle.session_of_seat(HOST_SEAT + 1)
		away = _unit_of_seat(failing, HOST_SEAT)
		_end_map(rig, failing, ENEMY)
		_note(failed, _difference(rig), "a visitor's map fails")
	_end_battle(rig, failed)
	var shared: XpAward = _award_of(rig.session, owner, visitor)
	var unshared: XpAward = null if away.is_empty() else _award_of(rig.session, HOST_SEAT, away)
	_check("%s every client's run and results equal the host's, a visitor's shared XP" % [tag], (
			_results_difference(rig).is_empty()
			and shared != null and shared.shared > 0
			and (away.is_empty() or (unshared != null and unshared.shared == 0))
	), "%s; visitor %s, on the failed map %s" % [
		_results_difference(rig),
		{} if shared == null else shared.capture(),
		{} if unshared == null else unshared.capture(),
	])
	_check_batches(rig, tag, failed)
	_stop(rig)


# Every map fails but the last seat's, whose units all fall: it freezes with no help left, so the
# run is lost on the host and every mirror; the host's end of the battle ends the run.
func _test_lost_run(client_count: int) -> void:
	var seat_count: int = client_count + 1
	var tag: String = "coop battle %d seats, lost run (seed %s):" % [seat_count, LOST_SEED]
	var rig: Rig = _start(client_count, LOST_SEED, false)
	if rig == null:
		_check("%s the battle opens on every mirror" % [tag], false)
		return
	var battle: CombatEncounter = rig.session.encounter
	var last: CombatSession = battle.session_of_seat(seat_count - 1)
	var failed: PackedStringArray = _start_every_seat(rig)
	for seat: int in range(0, seat_count - 1):
		_end_map(rig, battle.session_of_seat(seat), ENEMY)
		_note(failed, _difference(rig), "map %d fails" % [seat])
	var everyone: Array[String] = []
	everyone.assign(last.state.units_of(PLAYER))
	var fell: String = _host_acts(rig, FellFixture.new(seat_count - 1, everyone), last.session_id)
	_note(failed, _difference(rig), "last map emptied")
	_check("%s the run is lost on the host and every mirror, before every map ended" % [tag], (
			fell.is_empty() and _lost_everywhere(rig) == [true] and not battle.is_finished()
	), "fell %s, lost %s" % [fell, _lost_everywhere(rig)])
	_check_batches(rig, tag, failed)

	var result: CampaignSession.BattleResult = CampaignService.end_battle()
	rig.harness.step_until_idle()
	var record: ArchiveRecord = SaveService.take_ended_run()
	var closed: PackedStringArray = []
	for index: int in rig.clients():
		var copy: CampaignSession = rig.mirror(index).session
		if copy == null or copy.encounter != null:
			closed.append("client %d's battle is open" % [index])
		elif RunStateCases.run_text(copy.run) != RunStateCases.run_text(rig.session.run):
			closed.append("client %d's run differs" % [index])
	_check("%s the host ends the run as lost; every mirror closes its battle on the run" % [tag], (
			result != null
			and CampaignService.session == null
			and record != null and not record.won
			and closed.is_empty()
	), "; ".join(closed))
	_stop(rig)


# Every message the cases heard is under Steam's limit, as it travelled; each kind's largest is
# printed for the step report.
func _test_sizes() -> void:
	var lines: PackedStringArray = []
	var is_under: bool = not _sizes.is_empty()
	for kind: String in _sizes:
		print("      size: %s %d B" % [kind, _sizes[kind]])
		lines.append("%s %d" % [kind, _sizes[kind]])
		is_under = is_under and _sizes[kind] <= NetRelayScript._SEND_BUDGET
	_check("coop battle: every message heard is under Steam's message limit", is_under, (
			", ".join(lines)
	))


# A multiplayer run of client_count + 1 seats on seed_text, no starting offers, with swaps between
# seats 0 and 1 (and 2 and 3) when swapped (the last seat then holds FOLLOWING_HEIRLOOM), its
# floor-1 Standard battle begun with no opening swap and pushed to a started mirror per client.
# Null, the run ended, when any of it fails.
func _start(client_count: int, seed_text: String, swapped: bool) -> Rig:
	SaveFile.delete_folder("user://saves/")
	SaveService.open_save_file(SAVE_NUMBER)
	var steam_ids: PackedInt64Array = []
	for seat: int in client_count + 1:
		steam_ids.append(FIRST_STEAM_ID + seat)
	if SaveService.start_new_multiplayer_run(steam_ids) != OK:
		SaveService.close_save_file()
		return null
	# The run is rebuilt on the seed, as the debug command line's --run-seed= would make it.
	SaveService.campaign.run_seed = RunSeed.parse(seed_text)
	SaveService.campaign_activated.emit(CampaignData.Mode.MULTIPLAYER, false)
	var session: CampaignSession = CampaignService.session
	if session == null or session.run == null:
		_end_run()
		return null
	for seat: int in session.run.seat_numbers():
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var pairs: int = 0
	if swapped:
		for first: int in range(0, client_count + 1, 2):
			_swap(session, first, first + 1)
			pairs += 1
		session.run.seat_run(client_count).add_heirloom(FOLLOWING_HEIRLOOM)
	if (
			session.run.flow.swaps.size() != pairs
			or not Fixture.enter(session.run, CampaignGraph.NodeType.STANDARD)
	):
		_end_run()
		return null
	var rig: Rig = Rig.new()
	rig.session = session
	rig.sizes = _sizes
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(client_count):
		rig.harness.stop()
		_end_run()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	for seat: int in client_count + 1:
		directory.add_seat(seat, FIRST_STEAM_ID + seat, rig.harness.peer_id(seat))
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		relay.seats = directory
		rig.relays.append(relay)
		rig.mirrors.append(null)
		rig.settles.append({})
	for index: int in rig.clients():
		rig.add_mirror(index)
		rig.mirror(index).start()
	rig.harness.step_until_idle()
	var request: CampaignSession.BattleRequest = session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		_stop(rig)
		return null
	for seat: int in session.run.seat_numbers():
		request.opening_swap[seat] = false
	if CampaignService.begin_battle(request) != OK:
		_stop(rig)
		return null
	rig.harness.step_until_idle()
	rig.relay(HOST)._process(0.0)
	rig.harness.step_until_idle()
	for index: int in rig.clients():
		if rig.view(index) == null:
			_stop(rig)
			return null
	return rig


# Seat first proposes, and seat second accepts, a swap of their last army units.
func _swap(session: CampaignSession, first: int, second: int) -> void:
	var mine: String = _soldier(session, first)
	var theirs: String = _soldier(session, second)
	CampaignService.submit_command(
			HostFill.complete(ProposeSwapCommand.new(first, mine, second, theirs), session)
	)
	CampaignService.submit_command(
			HostFill.complete(AnswerSwapCommand.new(second, first, true, mine, theirs), session)
	)


# Each seat's Start on every map still waiting for it, as that seat sends it. Returns the steps
# whose state differed between host and mirrors, and any refusal.
func _start_every_seat(rig: Rig) -> PackedStringArray:
	var failed: PackedStringArray = []
	for map: CombatSession in rig.session.encounter.get_sessions():
		for seat: int in map.state.seats_to_start.duplicate():
			var reason: String = _act(rig, seat, StartCommand.new(seat), map.session_id)
			_note(failed, reason, "s%d Start %d refused" % [map.session_id, seat])
			_note(failed, _difference(rig), "s%d Start %d" % [map.session_id, seat])
	return failed


# Sends command for seat on the map session_id as that seat does (the host seat's on the host, a
# client's through its mirror), lets the network settle, and returns its refusal: empty when it
# resolved.
func _act(rig: Rig, seat: int, command: Command, session_id: int) -> String:
	if seat == HOST_SEAT:
		return _host_acts(rig, command, session_id)
	var token: int = rig.mirror(seat).submit_combat(command, session_id)
	rig.harness.step_until_idle()
	if token == NetRelayScript.NO_TOKEN:
		return "not sent"
	var settled: Dictionary = rig.settles[seat]
	if not settled.has(token):
		return "never settled"
	return str(settled[token])


# Resolves command on the host's map session_id (a host seat's command, or a fixture standing for
# the battle's own events), lets the network settle, and returns its refusal; empty when resolved.
# An accepted send makes no map batch (its facts are the encounter's), so only a rejected batch
# for the command's arrival is a refusal.
func _host_acts(rig: Rig, command: Command, session_id: int) -> String:
	var batches: Array[CombatSession.FactBatch] = CampaignService.submit_combat(
			command, session_id
	)
	rig.harness.step_until_idle()
	for batch: CombatSession.FactBatch in batches:
		if batch.is_rejected() and batch.arrival == command.arrival:
			return batch.rejected_reason
	return ""


# Seat's turn for a unit of its on the map session_id, read from its own view of the battle: the
# driver's attack or walk for unit_id, or its first unit that can act when unit_id is empty.
func _play_unit(rig: Rig, seat: int, session_id: int, unit_id: String = "") -> String:
	var view: CombatEncounter = rig.view(seat)
	var map: CombatSession = null if view == null else view.get_session(session_id)
	if map == null:
		return "seat %d has no view of s%d" % [seat, session_id]
	var acting: PackedStringArray = TurnInputModel.acting_units(map, seat)
	var unit: String = unit_id
	if unit.is_empty() and not acting.is_empty():
		unit = acting[0]
	if not acting.has(unit):
		return "seat %d has no unit to act on s%d (%s)" % [seat, session_id, acting]
	var turn: UnitTurnCommand = _driver._turn_for(map, unit)
	turn.seat = seat
	return _act(rig, seat, turn, session_id)


# Ends map's combat with winner, outside any command, as the objectives check would; sent as its
# own batch.
func _end_map(rig: Rig, map: CombatSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	map.engine.record(ended)
	map.flush("test end")
	rig.harness.step_until_idle()


# Wins every map still being fought, then ends the battle on the host as its screen does once
# every map has ended, and lets the network settle.
func _end_battle(rig: Rig, failed: PackedStringArray) -> void:
	for map: CombatSession in rig.session.encounter.get_sessions():
		if not map.is_finished:
			_end_map(rig, map, PLAYER)
			_note(failed, _difference(rig), "s%d won" % [map.session_id])
	if CampaignService.end_battle() == null:
		failed.append("the battle didn't end")
	rig.harness.step_until_idle()


# Each client's board (a BattleView bound to its mirror's map session_id) shows unit_id's token,
# and its unit detail its owner's heirlooms, as the host's board and detail do, with no mismatch;
# a profile shown wrong, on the token or its info's mark, is a mismatch.
func _check_board(rig: Rig, tag: String, session_id: int, unit_id: String) -> void:
	var host_map: CombatSession = rig.session.encounter.get_session(session_id)
	var host_view: BattleView = _bound_view(host_map)
	var token: String = _token_text(host_view, unit_id)
	var effects: String = _effects_text(host_map, unit_id)
	var differences: PackedStringArray = host_view.mismatches()
	host_view.free()
	var owner_view: BattleView = null
	for index: int in rig.clients():
		var map: CombatSession = rig.view(index).get_session(session_id)
		var view: BattleView = _bound_view(map)
		if _token_text(view, unit_id) != token:
			differences.append("client %d shows %s" % [index, _token_text(view, unit_id)])
		if _effects_text(map, unit_id) != effects:
			differences.append("client %d lists %s" % [index, _effects_text(map, unit_id)])
		differences.append_array(view.mismatches())
		if map.state.seat_of(unit_id) == index:
			owner_view = view
		else:
			view.free()
	_check("%s each client's board shows the visitor and its owner's heirlooms as the host's" % [
		tag,
	], (
			not unit_id.is_empty() and not token.contains("no token")
			and effects.contains(_heirloom_name()) and differences.is_empty()
	), "%s; %s; %s" % [token, effects, "; ".join(differences)])
	if owner_view == null:
		_check("%s the visitor's owner has a board of it" % [tag], false)
		return
	var shown: UnitToken = owner_view.token_of(unit_id)
	var held: WeaponTriangle.Profile = shown.profile
	var other: WeaponTriangle.Profile = (
			WeaponTriangle.Profile.POWER if held != WeaponTriangle.Profile.POWER
			else WeaponTriangle.Profile.NIMBLE
	)
	shown.show_profile(other)
	var on_token: PackedStringArray = owner_view.mismatches()
	shown.show_profile(held)
	shown.info.get_profile_mark().show_profile(other)
	var on_mark: PackedStringArray = owner_view.mismatches()
	shown.info.get_profile_mark().show_profile(held)
	var restored: PackedStringArray = owner_view.mismatches()
	owner_view.free()
	_check("%s a token or profile mark showing another weapon profile is a mismatch" % [tag], (
			_has_line(on_token, "%s shows the" % [unit_id])
			and _has_line(on_mark, "%s's profile mark" % [unit_id])
			and restored.is_empty()
	), "%s / %s / %s" % ["; ".join(on_token), "; ".join(on_mark), "; ".join(restored)])


# A board bound to map, in the tree, settled.
func _bound_view(map: CombatSession) -> BattleView:
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(map)
	for _frame: int in MAX_SETTLE_FRAMES:
		if view.is_settled():
			break
		view.advance(FRAME)
	return view


# What view's token of unit_id shows, as text to compare peers by.
func _token_text(view: BattleView, unit_id: String) -> String:
	var token: UnitToken = view.token_of(unit_id)
	if token == null:
		return "no token"
	return JSON.stringify([
		token.tile, token.side, token.hp, token.max_hp, token.stance, token.stance_max,
		token.block, token.profile, token.has_acted,
	])


# The heirloom lines unit_id's detail lists on map (its owner's army effects there), as text.
func _effects_text(map: CombatSession, unit_id: String) -> String:
	var detail: UnitDetailViewModel = UnitDetailViewModel.build(map, unit_id)
	if detail == null:
		return "no detail"
	var lines: Array = []
	for line: UnitDetailViewModel.EffectLine in detail.heirlooms:
		lines.append([line.label, line.text, line.charges_left])
	return JSON.stringify(lines)


# FOLLOWING_HEIRLOOM's display name, as its effect lines are labelled.
func _heirloom_name() -> String:
	var definition: HeirloomDefinition = EffectCatalog.index().heirloom(FOLLOWING_HEIRLOOM)
	return FOLLOWING_HEIRLOOM if definition == null else definition.display_name


# The first way a client's battle differs from the host's: its encounter or a map; empty when
# every mirror is equal.
func _difference(rig: Rig) -> String:
	var host: CombatEncounter = rig.session.encounter
	for index: int in rig.clients():
		var copy: CombatEncounter = rig.view(index)
		if host == null or copy == null:
			return "client %d has no battle" % [index]
		if copy.state_hash() != host.state_hash():
			return "client %d's encounter differs" % [index]
		for map: CombatSession in host.get_sessions():
			if copy.get_session(map.session_id).state_hash() != map.state_hash():
				return "client %d's map %d differs" % [index, map.session_id]
	return ""


# The first way a client differs from the host after the battle's end: a battle still open, its
# run, or a seat's results; empty when every client is equal.
func _results_difference(rig: Rig) -> String:
	for index: int in rig.clients():
		var copy: CampaignSession = rig.mirror(index).session
		if copy == null or copy.run == null:
			return "client %d has no run" % [index]
		if copy.encounter != null:
			return "client %d's battle is still open" % [index]
		if RunStateCases.run_text(copy.run) != RunStateCases.run_text(rig.session.run):
			return "client %d's run differs" % [index]
		for seat: int in rig.session.run.seat_numbers():
			var host_text: String = _results_text(rig.session, seat)
			if _results_text(copy, seat) != host_text:
				return "client %d's results for seat %d differ: %s / %s" % [
					index, seat, _results_text(copy, seat), host_text,
				]
	return ""


# Every check that a batch's hash matched as a client applied it, and every step's comparison.
func _check_batches(rig: Rig, tag: String, failed: PackedStringArray) -> void:
	_check("%s every client matches every batch it applies and every step" % [tag], (
			rig.checks > 0 and rig.failures.is_empty() and failed.is_empty()
	), "%d checks; %s; %s" % [rig.checks, rig.failures, failed])


# Each distinct answer of the host and every mirror to whether the map session_id's aid is called.
func _aid_everywhere(rig: Rig, session_id: int) -> Array[bool]:
	var answers: Array[bool] = []
	for battle: CombatEncounter in rig.battles():
		var answer: bool = battle.is_aid_called(session_id)
		if not answers.has(answer):
			answers.append(answer)
	return answers


# Each distinct answer of the host and every mirror to whether the map session_id is frozen.
func _frozen_everywhere(rig: Rig, session_id: int) -> Array[bool]:
	var answers: Array[bool] = []
	for battle: CombatEncounter in rig.battles():
		var answer: bool = battle.is_frozen(session_id)
		if not answers.has(answer):
			answers.append(answer)
	return answers


# Each distinct answer of the host and every mirror to whether the run is lost.
func _lost_everywhere(rig: Rig) -> Array[bool]:
	var answers: Array[bool] = []
	for battle: CombatEncounter in rig.battles():
		var answer: bool = battle.is_run_lost()
		if not answers.has(answer):
			answers.append(answer)
	return answers


# Whether unit_id is on its way to another map on the host and every mirror.
func _in_transit_everywhere(rig: Rig, unit_id: String) -> bool:
	for battle: CombatEncounter in rig.battles():
		if unit_id.is_empty() or not battle.units_in_transit().has(unit_id):
			return false
	return true


# Whether unit_id stands on the map session_id on the host and every mirror.
func _landed_everywhere(rig: Rig, unit_id: String, session_id: int) -> bool:
	for battle: CombatEncounter in rig.battles():
		var map: CombatSession = battle.session_of_unit(unit_id)
		if (
				unit_id.is_empty() or map == null or map.session_id != session_id
				or not map.state.has_unit(unit_id)
		):
			return false
	return true


# Seat's surviving units on its won map that could be sent: there and not on their way, its
# commander last.
func _sendable(battle: CombatEncounter, map: CombatSession, seat: int) -> PackedStringArray:
	var found: PackedStringArray = []
	var commander: String = map.state.commander_of(seat)
	for unit_id: String in map.state.units_of(PLAYER):
		if (
				map.state.seat_of(unit_id) == seat and unit_id != commander
				and battle.session_of_unit(unit_id) == map
				and not battle.units_in_transit().has(unit_id)
		):
			found.append(unit_id)
	if map.state.has_unit(commander):
		found.append(commander)
	return found


# Seat's first player unit on map; empty when it has none there.
func _unit_of_seat(map: CombatSession, seat: int) -> String:
	for unit_id: String in map.state.units_of(PLAYER):
		if map.state.seat_of(unit_id) == seat:
			return unit_id
	return ""


# The last unit of seat's army: never its commander.
func _soldier(session: CampaignSession, seat: int) -> String:
	var army: Array[UnitInstance] = session.run.seat_run(seat).army
	return army[army.size() - 1].instance_id


# Adds step to failed when difference isn't empty.
func _note(failed: PackedStringArray, difference: String, step: String) -> void:
	if not difference.is_empty():
		failed.append("%s: %s" % [step, difference])


func _stop(rig: Rig) -> void:
	for mirror: ClientMirror in rig.mirrors:
		if mirror != null:
			mirror.close()
	rig.harness.stop()
	_end_run()


func _end_run() -> void:
	if SaveService.has_multiplayer_campaign():
		SaveService.abandon_run(CampaignData.Mode.MULTIPLAYER)
	SaveService.take_ended_run()
	SaveService.close_save_file()
	SaveFile.delete_folder("user://saves/")


func _has_test_user_dir() -> bool:
	for part: String in OS.get_user_data_dir().split("/"):
		if part.begins_with("bandit_bash_tests"):
			return true
	return false


# What seat's victory sequence would show on of, as text to compare peers by: the loss, the
# grades and gold, each unit's XP award, the fallen, the level-ups and the item pick.
static func _results_text(of: CampaignSession, seat: int) -> String:
	var model: CombatResultsModel = CombatResultsModel.build(of, seat)
	if model == null:
		return "no results"
	var grades: Dictionary = {}
	if model.grades != null:
		grades = model.grades.capture()
	var pick: Dictionary = {}
	if model.pick != null:
		pick = model.pick.capture()
	var xp: Array = []
	for line: CombatResultsModel.XpLine in model.xp_lines:
		xp.append([line.unit_id, line.name, line.level, line.xp, line.award.capture()])
	var fallen: Array = []
	for line: CombatResultsModel.XpLine in model.fallen_lines:
		fallen.append([line.unit_id, line.name])
	var levels: Array = []
	for line: CombatResultsModel.LevelUpLine in model.level_up_lines:
		levels.append([line.unit_id, line.level, line.gains])
	return JSON.stringify([
		model.is_lost, model.is_boss, model.gold_held, model.standout_name, grades, xp, fallen,
		levels, pick,
	])


# unit_id's XP award in seat's results on of; null when it earned none.
static func _award_of(of: CampaignSession, seat: int, unit_id: String) -> XpAward:
	var model: CombatResultsModel = CombatResultsModel.build(of, seat)
	if model == null:
		return null
	for line: CombatResultsModel.XpLine in model.xp_lines:
		if line.unit_id == unit_id:
			return line.award
	return null


static func _has_line(lines: PackedStringArray, wanted: String) -> bool:
	for line: String in lines:
		if line.contains(wanted):
			return true
	return false


static func _ignore(_case_name: String, _passed: bool, _detail: String = "") -> void:
	pass



# One case's peers: the host's session, the harness, each branch's relay, mirror and settled
# tokens (token to reason), every batch hash a client checked and those it didn't match, and the
# largest message of each kind heard (shared by every case).
class Rig:
	extends RefCounted

	var session: CampaignSession = null
	var harness: NetHarness = null
	var relays: Array[Node] = []
	var mirrors: Array[ClientMirror] = []
	var settles: Array[Dictionary] = []
	var checks: int = 0
	var failures: PackedStringArray = []
	var sizes: Dictionary[String, int] = {}

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func mirror(index: int) -> ClientMirror:
		return mirrors[index]

	# The client branches, which are also their seats.
	func clients() -> PackedInt32Array:
		var found: PackedInt32Array = []
		for index: int in range(1, harness.size()):
			found.append(index)
		return found

	# Seat's view of the battle: the host's encounter, or the client's mirror of it.
	func view(seat: int) -> CombatEncounter:
		if seat == HOST_SEAT:
			return session.encounter
		var copy: CampaignSession = mirror(seat).session
		return null if copy == null else copy.encounter

	# The host's battle and every client's, the missing ones left out.
	func battles() -> Array[CombatEncounter]:
		var found: Array[CombatEncounter] = []
		for seat: int in harness.size():
			var battle: CombatEncounter = view(seat)
			if battle != null:
				found.append(battle)
		return found

	# A mirror for client branch index, not started; the checks hear its relay after it.
	func add_mirror(index: int) -> void:
		var client: NetRelayScript = relay(index)
		mirrors[index] = ClientMirror.new(client, session.rng.run_seed)
		client.combat_batch_received.connect(_on_map_batch.bind(index))
		client.encounter_batch_received.connect(_on_encounter_batch.bind(index))
		client.campaign_batch_received.connect(_on_campaign_batch)
		client.sync_received.connect(_on_sync)
		client.command_settled.connect(_on_settled.bind(index))

	func _on_map_batch(wire: Array, index: int) -> void:
		_measure("combat_batch", NetRelayScript._size_of([wire]))
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = view(index)
		if (
				batch == null or battle == null or batch.is_rejected()
				or batch.state_hash == CombatSession.NO_HASH
		):
			return
		var map: CombatSession = battle.get_session(batch.session_id)
		if map == null or map.last_seq() != batch.last_seq():
			return
		checks += 1
		if map.state_hash() != batch.state_hash:
			failures.append("client %d s%d#%d" % [index, batch.session_id, map.last_seq()])

	func _on_encounter_batch(wire: Array, index: int) -> void:
		_measure("encounter_batch", NetRelayScript._size_of([wire]))
		var batch: CombatSession.FactBatch = CombatSession.FactBatch.from_wire(wire)
		var battle: CombatEncounter = view(index)
		if batch == null or battle == null or batch.state_hash == CombatSession.NO_HASH:
			return
		checks += 1
		if battle.state_hash() != batch.state_hash:
			failures.append("client %d encounter #%d" % [index, batch.last_seq()])

	func _on_campaign_batch(facts: Array, run: Dictionary) -> void:
		_measure("campaign_batch", NetRelayScript._size_of([NetRelayScript._pack([facts, run])]))

	func _on_sync(run: Dictionary, battle: Dictionary, facts: Array, screen: int) -> void:
		_measure("sync", NetRelayScript._size_of([
			NetRelayScript._pack([run, battle, facts, screen]),
		]))

	func _on_settled(token: int, reason: String, index: int) -> void:
		settles[index][token] = reason

	func _measure(kind: String, size: int) -> void:
		var largest: int = sizes.get(kind, 0)
		sizes[kind] = maxi(largest, size)


# Defeats each unit through CombatState.defeat: the battle's own blow, standing for a fall the
# enemies or the darkness deal, on the host only.
class FellFixture:
	extends Command

	var unit_ids: PackedStringArray = []

	func _init(owner_seat: int, defeated: Array[String]) -> void:
		seat = owner_seat
		unit_ids = PackedStringArray(defeated)

	func get_label() -> String:
		return "fell"

	func resolve(session: CombatSession) -> void:
		for unit_id: String in unit_ids:
			session.state.defeat(session.engine, unit_id, "")
