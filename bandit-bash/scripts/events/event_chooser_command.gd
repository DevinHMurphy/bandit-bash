# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_chooser_command.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventChooserCommand
extends EventCommand
## The seat opens the unit or weapon chooser of an option of the open event, or closes it
## ([constant EventRunState.NO_OPTION]), recording [constant CampaignFact.Kind.EVENT_CHOOSING].
##
## Saved like every command, so a quit mid-choice resumes in the chooser. Only an option with a
## chooser ([method EventOption.chooser]) that the seat can choose now opens one; a team choice
## has no chooser stage. Choosing the option itself is [EventOptionCommand], from either stage.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The option whose chooser opens; [constant EventRunState.NO_OPTION] closes the open one.
var option_index: int = EventRunState.NO_OPTION


func _init(sender: int = -1, option: int = EventRunState.NO_OPTION) -> void:
	seat = sender
	option_index = option


func get_label() -> String:
	if option_index == EventRunState.NO_OPTION:
		return "close event chooser"
	return "open event chooser %d" % [option_index]


func validate(run: CampaignRunState) -> String:
	var problem: String = open_problem(run)
	if problem.is_empty():
		problem = EventCommand.seat_problem(run, seat)
	if not problem.is_empty():
		return problem
	var event: EventDefinition = open_event(run)
	if event.is_team_choice:
		return "a team choice has no chooser stage"
	if option_index == EventRunState.NO_OPTION:
		var is_open: bool = run.events.seat_event(seat).choosing != EventRunState.NO_OPTION
		return "" if is_open else "seat %d has no chooser open" % [seat]
	if option_index < 0 or option_index >= event.options.size():
		return "the event has no option %d" % [option_index]
	if event.options[option_index].chooser() == EventOutcome.Chooser.NONE:
		return "\"%s\" has nothing to choose" % [event.options[option_index].title]
	return EventResolver.unmet_reason(
			EventContext.of(run, seat, event, option_index, catalog)
	)


func resolve(run: CampaignRunState) -> void:
	run.events.seat_event(seat).choosing = option_index
	EventCommand.record_event(run, CampaignFact.Kind.EVENT_CHOOSING, seat, option_index)
