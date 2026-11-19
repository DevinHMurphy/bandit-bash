# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     surprise_combat_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name SurpriseCombatOutcome
extends EventOutcome
## Starts a surprise combat: a Standard combat at the event node's floor and step, with a
## Standard combat's full rewards (events.md, Rules).
##
## Only a descriptor: it sets [member EventResult.surprise_combat] and changes no run state, so
## it records no fact. The battle bridge runs the combat from it. An event with one is always a
## team choice ([method EventDefinition.problems]).
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md


func apply(ctx: EventContext, _index: int) -> void:
	ctx.result.surprise_combat = EventResult.SurpriseCombat.new(ctx.run.floor_number, ctx.run.node)
