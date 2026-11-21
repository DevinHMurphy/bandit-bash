# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_wire_cases.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Campaign wire cases for tests/net/run_all.gd ([method CampaignCommand.to_wire],
## [method CampaignBatch.to_wire]): every campaign and event command type goes through JSON to an
## equal command carrying no host-side object, and once the host fills it in through the factories
## its own seat uses, resolves on a fresh session exactly as the original did; nested picks
## round-trip and a teammate's picks never travel; every malformed form is refused with one
## error; a batch round-trips with its facts and its rejection; every [CampaignCommand] class in
## the project has a registered wire type; the fingerprint covers the campaign wire names.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NodeFixture = preload("res://tests/campaign/node_fixture.gd")
const EventFixture = preload("res://tests/events/event_fixture.gd")

const RUN_SEED: int = 0x0C4A3
# Gold every seat holds inside a node, so a purchase or a re-roll is never refused for its price.
const RICH: int = 1000
# Seeds of the offers rolled straight into a run, as a battle's results or a run start would.
const PICK_SEED: int = 10
const KEY_SEED: int = 11
const OFFER_SEED: int = 12
# The goblet's option holding a random weapon grant, the grant's block, and the toll's Fight.
const BREAK_THE_ICE: int = 1
const WEAPON_BLOCK: int = 0
const FIGHT: int = 1
# Every campaign and event command type built so far; a lower count means one went missing.
const COMMAND_TYPES: int = 22
# Classes whose values are plain picks, which travel; any other object is host state.
const PLAIN_CLASSES: PackedStringArray = ["ItemPlacement", "EventChoice"]

var _events: EventFixture = null


func run() -> void:
	print("    (errors from CampaignCommand, CampaignBatch and CampaignFact below are expected)")
	_events = EventFixture.new()
	_check("campaign wire: the event fixture's content loads", _events.is_ready())
	if not _events.is_ready():
		return
	_test_round_trips()
	_test_nested_fields()
	_test_malformed_commands()
	_test_batches()
	_test_registered()
	_test_fingerprint()


# Every scenario's command through JSON and onto a fresh session; then every type has one.
func _test_round_trips() -> void:
	var covered: PackedStringArray = []
	for scenario: Scenario in _scenarios():
		_round_trip(scenario)
		covered.append(scenario.wire_type)
	var missing: PackedStringArray = []
	for class_id: String in _concrete_classes("CampaignCommand"):
		if not covered.has(_wire_type_of(class_id)):
			missing.append(class_id)
	_check("campaign wire: every command type has a round-trip case", (
			missing.is_empty() and covered.size() >= COMMAND_TYPES
	), "missing %s" % [missing])


func _round_trip(scenario: Scenario) -> void:
	var case_name: String = "campaign wire: %s goes through JSON and resolves the same" % [
		scenario.wire_type,
	]
	var host: CampaignSession = scenario.build.call()
	var sent: CampaignCommand = scenario.make.call(host) if host != null else null
	var problem: String = "no session or command" if sent == null else sent.validate(host.run)
	if not problem.is_empty():
		_check(case_name, false, "setup: %s" % [problem])
		return
	var wire: Array = sent.to_wire()
	var decoded: CampaignCommand = CampaignCommand.from_wire(_through_json(wire))
	if (
			decoded == null
			or decoded.get_script() != sent.get_script()
			or decoded.to_wire() != wire
			or decoded.get_label() != sent.get_label()
	):
		_check(case_name, false, "decoded %s from %s" % [
			decoded.to_wire() if decoded != null else null, wire,
		])
		return
	var carried: PackedStringArray = _host_state_of(decoded)
	var fresh: CampaignSession = scenario.build.call()
	var unfilled: String = decoded.validate(fresh.run)
	var filled: CampaignCommand = decoded
	if scenario.fill.is_valid():
		filled = scenario.fill.call(fresh, decoded)
	var host_batch: CampaignBatch = host.submit(sent)
	var fresh_batch: CampaignBatch = fresh.submit(filled)
	var sent_type: String = wire[0]
	_check(case_name, (
			sent_type == scenario.wire_type
			and carried.is_empty()
			and scenario.fill.is_valid() != unfilled.is_empty()
			and not host_batch.is_rejected()
			and host_batch.to_wire() == fresh_batch.to_wire()
			and _run_text(host.run) == _run_text(fresh.run)
	), "carried %s; unfilled \"%s\"; host \"%s\"; fresh \"%s\"" % [
		carried, unfilled, host_batch.rejected_reason, fresh_batch.rejected_reason,
	])


