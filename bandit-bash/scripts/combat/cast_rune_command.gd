# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     cast_rune_command.gd
# Author:
# Created:  October 28, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name CastRuneCommand
extends Command
## A seat casts a rune from its slots on its own map ([RuneResolver]), outside the action economy
## and for no unit, during the player phase until it ends its turn there. Only a seat's own map
## holds its runes and their effects, so a cast on a teammate's map (by a sent unit or a visitor)
## finds no rune and is refused. [member RuneDefinition.target_kind] says which fields the cast
## names, and naming any other is refused: a [code]unit[/code] rune [member target_id]; a
## [code]pair[/code] rune (Recall) [member target_id] and [member second_target_id]; an
## [code]object[/code] rune (Spark) [member tile], whose object the map's
## [constant CombatHooks.Hook.OBJECT_OPERATIONS] act on. [method cast_on] is the one cast path:
## [method resolve] runs it on the session, [method validate] and [method CombatForecast.rune] on
## a sandbox copy, where [method MapObjects.operate] stands in for the hooks.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## Its name on the wire ([method Command.get_wire_type]). Its fields follow the common ones: the
## rune, the target, the second target, the tile ([code][x, y][/code], or [code][][/code] for none).
const WIRE_TYPE: String = "cast_rune"

# What each kind's cast names, the refusal of one that names something else.
const _NEEDS: Dictionary[String, String] = {
	ContentIds.RUNE_UNIT: "a unit rune names one unit and no tile",
	ContentIds.RUNE_PAIR: "a pair rune names two units and no tile",
	ContentIds.RUNE_OBJECT: "an object rune names a tile and no unit",
}

## The rune's instance id, in [member CombatState.rune_slots] of the seat.
var rune_id: String = ""

## The unit a [code]unit[/code] rune acts on; Recall's first unit. Empty for an object rune.
var target_id: String = ""

## Recall's second unit; empty for every other rune.
var second_target_id: String = ""

## The tile of the object an [code]object[/code] rune acts on; [constant CombatFact.NO_TILE] for
## every other rune.
var tile: Vector2i = CombatFact.NO_TILE


func _init(
		sender: int = -1,
		rune: String = "",
		target: String = "",
		second_target: String = "",
		on_tile: Vector2i = CombatFact.NO_TILE
) -> void:
	seat = sender
	rune_id = rune
	target_id = target
	second_target_id = second_target
	tile = on_tile


func get_label() -> String:
	return "rune" if second_target_id.is_empty() else "recall"


func get_wire_type() -> String:
	return WIRE_TYPE


func get_target_id() -> String:
	return target_id


func validate(session: CombatSession) -> String:
	var reason: String = CommandValidator.player_phase_reason(session, seat)
	if not reason.is_empty():
		return reason
	# The resolver's own checks (the slot, the targets, whether the effect can fire) run on a copy.
	var trial: EffectEngine = session.engine.copy_for_sandbox(ForcedRolls.new())
	return cast_on(trial, sandbox_rule(trial))


func resolve(session: CombatSession) -> void:
	var run_hooks: Callable = func(rune: String, object_id: String) -> bool:
		return _run_object_hooks(session, rune, object_id)
	cast_on(session.engine, run_hooks)


## Casts the rune on [param engine]'s state, the session's or a sandbox's. [param operate] acts on
## an object rune's object, as in [method RuneResolver.cast_on_object]. Returns why the cast is
## illegal, recording nothing then; empty when it resolved.
func cast_on(engine: EffectEngine, operate: Callable) -> String:
	var state: CombatState = engine.state as CombatState
	if state == null:
		return "the engine's state is not a combat state"
	var rune: RuneDefinition = RuneResolver.definition_of(engine, rune_id)
	if rune == null:
		return "%s has no effect on this map" % [rune_id]
	var reason: String = _fields_reason(rune)
	if not reason.is_empty():
		return reason
	match rune.target_kind:
		ContentIds.RUNE_PAIR:
			return RuneResolver.recall(
					engine, state, seat, rune_id, target_id, second_target_id
			)
		ContentIds.RUNE_OBJECT:
			return RuneResolver.cast_on_object(engine, state, seat, rune_id, tile, operate)
	return RuneResolver.cast(
			engine, state, seat, RuneResolver.effect_of(engine, rune_id), target_id
	)


func _wire_fields() -> Array:
	var at: Array = [] if tile == CombatFact.NO_TILE else [tile.x, tile.y]
	return [rune_id, target_id, second_target_id, at]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 4 or not values[3] is Array:
		return false
	for i: int in 3:
		if not values[i] is String:
			return false
	var at: Array = values[3]
	var on_tile: Vector2i = CombatFact.NO_TILE
	if not at.is_empty():
		if at.size() != 2:
			return false
		var x: Variant = _wire_int(at[0])
		var y: Variant = _wire_int(at[1])
		if x == null or y == null:
			return false
		on_tile = Vector2i(x as int, y as int)
	rune_id = values[0]
	target_id = values[1]
	second_target_id = values[2]
	tile = on_tile
	return true


# Why the cast names fields rune's kind doesn't use, or misses one it needs; empty when it fits.
func _fields_reason(rune: RuneDefinition) -> String:
	var has_tile: bool = tile != CombatFact.NO_TILE
	var fits: bool = false
	match rune.target_kind:
		ContentIds.RUNE_UNIT:
			fits = not target_id.is_empty() and second_target_id.is_empty() and not has_tile
		ContentIds.RUNE_PAIR:
			fits = not target_id.is_empty() and not second_target_id.is_empty() and not has_tile
		ContentIds.RUNE_OBJECT:
			fits = target_id.is_empty() and second_target_id.is_empty() and has_tile
	if fits:
		return ""
	var needs: String = _NEEDS.get(rune.target_kind, "%s names other targets" % [rune.id])
	return needs


## The map's own object rule on [param engine], for a cast on a copy: [method MapObjects.operate],
## the only [constant CombatHooks.Hook.OBJECT_OPERATIONS] registration a battle makes.
static func sandbox_rule(engine: EffectEngine) -> Callable:
	return func(rune: String, object_id: String) -> bool:
		var state: CombatState = engine.state as CombatState
		return state != null and MapObjects.operate(engine, state, rune, object_id)


# The session's OBJECT_OPERATIONS registrations in order, until one acts; false when none does.
static func _run_object_hooks(session: CombatSession, rune: String, object_id: String) -> bool:
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.OBJECT_OPERATIONS):
		if run.call(session, rune, object_id):
			return true
	return false
