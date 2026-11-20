# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_requirements.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name EventRequirements
extends Resource
## What an event option needs before it can be chosen: gold, a unit type, the commander, an
## item, a fallen unit, or room to grow the army. An unmet one greys the option out, with the
## reason shown (events.md, Rules).
##
## [method unmet_reason] checks every requirement once over the whole army, never unit by unit,
## so the first unit can't decide for the rest. Pure: it reads the seat's run and changes
## nothing. In co-op an option needs every seat to meet it; that check is the caller's.
##
## @tutorial(Events): docs/design/events.md

## The most units an army may ever hold (game-vision.md, Army: the hard ceiling).[br]
## [b]Units:[/b] units.
const ARMY_SIZE_CEILING: int = 8

## Gold the seat must hold.[br]
## [b]Units:[/b] gold. [b]0:[/b] none needed.
@export_range(0, 1000, 1, "or_greater") var gold: int = 0

## Content id of a unit type the living army must include, such as [code]archer[/code].
## [b]Empty:[/b] none needed.
@export var unit_type_id: String = ""

## Whether the army's commander must be alive in the army.
@export var needs_commander: bool = false

## Content id of an item a living unit or the convoy must hold. [b]Empty:[/b] none needed.
@export var item_id: String = ""

## Whether at least one unit must have fallen.
@export var needs_fallen_unit: bool = false

## Whether max army size must be below [constant ARMY_SIZE_CEILING], so it can still grow.
@export var needs_army_room: bool = false


## Why [param seat_run] doesn't meet these requirements: the first unmet one, in field order.
## Empty when it meets them all. [param catalog] names unit types and items in the reason.
func unmet_reason(seat_run: SeatRun, catalog: EffectCatalog.Index) -> String:
	if seat_run.gold < gold:
		return "needs %d gold" % [gold]
	if not unit_type_id.is_empty() and not _has_unit_type(seat_run):
		return "needs a %s in the army" % [_name_of(catalog, unit_type_id)]
	if needs_commander and EventOutcome.living_unit(seat_run, seat_run.commander_id) == null:
		return "needs the commander"
	if not item_id.is_empty() and not _holds_item(seat_run):
		return "needs a %s" % [_name_of(catalog, item_id)]
	if needs_fallen_unit and seat_run.fallen.is_empty():
		return "needs a fallen unit"
	if needs_army_room and max_army_size(seat_run, catalog) >= ARMY_SIZE_CEILING:
		return "the army is already at its largest (%d)" % [ARMY_SIZE_CEILING]
	return ""


func _has_unit_type(seat_run: SeatRun) -> bool:
	for unit: UnitInstance in seat_run.army:
		if unit.unit_type_id == unit_type_id:
			return true
	return false


# Held by a living unit or in the convoy: a fallen unit's items aren't the army's until taken.
func _holds_item(seat_run: SeatRun) -> bool:
	var places: PackedStringArray = seat_run.convoy.duplicate()
	for unit: UnitInstance in seat_run.army:
		places.append_array(unit.item_ids())
	for held_id: String in places:
		var held: ItemInstance = seat_run.items.get(held_id, null)
		if held != null and held.definition_id == item_id:
			return true
	return false


## [param seat_run]'s own max army size ([method RunOperations.max_army_size]: its faction's, its
## heirlooms' and curses', and its event changes). 0 for a faction not in [param catalog].
static func max_army_size(seat_run: SeatRun, catalog: EffectCatalog.Index) -> int:
	return RunOperations.max_army_size(seat_run, catalog)


static func _name_of(catalog: EffectCatalog.Index, id: String) -> String:
	var carrier: EffectCarrierDefinition = catalog.definition(id) as EffectCarrierDefinition
	return id if carrier == null or carrier.display_name.is_empty() else carrier.display_name
