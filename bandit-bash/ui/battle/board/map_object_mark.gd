# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_object_mark.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name MapObjectMark
extends Node2D
## One map object on the battle board: a greybox glyph per kind on its tile, dimmed while spent
## (an open door, an opened or searched container, an unlit brazier), and a corner tag linking it:
## a lever and the doors it pulls share a letter, a passage's two ends a number.
##
## Breakables aren't marks: they stand as units and draw as tokens. The glyph's colour comes from
## the battle theme's variation for its kind ([code]ObjectDoorGlyph[/code],
## [code]ObjectLeverGlyph[/code], [code]ObjectLootGlyph[/code], [code]ObjectPassageGlyph[/code],
## [code]ObjectBrazierGlyph[/code]); the tag is [code]ObjectTag[/code]. Its origin is the tile
## centre. [BattleView] places one per object and plays each change onto it; the tile panel
## names the object and its state for the cursor, mouse or pad alike.
##
## @tutorial(Map objects): docs/design/map-objects.md

# ASSUMPTION: greybox glyphs, all in the default font, until the art pass; no basis in the vision
# or Godot_FE.
## The glyph of a closed door.
@export var closed_door_glyph: String = "#"

## The glyph of an open door.
@export var open_door_glyph: String = "¦"

## The glyph of a lever.
@export var lever_glyph: String = "/"

## The glyph of a chest.
@export var chest_glyph: String = "$"

## The glyph of a searchable: a house, a food shelf, a book shelf or a weapon rack.
@export var searchable_glyph: String = "?"

## The glyph of a passage end.
@export var passage_glyph: String = "@"

## The glyph of a brazier.
@export var brazier_glyph: String = "*"

# ASSUMPTION: greybox tint, as above.
## The tint of a spent object: an open door, an opened or searched container, an unlit brazier.
## [br][b]White:[/b] a spent object looks like any other.
@export var spent_modulate: Color = Color(1.0, 1.0, 1.0, 0.45)

## The object shown; empty before [method show_object].
var object_id: String = ""

## The view shown; null before [method show_object].
var view: BoardViewModel.ObjectView = null

@onready var _glyph: Label = %GlyphLabel
@onready var _tag: Label = %TagLabel


## Shows [param shown] at [param board_position], its tile's centre in the board's space.
func show_object(shown: BoardViewModel.ObjectView, board_position: Vector2) -> void:
	view = shown
	object_id = shown.id
	position = board_position
	_tag.text = shown.tag
	_tag.visible = not shown.tag.is_empty()
	_glyph.theme_type_variation = _variation_of(shown.kind)
	refresh()


## Draws [member view]'s state again after it changed: the glyph and the spent tint.
func refresh() -> void:
	if view == null:
		return
	_glyph.text = glyph_of(view)
	modulate = spent_modulate if view.is_spent() else Color.WHITE


## The glyph text of [param of_view].
func glyph_of(of_view: BoardViewModel.ObjectView) -> String:
	match of_view.kind:
		MapLayout.ObjectKind.DOOR:
			return open_door_glyph if of_view.is_open else closed_door_glyph
		MapLayout.ObjectKind.LEVER:
			return lever_glyph
		MapLayout.ObjectKind.CHEST:
			return chest_glyph
		MapLayout.ObjectKind.PASSAGE:
			return passage_glyph
		MapLayout.ObjectKind.BRAZIER:
			return brazier_glyph
	return searchable_glyph


## The glyph shown, for tests.
func get_glyph_text() -> String:
	return _glyph.text


## The tag shown, for tests; empty when hidden.
func get_tag_text() -> String:
	return _tag.text if _tag.visible else ""


static func _variation_of(kind: MapLayout.ObjectKind) -> StringName:
	match kind:
		MapLayout.ObjectKind.DOOR:
			return &"ObjectDoorGlyph"
		MapLayout.ObjectKind.LEVER:
			return &"ObjectLeverGlyph"
		MapLayout.ObjectKind.PASSAGE:
			return &"ObjectPassageGlyph"
		MapLayout.ObjectKind.BRAZIER:
			return &"ObjectBrazierGlyph"
	return &"ObjectLootGlyph"
