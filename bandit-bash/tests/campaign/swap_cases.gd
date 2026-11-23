# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## Co-op unit swap rules for tests/campaign/run_all.gd ([ProposeSwapCommand], [AnswerSwapCommand],
## [WithdrawSwapCommand], [UnitSwap]), on real 2-, 3- and 4-seat runs: propose and accept, decline,
## withdraw an open proposal and an accepted swap; every refusal, each changing nothing; an accept
## ending the other proposals naming its units; a unit leaving its army ending its proposal and
## swap in the same batch; a quit losing an open proposal and keeping an accepted swap; run_flow
## version 1 loading with none; bad swap data refused; the three wire forms through JSON and every
## malformed one refused; solo unchanged.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const RUN_SEED: int = 0x0C05
const SEAT_COUNTS: Array[int] = [2, 4]
# The reason a test dismissal records, as an event's id would be.
const DISMISS_SOURCE: String = "test_dismissal"

var _report: Callable


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	for seat_count: int in SEAT_COUNTS:
		_test_propose_and_accept(seat_count)
		_test_decline(seat_count)
		_test_withdraw(seat_count)
		_test_refusals(seat_count)
	_test_accept_ends_others()
	_test_unit_leaves()
	_test_quit()
	_test_flow_version_1()
	_test_bad_swap_data()
	_test_wire_forms()
	_test_malformed_wire()
	_test_solo_unchanged()


# Seat 0 proposes to the last seat, which accepts: SWAP_PROPOSED then SWAP_ACCEPTED, the proposal
# open between them and saved as a swap after.
func _test_propose_and_accept(seat_count: int) -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var run: CampaignRunState = made.run
	var last: int = seat_count - 1
	var mine: String = _unit_of(run, 0)
	var theirs: String = _unit_of(run, last)
	var proposed: CampaignBatch = made.submit(ProposeSwapCommand.new(0, mine, last, theirs))
	var is_open: bool = run.swap_proposals.size() == 1 and run.flow.swaps.is_empty()
	var accepted: CampaignBatch = made.submit(AnswerSwapCommand.new(last, 0, true, mine, theirs))
	var label: String = "swap %d seats" % [seat_count]
	_check("%s: a proposal records SWAP_PROPOSED and waits, unsaved" % [label], (
			Fixture.kinds(proposed) == [CampaignFact.Kind.SWAP_PROPOSED]
			and _is_fact(proposed.facts[0], 0, mine, theirs, last)
			and is_open
	), proposed.rejected_reason)
	var swap: UnitSwap = run.flow.swaps[0] if run.flow.swaps.size() == 1 else null
	_check("%s: an accept records SWAP_ACCEPTED and saves the swap" % [label], (
			Fixture.kinds(accepted) == [CampaignFact.Kind.SWAP_ACCEPTED]
			and _is_fact(accepted.facts[0], last, theirs, mine, 0)
			and run.swap_proposals.is_empty()
			and swap != null
			and swap.seat_a == 0 and swap.unit_a == mine
			and swap.seat_b == last and swap.unit_b == theirs
			and (run.flow.capture()["swaps"] as Array).size() == 1
	), accepted.rejected_reason)


# The partner declines: SWAP_ENDED "declined", and nothing is saved.
func _test_decline(seat_count: int) -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var run: CampaignRunState = made.run
	var mine: String = _unit_of(run, 0)
	var theirs: String = _unit_of(run, 1)
	made.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	var declined: CampaignBatch = made.submit(AnswerSwapCommand.new(1, 0, false, mine, theirs))
	_check("decline %d seats: SWAP_ENDED declined, no swap" % [seat_count], (
			Fixture.kinds(declined) == [CampaignFact.Kind.SWAP_ENDED]
			and _is_fact(declined.facts[0], 0, mine, theirs, 1, UnitSwap.END_DECLINED)
			and run.swap_proposals.is_empty()
			and run.flow.swaps.is_empty()
	), declined.rejected_reason)


