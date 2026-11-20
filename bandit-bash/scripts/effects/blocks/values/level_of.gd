# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     level_of.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

@tool
class_name LevelOf
extends ValueSource
## A unit's current level, or a multiple of it: "2 × this unit's level" (the Drengr's Vanguard).
##
## Read from the battle state ([method SandboxState.level_of]) at the moment of asking. A level
## changes only between battles, so within one battle the amount is the same at every trigger,
## and a resumed battle reads the level its save carried.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Whose level is read. [b]Null:[/b] the effect's owner. A selector that picks several units is a
## content error.
@export var subject: TargetSelector = null

## Amount per level, in the operation's units (Block for Vanguard), exact.[br]
## [b]1:[/b] the level itself. [b]0:[/b] always 0. Negative is a loss.
@export var per_level: float = 1.0


func describe() -> String:
	var whose: String = "this unit" if subject == null else subject.describe()
	var level: String = "%s's level" % [whose]
	if is_equal_approx(per_level, 1.0):
		return level
	return "%s × %s" % [EffectTerms.format_number(per_level), level]


## The first selected unit's level times [member per_level]; 0 when none is selected or it has
## left the battle.
func evaluate(ctx: EffectContext) -> float:
	var units: PackedStringArray = PackedStringArray([ctx.owner_unit_id()])
	if subject != null:
		units = subject.select(ctx)
	if units.is_empty() or units[0].is_empty():
		return 0.0
	if units.size() > 1:
		ctx.engine.diagnostics.append(
				"LevelOf: the subject selector picked %d units" % [units.size()]
		)
	var state: SandboxState = ctx.engine.state
	if state == null or not state.has_unit(units[0]):
		return 0.0
	return state.level_of(units[0]) * per_level
