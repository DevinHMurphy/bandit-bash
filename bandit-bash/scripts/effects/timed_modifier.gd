# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     timed_modifier.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name TimedModifier
extends RefCounted
## A modifier one unit holds until an end or for a number of attacks: Momentum's "+15 Hit on its
## next attack this combat", War Horn's "+2 Attack until the end of the next phase".
##
## Session state, added by [AddTimedModifier] through [method EffectEngine.add_timed_modifier] and
## removed by [method EffectEngine.reach_boundary], whichever comes first: its end or its last use.
## Checked live on every query of its holder, never cached in a stat sheet.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Instance id of the unit holding it.
var holder_id: String = ""

## The change it makes while held.
var modifier: Modifier = null

## When it expires at the latest.
var end: AddTimedModifier.End = AddTimedModifier.End.THIS_EXCHANGE

## Attacks left before it expires; 0 when only [member end] limits it.
var uses_left: int = 0

## The session's phase it belongs to: the phase it was added in, or the next phase to start when
## it was added between phases.
var phase: int = 0

## The session's attack count when it was added. Only an attack started after that spends a use.
var attacks_before: int = 0

## Instance id of the effect that added it.
var source_effect_id: String = ""


## A copy, for a sandbox. The modifier is shared: it never changes.
func copy() -> TimedModifier:
	var timed: TimedModifier = TimedModifier.new()
	timed.holder_id = holder_id
	timed.modifier = modifier
	timed.end = end
	timed.uses_left = uses_left
	timed.phase = phase
	timed.attacks_before = attacks_before
	timed.source_effect_id = source_effect_id
	return timed