# The proposer withdraws its open proposal; later the partner withdraws an accepted swap.
func _test_withdraw(seat_count: int) -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var run: CampaignRunState = made.run
	var mine: String = _unit_of(run, 0)
	var theirs: String = _unit_of(run, 1)
	made.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	var pulled: CampaignBatch = made.submit(WithdrawSwapCommand.new(0, 1))
	var proposal_gone: bool = run.swap_proposals.is_empty()
	made.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	made.submit(AnswerSwapCommand.new(1, 0, true, mine, theirs))
	var undone: CampaignBatch = made.submit(WithdrawSwapCommand.new(1, 0))
	_check("withdraw %d seats: an open proposal by its proposer, a swap by its partner" % [
		seat_count,
	], (
			Fixture.kinds(pulled) == [CampaignFact.Kind.SWAP_ENDED]
			and _is_fact(pulled.facts[0], 0, mine, theirs, 1, UnitSwap.END_WITHDRAWN)
			and proposal_gone
			and Fixture.kinds(undone) == [CampaignFact.Kind.SWAP_ENDED]
			and _is_fact(undone.facts[0], 0, mine, theirs, 1, UnitSwap.END_WITHDRAWN)
			and run.flow.swaps.is_empty()
	), "%s / %s" % [pulled.rejected_reason, undone.rejected_reason])


# Every refusal of the swaps decisions, each changing nothing and recording nothing.
func _test_refusals(seat_count: int) -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, seat_count)
	var run: CampaignRunState = made.run
	var last: int = seat_count - 1
	var mine: String = _unit_of(run, 0)
	var spare: String = _unit_of(run, 0, 1)
	var theirs: String = _unit_of(run, 1)
	var commander: String = run.seat_run(0).commander_id
	var label: String = "refused %d seats" % [seat_count]
	var before: String = _run_text(run)
	var facts: int = run.fact_log.size()
	var reasons: Dictionary[String, String] = {
		"itself": _reason(made, ProposeSwapCommand.new(0, mine, 0, spare)),
		"a stranger seat": _reason(made, ProposeSwapCommand.new(0, mine, 7, theirs)),
		"the commander": _reason(made, ProposeSwapCommand.new(0, commander, 1, theirs)),
		"the partner's commander": _reason(made, ProposeSwapCommand.new(
				0, mine, 1, run.seat_run(1).commander_id
		)),
		"a teammate's unit as its own": _reason(made, ProposeSwapCommand.new(0, theirs, 1, mine)),
		"no such unit": _reason(made, ProposeSwapCommand.new(0, "unit:none", 1, theirs)),
		"an answer with no proposal": _reason(
				made, AnswerSwapCommand.new(1, 0, true, mine, theirs)
		),
		"a withdraw with none": _reason(made, WithdrawSwapCommand.new(0, 1)),
	}
	var expected: Dictionary[String, String] = {
		"itself": "a swap is with a teammate",
		"a stranger seat": "seat 7 isn't in the run",
		"the commander": "a commander stays on its own map",
		"the partner's commander": "a commander stays on its own map",
		"a teammate's unit as its own": "seat 0 has no living unit %s in its army" % [theirs],
		"no such unit": "seat 0 has no living unit unit:none in its army",
		"an answer with no proposal": "seat 0 has no open proposal to seat 1",
		"a withdraw with none": "seat 0 has no swap or proposal with seat 1",
	}
	_check_reasons(label + " (nothing open)", reasons, expected)
	_check("%s: nothing changed" % [label], (
			_run_text(run) == before and run.fact_log.size() == facts
			and run.swap_proposals.is_empty()
	))

	made.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	before = _run_text(run)
	facts = run.fact_log.size()
	reasons = {
		"a second proposal for the pair": _reason(
				made, ProposeSwapCommand.new(0, spare, 1, _unit_of(run, 1, 1))
		),
		"the reverse proposal": _reason(made, ProposeSwapCommand.new(1, theirs, 0, mine)),
		"an answer from the proposer": _reason(
				made, AnswerSwapCommand.new(0, 0, true, mine, theirs)
		),
		"an answer naming other units": _reason(
				made, AnswerSwapCommand.new(1, 0, true, spare, theirs)
		),
	}
	expected = {
		"a second proposal for the pair": "seat 0 and seat 1 already have a swap or a proposal",
		"the reverse proposal": "seat 1 and seat 0 already have a swap or a proposal",
		"an answer from the proposer": "seat 0 has no open proposal to seat 0",
		"an answer naming other units": "seat 0's proposal names other units now",
	}
	if seat_count > 2:
		reasons["an answer from a third seat"] = _reason(
				made, AnswerSwapCommand.new(last, 0, true, mine, theirs)
		)
		expected["an answer from a third seat"] = "seat 0 has no open proposal to seat %d" % [last]
		reasons["a withdraw by a third seat"] = _reason(made, WithdrawSwapCommand.new(last, 0))
		expected["a withdraw by a third seat"] = (
				"seat %d has no swap or proposal with seat 0" % [last]
		)
	_check_reasons(label + " (a proposal open)", reasons, expected)
	_check("%s: the open proposal stands unchanged" % [label], (
			_run_text(run) == before and run.fact_log.size() == facts
			and run.swap_proposals.size() == 1
	))

	made.submit(AnswerSwapCommand.new(1, 0, true, mine, theirs))
	if seat_count > 2:
		var in_swap: String = _reason(
				made, ProposeSwapCommand.new(last, _unit_of(run, last), 0, mine)
		)
		_check("%s: a unit already in an accepted swap" % [label], (
				in_swap == "%s is already in a swap" % [mine]
		), in_swap)
	var again: String = _reason(made, ProposeSwapCommand.new(0, spare, 1, _unit_of(run, 1, 1)))
	_check("%s: a pair with an accepted swap" % [label], (
			again == "seat 0 and seat 1 already have a swap or a proposal"
	), again)

	Fixture.choose(made, run.next_nodes()[0])
	var inside: Dictionary[String, String] = {
		"propose": _reason(made, ProposeSwapCommand.new(0, spare, last, _unit_of(run, last, 1))),
		"answer": _reason(made, AnswerSwapCommand.new(1, 0, true, mine, theirs)),
		"withdraw": _reason(made, WithdrawSwapCommand.new(0, 1)),
	}
	var on_map_only: Dictionary[String, String] = {
		"propose": "swaps are agreed on the campaign map",
		"answer": "swaps are agreed on the campaign map",
		"withdraw": "swaps are agreed on the campaign map",
	}
	_check_reasons(label + " (inside a node)", inside, on_map_only)
	_check("%s: inside a node the swap stands" % [label], run.flow.swaps.size() == 1)


