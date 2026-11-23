# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     screen_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The event screen over a real solo run, through the real [code]SaveService[/code],
## [code]CampaignService[/code] and router, in Unknown nodes made so, each event opened as RN10
## will open one. The screen opens on the game's empty pool showing the event closed, and plays
## the draw's fact (event_map_enter); each case re-opens its panel on the test event. Quit and
## Continue through Loading lands on the event screen at the option list, in the saved chooser
## and at the outcome, each as before. Leave returns to the map. The revive's fact sounds
## resurrect. A surprise combat's Fight goes to the battle screen, Continue at that stage goes
## straight there, and the battle begins.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"

# The screens drive the real SaveService, which writes save files (see tests/ui/ui_suite.gd).
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

const SCREEN_PATH: String = "res://ui/campaign/events/event_screen.tscn"
const LOADING_PATH: String = "res://ui/screens/loading_gate.tscn"
const GAMEPLAY_PATH: String = "res://ui/battle/gameplay.tscn"
const CUES_PATH: String = "res://data/audio/maps/campaign_facts.tres"

# SceneRouter.Screen values, read through the node as the suites do.
const SCREEN_GAMEPLAY: int = 3
const SCREEN_MAP: int = 9
const SCREEN_EVENT: int = 13

const SAVE_NUMBER: int = 1
const RUN_SEED: int = 0xE7E57

var _check: Callable
var _root: Window = null
var _fx: Fixture = null
var _saves: Node = null
var _service: Node = null
var _router: Node = null
var _catalog: EffectCatalog.Index = null
var _cues: FactCueListener = null

# The test event open now, its pool, and every fact the run's buses played.
var _pool: EventPool = null
var _played: Array[CampaignFact] = []
var _watched: Array[CampaignBus] = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_fx = Fixture.new(root)


func run() -> void:
	_saves = _root.get_node(^"SaveService")
	_service = _root.get_node(^"CampaignService")
	_router = _root.get_node(^"SceneRouter")
	_catalog = EffectCatalog.index()
	_cues = FactCueListener.new(load(CUES_PATH) as FactCueMap, Callable())
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	_ok("a new solo run starts", err == OK, error_string(err))
	if err != OK:
		return
	# These cases start past the starting heirloom offer, with nothing taken from it.
	_session().run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	_enter_unknown(_session().run.graph.nodes_on_floor(1)[0])
	_open_event(Fixture.trials())
	_test_option_list()
	_test_chooser()
	_test_outcome_and_leave()
	_test_revive()
	_test_fight()
	_saves.call(&"close_save_file")


func _test_option_list() -> void:
	var screen: Control = _open_screen()
	var panel: EventPanel = screen.call(&"get_panel")
	var header: RunHeader = screen.call(&"get_header")
	var drawn: Array[CampaignFact] = _facts(CampaignFact.Kind.EVENT_DRAWN)
	_ok("screen: on the game's empty pool the event shows closed, with Leave", (
			panel.get_step() == EventPanel.Step.CLOSED and panel.get_leave_button().visible
			and header.title == "Event"
	), str(EventPanel.Step.find_key(panel.get_step())))
	_ok("screen: the draw's fact plays once as it opens, sounding event_map_enter", (
			drawn.size() == 1 and _cues.cue_for_campaign(drawn[0]) == &"event_map_enter"
	), "%d drawn" % [drawn.size()])
	_reopen(panel)
	_ok("screen: re-opened on the test event, the header takes its name", (
			header.title == "Trial of the Three Doors"
	), header.title)
	var before: PackedStringArray = _card_texts(panel)
	var context: StringName = screen.call(&"get_hint_context")
	_close(screen)
	var after_screen: Control = _quit_and_continue()
	var after: EventPanel = null if after_screen == null else after_screen.call(&"get_panel")
	if after != null:
		_reopen(after)
	_ok("continue: at the option list, Loading lands on the event screen with the same cards", (
			before.size() == 3 and context == &"OPTIONS" and after != null
			and after.get_step() == EventPanel.Step.OPTIONS and _card_texts(after) == before
	), "" if after == null else str(EventPanel.Step.find_key(after.get_step())))
	_close(after_screen)


