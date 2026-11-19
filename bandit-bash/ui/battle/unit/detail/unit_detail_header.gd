# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_detail_header.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitDetailHeader
extends VBoxContainer
## The top of the [UnitDetailPanel]: the unit's sprite, name, type and side, vitals with its HP bar,
## a player unit's level and XP ([DetailProgress]), and the row of Previous, its place among its
## side's units, Next and Close (ui-lift.md, Unit detail pop-up).
##
## It only reports presses ([signal step_pressed], [signal close_pressed]); the panel passes them
## on. Previous and Next never take focus, so a pad's and the keyboard's focus stays on Close; they
## step with the shoulder buttons and Q / E instead, which [BattleController] reads. Holds no rules.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## Previous ([param forward] false) or Next (true) was clicked.
signal step_pressed(forward: bool)

## Close was clicked or accepted.
signal close_pressed()

## The unit sprites by unit type, as the board's tokens draw them.[br]
## [b]Unset:[/b] no sprite shows.
@export var sprites: UnitSpriteTable = null

## The line under the name: [code]%s[/code] the unit type, then its side.
@export var summary_format: String = "%s · %s"

## Added to the summary for its army's commander.[br]
## [b]Empty:[/b] commanders aren't called out.
@export var commander_text: String = "Commander"

## Added to the summary once the unit has acted this phase.[br]
## [b]Empty:[/b] it isn't called out.
@export var acted_text: String = "Has acted"

## Added to an enemy's summary: [code]%d[/code] its level. A player unit's level shows with its
## XP instead. [b]Empty:[/b] an enemy's level isn't shown.
@export var enemy_level_format: String = "Lv %d"

## Added to the summary of a unit with a prefix: [code]%s[/code] the prefix's name.
## [b]Empty:[/b] the prefix isn't called out (it still leads the unit's name).
@export var prefix_format: String = "Prefix: %s"

## The vitals line: [code]%d[/code] HP and its maximum, Stance and its maximum, then Block.
@export var vitals_format: String = "HP %d/%d · Stance %d/%d · Block %d"

## The place among its side's units: [code]%d[/code] its place from 1, then how many.
@export var place_format: String = "%d of %d"

var _summary_text: String = ""

@onready var _sprite: TextureRect = %Sprite
@onready var _name: Label = %UnitName
@onready var _summary: Label = %Summary
@onready var _vitals: Label = %Vitals
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _progress: DetailProgress = %Progress
@onready var _previous: Button = %PreviousButton
@onready var _place: Label = %Place
@onready var _next: Button = %NextButton
@onready var _close: Button = %CloseButton


func _ready() -> void:
	_previous.pressed.connect(_on_previous_button_pressed)
	_next.pressed.connect(_on_next_button_pressed)
	_close.pressed.connect(_on_close_button_pressed)


## Draws [param view]'s header.
func show_header(view: UnitDetailViewModel) -> void:
	if view == null:
		return
	var texture: Texture2D = sprites.sprite_for(view.type_id) if sprites != null else null
	_sprite.texture = texture
	_sprite.visible = texture != null
	_name.text = view.name
	var summary: String = summary_format % [
		view.type_name, (CombatFact.CombatSide.find_key(view.side) as String).capitalize(),
	]
	if view.is_commander and not commander_text.is_empty():
		summary += " · " + commander_text
	if view.side == CombatFact.CombatSide.ENEMY and not enemy_level_format.is_empty():
		summary += " · " + enemy_level_format % [view.level]
	if not view.prefix_name.is_empty() and not prefix_format.is_empty():
		summary += " · " + prefix_format % [view.prefix_name]
	if view.has_acted and not acted_text.is_empty():
		summary += " · " + acted_text
	_summary_text = summary
	_summary.text = summary
	_vitals.text = vitals_format % [view.hp, view.max_hp, view.stance, view.stance_max, view.block]
	_hp_bar.max_value = maxf(float(view.max_hp), 1.0)
	_hp_bar.value = float(view.hp)
	_progress.show_progress(view.level, view.xp, view.xp_per_level)
	_place.text = place_format % [view.place + 1, view.side_count]
	var can_step: bool = view.side_count > 1
	_previous.disabled = not can_step
	_next.disabled = not can_step


## The Close button, which holds focus while the panel is open.
func get_close_button() -> Button:
	return _close


## The Previous and Next buttons, for tests that press them.
func get_step_buttons() -> Array[Button]:
	return [_previous, _next]


## Its lines as shown, for tests: name, summary, vitals, level, XP, place.
func get_texts() -> PackedStringArray:
	var progress: PackedStringArray = _progress.get_texts()
	return PackedStringArray([
		_name.text, _summary_text, _vitals.text, progress[0], progress[1], _place.text,
	])


func _on_previous_button_pressed() -> void:
	step_pressed.emit(false)


func _on_next_button_pressed() -> void:
	step_pressed.emit(true)


func _on_close_button_pressed() -> void:
	close_pressed.emit()
