# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     leaving_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The event panel's "which unit leaves?" step over runs in memory, by keyboard, mouse and pad: a
## recruit with room never asks; a recruit into a full army asks, each unit with level and HP,
## then the named unit leaves, its items to the convoy, and the archer joins; a revive into a full
## army lists the fallen ungreyed, then asks which unit leaves. The commander and a unit whose
## items the convoy can't take are greyed with their reasons; with none able to leave only Back
## is left. Back steps one choice at a time (a placement to the leaving unit, it to the saved
## fallen chooser, that to the cards); a refusal says why and changes nothing; a quit at the step
## resumes at the fallen chooser; the step is hinted as a chooser.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

const SCREEN_SCRIPT: String = "res://ui/campaign/events/event_screen.gd"
const DEVICES: PackedStringArray = ["key", "mouse", "pad"]
const COMMANDER_REASON: String = "(the commander never leaves the army)"
const CONVOY_REASON: String = "the convoy can't take its "

var _check: Callable
var _root: Window = null
var _fx: Fixture = null

# Every step the panel under test entered, in order.
var _steps: Array[EventPanel.Step] = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the panels are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_fx = Fixture.new(root)


func run() -> void:
	if not _fx.base.is_ready():
		_ok("the fixture's catalog and rules load", false)
		return
	for device: String in DEVICES:
		_test_room(device)
		_test_recruit(device)
		_test_revive(device)
		_test_back(device)
	_test_greyed()
	_test_none_can_leave()
	_test_refused()
	_test_continue()
	_test_hint()


func _test_room(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp(), 1, true)
	var seat_run: SeatRun = made.run.seat_run(0)
	var size: int = seat_run.army.size()
	var log_size: int = made.run.fact_log.size()
	var panel: EventPanel = _open(made)
	var pressed: bool = _press_card(panel, device, Fixture.HIRE)
	_ok("%s: a recruit with room never asks which unit leaves; the archer joins" % [device], (
			pressed and _is_done(panel, Fixture.HIRE)
			and not _steps.has(EventPanel.Step.LEAVING)
			and seat_run.army.size() == size + 1
			and seat_run.army[-1].unit_type_id == Fixture.RECRUIT_TYPE
			and _kinds_since(made, log_size).find(CampaignFact.Kind.UNIT_DISMISSED) == -1
	), _state(panel))
	_fx.close_panel(panel)


