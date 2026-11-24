# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_pause_menu_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The co-op pause menu for tests/ui/campaign/run_all.gd, on a 2-seat host run through the real
## SaveService and CampaignService at 1280×720, opened as the host and as a client
## ([method PauseMenu.open_as], as no Steam session runs here). On the campaign map and the battle
## screen: each role's buttons, walked by keys, mouse and pad; the tree never pausing, so the game
## goes on; the screen beneath taking no key meanwhile; the hint bar's co-op set, never PAUSED;
## Save & Quit's and Forfeit's questions, declined; Options and the board key in the buttons'
## place; a forfeit sent while the run is paused, refused "paused" and shown. Solo unchanged: the
## tree paused, PAUSED hints, Save & Quit first. Nothing here changes scene: the confirmed Save &
## Quit and a resolved forfeit route, so the net suite covers them. Autoloads are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const NetRelayScript = preload("res://scripts/autoload/net_relay.gd")

const MAP_SCENE: String = "res://ui/campaign/campaign_map_screen.tscn"
const GAMEPLAY_SCENE: String = "res://ui/battle/gameplay.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 3
# Two made-up Steam ids: the host's, then the teammate's.
const STEAM_IDS: Array[int] = [0x3111, 0x3222]

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# A hold longer than any case, so the battle's end never routes inside one.
const LONG_HOLD: float = 600.0

# SeatDirectory.State.DROPPED and CONNECTED, as the host's seat change sends them.
const DROPPED: int = 1
const CONNECTED: int = 0

const MENU_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_accept", &"ui_cancel"]

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _relay: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")
	_service = root.get_node(^"CampaignService")
	_relay = root.get_node(^"NetRelay")


## Runs every case. Call only with a test user folder.
func run() -> void:
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	if _new_run() != null:
		_test_map_host()
		_test_map_client()
		_test_map_solo()
		_test_battle()
	if _saves.call(&"has_multiplayer_campaign"):
		_saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# A new 2-seat host run past its starting offers, on the map.
func _new_run() -> CampaignSession:
	var ids: PackedInt64Array = []
	for steam_id: int in STEAM_IDS:
		ids.append(steam_id)
	var err: Error = _saves.call(&"start_new_multiplayer_run", ids)
	var session: CampaignSession = _session()
	_check.call("pause menu: a new 2-seat host run starts", (
			err == OK and session != null and session.run != null
	), error_string(err))
	if session == null or session.run == null:
		return null
	for seat: int in session.seats:
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	return session


