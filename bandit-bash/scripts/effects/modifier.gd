# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     modifier.gd
# Author:
# Created:  October 26, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name Modifier
extends RefCounted
## One sourced change to a value key or a permission: "+8 Bounty Ledger", "×0.5 Bulwark".
##
## Runtime data, created from effect operations and item or unit deltas; never a Resource, so it
## carries no shared state. [ValueBreakdown] combines a key's modifiers in a fixed order of
## [enum Mode], so the order they were added in never matters.[br]
## [member key] is a value from [CombatValue], [DamageStage] or [CampaignValue]; those classes
## own disjoint blocks of numbers, so one int names any key.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## How a modifier changes its key. Value modes apply in the order listed; the rule clamps of the
## key's class apply after [constant FIXED].
enum Mode {
	## "X instead of Y": replaces the base and keeps every other bonus. One per key wins.
	REPLACE_BASE = 0,
	## "+X": added to the value. Flat changes apply before multipliers.
	ADD = 1,
	## "×X" or "+X%" (as a factor, so +20% is 1.2): every factor multiplies.
	MULTIPLY = 2,
	## "At least X": the highest floor applies.
	FLOOR = 3,
	## "At most X": the lowest cap applies.
	CAP = 4,
	## "Always X": the final value, ignoring every other modifier. One per key wins.
	FIXED = 5,
	## Allows a permission, unless anything denies it.
	GRANT = 6,
	## Forbids a permission. Denial beats grant.
	DENY = 7,
}

## The kind of carrier a modifier comes from. Values follow the reaction order of carrier kinds
## (event bus plan, question 6); [method get_specificity] ranks them for override collisions.
enum SourceKind {
	## A unit-type trait.
	UNIT_TRAIT = 0,
	## The Weapon slot or the stowed weapon.
	WEAPON = 1,
	## The Equipment slot.
	EQUIPMENT = 2,
	## A Pouch item.
	POUCH_ITEM = 3,
	## A heirloom of the owner's army.
	HEIRLOOM = 4,
	## A curse (a negative heirloom).
	CURSE = 5,
	## A rune cast this combat.
	RUNE = 6,
}

## [member stat] of a modifier whose key isn't per stat.
const NO_STAT: int = -1

## What [method key_from_id] returns for text that names no value key or permission.
const NO_KEY: int = -1

# The enums a value key or permission comes from, by the prefix that names them in saved data
# (key_id()). The classes own disjoint blocks of numbers, so each key has exactly one prefix.
const _KEY_ENUMS: Dictionary[String, Dictionary] = {
	"combat": CombatValue.Key,
	"combat_permission": CombatValue.Permission,
	"stage": DamageStage.Key,
	"campaign": CampaignValue.Key,
	"campaign_permission": CampaignValue.Permission,
}

## The key this modifier changes: a [CombatValue], [DamageStage] or [CampaignValue] value.
var key: int = 0

## The [enum CombatValue.Stat] a per-stat key's modifier applies to, such as Speed for Training
## Weights' denial of [constant CampaignValue.STAT_CAN_GROW]. [constant NO_STAT] for other keys.
var stat: int = NO_STAT

## How it changes [member key].
var mode: Mode = Mode.ADD

## The amount: an addend, a factor, a bound, or a replacement. Ignored by [constant GRANT] and
## [constant DENY]. For an enum-valued key, the enum value.
var value: float = 0.0

## The kind of carrier it comes from.
var source_kind: SourceKind = SourceKind.UNIT_TRAIT

## Instance id of the effect or carrier it comes from. Breaks override ties; never parsed.
var source_id: String = ""

## Display name of the source for breakdown text, such as "Iron Skin".
var label: String = ""


func _init(
		modifier_key: int,
		modifier_mode: Mode,
		modifier_value: float,
		modifier_source_kind: SourceKind,
		modifier_source_id: String,
		modifier_label: String
) -> void:
	key = modifier_key
	mode = modifier_mode
	value = modifier_value
	source_kind = modifier_source_kind
	source_id = modifier_source_id
	label = modifier_label


