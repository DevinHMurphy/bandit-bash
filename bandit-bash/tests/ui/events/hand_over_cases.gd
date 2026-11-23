# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hand_over_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The event panel's hand-over step over runs in memory, by keyboard, mouse and pad: after the
## unit that leaves, one row per item opening at the convoy; a lance the archer can't use greyed
## on Recruit with its reason and out of the focus order; Scrap and Recruit chosen and sent with
## the option, the run settled as chosen. A nearly full convoy greys Convoy and holds Confirm with
## its reason until an item is scrapped; Best fit; a revive's Revived place and the note of the
## revived unit's own item sent to the convoy; a quit mid-step resumes at the cards, nothing
## sent; in co-op seat 1 hands over its own unit only. The outcome summary's keywords show as one
## column beside it while Leave or Team holds pad or key focus, never for a click; the hints.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

const SCREEN_SCRIPT: String = "res://ui/campaign/events/event_screen.gd"
const SCREEN_SCENE: String = "res://ui/campaign/events/event_screen.tscn"
const DEVICES: PackedStringArray = ["key", "mouse", "pad"]
const RECRUIT: int = Guildhall.HandOver.RECRUIT
const CONVOY: int = Guildhall.HandOver.CONVOY
const SCRAP: int = Guildhall.HandOver.SCRAP

var _check: Callable
var _root: Window = null
var _fx: Fixture = null


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
		_test_places(device)
	_test_convoy_room()
	_test_best_fit()
	_test_revive()
	_test_continue()
	_test_coop()
	for device: String in DEVICES:
		_test_keyword_column(device)
	_test_hints()


func _test_places(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var lance: String = leaving.weapon_id
	var potion: String = leaving.pouch_id
	var panel: EventPanel = _to_hand_over(made, leaving)
	var hand_over: EventHandOverPanel = panel.get_hand_over_panel()
	var rows: Array[HandOverRow] = hand_over.get_rows()
	var opened: bool = (
			panel.get_step() == EventPanel.Step.HAND_OVER and rows.size() == 2
			and rows[0].item_id == lance and rows[1].item_id == potion
			and rows[0].place == CONVOY and rows[1].place == CONVOY
			and hand_over.get_question().begins_with("Hakkapel leaves for Archer.")
	)
	var greyed: Button = rows[0].button_for(RECRUIT) if rows.size() == 2 else null
	_ok("%s: one row per item, at the convoy; the lance's Recruit greyed with why" % [device], (
			opened and greyed != null and greyed.disabled
			and greyed.focus_mode == Control.FOCUS_NONE
			and _row_text(rows[0]).contains("Recruit: the recruit can't use it")
	), "%s | %s" % [hand_over.get_question(), _row_text(rows[0]) if rows.size() > 0 else ""])
	if not opened:
		_fx.close_panel(panel)
		return
	var scrapped: bool = _choose(device, rows[0].button_for(SCRAP), [])
	rows = hand_over.get_rows()
	var onto: bool = scrapped and _choose(
			device, rows[1].button_for(RECRUIT), ["down", "left", "left"]
	)
	var confirm: Button = Fixture.button_starting(hand_over.get_choice_buttons(), "Confirm")
	var confirmed: bool = onto and confirm != null and _fx.press(device, confirm, "down")
	var sent: EventOptionCommand = _fx.commands[-1] as EventOptionCommand
	var joined: UnitInstance = seat_run.army[-1]
	_ok("%s: Scrap and Recruit are sent with the option; the run settles as chosen" % [device], (
			confirmed and panel.get_step() == EventPanel.Step.OUTCOME
			and sent != null and sent.choice.replaced_id == leaving.instance_id
			and sent.choice.hand_over == {lance: SCRAP, potion: RECRUIT}
			and joined.pouch_id == potion and not seat_run.items.has(lance)
			and not seat_run.army.has(leaving) and _fx.base.is_whole(seat_run)
	), "%s; %s" % [_state(panel), "" if sent == null else str(sent.choice.hand_over)])
	_fx.close_panel(panel)


func _test_convoy_room() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, _fx.base.catalog)
	while seat_run.convoy.size() < capacity - 1:
		_fx.base.add_to_convoy(made, Fixture.EQUIPMENT_ID)
	var panel: EventPanel = _to_hand_over(made, leaving)
	var hand_over: EventHandOverPanel = panel.get_hand_over_panel()
	var confirm: Button = Fixture.button_starting(hand_over.get_choice_buttons(), "Confirm")
	_ok("convoy: everything to a convoy with room for one holds Confirm, saying why", (
			confirm != null and confirm.disabled and confirm.focus_mode == Control.FOCUS_NONE
			and confirm.text.contains("can't: the convoy can't take 2 more")
	), "" if confirm == null else confirm.text)
	hand_over.get_rows()[1].button_for(SCRAP).pressed.emit()
	var rows: Array[HandOverRow] = hand_over.get_rows()
	confirm = Fixture.button_starting(hand_over.get_choice_buttons(), "Confirm")
	var full: Button = rows[1].button_for(CONVOY)
	_ok("convoy: one scrapped, the convoy is full for it (greyed, why) and Confirm opens", (
			confirm != null and not confirm.disabled and confirm.text == "Confirm"
			and full.disabled and _row_text(rows[1]).contains("Convoy: the convoy is full")
			and not rows[0].button_for(CONVOY).disabled
	), "%s | %s" % [_row_text(rows[1]), "" if confirm == null else confirm.text])
	_fx.close_panel(panel)