# Every field of the commands with nested picks set away from its default, a teammate's picks
# left behind, and the decoded picks equal to the sent ones.
func _test_nested_fields() -> void:
	var buy: GuildhallPurchaseCommand = GuildhallPurchaseCommand.new(2, 1)
	buy.arrival = 7
	buy.replaced_id = "unit:4"
	buy.hand_over["item:9"] = Guildhall.HandOver.SCRAP
	buy.hand_over["item:3"] = Guildhall.HandOver.RECRUIT
	buy.discard_slot = 2
	var bought: GuildhallPurchaseCommand = (
			CampaignCommand.from_wire(_through_json(buy.to_wire())) as GuildhallPurchaseCommand
	)
	_check("campaign wire: a hand-over round-trips in its order", (
			bought != null
			and bought.to_wire() == buy.to_wire()
			and bought.hand_over.keys() == buy.hand_over.keys()
			and bought.hand_over["item:9"] == Guildhall.HandOver.SCRAP
	), str(bought.to_wire() if bought != null else null))

	var picks: EventChoice = EventChoice.new("unit:2", "item:5")
	picks.placements[3] = ItemPlacement.new(
			ItemPlacement.Destination.EQUIP, "unit:2", true, "item:8"
	)
	picks.placements[0] = ItemPlacement.new(ItemPlacement.Destination.SCRAP)
	picks.rune_discard_slot = 1
	picks.replaced_id = "unit:6"
	var chose: EventOptionCommand = EventOptionCommand.new(1, 2, picks)
	chose.team_choices[0] = EventChoice.new("unit:1")
	var decoded: EventOptionCommand = (
			CampaignCommand.from_wire(_through_json(chose.to_wire())) as EventOptionCommand
	)
	var read: EventChoice = decoded.choice if decoded != null else null
	var placed: ItemPlacement = read.placements.get(3, null) if read != null else null
	_check("campaign wire: an event choice round-trips; a teammate's picks never travel", (
			read != null
			and decoded.to_wire() == chose.to_wire()
			and read.placements.keys() == [3, 0]
			and placed != null
			and placed.destination == ItemPlacement.Destination.EQUIP
			and placed.is_displaced_scrapped
			and placed.convoy_scrap_id == "item:8"
			and read.rune_discard_slot == 1
			and read.replaced_id == "unit:6"
			and decoded.team_choices.is_empty()
	), str(decoded.to_wire() if decoded != null else null))

	var skip: ItemPickCommand = ItemPickCommand.new(0, ItemPickCommand.SKIP)
	var skipped: ItemPickCommand = (
			CampaignCommand.from_wire(_through_json(skip.to_wire())) as ItemPickCommand
	)
	_check("campaign wire: no placement stays none, not a default one", (
			skipped != null and skipped.placement == null and skipped.index == ItemPickCommand.SKIP
	))


