# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_status.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SwapStatus
extends VBoxContainer
## The co-op unit swaps in the campaign map's side panel, for the viewer: a line per teammate
## with an open proposal or an accepted swap ([method SwapText.status_line]), so a proposal
## waiting for an answer is seen without opening the [SwapPanel]. Hidden when there is none, and
## always in solo. Reads no input.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

@onready var _lines_label: Label = %Lines


func _ready() -> void:
	visible = false


## Shows [param run]'s swaps for [param viewer]; hides when none names the viewer.
func show_swaps(run: CampaignRunState, viewer: int) -> void:
	var lines: PackedStringArray = []
	if run != null and run.seats.size() > 1:
		for partner: int in run.seat_numbers():
			if partner == viewer:
				continue
			var line: String = SwapText.status_line(run, viewer, partner)
			if not line.is_empty():
				lines.append(line)
	_lines_label.text = "\n".join(lines)
	visible = not lines.is_empty()


## The lines shown, in seat order, for tests.
func get_lines() -> PackedStringArray:
	if _lines_label.text.is_empty():
		return PackedStringArray()
	return _lines_label.text.split("\n")
