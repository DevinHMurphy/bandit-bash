# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pack_definition.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

@tool
class_name PackDefinition
extends EffectCarrierDefinition
## A pack: the enemy classes a battle fields together and how many of each, such as Field
## Hospital's Hedge Healer, Brute and Shieldbearer (enemy-roster.md, Packs).
##
## Content data in [code]res://data/enemies/packs/[/code]; read-only at runtime. Setup draws a pack
## per encounter and fills the map's enemy slots from [method units]. Every class it names must be
## an [EnemyClassDefinition] and every count at least 1; the content test checks both.
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

## How many units of each enemy class it fields, by the class's content id, in the order setup
## places them.[br]
## [b]Units:[/b] units; at least 1 each.
@export var class_counts: Dictionary[String, int] = {}


## Every unit it fields as its class id, each class repeated by its count, in
## [member class_counts] order. A count below 1 adds nothing.
func units() -> PackedStringArray:
	var listed: PackedStringArray = []
	for class_id: String in class_counts:
		for _i: int in maxi(class_counts[class_id], 0):
			listed.append(class_id)
	return listed
