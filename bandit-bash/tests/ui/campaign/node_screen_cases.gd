# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     node_screen_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The Treasure and Camp screens, the Key combat's heirloom picker and the map's army view for
## tests/ui/campaign/run_all.gd, on a real solo run through the real SaveService and
## CampaignService, at 1280×720. Each by keyboard, mouse and pad: the chest rolled and saved on
## entry and taken by Enter, a Legendary placed by clicks, Leave's question answered by B without
## the pause menu; the Feast cooking by keys, Train by clicks (the commander greyed out), re-gearing
## and a bare Feast by pad, refused choices saying why; the heirloom taken by Enter and by click,
## B backing out; the army viewed from the map by I, a click and Y, a convoy item scrapped in one
## press. Leaving for the map is the walk's (run_all.gd), which routes; nothing here changes scene.
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const TREASURE_SCENE: String = "res://ui/campaign/treasure_screen.tscn"
const CAMP_SCENE: String = "res://ui/campaign/camp_screen.tscn"
const MAP_SCENE: String = "res://ui/campaign/campaign_map_screen.tscn"
const PICKER_SCENE: String = "res://ui/campaign/victory/key_heirloom_picker.tscn"

# The save file the cases write, in the test user folder only; the walk uses 1.
const SAVE_NUMBER: int = 2
const RUN_SEED: int = 0x7E57

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

const HEARTBEET: String = "heartbeet"
const LUCKY_COIN: String = "lucky_coin"
const ARCHER: int = 2

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
		_test_treasure_by_key()
		_test_treasure_by_mouse()
		_test_treasure_by_pad()
		_test_camp_by_key()
		_test_camp_by_mouse()
		_test_camp_by_pad()
		_test_camp_refused()
		_test_key_heirloom()
		_test_map_army_view()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_treasure_by_key() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.TREASURE)
	var screen: Control = _add(TREASURE_SCENE)
	var seat_run: SeatRun = session.run.seat_run(0)
	var chest: TreasureChest = TreasureChest.pending(seat_run)
	var view: ChestView = screen.call(&"get_chest_view")
	_check.call("treasure: the chest is rolled and saved on entry, its size shown", (
			chest != null and not chest.is_resolved and _saved_has(TreasureChest.OFFER_KEY)
			and view.get_size_text().begins_with(chest.size_name())
	), view.get_size_text())
	var gold_before: int = seat_run.gold
	(screen.call(&"get_open_button") as Button).grab_focus()
	_press_key(KEY_ENTER)
	var panel: PlacementPanel = screen.call(&"get_placement_panel")
	if panel.visible:
		_press_key(KEY_DOWN)
		_focus_starting(panel.get_choice_buttons(), "Send it to the convoy")
		_press_key(KEY_ENTER)
	var taken: TreasureChest = TreasureChest.pending(seat_run)
	var leave: Button = screen.call(&"get_leave_button")
	_check.call("treasure (keys): Enter takes the chest whole; Leave becomes Continue", (
			taken.is_resolved and taken.is_taken
			and seat_run.gold == gold_before + chest.gold
			and (chest.heirloom_id.is_empty() or seat_run.heirloom_ids().has(chest.heirloom_id))
			and leave.text == "Continue"
			and leave.theme_type_variation == &"PrimaryButton"
			and not (screen.call(&"get_open_button") as Button).visible
			and (screen.call(&"get_status_text") as String).begins_with("Took")
	), "%s; %s" % [screen.call(&"get_status_text"), leave.text])
	_remove(screen)


func _test_treasure_by_mouse() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var legendary: ItemDefinition = TreasureChest.usable_legendaries(seat_run, _catalog)[0]
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_RARE
	chest.item = ItemPick.Offer.new(legendary.id, session.ids.next_item_id(legendary.display_name))
	chest.store(seat_run)
	var screen: Control = _add(TREASURE_SCENE)
	var view: ChestView = screen.call(&"get_chest_view")
	_check.call("treasure (mouse): a Large chest's Legendary shows on its card, no heirloom", (
			view.get_item_card().visible and not view.get_heirloom_card().visible
			and view.get_item_card().item_name == legendary.display_name
	), view.get_item_card().item_name)
	_click(screen.call(&"get_open_button") as Button)
	var panel: PlacementPanel = screen.call(&"get_placement_panel")
	var opened: bool = panel.visible
	var convoy: Button = _starting(panel.get_choice_buttons(), "Send it to the convoy")
	if convoy != null:
		_click(convoy)
	_check.call("treasure (mouse): Open asks where the Legendary goes; the convoy takes it", (
			opened and convoy != null
			and seat_run.convoy.has(chest.item.instance_id)
			and TreasureChest.pending(seat_run).is_taken
			and not panel.visible
	), "panel %s" % [opened])
	_remove(screen)


