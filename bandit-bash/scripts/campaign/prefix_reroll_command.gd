# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     prefix_reroll_command.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name PrefixRerollCommand
extends CampaignCommand
## A seat re-rolls the prefix of one of its living units at the Guildhall
## ([method Guildhall.reroll]), checked by [method Guildhall.reroll_problem]. The new prefix comes
## from the seat's own [code]PREFIX_REROLL[/code] stream for the node ([method reroll_stream]), so
## one seat's re-rolls never move another's.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Unit roster, Prefixes): docs/design/unit-roster.md

## Its name on the wire ([method CampaignCommand.get_wire_type]): the unit travels; the catalog
## and the stream are the host's.
const WIRE_TYPE: String = "prefix_reroll"

## Instance id of the living unit re-rolled.
var unit_id: String = ""

## Content the prefixes and the seat's heirlooms come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null

## The seat's [code]PREFIX_REROLL[/code] stream for the node ([method reroll_stream]).
var stream: RngStream = null


func _init(sender: int = -1, unit: String = "") -> void:
	seat = sender
	unit_id = unit


func get_label() -> String:
	return "re-roll %s" % [unit_id]


func validate(run: CampaignRunState) -> String:
	if stream == null:
		return "the re-roll stream is missing"
	return Guildhall.reroll_problem(run, seat, unit_id, _contents())


func resolve(run: CampaignRunState) -> void:
	Guildhall.reroll(run, seat, unit_id, _contents(), stream)


func get_wire_type() -> String:
	return WIRE_TYPE


func _wire_fields() -> Array:
	return [unit_id]


func _read_wire_fields(values: Array) -> bool:
	if values.size() != 1 or not values[0] is String:
		return false
	unit_id = values[0]
	return true


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()


## The re-roll of seat [param sender]'s unit [param unit] with [param session]'s stream for it.
## [param catalog_used] null: the loaded one. Null, reported, with no run.
static func for_session(
		session: CampaignSession,
		sender: int,
		unit: String,
		catalog_used: EffectCatalog.Index = null
) -> PrefixRerollCommand:
	if session == null or session.run == null:
		push_error("PrefixRerollCommand: no run to re-roll in")
		return null
	var command: PrefixRerollCommand = PrefixRerollCommand.new(sender, unit)
	command.catalog = catalog_used
	command.stream = reroll_stream(session, sender)
	return command


## Seat [param seat]'s [code]PREFIX_REROLL[/code] stream for the node [param session]'s run is in:
## run-saved, per seat.
static func reroll_stream(session: CampaignSession, seat: int) -> RngStream:
	return session.rng.stream(RngKey.new(
			RngKey.RngPurpose.PREFIX_REROLL, session.run.floor_number, session.run.node, seat
	))
