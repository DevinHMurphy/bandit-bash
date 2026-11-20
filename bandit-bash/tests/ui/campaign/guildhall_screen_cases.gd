# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_screen_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Guildhall screen for tests/ui/campaign/run_all.gd, on a real solo run through the real
## SaveService and CampaignService, at 1280×720: routed to by a Guildhall node; its stock rolled
## and saved on entry, a card per entry priced for the seat, the same after a Save & Quit and
## Continue; a recruit bought by keys into an army with room; a full army's recruit by clicks (the
## unit replaced, the hand-over rows, Best fit, the price); a rune by pad, B backing out with no
## pause menu, and a full slot's discard; a re-roll by keys with its price rising; and a refused card
## saying why. Leaving is the walk's (run_all.gd), which routes; nothing here changes scene.
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before and
## after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const GUILDHALL_SCENE: String = "res://ui/campaign/guildhall_screen.tscn"

# SceneRouter.Screen.GUILDHALL: a case file can't name the autoload.
const SCREEN_GUILDHALL: int = 17

# The save file the cases write, in the test user folder only; the walk uses 1.
const SAVE_NUMBER: int = 3
const RUN_SEED: int = 0xA503

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# Gold a staged seat holds, enough for anything stocked. Units: gold.
const RICH: int = 1000

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")
	_service = root.get_node(^"CampaignService")


## Runs every case. Call only with a test user folder.
func run() -> void:
	_catalog = EffectCatalog.index()
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	if _new_run() != null:
		_test_entry_and_resume()
		_test_recruit_by_key()
		_test_replace_by_mouse()
		_test_rune_by_pad()
		_test_reroll_by_key()
		_test_refused()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_entry_and_resume() -> void:
	var session: CampaignSession = _session()
	_check.call("guildhall: the map has a Guildhall", Fixture.enter(session.run, _guildhall()))
	_check.call("guildhall: a Guildhall node routes to the Guildhall screen", (
			(RunScreen.of(session) as int) == SCREEN_GUILDHALL
	), str(RunScreen.of(session)))
	session.run.seat_run(0).gold = RICH
	var screen: Control = _add(GUILDHALL_SCENE)
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	var view: GuildhallStockView = screen.call(&"get_stock_view")
	_check.call("guildhall: the stock is rolled and saved on entry, a card per entry, priced", (
			stock != null and view.get_cards().size() == stock.entries.size()
			and view.get_cards()[0].text.contains("gold")
	), "%d cards" % [view.get_cards().size()])
	var before: String = JSON.stringify(stock.capture())
	_remove(screen)
	var reopened: CampaignSession = _reopen()
	var kept: GuildhallStock = GuildhallStock.pending(reopened.run) if reopened != null else null
	_check.call("resume: Save & Quit, Continue shows the same stock at the Guildhall", (
			kept != null and JSON.stringify(kept.capture()) == before
			and (RunScreen.of(reopened) as int) == SCREEN_GUILDHALL
	))
	_leave_node()


func _test_recruit_by_key() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	_make_room(seat_run)
	var screen: Control = _add(GUILDHALL_SCENE)
	var view: GuildhallStockView = screen.call(&"get_stock_view")
	var panel: GuildhallPanel = screen.call(&"get_panel")
	var index: int = _first_recruit(session)
	var size_before: int = seat_run.army.size()
	view.card_for(index).grab_focus()
	_press_key(KEY_ENTER)
	var asked: bool = panel.visible and panel.get_step() == GuildhallPanel.Step.RECRUIT
	_focus_starting(panel.get_choice_buttons(), "Recruit for")
	_press_key(KEY_ENTER)
	_check.call("keys: Enter on a recruit shows its price; Enter recruits it into the room left", (
			asked and not panel.visible and seat_run.army.size() == size_before + 1
			and (screen.call(&"get_status_text") as String).begins_with("Recruited")
			and view.card_for(index).disabled
	), screen.call(&"get_status_text") as String)
	_remove(screen)
	_leave_node()


