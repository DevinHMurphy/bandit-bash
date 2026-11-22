# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_vote_status.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EventVoteStatus
extends VBoxContainer
## The team's vote on a team-choice event of more than one seat: how the vote works, how many
## have voted and this seat's own vote while it is open, then the option the votes drew; under
## it, each teammate's vote by name ([method vote_text]). Each option's own count shows on its
## card. Hidden outside a team vote: solo shows a team choice as an ordinary choice (events.md,
## Co-op). Reads no input.
##
## @tutorial(Events, Co-op): docs/design/events.md

@onready var _heading_label: Label = %Heading
@onready var _detail_label: Label = %Detail
@onready var _seats_label: Label = %Seats


func _ready() -> void:
	visible = false


## Shows [param view]'s vote among [param seat_count] seats, or hides for an event that isn't a
## team vote.
func show_votes(view: EventView, seat_count: int) -> void:
	visible = view.is_open() and view.is_team_vote
	if not visible:
		return
	var lines: PackedStringArray = []
	for teammate: int in EventTeamStatus.teammates_of(view):
		lines.append(vote_text(view, teammate))
	_seats_label.text = "\n".join(lines)
	_seats_label.visible = not lines.is_empty()
	var own: int = view.votes.get(view.seat, EventRunState.NO_OPTION)
	var own_text: String = (
			"" if own == EventRunState.NO_OPTION
			else "Your vote: %s." % [view.options[own].option.title]
	)
	if view.is_vote_needed():
		_heading_label.text = "Team choice: everyone votes"
		_detail_label.text = "%d of %d votes cast. %s One option is drawn, weighted by votes." % [
			view.votes.size(), seat_count,
			"You haven't voted." if own_text.is_empty() else own_text,
		]
		return
	var drawn: EventView.OptionView = view.options[view.drawn]
	_heading_label.text = "The team drew %s" % [drawn.option.title]
	_detail_label.text = "%d of %d votes were for it. %s" % [
		drawn.vote_count, view.votes.size(), own_text,
	]
	_detail_label.text = _detail_label.text.strip_edges()


## The heading shown, for tests.
func get_heading() -> String:
	return _heading_label.text


## The detail line shown, for tests.
func get_detail() -> String:
	return _detail_label.text


## Each teammate's vote as shown, one line each in seat order, for tests.
func get_seat_lines() -> PackedStringArray:
	if _seats_label.text.is_empty():
		return PackedStringArray()
	return _seats_label.text.split("\n")


## Seat [param seat]'s vote in [param view] as its line reads: "Player 2 voted for Fight." or
## "Player 2 hasn't voted.".
static func vote_text(view: EventView, seat: int) -> String:
	var vote: int = view.votes.get(seat, EventRunState.NO_OPTION)
	var shown_name: String = CampaignLink.seat_name(seat)
	if vote < 0 or vote >= view.options.size():
		return "%s hasn't voted." % [shown_name]
	return "%s voted for %s." % [shown_name, view.options[vote].option.title]
