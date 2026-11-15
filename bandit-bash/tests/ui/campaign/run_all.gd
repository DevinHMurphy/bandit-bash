# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  November 15, 2026
# Modified: November 15, 2026
# ==============================================================================

extends "res://tests/ui/ui_suite.gd"
## Campaign screens suite: a solo run played through the real screens and the real router, from
## Loading to the map, into four nodes and back, by keyboard, mouse and pad in turn. The map
## (only the reachable nodes enabled and focusable, the route marked, left and right between the
## choices, the header, legend and hints), the battle won and routed to Results, Results (grades,
## XP rows, Standout, level-ups, the pick's cards, Continue locked until the pick is resolved),
## the placement panel (to the convoy, scrapped, equipped; Back by pad without opening the pause
## menu), a quit and Continue on Results before and after the take showing the same, the node
## placeholder, and the Boss's End run reaching the run's end. Pad glyphs show on the hint bar.
##
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tests/ui/campaign/run_all.gd[/code].
## Prints one PASS, FAIL or SKIP line per check and
## [code]--- N passed, M failed, K skipped ---[/code]; exits with code 1 on any failure. It needs
## a test user folder (see the base). Battles are won by recording their end, not played.

# SceneRouter.Screen values: a suite can't name the autoload (see the base).
const SCREEN_LOADING: int = 2
const SCREEN_GAMEPLAY: int = 3
const SCREEN_RESULTS: int = 4
const SCREEN_MAP: int = 9
const SCREEN_COMBAT_RESULTS: int = 10
const SCREEN_PLACEHOLDER: int = 11

# The devices in turn: each node is chosen with the next, each Results and placeholder answered
# with the next of its own turn.
const DEVICES: PackedStringArray = ["keyboard", "mouse", "pad"]

# Nodes the walk enters, and how many of them must be combats; at least one other is wanted too.
const NODES_TO_PLAY: int = 5
const COMBATS_WANTED: int = 3

# Frames left after an action for the router's scene change and the screen's deferred focus.
const SETTLE_FRAMES: int = 3

# Frames the whole walk may take before it counts as stuck.
const FRAME_LIMIT: int = 4000

# Frames to wait for a new scene after an action before it counts as not routed.
const ROUTE_LIMIT: int = 60

# The Input Helper autoload, which tells the device adapters the pad family in use.
const HELPER_PATH: NodePath = ^"/root/InputHelper"

const JOY_A: JoyButton = JOY_BUTTON_A
const JOY_B: JoyButton = JOY_BUTTON_B

var _frame: int = 0
var _wait: int = 0
var _waited_for_route: int = 0
var _is_done: bool = false
var _old_root_size: Vector2i = Vector2i.ZERO

# The scene last acted on: the walk acts once per scene, on the next one the router shows.
var _acted_scene: Node = null

# Nodes entered so far, the node the last choice should have entered, and the route planned on
# the first map (_plan_route).
var _entered: int = 0
var _expected_node: int = -1
var _route: PackedInt32Array = []

# Results left so far, whose count picks the next Results' device.
var _results_done: int = 0

# Results' quit and Continue: 0 not yet, 1 quit before the take, 2 taken, 3 quit after it, 4 done.
var _resume_step: int = 0
var _snapshot: PackedStringArray = []

# The devices that chose a node, answered Results and answered a placeholder.
var _chose_with: Dictionary[String, bool] = {}
var _results_with: Dictionary[String, bool] = {}
var _placeholder_with: Dictionary[String, bool] = {}

