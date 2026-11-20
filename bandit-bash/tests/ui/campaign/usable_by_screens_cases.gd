# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     usable_by_screens_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## Who can use an item, on the Armory's stock cards and the Treasure chest, on a real solo run
## through the real SaveService and CampaignService, at 1280×720: a weapon's card shows the icons
## of exactly its wielders and names them on focus, equipment says "Any unit", an heirloom's card
## shows no row; buying still works by keys, pad and a click on a wielder's icon; and the chest
## names its weapon's wielders while Open has focus, reached by d-pad, beside the card so the gold
## line stays clear.[br]
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload or a screen: they are reached as nodes and by call().

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const ARMORY_SCENE: String = "res://ui/campaign/armory_screen.tscn"
const TREASURE_SCENE: String = "res://ui/campaign/treasure_screen.tscn"

# The save file the cases write, in the test user folder only; the walk uses 1.
const SAVE_NUMBER: int = 3
const RUN_SEED: int = 0x0B10

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# Gold a staged seat holds, enough for anything stocked. Units: gold.
const RICH: int = 1000

# The staged stock's entries, by index.
const WEAPON: int = 0
const EQUIPMENT: int = 1
const HEIRLOOM: int = 2
const SECOND_WEAPON: int = 3

# The most a card's who-can-use row may end short of its right edge: the card's 12-unit margin and
# a little slack. Units: base units.
const RIGHT_EDGE_SLACK: float = 16.0

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
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = _session()
	_check.call("usable by: a new solo run starts", (
			err == OK and session != null
	), error_string(err))
	if session != null:
		session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
		_test_armory(session)
		_test_chest(session)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_armory(session: CampaignSession) -> void:
	var seat_run: SeatRun = session.run.seat_run(0)
	var weapon: WeaponDefinition = _some_wield(seat_run)
	var equipment: ItemDefinition = _first_of(EffectCatalog.Kind.EQUIPMENT)
	var heirloom_ids: PackedStringArray = HeirloomDraw.candidates(
			seat_run, _catalog, PackedStringArray([ContentIds.HEIRLOOM_COMMON]), false
	)
	_check.call("armory: the run has a weapon some units wield, equipment and an heirloom", (
			weapon != null and equipment != null and not heirloom_ids.is_empty()
			and Fixture.enter(session.run, CampaignGraph.NodeType.ARMORY)
	))
	if weapon == null or equipment == null or heirloom_ids.is_empty():
		return
	seat_run.gold = RICH
	_stage(session, [
		_new_item(session, weapon.id, ArmoryStock.CATEGORY_WEAPON),
		_new_item(session, equipment.id, ArmoryStock.CATEGORY_EQUIPMENT),
		ArmoryStock.Entry.new(ArmoryStock.CATEGORY_HEIRLOOM, heirloom_ids[0], "", false),
		_new_item(session, weapon.id, ArmoryStock.CATEGORY_WEAPON),
	])
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var expected: PackedStringArray = _wielder_names(session, weapon)
	var row: ItemUsableBy = view.card_for(WEAPON).get_usable_by()
	_check.call("armory: a weapon's card shows the icons of exactly the units that wield it", (
			row.visible and row.get_icon_names() == expected.slice(0, row.max_icons)
			and expected.size() < seat_run.army.size()
			and row.get_more_text() == (
					"" if expected.size() <= row.max_icons
					else row.more_format % [expected.size() - row.max_icons]
			)
	), "%s; expected %s of %d units" % [
		", ".join(row.get_icon_names()), ", ".join(expected), seat_run.army.size(),
	])
	var any: ItemUsableBy = view.card_for(EQUIPMENT).get_usable_by()
	_check.call("armory: an equipment card says Any unit, with no icons", (
			any.visible and any.get_note_text() == "Any unit" and any.get_icons().is_empty()
	), any.get_note_text())
	_check.call("armory: an heirloom's card shows no who-can-use row", (
			not view.card_for(HEIRLOOM).get_usable_by().visible
	))
	_check.call("armory: the rows sit inside their cards at the right, over no line", (
			_fits_inside(view.card_for(WEAPON)) and _fits_inside(view.card_for(EQUIPMENT))
	))
	view.card_for(WEAPON).grab_focus()
	var tip: PackedStringArray = row.get_tip().get_texts()
	_check.call("armory: focus on the weapon's card names every wielder", (
			row.get_tip().visible and tip[0] == row.names_title and tip[1] == ", ".join(expected)
	), " / ".join(tip))
	view.card_for(EQUIPMENT).grab_focus()
	_check.call("armory: focus leaving the card hides the names", (
			not row.get_tip().visible and not any.get_tip().visible
	))
	_remove(screen)
	_test_buy_by_key(session)
	_test_buy_by_pad(session)
	_test_buy_by_click(session)
	_leave_node()


