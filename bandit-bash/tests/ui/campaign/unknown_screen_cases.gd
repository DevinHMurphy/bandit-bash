# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unknown_screen_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The Unknown node's routing for tests/ui/campaign/run_all.gd, on a real solo run through the real
## SaveService and CampaignService, at 1280×720: each outcome routed to its screen (a combat to the
## battle, the Armory, the Guildhall, the Treasure, an event to the event screen, an event with
## none drawn to the placeholder); the entry rolled and saved by RunScreen.enter_unknown, the same
## after a Save & Quit and Continue and never rolled twice; a quit before the roll rolling on
## Continue what the node's own stream gives; an Unknown that became an Armory, Guildhall or
## Treasure rolling that node's offer as its screen opens; and the placeholder naming the node.
## Leaving is by command, as the walk (run_all.gd) does the routing; nothing here changes scene.
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const PLACEHOLDER_SCENE: String = "res://ui/campaign/node_placeholder_screen.tscn"
const ARMORY_SCENE: String = "res://ui/campaign/armory_screen.tscn"
const GUILDHALL_SCENE: String = "res://ui/campaign/guildhall_screen.tscn"
const TREASURE_SCENE: String = "res://ui/campaign/treasure_screen.tscn"

# SceneRouter.Screen values: a case file can't name the autoload.
const SCREEN_GAMEPLAY: int = 3
const SCREEN_PLACEHOLDER: int = 11
const SCREEN_EVENT: int = 13
const SCREEN_TREASURE: int = 14
const SCREEN_ARMORY: int = 16
const SCREEN_GUILDHALL: int = 17

# The save file the cases write, in the test user folder only; the walk uses 1.
const SAVE_NUMBER: int = 3
const RUN_SEED: int = 0xA510

const SCREEN_SIZE: Vector2 = Vector2(1280.0, 720.0)

# The screen each outcome routes to, with no event open.
const ROUTES: Dictionary[String, int] = {
	"combat": SCREEN_GAMEPLAY,
	"armory": SCREEN_ARMORY,
	"guildhall": SCREEN_GUILDHALL,
	"treasure": SCREEN_TREASURE,
	"event": SCREEN_PLACEHOLDER,
}

var _check: Callable
var _root: Window = null
var _saves: Node = null
var _service: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")
	_service = root.get_node(^"CampaignService")


## Runs every case. Call only with a test user folder.
func run() -> void:
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	if _new_run() != null:
		_test_routes()
		_test_entry_saved()
		_test_quit_before_the_roll()
		_test_node_screens()
		_test_placeholder()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


func _test_routes() -> void:
	var session: CampaignSession = _session()
	if not Fixture.enter(session.run, CampaignGraph.NodeType.UNKNOWN):
		_check.call("unknown: the map has an Unknown node", false)
		return
	var wrong: PackedStringArray = []
	for outcome: String in ROUTES:
		session.run.flow.unknown = outcome
		var screen: int = RunScreen.of(session)
		if screen != ROUTES[outcome]:
			wrong.append("%s -> %d" % [outcome, screen])
	session.run.flow.unknown = UnknownResolution.EVENT
	var opened: CampaignBatch = _service.call(&"submit_command", EventNode.open(session))
	var event_screen: int = RunScreen.of(session)
	_check.call("routes: each outcome to its screen; an event to the event screen once drawn", (
			wrong.is_empty() and opened != null and not opened.is_rejected()
			and event_screen == SCREEN_EVENT
	), "%s; event %d" % [", ".join(wrong), event_screen])
	_leave_node()


func _test_entry_saved() -> void:
	var session: CampaignSession = _at_new_unknown()
	if session == null:
		return
	var due: bool = ResolveUnknownCommand.is_due(session.run)
	RunScreen.enter_unknown(session)
	var outcome: String = session.run.flow.unknown
	var odds: Dictionary[String, int] = session.run.flow.unknown_odds.duplicate()
	var is_event: bool = outcome == UnknownResolution.EVENT
	var event_id: String = session.run.events.event_id if is_event else ""
	var screen: int = RunScreen.of(session)
	_check.call("entry: enter_unknown rolls the node, opens an event's event, routes by it", (
			due and UnknownResolution.OUTCOMES.has(outcome) and not odds.is_empty()
			and (not is_event or session.run.events.is_open_at(
					session.run.floor_number, session.run.node
			))
			and screen == (SCREEN_EVENT if is_event else ROUTES[outcome])
	), "%s -> %d" % [outcome, screen])
	var reopened: CampaignSession = _reopen()
	if reopened == null:
		return
	RunScreen.enter_unknown(reopened)
	_check.call("entry: Save & Quit, Continue keeps the outcome, odds and event; no new roll", (
			reopened.run.flow.unknown == outcome
			and reopened.run.flow.unknown_odds == odds
			and reopened.run.events.event_id == event_id
			and RunScreen.of(reopened) == screen
	), "%s %s" % [reopened.run.flow.unknown, reopened.run.flow.unknown_odds])
	_leave_node()