# The Boss case: 0 not begun, 1 its Results shown, 2 the run's end reached.
var _boss_step: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_start("Campaign screens tests")
		if not _has_test_user_dir():
			_skip("campaign screens", "the screens need a test user folder (see the class doc)")
			_finish()
			return false
		_begin_run()
		return false
	if _is_done:
		return false
	if _frame > FRAME_LIMIT:
		_check("walk: the run finished within %d frames" % [FRAME_LIMIT], false, (
				"stuck on screen %d" % [_router().get(&"current_screen")]
		))
		_end()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	var scene: Node = current_scene
	if scene == null or scene == _acted_scene:
		_waited_for_route += 1
		if _waited_for_route > ROUTE_LIMIT:
			_check("walk: every action routed on to a new screen", false, (
					"screen %d after %d frames" % [
						_router().get(&"current_screen"), _waited_for_route,
					]
			))
			_end()
		return false
	_waited_for_route = 0
	_acted_scene = scene
	_wait = SETTLE_FRAMES
	var screen: int = _router().get(&"current_screen")
	match screen:
		SCREEN_LOADING:
			_on_loading(scene)
		SCREEN_MAP:
			_on_map(scene)
		SCREEN_GAMEPLAY:
			_on_battle(scene)
		SCREEN_COMBAT_RESULTS:
			_on_results(scene)
		SCREEN_PLACEHOLDER:
			_on_placeholder(scene)
		SCREEN_RESULTS:
			_on_run_end(scene)
		_:
			_check("walk: only run screens show", false, "screen %d" % [screen])
			_end()
	return false


# A new solo run, opened through Loading as the New Run screen does.
func _begin_run() -> void:
	_old_root_size = root.size
	root.size = BASE_SCREEN_SIZE
	var saves: Node = root.get_node(^"SaveService")
	SaveFile.delete_folder("user://saves/")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"start_new_solo_run", RUN_SEED)
	_check("walk: a new solo run starts", err == OK, error_string(err))
	if err != OK:
		_end()
		return
	_router().call(&"goto_screen", SCREEN_LOADING)


func _on_loading(scene: Node) -> void:
	var button: Button = scene.get_node(^"%ContinueButton")
	_check("loading: Continue has focus, for a pad", button.has_focus())
	_press_key(KEY_ENTER)


func _on_map(scene: Node) -> void:
	var run: CampaignRunState = _run()
	if _expected_node >= 0:
		_check("map %d: back on the map after node %d, its floor reached" % [
			_entered, _expected_node,
		], run.is_on_map() and run.node == _expected_node and run.floor_number == _entered)
	if _entered == NODES_TO_PLAY:
		_finish_walk()
		_begin_boss_case()
		return
	var view: CampaignMapView = scene.call(&"get_map_view")
	var reachable: PackedInt32Array = view.get_reachable()
	_check_map(scene, view, run)
	var device: String = DEVICES[_entered % DEVICES.size()]
	if _route.is_empty():
		_route = _plan_route(run.graph)
	var target: int = 0
	if _entered < _route.size():
		target = maxi(reachable.find(_route[_entered]), 0)
	_expected_node = reachable[target]
	_entered += 1
	_chose_with[device] = true
	match device:
		"keyboard":
			if _entered == 1:
				_press_key(KEY_ESCAPE)
				var opened: bool = paused
				_press_key(KEY_ESCAPE)
				_check("map (keys): Esc opens the pause menu; closing it gives focus back", (
						opened and not paused and view.get_node_button(reachable[0]).has_focus()
				), "paused %s then %s" % [opened, paused])
			if reachable.size() > 1:
				_press_key(KEY_RIGHT)
				var moved: bool = view.get_node_button(reachable[1]).has_focus()
				_press_key(KEY_LEFT)
				_check("map (keys): Right and Left move between the reachable nodes", (
						moved and view.get_node_button(reachable[0]).has_focus()
				))
			for _step: int in target:
				_press_key(KEY_RIGHT)
			_press_key(KEY_ENTER)
		"mouse":
			var button: MapNodeButton = view.get_node_button(_expected_node)
			_click(button.get_global_rect().get_center())
		"pad":
			_use_pad()
			var bar: ControlHintBar = scene.get_node(^"%ControlHintBar")
			bar.refresh()
			_check("map (pad): the hint bar draws pad glyphs", (
					bar.get_markup().contains("[img")
			), bar.get_markup())
			for _step: int in target:
				_press_pad(JOY_BUTTON_DPAD_RIGHT)
			_check("map (pad): the d-pad moves focus to the node to choose", (
					view.get_node_button(_expected_node).has_focus()
			))
			_press_pad(JOY_A)


