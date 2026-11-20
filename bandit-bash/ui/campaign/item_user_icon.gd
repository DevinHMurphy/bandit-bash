# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_user_icon.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name ItemUserIcon
extends TextureRect
## One unit that can use an offered item, on an [ItemUsableBy] row: its sprite, as the board draws
## it ([UnitSpriteTable]), or its name's initial when its type has none.
##
## The mouse over it asks the row to show the unit's name ([signal pointed], [signal unpointed]).
## It takes no focus, as the card it sits on holds it; clicks pass through to the card, so a click
## on an icon still picks the item. Reads no input.

## The mouse entered it: the row shows its unit's name.
signal pointed(icon: ItemUserIcon)

## The mouse left it.
signal unpointed(icon: ItemUserIcon)

## The icon's width and height; the sprite is drawn whole inside, keeping its shape.[br]
## [b]Units:[/b] base units. 32 draws a 32 × 32 unit sprite at its own size at 1280×720.
@export_range(16.0, 64.0, 4.0) var icon_size: float = 32.0:
	set(value):
		icon_size = value
		if not is_node_ready():
			return
		custom_minimum_size = Vector2(icon_size, icon_size)

## Instance id of the unit shown, by [method show_unit]; empty before it.
var unit_id: String = ""

## The unit's name as its tooltip shows it, by [method show_unit]; empty before it.
var unit_name: String = ""

@onready var _initial: Label = %Initial


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


## Shows the unit [param id], named [param shown_name], as [param sprite]; its name's initial
## when [param sprite] is null.
func show_unit(id: String, shown_name: String, sprite: Texture2D) -> void:
	unit_id = id
	unit_name = shown_name
	texture = sprite
	_initial.visible = sprite == null
	_initial.text = shown_name.left(1).to_upper()


## Whether it shows the initial, as its type has no sprite.
func is_showing_initial() -> bool:
	return _initial.visible


func _on_mouse_entered() -> void:
	pointed.emit(self)


func _on_mouse_exited() -> void:
	unpointed.emit(self)
