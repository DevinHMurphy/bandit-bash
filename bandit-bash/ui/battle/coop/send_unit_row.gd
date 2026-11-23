# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     send_unit_row.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SendUnitRow
extends Button
## One unit the [SendPanel] offers ([CoopViewModel.SendableUnit]): its name and HP, the map it
## would leave when it stands on another won map than the seat's own, and "Picked" while picked,
## since the theme draws a pressed toggle as a plain button. A toggle: pressed, it is picked for
## the send. Only asks: the panel keeps the picks. Reads no input action itself; the GUI presses
## it on accept and moves focus between rows.

## The row was picked ([param is_picked] true) or dropped.
signal picked(unit_id: String, is_picked: bool)

# ASSUMPTION: the mark's wording; no design doc words it.
## Added to the text while the unit is picked.
@export var picked_text: String = " · Picked"

## The unit shown; empty before [method show_unit].
var unit_id: String = ""

## The won map the unit would go from.
var source_session_id: int = -1

# The text without the picked mark.
var _base_text: String = ""


func _ready() -> void:
	toggle_mode = true
	toggled.connect(_on_toggled)


## Shows [param unit]; [param source_title] names the map it would leave, empty for the seat's
## own (not shown). Picked state is dropped.
func show_unit(unit: CoopViewModel.SendableUnit, source_title: String = "") -> void:
	unit_id = unit.unit_id
	source_session_id = unit.source_session_id
	_base_text = "%s · %d / %d HP" % [unit.name, unit.hp, unit.max_hp]
	if not source_title.is_empty():
		_base_text += " · from %s" % [source_title]
	set_picked(false)


## Sets whether the row is picked, sending no [signal picked].
func set_picked(is_picked: bool) -> void:
	set_pressed_no_signal(is_picked)
	text = _base_text + (picked_text if is_picked else "")


func _on_toggled(is_on: bool) -> void:
	text = _base_text + (picked_text if is_on else "")
	picked.emit(unit_id, is_on)
