# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reward_picker.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RewardPicker
extends Control
## The base of every reward's picker: a modal the [VictoryOverlay] opens over the Rewards stage
## when a [RewardRow] is chosen ([member VictoryReward.picker_path]).
##
## A picker sends its own commands through [code]CampaignService.submit_command()[/code], which
## saves, and then reports [signal resolved]: the overlay rebuilds the list from the saved run, so
## the taken row leaves it. Backing out reports [signal cancelled] and changes nothing. Each
## subclass's scene is its own look and focus.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## The reward was taken or settled and saved; [param note] says what became of it (shown on the
## overlay's status line), or is empty.
signal resolved(note: String)

## The player backed out: nothing was sent.
signal cancelled()

## [method get_hint_context] changed, so the overlay's hint bar follows the picker's step.
signal hint_context_changed()


## Opens for [param reward] of seat [param seat], focusing its first choice.
func open(_reward: VictoryReward, _seat: int) -> void:
	pass


## The hint bar's context while the picker shows: a key of the overlay's [ScreenHints] actions.
func get_hint_context() -> StringName:
	return &"PICK"
