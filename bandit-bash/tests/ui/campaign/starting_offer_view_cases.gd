# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_offer_view_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The starting heirloom offer's view for tests/ui/campaign/run_all.gd, laid out at 1280×720 over
## real runs whose offers hold the heirloom each case wants: War Chest taken by keyboard;
## Abundance by mouse, a recruit card clicked, Back clicked; Mercenary Contract by pad, A through
## the recruit and the unit, B back each step without the pause menu, the commander greyed out;
## Ancestral Weapon by keyboard into the placement panel, Esc back out of it and the convoy chosen;
## Veteran Company's unit column; three refused heirlooms shown with their reasons and Skip. Every
## command the view builds is one the run accepts. The real screen is the walk's, by keyboard.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

const VIEW_SCENE: PackedScene = preload("res://ui/campaign/starting_offer_view.tscn")
const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const MERCENARY: String = "mercenary"

# Seeds searched for an offer holding the heirloom a case wants.
const SEEDS: int = 300

# The layout every case runs at: the project's base viewport.
const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

var _check: Callable
var _root: Window = null
var _catalog: EffectCatalog.Index = null
var _map_rules: CampaignMapRules = null
var _commands: Array[StartingHeirloomCommand] = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the view is added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	_catalog = EffectCatalog.index()
	_map_rules = load(RULES_PATH) as CampaignMapRules
	_ok("view: the catalog and map rules load", _catalog != null and _map_rules != null, "")
	if _catalog == null or _map_rules == null:
		return
	_test_key()
	_test_mouse()
	_test_pad()
	_test_weapon_by_key()
	_test_upgrade_column()
	_test_refused()


func _test_key() -> void:
	var session: CampaignSession = _session_offering("war_chest")
	var view: StartingOfferView = _open(session)
	var index: int = _index_of(session, "war_chest")
	var cards: Array[Button] = view.get_cards()
	_ok("key: three heirloom cards, each with its name and bonus line", (
			cards.size() == 3 and cards[index].text.contains("War Chest")
			and cards[index].text.contains("gain 100 gold") and view.focus_first()
	), "" if cards.is_empty() else cards[index].text)
	cards[index].grab_focus()
	_press_key(KEY_ENTER)
	_ok("key: Enter on War Chest builds its command at once, which the run accepts", (
			_commands.size() == 1 and _commands[0].option == index
			and _commands[0].recruit == StartingHeirloomCommand.NO_CHOICE
			and _commands[0].validate(session.run).is_empty()
	), _last_problem(session))
	_close(view)


func _test_mouse() -> void:
	var session: CampaignSession = _session_offering("abundance")
	var view: StartingOfferView = _open(session)
	var index: int = _index_of(session, "abundance")
	_click(view.get_cards()[index])
	var recruits: Array[Button] = view.get_cards()
	_ok("mouse: a click on Abundance shows its two recruits and Back", (
			view.get_step() == StartingOfferView.Step.RECRUIT and recruits.size() == 2
			and recruits[0] is RecruitOfferCard and view.get_back_button().visible
			and recruits[0].text.contains("level 1") and recruits[0].text.contains("Brings")
			and _commands.is_empty()
	), str(view.get_step()))
	_click(view.get_back_button())
	_ok("mouse: Back returns to the three heirlooms", (
			view.get_step() == StartingOfferView.Step.HEIRLOOM and view.get_cards().size() == 3
	))
	_click(view.get_cards()[index])
	_click(view.get_cards()[1])
	_ok("mouse: a click on the second recruit builds the command, which the run accepts", (
			_commands.size() == 1 and _commands[0].option == index and _commands[0].recruit == 1
			and _commands[0].validate(session.run).is_empty()
	), _last_problem(session))
	_close(view)


func _test_pad() -> void:
	var session: CampaignSession = _session_offering("mercenary_contract")
	var view: StartingOfferView = _open(session)
	var index: int = _index_of(session, "mercenary_contract")
	view.get_cards()[index].grab_focus()
	_press_pad(JOY_BUTTON_A)
	view.focus_first()
	var to_recruits: bool = view.get_step() == StartingOfferView.Step.RECRUIT
	_press_pad(JOY_BUTTON_B)
	var back_to_three: bool = view.get_step() == StartingOfferView.Step.HEIRLOOM
	view.get_cards()[index].grab_focus()
	_press_pad(JOY_BUTTON_A)
	view.focus_first()
	_press_pad(JOY_BUTTON_A)
	var buttons: Array[Button] = view.get_unit_panel().get_choice_buttons()
	var commander_button: Button = buttons[0] if not buttons.is_empty() else null
	_ok("pad: A to the recruits, B back to the three, A through a recruit to the units", (
			to_recruits and back_to_three
			and view.get_step() == StartingOfferView.Step.UNIT
			and commander_button != null and commander_button.disabled
			and commander_button.focus_mode == Control.FOCUS_NONE
	), "" if commander_button == null else commander_button.text)
	_press_pad(JOY_BUTTON_B)
	var back_to_recruits: bool = view.get_step() == StartingOfferView.Step.RECRUIT
	view.focus_first()
	_press_pad(JOY_BUTTON_A)
	_press_pad(JOY_BUTTON_A)
	var eligible: PackedStringArray = StartingOffer.eligible_units(session.run, 0, _catalog, true)
	_ok("pad: B back to the recruits, then A on the first unit that can leave", (
			back_to_recruits and _commands.size() == 1 and _commands[0].recruit == 0
			and _commands[0].unit_id == eligible[0]
			and _commands[0].validate(session.run).is_empty()
	), _last_problem(session))
	_close(view)


