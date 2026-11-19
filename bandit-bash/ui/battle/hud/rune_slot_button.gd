# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_slot_button.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RuneSlotButton
extends Control
## One slot of the [RuneBar]: a circle, empty or showing a held rune's icon (its name where it has
## no icon), dimmed while the rune can't be cast, with its Discard button under it, as wide as the
## circle and 32 units tall (the style guide's click floor).
##
## It only reports: a press on the rune ([signal pressed]) or on Discard
## ([signal discard_pressed]), and being pointed at by the mouse or focus ([signal pointed],
## [signal unpointed]). The [BattleController] decides what a press does. Mouse clicks work
## whatever its focus mode; keys and pads reach it only while [method set_navigable] is on. The
## circle and its focus ring are the scene's styles.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The rune was clicked, or accepted while focused.
signal pressed()

## Discard was clicked, or accepted while focused.
signal discard_pressed()

## The mouse entered, or focus moved onto, the rune ([param is_discard] false) or Discard (true).
signal pointed(is_discard: bool)

## The mouse left, or focus left, the part last pointed at.
signal unpointed()

# ASSUMPTION: the circle, its hover and gold focus ring, and the X under it (the theme's RuneSlot
# and RuneDiscardButton styles) are placeholders for the art pass.
## How a held rune that can't be cast now is tinted: its icon or name is multiplied by it.
## Defaults to the style guide's disabled look, white at [constant UiTokens.DISABLED_ALPHA].[br]
## [b]White:[/b] no different from a rune that can be cast. Alpha 0 hides it.
@export var refused_modulate: Color = Color(1.0, 1.0, 1.0, UiTokens.DISABLED_ALPHA)

var _rune: TurnInputModel.HeldRune = null

@onready var _slot: Button = %Slot
@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %Name
@onready var _discard: Button = %Discard


func _ready() -> void:
	_slot.pressed.connect(_on_slot_pressed)
	_discard.pressed.connect(_on_discard_pressed)
	_slot.mouse_entered.connect(_on_part_pointed.bind(false))
	_slot.focus_entered.connect(_on_part_pointed.bind(false))
	_discard.mouse_entered.connect(_on_part_pointed.bind(true))
	_discard.focus_entered.connect(_on_part_pointed.bind(true))
	_slot.mouse_exited.connect(_on_part_unpointed)
	_slot.focus_exited.connect(_on_part_unpointed)
	_discard.mouse_exited.connect(_on_part_unpointed)
	_discard.focus_exited.connect(_on_part_unpointed)
	show_empty()


## Shows [param rune] in the circle: [param icon], else its name; tinted by
## [member refused_modulate] unless [param can_cast]. Discard shows with it.
func show_rune(rune: TurnInputModel.HeldRune, icon: Texture2D, can_cast: bool) -> void:
	_rune = rune
	_icon.texture = icon
	_icon.visible = icon != null
	_name.text = rune.label
	_name.visible = icon == null
	var tint: Color = Color.WHITE if can_cast else refused_modulate
	_icon.modulate = tint
	_name.modulate = tint
	_slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_discard.visible = true


## Shows the empty circle: no icon, no name, no Discard, and nothing to press.
func show_empty() -> void:
	_rune = null
	_icon.texture = null
	_icon.visible = false
	_name.text = ""
	_name.visible = false
	_slot.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_discard.visible = false
	set_navigable(false)


## The rune shown; null while empty.
func get_rune() -> TurnInputModel.HeldRune:
	return _rune


## Whether the slot is empty.
func is_empty() -> bool:
	return _rune == null


## The icon shown; null while empty or showing the rune's name.
func get_icon() -> Texture2D:
	return _icon.texture


## Whether the rune shows tinted by [member refused_modulate], as one that can't be cast now.
func is_dimmed() -> bool:
	return _rune != null and _icon.modulate == refused_modulate


## Lets keys and pads focus the rune and its Discard ([param is_navigable] true), or neither. An
## empty slot is never navigable. Turning it off drops a focus held inside.
func set_navigable(is_navigable: bool) -> void:
	var mode: Control.FocusMode = Control.FOCUS_NONE
	if is_navigable and _rune != null:
		mode = Control.FOCUS_ALL
	_slot.focus_mode = mode
	_discard.focus_mode = mode
	if mode == Control.FOCUS_NONE and (_slot.has_focus() or _discard.has_focus()):
		get_viewport().gui_release_focus()


## The circle's button, for tests that press it and for the bar's focus links.
func get_slot_button() -> Button:
	return _slot


## The Discard button, for tests that press it and for the bar's focus links.
func get_discard_button() -> Button:
	return _discard


func _on_slot_pressed() -> void:
	if _rune != null:
		pressed.emit()


func _on_discard_pressed() -> void:
	if _rune != null:
		discard_pressed.emit()


func _on_part_pointed(is_discard: bool) -> void:
	pointed.emit(is_discard)


func _on_part_unpointed() -> void:
	unpointed.emit()
