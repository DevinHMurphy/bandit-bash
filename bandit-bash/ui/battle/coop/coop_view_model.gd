# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_view_model.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name CoopViewModel
extends RefCounted
## What a co-op battle's panels show one seat, read from the [CombatEncounter] as it stands: each
## map's status ([MapStatus]), the units the seat could send ([SendableUnit]), whether it may send
## now and where, and when a send would land.
##
## Reading only, and static: it never submits or changes state. The send rules here follow
## [SendUnitsCommand]'s, so the panel offers only what the encounter would accept; the encounter
## still checks every send when it resolves. The same reads work on a host and on a client's
## mirror, since frozen maps and the run's loss are derived from each map's state.
##
## @tutorial(Co-op combat plan): docs/plans/2026-11-20-coop-combat.md

## [method arrival_turn] of a send that lands at once (on a frozen map).
const AT_ONCE: int = 0

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY


## Every map of [param encounter] as [param seat] sees it: the seat's own first, then by session
## id. A forfeited map ([method CombatEncounter.is_map_forfeited]) has left every view and isn't
## listed. Empty for no encounter.
static func maps(encounter: CombatEncounter, seat: int) -> Array[MapStatus]:
	var found: Array[MapStatus] = []
	if encounter == null:
		return found
	var own: CombatSession = encounter.session_of_seat(seat)
	if own != null and not encounter.is_map_forfeited(own.session_id):
		found.append(status(encounter, own.session_id, seat))
	for session: CombatSession in encounter.get_sessions():
		if session != own and not encounter.is_map_forfeited(session.session_id):
			found.append(status(encounter, session.session_id, seat))
	return found


## The map [param session_id] of [param encounter] as [param seat] sees it; null for no such map.
static func status(encounter: CombatEncounter, session_id: int, seat: int) -> MapStatus:
	var session: CombatSession = encounter.get_session(session_id)
	if session == null:
		return null
	var state: CombatState = session.state
	var shown: MapStatus = MapStatus.new()
	shown.session_id = session_id
	shown.owner_seat = owner_of(session)
	shown.is_own = session.seats.has(seat)
	shown.title = map_title(session, seat)
	shown.turn = state.turn
	shown.units_left = state.units_of(PLAYER).size()
	shown.enemies_left = state.units_of(ENEMY).size()
	shown.is_finished = session.is_finished
	shown.is_won = session.is_won
	shown.is_aid_called = encounter.is_aid_called(session_id)
	shown.is_frozen = encounter.is_frozen(session_id)
	shown.has_units = PhaseRunner.seats_with_units(session).has(seat)
	shown.can_act = shown.has_units and can_act_on(session, seat)
	for unit_id: String in encounter.units_in_transit():
		if _target_of(encounter, unit_id) == session_id:
			shown.arriving += 1
	return shown


## A map's name for [param seat]: "Your map" for its own, else its owner's, such as
## "Player 2's map" ([method CampaignLink.seat_name]).
static func map_title(session: CombatSession, seat: int) -> String:
	if session.seats.has(seat) or session.seats.is_empty():
		return "Your map"
	return "%s's map" % [CampaignLink.seat_name(owner_of(session))]


## The seat whose map [param session] is: the lowest of its own seats (one per map in parallel
## maps); -1 for a map with none. A map's owner, never the screen's own seat, which is
## [method CampaignService.local_seat].
static func owner_of(session: CombatSession) -> int:
	var lowest: int = -1
	for seat: int in session.seats:
		if lowest < 0 or seat < lowest:
			lowest = seat
	return lowest


## Whether [param seat] has something to do on [param session] now: its opening swap window, or
## its part of the player phase.
static func can_act_on(session: CombatSession, seat: int) -> bool:
	if session.is_finished:
		return false
	if TurnInputModel.is_swapping(session, seat):
		return true
	return (
			CommandValidator.player_phase_reason(session, seat).is_empty()
			and PhaseRunner.seats_with_units(session).has(seat)
	)


## Whether any map of [param encounter] is frozen ([method CombatEncounter.is_frozen]).
static func is_any_frozen(encounter: CombatEncounter) -> bool:
	if encounter == null:
		return false
	for session: CombatSession in encounter.get_sessions():
		if encounter.is_frozen(session.session_id):
			return true
	return false


## How many maps of [param encounter] are still being fought; a forfeited one isn't waited for.
static func maps_left(encounter: CombatEncounter) -> int:
	var left: int = 0
	if encounter == null:
		return left
	for session: CombatSession in encounter.get_sessions():
		if not session.is_finished and not encounter.is_map_forfeited(session.session_id):
			left += 1
	return left


## Every unit [param seat] could send now: its surviving player units whose current record is on
## a won map ([method CombatEncounter.session_of_unit]) and that aren't on their way, its own map's
## first, then by map and in state order.
static func sendable(encounter: CombatEncounter, seat: int) -> Array[SendableUnit]:
	var found: Array[SendableUnit] = []
	if encounter == null:
		return found
	var travelling: PackedStringArray = encounter.units_in_transit()
	var sources: Array[CombatSession] = []
	var own: CombatSession = encounter.session_of_seat(seat)
	if own != null:
		sources.append(own)
	for session: CombatSession in encounter.get_sessions():
		if session != own:
			sources.append(session)
	for source: CombatSession in sources:
		if not source.is_finished or not source.is_won:
			continue
		for unit_id: String in source.state.units_of(PLAYER):
			if (
					source.state.seat_of(unit_id) != seat
					or travelling.has(unit_id)
					or encounter.session_of_unit(unit_id) != source
			):
				continue
			var unit: HudViewModel.UnitView = HudViewModel.unit_view(source, unit_id)
			var shown: SendableUnit = SendableUnit.new()
			shown.unit_id = unit_id
			shown.name = unit.name
			shown.hp = unit.hp
			shown.max_hp = unit.max_hp
			shown.source_session_id = source.session_id
			found.append(shown)
	return found