func _test_replace_by_mouse() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var screen: Control = _add(GUILDHALL_SCENE)
	var view: GuildhallStockView = screen.call(&"get_stock_view")
	var panel: GuildhallPanel = screen.call(&"get_panel")
	var index: int = _first_recruit(session)
	var leaving: UnitInstance = seat_run.army[1]
	_click(view.card_for(index))
	var commander: Button = _first_with(panel.get_choice_buttons(), "commander never leaves")
	_check.call("mouse: a full army asks which unit leaves; the commander is greyed, saying why", (
			panel.get_step() == GuildhallPanel.Step.REPLACE
			and commander != null and commander.disabled
	))
	var replace: Button = _starting(panel.get_choice_buttons(), "Replace")
	if replace != null:
		_click(replace)
	var rows: Array[HandOverRow] = panel.get_rows()
	_check.call("mouse: the hand-over lists the leaving unit's items and the recruit's own", (
			panel.get_step() == GuildhallPanel.Step.HAND_OVER
			and rows.size() == Guildhall.hand_over_items(
					session.run, 0, leaving.instance_id,
					Guildhall.recruit_for(session.run, 0, index, _catalog)
			).size()
	), "%d rows" % [rows.size()])
	var scrapped: bool = false
	if not rows.is_empty():
		var scrap: Button = rows[0].button_for(Guildhall.HandOver.SCRAP)
		_click(scrap)
		scrapped = panel.get_hand_over().get(rows[0].item_id, -1) == Guildhall.HandOver.SCRAP
	var best: Button = _starting(panel.get_choice_buttons(), "Best fit")
	if best != null:
		_click(best)
	var refit: bool = (
			not rows.is_empty()
			and panel.get_hand_over() == Guildhall.best_fit(
					session.run, 0, index, leaving.instance_id, _catalog
			)
	)
	var confirm: Button = _starting(panel.get_choice_buttons(), "Recruit for")
	if confirm != null:
		_click(confirm)
	_check.call("mouse: a place pressed changes it; Best fit restores the suggestion; it recruits", (
			scrapped and refit and confirm != null and not panel.visible
			and seat_run.unit(leaving.instance_id) == null
			and Fixture.is_whole(seat_run)
	), "scrapped %s, refit %s" % [scrapped, refit])
	_remove(screen)
	_leave_node()


func _test_rune_by_pad() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var screen: Control = _add(GUILDHALL_SCENE)
	var view: GuildhallStockView = screen.call(&"get_stock_view")
	var panel: GuildhallPanel = screen.call(&"get_panel")
	var runes: PackedInt32Array = GuildhallStock.pending(session.run).indexes_of(
			GuildhallStock.CATEGORY_RUNE
	)
	view.card_for(runes[0]).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var asked: bool = panel.visible and panel.get_step() == GuildhallPanel.Step.RUNE
	_press_pad(JOY_BUTTON_B)
	_check.call("pad: A on a rune shows its price; B backs out, no pause menu", (
			asked and not panel.visible and not _root.get_tree().paused
			and seat_run.rune_slots[0].is_empty()
	))
	view.card_for(runes[0]).grab_focus()
	_press_pad(JOY_BUTTON_A)
	_focus_starting(panel.get_choice_buttons(), "Buy for")
	_press_pad(JOY_BUTTON_A)
	_check.call("pad: A, A buys the rune into the first slot", (
			not seat_run.rune_slots[0].is_empty() and not panel.visible
	))
	for slot: int in SeatRun.RUNE_SLOT_COUNT:
		if seat_run.rune_slots[slot].is_empty():
			seat_run.rune_slots[slot] = SeatRun.RuneSlot.new(
					session.ids.next_rune_id("mend"), "mend"
			)
	view.card_for(runes[1]).pressed.emit()
	var discards: int = 0
	for button: Button in panel.get_choice_buttons():
		if button.text.begins_with("Discard") and not button.disabled:
			discards += 1
	_check.call("full slots: the rune asks which of the three to discard", (
			panel.get_step() == GuildhallPanel.Step.RUNE and discards == SeatRun.RUNE_SLOT_COUNT
	), str(discards))
	_remove(screen)
	_leave_node()


func _test_reroll_by_key() -> void:
	var session: CampaignSession = _at_guildhall()
	var seat_run: SeatRun = session.run.seat_run(0)
	var screen: Control = _add(GUILDHALL_SCENE)
	var panel: GuildhallPanel = screen.call(&"get_panel")
	var unit: UnitInstance = seat_run.army[1]
	unit.prefix_id = UnitPrefixDefinition.NO_PREFIX
	(screen.call(&"get_reroll_button") as Button).grab_focus()
	_press_key(KEY_ENTER)
	var first: String = _choice_for(panel, unit)
	_focus_text(panel.get_choice_buttons(), first)
	_press_key(KEY_ENTER)
	unit.prefix_id = UnitPrefixDefinition.NO_PREFIX
	panel.refresh()
	var second: String = _choice_for(panel, unit)
	var commander: Button = null
	for button: Button in panel.get_choice_buttons():
		if button.disabled and button.text.contains("commander"):
			commander = button
	_check.call("keys: Re-roll lists the units with prices; a re-roll stays open, the price rises", (
			panel.visible and panel.get_step() == GuildhallPanel.Step.REROLL
			and first.ends_with("13 gold") and second.ends_with("20 gold")
			and commander != null
	), "%s / %s" % [first, second])
	_remove(screen)
	_leave_node()