# The map shows the run: reachable nodes enabled and focusable, the others not, the route marked,
# the first choice focused, the header and the hints.
func _check_map(scene: Node, view: CampaignMapView, run: CampaignRunState) -> void:
	var reachable: PackedInt32Array = view.get_reachable()
	var expected: PackedInt32Array = run.next_nodes()
	var shown: PackedInt32Array = reachable.duplicate()
	shown.sort()
	var wrong: PackedStringArray = []
	for node_id: int in run.graph.node_count():
		var button: MapNodeButton = view.get_node_button(node_id)
		var is_choice: bool = reachable.has(node_id)
		if button.disabled == is_choice or (button.focus_mode == Control.FOCUS_ALL) != is_choice:
			wrong.append("node %d" % [node_id])
		if run.visited.has(node_id) and button.get_mark() < MapNodeButton.Mark.VISITED:
			wrong.append("route node %d unmarked" % [node_id])
	var header: RunHeader = scene.get_node(^"%RunHeader")
	var bar: ControlHintBar = scene.get_node(^"%ControlHintBar")
	bar.refresh()
	_check("map %d: only the %d reachable nodes take focus, the route is marked" % [
		_entered, expected.size(),
	], (
			shown == expected
			and not expected.is_empty()
			and wrong.is_empty()
			and view.get_node_button(reachable[0]).has_focus()
	), "%s vs %s; %s" % [shown, expected, ", ".join(wrong)])
	_check("map %d: the header shows the floor and gold; the hints show Choose" % [_entered], (
			header.get_floor_text() == "Floor %d / %d" % [
				run.floor_number, run.graph.get_floor_count(),
			]
			and header.get_gold_text() == "Gold %d" % [run.seat_run(0).gold]
			and bar.get_context() == &"MAP"
			and bar.get_text().contains("Choose")
	), "%s; %s; %s" % [header.get_floor_text(), bar.get_context(), bar.get_text()])
	if _entered == 0:
		var legend: MapLegend = scene.get_node(^"%MapLegend")
		_check("map: the legend lists every node type", (
				legend.get_lines().size() == CampaignMapView.TYPE_NAMES.size()
		), ", ".join(legend.get_lines()))


# The battle shown is the chosen node's; it is won by recording its end, and the screen routes on.
func _on_battle(scene: Node) -> void:
	var run: CampaignRunState = _run()
	var view: BattleView = scene.call(&"get_view")
	var session: CombatSession = view.get_session()
	_check("battle %d: the chosen combat node's battle begins" % [_entered], (
			session != null and run.node == _expected_node and not run.is_on_map()
	))
	if session == null:
		_end()
		return
	scene.set(&"end_banner_time", 0.0)
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = CombatFact.CombatSide.PLAYER
	session.engine.record(ended)
	for _step: int in 600:
		if view.is_settled():
			break
		view.advance(1.0 / 60.0)
	view.settled.emit()


