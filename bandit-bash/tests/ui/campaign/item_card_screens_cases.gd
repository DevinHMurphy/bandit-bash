# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_card_screens_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Treasure screen's chest on a real solo run through the real SaveService and
## CampaignService, at 1280×720: a Legendary weapon's card shows the icons of exactly the seat's
## units that can wield it, and a Legendary every unit can use says "Any unit". The card alone is
## item_offer_card_cases.gd's.[br]
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload or the screen: they are reached as nodes and by call().

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const TREASURE_SCENE: String = "res://ui/campaign/treasure_screen.tscn"

# The save file the cases write, in the test user folder only; the walk uses 1, the node screens 2.
const SAVE_NUMBER: int = 3
const RUN_SEED: int = 0x1C0

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screen is added.
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
	_check.call("item card screens: a new solo run starts", (
			err == OK and session != null
	), error_string(err))
	if session != null:
		session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
		_test_treasure(session)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_treasure(session: CampaignSession) -> void:
	var seat_run: SeatRun = session.run.seat_run(0)
	Fixture.enter(session.run, CampaignGraph.NodeType.TREASURE)
	var weapon: ItemDefinition = null
	var other: ItemDefinition = null
	for legendary: ItemDefinition in TreasureChest.usable_legendaries(seat_run, _catalog):
		if legendary is WeaponDefinition and weapon == null:
			weapon = legendary
		elif not legendary is WeaponDefinition and other == null:
			other = legendary
	_check.call("treasure: the run has a usable Legendary weapon and another Legendary", (
			weapon != null and other != null
	))
	if weapon == null or other == null:
		return
	var row: ItemUsableBy = _chest_row(session, weapon)
	var expected: PackedStringArray = []
	for unit: UnitInstance in ItemUsableBy.wielders(weapon, seat_run, _catalog):
		expected.append(CombatResultsModel.unit_name(
				session.ids, seat_run, unit.instance_id, _catalog
		))
	var shown: PackedStringArray = [] if row == null else row.get_icon_names()
	_check.call("treasure: the chest's Legendary weapon shows exactly the units that wield it", (
			row != null and row.visible and not expected.is_empty()
			and shown == expected.slice(0, row.max_icons)
	), "%s; expected %s" % [", ".join(shown), ", ".join(expected)])
	_remove_screen()
	row = _chest_row(session, other)
	_check.call("treasure: a Legendary every unit can use says Any unit", (
			row != null and row.get_note_text() == "Any unit" and row.get_icons().is_empty()
	), "" if row == null else row.get_note_text())
	_remove_screen()


# The Treasure screen opened on a Rare chest holding definition; the chest card's who-can-use row.
func _chest_row(session: CampaignSession, definition: ItemDefinition) -> ItemUsableBy:
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_RARE
	chest.item = ItemPick.Offer.new(definition.id, session.ids.next_item_id(definition.display_name))
	chest.store(session.run.seat_run(0))
	var scene: PackedScene = load(TREASURE_SCENE)
	var screen: Control = scene.instantiate()
	screen.name = "ItemCardTreasure"
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = SCREEN_SIZE
	var view: ChestView = screen.call(&"get_chest_view")
	if view == null or not view.get_item_card().visible:
		return null
	return view.get_item_card().get_usable_by()


func _remove_screen() -> void:
	var screen: Node = _root.get_node_or_null(^"ItemCardTreasure")
	if screen == null:
		return
	_root.remove_child(screen)
	screen.free()
