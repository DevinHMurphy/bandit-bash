# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_icon.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name IntentIcon
extends Node2D
## One enemy's intent icon over its token: a greybox glyph per [enum EnemyIntent.Kind] (combat UI
## plan, question 10; game-vision.md, Enemy intentions: attack, guard, buff, advance).
##
## The glyph is a label authored in the scene; its font and colour come from the battle theme's
## variation for the kind ([code]IntentAttackGlyph[/code], [code]IntentHealGlyph[/code],
## [code]IntentGuardGlyph[/code], [code]IntentAdvanceGlyph[/code]). Its origin is the enemy's tile
## centre. [IntentDisplay] places and reuses these, one per acting enemy.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: greybox glyphs, all in the default font; no basis in the vision or Godot_FE.
## The glyph of an attack.
@export var attack_glyph: String = "×"

## The glyph of a heal (the vision's buff icon).
@export var heal_glyph: String = "+"

## The glyph of a guard: a Support regroup, or a Wait.
@export var guard_glyph: String = "="

## The glyph of an advance toward its target.
@export var advance_glyph: String = "»"

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


## Shows [param entry]'s icon at [param board_position], the enemy's tile centre in the board's
## space; [param is_previewed]: it is a move preview's.
func show_entry(entry: IntentViewModel.Entry, board_position: Vector2, is_previewed: bool) -> void:
	enemy_id = entry.enemy_id
	kind = entry.kind
	is_preview = is_previewed
	position = board_position
	_glyph.text = glyph_of(kind)
	_glyph.theme_type_variation = _variation_of(kind)
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
	return guard_glyph


## The glyph shown, for tests.
func get_glyph_text() -> String:
	return _glyph.text


static func _variation_of(of_kind: EnemyIntent.Kind) -> StringName:
	match of_kind:
		EnemyIntent.Kind.ATTACK:
			return &"IntentAttackGlyph"
		EnemyIntent.Kind.HEAL:
			return &"IntentHealGlyph"
		EnemyIntent.Kind.ADVANCE:
			return &"IntentAdvanceGlyph"
	return &"IntentGuardGlyph"
