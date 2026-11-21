# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     open_armory_command.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name OpenArmoryCommand
extends CampaignCommand
## Rolls the Armory's shared stock at the Armory node the run is in ([method ArmoryStock.roll]),
## from the node's shared [code]SHOP_STOCK[/code] stream, and saves it in the run's shop stock:
## the Armory screen's entry point, as [OpenTreasureCommand] is a Treasure's.
##
## Valid only inside an Armory whose stock isn't rolled yet, so a continued run shows the stock it
## saved and never rolls again. Records no fact: rolling an offer changes no state a player sees
## until something is bought. The command's save ([method CampaignService.submit_command]) keeps
## the stock before anything shows.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Its name on the wire ([method CampaignCommand.get_wire_type]). It has no fields of its own:
## the catalog, allocator and stream are the host's.
const WIRE_TYPE: String = "open_armory"

## Content the stock draws from.
var catalog: EffectCatalog.Index = null

## Mints each stocked item's instance id: the session's allocator.
var ids: InstanceIdAllocator = null

## The node's shared [code]SHOP_STOCK[/code] stream ([method stock_stream]).
var stream: RngStream = null


func _init(sender: int = -1) -> void:
	seat = sender


func get_label() -> String:
	return "open armory"


func validate(run: CampaignRunState) -> String:
	if not Armory.is_at_armory(run):
		return "the run isn't inside an Armory"
	if catalog == null or ids == null or stream == null:
		return "the catalog, id allocator or shop stream is missing"
	if run.flow.shop_stock.has(ArmoryStock.OFFER_KEY):
		return "the Armory's stock is already rolled"
	return ""


func resolve(run: CampaignRunState) -> void:
	ArmoryStock.roll(stream, run, catalog, ids).store(run)


func get_wire_type() -> String:
	return WIRE_TYPE


## The command that rolls the stock at the Armory [param session]'s run is in, with the node's
## stream and the session's allocator, sent from the host seat. [param catalog_used] null: the
## loaded one. Null, reported, with no run.
static func for_session(
		session: CampaignSession, catalog_used: EffectCatalog.Index = null
) -> OpenArmoryCommand:
	if session == null or session.run == null:
		push_error("OpenArmoryCommand: no run to open an Armory in")
		return null
	var command: OpenArmoryCommand = OpenArmoryCommand.new(CampaignData.HOST_SEAT)
	command.catalog = catalog_used if catalog_used != null else EffectCatalog.index()
	command.ids = session.ids
	command.stream = stock_stream(session)
	return command


## The shared [code]SHOP_STOCK[/code] stream of the node [param session]'s run is in: the stock's
## roll and a unique heirloom's restock draw from it, in that order.
static func stock_stream(session: CampaignSession) -> RngStream:
	return session.rng.stream(RngKey.new(
			RngKey.RngPurpose.SHOP_STOCK, session.run.floor_number, session.run.node
	))
