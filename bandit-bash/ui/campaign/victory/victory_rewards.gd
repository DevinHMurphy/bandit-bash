# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_rewards.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name VictoryRewards
extends RefCounted
## The rewards of a won combat for the Rewards stage, read from the saved run through a
## [CombatResultsModel]: the item pick, while the combat offered one, then a Key combat's
## heirloom. Static; never instanced.
##
## Gold is not a reward here: it is granted as the combat ends and shows as collected in the
## Grade stage (ui-lift.md, decision 4).
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md
## @todo: TOD-001 - List rune rewards once they are rolled.

## Every reward of [param model], taken ones included, in the order shown; empty for null. The
## item pick's row shows its first offer's icon (the placeholder when no offer has one).
static func build(model: CombatResultsModel) -> Array[VictoryReward]:
	var rewards: Array[VictoryReward] = []
	if model == null:
		return rewards
	if model.pick != null and not model.pick.offers.is_empty():
		var item_pick: ItemPickReward = ItemPickReward.new(model.pick)
		# ASSUMPTION: the first offer's icon stands for the pick, as reward screens show an item;
		# a per-slot kind icon is the alternative.
		for definition: ItemDefinition in model.offers:
			if definition != null and definition.icon != null:
				item_pick.icon = definition.icon
				break
		rewards.append(item_pick)
	if model.key_heirloom != null:
		rewards.append(KeyHeirloomReward.new(model.key_heirloom, model.key_heirloom_definition))
	# TODO(TOD-001): rune rewards join here.
	return rewards


## The rewards of [param rewards] not yet taken, in order.
static func open_of(rewards: Array[VictoryReward]) -> Array[VictoryReward]:
	var open: Array[VictoryReward] = []
	for reward: VictoryReward in rewards:
		if not reward.is_taken():
			open.append(reward)
	return open


## Whether any of [param rewards] is taken: a resumed sequence then opens on the Rewards stage.
static func has_taken(rewards: Array[VictoryReward]) -> bool:
	for reward: VictoryReward in rewards:
		if reward.is_taken():
			return true
	return false
