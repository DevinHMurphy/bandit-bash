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
## [EventDraw] fills it when the event is made, before the option shows, so the player sees the
## exact item, rune, heirloom and curse: [method EventResolver.roll] the items and runes, then the
## tier heirlooms and the tier curse. Plain data with ids only, saved in the [code]events[/code]
## section through [method capture] and [method restore].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_PICKS: String = "picks"
const _KEY_CURSE: String = "curse"

## The content id each block drew, by the block's index in its option. Empty for a block whose
## pool was empty; missing for a block that draws nothing.
var picks: Dictionary[int, String] = {}

## Content id of the curse drawn for the option's curse tier. [b]Empty:[/b] none drawn.
var curse_id: String = ""


## What the block at [param index] drew; empty when it drew nothing.
func pick(index: int) -> String:
	return picks.get(index, "")


## These rolls as plain JSON: block indices as decimal strings.
func capture() -> Dictionary:
	var pick_data: Dictionary = {}
	for index: int in picks:
		pick_data[str(index)] = picks[index]
	return {_KEY_PICKS: pick_data, _KEY_CURSE: curse_id}


## The rolls [param data] describes, as [method capture] wrote it; null for a missing field, a
## block index that isn't a whole number from 0, or an id that isn't a string.
static func restore(data: Dictionary) -> EventRolls:
	var pick_data: Variant = data.get(_KEY_PICKS)
	var curse: Variant = data.get(_KEY_CURSE)
	if not pick_data is Dictionary or not curse is String:
		return null
	var rolls: EventRolls = EventRolls.new()
	for key: Variant in pick_data as Dictionary:
		var value: Variant = (pick_data as Dictionary)[key]
		if not key is String or not (key as String).is_valid_int() or not value is String:
			return null
		var index: int = (key as String).to_int()
		if index < 0:
			return null
		rolls.picks[index] = value as String
	rolls.curse_id = curse as String
	return rolls
