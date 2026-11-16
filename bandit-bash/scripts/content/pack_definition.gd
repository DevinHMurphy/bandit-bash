# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pack_definition.gd
# Author:
# Created:  October 30, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name PackDefinition
extends EffectCarrierDefinition
## A pack: the enemy classes a battle fields together at each difficulty step, such as Field
## Hospital's Hedge Healer, Brute and Shieldbearer, and the pool setup draws it from.
##
## Content data in [code]res://data/enemies/packs/[/code]; read-only at runtime. Setup step 4
## draws a pack from one pool and fills the map's enemy slots from [method units] at the floor's
## step. A drawn pack fields exactly [constant STEP_SIZES] units at each step; its leader is one of
## those units, its mini-boss is not. The content test checks the sizes, the classes and the roles.
##
## @tutorial(Enemy packs): docs/design/enemy-packs.md

## Which draw a pack belongs to. Saved by number in .tres files: append only.
enum Pool {
	## Drawn for a step's first standard combats ([constant EnemySetup.BASIC_COMBATS_PER_STEP]).
	BASIC = 0,
	## Drawn for a step's later standard combats.
	HARD = 1,
	## A mini-boss's escort, drawn for key combats.
	KEY = 2,
	## Never drawn: kept for tests and fixed maps (the M1 Pack).
	NONE = 3,
}

## The difficulty steps a pack lists units for (game-vision.md, Run structure).
const STEPS: int = 3

## Units a drawn pack fields at each step, step 1 first: the vision's standard combat counts. A
## key pack's escorts number the same, with its mini-boss on top.
const STEP_SIZES: Array[int] = [3, 4, 5]

## The draw it belongs to. [b]NONE:[/b] never drawn.
@export var pool: Pool = Pool.BASIC

## How many units of each enemy class it fields at step 1 (floors 1-5), by class id, in the order
## setup places them.[br]
## [b]Units:[/b] units; at least 1 each.
@export var step_1_counts: Dictionary[String, int] = {}

## As [member step_1_counts], at step 2 (floors 6-11).[br]
## [b]Units:[/b] units; at least 1 each.
@export var step_2_counts: Dictionary[String, int] = {}

## As [member step_1_counts], at step 3 (floors 12-17).[br]
## [b]Units:[/b] units; at least 1 each.
@export var step_3_counts: Dictionary[String, int] = {}

## The enemy class of its leader, an elite of one of its own units (enemy-packs.md, Decisions 9
## and 10): its signature class, fielded at every step. Read by leaders' placement, not by
## setup step 4. [b]Empty:[/b] no leader, as for a key pack.
@export var leader_class_id: String = ""

## The content id of the mini-boss a key pack escorts; its escorts are the pack's units. Read by
## mini-bosses' placement, not by setup step 4. [b]Empty:[/b] none; only a key pack names one.
@export var mini_boss_id: String = ""


## Whether setup ever draws it: every pool but [constant Pool.NONE].
func is_drawn() -> bool:
	return pool != Pool.NONE


## The counts it fields at [param step] (1 to [constant STEPS]), by class id; a step outside them
## reads the nearest one.
func counts_at(step: int) -> Dictionary[String, int]:
	match clampi(step, 1, STEPS):
		1:
			return step_1_counts
		2:
			return step_2_counts
	return step_3_counts


## Every unit it fields at [param step] ([method counts_at]) as its class id, each class repeated
## by its count, in placement order. A count below 1 adds nothing.
func units(step: int) -> PackedStringArray:
	var listed: PackedStringArray = []
	var counts: Dictionary[String, int] = counts_at(step)
	for class_id: String in counts:
		for _i: int in maxi(counts[class_id], 0):
			listed.append(class_id)
	return listed


## Every class it fields at any step, each once, in the order first listed from step 1 up.
func class_ids() -> PackedStringArray:
	var found: PackedStringArray = []
	for step: int in range(1, STEPS + 1):
		for class_id: String in counts_at(step):
			if not found.has(class_id):
				found.append(class_id)
	return found
