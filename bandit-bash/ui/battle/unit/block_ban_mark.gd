# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     block_ban_mark.gd
# Author:
# Created:  November 15, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BlockBanMark
extends Label
## A small mark beside a unit's Block badge on its [UnitInfo] while the unit can't gain Block
## (Haunted's ban, or anything else that denies
## [constant CombatValue.Permission.CAN_GAIN_BLOCK]; combat UI plan, UI12).
##
## [UnitInfo] says whether it shows ([method show_ban]); the mark holds no rules. Its look is the
## theme's [code]BlockBanMarkLabel[/code] style ([code]battle_theme.tres[/code]) over Godot_FE's
## shield icon in the [code]block[/code] colour, so it reads as "no Block" by shape: a slashed
## shield. The unit panel names the ban in words for anyone the mark doesn't reach.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: Godot_FE has no "no" sign, so the shield keeps the glyph over it.
## The shield drawn behind [member mark_text], tinted the [code]block[/code] token.[br]
## [b]Unset:[/b] the glyph alone.
@export var shield_texture: Texture2D = null:
	set(value):
		shield_texture = value
		if not is_node_ready():
			return
		_apply_shield()

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

@onready var _shield: TextureRect = %Shield


func _ready() -> void:
	text = mark_text
	_apply_shield()
	show_ban(is_banned)


## Shows the mark while [param banned] is true; hides it otherwise.
func show_ban(banned: bool) -> void:
	is_banned = banned
	visible = banned


## Whether the mark shows, for tests.
func is_shown() -> bool:
	return visible


## The shield drawn behind the glyph, for tests; null for none.
func get_shield() -> Texture2D:
	return _shield.texture if _shield.visible else null


func _apply_shield() -> void:
	_shield.texture = shield_texture
	_shield.visible = shield_texture != null
	_shield.self_modulate = UiTokens.color(UiTokens.BLOCK)
