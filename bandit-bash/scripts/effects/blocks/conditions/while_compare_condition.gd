# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     while_compare_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name WhileCompareCondition
extends EffectCondition
## Passes while one of this unit's numbers is higher or lower than its opponent's, or than a fixed
## threshold: "while this unit's Attack Speed is higher than its opponent's", "while below half HP".
##
## Comparisons are [b]strict[/b]: a tie fails. Checked live at every attack. An opponent
## comparison applies only from Before Combat to After Combat.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## What is compared. Saved as an int: [b]append only[/b].
enum Quantity {
	## The value key in [member key], such as Attack Speed or Parry.
	VALUE = 0,
	## Current HP.
	CURRENT_HP = 1,
	## Current HP as a percent of maximum HP.
	HP_PERCENT = 2,
	## Current Block.
	BLOCK = 3,
	## Current Stance.
	STANCE = 4,
}

## The direction of the comparison. Saved as an int: [b]append only[/b].
enum Comparison {
	## Strictly higher.
	HIGHER_THAN = 0,
	## Strictly lower.
	LOWER_THAN = 1,
}

## What this unit's number is compared with. Saved as an int: [b]append only[/b].
enum Against {
	## The same number on the opponent in the current exchange.
	OPPONENT = 0,
	## [member threshold].
	THRESHOLD = 1,
}

## What is compared.
@export var quantity: Quantity = Quantity.VALUE

## The value key compared when [member quantity] is [constant VALUE]; ignored otherwise.
@export var key: int = 0

## The direction of the comparison.
@export var comparison: Comparison = Comparison.HIGHER_THAN

## What this unit's number is compared with.
@export var against: Against = Against.OPPONENT

## The number compared with when [member against] is [constant THRESHOLD], in the quantity's own
## units ([constant HP_PERCENT]: 50 is half HP). Ignored otherwise.
@export var threshold: float = 0.0


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "key":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = EffectDefinition.value_key_hint()


func describe() -> String:
	var quantity_name: String = _quantity_name()
	var direction: String = "higher" if comparison == Comparison.HIGHER_THAN else "lower"
	var other: String = "its opponent's"
	if against == Against.THRESHOLD:
		other = EffectDefinition.format_number(threshold)
	return "while this unit's %s is %s than %s" % [quantity_name, direction, other]


func test(ctx: EffectContext) -> bool:
	if not ctx.engine.state.has_unit(ctx.subject_id):
		return false
	var other: float = threshold
	if against == Against.OPPONENT:
		var opponent: String = ctx.opponent_of(ctx.subject_id)
		if not ctx.engine.state.has_unit(opponent):
			return false
		other = _quantity_of(ctx, opponent)
	var mine: float = _quantity_of(ctx, ctx.subject_id)
	return mine > other if comparison == Comparison.HIGHER_THAN else mine < other


func _quantity_name() -> String:
	match quantity:
		Quantity.VALUE:
			return EffectDefinition.key_name(key)
		Quantity.CURRENT_HP:
			return "HP"
		Quantity.HP_PERCENT:
			return "HP %"
		Quantity.BLOCK:
			return "Block"
		Quantity.STANCE:
			return "Stance"
	return "value"


# The quantity of unit_id, exact. A value key is read through the engine with ctx, so the
# comparison is checked live at each attack.
func _quantity_of(ctx: EffectContext, unit_id: String) -> float:
	var state: SandboxState = ctx.engine.state
	match quantity:
		Quantity.VALUE:
			return ctx.engine.stats(unit_id).get_value(key, ctx)
		Quantity.CURRENT_HP:
			return state.get_hp(unit_id)
		Quantity.HP_PERCENT:
			var max_hp: float = ctx.engine.stats(unit_id).get_value(CombatValue.Key.HP)
			return 0.0 if max_hp <= 0.0 else state.get_hp(unit_id) * 100.0 / max_hp
		Quantity.BLOCK:
			return state.get_block(unit_id)
		Quantity.STANCE:
			return state.get_stance(unit_id)
	return 0.0
