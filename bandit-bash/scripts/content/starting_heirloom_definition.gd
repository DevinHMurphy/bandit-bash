# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_heirloom_definition.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

@tool
class_name StartingHeirloomDefinition
extends HeirloomDefinition
## A starting heirloom (heirlooms.md, Starting heirlooms): offered only at run start, 1 of 3 drawn
## from the pool of 7. Its lasting part is ordinary [member EffectCarrierDefinition.effects]
## (Abundance's +1 max army size, Tactician's Manual's triangle); its one-time [member bonus] is
## data the run start's rules read ([StartingOffer]), since no effect block grants a recruit, a
## weapon pick or an upgrade. [method describe] adds the bonus's line, so every heirloom view
## shows it. Lives in [code]res://data/heirlooms/[/code] with tier [code]starting[/code].
##
## @tutorial(Heirlooms, Starting heirlooms): docs/design/heirlooms.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## What it gives once, when taken. Stored as an int in its .tres: [b]append only[/b], with
## explicit values.
enum Bonus {
	## Nothing beyond its effects (Tactician's Manual).
	NONE = 0,
	## Recruit 1 of [member offer_count] offered units into the army (Abundance).
	RECRUIT = 1,
	## Take 1 of [member offer_count] weapons of [member item_rarity] the army can use, placed
	## like any new item (Ancestral Weapon).
	WEAPON = 2,
	## Upgrade one living unit that isn't the commander, as a Camp's Train (Veteran Company).
	UPGRADE = 3,
	## Gain [member gold] gold (War Chest).
	GOLD = 4,
	## Gain a random heirloom of [member heirloom_tier] (Family Relic).
	HEIRLOOM = 5,
	## Recruit 1 of [member offer_count] units in place of a unit that isn't the commander
	## (Mercenary Contract).
	REPLACE = 6,
}

## What it gives once, when taken.
@export var bonus: Bonus = Bonus.NONE

## Gold given by [constant Bonus.GOLD]; ignored otherwise.[br]
## [b]Units:[/b] gold. [b]0:[/b] none.
@export_range(0, 1000, 1, "or_greater") var gold: int = 0

## Units or weapons offered by [constant Bonus.RECRUIT], [constant Bonus.REPLACE] and
## [constant Bonus.WEAPON]; ignored otherwise. Fewer are offered when the pool runs short.[br]
## [b]Units:[/b] offers. [b]0:[/b] none, so the heirloom can't be taken.
@export_range(0, 5) var offer_count: int = 0

## Whether [constant Bonus.RECRUIT] and [constant Bonus.REPLACE] recruits roll a +1 or +2 prefix
## ([method UnitPrefixDefinition.roll_elite]). [b]False:[/b] they have no prefix.
@export var is_prefix_positive: bool = false

## Rarity of the weapons [constant Bonus.WEAPON] offers; ignored otherwise.
@export var item_rarity: ItemDefinition.Rarity = ItemDefinition.Rarity.RARE

## Tier, from [constant ContentIds.HEIRLOOM_TIERS], of the heirloom [constant Bonus.HEIRLOOM]
## draws; ignored otherwise. [b]Empty:[/b] none, so the heirloom can't be taken.
@export var heirloom_tier: String = ""


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property["name"] == "heirloom_tier":
		ContentIds.apply_hint(property, ContentIds.HEIRLOOM_TIERS)


## Its effects' text, then its bonus's line, such as "Run start: gain 100 gold".
func describe() -> PackedStringArray:
	var texts: PackedStringArray = super()
	var line: String = bonus_text()
	if not line.is_empty():
		texts.append(line)
	return texts


## Its bonus as one line of text; empty for [constant Bonus.NONE].
func bonus_text() -> String:
	match bonus:
		Bonus.RECRUIT:
			return "Run start: recruit 1 of %d units %s" % [offer_count, _prefix_text()]
		Bonus.REPLACE:
			return "Run start: recruit 1 of %d units %s, replacing a unit (not the commander)" % [
				offer_count, _prefix_text(),
			]
		Bonus.WEAPON:
			return "Run start: take 1 of %d %s weapons the army can use" % [
				offer_count, (ItemDefinition.Rarity.find_key(item_rarity) as String).capitalize(),
			]
		Bonus.UPGRADE:
			return "Run start: upgrade one unit (not the commander) for free"
		Bonus.GOLD:
			return "Run start: gain %d gold" % [gold]
		Bonus.HEIRLOOM:
			return "Run start: gain a random %s heirloom" % [heirloom_tier.capitalize()]
	return ""


func _prefix_text() -> String:
	return "with a +1 or +2 prefix" if is_prefix_positive else "with no prefix"
