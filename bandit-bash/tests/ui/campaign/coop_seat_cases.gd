# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_seat_cases.gd
# Author:
# Created:  November 21, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## Every campaign screen for its own seat, for tests/ui/campaign/run_all.gd: a 2-seat host run
## through the real SaveService and CampaignService, the local seat set to 1, at 1280×720. Each
## screen shows seat 1's gold, chest, army and choices and sends seat 1's commands; a teammate's
## batch rebuilds it (gold, a sold card "bought by Player 1", a Camp choice); a refusal waiting on
## the teammate names them. The Team panel by mouse, keys and pad. No file under ui/ reads
## seats[0]. No press here moves the run to another
## screen, so nothing changes scene.
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")
const SceneScan = preload("res://tests/ui/theme/scene_scan_cases.gd")

const MAP_SCENE: String = "res://ui/campaign/campaign_map_screen.tscn"
const START_SCENE: String = "res://ui/campaign/starting_heirloom_screen.tscn"
const TREASURE_SCENE: String = "res://ui/campaign/treasure_screen.tscn"
const CAMP_SCENE: String = "res://ui/campaign/camp_screen.tscn"
const ARMORY_SCENE: String = "res://ui/campaign/armory_screen.tscn"
const GUILDHALL_SCENE: String = "res://ui/campaign/guildhall_screen.tscn"
const PLACEHOLDER_SCENE: String = "res://ui/campaign/node_placeholder_screen.tscn"
const RESULTS_SCENE: String = "res://ui/campaign/combat_results_screen.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 3
# Two made-up Steam ids: the host's, then the teammate's.
const STEAM_IDS: Array[int] = [0x1111, 0x2222]

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# Each seat's gold, unlike, so a header showing the wrong seat's reads wrong.
const HOST_GOLD: int = 50
const OWN_GOLD: int = 321
const RICH: int = 9000

# The ingredient staged in the teammate's convoy, for a scrap that changes only their part.
const INGREDIENT: String = "heartbeet"

# The files that may still read seats[0], each for its own step (P11). None is left.
const SEAT_ZERO_EXEMPT: PackedStringArray = []

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _catalog: EffectCatalog.Index = null

# Every batch the session settled since the last _batches.clear(): [seat, is_rejected].
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
		_test_map()
		_test_starting_offer()
		_test_treasure()
		_test_camp()
		_test_armory()
		_test_guildhall()
		_test_placeholder()
		_test_results()
	_saves.call(&"close_save_file")
	_check.call("local seat: a closed run puts it back to the host seat", (
			_service.call(&"local_seat") == CampaignData.HOST_SEAT
	), str(_service.call(&"local_seat")))
	SaveFile.delete_folder("user://saves/")
	_test_seat_zero_scan()


# A new 2-seat host run, the local seat set to 1, each seat's gold its own. Both starting offers
# stay open; the map case puts seat 1's aside, and seat 0's stays open throughout.
func _new_run() -> CampaignSession:
	var ids: PackedInt64Array = []
	for steam_id: int in STEAM_IDS:
		ids.append(steam_id)
	var err: Error = _saves.call(&"start_new_multiplayer_run", ids)
	var session: CampaignSession = _session()
	_check.call("co-op: a new 2-seat host run starts", (
			err == OK and session != null and session.seats == PackedInt32Array([0, 1])
			and session.mode == CampaignData.Mode.MULTIPLAYER
	), error_string(err))
	if session == null:
		return null
	var was_host: bool = _service.call(&"local_seat") == CampaignData.HOST_SEAT
	var is_set: bool = _service.call(&"set_local_seat", 1)
	_check.call("local seat: the host seat, until set to seat 1", (
			was_host and is_set and _service.call(&"local_seat") == 1
	), str(_service.call(&"local_seat")))
	session.run.seat_run(0).gold = HOST_GOLD
	session.run.seat_run(1).gold = OWN_GOLD
	session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
	return session


