# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_progress.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name DetailProgress
extends HBoxContainer
## A player unit's level and XP in the [UnitDetailPanel]: "Lv 4", a bar filling toward the next
## level, and the XP as a number (ui-lift.md, Unit detail pop-up; Godot_FE's
## [code]unit_experience_info[/code]). Hidden while there is no run record. Holds no rules.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The level: [code]%d[/code] the level.
@export var level_format: String = "Lv %d"

## The XP: [code]%d[/code] the XP toward the next level, then XP per level.
@export var xp_format: String = "XP %d / %d"

@onready var _level: Label = %Level
@onready var _bar: ProgressBar = %XpBar
@onready var _xp: Label = %Xp


## Shows [param level] with [param xp] of [param per_level]; hides when [param xp] is below 0 or
## [param per_level] is 0.
func show_progress(level: int, xp: int, per_level: int) -> void:
	visible = xp >= 0 and per_level > 0
	if not visible:
		return
	_level.text = level_format % [level]
	_bar.max_value = float(per_level)
	_bar.value = float(clampi(xp, 0, per_level))
	_xp.text = xp_format % [xp, per_level]


## Its lines as shown, for tests: level, XP (empty while hidden).
func get_texts() -> PackedStringArray:
	if not visible:
		return PackedStringArray(["", ""])
	return PackedStringArray([_level.text, _xp.text])