# Every type's default with a slot added or taken away, the common slots mistyped or out of range,
# an unknown type; then each type's own fields mistyped or out of range. Each refused with one
# error.
func _test_malformed_commands() -> void:
	var unrefused: Array = []
	for class_id: String in _concrete_classes("CampaignCommand"):
		var wire: Array = _default_of(class_id).to_wire()
		var longer: Array = wire.duplicate()
		longer.append(0)
		var shorter: Array = wire.duplicate()
		shorter.pop_back()
		_note_unrefused(longer, unrefused)
		_note_unrefused(shorter, unrefused)
	_check("campaign wire: one slot too many or too few is refused, for every type", (
			unrefused.is_empty()
	), str(unrefused))

	unrefused.clear()
	for bad: Array in [
		[],
		["no_such_command", 0, 0],
		[5, 0, 0, 3],
		["choose_node", "0", 0, 3],
		["choose_node", 0.5, 0, 3],
		["choose_node", true, 0, 3],
		["choose_node", -2, 0, 3],
		["choose_node", 0, -1, 3],
		["choose_node", 0, 1e300, 3],
	]:
		_note_unrefused(bad, unrefused)
	_check("campaign wire: an unknown type and bad common slots are refused", (
			unrefused.is_empty()
	), str(unrefused))

	unrefused.clear()
	var equip: Array = [ItemPlacement.Destination.EQUIP, "unit:1", false, ""]
	for bad: Array in [
		["choose_node", 0, 0, -2],
		["choose_node", 0, 0, "3"],
		["choose_node", 0, 0, 3.5],
		["armory_purchase", 0, 0, -2, "", false],
		["armory_purchase", 0, 0, 1, 5, false],
		["armory_purchase", 0, 0, 1, "", 1],
		["guildhall_purchase", 0, 0, 0, "", [], -2],
		["guildhall_purchase", 0, 0, 0, "", {}, -1],
		["guildhall_purchase", 0, 0, 0, "u", [["item:1", 7]], -1],
		["guildhall_purchase", 0, 0, 0, "u", [["item:1", 1], ["item:1", 2]], -1],
		["guildhall_purchase", 0, 0, 0, "u", [["item:1", 1, 2]], -1],
		["guildhall_purchase", 0, 0, 0, "u", [[3, 1]], -1],
		["gift_item", 0, 0, "item:1", -2],
		["item_pick", 0, 0, -2, []],
		["item_pick", 0, 0, 0, [9, "", false, ""]],
		["item_pick", 0, 0, 0, [0, "", false]],
		["item_pick", 0, 0, 0, [0, "", 0, ""]],
		["item_pick", 0, 0, 0, "convoy"],
		["key_heirloom", 0, 0, 1],
		["regear", 0, 0, "item:1", "unit:1", 3],
		["regear", 0, 0, "item:1", "unit:1", -1],
		["starting_heirloom", 0, 0, 0, -2, -1, "", []],
		["starting_heirloom", 0, 0, 0, -1, -1, "", equip.slice(1)],
		["treasure", 0, 0, "yes", []],
		["event_chooser", 0, 0, 1.5],
		["event_chooser", 0, 0, -2],
		["event_vote", 0, 0, "1"],
		["event_option", 0, 0, 0, ["u", "w", [[-1, equip]], -1, ""]],
		["event_option", 0, 0, 0, ["u", "w", [[0, equip], [0, equip]], -1, ""]],
		["event_option", 0, 0, 0, ["u", "w", [[0, []]], -1, ""]],
		["event_option", 0, 0, 0, ["u", "w", [], -2, ""]],
		["event_option", 0, 0, 0, ["u", "w", [], -1]],
		["event_option", 0, 0, 0, ["u", 4, [], -1, ""]],
	]:
		_note_unrefused(bad, unrefused)
	_check("campaign wire: each type's fields mistyped or out of range are refused", (
			unrefused.is_empty()
	), str(unrefused))


# A batch that resolved with facts and a rejected one through JSON, then malformed batches.
func _test_batches() -> void:
	var session: CampaignSession = _with_open_armory()
	var resolved: CampaignBatch = session.submit(_armory_purchase(session))
	var rejected: CampaignBatch = session.submit(ChooseNodeCommand.new(0, CampaignGraph.NO_NODE))
	var back: CampaignBatch = CampaignBatch.from_wire(_through_json(resolved.to_wire()))
	var refused: CampaignBatch = CampaignBatch.from_wire(_through_json(rejected.to_wire()))
	_check("campaign wire: a batch round-trips with its facts", (
			not resolved.is_rejected()
			and resolved.facts.size() > 1
			and back != null
			and back.to_wire() == resolved.to_wire()
			and back.facts[0].kind == resolved.facts[0].kind
	), "%s / %s" % [resolved.rejected_reason, back.to_wire() if back != null else null])
	_check("campaign wire: a rejected batch round-trips with its rejection", (
			rejected.is_rejected()
			and refused != null
			and refused.is_rejected()
			and refused.rejected_reason == rejected.rejected_reason
			and refused.facts.is_empty()
			and refused.to_wire() == rejected.to_wire()
	), rejected.rejected_reason)
	if resolved.facts.is_empty():
		return

	var fact_wire: Array = resolved.facts[0].to_wire()
	# Each malformed batch and how many lines refusing it logs: a fact CampaignFact.from_wire()
	# refuses warns there too.
	var cases: Array = [
		[[], 1],
		[[0, 1, "label", ""], 1],
		[[0, 1, "label", "", [], 0], 1],
		[["0", 1, "label", "", []], 1],
		[[0, 1.5, "label", "", []], 1],
		[[-2, 1, "label", "", []], 1],
		[[0, -1, "label", "", []], 1],
		[[0, 1, 3, "", []], 1],
		[[0, 1, "label", false, []], 1],
		[[0, 1, "label", "", {}], 1],
		[[0, 1, "label", "", ["fact"]], 1],
		[[0, 1, "label", "refused", [fact_wire]], 1],
		[[0, 1, "label", "", [fact_wire.slice(1)]], 2],
	]
	var unrefused: Array = []
	for entry: Array in cases:
		var bad: Array = entry[0]
		var catcher: ErrorCatcher = ErrorCatcher.new()
		OS.add_logger(catcher)
		var read: CampaignBatch = CampaignBatch.from_wire(bad)
		OS.remove_logger(catcher)
		if read != null or catcher.get_errors().size() != (entry[1] as int):
			unrefused.append([bad, catcher.get_errors().size()])
	_check("campaign wire: malformed batches are refused, each logged once", (
			unrefused.is_empty()
	), str(unrefused))


