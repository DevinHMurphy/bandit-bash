# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fast_forward_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends "res://tests/net/net_case_base.gd"
## Fast-forward cases for tests/net/run_all.gd ([code]NetRelay[/code]'s FAST_FORWARD notice,
## [BattleController]'s hold), on the Powder Keep (Defeat the Boss). On the wire, 2 and 4 peers:
## a client's hold reaches the host and every other client, the host's every client, and bad
## data is dropped. On a co-op board whose map 0 holds a seat-1 visitor: map 0 plays fast only
## while both seats hold there (a hold on another map doesn't count, a drop lets it go); seat 1
## alone on map 1 decides alone, as does a viewer with no units on a map; a player unit's defeat
## and an attack with the Boss let this player's hold go and leave the teammate's; other facts
## don't. Solo: the hold speeds the board, the same key moments let it go, a press is fast again,
## and release slows it.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "net"

const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")

const HOST: int = NetHarness.HOST
const RELAY_NAME: StringName = &"NetRelay"
const FIRST_STEAM_ID: int = 76561198000000001

const KEEP_PATH: String = "res://maps/boss/powder_keep.tres"
const BOSS_FLOOR: int = 18
const NODE: int = 0
const RUN_SEED: int = 1515

const FAST_FORWARD: int = NetRelayScript.NoticeKind.FAST_FORWARD
const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _catalog: EffectCatalog.Index = null
var _keep: CombatMapDefinition = null


func run() -> void:
	for client_count: int in [1, 3]:
		_test_wire(client_count)
	_catalog = EffectCatalog.index()
	_keep = load(KEEP_PATH) as CombatMapDefinition
	if _catalog == null or _keep == null:
		_check("fast-forward: the catalog and the Powder Keep load", false)
		return
	_test_shared_map()
	_test_alone()
	_test_stops()
	_test_solo()


func _test_wire(client_count: int) -> void:
	var tag: String = "fast-forward wire %d peers:" % [client_count + 1]
	var rig: Rig = _start_wire(client_count)
	if rig == null:
		_check("%s the rig starts" % [tag], false)
		return
	rig.relay(1).send_notice(FAST_FORWARD, [3, true])
	rig.harness.step_until_idle()
	var up: bool = rig.heard[HOST] == [[1, FAST_FORWARD, [3, true]]] and rig.heard[1].is_empty()
	for index: int in range(2, rig.harness.size()):
		up = up and rig.heard[index] == [[1, FAST_FORWARD, [3, true]]]
	_check("%s a client's hold reaches the host and every other client" % [tag], up, str(rig.heard))
	rig.clear()
	rig.relay(HOST).send_notice(FAST_FORWARD, [0, false])
	rig.harness.step_until_idle()
	var down: bool = rig.heard[HOST].is_empty()
	for index: int in range(1, rig.harness.size()):
		down = down and rig.heard[index] == [[0, FAST_FORWARD, [0, false]]]
	_check("%s the host's release reaches every client, as seat 0" % [tag], down, str(rig.heard))
	rig.clear()
	var bad: Array[Array] = [[], [0], [0, 1], [-1, true], ["0", true], [0, true, 1], [0.0, true]]
	var client: NetRelayScript = rig.relay(1)
	for data: Array in bad:
		client.send_notice(FAST_FORWARD, data)
		client.rpc_id(1, &"_notice", 0, FAST_FORWARD, data)
	rig.harness.step_until_idle()
	var quiet: bool = true
	for index: int in rig.harness.size():
		quiet = quiet and rig.heard[index].is_empty()
	_check("%s a hold with bad data is refused and dropped" % [tag], quiet, str(rig.heard))
	rig.harness.stop()


# Map 0 holds seat 0's units and a seat-1 visitor; seat 0 plays there.
func _test_shared_map() -> void:
	var board: Board = _coop_board(0, 0)
	if board == null:
		return
	var map_0: int = board.session.session_id
	var map_1: int = board.battle.session_of_seat(1).session_id
	_check("fast-forward shared: map 0 holds both seats' units", (
			PhaseRunner.seats_with_units(board.session) == PackedInt32Array([0, 1])
	), str(PhaseRunner.seats_with_units(board.session)))
	_hold(board, true)
	var alone: bool = board.view.is_fast_forward()
	_teammate(1, map_1, true)
	var elsewhere: bool = board.view.is_fast_forward()
	_teammate(1, map_0, true)
	var both: bool = board.view.is_fast_forward()
	_check("fast-forward shared: fast only while every player with units there holds", (
			not alone and not elsewhere and both
	), "alone %s, teammate elsewhere %s, both %s" % [alone, elsewhere, both])
	_teammate(1, map_0, false)
	var released: bool = board.view.is_fast_forward()
	_teammate(1, map_0, true)
	NetRelay.seat_dropped.emit(1)
	var dropped: bool = board.view.is_fast_forward()
	_check("fast-forward shared: a teammate's release or drop slows it again", (
			not released and not dropped
	), "released %s, dropped %s" % [released, dropped])
	_teammate(1, map_0, true)
	_hold(board, false)
	var own_release: bool = board.view.is_fast_forward()
	_hold(board, true)
	_check("fast-forward shared: this player's own release slows it, a new press speeds it", (
			not own_release and board.view.is_fast_forward()
	))
	_teammate(1, map_0, false)
	_free(board)


