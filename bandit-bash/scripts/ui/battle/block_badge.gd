# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     block_badge.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name BlockBadge
extends Panel
## A unit's Block as a small numbered badge beside its token's bars (combat UI plan, question 23).
##
## [UnitToken] says how much ([method show_block]); the badge holds no rules. Its look is the
## theme's [code]BlockBadge[/code] panel and [code]BlockBadgeLabel[/code] label styles
## ([code]battle_theme.tres[/code]).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Whether the badge shows a unit with no Block, as a 0.[br]
## [b]Off:[/b] it shows only while the unit has Block.
@export var is_shown_at_zero: bool = false:
	set(value):
		is_shown_at_zero = value
		if not is_node_ready():
			return
		show_block(amount)

## The Block shown.
var amount: int = 0

@onready var _count: Label = %Count


func _ready() -> void:
	show_block(amount)


## Shows [param value] Block; it is never shown below 0.
func show_block(value: int) -> void:
	amount = maxi(value, 0)
	_count.text = str(amount)
	visible = amount > 0 or is_shown_at_zero


## The number shown, for tests.
func get_text() -> String:
	return _count.text
