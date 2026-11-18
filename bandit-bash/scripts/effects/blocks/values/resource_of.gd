# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     resource_of.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

@tool
class_name ResourceOf
extends ValueSource
## A unit's current HP, Block or Stance: "this unit's current Stance" (the Shieldbearer's Braced,
## +2 DEF per point).
##
## Read from the battle state at the moment of asking, so a modifier scaled by it
## ([member ModifyValue.per]) is live: it falls as the pool is spent and returns with the refresh.
## [StatOf] reads value keys, which hold maximums (HP, [constant CombatValue.Key.STANCE_MAX]), never
## what is left.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The pool read. Stance can stand above its maximum (Command, Triage); the value read does too.
@export var pool: GainResource.Pool = GainResource.Pool.STANCE

## Whose pool is read. [b]Null:[/b] the effect's owner. A selector that picks several units is a
## content error.
@export var subject: TargetSelector = null


func describe() -> String:
	var whose: String = "this unit" if subject == null else subject.describe()
	return "%s's current %s" % [whose, GainResource.POOL_TEXT[pool]]


## The first selected unit's current [member pool]; 0 when none is selected or it has left the
## battle.
func evaluate(ctx: EffectContext) -> float:
	var units: PackedStringArray = PackedStringArray([ctx.owner_unit_id()])
	if subject != null:
		units = subject.select(ctx)
	if units.is_empty() or units[0].is_empty():
		return 0.0
	if units.size() > 1:
		ctx.engine.diagnostics.append(
				"ResourceOf: the subject selector picked %d units" % [units.size()]
		)
	var state: SandboxState = ctx.engine.state
	if state == null or not state.has_unit(units[0]):
		return 0.0
	match pool:
		GainResource.Pool.HP:
			return float(state.get_hp(units[0]))
		GainResource.Pool.BLOCK:
			return float(state.get_block(units[0]))
	return float(state.get_stance(units[0]))
