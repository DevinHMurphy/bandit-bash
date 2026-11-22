# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     shop_panel_keywords_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## Keyword tooltips in the shop panels by keyboard and pad, for the ui/campaign suite. In the
## [PurchasePanel]'s deal (the Iron Shield held, the Knight Shield offered), pad focus on a choice
## shows the Details' and the comparison's keywords in one column on the Details text, each once;
## moving between choices keeps it; a hovered keyword adds none; focus leaving the panel, or the
## panel closing, hides it; mouse focus shows none while hovering still shows a keyword's own. The
## [GuildhallPanel]'s rune (Clarity) likewise. The column sits beside the panel, inside the window,
## at 1280×720, 1920×1080 and 1280×800. Real panel scenes on the root viewport, on a real run.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const PURCHASE_SCENE: PackedScene = preload("res://ui/campaign/purchase_panel.tscn")
const GUILDHALL_SCENE: PackedScene = preload("res://ui/campaign/guildhall_panel.tscn")

const RUN_SEED: int = 0xBF9

# The equipment compared: Iron Shield (DEF, Block) held; Knight Shield (DEF, RES, Block) offered.
const HELD_ID: String = "iron_shield"
const OFFERED_ID: String = "knight_shield"
const DEAL_IDS: PackedStringArray = ["def", "block", "res"]

# Details text staged on the deal, as an item's own details carry no keyword: HP is new, DEF is
# the comparison's too.
const STAGED_DETAILS: String = "+4 [kw=hp]HP[/kw] and +1 [kw=def]DEF[/kw]."
const STAGED_IDS: PackedStringArray = ["hp", "def", "block", "res"]

# The rune stocked: Hit, Attack and Phase End.
const RUNE_ID: String = "clarity"
const RUNE_IDS: PackedStringArray = ["hit", "attack", "phase_end"]

const SCREEN_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 800),
]

# Gold a staged seat holds, enough for every deal. Units: gold.
const RICH: int = 1000

var _check: Callable
var _root: Window = null
var _catalog: EffectCatalog.Index = null
var _session: CampaignSession = null
var _unit_id: String = ""


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the panels are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	_catalog = EffectCatalog.index()
	_session = Fixture.session(RUN_SEED)
	var seat_run: SeatRun = _session.run.seat_run(0)
	seat_run.gold = RICH
	if not _hold_shield(seat_run):
		return
	var old_size: Vector2i = _root.size
	_root.size = SCREEN_SIZES[0]
	_test_purchase_by_pad()
	_test_purchase_by_mouse()
	_test_guildhall()
	_test_on_screen()
	_root.size = old_size


func _test_purchase_by_pad() -> void:
	var panel: PurchasePanel = _open_deal()
	if panel == null:
		return
	var details: EffectText = panel.get_node(^"%Details")
	var buttons: Array[Button] = panel.get_choice_buttons()
	_ok("purchase: the deal opens with its first choice under key or pad focus", (
			buttons.size() == 3 and buttons[0].has_focus(true)
	), "%d choices" % [buttons.size()])
	_ok("purchase: pad focus shows the comparison's keywords, each once, beside the panel", (
			_shown_ids(details) == DEAL_IDS
	), str(_shown_ids(details)))
	details.marked_text = STAGED_DETAILS
	_press_pad(JOY_BUTTON_DPAD_DOWN)
	_ok("purchase: moving to the next choice keeps the column, with the Details' keywords first", (
			buttons[1].has_focus(true) and _shown_ids(details) == STAGED_IDS
	), str(_shown_ids(details)))
	_press_pad(JOY_BUTTON_DPAD_UP)
	_ok("purchase: and moving back keeps it", (
			buttons[0].has_focus(true) and _shown_ids(details) == STAGED_IDS
	), str(_shown_ids(details)))
	var cells: Array[EffectText] = panel.get_comparison().get_effect_texts()
	var is_cell_quiet: bool = not cells.is_empty()
	for cell: EffectText in cells:
		cell.meta_hover_started.emit(DEAL_IDS[0])
		is_cell_quiet = is_cell_quiet and cell.get_shown_tooltips().is_empty()
		cell.meta_hover_ended.emit(DEAL_IDS[0])
	_ok("purchase: meanwhile a hovered comparison keyword adds no tooltip of its own", (
			is_cell_quiet and _shown_ids(details) == STAGED_IDS
	), str(_shown_ids(details)))
	details.meta_hover_started.emit(STAGED_IDS[0])
	var while_hovered: PackedStringArray = _shown_ids(details)
	details.meta_hover_ended.emit(STAGED_IDS[0])
	_ok("purchase: and a hovered Details keyword keeps the whole column", (
			while_hovered == STAGED_IDS and _shown_ids(details) == STAGED_IDS
	), "%s, then %s" % [while_hovered, _shown_ids(details)])
	var outside: Button = Button.new()
	_root.add_child(outside)
	outside.grab_focus()
	_ok("purchase: focus leaving the panel hides the column", (
			details.get_shown_tooltips().is_empty()
	), str(_shown_ids(details)))
	buttons[0].grab_focus()
	_ok("purchase: focus coming back shows it again", _shown_ids(details) == STAGED_IDS, (
			str(_shown_ids(details))
	))
	panel.close()
	_ok("purchase: closing the panel hides the column", details.get_shown_tooltips().is_empty(), (
			str(_shown_ids(details))
	))
	_free(outside)
	_free(panel)