func _test_best_fit() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var panel: EventPanel = _to_hand_over(made, leaving)
	var hand_over: EventHandOverPanel = panel.get_hand_over_panel()
	Fixture.button_starting(hand_over.get_choice_buttons(), "Best fit").pressed.emit()
	var shown: Dictionary[String, int] = hand_over.get_hand_over()
	var potion_place: int = shown.get(leaving.pouch_id, -1)
	var lance_place: int = shown.get(leaving.weapon_id, -1)
	_ok("best fit: the potion onto the archer, the lance it can't use to the convoy", (
			potion_place == RECRUIT and lance_place == CONVOY
			and hand_over.get_rows()[1].place == RECRUIT
	), str(shown))
	_fx.close_panel(panel)


func _test_revive() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.shrine(), 1, true)
	var seat_run: SeatRun = made.run.seat_run(0)
	_fx.fill_army(made, seat_run)
	var fallen: UnitInstance = seat_run.fallen[0]
	var own_potion: ItemInstance = seat_run.items[fallen.pouch_id]
	var leaving: UnitInstance = _fx.base.unit_of_type(seat_run, Fixture.RECRUIT_TYPE)
	var tonic: String = leaving.pouch_id
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[Fixture.PRAYER].pressed.emit()
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	panel.get_chooser().get_choice_buttons()[seat_run.army.find(leaving)].pressed.emit()
	var hand_over: EventHandOverPanel = panel.get_hand_over_panel()
	var rows: Array[HandOverRow] = hand_over.get_rows()
	var named: bool = (
			panel.get_step() == EventPanel.Step.HAND_OVER and rows.size() == 2
			and rows[1].button_for(RECRUIT).text == EventScreenModel.REVIVED_PLACE
	)
	if named:
		rows[1].button_for(RECRUIT).pressed.emit()
	var note: String = "The revived unit's %s goes to the convoy." % [
		EventScreenModel.held_item_name(own_potion, _fx.base.catalog),
	]
	_ok("revive: the place reads Revived; its own Pouch item's move is noted", (
			named and hand_over.get_notes() == note and hand_over.get_rows()[1].place == RECRUIT
	), hand_over.get_notes())
	Fixture.button_starting(hand_over.get_choice_buttons(), "Confirm").pressed.emit()
	_ok("revive: the revived unit holds the item; its own goes to the convoy", (
			panel.get_step() == EventPanel.Step.OUTCOME and seat_run.army.has(fallen)
			and fallen.pouch_id == tonic and seat_run.convoy.has(own_potion.instance_id)
			and _fx.base.is_whole(seat_run)
	), _state(panel))
	_fx.close_panel(panel)