# The host's menu by keys: Resume, Options, Save & Quit; the game going on beneath, which takes
# no key; Save & Quit asking first and Esc declining; Options in the buttons' place; the co-op
# hints; Esc closing it with the focus given back.
func _test_map_host() -> void:
	var screen: Control = _add(MAP_SCENE)
	var menu: PauseMenu = screen.get_node(^"PauseMenu") as PauseMenu
	var bar: ControlHintBar = screen.get_node(^"ControlHintBar") as ControlHintBar
	var army: Control = screen.call(&"get_army_view")
	var before: Control = _root.gui_get_focus_owner()
	menu.open_as(PauseMenu.Role.HOST)
	menu.keep_focus()
	_lay_out(screen)
	bar.refresh()
	_check.call("map host: Resume, Options, Save & Quit; the tree goes on; the co-op hints", (
			_shown_buttons(menu) == ["Resume", "Options", "Save & Quit"]
			and _title(menu) == "Menu"
			and not _root.get_tree().paused and screen.can_process()
			and _button(menu, &"ResumeButton").has_focus()
			and bar.get_context() == PauseMenu.HINT_MENU
			and bar.get_shown_actions() == MENU_ACTIONS
			and bar.get_text().contains("Close") and not bar.get_text().contains("Resume")
	), "%s; %s; '%s'" % [_shown_buttons(menu), bar.get_context(), bar.get_text()])
	_press_key(KEY_CTRL)
	_check.call("map host: a key the map reads (Ctrl, the army) does nothing under the menu", (
			not army.visible and menu.is_open()
	), "army %s" % [army.visible])
	_press_key(KEY_DOWN)
	var on_options: bool = _button(menu, &"OptionsButton").has_focus()
	_press_key(KEY_DOWN)
	var on_save: bool = _button(menu, &"SaveQuitButton").has_focus()
	_press_key(KEY_DOWN)
	var stays: bool = _button(menu, &"SaveQuitButton").has_focus()
	var seq_before: int = (_saves.get(&"campaign") as CampaignData).checkpoint_seq
	_press_key(KEY_ENTER)
	var confirm: MenuConfirm = menu.get_save_quit_confirm()
	bar.refresh()
	var asks: bool = (
			confirm.visible and confirm.get_cancel_button().has_focus()
			and bar.get_context() == PauseMenu.HINT_CONFIRM
	)
	_press_key(KEY_ESCAPE)
	_check.call("map host (keys): down the column; Save & Quit asks first, Esc declines", (
			on_options and on_save and stays and asks
			and not confirm.visible and menu.is_open()
			and _button(menu, &"SaveQuitButton").has_focus()
			and (_saves.get(&"campaign") as CampaignData).checkpoint_seq == seq_before
	), "options %s, save %s, stays %s, asks %s" % [on_options, on_save, stays, asks])
	_button(menu, &"OptionsButton").grab_focus()
	_press_key(KEY_ENTER)
	var options: OptionsPanel = menu.get_options_panel()
	var slider: HSlider = options.get_volume_row(SettingsData.Channel.MASTER).get_slider()
	bar.refresh()
	var options_shown: bool = (
			menu.is_options_open() and slider.has_focus()
			and bar.get_context() == PauseMenu.HINT_OPTIONS
	)
	_press_key(KEY_ESCAPE)
	_check.call("map host (keys): Options shows the settings in the buttons' place; Esc back", (
			options_shown and not menu.is_options_open() and menu.is_open()
			and _button(menu, &"OptionsButton").has_focus()
	), "shown %s" % [options_shown])
	_press_key(KEY_ESCAPE)
	bar.refresh()
	_check.call("map host (keys): Esc closes it, the focus given back, the map's hints again", (
			not menu.is_open() and _root.gui_get_focus_owner() == before
			and bar.get_context() != PauseMenu.HINT_MENU
	), "%s" % [bar.get_context()])
	_remove(screen)


# The client's menu by pad and mouse: Resume, Options, Leave Match, Forfeit; Forfeit asks first,
# B declines; a forfeit sent while another seat is dropped is refused "paused" and shown, Forfeit
# offered again; Resume by mouse.
func _test_map_client() -> void:
	_service.call(&"set_local_seat", 1)
	var screen: Control = _add(MAP_SCENE)
	var menu: PauseMenu = screen.get_node(^"PauseMenu") as PauseMenu
	menu.open_as(PauseMenu.Role.CLIENT)
	menu.keep_focus()
	_lay_out(screen)
	_check.call("map client: Resume, Options, Leave Match, Forfeit; the tree goes on", (
			_shown_buttons(menu) == ["Resume", "Options", "Leave Match", "Forfeit"]
			and not _root.get_tree().paused
	), "%s" % [_shown_buttons(menu)])
	for _step: int in 3:
		_press_pad(JOY_BUTTON_DPAD_DOWN)
	var forfeit: Button = _button(menu, &"ForfeitButton")
	var on_forfeit: bool = forfeit.has_focus()
	_press_pad(JOY_BUTTON_A)
	var confirm: MenuConfirm = menu.get_forfeit_confirm()
	var asks: bool = confirm.visible and confirm.get_cancel_button().has_focus()
	_press_pad(JOY_BUTTON_B)
	_check.call("map client (pad): d-pad to Forfeit; A asks first; B declines, nothing sent", (
			on_forfeit and asks and not confirm.visible and forfeit.has_focus()
			and menu.get_status_text().is_empty()
			and _session().seats.has(1)
	), "on %s, asks %s; '%s'" % [on_forfeit, asks, menu.get_status_text()])
	_set_seat(0, DROPPED)
	_press_pad(JOY_BUTTON_A)
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	var on_confirm: bool = confirm.get_confirm_button().has_focus()
	_press_pad(JOY_BUTTON_A)
	var status: String = menu.get_status_text()
	_set_seat(0, CONNECTED)
	_check.call("map client (pad): a forfeit while the run is paused is refused \"paused\"", (
			on_confirm and status == "Couldn't forfeit: paused."
			and not forfeit.disabled and menu.is_open()
			and _session().seats.has(1)
	), "'%s'" % [status])
	_click(_button(menu, &"ResumeButton"))
	_check.call("map client (mouse): Resume closes it", not menu.is_open())
	_remove(screen)
	_service.call(&"set_local_seat", CampaignData.HOST_SEAT)


