# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     instance_id_allocator.gd
# Author:
# Created:  October 28, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name InstanceIdAllocator
extends RefCounted
## Mints every instance id of a run, such as [code]item:412[/code] or [code]unit:57[/code], from one
## counter shared by a preset per kind.
##
## Owned by the host's [CampaignSession]. Every session on the host mints from it on the main
## thread, so parallel maps can't collide. Ids are never parsed and never reused: what an instance
## is lives in its own data, and the kind prefix is only for people reading logs. Log and error text
## comes from [method describe], never from taking an id apart.[br]
## The counter is saved with the campaign and at every combat checkpoint (event bus plan EB7), so
## a resumed enemy phase mints the same ids; [method get_next_value] is what gets saved.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The value the first id of a run carries: ids count from 1.
const FIRST_VALUE: int = 1

# The next value to mint, shared by every kind.
var _next: int = FIRST_VALUE

# Display text per id: every minted id (empty text when it has none) and ids named later.
var _labels: Dictionary[String, String] = {}


## A new item id. [param label]: display text for [method describe], such as "Iron Axe".
func next_item_id(label: String = "") -> String:
	return _mint("item", label)


## A new id for a player's unit. [param label]: display text, such as its unit type.
func next_unit_id(label: String = "") -> String:
	return _mint("unit", label)


## A new id for an enemy unit. [param label]: display text, such as its class.
func next_enemy_id(label: String = "") -> String:
	return _mint("enemy", label)


## A new rune id, so two copies of one rune are told apart (event bus plan, fix F2).
## [param label]: display text, such as "Mend".
func next_rune_id(label: String = "") -> String:
	return _mint("rune", label)


## A new effect instance id, the [member CombatFact.source_effect_id] of what it causes.
## [param label]: display text, usually empty: [method CombatSession.describe] names an effect by
## its definition and owner.
func next_effect_id(label: String = "") -> String:
	return _mint("effect", label)


## The value the next id will carry. Never decreases.
func get_next_value() -> int:
	return _next


## Names [param id] in [method describe]. Also how an id not minted here, such as a seat's subject
## id ([method seat_subject_id]), becomes known.
func set_label(id: String, label: String) -> void:
	if id.is_empty():
		return
	_labels[id] = label


## Whether [param id] was minted here or named with [method set_label].
func is_known(id: String) -> bool:
	return _labels.has(id)


## The display text of [param id]; empty when it has none or is unknown.
func label_of(id: String) -> String:
	return _labels.get(id, "")


## [param id] with its display text, such as [code]item:412 (Iron Axe)[/code]; the bare id when it
## has no text or is unknown.
func describe(id: String) -> String:
	var label: String = label_of(id)
	return id if label.is_empty() else "%s (%s)" % [id, label]


func _mint(kind: String, label: String) -> String:
	var id: String = "%s:%d" % [kind, _next]
	_next += 1
	_labels[id] = label
	return id


# A seat, not an instance, so it never comes from the counter.
## The id [param seat]'s army is queried by, [code]seat:N[/code]: the
## [member EffectOwner.owner_id] of its heirlooms and curses.
static func seat_subject_id(seat: int) -> String:
	return "seat:%d" % [seat]


# A map object's spot, not a minted instance: its id is the same on every co-op copy of the map
# and every load (combat map plan, Authoring and loading), so it never comes from the counter.
## The id of the map object on spot [param spot_index] ([member MapLayout.Marker.index]),
## [code]object:N[/code]. Named with [method set_label] when the object is placed.
static func object_id(spot_index: int) -> String:
	return "object:%d" % [spot_index]


# Not minted, for the same reason as object_id().
## The id of reinforcement point [param point_index] ([member MapLayout.Marker.index]),
## [code]point:N[/code]. Named with [method set_label] when its waves are loaded.
static func point_id(point_index: int) -> String:
	return "point:%d" % [point_index]
