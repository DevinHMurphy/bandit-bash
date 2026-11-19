# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_effect_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name DetailEffectRow
extends HBoxContainer
## One trait, heirloom or curse in the [UnitDetailPanel]: its name and its effect text, the same
## generated text as everywhere else ([method EffectDefinition.describe]), with its charges left
## where it has a limit (ui-lift.md, Unit detail pop-up). Holds no rules.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## Added to the text of an effect with limited charges: [code]%d[/code] the charges left.
@export var charges_format: String = " (%d left)"

# ASSUMPTION: " (heirloom)" marks the army's effects, curses included; no doc words it.
## Added to the name of one of the army's effects, so a heirloom reads apart from a trait.[br]
## [b]Empty:[/b] heirlooms and traits read alike.
@export var army_suffix: String = " (heirloom)"

@onready var _name: Label = %EffectName
@onready var _text: Label = %EffectText


## Draws [param line]; [param is_army] when it is one of the army's heirlooms or curses.
func show_effect(line: UnitDetailViewModel.EffectLine, is_army: bool) -> void:
	if line == null:
		return
	_name.text = line.label + (army_suffix if is_army else "")
	var text: String = line.text
	if line.charges_left >= 0:
		text += charges_format % [line.charges_left]
	_text.text = text


## Its lines as shown, for tests: name, text.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_name.text, _text.text])
