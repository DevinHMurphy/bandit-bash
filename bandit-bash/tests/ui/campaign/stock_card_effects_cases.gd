# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stock_card_effects_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Armory stock card's effect lines for the ui/campaign suite (RF-037): an Equipment card
## (the Iron Shield) and a Consumable card (the Brawn Prawn) show the same effect lines as an
## [ItemOfferCard] of the same item, between the details and the price; the same card shown
## again as an heirloom entry, with no item, shows none. Cards are built from their scenes on the
## root viewport and shown as [StockView] shows an entry, [method StockCard.show_entry] then
## [method StockCard.show_users].

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

const STOCK_CARD_SCENE: PackedScene = preload("res://ui/campaign/stock_card.tscn")
const OFFER_CARD_SCENE: PackedScene = preload("res://ui/campaign/item_offer_card.tscn")

# The items shown, by stock category.
const ITEMS: Dictionary[String, String] = {
	ArmoryStock.CATEGORY_EQUIPMENT: "iron_shield",
	ArmoryStock.CATEGORY_CONSUMABLE: "brawn_prawn",
}

const PRICE: String = "40 gold"

var _check: Callable
var _root: Window = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the cards are added.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	for category: String in ITEMS:
		_test_item(category, ITEMS[category])


func _test_item(category: String, item_id: String) -> void:
	var item: ItemDefinition = _catalog.item(item_id)
	if item == null:
		_check.call("stock card %s: in the catalog" % [item_id], false, "")
		return
	var card: StockCard = STOCK_CARD_SCENE.instantiate()
	var offer: ItemOfferCard = OFFER_CARD_SCENE.instantiate()
	_root.add_child(card)
	_root.add_child(offer)
	var details: String = CombatResultsModel.item_details(item)
	card.show_entry(0, item.display_name, details, PRICE, item.icon, "")
	card.show_users(item, null, _catalog)
	offer.show_item(item, item_id)
	var effects: PackedStringArray = item.describe()
	var expected: PackedStringArray = [item.display_name]
	expected.append_array(details.split("\n"))
	expected.append_array(effects)
	expected.append(PRICE)
	var offer_lines: PackedStringArray = offer.get_lines()
	_check.call("stock card %s (%s): its effect lines, as on the offer card" % [
		item_id, category,
	], (
			not effects.is_empty()
			and card.get_lines() == expected
			and offer_lines.slice(offer_lines.size() - effects.size()) == effects
	), "card %s; offer %s" % [str(card.get_lines()), str(offer_lines)])

	card.show_entry(1, "Burglar's Roll", "An heirloom's text", PRICE, null, "")
	_check.call("stock card %s: shown again as an heirloom, no item lines" % [item_id], (
			card.get_lines() == PackedStringArray(["Burglar's Roll", "An heirloom's text", PRICE])
	), str(card.get_lines()))
	card.free()
	offer.free()
