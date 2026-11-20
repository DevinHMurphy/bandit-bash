# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     475_armory_cards.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## From the map: an Armory's stock cards with who can use each item: a weapon's card focused,
## its wielders' icons and their names in the tooltip; an Equipment or Trinket card focused,
## "Any unit"; an heirloom's card focused, with no row. The node is staged on the run (the
## screens route by the run's stage), then left, so the group ends on the map; the staged gold is
## put back first.[br]
## Needs: the map, as the armory shots leave it (470_armory).

# SceneRouter.Screen.ARMORY (the script can't name the autoload; see the base).
const SCREEN_ARMORY: int = 16

# Gold staged so every card can be bought, and so focused. Units: gold.
const STAGED_GOLD: int = 300

# The shots, by the stock category of the card each focuses; the first card found of any.
const SHOTS: Dictionary[String, Array] = {
	"armory_cards_wielders": [ArmoryStock.CATEGORY_WEAPON],
	"armory_cards_any_unit": [ArmoryStock.CATEGORY_EQUIPMENT, ArmoryStock.CATEGORY_TRINKET],
	"armory_cards_heirloom": [ArmoryStock.CATEGORY_HEIRLOOM],
}


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the armory card shots need the map (screen %d)" % [router_screen()])
		return true
	if not _stage_node(CampaignGraph.NodeType.ARMORY):
		return true
	var seat_run: SeatRun = campaign().run.seat_run(0)
	var gold: int = seat_run.gold
	seat_run.gold = STAGED_GOLD
	note("armory card shots: the seat's gold staged at %d" % [STAGED_GOLD])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_ARMORY)
	await frames(SETTLE_FRAMES)
	for shot: String in SHOTS:
		var categories: PackedStringArray = PackedStringArray(SHOTS[shot])
		var card: StockCard = _first_card(categories)
		if card == null:
			note("no card of %s can be bought, so %s isn't shot" % [", ".join(categories), shot])
			continue
		card.grab_focus()
		await frames(SETTLE_FRAMES)
		await capture(shot)
	seat_run.gold = gold
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The first card that can be bought of an entry in one of categories; null for none.
func _first_card(categories: PackedStringArray) -> StockCard:
	var view: StockView = scene().call(&"get_stock_view")
	var stock: ArmoryStock = ArmoryStock.pending(campaign().run)
	if view == null or stock == null:
		return null
	for card: StockCard in view.get_cards():
		if categories.has(stock.entries[card.entry_index].category) and not card.disabled:
			return card
	return null


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
