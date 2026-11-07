# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_token.gd
# Author:
# Created:  November 4, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name UnitToken
extends Node2D
## One unit on the battle board: its sprite, or its type's letters when it has none, in the world;
## its HP, Stance, Block and range-tracked icon on its [UnitInfo] (combat UI plan, questions 22,
## 23 and 29).
##
## [BattleView] places one per unit, moves it and gives it each value as the facts play
## ([method show_unit], [method show_hp], [method show_stance], [method show_block],
## [method show_turn], [method show_range_tracked]); the token keeps the values shown and passes
## them to [member info], which the [UnitInfoLayer] keeps over it on screen. It holds no rules.
## Its origin is the tile's centre; the layout is authored in the scene for 32 px tiles.[br]
## [b]The sprite[/b] is [member sprites]'s texture for the unit's type, drawn by
## [code]unit_sprite.gdshader[/code] (Godot_FE's [code]StrokeShader[/code], rewritten): outlined
## in its side's colour, gray while [method is_grayed], tinted by [member range_tracked_tint] while
## its range is tracked (white by default: the icon on its info shows it), and flashed by a
## critical hit ([method flash]). A type with no sprite shows its letters on a square of its
## side's colour, gray while grayed.[br]
## [b]Gray only in its own phase[/b] (question 28 (f)): a spent unit grays only while it is its
## side's phase ([method show_phase]), so in your turn an enemy never looks disabled.[br]
## [b]Target outlines[/b] stay [TargetMark]s, which also mark map objects and lettered units.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The sprite shader's outline colour parameter.
const OUTLINE_COLOR_PARAM: StringName = &"line_color"

## The sprite shader's outline width parameter.
const OUTLINE_WIDTH_PARAM: StringName = &"line_thickness"

## The sprite shader's parameter for how gray the sprite is.
const GRAY_PARAM: StringName = &"gray_amount"

## The sprite shader's tint parameter.
const TINT_PARAM: StringName = &"modulate_color"

## The sprite shader's flash colour parameter.
const FLASH_COLOR_PARAM: StringName = &"flash_color"

## The sprite shader's parameter for how far the sprite is drawn toward the flash colour.
const FLASH_AMOUNT_PARAM: StringName = &"flash_amount"

@export_group("Sprite")

## The sprite drawn for each unit type and enemy class; a type it doesn't list shows its letters.
## Edit [code]assets/sprites/units/unit_sprites.tres[/code] to add or change one.[br]
## [b]Unset:[/b] every unit shows its letters.
@export var sprites: UnitSpriteTable = null

## The sprite's outline for a player-side unit (Godot_FE's [code]Color.NAVY_BLUE[/code]).
@export var player_outline: Color = Color(0.0, 0.0, 0.501961, 1.0)

## The sprite's outline for an enemy-side unit (Godot_FE's [code]Color.DARK_RED[/code]).
@export var enemy_outline: Color = Color(0.545098, 0.0, 0.0, 1.0)

## The sprite's outline for a unit on neither side (Godot_FE's white).
@export var other_outline: Color = Color(1.0, 1.0, 1.0, 1.0)

## The outline's width, in the sprite's own pixels (Godot_FE's [code]line_thickness[/code]).[br]
## [b]Units:[/b] texels. [b]0.0:[/b] no outline.
@export_range(0.0, 4.0, 0.5) var outline_width: float = 1.0

## How gray a spent unit is in its side's phase ([method is_grayed]); Godot_FE's
## [code]color_factor[/code] was 1.[br]
## [b]0.0:[/b] spent units keep their colour. [b]1.0:[/b] fully gray.
@export_range(0.0, 1.0, 0.01) var spent_gray: float = 1.0

## The tint on the sprite while its range is tracked. Godot_FE tinted an enemy whose range showed
## red ([code]combat_unit_display.gd[/code]'s [code]RED[/code], about (1.0, 0.53, 0.46)); here
## the range-tracked icon carries it (question 28 (e)).[br]
## [b]White:[/b] no tint; the icon alone shows it.
@export var range_tracked_tint: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Letters")

# ASSUMPTION: greybox colour; the combat UI plan sets no palette (Design Basis, Gaps).
## Body colour of a lettered player-side unit.
@export var player_color: Color = Color(0.25, 0.45, 0.9, 1.0)

# ASSUMPTION: greybox colour, as above.
## Body colour of a lettered enemy-side unit.
@export var enemy_color: Color = Color(0.85, 0.25, 0.25, 1.0)

# ASSUMPTION: greybox colour, as above.
## Body colour of a lettered unit on neither side (a map object standing as a unit).
@export var other_color: Color = Color(0.6, 0.6, 0.6, 1.0)

## How many letters of the unit type id the token shows, underscores skipped, upper case
## ([method BoardViewModel.letter_of]); more than two may not fit the 26 px body.[br]
## [b]Units:[/b] letters. [b]1:[/b] one letter, so types that share one look alike.
@export_range(1, 3) var letter_count: int = 2

