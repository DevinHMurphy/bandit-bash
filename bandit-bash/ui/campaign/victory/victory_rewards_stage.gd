# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_rewards_stage.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name VictoryRewardsStage
extends VBoxContainer
## The victory's last stage: a centred list with a [RewardRow] per reward not yet taken, or a line
## saying none is left. It only asks: choosing a row emits [signal reward_chosen] and the
## [VictoryOverlay] opens its picker. The rows are one column whose last leads down to the
## overlay's Leave ([method link_focus]). Reads no input action itself.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## The player chose [param reward]'s row.
signal reward_chosen(reward: VictoryReward)

const ROW_SCENE: PackedScene = preload("res://ui/campaign/victory/reward_row.tscn")

@onready var _rows: VBoxContainer = %Rows
@onready var _empty_label: Label = %Empty


## Shows a row per reward of [param rewards] in order; the "none left" line when it is empty.
func show_rewards(rewards: Array[VictoryReward]) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for reward: VictoryReward in rewards:
		var row: RewardRow = ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.show_reward(reward)
		row.pressed.connect(_on_row_pressed.bind(reward))
	_empty_label.visible = rewards.is_empty()


## The rows shown, in order.
func get_rows() -> Array[RewardRow]:
	var rows: Array[RewardRow] = []
	for child: Node in _rows.get_children():
		if child is RewardRow and not child.is_queued_for_deletion():
			rows.append(child as RewardRow)
	return rows


## Gives focus to the first row; returns whether one took it.
func focus_first() -> bool:
	var rows: Array[RewardRow] = get_rows()
	if rows.is_empty():
		return false
	rows[0].grab_focus()
	return true


## Links the rows as one column: up and down step along it, the last row's down goes to
## [param below] and [param below]'s up to the last row (to itself with no rows).
func link_focus(below: Control) -> void:
	var rows: Array[RewardRow] = get_rows()
	for i: int in rows.size():
		var row: RewardRow = rows[i]
		var self_path: NodePath = row.get_path_to(row)
		row.focus_neighbor_top = row.get_path_to(rows[maxi(i - 1, 0)])
		row.focus_neighbor_bottom = (
				row.get_path_to(below) if i == rows.size() - 1 else row.get_path_to(rows[i + 1])
		)
		row.focus_neighbor_left = self_path
		row.focus_neighbor_right = self_path
		row.focus_previous = row.focus_neighbor_top
		row.focus_next = row.focus_neighbor_bottom
	below.focus_neighbor_top = (
			below.get_path_to(rows[rows.size() - 1]) if not rows.is_empty()
			else below.get_path_to(below)
	)


func _on_row_pressed(reward: VictoryReward) -> void:
	reward_chosen.emit(reward)