func _test_purchase_by_mouse() -> void:
	var panel: PurchasePanel = _open_deal()
	if panel == null:
		return
	var details: EffectText = panel.get_node(^"%Details")
	var buttons: Array[Button] = panel.get_choice_buttons()
	_lay_out(panel)
	var point: Vector2 = buttons[1].get_global_rect().get_center()
	_push_click(point, true)
	_ok("purchase: a mouse press focuses the choice with the focus hidden, and shows no column", (
			buttons[1].has_focus() and not buttons[1].has_focus(true)
			and details.get_shown_tooltips().is_empty()
	), "focus %s, %s" % [buttons[1].has_focus(), _shown_ids(details)])
	# Released away from the choice, so nothing is pressed.
	_push_click(Vector2.ZERO, false)
	var cells: Array[EffectText] = panel.get_comparison().get_effect_texts()
	var after: EffectText = null if cells.is_empty() else cells[cells.size() - 1]
	if after == null:
		_ok("purchase: the comparison has effect cells", false, "")
		_free(panel)
		return
	after.meta_hover_started.emit(DEAL_IDS[2])
	var hovered: Array[KeywordTooltip] = after.get_shown_tooltips()
	_ok("purchase: with mouse focus, hovering a keyword shows its own tooltip alone", (
			hovered.size() == 1 and hovered[0].keyword_id == DEAL_IDS[2]
			and details.get_shown_tooltips().is_empty()
	), "%d on the cell, %s on the Details" % [hovered.size(), _shown_ids(details)])
	after.meta_hover_ended.emit(DEAL_IDS[2])
	_ok("purchase: and leaving it hides it, no column after", (
			after.get_shown_tooltips().is_empty() and details.get_shown_tooltips().is_empty()
	), "")
	_free(panel)


