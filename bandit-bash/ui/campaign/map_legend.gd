# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_legend.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

class_name MapLegend
extends VBoxContainer
## The campaign map's key: each node type's colour and letter, with its name
## ([constant CampaignMapView.TYPE_NAMES]), read from [member map_view] so the two never
## disagree.
##
## Built once, when it enters the tree. Takes no input.

## The map whose colours and letters the legend lists.[br]
## [b]Unset:[/b] the legend stays empty.
@export var map_view: CampaignMapView = null

## The side of each colour swatch.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(8.0, 40.0, 1.0) var swatch_size: float = 14.0


func _ready() -> void:
	if map_view == null:
		return
	for type: CampaignGraph.NodeType in CampaignMapView.TYPE_NAMES:
		var row: HBoxContainer = HBoxContainer.new()
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(swatch_size, swatch_size)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = map_view.type_colors.get(type, Color.GRAY)
		var label: Label = Label.new()
		var letter: String = map_view.type_letters.get(type, "?")
		label.text = "%s  %s" % [letter, CampaignMapView.TYPE_NAMES[type]]
		row.add_child(swatch)
		row.add_child(label)
		add_child(row)


## The legend's lines as text ("S  Combat"), for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for row: Node in get_children():
		for child: Node in row.get_children():
			if child is Label:
				lines.append((child as Label).text)
	return lines
