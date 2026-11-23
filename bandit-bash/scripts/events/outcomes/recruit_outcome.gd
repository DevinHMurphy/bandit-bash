# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     recruit_outcome.gd
# Author:
# Created:  November 20, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name RecruitOutcome
extends EventOutcome
## A unit joins the army: "recruit a unit with a guaranteed +1 or +2 prefix, at the army's
## average level" (events.md, Mercenary Camp).
##
## Its type named or drawn evenly from the recruit pool, then its prefix, are rolled with the
## event ([method roll_recruit], saved in [EventRolls]) so the player sees the recruit first; it is
## made as the option applies ([method RecruitOffer.make]) at [member level] or the army's average,
## with its type's starting weapon and [member gear_ids]. Into a full army it replaces the living
## unit the player names, whose items are handed over ([method EventOutcome.join_problem],
## [EventHandOver]). Records [constant CampaignFact.Kind.UNIT_DISMISSED] for that, then
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


func validate(ctx: EventContext, index: int) -> String:
	if not unit_type_id.is_empty():
		var unit_type: UnitTypeDefinition = ctx.catalog.unit_type(unit_type_id)
		if unit_type == null or unit_type.is_commander:
			return "unit type \"%s\" can't be recruited" % [unit_type_id]
	if not prefix_id.is_empty() and ctx.catalog.unit_prefix(prefix_id) == null:
		return "unit prefix \"%s\" isn't in the catalog" % [prefix_id]
	var gear_problem: String = _gear_problem(ctx.catalog)
	if not gear_problem.is_empty():
		return gear_problem
	if not is_known(ctx.rolls, index) and ctx.stream == null:
		return "no stream to draw the recruit from"
	return EventOutcome.join_problem(ctx, joining(ctx, index))


func apply(ctx: EventContext, index: int) -> void:
	var joining_offer: RecruitOffer = _make(ctx, index, ctx.ids)
	if joining_offer == null:
		push_error("RecruitOutcome: %s's recruit couldn't be made" % [ctx.event_id()])
		return
	var replaced_id: String = ctx.choice.replaced_id
	if replaced_id.is_empty():
		RunOperations.recruit(ctx.run, ctx.seat, joining_offer, ctx.event_id())
		return
	var taken: PackedStringArray = EventHandOver.set_aside(
			ctx.run, ctx.seat, replaced_id, ctx.choice.hand_over, ctx.catalog
	)
	RunOperations.replace(ctx.run, ctx.seat, replaced_id, joining_offer, ctx.event_id())
	EventHandOver.hand_to(ctx.run, ctx.seat, joining_offer.unit, taken, ctx.catalog)


## The recruit as it would join [param ctx]'s army now, its items' ids from a throwaway allocator;
## null until its type and prefix are known ([method is_known]).
func joining(ctx: EventContext, index: int) -> RecruitOffer:
	if not is_known(ctx.rolls, index):
		return null
	return _make(ctx, index, InstanceIdAllocator.new())


## Rolls the recruit's random parts into [param rolls] for the block at [param index], from
## [param stream] as the event is made: its type when none is named, then its prefix by
## [member prefix_roll] when none is named. Nothing when both are fixed, or the pool is empty.
func roll_recruit(
		rolls: EventRolls, index: int, stream: RngStream, catalog: EffectCatalog.Index
) -> void:
	if not _is_drawn():
		return
	var type_id: String = unit_type_id
	if type_id.is_empty():
		var pool: PackedStringArray = RecruitOffer.pool(catalog)
		if pool.is_empty():
			return
		type_id = pool[stream.pick_index(pool.size())]
	rolls.picks[index] = type_id
	rolls.prefixes[index] = _drawn_prefix(stream, catalog)


## Whether the recruit at [param index] is known before it applies: nothing of it is drawn, or
## [param rolls] holds its roll. False only for a run saved before recruits were rolled, which
## draws it as the option applies.
func is_known(rolls: EventRolls, index: int) -> bool:
	return not _is_drawn() or rolls.picks.has(index)


## Content id of the recruit's unit type: named, or rolled into [param rolls] at [param index];
## empty while unknown.
func joining_type(rolls: EventRolls, index: int) -> String:
	return unit_type_id if not unit_type_id.is_empty() else rolls.pick(index)


## Content id of the recruit's prefix: named, none for [constant PrefixRoll.NONE], else rolled into
## [param rolls] at [param index]. [constant UnitPrefixDefinition.NO_PREFIX] for none.
func joining_prefix(rolls: EventRolls, index: int) -> String:
	if not prefix_id.is_empty():
		return prefix_id
	if prefix_roll == PrefixRoll.NONE:
		return UnitPrefixDefinition.NO_PREFIX
	return rolls.prefix(index)


# Whether the type or the prefix is drawn at random.
func _is_drawn() -> bool:
	return unit_type_id.is_empty() or (prefix_id.is_empty() and prefix_roll != PrefixRoll.NONE)


# A prefix drawn from stream by prefix_roll, or the named one.
func _drawn_prefix(stream: RngStream, catalog: EffectCatalog.Index) -> String:
	if not prefix_id.is_empty():
		return prefix_id
	match prefix_roll:
		PrefixRoll.ELITE:
			return UnitPrefixDefinition.roll_elite(stream, catalog)
		PrefixRoll.RANDOM:
			return UnitPrefixDefinition.roll(stream, catalog)
	return UnitPrefixDefinition.NO_PREFIX


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


# The recruit, at the level the army stands at before any unit leaves, its ids from allocator:
# its rolled type and prefix, or, for a run saved before recruits were rolled, the type and then
# the prefix drawn from ctx's stream now.
func _make(ctx: EventContext, index: int, allocator: InstanceIdAllocator) -> RecruitOffer:
	var type_id: String = joining_type(ctx.rolls, index)
	var chosen_prefix: String = joining_prefix(ctx.rolls, index)
	if not is_known(ctx.rolls, index):
		type_id = unit_type_id
		if type_id.is_empty():
			var pool: PackedStringArray = RecruitOffer.pool(ctx.catalog)
			type_id = pool[ctx.stream.pick_index(pool.size())]
		chosen_prefix = _drawn_prefix(ctx.stream, ctx.catalog)
	var joins_at: int = level if level > 0 else RecruitOffer.level_for(ctx.seat_run())
	var made: RecruitOffer = RecruitOffer.make(
			ctx.catalog, type_id, chosen_prefix, joins_at, allocator
	)
	if made == null:
		return null
	for item_id: String in gear_ids:
		var definition: ItemDefinition = ctx.catalog.item(item_id)
		var item: ItemInstance = ItemInstance.new(
				allocator.next_item_id(definition.display_name), definition.id
		)
		made.items[item.instance_id] = item
		ItemPlacement.put_item(made.unit, ItemPlacement.slot_for(definition), item.instance_id)
	return made
