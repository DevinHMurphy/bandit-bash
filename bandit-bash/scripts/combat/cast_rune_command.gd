# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     cast_rune_command.gd
# Author:
# Created:  October 28, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name CastRuneCommand
extends Command
## A seat casts a rune from its slots on this map (combat core plan, Commands; [RuneResolver]).
##
## Runes are outside the action economy and act for no unit, so any seat holding the rune may
## cast it during this map's player phase, a teammate's map included (the encounter routes it
## there with the caster's seat). A seat that has ended its turn here can't. Most runes fire their
## effect on [member target_id]; Recall swaps [member target_id] and [member second_target_id],
## two of the seat's units. A rune cast on a map object (Spark on a powder keg) runs the map's
## [constant CombatHooks.Hook.OBJECT_OPERATIONS] instead ([method RuneResolver.cast_on_object]);
## validation tries the map's own rule ([method MapObjects.operate]) on a sandbox copy, since the
## hook acts on the real session.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## The rune's instance id, in [member CombatState.rune_slots] of the seat.
var rune_id: String = ""

## The unit the rune acts on; Recall's first unit.
var target_id: String = ""

# ASSUMPTION: a cast naming a second unit is Recall, until the rune catalog (P03) says which rune
# is Recall.
## Recall's second unit; empty for every other rune.
var second_target_id: String = ""


func _init(
		sender: int = -1, rune: String = "", target: String = "", second_target: String = ""
) -> void:
	seat = sender
	rune_id = rune
	target_id = target
	second_target_id = second_target


func get_label() -> String:
	return "rune" if second_target_id.is_empty() else "recall"


func get_target_id() -> String:
	return target_id


func validate(session: CombatSession) -> String:
	var reason: String = CommandValidator.player_phase_reason(session, seat)
	if not reason.is_empty():
		return reason
	if second_target_id.is_empty() and _rune_effect(session.engine) == null:
		return "%s has no effect on this map" % [rune_id]
	# The resolver's own checks (the slot, the targets, whether the effect can fire) run on a copy.
	var trial: EffectEngine = session.engine.copy_for_sandbox(ForcedRolls.new())
	var trial_state: CombatState = trial.state
	if _is_on_object(trial_state):
		var try_rule: Callable = func(rune: String, object_id: String) -> bool:
			return MapObjects.operate(trial, trial_state, rune, object_id)
		return RuneResolver.cast_on_object(
				trial, trial_state, seat, _rune_effect(trial), target_id, try_rule
		)
	return _cast(trial, trial_state)


func resolve(session: CombatSession) -> void:
	if _is_on_object(session.state):
		var run_hooks: Callable = func(rune: String, object_id: String) -> bool:
			return _run_object_hooks(session, rune, object_id)
		RuneResolver.cast_on_object(
				session.engine, session.state, seat, _rune_effect(session.engine), target_id,
				run_hooks
		)
		return
	_cast(session.engine, session.state)


# Casts the rune on state; returns why it couldn't, recording nothing then.
func _cast(engine: EffectEngine, state: CombatState) -> String:
	if not second_target_id.is_empty():
		return RuneResolver.recall(engine, state, seat, rune_id, target_id, second_target_id)
	return RuneResolver.cast(engine, state, seat, _rune_effect(engine), target_id)


# Whether the cast names one map object, which the map's rules act on.
func _is_on_object(state: CombatState) -> bool:
	return second_target_id.is_empty() and state.map.object(target_id) != null


# The rune's effect instance in engine; null when it has none.
func _rune_effect(engine: EffectEngine) -> EffectInstance:
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind == EffectOwner.Kind.RUNE and instance.owner.owner_id == rune_id:
			return instance
	return null


# The session's OBJECT_OPERATIONS registrations in order, until one acts; false when none does.
static func _run_object_hooks(session: CombatSession, rune: String, object_id: String) -> bool:
	for run: Callable in session.hooks.get_registered(CombatHooks.Hook.OBJECT_OPERATIONS):
		if run.call(session, rune, object_id):
			return true
	return false
