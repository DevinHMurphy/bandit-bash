# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_team_status.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventTeamStatus
extends VBoxContainer
## Each teammate's part in the event open at a co-op node, a line per seat in seat order: in an
## event each seat chooses alone, what they chose or that they are still choosing; in a team vote,
## once the votes drew the option, whether they have taken it for their own army yet. The node is
## left only once every seat has chosen. Hidden in solo, with no event, and while a team vote is
## still open, when the [EventVoteStatus] lists each vote. Reading only; takes no input.
##
## @tutorial(Co-op combat plan, Screens): docs/plans/2026-11-20-coop-combat.md


func _ready() -> void:
	visible = false


## Shows each teammate of [param view]'s seat, or hides as the class doc says.
func show_team(view: EventView) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var teammates: PackedInt32Array = teammates_of(view)
	visible = view.is_open() and not view.is_vote_needed() and not teammates.is_empty()
	if not visible:
		return
	for seat: int in teammates:
		var label: Label = Label.new()
		label.theme_type_variation = &"MutedLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = choice_text(view, seat)
		add_child(label)


## Every line shown, in seat order, for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for child: Node in get_children():
		if child is Label and not child.is_queued_for_deletion():
			lines.append((child as Label).text)
	return lines


## Every seat of [param view]'s event but its own, ascending; empty with no event open.
static func teammates_of(view: EventView) -> PackedInt32Array:
	var others: PackedInt32Array = []
	for seat: int in view.choices:
		if seat != view.seat:
			others.append(seat)
	others.sort()
	return others


## Seat [param seat]'s part in [param view] as one line: "Player 2 chose Drink Deep." or "Player 2
## is still choosing."; in a team vote "Player 2 took Intimidate." or "Player 2 hasn't taken
## Intimidate yet.", and before the draw its vote ([method EventVoteStatus.vote_text]).
static func choice_text(view: EventView, seat: int) -> String:
	if view.is_vote_needed():
		return EventVoteStatus.vote_text(view, seat)
	var shown_name: String = CampaignLink.seat_name(seat)
	var chosen: int = view.choices.get(seat, EventRunState.NO_OPTION)
	if view.is_team_vote and view.drawn >= 0 and view.drawn < view.options.size():
		var drawn_title: String = view.options[view.drawn].option.title
		if chosen == EventRunState.NO_OPTION:
			return "%s hasn't taken %s yet." % [shown_name, drawn_title]
		return "%s took %s." % [shown_name, drawn_title]
	if chosen < 0 or chosen >= view.options.size():
		return "%s is still choosing." % [shown_name]
	return "%s chose %s." % [shown_name, view.options[chosen].option.title]
