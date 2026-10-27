# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_owner.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name EffectOwner
extends RefCounted
## Who an [EffectInstance] belongs to: a unit, an item (resolved to the unit holding it), an army
## (a seat), a rune, or a map object.
##
## Scope is evaluated relative to the owner: This unit is [member holder_id]; Your Unit is every
## unit of [member side] and [member seat]. Plain data with ids only, so a sandbox can copy it.
## Use the static constructors.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## What kind of thing owns the effect.
enum Kind {
	## A unit's own trait.
	UNIT = 0,
	## An item; its effects act through the unit holding it.
	ITEM = 1,
	## A player's army: heirlooms and curses. No unit holds them.
	ARMY = 2,
	## A rune cast this combat. No unit holds it; it acts on the command's target.
	RUNE = 3,
	# ASSUMPTION: map-object cascades are exempted by owner kind; the plan exempts "map-object
	# cascades" without saying how the engine recognizes one.
	## A map object such as a powder keg. Its reactions are exempt from the reaction caps.
	MAP_OBJECT = 4,
}

## What kind of thing owns the effect.
var kind: Kind = Kind.UNIT

## Instance id of the owner: the unit, item, rune or object, or the seat's subject id for an army
## (the id its campaign values are queried by).
var owner_id: String = ""

## Instance id of the unit the effect acts through: the unit itself, or the item's holder. Empty
## for an army, a rune, or an item nobody holds (in the convoy).
var holder_id: String = ""

## The owning player's seat; [code]-1[/code] for enemies and map objects.
var seat: int = -1

## The owner's side, for scopes and side filters. [constant CombatFact.CombatSide.NONE] for a map
## object.
var side: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER


## The id the owner's values are queried by: [member holder_id], or [member owner_id] for an army.
func subject_id() -> String:
	return owner_id if kind == Kind.ARMY else holder_id


## A copy, for a sandbox.
func copy() -> EffectOwner:
	var owner: EffectOwner = EffectOwner.new()
	owner.kind = kind
	owner.owner_id = owner_id
	owner.holder_id = holder_id
	owner.seat = seat
	owner.side = side
	return owner


## A unit's own trait. [param unit_seat]: [code]-1[/code] for an enemy.
static func for_unit(
		unit_id: String, unit_seat: int, unit_side: CombatFact.CombatSide
) -> EffectOwner:
	return _make(Kind.UNIT, unit_id, unit_id, unit_seat, unit_side)


## An item held by [param holder] (empty: held by nobody).
static func for_item(
		item_id: String, holder: String, unit_seat: int, unit_side: CombatFact.CombatSide
) -> EffectOwner:
	return _make(Kind.ITEM, item_id, holder, unit_seat, unit_side)


## A player's army, queried as [param seat_subject_id].
static func for_army(seat_subject_id: String, army_seat: int) -> EffectOwner:
	return _make(Kind.ARMY, seat_subject_id, "", army_seat, CombatFact.CombatSide.PLAYER)


## A rune cast by [param caster_seat].
static func for_rune(rune_id: String, caster_seat: int) -> EffectOwner:
	return _make(Kind.RUNE, rune_id, "", caster_seat, CombatFact.CombatSide.PLAYER)


## A map object; it acts through itself, as its own holder.
static func for_object(object_id: String) -> EffectOwner:
	return _make(Kind.MAP_OBJECT, object_id, object_id, -1, CombatFact.CombatSide.NONE)


static func _make(
		owner_kind: Kind,
		id: String,
		holder: String,
		owner_seat: int,
		owner_side: CombatFact.CombatSide
) -> EffectOwner:
	var owner: EffectOwner = EffectOwner.new()
	owner.kind = owner_kind
	owner.owner_id = id
	owner.holder_id = holder
	owner.seat = owner_seat
	owner.side = owner_side
	return owner
