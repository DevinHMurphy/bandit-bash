# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory_purchase_command.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name ArmoryPurchaseCommand
extends CampaignCommand
## A seat buys one entry of the Armory's shared stock ([method Armory.buy]): an item onto its
## living unit [member unit_id], the replaced item traded in or sent to the convoy, or an heirloom
## into its heirlooms.
##
## Checked by [method Armory.purchase_problem] against the stock as it is on arrival, so of two
## seats buying one entry the first confirmed purchase gets it and the second is refused, costing
## nothing (game-vision.md, Co-op ownership).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The index of the entry in [member ArmoryStock.entries].
var entry: int = -1

## Instance id of the living unit an item goes onto; empty for an heirloom.
var unit_id: String = ""

## Whether the item the new one replaces is traded in; false sends it to the convoy. Always false
## for an empty slot and for an heirloom.
var is_traded_in: bool = false

## Content the stock and the seat's items come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null

## The node's shared [code]SHOP_STOCK[/code] stream ([method OpenArmoryCommand.stock_stream]),
## which restocks a unique heirloom's slot in co-op.
var stream: RngStream = null


func _init(
		sender: int = -1, stock_index: int = -1, unit: String = "", trade_in: bool = false
) -> void:
	seat = sender
	entry = stock_index
	unit_id = unit
	is_traded_in = trade_in


func get_label() -> String:
	var onto: String = "" if unit_id.is_empty() else " onto %s" % [unit_id]
	return "buy entry %d%s%s" % [entry, onto, ", trading in" if is_traded_in else ""]


func validate(run: CampaignRunState) -> String:
	if stream == null:
		return "the shop stream is missing"
	return Armory.purchase_problem(run, seat, entry, unit_id, is_traded_in, _contents())


func resolve(run: CampaignRunState) -> void:
	Armory.buy(run, seat, entry, unit_id, is_traded_in, _contents(), stream)


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()


## The purchase of entry [param stock_index] by seat [param sender] onto [param unit] (empty for an
## heirloom), trading in when [param trade_in], with [param session]'s shop stream.
## [param catalog_used] null: the loaded one. Null, reported, with no run.
static func for_session(
		session: CampaignSession,
		sender: int,
		stock_index: int,
		unit: String = "",
		trade_in: bool = false,
		catalog_used: EffectCatalog.Index = null
) -> ArmoryPurchaseCommand:
	if session == null or session.run == null:
		push_error("ArmoryPurchaseCommand: no run to buy in")
		return null
	var command: ArmoryPurchaseCommand = ArmoryPurchaseCommand.new(
			sender, stock_index, unit, trade_in
	)
	command.catalog = catalog_used
	command.stream = OpenArmoryCommand.stock_stream(session)
	return command
