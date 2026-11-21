# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     open_guildhall_command.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name OpenGuildhallCommand
extends CampaignCommand
## Rolls the Guildhall's shared stock at the Guildhall node the run is in
## ([method GuildhallStock.roll]), from the node's shared [code]SHOP_STOCK[/code] stream, and
## saves it in the run's shop stock: the Guildhall screen's entry point, as [OpenArmoryCommand] is
## the Armory's.
##
## Valid only inside a Guildhall whose stock isn't rolled yet, so a continued run shows the stock
## it saved and never rolls again. Records no fact: rolling an offer changes no state a player sees
## until something is bought. The command's save ([method CampaignService.submit_command]) keeps
## the stock before anything shows.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]). It has no fields of its own:
## the catalog, allocator and stream are the host's.
const WIRE_TYPE: String = "open_guildhall"

## Content the stock draws from.
var catalog: EffectCatalog.Index = null

## Mints each recruit's and rune's instance ids: the session's allocator.
var ids: InstanceIdAllocator = null

## The node's shared [code]SHOP_STOCK[/code] stream ([method OpenArmoryCommand.stock_stream]).
var stream: RngStream = null


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "open guildhall"


func validate(run: CampaignRunState) -> String:
	if not Guildhall.is_at_guildhall(run):
		return "the run isn't inside a Guildhall"
	if catalog == null or ids == null or stream == null:
		return "the catalog, id allocator or shop stream is missing"
	if run.flow.shop_stock.has(GuildhallStock.OFFER_KEY):
		return "the Guildhall's stock is already rolled"
	return ""


func resolve(run: CampaignRunState) -> void:
	GuildhallStock.roll(stream, run, catalog, ids).store(run)


func get_wire_type() -> String:
	return WIRE_TYPE


## The command that rolls the stock at the Guildhall [param session]'s run is in, with the node's
## stream and the session's allocator, sent from the host seat. [param catalog_used] null: the
## loaded one. Null, reported, with no run.
static func for_session(
		session: CampaignSession, catalog_used: EffectCatalog.Index = null
) -> OpenGuildhallCommand:
	if session == null or session.run == null:
		push_error("OpenGuildhallCommand: no run to open a Guildhall in")
		return null
	var command: OpenGuildhallCommand = OpenGuildhallCommand.new(CampaignData.HOST_SEAT)
	command.catalog = catalog_used if catalog_used != null else EffectCatalog.index()
	command.ids = session.ids
	command.stream = OpenArmoryCommand.stock_stream(session)
	return command
