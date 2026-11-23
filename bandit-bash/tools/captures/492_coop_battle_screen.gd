# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     492_coop_battle_screen.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The co-op battle screen's parts ([CoopBattle]), each on a seeded co-op session standing in for
## the solo run in CampaignService, begun on the session itself, which saves nothing, as 489's co-op
## battle does: the maps panel with the host's call for aid up; a teammate's map spectated; after
## the host's win the send panel, its question and the wait; a 4-seat battle's frozen map and the
## send panel's rule; a lost run's banner; a swap visitor's opening move on the partner's map; and
## a seat whose map was lost at its results. Every battle's end hold is lengthened so none ends,
## and the solo session comes back after, so 500 starts on the map as 491 left it.[br]
## Needs: the map, as the wait overlay shots leave it (491_seat_wait); its co-op battles are built
## as 489_coop_battle's are.

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const FACTION: String = "mercenary"

# A hold longer than the group, so no staged battle ends and saves.
const LONG_HOLD: float = 600.0

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op battle screen shots need the map (screen %d)" % [router_screen()])
		return true
	var solo: CampaignSession = campaign()
	note("co-op battle screen shots: seeded co-op runs %X, battles begun unsaved, for the host" % [
		RUN_SEED,
	])
	await _send_shots()
	await _frozen_shots()
	await _lost_run_shot()
	await _visitor_shot()
	await _lost_results_shot()
	node(^"CampaignService").set(&"session", solo)
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# 2 seats: the maps panel with the call for aid up, a teammate's map viewed, then the host's win:
# the send panel, its question, and the wait once it is closed.
func _send_shots() -> void:
	var coop: CampaignSession = await _open_battle(2, false)
	if coop == null:
		return
	var screen: Node = scene()
	var parts: CoopBattle = screen.call(&"get_coop") as CoopBattle
	var battle: CombatEncounter = coop.encounter
	parts.request_aid(true)
	parts.open_maps()
	await frames(SETTLE_FRAMES)
	await capture("coop_maps_panel")
	parts.close_panels()
	screen.call(&"view_map", battle.session_of_seat(1).session_id)
	await frames(SETTLE_FRAMES)
	await capture("coop_spectate")
	screen.call(&"view_map", battle.session_of_seat(0).session_id)
	_end(battle.session_of_seat(0), PLAYER)
	settle(battle_view())
	parts.refresh()
	await frames(SETTLE_FRAMES)
	var panel: SendPanel = parts.get_send_panel()
	var rows: Array[SendUnitRow] = panel.get_unit_rows()
	if rows.size() >= 2:
		rows[0].button_pressed = true
		rows[1].button_pressed = true
	var targets: Array[MapStatusRow] = panel.get_map_rows()
	if not targets.is_empty():
		targets[0].get_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_send_panel")
	panel.get_send_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_send_confirm")
	panel.get_back_button().pressed.emit()
	panel.get_close_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_waiting")
	coop.close()


# 4 seats: Player 2's map frozen, viewed under its banner; then the host's win: the send panel
# with the frozen-map rule, a unit picked for the frozen map.
func _frozen_shots() -> void:
	var coop: CampaignSession = await _open_battle(4, false)
	if coop == null:
		return
	var screen: Node = scene()
	var parts: CoopBattle = screen.call(&"get_coop") as CoopBattle
	var battle: CombatEncounter = coop.encounter
	var frozen: CombatSession = battle.session_of_seat(1)
	_freeze(frozen)
	screen.call(&"view_map", frozen.session_id)
	parts.refresh()
	await frames(SETTLE_FRAMES)
	await capture("coop_frozen_banner")
	screen.call(&"view_map", battle.session_of_seat(0).session_id)
	_end(battle.session_of_seat(0), PLAYER)
	settle(battle_view())
	parts.refresh()
	await frames(SETTLE_FRAMES)
	var panel: SendPanel = parts.get_send_panel()
	var rows: Array[SendUnitRow] = panel.get_unit_rows()
	if not rows.is_empty():
		rows[0].button_pressed = true
	for row: MapStatusRow in panel.get_map_rows():
		if row.session_id == frozen.session_id:
			row.get_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_frozen_send")
	coop.close()


# 2 seats: the host's map lost and the teammate's frozen, so the run is lost.
func _lost_run_shot() -> void:
	var coop: CampaignSession = await _open_battle(2, false)
	if coop == null:
		return
	var parts: CoopBattle = scene().call(&"get_coop") as CoopBattle
	_end(coop.encounter.session_of_seat(0), ENEMY)
	settle(battle_view())
	_freeze(coop.encounter.session_of_seat(1))
	parts.refresh()
	await frames(SETTLE_FRAMES)
	await capture("coop_run_lost")
	coop.close()


