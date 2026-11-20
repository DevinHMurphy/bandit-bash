# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_offer_card_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The item offer card at 1280×720, over armies built in memory from the real catalog: a pouch
## item's effect lines and "Any unit"; a sword's icons for exactly its wielders (an upgraded Thief's
## sword included), with their sprites and names; four icons then "+2"; a bow no unit can wield; the
## names on focus and hover. Then the cards as their screens show them: the item pick's row of
## equal heights, its text wrapped inside each card, picked and skipped by keyboard, pad and mouse
## (a click on an icon picks); the chest's Legendary; the starting offer's Ancestral Weapon. The
## Treasure screen and the victory picker are item_card_screens_cases.gd's and
## item_reward_card_cases.gd's.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

const CARD_SCENE: PackedScene = preload("res://ui/campaign/item_offer_card.tscn")
const PANEL_SCENE: PackedScene = preload("res://ui/campaign/item_pick_panel.tscn")
const CHEST_SCENE: PackedScene = preload("res://ui/campaign/chest_view.tscn")
const OFFER_SCENE: PackedScene = preload("res://ui/campaign/starting_offer_view.tscn")
const SPRITES_PATH: String = "res://assets/sprites/units/unit_sprites.tres"
const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"

const MERCENARY: String = "mercenary"
const ANCESTRAL_WEAPON: String = "ancestral_weapon"
const LUCKY_COIN: String = "lucky_coin"

# Seeds searched for a starting offer holding Ancestral Weapon.
const SEEDS: int = 300

# The layout every case runs at: the project's base viewport.
const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# Layout passes before a size is read: each sorts every container, parents first, then fits each
# card, as frames would.
const LAYOUT_PASSES: int = 4

# Slack for sizes compared after layout, in base units.
const TOLERANCE: float = 0.5

var _check: Callable
var _root: Window = null
var _catalog: EffectCatalog.Index = null
var _sprites: UnitSpriteTable = null
var _ids: InstanceIdAllocator = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the cards are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	_catalog = EffectCatalog.index()
	_sprites = load(SPRITES_PATH) as UnitSpriteTable
	var sword: WeaponDefinition = _weapon_of("sword")
	var bow: WeaponDefinition = _weapon_of("bow")
	var coin: ItemDefinition = null if _catalog == null else _catalog.item(LUCKY_COIN)
	_ok("card: the catalog, sprites, a sword, a bow and the Lucky Coin load", (
			_catalog != null and _sprites != null and sword != null and bow != null
			and coin != null and not coin.describe().is_empty()
	))
	if _catalog == null or _sprites == null or sword == null or bow == null or coin == null:
		return
	_test_pouch(coin)
	_test_wielders(sword)
	_test_more(sword)
	_test_no_wielder(bow)
	_test_row_heights(sword, coin)
	_test_pick_by_keys(sword)
	_test_pick_by_pad(sword)
	_test_pick_by_mouse(sword)
	_test_chest(sword)
	_test_starting_offer()


func _test_pouch(coin: ItemDefinition) -> void:
	var seat_run: SeatRun = _army([["drengr", false], ["archer", false]])
	var card: ItemOfferCard = _card(coin, seat_run)
	var lines: PackedStringArray = card.get_lines()
	var expected: PackedStringArray = [coin.display_name, CombatResultsModel.item_details(coin)]
	expected.append_array(coin.describe())
	var row: ItemUsableBy = card.get_usable_by()
	_ok("pouch: name, rarity and kind, then one line per effect", lines == expected, (
			" | ".join(lines)
	))
	_ok("pouch: any unit can carry it, so the row says Any unit and shows no icons", (
			row.visible and row.get_note_text() == "Any unit" and row.get_icons().is_empty()
			and row.get_more_text().is_empty()
	), row.get_note_text())
	card.grab_focus()
	_ok("pouch: focus shows no names tooltip, the row says it in words", (
			not row.get_tip().visible
	))
	_free(card)


