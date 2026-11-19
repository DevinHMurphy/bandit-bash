# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_legend_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MapLegendRow
extends HBoxContainer
## One line of the campaign map's key ([MapLegend]): a node type's colour swatch, then its letter
## and name. Filled by the legend ([method show_type]); takes no input.

## The side of the colour swatch.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(8.0, 40.0, 1.0) var swatch_size: float = 14.0:
	set(value):
		swatch_size = value
		if not is_node_ready():
			return
		_swatch.custom_minimum_size = Vector2(swatch_size, swatch_size)

@onready var _swatch: ColorRect = %Swatch
@onready var _label: Label = %Label


func _ready() -> void:
	_swatch.custom_minimum_size = Vector2(swatch_size, swatch_size)


## Shows a node type in [param color], as [param letter] and [param type_name].
func show_type(color: Color, letter: String, type_name: String) -> void:
	_swatch.color = color
	_label.text = "%s  %s" % [letter, type_name]


## The line's text ("S  Combat").
func get_text() -> String:
	return _label.text
