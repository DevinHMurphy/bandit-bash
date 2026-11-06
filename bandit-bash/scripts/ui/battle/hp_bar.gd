# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hp_bar.gd
# Author:
# Created:  November 6, 2026
# Modified: November 6, 2026
# ==============================================================================

class_name HpBar
extends ProgressBar
## A unit's HP bar on its [UnitInfo], with the HP drawn inside it (combat UI plan, question 29
## (1)).
##
## Godot_FE's [code]Healthbar[/code] look, as data: the theme's [code]HpBar[/code] background
## and fill styles and [code]HpBarLabel[/code] number ([code]battle_theme.tres[/code]). Unlike
## Godot_FE's, it always shows, full or not, and it draws its number; it takes the value it is
## given ([method show_hp]) and holds no rules.[br]
## [b]Not a [StancePips]:[/b] HP is a continuous bar of tens of points with a number, so it shares
## nothing with the pips' per-point segments, overflow colour or Exposed look.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: the number is the current HP alone; question 29 (1) says "the numbers inside it".
## Whether the number also shows the maximum, as [code]14/22[/code].[br]
## [b]Off:[/b] only the current HP, as [code]14[/code].
@export var is_maximum_shown: bool = false:
	set(is_shown):
		is_maximum_shown = is_shown
		if not is_node_ready():
			return
		show_hp(roundi(value), roundi(max_value))

@onready var _number: Label = %Number


func _ready() -> void:
	show_hp(roundi(value), roundi(max_value))


## Shows [param current] HP of [param maximum]; HP is never shown below 0, and a maximum below 1
## is drawn as 1.
func show_hp(current: int, maximum: int) -> void:
	max_value = maxi(maximum, 1)
	value = maxi(current, 0)
	var shown: int = maxi(current, 0)
	_number.text = "%d/%d" % [shown, maxi(maximum, 1)] if is_maximum_shown else str(shown)


## The number drawn inside the bar.
func get_text() -> String:
	return _number.text