# 2 seats with the host's first unit swapped for the teammate's: on the partner's map in its
# opening swap window, the visitor picked, its free deployment tiles shown.
func _visitor_shot() -> void:
	var coop: CampaignSession = await _open_battle(2, true)
	if coop == null:
		return
	var screen: Node = scene()
	var partner: CombatSession = coop.encounter.session_of_seat(1)
	screen.call(&"view_map", partner.session_id)
	settle(battle_view())
	var controller: BattleController = battle_controller()
	for unit_id: String in partner.state.units_of(PLAYER):
		if partner.state.seat_of(unit_id) == 0:
			controller.move_cursor(partner.state.tile_of(unit_id))
			controller.confirm_tile(partner.state.tile_of(unit_id))
	await frames(SETTLE_FRAMES)
	if controller.get_stage() != BattleController.Stage.SWAP_PICKED:
		note("coop_visitor_move: the visitor wasn't picked (stage %d)" % [controller.get_stage()])
	await capture("coop_visitor_move")
	coop.close()


# 2 seats: the host's map lost, the teammate's won, applied in memory: the host's results.
func _lost_results_shot() -> void:
	var coop: CampaignSession = await _open_battle(2, false)
	if coop == null:
		return
	var battle: CombatEncounter = coop.encounter
	_end(battle.session_of_seat(0), ENEMY)
	_end(battle.session_of_seat(1), PLAYER)
	var result: CampaignSession.BattleResult = coop.collect_battle()
	var applied: CampaignRunState = coop.run.apply_battle(
			result,
			coop.ids,
			coop.reward_rolls(result),
			CombatRewardRules.load_default(),
			EffectCatalog.index()
	)
	if applied == null:
		fail("the 2-seat battle's result couldn't be applied")
		coop.close()
		return
	coop.run = applied
	coop.end_battle()
	node(^"SceneRouter").call(&"goto_screen", SCREEN_COMBAT_RESULTS)
	await frames(SETTLE_FRAMES)
	await fade_capture("coop_lost_results")
	coop.close()


# A new seat_count-seat run inside its first Standard combat, its battle begun unsaved with every
# seat's opening swap as with_swap says (on with the swap, which needs it), shown on the gameplay
# screen for the host with its end hold lengthened; null, failing, when any step can't be done.
func _open_battle(seat_count: int, with_swap: bool) -> CampaignSession:
	var coop: CampaignSession = _new_coop(seat_count)
	if coop == null:
		fail("a %d-seat run couldn't be built" % [seat_count])
		return null
	if with_swap and not _swap_first_units(coop):
		fail("the 2-seat run's swap was refused")
		coop.close()
		return null
	if not _enter_standard(coop.run):
		fail("the %d-seat run couldn't reach a Standard combat" % [seat_count])
		coop.close()
		return null
	var request: CampaignSession.BattleRequest = coop.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		fail("the %d-seat battle has no request" % [seat_count])
		coop.close()
		return null
	for seat: int in coop.seats:
		request.opening_swap[seat] = with_swap
	if coop.begin_battle(request) == null:
		fail("the %d-seat battle couldn't begin" % [seat_count])
		coop.close()
		return null
	node(^"CampaignService").set(&"session", coop)
	node(^"SceneRouter").call(&"goto_screen", SCREEN_GAMEPLAY)
	await frames(SETTLE_FRAMES)
	var screen: Node = scene()
	if screen == null or not screen.has_method(&"get_coop"):
		fail("the %d-seat battle's screen didn't open" % [seat_count])
		coop.close()
		return null
	screen.set(&"end_banner_time", LONG_HOLD)
	(screen.call(&"get_coop") as CoopBattle).send_offer_delay = 0.0
	settle(battle_view())
	await frames(SETTLE_FRAMES)
	return coop


# A new seat_count-seat run on RUN_SEED, as CampaignService builds one, with no starting offer
# left open.
func _new_coop(seat_count: int) -> CampaignSession:
	var seats: PackedInt32Array = []
	var factions: Dictionary[int, String] = {}
	for seat: int in seat_count:
		seats.append(seat)
		factions[seat] = FACTION
	var made: CampaignSession = CampaignSession.new(CampaignData.Mode.MULTIPLAYER, RUN_SEED, seats)
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


# Swaps seat 0's first non-commander unit for seat 1's, both seats agreeing. False when refused.
func _swap_first_units(coop: CampaignSession) -> bool:
	var mine: String = _first_unit(coop.run, 0)
	var theirs: String = _first_unit(coop.run, 1)
	coop.submit(ProposeSwapCommand.new(0, mine, 1, theirs))
	coop.submit(AnswerSwapCommand.new(1, 0, true, mine, theirs))
	return coop.run.flow.swaps.size() == 1


func _first_unit(run: CampaignRunState, seat: int) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			return unit.instance_id
	return ""


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


# Ends map's combat with winner, sent as its own batch, as the objectives check would.
func _end(map: CombatSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	map.engine.record(ended)
	map.flush("capture end")


# Freezes map as a co-op map with no player unit left freezes: every player unit defeated, held
# after its enemy phase (CombatEncounter.is_frozen). Staged: no fact records it.
func _freeze(map: CombatSession) -> void:
	for unit_id: String in map.state.units_of(PLAYER):
		map.state.defeat(map.engine, unit_id, "")
	map.state.phase_side = ENEMY
	map.state.is_phase_ended = true
	map.flush("capture freeze")
