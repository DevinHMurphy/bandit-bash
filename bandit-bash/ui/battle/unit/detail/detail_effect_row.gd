# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_effect_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name DetailEffectRow
extends HBoxContainer
## One trait, heirloom or curse in the [UnitDetailPanel]: its name and its effect text, the same
## generated text as everywhere else ([method EffectDefinition.describe_marked], in an
## [EffectText]), with its charges left where it has a limit (ui-lift.md, Unit detail pop-up).
## Holds no rules.[br]
## It is a focus stop the panel steps keys and pads through (the mouse never focuses it), so key
## or pad focus shows its keywords beside it; it draws the theme's focus look
## ([code]Button[/code]'s [code]focus[/code] style) while that focus is on it.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## Added to the text of an effect with limited charges: [code]%d[/code] the charges left.
@export var charges_format: String = " (%d left)"

## Added to the name of one of the army's effects, so a heirloom reads apart from a trait.[br]
## [b]Empty:[/b] heirlooms and traits read alike.
@export var army_suffix: String = " (heirloom)"

@onready var _name: Label = %EffectName
@onready var _text: EffectText = %EffectText


func _ready() -> void:
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	if has_focus(true):
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), Rect2(Vector2.ZERO, size))


## Draws [param line], its keywords coloured; [param is_army] when it is one of the army's
## heirlooms or curses.
func show_effect(line: UnitDetailViewModel.EffectLine, is_army: bool) -> void:
	if line == null:
		return
	_name.text = line.label + (army_suffix if is_army else "")
	var text: String = line.marked_text
	if line.charges_left >= 0:
		text += charges_format % [line.charges_left]
	_text.marked_text = text


## The effect text, for tests of its keywords and tooltips.
func get_effect_text() -> EffectText:
	return _text


## Its lines as shown, for tests: name, text (its words, without keyword tags).
func get_texts() -> PackedStringArray:
	return PackedStringArray([_name.text, _text.get_plain_text()])