func _test_buy_by_key(session: CampaignSession) -> void:
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	view.card_for(WEAPON).grab_focus()
	_press_key(KEY_ENTER)
	var asked: bool = panel.visible and panel.get_step() == PurchasePanel.Step.UNIT
	_focus(_onto(panel))
	_press_key(KEY_ENTER)
	_focus(_deal(panel))
	_press_key(KEY_ENTER)
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	_check.call("keys: Enter on a weapon's card, its unit and a deal buys it", (
			asked and stock.entries[WEAPON].buyer == 0 and not panel.visible
	), screen.call(&"get_status_text") as String)
	_remove(screen)


func _test_buy_by_pad(session: CampaignSession) -> void:
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	view.card_for(EQUIPMENT).grab_focus()
	_press_pad(JOY_BUTTON_A)
	var asked: bool = panel.visible and panel.get_step() == PurchasePanel.Step.UNIT
	_focus(_onto(panel))
	_press_pad(JOY_BUTTON_A)
	_focus(_deal(panel))
	_press_pad(JOY_BUTTON_A)
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	_check.call("pad: A on an equipment card, its unit and a deal buys it", (
			asked and stock.entries[EQUIPMENT].buyer == 0 and not panel.visible
	), screen.call(&"get_status_text") as String)
	_remove(screen)


func _test_buy_by_click(session: CampaignSession) -> void:
	var screen: Control = _add(ARMORY_SCENE)
	var view: StockView = screen.call(&"get_stock_view")
	var panel: PurchasePanel = screen.call(&"get_purchase_panel")
	var icons: Array[ItemUserIcon] = view.card_for(SECOND_WEAPON).get_usable_by().get_icons()
	if not icons.is_empty():
		_click(icons[0])
	var asked: bool = panel.visible and panel.get_step() == PurchasePanel.Step.UNIT
	var onto: Button = _onto(panel)
	if onto != null:
		_click(onto)
	var deal: Button = _deal(panel)
	if deal != null:
		_click(deal)
	var stock: ArmoryStock = ArmoryStock.pending(session.run)
	_check.call("mouse: a click on a wielder's icon presses its card; clicks then buy it", (
			not icons.is_empty() and asked and stock.entries[SECOND_WEAPON].buyer == 0
			and not panel.visible
	), screen.call(&"get_status_text") as String)
	_remove(screen)


func _test_chest(session: CampaignSession) -> void:
	var seat_run: SeatRun = session.run.seat_run(0)
	var weapon: ItemDefinition = null
	for legendary: ItemDefinition in TreasureChest.usable_legendaries(seat_run, _catalog):
		if legendary is WeaponDefinition:
			weapon = legendary
			break
	_check.call("treasure: the run has a usable Legendary weapon and a Treasure", (
			weapon != null and Fixture.enter(session.run, CampaignGraph.NodeType.TREASURE)
	))
	if weapon == null:
		return
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_RARE
	chest.item = ItemPick.Offer.new(weapon.id, session.ids.next_item_id(weapon.id))
	chest.gold = TreasureChest.GOLD_MIN
	chest.store(seat_run)
	var screen: Control = _add(TREASURE_SCENE)
	var view: ChestView = screen.call(&"get_chest_view")
	var open: Button = screen.call(&"get_open_button")
	var leave: Button = screen.call(&"get_leave_button")
	var row: ItemUsableBy = view.get_item_card().get_usable_by()
	leave.grab_focus()
	_press_pad(JOY_BUTTON_DPAD_LEFT)
	_lay_out(screen)
	var tip: PackedStringArray = row.get_tip().get_texts()
	var expected: String = ", ".join(_wielder_names(session, weapon))
	_check.call("treasure: d-pad to Open names every wielder of the chest's weapon", (
			_root.gui_get_focus_owner() == open and row.get_tip().visible
			and tip[0] == row.names_title and tip[1] == expected
	), "%s; expected %s; focus %s, row shown %s, Open shown %s, chest %s" % [
		" / ".join(tip), expected, _root.gui_get_focus_owner(), row.is_visible_in_tree(),
		open.visible, view.get_size_text(),
	])
	var tip_area: Rect2 = row.get_tip().get_global_rect()
	var gold: Label = _gold_label(view)
	_check.call("treasure: the names open beside the card, clear of the gold line and buttons", (
			gold != null and not tip_area.intersects(gold.get_global_rect())
			and not tip_area.intersects(open.get_global_rect())
			and tip_area.position.x >= view.get_item_card().get_global_rect().end.x - row.size.x
	), "%s; gold %s" % [tip_area, gold.get_global_rect() if gold != null else Rect2()])
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	_check.call("treasure: d-pad on to Leave hides the names", (
			_root.gui_get_focus_owner() == leave and not row.get_tip().visible
	))
	_remove(screen)


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# Each unit of the seat that can wield definition, named as the row names it, in army order.
func _wielder_names(session: CampaignSession, definition: ItemDefinition) -> PackedStringArray:
	var seat_run: SeatRun = session.run.seat_run(0)
	var names: PackedStringArray = []
	for unit: UnitInstance in ItemUsableBy.wielders(definition, seat_run, _catalog):
		names.append(CombatResultsModel.unit_name(
				session.ids, seat_run, unit.instance_id, _catalog
		))
	return names


