# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     470_armory.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## From the map: an Armory (its stock as rolled on entry), a weapon's before/after comparison and
## deal, and a refused purchase (the convoy full, so the old weapon can only be traded in; then
## every card the seat can't afford). The node is staged on the run (the screens route by the
## run's stage), then left, so the group ends on the map.[br]
## Needs: the map, as the treasure and camp shots leave it (460_treasure_and_camp).

# SceneRouter.Screen.ARMORY (the script can't name the autoload; see the base).
const SCREEN_ARMORY: int = 16

# Gold staged for the comparison, so a weapon is affordable. Units: gold.
const STAGED_GOLD: int = 300


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the armory shots need the map (screen %d)" % [router_screen()])
		return true
	if not _stage_node(CampaignGraph.NodeType.ARMORY):
		return true
	var seat_run: SeatRun = campaign().run.seat_run(0)
	var gold: int = seat_run.gold
	seat_run.gold = STAGED_GOLD
	note("armory shots: the seat's gold staged at %d" % [STAGED_GOLD])
	await goto(SCREEN_ARMORY, "armory")
	var card: StockCard = _first_weapon_card()
	if card == null:
		note("no weapon card can be bought, so the comparison isn't shot")
	else:
		await _compare(card)
	await _refused(seat_run)
	seat_run.gold = gold
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The weapon's unit chosen and its deal shown, then backed out.
func _compare(card: StockCard) -> void:
	card.pressed.emit()
	await frames(SETTLE_FRAMES)
	var panel: PurchasePanel = scene().call(&"get_purchase_panel")
	var unit_id: String = _first_unit(panel)
	if unit_id.is_empty():
		note("no unit can take the weapon, so the comparison isn't shot")
		panel.step_back()
		return
	panel.choose_unit(unit_id)
	await frames(SETTLE_FRAMES)
	await capture("armory_compare")
	panel.step_back()
	panel.step_back()
	await frames(SETTLE_FRAMES)


# The convoy filled so a weapon's old one can only be traded in; then the gold taken away and
# the screen reopened, every card it can't afford refused with its reason.
func _refused(seat_run: SeatRun) -> void:
	var card: StockCard = _first_weapon_card()
	var added: PackedStringArray = []
	if card != null:
		var catalog: EffectCatalog.Index = EffectCatalog.index()
		var stock: ArmoryStock = ArmoryStock.pending(campaign().run)
		var definition_id: String = stock.entries[card.entry_index].definition_id
		while not ItemPlacement.is_convoy_full(seat_run, catalog):
			var item_id: String = campaign().ids.next_item_id(definition_id)
			seat_run.items[item_id] = ItemInstance.new(item_id, definition_id)
			seat_run.convoy.append(item_id)
			added.append(item_id)
		note("refused shot: the convoy filled with %d staged weapons" % [added.size()])
		card.pressed.emit()
		await frames(SETTLE_FRAMES)
		var panel: PurchasePanel = scene().call(&"get_purchase_panel")
		var unit_id: String = _first_unit(panel)
		if not unit_id.is_empty():
			panel.choose_unit(unit_id)
			await frames(SETTLE_FRAMES)
			await capture("armory_refused_convoy")
		panel.step_back()
		panel.step_back()
		await frames(SETTLE_FRAMES)
	for item_id: String in added:
		seat_run.convoy.remove_at(seat_run.convoy.find(item_id))
		seat_run.items.erase(item_id)
	seat_run.gold = 0
	note("refused shot: the seat's gold staged at 0")
	await goto(SCREEN_ARMORY, "armory_refused_gold")


# The first card of a weapon that can be bought; null for none.
func _first_weapon_card() -> StockCard:
	var view: StockView = scene().call(&"get_stock_view")
	var stock: ArmoryStock = ArmoryStock.pending(campaign().run)
	for card: StockCard in view.get_cards():
		var entry: ArmoryStock.Entry = stock.entries[card.entry_index]
		if entry.category == ArmoryStock.CATEGORY_WEAPON and not card.disabled:
			return card
	return null


# The first unit the panel's unit step offers that has a weapon to replace, else any it offers.
func _first_unit(panel: PurchasePanel) -> String:
	var run: CampaignRunState = campaign().run
	var seat_run: SeatRun = run.seat_run(0)
	var stock: ArmoryStock = ArmoryStock.pending(run)
	var definition: ItemDefinition = null
	for entry: ArmoryStock.Entry in stock.entries:
		if entry.category == ArmoryStock.CATEGORY_WEAPON and not entry.is_sold():
			definition = EffectCatalog.index().item(entry.definition_id)
			break
	var usable: PackedStringArray = Armory.usable_units(seat_run, definition, EffectCatalog.index())
	for unit_id: String in usable:
		if Armory.replaced_item(seat_run, unit_id, definition) != null:
			return unit_id
	return "" if usable.is_empty() else usable[0]


# Puts the run inside the first node of type reached from its map's floor 1, one node per floor,
# as choosing each would (the screens route by the run's stage). Returns false, with a NOTE and
# nothing changed, for a map with none.
func _stage_node(type: CampaignGraph.NodeType) -> bool:
	var run: CampaignRunState = campaign().run
	var routes: Array[PackedInt32Array] = []
	for start: int in run.graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var last: int = route[route.size() - 1]
		if run.graph.type_of(last) == type:
			run.visited = route
			run.floor_number = route.size()
			run.node = last
			run.flow.stage = RunFlow.Stage.NODE
			return true
		for child: int in run.graph.children_of(last):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			routes.append(longer)
	note("the map has no %s node to stage" % [CampaignGraph.NodeType.find_key(type)])
	return false
