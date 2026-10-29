# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_definition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name EffectDefinition
extends Resource
## One effect: a trigger, a scope, conditions and operations, authored in the inspector.
##
## Items, traits, heirlooms, curses and runes all carry their effects as these
## ([EffectCarrierDefinition]). [b]Read-only at runtime:[/b] Godot shares a loaded .tres, so
## counters, charges and owners live on the effect's runtime instance, never here.[br]
## [method describe] generates the effect text in the effect-triggers.md grammar,
## "[Every Nth] <trigger> by <scope> [this combat | this campaign]: <operation>", so text and
## behavior can't drift. Its enums, their text and the text helpers blocks share live in
## [EffectTerms], a leaf: blocks must never name this class (see there for why).
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Bits of [member tags].
enum Tag {
	## Once any player owns it, it is never offered to anyone else (co-op).
	UNIQUE = 1,
	## A negative heirloom. Curses resolve last among reactions.
	CURSE = 2,
}

## Content id: snake_case, equal to the file name, unique among effects. Never shown to players.
@export var id: String = ""

## When the effect is checked. [b]Always:[/b] an always-on effect; its operations are modifiers.
@export var trigger: EffectTerms.Trigger = EffectTerms.Trigger.ALWAYS

## Whose events count, relative to the owner. Heirlooms never use This unit.
@export var scope: EffectTerms.Scope = EffectTerms.Scope.THIS_UNIT

## Tests that must all pass for the operations to run. A [CounterCondition] supplies the
## "Every Nth" and lane words of the text. Empty: always passes.
@export var conditions: Array[EffectCondition] = []

## What the effect does, in order. Empty is a content error.
@export var operations: Array[EffectOperation] = []

@export_group("Charges")

## Uses before the effect stops working, spent once per activation (potions, staff uses).
##
## [b]0:[/b] no limit. Refilled at the start of [member charge_lane]'s period.
@export_range(0, 99) var charges: int = 0

## When [member charges] refill: every battle (per map) or once per run.
@export var charge_lane: EffectTerms.Lane = EffectTerms.Lane.COMBAT

@export_group("")

## Content tags. [b]Unique:[/b] never offered to a second player in co-op. [b]Curse:[/b] a negative
## heirloom that resolves last. [b]0:[/b] no tags.
@export_flags("Unique:1", "Curse:2") var tags: int = 0


## The effect text, generated from the data, such as
## [code]Every 7th Attack made by Your Unit this combat: that attack gains lifesteal[/code].
func describe() -> String:
	var counter: CounterCondition = null
	var clauses: PackedStringArray = []
	for condition: EffectCondition in conditions:
		if condition == null:
			continue
		if condition is CounterCondition and counter == null:
			counter = condition
		else:
			clauses.append(condition.describe())

	var head: String = ""
	if trigger != EffectTerms.Trigger.ALWAYS:
		head = EffectTerms.TRIGGER_TEXT.get(trigger, "Trigger %d" % [trigger])
		if scope != EffectTerms.Scope.THIS_UNIT:
			head += " by %s" % [EffectTerms.SCOPE_TEXT[scope]]
	if counter != null:
		head = ("%s %s" % [counter.describe_count(), head]).strip_edges()
		head += " %s" % [EffectTerms.LANE_TEXT[counter.lane]]
	if head.is_empty() and clauses.is_empty():
		head = EffectTerms.TRIGGER_TEXT[EffectTerms.Trigger.ALWAYS]

	var opening: PackedStringArray = []
	if not head.is_empty():
		opening.append(head)
	opening.append_array(clauses)
	var actions: PackedStringArray = []
	for operation: EffectOperation in operations:
		if operation != null:
			actions.append(operation.describe_for_trigger(trigger))

	var text: String = "%s: %s" % [", ".join(opening), ", ".join(actions)]
	if charges > 0:
		var uses: String = "use" if charges == 1 else "uses"
		text += " (%d %s %s)" % [charges, uses, EffectTerms.LANE_TEXT[charge_lane]]
	return text.left(1).to_upper() + text.substr(1)


## Whether [member tags] includes [param tag].
func has_tag(tag: Tag) -> bool:
	return tags & tag != 0

