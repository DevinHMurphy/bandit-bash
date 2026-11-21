# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     consumable_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: November 20, 2026
# ==============================================================================

@tool
class_name ConsumableDefinition
extends ItemDefinition
## A consumable Pouch item: potions, Guard Tonics, the Elixir, the Key, the Lockpick, stat boosters
## and ingredients (items.md, Consumables and Ingredients).
##
## Lives in [code]res://data/items/consumables/[/code]. Using one is the unit's action, on itself
## or an adjacent ally. [member use_kind] says how it is used; its
## [member EffectCarrierDefinition.effects] carry what has no field here, such as a stat booster's
## permanent gain or an eaten ingredient's growth. Uses left live on the item's instance.
##
## @tutorial(Items, Consumables): docs/design/items.md

## The [member use_kind] of an ingredient, which is eaten or cooked (items.md, Ingredients).
const INGREDIENT_USE_KIND: String = "ingredient"

# ASSUMPTION: the wording "When eaten" (P01 question 67; RF-036 says "or similar").
## The lead-in of an ingredient's effect text: it has two uses, so the text names the one its
## effects describe ("When eaten, heal the target for 5 HP and …"); cooking has its own fields.
const EATEN_LEAD_IN: String = "When eaten"

## How it is used, from [constant ContentIds.CONSUMABLE_USE_KINDS].
@export var use_kind: String = ""

## HP healed ([code]heal[/code], and an eaten [code]ingredient[/code]) or Block gained
## ([code]block[/code]). Other use kinds leave it 0.[br]
## [b]Units:[/b] HP or Block.
@export_range(0, 30, 1, "or_greater") var amount: int = 0

## Uses before it is spent or until it refills, by [member uses_lane]. The only count of them: its
## use effect carries no charges of its own, or the content test fails it.[br]
## [b]0:[/b] never used up (the Lockpick).
@export_range(0, 9, 1, "or_greater") var uses: int = 1

## When [member uses] refill. [b]Combat:[/b] at the start of every combat ("1 per map", potions).
## [b]Campaign:[/b] never in a run: spent for good when they run out (the Elixir, the Key).
@export var uses_lane: EffectTerms.Lane = EffectTerms.Lane.COMBAT

@export_group("Cooked")

## What cooking it at a Camp Feast gives every living unit's next level-up, by
## [enum CombatValue.Stat]. Ingredients only. [b]Empty:[/b] no level-up gain.[br]
## [b]Units:[/b] stat points.
@export var cooked_gains: Dictionary[CombatValue.Stat, int] = {}

## Hit every living unit gains at once when it is cooked, since Hit has no growth. Ingredients
## only.[br]
## [b]Units:[/b] Hit percent. [b]0:[/b] none.
@export_range(0, 20, 1, "or_greater") var cooked_hit: int = 0

@export_group("")


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "use_kind":
		ContentIds.apply_hint(property, ContentIds.CONSUMABLE_USE_KINDS)


## The effect text of every effect, one line each, in order: an ingredient's open with
## [constant EATEN_LEAD_IN]; any other consumable's read as its use's action.
func describe() -> PackedStringArray:
	if use_kind != INGREDIENT_USE_KIND:
		return super()
	var texts: PackedStringArray = []
	for effect: EffectDefinition in effects:
		var text: String = "" if effect == null else effect.describe(EATEN_LEAD_IN)
		if not text.is_empty():
			texts.append(text)
	return texts


func _get_kind() -> String:
	return ContentIds.ITEM_CONSUMABLE
