# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_carrier_definition.gd
# Author:
# Created:  October 26, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name EffectCarrierDefinition
extends Resource
## Base for anything that carries effects: heirlooms (curses included), items, unit types, enemy
## classes and runes, each extended in its own plan.
##
## [b]Read-only at runtime:[/b] per-item and per-unit changes (granted effects, stat deltas) live
## on instances, never on the shared .tres.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Content id: snake_case, equal to the file name, unique within its kind. Never shown to players.
@export var id: String = ""

## Name shown to players, such as "Iron Heart".
@export var display_name: String = ""

## The effects this carrier brings. Empty: a carrier with no effects (a plain weapon).
@export var effects: Array[EffectDefinition] = []


## [method describe_marked]'s lines as plain words, their keyword tags removed, for logs, plain
## labels and tests of the words.
func describe() -> PackedStringArray:
	var texts: PackedStringArray = []
	for text: String in describe_marked():
		texts.append(EffectTerms.plain_text(text))
	return texts


## The effect text of every effect, one sentence each, in order, keywords marked for
## [EffectText]; an effect with no text (none of its blocks say anything) gives no line, so a
## card shows no empty one. Carriers with their own wording override this, not [method describe].
func describe_marked() -> PackedStringArray:
	var texts: PackedStringArray = []
	for effect: EffectDefinition in effects:
		if effect == null:
			continue
		var text: String = effect.describe_marked()
		if not text.is_empty():
			texts.append(text)
	return texts
