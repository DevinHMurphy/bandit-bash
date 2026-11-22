# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory_model.gd
# Author:
# Created:  November 20, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name ArmoryModel
extends RefCounted
## What the Armory's screens show, read from the run: each stock entry's name, details, price and
## refusal for its card, and the before/after rows of an item against the one it replaces
## ([ItemComparison]). Prices and refusals come from [Armory]'s rules, never worked out here; in
## co-op a refusal names the teammate it is about. Presentation only; static, never instantiated.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The name of each stock category on its row.
const CATEGORY_NAMES: Dictionary[String, String] = {
	ArmoryStock.CATEGORY_WEAPON: "Weapons",
	ArmoryStock.CATEGORY_EQUIPMENT: "Equipment",
	ArmoryStock.CATEGORY_TRINKET: "Trinket",
	ArmoryStock.CATEGORY_CONSUMABLE: "Consumables",
	ArmoryStock.CATEGORY_HEIRLOOM: "Heirlooms",
}

## A comparison cell with nothing in it: the slot is empty, or the item has no such number.
const NONE: String = "-"


## [param entry]'s name: its item's or heirloom's, or its id when the catalog lacks it.
static func entry_name(entry: ArmoryStock.Entry, catalog: EffectCatalog.Index) -> String:
	if entry.is_heirloom():
		var heirloom: HeirloomDefinition = catalog.heirloom(entry.definition_id)
		return entry.definition_id if heirloom == null else heirloom.display_name
	return CombatResultsModel.item_name(catalog.item(entry.definition_id), entry.definition_id)


## [param entry]'s details under its name: an item's rarity, kind and weapon numbers
## ([method CombatResultsModel.item_details]), or an heirloom's effect text, keywords marked for
## an [EffectText] (its tier is on its price line, [method price_text]).
static func entry_details(entry: ArmoryStock.Entry, catalog: EffectCatalog.Index) -> String:
	if not entry.is_heirloom():
		return CombatResultsModel.item_details(catalog.item(entry.definition_id))
	var heirloom: HeirloomDefinition = catalog.heirloom(entry.definition_id)
	if heirloom == null:
		return "Not in the catalog"
	return "\n".join(heirloom.describe_marked())


## Why seat [param seat] can't buy stock entry [param index] of [param run], as its card says it
## ([method Armory.entry_problem]): an entry a teammate bought reads "bought by" them, and in
## co-op every seat the rules name reads as its player. Empty when it can be bought.
static func entry_refusal(
		run: CampaignRunState, seat: int, index: int, catalog: EffectCatalog.Index
) -> String:
	var buyer: String = bought_by(run, seat, index)
	if not buyer.is_empty():
		return buyer
	var problem: String = Armory.entry_problem(run, seat, index, catalog)
	return CampaignLink.name_seats(problem) if run.seat_numbers().size() > 1 else problem


## "bought by Player 2" when a teammate of seat [param seat] bought stock entry [param index] of
## [param run]; empty when nobody did, the seat itself did, or there is no such entry.
static func bought_by(run: CampaignRunState, seat: int, index: int) -> String:
	var stock: ArmoryStock = ArmoryStock.pending(run)
	if stock == null or index < 0 or index >= stock.entries.size():
		return ""
	var entry: ArmoryStock.Entry = stock.entries[index]
	if not entry.is_sold() or entry.buyer == seat:
		return ""
	return "bought by %s" % [CampaignLink.seat_name(entry.buyer)]


## [param entry]'s icon; null for none.
static func entry_icon(entry: ArmoryStock.Entry, catalog: EffectCatalog.Index) -> Texture2D:
	if entry.is_heirloom():
		var heirloom: HeirloomDefinition = catalog.heirloom(entry.definition_id)
		return null if heirloom == null else heirloom.icon
	var item: ItemDefinition = catalog.item(entry.definition_id)
	return null if item == null else item.icon


## [param seat_run]'s price of [param entry] as its card shows it: [code]32 gold (40 listed)[/code]
## when a discount changed it, else [code]40 gold[/code]; an heirloom's tier first
## ([code]Shop, 150 gold[/code]).
static func price_text(
		seat_run: SeatRun, entry: ArmoryStock.Entry, catalog: EffectCatalog.Index
) -> String:
	var paid: int = Armory.price(seat_run, entry, catalog)
	var listed: int = Armory.list_price(entry, catalog)
	if paid == Prices.NO_PRICE:
		return "Not for sale"
	var text: String = "%d gold" % [paid]
	if paid != listed:
		text = "%d gold (%d listed)" % [paid, listed]
	var heirloom: HeirloomDefinition = (
			catalog.heirloom(entry.definition_id) if entry.is_heirloom() else null
	)
	return text if heirloom == null else "%s, %s" % [heirloom.tier.capitalize(), text]


