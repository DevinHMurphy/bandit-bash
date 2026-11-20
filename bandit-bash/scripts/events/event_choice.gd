# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_choice.gd
# Author:
# Created:  November 19, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name EventChoice
extends RefCounted
## What a player picked after choosing an event option: the unit or weapon its blocks act on,
## where each new item goes, the rune slot to free when every slot is full, and the unit to
## dismiss when a recruit or a revived unit joins a full army.
##
## Plain data with ids only, filled in by the event screen's choosers and checked by
## [EventResolver] against the run as it stands.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## [member rune_discard_slot] when no rune is discarded.
const NO_SLOT: int = -1

## Instance id of the chosen unit: a living one, or a fallen one for the revive shrine.
## [b]Empty:[/b] none chosen.
var unit_id: String = ""

## Instance id of the chosen weapon or staff. [b]Empty:[/b] none chosen.
var weapon_id: String = ""

## Where each item-granting block's new item goes, by the block's index in its option.
## [b]Missing:[/b] into the convoy.
var placements: Dictionary[int, ItemPlacement] = {}

## The rune slot emptied for a new rune when every slot holds one; [constant NO_SLOT] when a slot
## is free.
var rune_discard_slot: int = NO_SLOT

## Instance id of the living unit that leaves the army for good, its items to the convoy, so a
## recruit or a revived unit can join a full army (recruiting past the max). Never the commander.
## [b]Empty:[/b] none; needed exactly when the army is full.
var replaced_id: String = ""


func _init(chosen_unit_id: String = "", chosen_weapon_id: String = "") -> void:
	unit_id = chosen_unit_id
	weapon_id = chosen_weapon_id


## Where the block at [param index] puts its new item: its placement, or the convoy.
func placement_for(index: int) -> ItemPlacement:
	return placements.get(index, ItemPlacement.new())
