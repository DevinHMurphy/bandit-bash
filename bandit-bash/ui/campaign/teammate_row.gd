# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     teammate_row.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name TeammateRow
extends VBoxContainer
## One teammate in the [TeamPanel]: a button naming them with their gold and army size, their
## [HeirloomBar] under it as the run saved it, and a note (none held, or what the screen adds,
## such as their Camp choice). Reading only: it changes nothing in the run.
##
## Keys and pads read the heirlooms by pressing the button, which moves focus onto the bar's
## icons (each showing its tooltip); Back gives the focus back to the button. The mouse hovers
## the icons at any time.

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions):
#   "ui_accept"            -> Enter, Space; pad A [Cross]   (on the button, read through the GUI:
#                             focus onto the heirlooms)
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick     (on the heirlooms, through the GUI:
#                             between icons, wrapping)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (read in _input while the
#                             heirlooms have focus: back to the button, before the panel closes)
#   Mouse: a click on the button; hovering an icon shows its tooltip.
# ============================================================

## Focus moved onto the teammate's heirlooms.
signal heirlooms_opened()

## Focus left the teammate's heirlooms, back to the button.
signal heirlooms_closed()

## The button's least size, so names, gold and army line up across rows.[br]
## [b]Units:[/b] base units. [b](0, 0):[/b] as large as its text.
@export var button_size: Vector2 = Vector2(420.0, 36.0):
	set(value):
		button_size = value
		if not is_node_ready():
			return
		_name_button.custom_minimum_size = button_size

## The seat shown; [constant CampaignData.HOST_SEAT] until [method show_seat].
var shown_seat: int = CampaignData.HOST_SEAT

@onready var _name_button: Button = %NameButton
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _note_label: Label = %Note


func _ready() -> void:
	_name_button.custom_minimum_size = button_size
	_name_button.pressed.connect(_on_name_button_pressed)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)


func _input(event: InputEvent) -> void:
	if not _heirlooms.is_navigable() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_heirlooms.close_focus()


## Shows seat [param teammate] of [param run]: its name, gold, army against its max (read through
## [param catalog]) and heirlooms, and [param note] under them; with no note and no heirlooms,
## says it holds none.
func show_seat(
		run: CampaignRunState, teammate: int, catalog: EffectCatalog.Index, note: String = ""
) -> void:
	shown_seat = teammate
	var seat_run: SeatRun = run.seat_run(teammate)
	if seat_run == null:
		var none: Array[HeirloomViewModel] = []
		_name_button.text = CampaignLink.seat_name(teammate)
		_heirlooms.show_views(none)
		_note_label.text = "Not in this run."
		_note_label.visible = true
		return
	_name_button.text = "%s · Gold %d · Army %d / %d" % [
		CampaignLink.seat_name(teammate), seat_run.gold, seat_run.army.size(),
		RunOperations.max_army_size(seat_run, catalog),
	]
	_heirlooms.show_views(HeirloomViewModel.for_run(seat_run))
	var lines: PackedStringArray = []
	if not _heirlooms.has_icons():
		lines.append("No heirlooms yet.")
	if not note.is_empty():
		lines.append(note)
	_note_label.text = " ".join(lines)
	_note_label.visible = not lines.is_empty()


## The button naming the teammate, for the panel's focus and for tests.
func get_name_button() -> Button:
	return _name_button


## The teammate's heirloom bar, for tests.
func get_heirloom_bar() -> HeirloomBar:
	return _heirlooms


## The note's text, for tests.
func get_note_text() -> String:
	return _note_label.text


## Whether keys and pads are on the heirlooms.
func is_reading_heirlooms() -> bool:
	return _heirlooms.is_navigable()


func _on_name_button_pressed() -> void:
	if _heirlooms.open_focus():
		heirlooms_opened.emit()


func _on_heirloom_bar_navigation_ended() -> void:
	heirlooms_closed.emit()
