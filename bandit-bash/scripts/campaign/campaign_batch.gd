# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_batch.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name CampaignBatch
extends RefCounted
## What one [CampaignCommand] did: the facts it recorded, in order, or why it was rejected.
##
## Made by [method CampaignRunState.resolve] and announced by
## [signal CampaignSession.campaign_batch_resolved]. Presentation plays [member facts]; a rejected
## batch has none.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The seat that sent the command.
var seat: int = -1

## The command's arrival stamp ([member CampaignCommand.arrival]).
var arrival: int = 0

## The command's [method CampaignCommand.get_label], for logs.
var label: String = ""

## Why the command was rejected. [b]Empty:[/b] it resolved.
var rejected_reason: String = ""

## The facts it recorded, in order; empty when rejected.
var facts: Array[CampaignFact] = []


## Whether the command was rejected and changed nothing.
func is_rejected() -> bool:
	return not rejected_reason.is_empty()
