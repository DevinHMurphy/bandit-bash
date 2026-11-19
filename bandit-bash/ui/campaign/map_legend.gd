# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_legend.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MapLegend
extends VBoxContainer
## The campaign map's key: each node type's colour and letter, with its name
## ([constant CampaignMapView.TYPE_NAMES]), read from [member map_view] so the two never
## disagree.
##
## Built once, when it enters the tree, a [MapLegendRow] per type. Takes no input.

const ROW_SCENE: PackedScene = preload("res://ui/campaign/map_legend_row.tscn")

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
		var row: MapLegendRow = ROW_SCENE.instantiate()
		row.swatch_size = swatch_size
		add_child(row)
		var color: Color = map_view.type_colors.get(type, Color.GRAY)
		var letter: String = map_view.type_letters.get(type, "?")
		row.show_type(color, letter, CampaignMapView.TYPE_NAMES[type])


## The legend's lines as text ("S  Combat"), for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in get_children():
		var row: MapLegendRow = child as MapLegendRow
		if row != null:
			lines.append(row.get_text())
	return lines
