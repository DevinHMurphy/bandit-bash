# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     480_guildhall.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## From the map: a Guildhall (its stock as rolled on entry), a full army's recruit (the unit to
## replace, then the hand-over at Best fit), a rune with every slot full (the discard choice), the
## re-roll list, and every card the seat can't afford. The node is staged on the run (the screens
## route by the run's stage), then left, so the group ends on the map; staged gold and runes are
## put back first.[br]
## Needs: the map, as the armory shots leave it (470_armory).

# SceneRouter.Screen.GUILDHALL (the script can't name the autoload; see the base).
const SCREEN_GUILDHALL: int = 17

# Gold staged so every card can be bought. Units: gold.
const STAGED_GOLD: int = 300

# The rune staged into empty slots for the discard shot.
const STAGED_RUNE: String = "mend"


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the guildhall shots need the map (screen %d)" % [router_screen()])
		return true
	if not _stage_node(CampaignGraph.NodeType.GUILDHALL):
		return true
	var seat_run: SeatRun = campaign().run.seat_run(0)
	var gold: int = seat_run.gold
	var runes: Dictionary = seat_run.capture_runes()
	seat_run.gold = STAGED_GOLD
	note("guildhall shots: the seat's gold staged at %d" % [STAGED_GOLD])
	await goto(SCREEN_GUILDHALL, "guildhall")
	await _replace()
	await _rune_discard(seat_run)
	await _reroll()
	seat_run.gold = 0
	note("refused shot: the seat's gold staged at 0")
	await goto(SCREEN_GUILDHALL, "guildhall_refused_gold")
	seat_run.gold = gold
	seat_run.restore_runes(runes)
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# The first recruit's card pressed: with the army full, the unit to replace, then the hand-over
# for the first unit that can leave; backed out.
func _replace() -> void:
	var view: GuildhallStockView = scene().call(&"get_stock_view")
	var panel: GuildhallPanel = scene().call(&"get_panel")
	var stock: GuildhallStock = GuildhallStock.pending(campaign().run)
	var indexes: PackedInt32Array = stock.indexes_of(GuildhallStock.CATEGORY_RECRUIT)
	if indexes.is_empty():
		note("no recruit is stocked, so the hand-over isn't shot")
		return
	view.card_for(indexes[0]).pressed.emit()
	await frames(SETTLE_FRAMES)
	if panel.get_step() != GuildhallPanel.Step.REPLACE:
		note("the army has room, so the replacement isn't shot")
		panel.step_back()
		return
	await capture("guildhall_replace")
	var leaving: PackedStringArray = Guildhall.replaceable_units(campaign().run.seat_run(0))
	if leaving.is_empty():
		panel.step_back()
		return
	panel.choose_replaced(leaving[0])
	await frames(SETTLE_FRAMES)
	await capture("guildhall_hand_over")
	panel.step_back()
	panel.step_back()
	await frames(SETTLE_FRAMES)


# Every rune slot filled, then the first rune's card pressed: the discard choice; backed out.
func _rune_discard(seat_run: SeatRun) -> void:
	var stock: GuildhallStock = GuildhallStock.pending(campaign().run)
	var indexes: PackedInt32Array = stock.indexes_of(GuildhallStock.CATEGORY_RUNE)
	if indexes.is_empty():
		note("no rune is stocked, so the discard isn't shot")
		return
	for slot: int in SeatRun.RUNE_SLOT_COUNT:
		if seat_run.rune_slots[slot].is_empty():
			seat_run.rune_slots[slot] = SeatRun.RuneSlot.new(
					campaign().ids.next_rune_id(STAGED_RUNE), STAGED_RUNE
			)
	note("discard shot: every rune slot staged full")
	var view: GuildhallStockView = scene().call(&"get_stock_view")
	var panel: GuildhallPanel = scene().call(&"get_panel")
	view.card_for(indexes[0]).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("guildhall_rune_discard")
	panel.step_back()
	await frames(SETTLE_FRAMES)


# Re-roll pressed: each living unit with its price, the commander refused; backed out.
func _reroll() -> void:
	var panel: GuildhallPanel = scene().call(&"get_panel")
	(scene().call(&"get_reroll_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("guildhall_reroll")
	panel.step_back()
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