func _test_weapon_by_key() -> void:
	var session: CampaignSession = _session_offering("ancestral_weapon")
	var view: StartingOfferView = _open(session)
	view.get_cards()[_index_of(session, "ancestral_weapon")].grab_focus()
	_press_key(KEY_ENTER)
	view.focus_first()
	var weapons: int = view.get_cards().size()
	_press_key(KEY_ENTER)
	var placement: PlacementPanel = view.get_placement_panel()
	var is_placing: bool = view.get_step() == StartingOfferView.Step.PLACEMENT and placement.visible
	_press_key(KEY_ESCAPE)
	var is_back: bool = view.get_step() == StartingOfferView.Step.WEAPON and not placement.visible
	view.focus_first()
	_press_key(KEY_ENTER)
	var convoy: Button = null
	for button: Button in placement.get_choice_buttons():
		if button.text.begins_with("Send it to the convoy"):
			convoy = button
	if convoy != null:
		convoy.grab_focus()
		_press_key(KEY_ENTER)
	_ok("key: Ancestral Weapon's three weapons, the placement, Esc back, then the convoy", (
			weapons == 3 and is_placing and is_back and _commands.size() == 1
			and _commands[0].weapon == 0 and _commands[0].placement != null
			and _commands[0].placement.destination == ItemPlacement.Destination.CONVOY
			and _commands[0].validate(session.run).is_empty()
	), _last_problem(session))
	_close(view)


func _test_upgrade_column() -> void:
	var session: CampaignSession = _session_offering("veteran_company")
	var view: StartingOfferView = _open(session)
	view.get_cards()[_index_of(session, "veteran_company")].grab_focus()
	_press_key(KEY_ENTER)
	var buttons: Array[Button] = view.get_unit_panel().get_choice_buttons()
	var enabled: int = 0
	for button: Button in buttons:
		enabled += 0 if button.disabled else 1
	_press_key(KEY_DOWN)
	_press_key(KEY_ENTER)
	var eligible: PackedStringArray = StartingOffer.eligible_units(session.run, 0, _catalog, false)
	_ok("key: Veteran Company's column: three units and Back, the commander greyed; Down, Enter", (
			view.get_step() == StartingOfferView.Step.UNIT
			and buttons.size() == 5 and enabled == 4 and buttons[0].disabled
			and _commands.size() == 1 and _commands[0].unit_id == eligible[1]
			and _commands[0].validate(session.run).is_empty()
	), _last_problem(session))
	_close(view)


func _test_refused() -> void:
	var session: CampaignSession = _session(4)
	var seat_run: SeatRun = session.run.seat_run(0)
	var offer: StartingOffer = StartingOffer.new()
	for heirloom_id: String in ["veteran_company", "mercenary_contract", "ancestral_weapon"]:
		offer.options.append(StartingOffer.Option.new(heirloom_id))
	offer.store(seat_run)
	for unit: UnitInstance in seat_run.army.duplicate():
		if unit.instance_id != seat_run.commander_id:
			seat_run.army.erase(unit)
			seat_run.fallen.append(unit)
	var view: StartingOfferView = _open(session)
	var says_why: bool = true
	for card: Button in view.get_cards():
		says_why = (
				says_why and card.disabled and card.focus_mode == Control.FOCUS_NONE
				and card.text.contains("Can't take it:")
		)
	_click(view.get_skip_button())
	_ok("refused: every card greyed with its reason; Skip shows and builds the skip", (
			says_why and view.get_skip_button().visible and _commands.size() == 1
			and _commands[0].option == StartingHeirloomCommand.SKIP
			and _commands[0].validate(session.run).is_empty()
	), _last_problem(session))
	_close(view)


# --- Helpers -----------------------------------------------------------------------------------


# The view on session's seat 0 offer, laid out at SCREEN_SIZE, its commands collected.
func _open(session: CampaignSession) -> StartingOfferView:
	_commands.clear()
	var view: StartingOfferView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	# Anchored top-left, so its size holds at SCREEN_SIZE whatever the window is.
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = SCREEN_SIZE
	view.command_ready.connect(_commands.append)
	view.open(session, 0, _catalog)
	_lay_out(view)
	view.focus_first()
	return view


func _close(view: StartingOfferView) -> void:
	_root.remove_child(view)
	view.free()


# Sorts the view's containers twice, parents first, as a frame's deferred sort would.
func _lay_out(view: Control) -> void:
	for _pass: int in 2:
		for node: Node in view.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# A left click at the middle of control, its view laid out first.
func _click(control: Control) -> void:
	var view: Control = control
	while view != null and not view is StartingOfferView:
		view = view.get_parent_control()
	if view != null:
		_lay_out(view)
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


func _session(run_seed: int) -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			_map_rules, session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog, factions, session.ids, session.starting_offer_streams()
	)
	session.run = start.run
	return session


func _session_offering(heirloom_id: String) -> CampaignSession:
	for run_seed: int in SEEDS:
		var session: CampaignSession = _session(run_seed)
		if _index_of(session, heirloom_id) >= 0:
			return session
	_ok("view: some seed offers %s" % [heirloom_id], false, "")
	return _session(0)


func _index_of(session: CampaignSession, heirloom_id: String) -> int:
	var offer: StartingOffer = StartingOffer.pending(session.run.seat_run(0))
	for index: int in offer.options.size():
		if offer.options[index].heirloom_id == heirloom_id:
			return index
	return -1


func _last_problem(session: CampaignSession) -> String:
	if _commands.is_empty():
		return "no command"
	return _commands[-1].validate(session.run)


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
