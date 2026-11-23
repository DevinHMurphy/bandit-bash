# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_flow.gd
# Author:
# Created:  November 13, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name RunFlow
extends RefCounted
## Where a run stands between its map and its nodes, and the run-wide state every seat shares:
## the Unknown odds and outcome, the maps already used, the shop stock and the accepted swaps.
##
## Pure data held by [CampaignRunState], saved as the [code]run_flow[/code] section through
## [method capture] and [method restore]. The node the run is at is
## [member CampaignRunState.node]; this holds only the stage within it. The Unknown odds and
## outcome, used maps, shop stock and swaps start empty, which means the base odds, nothing
## rolled, no map used, no stock rolled and no swap; the rules that set them fill them.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# Meaningful while a run exists (a CampaignRunState holds it).
# MAP      the run is on the campaign map between nodes. ChooseNodeCommand (solo) or, in co-op,
#          the RouteVoteCommand that completes the votes locks the next floor and moves to NODE.
# NODE     the run is inside CampaignRunState.node; a combat node's battle begins and ends here.
#          Both are rejected; LeaveNodeCommand goes back to MAP with the node still
#          visited and its floor still locked. A won battle moves to RESULTS
#          (CampaignRunState.apply_battle); a lost one stays. An Unknown node's outcome is rolled
#          here (ResolveUnknownCommand) and kept in unknown until the node is left.
# RESULTS  a combat node's battle is won and paid: each seat's report and item pick wait in its
#          pending offers. ItemPickCommand takes or skips a seat's pick; LeaveNodeCommand goes back
#          to MAP once every pick is resolved, clearing both. No battle begins here.
# Other nodes append their own stages (a shop's stock) and leave through LeaveNodeCommand. A node
# is never left back onto its own floor: the floor stays locked, as Godot_FE's campaign_map.gd
# locks it.
## Where the run is; see the block above. Saved by name ([method stage_id]), so values may be
## renumbered, never renamed without a migration.
enum Stage {
	## Between nodes, on the campaign map.
	MAP,
	## Inside the run's current node.
	NODE,
	## At the results of the current node's won combat.
	RESULTS,
}

# Saved names of Stage. Never change one: saved runs are read by these names.
const _STAGE_IDS: Dictionary[Stage, String] = {
	Stage.MAP: "map",
	Stage.NODE: "node",
	Stage.RESULTS: "results",
}

# capture()'s keys. Never change them: saved runs are read by these names.
const _KEY_STAGE: String = "stage"
const _KEY_UNKNOWN_ODDS: String = "unknown_odds"
const _KEY_USED_MAPS: String = "used_maps"
const _KEY_SHOP_STOCK: String = "shop_stock"
const _KEY_UNKNOWN: String = "unknown"
const _KEY_SWAPS: String = "swaps"

## Where the run is.
var stage: Stage = Stage.MAP

## The current chance of each typed thing an Unknown node can become, by
## [UnknownResolution]'s odds key; an event takes the rest.[br]
## [b]Units:[/b] percent. [b]Empty:[/b] every outcome at its base chance.
var unknown_odds: Dictionary[String, int] = {}

## What the Unknown node the run is in became, an [UnknownResolution] outcome id, cleared when the
## node is left. [b]Empty:[/b] not rolled yet, or not inside an Unknown node.
var unknown: String = ""

## Combat map ids the run has used since its pool last refilled, oldest first. [b]Empty:[/b] none.
var used_maps: PackedStringArray = []

## Stock rolled for shops every seat shares, as plain JSON in the shape the shop's rules define.
## [b]Empty:[/b] nothing rolled.
var shop_stock: Dictionary = {}

## The co-op swaps accepted for the next combat the team fights ([AnswerSwapCommand]), in the order
## accepted; [method CampaignRunState.battle_request] puts each visitor on its partner's map. They
## end when that combat ends or a named unit leaves its army. [b]Empty:[/b] none.
var swaps: Array[UnitSwap] = []