# With three seats, seat 0's unit is proposed to seats 1 and 2; seat 1 accepts, which ends seat
# 0's other proposal (it names the same unit) and seat 2's proposal naming seat 1's unit.
func _test_accept_ends_others() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var run: CampaignRunState = made.run
	var shared: String = _unit_of(run, 0)
	var ones: String = _unit_of(run, 1)
	var twos: String = _unit_of(run, 2)
	made.submit(ProposeSwapCommand.new(0, shared, 1, ones))
	made.submit(ProposeSwapCommand.new(0, shared, 2, twos))
	made.submit(ProposeSwapCommand.new(2, twos, 1, ones))
	var accepted: CampaignBatch = made.submit(AnswerSwapCommand.new(1, 0, true, shared, ones))
	_check("accept: the other open proposals naming either unit end, unit_left", (
			Fixture.kinds(accepted) == [
				CampaignFact.Kind.SWAP_ACCEPTED,
				CampaignFact.Kind.SWAP_ENDED,
				CampaignFact.Kind.SWAP_ENDED,
			]
			and _is_fact(accepted.facts[1], 0, shared, twos, 2, UnitSwap.END_UNIT_LEFT)
			and _is_fact(accepted.facts[2], 2, twos, ones, 1, UnitSwap.END_UNIT_LEFT)
			and run.swap_proposals.is_empty()
			and run.flow.swaps.size() == 1
	), accepted.rejected_reason)