func _test_map() -> void:
	var session: CampaignSession = _session()
	var own: SeatRun = session.run.seat_run(1)
	var offer: StartingOffer = StartingOffer.pending(own)
	own.pending_offers.erase(StartingOffer.OFFER_KEY)
	var screen: Control = _add(MAP_SCENE)
	var header: RunHeader = screen.get_node(^"%RunHeader")
	_check.call("map: the header shows seat 1's gold", (
			header.get_gold_text() == "Gold %d" % [OWN_GOLD]
	), header.get_gold_text())
	_batches.clear()
	var map_view: CampaignMapView = screen.call(&"get_map_view")
	map_view.focus_first_reachable()
	_press_key(KEY_ENTER)
	var status: String = screen.call(&"get_status_text")
	_check.call("map: Enter sends seat 1's choice; the teammate's open offer refuses it by name", (
			_only_batch(1, true)
			and status == "Can't go there: Player 1 hasn't taken its starting heirloom."
	), "%s; %s" % [status, _batches])
	_press_key(KEY_CTRL)
	var army: ArmyView = screen.call(&"get_army_view")
	var rows_own: bool = not army.get_rows().is_empty()
	for row: UnitGearRow in army.get_rows():
		rows_own = rows_own and own.unit(row.unit_id) != null
	var team_button: Button = army.get_team_button()
	_check.call("map: Ctrl opens seat 1's army, with Team in co-op", (
			army.visible and rows_own and team_button.visible
	), "rows %d, team %s" % [army.get_rows().size(), team_button.visible])
	_test_team_panel_by_keys(screen, team_button, &"ARMY")
	own.gold = OWN_GOLD + 1
	var host: SeatRun = session.run.seat_run(0)
	var beet: String = session.ids.next_item_id("Heartbeet")
	host.items[beet] = ItemInstance.new(beet, INGREDIENT)
	host.convoy.append(beet)
	_batches.clear()
	_submit(ScrapItemCommand.new(0, beet))
	_check.call("map: the teammate's scrap rebuilds the header with seat 1's gold", (
			_only_batch(0, false) and header.get_gold_text() == "Gold %d" % [OWN_GOLD + 1]
	), header.get_gold_text())
	_remove(screen)
	offer.store(own)


# The Team panel over screen, opened from opener by keys: a row per teammate naming them, Enter
# on it onto their heirlooms, Esc back, Esc again closed with the focus and hints given back.
func _test_team_panel_by_keys(screen: Control, opener: Button, context: StringName) -> void:
	var hints: ScreenHints = screen.get_node(^"ScreenHints")
	var panel: TeamPanel = screen.call(&"get_team_panel")
	opener.grab_focus()
	_press_key(KEY_ENTER)
	var rows: Array[TeammateRow] = panel.get_rows()
	var name_text: String = rows[0].get_name_button().text if not rows.is_empty() else ""
	_check.call("team (keys): Enter on Team lists the teammate by name and gold", (
			panel.visible and rows.size() == 1 and rows[0].shown_seat == 0
			and name_text.begins_with("Player 1 · Gold %d" % [HOST_GOLD])
			and hints.context == TeamPanel.HINT_TEAM
			and rows[0].get_name_button().has_focus()
	), "%s; %s" % [name_text, hints.context])
	if rows.is_empty():
		return
	_press_key(KEY_ENTER)
	var on_icons: bool = rows[0].is_reading_heirlooms()
	var icons_context: StringName = hints.context
	_press_key(KEY_ESCAPE)
	_check.call("team (keys): Enter reads the teammate's heirlooms; Esc goes back to the row", (
			on_icons and icons_context == TeamPanel.HINT_HEIRLOOMS
			and not rows[0].is_reading_heirlooms() and panel.visible
			and rows[0].get_name_button().has_focus() and hints.context == TeamPanel.HINT_TEAM
	), "%s, %s" % [on_icons, icons_context])
	_press_key(KEY_ESCAPE)
	_check.call("team (keys): Esc closes it, giving back the focus and the hints", (
			not panel.visible and opener.has_focus() and hints.context == context
			and not _root.get_tree().paused
	), "%s; %s" % [opener.has_focus(), hints.context])


