# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_prefix_outcome.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name WeaponPrefixOutcome
extends EventOutcome
## Applies a weapon prefix to a chosen weapon: a Standard Sword made Heavy. Weapons never
## generate with a prefix; events are how one gets it (game-vision.md, Weapon modifications).
##
## Sets the item's [member ItemInstance.prefix_id], and [Loadout] applies the prefix's deltas in
## battle, sourced to it. The prefix must fit the weapon: its type is in
## [member WeaponPrefixDefinition.weapon_types] and, on a staff, its kind in
## [member WeaponPrefixDefinition.staff_kinds] (each list empty: any). A weapon holds one prefix,
## so one that has a prefix is refused. Records [constant CampaignFact.Kind.ITEM_MODIFIED].
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

## Content id of the [WeaponPrefixDefinition] applied.
@export var prefix_id: String = ""


func chooser() -> EventOutcome.Chooser:
	return EventOutcome.Chooser.WEAPON


func validate(ctx: EventContext, _index: int) -> String:
	var problem: String = ItemModificationOutcome.weapon_problem(ctx)
	if not problem.is_empty():
		return problem
	var prefix: WeaponPrefixDefinition = ctx.catalog.weapon_prefix(prefix_id)
	if prefix == null:
		return "weapon prefix \"%s\" isn't in the catalog" % [prefix_id]
	var item: ItemInstance = ItemModificationOutcome.chosen_weapon(ctx)
	if not item.prefix_id.is_empty():
		return "%s already has a prefix" % [item.instance_id]
	var weapon: WeaponDefinition = ctx.catalog.weapon(item.definition_id)
	if not prefix.weapon_types.is_empty() and not prefix.weapon_types.has(weapon.weapon_type):
		return "%s doesn't fit a %s" % [prefix.display_name, weapon.weapon_type]
	var staff: StaffDefinition = weapon as StaffDefinition
	if staff != null and not prefix.staff_kinds.is_empty():
		if not prefix.staff_kinds.has(staff.staff_kind):
			return "%s doesn't fit a %s staff" % [prefix.display_name, staff.staff_kind]
	return ""


func apply(ctx: EventContext, _index: int) -> void:
	var item: ItemInstance = ItemModificationOutcome.chosen_weapon(ctx)
	item.prefix_id = prefix_id
	EventOutcome.record(ctx, CampaignFact.Kind.ITEM_MODIFIED, item.instance_id)