func _test_chooser() -> void:
	var screen: Control = _open_screen()
	var panel: EventPanel = _reopen(_panel_of(screen))
	panel.focus_first()
	var pressed: bool = _fx.press("key", panel.get_cards()[Fixture.TEMPER], "right")
	var question: String = panel.get_chooser().get_question()
	var before: PackedStringArray = _button_texts(panel.get_chooser().get_choice_buttons())
	var context: StringName = screen.call(&"get_hint_context")
	_close(screen)
	var after_screen: Control = _quit_and_continue()
	var after: EventPanel = null if after_screen == null else after_screen.call(&"get_panel")
	if after != null:
		_reopen(after)
	_ok("continue: in the saved weapon chooser, the screen reopens in it with the same choices", (
			pressed and context == &"CHOOSE" and after != null
			and after.get_step() == EventPanel.Step.CHOOSER
			and after.get_chooser().get_question() == question
			and _button_texts(after.get_chooser().get_choice_buttons()) == before
	), question)
	_close(after_screen)


func _test_outcome_and_leave() -> void:
	var screen: Control = _open_screen()
	var panel: EventPanel = _reopen(_panel_of(screen))
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	panel.get_chooser().focus_first()
	var pressed: bool = _fx.press("pad", buttons[1], "down")
	var summary: String = panel.get_summary().get_lines()
	var context: StringName = screen.call(&"get_hint_context")
	_close(screen)
	var after_screen: Control = _quit_and_continue()
	var after: EventPanel = null if after_screen == null else after_screen.call(&"get_panel")
	if after != null:
		_reopen(after)
	_ok("continue: at the outcome, the screen reopens on the same summary and Leave", (
			pressed and context == &"DONE" and after != null
			and after.get_step() == EventPanel.Step.OUTCOME
			and after.get_summary().get_lines() == summary
			and after.get_leave_button().text == "Leave"
	), summary)
	if after == null:
		return
	_fx.click(after.get_leave_button())
	_ok("leave: Leave returns the run to the map, saved", (
			_session().run.is_on_map() and _screen() == SCREEN_MAP
			and not _facts(CampaignFact.Kind.NODE_LEFT).is_empty()
	), str(_screen()))
	_close(after_screen)


func _test_revive() -> void:
	_enter_unknown(_session().run.graph.children_of(_session().run.node)[0])
	var seat_run: SeatRun = _session().run.seat_run(0)
	var soldier: UnitInstance = _fx.base.soldier(seat_run)
	_fx.base.fell(seat_run, soldier)
	_open_event(Fixture.shrine())
	var screen: Control = _open_screen()
	var panel: EventPanel = _reopen(_panel_of(screen))
	panel.get_cards()[Fixture.PRAYER].pressed.emit()
	panel.get_chooser().get_choice_buttons()[0].pressed.emit()
	var revived: Array[CampaignFact] = _facts(CampaignFact.Kind.UNIT_REVIVED)
	_ok("revive: the prayer brings the soldier back and its fact sounds resurrect", (
			panel.get_step() == EventPanel.Step.OUTCOME
			and seat_run.army.has(soldier) and seat_run.fallen.is_empty()
			and revived.size() == 1 and _cues.cue_for_campaign(revived[0]) == &"resurrect"
	), "%d revived" % [revived.size()])
	panel.focus_first()
	_fx.press_key(KEY_ENTER)
	_ok("revive: Enter on the focused Leave returns to the map", (
			_session().run.is_on_map()
	))
	_close(screen)


func _test_fight() -> void:
	_enter_unknown(_session().run.graph.children_of(_session().run.node)[0])
	_open_event(Fixture.toll())
	var screen: Control = _open_screen()
	var panel: EventPanel = _reopen(_panel_of(screen))
	panel.get_cards()[Fixture.FIGHT].pressed.emit()
	var context: StringName = screen.call(&"get_hint_context")
	var fight: Button = panel.get_leave_button()
	_ok("fight: the outcome's button is Fight, hinted as Fight", (
			panel.get_step() == EventPanel.Step.OUTCOME and fight.text == "Fight"
			and context == &"FIGHT"
	), str(context))
	fight.pressed.emit()
	_ok("fight: Fight goes to the battle screen", (
			_screen() == SCREEN_GAMEPLAY
	), str(_screen()))
	_close(screen)
	var resumed: Control = _quit_and_continue(false)
	_ok("continue: with the surprise combat pending, Loading goes straight to the battle", (
			resumed == null and _screen() == SCREEN_GAMEPLAY
	), str(_screen()))
	var battle: Node = (load(GAMEPLAY_PATH) as PackedScene).instantiate()
	_root.add_child(battle)
	var session: CampaignSession = _session()
	_ok("fight: the battle screen begins the surprise combat in the Unknown node", (
			session.encounter != null and not session.run.is_on_map()
			and session.run.events.is_combat_pending_at(
					session.run.floor_number, session.run.node
			)
	))
	_root.remove_child(battle)
	battle.free()


