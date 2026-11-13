# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_command.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

@abstract
class_name CampaignCommand
extends RefCounted
## One request from a seat to its run's campaign layer: choosing a node, leaving one.
##
## The campaign counterpart of [Command]. [method CampaignSession.submit] stamps it on arrival
## and [method CampaignRunState.resolve] checks it against the run as it is then, never as it was
## when sent: so the first arrival wins (two seats choosing on one floor, a shop item two seats
## want), and a rejected command changes nothing and costs nothing. Resolving is rules code: pure,
## never awaits, and records every change as a [CampaignFact] ([method CampaignRunState.record]).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The seat that sent it. The host sets it from the connection, never from the message.
var seat: int = -1

## Arrival stamp, set by [method CampaignSession.submit]: the host's order of arrival. 0 until then.
var arrival: int = 0


## A short name for log lines, such as [code]choose node[/code].
func get_label() -> String:
	return "campaign command"


## Why the command can't resolve on [param run] now; empty when it can. Changes nothing.
func validate(_run: CampaignRunState) -> String:
	return ""


## Resolves the command on [param run] once [method validate] passed, recording a fact for every
## change.
@abstract func resolve(run: CampaignRunState) -> void
