# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_save_sections.gd
# Author:
# Created:  November 13, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name RunSaveSections
extends RefCounted
## The save sections of a run's [CampaignRunState] in the [code]CAMPAIGN[/code] block:
## [code]campaign_map[/code] and [code]run_flow[/code] ([SaveSection]s), and per seat
## [code]roster[/code], [code]heirlooms[/code], [code]runes[/code] and [code]economy[/code]
## ([PlayerSaveSection]s): [code]economy[/code] at [constant ECONOMY_VERSION],
## [code]heirlooms[/code] at [constant HEIRLOOMS_VERSION], the rest at [constant VERSION].
## [code]CampaignService[/code] registers them, map before flow.[br]
## [b]Load order:[/b] sections restore before the run's session exists, so each only checks its data
## and holds it; [method attach] builds the session's [member CampaignSession.run] from it.
## [code]{}[/code] is a part with no run, as a new run's first save writes before its session is
## built: when every part is empty, [method attach] says so and the caller builds the run. A file
## with only some parts is refused at [method attach] and kept as it was.
##
## @tutorial(Save system design): docs/design/save-system.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The part of the run a section saves.
enum Part {
	## The graph and the route: [method CampaignRunState.capture_map].
	MAP,
	## The stage and the shared state: [method RunFlow.capture].
	FLOW,
	## Army, convoy, fallen units and items: [method SeatRun.capture_roster].
	ROSTER,
	## Owned heirlooms and curses, copies included: [method SeatRun.capture_heirlooms].
	HEIRLOOMS,
	## The rune slots: [method SeatRun.capture_runes].
	RUNES,
	## Gold, the rare offset and pending offers: [method SeatRun.capture_economy].
	ECONOMY,
}

## The data version of every section but [code]economy[/code] ([constant ECONOMY_VERSION]) and
## [code]heirlooms[/code] ([constant HEIRLOOMS_VERSION]).
const VERSION: int = 1

## The [code]heirlooms[/code] section's data version. 2: it carries the seat's value changes
## ([member SeatRun.value_changes]); a version 1 section has none and reads as it is.
const HEIRLOOMS_VERSION: int = 2

## The [code]economy[/code] section's data version. 2: the combat report in its pending offers
## carries each unit's battle stats ([constant CampaignRunState.COMBAT_REPORT_KEY]); a version 1
## report has none and reads as it is.
const ECONOMY_VERSION: int = 2

# Section keys. Never change one: it is how saved data finds its owner (save-system.md).
const _KEYS: Dictionary[Part, String] = {
	Part.MAP: "campaign_map",
	Part.FLOW: "run_flow",
	Part.ROSTER: "roster",
	Part.HEIRLOOMS: "heirlooms",
	Part.RUNES: "runes",
	Part.ECONOMY: "economy",
}

const _SEAT_PARTS: Array[Part] = [Part.ROSTER, Part.HEIRLOOMS, Part.RUNES, Part.ECONOMY]

## The [code]campaign_map[/code] section.
var map: SharedSection = null

## The [code]run_flow[/code] section.
var flow: SharedSection = null

## The per-seat sections, in [enum Part] order: roster, heirlooms, runes, economy.
var seat_sections: Array[SeatSection] = []

# Shared by every section; the sections hold it, never this object, so nothing forms a cycle.
var _store: Store = Store.new()


func _init() -> void:
	map = SharedSection.new(_store, Part.MAP)
	flow = SharedSection.new(_store, Part.FLOW)
	for part: Part in _SEAT_PARTS:
		seat_sections.append(SeatSection.new(_store, part))