func _on_results(scene: Node) -> void:
	if _boss_step == 1:
		_on_boss_results(scene)
		return
	var device: String = DEVICES[_results_done % DEVICES.size()]
	var model: CombatResultsModel = scene.call(&"get_model")
	var pick_panel: ItemPickPanel = scene.call(&"get_pick_panel")
	var continue_button: Button = scene.call(&"get_continue_button")
	var bar: ControlHintBar = scene.get_node(^"%ControlHintBar")
	bar.refresh()
	# Steps 1 and 3 are the same Results again after a quit, checked against the snapshot instead.
	if _resume_step != 1 and _resume_step != 3:
		_check_results(scene, model)
	if device == "keyboard" and _resume_step == 0:
		_snapshot = _results_text(scene)
		_resume_step = 1
		_quit_and_continue()
		return
	if _resume_step == 1:
		_check("results: after a quit and Continue it shows the same report and offers", (
				_results_text(scene) == _snapshot and not model.pick.is_resolved
		), " | ".join(_results_text(scene)))
		_resume_step = 2
	if _resume_step == 3:
		_check("results: after a quit and Continue once taken, the pick shows taken", (
				_results_text(scene) == _snapshot
				and model.pick.is_resolved
				and not continue_button.disabled
				and continue_button.has_focus()
		), " | ".join(_results_text(scene)))
		_resume_step = 4
		_results_done += 1
		_press_key(KEY_ENTER)
		return
	if model.pick == null or model.pick.is_resolved:
		_check("results %d: an open pick is offered" % [_entered], false)
		_end()
		return
	_results_with[device] = true
	match device:
		"keyboard":
			_take_by_keys(scene)
		"mouse":
			_take_by_mouse(scene)
		"pad":
			_take_by_pad(scene, bar)
	_check("results %d (%s): once placed, the pick shows its outcome and Continue opens" % [
		_entered, device,
	], (
			_model_of(scene).pick.is_resolved
			and not pick_panel.get_outcome_text().is_empty()
			and not continue_button.disabled
			and continue_button.has_focus()
			and _hint_context(scene) == &"DONE"
	), "%s; %s" % [pick_panel.get_outcome_text(), _hint_context(scene)])
	if device == "keyboard" and _resume_step == 2:
		_snapshot = _results_text(scene)
		_resume_step = 3
		_quit_and_continue()
		return
	_results_done += 1
	match device:
		"mouse":
			_click(continue_button.get_global_rect().get_center())
		"pad":
			_press_pad(JOY_A)
		_:
			_press_key(KEY_ENTER)


# Results shows the report: the grades, an XP row per standing unit, the Standout line, the
# level-ups, the pick's cards with the first focused, Continue locked, the PICK hints.
func _check_results(scene: Node, model: CombatResultsModel) -> void:
	var run: CampaignRunState = _run()
	var grades: GradesPanel = scene.get_node(^"%GradesPanel")
	var xp: XpPanel = scene.get_node(^"%XpPanel")
	var levels: LevelUpPanel = scene.get_node(^"%LevelUpPanel")
	var pick_panel: ItemPickPanel = scene.call(&"get_pick_panel")
	var continue_button: Button = scene.call(&"get_continue_button")
	var cards: Array[ItemOfferCard] = pick_panel.get_offer_cards()
	var lines: PackedStringArray = grades.get_lines()
	_check("results %d: grades and gold, an XP row per unit, the Standout and level-ups" % [
		_entered,
	], (
			model != null
			and not model.is_boss
			and lines.size() >= 4
			and lines[lines.size() - 1] == "Gold earned: %d" % [model.grades.gold]
			and xp.get_rows().size() == run.seat_run(0).army.size()
			and not xp.get_standout_text().is_empty()
			and not levels.get_text().is_empty()
	), "%s; %d rows; %s" % [", ".join(lines), xp.get_rows().size(), xp.get_standout_text()])
	_check("results %d: the pick's cards show, the first focused, Continue locked" % [_entered], (
			cards.size() == model.pick.offers.size()
			and not cards.is_empty()
			and cards[0].has_focus()
			and continue_button.disabled
			and _hint_context(scene) == &"PICK"
	), "%d cards; focus %s; %s" % [cards.size(), cards[0].has_focus(), _hint_context(scene)])