func _test_wielders(sword: WeaponDefinition) -> void:
	# Drengr (axe, sword), an unupgraded Thief (dagger), an upgraded Thief (+sword), an Archer
	# (bow), a Freewing (sword): the commander, the upgraded Thief and the Freewing wield it.
	var seat_run: SeatRun = _army([
		["drengr", false], ["thief", false], ["thief", true], ["archer", false],
		["freewing", false],
	])
	var expected_ids: PackedStringArray = [
		seat_run.army[0].instance_id, seat_run.army[2].instance_id, seat_run.army[4].instance_id,
	]
	var card: ItemOfferCard = _card(sword, seat_run)
	var row: ItemUsableBy = card.get_usable_by()
	var icons: Array[ItemUserIcon] = row.get_icons()
	var shown_ids: PackedStringArray = []
	var sprites_match: bool = icons.size() == expected_ids.size()
	for icon: ItemUserIcon in icons:
		shown_ids.append(icon.unit_id)
		var unit: UnitInstance = seat_run.unit(icon.unit_id)
		sprites_match = (
				sprites_match and unit != null and not icon.is_showing_initial()
				and icon.texture == _sprites.sprite_for(unit.unit_type_id)
		)
	_ok("weapon: icons for exactly the units that wield a sword, an upgraded Thief's included", (
			shown_ids == expected_ids and row.get_note_text().is_empty()
			and row.get_more_text().is_empty()
	), ", ".join(shown_ids))
	_ok("weapon: each icon is its unit's sprite, as the board draws it", sprites_match)
	_ok("weapon: its numbers stay on the card", (
			card.get_lines().size() >= 3 and card.get_lines()[2].begins_with("Dmg ")
	), " | ".join(card.get_lines()))
	_ok("weapon: the icons sit at the card's bottom right", _is_bottom_right(card))
	card.grab_focus()
	var tip: PackedStringArray = row.get_tip().get_texts()
	_ok("weapon: keyboard or pad focus lists every wielder's name in army order", (
			row.get_tip().visible and tip[0] == "Can wield it"
			and tip[1] == ", ".join(row.get_icon_names())
	), " | ".join(tip))
	card.release_focus()
	var left: bool = not row.get_tip().visible
	var hovered: bool = false
	if icons.size() > 1:
		icons[1].mouse_entered.emit()
		tip = row.get_tip().get_texts()
		hovered = row.get_tip().visible and tip[0] == "Ana 3" and tip[1].is_empty()
		icons[1].mouse_exited.emit()
	_ok("weapon: focus leaving hides the names; the mouse over an icon shows its unit's name", (
			left and hovered and not row.get_tip().visible
	), " | ".join(tip))
	_free(card)


func _test_more(sword: WeaponDefinition) -> void:
	var seat_run: SeatRun = _army([
		["drengr", false], ["freewing", false], ["hakkapel", false], ["sellsword", false],
		["archer", false], ["freewing", false], ["thief", true],
	])
	var card: ItemOfferCard = _card(sword, seat_run)
	var row: ItemUsableBy = card.get_usable_by()
	row.get_more_label().mouse_entered.emit()
	var tip: PackedStringArray = row.get_tip().get_texts()
	_ok("weapon: six wielders show four icons in army order, then +2", (
			row.get_icon_names() == PackedStringArray(["Ana 1", "Ana 2", "Ana 3", "Ana 4"])
			and row.get_more_text() == "+2"
	), "%s %s" % [", ".join(row.get_icon_names()), row.get_more_text()])
	_ok("weapon: the mouse over +2 names the two it hides", (
			row.get_tip().visible and tip[1] == "Ana 6, Ana 7"
	), " | ".join(tip))
	_free(card)


func _test_no_wielder(bow: WeaponDefinition) -> void:
	var seat_run: SeatRun = _army([["drengr", false], ["thief", false], ["mage", true]])
	var card: ItemOfferCard = _card(bow, seat_run)
	var row: ItemUsableBy = card.get_usable_by()
	card.grab_focus()
	_ok("weapon: a bow no unit can wield says so, with no icons and no names tooltip", (
			row.get_note_text() == "No unit can wield it" and row.get_icons().is_empty()
			and not row.get_tip().visible
	), row.get_note_text())
	_free(card)