func _test_refused() -> void:
	var session: CampaignSession = _at_guildhall()
	session.run.seat_run(0).gold = 0
	var screen: Control = _add(GUILDHALL_SCENE)
	var card: Button = (screen.call(&"get_stock_view") as GuildhallStockView).card_for(
			_first_recruit(session)
	)
	_check.call("refused: a card the seat can't afford says why and takes no focus", (
			card.disabled and card.focus_mode == Control.FOCUS_NONE
			and card.text.contains("Can't buy: too little gold")
	), card.text)
	_remove(screen)
	_leave_node()


# A new solo run through SaveService, past its starting offer; null, checked, if none starts.
func _new_run() -> CampaignSession:
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = _session()
	_check.call("guildhall: a new solo run starts", err == OK and session != null, error_string(err))
	if session == null:
		return null
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	return session


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# The run inside its first Guildhall with plenty of gold.
func _at_guildhall() -> CampaignSession:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, _guildhall())
	session.run.seat_run(0).gold = RICH
	return session


# Save & Quit, then Continue Run: the session as the save gives it back.
func _reopen() -> CampaignSession:
	_saves.call(&"save_checkpoint")
	_saves.call(&"close_save_file")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = _saves.call(&"continue_solo_run")
	if err != OK:
		_check.call("resume: the run continues", false, error_string(err))
		return null
	return _session()


# Leaves the node the run is in, as the screen's Leave would.
func _leave_node() -> void:
	var left: CampaignBatch = _service.call(&"submit_command", LeaveNodeCommand.new(0))
	if left == null or left.is_rejected():
		_check.call("guildhall: the node is left", false, (
				left.rejected_reason if left != null else ""
		))


# Dismisses seat_run's last unit, its items dropped from the roster, so the army has room.
func _make_room(seat_run: SeatRun) -> void:
	var unit: UnitInstance = seat_run.army[seat_run.army.size() - 1]
	for item_id: String in unit.item_ids():
		seat_run.items.erase(item_id)
	seat_run.army.erase(unit)


func _first_recruit(session: CampaignSession) -> int:
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	for index: int in stock.indexes_of(GuildhallStock.CATEGORY_RECRUIT):
		if not stock.entries[index].is_sold():
			return index
	return -1


# The text of unit's re-roll choice on the panel; empty when none shows it.
func _choice_for(panel: GuildhallPanel, unit: UnitInstance) -> String:
	var title: String = RecruitOfferCard.title_of(unit, _catalog)
	for button: Button in panel.get_choice_buttons():
		if button.text.begins_with(title) and not button.disabled:
			return button.text
	return ""


func _guildhall() -> CampaignGraph.NodeType:
	return CampaignGraph.NodeType.GUILDHALL


# scene instanced into the root at SCREEN_SIZE, anchored top-left, laid out.
func _add(path: String) -> Control:
	var scene: PackedScene = load(path)
	var screen: Control = scene.instantiate()
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = SCREEN_SIZE
	_lay_out(screen)
	return screen


func _remove(screen: Control) -> void:
	_root.remove_child(screen)
	screen.free()


func _starting(buttons: Array[Button], prefix: String) -> Button:
	for button: Button in buttons:
		if button.text.begins_with(prefix) and not button.disabled:
			return button
	return null


func _first_with(buttons: Array[Button], part: String) -> Button:
	for button: Button in buttons:
		if button.text.contains(part):
			return button
	return null


func _focus_starting(buttons: Array[Button], prefix: String) -> void:
	var button: Button = _starting(buttons, prefix)
	if button != null:
		button.grab_focus()


func _focus_text(buttons: Array[Button], text: String) -> void:
	for button: Button in buttons:
		if button.text == text:
			button.grab_focus()
			return


# Sorts the screen's containers twice, parents first, as a frame's deferred sort would.
func _lay_out(screen: Control) -> void:
	for _pass: int in 2:
		for node: Node in screen.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# A left click at the middle of control, its screen laid out first.
func _click(control: Control) -> void:
	var top: Control = control
	while top.get_parent_control() != null:
		top = top.get_parent_control()
	_lay_out(top)
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