# Keyboard: Enter on the first card, Down to Send to the convoy, Enter; a full convoy's first
# item is scrapped to make room.
func _take_by_keys(scene: Node) -> void:
	var panel: PlacementPanel = scene.call(&"get_placement_panel")
	var offer_id: String = _model_of(scene).pick.offers[0].instance_id
	_press_key(KEY_ENTER)
	_check("placement (keys): Enter on a card opens the panel with the PLACE hints", (
			panel.visible
			and panel.get_step() == PlacementPanel.Step.DESTINATION
			and _hint_context(scene) == &"PLACE"
	))
	var index: int = _enabled_index(panel, "Send it to the convoy")
	for _step: int in index:
		_press_key(KEY_DOWN)
	_check("placement (keys): Down reaches Send it to the convoy", (
			index >= 0 and _enabled(panel)[index].has_focus()
	), str(index))
	_press_key(KEY_ENTER)
	if panel.visible and panel.get_step() == PlacementPanel.Step.CONVOY_SCRAP:
		_press_key(KEY_ENTER)
	_check("placement (keys): the item is in the convoy", (
			not panel.visible and _run().seat_run(0).convoy.has(offer_id)
	))


# Mouse: a click on the first card, then on Scrap it.
func _take_by_mouse(scene: Node) -> void:
	var panel: PlacementPanel = scene.call(&"get_placement_panel")
	var pick_panel: ItemPickPanel = scene.call(&"get_pick_panel")
	var seat_run: SeatRun = _run().seat_run(0)
	var offer: ItemPick.Offer = _model_of(scene).pick.offers[0]
	var gold_before: int = seat_run.gold
	var gold: int = ItemPlacement.scrap_value(EffectCatalog.index().item(offer.definition_id))
	_click(pick_panel.get_offer_cards()[0].get_global_rect().get_center())
	var index: int = _enabled_index(panel, "Scrap it for")
	_check("placement (mouse): a click on a card opens the panel", panel.visible and index >= 0)
	if index < 0:
		return
	_click(_enabled(panel)[index].get_global_rect().get_center())
	_check("placement (mouse): a click on Scrap it pays its gold; the item never joins", (
			not panel.visible
			and seat_run.gold == gold_before + gold
			and not seat_run.items.has(offer.instance_id)
	), "gold %d -> %d (+%d)" % [gold_before, seat_run.gold, gold])


# Pad: the d-pad along the cards, A opens the panel, B backs out without the pause menu, A again,
# then the first unit that can use it equips it (the convoy when none can).
func _take_by_pad(scene: Node, bar: ControlHintBar) -> void:
	_use_pad()
	bar.refresh()
	var panel: PlacementPanel = scene.call(&"get_placement_panel")
	var pick_panel: ItemPickPanel = scene.call(&"get_pick_panel")
	var cards: Array[ItemOfferCard] = pick_panel.get_offer_cards()
	_check("results (pad): the hint bar draws pad glyphs", bar.get_markup().contains("[img"))
	if cards.size() > 1:
		_press_pad(JOY_BUTTON_DPAD_RIGHT)
		var moved: bool = cards[1].has_focus()
		_press_pad(JOY_BUTTON_DPAD_LEFT)
		_check("results (pad): the d-pad moves along the cards", moved and cards[0].has_focus())
	_press_pad(JOY_A)
	var opened: bool = panel.visible
	_press_pad(JOY_B)
	_check("placement (pad): A opens the panel; B closes it, not opening the pause menu", (
			opened and not panel.visible and not paused and cards[0].has_focus()
	), "opened %s, shown %s, paused %s" % [opened, panel.visible, paused])
	_press_pad(JOY_A)
	var index: int = _enabled_index(panel, "Equip on")
	var is_equip: bool = index >= 0
	if not is_equip:
		index = _enabled_index(panel, "Send it to the convoy")
	for _step: int in index:
		_press_pad(JOY_BUTTON_DPAD_DOWN)
	var unit_text: String = _enabled(panel)[index].text
	var offer_id: String = _model_of(scene).pick.offers[0].instance_id
	_press_pad(JOY_A)
	# A displaced item to the convoy, then a convoy item to scrap: each step's first choice.
	for _step: int in 2:
		if panel.visible:
			_press_pad(JOY_A)
	var holder: String = ""
	for unit: UnitInstance in _run().seat_run(0).army:
		if unit.item_ids().has(offer_id):
			holder = unit.instance_id
	_check("placement (pad): the d-pad and A equip it (%s)" % [unit_text], (
			not holder.is_empty() if is_equip else _run().seat_run(0).convoy.has(offer_id)
	), holder)


