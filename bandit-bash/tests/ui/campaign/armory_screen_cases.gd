# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     armory_screen_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Armory screen for tests/ui/campaign/run_all.gd, on a real solo run through the real
## SaveService and CampaignService, at 1280×720: routed to by an Armory node; its stock rolled and
## saved on entry, a card per entry priced for the seat; a weapon bought by keys (its unit, then
## the before/after comparison and the deal), equipment traded in by clicks, an heirloom by pad
## with B backing out and no pause menu; refused cards and deals saying why (gold, the convoy
## full); and a Save & Quit then Continue at the Armory showing the same stock, before and after
## buying. Leaving for the map is the walk's (run_all.gd), which routes; nothing here changes scene.
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const ARMORY_SCENE: String = "res://ui/campaign/armory_screen.tscn"

# SceneRouter.Screen.ARMORY: a case file can't name the autoload.
const SCREEN_ARMORY: int = 16

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
		_test_buy_by_key()
		_test_trade_in_by_mouse()
		_test_heirloom_by_pad()
		_test_refused()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_entry_and_resume() -> void:
	var session: CampaignSession = _session()
	_check.call("armory: the map has an Armory", Fixture.enter(session.run, _armory()))
	_check.call("armory: an Armory node routes to the Armory screen", (
			(RunScreen.of(session) as int) == SCREEN_ARMORY
	), str(RunScreen.of(session)))
	session.run.seat_run(0).gold = RICH
	var screen: Control = _add(ARMORY_SCENE)
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	var view: StockView = screen.call(&"get_stock_view")
	_check.call("armory: the stock is rolled and saved on entry, a card per entry, priced", (
			stock != null and view.get_cards().size() == stock.entries.size()
			and view.get_cards()[0].text.contains("gold")
	), "%d cards" % [view.get_cards().size()])
	var before: String = JSON.stringify(stock.capture())
	_remove(screen)
	var reopened: CampaignSession = _reopen()
	var kept: ArmoryStock = ArmoryStock.pending(reopened.run) if reopened != null else null
	_check.call("resume (before buying): Save & Quit, Continue shows the same stock", (
			kept != null and JSON.stringify(kept.capture()) == before
			and (RunScreen.of(reopened) as int) == SCREEN_ARMORY
	))
	if kept == null:
		return
	var index: int = _first_item(reopened, kept)
	var definition: ItemDefinition = _catalog.item(kept.entries[index].definition_id)
	var unit_id: String = Armory.usable_units(reopened.run.seat_run(0), definition, _catalog)[0]
	var bought: CampaignBatch = _service.call(&"submit_command", ArmoryPurchaseCommand.for_session(
			reopened, 0, index, unit_id, true
	))
	var gold_after: int = reopened.run.seat_run(0).gold
	var again: CampaignSession = _reopen()
	var sold: ArmoryStock = ArmoryStock.pending(again.run) if again != null else null
	_check.call("resume (after buying): the entry stays sold, the gold and the item kept", (
			bought != null and not bought.is_rejected()
			and sold != null and sold.entries[index].buyer == 0
			and again.run.seat_run(0).gold == gold_after
			and again.run.seat_run(0).items.has(kept.entries[index].instance_id)
	), bought.rejected_reason if bought != null else "no batch")
	_leave_node()


