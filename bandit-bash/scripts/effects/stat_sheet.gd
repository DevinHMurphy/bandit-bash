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
## The values of one subject: a unit in combat, or a seat on the campaign layer.
##
## Holds base values and unconditional [Modifier]s (type base, prefix, permanent deltas, item
## stats and deltas, always-on effects) and caches each key's static answer until that key's
## inputs change. A sheet made by an [EffectEngine] also adds the live part on every query:
## conditional effects, timed modifiers and the "that hit" modifiers of [param ctx], from
## [method EffectEngine.live_modifiers]. Callers never assemble a value themselves.[br]
## A per-stat key ([constant CampaignValue.STAT_CAN_GROW]) is answered once per
## [enum CombatValue.Stat]: pass the stat, and only modifiers naming it count.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

# Cache slots per key: one per stat plus Modifier.NO_STAT. Above the Stat enum's size.
const _STAT_SLOTS: int = 16

## Instance id of the unit, or the seat's id, this sheet describes.
var subject_id: String = ""

# Base value per key; a key with no base starts at 0.
var _bases: Dictionary[int, float] = {}

# Text naming each base in breakdowns, such as "Hakkapel base".
var _base_labels: Dictionary[int, String] = {}

# Unconditional modifiers per key, each an Array[Modifier] (typed collections can't nest).
var _modifiers: Dictionary[int, Array] = {}

# Static answers per cache slot (key and stat), dropped when that key's inputs change.
var _cache: Dictionary[int, ValueBreakdown] = {}

# The engine adding the live part, held weakly: an engine caches its sheets, so a strong
# reference back would be a cycle. Null for a standalone sheet.
var _engine_ref: WeakRef = null


## [param engine]: adds the live part to every query. [b]Null:[/b] static values only.
func _init(subject: String, engine: EffectEngine = null) -> void:
	subject_id = subject
	_engine_ref = null if engine == null else weakref(engine)


## Sets the base of [param key], replacing any earlier base. [param label] names it in
## breakdowns ("base" when empty).
func set_base(key: int, value: float, label: String = "") -> void:
	_bases[key] = value
	_base_labels[key] = label
	_drop_cached(key)


## The base of [param key]: the one set, else its [constant CampaignValue.DEFAULT_BASES] entry,
## else 0.
func get_base(key: int) -> float:
	return _bases.get(key, CampaignValue.DEFAULT_BASES.get(key, 0.0))


## Adds an unconditional modifier to its key.
func add_modifier(modifier: Modifier) -> void:
	if not _modifiers.has(modifier.key):
		var list: Array[Modifier] = []
		_modifiers[modifier.key] = list
	_modifiers[modifier.key].append(modifier)
	_drop_cached(modifier.key)


## The unconditional modifiers of [param key] for [param stat], in the order they were added. A
## copy.
func get_modifiers(key: int, stat: int = Modifier.NO_STAT) -> Array[Modifier]:
	var list: Array[Modifier] = []
	if not _modifiers.has(key):
		return list
	for modifier: Modifier in _modifiers[key]:
		if modifier.stat == stat:
			list.append(modifier)
	return list


## The exact value of [param key].
func get_value(
		key: int, ctx: EffectContext = null, stat: int = Modifier.NO_STAT
) -> float:
	return explain(key, ctx, stat).total


## The value of [param key], rounded once by the key's rule.
func get_int(key: int, ctx: EffectContext = null, stat: int = Modifier.NO_STAT) -> int:
	return explain(key, ctx, stat).get_int()


## The full answer for [param key], with one line per source. Don't modify it: a query with no
## live modifiers returns the cached static answer.
## [param ctx]: the action in flight, for conditions and "that hit" modifiers; null for none.
func explain(
		key: int, ctx: EffectContext = null, stat: int = Modifier.NO_STAT
) -> ValueBreakdown:
	var static_answer: ValueBreakdown = explain_static(key, stat)
	var engine: EffectEngine = _engine()
	if engine == null:
		return static_answer
	var live: Array[Modifier] = engine.live_modifiers(subject_id, key, ctx, stat)
	if live.is_empty():
		return static_answer
	var modifiers: Array[Modifier] = get_modifiers(key, stat)
	modifiers.append_array(live)
	return ValueBreakdown.compute(key, get_base(key), _base_labels.get(key, ""), modifiers)


## Whether [param permission] is allowed. Any denial beats any grant.
func is_allowed(
		permission: int, ctx: EffectContext = null, stat: int = Modifier.NO_STAT
) -> bool:
	return explain_permission(permission, ctx, stat).is_allowed()


## The full answer for [param permission], with one line per grant and denial. Don't modify it.
func explain_permission(
		permission: int, ctx: EffectContext = null, stat: int = Modifier.NO_STAT
) -> ValueBreakdown:
	var static_answer: ValueBreakdown = explain_static_permission(permission, stat)
	var engine: EffectEngine = _engine()
	if engine == null:
		return static_answer
	var live: Array[Modifier] = engine.live_modifiers(subject_id, permission, ctx, stat)
	if live.is_empty():
		return static_answer
	var modifiers: Array[Modifier] = get_modifiers(permission, stat)
	modifiers.append_array(live)
	return ValueBreakdown.compute_permission(permission, modifiers)


## The cached answer for [param key] from this sheet's bases and modifiers only, without the live
## part. Don't modify it.
func explain_static(key: int, stat: int = Modifier.NO_STAT) -> ValueBreakdown:
	var slot: int = _slot(key, stat)
	if not _cache.has(slot):
		_cache[slot] = ValueBreakdown.compute(
				key, get_base(key), _base_labels.get(key, ""), get_modifiers(key, stat)
		)
	return _cache[slot]


## The cached answer for [param permission] from this sheet's modifiers only. Don't modify it.
func explain_static_permission(
		permission: int, stat: int = Modifier.NO_STAT
) -> ValueBreakdown:
	var slot: int = _slot(permission, stat)
	if not _cache.has(slot):
		_cache[slot] = ValueBreakdown.compute_permission(
				permission, get_modifiers(permission, stat)
		)
	return _cache[slot]


## A copy with the same bases and modifiers, linked to [param engine] (a sandbox's engine).
## Modifiers are shared: they are never changed once added.
func copy_for(engine: EffectEngine) -> StatSheet:
	var copy: StatSheet = StatSheet.new(subject_id, engine)
	for key: int in _bases:
		copy.set_base(key, _bases[key], _base_labels.get(key, ""))
	for key: int in _modifiers:
		for modifier: Modifier in _modifiers[key]:
			copy.add_modifier(modifier)
	return copy


## Every key and stat this sheet holds a base or a modifier for, as (key, stat) pairs: what
## [EffectEngine]'s verify mode compares.
func get_slots() -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	for key: int in _bases:
		slots.append(Vector2i(key, Modifier.NO_STAT))
	for key: int in _modifiers:
		for modifier: Modifier in _modifiers[key]:
			var slot: Vector2i = Vector2i(key, modifier.stat)
			if not slots.has(slot):
				slots.append(slot)
	return slots


func _engine() -> EffectEngine:
	if _engine_ref == null:
		return null
	var engine: EffectEngine = _engine_ref.get_ref()
	return engine


func _drop_cached(key: int) -> void:
	for stat: int in range(Modifier.NO_STAT, _STAT_SLOTS - 1):
		_cache.erase(_slot(key, stat))


static func _slot(key: int, stat: int) -> int:
	return key * _STAT_SLOTS + stat + 1
