# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     489_coop_battle.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## A co-op host's battle screen in a 2-seat run, on the host's own map: the swap window, then the
## battle started with the cursor on the host's first unit. A seeded 2-seat session stands in for
## the solo run in CampaignService, as 485's does; its first Standard combat is entered and begun
## on the session itself, which saves nothing, so the screen shows it as a battle already on (its
## event log opens "Battle resumed"). The solo session then comes back and the group ends on the
## map, as it found it, so 500 starts where 488 left it.[br]
## Needs: the map, as the shop panel shots leave it (488_shop_panel_keywords).

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const FACTION: String = "mercenary"

# The teammate's seat.
const TEAMMATE: int = 1


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op battle shots need the map (screen %d)" % [router_screen()])
		return true
	var solo: CampaignSession = campaign()
	var coop: CampaignSession = _new_coop()
	if coop == null or not _enter_standard(coop.run):
		fail("the 2-seat run couldn't reach a Standard combat")
		return true
	var request: CampaignSession.BattleRequest = coop.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null or coop.begin_battle(request) == null:
		fail("the 2-seat battle couldn't begin")
		coop.close()
		return true
	node(^"CampaignService").set(&"session", coop)
	note("co-op battle shots: a 2-seat run seeded %X, its battle begun unsaved, for the host" % [
		RUN_SEED,
	])
	await goto(SCREEN_GAMEPLAY, "coop_battle_swap_window")
	var view: BattleView = battle_view()
	var controller: BattleController = battle_controller()
	controller.request_start()
	settle(view)
	await frames(SETTLE_FRAMES)
	var session: CombatSession = view.get_session()
	controller.move_cursor(session.state.tile_of(first_player(session)))
	await frames(SETTLE_FRAMES)
	await capture("coop_battle_hud")
	node(^"CampaignService").set(&"session", solo)
	coop.close()
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# A new 2-seat run on RUN_SEED, as CampaignService builds one, with no starting offer left open.
func _new_coop() -> CampaignSession:
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, TEAMMATE])
	)
	var factions: Dictionary[int, String] = {0: FACTION, TEAMMATE: FACTION}
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids,
			made.starting_offer_streams()
	)
	if start.run == null:
		return null
	made.run = start.run
	for seat: int in made.seats:
		made.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	return made


# Puts run inside the first Standard combat reached from floor 1, breadth first, as choosing each
# node on the way would. False when the map has none.
func _enter_standard(run: CampaignRunState) -> bool:
	var routes: Array[PackedInt32Array] = []
	for start: int in run.graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var last: int = route[route.size() - 1]
		if run.graph.type_of(last) == CampaignGraph.NodeType.STANDARD:
			run.visited = route
			run.floor_number = route.size()
			run.node = last
			run.flow.stage = RunFlow.Stage.NODE
			return true
		for child: int in run.graph.children_of(last):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			routes.append(longer)
	return false
