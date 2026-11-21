# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: November 20, 2026
# ==============================================================================

@tool
class_name RuneDefinition
extends EffectCarrierDefinition
## A rune: a single-use ability in its own slots, cast on the player turn outside the action
## economy, on anything anywhere on the map (game-vision.md, Run-wide resources; items.md, Runes).
##
## Lives in [code]res://data/runes/[/code]. [member target_kind], [member target_side] and
## [member needs_unacted_target] say what it may be cast on ([method RuneResolver.target_reason]);
## its [member EffectCarrierDefinition.effects] are what it does on a unit. Combat finds a cast
## rune's definition by its effect ([method RuneResolver.definition_of]), so every rune carries
## one: Recall's and Spark's hold only their wording, in a [CustomOperation], and the resolver or
## the map does the work. Its text ([method describe]) names who it is cast on
## ([method target_noun]). Runes cost a flat price ([constant Prices.RUNE_PRICE]).
##
## @tutorial(Items, Runes): docs/design/items.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## Who a player-side [code]unit[/code] rune is cast on, in its text and the target picker.
const ALLY_NOUN: String = "an ally"

## Who an enemy-side [code]unit[/code] rune is cast on.
const ENEMY_NOUN: String = "an enemy"

## Added to the noun of a rune with [member needs_unacted_target] (Haste).
const UNACTED_TEXT: String = " that hasn't acted"

## Who a [code]pair[/code] rune (Recall) is cast on.
const PAIR_NOUN: String = "two of your units"

## What an [code]object[/code] rune is cast on: the powder keg, the only object a rune acts on
## ([method MapObjects.operate]).
const OBJECT_NOUN: String = "a powder keg"

## How it is aimed, from [constant ContentIds.RUNE_TARGET_KINDS]. [b]unit:[/b] one unit; its
## effects act on it. [b]pair:[/b] two of the caster's own units swap tiles (Recall).
## [b]object:[/b] the map object on a tile the player picks (Spark). Empty is a content error.
@export var target_kind: String = ""

## Which side a [code]unit[/code] rune's unit is on, from [constant ContentIds.RUNE_TARGET_SIDES]:
## [b]player[/b] (the caster's units or a teammate's) or [b]enemy[/b]. Ignored by the other kinds;
## empty on a [code]unit[/code] rune is a content error.
@export var target_side: String = ""

## Whether a [code]unit[/code] rune's unit must not have acted this turn (Haste). Moving without
## acting doesn't count as acting. [b]Off:[/b] any unit of [member target_side].
@export var needs_unacted_target: bool = false


func _validate_property(property: Dictionary) -> void:
	match property["name"]:
		"target_kind":
			ContentIds.apply_hint(property, ContentIds.RUNE_TARGET_KINDS)
		"target_side":
			ContentIds.apply_hint(property, ContentIds.RUNE_TARGET_SIDES)


## Who or what the rune is cast on, from its kind, side and [member needs_unacted_target]:
## [code]an ally[/code], [code]an enemy[/code], [code]an ally that hasn't acted[/code],
## [code]two of your units[/code], [code]a powder keg[/code]. Empty for an unknown kind.
func target_noun() -> String:
	match target_kind:
		ContentIds.RUNE_UNIT:
			var is_enemy: bool = target_side == ContentIds.RUNE_SIDE_ENEMY
			var noun: String = ENEMY_NOUN if is_enemy else ALLY_NOUN
			return noun + UNACTED_TEXT if needs_unacted_target else noun
		ContentIds.RUNE_PAIR:
			return PAIR_NOUN
		ContentIds.RUNE_OBJECT:
			return OBJECT_NOUN
	return ""


## The text of every effect, one sentence each, read as the cast: the command's target named by
## [method target_noun] ("Heal an ally for 10 HP."),
## and timed modifiers that last alike joined under one duration ("+20 Hit and +2 Attack on its
## next attack until Phase End"). Only runes read this way; other carriers' text is
## [method EffectDefinition.describe]'s. An effect with a trigger, conditions or charges keeps
## its own text, with the target named.
func describe() -> PackedStringArray:
	var texts: PackedStringArray = []
	for effect: EffectDefinition in effects:
		if effect != null:
			texts.append(_describe_cast(effect))
	return texts


# One effect's text as the cast reads it (see describe()).
func _describe_cast(effect: EffectDefinition) -> String:
	var is_plain: bool = (
			effect.trigger == EffectTerms.Trigger.ALWAYS
			and effect.conditions.is_empty()
			and effect.charges == 0
	)
	if not is_plain:
		return _name_target(effect.describe())
	var actions: PackedStringArray = []
	var i: int = 0
	var operations: Array[EffectOperation] = effect.operations
	while i < operations.size():
		var operation: EffectOperation = operations[i]
		if operation == null:
			i += 1
			continue
		var run: Array[AddTimedModifier] = _joinable_run(operations, i)
		if run.size() > 1:
			actions.append(_describe_joined(run))
			i += run.size()
			continue
		actions.append(operation.describe_for_trigger(effect.trigger))
		i += 1
	return EffectTerms.sentence(_name_target(EffectTerms.join_list(actions)))


# Where the target's own words, the first time, become target_noun() and later ones "it".
func _name_target(text: String) -> String:
	var noun: String = target_noun()
	if noun.is_empty():
		return text
	var placeholder: String = CommandTarget.new().describe()
	var at: int = text.find(placeholder)
	if at < 0:
		return text
	var rest: String = text.substr(at + placeholder.length()).replace(placeholder, "it")
	return text.left(at) + noun + rest


# The AddTimedModifiers from operations[start] on that give the same target an added value with
# the same end and uses, so one "give X A and B <duration>" says them all; fewer than two: none.
static func _joinable_run(
		operations: Array[EffectOperation], start: int
) -> Array[AddTimedModifier]:
	var run: Array[AddTimedModifier] = []
	var first: AddTimedModifier = operations[start] as AddTimedModifier
	if first == null or not _is_joinable(first):
		return run
	run.append(first)
	for j: int in range(start + 1, operations.size()):
		var next: AddTimedModifier = operations[j] as AddTimedModifier
		if (
				next == null
				or not _is_joinable(next)
				or next.end != first.end
				or next.uses != first.uses
				or next.target.describe() != first.target.describe()
		):
			break
		run.append(next)
	return run


# Whether modifier reads "give <who> <change> <duration>" on another unit: an added value, not a
# permission, and not to the owner.
static func _is_joinable(modifier: AddTimedModifier) -> bool:
	return (
			modifier.mode != Modifier.Mode.GRANT
			and modifier.mode != Modifier.Mode.DENY
			and modifier.target != null
			and not modifier.target.is_owner()
	)


# "give <who> <change> and <change> <duration>" for a run _joinable_run() found.
static func _describe_joined(run: Array[AddTimedModifier]) -> String:
	var changes: PackedStringArray = []
	for modifier: AddTimedModifier in run:
		changes.append(EffectTerms.describe_modifier(modifier.key, modifier.mode, modifier.value))
	var joined: String = ", ".join(changes.slice(0, changes.size() - 1))
	joined += " and " + changes[changes.size() - 1]
	return "give %s %s %s" % [run[0].target.describe(), joined, run[0].describe_duration()]
