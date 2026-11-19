# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_grade_stage.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name VictoryGradeStage
extends VBoxContainer
## The victory's first stage: the combat's two grades (under par, no losses), each earned or not
## with the gold it added; the combat's own gold; flat extra gold when there is any; and the total
## as already collected, with the gold held now (ui-lift.md, decision 4: gold is no reward row).
## Read from [CombatResultsModel]; nothing to choose, so it takes no focus.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

const ROW_SCENE: PackedScene = preload("res://ui/campaign/victory/grade_row.tscn")

@onready var _rows: VBoxContainer = %Rows
@onready var _total_label: Label = %Total
@onready var _held_label: Label = %Held


## Shows [param model]'s grades and gold.
func show_grades(model: CombatResultsModel) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var grades: CombatGrades = model.grades
	_add_row("Under par", grades.is_under_par, grades.bonus_per_grade)
	_add_row("No losses", grades.is_without_losses, grades.bonus_per_grade)
	_add_gold_row("Combat gold", "%d gold" % [grades.base_gold])
	if grades.extra_gold > 0:
		_add_gold_row("Extra gold", "+%d gold" % [grades.extra_gold])
	_total_label.text = "%d gold collected" % [grades.gold]
	_held_label.text = "You now hold %d gold." % [model.gold_held]


## Each row's text, in order, then the total, for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in _rows.get_children():
		if child is GradeRow and not child.is_queued_for_deletion():
			lines.append((child as GradeRow).get_text())
	lines.append(_total_label.text)
	return lines


func _add_row(grade: String, is_earned: bool, bonus: int) -> void:
	var row: GradeRow = ROW_SCENE.instantiate()
	_rows.add_child(row)
	row.show_row(grade, "Earned: +%d gold" % [bonus] if is_earned else "Not earned", is_earned)


func _add_gold_row(label: String, value: String) -> void:
	var row: GradeRow = ROW_SCENE.instantiate()
	_rows.add_child(row)
	row.show_row(label, value)
