# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     keyword_glossary.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

@tool
class_name KeywordGlossary
extends Resource
## Every keyword effect text marks ([constant EffectTerms.KEYWORDS]), one [KeywordEntry] each:
## what [EffectText] colours a keyword by and what its [KeywordTooltip] says.
##
## One file, [constant PATH]; the content test checks it holds one entry per id in
## [constant EffectTerms.KEYWORD_IDS], each with a name, a colour group and an explanation.
## Read-only at runtime; content data, never saved.
##
## @tutorial(Keywords): docs/design/keywords.md

## The glossary every [EffectText] reads.
const PATH: String = "res://data/keywords/keyword_glossary.tres"

## The entries, in [constant EffectTerms.KEYWORDS] order. Empty: no keyword is coloured.
@export var entries: Array[KeywordEntry] = []


## The entry for keyword [param id]; null when there is none.
func entry(id: String) -> KeywordEntry:
	for found: KeywordEntry in entries:
		if found != null and found.id == id:
			return found
	return null


## The glossary at [constant PATH], loaded once and shared through Godot's resource cache; null,
## with an error, when it doesn't load.
static func shared() -> KeywordGlossary:
	var glossary: KeywordGlossary = load(PATH) as KeywordGlossary
	if glossary == null:
		push_error("KeywordGlossary: the glossary did not load - %s" % [PATH])
	return glossary