func _test_starting_offer() -> void:
	var session: CampaignSession = _session()
	var own: SeatRun = session.run.seat_run(1)
	var screen: Control = _add(START_SCENE)
	var view: StartingOfferView = screen.call(&"get_view")
	var shown: PackedStringArray = []
	for card: Button in view.get_cards():
		if card is HeirloomOfferCard:
			shown.append((card as HeirloomOfferCard).heirloom_name)
	var offered: PackedStringArray = []
	for option: StartingOffer.Option in StartingOffer.pending(own).options:
		var definition: HeirloomDefinition = StartingOffer.definition_of(option, _catalog)
		offered.append(definition.display_name if definition != null else option.heirloom_id)
	var header: RunHeader = screen.get_node(^"%RunHeader")
	_check.call("starting offer: seat 1's offer and gold show", (
			not shown.is_empty() and shown == offered
			and header.get_gold_text() == "Gold %d" % [own.gold]
	), "%s vs %s" % [shown, offered])
	_batches.clear()
	view.command_ready.emit(StartingHeirloomCommand.new(1, 99))
	_check.call("starting offer: the view's command goes out as seat 1's; its refusal shows", (
			_only_batch(1, true)
			and (view.get_status_text() as String).begins_with("Can't take it:")
	), view.get_status_text())
	_remove(screen)
	own.pending_offers.erase(StartingOffer.OFFER_KEY)


func _test_treasure() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.TREASURE)
	var gold_before: int = session.run.seat_run(1).gold
	for seat: int in session.seats:
		var chest: TreasureChest = TreasureChest.new()
		chest.gold = 25 if seat == 0 else 45
		chest.store(session.run.seat_run(seat))
	var screen: Control = _add(TREASURE_SCENE)
	var view: ChestView = screen.call(&"get_chest_view")
	_check.call("treasure: seat 1's chest shows", (
			view.get_gold_text().contains("45")
	), view.get_gold_text())
	_batches.clear()
	_click(screen.call(&"get_open_button") as Button)
	var own_chest: TreasureChest = TreasureChest.pending(session.run.seat_run(1))
	_check.call("treasure (mouse): Open takes seat 1's chest only", (
			_only_batch(1, false) and own_chest.is_taken
			and session.run.seat_run(1).gold == gold_before + 45
			and not TreasureChest.pending(session.run.seat_run(0)).is_resolved
			and screen.call(&"get_status_text") == "Took 45 gold."
	), "%s; %s" % [screen.call(&"get_status_text"), _batches])
	_batches.clear()
	_click(screen.call(&"get_leave_button") as Button)
	var status: String = screen.call(&"get_status_text")
	_check.call("treasure: Leave waits for the teammate's chest and says so by name", (
			_only_batch(1, true)
			and status == "Can't do that: Player 1 hasn't taken or given up its chest."
	), status)
	var team_button: Button = screen.call(&"get_team_button")
	var panel: TeamPanel = screen.call(&"get_team_panel")
	team_button.grab_focus()
	_press_pad(JOY_BUTTON_A)
	var opened: bool = panel.visible
	var host_gold: int = session.run.seat_run(0).gold
	_submit(TreasureCommand.new(0, true))
	var rows: Array[TeammateRow] = panel.get_rows()
	var row_text: String = rows[0].get_name_button().text if not rows.is_empty() else ""
	_check.call("treasure (pad): A opens Team; the teammate's take rebuilds their gold", (
			opened and row_text.begins_with("Player 1 · Gold %d" % [host_gold + 25])
	), row_text)
	_press_pad(JOY_BUTTON_B)
	_check.call("treasure (pad): B closes Team, no pause menu", (
			not panel.visible and team_button.has_focus() and not _root.get_tree().paused
	))
	_remove(screen)
	_leave_node()


func _test_camp() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.CAMP)
	var screen: Control = _add(CAMP_SCENE)
	var status_view: CampTeamStatus = screen.call(&"get_team_status")
	_check.call("camp: the teammate shows as still choosing", (
			status_view.visible
			and status_view.get_lines() == PackedStringArray(["Player 1 is still choosing."])
	), str(status_view.get_lines()))
	_batches.clear()
	(screen.call(&"get_feast_card") as Button).grab_focus()
	_press_key(KEY_ENTER)
	var ingredients: IngredientPanel = screen.call(&"get_ingredient_panel")
	_focus_starting(ingredients.get_choice_buttons(), "Cook nothing")
	_press_key(KEY_ENTER)
	_check.call("camp (keys): seat 1 feasts; the teammate hasn't chosen", (
			_only_batch(1, false)
			and Camp.choice_of(session.run.seat_run(1)) == Camp.Choice.FEAST
			and Camp.choice_of(session.run.seat_run(0)) == Camp.Choice.NONE
	), "%s" % [_batches])
	_batches.clear()
	_click(screen.call(&"get_leave_button") as Button)
	var status: String = screen.call(&"get_status_text")
	_check.call("camp: Leave waits for the teammate's choice and says so by name", (
			_only_batch(1, true)
			and status == "Can't do that: Player 1 hasn't chosen Feast or Train."
	), status)
	_submit(FeastCommand.new(0))
	_check.call("camp: the teammate's Feast rebuilds their line", (
			status_view.get_lines() == PackedStringArray(["Player 1 chose Feast."])
	), str(status_view.get_lines()))
	var panel: TeamPanel = screen.call(&"get_team_panel")
	_click(screen.call(&"get_team_button") as Button)
	var rows: Array[TeammateRow] = panel.get_rows()
	_check.call("camp (mouse): Team names the teammate's Camp choice", (
			panel.visible and rows.size() == 1
			and rows[0].get_note_text().contains("Player 1 chose Feast.")
	), rows[0].get_note_text() if not rows.is_empty() else "")
	_click(panel.get_close_button())
	_check.call("camp (mouse): Close closes Team", not panel.visible)
	_remove(screen)
	_leave_node()


