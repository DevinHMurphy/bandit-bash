# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_grant_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ItemGrantOutcome
extends EventOutcome
## Gives an item: a named one ("gain the Cleansed Goblet"), or a random one rolled before the
## option shows ("a random rare weapon").
##
## A rare weapon or tome follows the item pick's weapon rule: of a type the army can use at the
## pick's chance, else any type, and only of Rare, so an empty pool greys the option out. A
## trinket rolls its rarity on a Standard combat's odds without the rare offset. The new item is
## placed as [member EventChoice.placements] says, through [ItemPlacement].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## The random item kinds an event gives.
enum RandomItem {
	## None: [member item_id] names the item.
	NONE = 0,
	## A Rare weapon or staff.
	RARE_WEAPON = 1,
	## A Rare magic tome: an anima, holy or dark weapon.
	RARE_TOME = 2,
	## A trinket of a rolled rarity.
	TRINKET = 3,
}

## The weapon types that make a magic tome.
const TOME_TYPES: PackedStringArray = [
	ContentIds.WEAPON_ANIMA,
	ContentIds.WEAPON_HOLY,
	ContentIds.WEAPON_DARK,
]

## Content id of the [ItemDefinition] given when [member random] is [constant RandomItem.NONE].
@export var item_id: String = ""

## The kind of random item given. [b]None:[/b] [member item_id] is given.
@export var random: RandomItem = RandomItem.NONE


func draws() -> bool:
	return random != RandomItem.NONE


func roll(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		rules: CombatRewardRules
) -> String:
	match random:
		RandomItem.RARE_WEAPON, RandomItem.RARE_TOME:
			return _roll_rare_weapon(stream, seat_run, catalog, rules)
		RandomItem.TRINKET:
			var candidates: Array[ItemDefinition] = ItemPools.items_of(
					catalog, [EffectCatalog.Kind.TRINKET]
			)
			var rarity: int = stream.pick_weighted(
					rules.rarity_table(CombatMapDefinition.CombatType.STANDARD)
			)
			var found: ItemDefinition = ItemPools.draw(stream, candidates, maxi(rarity, 0))
			return "" if found == null else found.id
	return ""


func offer_problem(ctx: EventContext, index: int) -> String:
	var picked: String = _picked(ctx, index)
	if picked.is_empty() or ctx.catalog.item(picked) == null:
		return "no item is left to give"
	return ""


func validate(ctx: EventContext, index: int) -> String:
	var problem: String = offer_problem(ctx, index)
	if not problem.is_empty():
		return problem
	return ctx.choice.placement_for(index).validate(
			ctx.seat_run(), ctx.catalog.item(_picked(ctx, index)), ctx.catalog
	)


func apply(ctx: EventContext, index: int) -> void:
	var definition: ItemDefinition = ctx.catalog.item(_picked(ctx, index))
	var item: ItemInstance = ItemInstance.new(
			ctx.ids.next_item_id(definition.display_name), definition.id
	)
	ctx.choice.placement_for(index).apply(ctx.run, ctx.seat, item, ctx.catalog)


func _picked(ctx: EventContext, index: int) -> String:
	return item_id if random == RandomItem.NONE else ctx.rolls.pick(index)


# Of Rare only: of a type the army can use at the rules' chance (any type when none fits), with
# one draw for that chance and one for the item; empty when no Rare weapon of the kind exists.
func _roll_rare_weapon(
		stream: RngStream,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		rules: CombatRewardRules
) -> String:
	var candidates: Array[ItemDefinition] = []
	for definition: ItemDefinition in ItemPick.items_for(ItemPick.Slot.WEAPON, catalog):
		var weapon: WeaponDefinition = definition as WeaponDefinition
		if random == RandomItem.RARE_WEAPON or (
				weapon != null and TOME_TYPES.has(weapon.weapon_type)
		):
			candidates.append(definition)
	var needs_usable: bool = stream.roll_percent(rules.usable_weapon_chance)
	var usable: PackedStringArray = (
			ItemPick.usable_weapon_types(seat_run, catalog) if needs_usable
			else PackedStringArray()
	)
	var pool: Array[ItemDefinition] = ItemPools.of_rarity(
			candidates, ItemDefinition.Rarity.RARE, {}, usable
	)
	if pool.is_empty() and not usable.is_empty():
		pool = ItemPools.of_rarity(candidates, ItemDefinition.Rarity.RARE)
	if pool.is_empty():
		return ""
	return pool[0 if pool.size() == 1 else stream.pick_index(pool.size())].id
