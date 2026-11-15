# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     xp_panel.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name XpPanel
extends VBoxContainer
## Results' experience: one [XpRow] per unit still standing, in roster order, and the Standout
## named below them (game-vision.md, Units: Experience).
##
## Reading only; takes no input. Units that fell earned nothing and aren't in the report, so
## they aren't listed.

const ROW_SCENE: PackedScene = preload("res://ui/campaign/xp_row.tscn")

@onready var _rows: VBoxContainer = %Rows
@onready var _standout_label: Label = %Standout


## Shows [param model]'s XP lines and its Standout.
func show_xp(model: CombatResultsModel) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for line: CombatResultsModel.XpLine in model.xp_lines:
		var row: XpRow = ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.show_line(line, model.xp_per_level)
	_standout_label.text = (
			"Standout: %s" % [model.standout_name] if not model.standout_name.is_empty()
			else "No Standout: nobody acted."
	)


## The rows shown, for tests.
func get_rows() -> Array[XpRow]:
	var rows: Array[XpRow] = []
	for child: Node in _rows.get_children():
		rows.append(child as XpRow)
	return rows


## The Standout line as shown, for tests.
func get_standout_text() -> String:
	return _standout_label.text
