# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     level_up_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name LevelUpCard
extends PanelContainer
## One level-up over the victory recap: the unit's name, the level it reached and every stat point
## it gained. The recap shows the level-ups in the order reached, one card at a time; Continue
## moves on. Reads no input.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

@onready var _name_label: Label = %Name
@onready var _level_label: Label = %Level
@onready var _gains_label: Label = %Gains
@onready var _count_label: Label = %Count


## Shows [param line], the [param index]-th (from 0) of [param count] level-ups.
func show_level_up(line: CombatResultsModel.LevelUpLine, index: int, count: int) -> void:
	_name_label.text = line.name
	_level_label.text = "Level %d" % [line.level]
	_gains_label.text = line.gains
	_count_label.text = "Level-up %d of %d" % [index + 1, count]
	_count_label.visible = count > 1


## The card's text in reading order, for tests.
func get_text() -> String:
	return " | ".join([_name_label.text, _level_label.text, _gains_label.text])
