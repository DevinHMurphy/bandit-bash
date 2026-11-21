# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     415_effect_text.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The effect text step's shots: the unit detail pop-up of a Shaman holding Life Tap (a lifesteal
## weapon), its Weapon row showing the profile and the weapon's effect line, drawn over the map on
## a battle built for it alone; then an Armory, staged on the run, with an Equipment card and a
## Consumable card focused, each showing its effect lines. The node is left, then the staged
## gold and the run's route put back, so the group ends on the map as it found it.[br]
## Needs: the map (400_victory leaves it there; 405_reward_cards puts it back). Runs before 450.

const DETAIL_SCENE: PackedScene = preload("res://ui/battle/unit/unit_detail_panel.tscn")

# SceneRouter.Screen.ARMORY (the script can't name the autoload; see the base).
const SCREEN_ARMORY: int = 16

# The unit and its lifesteal weapon.
const UNIT_TYPE: String = "shaman"
const WEAPON_ID: String = "life_tap"

# Any fixed seed: the shot's battle rolls nothing.
const BATTLE_SEED: int = 0x415

# Gold staged so every card can be bought, and so focused, as 475_armory_cards stages it.
# Units: gold.
const STAGED_GOLD: int = 300

# The Armory shots, by the stock category of the card each focuses.
const SHOTS: Dictionary[String, String] = {
	"effect_text_armory_equipment": ArmoryStock.CATEGORY_EQUIPMENT,
	"effect_text_armory_consumable": ArmoryStock.CATEGORY_CONSUMABLE,
}


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the effect text shots need the map (screen %d)" % [router_screen()])
		return true
	await _unit_detail()
	await _armory()
	return true


# The pop-up for a lone Shaman holding Life Tap, over the map, then removed.
func _unit_detail() -> void:
	var session: CombatSession = _battle()
	var unit_id: String = "" if session == null else first_player(session)
	var view: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
	if view == null:
		fail("the %s holding %s didn't load" % [UNIT_TYPE, WEAPON_ID])
		return
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	tree.root.add_child(panel)
	panel.show_detail(view)
	await frames(SETTLE_FRAMES)
	await capture("effect_text_unit_detail")
	panel.free()
	await frames(SETTLE_FRAMES)


# An Armory staged on the run, an Equipment then a Consumable card focused; then left.
func _armory() -> void:
	var run_state: CampaignRunState = campaign().run
	var visited: PackedInt32Array = run_state.visited.duplicate()
	var floor_number: int = run_state.floor_number
	var at_node: int = run_state.node
	if not _stage_armory():
		return
	var seat_run: SeatRun = run_state.seat_run(0)
	var gold: int = seat_run.gold
	seat_run.gold = STAGED_GOLD
	note("effect text shots: the seat's gold staged at %d" % [STAGED_GOLD])
	node(^"SceneRouter").call(&"goto_screen", SCREEN_ARMORY)
	await frames(SETTLE_FRAMES)
	for shot: String in SHOTS:
		var card: StockCard = _first_card(SHOTS[shot])
		if card == null:
			note("no %s card can be bought, so %s isn't shot" % [SHOTS[shot], shot])
			continue
		card.grab_focus()
		await frames(SETTLE_FRAMES)
		await capture(shot)
	seat_run.gold = gold
	node(^"CampaignService").call(&"submit_command", LeaveNodeCommand.new(0))
	run_state.visited = visited
	run_state.floor_number = floor_number
	run_state.node = at_node
	run_state.flow.stage = RunFlow.Stage.MAP
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)


# A battle of one plain row holding only the Shaman with Life Tap; null when it didn't load.
func _battle() -> CombatSession:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "effect_text_capture"
	var plain: MapLayout.Terrain = MapLayout.Terrain.from_definition(
			MapLoader.load_terrain("plain")
	)
	layout.set_terrain(Vector2i.ZERO, plain)
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = CombatSession.new(
			0, PackedInt32Array([0]), MapGrid.new(layout),
			LiveRolls.new(RngStream.new(BATTLE_SEED)), ids
	)
	var weapon: WeaponDefinition = catalog.weapon(WEAPON_ID)
	var unit_type: UnitTypeDefinition = catalog.unit_type(UNIT_TYPE)
	if weapon == null or unit_type == null:
		return null
	var unit: UnitInstance = UnitInstance.new(ids.next_unit_id(unit_type.display_name), UNIT_TYPE)
	var item: ItemInstance = ItemInstance.new(ids.next_item_id(weapon.display_name), WEAPON_ID)
	var items: Dictionary[String, ItemInstance] = {item.instance_id: item}
	unit.weapon_id = item.instance_id
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			catalog, unit, items, CombatFact.CombatSide.PLAYER, 0, ids
	)
	if not loaded.is_loaded():
		return null
	for record: CombatState.WeaponStats in loaded.weapons:
		session.state.add_weapon(record)
	for instance: EffectInstance in loaded.effects:
		session.engine.register(instance)
	loaded.state.tile = Vector2i.ZERO
	return session if session.add_unit(loaded.state, loaded.bases) else null


# The first card of category that can be bought; null for none.
func _first_card(category: String) -> StockCard:
	var view: StockView = scene().call(&"get_stock_view")
	var stock: ArmoryStock = ArmoryStock.pending(campaign().run)
	if view == null or stock == null:
		return null
	for card: StockCard in view.get_cards():
		if stock.entries[card.entry_index].category == category and not card.disabled:
			return card
	return null


# Puts the run inside the first Armory reached from its map's floor 1, one node per floor, as
# choosing each would. Returns false, with a NOTE and nothing changed, for a map with none.
func _stage_armory() -> bool:
	var run_state: CampaignRunState = campaign().run
	var routes: Array[PackedInt32Array] = []
	for start: int in run_state.graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var last: int = route[route.size() - 1]
		if run_state.graph.type_of(last) == CampaignGraph.NodeType.ARMORY:
			run_state.visited = route
			run_state.floor_number = route.size()
			run_state.node = last
			run_state.flow.stage = RunFlow.Stage.NODE
			return true
		for child: int in run_state.graph.children_of(last):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			routes.append(longer)
	note("the map has no Armory node to stage")
	return false
