# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     cast_rune_command.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name CastRuneCommand
extends Command
## A seat casts a rune from its slots on this map (combat core plan, Commands; [RuneResolver]).
##
## Runes are outside the action economy and act for no unit, so any seat holding the rune may
## cast it during this map's player phase, a teammate's map included (the encounter routes it
## there with the caster's seat). A seat that has ended its turn here can't. Most runes fire their
## effect on [member target_id]; Recall swaps [member target_id] and [member second_target_id],
## two of the seat's units.
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
	return _cast(trial, trial_state)


func resolve(session: CombatSession) -> void:
	_cast(session.engine, session.state)


# Casts the rune on state; returns why it couldn't, recording nothing then.
func _cast(engine: EffectEngine, state: CombatState) -> String:
	if not second_target_id.is_empty():
		return RuneResolver.recall(engine, state, seat, rune_id, target_id, second_target_id)
	return RuneResolver.cast(engine, state, seat, _rune_effect(engine), target_id)


# The rune's effect instance in engine; null when it has none.
func _rune_effect(engine: EffectEngine) -> EffectInstance:
	for instance: EffectInstance in engine.get_instances():
		if instance.owner.kind == EffectOwner.Kind.RUNE and instance.owner.owner_id == rune_id:
			return instance
	return null
