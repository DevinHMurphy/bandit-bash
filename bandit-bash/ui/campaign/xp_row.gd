# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     xp_row.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name XpRow
extends HBoxContainer
## One unit's line in Results' XP: its name, how its XP adds up (shared, personal, the Standout's
## bonus, times its XP percent when that isn't 100), and its level and XP now.
##
## Reading only; takes no input.

## The width of the name column, so every row's breakdown lines up.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(40.0, 400.0, 1.0) var name_width: float = 150.0:
	set(value):
		name_width = value
		if not is_node_ready():
			return
		_name_label.custom_minimum_size.x = name_width

@onready var _name_label: Label = %Name
@onready var _breakdown_label: Label = %Breakdown
@onready var _level_label: Label = %Level


func _ready() -> void:
	_name_label.custom_minimum_size.x = name_width


## Shows [param line]; [param xp_per_level] is the XP a level takes.
func show_line(line: CombatResultsModel.XpLine, xp_per_level: int) -> void:
	_name_label.text = line.name
	_breakdown_label.text = breakdown_text(line.award)
	_level_label.text = "Lv %d · %d / %d XP" % [line.level, line.xp, xp_per_level]


## The breakdown as shown, for tests.
func get_breakdown_text() -> String:
	return _breakdown_label.text


## [param award] as a sum: [code]40 shared + 12 personal + 5 Standout = 57[/code], with
## [code]× 110%[/code] before the total when its percent isn't 100.
static func breakdown_text(award: XpAward) -> String:
	var text: String = "%d shared + %d personal" % [award.shared, award.personal]
	if award.is_standout:
		text += " + %d Standout" % [award.standout]
	if award.percent != 100:
		text = "(%s) × %d%%" % [text, award.percent]
	return "%s = %d" % [text, award.total]
