# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_story.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventStory
extends HBoxContainer
## The event's scene as the player reads it before choosing: its art on the left, its name and
## text beside it. An event with no art ([member EventDefinition.art] unset) shows
## [member placeholder_art], or with none the slot's muted placeholder word, until the art pass.
## Shows a problem instead when the event can't be shown. Reads no input.
##
## @tutorial(Events): docs/design/events.md

## The art slot's size.[br]
## [b]Units:[/b] base units. [b]0:[/b] the slot takes no room (the art is still drawn at its own
## size inside its frame).
@export var art_size: Vector2 = Vector2(200.0, 150.0):
	set(value):
		art_size = value
		if not is_node_ready():
			return
		_frame.custom_minimum_size = art_size

## The picture shown for an event without art of its own. [b]Unset:[/b] the slot's placeholder
## word shows on its frame instead.
@export var placeholder_art: Texture2D = null

## The width the event's text wraps at, so it reads as a paragraph beside the art.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as the text, unwrapped.
@export var text_width: float = 620.0:
	set(value):
		text_width = value
		if not is_node_ready():
			return
		_text_label.custom_minimum_size.x = text_width

@onready var _frame: PanelContainer = %ArtFrame
@onready var _art: TextureRect = %Art
@onready var _placeholder_label: Label = %ArtPlaceholder
@onready var _title_label: Label = %Title
@onready var _text_label: Label = %Text


func _ready() -> void:
	_frame.custom_minimum_size = art_size
	_text_label.custom_minimum_size.x = text_width


## Shows [param event]: its art (or the placeholder), name and text.
func show_event(event: EventDefinition) -> void:
	var picture: Texture2D = event.art if event.art != null else placeholder_art
	_art.texture = picture
	_placeholder_label.visible = picture == null
	_title_label.text = event.title if not event.title.is_empty() else event.id
	_text_label.text = event.text


## Shows that no event can be shown here, and [param problem] as the reason.
func show_problem(problem: String) -> void:
	_art.texture = null
	_placeholder_label.visible = true
	_title_label.text = "This event can't be shown"
	_text_label.text = "The %s. Leave returns to the map." % [problem]


## The heading shown, for tests.
func get_title_text() -> String:
	return _title_label.text


## The text shown, for tests.
func get_text() -> String:
	return _text_label.text


## Whether the placeholder shows in the art slot, for tests.
func is_placeholder_shown() -> bool:
	return _placeholder_label.visible
