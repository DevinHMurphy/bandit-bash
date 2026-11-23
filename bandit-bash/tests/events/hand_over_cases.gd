# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hand_over_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The hand-over at events (EventHandOver), resolved against real runs: a recruit into a full army
## takes one item onto itself, sends one to the convoy and scraps one for the Guildhall's scrap
## gold, with its facts in order; a weapon it wields displaces its own to the convoy; a revived
## unit takes an item the same way. Refused, changing nothing: a weapon it can't wield, an item
## not the leaving unit's, a hand-over with room, too much for the convoy (a displaced item
## counted); question 38's refusals are unchanged with no hand-over. Best fit; the choice's wire
## form round-trips and malformed ones are refused; a teammate's item is refused; each co-op seat
## hands over its own unit's items. A rolled recruit: rolled at open, saved, previewed and joined
## as rolled; a run saved before rolls draws at apply. EventRolls' optional prefixes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

const ARCHER: String = "archer"
const BUCKLER: String = "buckler"
const SIMPLE_BOW: String = "simple_bow"

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("hand-over: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_places()
	_test_displaced()
	_test_revive()
	_test_refusals()
	_test_unchanged_refusals()
	_test_best_fit()
	_test_wire()
	_test_teammate()
	_test_coop()
	_test_rolled_recruit()
	_test_unrolled_recruit()
	_test_rolls_capture()


func _test_places() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.soldier(seat_run)
	var buckler: ItemInstance = _equip_buckler(made, leaving)
	var lance: String = leaving.weapon_id
	var potion: String = leaving.pouch_id
	var gold: int = seat_run.gold
	var worth: int = ItemPlacement.held_scrap_value(buckler, _fx.catalog, seat_run)
	var choice: EventChoice = _replacing(leaving, {
		buckler.instance_id: Guildhall.HandOver.SCRAP,
		potion: Guildhall.HandOver.RECRUIT,
		lance: Guildhall.HandOver.CONVOY,
	})
	var result: EventResult = _resolve(made, [_archer()], choice)
	var joined: UnitInstance = seat_run.army[-1]
	_check("places: onto the recruit, the convoy and scrapped, each where it was sent", (
			not result.is_rejected() and joined.unit_type_id == ARCHER
			and joined.pouch_id == potion and seat_run.convoy.has(lance)
			and not seat_run.items.has(buckler.instance_id)
			and not seat_run.convoy.has(buckler.instance_id)
			and not seat_run.army.has(leaving) and _fx.is_whole(seat_run)
	), result.rejected_reason)
	var scrapped: CampaignFact = _first(result.facts, CampaignFact.Kind.ITEM_SCRAPPED)
	_check("places: scrapping pays the Guildhall's scrap gold at the seat's rate", (
			worth > 0 and seat_run.gold == gold + worth
			and scrapped != null and scrapped.amount == worth
			and scrapped.actor_id == buckler.instance_id
	), "%d -> %d (worth %d)" % [gold, seat_run.gold, worth])
	var kinds: Array[CampaignFact.Kind] = _fx.kinds(result.facts)
	var dismissed: int = kinds.find(CampaignFact.Kind.UNIT_DISMISSED)
	var recruited: int = kinds.find(CampaignFact.Kind.UNIT_RECRUITED)
	var handed: CampaignFact = result.facts[-1]
	_check("places: scrap, the convoy's item, the dismissal, the recruit, then the item it took", (
			kinds.find(CampaignFact.Kind.ITEM_SCRAPPED) < dismissed and dismissed < recruited
			and recruited == kinds.size() - 2
			and handed.kind == CampaignFact.Kind.ITEM_EQUIPPED
			and handed.actor_id == potion and handed.target_id == joined.instance_id
	), str(kinds))


func _test_displaced() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.unit_of_type(seat_run, ARCHER)
	var bow: String = leaving.weapon_id
	var choice: EventChoice = _replacing(leaving, {bow: Guildhall.HandOver.RECRUIT})
	var result: EventResult = _resolve(made, [_archer()], choice)
	var joined: UnitInstance = seat_run.army[-1]
	var own: String = _last_convoy(seat_run)
	_check("displaced: a bow onto the new archer sends its own Simple Bow to the convoy", (
			not result.is_rejected() and joined.weapon_id == bow
			and seat_run.items.has(own) and seat_run.items[own].definition_id == SIMPLE_BOW
			and own != bow and _fx.is_whole(seat_run)
	), result.rejected_reason)

	var full: CampaignSession = _fx.session()
	var full_run: SeatRun = full.run.seat_run(0)
	var archer: UnitInstance = _fx.unit_of_type(full_run, ARCHER)
	_fill_convoy(full, 0)
	var crowded: EventChoice = _replacing(archer, {
		archer.weapon_id: Guildhall.HandOver.RECRUIT,
		archer.pouch_id: Guildhall.HandOver.SCRAP,
	})
	var log_size: int = full.run.fact_log.size()
	var refused: EventResult = _resolve(full, [_archer()], crowded)
	_check("displaced: the displaced item needs the convoy's room, or it is refused", (
			refused.is_rejected() and refused.rejected_reason.contains("the convoy can't take 1")
			and full.run.fact_log.size() == log_size and full_run.army.has(archer)
	), refused.rejected_reason)


func _test_revive() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var lost: UnitInstance = _fx.soldier(seat_run)
	_fx.fell(seat_run, lost)
	RunOperations.recruit(made.run, 0, RecruitOffer.make(
			_fx.catalog, ARCHER, "", 1, made.ids
	), "test")
	var leaving: UnitInstance = _fx.unit_of_type(seat_run, ARCHER)
	var tonic: String = leaving.pouch_id
	var bow: String = leaving.weapon_id
	var own_potion: String = lost.pouch_id
	var choice: EventChoice = _replacing(leaving, {tonic: Guildhall.HandOver.RECRUIT})
	choice.unit_id = lost.instance_id
	var result: EventResult = _resolve(made, [ReviveOutcome.new()], choice)
	_check("revive: the revived unit takes the item, its own Pouch item to the convoy", (
			not result.is_rejected() and seat_run.army.has(lost) and lost.pouch_id == tonic
			and seat_run.convoy.has(own_potion) and seat_run.convoy.has(bow)
			and _fx.is_whole(seat_run)
			and _fx.kinds(result.facts).find(CampaignFact.Kind.UNIT_REVIVED)
					< _fx.kinds(result.facts).rfind(CampaignFact.Kind.ITEM_EQUIPPED)
	), "%s; convoy %s; %s" % [result.rejected_reason, seat_run.convoy, _fx.kinds(result.facts)])

	var bow_made: CampaignSession = _fx.session()
	var bow_run: SeatRun = bow_made.run.seat_run(0)
	var fallen: UnitInstance = _fx.soldier(bow_run)
	_fx.fell(bow_run, fallen)
	RunOperations.recruit(bow_made.run, 0, RecruitOffer.make(
			_fx.catalog, ARCHER, "", 1, bow_made.ids
	), "test")
	var archer: UnitInstance = _fx.unit_of_type(bow_run, ARCHER)
	var bow_choice: EventChoice = _replacing(archer, {archer.weapon_id: Guildhall.HandOver.RECRUIT})
	bow_choice.unit_id = fallen.instance_id
	var refused: EventResult = _resolve(bow_made, [ReviveOutcome.new()], bow_choice)
	_check("revive: a weapon the revived unit can't wield is refused", (
			refused.is_rejected() and refused.rejected_reason.contains("can't wield a bow")
			and bow_run.fallen.has(fallen)
	), refused.rejected_reason)


func _test_refusals() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.soldier(seat_run)
	var army: Array[UnitInstance] = seat_run.army.duplicate()
	var log_size: int = made.run.fact_log.size()
	var wield: EventResult = _resolve(made, [_archer()], _replacing(leaving, {
		leaving.weapon_id: Guildhall.HandOver.RECRUIT,
	}))
	_check("refused: a lance onto an archer, which can't wield it", (
			wield.is_rejected() and wield.rejected_reason.contains("can't wield a lance")
	), wield.rejected_reason)

	var other: String = _fx.unit_of_type(seat_run, ARCHER).weapon_id
	var stranger: EventResult = _resolve(made, [_archer()], _replacing(leaving, {
		other: Guildhall.HandOver.SCRAP,
	}))
	_check("refused: an item that isn't the leaving unit's", (
			stranger.is_rejected() and stranger.rejected_reason.contains("isn't one of")
	), stranger.rejected_reason)

	_fill_convoy(made, 1)
	var crowded: EventResult = _resolve(made, [_archer()], _replacing(leaving, {
		leaving.pouch_id: Guildhall.HandOver.CONVOY,
		leaving.weapon_id: Guildhall.HandOver.CONVOY,
	}))
	_check("refused: more for the convoy than its room, so some must be scrapped", (
			crowded.is_rejected()
			and crowded.rejected_reason.contains("the convoy can't take 2 more")
			and crowded.rejected_reason.contains("so scrap some")
	), crowded.rejected_reason)
	var scrapping: EventChoice = _replacing(leaving, {
		leaving.pouch_id: Guildhall.HandOver.SCRAP,
	})
	_check("refused: nothing changed; scrapping one makes it fit", (
			seat_run.army == army and made.run.fact_log.size() == log_size
			and EventResolver.refusal(_fx.context(
					made, _fx.event_of([_archer()]), scrapping
			)).is_empty()
	))

	var roomy: CampaignSession = _fx.session()
	var roomy_run: SeatRun = roomy.run.seat_run(0)
	_fx.fell(roomy_run, roomy_run.army[-1])
	var handed: EventChoice = EventChoice.new()
	handed.hand_over[_fx.soldier(roomy_run).weapon_id] = Guildhall.HandOver.SCRAP
	var with_room: EventResult = _resolve(roomy, [_archer()], handed)
	_check("refused: a hand-over while the army has room, as no unit leaves", (
			with_room.is_rejected() and with_room.rejected_reason.contains("nothing is handed")
	), with_room.rejected_reason)

	var leader: EventChoice = _replacing(leaving, {})
	leader.replaced_id = seat_run.commander_id
	leader.hand_over[seat_run.unit(seat_run.commander_id).weapon_id] = Guildhall.HandOver.SCRAP
	var commander: EventResult = _resolve(made, [_archer()], leader)
	_check("refused: the commander never leaves, whatever its hand-over", (
			commander.is_rejected()
			and commander.rejected_reason == "the commander never leaves the army"
	), commander.rejected_reason)


func _test_unchanged_refusals() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.soldier(seat_run)
	_fill_convoy(made, leaving.item_ids().size() - 1)
	var expected: String = RunOperations.dismiss_problem(
			made.run, 0, leaving.instance_id, _fx.catalog
	)
	var none: EventResult = _resolve(made, [_archer()], _replacing(leaving, {}))
	var leader: EventChoice = _replacing(leaving, {})
	leader.replaced_id = seat_run.commander_id
	var commander: EventResult = _resolve(made, [_archer()], leader)
	var unnamed: EventResult = _resolve(made, [_archer()], EventChoice.new())
	_check("question 38: with no hand-over, the convoy, commander and full-army refusals hold", (
			none.is_rejected() and none.rejected_reason == expected
			and expected.begins_with("the convoy can't take its")
			and commander.rejected_reason == "the commander never leaves the army"
			and unnamed.rejected_reason.contains("choose a unit to dismiss")
	), "%s | %s | %s" % [none.rejected_reason, commander.rejected_reason, unnamed.rejected_reason])

	var roomy: CampaignSession = _fx.session()
	var roomy_run: SeatRun = roomy.run.seat_run(0)
	_fx.fell(roomy_run, roomy_run.army[-1])
	var named: EventResult = _resolve(roomy, [_archer()], _replacing(_fx.soldier(roomy_run), {}))
	_check("question 38: naming a unit while the army has room is refused as before", (
			named.is_rejected() and named.rejected_reason.contains("the army has room")
	), named.rejected_reason)


func _test_best_fit() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.soldier(seat_run)
	var buckler: ItemInstance = _equip_buckler(made, leaving)
	var joining: RecruitOffer = RecruitOffer.make(
			_fx.catalog, ARCHER, "", 1, InstanceIdAllocator.new()
	)
	var fit: Dictionary[String, int] = EventHandOver.best_fit(
			seat_run, leaving, joining, _fx.catalog
	)
	_check("best fit: what the archer can use onto it, the lance to the convoy", (
			_place(fit, buckler.instance_id) == Guildhall.HandOver.RECRUIT
			and _place(fit, leaving.pouch_id) == Guildhall.HandOver.RECRUIT
			and _place(fit, leaving.weapon_id) == Guildhall.HandOver.CONVOY
			and EventHandOver.problem(seat_run, leaving, joining, fit, _fx.catalog).is_empty()
	), str(fit))
	_fill_convoy(made, 0)
	var crowded: Dictionary[String, int] = EventHandOver.best_fit(
			seat_run, leaving, joining, _fx.catalog
	)
	_check("best fit: with the convoy full, what can't go on the recruit is scrapped", (
			_place(crowded, leaving.weapon_id) == Guildhall.HandOver.SCRAP
			and _place(crowded, leaving.pouch_id) == Guildhall.HandOver.RECRUIT
			and EventHandOver.compact(crowded).size() == crowded.size()
			and EventHandOver.compact(fit).size() == fit.size() - 1
	), str(crowded))


func _test_wire() -> void:
	var choice: EventChoice = _replacing(UnitInstance.new("unit:2", ARCHER), {
		"item:3": Guildhall.HandOver.SCRAP, "item:4": Guildhall.HandOver.RECRUIT,
	})
	choice.unit_id = "unit:1"
	var command: EventOptionCommand = EventOptionCommand.new(0, 1, choice)
	var wire: Array = command.to_wire()
	var read: EventOptionCommand = CampaignCommand.from_wire(wire) as EventOptionCommand
	_check("wire: the hand-over travels as the choice's 6th field, in order", (
			read != null and read.choice != null
			and read.choice.hand_over == choice.hand_over
			and read.choice.hand_over.keys() == choice.hand_over.keys()
			and read.choice.replaced_id == "unit:2"
			and (wire[-1] as Array).size() == 6
	), str(wire))
	var bad: PackedStringArray = []
	var shapes: Dictionary[String, Variant] = {
		"a repeated item": [["item:3", 2], ["item:3", 1]],
		"no such place": [["item:3", 7]],
		"an id not a string": [[3, 2]],
		"a pair too short": [["item:3"]],
		"not a list": "item:3",
	}
	for label: String in shapes:
		var broken: Array = wire.duplicate(true)
		var broken_choice: Array = broken[-1]
		broken_choice[5] = shapes[label]
		if CampaignCommand.from_wire(broken) != null:
			bad.append(label)
	var five: Array = wire.duplicate(true)
	var five_choice: Array = five[-1]
	five_choice.resize(5)
	if CampaignCommand.from_wire(five) != null:
		bad.append("the five-field choice")
	_check("wire: malformed hand-overs and the old five-field choice are refused", bad.is_empty(),
			", ".join(bad))


func _test_teammate() -> void:
	var made: CampaignSession = _fx.unknown_session(2)
	var events: EventPool = _fx.pool([_fx.event_of([_archer()])])
	_fx.open(made, events)
	var own: SeatRun = made.run.seat_run(0)
	var mate: SeatRun = made.run.seat_run(1)
	var choice: EventChoice = _replacing(_fx.soldier(own), {
		_fx.soldier(mate).weapon_id: Guildhall.HandOver.SCRAP,
	})
	var batch: CampaignBatch = _fx.choose(made, events, 0, 0, choice)
	_check("teammate: a hand-over naming a teammate's item is refused", (
			batch.is_rejected() and batch.rejected_reason.contains("belongs to seat 1's army")
	), batch.rejected_reason)


func _test_coop() -> void:
	var made: CampaignSession = _fx.unknown_session(2)
	var events: EventPool = _fx.pool([_fx.event_of([_archer()])])
	_fx.open(made, events)
	var results: PackedStringArray = []
	var ok: bool = true
	for seat: int in [0, 1]:
		var seat_run: SeatRun = made.run.seat_run(seat)
		var leaving: UnitInstance = _fx.soldier(seat_run)
		var potion: String = leaving.pouch_id
		var lance: String = leaving.weapon_id
		var other: SeatRun = made.run.seat_run(1 - seat)
		var other_convoy: int = other.convoy.size()
		var place: int = Guildhall.HandOver.SCRAP if seat == 0 else Guildhall.HandOver.CONVOY
		var batch: CampaignBatch = _fx.choose(made, events, seat, 0, _replacing(leaving, {
			potion: Guildhall.HandOver.RECRUIT, lance: place,
		}))
		results.append(batch.rejected_reason)
		ok = ok and not batch.is_rejected() and seat_run.army[-1].pouch_id == potion
		ok = ok and seat_run.convoy.has(lance) == (seat == 1)
		ok = ok and seat_run.items.has(lance) == (seat == 1)
		ok = ok and other.convoy.size() == other_convoy and _fx.is_whole(seat_run)
	_check("co-op: each seat hands over its own unit's items with its own command", (
			ok and made.run.events.is_finished()
	), " | ".join(results))


func _test_rolled_recruit() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var hire: RecruitOutcome = _random_recruit()
	var event: EventDefinition = _fx.event_of([hire])
	var events: EventPool = _fx.pool([event])
	_fx.open(made, events)
	var rolls: EventRolls = made.run.events.seat_event(0).rolls_of(0)
	var type_id: String = rolls.pick(0)
	var prefix: UnitPrefixDefinition = _fx.catalog.unit_prefix(rolls.prefix(0))
	_check("rolled: the recruit's type and an elite prefix are rolled as the event opens", (
			rolls.picks.has(0) and RecruitOffer.pool(_fx.catalog).has(type_id)
			and prefix != null and prefix.tier > 0 and hire.is_known(rolls, 0)
	), "%s %s" % [type_id, rolls.prefix(0)])
	var resumed: CampaignSession = _fx.resume(made)
	var kept: EventRolls = (
			null if resumed == null else resumed.run.events.seat_event(0).rolls_of(0)
	)
	_check("rolled: a quit and Continue keeps the rolled recruit", (
			kept != null and kept.pick(0) == type_id and kept.prefix(0) == rolls.prefix(0)
	), error_string(_fx.resume_error))
	if resumed == null:
		return
	var seat_run: SeatRun = resumed.run.seat_run(0)
	var leaving: UnitInstance = _fx.soldier(seat_run)
	var potion: String = leaving.pouch_id
	var choice: EventChoice = _replacing(leaving, {potion: Guildhall.HandOver.RECRUIT})
	var preview: RecruitOffer = EventScreenModel.joining(
			resumed.run, 0, event, 0, choice, _fx.catalog
	)
	var batch: CampaignBatch = _fx.choose(resumed, events, 0, 0, choice)
	var joined: UnitInstance = seat_run.army[-1]
	_check("rolled: it is previewed and joins as rolled, taking the item handed to it", (
			preview != null and preview.unit.unit_type_id == type_id
			and preview.unit.prefix_id == rolls.prefix(0)
			and not batch.is_rejected() and joined.unit_type_id == type_id
			and joined.prefix_id == rolls.prefix(0) and joined.pouch_id == potion
	), batch.rejected_reason)


func _test_unrolled_recruit() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	_fx.fell(seat_run, seat_run.army[-1])
	var hire: RecruitOutcome = _random_recruit()
	var ctx: EventContext = _fx.context(made, _fx.event_of([hire]))
	var unknown: bool = not hire.is_known(ctx.rolls, 0) and hire.joining(ctx, 0) == null
	var result: EventResult = EventResolver.resolve(ctx)
	var joined: UnitInstance = seat_run.army[-1]
	var prefix: UnitPrefixDefinition = _fx.catalog.unit_prefix(joined.prefix_id)
	_check("unrolled: a run saved before rolls draws the recruit as the option applies", (
			unknown and not result.is_rejected()
			and RecruitOffer.pool(_fx.catalog).has(joined.unit_type_id)
			and prefix != null and prefix.tier > 0
	), result.rejected_reason)

	var full: CampaignSession = _fx.session()
	var full_run: SeatRun = full.run.seat_run(0)
	var leaving: UnitInstance = _fx.soldier(full_run)
	var choice: EventChoice = _replacing(leaving, {leaving.pouch_id: Guildhall.HandOver.RECRUIT})
	var refused: EventResult = EventResolver.resolve(_fx.context(
			full, _fx.event_of([_random_recruit()]), choice
	))
	_check("unrolled: nothing can be handed to a recruit not yet known", (
			refused.is_rejected() and refused.rejected_reason.contains("isn't known yet")
	), refused.rejected_reason)


func _test_rolls_capture() -> void:
	var plain: EventRolls = EventRolls.new()
	plain.picks[0] = "potion"
	var plain_data: Dictionary = plain.capture()
	var recruit: EventRolls = EventRolls.new()
	recruit.picks[1] = ARCHER
	recruit.prefixes[1] = "steady"
	var read: EventRolls = EventRolls.restore(
			JSON.parse_string(JSON.stringify(recruit.capture())) as Dictionary
	)
	var old: EventRolls = EventRolls.restore({"picks": {"0": "potion"}, "curse": ""})
	_check("rolls: no prefixes saves as before; prefixes round-trip; an old save reads", (
			not plain_data.has("prefixes") and plain_data.keys() == ["picks", "curse"]
			and read != null and read.pick(1) == ARCHER and read.prefix(1) == "steady"
			and old != null and old.prefixes.is_empty() and old.pick(0) == "potion"
	), str(plain_data))
	var bad: Array = [
		{"picks": {}, "curse": "", "prefixes": []},
		{"picks": {}, "curse": "", "prefixes": {"-1": "steady"}},
		{"picks": {}, "curse": "", "prefixes": {"0": 3}},
	]
	var refused: bool = true
	for data: Variant in bad:
		refused = refused and EventRolls.restore(data as Dictionary) == null
	_check("rolls: malformed prefixes are refused", refused)


# --- Helpers -----------------------------------------------------------------------------------


func _resolve(
		made: CampaignSession, outcomes: Array[EventOutcome], choice: EventChoice = null
) -> EventResult:
	return EventResolver.resolve(_fx.context(made, _fx.event_of(outcomes), choice))


# A choice dismissing leaving with hand_over.
func _replacing(leaving: UnitInstance, hand_over: Dictionary) -> EventChoice:
	var choice: EventChoice = EventChoice.new()
	choice.replaced_id = leaving.instance_id
	for item_id: Variant in hand_over:
		choice.hand_over[item_id as String] = hand_over[item_id] as int
	return choice


func _archer() -> RecruitOutcome:
	var hire: RecruitOutcome = RecruitOutcome.new()
	hire.unit_type_id = ARCHER
	return hire


# A recruit of any type with an elite prefix, as Mercenary Camp's "Hire the Best".
func _random_recruit() -> RecruitOutcome:
	var hire: RecruitOutcome = RecruitOutcome.new()
	hire.prefix_roll = RecruitOutcome.PrefixRoll.ELITE
	return hire


# Puts a new buckler in unit's empty Equipment slot.
func _equip_buckler(made: CampaignSession, unit: UnitInstance) -> ItemInstance:
	var seat_run: SeatRun = made.run.seat_run(0)
	var item: ItemInstance = ItemInstance.new(made.ids.next_item_id(BUCKLER), BUCKLER)
	seat_run.items[item.instance_id] = item
	ItemPlacement.put_item(unit, Loadout.Slot.EQUIPMENT, item.instance_id)
	return item


# Fills seat 0's convoy until it has room for room more.
func _fill_convoy(made: CampaignSession, room: int) -> void:
	var seat_run: SeatRun = made.run.seat_run(0)
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, _fx.catalog)
	while seat_run.convoy.size() < capacity - room:
		_fx.add_to_convoy(made, BUCKLER)


# Where hand_over sends item_id; -1 when it doesn't name it.
func _place(hand_over: Dictionary[String, int], item_id: String) -> int:
	return hand_over.get(item_id, -1)


func _last_convoy(seat_run: SeatRun) -> String:
	return "" if seat_run.convoy.is_empty() else seat_run.convoy[-1]


func _first(facts: Array[CampaignFact], kind: CampaignFact.Kind) -> CampaignFact:
	for fact: CampaignFact in facts:
		if fact.kind == kind:
			return fact
	return null


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call("hand-over %s" % [case_name], passed, detail)
