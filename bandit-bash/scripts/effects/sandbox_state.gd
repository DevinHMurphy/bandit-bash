# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     sandbox_state.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

@abstract
class_name SandboxState
extends RefCounted
## The rules state of one session as the effect engine sees it: the hook between the engine and
## the combat core's state.
##
## The engine can't know the combat core's state, so P02's [code]CombatState[/code] extends this
## class. A [Sandbox] calls [method copy_for_sandbox] and copies the engine's own state itself.
## The read methods answer conditions, selectors and value sources; the write methods are called
## only by the engine's resource paths ([method EffectEngine.gain_block] and the others), which
## emit the facts. Implementations hold no nodes or Resources, never log, and are safe to use from
## one worker thread at a time.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


## A copy the sandbox may change freely: changes never reach this state. Copy on write where it
## matters; the copy shares nothing mutable with the original.
@abstract func copy_for_sandbox() -> SandboxState


## Every unit and map object on the map, defeated ones excluded, in a fixed order (roster order,
## then spawn order). Selectors and position conditions iterate in this order.
@abstract func unit_ids() -> PackedStringArray


## Whether [param id] is a unit or object on the map that hasn't been defeated.
@abstract func has_unit(id: String) -> bool


## The side of [param id]; [constant CombatFact.CombatSide.NONE] for a map object or an unknown id.
@abstract func side_of(id: String) -> CombatFact.CombatSide


## The seat controlling [param id]; [code]-1[/code] for an enemy, an object or an unknown id.
@abstract func seat_of(id: String) -> int


## The tile [param id] stands on; [constant CombatFact.NO_TILE] for an unknown id.
@abstract func tile_of(id: String) -> Vector2i


## The walking distance from [param from_id] to [param to_id], in tiles: the steps [param from_id]
## could take with its own movement type, walls and terrain counted; -1 when there is no path.
## "Within N movable tiles" uses it; "within N tiles" is grid distance
## ([method EffectEngine.tile_distance]).
@abstract func walking_distance(from_id: String, to_id: String) -> int


## Current HP of [param id].
@abstract func get_hp(id: String) -> int


## Current Block of [param id].
@abstract func get_block(id: String) -> int


## Current Stance of [param id]. 0 is Exposed.
@abstract func get_stance(id: String) -> int


## Tiles [param id] has moved during its current unit turn.
@abstract func tiles_moved(id: String) -> int


## The darkness layer ([enum WhileLayerCondition.Layer]) of the tile [param id] stands on.
@abstract func darkness_layer(id: String) -> int


## Instance id of the weapon in [param unit_id]'s Weapon slot; empty when it holds none. A weapon
## carrier's effects are dormant unless it is this one, so a stowed weapon never counts.
@abstract func equipped_weapon_id(unit_id: String) -> String


## Sets the current HP of [param id]. The engine has already clamped [param value].
@abstract func set_hp(id: String, value: int) -> void


## Sets the current Block of [param id]. The engine has already clamped [param value].
@abstract func set_block(id: String, value: int) -> void


## Sets the current Stance of [param id]. The engine has already clamped [param value].
@abstract func set_stance(id: String, value: int) -> void


## Adds [param points] percentage points to [param id]'s growth for [param stat] (an
## [enum CombatValue.Stat]), kept for the battle-end bridge. Ignores an unknown id.
@abstract func add_growth(id: String, stat: int, points: int) -> void


## Resolves splash damage with the combat core's one splash rule (Block absorbs it; it fires
## Damage taken, never Hit taken; it can defeat), recording every fact through
## [method EffectEngine.record].
## [param source_id]: the unit dealing it, or empty. [param source_effect_id]: the effect instance.
@abstract func deal_splash(
		engine: EffectEngine,
		source_id: String,
		target_id: String,
		amount: int,
		source_effect_id: String
) -> void
