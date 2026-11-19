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
## [CombatResultsModel]: today the item pick, while the combat offered one. Static; never
## instanced.
##
## Gold is not a reward here: it is granted as the combat ends and shows as collected in the
## Grade stage (ui-lift.md, decision 4).
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md
## @todo: TOD-001 - List the key combat's heirloom (RN7) and rune rewards once they are rolled.

## Every reward of [param model], taken ones included, in the order shown; empty for null.
static func build(model: CombatResultsModel) -> Array[VictoryReward]:
	var rewards: Array[VictoryReward] = []
	if model == null:
		return rewards
	if model.pick != null and not model.pick.offers.is_empty():
		rewards.append(ItemPickReward.new(model.pick))
	# TODO(TOD-001): the key combat's heirloom (RN7) and runes join here.
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