## [param item]'s name as the Armory shows it: "Infused <name>" once modified (items.md).
static func held_name(item: ItemInstance, catalog: EffectCatalog.Index) -> String:
	if item == null:
		return NONE
	return EventScreenModel.held_item_name(item, catalog)


## The rows comparing [param current] (null: an empty slot) with the offered [param offered]: for
## weapons their numbers, a modified item's changes included, each with the change it makes; for
## other items their kind and effect text.
static func comparison_rows(
		current: ItemInstance, offered: ItemDefinition, catalog: EffectCatalog.Index
) -> Array[Row]:
	var rows: Array[Row] = []
	var held: ItemDefinition = null if current == null else catalog.item(current.definition_id)
	var held_weapon: WeaponDefinition = held as WeaponDefinition
	var new_weapon: WeaponDefinition = offered as WeaponDefinition
	if new_weapon != null:
		rows.append(_number_row("Damage", held_weapon, current, new_weapon, &"damage",
				DamageStage.Key.ATTACK))
		rows.append(_number_row("Hit", held_weapon, current, new_weapon, &"hit",
				CombatValue.Key.HIT))
		rows.append(_number_row("Crit", held_weapon, current, new_weapon, &"crit",
				CombatValue.Key.CRIT_CHANCE))
		rows.append(_number_row("Attacks", held_weapon, current, new_weapon, &"atk_x",
				CombatValue.Key.ATK_X))
		rows.append(_number_row("Range", held_weapon, current, new_weapon, &"range_max",
				CombatValue.Key.RANGE_MAX))
		var weight: Row = _number_row("Weight", held_weapon, current, new_weapon, &"weight",
				CombatValue.Key.NET_WEIGHT)
		weight.is_lower_better = true
		rows.append(weight)
		rows.append(Row.new("Type", _weapon_type(held_weapon), _weapon_type(new_weapon)))
		return rows
	rows.append(Row.new(
			"Kind", NONE if held == null else CombatResultsModel.item_details(held),
			CombatResultsModel.item_details(offered)
	))
	rows.append(Row.new(
			"Effects", NONE if held == null else _effects(held), _effects(offered)
	))
	return rows


# A numeric row: property of each weapon, the held one's deltas of key added; no change when
# either side has no weapon.
static func _number_row(
		label: String,
		held: WeaponDefinition,
		current: ItemInstance,
		offered: WeaponDefinition,
		property: StringName,
		key: int
) -> Row:
	var after: int = offered.get(property) as int
	if held == null:
		return Row.new(label, NONE, str(after))
	var before: int = (held.get(property) as int) + roundi(_delta(current, key))
	var row: Row = Row.new(label, str(before), str(after))
	row.change = after - before
	row.is_numeric = true
	return row


static func _delta(item: ItemInstance, key: int) -> float:
	var total: float = 0.0
	if item == null:
		return total
	for delta: ItemInstance.StatDelta in item.stat_deltas:
		if delta.key == key:
			total += delta.amount
	return total


static func _weapon_type(weapon: WeaponDefinition) -> String:
	if weapon == null:
		return NONE
	var profile: Variant = WeaponTriangle.Profile.find_key(weapon.profile)
	var profile_name: String = NONE if profile == null else (profile as String).capitalize()
	return "%s, %s" % [weapon.weapon_type, profile_name]


static func _effects(definition: ItemDefinition) -> String:
	var lines: PackedStringArray = definition.describe()
	return "none" if lines.is_empty() else "\n".join(lines)


## One line of a comparison: what it measures, the replaced item's value and the offer's.
class Row:
	extends RefCounted

	## What the row measures, such as [code]Damage[/code].
	var label: String = ""
	## The replaced item's value as shown; [constant ArmoryModel.NONE] for an empty slot.
	var before: String = ""
	## The offered item's value as shown.
	var after: String = ""
	## The offer's value less the replaced one's, for numeric rows with both sides.
	var change: int = 0
	## Whether [member change] means anything: a number on both sides.
	var is_numeric: bool = false
	## Whether a lower value is the better one (weight).
	var is_lower_better: bool = false

	func _init(row_label: String = "", before_text: String = "", after_text: String = "") -> void:
		label = row_label
		before = before_text
		after = after_text

	## The change as shown after the offer's value, such as [code]+2[/code]; empty for none.
	func change_text() -> String:
		if not is_numeric or change == 0:
			return ""
		return "%+d" % [change]

	## Whether the offer is better on this row; false for no change or a non-numeric row.
	func is_better() -> bool:
		if not is_numeric or change == 0:
			return false
		return change < 0 if is_lower_better else change > 0
