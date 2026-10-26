# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     all_of_scope.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name AllOfScope
extends TargetSelector
## Selects every unit in a scope, relative to the effect's owner: "your units", "every unit".
##
## Non-positional, so Any Ally Unit and Any Unit reach partners' maps through the encounter
## (event bus plan, question 12).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Text for each scope as a target.
const SCOPE_TARGET_TEXT: Dictionary[int, String] = {
	EffectDefinition.Scope.THIS_UNIT: "this unit",
	EffectDefinition.Scope.YOUR_UNIT: "your units",
	EffectDefinition.Scope.ANY_ALLY_UNIT: "every ally unit",
	EffectDefinition.Scope.ANY_UNIT: "every unit",
}

## The units selected. [b]This unit:[/b] the same as [Owner].
@export var scope: EffectDefinition.Scope = EffectDefinition.Scope.YOUR_UNIT


func describe() -> String:
	return SCOPE_TARGET_TEXT[scope]


func is_owner() -> bool:
	return scope == EffectDefinition.Scope.THIS_UNIT
