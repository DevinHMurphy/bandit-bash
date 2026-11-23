# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_rolls.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventRolls
extends RefCounted
## One seat's rolled random parts of one event option: the content id each block drew, a
## recruit's prefix, and the option's named curse.
##
## [EventDraw] fills it when the event is made, before the option shows, so the player sees the
## exact item, rune, heirloom, recruit and curse: [method EventResolver.roll] the items and runes,
## then the tier heirlooms, the tier curse, and last each recruit. Plain data with ids only, saved
## in the [code]events[/code] section through [method capture] and [method restore].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_PICKS: String = "picks"
const _KEY_CURSE: String = "curse"
const _KEY_PREFIXES: String = "prefixes"

## The content id each block drew, by the block's index in its option: an item, rune or heirloom,
## or a recruit's unit type. Empty for a block whose pool was empty; missing for a block that
## draws nothing, and for a recruit in a run saved before recruits were rolled.
var picks: Dictionary[int, String] = {}

## Content id of the unit prefix each recruit block rolled, by the block's index, beside its type
## in [member picks]. [constant UnitPrefixDefinition.NO_PREFIX] for none.
var prefixes: Dictionary[int, String] = {}

## Content id of the curse drawn for the option's curse tier. [b]Empty:[/b] none drawn.
var curse_id: String = ""


## What the block at [param index] drew; empty when it drew nothing.
func pick(index: int) -> String:
	return picks.get(index, "")


## The unit prefix the recruit block at [param index] rolled; empty when it rolled none.
func prefix(index: int) -> String:
	return prefixes.get(index, UnitPrefixDefinition.NO_PREFIX)


## These rolls as plain JSON: block indices as decimal strings. The prefixes are left out when
## there are none, so an option without a recruit saves as it always has.
func capture() -> Dictionary:
	var data: Dictionary = {_KEY_PICKS: _by_index(picks), _KEY_CURSE: curse_id}
	if not prefixes.is_empty():
		data[_KEY_PREFIXES] = _by_index(prefixes)
	return data


## The rolls [param data] describes, as [method capture] wrote it; null for a missing field, a
## block index that isn't a whole number from 0, or an id that isn't a string. The prefixes are
## optional (none).
static func restore(data: Dictionary) -> EventRolls:
	var pick_data: Variant = data.get(_KEY_PICKS)
	var curse: Variant = data.get(_KEY_CURSE)
	var prefix_data: Variant = data.get(_KEY_PREFIXES, {})
	if not pick_data is Dictionary or not curse is String or not prefix_data is Dictionary:
		return null
	var rolls: EventRolls = EventRolls.new()
	if (
			not _read_by_index(pick_data as Dictionary, rolls.picks)
			or not _read_by_index(prefix_data as Dictionary, rolls.prefixes)
	):
		return null
	rolls.curse_id = curse as String
	return rolls


# ids as JSON: block indices as decimal strings.
static func _by_index(ids: Dictionary[int, String]) -> Dictionary:
	var found: Dictionary = {}
	for index: int in ids:
		found[str(index)] = ids[index]
	return found


# Fills into from data as _by_index() wrote it; false for a key that isn't a whole number from 0
# or a value that isn't a string.
static func _read_by_index(data: Dictionary, into: Dictionary[int, String]) -> bool:
	for key: Variant in data:
		var value: Variant = data[key]
		if not key is String or not (key as String).is_valid_int() or not value is String:
			return false
		var index: int = (key as String).to_int()
		if index < 0:
			return false
		into[index] = value as String
	return true
