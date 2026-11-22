# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camp_team_status.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name CampTeamStatus
extends VBoxContainer
## Each teammate's choice at a co-op Camp, a line per seat: what they chose, or that they are still
## choosing, since the team leaves only once every seat has chosen ([LeaveNodeCommand]). Hidden in
## solo and with no teammates. Reading only; takes no input.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The name each choice is shown by, as the Camp screen's cards name them.
const CHOICE_NAMES: Dictionary[Camp.Choice, String] = {
	Camp.Choice.FEAST: "Feast",
	Camp.Choice.TRAIN: "Train",
}


func _ready() -> void:
	visible = false


## Shows the choice of each seat of [param teammates] in [param run]; hides with none.
func show_choices(run: CampaignRunState, teammates: PackedInt32Array) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	visible = not teammates.is_empty()
	for seat: int in teammates:
		var label: Label = Label.new()
		label.theme_type_variation = &"MutedLabel"
		label.text = choice_text(run, seat)
		add_child(label)


## Every line shown, in seat order, for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in get_children():
		if child is Label and not child.is_queued_for_deletion():
			lines.append((child as Label).text)
	return lines


## Seat [param seat]'s line: "Player 2 chose Feast." or "Player 2 is still choosing.".
static func choice_text(run: CampaignRunState, seat: int) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	var chosen: Camp.Choice = Camp.choice_of(seat_run) if seat_run != null else Camp.Choice.NONE
	if chosen == Camp.Choice.NONE:
		return "%s is still choosing." % [CampaignLink.seat_name(seat)]
	return "%s chose %s." % [CampaignLink.seat_name(seat), CHOICE_NAMES[chosen]]
