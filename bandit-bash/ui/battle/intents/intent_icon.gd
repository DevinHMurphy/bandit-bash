# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_icon.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name IntentIcon
extends Node2D
## One enemy's intent icon over its token: Godot_FE's action icon per [enum EnemyIntent.Kind]
## (combat UI plan, question 10; game-vision.md, Enemy intentions: attack, guard, buff, advance),
## or its greybox glyph for a kind with no icon. Each kind has its own shape, so none relies on
## its colour.
##
## The icon and the glyph take the colour of the battle theme's variation for the kind
## ([code]IntentAttackGlyph[/code], [code]IntentHealGlyph[/code], [code]IntentGuardGlyph[/code],
## [code]IntentAdvanceGlyph[/code], [code]IntentUseObjectGlyph[/code]: a lever, Brazier or
## container; [code]IntentSignatureGlyph[/code]: a signature move). Its origin is the enemy's tile
## centre. [IntentDisplay] places and reuses these, one per acting enemy.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(Art sources): docs/design/art-sources.md

@export_group("Icons")

## The icon of an attack (Godot_FE's physical damage icon: crossed swords).[br]
## [b]Unset:[/b] [member attack_glyph] shows.
@export var attack_texture: Texture2D = null

## The icon of a heal (Godot_FE's support action: a cross).[br]
## [b]Unset:[/b] [member heal_glyph] shows.
@export var heal_texture: Texture2D = null

## The icon of a guard (Godot_FE's wait action).[br][b]Unset:[/b] [member guard_glyph] shows.
@export var guard_texture: Texture2D = null

## The icon of an advance (Godot_FE's arrow).[br][b]Unset:[/b] [member advance_glyph] shows.
@export var advance_texture: Texture2D = null

## The icon of an object use (Godot_FE's interact action).[br]
## [b]Unset:[/b] [member use_object_glyph] shows.
@export var use_object_texture: Texture2D = null

## The icon of a signature move (Godot_FE's skill action).[br]
## [b]Unset:[/b] [member signature_glyph] shows.
@export var signature_texture: Texture2D = null

## The height the icon is drawn at, whatever its own size (Godot_FE's are 8 or 16 px).[br]
## [b]Units:[/b] board pixels, on a 32 px tile.
@export_range(4.0, 32.0, 1.0) var icon_height: float = 16.0

@export_group("Glyphs")

# ASSUMPTION: greybox glyphs, all in the default font, for a kind with no icon; no basis in the
# vision or Godot_FE.
## The glyph of an attack.
@export var attack_glyph: String = "×"

## The glyph of a heal (the vision's buff icon).
@export var heal_glyph: String = "+"

## The glyph of a guard: a Support regroup, or a Wait.
@export var guard_glyph: String = "="

## The glyph of an advance toward its target.
@export var advance_glyph: String = "»"

# ASSUMPTION: greybox glyph and its theme colour, as above; Latin-1, so the default font draws it.
## The glyph of an object use: pulling a lever, dousing a Brazier, looting a container.
@export var use_object_glyph: String = "¤"

# ASSUMPTION: greybox glyph and its theme colour, as above; Latin-1, so the default font draws it.
## The glyph of a signature move firing at the next enemy Phase Start, such as War Horn.
@export var signature_glyph: String = "§"

@export_group("")

# ASSUMPTION: greybox tints, as above.
## The icon's tint in a move preview, so the re-planned intents read as previewed.[br]
## [b]White:[/b] a preview looks like the current intents.
@export var preview_modulate: Color = Color(0.75, 0.85, 1.0, 0.8)

## The tint, in a move preview, of an enemy whose intent the move changes; takes the place of
## [member preview_modulate].[br]
## [b]White:[/b] a changed intent looks like any other previewed one.
@export var changed_modulate: Color = Color(1.0, 0.75, 0.3, 1.0)

## The enemy shown; empty while unused.
var enemy_id: String = ""

## The kind shown.
var kind: EnemyIntent.Kind = EnemyIntent.Kind.GUARD

## Whether it shows a preview's intent.
var is_preview: bool = false

@onready var _glyph: Label = %GlyphLabel
@onready var _art: Sprite2D = %Art


## Shows [param entry]'s icon at [param board_position], the enemy's tile centre in the board's
## space; [param is_previewed]: it is a move preview's.
func show_entry(entry: IntentViewModel.Entry, board_position: Vector2, is_previewed: bool) -> void:
	enemy_id = entry.enemy_id
	kind = entry.kind
	is_preview = is_previewed
	position = board_position
	_glyph.text = glyph_of(kind)
	_glyph.theme_type_variation = _variation_of(kind)
	var texture: Texture2D = texture_of(kind)
	_art.texture = texture
	_art.visible = texture != null
	_glyph.visible = texture == null
	if texture != null:
		_art.scale = Vector2.ONE * (icon_height / maxf(float(texture.get_height()), 1.0))
		_art.self_modulate = _glyph.get_theme_color(&"font_color", _variation_of(kind))
	if not is_previewed:
		modulate = Color.WHITE
	else:
		modulate = changed_modulate if entry.is_changed else preview_modulate
	visible = true


## Hides the icon and forgets its enemy.
func release() -> void:
	visible = false
	enemy_id = ""


## The glyph text of [param of_kind].
func glyph_of(of_kind: EnemyIntent.Kind) -> String:
	match of_kind:
		EnemyIntent.Kind.ATTACK:
			return attack_glyph
		EnemyIntent.Kind.HEAL:
			return heal_glyph
		EnemyIntent.Kind.ADVANCE:
			return advance_glyph
		EnemyIntent.Kind.USE_OBJECT:
			return use_object_glyph
		EnemyIntent.Kind.SIGNATURE:
			return signature_glyph
	return guard_glyph


## The icon of [param of_kind]; null when it has none, so its glyph shows.
func texture_of(of_kind: EnemyIntent.Kind) -> Texture2D:
	match of_kind:
		EnemyIntent.Kind.ATTACK:
			return attack_texture
		EnemyIntent.Kind.HEAL:
			return heal_texture
		EnemyIntent.Kind.ADVANCE:
			return advance_texture
		EnemyIntent.Kind.USE_OBJECT:
			return use_object_texture
		EnemyIntent.Kind.SIGNATURE:
			return signature_texture
	return guard_texture


## The glyph of the kind shown, for tests; it shows only while the kind has no icon.
func get_glyph_text() -> String:
	return _glyph.text


## The icon shown, for tests; null while the glyph shows.
func get_art() -> Texture2D:
	return _art.texture if _art.visible else null


static func _variation_of(of_kind: EnemyIntent.Kind) -> StringName:
	match of_kind:
		EnemyIntent.Kind.ATTACK:
			return &"IntentAttackGlyph"
		EnemyIntent.Kind.HEAL:
			return &"IntentHealGlyph"
		EnemyIntent.Kind.ADVANCE:
			return &"IntentAdvanceGlyph"
		EnemyIntent.Kind.USE_OBJECT:
			return &"IntentUseObjectGlyph"
		EnemyIntent.Kind.SIGNATURE:
			return &"IntentSignatureGlyph"
	return &"IntentGuardGlyph"
