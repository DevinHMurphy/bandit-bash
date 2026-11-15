# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     all_of_scope.gd
# Author:
# Created:  October 26, 2026
# Modified: November 14, 2026
# ==============================================================================

@tool
class_name AllOfScope
extends TargetSelector
## Selects every unit in a scope, relative to the effect's owner: "your units", "every unit",
## "every ally unit adjacent to a unit of another player" (Brothers in Arms).
##
## Non-positional, so Any Ally Unit and Any Unit reach partners' maps through the encounter
## (event bus plan, question 12); a [member where] filter that tests position still only sees each
## unit's own map.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Text for each scope as a target.
const SCOPE_TARGET_TEXT: Dictionary[int, String] = {
	EffectTerms.Scope.THIS_UNIT: "this unit",
	EffectTerms.Scope.YOUR_UNIT: "your units",
	EffectTerms.Scope.ANY_ALLY_UNIT: "every ally unit",
	EffectTerms.Scope.ANY_UNIT: "every unit",
}

## The units selected. [b]This unit:[/b] the same as [Owner].
@export var scope: EffectTerms.Scope = EffectTerms.Scope.YOUR_UNIT

## Keeps only the units this passes for, each tested as "this unit". Use a While condition: a
## Counter or Chance would count or roll once per unit. [b]Null:[/b] every unit in the scope.
@export var where: EffectCondition = null


## The scope's noun, then the filter's text without its "while", such as "every ally unit adjacent
## to a unit of another player".
func describe() -> String:
	var noun: String = SCOPE_TARGET_TEXT[scope]
	if where == null:
		return noun
	return "%s %s" % [noun, where.describe().trim_prefix("while ")]


func is_owner() -> bool:
	return scope == EffectTerms.Scope.THIS_UNIT and where == null


func select(ctx: EffectContext) -> PackedStringArray:
	var units: PackedStringArray = ctx.engine.units_in_scope(ctx.instance.owner, scope)
	if where == null:
		return units
	var kept: PackedStringArray = []
	var saved_subject: String = ctx.subject_id
	for unit_id: String in units:
		ctx.subject_id = unit_id
		if where.test(ctx):
			kept.append(unit_id)
	ctx.subject_id = saved_subject
	return kept