# Seat 1 alone on map 1, and seat 0 viewing map 1, where it has no units.
func _test_alone() -> void:
	var board: Board = _coop_board(1, 1)
	if board == null:
		return
	_hold(board, true)
	_check("fast-forward alone: a player alone on a map decides alone", (
			PhaseRunner.seats_with_units(board.session) == PackedInt32Array([1])
			and board.view.is_fast_forward()
	))
	_free(board)
	var viewer: Board = _coop_board(1, 0)
	if viewer == null:
		return
	_teammate(1, viewer.session.session_id, false)
	_hold(viewer, true)
	_check("fast-forward alone: a viewer with no units on a map decides for its own view", (
			viewer.view.is_fast_forward()
	))
	_free(viewer)


func _test_stops() -> void:
	var board: Board = _coop_board(0, 0)
	if board == null:
		return
	var map_0: int = board.session.session_id
	var bosses: PackedStringArray = Objectives.marked_ids(board.session)
	var own_ids: PackedStringArray = board.session.state.units_of(PLAYER)
	var enemy_ids: PackedStringArray = []
	for enemy_id: String in board.session.state.units_of(ENEMY):
		if not bosses.has(enemy_id):
			enemy_ids.append(enemy_id)
	if bosses.is_empty() or own_ids.is_empty() or enemy_ids.is_empty():
		_check("fast-forward stops: the keep has a Boss, a grunt and player units", false, (
				"%s / %s / %s" % [bosses, own_ids, enemy_ids]
		))
		_free(board)
		return
	_check("fast-forward stops: the controller follows the map's played facts", (
			board.session.bus.fact_played.is_connected(board.controller._on_bus_fact_played)
	))
	_teammate(1, map_0, true)
	var quiet: Array[CombatFact] = [
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, own_ids[0], enemy_ids[0]),
		CombatFact.new(CombatFact.Kind.DEFEATED, enemy_ids[0], own_ids[0]),
	]
	var stops: Array[CombatFact] = [
		CombatFact.new(CombatFact.Kind.DEFEATED, own_ids[0], enemy_ids[0]),
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, bosses[0], own_ids[0]),
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, own_ids[0], bosses[0]),
	]
	_hold(board, true)
	var kept: bool = board.view.is_fast_forward()
	for fact: CombatFact in quiet:
		board.controller._on_bus_fact_played(fact)
		kept = kept and board.view.is_fast_forward()
	_check("fast-forward stops: an attack without the Boss and an enemy's defeat don't stop it", (
			kept
	))
	for fact: CombatFact in stops:
		_hold(board, true)
		var was_fast: bool = board.view.is_fast_forward()
		board.controller._on_bus_fact_played(fact)
		_check("fast-forward stops: %s lets this player's hold go" % [
			CombatFact.Kind.find_key(fact.kind),
		], was_fast and not board.view.is_fast_forward())
		# The teammate's hold stays: a press is all it takes again.
		_hold(board, false)
		_hold(board, true)
		_check("fast-forward stops: after %s the teammate still holds; a press is fast again" % [
			CombatFact.Kind.find_key(fact.kind),
		], board.view.is_fast_forward())
	_teammate(1, map_0, false)
	_free(board)


func _test_solo() -> void:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = _request([0])
	request.armies[0] = _army(run, 2, -1)
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		_check("fast-forward solo: the battle begins", false)
		run.close()
		return
	var board: Board = _board(run, battle, battle.get_session(0), 0)
	var bosses: PackedStringArray = Objectives.marked_ids(board.session)
	var own_ids: PackedStringArray = board.session.state.units_of(PLAYER)
	if bosses.is_empty() or own_ids.is_empty():
		_check("fast-forward solo: the keep has a Boss and player units", false)
		_free(board)
		return
	_hold(board, true)
	var held: bool = board.view.is_fast_forward()
	var stopped: PackedStringArray = []
	for fact: CombatFact in [
		CombatFact.new(CombatFact.Kind.DEFEATED, own_ids[0], bosses[0]),
		CombatFact.new(CombatFact.Kind.ATTACK_MADE, bosses[0], own_ids[0]),
	]:
		_hold(board, false)
		_hold(board, true)
		var was_fast: bool = board.view.is_fast_forward()
		board.controller._on_bus_fact_played(fact)
		if was_fast and not board.view.is_fast_forward():
			stopped.append(str(CombatFact.Kind.find_key(fact.kind)))
	_hold(board, false)
	_hold(board, true)
	var again: bool = board.view.is_fast_forward()
	_hold(board, false)
	_check("fast-forward solo: the key moments let the hold go, a press is fast again", (
			held and stopped.size() == 2 and again and not board.view.is_fast_forward()
	), "held %s, stopped by %s, fast again %s" % [held, stopped, again])
	_free(board)


