# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_stat_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name DetailStatRow
extends HBoxContainer
## One value in the [UnitDetailPanel]: its short name, its value, every line of its breakdown
## ("7 base +2 Iron Heart", each modifier as +x or -x with its source) and, for a player unit's
## stat, its growth (ui-lift.md, Unit detail pop-up).
##
## Draws a [UnitDetailViewModel.ValueRow]; holds no rules. The lines come from
## [method StatSheet.explain], so they always sum to the value shown.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The growth cell: [code]%d[/code] the growth in percent.
@export var growth_format: String = "%d%%"

## Shown in place of the breakdown when nothing changes the value. [b]Empty:[/b] nothing shows.
@export var no_sources_text: String = ""

var _row: UnitDetailViewModel.ValueRow = null

@onready var _label: Label = %Label
@onready var _value: Label = %Value
@onready var _sources: Label = %Sources
@onready var _growth: Label = %Growth


## Draws [param row].
func show_row(row: UnitDetailViewModel.ValueRow) -> void:
	_row = row
	if row == null:
		return
	_label.text = row.label
	_value.text = "%d" % [row.value]
	_sources.text = " ".join(row.sources) if not row.sources.is_empty() else no_sources_text
	_growth.text = growth_format % [row.growth] if row.growth >= 0 else ""
	_growth.visible = row.growth >= 0


## The row shown; null before [method show_row].
func get_row() -> UnitDetailViewModel.ValueRow:
	return _row


## Its cells as shown, for tests: name, value, sources, growth.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_label.text, _value.text, _sources.text, _growth.text])