func _test_treasure_by_pad() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_COMMON
	chest.gold = 25
	chest.heirloom_id = HeirloomDraw.candidates(
			seat_run, _catalog, PackedStringArray([ContentIds.HEIRLOOM_COMMON]), false
	)[0]
	chest.store(seat_run)
	var screen: Control = _add(TREASURE_SCENE)
	var view: ChestView = screen.call(&"get_chest_view")
	var dialog: LeaveConfirmDialog = screen.call(&"get_confirm_dialog")
	(screen.call(&"get_leave_button") as Button).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var asked: bool = dialog.visible and dialog.get_question().contains("chest")
	_press_pad(JOY_BUTTON_B)
	_check.call("treasure (pad): Leave with the chest closed asks first; B stays, no pause menu", (
			asked and not dialog.visible and not _root.get_tree().paused
			and TreasureChest.is_open(seat_run)
			and view.get_gold_text() == "+25 gold"
	), "asked %s, paused %s" % [asked, _root.get_tree().paused])
	(screen.call(&"get_open_button") as Button).grab_focus()
	_press_pad(JOY_BUTTON_A)
	_check.call("treasure (pad): A on Open takes the gold and the heirloom", (
			not TreasureChest.is_open(seat_run)
			and seat_run.heirloom_ids().has(chest.heirloom_id)
	))
	_remove(screen)
	_leave_node(session)


func _test_camp_by_key() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.CAMP)
	var seat_run: SeatRun = session.run.seat_run(0)
	var beet: String = Fixture.add_to_convoy(seat_run, HEARTBEET, session.ids)
	var archer: UnitInstance = seat_run.army[ARCHER]
	archer.hp = 1
	var screen: Control = _add(CAMP_SCENE)
	var leave: Button = screen.call(&"get_leave_button")
	_check.call("camp: Leave is refused until a choice is made, saying why", (
			leave.disabled and leave.text.contains("choose Feast or Train")
	), leave.text)
	(screen.call(&"get_feast_card") as Button).grab_focus()
	_press_key(KEY_ENTER)
	var panel: IngredientPanel = screen.call(&"get_ingredient_panel")
	var choices: Array[Button] = panel.get_choice_buttons()
	var shown: bool = (
			panel.visible and choices.size() == 3 and choices[0].text.contains("Heartbeet")
	)
	_press_key(KEY_ENTER)
	_check.call("camp (keys): Feast asks for an ingredient; Enter cooks the Heartbeet", (
			shown
			and Camp.choice_of(seat_run) == Camp.Choice.FEAST
			and not seat_run.items.has(beet)
			and archer.hp > 1
			and archer.pending_gains.size() == 1
			and not panel.visible
			and _saved_has(Camp.OFFER_KEY)
	), "%s; hp %d" % [choices[0].text if not choices.is_empty() else "none", archer.hp])
	var feast: CampChoiceCard = screen.call(&"get_feast_card")
	var train: CampChoiceCard = screen.call(&"get_train_card")
	_check.call("camp (keys): both cards now say the choice is made; Leave opens up", (
			feast.disabled and train.disabled
			and feast.problem.contains("you chose Feast") and train.problem.contains("Feast")
			and not leave.disabled and leave.text == "Leave"
	), "%s / %s" % [feast.problem, leave.text])
	_remove(screen)


func _test_camp_by_mouse() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.pending_offers.erase(Camp.OFFER_KEY)
	var screen: Control = _add(CAMP_SCENE)
	_click(screen.call(&"get_train_card") as Button)
	var choice: UnitChoicePanel = screen.call(&"get_unit_choice")
	var buttons: Array[Button] = choice.get_choice_buttons()
	var commander_refused: bool = buttons.size() > 0 and buttons[0].disabled
	var archer_button: Button = _starting(buttons, "Upgrade Archer")
	if archer_button != null:
		_click(archer_button)
	_check.call("camp (mouse): Train asks which unit (the commander greyed out); a click trains", (
			commander_refused and archer_button != null
			and seat_run.army[ARCHER].is_upgraded
			and Camp.choice_of(seat_run) == Camp.Choice.TRAIN
			and not screen.call(&"is_unit_choice_shown")
	), str(buttons.map(func(b: Button) -> String: return b.text)))
	_remove(screen)


