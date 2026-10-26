# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     constant.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name Constant
extends ValueSource
## A fixed amount: "3".
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The amount, in the operation's units (HP, Block, Stance, splash damage). Negative is a loss.
@export var value: float = 0.0


func describe() -> String:
	return EffectDefinition.format_number(value)