func _on_placeholder(scene: Node) -> void:
	var device: String = DEVICES[(_entered - 1) % DEVICES.size()]
	var button: Button = scene.call(&"get_continue_button")
	var run: CampaignRunState = _run()
	var title: Label = scene.get_node(^"%Title")
	_check("placeholder: names the node and focuses Continue", (
			title.text == CampaignMapView.TYPE_NAMES[run.graph.type_of(run.node)]
			and button.has_focus()
			and _hint_context(scene) == &"NODE"
	), title.text)
	_placeholder_with[device] = true
	match device:
		"mouse":
			_click(button.get_global_rect().get_center())
		"pad":
			_press_pad(JOY_A)
		_:
			_press_key(KEY_ENTER)


# Back on the map after every node: each device chose a node and answered Results.
func _finish_walk() -> void:
	_check("walk: %d nodes entered, one floor each" % [NODES_TO_PLAY], (
			_run().floor_number == NODES_TO_PLAY and _run().visited.size() == NODES_TO_PLAY
	))
	_check("walk: keyboard, mouse and pad each chose a node and answered Results", (
			_chose_with.size() == 3 and _results_with.size() == 3 and _resume_step == 4
	), "chose %s; results %s; resume %d" % [
		_chose_with.keys(), _results_with.keys(), _resume_step,
	])
	if _placeholder_with.is_empty():
		_skip("placeholder", "the seed's route reached no node that isn't a combat")


# Puts the run at its Boss's results, as a won Boss battle leaves it (a report, no pick), and
# opens Results.
func _begin_boss_case() -> void:
	var run: CampaignRunState = _run()
	var boss: int = run.graph.nodes_on_floor(run.graph.get_floor_count())[0]
	run.node = boss
	run.flow.stage = RunFlow.Stage.RESULTS
	var grades: CombatGrades = CombatGrades.new()
	grades.base_gold = 100
	grades.gold = 100
	run.seat_run(0).pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
		"grades": grades.capture(), "xp": [], "level_ups": [],
	}
	_boss_step = 1
	_router().call(&"goto_screen", SCREEN_COMBAT_RESULTS)


func _on_boss_results(scene: Node) -> void:
	var model: CombatResultsModel = scene.call(&"get_model")
	var pick_panel: ItemPickPanel = scene.call(&"get_pick_panel")
	var button: Button = scene.call(&"get_continue_button")
	_check("boss: Results offers End run, no pick, focused, with the BOSS hints", (
			model != null
			and model.is_boss
			and not pick_panel.visible
			and button.text == "End run"
			and not button.disabled
			and button.has_focus()
			and _hint_context(scene) == &"BOSS"
	), "%s; %s" % [button.text, _hint_context(scene)])
	_boss_step = 2
	_press_key(KEY_ENTER)


func _on_run_end(scene: Node) -> void:
	var title: Label = scene.get_node(^"%Title")
	var leave: Button = scene.get_node(^"%LeaveButton")
	_check("boss: End run archives the run as won and shows the run's end", (
			_boss_step == 2
			and title.text == "Run Won"
			and root.get_node(^"CampaignService").get(&"session") == null
			and leave.has_focus()
			and _hint_context(scene) == &"END"
	), "%s; focus %s; %s" % [title.text, leave.has_focus(), _hint_context(scene)])
	_end()


# Closes the save file and continues the run from it, through Loading, as Save & Quit then
# Continue Run do.
func _quit_and_continue() -> void:
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"close_save_file")
	saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = saves.call(&"continue_solo_run")
	_check("results: the run continues from its save (%d)" % [_resume_step], (
			err == OK
	), error_string(err))
	_router().call(&"goto_screen", SCREEN_LOADING)