# Solo as before: the tree paused, PAUSED hints, Save & Quit focused first, no co-op buttons.
func _test_map_solo() -> void:
	var screen: Control = _add(MAP_SCENE)
	var menu: PauseMenu = screen.get_node(^"PauseMenu") as PauseMenu
	var bar: ControlHintBar = screen.get_node(^"ControlHintBar") as ControlHintBar
	menu.open_as(PauseMenu.Role.SOLO)
	menu.keep_focus()
	bar.refresh()
	_check.call("map solo: unchanged - paused, PAUSED hints, Save & Quit first", (
			PauseMenu.role_now() == PauseMenu.Role.SOLO
			and _root.get_tree().paused
			and _shown_buttons(menu) == ["Resume", "Save & Quit"]
			and _title(menu) == "Paused"
			and _button(menu, &"SaveQuitButton").has_focus()
			and bar.get_context() == ScreenHints.PAUSED_CONTEXT
	), "%s; %s" % [_shown_buttons(menu), bar.get_context()])
	menu.close()
	_check.call("map solo: closing unpauses", not _root.get_tree().paused)
	_remove(screen)


# The battle screen, the host's menu by mouse and keys: Board Key among its buttons; the board
# takes no key under it (T doesn't ask to end the turn) and keeps processing; the board key in
# the buttons' place with its own hints; a client's Forfeit asks and Stay declines by mouse.
func _test_battle() -> void:
	var session: CampaignSession = _session()
	if _enter_battle(session) != OK:
		_check.call("battle: the co-op battle begins", false)
		return
	var screen: BattleScreen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate() as BattleScreen
	screen.end_banner_time = LONG_HOLD
	_root.add_child(screen)
	BattleViewCases.settle(screen.get_view())
	var controller: BattleController = screen.get_node(^"BattleController") as BattleController
	var map: CombatSession = session.encounter.session_of_seat(CampaignData.HOST_SEAT)
	_service.call(&"submit_combat", StartCommand.new(CampaignData.HOST_SEAT), map.session_id)
	BattleViewCases.settle(screen.get_view())
	var context_before: StringName = controller.get_hint_context()
	var menu: PauseMenu = screen.get_node(^"PauseMenu") as PauseMenu
	var bar: ControlHintBar = screen.get_node(^"Hud/ControlHintBar") as ControlHintBar
	menu.open_as(PauseMenu.Role.HOST)
	menu.keep_focus()
	_lay_out(screen)
	bar.refresh()
	_press_key(KEY_T)
	_check.call("battle host: Board Key among the buttons; the board goes on but takes no key", (
			_shown_buttons(menu) == ["Resume", "Board Key", "Options", "Save & Quit"]
			and not _root.get_tree().paused and screen.get_view().can_process()
			and controller.get_hint_context() == context_before
			and bar.get_context() == PauseMenu.HINT_MENU
	), "%s; %s then %s; bar %s" % [
		_shown_buttons(menu), context_before, controller.get_hint_context(), bar.get_context(),
	])
	_click(_button(menu, &"BoardKeyButton"))
	bar.refresh()
	var key_shown: bool = menu.is_board_key_open() and bar.get_context() == PauseMenu.HINT_BOARD_KEY
	_press_key(KEY_ESCAPE)
	_check.call("battle host (mouse): Board Key shows the key; Esc goes back to the buttons", (
			key_shown and not menu.is_board_key_open() and menu.is_open()
			and _button(menu, &"BoardKeyButton").has_focus()
	), "shown %s" % [key_shown])
	_press_key(KEY_ESCAPE)
	var closed_context: StringName = controller.get_hint_context()
	# The same T now reaches the board, so the menu was what held it off.
	_press_key(KEY_T)
	var after_t: StringName = controller.get_hint_context()
	_check.call("battle host (keys): Esc closes it; turn input is back, T acting again", (
			not menu.is_open() and closed_context == context_before and after_t != context_before
	), "%s, then %s after T" % [closed_context, after_t])
	controller.step_back()
	menu.open_as(PauseMenu.Role.CLIENT)
	_lay_out(screen)
	_click(_button(menu, &"ForfeitButton"))
	var confirm: MenuConfirm = menu.get_forfeit_confirm()
	var asks: bool = confirm.visible
	_click(confirm.get_cancel_button())
	_check.call("battle client (mouse): Forfeit asks first; Stay declines", (
			asks and not confirm.visible and menu.is_open()
			and _shown_buttons(menu) == ["Resume", "Board Key", "Options", "Leave Match", "Forfeit"]
	), "asks %s; %s" % [asks, _shown_buttons(menu)])
	menu.close()
	screen.free()