func _test_recruit(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var size: int = seat_run.army.size()
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var carried: PackedStringArray = leaving.item_ids()
	var log_size: int = made.run.fact_log.size()
	var panel: EventPanel = _open(made)
	var pressed: bool = _press_card(panel, device, Fixture.HIRE)
	var chooser: EventChooser = panel.get_chooser()
	var question: String = chooser.get_question()
	var buttons: Array[Button] = chooser.get_choice_buttons()
	var rows_ok: bool = buttons.size() == size + 1 and buttons[-1].text == "Back"
	for index: int in mini(size, buttons.size()):
		var unit: UnitInstance = seat_run.army[index]
		var title: String = EventScreenModel.title_of(unit, _fx.base.catalog)
		rows_ok = rows_ok and buttons[index].text.begins_with(
				"%s, level %d, HP " % [title, unit.level]
		)
	var asked: bool = (
			pressed and panel.get_step() == EventPanel.Step.LEAVING and rows_ok
			and question == ("Hire an Archer: the army is full (%d of %d). Which unit leaves? "
					+ "Its items go to the convoy.") % [size, size]
	)
	var chose: bool = asked and _fx.press(device, buttons[seat_run.army.find(leaving)], "down")
	var sent: EventOptionCommand = _fx.commands[-1] as EventOptionCommand
	var kinds: Array[CampaignFact.Kind] = _kinds_since(made, log_size)
	var dismissed_at: int = kinds.find(CampaignFact.Kind.UNIT_DISMISSED)
	var in_convoy: bool = not carried.is_empty()
	for item_id: String in carried:
		in_convoy = in_convoy and seat_run.convoy.has(item_id)
	_ok("%s: a recruit into a full army asks which unit leaves, each with level and HP" % [
		device,
	], asked, "%s | %s" % [question, " | ".join(_texts(buttons))])
	_ok("%s: the named unit leaves, its items to the convoy, and the archer takes its place" % [
		device,
	], (
			chose and _is_done(panel, Fixture.HIRE)
			and sent != null and sent.choice.replaced_id == leaving.instance_id
			and seat_run.army.size() == size and not seat_run.army.has(leaving)
			and seat_run.army[-1].unit_type_id == Fixture.RECRUIT_TYPE
			and in_convoy and _fx.base.is_whole(seat_run)
			and dismissed_at >= 0
			and kinds.find(CampaignFact.Kind.UNIT_RECRUITED) > dismissed_at
	), _state(panel))
	_fx.close_panel(panel)


func _test_revive(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.shrine(), 1, true)
	var seat_run: SeatRun = made.run.seat_run(0)
	_fx.fill_army(made, seat_run)
	var fallen: UnitInstance = seat_run.fallen[0]
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var weapon_id: String = leaving.weapon_id
	var panel: EventPanel = _open(made)
	var pressed: bool = _press_card(panel, device, Fixture.PRAYER)
	var fallen_button: Button = panel.get_chooser().get_choice_buttons()[0]
	var listed: bool = (
			pressed and panel.get_step() == EventPanel.Step.CHOOSER
			and made.run.events.seat_event(0).choosing == Fixture.PRAYER
			and fallen_button.text.contains("fallen") and not fallen_button.disabled
	)
	_ok("%s: in a full army the fallen chooser greys no fallen unit" % [device], listed,
			fallen_button.text)
	var picked: bool = listed and _fx.press(device, fallen_button, "down")
	var asked: bool = picked and panel.get_step() == EventPanel.Step.LEAVING
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var chose: bool = asked and _fx.press(device, buttons[seat_run.army.find(leaving)], "down")
	_ok("%s: the fallen unit first, then which unit leaves; it rejoins in the leaver's place" % [
		device,
	], (
			chose and _is_done(panel, Fixture.PRAYER)
			and seat_run.army.has(fallen) and not seat_run.fallen.has(fallen)
			and not seat_run.army.has(leaving) and not seat_run.fallen.has(leaving)
			and seat_run.convoy.has(weapon_id) and _fx.base.is_whole(seat_run)
	), _state(panel))
	_fx.close_panel(panel)


func _test_back(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.shrine(), 1, true)
	var seat_run: SeatRun = made.run.seat_run(0)
	_fx.fill_army(made, seat_run)
	var army: Array[UnitInstance] = seat_run.army.duplicate()
	var panel: EventPanel = _open(made)
	panel.get_cards()[Fixture.PRAYER].pressed.emit()
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	var leaving_shown: bool = panel.get_step() == EventPanel.Step.LEAVING
	_fx.back(device, panel.get_chooser().get_choice_buttons()[-1])
	var at_fallen: bool = (
			panel.get_step() == EventPanel.Step.CHOOSER
			and made.run.events.seat_event(0).choosing == Fixture.PRAYER
			and panel.get_chooser().get_question().contains("which fallen unit")
	)
	_fx.back(device, panel.get_chooser().get_choice_buttons()[-1])
	_ok("back %s: the leaving unit to the saved fallen chooser, that to the cards" % [device], (
			leaving_shown and at_fallen and panel.get_step() == EventPanel.Step.OPTIONS
			and made.run.events.seat_event(0).choosing == EventRunState.NO_OPTION
			and seat_run.army == army and not _root.get_tree().paused
	), _state(panel))
	_fx.close_panel(panel)

	var hire_run: CampaignSession = _fx.session_with(Fixture.camp())
	var hire: EventPanel = _open(hire_run)
	var sent: int = _fx.commands.size()
	hire.get_cards()[Fixture.HIRE].pressed.emit()
	var asked: bool = hire.get_step() == EventPanel.Step.LEAVING
	_fx.back(device, hire.get_chooser().get_choice_buttons()[-1])
	_ok("back %s: a recruit's leaving step returns to the cards, nothing sent" % [device], (
			asked and hire.get_step() == EventPanel.Step.OPTIONS
			and _fx.commands.size() == sent
			and hire_run.run.events.seat_event(0).chosen == EventRunState.NO_OPTION
	), _state(hire))
	_fx.close_panel(hire)

	var armed_run: CampaignSession = _fx.session_with(Fixture.camp())
	var armed: EventPanel = _open(armed_run)
	var leaving: UnitInstance = _fx.base.soldier(armed_run.run.seat_run(0))
	armed.get_cards()[Fixture.HIRE_ARMED].pressed.emit()
	var first_leaving: bool = armed.get_step() == EventPanel.Step.LEAVING
	armed.get_chooser().get_choice_buttons()[
			armed_run.run.seat_run(0).army.find(leaving)
	].pressed.emit()
	var placing: bool = armed.get_step() == EventPanel.Step.PLACEMENT
	_fx.back(device, Fixture.button_starting(
			armed.get_placement_panel().get_choice_buttons(), "Back"
	))
	_ok("back %s: the placement after the leaving unit returns to it, asked afresh" % [device], (
			first_leaving and placing and armed.get_step() == EventPanel.Step.LEAVING
			and not armed.get_placement_panel().visible
			and armed.get_chooser().get_question().contains("Which unit leaves?")
	), _state(armed))
	_fx.close_panel(armed)


func _test_greyed() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var loaded: UnitInstance = _fx.base.soldier(seat_run)
	_fx.overload_convoy(made, loaded)
	var panel: EventPanel = _open(made)
	panel.get_cards()[Fixture.HIRE].pressed.emit()
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var commander: Button = buttons[_index_of(seat_run, seat_run.commander_id)]
	var heavy: Button = buttons[seat_run.army.find(loaded)]
	var others_open: bool = true
	for index: int in seat_run.army.size():
		var unit_id: String = seat_run.army[index].instance_id
		if unit_id != seat_run.commander_id and unit_id != loaded.instance_id:
			others_open = others_open and not buttons[index].disabled
	_ok("greyed: the commander, and a unit whose items the convoy can't take, each say why", (
			commander.disabled and commander.focus_mode == Control.FOCUS_NONE
			and commander.text.ends_with(COMMANDER_REASON)
			and heavy.disabled and heavy.focus_mode == Control.FOCUS_NONE
			and heavy.text.contains(CONVOY_REASON + "%d items" % [loaded.item_ids().size()])
			and others_open
	), " | ".join(_texts(buttons)))
	_fx.close_panel(panel)


func _test_none_can_leave() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	while seat_run.convoy.size() < ItemPlacement.convoy_capacity(seat_run, _fx.base.catalog):
		_fx.base.add_to_convoy(made, Fixture.EQUIPMENT_ID)
	var panel: EventPanel = _open(made)
	var card_open: bool = not panel.get_cards()[Fixture.HIRE].disabled
	panel.get_cards()[Fixture.HIRE].pressed.emit()
	panel.focus_first()
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var greyed: int = 0
	for button: Button in buttons:
		greyed += 1 if button.disabled else 0
	_ok("none can leave: the hire stays offered; every unit is greyed and Back holds focus", (
			card_open and panel.get_step() == EventPanel.Step.LEAVING
			and greyed == seat_run.army.size()
			and _root.gui_get_focus_owner() == buttons[-1]
	), " | ".join(_texts(buttons)))
	_fx.close_panel(panel)


func _test_refused() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var army: Array[UnitInstance] = seat_run.army.duplicate()
	var log_size: int = made.run.fact_log.size()
	var panel: EventPanel = _open(made)
	panel.get_cards()[Fixture.HIRE].pressed.emit()
	var button: Button = panel.get_chooser().get_choice_buttons()[seat_run.army.find(leaving)]
	_fx.overload_convoy(made, leaving)
	var convoy: int = seat_run.convoy.size()
	button.pressed.emit()
	_ok("refused: a leaving unit the run refuses says why, stays on the step, changes nothing", (
			panel.get_step() == EventPanel.Step.LEAVING
			and panel.get_status_text().begins_with("Can't do that: ")
			and panel.get_status_text().contains(CONVOY_REASON)
			and seat_run.army == army and seat_run.convoy.size() == convoy
			and made.run.fact_log.size() == log_size
			and made.run.events.seat_event(0).chosen == EventRunState.NO_OPTION
	), panel.get_status_text())
	_fx.close_panel(panel)


func _test_continue() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.shrine(), 1, true)
	_fx.fill_army(made, made.run.seat_run(0))
	var panel: EventPanel = _open(made)
	panel.get_cards()[Fixture.PRAYER].pressed.emit()
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	var asked: bool = panel.get_step() == EventPanel.Step.LEAVING
	_fx.close_panel(panel)
	var resumed: CampaignSession = _fx.base.resume(made)
	if resumed == null:
		_ok("continue: the run resumes from its save", false, error_string(_fx.base.resume_error))
		return
	var after: EventPanel = _open(resumed)
	var buttons: Array[Button] = after.get_chooser().get_choice_buttons()
	_ok("continue: a quit at the unsaved leaving step resumes at the saved fallen chooser", (
			asked and after.get_step() == EventPanel.Step.CHOOSER
			and buttons.size() == 2 and not buttons[0].disabled
	), _state(after))
	_fx.close_panel(after)