func _test_continue() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp())
	var seat_run: SeatRun = made.run.seat_run(0)
	var leaving: UnitInstance = _fx.base.soldier(seat_run)
	var army: Array[UnitInstance] = seat_run.army.duplicate()
	var sent: int = _fx.commands.size()
	var panel: EventPanel = _to_hand_over(made, leaving)
	panel.get_hand_over_panel().get_rows()[0].button_for(SCRAP).pressed.emit()
	var asked: bool = panel.get_step() == EventPanel.Step.HAND_OVER
	_fx.close_panel(panel)
	var resumed: CampaignSession = _fx.base.resume(made)
	if resumed == null:
		_ok("continue: the run resumes from its save", false, error_string(_fx.base.resume_error))
		return
	var after: EventPanel = _fx.open_panel(resumed)
	_ok("continue: a quit at the unsaved hand-over resumes at the cards, nothing sent", (
			asked and after.get_step() == EventPanel.Step.OPTIONS
			and _fx.commands.size() == sent and seat_run.army == army
			and resumed.run.events.seat_event(0).chosen == EventRunState.NO_OPTION
			and resumed.run.seat_run(0).items.has(leaving.weapon_id)
	), _state(after))
	_fx.close_panel(after)


func _test_coop() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.camp(), 2)
	var own: SeatRun = made.run.seat_run(1)
	var mate: SeatRun = made.run.seat_run(0)
	var mate_army: Array[UnitInstance] = mate.army.duplicate()
	var mate_items: int = mate.items.size()
	var leaving: UnitInstance = _fx.base.soldier(own)
	var lance: String = leaving.weapon_id
	var panel: EventPanel = _to_hand_over(made, leaving, 1)
	var hand_over: EventHandOverPanel = panel.get_hand_over_panel()
	var rows_own: bool = hand_over.get_rows().size() == leaving.item_ids().size()
	hand_over.get_rows()[0].button_for(SCRAP).pressed.emit()
	Fixture.button_starting(hand_over.get_choice_buttons(), "Confirm").pressed.emit()
	var sent: EventOptionCommand = _fx.commands[-1] as EventOptionCommand
	_ok("co-op: seat 1 hands over its own unit's items; seat 0's army is untouched", (
			rows_own and sent != null and sent.seat == 1
			and sent.choice.hand_over == {lance: SCRAP}
			and not own.items.has(lance) and not own.army.has(leaving)
			and mate.army == mate_army and mate.items.size() == mate_items
	), _state(panel))
	_fx.close_panel(panel)


func _test_keyword_column(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.toll())
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[Fixture.INTIMIDATE].pressed.emit()
	var lines: EffectText = panel.get_summary().get_effect_text()
	var ids: PackedStringArray = lines.get_keyword_ids()
	var leave: Button = panel.get_leave_button()
	_root.gui_release_focus()
	var shown: int = -1
	if device == "mouse":
		_fx.click(leave)
	else:
		leave.grab_focus()
		shown = lines.get_shown_tooltips().size()
		_root.gui_release_focus()
	var after: int = lines.get_shown_tooltips().size()
	var column: Control = lines.get_tooltip_column()
	var outcome: bool = panel.get_step() == EventPanel.Step.OUTCOME and not ids.is_empty()
	if device == "mouse":
		_ok("keywords mouse: a click on Leave shows no column", (
				outcome and after == 0
		), "%d keywords; %d shown" % [ids.size(), after])
	else:
		_fx.lay_out(panel)
		_ok("keywords %s: Leave's focus shows the summary's keywords as one column, then hides" % [
			device,
		], (
				outcome and shown == ids.size() and after == 0
		), "%d keywords; %d shown, then %d" % [ids.size(), shown, after])
	if device == "pad":
		leave.grab_focus()
		lines.place_tooltips()
		var beside: bool = (
				column.visible
				and not column.get_global_rect().intersects(lines.get_global_rect())
				and _root.get_visible_rect().encloses(column.get_global_rect())
		)
		_ok("keywords: the column sits beside the summary, on screen, at 1280×720", beside,
				"%s vs %s" % [column.get_global_rect(), lines.get_global_rect()])
	_fx.close_panel(panel)