# Every CampaignCommand class anywhere in the project that can be made declares a wire name its
# registry knows: its default goes through the wire to its own class. No two command types, combat
# or campaign, share a name.
func _test_registered() -> void:
	var problems: PackedStringArray = []
	var owners: Dictionary[String, String] = {}
	for base: String in ["Command", "CampaignCommand"]:
		for class_id: String in _concrete_classes(base):
			var wire_type: String = _wire_type_of(class_id)
			if wire_type.is_empty():
				# A combat test fixture is never sent; a campaign class must be.
				if base == "CampaignCommand":
					problems.append("%s declares no WIRE_TYPE" % [class_id])
				continue
			if owners.has(wire_type):
				problems.append("%s and %s share %s" % [owners[wire_type], class_id, wire_type])
			owners[wire_type] = class_id
	var campaign_classes: PackedStringArray = _concrete_classes("CampaignCommand")
	for class_id: String in campaign_classes:
		var made: CampaignCommand = _default_of(class_id)
		if made == null or made.get_wire_type() != _wire_type_of(class_id):
			problems.append("%s answers another wire type" % [class_id])
			continue
		var decoded: CampaignCommand = CampaignCommand.from_wire(made.to_wire())
		if decoded == null or decoded.get_script() != made.get_script():
			problems.append("%s isn't in CampaignCommand._of_wire_type()" % [class_id])
	_check("campaign wire: every CampaignCommand class has a registered, unique wire type", (
			problems.is_empty() and campaign_classes.size() >= COMMAND_TYPES
	), "%d classes; %s" % [campaign_classes.size(), problems])


func _test_fingerprint() -> void:
	var listed: Dictionary[String, String] = NetContract.command_wire_types()
	var missing: PackedStringArray = []
	for class_id: String in _concrete_classes("CampaignCommand"):
		if listed.get(class_id, "") != _wire_type_of(class_id):
			missing.append(class_id)
	_check("campaign wire: the fingerprint's command list has every campaign wire name", (
			missing.is_empty()
	), "missing %s" % [missing])

	var parts: Dictionary = NetContract.format_parts()
	var base: int = NetContract.combine("v", parts, "c")
	var renamed: Dictionary = parts.duplicate(true)
	(renamed["commands"] as Dictionary)["ChooseNodeCommand"] = "choose_node_2"
	var dropped: Dictionary = parts.duplicate(true)
	(dropped["commands"] as Dictionary).erase("EventVoteCommand")
	_check("campaign wire: a renamed or removed campaign wire name changes the fingerprint", (
			NetContract.combine("v", renamed, "c") != base
			and NetContract.combine("v", dropped, "c") != base
	))


