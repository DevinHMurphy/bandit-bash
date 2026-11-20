# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_reward_card_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The victory item picker's cards on a real solo run through the real SaveService and
## CampaignService, at 1280×720, its Results staged with a weapon pick: each card shows the icons
## of exactly the seat's units that can wield it (or that none can), the first is focused with
## their names; Enter opens the placement and Esc backs out to the cards; the pad's A on Skip
## skips, which the run accepts. The card alone is tests/ui/campaign/item_offer_card_cases.gd's.[br]
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload or the picker: they are reached as nodes and by call().

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/victory"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const PICKER_SCENE: String = "res://ui/campaign/victory/item_reward_picker.tscn"

const SAVE_NUMBER: int = 3
const RUN_SEED: int = 0x1C1

# The offers staged: a weapon the army wields, one it can't, and another it wields.
const OFFERS: int = 3

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the picker is added and input is pushed.
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
	var session: CampaignSession = _service.get(&"session") as CampaignSession
	_check.call("item reward cards: a new solo run starts", (
			err == OK and session != null
	), error_string(err))
	if session != null:
		_test_picker(session)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_picker(session: CampaignSession) -> void:
	var seat_run: SeatRun = session.run.seat_run(0)
	var pick: ItemPick = _stage_weapon_pick(session)
	if pick == null:
		return
	var scene: PackedScene = load(PICKER_SCENE)
	var picker: Control = scene.instantiate()
	_root.add_child(picker)
	picker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	picker.size = SCREEN_SIZE
	picker.call(&"open", ItemPickReward.new(pick), 0)
	var panel: ItemPickPanel = picker.call(&"get_pick_panel")
	var cards: Array[ItemOfferCard] = panel.get_offer_cards()
	var rows_match: bool = cards.size() == OFFERS
	var details: PackedStringArray = []
	for index: int in mini(cards.size(), OFFERS):
		var definition: ItemDefinition = _catalog.item(pick.offers[index].definition_id)
		var row: ItemUsableBy = cards[index].get_usable_by()
		var expected: PackedStringArray = []
		for unit: UnitInstance in ItemUsableBy.wielders(definition, seat_run, _catalog):
			expected.append(unit.instance_id)
		var shown: PackedStringArray = []
		for icon: ItemUserIcon in row.get_icons():
			shown.append(icon.unit_id)
		var says_none: bool = expected.is_empty() and row.get_note_text() == "No unit can wield it"
		rows_match = rows_match and (says_none or shown == expected.slice(0, row.max_icons))
		details.append("%s: %s" % [definition.id, ", ".join(shown)])
	_check.call("picker: each weapon card shows exactly the seat's units that can wield it", (
			rows_match
	), "; ".join(details))
	var first_tip: GameTooltip = null if cards.is_empty() else cards[0].get_usable_by().get_tip()
	_check.call("picker: the first card opens focused, listing its wielders' names", (
			not cards.is_empty() and cards[0].has_focus()
			and first_tip.visible and first_tip.get_texts()[0] == "Can wield it"
	))
	var placement: PlacementPanel = picker.call(&"get_placement_panel")
	_press_key(KEY_ENTER)
	var opened: bool = placement.visible
	_press_key(KEY_ESCAPE)
	_check.call("picker (keys): Enter on the card opens its placement, Esc backs out to it", (
			opened and not placement.visible and not cards.is_empty() and cards[0].has_focus()
	))
	panel.get_skip_button().grab_focus()
	_press_pad(JOY_BUTTON_A)
	var after: ItemPick = ItemPick.pending(seat_run)
	_check.call("picker (pad): A on Skip skips the pick, which the run accepts", (
			after != null and after.is_resolved and after.taken == ItemPick.NOT_TAKEN
			and not picker.visible
	), picker.call(&"get_status_text") as String)
	_root.remove_child(picker)
	picker.free()


# Seat 0's run put at a won combat's Results holding a weapon pick: a weapon its army wields, one
# it can't, then another it wields. Null, with a failed check, when the catalog has none of either.
func _stage_weapon_pick(session: CampaignSession) -> ItemPick:
	var seat_run: SeatRun = session.run.seat_run(0)
	seat_run.pending_offers.erase(StartingOffer.OFFER_KEY)
	var usable: Array[ItemDefinition] = []
	var unusable: ItemDefinition = null
	for item: ItemDefinition in ItemPick.items_for(ItemPick.Slot.WEAPON, _catalog):
		if ItemUsableBy.wielders(item, seat_run, _catalog).is_empty():
			unusable = item if unusable == null else unusable
		elif usable.size() < OFFERS - 1:
			usable.append(item)
	_check.call("picker: the catalog has weapons the army wields and one it can't", (
			usable.size() == OFFERS - 1 and unusable != null
	))
	if usable.size() < OFFERS - 1 or unusable == null:
		return null
	session.run.flow.stage = RunFlow.Stage.RESULTS
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
		"grades": CombatGrades.new().capture(), "xp": [], "level_ups": [],
	}
	var pick: ItemPick = ItemPick.new()
	pick.slot = ItemPick.Slot.WEAPON
	for item: ItemDefinition in [usable[0], unusable, usable[1]]:
		pick.offers.append(ItemPick.Offer.new(item.id, session.ids.next_item_id(item.display_name)))
	pick.store(seat_run)
	return pick


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