func _test_armory() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.ARMORY)
	for seat: int in session.seats:
		session.run.seat_run(seat).gold = RICH
	var heirlooms: PackedStringArray = HeirloomDraw.candidates(
			session.run.seat_run(1), _catalog, PackedStringArray([ContentIds.HEIRLOOM_COMMON]),
			false
	)
	var stock: ArmoryStock = ArmoryStock.new()
	for index: int in 3:
		stock.entries.append(ArmoryStock.Entry.new(
				ArmoryStock.CATEGORY_HEIRLOOM, heirlooms[index], "", false
		))
	stock.store(session.run)
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	_submit(ArmoryPurchaseCommand.for_session(session, 0, 1))
	var sold: StockCard = view.card_for(1)
	_check.call("armory: the teammate's purchase rebuilds its card, bought by them", (
			sold != null and sold.disabled and sold.problem == "bought by Player 1"
	), sold.problem if sold != null else "no card")
	view.card_for(0).grab_focus()
	_press_pad(JOY_BUTTON_A)
	_submit(ArmoryPurchaseCommand.for_session(session, 0, 0))
	_batches.clear()
	_focus_starting(panel.get_choice_buttons(), "Buy for")
	_press_pad(JOY_BUTTON_A)
	_check.call("armory (pad): an entry the teammate bought first is refused by name", (
			_only_batch(1, true) and panel.visible
			and _panel_problem(panel) == "Can't do that: bought by Player 1."
	), _panel_problem(panel))
	_press_pad(JOY_BUTTON_B)
	_batches.clear()
	view.card_for(2).grab_focus()
	_press_key(KEY_ENTER)
	_focus_starting(panel.get_choice_buttons(), "Buy for")
	_press_key(KEY_ENTER)
	var header: RunHeader = screen.get_node(^"%RunHeader")
	var own: SeatRun = session.run.seat_run(1)
	_check.call("armory (keys): seat 1 buys for itself; its gold shows", (
			_only_batch(1, false) and own.heirloom_ids().has(heirlooms[2])
			and header.get_gold_text() == "Gold %d" % [own.gold] and own.gold < RICH
	), "%s; %s" % [header.get_gold_text(), _batches])
	_remove(screen)
	_leave_node()


func _test_guildhall() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.GUILDHALL)
	for seat: int in session.seats:
		session.run.seat_run(seat).gold = RICH
	var screen: Control = _add(GUILDHALL_SCENE)
	var stock: GuildhallStock = GuildhallStock.pending(session.run)
	var runes: PackedInt32Array = stock.indexes_of(GuildhallStock.CATEGORY_RUNE)
	var header: RunHeader = screen.get_node(^"%RunHeader")
	session.run.seat_run(1).gold = RICH - 1
	_submit(GuildhallPurchaseCommand.new(0, runes[0]))
	var view: GuildhallStockView = screen.call(&"get_stock_view")
	var card: StockCard = view.card_for(runes[0]) as StockCard
	_check.call("guildhall: the teammate's rune rebuilds its card, bought by them; seat 1's gold", (
			card != null and card.disabled and card.problem == "bought by Player 1"
			and header.get_gold_text() == "Gold %d" % [RICH - 1]
	), "%s; %s" % [card.problem if card != null else "no card", header.get_gold_text()])
	_remove(screen)
	_leave_node()


