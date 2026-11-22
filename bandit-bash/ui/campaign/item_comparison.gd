# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_comparison.gd
# Author:
# Created:  November 20, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name ItemComparison
extends GridContainer
## A before/after comparison of the item a purchase replaces and the one bought
## ([method ArmoryModel.comparison_rows]): a column each under their names, one row per number or
## line, the change after the offer's value (+2), in [member better_color] or
## [member worse_color]. An effect row ([member ArmoryModel.Row.is_marked]) shows each side in an
## [EffectText]: keywords coloured, a tooltip on hover, all of them while a focusable ancestor
## holds key or pad focus ([PurchasePanel] has none). Shows only; takes no focus, reads no input.

const EFFECT_TEXT_SCENE: PackedScene = preload("res://ui/common/text/effect_text.tscn")

## The width of each item's column; longer text wraps within it.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by the text alone, never wrapping.
@export var value_width: float = 200.0

## The width of the row labels' column, which never wraps.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by the longest label.
@export var label_width: float = 80.0

## The offer's value where it is better than the replaced item's: the theme's accent.
@export var better_color: Color = UiTokens.color(UiTokens.ACCENT)

## The offer's value where it is worse than the replaced item's: the theme's danger.
@export var worse_color: Color = UiTokens.color(UiTokens.DANGER)

## Each row as shown, label then before then after, in plain words (an effect row's keyword tags
## removed), for tests: rebuilt by [method show_comparison].
var shown: Array[PackedStringArray] = []


## Shows [param rows] under [param before_name] (the replaced item, [constant ArmoryModel.NONE]
## for an empty slot) and [param after_name] (the offer).
func show_comparison(before_name: String, after_name: String, rows: Array) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	shown.clear()
	columns = 3
	_add("", &"MutedLabel")
	_add(before_name, &"HeaderLabel")
	_add(after_name, &"HeaderLabel")
	for row: ArmoryModel.Row in rows:
		_add(row.label, &"MutedLabel")
		if row.is_marked:
			var before_text: EffectText = _add_effect_text(row.before)
			var after_text: EffectText = _add_effect_text(row.after)
			shown.append(PackedStringArray([
				row.label, before_text.get_plain_text(), after_text.get_plain_text(),
			]))
			continue
		var change: String = row.change_text()
		var after: String = row.after if change.is_empty() else "%s (%s)" % [row.after, change]
		_add(row.before, &"BodyLabel")
		var after_label: Label = _add(after, &"BodyLabel")
		if not change.is_empty():
			after_label.add_theme_color_override(
					&"font_color", better_color if row.is_better() else worse_color
			)
		shown.append(PackedStringArray([row.label, row.before, after]))


# A cell in the next column: the labels' column never wraps; an item's column wraps at
# value_width when that is set.
func _add(text: String, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	var is_label_column: bool = get_child_count() % columns == 0
	if is_label_column:
		label.custom_minimum_size = Vector2(label_width, 0.0)
	elif value_width > 0.0:
		label.custom_minimum_size = Vector2(value_width, 0.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


# An item's cell of effect text, keyword tags in marked_text: wraps at value_width as _add's do,
# or sized by its text alone when that is 0.
func _add_effect_text(marked_text: String) -> EffectText:
	var text: EffectText = EFFECT_TEXT_SCENE.instantiate()
	text.marked_text = marked_text
	if value_width > 0.0:
		text.custom_minimum_size = Vector2(value_width, 0.0)
	else:
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(text)
	return text
