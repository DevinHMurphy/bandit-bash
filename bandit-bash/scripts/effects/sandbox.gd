# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     sandbox.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name Sandbox
extends RefCounted
## A scratch copy of one session for a forecast or an AI branch: the same resolver runs on
## [member engine], and nothing leaves it.
##
## Counters advance, reactions queue and resolve and timed modifiers apply inside it, so the
## forecast equals what executes by construction. The real state, the real stream and the real
## counters are untouched, and no fact reaches a bus. Create it on the main thread; it shares no
## mutable state, so it may then resolve on a worker thread, one thread at a time. A sandbox can be
## made from another sandbox's engine, to branch from a point inside a simulation.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The copy to resolve on: its state, effects and [member EffectEngine.rolls].
var engine: EffectEngine = null


## [param roll_source]: [ForecastRolls], [ForcedRolls] or [SampledRolls]. A [LiveRolls] would
## advance a session's stream, so it is replaced with [ForecastRolls] and reported in the copy's
## diagnostics.
func _init(source: EffectEngine, roll_source: RollSource) -> void:
	var rolls: RollSource = roll_source
	var refused: bool = rolls is LiveRolls
	if refused:
		rolls = ForecastRolls.new()
	engine = source.copy_for_sandbox(rolls)
	if refused:
		engine.diagnostics.append("Sandbox: a live roll source was refused; using ForecastRolls")


## The facts the sandbox resolved, in order. Their seq continues the source's.
func facts() -> Array[CombatFact]:
	return engine.fact_log


## The rolls the sandbox made, with their probabilities.
func roll_records() -> Array[RollRecord]:
	return engine.rolls.records
