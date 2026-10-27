# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     value_source.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
@abstract
class_name ValueSource
extends Resource
## Base for how much an operation gives: a constant, part of a fact, a stat, a count, a counter.
##
## Subclasses are inspector blocks inside operations; read-only at runtime. Amounts stay exact;
## the operation that applies them rounds (heals and Block gains halve up).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md


## This amount as effect text, such as "3" or "100% of that overheal".
@abstract func describe() -> String


## The amount for [param ctx]'s effect and fact, exact.
@abstract func evaluate(ctx: EffectContext) -> float
