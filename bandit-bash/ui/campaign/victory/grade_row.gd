# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     grade_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name GradeRow
extends PanelContainer
## One line of the victory's Grade stage: a grade or a gold part on the left, what it paid on the
## right. A grade not earned reads "Not earned" in muted text, so colour is never the only sign.
## Not focusable: the stage has nothing to choose.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

@onready var _label: Label = %Label
@onready var _value: Label = %Value


## Shows [param label] with [param value]; muted when not [param is_earned].
func show_row(label: String, value: String, is_earned: bool = true) -> void:
	_label.text = label
	_value.text = value
	_value.theme_type_variation = &"BodyLabel" if is_earned else &"MutedLabel"


## The row as one line, for tests: [code]Under par: +8 gold[/code].
func get_text() -> String:
	return "%s: %s" % [_label.text, _value.text]