func _test_guildhall() -> void:
	var panel: GuildhallPanel = _open_rune()
	if panel == null:
		return
	var details: EffectText = panel.get_node(^"%Details")
	var buttons: Array[Button] = panel.get_choice_buttons()
	_ok("guildhall: the rune's first choice holds key or pad focus", (
			panel.get_step() == GuildhallPanel.Step.RUNE and buttons.size() >= 2
			and buttons[0].has_focus(true)
	), "%d choices" % [buttons.size()])
	_ok("guildhall: pad focus shows the rune's keywords, each once, beside the panel", (
			_shown_ids(details) == RUNE_IDS
	), str(_shown_ids(details)))
	_press_pad(JOY_BUTTON_DPAD_DOWN)
	_ok("guildhall: moving to the next choice keeps the column", (
			buttons[1].has_focus(true) and _shown_ids(details) == RUNE_IDS
	), str(_shown_ids(details)))
	details.meta_hover_started.emit(RUNE_IDS[1])
	details.meta_hover_ended.emit(RUNE_IDS[1])
	_ok("guildhall: a hovered keyword keeps the whole column", _shown_ids(details) == RUNE_IDS, (
			str(_shown_ids(details))
	))
	var outside: Button = Button.new()
	_root.add_child(outside)
	outside.grab_focus()
	_ok("guildhall: focus leaving the panel hides the column", (
			details.get_shown_tooltips().is_empty()
	), str(_shown_ids(details)))
	_free(outside)
	buttons[0].grab_focus(true)
	_ok("guildhall: mouse focus shows none", details.get_shown_tooltips().is_empty(), (
			str(_shown_ids(details))
	))
	details.meta_hover_started.emit(RUNE_IDS[0])
	_ok("guildhall: and hovering a keyword shows its own", (
			_shown_ids(details) == PackedStringArray([RUNE_IDS[0]])
	), str(_shown_ids(details)))
	details.meta_hover_ended.emit(RUNE_IDS[0])
	_press_pad(JOY_BUTTON_DPAD_DOWN)
	_ok("guildhall: a pad press after the mouse shows the column", (
			buttons[1].has_focus(true) and _shown_ids(details) == RUNE_IDS
	), str(_shown_ids(details)))
	panel.close()
	_ok("guildhall: closing the panel hides the column", details.get_shown_tooltips().is_empty(), (
			str(_shown_ids(details))
	))
	_free(panel)


# Each panel's column beside its panel and inside the window at each size.
func _test_on_screen() -> void:
	for screen_size: Vector2i in SCREEN_SIZES:
		_root.size = screen_size
		var purchase: PurchasePanel = _open_deal()
		if purchase != null:
			var details: EffectText = purchase.get_node(^"%Details")
			details.marked_text = STAGED_DETAILS
			purchase.get_choice_buttons()[1].grab_focus()
			_check_on_screen("purchase", purchase, details, STAGED_IDS, screen_size)
			_free(purchase)
		var guildhall: GuildhallPanel = _open_rune()
		if guildhall != null:
			var rune_details: EffectText = guildhall.get_node(^"%Details")
			_check_on_screen("guildhall", guildhall, rune_details, RUNE_IDS, screen_size)
			_free(guildhall)
	_root.size = SCREEN_SIZES[0]


func _check_on_screen(
		what: String,
		panel: Control,
		details: EffectText,
		ids: PackedStringArray,
		screen_size: Vector2i
) -> void:
	_lay_out(panel)
	_settle(details)
	var screen: Rect2 = _root.get_visible_rect()
	var outside: PackedStringArray = []
	for tooltip: KeywordTooltip in details.get_shown_tooltips():
		var rect: Rect2 = tooltip.get_global_rect()
		if not screen.grow(0.5).encloses(rect):
			outside.append("%s %s" % [tooltip.keyword_id, rect])
	var column: Rect2 = details.get_tooltip_column().get_global_rect()
	var box: Rect2 = details.get_card().get_global_rect()
	var is_beside: bool = (
			column.position.x >= box.end.x - 0.5 or column.end.x <= box.position.x + 0.5
	)
	_ok("on screen: at %dx%d the %s column is beside its panel and inside the window" % [
		screen_size.x, screen_size.y, what,
	], (
			_shown_ids(details) == ids and outside.is_empty() and is_beside
			and details.get_card() is PanelContainer
	), "%s; column %s, panel %s, window %s" % [", ".join(outside), column, box, screen])


