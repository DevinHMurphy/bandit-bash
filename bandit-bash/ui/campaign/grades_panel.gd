# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     grades_panel.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name GradesPanel
extends VBoxContainer
## Results' grades and gold: the combat's base gold, each grade with the bonus it earned or a dash,
## any flat extra gold, and the total the seat was paid (game-vision.md, Gold).
##
## Reading only; takes no input.

## What a grade not earned shows in place of its bonus.
@export var missed_text: String = "—"

@onready var _rows: GridContainer = %Rows


## Shows [param grades] as one row per part, the total last.
func show_grades(grades: CombatGrades) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if grades == null:
		return
	_add_row("Base gold", str(grades.base_gold))
	_add_row(
			"Under par",
			"+%d" % [grades.bonus_per_grade] if grades.is_under_par else missed_text
	)
	_add_row(
			"No losses",
			"+%d" % [grades.bonus_per_grade] if grades.is_without_losses else missed_text
	)
	if grades.extra_gold != 0:
		_add_row("Extra gold", "%+d" % [grades.extra_gold])
	_add_row("Gold earned", str(grades.gold))


## The rows as text, [code]Label: value[/code] each, for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var cells: Array[Node] = _rows.get_children()
	for i: int in range(0, cells.size() - 1, 2):
		lines.append("%s: %s" % [(cells[i] as Label).text, (cells[i + 1] as Label).text])
	return lines


func _add_row(label: String, value: String) -> void:
	var name_label: Label = Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rows.add_child(name_label)
	_rows.add_child(value_label)
