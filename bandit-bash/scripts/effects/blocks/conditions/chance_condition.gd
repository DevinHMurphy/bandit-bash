# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     chance_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name ChanceCondition
extends EffectCondition
## Passes with a percent chance: "25% chance".
##
## [b]Randomness goes through the roll source[/b] (one [code]roll_percent[/code]), never a stream
## or the global RNG, so the forecast can list it as "25%: +X" and the AI can branch on it. This
## block holds no random state.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Chance to pass, in percent.
##
## [b]0:[/b] never passes. [b]100:[/b] always passes, which needs no condition at all.
@export_range(0, 100) var chance_percent: int = 100


func describe() -> String:
	return "%d%% chance" % [chance_percent]


## One [method RollSource.roll_percent] against [member chance_percent]. Never passes, and never
## rolls, during a value query.
func test(ctx: EffectContext) -> bool:
	if ctx.is_query:
		return false
	if ctx.engine.rolls == null:
		ctx.engine.diagnostics.append("ChanceCondition: the engine has no roll source")
		return false
	return ctx.engine.rolls.roll_percent(chance_percent)
