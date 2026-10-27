# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_attack_condition.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

@tool
class_name WhileAttackCondition
extends EffectCondition
## Passes while the attack in flight matches, seen from this unit's side: "against Beasts" when it
## attacks, "from magic" when it is attacked. Makes two-sided damage stages ("deals ×2 damage to
## Beasts", "takes 2 more damage from bows") a condition on the attacker's or the defender's key.
##
## The opponent is the defender when this unit attacks and the attacker when it is attacked. The
## damage type (after any override), the weapon type and the crit belong to the attack itself.
## Holds only during an attack ([member EffectContext.attack_index] 0 or more); before and after
## combat and outside an exchange it fails. Like every condition on an always-on modifier it is
## tested live on each query, so cached stat sheets never hold its result.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## What is tested. Saved as an int: [b]append only[/b].
enum Kind {
	## The opponent has the tag [member type_name] ("Beast").
	OPPONENT_TAG = 0,
	## The opponent's unit type is [member type_name] ("Archer").
	OPPONENT_UNIT_TYPE = 1,
	## The attack deals [member damage_type] damage.
	DAMAGE_TYPE = 2,
	## The attacker's weapon type is [member type_name] ("Bow").
	WEAPON_TYPE = 3,
	## The hit is a critical hit.
	IS_CRIT = 4,
}

## This unit's part in the attack. Saved as an int: [b]append only[/b].
enum Role {
	## This unit makes the attack ("against Beasts").
	ATTACKING = 0,
	## This unit is attacked ("from magic").
	ATTACKED = 1,
}

## Whether this unit must be attacking or attacked.
@export var role: Role = Role.ATTACKING

## What is tested.
@export var kind: Kind = Kind.OPPONENT_TAG

## The tag, unit type or weapon type matched, written as in its definition: "Beast", "Archer",
## "Bow". Ignored by [constant DAMAGE_TYPE] and [constant IS_CRIT].[br]
## [b]Text:[/b] a name ending in "ed" reads "Armored units", others gain an "s"; a weapon type
## reads in lower case ("bows").
@export var type_name: String = ""

## The damage type matched by [constant DAMAGE_TYPE]; ignored by the other kinds.
@export var damage_type: CombatFact.DamageType = CombatFact.DamageType.MAGIC


func describe() -> String:
	var linker: String = "against" if role == Role.ATTACKING else "from"
	match kind:
		Kind.DAMAGE_TYPE:
			if role == Role.ATTACKING:
				linker = "with"
			var type_text: String = (
					(CombatFact.DamageType.find_key(damage_type) as String).to_lower()
			)
			return "%s %s" % [linker, type_text]
		Kind.WEAPON_TYPE:
			if role == Role.ATTACKING:
				linker = "with"
			return "%s %s" % [linker, _plural(type_name.to_lower())]
		Kind.IS_CRIT:
			return "on a crit" if role == Role.ATTACKING else "from a crit"
	return "%s %s" % [linker, _plural(type_name)]


func test(ctx: EffectContext) -> bool:
	if ctx.attack_index < 0 or ctx.attacker_id.is_empty() or ctx.defender_id.is_empty():
		return false
	var unit_id: String = ctx.attacker_id if role == Role.ATTACKING else ctx.defender_id
	if ctx.subject_id != unit_id:
		return false
	var state: SandboxState = ctx.engine.state
	var opponent: String = ctx.opponent_of(unit_id)
	match kind:
		Kind.OPPONENT_TAG:
			return state.tags_of(opponent).has(type_name)
		Kind.OPPONENT_UNIT_TYPE:
			return state.unit_type_of(opponent) == type_name
		Kind.DAMAGE_TYPE:
			var sheet: StatSheet = ctx.engine.stats(ctx.attacker_id)
			return sheet.get_int(CombatValue.Key.DAMAGE_TYPE, ctx) == damage_type
		Kind.WEAPON_TYPE:
			return state.weapon_type_of(ctx.weapon_id) == type_name
		Kind.IS_CRIT:
			return ctx.is_crit
	return false


static func _plural(noun: String) -> String:
	if noun.ends_with("ed"):
		return "%s units" % [noun]
	return noun if noun.ends_with("s") else noun + "s"
