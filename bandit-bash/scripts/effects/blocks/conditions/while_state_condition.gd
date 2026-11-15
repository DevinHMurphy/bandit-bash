# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_state_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: November 14, 2026
# ==============================================================================

@tool
class_name WhileStateCondition
extends EffectCondition
## Passes while a unit is in a state: "while Exposed", "while the opponent is Exposed", "while it
## is the commander", "while holding a Power weapon".
##
## Checked live on every query, so a weapon swap or a Stance change shows at once. The opponent
## exists only from Before Combat to After Combat; outside an exchange an opponent test fails.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## A state a unit can be in. Saved as an int: [b]append only[/b].
enum State {
	## Stance is 0.
	EXPOSED = 0,
	## The unit is its seat's commander on this map ([method SandboxState.is_commander]).
	COMMANDER = 1,
	## The weapon in its Weapon slot has the profile [member profile]. A stowed weapon never counts.
	WIELDING_PROFILE = 2,
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

## The weapon profile [constant State.WIELDING_PROFILE] tests for; ignored by the other states.
## [b]None:[/b] a weapon outside the triangle (a bow, gauntlets).
@export var profile: WeaponTriangle.Profile = WeaponTriangle.Profile.POWER


func describe() -> String:
	var is_opponent: bool = subject == Subject.OPPONENT
	match state:
		State.COMMANDER:
			if is_opponent:
				return "while the opponent is a commander"
			return "while it is the commander"
		State.WIELDING_PROFILE:
			var weapon: String = "a %s weapon" % [
				(WeaponTriangle.Profile.find_key(profile) as String).capitalize(),
			]
			if is_opponent:
				return "while the opponent holds %s" % [weapon]
			return "while holding %s" % [weapon]
	var state_name: String = (State.find_key(state) as String).capitalize()
	if is_opponent:
		return "while the opponent is %s" % [state_name]
	return "while %s" % [state_name]


func test(ctx: EffectContext) -> bool:
	var unit_id: String = ctx.subject_id
	if subject == Subject.OPPONENT:
		unit_id = ctx.opponent_of(ctx.subject_id)
	var sandbox: SandboxState = ctx.engine.state
	if not sandbox.has_unit(unit_id):
		return false
	match state:
		State.COMMANDER:
			return sandbox.is_commander(unit_id)
		State.WIELDING_PROFILE:
			var weapon_id: String = sandbox.equipped_weapon_id(unit_id)
			return not weapon_id.is_empty() and sandbox.weapon_profile_of(weapon_id) == profile
	return sandbox.get_stance(unit_id) == 0