func _test_placeholder() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.UNKNOWN)
	var screen: Control = _add(PLACEHOLDER_SCENE)
	var header: RunHeader = screen.get_node(^"%RunHeader")
	_check.call("placeholder: seat 1's gold and Team show", (
			header.get_gold_text() == "Gold %d" % [session.run.seat_run(1).gold]
			and (screen.call(&"get_team_button") as Button).visible
	), header.get_gold_text())
	session.run.flow.stage = RunFlow.Stage.MAP
	_batches.clear()
	(screen.call(&"get_continue_button") as Button).grab_focus()
	_press_key(KEY_ENTER)
	_check.call("placeholder (keys): Continue sends seat 1's Leave; a refusal shows", (
			_only_batch(1, true)
			and screen.call(&"get_status_text") == "Couldn't leave: the run is on the map."
	), screen.call(&"get_status_text"))
	_remove(screen)


func _test_results() -> void:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, CampaignGraph.NodeType.KEY)
	session.run.flow.stage = RunFlow.Stage.RESULTS
	for seat: int in session.seats:
		var grades: CombatGrades = CombatGrades.new()
		grades.base_gold = 45 if seat == 0 else 123
		grades.gold = grades.base_gold
		session.run.seat_run(seat).pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
			"grades": grades.capture(), "xp": [], "level_ups": [],
		}
	var host: SeatRun = session.run.seat_run(0)
	var key: KeyHeirloom = KeyHeirloom.new()
	key.heirloom_id = HeirloomDraw.candidates(host, _catalog, HeirloomDraw.TIERS, false)[0]
	key.store(host)
	var screen: Control = _add(RESULTS_SCENE)
	var overlay: VictoryOverlay = screen.call(&"get_overlay")
	var model: CombatResultsModel = overlay.get_model()
	_check.call("results: the victory sequence shows seat 1's results", (
			model != null and model.grades.gold == 123
	), str(model.grades.gold) if model != null else "no model")
	# Grade, then the recap (no XP to fill), then Rewards, empty for seat 1.
	for _press: int in 2:
		overlay.get_primary_button().pressed.emit()
	_batches.clear()
	overlay.get_primary_button().pressed.emit()
	_check.call("results: Leave sends seat 1's; the teammate's open heirloom refuses it by name", (
			_only_batch(1, true) and overlay.get_stage() == VictoryOverlay.Stage.REWARDS
			and overlay.get_status_text()
			== "Can't do that: Player 1 hasn't taken or given up its heirloom."
	), "%s; stage %d" % [overlay.get_status_text(), overlay.get_stage()])
	_remove(screen)


func _test_seat_zero_scan() -> void:
	var pattern: RegEx = RegEx.create_from_string("seats\\s*\\[\\s*0\\s*\\]|seats\\.front\\(\\)")
	var found: PackedStringArray = []
	var scripts: PackedStringArray = SceneScan.files_under("res://ui/", ".gd")
	for path: String in scripts:
		if SEAT_ZERO_EXEMPT.has(path):
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			if pattern.search(lines[i]) != null:
				found.append("%s:%d" % [path, i + 1])
	_check.call("scan: no script under ui/ reads seats[0] (but %d listed for their steps)" % [
		SEAT_ZERO_EXEMPT.size(),
	], found.is_empty() and scripts.size() > 50, "; ".join(found))


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# Sends command as the teammate or the host would, outside any screen.
func _submit(command: CampaignCommand) -> void:
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	if batch == null or batch.is_rejected():
		_check.call("co-op: %s resolves" % [command.get_label()], false, (
				batch.rejected_reason if batch != null else "no batch"
		))


# Leaves the node the run is in, as the screens' Leave would, every seat's chest put aside.
func _leave_node() -> void:
	var run: CampaignRunState = _session().run
	for seat: int in run.seat_numbers():
		run.seat_run(seat).pending_offers.erase(TreasureChest.OFFER_KEY)
	_submit(LeaveNodeCommand.new(0))


# Whether exactly one batch settled since the last clear, of seat, rejected or not.
func _only_batch(seat: int, is_rejected: bool) -> bool:
	return _batches.size() == 1 and _batches[0] == [seat, is_rejected]


func _panel_problem(panel: Control) -> String:
	var label: Label = panel.find_child("Problem", true, false) as Label
	return label.text if label != null else ""


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	_batches.append([batch.seat, batch.is_rejected()])


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


func _focus_starting(buttons: Array[Button], prefix: String) -> void:
	for button: Button in buttons:
		if button.text.begins_with(prefix) and not button.disabled:
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
