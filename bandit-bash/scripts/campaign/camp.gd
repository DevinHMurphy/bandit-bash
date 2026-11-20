# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     camp.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name Camp
extends RefCounted
## A Camp's rules (game-vision.md, Campaign nodes; items.md, Ingredients): each seat chooses one of
## Feast or Train, once per visit, saved in its [member SeatRun.pending_offers] under
## [constant OFFER_KEY] until the run leaves; leaving needs every seat's choice.
##
## [b]Feast:[/b] every living unit of every seat heals [constant FEAST_HEAL_PERCENT] of its max HP,
## halves up, through its healing received ([method RunOperations.healing_received_percent]), so
## several seats' Feasts stack. One ingredient may be cooked, from the cook's convoy or a living
## unit's Pouch: it is used up, and every living unit of the cook's army gains its cooked stats on
## its next level-up, and its cooked Hit at once. [b]Train:[/b] one unit is upgraded
## ([method RunOperations.upgrade]). Re-gearing alongside is [Regear]'s. Pure and static.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
## @tutorial(Items, Ingredients): docs/design/items.md

## What a seat chose at the Camp. Saved by name ([constant CHOICE_IDS]), so values may be
## renumbered, never renamed without a migration.
enum Choice {
	## Not chosen yet.
	NONE,
	## The Feast.
	FEAST,
	## Train.
	TRAIN,
}

## The key of a seat's Camp visit in [member SeatRun.pending_offers]:
## [code]{"choice": CHOICE_IDS[choice]}[/code].
const OFFER_KEY: String = "camp"

## The saved name of each [enum Choice]. Never change one: saved runs are read by these names.
const CHOICE_IDS: Dictionary[Choice, String] = {
	Choice.NONE: "",
	Choice.FEAST: "feast",
	Choice.TRAIN: "train",
}

## A Feast's heal, as a share of each unit's max HP (game-vision.md; P08 question 9: halves round
## up). [b]Units:[/b] percent.
const FEAST_HEAL_PERCENT: int = 35

## [member CampaignFact.definition_id] of a Feast's heals.
const FEAST_SOURCE: String = "camp_feast"

## [member CampaignFact.definition_id] of Train's upgrade.
const TRAIN_SOURCE: String = "camp_train"

## The use kind of a consumable that can be cooked ([member ConsumableDefinition.use_kind]).
const INGREDIENT_USE_KIND: String = "ingredient"

## Pending gains a cooked ingredient adds: the next level-up only.
const COOKED_LEVEL_UPS: int = 1

const _KEY_CHOICE: String = "choice"
const _PERCENT: float = 100.0


## Whether [param run] is inside a Camp node.
static func is_at_camp(run: CampaignRunState) -> bool:
	return (
			run.flow.stage == RunFlow.Stage.NODE
			and run.graph != null and run.graph.has_node_id(run.node)
			and run.graph.type_of(run.node) == CampaignGraph.NodeType.CAMP
	)


## What [param seat_run] chose at this Camp; [constant Choice.NONE] for none yet or unusable data
## (reported).
static func choice_of(seat_run: SeatRun) -> Choice:
	if seat_run == null:
		return Choice.NONE
	var data: Variant = seat_run.pending_offers.get(OFFER_KEY, null)
	if data == null:
		return Choice.NONE
	var read: Variant = (
			CHOICE_IDS.find_key((data as Dictionary).get(_KEY_CHOICE)) if data is Dictionary
			else null
	)
	if read == null:
		push_error("Camp: seat %d's camp visit is unusable - %s" % [seat_run.seat, data])
		return Choice.NONE
	return read as Choice


## Why seat [param seat] can't make its Camp choice now: the run isn't at a Camp, no such seat, or
## it chose already. Empty when it can.
static func choice_problem(run: CampaignRunState, seat: int) -> String:
	if not is_at_camp(run):
		return "the run isn't inside a Camp"
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return "seat %d isn't in the run" % [seat]
	if choice_of(seat_run) != Choice.NONE:
		return "seat %d already chose at this Camp" % [seat]
	return ""


