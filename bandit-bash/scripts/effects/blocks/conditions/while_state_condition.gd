# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_state_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name WhileStateCondition
extends EffectCondition
## Passes while a unit is in a state: "while Exposed", "while the opponent is Exposed", "while it
## is the commander", "while holding a Power weapon", "while holding a bow".
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
	## The weapon in its Weapon slot has the weapon type [member weapon_type] (the Short Quiver's
	## bows). A stowed weapon never counts.
	WIELDING_TYPE = 3,
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

## The weapon type [constant State.WIELDING_TYPE] tests for, from
## [constant ContentIds.WEAPON_TYPES]; ignored by the other states. Text reads it as its id
## ("while holding a bow").
@export var weapon_type: String = ""


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "weapon_type":
		ContentIds.apply_hint(property, ContentIds.WEAPON_TYPES)


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
		State.WIELDING_TYPE:
			if is_opponent:
				return "while the opponent holds %s" % [_article(weapon_type)]
			return "while holding %s" % [_article(weapon_type)]
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
		State.WIELDING_TYPE:
			var weapon_id: String = sandbox.equipped_weapon_id(unit_id)
			return not weapon_id.is_empty() and sandbox.weapon_type_of(weapon_id) == weapon_type
	return sandbox.get_stance(unit_id) == 0


# word with "a" or "an" before it: "a bow", "an axe", "an anima".
static func _article(word: String) -> String:
	var is_vowel: bool = not word.is_empty() and "aeiou".contains(word[0])
	return "%s %s" % ["an" if is_vowel else "a", word]