# One scenario per command type: where its command resolves, how the host builds it, and for a
# type with host-side objects, how the host fills in a decoded one: the factory its own seat uses,
# given only the decoded plain values.
func _scenarios() -> Array[Scenario]:
	var armory: Callable = _inside.bind(CampaignGraph.NodeType.ARMORY)
	var camp: Callable = _inside.bind(CampaignGraph.NodeType.CAMP)
	var guildhall: Callable = _inside.bind(CampaignGraph.NodeType.GUILDHALL)
	var unknown: Callable = _events.unknown_session.bind(1)
	var goblet: Callable = _with_event.bind(_goblet, 1)
	var made: Array[Scenario] = [
		Scenario.new(ChooseNodeCommand.WIRE_TYPE, _on_map, _choose_node),
		Scenario.new(LeaveNodeCommand.WIRE_TYPE, armory, _leave_node),
		Scenario.new(
				StartingHeirloomCommand.WIRE_TYPE, _with_starting_offer, _starting_heirloom
		),
		Scenario.new(ItemPickCommand.WIRE_TYPE, _with_item_pick, _item_pick),
		Scenario.new(KeyHeirloomCommand.WIRE_TYPE, _with_key_heirloom, _key_heirloom),
		Scenario.new(
				OpenTreasureCommand.WIRE_TYPE, _inside.bind(CampaignGraph.NodeType.TREASURE),
				_open_treasure, _refill_open_treasure
		),
		Scenario.new(TreasureCommand.WIRE_TYPE, _with_open_treasure, _treasure),
		Scenario.new(FeastCommand.WIRE_TYPE, camp, _feast),
		Scenario.new(TrainCommand.WIRE_TYPE, camp, _train),
		Scenario.new(RegearCommand.WIRE_TYPE, camp, _regear),
		Scenario.new(GiftItemCommand.WIRE_TYPE, _with_gift, _gift_item),
		Scenario.new(ScrapItemCommand.WIRE_TYPE, _with_scrap, _scrap_item),
		Scenario.new(OpenArmoryCommand.WIRE_TYPE, armory, _open_armory, _refill_open_armory),
		Scenario.new(
				ArmoryPurchaseCommand.WIRE_TYPE, _with_open_armory, _armory_purchase,
				_refill_armory_purchase
		),
		Scenario.new(
				OpenGuildhallCommand.WIRE_TYPE, guildhall, _open_guildhall,
				_refill_open_guildhall
		),
		Scenario.new(
				GuildhallPurchaseCommand.WIRE_TYPE, _with_open_guildhall, _guildhall_purchase
		),
		Scenario.new(
				PrefixRerollCommand.WIRE_TYPE, _with_open_guildhall, _prefix_reroll,
				_refill_prefix_reroll
		),
		Scenario.new(
				ResolveUnknownCommand.WIRE_TYPE, unknown, _resolve_unknown,
				_refill_resolve_unknown
		),
		Scenario.new(OpenEventCommand.WIRE_TYPE, unknown, _open_event, _refill_open_event),
		Scenario.new(
				EventChooserCommand.WIRE_TYPE, goblet, _event_chooser, _refill_event_chooser
		),
		Scenario.new(
				EventVoteCommand.WIRE_TYPE, _with_first_vote, _event_vote, _refill_event_vote
		),
		Scenario.new(
				EventOptionCommand.WIRE_TYPE, goblet, _event_option, _refill_event_option
		),
	]
	return made


# A new solo run on the map before its first node, with no starting offer.
func _on_map() -> CampaignSession:
	return NodeFixture.session(RUN_SEED)


# A new run of seat_count seats inside its first floor-1 node, made a node of type and entered by
# choosing it, every seat holding RICH gold.
func _inside(type: CampaignGraph.NodeType, seat_count: int = 1) -> CampaignSession:
	var made: CampaignSession = NodeFixture.session(RUN_SEED, seat_count)
	var first: int = made.run.graph.nodes_on_floor(1)[0]
	made.run.graph.set_node_type(first, type)
	made.submit(ChooseNodeCommand.new(0, first))
	for seat: int in made.run.seat_numbers():
		made.run.seat_run(seat).gold = RICH
	return made


func _with_starting_offer() -> CampaignSession:
	var made: CampaignSession = _on_map()
	var seat_run: SeatRun = made.run.seat_run(0)
	var offer: StartingOffer = StartingOffer.roll(
			RngStream.new(OFFER_SEED), seat_run, EffectCatalog.index(), made.ids, false
	)
	offer.store(seat_run)
	return made


func _with_item_pick() -> CampaignSession:
	var made: CampaignSession = _inside(CampaignGraph.NodeType.STANDARD)
	made.run.flow.stage = RunFlow.Stage.RESULTS
	var seat_run: SeatRun = made.run.seat_run(0)
	var pick: ItemPick = ItemPick.roll(
			RngStream.new(PICK_SEED), CombatMapDefinition.CombatType.STANDARD, seat_run,
			_events.rules, EffectCatalog.index(), made.ids
	)
	if pick != null:
		pick.store(seat_run)
	return made


func _with_key_heirloom() -> CampaignSession:
	var made: CampaignSession = _inside(CampaignGraph.NodeType.KEY)
	made.run.flow.stage = RunFlow.Stage.RESULTS
	var seat_run: SeatRun = made.run.seat_run(0)
	var offer: KeyHeirloom = KeyHeirloom.roll(
			RngStream.new(KEY_SEED), seat_run, EffectCatalog.index(), false
	)
	if offer != null:
		offer.store(seat_run)
	return made


func _with_open_treasure() -> CampaignSession:
	var made: CampaignSession = _inside(CampaignGraph.NodeType.TREASURE)
	made.submit(OpenTreasureCommand.for_session(made))
	return made


func _with_open_armory() -> CampaignSession:
	var made: CampaignSession = _inside(CampaignGraph.NodeType.ARMORY)
	made.submit(OpenArmoryCommand.for_session(made))
	return made


func _with_open_guildhall() -> CampaignSession:
	var made: CampaignSession = _inside(CampaignGraph.NodeType.GUILDHALL)
	made.submit(OpenGuildhallCommand.for_session(made))
	return made


