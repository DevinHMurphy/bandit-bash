# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reward_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RewardRow
extends Button
## One reward in the victory's Rewards stage, as the style guide's row: its 32-unit icon on the
## left, its title and what it offers, and a hint on the right. Pressing it (click, Enter or A)
## emits [signal pressed]; the stage opens the reward's picker. Its height follows its content.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## The right-hand hint, saying what pressing the row does.
@export var hint: String = "Choose":
	set(value):
		hint = value
		if is_node_ready():
			_hint_label.text = hint

var _reward: VictoryReward = null

@onready var _content: MarginContainer = %Content
@onready var _icon: RewardIcon = %Icon
@onready var _title_label: Label = %Title
@onready var _detail_label: Label = %Detail
@onready var _hint_label: Label = %Hint


func _ready() -> void:
	_hint_label.text = hint
	_content.minimum_size_changed.connect(_fit)
	_fit()


## Shows [param reward].
func show_reward(reward: VictoryReward) -> void:
	_reward = reward
	_icon.texture = reward.icon
	_title_label.text = reward.title
	_detail_label.text = reward.detail


## The reward shown; null before [method show_reward].
func get_reward() -> VictoryReward:
	return _reward


## The row's title, for tests.
func get_title() -> String:
	return _title_label.text


# The button sizes to its content, which it doesn't lay out itself.
func _fit() -> void:
	custom_minimum_size = Vector2(0.0, _content.get_combined_minimum_size().y)
