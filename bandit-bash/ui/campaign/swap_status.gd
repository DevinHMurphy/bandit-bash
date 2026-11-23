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
## with an open proposal or an accepted swap ([method SwapText.status_line]), then, while one
## waits for the viewer's answer, where to answer it ([constant ANSWER_HINT]), so it is seen
## without opening the [SwapPanel]. Hidden when there is none, and always in solo. Reads no input.
##
## @tutorial(Unit swaps): docs/design/coop-unit-swaps.md

## The last line while a teammate's proposal waits for the viewer: how to reach the [SwapPanel].
const ANSWER_HINT: String = "Answer in Army, then Swaps."

@onready var _lines_label: Label = %Lines


func _ready() -> void:
	visible = false


## Shows [param run]'s swaps for [param viewer]; hides when none names the viewer.
func show_swaps(run: CampaignRunState, viewer: int) -> void:
	var lines: PackedStringArray = []
	var is_waiting: bool = false
	if run != null and run.seats.size() > 1:
		for partner: int in run.seat_numbers():
			if partner == viewer:
				continue
			var line: String = SwapText.status_line(run, viewer, partner)
			if not line.is_empty():
				lines.append(line)
			is_waiting = is_waiting or (
					SwapText.status_of(run, viewer, partner)
					== SwapText.PairStatus.PROPOSED_TO_VIEWER
			)
	if is_waiting:
		lines.append(ANSWER_HINT)
	_lines_label.text = "\n".join(lines)
	visible = not lines.is_empty()


## The lines shown, in seat order, then [constant ANSWER_HINT] when it shows, for tests.
func get_lines() -> PackedStringArray:
	if _lines_label.text.is_empty():
		return PackedStringArray()
	return _lines_label.text.split("\n")
