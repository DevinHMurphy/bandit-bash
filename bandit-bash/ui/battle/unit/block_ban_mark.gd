# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     block_ban_mark.gd
# Author:
# Created:  November 15, 2026
# Modified: November 15, 2026
# ==============================================================================

class_name BlockBanMark
extends Label
## A small mark beside a unit's Block badge on its [UnitInfo] while the unit can't gain Block
## (Haunted's ban, or anything else that denies
## [constant CombatValue.Permission.CAN_GAIN_BLOCK]; combat UI plan, UI12).
##
## [UnitInfo] says whether it shows ([method show_ban]); the mark holds no rules. Its look is the
## theme's [code]BlockBanMarkLabel[/code] style ([code]battle_theme.tres[/code]). The unit panel
## names the ban in words for anyone the glyph doesn't reach.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: greybox glyph and colour; no basis in the vision or Godot_FE (Latin-1, so the default
# font draws it).
## The mark's text: a "no" sign over the Block badge's corner.[br]
## [b]Empty:[/b] nothing is drawn while banned, though [method is_shown] still reports it.
@export var mark_text: String = "Ø":
	set(value):
		mark_text = value
		if not is_node_ready():
			return
		text = mark_text

## Whether the unit is shown as unable to gain Block.
var is_banned: bool = false


func _ready() -> void:
	text = mark_text
	show_ban(is_banned)


## Shows the mark while [param banned] is true; hides it otherwise.
func show_ban(banned: bool) -> void:
	is_banned = banned
	visible = banned


## Whether the mark shows, for tests.
func is_shown() -> bool:
	return visible