# What Results shows, as text: the grades, XP rows, Standout, level-ups, cards and outcome.
func _results_text(scene: Node) -> PackedStringArray:
	var grades: GradesPanel = scene.get_node(^"%GradesPanel")
	var xp: XpPanel = scene.get_node(^"%XpPanel")
	var levels: LevelUpPanel = scene.get_node(^"%LevelUpPanel")
	var pick_panel: ItemPickPanel = scene.call(&"get_pick_panel")
	var text: PackedStringArray = grades.get_lines()
	for row: XpRow in xp.get_rows():
		text.append(row.get_breakdown_text())
	text.append(xp.get_standout_text())
	text.append(levels.get_text())
	for card: ItemOfferCard in pick_panel.get_offer_cards():
		text.append(card.text)
	text.append(_model_of(scene).pick_outcome())
	return text


# Tells the adapters a pad is in use, as the addon does when one is pressed.
func _use_pad() -> void:
	var helper: Node = root.get_node_or_null(HELPER_PATH)
	if helper != null:
		helper.emit_signal(&"device_changed", "xbox", 0)


# A press and release of joypad button.
func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = is_down
		root.push_input(event, true)


# The index among the panel's enabled choices of the first whose text starts with prefix; -1.
func _enabled_index(panel: PlacementPanel, prefix: String) -> int:
	var choices: Array[Button] = _enabled(panel)
	for i: int in choices.size():
		if choices[i].text.begins_with(prefix):
			return i
	return -1


func _enabled(panel: PlacementPanel) -> Array[Button]:
	var choices: Array[Button] = []
	for button: Button in panel.get_choice_buttons():
		if not button.disabled:
			choices.append(button)
	return choices


# A route of NODES_TO_PLAY nodes from floor 1 with at least COMBATS_WANTED combats and a node that
# isn't one, so every device answers a Results and a placeholder shows; without one, the route
# with the most combats.
func _plan_route(graph: CampaignGraph) -> PackedInt32Array:
	var best: PackedInt32Array = []
	var best_combats: int = -1
	var routes: Array[PackedInt32Array] = []
	for start: int in graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_back()
		if route.size() < NODES_TO_PLAY:
			for child: int in graph.children_of(route[route.size() - 1]):
				var longer: PackedInt32Array = route.duplicate()
				longer.append(child)
				routes.append(longer)
			continue
		var combats: int = 0
		for node_id: int in route:
			combats += 1 if _is_combat(graph.type_of(node_id)) else 0
		if combats >= COMBATS_WANTED and combats < route.size():
			return route
		if combats > best_combats:
			best = route
			best_combats = combats
	return best


func _is_combat(type: CampaignGraph.NodeType) -> bool:
	return (
			type == CampaignGraph.NodeType.STANDARD
			or type == CampaignGraph.NodeType.KEY
			or type == CampaignGraph.NodeType.BOSS
	)


func _model_of(scene: Node) -> CombatResultsModel:
	var model: CombatResultsModel = scene.call(&"get_model")
	return model


func _hint_context(scene: Node) -> StringName:
	var bar: ControlHintBar = scene.get_node(^"%ControlHintBar")
	bar.refresh()
	return bar.get_context()


func _run() -> CampaignRunState:
	var session: CampaignSession = root.get_node(^"CampaignService").get(&"session")
	return null if session == null else session.run


func _router() -> Node:
	return root.get_node(^"SceneRouter")


# Drops the run and its save file, gives the root its size back, and finishes.
func _end() -> void:
	_is_done = true
	var saves: Node = root.get_node(^"SaveService")
	saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")
	var helper: Node = root.get_node_or_null(HELPER_PATH)
	if helper != null:
		helper.emit_signal(&"device_changed", "keyboard", -1)
	if current_scene != null:
		current_scene.queue_free()
	root.size = _old_root_size
	_finish()