# Two seats at a Camp, the first with an item in its convoy.
func _with_gift() -> CampaignSession:
	var made: CampaignSession = _inside(CampaignGraph.NodeType.CAMP, 2)
	_add_owned_to_convoy(made)
	return made


func _with_scrap() -> CampaignSession:
	var made: CampaignSession = _on_map()
	_add_owned_to_convoy(made)
	return made


# A run of seat_count seats inside an Unknown node with an event of pool() open.
func _with_event(pool: Callable, seat_count: int) -> CampaignSession:
	var made: CampaignSession = _events.unknown_session(seat_count)
	var events: EventPool = pool.call()
	_events.open(made, events)
	return made


# Two seats in the toll's team choice, seat 0 having voted to fight.
func _with_first_vote() -> CampaignSession:
	var made: CampaignSession = _with_event(_toll, 2)
	_events.vote(made, _toll(), 0, FIGHT)
	return made


# A new item in seat 0's convoy of the same kind as an item its army holds.
func _add_owned_to_convoy(made: CampaignSession) -> void:
	var seat_run: SeatRun = made.run.seat_run(0)
	var first: ItemInstance = seat_run.items.values()[0]
	NodeFixture.add_to_convoy(seat_run, first.definition_id, made.ids)


func _goblet() -> EventPool:
	return _events.pool([_events.goblet()])


func _toll() -> EventPool:
	return _events.pool([_events.toll()])


func _choose_node(session: CampaignSession) -> CampaignCommand:
	return ChooseNodeCommand.new(0, session.run.graph.nodes_on_floor(1)[0])


func _leave_node(_session: CampaignSession) -> CampaignCommand:
	return LeaveNodeCommand.new(0)


func _starting_heirloom(session: CampaignSession) -> CampaignCommand:
	var seat_run: SeatRun = session.run.seat_run(0)
	var offer: StartingOffer = StartingOffer.pending(seat_run)
	var units: PackedStringArray = [""]
	units.append_array(_unit_ids(seat_run))
	var choices: PackedInt32Array = [StartingHeirloomCommand.NO_CHOICE, 0]
	var candidates: Array[CampaignCommand] = []
	for option: int in (offer.options.size() if offer != null else 0):
		for recruit: int in choices:
			for weapon: int in choices:
				for unit: String in units:
					var taking: StartingHeirloomCommand = StartingHeirloomCommand.new(0, option)
					taking.recruit = recruit
					taking.weapon = weapon
					taking.unit_id = unit
					if weapon != StartingHeirloomCommand.NO_CHOICE:
						taking.placement = ItemPlacement.new()
					candidates.append(taking)
	return _first_valid(session.run, candidates)


func _item_pick(session: CampaignSession) -> CampaignCommand:
	var pick: ItemPick = ItemPick.pending(session.run.seat_run(0))
	var candidates: Array[CampaignCommand] = []
	for index: int in (pick.offers.size() if pick != null else 0):
		candidates.append(ItemPickCommand.new(0, index, ItemPlacement.new()))
	return _first_valid(session.run, candidates)


func _key_heirloom(_session: CampaignSession) -> CampaignCommand:
	return KeyHeirloomCommand.new(0)


func _open_treasure(session: CampaignSession) -> CampaignCommand:
	return OpenTreasureCommand.for_session(session)


func _refill_open_treasure(fresh: CampaignSession, _decoded: CampaignCommand) -> CampaignCommand:
	return OpenTreasureCommand.for_session(fresh)


func _treasure(session: CampaignSession) -> CampaignCommand:
	var candidates: Array[CampaignCommand] = [
		TreasureCommand.new(0, true, null),
		TreasureCommand.new(0, true, ItemPlacement.new()),
	]
	return _first_valid(session.run, candidates)


func _feast(_session: CampaignSession) -> CampaignCommand:
	return FeastCommand.new(0)


func _train(session: CampaignSession) -> CampaignCommand:
	var candidates: Array[CampaignCommand] = []
	for unit: String in _unit_ids(session.run.seat_run(0)):
		candidates.append(TrainCommand.new(0, unit))
	return _first_valid(session.run, candidates)


# Moves an equipped item to the convoy.
func _regear(session: CampaignSession) -> CampaignCommand:
	var candidates: Array[CampaignCommand] = []
	for unit: UnitInstance in session.run.seat_run(0).army:
		for item: String in [unit.weapon_id, unit.equipment_id, unit.pouch_id]:
			if not item.is_empty():
				candidates.append(RegearCommand.new(0, item, "", Loadout.Slot.POUCH))
	return _first_valid(session.run, candidates)


