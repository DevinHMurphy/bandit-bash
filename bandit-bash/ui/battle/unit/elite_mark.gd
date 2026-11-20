# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     elite_mark.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EliteMark
extends Panel
## The mark on an elite's [UnitInfo]: an enemy with a prefix (RF-025), so the board shows it
## without opening the unit's detail. The placeholder style (ui-style.md, Icons): a flat
## [member color] symbol on the theme's [code]EliteMark[/code] dark circle. Beside, not instead
## of, a leader's [LeaderMark] outline. Holds no rules.
##
## @tutorial(UI lift, UL6): docs/design/ui-lift.md

# NOTE: the scene's crown is the commander heirloom's icon, the only fitting art: a placeholder
# that may read as that heirloom until the art pass (RF-008).
## The symbol drawn.[br]
## [b]Unset:[/b] the circle shows alone.
@export var icon: Texture2D = null:
	set(value):
		icon = value
		if is_node_ready():
			_icon.texture = icon

## The symbol's colour. Defaults to the [code]accent[/code] token.
@export var color: Color = UiTokens.color(UiTokens.ACCENT):
	set(value):
		color = value
		if is_node_ready():
			_icon.self_modulate = color

@onready var _icon: TextureRect = %Icon


func _ready() -> void:
	_icon.texture = icon
	_icon.self_modulate = color


## Shows the mark while [param is_elite].
func show_elite(is_elite: bool) -> void:
	visible = is_elite


## Whether the mark shows.
func is_shown() -> bool:
	return visible
