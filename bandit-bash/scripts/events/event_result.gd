# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_result.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventResult
extends RefCounted
## What resolving one event option for one seat did: the facts it recorded and the surprise
## combat it calls for, or why it was refused, which changes nothing.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The seat the option resolved for.
var seat: int = 0

## Why the option was refused. [b]Empty:[/b] it applied.
var rejected_reason: String = ""

## The facts it recorded, in order.
var facts: Array[CampaignFact] = []

## The combat the option starts, which the battle bridge runs. [b]Null:[/b] none.
var surprise_combat: SurpriseCombat = null


## Whether the option was refused.
func is_rejected() -> bool:
	return not rejected_reason.is_empty()


## A surprise combat: a Standard combat at the event node's floor and step, with normal rewards.
class SurpriseCombat:
	extends RefCounted

	## The combat's kind; always Standard.
	var combat_type: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD
	## The event node's floor.
	var floor_number: int = 0
	## The event node's [CampaignGraph] id.
	var node: int = CampaignGraph.NO_NODE

	func _init(at_floor: int = 0, at_node: int = CampaignGraph.NO_NODE) -> void:
		floor_number = at_floor
		node = at_node