# Votes the run into its first floor-1 Standard combat and begins the battle, no swap window.
func _enter_battle(session: CampaignSession) -> Error:
	for node: int in session.run.next_nodes():
		if session.run.graph.type_of(node) != CampaignGraph.NodeType.STANDARD:
			continue
		for seat: int in session.seats:
			_service.call(&"submit_command", RouteVoteCommand.for_session(session, seat, node))
		break
	if session.run.flow.stage != RunFlow.Stage.NODE:
		return ERR_UNCONFIGURED
	var request: CampaignSession.BattleRequest = session.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return ERR_CANT_CREATE
	for seat: int in session.seats:
		request.opening_swap[seat] = false
	return _service.call(&"begin_battle", request)


# Tells the NetRelay autoload seat's connection is now state, as the host's word would; it asks
# its API whether it is the host, so Godot's solo peer stands in meanwhile (as 491_seat_wait).
# The wait overlay is refreshed at once: later case files run in this same frame, and one left
# showing would take their clicks.
func _set_seat(seat: int, state: int) -> void:
	var api: MultiplayerAPI = _relay.multiplayer
	var kept: MultiplayerPeer = api.multiplayer_peer
	if kept == null:
		api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_relay.call(&"_seat_changed", seat, state, 0.0)
	if kept == null:
		api.multiplayer_peer = null
	for child: Node in _relay.get_children():
		if child is SeatWaitOverlay:
			(child as SeatWaitOverlay).refresh()


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


func _button(menu: PauseMenu, node_name: StringName) -> Button:
	return menu.get_node("%%%s" % [node_name]) as Button


func _title(menu: PauseMenu) -> String:
	return (menu.get_node(^"%Title") as Label).text


# The texts of the menu's visible buttons, top to bottom.
func _shown_buttons(menu: PauseMenu) -> Array[String]:
	var shown: Array[String] = []
	for child: Node in menu.get_node(^"%Column").get_children():
		var button: Button = child as Button
		if button != null and button.visible:
			shown.append(button.text)
	return shown


func _add(path: String) -> Control:
	var scene: PackedScene = load(path)
	var screen: Control = scene.instantiate()
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = SCREEN_SIZE
	_lay_out(screen)
	return screen


func _remove(screen: Node) -> void:
	_root.remove_child(screen)
	screen.free()


# Sorts the containers under node twice, parents first, as a frame's deferred sort would.
func _lay_out(node: Node) -> void:
	for _pass: int in 2:
		for found: Node in node.find_children("*", "Container", true, false):
			found.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _click(control: Control) -> void:
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
