# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_class_definition.gd
# Author:
# Created:  October 30, 2026
# Modified: November 25, 2026
# ==============================================================================

@tool
class_name EnemyClassDefinition
extends UnitTypeDefinition
## One enemy class: a unit type on the player's rules plus its AI behavior, its target rule and,
## for a few, a signature move ([member signature_move]).
##
## Content data in [code]res://data/enemies/[/code]; read-only at runtime. Its own catalog kind
## ([constant EffectCatalog.Kind.ENEMY_CLASS]), so it never counts as a player unit type. Never a
## commander and no role; its upgrade fields stay empty. A mini-boss is a class of its own built on
## a base class ([member base_class_id]), which a key pack names. A unit of this class at level L
## has its base plus floor(growth % × (L − 1)) in each stat, a source named for the level
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
	## (Duelist, Stonelet).
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

## The equipment every unit of the class carries in its Equipment slot, by content id, such as a
## shield; setup builds it with the weapon ([EnemySetup]). The content test checks it names
## equipment. A non-humanoid carries none: its numbers are its stats (enemy-roster.md).[br]
## [b]Empty:[/b] the Equipment slot stays empty.
@export var starting_equipment_id: String = ""

## Its signature move: the one of its trait [member effects] on a telegraphed cooldown, such as
## the Warcaller's War Horn, which [Intents] shows as a [constant EnemyIntent.Kind.SIGNATURE]
## intent the phase before it fires. Name the same resource as in [member effects]; the content
## test checks it is there. [b]Null:[/b] no signature move, as for most classes.
@export var signature_move: EffectDefinition = null

## Its signature move as players read it in intents and breakdowns, such as "Command"; setup labels
## that one effect with it. [b]Empty:[/b] the trait name, as for the Warcaller, whose trait is its
## War Horn.
@export var signature_name: String = ""

## The class it is an elite of, by content id, such as the Brigand Captain's [code]brute[/code]:
## it carries that class's stats, growths, gear, behavior and trait, plus its own signature move.
## The content test checks they match, except a post holder's behavior. [b]Empty:[/b] a standard
## class.
@export var base_class_id: String = ""

## [b]On:[/b] it holds the tile it starts on, as the Powder Baron holds the throne: it acts only
## from there, never moves, and keeps its behavior after the darkness arrives (the-darkness.md,
## Arrival). [b]Off:[/b] it moves as its behavior says, as every other class does.
@export var holds_post: bool = false


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property["name"] == "target_rule_id":
		ContentIds.apply_hint(property, ContentIds.TARGET_RULES)
