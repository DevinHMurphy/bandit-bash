# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_purchase_command.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name GuildhallPurchaseCommand
extends CampaignCommand
## A seat buys one entry of the Guildhall's shared stock: a recruit
## ([method Guildhall.buy_recruit]), replacing [member replaced_id] with its items settled by
## [member hand_over] when the army is full, or a rune ([method Guildhall.buy_rune]), discarding
## the one in [member discard_slot] when every slot is full.
##
## Checked against the stock as it is on arrival, so of two seats buying one entry the first
## confirmed purchase gets it and the second is refused, costing nothing (game-vision.md, Co-op
## ownership).
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The index of the entry in [member GuildhallStock.entries].
var entry: int = -1

## Instance id of the living unit a recruit replaces; empty while the army has room, and for a
## rune.
var replaced_id: String = ""

## Where each handed-over item goes, by instance id ([enum Guildhall.HandOver]): every item of the
## replaced unit, and any of the recruit's own it gives up. Empty when no unit is replaced.
var hand_over: Dictionary[String, int] = {}

## The rune slot emptied for a bought rune when every slot is full; [constant Guildhall.NO_SLOT]
## otherwise, and for a recruit.
var discard_slot: int = Guildhall.NO_SLOT

## Content the stock and the seat's items come from; null: the loaded catalog.
var catalog: EffectCatalog.Index = null


func _init(sender: int = -1, stock_index: int = -1) -> void:
	seat = sender
	entry = stock_index


func get_label() -> String:
	var replacing: String = "" if replaced_id.is_empty() else " replacing %s" % [replaced_id]
	var discarding: String = (
			"" if discard_slot == Guildhall.NO_SLOT else ", discarding slot %d" % [discard_slot]
	)
	return "buy guildhall entry %d%s%s" % [entry, replacing, discarding]


func validate(run: CampaignRunState) -> String:
	var stock: GuildhallStock = GuildhallStock.pending(run)
	if stock != null and entry >= 0 and entry < stock.entries.size():
		if not stock.entries[entry].is_recruit():
			if not replaced_id.is_empty() or not hand_over.is_empty():
				return "a rune goes in the rune slots, so it replaces no unit"
			return Guildhall.rune_problem(run, seat, entry, discard_slot, _contents())
		if discard_slot != Guildhall.NO_SLOT:
			return "a recruit joins the army, so no rune is discarded"
	return Guildhall.recruit_problem(run, seat, entry, replaced_id, hand_over, _contents())


func resolve(run: CampaignRunState) -> void:
	if GuildhallStock.pending(run).entries[entry].is_recruit():
		Guildhall.buy_recruit(run, seat, entry, replaced_id, hand_over, _contents())
	else:
		Guildhall.buy_rune(run, seat, entry, discard_slot, _contents())


func _contents() -> EffectCatalog.Index:
	return catalog if catalog != null else EffectCatalog.index()