func _gift_item(session: CampaignSession) -> CampaignCommand:
	return GiftItemCommand.new(0, session.run.seat_run(0).convoy[0], 1)


func _scrap_item(session: CampaignSession) -> CampaignCommand:
	return ScrapItemCommand.new(0, session.run.seat_run(0).convoy[0])


func _open_armory(session: CampaignSession) -> CampaignCommand:
	return OpenArmoryCommand.for_session(session)


func _refill_open_armory(fresh: CampaignSession, _decoded: CampaignCommand) -> CampaignCommand:
	return OpenArmoryCommand.for_session(fresh)


func _armory_purchase(session: CampaignSession) -> CampaignCommand:
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	var units: PackedStringArray = [""]
	units.append_array(_unit_ids(session.run.seat_run(0)))
	var candidates: Array[CampaignCommand] = []
	for entry: int in (stock.entries.size() if stock != null else 0):
		for unit: String in units:
			for trade_in: bool in [false, true]:
				candidates.append(ArmoryPurchaseCommand.for_session(
						session, 0, entry, unit, trade_in
				))
	return _first_valid(session.run, candidates)


func _refill_armory_purchase(fresh: CampaignSession, decoded: CampaignCommand) -> CampaignCommand:
	var buy: ArmoryPurchaseCommand = decoded as ArmoryPurchaseCommand
	return ArmoryPurchaseCommand.for_session(
			fresh, buy.seat, buy.entry, buy.unit_id, buy.is_traded_in
	)


func _open_guildhall(session: CampaignSession) -> CampaignCommand:
	return OpenGuildhallCommand.for_session(session)


func _refill_open_guildhall(fresh: CampaignSession, _decoded: CampaignCommand) -> CampaignCommand:
	return OpenGuildhallCommand.for_session(fresh)


func _guildhall_purchase(session: CampaignSession) -> CampaignCommand:
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	var candidates: Array[CampaignCommand] = []
	for entry: int in (stock.entries.size() if stock != null else 0):
		candidates.append(GuildhallPurchaseCommand.new(0, entry))
	return _first_valid(session.run, candidates)


func _prefix_reroll(session: CampaignSession) -> CampaignCommand:
	var candidates: Array[CampaignCommand] = []
	for unit: String in _unit_ids(session.run.seat_run(0)):
		candidates.append(PrefixRerollCommand.for_session(session, 0, unit))
	return _first_valid(session.run, candidates)


func _refill_prefix_reroll(fresh: CampaignSession, decoded: CampaignCommand) -> CampaignCommand:
	var reroll: PrefixRerollCommand = decoded as PrefixRerollCommand
	return PrefixRerollCommand.for_session(fresh, reroll.seat, reroll.unit_id)


func _resolve_unknown(session: CampaignSession) -> CampaignCommand:
	return ResolveUnknownCommand.for_session(session)


func _refill_resolve_unknown(
		fresh: CampaignSession, _decoded: CampaignCommand
) -> CampaignCommand:
	return ResolveUnknownCommand.for_session(fresh)


func _open_event(session: CampaignSession) -> CampaignCommand:
	return EventNode.open(session, _goblet(), _events.catalog, _events.rules)


func _refill_open_event(fresh: CampaignSession, _decoded: CampaignCommand) -> CampaignCommand:
	return EventNode.open(fresh, _goblet(), _events.catalog, _events.rules)


func _event_chooser(session: CampaignSession) -> CampaignCommand:
	return EventNode.open_chooser(session, 0, 0, _goblet(), _events.catalog)


func _refill_event_chooser(fresh: CampaignSession, decoded: CampaignCommand) -> CampaignCommand:
	var opening: EventChooserCommand = decoded as EventChooserCommand
	return EventNode.open_chooser(
			fresh, opening.seat, opening.option_index, _goblet(), _events.catalog
	)


# Seat 1's vote, which completes the set and draws the team's option.
func _event_vote(session: CampaignSession) -> CampaignCommand:
	return EventNode.vote(session, 1, FIGHT, _toll(), _events.catalog)


func _refill_event_vote(fresh: CampaignSession, decoded: CampaignCommand) -> CampaignCommand:
	var voting: EventVoteCommand = decoded as EventVoteCommand
	return EventNode.vote(fresh, voting.seat, voting.option_index, _toll(), _events.catalog)


# The goblet's random weapon, sent to the convoy by an explicit placement.
func _event_option(session: CampaignSession) -> CampaignCommand:
	var picks: EventChoice = EventChoice.new()
	picks.placements[WEAPON_BLOCK] = ItemPlacement.new()
	return EventNode.choose(session, 0, BREAK_THE_ICE, picks, _goblet(), _events.catalog)


