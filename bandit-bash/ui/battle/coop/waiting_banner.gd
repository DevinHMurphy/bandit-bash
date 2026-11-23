# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     waiting_banner.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name WaitingBanner
extends PanelContainer
## What a co-op seat whose map has ended waits for: "Waiting for the other maps", with how many are
## still being fought, until the battle ends and the results open; or "The run is lost" once
## [method CombatEncounter.is_run_lost] holds, until the host ends the run for everyone.
## [CoopBattle] shows it; reading only.

# ASSUMPTION: the banner's wordings; no design doc words them.
## The waiting title.
@export var waiting_text: String = "Waiting for the other maps"

## The waiting line: [code]%d[/code] the maps still being fought.
@export var left_text: String = "%d still being fought. View one, or send units, from Maps."

## The lost run's title.
@export var lost_text: String = "The run is lost"

## The lost run's line.
@export var lost_line_text: String = "A frozen map can't be helped any more."

@onready var _title: Label = %Title
@onready var _line: Label = %Line


## Shows the wait, [param left] maps still being fought.
func show_waiting(left: int) -> void:
	_title.theme_type_variation = &"HudHeading"
	_title.text = waiting_text
	_line.text = left_text % [left]
	visible = true


## Shows that the run is lost.
func show_run_lost() -> void:
	_title.theme_type_variation = &"HudWarningHeading"
	_title.text = lost_text
	_line.text = lost_line_text
	visible = true


## The title and line shown, for tests.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_title.text, _line.text])
