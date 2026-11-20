# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_draw.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name HeirloomDraw
extends RefCounted
## The random heirloom a Treasure chest and a Key combat give (heirlooms.md, Tiers and sources):
## its tier rolled Common 50 / Uncommon 33 / Rare 17 ([method roll_tier]; a chest's size is its
## tier), then one heirloom of that tier ([method draw]).
##
## A drawn heirloom is one the seat doesn't own (offers never duplicate one), never a curse and
## never a starting, Shop or commander heirloom; co-op-only ones only in co-op. A tier with none
## left draws from the whole main pool (game-vision.md, Empty offer pools). Draws come only from
## the stream handed in; pure and static.
##
## @tutorial(Heirlooms, Tiers and sources): docs/design/heirlooms.md

## The main pool's tiers, in [constant TIER_WEIGHTS]' order.
const TIERS: PackedStringArray = [
	ContentIds.HEIRLOOM_COMMON,
	ContentIds.HEIRLOOM_UNCOMMON,
	ContentIds.HEIRLOOM_RARE,
]

## The chance of each of [constant TIERS] (heirlooms.md: Slay the Spire's chest-size odds, also
## the Key combat's heirloom odds). [b]Units:[/b] percent.
const TIER_WEIGHTS: PackedInt32Array = [50, 33, 17]


## A tier of [constant TIERS] from [param stream], by [constant TIER_WEIGHTS]; one draw.
static func roll_tier(stream: RngStream) -> String:
	var index: int = stream.pick_weighted(TIER_WEIGHTS)
	return TIERS[maxi(index, 0)]


## One heirloom of [param tier] for [param seat_run], evenly in id order, from [param stream]
## (see the class doc), the whole main pool when the tier has none left; [param is_coop] admits
## co-op-only heirlooms. Empty, drawing nothing, when nothing is left at all.
static func draw(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		tier: String,
		is_coop: bool
) -> String:
	var found: PackedStringArray = candidates(seat_run, catalog, PackedStringArray([tier]), is_coop)
	if found.is_empty():
		found = candidates(seat_run, catalog, TIERS, is_coop)
	if found.is_empty():
		return ""
	return found[stream.pick_index(found.size())]


## Ids of the heirlooms of [param tiers] [param seat_run] may be given (see the class doc), sorted.
static func candidates(
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		tiers: PackedStringArray,
		is_coop: bool
) -> PackedStringArray:
	var owned: PackedStringArray = seat_run.heirloom_ids()
	var found: PackedStringArray = []
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.HEIRLOOM):
		var heirloom: HeirloomDefinition = resource as HeirloomDefinition
		if heirloom == null or heirloom is CurseDefinition or not tiers.has(heirloom.tier):
			continue
		if owned.has(heirloom.id) or (heirloom.is_coop_only and not is_coop):
			continue
		found.append(heirloom.id)
	found.sort()
	return found
