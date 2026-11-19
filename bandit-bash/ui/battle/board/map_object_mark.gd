# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_object_mark.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MapObjectMark
extends Node2D
## One map object on the battle board: its art for its kind and state on its tile, dimmed while
## spent (an open door, an opened or searched container, an unlit brazier), and a corner tag
## linking it: a lever and the doors it pulls share a letter, a passage's two ends a number.
##
## Art is Godot_FE's entity and dungeon-tile art ([method art_of]); a kind with none (the house)
## shows the style guide's placeholder, its glyph in [code]accent[/code] on a dark circle
## ([RewardIcon]). States read by shape and opacity, never colour alone: a key door is a wooden
## door and a lever door a portcullis; an emptied shelf or rack loses its goods; an unlit brazier
## loses its flame. Breakables aren't marks: they stand as units and draw as tokens. Its origin is
## the tile centre. [BattleView] places one per object and plays each change onto it.
##
## @tutorial(Map objects): docs/design/map-objects.md
## @tutorial(Art sources): docs/design/art-sources.md

@export_group("Art")

## A chest, open or shut (an opened one is dimmed).[br]
## [b]Unset:[/b] the chest shows its placeholder glyph.
@export var chest_texture: Texture2D = null

## A door that needs a key or a lockpick (no lever group): a wooden door.[br]
## [b]Unset:[/b] the placeholder glyph.
@export var key_door_texture: Texture2D = null

## A door on a lever group: a portcullis, so it reads apart from a key door by shape.[br]
## [b]Unset:[/b] the placeholder glyph.
@export var lever_door_texture: Texture2D = null

## A lever.[br][b]Unset:[/b] the placeholder glyph.
@export var lever_texture: Texture2D = null

# ASSUMPTION: Godot_FE has no house entity, so a house keeps the placeholder (RF-008).
## A house, searched or not.[br][b]Unset:[/b] the placeholder glyph.
@export var house_texture: Texture2D = null

## A food shelf still holding its ingredient.[br][b]Unset:[/b] the placeholder glyph.
@export var food_shelf_texture: Texture2D = null

## A food shelf once searched.[br][b]Unset:[/b] the full shelf's art, dimmed.
@export var food_shelf_used_texture: Texture2D = null

## A book shelf still holding its rune.[br][b]Unset:[/b] the placeholder glyph.
@export var book_shelf_texture: Texture2D = null

## A book shelf once searched.[br][b]Unset:[/b] the full shelf's art, dimmed.
@export var book_shelf_used_texture: Texture2D = null

## A weapon rack still holding its weapon.[br][b]Unset:[/b] the placeholder glyph.
@export var weapon_rack_texture: Texture2D = null

## A weapon rack once searched.[br][b]Unset:[/b] the full rack's art, dimmed.
@export var weapon_rack_used_texture: Texture2D = null

# ASSUMPTION: Godot_FE built no passage, so its end is the dungeon tile sheet's stairs.
## A passage end.[br][b]Unset:[/b] the placeholder glyph.
@export var passage_texture: Texture2D = null

# ASSUMPTION: Godot_FE has no brazier; the dungeon tile sheet's wall torch stands in, lit and out.
## A lit brazier.[br][b]Unset:[/b] the placeholder glyph.
@export var brazier_lit_texture: Texture2D = null

## An unlit brazier.[br][b]Unset:[/b] the lit art, dimmed.
@export var brazier_unlit_texture: Texture2D = null

@export_group("Placeholder glyphs")

# ASSUMPTION: greybox glyphs, all in the default font, for a kind with no art; no basis in the
# vision or Godot_FE.
## The placeholder glyph of a closed door.
@export var closed_door_glyph: String = "#"

## The placeholder glyph of an open door.
@export var open_door_glyph: String = "¦"

## The placeholder glyph of a lever.
@export var lever_glyph: String = "/"

## The placeholder glyph of a chest.
@export var chest_glyph: String = "$"

## The placeholder glyph of a searchable: a house, a food shelf, a book shelf or a weapon rack.
@export var searchable_glyph: String = "?"

## The placeholder glyph of a passage end.
@export var passage_glyph: String = "@"

## The placeholder glyph of a brazier.
@export var brazier_glyph: String = "*"

@export_group("")

# ASSUMPTION: greybox tint, as above.
## The tint of a spent object: an open door, an opened or searched container, an unlit brazier.
## [br][b]White:[/b] a spent object looks like any other.
@export var spent_modulate: Color = Color(1.0, 1.0, 1.0, 0.45)

## The object shown; empty before [method show_object].
var object_id: String = ""

## The view shown; null before [method show_object].
var view: BoardViewModel.ObjectView = null

@onready var _art: Sprite2D = %Art
@onready var _placeholder: RewardIcon = %Placeholder
@onready var _tag: Label = %TagLabel


## Shows [param shown] at [param board_position], its tile's centre in the board's space.
func show_object(shown: BoardViewModel.ObjectView, board_position: Vector2) -> void:
	view = shown
	object_id = shown.id
	position = board_position
	_tag.text = shown.tag
	_tag.visible = not shown.tag.is_empty()
	refresh()


## Draws [member view]'s state again after it changed: the art or placeholder, and the spent tint.
func refresh() -> void:
	if view == null:
		return
	var texture: Texture2D = art_of(view)
	_art.texture = texture
	_art.visible = texture != null
	_placeholder.symbol = glyph_of(view)
	_placeholder.visible = texture == null
	modulate = spent_modulate if view.is_spent() else Color.WHITE


## The art of [param of_view] in its state; null when its kind has none, so the placeholder shows.
func art_of(of_view: BoardViewModel.ObjectView) -> Texture2D:
	match of_view.kind:
		MapLayout.ObjectKind.DOOR:
			return lever_door_texture if of_view.group_id >= 0 else key_door_texture
		MapLayout.ObjectKind.LEVER:
			return lever_texture
		MapLayout.ObjectKind.CHEST:
			return chest_texture
		MapLayout.ObjectKind.HOUSE:
			return house_texture
		MapLayout.ObjectKind.FOOD_SHELF:
			return _state_art(of_view.is_used, food_shelf_texture, food_shelf_used_texture)
		MapLayout.ObjectKind.BOOK_SHELF:
			return _state_art(of_view.is_used, book_shelf_texture, book_shelf_used_texture)
		MapLayout.ObjectKind.WEAPON_RACK:
			return _state_art(of_view.is_used, weapon_rack_texture, weapon_rack_used_texture)
		MapLayout.ObjectKind.PASSAGE:
			return passage_texture
		MapLayout.ObjectKind.BRAZIER:
			return _state_art(not of_view.is_lit, brazier_lit_texture, brazier_unlit_texture)
	return null


## The placeholder glyph of [param of_view], shown when it has no art.
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


## The placeholder glyph for the state shown, for tests; it shows only while there is no art.
func get_glyph_text() -> String:
	return _placeholder.symbol


## The art shown, for tests; null while the placeholder shows.
func get_art() -> Texture2D:
	return _art.texture if _art.visible else null


## The tag shown, for tests; empty when hidden.
func get_tag_text() -> String:
	return _tag.text if _tag.visible else ""


# The spent state's own art when it has one, else the unspent art (dimmed by the spent tint).
static func _state_art(is_spent: bool, unspent: Texture2D, spent: Texture2D) -> Texture2D:
	if is_spent and spent != null:
		return spent
	return unspent
