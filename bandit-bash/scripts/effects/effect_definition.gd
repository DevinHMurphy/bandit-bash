# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_definition.gd
# Author:
# Created:  October 26, 2026
# Modified: November 20, 2026
# ==============================================================================

@tool
class_name EffectDefinition
extends Resource
## One effect: a trigger, a scope, conditions and operations, authored in the inspector.
##
## Items, traits, heirlooms, curses and runes all carry their effects as these
## ([EffectCarrierDefinition]). [b]Read-only at runtime:[/b] Godot shares a loaded .tres, so
## counters, charges and owners live on the effect's runtime instance, never here.[br]
## [method describe] generates the effect text as a sentence in the effect-triggers.md grammar,
## "<head>, <conditions>, <operations>.", the head naming the scope as the trigger's subject
## ([method EffectTerms.trigger_head]), so text and behavior can't drift.
## Its enums, their text and the text helpers blocks share live in
## [EffectTerms], a leaf: blocks must never name this class (see there for why).
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Bits of [member tags].
enum Tag {
	## Once any player owns it, it is never offered to anyone else (co-op).
	UNIQUE = 1,
	## A negative heirloom. Curses resolve last among reactions, unless [member resolves_first].
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

## Resolves before every other reaction to the same fact, before the curses-last rule too, so its
## result is in place when the others resolve (Haunted's Block ban before Phase Start's Block
## gains). Two such effects keep the usual order between them. [b]Off:[/b] the usual reaction
## order ([EffectEngine]).
@export var resolves_first: bool = false

## What the effect adds to an item's price when an event grants it to that item
## ([method Prices.item_value]): "Hit dealt: heal 2" is 1. Read only for granted effects.[br]
## [b]Units:[/b] points on the prefix scale (1 point = 1 Might = 10 Hit). [b]0:[/b] adds nothing;
## negative lowers the price, never below the unmodified price.
@export var item_points: float = 0.0


# ASSUMPTION: the override replaces the whole built text, lead-in and charges included (P01
# question 65).
## Player-facing text [method describe] shows in place of the text built from the blocks, for an
## effect the blocks can't say: an opener (Burglar's Roll, the Key) has no operations, since
## [MapObjects] reads it by id. One or more whole sentences, punctuation included.[br]
## [b]Empty:[/b] the built text.
@export_multiline var written_text: String = ""


## The effect text as a sentence: [member written_text] when set, else built from the blocks
## ("Every 7th time one of your units attacks each combat, that attack gains lifesteal."). An
## always-on effect has no head ("+2 DEF."); a used Pouch item reads as its action ("Heal the
## target for 8 HP."). [param lead_in]: an opening its carrier gives, before the head and
## conditions ("When eaten"); empty for none. The grammar: docs/design/effect-triggers.md.
func describe(lead_in: String = "") -> String:
	if not written_text.is_empty():
		return written_text
	var counter: CounterCondition = null
	var clauses: PackedStringArray = []
	for condition: EffectCondition in conditions:
		if condition == null:
			continue
		if condition is CounterCondition and counter == null:
			counter = condition
		else:
			clauses.append(condition.describe())

	var count: String = ""
	var lane: EffectTerms.Lane = EffectTerms.Lane.COMBAT
	if counter != null:
		lane = counter.lane
		if counter.mode == CounterCondition.Mode.FIRST:
			count = EffectTerms.FIRST_COUNT
		elif counter.count > 1:
			count = EffectTerms.ordinal(counter.count)
	var opening: PackedStringArray = []
	for phrase: String in [lead_in, EffectTerms.trigger_head(trigger, scope, count, lane)]:
		if not phrase.is_empty():
			opening.append(phrase)
	opening.append_array(clauses)

	var text: String = describe_actions()
	if not opening.is_empty():
		text = ", ".join(opening) if text.is_empty() else "%s, %s" % [", ".join(opening), text]
	if charges > 0:
		text = "%s %s" % [text, EffectTerms.describe_charges(charges, charge_lane)]
	return EffectTerms.sentence(text)


## What the operations do, as one list with no head: "heal the target for 10 HP and permanently
## give the target +10% MGT growth". A range pair reads as one "Range becomes 1-2", and permanent
## changes given alike share one "permanently give the target +1 MGT, +1 SPD and +1 DEF".
func describe_actions() -> String:
	var actions: PackedStringArray = []
	var i: int = 0
	while i < operations.size():
		var operation: EffectOperation = operations[i]
		if i + 1 < operations.size() and _is_range_pair(operation, operations[i + 1]):
			var low: ModifyValue = operation
			var high: ModifyValue = operations[i + 1]
			actions.append(EffectTerms.describe_range_base(low.value, high.value))
			i += 2
			continue
		var run: Array[ChangeBaseStat] = _permanent_run(i)
		if run.size() > 1:
			var changes: PackedStringArray = []
			for change: ChangeBaseStat in run:
				changes.append(change.describe_change())
			actions.append(run[0].describe_with(EffectTerms.join_list(changes)))
			i += run.size()
			continue
		if operation != null:
			actions.append(operation.describe_for_trigger(trigger))
		i += 1
	return EffectTerms.join_list(actions)


## Whether [member tags] includes [param tag].
func has_tag(tag: Tag) -> bool:
	return tags & tag != 0


# The ChangeBaseStats from operations[start] on that change the same target's stats (not
# growths), so one "permanently give <who> A, B and C" says them all; fewer than two: none.
func _permanent_run(start: int) -> Array[ChangeBaseStat]:
	var run: Array[ChangeBaseStat] = []
	var first: ChangeBaseStat = operations[start] as ChangeBaseStat
	if first == null or first.mode != ChangeBaseStat.Mode.BASE:
		return run
	run.append(first)
	for j: int in range(start + 1, operations.size()):
		var next: ChangeBaseStat = operations[j] as ChangeBaseStat
		if (
				next == null
				or next.mode != first.mode
				or next.describe_with("") != first.describe_with("")
		):
			break
		run.append(next)
	return run


# Whether low then high set a unit's whole range in place of its weapon's (the Short Quiver): one
# "Range becomes 1-2" reads better than a clause per end.
static func _is_range_pair(low: EffectOperation, high: EffectOperation) -> bool:
	var first: ModifyValue = low as ModifyValue
	var second: ModifyValue = high as ModifyValue
	if first == null or second == null or first.per != null or second.per != null:
		return false
	return (
			first.key == CombatValue.Key.RANGE_MIN and second.key == CombatValue.Key.RANGE_MAX
			and first.mode == Modifier.Mode.REPLACE_BASE
			and second.mode == Modifier.Mode.REPLACE_BASE
	)

