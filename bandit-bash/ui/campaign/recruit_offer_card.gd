# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     recruit_offer_card.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name RecruitOfferCard
extends Button
## One unit on offer to recruit: a pressable card with its full preview (unit-roster.md,
## Recruiting): its name with its prefix and the prefix's tier, its level, trait, stats and the
## weapon it brings.
##
## The stats are [method UnitInstance.stats], so they are what the unit joins with. Pressing it
## (click, or accept while focused) asks to recruit it; [StartingOfferView] passes that on. It
## reads no input action itself.

## Stats the preview lists, in order, each with its short name.
const SHOWN_STATS: Dictionary[int, String] = {
	CombatValue.Key.HP: "HP",
	CombatValue.Key.MGT: "MGT",
	CombatValue.Key.SPD: "SPD",
	CombatValue.Key.DEF: "DEF",
	CombatValue.Key.RES: "RES",
	CombatValue.Key.MOVEMENT: "MOV",
}

## The card's width and least height, so three sit in a row at 1280×720 with room to spare.[br]
## [b]Units:[/b] base units. [b]0:[/b] sized by its text alone.
@export var card_size: Vector2 = Vector2(300.0, 160.0):
	set(value):
		card_size = value
		if not is_node_ready():
			return
		custom_minimum_size = card_size

## The unit's name as shown, by [method show_recruit]; empty before it.
var unit_title: String = ""


func _ready() -> void:
	custom_minimum_size = card_size


## Shows [param offer]'s unit and gear, read from [param catalog].
func show_recruit(offer: RecruitOffer, catalog: EffectCatalog.Index) -> void:
	var unit: UnitInstance = offer.unit
	unit_title = title_of(unit, catalog)
	var unit_type: UnitTypeDefinition = unit.definition(catalog)
	var sheet: StatSheet = unit.stats(catalog)
	var stats: PackedStringArray = []
	for key: int in SHOWN_STATS:
		stats.append("%s %d" % [SHOWN_STATS[key], sheet.get_int(key)])
	var weapon: ItemInstance = offer.items.get(unit.weapon_id, null)
	var weapon_name: String = "no weapon"
	if weapon != null:
		weapon_name = CombatResultsModel.item_name(
				catalog.item(weapon.definition_id), weapon.definition_id
		)
	var lines: PackedStringArray = [
		"%s · level %d" % [unit_title, unit.level],
		"Trait: %s" % ["—" if unit_type == null else unit_type.trait_name],
		" · ".join(stats),
		"Brings %s" % [weapon_name],
	]
	text = "\n".join(lines)


## [param unit]'s name as the roster shows it: its prefix with its tier, its type, and "+" once
## upgraded, such as "Swift (+1) Lancer" or "Archer+".
static func title_of(unit: UnitInstance, catalog: EffectCatalog.Index) -> String:
	var unit_type: UnitTypeDefinition = unit.definition(catalog)
	var type_name: String = unit.unit_type_id if unit_type == null else unit_type.display_name
	if unit.is_upgraded and unit_type != null and not unit_type.is_commander:
		type_name += "+"
	var prefix: UnitPrefixDefinition = (
			null if unit.prefix_id.is_empty() else catalog.unit_prefix(unit.prefix_id)
	)
	if prefix == null:
		return type_name
	return "%s (%+d) %s" % [prefix.display_name, prefix.tier, type_name]
