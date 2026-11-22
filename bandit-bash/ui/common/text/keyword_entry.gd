# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     keyword_entry.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

@tool
class_name KeywordEntry
extends Resource
## One keyword's glossary entry ([KeywordGlossary]): its id, the name its tooltip shows, the
## colour group it is drawn in and one plain sentence saying what it does.
##
## The colour is a group, never a colour: each group names a colour of the [code]EffectText[/code]
## theme type ([method colour_item]), so every scene draws a keyword alike and the theme is where
## a hue is retuned. Read-only at runtime; content data, never saved.
##
## @tutorial(Keywords): docs/design/keywords.md

## Which of the UI's colours a keyword takes, by the idea it stands for. Saved in .tres files as an
## int: [b]append only[/b], with explicit values.
enum ColourGroup {
	## Damage and attacking: the UI's red ([code]danger[/code]).
	DANGER = 0,
	## Block, defence and the player side: the UI's blue ([code]block[/code]).
	BLOCK = 1,
	## Healing and HP: the UI's green ([code]heal[/code]).
	HEAL = 2,
	## Gold, shops and every term with no colour of its own: the UI's gold ([code]accent[/code]).
	ACCENT = 3,
	## The darkness: its violet ([code]darkness[/code]).
	DARKNESS = 4,
}

## The theme type whose colours tint keywords ([method colour_item]).
const TEXT_THEME_TYPE: StringName = &"EffectText"

## The [constant TEXT_THEME_TYPE] colour of each group, each a token readable as text on panels.
const COLOUR_ITEMS: Dictionary[int, StringName] = {
	ColourGroup.DANGER: &"keyword_danger",
	ColourGroup.BLOCK: &"keyword_block",
	ColourGroup.HEAL: &"keyword_heal",
	ColourGroup.ACCENT: &"keyword_accent",
	ColourGroup.DARKNESS: &"keyword_darkness",
}

## The keyword's id, as [constant EffectTerms.KEYWORD_IDS] and the text's tags name it: snake_case,
## never changed once content uses it.
@export var id: String = ""

## The name its tooltip shows, such as "Block".
@export var display_name: String = ""

## The colour it is drawn in, in text and in its tooltip's name.
@export var colour_group: ColourGroup = ColourGroup.ACCENT

## What it does, in one plain sentence, under its name in the tooltip.[br]
## [b]Empty:[/b] a content error (the content test fails it).
@export_multiline var explanation: String = ""


## The [constant TEXT_THEME_TYPE] colour item for [param group]; the accent's for an unknown one.
static func colour_item(group: int) -> StringName:
	return COLOUR_ITEMS.get(group, COLOUR_ITEMS[ColourGroup.ACCENT])
