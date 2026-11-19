# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RuneOutcome
extends EventOutcome
## Gives a rune: a named one, or a random one rolled evenly before the option shows.
##
## It goes into the first empty rune slot. With every slot full the option is still offered, so
## runes stay worth spending: the player names a slot to empty
## ([member EventChoice.rune_discard_slot]), and that rune is discarded
## ([constant CampaignFact.Kind.RUNE_DISCARDED]). Records [constant CampaignFact.Kind.GAINED].
##
## @tutorial(Items, Runes): docs/design/items.md

## Content id of the [RuneDefinition] given when [member is_random] is false.
@export var rune_id: String = ""

## Whether the rune is drawn evenly from every rune instead of [member rune_id].
@export var is_random: bool = false


func draws() -> bool:
	return is_random


func roll(
		stream: RngStream,
		_seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		_rules: CombatRewardRules
) -> String:
	if not is_random:
		return ""
	var found: RuneDefinition = ItemPools.draw_rune(stream, catalog)
	return "" if found == null else found.id


func offer_problem(ctx: EventContext, index: int) -> String:
	var picked: String = _picked(ctx, index)
	if picked.is_empty() or ctx.catalog.rune(picked) == null:
		return "no rune is left to give"
	return ""


func validate(ctx: EventContext, index: int) -> String:
	var problem: String = offer_problem(ctx, index)
	if not problem.is_empty():
		return problem
	var discard: int = ctx.choice.rune_discard_slot
	var is_full: bool = _empty_slot(ctx.seat_run()) < 0
	if is_full and (discard < 0 or discard >= SeatRun.RUNE_SLOT_COUNT):
		return "every rune slot is full, so one rune must be discarded"
	if not is_full and discard != EventChoice.NO_SLOT:
		return "a rune slot is free, so nothing is discarded"
	return ""


func apply(ctx: EventContext, index: int) -> void:
	var seat_run: SeatRun = ctx.seat_run()
	var slot: int = _empty_slot(seat_run)
	if slot < 0:
		slot = ctx.choice.rune_discard_slot
		var old: SeatRun.RuneSlot = seat_run.rune_slots[slot]
		var discarded: CampaignFact = CampaignFact.new(
				CampaignFact.Kind.RUNE_DISCARDED, ctx.seat, old.instance_id
		)
		discarded.definition_id = old.definition_id
		discarded.amount = slot
		ctx.run.record(discarded)
	var definition_id: String = _picked(ctx, index)
	var instance_id: String = ctx.ids.next_rune_id(definition_id)
	seat_run.rune_slots[slot] = SeatRun.RuneSlot.new(instance_id, definition_id)
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, ctx.seat, instance_id)
	gained.definition_id = definition_id
	ctx.run.record(gained)


func _picked(ctx: EventContext, index: int) -> String:
	return ctx.rolls.pick(index) if is_random else rune_id


static func _empty_slot(seat_run: SeatRun) -> int:
	for index: int in seat_run.rune_slots.size():
		if seat_run.rune_slots[index].is_empty():
			return index
	return -1
