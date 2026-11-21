# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_batch.gd
# Author:
# Created:  November 13, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name CampaignBatch
extends RefCounted
## What one [CampaignCommand] did: the facts it recorded, in order, or why it was rejected.
##
## Made by [method CampaignRunState.resolve] and announced by
## [signal CampaignSession.campaign_batch_resolved]. Presentation plays [member facts]; a rejected
## batch has none. On the wire ([method to_wire], [method from_wire]) it carries its facts, for
## presentation, and never the run: some changes record no fact, so a mirror can't be kept from
## facts alone.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# Slots of the wire array: seat, arrival, label, rejection, facts.
const _WIRE_FIELDS: int = 5

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


## This batch as an Array of plain values, for RPCs and repro dumps:
## [code][seat, arrival, label, rejection, [each fact's CampaignFact.to_wire()]][/code].
## [method from_wire] reverses it. The slot order is a network contract: append new fields at the
## end only, and readers refuse any other length, since peers are one build.
func to_wire() -> Array:
	var fact_wires: Array = []
	for fact: CampaignFact in facts:
		fact_wires.append(fact.to_wire())
	return [seat, arrival, label, rejected_reason, fact_wires]


## Rebuilds a batch from [method to_wire] output, also after a trip through JSON, where numbers
## arrive as floats. Returns [code]null[/code], with one error, for a wrong length or value type,
## a number that isn't whole, a seat below [constant CampaignFact.NO_SEAT], a negative arrival, a
## fact [method CampaignFact.from_wire] refuses (which warns too), or a rejection with facts.
static func from_wire(data: Array) -> CampaignBatch:
	if (
			data.size() != _WIRE_FIELDS
			or not data[2] is String
			or not data[3] is String
			or not data[4] is Array
	):
		push_error("CampaignBatch: malformed wire data - %s" % [data])
		return null
	var sender: Variant = _wire_int(data[0])
	var stamp: Variant = _wire_int(data[1])
	var fact_wires: Array = data[4]
	if (
			sender == null or (sender as int) < CampaignFact.NO_SEAT
			or stamp == null or (stamp as int) < 0
			or (not (data[3] as String).is_empty() and not fact_wires.is_empty())
	):
		push_error("CampaignBatch: wire data out of range - %s" % [data])
		return null
	var batch: CampaignBatch = CampaignBatch.new()
	batch.seat = sender
	batch.arrival = stamp
	batch.label = data[2]
	batch.rejected_reason = data[3]
	for wire: Variant in fact_wires:
		var fact: CampaignFact = CampaignFact.from_wire(wire as Array) if wire is Array else null
		if fact == null:
			push_error("CampaignBatch: a fact can't be read - %s" % [wire])
			return null
		batch.facts.append(fact)
	return batch


# value as an int when it is one, or when it is a whole float within JSON's exact range (it went
# through JSON); null otherwise.
# NOTE: The same rule as CampaignCommand._wire_int(); keep the two in step.
static func _wire_int(value: Variant) -> Variant:
	if value is int:
		return value
	if not value is float:
		return null
	var number: float = value
	if number != floorf(number) or absf(number) > CampaignFact.MAX_EXACT_JSON_INT:
		return null
	return int(number)