## Letters to show instead, by unit type id, such as [code]"hedge_healer": "HH"[/code].[br]
## [b]Empty:[/b] every type shows its first [member letter_count] letters.
@export var letter_overrides: Dictionary[String, String] = {}

@export_group("")

## The unit this token stands for; empty until [method show_unit].
var unit_id: String = ""

## The tile the token shows the unit on. [BattleView] sets it when a move starts, so it is where
## the unit is going while the move plays. A walk turn input stages before its command
## ([method BattleView.stage_walk]) moves the token but leaves this the unit's tile.
var tile: Vector2i = CombatFact.NO_TILE

## The side it is drawn for.
var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

## The HP the token shows; follows the facts as they play.
var hp: int = 0

## The maximum HP the bar is drawn against.
var max_hp: int = 0

## The Stance the token shows; follows the facts as they play.
var stance: int = 0

## The Stance maximum the pips are drawn against.
var stance_max: int = 0

## The Block the badge shows; follows the facts as they play.
var block: int = 0

## Whether the unit has taken its action, as shown.
var has_acted: bool = false

## Whether the unit may still move after its action, as shown.
var is_second_move_pending: bool = false

## Whether the enemy range toggle tracks the unit.
var is_range_tracked: bool = false

## Whether it is the unit's side's phase, as shown; only then is a spent unit gray.
var is_phase_side: bool = true

## Its bars, numbers and icons on the [UnitInfoLayer], which sets this; null draws none of them.
var info: UnitInfo = null

## How far the token is drawn toward a flash's colour ([method flash]): 0.0 not at all.
var flash_amount: float = 0.0:
	set(value):
		flash_amount = value
		if is_node_ready():
			_apply_flash()

var _flash_color: Color = Color.WHITE

@onready var _sprite: Sprite2D = %Sprite
@onready var _body: ColorRect = %Body
@onready var _letter: Label = %Letter


## Draws [param view]: its sprite or letters, its side's outline or colour, its HP, Stance, Block
## and turn. Whether its range is tracked is left as it is.
func show_unit(view: BoardViewModel.UnitView) -> void:
	unit_id = view.id
	tile = view.tile
	side = view.side
	_letter.text = letters_for(view.unit_type)
	var texture: Texture2D = sprite_for(view.unit_type)
	_sprite.texture = texture
	_sprite.visible = texture != null
	_body.visible = texture == null
	_letter.visible = texture == null
	_set_param(OUTLINE_COLOR_PARAM, outline_of(side))
	_set_param(OUTLINE_WIDTH_PARAM, outline_width)
	show_hp(view.hp, view.max_hp)
	show_stance(view.stance, view.stance_max)
	show_block(view.block)
	show_turn(view.has_acted, view.is_second_move_pending)


## Shows [param current] HP of [param maximum]; HP is never shown below 0.
func show_hp(current: int, maximum: int) -> void:
	hp = maxi(current, 0)
	max_hp = maxi(maximum, 1)
	if is_instance_valid(info):
		info.show_hp(hp, max_hp)


## Shows [param current] Stance of [param maximum] on the pips; Stance is never shown below 0, and
## Triage can raise it past its maximum. Returns the pips' change tween on a drop, paused for the
## caller to step, else null ([method StancePips.show_stance]).
func show_stance(current: int, maximum: int) -> Tween:
	stance = maxi(current, 0)
	stance_max = maxi(maximum, 0)
	if not is_instance_valid(info):
		return null
	return info.show_stance(stance, stance_max)


## Flashes the HP bar from the HP shown to [param after] HP, an open forecast's prediction.
func show_hp_preview(after: int) -> void:
	if is_instance_valid(info):
		info.show_hp_preview(after)


## Flashes no HP.
func clear_hp_preview() -> void:
	if is_instance_valid(info):
		info.clear_hp_preview()


## Dims and flashes the pips a forecast's action would break, down to [param after] Stance.
func show_stance_preview(after: int) -> void:
	if is_instance_valid(info):
		info.show_stance_preview(after)


## Dims and flashes no pip.
func clear_stance_preview() -> void:
	if is_instance_valid(info):
		info.clear_stance_preview()


## Shows [param amount] Block on the badge; Block is never shown below 0.
func show_block(amount: int) -> void:
	block = maxi(amount, 0)
	if is_instance_valid(info):
		info.show_block(block)


## Shows whether the unit [param acted] and whether its [param second_move_pending]: it is drawn
## gray while [method is_grayed].
func show_turn(acted: bool, second_move_pending: bool) -> void:
	has_acted = acted
	is_second_move_pending = second_move_pending
	_apply_gray()


## Shows whether it is the unit's side's phase ([param is_own_phase]): a spent unit is gray only
## then, and in colour during the other side's phase.
func show_phase(is_own_phase: bool) -> void:
	is_phase_side = is_own_phase
	_apply_gray()


