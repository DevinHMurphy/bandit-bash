# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_rolls.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventRolls
extends RefCounted
## One seat's rolled random parts of one event option: the content id each block drew, and the
## option's named curse.
##
## [method EventResolver.roll] fills [member picks] before the option shows, so the player sees
## the exact item or rune; the draw of a curse from its tier fills [member curse_id]. Plain data
## with ids only.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The content id each block drew, by the block's index in its option. Empty for a block whose
## pool was empty; missing for a block that draws nothing.
var picks: Dictionary[int, String] = {}

## Content id of the curse drawn for the option's curse tier. [b]Empty:[/b] none drawn.
var curse_id: String = ""


## What the block at [param index] drew; empty when it drew nothing.
func pick(index: int) -> String:
	return picks.get(index, "")