# A Common weapon some of the seat's units wield and some don't; null for none.
func _some_wield(seat_run: SeatRun) -> WeaponDefinition:
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	for definition: ItemDefinition in ItemPools.items_of(_catalog, kinds):
		var weapon: WeaponDefinition = definition as WeaponDefinition
		if weapon == null or weapon.rarity != ItemDefinition.Rarity.COMMON:
			continue
		var count: int = ItemUsableBy.wielders(weapon, seat_run, _catalog).size()
		if count > 0 and count < seat_run.army.size():
			return weapon
	return null


# The first Common item of kind.
func _first_of(kind: EffectCatalog.Kind) -> ItemDefinition:
	var kinds: Array[EffectCatalog.Kind] = [kind]
	for definition: ItemDefinition in ItemPools.items_of(_catalog, kinds):
		if definition.rarity == ItemDefinition.Rarity.COMMON:
			return definition
	return null


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


# The unit step's first enabled "Onto" choice: a unit that can use the item; null for none.
func _onto(panel: PurchasePanel) -> Button:
	if panel.get_step() != PurchasePanel.Step.UNIT:
		return null
	for button: Button in panel.get_choice_buttons():
		if button.text.begins_with("Onto") and not button.disabled:
			return button
	return null


# The deal step's first enabled deal; null for none.
func _deal(panel: PurchasePanel) -> Button:
	if panel.get_step() != PurchasePanel.Step.DEAL:
		return null
	for button: Button in panel.get_choice_buttons():
		if button.text != "Back" and not button.disabled:
			return button
	return null


func _focus(button: Button) -> void:
	if button != null:
		button.grab_focus()


# The chest's gold line, found by its text, as the view keeps it private.
func _gold_label(view: ChestView) -> Label:
	for label: Label in view.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == view.get_gold_text():
			return label
	return null


# Whether every line and the who-can-use row lie inside card, the row over none of the lines and
# right of them all.
func _fits_inside(card: StockCard) -> bool:
	var area: Rect2 = card.get_global_rect()
	var row: Rect2 = card.get_usable_by().get_global_rect()
	for label: Label in card.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree() or card.get_usable_by().is_ancestor_of(label):
			continue
		var line: Rect2 = label.get_global_rect()
		if not area.encloses(line) or line.intersects(row):
			return false
	return area.encloses(row) and area.end.x - row.end.x <= RIGHT_EDGE_SLACK


# Leaves the node the run is in, as the screen's Leave would.
func _leave_node() -> void:
	var left: CampaignBatch = _service.call(&"submit_command", LeaveNodeCommand.new(0))
	if left == null or left.is_rejected():
		_check.call("armory: the node is left", false, left.rejected_reason if left != null else "")


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


# Lays out the screen as frames would: its containers sorted, parents first, each card fitted
# to its content, then sorted again for the last fit.
func _lay_out(screen: Control) -> void:
	var nodes: Array[Node] = screen.find_children("*", "", true, false)
	for _pass: int in 3:
		for node: Node in nodes:
			if node is Container and is_instance_valid(node):
				node.notification(Container.NOTIFICATION_SORT_CHILDREN)
		# A resized label rewraps when drawn, and nothing draws here: asking its size rewraps it.
		for node: Node in nodes:
			if node is Label and is_instance_valid(node):
				(node as Label).get_minimum_size()
		for node: Node in nodes:
			if node is StockCard and is_instance_valid(node):
				(node as StockCard).fit_content()
			elif node is ItemOfferCard and is_instance_valid(node):
				(node as ItemOfferCard).fit_content()


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
