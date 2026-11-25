# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_screen_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 24, 2026
# ==============================================================================

extends RefCounted
## The co-op battle screen's parts ([CoopBattle]) for the ui/input suite, on real 2- and 4-seat
## host battles through the real [code]SaveService[/code] and [code]CampaignService[/code], each on
## the gameplay screen: after a win the send panel opens by itself, and a send is picked and
## confirmed by keys, mouse and pad; Send none; the frozen-map rule shown and a send elsewhere
## refused, then a send to the frozen map landing at once and played there; call for aid raised and
## lowered by keys, mouse and pad, and seen by a teammate; spectating a teammate's map read-only by
## mouse and pad; waiting for the other maps, then the battle's end held and routed to its results;
## a lost run's banner and end; the visitor's opening move on the partner's map; a forfeited map
## leaving every view; a client's view of a teammate's call through its mirror; solo unchanged.
## Autoloads are reached as nodes. Runs only with a test user folder, as it writes save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/input"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

# Preloaded scripts used as types (gdscript.md, Naming).
const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const NetHarness = preload("res://tests/net/harness/net_harness.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

const GAMEPLAY_SCENE: String = "res://ui/battle/gameplay.tscn"
const ROW_SCENE: String = "res://ui/battle/coop/map_status_row.tscn"
const OVERLAY_SCENE: String = "res://ui/campaign/victory/victory_overlay.tscn"

# Any Steam ids: the first is the host's, one per seat.
const STEAM_BASE: int = 76561198000000001

# A hold longer than any case, so the battle's end never routes inside one.
const LONG_HOLD: float = 600.0

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _screen: BattleScreen = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")
	_service = root.get_node(^"CampaignService")


## Runs every case, each on its own run. Call only with a test user folder.
func run() -> void:
	_test_send(2, &"keys")
	_test_send(4, &"mouse")
	_test_send(2, &"pad")
	_test_send_none()
	_test_frozen_rule()
	_test_aid()
	_test_spectate()
	_test_waiting_then_results()
	_test_run_lost()
	_test_visitor_move()
	_test_forfeited_map()
	_test_client_view()
	_test_solo()


# A teammate who forfeits takes their map out of every view: it leaves the maps panel and can't
# be viewed; a view on it goes back to the seat's own map.
func _test_forfeited_map() -> void:
	var tag: String = "coop forfeit"
	var run: CampaignSession = _start(4)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	var leaving: CombatSession = battle.session_of_seat(2)
	_screen.view_map(leaving.session_id)
	var was_viewed: bool = coop.get_viewed() == leaving.session_id
	var has_left: bool = battle.forfeit(2)
	coop.refresh()
	coop.open_maps()
	var listed: PackedInt32Array = []
	for row: MapStatusRow in coop.get_maps_panel().get_rows():
		listed.append(row.session_id)
	_check.call("%s: the map leaves the panel and the view, and can't be viewed again" % [tag], (
			was_viewed
			and has_left
			and not listed.has(leaving.session_id)
			and listed.size() == 3
			and _screen.get_view().get_session() == battle.session_of_seat(0)
			and not _screen.view_map(leaving.session_id)
	), "viewed %s, left %s, listed %s" % [was_viewed, has_left, listed])
	coop.close_panels()
	_finish()


# After the host's map is won the send panel opens by itself, input held and the wait shown; a
# unit and a map picked and confirmed by device sends it there, and the panel closes.
func _test_send(seat_count: int, device: StringName) -> void:
	var tag: String = "coop send (%d seats, %s)" % [seat_count, device]
	var run: CampaignSession = _start(seat_count)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	var own: CombatSession = battle.session_of_seat(0)
	_win(own, PLAYER)
	BattleViewCases.settle(_screen.get_view())
	coop.refresh()
	var panel: SendPanel = coop.get_send_panel()
	var waiting: PackedStringArray = coop.get_waiting_banner().get_texts()
	_check.call("%s: the panel opens by itself after the win, input held, the wait shown" % [tag], (
			panel.visible
			and _screen.get_controller().is_held()
			and coop.get_hint_context() == &"SEND"
			and coop.get_waiting_banner().visible
			and waiting[0] == "Waiting for the other maps"
	), "panel %s, context %s, %s" % [panel.visible, coop.get_hint_context(), waiting])
	var target: int = seat_count - 1
	var rows: Array[SendUnitRow] = panel.get_unit_rows()
	var unit_id: String = rows[0].unit_id if not rows.is_empty() else ""
	var map_row: MapStatusRow = _map_row(panel, target)
	match device:
		&"mouse":
			_click(rows[0])
			_click(map_row.get_button())
			_click(panel.get_send_button())
		_:
			_press(device, &"ui_accept")
			for _i: int in rows.size() + panel.get_map_rows().find(map_row):
				_press(device, &"ui_down")
			_press(device, &"ui_accept")
			_press(device, &"ui_accept")
	var asked: String = panel.get_question()
	var is_asking: bool = panel.is_confirming() and coop.get_hint_context() == &"SEND_CONFIRM"
	if device == &"mouse":
		_click(panel.get_confirm_button())
	else:
		_press(device, &"ui_accept")
	_check.call("%s: picked and confirmed, it goes to the map picked" % [tag], (
			is_asking
			and asked.contains(CoopViewModel.map_title(battle.get_session(target), 0))
			and battle.units_in_transit().has(unit_id)
			and battle.has_sent(0)
			and CoopViewModel.status(battle, target, 0).arriving == 1
			and not panel.visible
			and not _screen.get_controller().is_held()
	), "asking %s (%s), transit %s, sent %s" % [
		is_asking, asked, battle.units_in_transit(), battle.has_sent(0),
	])
	_finish()


# Send none by keys: asked first, then final; the panel doesn't open again.
func _test_send_none() -> void:
	var tag: String = "coop send none"
	var run: CampaignSession = _start(2)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	_win(battle.session_of_seat(0), PLAYER)
	BattleViewCases.settle(_screen.get_view())
	coop.refresh()
	var panel: SendPanel = coop.get_send_panel()
	for _i: int in panel.get_unit_rows().size() + panel.get_map_rows().size():
		_press_key(KEY_DOWN)
	var is_on_none: bool = _focus() == panel.get_send_none_button()
	_press_key(KEY_ENTER)
	var asked: String = panel.get_question()
	_press_key(KEY_ENTER)
	coop.refresh()
	_check.call("%s: by keys, asked first, sends none, and the panel stays closed" % [tag], (
			is_on_none
			and asked.begins_with("Send no units?")
			and battle.has_sent(0)
			and battle.units_in_transit().is_empty()
			and not panel.visible
			and not CoopViewModel.can_send(battle, 0)
	), "on none %s, asked %s, sent %s" % [is_on_none, asked, battle.has_sent(0)])
	_finish()


# A teammate's frozen map, viewed read-only with its banner; after the host's win the send panel
# shows the rule, refuses a send to a map that isn't frozen, and a send by keys to the frozen map
# lands at once and is played there.
func _test_frozen_rule() -> void:
	var tag: String = "coop frozen"
	var run: CampaignSession = _start(4)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	var controller: BattleController = _screen.get_controller()
	var frozen: CombatSession = battle.session_of_seat(1)
	_freeze(frozen)
	coop.refresh()
	_press_key(KEY_C)
	var maps: MapsPanel = coop.get_maps_panel()
	var is_maps: bool = maps.visible and coop.get_hint_context() == &"MAPS"
	_press_key(KEY_DOWN)
	_press_key(KEY_ENTER)
	coop.refresh()
	var banner: FrozenBanner = coop.get_frozen_banner()
	_check.call("%s: a teammate's frozen map is viewed by keys, read-only, under its banner" % [
		tag,
	], (
			is_maps
			and not maps.visible
			and _screen.get_view().get_session() == frozen
			and banner.visible
			and banner.get_line().contains("Player 2's map")
			and not controller.get_live_actions().has(&"end_turn")
			and not controller.is_accepting_input()
	), "maps %s, viewed %d, banner %s" % [
		is_maps, _screen.get_view().get_session().session_id, banner.visible,
	])
	_screen.view_map(battle.session_of_seat(0).session_id)
	_win(battle.session_of_seat(0), PLAYER)
	BattleViewCases.settle(_screen.get_view())
	coop.refresh()
	var panel: SendPanel = coop.get_send_panel()
	var others_refused: bool = true
	for row: MapStatusRow in panel.get_map_rows():
		var should_refuse: bool = row.session_id != frozen.session_id
		others_refused = others_refused and row.get_button().disabled == should_refuse
	_check.call("%s: the send panel shows the rule; only the frozen map can be picked" % [tag], (
			panel.visible
			and panel.get_rule().visible
			and not panel.get_send_none_button().visible
			and others_refused
	), "panel %s, rule %s, none %s" % [
		panel.visible, panel.get_rule().visible, panel.get_send_none_button().visible,
	])
	var unit_id: String = panel.get_unit_rows()[0].unit_id
	var elsewhere: int = battle.session_of_seat(2).session_id
	coop.send(PackedStringArray([unit_id]), battle.session_of_seat(0).session_id, elsewhere)
	_check.call("%s: a send to a map that isn't frozen is refused, the reason shown" % [tag], (
			panel.get_status_text().contains("send to a frozen map")
			and not battle.has_sent(0)
			and battle.units_in_transit().is_empty()
	), panel.get_status_text())
	_press_key(KEY_ENTER)
	for _i: int in panel.get_unit_rows().size():
		_press_key(KEY_DOWN)
	_press_key(KEY_ENTER)
	_press_key(KEY_ENTER)
	_press_key(KEY_ENTER)
	coop.refresh()
	_check.call("%s: sent by keys to the frozen map, it lands at once; the map goes on" % [tag], (
			frozen.state.has_unit(unit_id)
			and not battle.is_frozen(frozen.session_id)
			and CoopViewModel.status(battle, frozen.session_id, 0).can_act
	), "on it %s, frozen %s" % [
		frozen.state.has_unit(unit_id), battle.is_frozen(frozen.session_id),
	])
	coop.open_maps()
	var row_note: String = _map_row_of(maps, frozen.session_id).get_note()
	_press_key(KEY_DOWN)
	_press_key(KEY_ENTER)
	BattleViewCases.settle(_screen.get_view())
	_check.call("%s: on the teammate's map the seat plays its sent unit" % [tag], (
			row_note.contains("Your units can act")
			and _screen.get_view().get_session() == frozen
			and controller.get_stage() == BattleController.Stage.IDLE
			and TurnInputModel.acting_units(frozen, 0).has(unit_id)
			and controller.get_live_actions().has(&"end_turn")
	), "note %s, stage %d" % [row_note, controller.get_stage()])
	_finish()


# Call for aid on the host's own map: raised by keys in the maps panel, seen on a teammate's view,
# lowered by the strip's button, raised again by pad.
func _test_aid() -> void:
	var tag: String = "coop aid"
	var run: CampaignSession = _start(2)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	var own_id: int = battle.session_of_seat(0).session_id
	_press_key(KEY_C)
	_press_key(KEY_DOWN)
	_press_key(KEY_DOWN)
	var on_aid: bool = _focus() == coop.get_maps_panel().get_aid_button()
	_press_key(KEY_ENTER)
	var row: MapStatusRow = (load(ROW_SCENE) as PackedScene).instantiate()
	_root.add_child(row)
	row.show_status(CoopViewModel.status(battle, own_id, 1), false)
	var seen: String = row.get_note()
	row.free()
	_check.call("%s: raised by keys, and a teammate sees it" % [tag], (
			on_aid
			and battle.is_aid_called(own_id)
			and seen.contains("Calls for aid")
			and CoopViewModel.maps(battle, 1)[1].is_aid_called
	), "on aid %s, called %s, seen %s" % [on_aid, battle.is_aid_called(own_id), seen])
	_press_key(KEY_ESCAPE)
	var closed: bool = not coop.get_maps_panel().visible
	coop.refresh()
	_click(coop.get_bar().get_aid_button())
	var lowered: bool = not battle.is_aid_called(own_id)
	_press_pad(JOY_BUTTON_X)
	_press_pad(JOY_BUTTON_DPAD_DOWN)
	_press_pad(JOY_BUTTON_DPAD_DOWN)
	_press_pad(JOY_BUTTON_A)
	_check.call("%s: Esc closes; lowered by the mouse, raised again by pad" % [tag], (
			closed and lowered and battle.is_aid_called(own_id)
	), "closed %s, lowered %s" % [closed, lowered])
	_press_pad(JOY_BUTTON_B)
	_finish()


# A teammate's map viewed by the mouse, read-only, the strip naming it; back by pad.
func _test_spectate() -> void:
	var tag: String = "coop spectate"
	var run: CampaignSession = _start(2)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	var controller: BattleController = _screen.get_controller()
	var other: CombatSession = battle.session_of_seat(1)
	_click(coop.get_bar().get_maps_button())
	_click(_map_row_of(coop.get_maps_panel(), other.session_id).get_button())
	coop.refresh()
	var bar_text: String = coop.get_bar().get_maps_button().text
	_check.call("%s: by the mouse, the teammate's map shows read-only" % [tag], (
			_screen.get_view().get_session() == other
			and coop.get_viewed() == other.session_id
			and bar_text.contains("Player 2")
			and TurnInputModel.end_turn_command(other, 0) == null
			and not controller.get_live_actions().has(&"end_turn")
			and not controller.get_live_actions().has(&"open_runes")
	), "viewed %d, bar %s, actions %s" % [
		coop.get_viewed(), bar_text, controller.get_live_actions(),
	])
	_press_pad(JOY_BUTTON_X)
	_press_pad(JOY_BUTTON_DPAD_UP)
	_press_pad(JOY_BUTTON_A)
	_check.call("%s: back to its own map by pad, played again" % [tag], (
			_screen.get_view().get_session() == battle.session_of_seat(0)
			and controller.get_live_actions().has(&"end_turn")
	), "viewed %d" % [coop.get_viewed()])
	_finish()


# Once the host's map has ended the wait shows; once every map has, the end is held and the run
# goes to the battle's results, where a seat whose map was lost gets the loss.
func _test_waiting_then_results() -> void:
	var tag: String = "coop results"
	var run: CampaignSession = _start(2)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	_win(battle.session_of_seat(0), ENEMY)
	BattleViewCases.settle(_screen.get_view())
	coop.refresh()
	var waiting: PackedStringArray = coop.get_waiting_banner().get_texts()
	var is_waiting: bool = (
			coop.get_waiting_banner().visible
			and waiting[0] == "Waiting for the other maps"
			and waiting[1].begins_with("1 still")
			and coop.get_hint_context() == &"WAITING"
			and not _screen.is_end_held()
			and not coop.get_send_panel().visible
	)
	_win(battle.session_of_seat(1), PLAYER)
	BattleViewCases.settle(_screen.get_view())
	coop.refresh()
	_check.call("%s: the lost seat waits, then the end is held once every map has ended" % [tag], (
			is_waiting
			and _screen.is_end_held()
			and not coop.get_waiting_banner().visible
	), "%s, held %s" % [waiting, _screen.is_end_held()])
	_close_screen()
	var result: CampaignSession.BattleResult = _service.call(&"end_battle")
	var session: CampaignSession = _service.get(&"session")
	var lost: CombatResultsModel = null
	if session != null:
		lost = CombatResultsModel.build(session, 0)
	_check.call("%s: the battle's end routes to its results, seat 0's the loss" % [tag], (
			result != null
			and BattleScreen.screen_after_battle(session) == SceneRouter.Screen.COMBAT_RESULTS
			and lost != null
			and lost.is_lost
	), "route %s" % [BattleScreen.screen_after_battle(session)])
	var overlay: VictoryOverlay = (load(OVERLAY_SCENE) as PackedScene).instantiate()
	_root.add_child(overlay)
	overlay.open(0, true)
	var title: String = overlay.get_title()
	var status: String = overlay.get_status_text()
	var button: String = overlay.get_primary_button().text
	var stages_hidden: bool = (
			not overlay.get_grade_stage().visible
			and not overlay.get_recap_stage().visible
			and not overlay.get_rewards_stage().visible
	)
	overlay.get_primary_button().pressed.emit()
	var refusal: String = overlay.get_status_text()
	var leave: ReadyToggle = overlay.get_primary_button() as ReadyToggle
	_check.call("%s: the failed seat's results show the loss and Leave (Ready), which waits" % [
		tag,
	], (
			title == VictoryOverlay.LOST_TITLE
			and status == VictoryOverlay.LOST_TEXT
			and button == "Ready"
			and leave != null and leave.solo_text == "Leave" and not leave.is_ready()
			and stages_hidden
			and overlay.get_stage() == VictoryOverlay.Stage.REWARDS
			and refusal.begins_with("Can't do that")
	), "%s / %s / %s / %s" % [title, status, button, refusal])
	overlay.free()
	_finish()


# The host's map lost and the teammate's frozen: the lost banner shows, input stops, the view
# can't move, and the end is held; ending the battle then ends the run for everyone.
func _test_run_lost() -> void:
	var tag: String = "coop run lost"
	var run: CampaignSession = _start(2)
	if run == null:
		_check.call("%s: the battle begins" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var coop: CoopBattle = _screen.get_coop()
	_win(battle.session_of_seat(0), ENEMY)
	BattleViewCases.settle(_screen.get_view())
	_freeze(battle.session_of_seat(1))
	coop.refresh()
	var texts: PackedStringArray = coop.get_waiting_banner().get_texts()
	_check.call("%s: the banner shows, input stops and the end is held" % [tag], (
			coop.is_run_lost_shown()
			and texts[0] == "The run is lost"
			and _screen.is_end_held()
			and not _screen.view_map(battle.session_of_seat(1).session_id)
			and not coop.open_maps()
			and _screen.get_controller().get_hint_context().is_empty()
	), "%s, held %s" % [texts, _screen.is_end_held()])
	_close_screen()
	_service.call(&"end_battle")
	var session: CampaignSession = _service.get(&"session")
	_check.call("%s: ending the battle ends the run, routed to the run's end" % [tag], (
			session == null
			and BattleScreen.screen_after_battle(session) == SceneRouter.Screen.RESULTS
			and not _saves.call(&"has_multiplayer_campaign")
	))
	_finish()


# A swap visitor's owner, in the opening swap window, views the partner's map, picks the visitor
# and moves it by keys onto a free deployment tile, then Starts there.
func _test_visitor_move() -> void:
	var tag: String = "coop visitor"
	var run: CampaignSession = _start(2, true)
	if run == null:
		_check.call("%s: the battle begins with a swap" % [tag], false)
		_finish()
		return
	var battle: CombatEncounter = run.encounter
	var partner: CombatSession = battle.session_of_seat(1)
	var visitor: String = ""
	for unit_id: String in partner.state.units_of(PLAYER):
		if partner.state.seat_of(unit_id) == 0:
			visitor = unit_id
	var controller: BattleController = _screen.get_controller()
	BattleViewCases.settle(_screen.get_view())
	_press_key(KEY_C)
	_press_key(KEY_DOWN)
	_press_key(KEY_ENTER)
	BattleViewCases.settle(_screen.get_view())
	var hint: String = controller.swap_window.get_hint()
	var moves: Array[TurnInputModel.TargetOption] = TurnInputModel.opening_moves(partner, visitor)
	var is_swapping: bool = controller.get_stage() == BattleController.Stage.SWAP
	controller.move_cursor(partner.state.tile_of(visitor))
	_press_key(KEY_ENTER)
	var is_picked: bool = controller.get_stage() == BattleController.Stage.SWAP_PICKED
	var goal: Vector2i = moves[0].tile if not moves.is_empty() else CombatFact.NO_TILE
	controller.move_cursor(goal)
	_press_key(KEY_ENTER)
	BattleViewCases.settle(_screen.get_view())
	var moved: bool = not visitor.is_empty() and partner.state.tile_of(visitor) == goal
	_press_key(KEY_T)
	BattleViewCases.settle(_screen.get_view())
	_check.call("%s: moved by keys onto a free tile on the partner's map, then Start" % [tag], (
			not visitor.is_empty()
			and _screen.get_view().get_session() == partner
			and is_swapping
			and hint.contains("visits here")
			and not moves.is_empty()
			and is_picked
			and moved
			and not partner.state.seats_to_start.has(0)
	), "visitor %s, swapping %s, hint %s, moves %d, picked %s, moved %s" % [
		visitor, is_swapping, hint, moves.size(), is_picked, moved,
	])
	_finish()


# A client's screen on its mirror: the host's call for aid and its map's win show on the client's
# strip and maps panel, and the client's own map is played.
func _test_client_view() -> void:
	var tag: String = "coop client"
	_start_files()
	var steam_ids: PackedInt64Array = [STEAM_BASE, STEAM_BASE + 1]
	_saves.call(&"start_new_multiplayer_run", steam_ids)
	var host: CampaignSession = _service.get(&"session")
	if host == null or host.run == null:
		_check.call("%s: the run starts" % [tag], false)
		_finish()
		return
	for seat: int in host.seats:
		host.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	var harness: NetHarness = NetHarness.new(_root)
	var mirror: ClientMirror = null
	if harness.start(1):
		mirror = _rig(harness, host)
	var battle: CombatEncounter = null
	if mirror != null and _enter_battle(host, false) == OK:
		battle = host.encounter
		harness.step_until_idle()
		mirror.start()
		harness.step_until_idle()
	var copy: CampaignSession = null if mirror == null else mirror.session
	if battle == null or copy == null or copy.encounter == null:
		_check.call("%s: the mirror holds the battle" % [tag], false)
		_stop_rig(harness, mirror)
		return
	_service.call(&"submit_combat", CallForAidCommand.new(0, true), 0)
	harness.step_until_idle()
	_service.set(&"session", copy)
	_service.call(&"set_local_seat", 1)
	_open_screen()
	var coop: CoopBattle = _screen.get_coop()
	coop.refresh()
	var bar_text: String = coop.get_bar().get_maps_button().text
	coop.open_maps()
	var rows: Array[MapStatusRow] = coop.get_maps_panel().get_rows()
	var host_note: String = rows[1].get_note() if rows.size() == 2 else ""
	var own_map: CombatSession = copy.encounter.session_of_seat(1)
	_check.call("%s: the client sees the host's call for aid, on its own map" % [tag], (
			copy.encounter.is_aid_called(0)
			and bar_text.contains("Aid called")
			and host_note.contains("Calls for aid")
			and _screen.get_view().get_session() == own_map
			and coop.get_viewed() == own_map.session_id
	), "bar %s, note %s" % [bar_text, host_note])
	coop.close_panels()
	_service.set(&"session", host)
	_win(battle.session_of_seat(0), PLAYER)
	harness.step_until_idle()
	_service.set(&"session", copy)
	coop.refresh()
	coop.open_maps()
	rows = coop.get_maps_panel().get_rows()
	var host_row: String = rows[1].get_button().text if rows.size() == 2 else ""
	_check.call("%s: and the host's map won, through the mirror" % [tag], (
			host_row.contains("Won") and copy.encounter.session_of_seat(0).is_finished
	), host_row)
	coop.close_panels()
	_close_screen()
	_service.call(&"set_local_seat", CampaignData.HOST_SEAT)
	_service.set(&"session", host)
	_stop_rig(harness, mirror)


# A solo battle: no co-op part shows and the hint bar stays the controller's.
func _test_solo() -> void:
	var tag: String = "coop solo"
	_start_files()
	var err: Error = _saves.call(&"start_new_solo_run", 0x51A7E)
	var run: CampaignSession = _service.get(&"session")
	if err != OK or run == null or run.run == null:
		_check.call("%s: a solo run starts" % [tag], false)
		_finish()
		return
	run.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	_service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	_open_screen()
	var coop: CoopBattle = _screen.get_coop()
	var hints: ControlHintBar = _screen.get_node(^"%ControlHintBar")
	_check.call("%s: unchanged, with no co-op part" % [tag], (
			not coop.is_bound()
			and not coop.get_bar().visible
			and hints.controller == _screen.get_controller()
			and is_equal_approx(hints.right_margin, 316.0)
			and not coop.open_maps()
	))
	_close_screen()
	_saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# A new multiplayer run of seat_count seats, past its starting offers, inside its first floor-1
# Standard combat (every seat's vote), its battle begun, and the gameplay screen open on it; with
# a swap, seat 0's first unit is swapped for seat 1's first and every seat's swap window opens.
# Null when any step failed.
func _start(seat_count: int, with_swap: bool = false) -> CampaignSession:
	_start_files()
	var steam_ids: PackedInt64Array = []
	for seat: int in seat_count:
		steam_ids.append(STEAM_BASE + seat)
	_saves.call(&"start_new_multiplayer_run", steam_ids)
	var run: CampaignSession = _service.get(&"session")
	if run == null or run.run == null:
		return null
	for seat: int in run.seats:
		run.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	if with_swap:
		var mine: String = _unit_of(run.run, 0)
		var theirs: String = _unit_of(run.run, 1)
		_service.call(&"submit_command", ProposeSwapCommand.new(0, mine, 1, theirs))
		_service.call(&"submit_command", AnswerSwapCommand.new(1, 0, true, mine, theirs))
	if _enter_battle(run, with_swap) != OK:
		return null
	_open_screen()
	return run


# Votes run into its first floor-1 Standard combat and begins the battle, every seat's opening
# swap as swap_window says. Returns the begin's error.
func _enter_battle(run: CampaignSession, swap_window: bool) -> Error:
	for node: int in run.run.next_nodes():
		if run.run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		for seat: int in run.seats:
			_service.call(&"submit_command", RouteVoteCommand.for_session(run, seat, node))
		break
	if run.run.flow.stage != RunFlow.Stage.NODE:
		return ERR_UNCONFIGURED
	var request: CampaignSession.BattleRequest = run.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return ERR_CANT_CREATE
	for seat: int in run.seats:
		request.opening_swap[seat] = swap_window
	return _service.call(&"begin_battle", request)


# The gameplay screen on the run in progress, its end hold longer than any case; the send panel
# may open as soon as a map ends, so no case waits for the banner.
func _open_screen() -> void:
	_screen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate() as BattleScreen
	_screen.end_banner_time = LONG_HOLD
	_root.add_child(_screen)
	_screen.get_coop().send_offer_delay = 0.0
	BattleViewCases.settle(_screen.get_view())


func _close_screen() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func _start_files() -> void:
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", 1)


# Closes the screen and the save file and deletes the test saves; a run still on is abandoned.
func _finish() -> void:
	_close_screen()
	if _saves.call(&"has_multiplayer_campaign"):
		_saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# A relay under each harness branch, seating the host and the client, and the client's mirror,
# not started; null when it can't be built.
func _rig(harness: NetHarness, host: CampaignSession) -> ClientMirror:
	var directory: SeatDirectory = SeatDirectory.new()
	directory.add_seat(CampaignData.HOST_SEAT, STEAM_BASE, harness.peer_id(0))
	directory.add_seat(1, STEAM_BASE + 1, harness.peer_id(1))
	var relays: Array[NetRelayScript] = []
	for index: int in harness.size():
		var relay: NetRelayScript = NetRelayScript.new()
		relay.name = &"NetRelay"
		harness.branch(index).add_child(relay)
		relay.seats = directory
		relays.append(relay)
	return ClientMirror.new(relays[1], host.rng.run_seed)


func _stop_rig(harness: NetHarness, mirror: ClientMirror) -> void:
	if mirror != null:
		mirror.close()
	harness.stop()
	_finish()


# Ends map's combat with winner, as the objectives check would, sent as its own batch.
func _win(map: CombatSession, winner: CombatFact.CombatSide) -> void:
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = winner
	map.engine.record(ended)
	map.flush("test end")


# Freezes map as a co-op map with no player unit left freezes: every player unit defeated, held
# after its enemy phase (CombatEncounter.is_frozen).
func _freeze(map: CombatSession) -> void:
	for unit_id: String in map.state.units_of(PLAYER):
		map.state.defeat(map.engine, unit_id, "")
	map.state.phase_side = ENEMY
	map.state.is_phase_ended = true


# The first living unit of seat's army that isn't its commander; empty when there is none.
func _unit_of(run: CampaignRunState, seat: int) -> String:
	var seat_run: SeatRun = run.seat_run(seat)
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id:
			return unit.instance_id
	return ""


func _map_row(panel: SendPanel, session_id: int) -> MapStatusRow:
	for row: MapStatusRow in panel.get_map_rows():
		if row.session_id == session_id:
			return row
	return null


func _map_row_of(panel: MapsPanel, session_id: int) -> MapStatusRow:
	for row: MapStatusRow in panel.get_rows():
		if row.session_id == session_id:
			return row
	return null


func _focus() -> Control:
	return _root.gui_get_focus_owner()


# Presses action on device: keys (its key) or pad (its button).
func _press(device: StringName, action: StringName) -> void:
	var keys: Dictionary[StringName, Key] = {&"ui_accept": KEY_ENTER, &"ui_down": KEY_DOWN}
	var pads: Dictionary[StringName, JoyButton] = {
		&"ui_accept": JOY_BUTTON_A, &"ui_down": JOY_BUTTON_DPAD_DOWN,
	}
	if device == &"pad":
		_press_pad(pads[action])
	else:
		_press_key(keys[action])


# Sorts the containers under node twice, parents first, as a frame's deferred sort would.
func _lay_out(node: Node) -> void:
	for _pass: int in 2:
		for found: Node in node.find_children("*", "Container", true, false):
			found.notification(Container.NOTIFICATION_SORT_CHILDREN)


# A left click at the middle of control, its screen laid out first.
func _click(control: Control) -> void:
	_lay_out(_screen)
	var point: Vector2 = control.get_global_rect().get_center()
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		_root.push_input(click, true)


func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = is_down
		_root.push_input(event, true)


func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		_root.push_input(event, true)