func _test_hints() -> void:
	var screen: GDScript = load(SCREEN_SCRIPT) as GDScript
	var constants: Dictionary = {} if screen == null else screen.get_script_constant_map()
	var contexts: Dictionary = constants.get("HINT_CONTEXTS", {}) as Dictionary
	var scene: PackedScene = load(SCREEN_SCENE) as PackedScene
	var made: Node = null if scene == null else scene.instantiate()
	var hints: ScreenHints = null if made == null else made.get_node("ScreenHints") as ScreenHints
	var bar: ControlHintBar = (
			null if made == null else made.get_node("ControlHintBar") as ControlHintBar
	)
	var team: StringName = constants.get("TEAM_FOCUS_CONTEXT", &"")
	var step_context: StringName = contexts.get(EventPanel.Step.HAND_OVER, &"")
	var labels: Dictionary[String, String] = {}
	if bar != null:
		labels = bar.labels
	var back_label: String = labels.get("HAND_OVER/ui_cancel", "")
	var team_label: String = labels.get("ON_TEAM/ui_accept", "")
	var steps_rows: bool = (
			hints != null and hints.actions.has(&"HAND_OVER")
			and hints.actions[&"HAND_OVER"].has("ui_left")
	)
	_ok("hints: the hand-over's context steps along rows and places, Choose and Back", (
			step_context == &"HAND_OVER" and steps_rows and back_label == "Back"
	), step_context)
	_ok("hints: while Team has focus, accept reads Team, on the cards as on the outcome", (
			team == &"ON_TEAM" and hints != null and hints.actions.has(team)
			and team_label == "Team"
	), str(team))
	if made != null:
		made.free()


# --- Helpers -----------------------------------------------------------------------------------


# A panel on made's camp at the hire's hand-over for seat, leaving named.
func _to_hand_over(made: CampaignSession, leaving: UnitInstance, seat: int = 0) -> EventPanel:
	var panel: EventPanel = _fx.open_panel(made, seat)
	panel.get_cards()[Fixture.HIRE].pressed.emit()
	var army: Array[UnitInstance] = made.run.seat_run(seat).army
	panel.get_chooser().get_choice_buttons()[army.find(leaving)].pressed.emit()
	_fx.lay_out(panel)
	panel.focus_first()
	return panel


# Presses target with device: a click, or the moves in path ("down", "left", "right") then right
# until focus reaches it, then Enter or A. False, pressing nothing, when focus can't reach it.
func _choose(device: String, target: Button, path: Array) -> bool:
	if target == null or target.disabled:
		return false
	if device != "mouse":
		for move: Variant in path:
			_move(device, str(move))
	return _fx.press(device, target, "right")


func _move(device: String, direction: String) -> void:
	var keys: Dictionary[String, Key] = {"down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT}
	var pads: Dictionary[String, JoyButton] = {
		"down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
	}
	if device == "key":
		_fx.press_key(keys[direction])
	else:
		_fx.press_pad(pads[direction])


# The row's name label text: the item, then any greyed place's reason.
func _row_text(row: HandOverRow) -> String:
	var label: Label = row.get_node("%ItemName") as Label
	return "" if label == null else label.text


func _state(panel: EventPanel) -> String:
	return "step %s; status '%s'; %s" % [
		str(EventPanel.Step.find_key(panel.get_step())), panel.get_status_text(),
		"" if _fx.last_batch == null else _fx.last_batch.rejected_reason,
	]


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events hand-over %s" % [case_name], passed, detail)