## Builds [param session]'s run from the held data and reads it from then on. Returns
## [constant OK]; [constant ERR_DOES_NOT_EXIST] when every part is empty (the session is attached
## with no run, for the caller to build one); [constant ERR_INVALID_PARAMETER] for null; or
## [constant ERR_INVALID_DATA] when only some parts hold a run, leaving the data held, unattached.
func attach(session: CampaignSession) -> Error:
	if session == null:
		push_error("RunSaveSections: attach needs a session")
		return ERR_INVALID_PARAMETER
	var present: int = 0
	var expected: int = 2 + _SEAT_PARTS.size() * session.seats.size()
	for part: Part in [Part.MAP, Part.FLOW]:
		present += 0 if _store.held(part).is_empty() else 1
	for seat: int in session.seats:
		for part: Part in _SEAT_PARTS:
			present += 0 if _store.held_seat(seat, part).is_empty() else 1
	if present == 0:
		_store.drop_held()
		_store.session = session
		return ERR_DOES_NOT_EXIST
	if present != expected:
		push_error(
				"RunSaveSections: the save holds %d of the run's %d parts; the run can't load"
				% [present, expected]
		)
		return ERR_INVALID_DATA
	session.run = _store.build(session.seats)
	_store.drop_held()
	_store.session = session
	return OK


## Stops reading the attached session: the run it belongs to was closed or replaced.
func detach() -> void:
	_store.session = null



# NOTE: The inner classes below read this file's constants and enum directly, never through
# "RunSaveSections.": an inner class naming its own outer class makes a script reference cycle,
# which keeps every script and resource it reaches (the content catalog included) alive at exit.
## What every section shares: the attached session, or the data held until one attaches.
class Store:
	extends RefCounted

	## The session whose run the sections capture; null until attached.
	var session: CampaignSession = null
	## The held map, parsed, so the flow can be checked against it; null when none is held.
	var scratch: CampaignRunState = null

	# Held data by part, and by "seat/part" for seat parts; {} is a part with no run.
	var _held: Dictionary[int, Dictionary] = {}
	var _held_seats: Dictionary[String, Dictionary] = {}

	## The held data of a shared [param part]; empty when none.
	func held(part: int) -> Dictionary:
		return _held.get(part, {})

	## The held data of [param seat]'s [param part]; empty when none.
	func held_seat(seat: int, part: int) -> Dictionary:
		return _held_seats.get(_seat_key(seat, part), {})

	## Holds [param data] for a shared [param part].
	func hold(part: int, data: Dictionary) -> void:
		_held[part] = data

	## Holds [param data] for [param seat]'s [param part].
	func hold_seat(seat: int, part: int, data: Dictionary) -> void:
		_held_seats[_seat_key(seat, part)] = data

	## Drops a shared [param part]'s held data.
	func drop(part: int) -> void:
		_held.erase(part)
		if part == Part.MAP:
			scratch = null

	## Drops [param seat]'s held [param part].
	func drop_seat(seat: int, part: int) -> void:
		_held_seats.erase(_seat_key(seat, part))

	## Drops every seat's held [param part].
	func drop_every_seat(part: int) -> void:
		for key: String in _held_seats.keys():
			if key.ends_with("/%d" % [part]):
				_held_seats.erase(key)

	## Drops everything held.
	func drop_held() -> void:
		_held.clear()
		_held_seats.clear()
		scratch = null

	## A run from the held data, which every restore already checked, for [param seats].
	func build(seats: PackedInt32Array) -> CampaignRunState:
		var run: CampaignRunState = CampaignRunState.new()
		run.restore_map(held(Part.MAP))
		run.restore_flow(held(Part.FLOW))
		for seat: int in seats:
			var seat_run: SeatRun = SeatRun.new(seat)
			seat_run.restore_roster(held_seat(seat, Part.ROSTER))
			seat_run.restore_heirlooms(held_seat(seat, Part.HEIRLOOMS))
			seat_run.restore_runes(held_seat(seat, Part.RUNES))
			seat_run.restore_economy(held_seat(seat, Part.ECONOMY))
			run.seats[seat] = seat_run
		return run

	func _seat_key(seat: int, part: int) -> String:
		return "%d/%d" % [seat, part]


