# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     change_base_stat.gd
# Author:
# Created:  October 26, 2026
# Modified: November 20, 2026
# ==============================================================================

@tool
class_name ChangeBaseStat
extends EffectOperation
## Permanently changes a unit's stat or growth: "permanently gain +1 MGT" (stat boosters), "+5% RES
## growth" (an eaten ingredient), "permanently gain +5 Hit" (a Hit stat booster or ingredient).
##
## Queued. A stat change adds a sourced permanent delta to the unit's instance, never to its type's
## definition; a growth change is kept on the unit's combat state and changes nothing in battle.
## The campaign bridge writes both to the roster at battle end, Hit deltas included.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## What changes. Saved as an int: [b]append only[/b].
enum Mode {
	## The stat itself ([constant CombatFact.Kind.STAT_CHANGED]).
	BASE = 0,
	## The stat's growth, the chance it rises on a level-up
	## ([constant CombatFact.Kind.GROWTH_CHANGED]).
	GROWTH = 1,
}

## Who changes. [b]Null:[/b] the effect's owner.
@export var target: TargetSelector = null

## The stat key changed: a [CombatValue] base stat key, such as [constant CombatValue.MGT], or in
## [constant BASE] mode also [constant CombatValue.HIT] ([constant CombatValue.PERMANENT_KEYS]).
## Hit has no growth.
@export var key: int = 0

## Whether the stat or its growth changes.
@export var mode: Mode = Mode.BASE

## The permanent change. Negative lowers it.[br]
## [b]Units:[/b] the stat's own units in [constant BASE]; percentage points in [constant GROWTH]
## (5 is +5%), rounded half up.
@export var value: float = 0.0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectTerms.value_key_hint()


func describe() -> String:
	return describe_with(describe_change())


## The change alone, with no target: "+1 MGT", "+5% RES growth".
func describe_change() -> String:
	if mode == Mode.GROWTH:
		return "%s%s%% %s growth" % [
			"-" if value < 0.0 else "+",
			EffectTerms.format_number(absf(value)),
			EffectTerms.key_name(key),
		]
	return EffectTerms.describe_modifier(key, Modifier.Mode.ADD, value)


## [param change] given to this operation's target for good: "permanently gain +1 MGT" on the
## owner, "permanently give the target +1 MGT, +1 SPD and +1 DEF" otherwise, so
## [method EffectDefinition.describe_actions] can say several alike changes once.
func describe_with(change: String) -> String:
	if target == null or target.is_owner():
		return "permanently gain %s" % [change]
	return "permanently give %s %s" % [target.describe(), change]


## Changes each target. [constant BASE] adds a permanent delta sourced to the effect
## ([method EffectEngine.add_delta]) and records [constant CombatFact.Kind.STAT_CHANGED];
## [constant GROWTH] goes through [method EffectEngine.add_growth], which records its fact. A key
## that isn't a base stat (or Hit, in [constant BASE]) is a content error, reported in
## diagnostics.
func apply(ctx: EffectContext) -> void:
	var instance: EffectInstance = ctx.instance
	var keys: Dictionary[int, int] = (
			CombatValue.PERMANENT_KEYS if mode == Mode.BASE else CombatValue.STAT_KEYS
	)
	var stat: Variant = keys.find_key(key)
	if stat == null:
		ctx.engine.diagnostics.append("ChangeBaseStat: %s changes key %d, not a %s" % [
			instance.instance_id, key, "base stat or Hit" if mode == Mode.BASE else "base stat",
		])
		return
	var points: int = ValueBreakdown.round_to_int(value, ValueBreakdown.Rounding.HALF_UP)
	for unit_id: String in _targets(target, ctx):
		if mode == Mode.GROWTH:
			ctx.engine.add_growth(unit_id, stat as int, points, instance.instance_id)
			continue
		ctx.engine.add_delta(unit_id, Modifier.new(
				key, Modifier.Mode.ADD, value, instance.source_kind, instance.instance_id,
				instance.label
		))
		var fact: CombatFact = CombatFact.new(CombatFact.Kind.STAT_CHANGED, unit_id)
		fact.amount = points
		fact.key = stat
		fact.source_effect_id = instance.instance_id
		fact.source = CombatFact.Source.EFFECT
		ctx.engine.record(fact)