# A command that dismisses a unit named in an accepted swap and in an open proposal ends both in
# its own batch (proposals first); a unit that fell ends its swap at the next command.
func _test_unit_leaves() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var run: CampaignRunState = made.run
	var leaving: String = _unit_of(run, 0)
	var ones: String = _unit_of(run, 1)
	var twos: String = _unit_of(run, 2)
	made.submit(ProposeSwapCommand.new(0, leaving, 1, ones))
	made.submit(AnswerSwapCommand.new(1, 0, true, leaving, ones))
	made.submit(ProposeSwapCommand.new(2, twos, 0, _unit_of(run, 0, 1)))
	var dismissed: CampaignBatch = made.submit(DismissFixture.new(0, leaving))
	var ended: Array[CampaignFact] = _of_kind(dismissed, CampaignFact.Kind.SWAP_ENDED)
	_check("leaves: a dismissed unit's swap ends in the dismissal's batch, unit_left", (
			not dismissed.is_rejected()
			and ended.size() == 1
			and _is_fact(ended[0], 0, leaving, ones, 1, UnitSwap.END_UNIT_LEFT)
			and run.flow.swaps.is_empty()
			and run.swap_proposals.size() == 1
	), dismissed.rejected_reason)
	var proposed_unit: String = ""
	if run.swap_proposals.size() == 1:
		proposed_unit = run.swap_proposals[0].unit_b
	var holder: SeatRun = run.seat_run(0)
	var fallen: UnitInstance = holder.unit(proposed_unit)
	if fallen != null:
		holder.army.erase(fallen)
		holder.fallen.append(fallen)
	var next: CampaignBatch = made.submit(ProposeSwapCommand.new(1, ones, 2, _unit_of(run, 2, 1)))
	var proposal_end: Array[CampaignFact] = _of_kind(next, CampaignFact.Kind.SWAP_ENDED)
	_check("leaves: a fallen unit's proposal ends at the next command", (
			fallen != null
			and proposal_end.size() == 1
			and proposal_end[0].target_id == proposed_unit
			and proposal_end[0].definition_id == UnitSwap.END_UNIT_LEFT
			and run.swap_proposals.size() == 1
			and run.swap_proposals[0].seat_a == 1
	), next.rejected_reason)


# A quit with one accepted swap and one open proposal: Continue keeps the swap, loses the proposal.
func _test_quit() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 4)
	var run: CampaignRunState = made.run
	made.submit(ProposeSwapCommand.new(0, _unit_of(run, 0), 1, _unit_of(run, 1)))
	made.submit(AnswerSwapCommand.new(1, 0, true, _unit_of(run, 0), _unit_of(run, 1)))
	made.submit(ProposeSwapCommand.new(2, _unit_of(run, 2), 3, _unit_of(run, 3)))
	var copied: CampaignRunState = Fixture.through_json(run)
	var kept: UnitSwap = (
			copied.flow.swaps[0] if copied != null and copied.flow.swaps.size() == 1 else null
	)
	_check("quit: Continue keeps the accepted swap and loses the open proposal", (
			copied != null
			and kept != null
			and JSON.stringify(kept.capture()) == JSON.stringify(run.flow.swaps[0].capture())
			and copied.swap_proposals.is_empty()
			and run.swap_proposals.size() == 1
	))
	var resumed: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, run.seat_numbers()
	)
	resumed.run = copied
	var answer: String = (
			_reason(resumed, AnswerSwapCommand.new(3, 2, true, _unit_of(run, 2), _unit_of(run, 3)))
			if copied != null else ""
	)
	_check("quit: the lost proposal can't be answered after Continue", (
			answer == "seat 2 has no open proposal to seat 3"
	), answer)