## The items seat [param seat] can cook: ingredients in its convoy in arrival order, then in its
## living units' Pouches in roster order.
static func ingredients(seat_run: SeatRun, catalog: EffectCatalog.Index) -> PackedStringArray:
	var found: PackedStringArray = []
	if seat_run == null:
		return found
	var places: PackedStringArray = seat_run.convoy.duplicate()
	for unit: UnitInstance in seat_run.army:
		if not unit.pouch_id.is_empty():
			places.append(unit.pouch_id)
	for item_id: String in places:
		var item: ItemInstance = seat_run.items.get(item_id, null)
		if is_ingredient(item, catalog):
			found.append(item_id)
	return found


## Whether [param item] is an ingredient ([constant INGREDIENT_USE_KIND]).
static func is_ingredient(item: ItemInstance, catalog: EffectCatalog.Index) -> bool:
	if item == null:
		return false
	var consumable: ConsumableDefinition = catalog.item(item.definition_id) as ConsumableDefinition
	return consumable != null and consumable.use_kind == INGREDIENT_USE_KIND


## Why seat [param seat] can't hold a Feast cooking [param ingredient_id] (empty: none) now: its
## choice is made ([method choice_problem]), or the item isn't an ingredient it can cook
## ([method ingredients]). Empty when it can.
static func feast_problem(
		run: CampaignRunState, seat: int, ingredient_id: String, catalog: EffectCatalog.Index
) -> String:
	var problem: String = choice_problem(run, seat)
	if not problem.is_empty() or ingredient_id.is_empty():
		return problem
	if not ingredients(run.seat_run(seat), catalog).has(ingredient_id):
		return "%s isn't an ingredient in the convoy or a living unit's Pouch" % [ingredient_id]
	return ""


## Holds seat [param seat]'s Feast, once [method feast_problem] passed: the choice is saved,
## [constant CampaignFact.Kind.FEAST_HELD] names the ingredient, which leaves the roster; each
## seat's living units heal ([constant CampaignFact.Kind.HP_CHANGED] each that gained HP); each of
## the cook's living units gains the cooked stats and Hit
## ([constant CampaignFact.Kind.UNIT_CHANGED] each).
static func feast(
		run: CampaignRunState, seat: int, ingredient_id: String, catalog: EffectCatalog.Index
) -> void:
	var seat_run: SeatRun = run.seat_run(seat)
	seat_run.pending_offers[OFFER_KEY] = {_KEY_CHOICE: CHOICE_IDS[Choice.FEAST]}
	var cooked: ConsumableDefinition = null
	var held: CampaignFact = CampaignFact.new(CampaignFact.Kind.FEAST_HELD, seat)
	if not ingredient_id.is_empty():
		var item: ItemInstance = seat_run.items[ingredient_id]
		cooked = catalog.item(item.definition_id) as ConsumableDefinition
		_remove_item(seat_run, ingredient_id)
		held.actor_id = ingredient_id
		held.definition_id = item.definition_id
	run.record(held)
	for each_seat: int in run.seat_numbers():
		var healed_run: SeatRun = run.seat_run(each_seat)
		for unit: UnitInstance in healed_run.army:
			_heal(run, healed_run, unit, catalog)
	if cooked == null:
		return
	for unit: UnitInstance in seat_run.army:
		_cook_for(run, seat, unit, cooked)


## The HP a Feast heals [param unit] of [param seat_run]: [constant FEAST_HEAL_PERCENT] of its max
## HP times its healing received, halves up, never past its max. 0 at full HP.
static func heal_amount(
		seat_run: SeatRun, unit: UnitInstance, catalog: EffectCatalog.Index
) -> int:
	var max_hp: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
	var current: int = max_hp if unit.hp == UnitInstance.FULL_HP else unit.hp
	if current >= max_hp:
		return 0
	var received: float = RunOperations.healing_received_percent(seat_run, unit, catalog)
	var heal: int = ValueBreakdown.round_to_int(
			max_hp * FEAST_HEAL_PERCENT / _PERCENT * received / _PERCENT,
			ValueBreakdown.Rounding.HALF_UP
	)
	return clampi(heal, 0, max_hp - current)


