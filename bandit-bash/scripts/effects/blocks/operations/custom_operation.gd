# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     custom_operation.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name CustomOperation
extends EffectOperation
## The script escape hatch: an operation whose behavior comes from a script that extends this one.
##
## [b]The escape hatch rule:[/b] when the same need appears in two pieces of content, it becomes a
## block of its own; until then a custom script is fine. Its text is authored in [member text]
## because the generator can't read a script's intent.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The effect text for this operation, such as "swap places with an adjacent ally". Empty is a
## content error.
@export var text: String = ""

## Whether the script changes the action in flight. [b]On:[/b] only allowed on a trigger with an
## inline window.
@export var inline: bool = false


func describe() -> String:
	return text


func is_inline() -> bool:
	return inline


## Does nothing here; the extending script overrides it. It must follow the engine's rules: no
## nodes, autoloads or global RNG, and every change through the engine's paths.
func apply(_ctx: EffectContext) -> void:
	pass
