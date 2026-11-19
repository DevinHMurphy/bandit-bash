# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_modification_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemModificationOutcome
extends EventOutcome
## Modifies a chosen weapon: "gains 'Hit dealt: heal 2' and +2 weight", "+1 AtkX and +4 weight".
##
## Adds granted effects and sourced stat deltas to the item's instance, never to its definition,
## so it shows as "Infused <name>" with what changed, and its price and scrap value follow
## (items.md, Modified items). The weapon is a weapon or staff on a living unit or in the convoy.
## Records [constant CampaignFact.Kind.ITEM_MODIFIED].
##
## @tutorial(Items, Modified items): docs/design/items.md

## Content ids of standalone catalog effects the weapon gains, such as "Hit dealt: heal 2".
## [b]Empty:[/b] none.
@export var effect_ids: PackedStringArray = []

## Changes to the weapon's numbers, by [CombatValue] or [DamageStage] key, such as
## [constant CombatValue.Key.NET_WEIGHT] +2.[br]
## [b]Units:[/b] the key's own. [b]Empty:[/b] none.
@export var stat_deltas: Dictionary[int, float] = {}


func chooser() -> EventOutcome.Chooser:
	return EventOutcome.Chooser.WEAPON


func validate(ctx: EventContext, _index: int) -> String:
	var problem: String = weapon_problem(ctx)
	if not problem.is_empty():
		return problem
	for effect_id: String in effect_ids:
		if ctx.catalog.effect(effect_id) == null:
			return "effect \"%s\" isn't in the catalog" % [effect_id]
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	var item: ItemInstance = chosen_weapon(ctx)
	item.granted_effect_ids.append_array(effect_ids)
	for key: int in stat_deltas:
		item.stat_deltas.append(ItemInstance.StatDelta.new(
				key, stat_deltas[key], ctx.event_id(), ctx.label()
		))
	EventOutcome.record(ctx, CampaignFact.Kind.ITEM_MODIFIED, item.instance_id)


## The weapon [member EventChoice.weapon_id] names when the seat may modify it: a weapon or staff
## on a living unit or in the convoy, never a fallen unit's. Null otherwise.
static func chosen_weapon(ctx: EventContext) -> ItemInstance:
	var seat_run: SeatRun = ctx.seat_run()
	var item: ItemInstance = seat_run.items.get(ctx.choice.weapon_id, null)
	if item == null or not ctx.catalog.item(item.definition_id) is WeaponDefinition:
		return null
	if seat_run.convoy.has(item.instance_id):
		return item
	for unit: UnitInstance in seat_run.army:
		if unit.item_ids().has(item.instance_id):
			return item
	return null


## Why [method chosen_weapon] finds no weapon; empty when it finds one.
static func weapon_problem(ctx: EventContext) -> String:
	if ctx.choice.weapon_id.is_empty():
		return "choose a weapon"
	if chosen_weapon(ctx) == null:
		return "%s isn't a weapon held by a living unit or in the convoy" % [ctx.choice.weapon_id]
	return ""
