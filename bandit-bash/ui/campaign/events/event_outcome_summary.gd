# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_outcome_summary.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventOutcomeSummary
extends VBoxContainer
## What the seat's chosen option did, once it is taken: its title, then its text and what it
## gave by name, its curse with tier and effect, the team's draw, a surprise combat, and in co-op
## who the team still waits on ([method EventScreenModel.summary_lines]). Built from saved state,
## so a quit and Continue shows the same summary. The lines are an [EffectText]: keywords
## coloured, each explained on hover. No focusable control holds it, so key and pad focus show
## no keyword tooltips here. Reads no input.
##
## @tutorial(Events): docs/design/events.md

## The width the summary's lines wrap at.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as the text, unwrapped.
@export var line_width: float = 720.0:
	set(value):
		line_width = value
		if not is_node_ready():
			return
		_lines_text.custom_minimum_size.x = line_width

@onready var _heading_label: Label = %Heading
@onready var _lines_text: EffectText = %Lines


func _ready() -> void:
	_lines_text.custom_minimum_size.x = line_width


## Shows the option [param title] as chosen, with [param lines] under it, keywords marked.
func show_outcome(title: String, lines: PackedStringArray) -> void:
	_heading_label.text = "You chose %s" % [title]
	_lines_text.marked_text = "\n".join(lines)


## The heading shown, for tests.
func get_heading() -> String:
	return _heading_label.text


## The lines shown, one per row, their words without keyword tags, for tests.
func get_lines() -> String:
	return _lines_text.get_plain_text()


## The lines as shown, keywords and all, for tests.
func get_effect_text() -> EffectText:
	return _lines_text
