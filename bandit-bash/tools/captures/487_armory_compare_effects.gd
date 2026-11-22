# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     487_armory_compare_effects.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## From the map: an Armory's before/after comparison of two equipment, whose Effects row shows each
## side's effect text with its keywords coloured, at rest and with the offer's first keyword
## hovered (its tooltip beside the panel). The node, its one-entry stock, the gold and the held
## shield are staged on the run; the shield and gold are put back and the node left, so the group
## ends on the map as it found it.[br]
## Needs: the map, as the co-op shots leave it (485_coop_screens).

# SceneRouter.Screen.ARMORY (the script can't name the autoload; see the base).
const SCREEN_ARMORY: int = 16

# Gold staged so the offer can be bought, and so its deal shown. Units: gold.
const STAGED_GOLD: int = 300

# The equipment compared: the one the first unit is staged holding, and the one stocked.
const HELD_ID: String = "iron_shield"
const OFFERED_ID: String = "steel_shield"


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the armory comparison shots need the map (screen %d)" % [router_screen()])
		return true
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var held: ItemDefinition = catalog.item(HELD_ID)
	var offered: ItemDefinition = catalog.item(OFFERED_ID)
	if held == null or offered == null:
		fail("the compared equipment isn't in the catalog")
		return true
	if not _stage_node(CampaignGraph.NodeType.ARMORY):
		return true
	var session: CampaignSession = campaign()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit: UnitInstance = seat_run.army[0]
	var slot: Loadout.Slot = ItemPlacement.slot_for(held)
	var previous: String = ItemPlacement.item_in(unit, slot)
	var staged_id: String = session.ids.next_item_id(HELD_ID)
	seat_run.items[staged_id] = ItemInstance.new(staged_id, HELD_ID)
	ItemPlacement.put_item(unit, slot, staged_id)
	var stock: ArmoryStock = ArmoryStock.new()
	stock.entries.append(ArmoryStock.Entry.new(
			ArmoryStock.CATEGORY_EQUIPMENT, OFFERED_ID, session.ids.next_item_id(OFFERED_ID), false
	))
	stock.store(session.run)
	var gold: int = seat_run.gold
	seat_run.gold = STAGED_GOLD
	note("armory comparison shots: %s held by the first unit, %s stocked, gold at %d" % [
		HELD_ID, OFFERED_ID, STAGED_GOLD,
	])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_ARMORY)
	await frames(SETTLE_FRAMES)
	await _compare(unit.instance_id)
	ItemPlacement.put_item(unit, slot, previous)
	seat_run.items.erase(staged_id)
	seat_run.gold = gold
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The stocked shield's deal for unit_id shown, at rest and with a keyword hovered; then backed
# out.
func _compare(unit_id: String) -> void:
	var view: StockView = scene().call(&"get_stock_view")
	var cards: Array[StockCard] = view.get_cards()
	if cards.is_empty() or cards[0].disabled:
		note("the stocked shield can't be bought, so the comparison isn't shot")
		return
	cards[0].pressed.emit()
	await frames(SETTLE_FRAMES)
	var panel: PurchasePanel = scene().call(&"get_purchase_panel")
	panel.choose_unit(unit_id)
	await frames(SETTLE_FRAMES)
	await capture("armory_compare_effects")
	var offer_text: EffectText = _offer_effect_text(panel.get_comparison())
	var ids: PackedStringArray = (
			PackedStringArray() if offer_text == null else offer_text.get_keyword_ids()
	)
	if ids.is_empty():
		note("the offer's effect text has no keyword, so the hover isn't shot")
	else:
		offer_text.meta_hover_started.emit(ids[0])
		await frames(SETTLE_FRAMES)
		await capture("armory_compare_keyword")
		offer_text.meta_hover_ended.emit(ids[0])
	panel.step_back()
	panel.step_back()
	await frames(SETTLE_FRAMES)


# The comparison's last EffectText: the offer's side of its Effects row; null for none.
func _offer_effect_text(comparison: ItemComparison) -> EffectText:
	var found: EffectText = null
	for child: Node in comparison.get_children():
		var text: EffectText = child as EffectText
		if text != null:
			found = text
	return found


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
