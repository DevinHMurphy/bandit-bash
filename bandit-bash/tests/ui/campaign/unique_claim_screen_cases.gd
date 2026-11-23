# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unique_claim_screen_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The Treasure screen and the key heirloom picker naming the heirloom they show in their takes
## ([UniqueClaims]), for tests/ui/campaign/run_all.gd: a 2-seat host run through the real
## SaveService and CampaignService, the local seat 1, Brothers in Arms offered to both seats. The
## teammate's first claim rebuilds the chest to its replacement, which Open then takes by name; a
## unique heirloom the teammate owns is refused by name. The picker, which shows its card as
## opened, sends the claimed heirloom and is refused "Player 1 took Brothers in Arms first", then
## opened again takes the replacement. Writes save files, so it runs only with a test user folder;
## it deletes user://saves/ before and after. It names no autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const TREASURE_SCENE: String = "res://ui/campaign/treasure_screen.tscn"
const PICKER_SCENE: String = "res://ui/campaign/victory/key_heirloom_picker.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 3
# Two made-up Steam ids: the host's, then the teammate's.
const STEAM_IDS: Array[int] = [0x1111, 0x2222]

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

const BROTHERS: String = "brothers_in_arms"
const BROTHERS_NAME: String = "Brothers in Arms"

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _catalog: EffectCatalog.Index = null

# Every batch the session settled since the last _batches.clear(): [seat, is_rejected, label].
var _batches: Array[Array] = []


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
		_test_treasure()
		_test_key_heirloom_picker()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# A new 2-seat host run, the local seat set to 1, both starting offers put aside.
func _new_run() -> CampaignSession:
	var ids: PackedInt64Array = []
	for steam_id: int in STEAM_IDS:
		ids.append(steam_id)
	var err: Error = _saves.call(&"start_new_multiplayer_run", ids)
	var session: CampaignSession = _session()
	var is_set: bool = session != null and _service.call(&"set_local_seat", 1)
	_check.call("unique claim screens: a 2-seat host run for seat 1", (
			err == OK and session != null and is_set
	), error_string(err))
	if session == null:
		return null
	for seat: int in session.seats:
		session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
	session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
	return session


func _test_treasure() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.TREASURE)
	_submit(OpenTreasureCommand.for_session(session))
	for seat: int in session.seats:
		_stage_chest(session.run.seat_run(seat), BROTHERS)
	var screen: Control = _add(TREASURE_SCENE)
	var view: ChestView = screen.call(&"get_chest_view")
	var shown: String = view.get_heirloom_card().heirloom_name
	_submit(TreasureCommand.new(0, true, null, BROTHERS))
	var chest: TreasureChest = TreasureChest.pending(session.run.seat_run(1))
	var rebuilt: String = view.get_heirloom_card().heirloom_name
	_check.call("treasure: the teammate's claim rebuilds seat 1's chest to its replacement", (
			shown == BROTHERS_NAME and chest.heirloom_id != BROTHERS
			and rebuilt == _name_of(chest.heirloom_id)
	), "%s -> %s" % [shown, rebuilt])
	var replacement: String = chest.heirloom_id
	_batches.clear()
	_click(screen.call(&"get_open_button") as Button)
	_check.call("treasure (mouse): Open takes the chest by the heirloom it shows", (
			_batches.size() == 1 and _batches[0][0] == 1 and not _batches[0][1]
			and _batches[0][2] == "take treasure, expecting %s" % [replacement]
			and session.run.seat_run(1).heirloom_ids().has(replacement)
	), str(_batches))
	_remove(screen)
	_stage_chest(session.run.seat_run(1), BROTHERS)
	screen = _add(TREASURE_SCENE)
	_batches.clear()
	(screen.call(&"get_open_button") as Button).grab_focus()
	_press_key(KEY_ENTER)
	var status: String = screen.call(&"get_status_text")
	_check.call("treasure (keys): a unique heirloom the teammate owns is refused by name", (
			_batches.size() == 1 and _batches[0][1]
			and status == "Can't do that: it is unique, and Player 1 owns it."
	), status)
	_remove(screen)
	for seat: int in session.seats:
		session.run.seat_run(seat).pending_offers.erase(TreasureChest.OFFER_KEY)
	_submit(LeaveNodeCommand.new(0))


func _test_key_heirloom_picker() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.KEY)
	session.run.flow.stage = RunFlow.Stage.RESULTS
	for seat: int in session.seats:
		var seat_run: SeatRun = session.run.seat_run(seat)
		seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
			"grades": CombatGrades.new().capture(), "xp": [], "level_ups": [],
		}
		var offer: KeyHeirloom = KeyHeirloom.new()
		offer.heirloom_id = BROTHERS
		offer.store(seat_run)
	var picker: KeyHeirloomPicker = _add(PICKER_SCENE) as KeyHeirloomPicker
	picker.open(null, 1)
	var shown: String = picker.get_card().heirloom_name
	_submit(KeyHeirloomCommand.new(0, true, BROTHERS))
	_batches.clear()
	picker.get_card().grab_focus()
	_press_pad(JOY_BUTTON_A)
	var status: String = picker.get_status_text()
	_check.call("key heirloom (pad): the card's take, lost to the teammate, is refused by name", (
			shown == BROTHERS_NAME and _batches.size() == 1 and _batches[0][1]
			and _batches[0][2] == "take key heirloom, expecting %s" % [BROTHERS]
			and status == "Can't take it: Player 1 took %s first." % [BROTHERS_NAME]
	), "%s; %s" % [status, _batches])
	var replacement: String = KeyHeirloom.pending(session.run.seat_run(1)).heirloom_id
	picker.open(null, 1)
	_batches.clear()
	picker.get_card().grab_focus()
	_press_key(KEY_ENTER)
	_check.call("key heirloom (keys): opened again, it shows and takes the replacement", (
			replacement != BROTHERS and picker.get_card().heirloom_name == _name_of(replacement)
			and _batches.size() == 1 and not _batches[0][1]
			and _batches[0][2] == "take key heirloom, expecting %s" % [replacement]
			and session.run.seat_run(1).heirloom_ids().has(replacement)
	), str(_batches))
	_remove(picker)


func _stage_chest(seat_run: SeatRun, heirloom_id: String) -> void:
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_UNCOMMON
	chest.heirloom_id = heirloom_id
	chest.store(seat_run)


func _name_of(heirloom_id: String) -> String:
	var heirloom: HeirloomDefinition = _catalog.heirloom(heirloom_id)
	return heirloom.display_name if heirloom != null else heirloom_id


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# Sends command as the teammate or the host would, outside any screen.
func _submit(command: CampaignCommand) -> void:
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	if batch == null or batch.is_rejected():
		_check.call("unique claim screens: %s resolves" % [command.get_label()], false, (
				batch.rejected_reason if batch != null else "no batch"
		))


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	_batches.append([batch.seat, batch.is_rejected(), batch.label])


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