## Shows whether the enemy range toggle [param is_tracked] the unit: the icon on its info, and
## [member range_tracked_tint] on its sprite.
func show_range_tracked(is_tracked: bool) -> void:
	is_range_tracked = is_tracked
	if is_instance_valid(info):
		info.show_range_tracked(is_tracked)
	_set_param(TINT_PARAM, range_tracked_tint if is_tracked else Color.WHITE)


## Starts a flash toward [param color] that fades over [param seconds] (a critical hit), on the
## sprite or the letters' body, and returns it, paused for the caller to step; null when
## [param seconds] is 0.
func flash(color: Color, seconds: float) -> Tween:
	if seconds <= 0.0:
		return null
	_flash_color = color
	_set_param(FLASH_COLOR_PARAM, color)
	flash_amount = 1.0
	var tween: Tween = create_tween()
	tween.pause()
	tween.tween_property(self, ^"flash_amount", 0.0, seconds)
	return tween


## Whether the unit can't act again before its side's next phase: it acted and has no second
## move pending, as [method TurnInputModel.can_act] reads a unit.
func is_spent() -> bool:
	return has_acted and not is_second_move_pending


## Whether the token is drawn gray: it is spent ([method is_spent]) and it is its side's phase.
func is_grayed() -> bool:
	return is_spent() and is_phase_side


## The sprite for [param unit_type]; null when [member sprites] has none.
func sprite_for(unit_type: String) -> Texture2D:
	return null if sprites == null else sprites.sprite_for(unit_type)


## Whether the token draws a sprite, not letters.
func has_sprite() -> bool:
	return _sprite.visible and _sprite.texture != null


## The sprite drawn; null while the token shows letters.
func get_sprite() -> Texture2D:
	return _sprite.texture if has_sprite() else null


## The letters shown for [param unit_type]: its [member letter_overrides] entry, else its first
## [member letter_count] letters.
func letters_for(unit_type: String) -> String:
	if letter_overrides.has(unit_type):
		return letter_overrides[unit_type]
	return BoardViewModel.letter_of(unit_type, letter_count)


## The token's letters, for tests: set whether they show or the sprite hides them.
func get_letters() -> String:
	return _letter.text


## Whether the letters show, for a type with no sprite.
func is_showing_letters() -> bool:
	return _letter.visible


## How gray the token is drawn now, for tests: 0.0 in colour, [member spent_gray] while grayed.
func get_gray() -> float:
	var gray: float = _get_param(GRAY_PARAM, 0.0)
	return gray


## The sprite's outline colour now, for tests.
func get_outline() -> Color:
	var outline: Color = _get_param(OUTLINE_COLOR_PARAM, Color.TRANSPARENT)
	return outline


## Whether the range-tracked icon shows on its info.
func is_range_icon_shown() -> bool:
	return is_instance_valid(info) and info.is_range_icon_shown()


## The Block badge on its info; null with no info.
func get_block_badge() -> BlockBadge:
	return info.get_block_badge() if is_instance_valid(info) else null


## The Stance pips as drawn, for tests: x the Stance, y its maximum; (-1, -1) with no info.
func get_stance_bar() -> Vector2i:
	if not is_instance_valid(info):
		return Vector2i(-1, -1)
	var pips: StancePips = info.get_stance_pips()
	return Vector2i(pips.stance, pips.stance_max)


## The letters' body colour for [param of_side].
func color_of(of_side: CombatFact.CombatSide) -> Color:
	match of_side:
		CombatFact.CombatSide.PLAYER:
			return player_color
		CombatFact.CombatSide.ENEMY:
			return enemy_color
	return other_color


## The sprite's outline colour for [param of_side].
func outline_of(of_side: CombatFact.CombatSide) -> Color:
	match of_side:
		CombatFact.CombatSide.PLAYER:
			return player_outline
		CombatFact.CombatSide.ENEMY:
			return enemy_outline
	return other_outline


# The gray on the sprite's shader, then the letters' body through _apply_flash().
func _apply_gray() -> void:
	_set_param(GRAY_PARAM, spent_gray if is_grayed() else 0.0)
	_apply_flash()


# The flash on the sprite's shader, and on the letters' body over its gray.
func _apply_flash() -> void:
	_set_param(FLASH_AMOUNT_PARAM, flash_amount)
	var body: Color = color_of(side)
	var luminance: float = body.get_luminance()
	var gray: float = spent_gray if is_grayed() else 0.0
	body = body.lerp(Color(luminance, luminance, luminance, body.a), gray)
	_body.color = body.lerp(Color(_flash_color, body.a), flash_amount)


# value: a float or a Color, whichever the parameter takes.
func _set_param(param: StringName, value: Variant) -> void:
	var shader: ShaderMaterial = _sprite.material as ShaderMaterial
	if shader != null:
		shader.set_shader_parameter(param, value)


# Returns a float or a Color, as fallback is; fallback when the sprite has no shader material.
func _get_param(param: StringName, fallback: Variant) -> Variant:
	var shader: ShaderMaterial = _sprite.material as ShaderMaterial
	if shader == null:
		return fallback
	var value: Variant = shader.get_shader_parameter(param)
	return fallback if value == null else value
