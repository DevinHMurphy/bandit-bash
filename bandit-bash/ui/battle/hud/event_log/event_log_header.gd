# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_log_header.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name EventLogHeader
extends PanelContainer
## A header row of the [EventLog]: a turn and phase ("Turn 3 · Player phase") or the battle's end
## in [code]accent[/code] over a rule (6.73:1 on [code]panel[/code]); the darkness phase's on a
## [code]darkness[/code]-filled row in [code]text[/code] (5.00:1), as its banner shows it, since
## [code]darkness[/code] as text fails contrast (2.06:1). Headers ignore the filters.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The row's theme type for a phase header and the battle's end.
@export var panel_type: StringName = &"EventLogHeaderPanel"

## The label's theme type for a phase header and the battle's end.
@export var label_type: StringName = &"EventLogHeaderLabel"

## The row's theme type for the darkness phase's header.
@export var darkness_panel_type: StringName = &"DarknessRowPanel"

## The label's theme type for the darkness phase's header.
@export var darkness_label_type: StringName = &"EventLogDarknessLabel"

var _is_darkness: bool = false

@onready var _label: Label = %Text


## Shows [param entry]'s text, on the darkness row when its tone is
## [constant EventLogWriter.Tone.DARKNESS_HEADER].
func show_entry(entry: EventLogWriter.Entry) -> void:
	_is_darkness = entry.tone == EventLogWriter.Tone.DARKNESS_HEADER
	_label.text = entry.text()
	theme_type_variation = darkness_panel_type if _is_darkness else panel_type
	_label.theme_type_variation = darkness_label_type if _is_darkness else label_type


## The header's text.
func get_text() -> String:
	return _label.text


## Whether it shows on the darkness row.
func is_darkness() -> bool:
	return _is_darkness
