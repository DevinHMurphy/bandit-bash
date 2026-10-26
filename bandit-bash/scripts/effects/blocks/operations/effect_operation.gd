# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_operation.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
@abstract
class_name EffectOperation
extends Resource
## Base for what an effect does: a modifier, a resource gain, splash, a grant.
##
## Subclasses are inspector blocks in [member EffectDefinition.operations]; read-only at runtime.
## An [b]inline[/b] operation changes the action in flight ("that hit") and is allowed only on a
## trigger with an inline window; every other operation is queued as a new action.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


## This operation as effect text, such as "gain 3 Block". Never empty.
@abstract func describe() -> String


## This operation's text inside an effect with [param trigger]. Inline operations name what they
## change ("that hit", "that heal"); the rest return [method describe].
func describe_for_trigger(_trigger: EffectDefinition.Trigger) -> String:
	return describe()


## Whether this changes the action in flight rather than queueing a new one.
func is_inline() -> bool:
	return false