## Whether the run is on the map, between nodes.
func is_on_map() -> bool:
	return stage == Stage.MAP


## The name [param of_stage] is saved under, such as [code]"map"[/code].
func stage_id(of_stage: Stage) -> String:
	return _STAGE_IDS[of_stage]


## This flow as plain JSON, for the [code]run_flow[/code] section.
func capture() -> Dictionary:
	var swap_data: Array = []
	for swap: UnitSwap in swaps:
		swap_data.append(swap.capture())
	return {
		_KEY_STAGE: _STAGE_IDS[stage],
		_KEY_UNKNOWN_ODDS: unknown_odds.duplicate(),
		_KEY_USED_MAPS: Array(used_maps),
		_KEY_SHOP_STOCK: shop_stock.duplicate(true),
		_KEY_UNKNOWN: unknown,
		_KEY_SWAPS: swap_data,
	}


## Takes [param data], as [method capture] wrote it, numbers as whole floats too. Returns
## [constant ERR_INVALID_DATA], changing nothing, for an unknown stage, a missing field, an odds
## value that isn't a whole number, an Unknown outcome that isn't one, a swap
## [method UnitSwap.restore] refuses or two swaps sharing a pair of seats or a unit. A missing Unknown outcome or swap list
## (a run saved before either was kept) reads as not rolled and none.
func restore(data: Dictionary) -> Error:
	var stage_key: Variant = _STAGE_IDS.find_key(data.get(_KEY_STAGE))
	var odds: Variant = data.get(_KEY_UNKNOWN_ODDS)
	var maps: Variant = data.get(_KEY_USED_MAPS)
	var stock: Variant = data.get(_KEY_SHOP_STOCK)
	var resolved: Variant = data.get(_KEY_UNKNOWN, "")
	var read_swaps: Array[UnitSwap] = []
	if not _read_swaps(data.get(_KEY_SWAPS, []), read_swaps):
		push_error("RunFlow: bad swaps - %s" % [data.get(_KEY_SWAPS)])
		return ERR_INVALID_DATA
	if stage_key == null or not odds is Dictionary or not maps is Array or not stock is Dictionary:
		push_error("RunFlow: not a run flow's data - %s" % [data])
		return ERR_INVALID_DATA
	if not resolved is String or not (
			(resolved as String).is_empty() or UnknownResolution.OUTCOMES.has(resolved as String)
	):
		push_error("RunFlow: bad Unknown outcome - %s" % [resolved])
		return ERR_INVALID_DATA
	var read_odds: Dictionary[String, int] = {}
	var odds_data: Dictionary = odds
	for outcome: Variant in odds_data:
		var chance: Variant = CampaignRunState.whole_number(odds_data[outcome])
		if not outcome is String or chance == null:
			push_error("RunFlow: bad Unknown odds - %s" % [odds_data])
			return ERR_INVALID_DATA
		read_odds[outcome as String] = chance as int
	var read_maps: PackedStringArray = []
	for map_id: Variant in maps as Array:
		if not map_id is String:
			push_error("RunFlow: bad used maps - %s" % [maps])
			return ERR_INVALID_DATA
		read_maps.append(map_id as String)

	stage = stage_key as Stage
	unknown_odds = read_odds
	used_maps = read_maps
	shop_stock = (stock as Dictionary).duplicate(true)
	unknown = resolved as String
	swaps = read_swaps
	return OK


# Reads data's swaps into into, in order: each one UnitSwap.restore() takes, no two joining the
# same pair of seats or naming the same unit. False, with into partly filled, for any other.
static func _read_swaps(data: Variant, into: Array[UnitSwap]) -> bool:
	if not data is Array:
		return false
	for entry: Variant in data as Array:
		var swap: UnitSwap = UnitSwap.restore(entry)
		if swap == null:
			return false
		for kept: UnitSwap in into:
			if (
					kept.joins(swap.seat_a, swap.seat_b)
					or kept.names_unit(swap.unit_a) or kept.names_unit(swap.unit_b)
			):
				return false
		into.append(swap)
	return true
