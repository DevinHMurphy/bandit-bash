# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     488_shop_panel_keywords.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## From the map: the shop panels with a choice focused by pad, their keyword tooltips in one
## column beside the panel. The Armory's deal of the Knight Shield onto the first unit, staged
## holding the Iron Shield (the comparison's DEF, Block and RES); then the Guildhall's Clarity
## rune (Hit, Attack, Phase End). Each node, its one-entry stock and the gold are staged on the
## run, then put back and the node left, so the group ends on the map as it found it.[br]
## Needs: the map, as the armory comparison shots leave it (487_armory_compare_effects).

# SceneRouter.Screen values (the script can't name the autoload; see the base).
const SCREEN_ARMORY: int = 16
const SCREEN_GUILDHALL: int = 17

# Gold staged so every choice can be taken, and so none is greyed out. Units: gold.
const STAGED_GOLD: int = 300

# The equipment compared: the one the first unit is staged holding, and the one stocked.
const HELD_ID: String = "iron_shield"
const OFFERED_ID: String = "knight_shield"

# The rune stocked.
const RUNE_ID: String = "clarity"


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the shop panel keyword shots need the map (screen %d)" % [router_screen()])
		return true
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var held: ItemDefinition = catalog.item(HELD_ID)
	if held == null or catalog.item(OFFERED_ID) == null or catalog.rune(RUNE_ID) == null:
		fail("the staged shields or rune aren't in the catalog")
		return true
	var seat_run: SeatRun = campaign().run.seat_run(0)
	var gold: int = seat_run.gold
	seat_run.gold = STAGED_GOLD
	note("shop panel keyword shots: gold at %d" % [STAGED_GOLD])
	if _stage_node(CampaignGraph.NodeType.ARMORY):
		await _armory_deal(seat_run, held)
		await _leave()
	if _stage_node(CampaignGraph.NodeType.GUILDHALL):
		await _guildhall_rune(seat_run)
		await _leave()
	seat_run.gold = gold
	return true


# The Knight Shield's deal onto the first unit, holding the Iron Shield, with the pad moved down
# one choice; then backed out and the shield put back.
func _armory_deal(seat_run: SeatRun, held: ItemDefinition) -> void:
	var session: CampaignSession = campaign()
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
	note("armory deal shot: %s held by the first unit, %s stocked" % [HELD_ID, OFFERED_ID])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_ARMORY)
	await frames(SETTLE_FRAMES)
	var cards: Array[StockCard] = (scene().call(&"get_stock_view") as StockView).get_cards()
	if cards.is_empty() or cards[0].disabled:
		note("the stocked shield can't be bought, so its deal isn't shot")
	else:
		cards[0].pressed.emit()
		await frames(SETTLE_FRAMES)
		var panel: PurchasePanel = scene().call(&"get_purchase_panel")
		panel.choose_unit(unit.instance_id)
		await frames(SETTLE_FRAMES)
		await _pad_down()
		await capture("armory_deal_pad_keywords")
		panel.step_back()
		panel.step_back()
		await frames(SETTLE_FRAMES)
	ItemPlacement.put_item(unit, slot, previous)
	seat_run.items.erase(staged_id)


# The Clarity rune's price, or its discard choice with every slot full, with the pad moved down
# one choice; then backed out.
func _guildhall_rune(seat_run: SeatRun) -> void:
	var stock: GuildhallStock = GuildhallStock.new()
	var entry: GuildhallStock.Entry = GuildhallStock.Entry.new(GuildhallStock.CATEGORY_RUNE)
	entry.definition_id = RUNE_ID
	entry.instance_id = campaign().ids.next_rune_id(RUNE_ID)
	stock.entries.append(entry)
	stock.store(campaign().run)
	var runes: Dictionary = seat_run.capture_runes()
	note("guildhall rune shot: %s stocked" % [RUNE_ID])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_GUILDHALL)
	await frames(SETTLE_FRAMES)
	var view: GuildhallStockView = scene().call(&"get_stock_view")
	var card: Button = view.card_for(0)
	if card == null or card.disabled:
		note("the stocked rune can't be bought, so its panel isn't shot")
	else:
		card.pressed.emit()
		await frames(SETTLE_FRAMES)
		await _pad_down()
		await capture("guildhall_rune_pad_keywords")
		(scene().call(&"get_panel") as GuildhallPanel).step_back()
		await frames(SETTLE_FRAMES)
	seat_run.restore_runes(runes)


# Moves focus one choice down by the pad's d-pad, as a player would, and lets it settle.
func _pad_down() -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_DPAD_DOWN
		event.pressed = is_down
		tree.root.push_input(event)
	await frames(SETTLE_FRAMES)


# Leaves the staged node for the map.
func _leave() -> void:
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)


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
