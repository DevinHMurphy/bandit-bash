# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     regear_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name RegearCommand
extends CampaignCommand
## One re-gearing move at a Camp ([method Regear.move]): a seat's item to a living unit's slot,
## or to the convoy, swapping with the item in a filled slot. Valid inside a Camp, before or after
## the seat's choice.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the item, the unit and the slot
## travel.
const WIRE_TYPE: String = "regear"

## Instance id of the item moved.
var item_id: String = ""

## Instance id of the living unit it moves to. [b]Empty:[/b] the convoy.
var unit_id: String = ""

## The slot of [member unit_id] it moves to; unused for the convoy.
var slot: Loadout.Slot = Loadout.Slot.WEAPON

## Content the run's units and items come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(
		sender: int = -1,
		item: String = "",
		unit: String = "",
		to_slot: Loadout.Slot = Loadout.Slot.WEAPON
) -> void:
	seat = sender
	item_id = item
	unit_id = unit
	slot = to_slot


func get_label() -> String:
	if unit_id.is_empty():
		return "move %s to the convoy" % [item_id]
	return "move %s to %s's %s" % [
		item_id, unit_id, (Loadout.Slot.find_key(slot) as String).to_lower(),
	]


func validate(run: CampaignRunState) -> String:
	return Regear.move_problem(run, seat, item_id, unit_id, slot, _contents())


func resolve(run: CampaignRunState) -> void:
	Regear.move(run, seat, item_id, unit_id, slot)


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [item_id, unit_id, slot]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 3 or not values[0] is String or not values[1] is String:
		return false
	var to_slot: Variant = _wire_enum(values[2], Loadout.Slot.values())
	if to_slot == null:
		return false
	item_id = values[0]
	unit_id = values[1]
	slot = to_slot as Loadout.Slot
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
