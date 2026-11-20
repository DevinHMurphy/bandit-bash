# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_vote_status.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventVoteStatus
extends VBoxContainer
## The team's vote on a team-choice event of more than one seat: how the vote works, how many
## have voted and this seat's own vote while it is open, then the option the votes drew. Each
## option's own count shows on its card. Hidden outside a team vote: solo shows a team choice as
## an ordinary choice (events.md, Co-op). Reads no input.
##
## @tutorial(Events, Co-op): docs/design/events.md

@onready var _heading_label: Label = %Heading
@onready var _detail_label: Label = %Detail


func _ready() -> void:
	visible = false


## Shows [param view]'s vote among [param seat_count] seats, or hides for an event that isn't a
## team vote.
func show_votes(view: EventView, seat_count: int) -> void:
	visible = view.is_open() and view.is_team_vote
	if not visible:
		return
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