## Whether this is a permission modifier ([constant GRANT] or [constant DENY]).
func is_permission() -> bool:
	return mode == Mode.GRANT or mode == Mode.DENY


## How specific the source is when two overrides collide on one key: lower wins. The unit's own
## items beat its trait, which beats a heirloom, which beats a rune (event bus plan, questions 9
## and 37).
func get_specificity() -> int:
	match source_kind:
		SourceKind.WEAPON, SourceKind.EQUIPMENT, SourceKind.POUCH_ITEM:
			return 0
		SourceKind.UNIT_TRAIT:
			return 1
		SourceKind.HEIRLOOM, SourceKind.CURSE:
			return 2
	return 3


## Whether this modifier sorts before [param other] in the canonical order: mode, specificity,
## source id, value, label. Sorting by it makes a breakdown independent of insertion order.
func sorts_before(other: Modifier) -> bool:
	if mode != other.mode:
		return mode < other.mode
	if get_specificity() != other.get_specificity():
		return get_specificity() < other.get_specificity()
	if source_id != other.source_id:
		return source_id < other.source_id
	if value != other.value:
		return value < other.value
	return label < other.label


## This modifier as plain JSON values, for snapshots and saves: its key, stat and enums by name
## (save-system.md data rules). [method from_capture] reverses it.
func capture() -> Dictionary:
	return {
		"key": Modifier.key_id(key),
		"stat": "" if stat == NO_STAT else CombatValue.Stat.find_key(stat) as String,
		"mode": Mode.find_key(mode) as String,
		"value": value,
		"source_kind": SourceKind.find_key(source_kind) as String,
		"source_id": source_id,
		"label": label,
	}


## A modifier from [method capture] output, also after a trip through JSON. Returns
## [code]null[/code] when a field is missing or names an unknown key, stat or enum value.
static func from_capture(data: Dictionary) -> Modifier:
	var modifier_key: int = Modifier.key_from_id(str(data.get("key", "")))
	var mode_name: String = str(data.get("mode", ""))
	var kind_name: String = str(data.get("source_kind", ""))
	var stat_name: String = str(data.get("stat", ""))
	var number: Variant = data.get("value", null)
	if (
			modifier_key == NO_KEY
			or not Mode.has(mode_name)
			or not SourceKind.has(kind_name)
			or not (stat_name.is_empty() or CombatValue.Stat.has(stat_name))
			or not (number is float or number is int)
	):
		return null
	var mode_value: int = Mode[mode_name]
	var kind_value: int = SourceKind[kind_name]
	var amount: float = number
	var modifier: Modifier = Modifier.new(
			modifier_key,
			mode_value as Mode,
			amount,
			kind_value as SourceKind,
			str(data.get("source_id", "")),
			str(data.get("label", ""))
	)
	if not stat_name.is_empty():
		var stat_value: int = CombatValue.Stat[stat_name]
		modifier.stat = stat_value
	return modifier


## [param value_key] (a [CombatValue], [DamageStage] or [CampaignValue] key or permission) as the
## text saved data names it by, such as [code]combat.HIT[/code]; empty for an unknown key.
## [method key_from_id] reverses it.
static func key_id(value_key: int) -> String:
	for prefix: String in _KEY_ENUMS:
		var name: Variant = _KEY_ENUMS[prefix].find_key(value_key)
		if name != null:
			return "%s.%s" % [prefix, name]
	return ""


## The value key or permission [param id] names ([method key_id]); [constant NO_KEY] when it
## names none.
static func key_from_id(id: String) -> int:
	var parts: PackedStringArray = id.split(".")
	if parts.size() != 2 or not _KEY_ENUMS.has(parts[0]):
		return NO_KEY
	var keys: Dictionary = _KEY_ENUMS[parts[0]]
	return keys.get(parts[1], NO_KEY)