# A version 1 run_flow section, saved before swaps, migrates as it is and loads with none; the
# section now saves at version 2.
func _test_flow_version_1() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 2)
	var data: Dictionary = Fixture.json(made.run.flow.capture())
	data.erase("swaps")
	var sections: RunSaveSections = RunSaveSections.new()
	var map_ok: Error = sections.map.restore(Fixture.json(made.run.capture_map()))
	var migrated: Error = sections.flow.migrate(data, 1)
	var restored: Error = sections.flow.restore(data)
	var read: RunFlow = RunFlow.new()
	_check("version 1: run_flow migrates as it is and loads with no swaps", (
			map_ok == OK
			and migrated == OK
			and restored == OK
			and read.restore(data) == OK
			and read.swaps.is_empty()
			and sections.flow.get_version() == RunSaveSections.FLOW_VERSION
			and RunSaveSections.FLOW_VERSION == 2
			and sections.map.get_version() == RunSaveSections.MAP_VERSION
	))


# Swap data that names one seat twice, an empty unit, a negative seat, or two swaps sharing a pair
# or a unit is refused, changing nothing.
func _test_bad_swap_data() -> void:
	var made: CampaignSession = Fixture.session(RUN_SEED, 3)
	var base: Dictionary = Fixture.json(made.run.flow.capture())
	var good: Dictionary = UnitSwap.new(0, "unit:1", 1, "unit:2").capture()
	var bad_lists: Array[Array] = [
		[UnitSwap.new(0, "unit:1", 0, "unit:2").capture()],
		[UnitSwap.new(0, "", 1, "unit:2").capture()],
		[UnitSwap.new(-1, "unit:1", 1, "unit:2").capture()],
		[UnitSwap.new(0, "unit:1", 1, "unit:1").capture()],
		[good, UnitSwap.new(1, "unit:3", 0, "unit:4").capture()],
		[good, UnitSwap.new(2, "unit:1", 1, "unit:5").capture()],
		["not a swap"],
	]
	var refused: int = 0
	var flow: RunFlow = RunFlow.new()
	print("    (%d errors about bad swaps follow)" % [bad_lists.size() + 1])
	for list: Array in bad_lists:
		var data: Dictionary = base.duplicate(true)
		data["swaps"] = list
		if flow.restore(data) == ERR_INVALID_DATA:
			refused += 1
	var not_a_list: Dictionary = base.duplicate(true)
	not_a_list["swaps"] = {}
	if flow.restore(not_a_list) == ERR_INVALID_DATA:
		refused += 1
	var fine: Dictionary = base.duplicate(true)
	fine["swaps"] = Fixture.json({"list": [good]})["list"]
	_check("bad data: every bad swap list is refused; a good one, through JSON, loads", (
			refused == bad_lists.size() + 1
			and flow.restore(fine) == OK
			and flow.swaps.size() == 1
			and flow.swaps[0].unit_b == "unit:2"
	), "%d refused" % [refused])


# Each command goes through JSON to an equal command, and resolves on a fresh run as the original.
func _test_wire_forms() -> void:
	var commands: Array[CampaignCommand] = [
		ProposeSwapCommand.new(0, "unit:3", 1, "unit:9"),
		AnswerSwapCommand.new(1, 0, true, "unit:3", "unit:9"),
		AnswerSwapCommand.new(1, 0, false, "unit:3", "unit:9"),
		WithdrawSwapCommand.new(1, 0),
	]
	var problems: PackedStringArray = []
	for command: CampaignCommand in commands:
		command.arrival = 4
		var wire: Array = command.to_wire()
		var decoded: CampaignCommand = CampaignCommand.from_wire(
				JSON.parse_string(JSON.stringify(wire)) as Array
		)
		if (
				decoded == null
				or decoded.get_script() != command.get_script()
				or decoded.to_wire() != wire
				or decoded.get_label() != command.get_label()
		):
			problems.append(str(wire))
	_check("wire: the three swap commands round-trip through JSON", (
			problems.is_empty()
			and commands[0].to_wire() == ["swap_propose", 0, 4, "unit:3", 1, "unit:9"]
			and commands[1].to_wire() == ["swap_answer", 1, 4, 0, true, "unit:3", "unit:9"]
			and commands[3].to_wire() == ["swap_withdraw", 1, 4, 0]
	), str(problems))


