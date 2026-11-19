# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_definition.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name EventDefinition
extends Resource
## A narrative event an Unknown node can hold: a short scene with 2–3 trade-off options
## (events.md).
##
## Lives in [code]res://data/events/[/code]. Read-only at runtime: what an option rolls and what
## the player picks live on the run, never here. A team-choice event is decided by one vote-
## weighted draw for the whole team and applies to every seat; an individual one lets each seat
## choose for itself.
##
## @tutorial(Events): docs/design/events.md

## When an event may be drawn.
enum Eligibility {
	## Whenever the run hasn't seen it.
	ALWAYS = 0,
	## Only once at least one unit of the army has fallen (the revive shrine).
	FALLEN_UNIT = 1,
}

## The fewest options an event has (events.md).
const MIN_OPTIONS: int = 2

## The most options an event has (events.md).
const MAX_OPTIONS: int = 3

## Content id: snake_case, equal to the file name, such as [code]dark_goblet[/code].
@export var id: String = ""

## Its name, shown as the event's heading, such as "Dark Goblet".
@export var title: String = ""

## The scene the player reads before choosing.
@export_multiline var text: String = ""

## The event's picture on its screen. [b]Unset:[/b] the screen's placeholder art.
@export var art: Texture2D = null

## Whether the team decides one option for every seat by vote, instead of each seat choosing for
## itself. Every event with a combat option is one.
@export var is_team_choice: bool = false

## When it may be drawn.
@export var eligibility: Eligibility = Eligibility.ALWAYS

## Its options, in the order shown: [constant MIN_OPTIONS] to [constant MAX_OPTIONS].
@export var options: Array[EventOption] = []


## Whether it may be drawn for [param seat_run]: always, or with a fallen unit.
func is_eligible(seat_run: SeatRun) -> bool:
	if eligibility == Eligibility.FALLEN_UNIT:
		return not seat_run.fallen.is_empty()
	return true


## What is wrong with this event as data, one line each: no id, the wrong number of options, a
## missing option, an option's own problems, or a combat option outside a team choice. Empty
## when it is sound.
func problems() -> PackedStringArray:
	var found: PackedStringArray = []
	if id.is_empty():
		found.append("an event has no id")
	if options.size() < MIN_OPTIONS or options.size() > MAX_OPTIONS:
		found.append("%s: %d options, not %d to %d" % [
			id, options.size(), MIN_OPTIONS, MAX_OPTIONS,
		])
	for option: EventOption in options:
		if option == null:
			found.append("%s: an option is missing" % [id])
			continue
		for problem: String in option.problems():
			found.append("%s: %s" % [id, problem])
		if not is_team_choice and _has_combat(option):
			found.append("%s: \"%s\" starts a combat, so the event is a team choice" % [
				id, option.title,
			])
	return found


static func _has_combat(option: EventOption) -> bool:
	for outcome: EventOutcome in option.outcomes:
		if outcome is SurpriseCombatOutcome:
			return true
	return false