## The units of seat [param seat] Train may upgrade ([method RunOperations.upgrade_problem]), in
## roster order.
static func trainable_units(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index
) -> PackedStringArray:
	var found: PackedStringArray = []
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null:
		return found
	for unit: UnitInstance in seat_run.army:
		if RunOperations.upgrade_problem(run, seat, unit.instance_id, catalog).is_empty():
			found.append(unit.instance_id)
	return found


## Why seat [param seat] can't Train now, whatever unit it names: its choice is made, or no unit
## can be upgraded. Empty when it can.
static func train_option_problem(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index
) -> String:
	var problem: String = choice_problem(run, seat)
	if not problem.is_empty():
		return problem
	if trainable_units(run, seat, catalog).is_empty():
		return "no unit can be upgraded (the commander never is, nor a unit twice)"
	return ""


## Why seat [param seat] can't Train its unit [param unit_id] now ([method choice_problem],
## [method RunOperations.upgrade_problem]). Empty when it can.
static func train_problem(
		run: CampaignRunState, seat: int, unit_id: String, catalog: EffectCatalog.Index
) -> String:
	var problem: String = choice_problem(run, seat)
	if not problem.is_empty():
		return problem
	return RunOperations.upgrade_problem(run, seat, unit_id, catalog)


## Trains seat [param seat]'s unit [param unit_id], once [method train_problem] passed: the
## choice is saved and the unit upgraded by [constant TRAIN_SOURCE]
## ([constant CampaignFact.Kind.UNIT_UPGRADED]).
static func train(
		run: CampaignRunState, seat: int, unit_id: String, catalog: EffectCatalog.Index
) -> void:
	run.seat_run(seat).pending_offers[OFFER_KEY] = {_KEY_CHOICE: CHOICE_IDS[Choice.TRAIN]}
	RunOperations.upgrade(run, seat, unit_id, catalog, TRAIN_SOURCE)


# Heals unit by its Feast amount, recording HP_CHANGED when it gained any; full HP is kept as
# UnitInstance.FULL_HP, so a later max-HP gain keeps it full.
static func _heal(
		run: CampaignRunState, seat_run: SeatRun, unit: UnitInstance, catalog: EffectCatalog.Index
) -> void:
	var gain: int = heal_amount(seat_run, unit, catalog)
	if gain <= 0:
		return
	var max_hp: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
	unit.hp = UnitInstance.FULL_HP if unit.hp + gain >= max_hp else unit.hp + gain
	var healed: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.HP_CHANGED, seat_run.seat, unit.instance_id
	)
	healed.amount = gain
	healed.definition_id = FEAST_SOURCE
	run.record(healed)


# The cooked ingredient's gains for unit: a pending gain per cooked stat, its Hit at once.
static func _cook_for(
		run: CampaignRunState, seat: int, unit: UnitInstance, cooked: ConsumableDefinition
) -> void:
	if cooked.cooked_gains.is_empty() and cooked.cooked_hit <= 0:
		return
	for stat: CombatValue.Stat in cooked.cooked_gains:
		var gain: UnitInstance.PendingGain = UnitInstance.PendingGain.new()
		gain.stat = stat
		gain.amount = cooked.cooked_gains[stat]
		gain.remaining = COOKED_LEVEL_UPS
		gain.source_id = cooked.id
		gain.label = cooked.display_name
		unit.pending_gains.append(gain)
	if cooked.cooked_hit > 0:
		unit.stat_deltas.append(ItemInstance.StatDelta.new(
				CombatValue.Key.HIT, float(cooked.cooked_hit), cooked.id, cooked.display_name
		))
	var changed: CampaignFact = CampaignFact.new(
			CampaignFact.Kind.UNIT_CHANGED, seat, unit.instance_id
	)
	changed.amount = cooked.cooked_hit
	changed.definition_id = cooked.id
	run.record(changed)


# Takes item_id out of seat_run: the convoy, or the living unit's Pouch it sits in.
static func _remove_item(seat_run: SeatRun, item_id: String) -> void:
	var at: int = seat_run.convoy.find(item_id)
	if at >= 0:
		seat_run.convoy.remove_at(at)
	for unit: UnitInstance in seat_run.army:
		if unit.pouch_id == item_id:
			unit.pouch_id = ""
	seat_run.items.erase(item_id)