func _test_buy_by_key() -> void:
	var session: CampaignSession = _at_armory()
	var unit: UnitInstance = session.run.seat_run(0).army[0]
	var weapon: WeaponDefinition = _wieldable(unit)
	_stage(session, [_new_item(session, weapon.id, ArmoryStock.CATEGORY_WEAPON)])
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	view.card_for(0).grab_focus()
	_press_key(KEY_ENTER)
	var asked_unit: bool = panel.visible and panel.get_step() == PurchasePanel.Step.UNIT
	_focus_starting(panel.get_choice_buttons(), "Onto")
	_press_key(KEY_ENTER)
	var comparison: ItemComparison = panel.get_comparison()
	var rows: PackedStringArray = []
	for row: PackedStringArray in comparison.shown:
		rows.append(row[0])
	_check.call("keys: Enter on a card asks the unit, then shows the before/after comparison", (
			asked_unit and panel.get_step() == PurchasePanel.Step.DEAL
			and comparison.visible and rows.has("Damage") and rows.has("Hit")
	), str(rows))
	var gold_before: int = session.run.seat_run(0).gold
	_focus_starting(panel.get_choice_buttons(), "Trade in")
	_press_key(KEY_ENTER)
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	_check.call("keys: Enter on the deal buys it; the card shows sold, the status the price", (
			stock.entries[0].buyer == 0 and not panel.visible
			and unit.weapon_id == stock.entries[0].instance_id
			and session.run.seat_run(0).gold < gold_before
			and (screen.call(&"get_status_text") as String).begins_with("Bought")
			and view.card_for(0).disabled
	), screen.call(&"get_status_text") as String)
	_remove(screen)
	_leave_node()


func _test_trade_in_by_mouse() -> void:
	var session: CampaignSession = _at_armory()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit: UnitInstance = seat_run.army[0]
	var equipment: ItemDefinition = _first_of(EffectCatalog.Kind.EQUIPMENT)
	var held: ItemInstance = _hold(session, unit, equipment)
	_stage(session, [_new_item(session, equipment.id, ArmoryStock.CATEGORY_EQUIPMENT)])
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	_click(view.card_for(0))
	var onto: Button = _starting(panel.get_choice_buttons(), "Onto")
	if onto != null:
		_click(onto)
	var trade: Button = _starting(panel.get_choice_buttons(), "Trade in")
	var value: int = Armory.trade_in_value(seat_run, unit.instance_id, equipment, _catalog)
	var price: int = Armory.price(seat_run, ArmoryStock.pending(session.run).entries[0], _catalog)
	var gold_before: int = seat_run.gold
	if trade != null:
		_click(trade)
	_check.call("mouse: clicks buy equipment, trading the old piece in for its scrap value", (
			onto != null and trade != null
			and not seat_run.items.has(held.instance_id)
			and seat_run.gold == gold_before - (price - value)
			and not panel.visible
	), "%s; %d -> %d" % [
		trade.text if trade != null else "no trade-in", gold_before, seat_run.gold,
	])
	_remove(screen)
	_leave_node()


func _test_heirloom_by_pad() -> void:
	var session: CampaignSession = _at_armory()
	var seat_run: SeatRun = session.run.seat_run(0)
	var heirloom_id: String = HeirloomDraw.candidates(
			seat_run, _catalog, PackedStringArray([ContentIds.HEIRLOOM_COMMON]), false
	)[0]
	_stage(session, [
		ArmoryStock.Entry.new(ArmoryStock.CATEGORY_HEIRLOOM, heirloom_id, "", false),
	])
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	view.card_for(0).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var asked: bool = panel.visible and panel.get_step() == PurchasePanel.Step.HEIRLOOM
	_press_pad(JOY_BUTTON_B)
	_check.call("pad: A on an heirloom shows its price; B backs out, no pause menu", (
			asked and not panel.visible and not _root.get_tree().paused
			and not seat_run.heirloom_ids().has(heirloom_id)
	), "asked %s, paused %s" % [asked, _root.get_tree().paused])
	view.card_for(0).grab_focus()
	_press_pad(JOY_BUTTON_A)
	_focus_starting(panel.get_choice_buttons(), "Buy for")
	_press_pad(JOY_BUTTON_A)
	_check.call("pad: A, A buys the heirloom into the heirlooms", (
			seat_run.heirloom_ids().has(heirloom_id) and not panel.visible
	))
	_remove(screen)
	_leave_node()