## The won map a send of no units goes from for [param seat]: its own when won, else the first won
## map holding a unit it could send; -1 for none.
static func send_source(encounter: CombatEncounter, seat: int) -> int:
	if encounter == null:
		return -1
	var own: CombatSession = encounter.session_of_seat(seat)
	if own != null and own.is_finished and own.is_won:
		return own.session_id
	var units: Array[SendableUnit] = sendable(encounter, seat)
	return units[0].source_session_id if not units.is_empty() else -1


## Whether [param seat] may send now, as [SendUnitsCommand] allows: while any map is frozen, when
## it has a unit to send; otherwise once, from a won map, while another map is still fought.
static func can_send(encounter: CombatEncounter, seat: int) -> bool:
	if encounter == null or encounter.seats.size() <= 1:
		return false
	if is_any_frozen(encounter):
		return not sendable(encounter, seat).is_empty()
	if encounter.has_sent(seat) or send_source(encounter, seat) < 0:
		return false
	return not targets(encounter, seat, send_source(encounter, seat)).is_empty()


## Whether a send of no units is allowed now: [method can_send] with no map frozen.
static func can_send_none(encounter: CombatEncounter, seat: int) -> bool:
	return can_send(encounter, seat) and not is_any_frozen(encounter)


## Why the map [param session_id] can't take a send from [param source_id] now; empty when it can:
## a map still fought, not forfeited, that isn't the source, and a frozen one while any map is
## frozen.
static func target_reason(encounter: CombatEncounter, session_id: int, source_id: int) -> String:
	var target: CombatSession = encounter.get_session(session_id)
	if target == null or session_id == source_id:
		return "not a map to send to"
	if target.is_finished:
		return "its combat has ended"
	if encounter.is_map_forfeited(session_id):
		return "its player left"
	if is_any_frozen(encounter) and not encounter.is_frozen(session_id):
		return "a map is frozen: send to a frozen map"
	return ""


## Every map a send from [param source_id] may go to now, by session id.
static func targets(encounter: CombatEncounter, seat: int, source_id: int) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for shown: MapStatus in maps(encounter, seat):
		if target_reason(encounter, shown.session_id, source_id).is_empty():
			found.append(shown.session_id)
	return found


## The receiving map's turn a send from [param source_id] lands at, by the battle clock: its first
## player Phase Start after the turn the source was won on, and after its turn now; [constant
## AT_ONCE] on a frozen map. -1 for an unknown map. A unit with no free tile waits longer.
static func arrival_turn(encounter: CombatEncounter, source_id: int, target_id: int) -> int:
	var source: CombatSession = encounter.get_session(source_id)
	var target: CombatSession = encounter.get_session(target_id)
	if source == null or target == null:
		return -1
	if encounter.is_frozen(target_id):
		return AT_ONCE
	return maxi(source.state.turn + 1, target.state.turn + 1)


# The map unit_id, on its way, was last sent to: the key of its latest UNIT_SENT on the
# encounter's log, which a mirror holds too; the encounter exposes no transfer's target.
static func _target_of(encounter: CombatEncounter, unit_id: String) -> int:
	for i: int in range(encounter.fact_log.size() - 1, -1, -1):
		var fact: CombatFact = encounter.fact_log[i]
		if fact.kind == CombatFact.Kind.UNIT_SENT and fact.actor_id == unit_id:
			return fact.key
	return -1


## One map as a seat sees it.
class MapStatus:
	extends RefCounted

	## The map's session id.
	var session_id: int = -1
	## The seat whose map it is; -1 for a map with no seat.
	var owner_seat: int = -1
	## Whether it is the seat's own map.
	var is_own: bool = false
	## Its name for the seat ([method CoopViewModel.map_title]).
	var title: String = ""
	## Its turn now.
	var turn: int = 0
	## Player units on it, of any seat.
	var units_left: int = 0
	## Enemy units on it.
	var enemies_left: int = 0
	## Whether its combat has ended, and whether it was won.
	var is_finished: bool = false
	var is_won: bool = false
	## Whether its call for aid is raised.
	var is_aid_called: bool = false
	## Whether it is frozen ([method CombatEncounter.is_frozen]).
	var is_frozen: bool = false
	## Whether the seat has units on it, and whether they have something to do now.
	var has_units: bool = false
	var can_act: bool = false
	## Units of any seat on their way to it.
	var arriving: int = 0


## One unit a seat could send.
class SendableUnit:
	extends RefCounted

	## The unit's instance id.
	var unit_id: String = ""
	## Its name ([method BattleText.name_of]).
	var name: String = ""
	## Its HP now and its max HP.
	var hp: int = 0
	var max_hp: int = 0
	## The won map it would go from.
	var source_session_id: int = -1
