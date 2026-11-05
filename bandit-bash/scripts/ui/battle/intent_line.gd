# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_line.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name IntentLine
extends Node2D
## One numbered line from an enemy to its intent's target, its number the enemy's place in the
## expected enemy phase (combat UI plan, question 10; the orchestrator's enemies-and-intents
## design item).
##
## Drawn with an arrowhead at the target; a move preview's line is dashed. The number is a label
## authored in the scene, styled by the theme's [code]IntentOrderLabel[/code], at the line's
## middle. [IntentDisplay] places and reuses these, one per intent with a target.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ASSUMPTION: greybox look for every export here; the combat UI plan sets no palette.
## The line's colour.
@export var line_color: Color = Color(1.0, 0.85, 0.3, 0.9):
	set(value):
		line_color = value
		queue_redraw()

## The line's colour in a move preview.
@export var preview_color: Color = Color(0.7, 0.85, 1.0, 0.9):
	set(value):
		preview_color = value
		queue_redraw()

## The line's width.[br]
## [b]Units:[/b] pixels.
@export_range(1.0, 8.0, 0.5) var line_width: float = 2.0:
	set(value):
		line_width = value
		queue_redraw()

## The length of each dash of a preview's line.[br]
## [b]Units:[/b] pixels. [b]0.0:[/b] a preview's line is solid too.
@export_range(0.0, 32.0, 0.5) var dash_length: float = 6.0:
	set(value):
		dash_length = value
		queue_redraw()

## How far short of each tile centre the line stops, so it doesn't cover the tokens.[br]
## [b]Units:[/b] pixels. [b]0.0:[/b] centre to centre.
@export_range(0.0, 32.0, 0.5) var end_inset: float = 10.0:
	set(value):
		end_inset = value
		queue_redraw()

## The length of the arrowhead's sides at the target.[br]
## [b]Units:[/b] pixels. [b]0.0:[/b] no arrowhead.
@export_range(0.0, 24.0, 0.5) var arrow_size: float = 7.0:
	set(value):
		arrow_size = value
		queue_redraw()

## The enemy whose line this is; empty while unused.
var enemy_id: String = ""

## The tile it points at.
var target_tile: Vector2i = CombatFact.NO_TILE

## Its number as shown, from 1.
var number: int = 0

## Whether it shows a preview's intent.
var is_preview: bool = false

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO

@onready var _number_label: Label = %OrderLabel


func _draw() -> void:
	var along: Vector2 = _to - _from
	if along.length() <= end_inset * 2.0:
		return
	var direction: Vector2 = along.normalized()
	var start: Vector2 = _from + direction * end_inset
	var end: Vector2 = _to - direction * end_inset
	var color: Color = preview_color if is_preview else line_color
	if is_preview and dash_length > 0.0:
		draw_dashed_line(start, end, color, line_width, dash_length)
	else:
		draw_line(start, end, color, line_width, true)
	if arrow_size <= 0.0:
		return
	for side: float in [-1.0, 1.0]:
		var barb: Vector2 = end - direction.rotated(side * PI / 6.0) * arrow_size
		draw_line(end, barb, color, line_width, true)


## Shows [param entry]'s line from [param from] to [param to], tile centres in the board's space;
## [param is_previewed]: it is a move preview's.
func show_entry(
		entry: IntentViewModel.Entry, from: Vector2, to: Vector2, is_previewed: bool
) -> void:
	enemy_id = entry.enemy_id
	target_tile = entry.target_tile
	number = entry.order + 1
	is_preview = is_previewed
	_from = from
	_to = to
	_number_label.text = str(number)
	_number_label.position = (from + to) * 0.5 - _number_label.size * 0.5
	visible = true
	queue_redraw()


## Hides the line and forgets its enemy.
func release() -> void:
	visible = false
	enemy_id = ""
