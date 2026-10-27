# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_state_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name WhileStateCondition
extends EffectCondition
## Passes while a unit is in a state: "while Exposed", "while the opponent is Exposed".
##
## Checked live on every query. The opponent exists only from Before Combat to After Combat;
## outside an exchange an opponent test fails.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## A state a unit can be in. Saved as an int: [b]append only[/b].
enum State {
	## Stance is 0.
	EXPOSED = 0,
}

## Whose state is tested. Saved as an int: [b]append only[/b].
enum Subject {
	## The unit the effect belongs to.
	THIS_UNIT = 0,
	## The other unit in the current exchange.
	OPPONENT = 1,
}

## The state that must hold.
@export var state: State = State.EXPOSED

## Whose state is tested.
@export var subject: Subject = Subject.THIS_UNIT


func describe() -> String:
	var state_name: String = String(State.find_key(state)).capitalize()
	if subject == Subject.OPPONENT:
		return "while the opponent is %s" % [state_name]
	return "while %s" % [state_name]


func test(ctx: EffectContext) -> bool:
	var unit_id: String = ctx.subject_id
	if subject == Subject.OPPONENT:
		unit_id = ctx.opponent_of(ctx.subject_id)
	if not ctx.engine.state.has_unit(unit_id):
		return false
	return ctx.engine.state.get_stance(unit_id) == 0
