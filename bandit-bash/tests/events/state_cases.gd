# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     state_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The events section and a continued run: the section's round trip through a registry and JSON
## (votes and a pending combat included), its refusal of a newer version and of unusable data,
## and quit and Continue before choosing, mid-chooser and after choosing, each saved through the
## campaign block's rng, instance_ids, run and events sections and loaded into a new session in
## CampaignService's order, showing the same event, rolls, stage and outcome. Saves go through
## memory and JSON only; no file is written.

const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

const CAMPAIGN: SaveSection.Block = SaveSection.Block.CAMPAIGN
const NO_OPTION: int = EventRunState.NO_OPTION
# Option 1 of the goblet: a rare weapon and a minor curse, no pick needed.
const ICE: int = 1

var _report: Callable
var _fx: Fixture = null
var _pool: EventPool = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("state: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_pool = _fx.pool([_fx.goblet()])
	_test_round_trip()
	_test_refusals()
	_test_continue_before_choosing()
	_test_continue_mid_chooser()
	_test_continue_after_choosing()


func _test_round_trip() -> void:
	var made: CampaignSession = _fx.unknown_session()
	_fx.open(made, _pool)
	var events: EventRunState = made.run.events
	events.votes[0] = ICE
	events.is_combat_pending = true
	var section: EventSaveSection = EventSaveSection.new()
	section.attach(made)
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	registry.register(CAMPAIGN, section)
	var saved: Dictionary = _json(registry.capture(CAMPAIGN, {}))
	var entry: Dictionary = saved.get(section.get_key(), {})
	var version: float = entry.get("version", 0.0)
	_check("state: the section saves under events at version 1", (
			section.get_key() == "events" and version == 1.0
	), str(entry))

	var loaded: EventSaveSection = EventSaveSection.new()
	var into: SaveSectionRegistry = SaveSectionRegistry.new()
	into.register(CAMPAIGN, loaded)
	var err: Error = into.restore(CAMPAIGN, saved)
	var fresh: CampaignSession = _fx.unknown_session()
	var attached: Error = loaded.attach(fresh)
	var vote: int = fresh.run.events.votes.get(0, NO_OPTION)
	_check("state: the round trip gives back every field, votes and the pending combat too", (
			err == OK and attached == OK
			and JSON.stringify(fresh.run.events.capture()) == JSON.stringify(events.capture())
			and fresh.run.events.votes.size() == 1 and vote == ICE
			and fresh.run.events.is_combat_pending
	), "%s / %s" % [error_string(err), error_string(attached)])
	_check("state: once attached, the section reads the run's events", (
			JSON.stringify(loaded.capture()) == JSON.stringify(fresh.run.events.capture())
	))

	var empty: EventSaveSection = EventSaveSection.new()
	var new_run: CampaignSession = _fx.unknown_session()
	_check("state: {} is a run with no events yet", (
			empty.restore({}) == OK and empty.attach(new_run) == OK
			and new_run.run.events.event_id.is_empty() and new_run.run.events.seen.is_empty()
	))
	var copied: EventRunState = events.copy()
	copied.seen.append("another")
	_check("state: a copy shares nothing with its source", not events.seen.has("another"))


func _test_refusals() -> void:
	var section: EventSaveSection = EventSaveSection.new()
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	registry.register(CAMPAIGN, section)
	var newer: Error = registry.restore(CAMPAIGN, {
		"events": {"version": EventSaveSection.VERSION + 1, "data": {"seen": [], "current": {}}},
	})
	_check("state: a newer events version is refused", newer == ERR_FILE_UNRECOGNIZED, (
			error_string(newer)
	))

	var made: CampaignSession = _fx.unknown_session()
	_fx.open(made, _pool)
	var good: Dictionary = _json(made.run.events.capture())
	var cases: Dictionary[String, Dictionary] = {
		"an empty seen id": _with(good, ["seen"], [""]),
		"a seat both choosing and chosen": _with(good, ["current", "seats", "0"], {
			"rolls": good["current"]["seats"]["0"]["rolls"], "choosing": 0, "chosen": 1,
		}),
		"a choice past the options": _with(good, ["current", "seats", "0", "chosen"], 9),
		"a vote past the options": _with(good, ["current", "votes"], {"0": 9}),
		"a vote for a seat not in the event": _with(good, ["current", "votes"], {"3": 0}),
		"a seat key that isn't a number": _with(good, ["current", "seats"], {"x": {}}),
		"a fractional node": _with(good, ["current", "node"], 1.5),
		"no event id": _with(good, ["current", "event"], ""),
	}
	for label: String in cases:
		var refused: EventSaveSection = EventSaveSection.new()
		_check("state: %s is refused" % [label], (
				refused.restore(cases[label]) == ERR_INVALID_DATA
		))
	var whole: EventSaveSection = EventSaveSection.new()
	_check("state: the saved data itself is accepted", whole.restore(good) == OK)


func _test_continue_before_choosing() -> void:
	var made: CampaignSession = _fx.unknown_session()
	_fx.open(made, _pool)
	var resumed: CampaignSession = _resume(made)
	if resumed == null:
		return
	_check("continue before choosing: the same event, rolls and named curses", (
			_view_text(resumed) == _view_text(made)
			and not resumed.run.events.seat_event(0).rolls_of(ICE).curse_id.is_empty()
	), "%s vs %s" % [_view_text(resumed), _view_text(made)])
	var again: CampaignBatch = _fx.open(resumed, _pool)
	_check("continue before choosing: the event isn't drawn again", (
			again.is_rejected() and again.rejected_reason.contains("already open")
	), again.rejected_reason)
	_fx.choose(made, _pool, 0, ICE)
	_fx.choose(resumed, _pool, 0, ICE)
	_check("continue before choosing: choosing gives the same item, id and curse", (
			_seat_text(resumed) == _seat_text(made)
	))


func _test_continue_mid_chooser() -> void:
	var made: CampaignSession = _fx.unknown_session()
	_fx.open(made, _pool)
	var opened: CampaignBatch = _fx.chooser(made, _pool, 0, 0)
	var resumed: CampaignSession = _resume(made)
	if resumed == null:
		return
	var view: EventView = EventNode.view(resumed, 0, _pool, _fx.catalog)
	_check("continue mid-chooser: the chooser of the same option is open", (
			not opened.is_rejected() and view.choosing == 0 and view.chosen == NO_OPTION
			and _view_text(resumed) == _view_text(made)
	), opened.rejected_reason)
	var unit_id: String = _fx.soldier(made.run.seat_run(0)).instance_id
	_fx.choose(made, _pool, 0, 0, EventChoice.new(unit_id))
	var chosen: CampaignBatch = _fx.choose(resumed, _pool, 0, 0, EventChoice.new(unit_id))
	_check("continue mid-chooser: picking the unit then gives the same outcome", (
			not chosen.is_rejected() and _seat_text(resumed) == _seat_text(made)
			and resumed.run.events.seat_event(0).choosing == NO_OPTION
	), chosen.rejected_reason)


func _test_continue_after_choosing() -> void:
	var made: CampaignSession = _fx.unknown_session()
	_fx.open(made, _pool)
	var unit_id: String = _fx.soldier(made.run.seat_run(0)).instance_id
	_fx.choose(made, _pool, 0, 0, EventChoice.new(unit_id))
	var resumed: CampaignSession = _resume(made)
	if resumed == null:
		return
	var view: EventView = EventNode.view(resumed, 0, _pool, _fx.catalog)
	_check("continue after choosing: the event shows chosen, with the outcome kept", (
			view.chosen == 0 and view.is_finished and _view_text(resumed) == _view_text(made)
			and _seat_text(resumed) == _seat_text(made)
	))
	var twice: CampaignBatch = _fx.choose(resumed, _pool, 0, 0, EventChoice.new(unit_id))
	_check("continue after choosing: the option can't be taken again", (
			twice.is_rejected() and twice.rejected_reason.contains("already chose")
	), twice.rejected_reason)


# made saved and loaded into a new session (Fixture.resume). Null, reported, when any step fails.
func _resume(made: CampaignSession) -> CampaignSession:
	var resumed: CampaignSession = _fx.resume(made)
	_check("continue: the save loads into a new session", resumed != null, (
			error_string(_fx.resume_error)
	))
	return resumed


# What the seat's event screen would show, as text.
func _view_text(made: CampaignSession) -> String:
	var view: EventView = EventNode.view(made, 0, _pool, _fx.catalog)
	var options: Array = []
	for shown: EventView.OptionView in view.options:
		options.append([shown.rolls.capture(), shown.curse_id, shown.unmet_reason])
	return JSON.stringify([
		view.event.id if view.is_open() else "", view.choosing, view.chosen, options,
	])


# Seat 0's roster, heirlooms, runes and gold, as text.
func _seat_text(made: CampaignSession) -> String:
	var seat_run: SeatRun = made.run.seat_run(0)
	return JSON.stringify([
		seat_run.capture_roster(), seat_run.capture_heirlooms(), seat_run.capture_runes(),
		seat_run.capture_economy(),
	])


# A deep copy of data with the value at path replaced.
func _with(data: Dictionary, path: Array, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	var at: Dictionary = copy
	for index: int in path.size() - 1:
		at = at[path[index]]
	at[path[path.size() - 1]] = value
	return copy


func _json(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