func _refill_event_option(fresh: CampaignSession, decoded: CampaignCommand) -> CampaignCommand:
	var choosing: EventOptionCommand = decoded as EventOptionCommand
	return EventNode.choose(
			fresh, choosing.seat, choosing.option_index, choosing.choice, _goblet(),
			_events.catalog
	)


# The first of candidates run accepts now; else the first, so its reason shows; null for none.
func _first_valid(run: CampaignRunState, candidates: Array[CampaignCommand]) -> CampaignCommand:
	for candidate: CampaignCommand in candidates:
		if candidate != null and candidate.validate(run).is_empty():
			return candidate
	return candidates[0] if not candidates.is_empty() else null


func _unit_ids(seat_run: SeatRun) -> PackedStringArray:
	var ids: PackedStringArray = []
	for unit: UnitInstance in seat_run.army:
		ids.append(unit.instance_id)
	return ids


# Adds [bad, errors logged] to unrefused unless CampaignCommand.from_wire() refuses bad with one
# error.
func _note_unrefused(bad: Array, unrefused: Array) -> void:
	var catcher: ErrorCatcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	var read: CampaignCommand = CampaignCommand.from_wire(bad)
	OS.remove_logger(catcher)
	if read != null or catcher.get_errors().size() != 1:
		unrefused.append([bad, catcher.get_errors().size()])


# The names of command's properties holding host state: an object other than a plain pick, or a
# dictionary holding any object.
func _host_state_of(command: CampaignCommand) -> PackedStringArray:
	var found: PackedStringArray = []
	for property: Dictionary in command.get_property_list():
		if not (property["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var property_name: String = property["name"]
		var value: Variant = command.get(property_name)
		if value is Object and not _is_plain(value as Object):
			found.append(property_name)
		elif value is Dictionary:
			for held: Variant in (value as Dictionary).values():
				if held is Object:
					found.append(property_name)
					break
	return found


func _is_plain(value: Object) -> bool:
	var script: Script = value.get_script() as Script
	return script != null and PLAIN_CLASSES.has(script.get_global_name())


# Every class in the project descending from base that can be made (not abstract), by name.
func _concrete_classes(base: String) -> PackedStringArray:
	var bases: Dictionary[String, String] = {}
	var paths: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[entry["class"] as String] = entry["base"] as String
		paths[entry["class"] as String] = entry["path"] as String
	var found: PackedStringArray = []
	for class_id: String in bases:
		var current: String = bases[class_id]
		while not current.is_empty() and current != base:
			current = bases.get(current, "")
		if current != base:
			continue
		var script: Script = load(paths[class_id]) as Script
		if script != null and not script.is_abstract():
			found.append(class_id)
	found.sort()
	return found


# The WIRE_TYPE constant class_id declares; empty when none.
func _wire_type_of(class_id: String) -> String:
	var script: Script = _script_of(class_id)
	if script == null:
		return ""
	return str(script.get_script_constant_map().get("WIRE_TYPE", ""))


# A new command of class_id with its defaults; null when it isn't one.
func _default_of(class_id: String) -> CampaignCommand:
	var script: GDScript = _script_of(class_id) as GDScript
	if script == null:
		return null
	return script.new() as CampaignCommand


func _script_of(class_id: String) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == class_id:
			return load(entry["path"] as String) as Script
	return null


# data after a trip through JSON; empty when it doesn't come back an Array.
func _through_json(data: Array) -> Array:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	return parsed as Array if parsed is Array else []


# Everything a run holds, as text: map, flow, events and every seat's sections.
func _run_text(run: CampaignRunState) -> String:
	var parts: Array = [run.capture_map(), run.flow.capture(), run.events.capture()]
	for seat: int in run.seat_numbers():
		var seat_run: SeatRun = run.seat_run(seat)
		parts.append_array([
			seat_run.capture_roster(),
			seat_run.capture_heirlooms(),
			seat_run.capture_runes(),
			seat_run.capture_economy(),
		])
	return JSON.stringify(parts)


# One command type's round trip: build() a fresh session where its command resolves, make(session)
# the command as the host builds it, and fill(session, decoded), only for a type with host-side
# objects, the host's fill-in of a decoded one. A type with a fill is refused until filled in.
class Scenario:
	extends RefCounted

	var wire_type: String = ""
	var build: Callable
	var make: Callable
	var fill: Callable

	func _init(
			type: String, builder: Callable, maker: Callable, filler: Callable = Callable()
	) -> void:
		wire_type = type
		build = builder
		make = maker
		fill = filler
