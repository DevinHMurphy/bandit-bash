# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_reward.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name VictoryReward
extends RefCounted
## One reward of a won combat as the Rewards stage lists it: one [RewardRow], and the
## [RewardPicker] that takes it. Built from the run as saved ([VictoryRewards]), so whether it is
## taken survives a quit.
##
## Each kind of reward is a subclass that fills the fields and answers [method is_taken] and
## [method skip_command]; its picker sends the commands that take it. The overlay knows no kind,
## so a new reward joins with a subclass and a picker scene.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

## What the row reads, in Alegreya.
var title: String = ""

## The row's second line: what the reward offers.
var detail: String = ""

## The row's 32-unit icon; null shows the placeholder mark.
var icon: Texture2D = null

## The [RewardPicker] scene that takes it, by path: loaded when the row is chosen, so this
## script and the picker's never preload each other.
var picker_path: String = ""


## Whether the seat took or settled it in the saved run, so its row leaves the list.
func is_taken() -> bool:
	return true


## The command Leave sends to give it up while it is open; null for none needed.
func skip_command(_seat: int) -> CampaignCommand:
	return null