func _test_refused() -> void:
	var session: CampaignSession = _at_armory()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit: UnitInstance = seat_run.army[0]
	var weapon: WeaponDefinition = _wieldable(unit)
	_hold(session, unit, weapon)
	_stage(session, [_new_item(session, weapon.id, ArmoryStock.CATEGORY_WEAPON)])
	seat_run.gold = 0
	var poor: Control = _add(ARMORY_SCENE)
	var card: StockCard = (poor.call(&"get_stock_view") as StockView).card_for(0)
	_check.call("refused: a card the seat can't afford says why and takes no focus", (
			card.disabled and card.focus_mode == Control.FOCUS_NONE
			and card.text.contains("Can't buy: too little gold")
	), card.text)
	_remove(poor)
	seat_run.gold = RICH
	while not ItemPlacement.is_convoy_full(seat_run, _catalog):
		Fixture.add_to_convoy(seat_run, weapon.id, session.ids)
	var screen: Control = _add(ARMORY_SCENE)
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	(screen.call(&"get_stock_view") as StockView).card_for(0).pressed.emit()
	panel.choose_unit(unit.instance_id)
	var convoy: Button = null
	for button: Button in panel.get_choice_buttons():
		if button.text.begins_with("Send"):
			convoy = button
	_check.call("refused: the convoy full, sending the old weapon there is greyed, saying why", (
			convoy != null and convoy.disabled and convoy.text.contains("convoy is full")
			and _starting(panel.get_choice_buttons(), "Trade in") != null
	), convoy.text if convoy != null else "no convoy choice")
	_remove(screen)
	_leave_node()


# A new solo run through SaveService, past its starting offer; null, checked, if none starts.
func _new_run() -> CampaignSession:
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = _session()
	_check.call("armory: a new solo run starts", err == OK and session != null, error_string(err))
	if session == null:
		return null
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	return session


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# The run inside its first Armory with plenty of gold.
func _at_armory() -> CampaignSession:
	var session: CampaignSession = _session()
	Fixture.enter(session.run, _armory())
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
		_check.call("armory: the node is left", false, left.rejected_reason if left != null else "")


func _stage(session: CampaignSession, entries: Array) -> void:
	var stock: ArmoryStock = ArmoryStock.new()
	for entry: ArmoryStock.Entry in entries:
		stock.entries.append(entry)
	stock.store(session.run)


func _new_item(
		session: CampaignSession, definition_id: String, category: String
) -> ArmoryStock.Entry:
	return ArmoryStock.Entry.new(
			category, definition_id, session.ids.next_item_id(definition_id), false
	)


# The first unsold item entry of stock seat 0 can buy.
func _first_item(session: CampaignSession, stock: ArmoryStock) -> int:
	for index: int in stock.entries.size():
		if stock.entries[index].is_heirloom():
			continue
		if Armory.entry_problem(session.run, 0, index, _catalog).is_empty():
			return index
	return 0


# A Common weapon unit can wield.
func _wieldable(unit: UnitInstance) -> WeaponDefinition:
	var types: PackedStringArray = ItemPlacement.weapon_types_of(unit, _catalog)
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	for definition: ItemDefinition in ItemPools.items_of(_catalog, kinds):
		var weapon: WeaponDefinition = definition as WeaponDefinition
		if (
				weapon != null and weapon.rarity == ItemDefinition.Rarity.COMMON
				and types.has(weapon.weapon_type)
		):
			return weapon
	return null


# The first Common item of kind.
func _first_of(kind: EffectCatalog.Kind) -> ItemDefinition:
	var kinds: Array[EffectCatalog.Kind] = [kind]
	for definition: ItemDefinition in ItemPools.items_of(_catalog, kinds):
		if definition.rarity == ItemDefinition.Rarity.COMMON:
			return definition
	return null


# Puts a new item of definition in unit's slot for it, dropping what was there from the roster.
func _hold(
		session: CampaignSession, unit: UnitInstance, definition: ItemDefinition
) -> ItemInstance:
	var seat_run: SeatRun = session.run.seat_run(0)
	var slot: Loadout.Slot = ItemPlacement.slot_for(definition)
	var previous: String = ItemPlacement.item_in(unit, slot)
	if not previous.is_empty():
		seat_run.items.erase(previous)
	var item_id: String = session.ids.next_item_id(definition.id)
	var item: ItemInstance = ItemInstance.new(item_id, definition.id)
	seat_run.items[item_id] = item
	ItemPlacement.put_item(unit, slot, item_id)
	return item


func _armory() -> CampaignGraph.NodeType:
	return CampaignGraph.NodeType.ARMORY


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
