# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_log.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name FactLog
extends PanelContainer
## The debug fact log: one line per batch the session sends, as
## [method CombatSession.describe_batch] writes it, newest last, in a scrolling box that its header
## collapses (combat UI plan, question 11).
##
## [BattleHud] adds a line as each batch resolves, before its facts play, so the log runs ahead of
## the board while playback catches up. Keeps the newest [member max_lines]. Debug-grade: the text
## is the log's, ids and all.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## How many lines are kept; older ones are dropped.
@export_range(10, 2000, 10) var max_lines: int = 200

## Whether the log is open when the scene loads; the header toggles it.
@export var is_open_at_start: bool = true

## The header's text: [code]%d[/code] the lines kept.
@export var title_format: String = "Fact log (%d)"

var _lines: PackedStringArray = []

@onready var _toggle: Button = %Toggle
@onready var _body: RichTextLabel = %Body


func _ready() -> void:
	_toggle.toggled.connect(_on_toggle_toggled)
	_toggle.set_pressed_no_signal(is_open_at_start)
	_body.visible = is_open_at_start
	_show_title()


## Adds [param line] as the newest line, dropping the oldest past [member max_lines].
func add_line(line: String) -> void:
	_lines.append(line)
	if _lines.size() > max_lines:
		_lines = _lines.slice(_lines.size() - max_lines)
	_body.text = "\n".join(_lines)
	_show_title()


## Drops every line.
func clear() -> void:
	_lines.clear()
	_body.text = ""
	_show_title()


## The lines kept, oldest first.
func get_lines() -> PackedStringArray:
	return _lines.duplicate()


## Opens or closes the log's box.
func set_open(is_open: bool) -> void:
	_toggle.button_pressed = is_open


## Whether the log's box shows.
func is_open() -> bool:
	return _body.visible


func _show_title() -> void:
	_toggle.text = title_format % [_lines.size()]


func _on_toggle_toggled(is_pressed: bool) -> void:
	_body.visible = is_pressed