func _test_camp_by_pad() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.pending_offers.erase(Camp.OFFER_KEY)
	var screen: Control = _add(CAMP_SCENE)
	(screen.call(&"get_army_button") as Button).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var army: ArmyView = screen.call(&"get_army_view")
	var opened: bool = army.visible and army.get_mode() == ArmyView.Mode.REGEAR
	var archer: UnitInstance = seat_run.army[ARCHER]
	var bow: String = archer.weapon_id
	_row_of(army, archer.instance_id).get_slot_button(Loadout.Slot.WEAPON).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var carrying: String = army.get_carrying()
	army.get_convoy_panel().get_to_convoy_button().grab_focus()
	_press_pad(JOY_BUTTON_A)
	_check.call("camp (pad): A opens re-gearing; A picks the bow up; A puts it in the convoy", (
			opened and carrying == bow
			and archer.weapon_id.is_empty() and seat_run.convoy.has(bow)
			and army.get_carrying().is_empty()
	), "carrying %s; %s" % [carrying, army.get_status_text()])
	_press_pad(JOY_BUTTON_B)
	_check.call("camp (pad): B closes the army view, no pause menu", (
			not army.visible and not _root.get_tree().paused
	))
	(screen.call(&"get_feast_card") as Button).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var panel: IngredientPanel = screen.call(&"get_ingredient_panel")
	var asked: bool = panel.visible
	_press_pad(JOY_BUTTON_B)
	var backed: bool = not panel.visible and Camp.choice_of(seat_run) == Camp.Choice.NONE
	(screen.call(&"get_feast_card") as Button).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var only: Array[Button] = panel.get_choice_buttons()
	_press_pad(JOY_BUTTON_A)
	_check.call("camp (pad): B backs out of the Feast; with no ingredient, A feasts on nothing", (
			asked and backed and not _root.get_tree().paused
			and only.size() == 2 and only[0].text == "Cook nothing"
			and Camp.choice_of(seat_run) == Camp.Choice.FEAST
	), "%d choices" % [only.size()])
	_remove(screen)


func _test_camp_refused() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.pending_offers.erase(Camp.OFFER_KEY)
	for unit: UnitInstance in seat_run.army:
		unit.is_upgraded = true
	var screen: Control = _add(CAMP_SCENE)
	var train: CampChoiceCard = screen.call(&"get_train_card")
	var feast: CampChoiceCard = screen.call(&"get_feast_card")
	_check.call("camp: with no unit to upgrade, Train is greyed out saying why; Feast stays", (
			train.disabled and train.focus_mode == Control.FOCUS_NONE
			and train.text.contains("Can't choose it")
			and not feast.disabled
	), train.text)
	_remove(screen)
	session.submit(FeastCommand.new(0))
	_leave_node(session)


func _test_key_heirloom() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	Fixture.enter(session.run, CampaignGraph.NodeType.KEY)
	session.run.flow.stage = RunFlow.Stage.RESULTS
	var grades: CombatGrades = CombatGrades.new()
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
		"grades": grades.capture(), "xp": [], "level_ups": [],
	}
	var devices: PackedStringArray = ["keyboard", "mouse", "pad"]
	for device: String in devices:
		var offer: KeyHeirloom = KeyHeirloom.new()
		offer.heirloom_id = HeirloomDraw.candidates(
				seat_run, _catalog, HeirloomDraw.TIERS, false
		)[0]
		offer.store(seat_run)
		var model: CombatResultsModel = CombatResultsModel.build(session, 0)
		var rewards: Array[VictoryReward] = VictoryRewards.build(model)
		var reward: VictoryReward = rewards[rewards.size() - 1] if not rewards.is_empty() else null
		var picker: KeyHeirloomPicker = _add(PICKER_SCENE) as KeyHeirloomPicker
		picker.open(reward, 0)
		var shown: String = picker.get_card().heirloom_name
		match device:
			"keyboard":
				_press_key(KEY_ENTER)
			"mouse":
				_click(picker.get_card())
			"pad":
				_press_pad(JOY_BUTTON_B)
				var backed: bool = (
						not picker.visible and KeyHeirloom.is_open(seat_run)
						and not _root.get_tree().paused
				)
				_check.call("key heirloom (pad): B backs out, the heirloom still offered", backed)
				picker.open(reward, 0)
				_press_pad(JOY_BUTTON_A)
		_check.call("key heirloom (%s): the reward row names it; taking it grants it" % [device], (
				reward is KeyHeirloomReward
				and reward.detail == model.key_heirloom_definition.display_name
				and shown == reward.detail
				and seat_run.heirloom_ids().has(offer.heirloom_id)
				and not KeyHeirloom.is_open(seat_run)
				and reward.skip_command(0) is KeyHeirloomCommand
		), "%s / %s" % [reward.detail if reward != null else "no row", shown])
		_remove(picker)
	seat_run.pending_offers.erase(KeyHeirloom.OFFER_KEY)
	session.submit(LeaveNodeCommand.new(0))


