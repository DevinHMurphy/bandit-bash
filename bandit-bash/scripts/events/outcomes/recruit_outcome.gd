# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     recruit_outcome.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name RecruitOutcome
extends EventOutcome
## A unit joins the army: "recruit a unit with a guaranteed +1 or +2 prefix, at the army's
## average level" (events.md, Mercenary Camp).
##
## Made as the option applies ([method RecruitOffer.make]): its type named or drawn evenly from the
## recruit pool, then its prefix, from the seat's [code]EVENT_OUTCOME[/code] stream; at
## [member level] or the army's average; with its type's starting weapon and [member gear_ids].
## Recruiting rules hold: into a full army it replaces the living unit the player names
## ([method EventOutcome.join_problem], [method RunOperations.replace]). Records
## [constant CampaignFact.Kind.UNIT_DISMISSED] for that, then
## [constant CampaignFact.Kind.UNIT_RECRUITED].
##
## @tutorial(Events): docs/design/events.md

## How the recruit's prefix is chosen when [member prefix_id] is empty.
enum PrefixRoll {
	## No prefix ("Take a Volunteer").
	NONE = 0,
	## A +1 or +2 prefix, by their odds ([method UnitPrefixDefinition.roll_elite]; "Hire the Best").
	ELITE = 1,
	## The normal recruit odds, which can come out negative ([method UnitPrefixDefinition.roll]).
	RANDOM = 2,
}

## Content id of the recruit's unit type, never a commander's. [b]Empty:[/b] drawn evenly from
## every unit type a recruit can be ([method RecruitOffer.pool]).
@export var unit_type_id: String = ""

## How the prefix is chosen when [member prefix_id] is empty.
@export var prefix_roll: PrefixRoll = PrefixRoll.NONE

## Content id of the recruit's [UnitPrefixDefinition]. [b]Empty:[/b] by [member prefix_roll].
@export var prefix_id: String = ""

## The level it joins at.[br]
## [b]Units:[/b] levels. [b]0:[/b] the army's average, rounded down, as every recruit joins
## ([method RecruitOffer.level_for]).
@export_range(0, 10, 1, "or_greater") var level: int = 0

## Content ids of the items it brings besides its type's starting weapon: at most one Equipment
## item and one trinket or consumable for the Pouch, never a weapon. [b]Empty:[/b] the starting
## weapon only.
@export var gear_ids: PackedStringArray = []


func offer_problem(ctx: EventContext, _index: int) -> String:
	if unit_type_id.is_empty() and RecruitOffer.pool(ctx.catalog).is_empty():
		return "no unit is left to recruit"
	return ""


func validate(ctx: EventContext, _index: int) -> String:
	if not unit_type_id.is_empty():
		var unit_type: UnitTypeDefinition = ctx.catalog.unit_type(unit_type_id)
		if unit_type == null or unit_type.is_commander:
			return "unit type \"%s\" can't be recruited" % [unit_type_id]
	if not prefix_id.is_empty() and ctx.catalog.unit_prefix(prefix_id) == null:
		return "unit prefix \"%s\" isn't in the catalog" % [prefix_id]
	var gear_problem: String = _gear_problem(ctx.catalog)
	if not gear_problem.is_empty():
		return gear_problem
	if _draws_at_apply() and ctx.stream == null:
		return "no stream to draw the recruit from"
	return EventOutcome.join_problem(ctx)


func apply(ctx: EventContext, _index: int) -> void:
	var joining: RecruitOffer = _make(ctx)
	if joining == null:
		push_error("RecruitOutcome: %s's recruit couldn't be made" % [ctx.event_id()])
		return
	var replaced_id: String = ctx.choice.replaced_id
	if replaced_id.is_empty():
		RunOperations.recruit(ctx.run, ctx.seat, joining, ctx.event_id())
	else:
		RunOperations.replace(ctx.run, ctx.seat, replaced_id, joining, ctx.event_id())


# Whether the type or the prefix is drawn as the option applies.
func _draws_at_apply() -> bool:
	return unit_type_id.is_empty() or (prefix_id.is_empty() and prefix_roll != PrefixRoll.NONE)


# Why gear_ids can't go on a recruit: an unknown item, a weapon, or two for one slot.
func _gear_problem(catalog: EffectCatalog.Index) -> String:
	var slots: Dictionary[Loadout.Slot, bool] = {}
	for item_id: String in gear_ids:
		var definition: ItemDefinition = catalog.item(item_id)
		if definition == null:
			return "item \"%s\" isn't in the catalog" % [item_id]
		var slot: Loadout.Slot = ItemPlacement.slot_for(definition)
		if slot == Loadout.Slot.WEAPON:
			return "a recruit's weapon is its type's own, not %s" % [item_id]
		if slots.has(slot):
			return "a recruit has one slot for %s" % [item_id]
		slots[slot] = true
	return ""


# The recruit, at the level the army stands at before any unit leaves; the type, then the prefix,
# drawn from ctx's stream when not named.
func _make(ctx: EventContext) -> RecruitOffer:
	var type_id: String = unit_type_id
	# Drawn as the option applies, so not shown before choosing (the events section
	# keeps one id per block, and a type with its prefix needs two).
	if type_id.is_empty():
		var pool: PackedStringArray = RecruitOffer.pool(ctx.catalog)
		type_id = pool[ctx.stream.pick_index(pool.size())]
	var chosen_prefix: String = prefix_id
	if chosen_prefix.is_empty():
		match prefix_roll:
			PrefixRoll.ELITE:
				chosen_prefix = UnitPrefixDefinition.roll_elite(ctx.stream, ctx.catalog)
			PrefixRoll.RANDOM:
				chosen_prefix = UnitPrefixDefinition.roll(ctx.stream, ctx.catalog)
	var joins_at: int = level if level > 0 else RecruitOffer.level_for(ctx.seat_run())
	var made: RecruitOffer = RecruitOffer.make(
			ctx.catalog, type_id, chosen_prefix, joins_at, ctx.ids
	)
	if made == null:
		return null
	for item_id: String in gear_ids:
		var definition: ItemDefinition = ctx.catalog.item(item_id)
		var item: ItemInstance = ItemInstance.new(
				ctx.ids.next_item_id(definition.display_name), definition.id
		)
		made.items[item.instance_id] = item
		ItemPlacement.put_item(made.unit, ItemPlacement.slot_for(definition), item.instance_id)
	return made