func _test_hint() -> void:
	var screen: GDScript = load(SCREEN_SCRIPT) as GDScript
	var contexts: Dictionary = {} if screen == null else (
			screen.get_script_constant_map().get("HINT_CONTEXTS", {}) as Dictionary
	)
	var hint: StringName = contexts.get(EventPanel.Step.LEAVING, &"")
	_ok("hints: the leaving step shows the chooser's hints (up, down, Choose, Back)", (
			hint == &"CHOOSE"
	), hint)


# --- Helpers -----------------------------------------------------------------------------------


# A panel on made's open event, its steps recorded in _steps from now on.
func _open(made: CampaignSession) -> EventPanel:
	_steps.clear()
	var panel: EventPanel = _fx.open_panel(made)
	panel.step_changed.connect(_steps.append)
	return panel


# Presses option index's card with device, from the first focusable card for key and pad.
func _press_card(panel: EventPanel, device: String, index: int) -> bool:
	var cards: Array[EventOptionCard] = panel.get_cards()
	if index >= cards.size() or cards[index].disabled:
		return false
	panel.focus_first()
	return _fx.press(device, cards[index], "right")


# Whether panel shows the outcome of option index, chosen and saved.
func _is_done(panel: EventPanel, index: int) -> bool:
	return (
			panel.get_step() == EventPanel.Step.OUTCOME
			and panel.get_view().chosen == index
	)


# The kinds of the facts made's run recorded after its first from facts.
func _kinds_since(made: CampaignSession, from: int) -> Array[CampaignFact.Kind]:
	var found: Array[CampaignFact.Kind] = []
	for index: int in range(from, made.run.fact_log.size()):
		found.append(made.run.fact_log[index].kind)
	return found


func _index_of(seat_run: SeatRun, unit_id: String) -> int:
	for index: int in seat_run.army.size():
		if seat_run.army[index].instance_id == unit_id:
			return index
	return -1


func _state(panel: EventPanel) -> String:
	return "step %s; status '%s'; %s" % [
		str(EventPanel.Step.find_key(panel.get_step())), panel.get_status_text(),
		"" if _fx.last_batch == null else _fx.last_batch.rejected_reason,
	]


func _texts(buttons: Array[Button]) -> PackedStringArray:
	var texts: PackedStringArray = []
	for button: Button in buttons:
		texts.append(button.text)
	return texts


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events leaving %s" % [case_name], passed, detail)