# A co-op battle on the keep: seat 0's army of two plus a visitor of seat 1's on map 0, seat 1's
# army of one on map 1; a board bound to map_seat's map for view_seat. Null, reported, on failure.
func _coop_board(map_seat: int, view_seat: int) -> Board:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	var request: CampaignSession.BattleRequest = _request([0, 1])
	request.armies[0] = _army(run, 2, 1)
	request.armies[1] = _army(run, 1, -1)
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		_check("fast-forward: the co-op battle begins", false)
		run.close()
		return null
	return _board(run, battle, battle.session_of_seat(map_seat), view_seat)


# A request on the keep at the Boss floor, turn 1 at once for every seat.
func _request(seats: Array[int]) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BOSS_FLOOR
	request.node = NODE
	request.pool = [_keep]
	request.catalog = _catalog
	for seat: int in seats:
		request.opening_swap[seat] = false
	return request


# count Archers with Simple Bows and, unless visitor_seat is -1, one more owned by visitor_seat.
func _army(run: CampaignSession, count: int, visitor_seat: int) -> CampaignSession.Army:
	var army: CampaignSession.Army = CampaignSession.Army.new()
	var total: int = count + (0 if visitor_seat < 0 else 1)
	for index: int in total:
		var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "archer")
		var bow_id: String = run.ids.next_item_id("Simple Bow")
		archer.weapon_id = bow_id
		army.unit_instances.append(archer)
		army.item_instances[bow_id] = ItemInstance.new(bow_id, "simple_bow")
		if index == count:
			army.visitor_seats[archer.instance_id] = visitor_seat
	return army


# A board on session for seat: the view, the HUD widgets and a controller, under the root.
func _board(
		run: CampaignSession, battle: CombatEncounter, session: CombatSession, seat: int
) -> Board:
	var board: Board = Board.new()
	board.run = run
	board.battle = battle
	board.session = session
	board.view = VIEW_SCENE.instantiate()
	_root.add_child(board.view)
	board.hud = CanvasLayer.new()
	_root.add_child(board.hud)
	var bar: TurnBar = TURN_BAR_SCENE.instantiate()
	var swap: SwapWindow = SWAP_WINDOW_SCENE.instantiate()
	var host: PanelHost = PANEL_HOST_SCENE.instantiate()
	var message: BattleMessage = MESSAGE_SCENE.instantiate()
	for widget: Control in [bar, swap, host, message]:
		board.hud.add_child(widget)
	board.controller = BattleController.new()
	board.controller.action_menu_scene = ACTION_MENU_SCENE
	board.controller.target_picker_scene = TARGET_PICKER_SCENE
	board.controller.confirm_dialog_scene = CONFIRM_SCENE
	board.controller.view = board.view
	board.controller.panel_host = host
	board.controller.turn_bar = bar
	board.controller.swap_window = swap
	board.controller.message = message
	_root.add_child(board.controller)
	board.view.bind(session)
	board.controller.bind(battle, session, seat)
	return board


func _free(board: Board) -> void:
	board.controller.unbind()
	board.view.unbind()
	for node: Node in [board.controller, board.view, board.hud]:
		_root.remove_child(node)
		node.free()
	board.run.close()


# Presses or releases fast_forward as the key does.
func _hold(board: Board, is_down: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"fast_forward"
	event.pressed = is_down
	board.controller._unhandled_input(event)


# seat's hold notice for the map session_id, as the relay hands it on.
func _teammate(seat: int, session_id: int, is_held: bool) -> void:
	NetRelay.notice_received.emit(seat, FAST_FORWARD, [session_id, is_held])


# A harness of client_count + 1 peers with a relay under each branch, every one seated, no run.
func _start_wire(client_count: int) -> Rig:
	var rig: Rig = Rig.new()
	rig.harness = NetHarness.new(_root)
	if not rig.harness.start(client_count):
		rig.harness.stop()
		return null
	var directory: SeatDirectory = SeatDirectory.new()
	for index: int in rig.harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = RELAY_NAME
		rig.harness.branch(index).add_child(relay)
		rig.relays.append(relay)
		rig.heard.append([])
		relay.notice_received.connect(rig.on_notice.bind(index))
		directory.add_seat(index, FIRST_STEAM_ID + index, rig.harness.peer_id(index))
	rig.relay(HOST).seats = directory
	return rig


# A co-op or solo battle's board: its run, battle, the map shown, the view and the controller.
class Board:
	extends RefCounted

	var run: CampaignSession = null
	var battle: CombatEncounter = null
	var session: CombatSession = null
	var view: BattleView = null
	var hud: CanvasLayer = null
	var controller: BattleController = null


# The wire cases' peers: the harness, each branch's relay and the notices it heard.
class Rig:
	extends RefCounted

	var harness: NetHarness = null
	var relays: Array[Node] = []
	var heard: Array[Array] = []

	func relay(index: int) -> NetRelayScript:
		return relays[index] as NetRelayScript

	func clear() -> void:
		for each: Array in heard:
			each.clear()

	func on_notice(seat: int, kind: int, data: Array, index: int) -> void:
		heard[index].append([seat, kind, data])
