# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_prefix_definition.gd
# Author:
# Created:  October 29, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name UnitPrefixDefinition
extends EffectCarrierDefinition
## A unit prefix, shown before the unit type ("Sturdy Lancer"): a permanent shift of a few stats
## and their growths in the same direction (unit-roster.md, Prefixes).
##
## Lives in [code]res://data/prefixes/units/[/code]. A unit rolls one, or none, which is the
## baseline ([method roll]; [method reroll] for the Guildhall's re-roll). The deltas apply as
## modifiers sourced to the prefix, so breakdowns name it. Prefixes never touch MOV or CON, and
## never take a stat or growth below 0. Commanders never roll one. The draws are pure: the caller
## hands in the stream its purpose owns (rng-streams plan, Purpose catalog).
##
## @tutorial(Unit roster, Prefixes): docs/design/unit-roster.md

## A roll's result when it lands on no prefix, as [member UnitInstance.prefix_id] holds it.
const NO_PREFIX: String = ""

## The results a roll lands on, by tier, in [constant TIER_WEIGHTS]' order; 0 is no prefix.
const TIERS: Array[int] = [0, 2, 1, -1, -2]

## Each result's weight out of 100, in [constant TIERS]' order: no prefix 30, +2 10, +1 35,
## -1 18, -2 7 (unit-roster.md, Odds, first pass). Recruits and enemies roll the same odds.
const TIER_WEIGHTS: Array[int] = [30, 10, 35, 18, 7]

## Quality tier, from +2 (strongest) to -2; the UI colors the name by it. No prefix is the
## baseline, so 0 is not a prefix tier.
@export_range(-2, 2) var tier: int = 1

## Stat changes, by [enum CombatValue.Stat] (HP, MGT, SPD, DEF, RES only).[br]
## [b]Units:[/b] stat points; negative lowers. [b]Empty:[/b] none.
@export var stat_deltas: Dictionary[CombatValue.Stat, int] = {}

## Growth changes, by [enum CombatValue.Stat] (HP, MGT, SPD, DEF, RES only).[br]
## [b]Units:[/b] percentage points (15 is +15%). [b]Empty:[/b] none.
@export var growth_deltas: Dictionary[CombatValue.Stat, int] = {}

## Hit change, which is not a stat (Keen's +20).[br]
## [b]Units:[/b] Hit percent. [b]0:[/b] none.
@export_range(-50, 50) var hit_delta: int = 0


## A prefix id for a new unit from [param stream]: the tier by [constant TIER_WEIGHTS], then a
## prefix of that tier from [param catalog] with equal odds, in id order (Terraria's reforge). A
## tier with no prefix in the catalog drops out of the odds. [constant NO_PREFIX] for no prefix,
## or a null stream or catalog (nothing drawn).
static func roll(stream: RngStream, catalog: EffectCatalog.Index) -> String:
	return _draw(stream, catalog, NO_PREFIX, false)


## A different result for a unit whose prefix is [param current_id] ([constant NO_PREFIX] for
## none), drawn like [method roll] with the current result left out, so a paid re-roll always
## changes something: a prefixed unit never lands on its prefix again, and one with no prefix
## always gains one. A tier left with nothing drops out of the odds.
static func reroll(stream: RngStream, catalog: EffectCatalog.Index, current_id: String) -> String:
	return _draw(stream, catalog, current_id, true)


## Every prefix of [param prefix_tier] in [param catalog], in id order, without
## [param excluded_id].
static func of_tier(
		catalog: EffectCatalog.Index, prefix_tier: int, excluded_id: String = NO_PREFIX
) -> Array[UnitPrefixDefinition]:
	var found: Array[UnitPrefixDefinition] = []
	if catalog == null:
		return found
	for resource: Resource in catalog.all_of(EffectCatalog.Kind.UNIT_PREFIX):
		var prefix: UnitPrefixDefinition = resource as UnitPrefixDefinition
		if prefix != null and prefix.tier == prefix_tier and prefix.id != excluded_id:
			found.append(prefix)
	return found


# One draw for the tier, then one for the prefix within it (none when it holds one). When
# excludes_current, the current result (a prefix, or none) is left out.
static func _draw(
		stream: RngStream,
		catalog: EffectCatalog.Index,
		current_id: String,
		excludes_current: bool
) -> String:
	if stream == null or catalog == null:
		return NO_PREFIX
	var weights: PackedInt32Array = []
	var total: int = 0
	for index: int in TIERS.size():
		var is_open: bool = false
		if TIERS[index] == 0:
			is_open = not (excludes_current and current_id == NO_PREFIX)
		else:
			is_open = not of_tier(catalog, TIERS[index], current_id).is_empty()
		var weight: int = TIER_WEIGHTS[index] if is_open else 0
		weights.append(weight)
		total += weight
	if total == 0:
		return NO_PREFIX
	var picked: int = stream.pick_weighted(weights)
	if picked < 0 or TIERS[picked] == 0:
		return NO_PREFIX
	var pool: Array[UnitPrefixDefinition] = of_tier(catalog, TIERS[picked], current_id)
	return pool[stream.pick_index(pool.size())].id