# The purchase panel at the deal of the Knight Shield onto the unit holding the Iron Shield;
# null, failing, when it can't open there.
func _open_deal() -> PurchasePanel:
	if not Fixture.enter(_session.run, CampaignGraph.NodeType.ARMORY):
		_ok("purchase: the map has an Armory", false, "seed %d" % [RUN_SEED])
		return null
	var stock: ArmoryStock = ArmoryStock.new()
	stock.entries.append(ArmoryStock.Entry.new(
			ArmoryStock.CATEGORY_EQUIPMENT, OFFERED_ID, _session.ids.next_item_id(OFFERED_ID), false
	))
	stock.store(_session.run)
	var panel: PurchasePanel = PURCHASE_SCENE.instantiate()
	_root.add_child(panel)
	panel.open(_session.run, 0, 0, _catalog, _session.ids)
	panel.choose_unit(_unit_id)
	if panel.get_step() != PurchasePanel.Step.DEAL or panel.get_choice_buttons().size() != 3:
		_ok("purchase: the deal opens with trade-in, convoy and Back", false, (
				"%d choices" % [panel.get_choice_buttons().size()]
		))
		_free(panel)
		return null
	return panel


# The Guildhall panel at a stocked rune, with a slot free; null, failing, when it can't open there.
func _open_rune() -> GuildhallPanel:
	if not Fixture.enter(_session.run, CampaignGraph.NodeType.GUILDHALL):
		_ok("guildhall: the map has a Guildhall", false, "seed %d" % [RUN_SEED])
		return null
	var stock: GuildhallStock = GuildhallStock.new()
	var entry: GuildhallStock.Entry = GuildhallStock.Entry.new(GuildhallStock.CATEGORY_RUNE)
	entry.definition_id = RUNE_ID
	entry.instance_id = _session.ids.next_rune_id(RUNE_ID)
	stock.entries.append(entry)
	stock.store(_session.run)
	var panel: GuildhallPanel = GUILDHALL_SCENE.instantiate()
	_root.add_child(panel)
	panel.open_entry(_session.run, 0, 0, _catalog, _session.ids)
	if panel.get_step() != GuildhallPanel.Step.RUNE or panel.get_choice_buttons().is_empty():
		_ok("guildhall: the rune opens at its price", false, str(panel.get_step()))
		_free(panel)
		return null
	return panel


# Gives the first unit the Iron Shield, so the deal replaces it.
func _hold_shield(seat_run: SeatRun) -> bool:
	var held: ItemDefinition = _catalog.item(HELD_ID)
	var offered: ItemDefinition = _catalog.item(OFFERED_ID)
	var rune: RuneDefinition = _catalog.rune(RUNE_ID)
	_ok("setup: the shields and the rune are in the catalog", (
			held != null and offered != null and rune != null and not seat_run.army.is_empty()
	), "")
	if held == null or offered == null or rune == null or seat_run.army.is_empty():
		return false
	var unit: UnitInstance = seat_run.army[0]
	var item_id: String = _session.ids.next_item_id(HELD_ID)
	seat_run.items[item_id] = ItemInstance.new(item_id, HELD_ID)
	ItemPlacement.put_item(unit, ItemPlacement.slot_for(held), item_id)
	_unit_id = unit.instance_id
	return true


# The keyword ids of text's shown tooltips, top to bottom.
func _shown_ids(text: EffectText) -> PackedStringArray:
	var ids: PackedStringArray = []
	for tooltip: KeywordTooltip in text.get_shown_tooltips():
		ids.append(tooltip.keyword_id)
	return ids


# Sizes and sorts control and its children now, as a frame's layout would.
func _lay_out(control: Control) -> void:
	for _pass: int in 3:
		control.reset_size()
		control.size = Vector2(_root.size)
		for node: Node in control.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# Sorts text's tooltip column and places it again, as the frame after showing it does.
func _settle(text: EffectText) -> void:
	var column: Control = text.get_tooltip_column()
	for _pass: int in 2:
		for tooltip: KeywordTooltip in text.get_shown_tooltips():
			tooltip.notification(Container.NOTIFICATION_SORT_CHILDREN)
			tooltip.get_node("Lines").notification(Container.NOTIFICATION_SORT_CHILDREN)
			tooltip.reset_size()
		column.notification(Container.NOTIFICATION_SORT_CHILDREN)
		text.place_tooltips()


func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		_root.push_input(event, true)


func _push_click(point: Vector2, is_down: bool) -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = is_down
	_root.push_input(click, true)


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
