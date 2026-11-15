# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     level_up_panel.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name LevelUpPanel
extends VBoxContainer
## Results' level-ups, all shown at once (game-vision.md, Units: Experience): each unit that
## leveled, the level it reached and every stat point it gained, one line per level-up.
##
## Reading only; takes no input.

## What shows when nobody leveled up.
@export var none_text: String = "No level-ups."

@onready var _lines: Label = %Lines


## Shows [param model]'s level-ups, in the order reached.
func show_level_ups(model: CombatResultsModel) -> void:
	var lines: PackedStringArray = []
	for leveled: CombatResultsModel.LevelUpLine in model.level_up_lines:
		lines.append("%s reached Lv %d: %s" % [leveled.name, leveled.level, leveled.gains])
	_lines.text = none_text if lines.is_empty() else "\n".join(lines)


## The lines as shown, for tests.
func get_text() -> String:
	return _lines.text