func _test_row_heights(sword: WeaponDefinition, coin: ItemDefinition) -> void:
	var longest: ItemDefinition = _longest_pouch_item()
	var panel: ItemPickPanel = _panel([coin, sword, longest], _army([["drengr", false]]))
	var cards: Array[ItemOfferCard] = panel.get_offer_cards()
	var heights: PackedFloat32Array = []
	var tallest: float = 0.0
	var shortest: float = INF
	for card: ItemOfferCard in cards:
		tallest = maxf(tallest, card.custom_minimum_size.y)
		shortest = minf(shortest, card.custom_minimum_size.y)
	var same: bool = cards.size() == 3
	var fits: bool = cards.size() == 3
	for card: ItemOfferCard in cards:
		heights.append(card.size.y)
		same = same and absf(card.size.y - tallest) <= TOLERANCE
		fits = fits and _fits_inside(card)
	_ok("row: cards of unequal content all take the tallest card's height", (
			same and shortest < tallest and tallest < SCREEN_SIZE.y / 2.0
	), "%s; content %.0f-%.0f" % [heights, shortest, tallest])
	_ok("row: long text wraps inside each card, the who-can-use row last and inside", fits, (
			"" if cards.is_empty() else str(longest.describe())
	))
	_free(panel)


func _test_pick_by_keys(sword: WeaponDefinition) -> void:
	var panel: ItemPickPanel = _panel([sword, sword, sword], _army([["drengr", false]]))
	var chosen: Array[int] = []
	var skipped: Array[bool] = []
	panel.offer_chosen.connect(chosen.append)
	panel.skip_chosen.connect(func() -> void: skipped.append(true))
	panel.focus_first()
	_press_key(KEY_RIGHT)
	var moved: bool = panel.get_offer_cards()[1].has_focus()
	_press_key(KEY_ENTER)
	_press_key(KEY_RIGHT)
	_press_key(KEY_RIGHT)
	_press_key(KEY_ENTER)
	_ok("keys: Right along the cards, Enter picks one; Right to Skip, Enter skips", (
			moved and chosen == [1] and skipped.size() == 1
	), "%s, %d skips" % [chosen, skipped.size()])
	_free(panel)


func _test_pick_by_pad(sword: WeaponDefinition) -> void:
	var panel: ItemPickPanel = _panel([sword, sword, sword], _army([["drengr", false]]))
	var chosen: Array[int] = []
	var skipped: Array[bool] = []
	panel.offer_chosen.connect(chosen.append)
	panel.skip_chosen.connect(func() -> void: skipped.append(true))
	panel.focus_first()
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	_press_pad(JOY_BUTTON_A)
	_press_pad(JOY_BUTTON_DPAD_RIGHT)
	var on_skip: bool = panel.get_skip_button().has_focus()
	_press_pad(JOY_BUTTON_A)
	_ok("pad: the d-pad along the cards, A picks the third; on to Skip, A skips", (
			chosen == [2] and on_skip and skipped.size() == 1
	), "%s, %d skips" % [chosen, skipped.size()])
	_free(panel)


func _test_pick_by_mouse(sword: WeaponDefinition) -> void:
	var seat_run: SeatRun = _army([["drengr", false], ["freewing", false]])
	var panel: ItemPickPanel = _panel([sword, sword, sword], seat_run)
	var chosen: Array[int] = []
	var skipped: Array[bool] = []
	panel.offer_chosen.connect(chosen.append)
	panel.skip_chosen.connect(func() -> void: skipped.append(true))
	var cards: Array[ItemOfferCard] = panel.get_offer_cards()
	_click(cards[0].get_global_rect().get_center())
	var icons: Array[ItemUserIcon] = cards[2].get_usable_by().get_icons()
	var where: String = "no icon"
	if not icons.is_empty():
		var point: Vector2 = icons[0].get_global_rect().get_center()
		_click(point)
		var under: Control = _root.gui_get_hovered_control()
		where = "icon %s, card %s, under %s" % [
			icons[0].get_global_rect(), cards[2].get_global_rect(),
			"none" if under == null else str(under.get_path()),
		]
	_click(panel.get_skip_button().get_global_rect().get_center())
	_ok("mouse: a click on a card picks it, a click on its unit icon too; Skip skips", (
			chosen == [0, 2] and skipped.size() == 1
	), "%s, %d skips; %s" % [chosen, skipped.size(), where])
	_free(panel)