# --- Helpers -----------------------------------------------------------------------------------


func _session() -> CampaignSession:
	return _service.get(&"session")


# The screen the router last went to, a SceneRouter.Screen value.
func _screen() -> int:
	return _router.get(&"current_screen")


func _panel_of(screen: Control) -> EventPanel:
	return screen.call(&"get_panel")


# Makes node_id an Unknown node and enters it, as choosing it on the map does.
func _enter_unknown(node_id: int) -> void:
	var session: CampaignSession = _session()
	_watch(session)
	session.run.graph.set_node_type(node_id, CampaignGraph.NodeType.UNKNOWN)
	var batch: CampaignBatch = _service.call(
			&"submit_command", ChooseNodeCommand.new(0, node_id)
	)
	_ok("setup: the run enters Unknown node %d" % [node_id], (
			batch != null and not batch.is_rejected()
	), "" if batch == null else batch.rejected_reason)


# Opens event at the run's node from a pool of it alone, as the Unknown node will.
func _open_event(event: EventDefinition) -> void:
	_pool = EventPool.new([event])
	var command: OpenEventCommand = EventNode.open(
			_session(), _pool, _catalog, CombatRewardRules.load_default()
	)
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	_ok("setup: %s opens at the node" % [event.id], (
			batch != null and not batch.is_rejected()
	), "" if batch == null else batch.rejected_reason)


# The event screen as the router opens it, laid out at the base viewport.
func _open_screen() -> Control:
	var screen: Control = (load(SCREEN_PATH) as PackedScene).instantiate()
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Fixture.SCREEN_SIZE
	return screen


# Re-opens panel's screen (its owner) on the test event's pool, as tests and captures do over the
# empty game pool.
func _reopen(panel: EventPanel) -> EventPanel:
	panel.owner.call(&"reopen", _pool, _catalog)
	_fx.lay_out(panel)
	panel.focus_first()
	return panel


func _close(screen: Control) -> void:
	if screen == null:
		return
	_root.remove_child(screen)
	screen.free()


# Saves and quits, then Continues from the save through Loading, as Save & Quit then Continue
# Run do. Returns the event screen when Loading routed to it (opened, as the router would), else
# null; with expect_event false, opens nothing.
func _quit_and_continue(expect_event: bool = true) -> Control:
	_saves.call(&"close_save_file")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = _saves.call(&"continue_solo_run")
	_watch(_session())
	var gate: Control = (load(LOADING_PATH) as PackedScene).instantiate()
	_root.add_child(gate)
	(gate.get_node(^"%ContinueButton") as Button).pressed.emit()
	_root.remove_child(gate)
	gate.free()
	var screen: int = _router.get(&"current_screen")
	if err != OK or not expect_event or screen != SCREEN_EVENT:
		if expect_event:
			_ok("continue: the run continues to the event screen", false, "%s, screen %d" % [
				error_string(err), screen,
			])
		return null
	return _open_screen()


# Records every fact session's bus plays from now on.
func _watch(session: CampaignSession) -> void:
	if session == null or _watched.has(session.bus):
		return
	_watched.append(session.bus)
	session.bus.fact_played.connect(_played.append)


func _facts(kind: CampaignFact.Kind) -> Array[CampaignFact]:
	var found: Array[CampaignFact] = []
	for fact: CampaignFact in _played:
		if fact.kind == kind:
			found.append(fact)
	return found


func _card_texts(panel: EventPanel) -> PackedStringArray:
	var texts: PackedStringArray = []
	for card: EventOptionCard in panel.get_cards():
		texts.append(card.get_card_text())
	return texts


func _button_texts(buttons: Array[Button]) -> PackedStringArray:
	var texts: PackedStringArray = []
	for button: Button in buttons:
		texts.append(button.text)
	return texts


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events %s" % [case_name], passed, detail)
