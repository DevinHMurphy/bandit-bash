# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     board_key_row.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name BoardKeyRow
extends HBoxContainer
## One line of the [BoardKey]: a [ProfileMark] drawn as the board draws it, then what it means.
## The campaign [MapLegendRow]'s look, with the mark in its swatch's place. Filled by the key
## ([method show_row]); takes no input.

## The side of the mark's square.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(8.0, 40.0, 1.0) var mark_size: float = 14.0:
	set(value):
		mark_size = value
		if not is_node_ready():
			return
		_mark.mark_size = mark_size

@onready var _mark: ProfileMark = %ProfileMark
@onready var _label: Label = %Label


func _ready() -> void:
	_mark.mark_size = mark_size


## Shows [param profile]'s shape in [param side]'s style, then [param text].
func show_row(
		side: CombatFact.CombatSide, profile: WeaponTriangle.Profile, text: String
) -> void:
	_mark.show_mark(side, profile)
	_label.text = text


## The line's text ("Power — beats Balance").
func get_text() -> String:
	return _label.text


## The mark, for tests.
func get_profile_mark() -> ProfileMark:
	return _mark