func _test_map_army_view() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	for _coin: int in 3:
		Fixture.add_to_convoy(seat_run, LUCKY_COIN, session.ids)
	var screen: Control = _add(MAP_SCENE)
	var army: ArmyView = screen.call(&"get_army_view")
	var hints: ScreenHints = screen.get_node(^"%ScreenHints")
	_press_key(KEY_I)
	var opened: bool = army.visible and army.get_mode() == ArmyView.Mode.VIEW
	var size_label: Label = army.get_node(^"%ArmySize")
	var max_size: int = RunOperations.max_army_size(seat_run, _catalog)
	_check.call("map army: it shows the army's size against its max (Muster Roll counts)", (
			size_label.text == "Army %d / %d" % [seat_run.army.size(), max_size]
	), size_label.text)
	var rows: Array[UnitGearRow] = army.get_rows()
	var slots_locked: bool = not rows.is_empty() and rows[0].get_slot_button(
			Loadout.Slot.WEAPON
	).disabled
	var gold_before: int = seat_run.gold
	var held: int = seat_run.convoy.size()
	var scrap: Array[Button] = army.get_convoy_panel().get_scrap_buttons()
	var first_focused: bool = not scrap.is_empty() and scrap[0].has_focus()
	_press_key(KEY_ENTER)
	_check.call("map army (keys): I opens it to view only; Enter on Scrap scraps in one press", (
			opened and slots_locked and first_focused and hints.context == &"ARMY"
			and seat_run.convoy.size() == held - 1 and seat_run.gold > gold_before
			and (screen.get_node(^"%RunHeader") as RunHeader).get_gold_text()
					== "Gold %d" % [seat_run.gold]
	), "open %s, locked %s, convoy %d" % [opened, slots_locked, seat_run.convoy.size()])
	_press_key(KEY_ESCAPE)
	_check.call("map army (keys): Esc closes it, not the pause menu; the hints go back to MAP", (
			not army.visible and not _root.get_tree().paused and hints.context == &"MAP"
	))
	_click(screen.call(&"get_army_button") as Button)
	var clicked_open: bool = army.visible
	_click(army.get_convoy_panel().get_scrap_buttons()[0])
	_click(army.get_close_button())
	_check.call("map army (mouse): the Army button opens it; a click scraps; Close closes", (
			clicked_open and seat_run.convoy.size() == held - 2 and not army.visible
	), "%d left" % [seat_run.convoy.size()])
	_press_pad(JOY_BUTTON_Y)
	var pad_open: bool = army.visible
	_press_pad(JOY_BUTTON_B)
	_check.call("map army (pad): Y opens it; B closes it, no pause menu", (
			pad_open and not army.visible and not _root.get_tree().paused
	))
	_remove(screen)


# A new solo run through SaveService, past its starting offer; null, checked, if none starts.
func _new_run() -> CampaignSession:
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = _session()
	_check.call("screens: a new solo run starts", err == OK and session != null, error_string(err))
	if session == null:
		return null
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	return session


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# Leaves the node the run is in, as the screens' Leave would.
func _leave_node(session: CampaignSession) -> void:
	var left: CampaignBatch = _service.call(&"submit_command", LeaveNodeCommand.new(0))
	if left == null or left.is_rejected():
		var reason: String = left.rejected_reason if left != null else ""
		_check.call("screens: the node is left", false, reason)
	if session.run.seat_run(0).pending_offers.has(TreasureChest.OFFER_KEY):
		session.run.seat_run(0).pending_offers.erase(TreasureChest.OFFER_KEY)


# Whether the run as last saved holds pending offer key for seat 0.
func _saved_has(key: String) -> bool:
	_saves.call(&"save_checkpoint")
	var session: CampaignSession = _session()
	var offers: Dictionary = session.run.seat_run(0).capture_economy().get("pending_offers", {})
	return offers.has(key)


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


func _row_of(army: ArmyView, unit_id: String) -> UnitGearRow:
	for row: UnitGearRow in army.get_rows():
		if row.unit_id == unit_id:
			return row
	return null


func _starting(buttons: Array[Button], prefix: String) -> Button:
	for button: Button in buttons:
		if button.text.begins_with(prefix) and not button.disabled:
			return button
	return null


func _focus_starting(buttons: Array[Button], prefix: String) -> void:
	var button: Button = _starting(buttons, prefix)
	if button != null:
		button.grab_focus()


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
