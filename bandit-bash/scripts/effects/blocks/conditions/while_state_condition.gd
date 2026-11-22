# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_state_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: November 21, 2026
# ==============================================================================

@tool
class_name WhileStateCondition
extends EffectCondition
## Passes while a unit is in a state: "while Exposed", "while the opponent is Exposed", "while it
## is the commander", "while holding a Power weapon", "while holding a bow", "while its Curse is a
## Hex Storm".
##
## Checked live on every query, so a weapon swap or a Stance change shows at once. A permission
## state reads the unit's stats, so it belongs on a reaction, never on an always-on effect that
## could change that permission. The opponent
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
	## [member permission] is allowed for the unit (the Hex Matron's Hex Storm, granted for a
	## phase).
	ALLOWED = 4,
	## [member permission] is denied for the unit, as it is with no grant for a default-denied one.
	DENIED = 5,
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

## The permission [constant State.ALLOWED] and [constant State.DENIED] test, a
## [enum CombatValue.Permission] value such as [constant CombatValue.Permission.HEX_STORM]; ignored
## by the other states. Text reads it as its effect text ("while its Curse is a Hex Storm").
@export var permission: int = CombatValue.Permission.HEX_STORM


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
		State.ALLOWED, State.DENIED:
			var texts: Dictionary[int, String] = (
					EffectTerms.PERMISSION_ALLOWED_TEXT if state == State.ALLOWED
					else EffectTerms.PERMISSION_DENIED_TEXT
			)
			var text: String = texts.get(permission, "%s %d" % [
				"allowed" if state == State.ALLOWED else "denied", permission,
			])
			if is_opponent:
				return "while the opponent %s" % [text]
			return "while %s" % [text]
	var state_name: String = EffectTerms.mark_if_keyword(
			(State.find_key(state) as String).capitalize()
	)
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
		State.ALLOWED:
			return ctx.engine.stats(unit_id).is_allowed(permission)
		State.DENIED:
			return not ctx.engine.stats(unit_id).is_allowed(permission)
	return sandbox.get_stance(unit_id) == 0


# word with "a" or "an" before it: "a bow", "an axe", "an anima".
static func _article(word: String) -> String:
	var is_vowel: bool = not word.is_empty() and "aeiou".contains(word[0])
	return "%s %s" % ["an" if is_vowel else "a", word]
