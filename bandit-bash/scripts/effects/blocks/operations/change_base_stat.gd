# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     change_base_stat.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name ChangeBaseStat
extends EffectOperation
## Permanently changes a unit's stat: "permanently +1 Might" (stat boosters).
##
## Queued. Adds a sourced permanent delta to the unit's instance, never to its type's definition;
## the campaign bridge writes it to the roster at battle end.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Who changes. [b]Null:[/b] the effect's owner.
@export var target: TargetSelector = null

## The stat key changed: a [CombatValue] base stat key, such as [constant CombatValue.MGT].
@export var key: int = 0

## The permanent change, in the stat's own units. Negative lowers it.
@export var value: float = 0.0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.value_key_hint()


func describe() -> String:
	var change: String = EffectDefinition.describe_modifier(key, Modifier.Mode.ADD, value)
	if target == null or target.is_owner():
		return "permanently %s" % [change]
	return "permanently give %s %s" % [target.describe(), change]


## Adds the change to each target as a permanent delta sourced to the effect
## ([method EffectEngine.add_delta]) and records [constant CombatFact.Kind.STAT_CHANGED]. A key
## that isn't a base stat is a content error, reported in diagnostics.
func apply(ctx: EffectContext) -> void:
	var instance: EffectInstance = ctx.instance
	var stat: Variant = CombatValue.STAT_KEYS.find_key(key)
	if stat == null:
		ctx.engine.diagnostics.append(
				"ChangeBaseStat: %s changes key %d, not a base stat" % [instance.instance_id, key]
		)
		return
	for unit_id: String in _targets(target, ctx):
		ctx.engine.add_delta(unit_id, Modifier.new(
				key, Modifier.Mode.ADD, value, instance.source_kind, instance.instance_id,
				instance.label
		))
		var fact: CombatFact = CombatFact.new(CombatFact.Kind.STAT_CHANGED, unit_id)
		fact.amount = ValueBreakdown.round_to_int(value, ValueBreakdown.Rounding.HALF_UP)
		fact.key = stat
		fact.source_effect_id = instance.instance_id
		fact.source = CombatFact.Source.EFFECT
		ctx.engine.record(fact)