# Every malformed swap wire form is refused with one error.
func _test_malformed_wire() -> void:
	var forms: Array[Array] = [
		["swap_propose", 0, 0, "unit:3", 1],
		["swap_propose", 0, 0, 3, 1, "unit:9"],
		["swap_propose", 0, 0, "unit:3", -2, "unit:9"],
		["swap_propose", 0, 0, "unit:3", 1.5, "unit:9"],
		["swap_answer", 1, 0, 0, 1, "unit:3", "unit:9"],
		["swap_answer", 1, 0, 0, true, "unit:3"],
		["swap_answer", 1, 0, "0", true, "unit:3", "unit:9"],
		["swap_withdraw", 1, 0],
		["swap_withdraw", 1, 0, null],
		["swap_withdraw", 1, 0, -3],
	]
	var accepted: PackedStringArray = []
	print("    (%d errors about malformed wire data follow)" % [forms.size()])
	for form: Array in forms:
		if CampaignCommand.from_wire(form) != null:
			accepted.append(str(form))
	_check("wire: every malformed swap form is refused", accepted.is_empty(), str(accepted))


# A solo run has no swaps: every command is refused, the flow saves an empty list, and the battle
# request lists no visitor.
func _test_solo_unchanged() -> void:
	var solo: CampaignSession = Fixture.session(RUN_SEED)
	var run: CampaignRunState = solo.run
	var reason: String = _reason(solo, ProposeSwapCommand.new(0, _unit_of(run, 0), 1, ""))
	Fixture.choose(solo, run.next_nodes()[0])
	var request: CampaignSession.BattleRequest = run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	_check("solo: no swap, an empty saved list, no visitor in the request", (
			reason == "a swap needs a teammate"
			and (run.flow.capture()["swaps"] as Array).is_empty()
			and request != null
			and request.armies[0].visitor_seats.is_empty()
			and request.armies[0].unit_instances.size() == run.seat_run(0).army.size()
	), reason)


# The index-th living unit of seat's army that isn't its commander; empty when there is none.
func _unit_of(run: CampaignRunState, seat: int, index: int = 0) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	var found: int = 0
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id == seat_run.commander_id:
			continue
		if found == index:
			return unit.instance_id
		found += 1
	return ""


# Why made refused command; empty when it resolved.
func _reason(made: CampaignSession, command: CampaignCommand) -> String:
	return made.submit(command).rejected_reason


func _is_fact(
		fact: CampaignFact, seat: int, actor: String, target: String, amount: int,
		reason: String = ""
) -> bool:
	return (
			fact.seat == seat and fact.actor_id == actor and fact.target_id == target
			and fact.amount == amount and fact.definition_id == reason
	)


func _of_kind(batch: CampaignBatch, kind: CampaignFact.Kind) -> Array[CampaignFact]:
	var found: Array[CampaignFact] = []
	for fact: CampaignFact in batch.facts:
		if fact.kind == kind:
			found.append(fact)
	return found


func _check_reasons(
		label: String, reasons: Dictionary[String, String], expected: Dictionary[String, String]
) -> void:
	for what: String in expected:
		var got: String = reasons.get(what, "")
		_check("%s: %s" % [label, what], got == expected[what], got)


func _run_text(run: CampaignRunState) -> String:
	var parts: Array = [run.capture_map(), run.flow.capture()]
	for seat: int in run.seat_numbers():
		parts.append(run.seat_run(seat).capture_roster())
	return JSON.stringify(parts)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)


## A campaign command that dismisses one of its seat's units, as an event's or the Guildhall's
## replacement does ([method RunOperations.dismiss]).
class DismissFixture:
	extends CampaignCommand

	var unit_id: String = ""

	func _init(sender: int, unit: String) -> void:
		seat = sender
		unit_id = unit

	func resolve(run: CampaignRunState) -> void:
		RunOperations.dismiss(run, seat, unit_id, DISMISS_SOURCE)
