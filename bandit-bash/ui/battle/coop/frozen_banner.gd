# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     frozen_banner.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name FrozenBanner
extends PanelContainer
## A frozen co-op map's banner ([method CombatEncounter.is_frozen]): no player unit is left there,
## so it waits at its next player phase until sent units land. [CoopBattle] shows it over the
## board while the viewed map is frozen; the [SendPanel] shows its own copy, with the rule that
## binds a send while any map is frozen. Reading only.

# ASSUMPTION: the banner's wordings; no design doc words them.
## The banner's title.
@export var title_text: String = "Frozen"

## The line on the seat's own frozen map.
@export var own_text: String = "None of your units are left; your map waits for a teammate's."

## The line on a teammate's frozen map: [code]%s[/code] its name ("Player 2's map").
@export var teammate_text: String = "%s has no player units left. It waits until help arrives."

## The send panel's line while any map is frozen: a send must take at least one unit there.
@export var rule_text: String = "A map is frozen: send at least one unit, to a frozen map."

@onready var _title: Label = %Title
@onready var _line: Label = %Line


func _ready() -> void:
	_title.text = title_text


## Shows the banner for the frozen map named [param map_title]; [param is_own]: the seat's own.
func show_map(map_title: String, is_own: bool) -> void:
	_line.text = own_text if is_own else teammate_text % [map_title]
	visible = true


## Shows the send rule while any map is frozen.
func show_rule() -> void:
	_line.text = rule_text
	visible = true


## The line shown, for tests.
func get_line() -> String:
	return _line.text
