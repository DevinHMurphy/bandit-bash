# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_option.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

@tool
class_name EventOption
extends Resource
## One choice of an event: its text, what it needs, its outcome blocks, and its curse, named or
## drawn from a tier (events.md).
##
## Data only: [EventResolver] applies its blocks in order, then its curse. Every block that asks
## the player to pick something asks for the same kind of pick ([method chooser]), so one unit
## chosen for "+2 MGT and -4 max HP" takes both. A curse is always named before the player
## chooses: a tier's curse is drawn into [member EventRolls.curse_id] when the event is made.
##
## @tutorial(Events): docs/design/events.md

## The option's name on its button, such as "Drink Deep".
@export var title: String = ""

## What it does, as the event screen shows it.
@export_multiline var text: String = ""

## What the seat must meet to choose it. [b]Null:[/b] nothing.
@export var requirements: EventRequirements = null

## Its outcome blocks, applied in order. [b]Empty:[/b] nothing happens ("Walk Away").
@export var outcomes: Array[EventOutcome] = []

## Content id of the [CurseDefinition] it gives, even one already held (a repeat adds a copy).
## [b]Empty:[/b] none, or one from [member curse_tier].
@export var curse_id: String = ""

## The curse tier it draws a curse from, from [constant ContentIds.CURSE_TIERS], when
## [member curse_id] is empty. [b]Empty:[/b] no curse.
@export var curse_tier: String = ""


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "curse_tier":
		ContentIds.apply_hint(property, ContentIds.CURSE_TIERS)


## What the player picks after choosing it: the first block's pick that isn't
## [constant EventOutcome.Chooser.NONE], or none.
func chooser() -> EventOutcome.Chooser:
	for outcome: EventOutcome in outcomes:
		if outcome != null and outcome.chooser() != EventOutcome.Chooser.NONE:
			return outcome.chooser()
	return EventOutcome.Chooser.NONE


## Whether it gives a curse, named or from a tier.
func has_curse() -> bool:
	return not curse_id.is_empty() or not curse_tier.is_empty()


## What is wrong with this option as data, one line each: a missing block, blocks asking for
## different picks, or an unknown curse tier. Empty when it is sound.
func problems() -> PackedStringArray:
	var found: PackedStringArray = []
	var wanted: EventOutcome.Chooser = chooser()
	for index: int in outcomes.size():
		var outcome: EventOutcome = outcomes[index]
		if outcome == null:
			found.append("\"%s\": block %d is missing" % [title, index])
		elif outcome.chooser() != EventOutcome.Chooser.NONE and outcome.chooser() != wanted:
			found.append("\"%s\": block %d asks for a different pick" % [title, index])
	if not curse_tier.is_empty() and not ContentIds.CURSE_TIERS.has(curse_tier):
		found.append("\"%s\": curse tier \"%s\" is unknown" % [title, curse_tier])
	return found