func _test_chest(sword: WeaponDefinition) -> void:
	var seat_run: SeatRun = _army([["drengr", false], ["thief", true], ["archer", false]])
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_RARE
	chest.item = ItemPick.Offer.new(sword.id, "item:chest")
	var view: ChestView = CHEST_SCENE.instantiate()
	_root.add_child(view)
	view.show_chest(chest, _catalog, seat_run, _ids)
	_settle(view)
	var card: ItemOfferCard = view.get_item_card()
	var row: ItemUsableBy = card.get_usable_by()
	_ok("chest: the Legendary's card shows its numbers and its two wielders", (
			card.visible and card.item_name == sword.display_name
			and row.get_icon_names() == PackedStringArray(["Ana 1", "Ana 2"])
			and _fits_inside(card)
	), ", ".join(row.get_icon_names()))
	_root.remove_child(view)
	view.free()


func _test_starting_offer() -> void:
	var rules: CampaignMapRules = load(RULES_PATH) as CampaignMapRules
	var session: CampaignSession = null
	var index: int = -1
	for run_seed: int in SEEDS:
		session = _session(rules, run_seed)
		index = _offer_index(session, ANCESTRAL_WEAPON)
		if index >= 0:
			break
	_ok("starting offer: some seed offers Ancestral Weapon", index >= 0)
	if index < 0:
		return
	var view: StartingOfferView = OFFER_SCENE.instantiate()
	_root.add_child(view)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = SCREEN_SIZE
	view.open(session, 0, _catalog)
	_settle(view, false)
	view.get_cards()[index].pressed.emit()
	_settle(view, false)
	var seat_run: SeatRun = session.run.seat_run(0)
	var weapons: Array[ItemPick.Offer] = StartingOffer.pending(seat_run).options[index].weapons
	var cards: Array[Button] = view.get_cards()
	var same_rows: bool = not cards.is_empty() and cards.size() == weapons.size()
	for card_index: int in mini(cards.size(), weapons.size()):
		var card: ItemOfferCard = cards[card_index] as ItemOfferCard
		var definition: ItemDefinition = _catalog.item(weapons[card_index].definition_id)
		var expected: PackedStringArray = []
		for unit: UnitInstance in ItemUsableBy.wielders(definition, seat_run, _catalog):
			expected.append(unit.instance_id)
		var shown: PackedStringArray = []
		if card != null:
			for icon: ItemUserIcon in card.get_usable_by().get_icons():
				shown.append(icon.unit_id)
		same_rows = (
				same_rows and card != null and definition != null
				and shown == expected.slice(0, 4) and _fits_inside(card)
		)
	_ok("starting offer: each Ancestral Weapon card shows its numbers and who can wield it", (
			view.get_step() == StartingOfferView.Step.WEAPON and same_rows
	), str(view.get_step()))
	_root.remove_child(view)
	view.free()


# --- Helpers -----------------------------------------------------------------------------------


# A seat run whose living army is one unit per [type id, is upgraded] entry, in order, named
# "Ana 1", "Ana 2" and on by a fresh _ids; the first is the commander.
func _army(units: Array[Array]) -> SeatRun:
	_ids = InstanceIdAllocator.new()
	var seat_run: SeatRun = SeatRun.new(0)
	for index: int in units.size():
		var entry: Array = units[index]
		var unit: UnitInstance = UnitInstance.new(
				_ids.next_unit_id("Ana %d" % [index + 1]), entry[0] as String
		)
		unit.is_upgraded = entry[1] as bool
		seat_run.army.append(unit)
	seat_run.commander_id = seat_run.army[0].instance_id
	return seat_run


# A card in the root showing definition for seat_run, laid out.
func _card(definition: ItemDefinition, seat_run: SeatRun) -> ItemOfferCard:
	var card: ItemOfferCard = CARD_SCENE.instantiate()
	_root.add_child(card)
	card.position = Vector2.ZERO
	card.show_item(definition, definition.id, seat_run, _catalog, _ids)
	_settle(card)
	return card


