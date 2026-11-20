# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unknown_resolution.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name UnknownResolution
extends RefCounted
## What an Unknown node becomes, rolled once as the team enters it (game-vision.md, Unknown (?)
## rolls), and the rising odds [member RunFlow.unknown_odds] carries from one Unknown to the next.
##
## One d100 is checked against the combat, shop and treasure chances in that order, Slay the
## Spire's; below none of them, it is an event. Chances summing past 100 squeeze out the event
## first, then the later types. A shop draws once more: an Armory or a Guildhall, evenly. The type
## that came up drops back to its base chance and every other one gains its base, so an event
## raises all three. Never a Camp: Camps are a visible routing choice. The base chances are the
## map rules' ([member CampaignMapRules.unknown_combat_chance] and the two after it); empty odds
## mean every type at base, as at a run's start. Pure and static.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## An Unknown that became a Standard combat. The outcome ids are saved in [member RunFlow.unknown]:
## never change one.
const COMBAT: String = "combat"
## An Unknown that became an Armory.
const ARMORY: String = "armory"
## An Unknown that became a Guildhall.
const GUILDHALL: String = "guildhall"
## An Unknown that became a Treasure.
const TREASURE: String = "treasure"
## An Unknown that became an event ([EventNode]).
const EVENT: String = "event"

## Every outcome id.
const OUTCOMES: PackedStringArray = [COMBAT, ARMORY, GUILDHALL, TREASURE, EVENT]

## The keys of [member RunFlow.unknown_odds], in the order the d100 checks them. The shop's chance
## covers the Armory and the Guildhall together. Saved: never change one.
const ODDS_COMBAT: String = "combat"
## The shop's chance (an Armory or a Guildhall).
const ODDS_SHOP: String = "shop"
## The treasure's chance.
const ODDS_TREASURE: String = "treasure"

## The odds keys in the order the d100 checks them.
const ODDS_ORDER: PackedStringArray = [ODDS_COMBAT, ODDS_SHOP, ODDS_TREASURE]

# The faces of the roll: 0 to 99 against chances in percent.
const _D100: int = 100

# A shop's two outcomes, drawn evenly.
const _SHOPS: PackedStringArray = [ARMORY, GUILDHALL]

# The node type each outcome plays as.
const _TYPES: Dictionary[String, CampaignGraph.NodeType] = {
	COMBAT: CampaignGraph.NodeType.STANDARD,
	ARMORY: CampaignGraph.NodeType.ARMORY,
	GUILDHALL: CampaignGraph.NodeType.GUILDHALL,
	TREASURE: CampaignGraph.NodeType.TREASURE,
	EVENT: CampaignGraph.NodeType.UNKNOWN,
}


## Each type's base chance from [param rules], which is also what it gains when another comes up,
## by odds key. [b]Units:[/b] percent.
static func base_chances(rules: CampaignMapRules) -> Dictionary[String, int]:
	return {
		ODDS_COMBAT: rules.unknown_combat_chance,
		ODDS_SHOP: rules.unknown_shop_chance,
		ODDS_TREASURE: rules.unknown_treasure_chance,
	}


## Each type's chance at the next Unknown, by odds key: [param flow]'s saved odds, and the base
## from [param rules] for any it has none for. The event's is what is left of 100.
## [b]Units:[/b] percent.
static func chances(flow: RunFlow, rules: CampaignMapRules) -> Dictionary[String, int]:
	var base: Dictionary[String, int] = base_chances(rules)
	var found: Dictionary[String, int] = {}
	for key: String in ODDS_ORDER:
		found[key] = flow.unknown_odds.get(key, base[key])
	return found


## Rolls the outcome of the Unknown [param flow]'s run is in from [param stream] (one d100, then a
## second draw for a shop), at [method chances]; saves it in [member RunFlow.unknown] and the new
## odds in [member RunFlow.unknown_odds]. Returns the outcome id.
static func roll(flow: RunFlow, rules: CampaignMapRules, stream: RngStream) -> String:
	var current: Dictionary[String, int] = chances(flow, rules)
	var base: Dictionary[String, int] = base_chances(rules)
	var draw: int = stream.randi_range(0, _D100 - 1)
	var came_up: String = ""
	var threshold: int = 0
	for key: String in ODDS_ORDER:
		threshold += current[key]
		if draw < threshold:
			came_up = key
			break
	var outcome: String = EVENT
	match came_up:
		ODDS_COMBAT:
			outcome = COMBAT
		ODDS_SHOP:
			outcome = _SHOPS[stream.pick_index(_SHOPS.size())]
		ODDS_TREASURE:
			outcome = TREASURE
	var next: Dictionary[String, int] = {}
	for key: String in ODDS_ORDER:
		next[key] = base[key] if key == came_up else current[key] + base[key]
	flow.unknown_odds = next
	flow.unknown = outcome
	return outcome


## The node type an Unknown of [param outcome] plays as: an event stays
## [constant CampaignGraph.NodeType.UNKNOWN], as does an id that isn't an outcome.
static func type_of(outcome: String) -> CampaignGraph.NodeType:
	return _TYPES.get(outcome, CampaignGraph.NodeType.UNKNOWN)


## Whether [param run] is inside an Unknown node on its map, before any battle there is won.
static func is_at_unknown(run: CampaignRunState) -> bool:
	return (
			run != null and run.flow.stage == RunFlow.Stage.NODE
			and run.graph != null and run.graph.has_node_id(run.node)
			and run.graph.type_of(run.node) == CampaignGraph.NodeType.UNKNOWN
	)


## Whether [param run] is inside an Unknown node that became an event and has none open there
## yet: [method EventNode.open]'s command is due. A rejection leaves it so.
static func needs_event(run: CampaignRunState) -> bool:
	return (
			is_at_unknown(run) and run.flow.unknown == EVENT
			and not run.events.is_open_at(run.floor_number, run.node)
	)
