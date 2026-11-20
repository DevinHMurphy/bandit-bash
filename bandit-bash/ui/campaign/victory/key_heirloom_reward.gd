# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     key_heirloom_reward.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name KeyHeirloomReward
extends VictoryReward
## A won Key combat's heirloom as a reward row: take it, in the [KeyHeirloomPicker], or give it up.
## Taken once the saved offer is resolved, either way; Leave gives it up
## ([KeyHeirloomCommand] not taking).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The picker that takes a Key combat's heirloom.
const PICKER_PATH: String = "res://ui/campaign/victory/key_heirloom_picker.tscn"

## The saved offer.
var offer: KeyHeirloom = null


## A reward for [param heirloom_offer], showing [param definition]'s name and icon (null: its id
## and the placeholder mark).
func _init(heirloom_offer: KeyHeirloom, definition: HeirloomDefinition) -> void:
	offer = heirloom_offer
	title = "Heirloom"
	detail = definition.display_name if definition != null else heirloom_offer.heirloom_id
	icon = definition.icon if definition != null else null
	picker_path = PICKER_PATH


func is_taken() -> bool:
	return offer == null or offer.is_resolved


func skip_command(seat: int) -> CampaignCommand:
	return KeyHeirloomCommand.new(seat, false)