# An open pick panel in the root offering definitions for seat_run, laid out.
func _panel(definitions: Array[ItemDefinition], seat_run: SeatRun) -> ItemPickPanel:
	var model: CombatResultsModel = CombatResultsModel.new()
	model.pick = ItemPick.new()
	for index: int in definitions.size():
		model.pick.offers.append(
				ItemPick.Offer.new(definitions[index].id, "item:pick%d" % [index])
		)
		model.offers.append(definitions[index])
	var panel: ItemPickPanel = PANEL_SCENE.instantiate()
	_root.add_child(panel)
	panel.position = Vector2.ZERO
	panel.show_pick(model, "", seat_run, _catalog, _ids)
	_settle(panel)
	return panel


func _free(control: Control) -> void:
	_root.remove_child(control)
	control.free()


# Lays out control as frames would, LAYOUT_PASSES times: control sized to its content when
# fit_root (else it keeps its size), every container under it sorted, parents first, then every
# card fitted to its content; then one last sort for the last fit.
func _settle(control: Control, fit_root: bool = true) -> void:
	var nodes: Array[Node] = [control]
	nodes.append_array(control.find_children("*", "", true, false))
	for pass_index: int in LAYOUT_PASSES + 1:
		if fit_root:
			control.size = control.get_combined_minimum_size()
		for node: Node in nodes:
			if node is Container and is_instance_valid(node):
				node.notification(Container.NOTIFICATION_SORT_CHILDREN)
		if pass_index == LAYOUT_PASSES:
			return
		# A resized label rewraps when drawn, and nothing draws here: asking its size rewraps it.
		for node: Node in nodes:
			if node is Label and is_instance_valid(node):
				(node as Label).get_minimum_size()
		for node: Node in nodes:
			if node is ItemOfferCard and is_instance_valid(node):
				(node as ItemOfferCard).fit_content()


# Whether every line and the who-can-use row lie inside card, the row below the text.
func _fits_inside(card: ItemOfferCard) -> bool:
	var area: Rect2 = card.get_global_rect().grow(TOLERANCE)
	var row: ItemUsableBy = card.get_usable_by()
	var lowest_text: float = 0.0
	for label: Label in card.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree() or row.is_ancestor_of(label):
			continue
		if not area.encloses(label.get_global_rect()):
			return false
		lowest_text = maxf(lowest_text, label.get_global_rect().end.y)
	return area.encloses(row.get_global_rect()) and row.get_global_rect().position.y >= lowest_text


# Whether card's who-can-use row ends at its content's right and bottom edges.
func _is_bottom_right(card: ItemOfferCard) -> bool:
	var row: Rect2 = card.get_usable_by().get_global_rect()
	var content_node: Control = card.get_node(^"%Content") as Control
	if content_node == null:
		return false
	var margin: Rect2 = content_node.get_global_rect()
	var content: Rect2 = Rect2(margin.position, margin.size - Vector2(12.0, 8.0))
	return (
			absf(row.end.x - content.end.x) <= TOLERANCE
			and absf(row.end.y - content.end.y) <= TOLERANCE
	)


func _weapon_of(weapon_type: String) -> WeaponDefinition:
	if _catalog == null:
		return null
	for item: ItemDefinition in ItemPick.items_for(ItemPick.Slot.WEAPON, _catalog):
		var weapon: WeaponDefinition = item as WeaponDefinition
		if weapon != null and weapon.weapon_type == weapon_type:
			return weapon
	return null


# The Pouch item with the most effect lines, for the tallest card.
func _longest_pouch_item() -> ItemDefinition:
	var longest: ItemDefinition = null
	for item: ItemDefinition in ItemPick.items_for(ItemPick.Slot.POUCH, _catalog):
		var length: int = "\n".join(item.describe()).length()
		if longest == null or length > "\n".join(longest.describe()).length():
			longest = item
	return longest


func _session(rules: CampaignMapRules, run_seed: int) -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			rules, session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog, factions, session.ids, session.starting_offer_streams()
	)
	session.run = start.run
	return session


func _offer_index(session: CampaignSession, heirloom_id: String) -> int:
	var offer: StartingOffer = StartingOffer.pending(session.run.seat_run(0))
	if offer == null:
		return -1
	for index: int in offer.options.size():
		if offer.options[index].heirloom_id == heirloom_id:
			return index
	return -1


func _click(point: Vector2) -> void:
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


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