func _test_quit_before_the_roll() -> void:
	var session: CampaignSession = _at_new_unknown()
	if session == null:
		return
	var run_state: CampaignRunState = session.run
	var expected: RunFlow = RunFlow.new()
	expected.unknown_odds = run_state.flow.unknown_odds.duplicate()
	UnknownResolution.roll(expected, CampaignMapRules.load_default(), RngStream.new(
			RngKey.derive_seed(
					session.rng.run_seed, RngKey.RngPurpose.UNKNOWN_RESOLUTION,
					run_state.floor_number, run_state.node, -1, -1
			)
	))
	var reopened: CampaignSession = _reopen()
	if reopened == null:
		return
	var still_due: bool = ResolveUnknownCommand.is_due(reopened.run)
	RunScreen.enter_unknown(reopened)
	_check.call("resume: a quit before the roll rolls on Continue what the node's stream gives", (
			still_due and reopened.run.flow.unknown == expected.unknown
			and reopened.run.flow.unknown_odds == expected.unknown_odds
	), "%s, wanted %s" % [reopened.run.flow.unknown, expected.unknown])
	_leave_node()


func _test_node_screens() -> void:
	var cases: Dictionary[String, String] = {
		UnknownResolution.ARMORY: ARMORY_SCENE,
		UnknownResolution.GUILDHALL: GUILDHALL_SCENE,
		UnknownResolution.TREASURE: TREASURE_SCENE,
	}
	var wrong: PackedStringArray = []
	for outcome: String in cases:
		var session: CampaignSession = _at_new_unknown()
		if session == null:
			return
		session.run.flow.unknown = outcome
		var screen: Control = _add(cases[outcome])
		var rolled: bool = false
		match outcome:
			UnknownResolution.ARMORY:
				rolled = ArmoryStock.pending(session.run) != null
			UnknownResolution.GUILDHALL:
				rolled = GuildhallStock.pending(session.run) != null
			UnknownResolution.TREASURE:
				rolled = TreasureChest.is_open(session.run.seat_run(0))
		if not rolled:
			wrong.append(outcome)
		_remove(screen)
		if outcome == UnknownResolution.TREASURE:
			session.run.seat_run(0).pending_offers.erase(TreasureChest.OFFER_KEY)
		_leave_node()
	_check.call("screens: an Unknown become an Armory, Guildhall or Treasure rolls its offer", (
			wrong.is_empty()
	), ", ".join(wrong))


func _test_placeholder() -> void:
	var session: CampaignSession = _at_new_unknown()
	if session == null:
		return
	session.run.flow.unknown = UnknownResolution.EVENT
	var routed: int = RunScreen.of(session)
	var screen: Control = _add(PLACEHOLDER_SCENE)
	var title: Label = screen.get_node(^"%Title")
	var button: Button = screen.call(&"get_continue_button")
	_check.call("placeholder: an event with none drawn shows it, naming the node, Continue ready", (
			routed == SCREEN_PLACEHOLDER
			and title.text == CampaignMapView.TYPE_NAMES[CampaignGraph.NodeType.UNKNOWN]
			and button != null and not button.disabled
	), "%d; %s" % [routed, title.text])
	_remove(screen)
	_leave_node()


# A new solo run through SaveService, past its starting offer; null, checked, if none starts.
func _new_run() -> CampaignSession:
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var session: CampaignSession = _session()
	_check.call("unknown: a new solo run starts", err == OK and session != null, error_string(err))
	if session == null:
		return null
	session.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	return session


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


# The run inside its first Unknown node, not rolled and with no event, saved there; null,
# checked, for a map with none.
func _at_new_unknown() -> CampaignSession:
	var session: CampaignSession = _session()
	var entered: bool = session != null and Fixture.enter(
			session.run, CampaignGraph.NodeType.UNKNOWN
	)
	if not entered:
		_check.call("unknown: the run enters an Unknown node", false)
		return null
	session.run.flow.unknown = ""
	# Every case enters the same node: an event an earlier case opened there is forgotten.
	session.run.events = EventRunState.new()
	_saves.call(&"save_checkpoint")
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


# Leaves the node the run is in by command, as its screen's Leave would.
func _leave_node() -> void:
	var left: CampaignBatch = _service.call(&"submit_command", LeaveNodeCommand.new(0))
	if left == null or left.is_rejected():
		_check.call("unknown: the node is left", false, (
				left.rejected_reason if left != null else ""
		))


func _add(path: String) -> Control:
	var scene: PackedScene = load(path)
	var screen: Control = scene.instantiate()
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = SCREEN_SIZE
	return screen


func _remove(screen: Control) -> void:
	_root.remove_child(screen)
	screen.free()
