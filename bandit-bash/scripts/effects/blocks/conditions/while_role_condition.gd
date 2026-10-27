# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_role_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name WhileRoleCondition
extends EffectCondition
## Passes while this unit has a role in the current exchange: "while it is the defender".
##
## Outside an exchange (before Before Combat, after After Combat) it fails.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## A role in an exchange. Saved as an int: [b]append only[/b].
enum Role {
	## The unit that started the exchange.
	INITIATOR = 0,
	## The unit that was attacked.
	DEFENDER = 1,
}

## The role that must hold.
@export var role: Role = Role.INITIATOR


func describe() -> String:
	return "while it is the %s" % [String(Role.find_key(role)).to_lower()]


func test(ctx: EffectContext) -> bool:
	return ctx.role_of(ctx.subject_id) == role
