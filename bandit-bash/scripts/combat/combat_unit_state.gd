# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_unit_state.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name CombatUnitState
extends RefCounted
## One unit's state on one map: where it stands, its HP, Block and Stance, and what it has done
## this turn and phase.
##
## Plain data with ids only, owned by [CombatState]. Maximum HP, maximum Stance and every combat
## value are queries ([method EffectEngine.stats]), never stored here. Rules code changes HP,
## Block and Stance only through the effect engine's resource paths and the combat core's damage
## rules, which emit the facts.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## Instance id, such as [code]unit:57[/code]. Never parsed.
var id: String = ""

## The unit's side.
var side: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

## The seat controlling it; [code]-1[/code] for an enemy.
var seat: int = -1

## The tile it stands on. Kept after a defeat, though [method CombatState.tile_of] then answers
## [constant CombatFact.NO_TILE].
var tile: Vector2i = CombatFact.NO_TILE

## How it crosses terrain: walking distance and where a shove may land it.
var movement_type: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT

# ASSUMPTION: unit tags are plain strings until the units plan (P03) defines them.
## What the unit is, for weapon effectiveness: "Flier", "Armored", "Mounted" (unit-roster.md,
## Movement and tags).
var tags: PackedStringArray = []

# ASSUMPTION: unit types are names until the units plan (P03) defines them.
## The unit's type, such as "Archer" (unit-roster.md), for conditions that test it.
var unit_type: String = ""

## Current HP.
var hp: int = 0

## Current Block.
var block: int = 0

## Current Stance. 0 is Exposed.
var stance: int = 0

## Whether it took its action this phase, which ends its turn.
var has_acted: bool = false

## Tiles moved during its current turn ("moved N+ tiles").
var tiles_moved: int = 0

## Movement cost spent this turn; a second move's budget is MOVEMENT less this.
var movement_spent: int = 0

## Whether a second move after acting is allowed and not yet taken
## ([constant CombatValue.Permission.MAY_MOVE_AFTER_ACTING]).
var is_second_move_pending: bool = false

## Whether it was shoved this phase: a unit can be shoved once per phase.
var has_been_shoved: bool = false

## Whether its free Sidearm swap is spent this unit turn.
var has_used_sidearm: bool = false

## Instance id of the weapon in its Weapon slot; empty when it holds none.
var equipped_weapon_id: String = ""

## Instance id of the weapon stowed in its Pouch; empty when none.
var stowed_weapon_id: String = ""

## Instance id of the consumable or trinket in its Pouch; empty when none. A Pouch holds one item,
## or a stowed weapon instead.
var pouch_item_id: String = ""

## The weight of each item in its Pouch, a stowed weapon included:
## [constant CampaignValue.Key.POUCH_ITEM_WEIGHT] of its army, read at battle start. 0 unless a
## curse says otherwise (Heavy Pack: 2).
var pouch_item_weight: int = 0

## Growth changes gained this battle, in percentage points by [enum CombatValue.Stat] (an eaten
## ingredient's +5% RES growth). They change nothing in battle; the battle-end bridge (EB6) writes
## them to the roster.
var growth_changes: Dictionary[int, int] = {}

## Whether it was defeated. A defeated unit stays in [CombatState], so its side and seat stay
## readable, but it is off the map.
var is_defeated: bool = false


## A copy sharing nothing mutable, for a sandbox.
func copy() -> CombatUnitState:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = id
	unit.side = side
	unit.seat = seat
	unit.tile = tile
	unit.movement_type = movement_type
	unit.tags = tags.duplicate()
	unit.unit_type = unit_type
	unit.hp = hp
	unit.block = block
	unit.stance = stance
	unit.has_acted = has_acted
	unit.tiles_moved = tiles_moved
	unit.movement_spent = movement_spent
	unit.is_second_move_pending = is_second_move_pending
	unit.has_been_shoved = has_been_shoved
	unit.has_used_sidearm = has_used_sidearm
	unit.equipped_weapon_id = equipped_weapon_id
	unit.stowed_weapon_id = stowed_weapon_id
	unit.pouch_item_id = pouch_item_id
	unit.pouch_item_weight = pouch_item_weight
	unit.growth_changes = growth_changes.duplicate()
	unit.is_defeated = is_defeated
	return unit


## How many items its Pouch holds, a stowed weapon included.
func pouch_count() -> int:
	return (0 if pouch_item_id.is_empty() else 1) + (0 if stowed_weapon_id.is_empty() else 1)
