# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     draw_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The event draw: eligibility (the shrine needs a fallen unit in every army); a run never sees
## an event twice until every eligible one is seen, then the pool refills; the draw and the rolls
## are fixed by the seed; a tier curse comes from the whole tier, held curses included; each seat
## rolls from its own stream; the rare heirloom is never one the seat owns, two in one option
## differ, co-op-only ones need a co-op run, and an empty pool greys the option out. Touches no
## save files.

const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

# Streams tried for the tier curse's spread; with 4 minor curses, missing one is about 1e-25.
const CURSE_TRIES: int = 200

# An option of both the goblet and the toll that needs no pick: Walk Away, and Intimidate.
const NO_PICK_OPTION: int = 2

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("draw: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_eligibility()
	_test_never_repeat()
	_test_seeded()
	_test_tier_curse()
	_test_seat_streams()
	_test_rare_heirloom()


func _test_eligibility() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool()
	_check("draw: without a fallen unit the shrine isn't eligible", (
			_ids(EventDraw.eligible(events, made.run)) == PackedStringArray([
				Fixture.GOBLET, Fixture.TOLL,
			])
	), str(_ids(EventDraw.eligible(events, made.run))))
	var seat_run: SeatRun = made.run.seat_run(0)
	_fx.fell(seat_run, _fx.soldier(seat_run))
	_check("draw: with a fallen unit the shrine is eligible", (
			_ids(EventDraw.eligible(events, made.run)).has(Fixture.SHRINE)
	))

	var team: CampaignSession = _fx.unknown_session(2)
	var first: SeatRun = team.run.seat_run(0)
	_fx.fell(first, _fx.soldier(first))
	_check("draw: in co-op the shrine needs a fallen unit in every army", (
			not _ids(EventDraw.eligible(events, team.run)).has(Fixture.SHRINE)
	))
	var second: SeatRun = team.run.seat_run(1)
	_fx.fell(second, _fx.soldier(second))
	_check("draw: with a fallen unit in both armies the shrine is eligible", (
			_ids(EventDraw.eligible(events, team.run)).has(Fixture.SHRINE)
	))
	var empty: CampaignSession = _fx.unknown_session()
	var refused: CampaignBatch = _fx.open(empty, EventPool.new([_fx.shrine()]))
	_check("draw: with nothing eligible the open is refused and nothing opens", (
			refused.is_rejected() and empty.run.events.event_id.is_empty()
			and refused.rejected_reason.contains("no event can be drawn")
	), refused.rejected_reason)


func _test_never_repeat() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool()
	var drawn: PackedStringArray = []
	for visit: int in 3:
		if visit > 0:
			_fx.choose(made, events, 0, NO_PICK_OPTION)
			_fx.next_unknown(made)
		var batch: CampaignBatch = _fx.open(made, events)
		if batch.is_rejected():
			_check("draw: an event opens at each Unknown node", false, batch.rejected_reason)
			return
		drawn.append(made.run.events.event_id)
	_check("draw: the first two Unknown nodes draw the two eligible events, once each", (
			drawn[0] != drawn[1] and _sorted(drawn.slice(0, 2)) == PackedStringArray([
				Fixture.GOBLET, Fixture.TOLL,
			])
	), str(drawn))
	_check("draw: with every eligible event seen, the pool refills and the seen list restarts", (
			drawn[2] in [Fixture.GOBLET, Fixture.TOLL]
			and made.run.events.seen == PackedStringArray([drawn[2]])
	), "%s seen %s" % [drawn, made.run.events.seen])
	var seen: PackedStringArray = PackedStringArray([Fixture.GOBLET, Fixture.TOLL])
	_check("draw: an unseen but ineligible shrine still refills, and stays unseen", (
			EventDraw.is_refill(events, made.run, seen)
			and _ids(EventDraw.candidates(events, made.run, seen)) == seen
	))
	_check("draw: an unseen eligible event is drawn before any seen one", (
			_ids(EventDraw.candidates(events, made.run, PackedStringArray([Fixture.GOBLET])))
					== PackedStringArray([Fixture.TOLL])
	))
	var again: CampaignBatch = _fx.open(made, events)
	_check("draw: a node opens one event only; opening again is refused", (
			again.is_rejected() and again.rejected_reason.contains("already open")
	), again.rejected_reason)


func _test_seeded() -> void:
	var one: CampaignSession = _fx.unknown_session()
	var two: CampaignSession = _fx.unknown_session()
	var events: EventPool = _fx.pool()
	_fx.open(one, events)
	_fx.open(two, events)
	_check("draw: the same seed draws the same event with the same rolls", (
			not one.run.events.event_id.is_empty()
			and JSON.stringify(one.run.events.capture())
					== JSON.stringify(two.run.events.capture())
	))
	var fact: CampaignFact = one.run.fact_log.back()
	_check("draw: opening records EVENT_DRAWN with the event and the node, for no seat", (
			fact.kind == CampaignFact.Kind.EVENT_DRAWN
			and fact.definition_id == one.run.events.event_id
			and fact.amount == one.run.node and fact.seat == CampaignFact.NO_SEAT
	))


func _test_tier_curse() -> void:
	var minor: PackedStringArray = _fx.curses_of(Fixture.MINOR)
	var seen: Dictionary[String, bool] = {}
	for index: int in CURSE_TRIES:
		var stream: RngStream = RngStream.new(RngKey.derive_seed(
				Fixture.RUN_SEED, RngKey.RngPurpose.EVENT_OUTCOME, 1, index, 0, -1
		))
		seen[EventDraw.draw_curse(Fixture.MINOR, stream, _fx.catalog)] = true
	var drawn: PackedStringArray = PackedStringArray(seen.keys())
	drawn.sort()
	_check("draw: a tier's curse comes from the whole tier and only that tier", (
			minor.size() > 1 and drawn == minor
	), "%s vs %s" % [drawn, minor])

	var made: CampaignSession = _fx.unknown_session()
	var seat_run: SeatRun = made.run.seat_run(0)
	for curse_id: String in minor:
		seat_run.add_heirloom(curse_id)
	_fx.open(made, _fx.pool([_fx.goblet()]))
	var curse: String = made.run.events.seat_event(0).rolls_of(1).curse_id
	_check("draw: with every minor curse held, the option still names one of them", (
			minor.has(curse)
	), curse)


func _test_seat_streams() -> void:
	var team: CampaignSession = _fx.unknown_session(2)
	var events: EventPool = _fx.pool([_fx.goblet()])
	_fx.open(team, events)
	var state: EventRunState = team.run.events
	var matches: bool = state.seats.size() == 2
	for seat: int in [0, 1]:
		var own: RngStream = RngStream.new(RngKey.derive_seed(
				Fixture.RUN_SEED, RngKey.RngPurpose.EVENT_OUTCOME,
				team.run.floor_number, team.run.node, seat, -1
		))
		var expected: Array[EventRolls] = EventDraw.roll_seat(
				events.event(Fixture.GOBLET), team.run, seat, own, _fx.catalog, _fx.rules
		)
		matches = matches and _rolls_text(expected) == _rolls_text(state.seat_event(seat).rolls)
	var differ: bool = (
			_rolls_text(state.seat_event(0).rolls) != _rolls_text(state.seat_event(1).rolls)
	)
	_check("draw: each seat's rolls come from its own EVENT_OUTCOME stream", matches)
	_check("draw: the two seats' rolls differ", differ)


func _test_rare_heirloom() -> void:
	var made: CampaignSession = _fx.unknown_session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var rare: PackedStringArray = EventDraw.heirloom_candidates(
			Fixture.RARE, seat_run, PackedStringArray(), false, _fx.catalog
	)
	_check("draw: the rare pool holds the catalog's rare heirlooms, no curses", (
			rare.size() > 2 and not rare.has("hunted")
	), str(rare))
	var owned: String = rare[0]
	seat_run.add_heirloom(owned)
	var altar: EventDefinition = _altar()
	var picks: PackedStringArray = []
	var distinct: bool = true
	for index: int in CURSE_TRIES:
		var stream: RngStream = RngStream.new(index)
		var rolls: Array[EventRolls] = EventDraw.roll_seat(
				altar, made.run, 0, stream, _fx.catalog, _fx.rules
		)
		var pair: EventRolls = rolls[0]
		picks.append(pair.pick(0))
		picks.append(pair.pick(1))
		distinct = distinct and pair.pick(0) != pair.pick(1)
	_check("draw: a drawn rare heirloom is never one the seat owns", not picks.has(owned))
	_check("draw: two rare heirlooms in one option always differ", distinct)

	var coop_only: String = "brothers_in_arms"
	var tier: String = _fx.catalog.heirloom(coop_only).tier
	_check("draw: a co-op-only heirloom is drawn only in a co-op run", (
			not EventDraw.heirloom_candidates(
					tier, seat_run, PackedStringArray(), false, _fx.catalog
			).has(coop_only)
			and EventDraw.heirloom_candidates(
					tier, seat_run, PackedStringArray(), true, _fx.catalog
			).has(coop_only)
	))

	for heirloom_id: String in rare:
		if heirloom_id != owned:
			seat_run.add_heirloom(heirloom_id)
	_fx.fell(seat_run, _fx.soldier(seat_run))
	var events: EventPool = _fx.pool([_fx.shrine()])
	_fx.open(made, events)
	var view: EventView = EventNode.view(made, 0, events, _fx.catalog)
	_check("draw: with every rare heirloom owned, Claim the Relic is greyed out", (
			view.is_open() and view.options[1].unmet_reason == "no heirloom is left to give"
			and view.options[0].is_available()
	), "" if not view.is_open() else view.options[1].unmet_reason)


# An event whose first option gives two rare heirlooms, as the Black Altar's Accept the Pact.
func _altar() -> EventDefinition:
	var first: HeirloomOutcome = HeirloomOutcome.new()
	first.tier = Fixture.RARE
	var second: HeirloomOutcome = HeirloomOutcome.new()
	second.tier = Fixture.RARE
	var event: EventDefinition = _fx.event_of([first, second])
	return event


func _ids(events: Array[EventDefinition]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for event: EventDefinition in events:
		ids.append(event.id)
	return ids


func _sorted(ids: PackedStringArray) -> PackedStringArray:
	var copy: PackedStringArray = ids.duplicate()
	copy.sort()
	return copy


func _rolls_text(rolls: Array[EventRolls]) -> String:
	var data: Array = []
	for each: EventRolls in rolls:
		data.append(each.capture())
	return JSON.stringify(data)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