## The [code]campaign_map[/code] or [code]run_flow[/code] section. A campaign reset (a new run, a
## run dropped) also lets go of the session.
class SharedSection:
	extends SaveSection

	var _store: Store = null
	var _part: Part = Part.MAP

	func _init(store: Store, part: Part) -> void:
		_store = store
		_part = part

	func get_key() -> String:
		return _KEYS[_part]

	func get_version() -> int:
		return VERSION

	## The attached session's run, else the held data; [code]{}[/code] with neither.
	func capture() -> Dictionary:
		if _store.session != null:
			var run: CampaignRunState = _store.session.run
			if run == null:
				return {}
			return run.capture_map() if _part == Part.MAP else run.flow.capture()
		return _store.held(_part).duplicate(true)

	## Checks [param data] and holds it; the flow is checked against the map, which restores
	## first. Lets go of any attached session. [constant ERR_INVALID_DATA] for unusable data.
	func restore(data: Dictionary) -> Error:
		_store.session = null
		if data.is_empty():
			_store.drop(_part)
			_store.hold(_part, {})
			return OK
		if _part == Part.MAP:
			var parsed: CampaignRunState = CampaignRunState.new()
			if parsed.restore_map(data) != OK:
				return ERR_INVALID_DATA
			_store.scratch = parsed
			_store.hold(_part, parsed.capture_map())
			return OK
		if _store.scratch == null:
			push_error("RunSaveSections: a run flow with no campaign map")
			return ERR_INVALID_DATA
		if _store.scratch.restore_flow(data) != OK:
			return ERR_INVALID_DATA
		_store.hold(_part, _store.scratch.flow.capture())
		return OK

	func reset() -> void:
		_store.drop(_part)
		_store.session = null


## One of a seat's four sections: [code]roster[/code], [code]heirlooms[/code],
## [code]runes[/code] or [code]economy[/code].
class SeatSection:
	extends PlayerSaveSection

	var _store: Store = null
	var _part: Part = Part.ROSTER

	func _init(store: Store, part: Part) -> void:
		_store = store
		_part = part

	func get_key() -> String:
		return _KEYS[_part]

	func get_version() -> int:
		match _part:
			Part.ECONOMY:
				return ECONOMY_VERSION
			Part.HEIRLOOMS:
				return HEIRLOOMS_VERSION
		return VERSION

	## [code]economy[/code] and [code]heirlooms[/code] from version 1 need no change: a combat
	## report without stats reads as one with none, and heirlooms without value changes as a seat
	## with none. Every other part has no older version.
	func migrate(data: Dictionary, from_version: int) -> Error:
		if (_part == Part.ECONOMY or _part == Part.HEIRLOOMS) and from_version == 1:
			return OK
		return super(data, from_version)

	## The attached session's seat, else the held data; [code]{}[/code] with neither.
	func capture(seat: int) -> Dictionary:
		if _store.session == null:
			return _store.held_seat(seat, _part).duplicate(true)
		var run: CampaignRunState = _store.session.run
		var seat_run: SeatRun = run.seat_run(seat) if run != null else null
		if seat_run == null:
			return {}
		match _part:
			Part.ROSTER:
				return seat_run.capture_roster()
			Part.HEIRLOOMS:
				return seat_run.capture_heirlooms()
			Part.RUNES:
				return seat_run.capture_runes()
		return seat_run.capture_economy()

	## Checks [param data] on a scratch seat and holds it. [constant ERR_INVALID_DATA] for
	## unusable data.
	func restore(seat: int, data: Dictionary) -> Error:
		_store.session = null
		if data.is_empty():
			_store.hold_seat(seat, _part, {})
			return OK
		var parsed: SeatRun = SeatRun.new(seat)
		var err: Error = OK
		var held: Dictionary = {}
		match _part:
			Part.ROSTER:
				err = parsed.restore_roster(data)
				held = parsed.capture_roster()
			Part.HEIRLOOMS:
				err = parsed.restore_heirlooms(data)
				held = parsed.capture_heirlooms()
			Part.RUNES:
				err = parsed.restore_runes(data)
				held = parsed.capture_runes()
			_:
				err = parsed.restore_economy(data)
				held = parsed.capture_economy()
		if err != OK:
			return ERR_INVALID_DATA
		_store.hold_seat(seat, _part, held)
		return OK

	func reset(seat: int) -> void:
		_store.drop_seat(seat, _part)

	func clear() -> void:
		_store.drop_every_seat(_part)
		_store.session = null
