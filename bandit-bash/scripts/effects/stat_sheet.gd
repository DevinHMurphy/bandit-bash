# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stat_sheet.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name StatSheet
extends RefCounted
## The static, cached values of one subject: a unit in combat, or a seat on the campaign layer.
##
## Holds base values and unconditional [Modifier]s (type base, prefix, permanent deltas, item
## stats and deltas, always-on effects) and answers queries through [ValueBreakdown], caching
## each key's answer until that key's inputs change. Conditional and timed modifiers are not
## stored here: they are checked live on every query by the effect engine's read API, which
## combines them with [method get_modifiers]. Callers never assemble a value themselves.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Instance id of the unit, or the seat's id, this sheet describes.
var subject_id: String = ""

# Base value per key; a key with no base starts at 0.
var _bases: Dictionary[int, float] = {}

# Text naming each base in breakdowns, such as "Hakkapel base".
var _base_labels: Dictionary[int, String] = {}

# Unconditional modifiers per key, each an Array[Modifier] (typed collections can't nest).
var _modifiers: Dictionary[int, Array] = {}

# Computed answers per value or permission key, dropped when that key's inputs change.
var _cache: Dictionary[int, ValueBreakdown] = {}


func _init(subject: String) -> void:
	subject_id = subject


## Sets the base of [param key], replacing any earlier base. [param label] names it in
## breakdowns ("base" when empty).
func set_base(key: int, value: float, label: String = "") -> void:
	_bases[key] = value
	_base_labels[key] = label
	_cache.erase(key)


## Adds an unconditional modifier to its key.
func add_modifier(modifier: Modifier) -> void:
	if not _modifiers.has(modifier.key):
		var list: Array[Modifier] = []
		_modifiers[modifier.key] = list
	_modifiers[modifier.key].append(modifier)
	_cache.erase(modifier.key)


## The unconditional modifiers of [param key], in the order they were added. A copy.
func get_modifiers(key: int) -> Array[Modifier]:
	var list: Array[Modifier] = []
	if _modifiers.has(key):
		list.assign(_modifiers[key])
	return list


## The exact value of [param key].
func get_value(key: int) -> float:
	return explain(key).total


## The value of [param key], rounded once by the key's rule.
func get_int(key: int) -> int:
	return explain(key).get_int()


## The full answer for [param key], with one line per source. Cached: don't modify it.
func explain(key: int) -> ValueBreakdown:
	if not _cache.has(key):
		_cache[key] = ValueBreakdown.compute(
				key, _bases.get(key, 0.0), _base_labels.get(key, ""), get_modifiers(key)
		)
	return _cache[key]


## Whether [param permission] is allowed. Any denial beats any grant.
func is_allowed(permission: int) -> bool:
	return explain_permission(permission).is_allowed()


## The full answer for [param permission], with one line per grant and denial. Cached: don't
## modify it.
func explain_permission(permission: int) -> ValueBreakdown:
	if not _cache.has(permission):
		_cache[permission] = ValueBreakdown.compute_permission(
				permission, get_modifiers(permission)
		)
	return _cache[permission]
