# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     percent_of_fact.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name PercentOfFact
extends ValueSource
## A percent of the triggering fact's amount: "100% of that overheal" (Overflowing Cup).
##
## Reads [member CombatFact.amount] and its HP part; the overheal is the amount minus the HP part.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The part of the fact read. Saved as an int: [b]append only[/b].
enum Field {
	## The whole amount: damage, healing or Block.
	AMOUNT = 0,
	## The part that reached HP.
	HP_AMOUNT = 1,
	## Healing beyond maximum HP.
	OVERHEAL = 2,
}

## Effect-text names of the fields.
const FIELD_TEXT: Dictionary[int, String] = {
	Field.AMOUNT: "amount",
	Field.HP_AMOUNT: "HP amount",
	Field.OVERHEAL: "overheal",
}

## The part of the fact read.
@export var field: Field = Field.AMOUNT

## The share taken. [b]Units:[/b] percent. [b]100:[/b] all of it. [b]0:[/b] nothing.
@export_range(0.0, 1000.0, 1.0) var percent: float = 100.0


func describe() -> String:
	return "%s%% of that %s" % [EffectDefinition.format_number(percent), FIELD_TEXT[field]]
