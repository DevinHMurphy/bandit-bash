# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_class_definition.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

@tool
class_name EnemyClassDefinition
extends UnitTypeDefinition
## One enemy class: a unit type on the player's rules plus its AI behavior and target rule.
##
## Content data in [code]res://data/enemies/[/code]; read-only at runtime. Its own catalog kind
## ([constant EffectCatalog.Kind.ENEMY_CLASS]), so it never counts as a player unit type. Never a
## commander and no role; its upgrade fields stay empty. A unit of this class at level L has its
## base plus floor(growth % × (L − 1)) in each stat, a source named for the level
## ([method UnitInstance.stat_sources]), and never rolls a level-up. Its weapons and staves never
## run out ([Loadout]); limits on an enemy live on its traits.
##
## @tutorial(Enemy roster): docs/design/enemy-roster.md
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

## How the AI plays the class (enemy-roster.md, Traits, behavior and intent); sets its intent icon.
## Data files store it by number: append new behaviors, never reorder them.
enum Behavior {
	## Goes for the best attack it can reach; otherwise advances on the nearest foe (Brute).
	AGGRESSIVE,
	## Holds its ground or its pack's back line, attacking only foes that come within reach
	## (Duelist, Shieldbearer).
	GUARD,
	## Attacks from where it stands while a foe is in range; moves only if none is (Crossbowman).
	HOLD,
	## Heals or buffs its allies and keeps away from your units (Hedge Healer, Warcaller).
	SUPPORT,
	## Chooses its target by what its curse or charge catches (Hexer, Raider).
	SKIRMISHER,
}

## How the AI plays it, which also sets its intent icon.
@export var behavior: Behavior = Behavior.AGGRESSIVE

## Which target rule its AI follows, from [constant ContentIds.TARGET_RULES], such as
## [code]nearest_foe[/code]. Every enemy class names one; the content test checks it.
@export var target_rule_id: String = ""

## The target rule as players read it beside the intent, such as "Nearest foe it can hit". Every
## enemy class has one; the content test checks it.
@export_multiline var target_rule_text: String = ""


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property["name"] == "target_rule_id":
		ContentIds.apply_hint(property, ContentIds.TARGET_RULES)
