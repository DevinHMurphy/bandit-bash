# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     detail_gear_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name DetailGearRow
extends HBoxContainer
## One slot in the [UnitDetailPanel]'s gear: its heading (Weapon, Stowed, Equipment, Pouch), the
## item's name, and under it the weapon's profile or the item's effect text (ui-lift.md, Unit
## detail pop-up). Holds no rules: the panel formats the lines.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The name shown when the slot holds nothing.
@export var empty_text: String = "—"

@onready var _heading: Label = %Heading
@onready var _item: Label = %Item
@onready var _detail: Label = %Detail


## Shows [param heading] with [param item_name] and [param detail] under it; an empty name shows
## [member empty_text], an empty detail hides its line.
func show_gear(heading: String, item_name: String, detail: String) -> void:
	_heading.text = heading
	_item.text = item_name if not item_name.is_empty() else empty_text
	_detail.text = detail
	_detail.visible = not detail.is_empty()


## Its lines as shown, for tests: heading, item, detail.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_heading.text, _item.text, _detail.text])
