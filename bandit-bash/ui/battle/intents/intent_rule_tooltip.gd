# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_rule_tooltip.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name IntentRuleTooltip
extends Node2D
## The hovered enemy's target rule beside its intent icon (combat UI plan, question 10), such as
## "Nearest foe it can hit", or the darkness's "Nearest foe" once it has arrived
## ([member EnemyIntent.target_rule_text]).
##
## A panel and label authored in the scene, styled by the battle theme
## ([code]IntentRuleLabel[/code]); its origin is the enemy's tile centre. [IntentDisplay] shows
## and hides it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The enemy whose rule shows; empty while hidden.
var enemy_id: String = ""

@onready var _panel: PanelContainer = %RulePanel
@onready var _label: Label = %RuleLabel


func _ready() -> void:
	hide_rule()


## Shows [param text], the rule of [param shown_id], at [param board_position], the enemy's tile
## centre in the board's space.
func show_rule(shown_id: String, text: String, board_position: Vector2) -> void:
	enemy_id = shown_id
	_label.text = text
	position = board_position
	# The panel sits centred above its anchor, however wide the text makes it.
	_panel.reset_size()
	_panel.position.x = -_panel.size.x * 0.5
	visible = true


## Hides the tooltip.
func hide_rule() -> void:
	enemy_id = ""
	visible = false


## The text shown; empty while hidden.
func get_text() -> String:
	return _label.text if visible else ""
