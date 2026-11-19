# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_pick_reward.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemPickReward
extends VictoryReward
## A won combat's item pick as a reward row: take one of the offers or skip, in the
## [ItemRewardPicker]. Taken once the saved pick is resolved, either way.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## The picker that takes an item pick.
const PICKER_PATH: String = "res://ui/campaign/victory/item_reward_picker.tscn"

## The row's second line per slot kind.
const SLOT_DETAILS: Dictionary[ItemPick.Slot, String] = {
	ItemPick.Slot.WEAPON: "Choose a weapon, or skip",
	ItemPick.Slot.EQUIPMENT: "Choose equipment, or skip",
	ItemPick.Slot.POUCH: "Choose a pouch item, or skip",
}

## The saved pick.
var pick: ItemPick = null


## A reward for [param item_pick].
func _init(item_pick: ItemPick) -> void:
	pick = item_pick
	title = "Item pick"
	detail = SLOT_DETAILS.get(item_pick.slot, "Choose an item, or skip")
	picker_path = PICKER_PATH


func is_taken() -> bool:
	return pick == null or pick.is_resolved


func skip_command(seat: int) -> CampaignCommand:
	return ItemPickCommand.new(seat, ItemPickCommand.SKIP)
