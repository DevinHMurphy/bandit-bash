# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hud_cases.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

extends RefCounted
## The HUD's cases for tests/ui/run_all.gd (combat UI plan, UI5 row): the tile info and the unit
## panel against state and [method CombatSession.stats]; the turn counter and its colour past par;
## a banner per phase change; the objective's text; the darkness counter against
## [method Darkness.source_counters] before and after arrival; the fact log against
## [method CombatSession.describe_batch]; target labels by name; the panel area clear of the turn
## bar and the map; and Use, listed exactly where the validator accepts it and sending the command
## it accepted. No autoload is named or needed.
##
## [b]The harness[/b] is turn_input_cases.gd's (the board, the turn bar, swap window, panel host
## and message under a [CanvasLayer], and a [BattleController] on the M1 battle) with a
## [BattleHud] on that layer and the board framed in its map area, as in the gameplay scene. The
## HUD redraws on the board's settles; where a case moves the cursor itself it calls
## [method BattleHud.refresh] to stand for the frame that would redraw it. Use runs on the map
## suite's object fixture ([code]tests/map/object_cases.gd[/code]), since the M1 map has no map
## objects.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")
const ObjectCases = preload("res://tests/map/object_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://scenes/ui/battle/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://scenes/ui/battle/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/battle/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://scenes/ui/battle/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/battle/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://scenes/ui/battle/forecast_panel.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_hud.tscn")
const TURN_COUNTER_SCENE: PackedScene = preload("res://scenes/ui/battle/turn_counter.tscn")

# turn_input_cases.gd's seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# End Turn presses the turn and darkness case makes before giving up: enough to pass par (5) and
# the darkness's arrival (end of turn 4) on M1 if the battle lasts.
const MAX_PHASES: int = 10

# Wait phases a case may play to bring an enemy into reach.
const MAX_WAIT_PHASES: int = 4

# The screen size the layout case lays out at: the project's base size.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1152, 648)

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const USE: TurnInputModel.ActionKind = TurnInputModel.ActionKind.USE
const USE_OBJECT: UnitTurnCommand.Action = UnitTurnCommand.Action.USE_OBJECT

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the harness is added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("hud: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_tile_info()
	_test_unit_panel()
	_test_turns_and_darkness()
	_test_turn_colour()
	_test_objective()
	_test_target_labels()
	_test_panel_area()
	_test_use()


# Every tile of the M1 map under the cursor: the tile info shows its terrain's name and bonuses and
# its occupant by name; off the map it hides.
func _test_tile_info() -> void:
	var rig: Rig = _rig(true)
	if rig == null:
		return
	var session: CombatSession = rig.h.session
	var info: TileInfo = rig.hud.get_tile_info()
	var wrong: PackedStringArray = []
	var occupied: int = 0
	var rect: Rect2i = session.layout.get_rect()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var tile: Vector2i = Vector2i(x, y)
			if not rig.h.controller.move_cursor(tile):
				wrong.append("%s: the cursor didn't move there" % [tile])
				continue
			rig.hud.refresh()
			var view: HudViewModel.TileView = info.get_view()
			var terrain: MapLayout.Terrain = session.layout.terrain_at(tile)
			var occupant: String = session.state.occupant_at(tile)
			var expected_name: String = BattleText.name_of(session, occupant)
			if (
					view == null
					or not info.visible
					or view.tile != tile
					or view.terrain_name != HudViewModel.terrain_name(terrain.id)
					or view.avoid != terrain.bonus.avoid
					or view.defense != terrain.bonus.defense
					or view.resistance != terrain.bonus.resistance
					or view.occupant_id != occupant
					or view.occupant_name != expected_name
			):
				wrong.append("%s: view differs from the layout" % [tile])
				continue
			var texts: PackedStringArray = info.get_texts()
			var bonuses: String = info.bonus_format % [
				terrain.bonus.avoid, terrain.bonus.defense, terrain.bonus.resistance,
			]
			if texts[0] != view.terrain_name or texts[1] != bonuses:
				wrong.append("%s: shows %s" % [tile, texts])
			if occupant.is_empty():
				if texts[2] != info.empty_text:
					wrong.append("%s: empty tile shows '%s'" % [tile, texts[2]])
			else:
				occupied += 1
				if not texts[2].begins_with(expected_name) or texts[2].contains(occupant):
					wrong.append("%s: occupant shows '%s'" % [tile, texts[2]])
	_check.call("tile info: every M1 tile shows its terrain, bonuses and occupant by name", (
			wrong.is_empty() and occupied == session.state.unit_ids().size()
	), "%d occupied; %s" % [occupied, "; ".join(wrong.slice(0, 3))])

	info.show_tile(HudViewModel.tile_view(session, rect.end + Vector2i.ONE))
	_check.call("tile info: hides off the map", not info.visible)
	rig.close()


# Every unit under the cursor: the panel matches its state and stats; with the cursor on an empty
# tile it shows the selected unit, and nothing once the selection is dropped.
func _test_unit_panel() -> void:
	var rig: Rig = _rig(true)
	if rig == null:
		return
	var session: CombatSession = rig.h.session
	var panel: UnitPanel = rig.hud.get_unit_panel()
	var wrong: PackedStringArray = []
	for unit_id: String in session.state.unit_ids():
		rig.h.controller.move_cursor(session.state.tile_of(unit_id))
		rig.hud.refresh()
		var problem: String = _unit_problem(session, unit_id, panel)
		if not problem.is_empty():
			wrong.append("%s: %s" % [unit_id, problem])
	_check.call("unit panel: each unit's HP, stats, weapon, Block and Stance match the session", (
			wrong.is_empty()
	), "; ".join(wrong.slice(0, 3)))

	var unit_id: String = TurnInputModel.acting_units(session, 0)[0]
	rig.h.controller.confirm_tile(session.state.tile_of(unit_id))
	var empty: Vector2i = CombatFact.NO_TILE
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		if session.state.occupant_at(tile).is_empty():
			empty = tile
			break
	rig.h.controller.move_cursor(empty)
	rig.hud.refresh()
	var shown: HudViewModel.UnitView = panel.get_view()
	var selected_shown: bool = panel.visible and shown != null and shown.unit_id == unit_id
	rig.h.controller.step_back()
	rig.hud.refresh()
	_check.call("unit panel: the selected unit shows off its tile, and nothing once dropped", (
			empty != CombatFact.NO_TILE and selected_shown and not panel.visible
	), "selected shown %s, then visible %s" % [selected_shown, panel.visible])
	rig.close()


# From the swap window, End Turn alone: after every settle the turn counter reads the turn against
# par, coloured only past par; the darkness counter is source_counters' first count, saying arrives
# before arrival and next wave after; a banner shows per Phase Start played; the fact log holds
# describe_batch's line for every batch since bind.
func _test_turns_and_darkness() -> void:
	var rig: Rig = _rig(false)
	if rig == null:
		return
	var session: CombatSession = rig.h.session
	var counter: TurnCounter = rig.hud.get_turn_counter()
	var darkness: DarknessCounter = rig.hud.get_darkness_counter()
	var banner: PhaseBanner = rig.hud.get_phase_banner()
	var banners_before: int = banner.get_shown_count()
	var wrong_turn: PackedStringArray = []
	var wrong_dark: PackedStringArray = []
	var swap_text: String = counter.get_text()
	rig.h.controller.request_start()
	BattleViewCases.settle(rig.h.view)
	var saw_before: bool = false
	var saw_after: bool = false
	var saw_past_par: bool = false
	for _phase: int in MAX_PHASES + 1:
		_check_turn(session, counter, wrong_turn)
		var problem: String = _darkness_problem(session, darkness)
		if not problem.is_empty():
			wrong_dark.append("turn %d: %s" % [session.state.turn, problem])
		saw_before = saw_before or not session.state.map.has_darkness_arrived
		saw_after = saw_after or session.state.map.has_darkness_arrived
		saw_past_par = saw_past_par or counter.is_past_par_shown()
		if session.is_finished:
			break
		rig.send(EndTurnCommand.new(0))
	var par: int = _map.turn_par
	_check.call("turn counter: 'before turn 1' in the swap window, then turn N of par N", (
			swap_text == counter.before_first_turn_format % [par] and wrong_turn.is_empty()
	), "%s; %s" % [swap_text, "; ".join(wrong_turn.slice(0, 3))])
	_check.call("turn counter: coloured once past par, and only then (played to turn %d)" % [
		session.state.turn,
	], saw_past_par == (session.state.turn > par) and wrong_turn.is_empty())
	_check.call("darkness counter: source_counters' count before and after arrival", (
			wrong_dark.is_empty() and saw_before and saw_after
	), "before %s, after %s; %s" % [saw_before, saw_after, "; ".join(wrong_dark.slice(0, 3))])
	var shown: int = banner.get_shown_count() - banners_before
	var last_texts: PackedStringArray = banner.get_texts()
	var expected_text: String = (
			banner.player_text if rig.last_phase_side == PLAYER else banner.enemy_text
	)
	_check.call("phase banner: one per Phase Start played, naming its side", (
			rig.phase_starts > 1 and shown == rig.phase_starts and last_texts[0] == expected_text
	), "%d banners for %d phase starts; last '%s'" % [shown, rig.phase_starts, last_texts[0]])
	var logged: PackedStringArray = rig.hud.get_fact_log().get_lines()
	_check.call("fact log: describe_batch's line for every batch since bind, in order", (
			not rig.lines.is_empty() and logged == rig.lines
	), "%d logged, %d sent" % [logged.size(), rig.lines.size()])
	rig.close()


# The counter on its own: within par it keeps the theme's colour, past par it takes past_par_color.
func _test_turn_colour() -> void:
	var counter: TurnCounter = TURN_COUNTER_SCENE.instantiate()
	_root.add_child(counter)
	var view: HudViewModel.TurnView = HudViewModel.TurnView.new()
	view.par = 5
	view.turn = 5
	counter.show_turn(view)
	var at_par: bool = counter.is_past_par_shown()
	var at_par_text: String = counter.get_text()
	view.turn = 6
	counter.show_turn(view)
	_check.call("turn counter: turn 5 of par 5 is plain, turn 6 takes the past-par colour", (
			not at_par
			and at_par_text == "Turn 5 of par 5"
			and counter.is_past_par_shown()
			and counter.get_text_color() == counter.past_par_color
	), "%s %s, then %s" % [at_par_text, at_par, counter.get_text()])
	counter.free()


# M1's objective (Rout) shows as text; every objective has one.
func _test_objective() -> void:
	var rig: Rig = _rig(true)
	if rig == null:
		return
	var missing: PackedStringArray = []
	for objective: int in CombatMapDefinition.Objective.values():
		if not HudViewModel.OBJECTIVE_TEXT.has(objective):
			missing.append(CombatMapDefinition.Objective.find_key(objective) as String)
	var shown: String = rig.hud.get_objective().get_text()
	_check.call("objective: M1 shows 'Rout: defeat every enemy'; every objective has a text", (
			shown == HudViewModel.OBJECTIVE_TEXT[CombatMapDefinition.Objective.ROUT]
			and missing.is_empty()
	), "'%s'; missing %s" % [shown, missing])
	rig.close()


# Every target TurnInputModel offers over a few player phases, and each forecast's headings, name
# the unit (BattleText.name_of), never its instance id.
func _test_target_labels() -> void:
	var rig: Rig = _rig(true)
	if rig == null:
		return
	var session: CombatSession = rig.h.session
	var wrong: PackedStringArray = []
	var labelled: int = 0
	var forecasts: int = 0
	for _phase: int in MAX_WAIT_PHASES:
		if session.is_finished:
			break
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			for tile: Vector2i in _sample_tiles(session, unit_id):
				var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
				for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
						session, unit_id, path
				):
					for target: TurnInputModel.TargetOption in option.targets:
						labelled += 1
						_check_label(session, target, wrong)
						var turn: UnitTurnCommand = target.command as UnitTurnCommand
						if turn == null or not turn.needs_fresh_forecast():
							continue
						forecasts += 1
						var model: ForecastViewModel = ForecastViewModel.build(session, turn, 0, 1)
						var names: PackedStringArray = [
							BattleText.name_of(session, turn.actor_id),
							BattleText.name_of(session, turn.get_target_id()),
						]
						if (
								model.actor_label != names[0]
								or model.target_label != names[1]
								or model.title.contains(turn.get_target_id())
						):
							wrong.append("forecast '%s': %s | %s" % [
								model.title, model.actor_label, model.target_label,
							])
		rig.wait_phase()
	_check.call("target labels: names, not ids, in the picker and the forecast", (
			wrong.is_empty() and labelled > 0 and forecasts > 0
	), "%d targets, %d forecasts; %s" % [labelled, forecasts, "; ".join(wrong.slice(0, 3))])
	rig.close()


# At the base size: the panel area, the HUD's left column and banner, and the turn bar cover none
# of the map; the panel area clips and stops above the turn bar, so the forecast with its
# breakdown open stays off the turn bar and End Turn, scrolling instead; it fits the area's width.
func _test_panel_area() -> void:
	var window: Window = _root.get_window()
	var old_size: Vector2i = window.size
	window.size = BASE_SCREEN_SIZE
	var rig: Rig = _rig(true)
	if rig == null:
		window.size = old_size
		return
	var map: Rect2 = _map_on_screen(rig)
	var area: Rect2 = rig.h.host.get_area_rect()
	var bar: Rect2 = rig.h.bar.get_global_rect()
	var left: Control = rig.hud.get_node(^"LeftColumn")
	var covers: PackedStringArray = []
	var widgets: Dictionary[String, Rect2] = {
		"panel area": area,
		"left column": left.get_global_rect(),
		"phase banner": rig.hud.get_phase_banner().get_global_rect(),
		"turn bar": bar,
		"swap window": rig.h.swap.get_global_rect(),
		"message": rig.h.message.get_global_rect(),
	}
	for widget_name: String in widgets:
		if widgets[widget_name].intersects(map):
			covers.append("%s %s" % [widget_name, widgets[widget_name]])
	_check.call("layout: at 1152×648 no HUD widget's area covers the M1 map", (
			map.has_area() and covers.is_empty()
	), "map %s; %s" % [map, "; ".join(covers)])

	var steps: PackedStringArray = []
	var pick: Array = []
	for _phase: int in MAX_WAIT_PHASES:
		pick = _find_forecast(rig.h.session)
		if not pick.is_empty() or rig.h.session.is_finished:
			break
		rig.wait_phase()
	var panel: ForecastPanel = null
	if pick.is_empty():
		steps.append("no attack, staff or shove offered")
	else:
		panel = _open_forecast(rig, pick, steps)
	var scroll: ScrollContainer = rig.h.host.get_node(^"%Scroll")
	if panel != null:
		panel.set_breakdown_open(true)
		if not scroll.is_ancestor_of(panel):
			steps.append("the forecast isn't in the panel area")
		if panel.get_combined_minimum_size().x > area.size.x:
			steps.append("the forecast is %d px wide, the area %d" % [
				panel.get_combined_minimum_size().x, area.size.x,
			])
	_check.call("forecast panel: with its breakdown open it stays off the turn bar and End Turn", (
			panel != null
			and panel.is_breakdown_showing()
			and scroll.clip_contents
			and not area.intersects(bar)
			and not area.intersects(rig.h.bar.get_end_turn_button().get_global_rect())
			and steps.is_empty()
	), "area %s, bar %s; %s" % [area, bar, "; ".join(steps)])
	rig.close()
	window.size = old_size


# Use on the object fixture: from every tile the unit can end on, the menu's Use lists exactly the
# objects whose use the validator accepts (with no item or the Pouch's key), in menu order; Use is
# never offered on M1, which has no objects; the house's command, sent, resolves to Object used.
func _test_use() -> void:
	var world: ObjectCases.ObjectWorld = ObjectCases.ObjectWorld.new([
		"plain plain plain plain plain",
		"plain plain plain plain plain",
		"plain plain plain plain plain",
	], [
		[Vector2i(2, 0), MapLayout.ObjectKind.HOUSE],
		[Vector2i(4, 0), MapLayout.ObjectKind.CHEST],
		[Vector2i(0, 2), MapLayout.ObjectKind.LEVER, 1],
		[Vector2i(4, 2), MapLayout.ObjectKind.DOOR, 1],
	])
	world.add_unit("hero", PLAYER, Vector2i(0, 0), "sword")
	var key_id: String = world.give_item("hero", MapObjects.KEY_EFFECT_ID, 1)
	world.open()
	var session: CombatSession = world.session
	var wrong: PackedStringArray = []
	var used_on: Dictionary[String, bool] = {}
	var house_turn: UnitTurnCommand = null
	var keyed: int = 0
	for tile: Vector2i in TurnInputModel.move_tiles(session, "hero"):
		var path: Array[Vector2i] = TurnInputModel.path_to(session, "hero", tile)
		var options: Array[TurnInputModel.ActionOption] = TurnInputModel.actions_at(
				session, "hero", path
		)
		var last_rank: int = -1
		var listed: Dictionary[String, TurnInputModel.TargetOption] = {}
		for option: TurnInputModel.ActionOption in options:
			var rank: int = TurnInputModel.MENU_ORDER.find(option.kind)
			if rank <= last_rank:
				wrong.append("%s: %s out of menu order" % [tile, option.label])
			last_rank = rank
			if option.kind != USE:
				continue
			for target: TurnInputModel.TargetOption in option.targets:
				listed[target.target_id] = target
		var expected: PackedStringArray = []
		for object_id: String in session.state.map.objects:
			var plain: UnitTurnCommand = UnitTurnCommand.new(0, "hero", USE_OBJECT, object_id, path)
			var with_key: UnitTurnCommand = UnitTurnCommand.new(
					0, "hero", USE_OBJECT, object_id, path
			)
			with_key.item_id = key_id
			if plain.validate(session).is_empty() or with_key.validate(session).is_empty():
				expected.append(object_id)
		expected.sort()
		var found: PackedStringArray = PackedStringArray(listed.keys())
		found.sort()
		if found != expected:
			wrong.append("%s: lists %s, the validator accepts %s" % [tile, found, expected])
		for object_id: String in listed:
			var target: TurnInputModel.TargetOption = listed[object_id]
			var turn: UnitTurnCommand = target.command as UnitTurnCommand
			used_on[object_id] = true
			if (
					turn.action != USE_OBJECT
					or turn.target_id != object_id
					or turn.validate(session) != ""
					or target.tile != session.state.map.object(object_id).tile
					or target.label != BattleText.name_of(session, object_id)
			):
				wrong.append("%s: %s's option is wrong" % [tile, object_id])
			if turn.item_id == key_id:
				keyed += 1
			if session.state.map.object(object_id).kind == MapLayout.ObjectKind.HOUSE:
				house_turn = turn
	_check.call("use: listed exactly where the validator accepts it, in menu order", (
			wrong.is_empty() and used_on.size() == session.state.map.objects.size() and keyed > 0
	), "used on %s, %d with the key; %s" % [used_on.keys(), keyed, "; ".join(wrong.slice(0, 3))])

	var resolved: bool = false
	if house_turn != null:
		session.submit(house_turn)
		var batch: CombatSession.FactBatch = session.resolve_next()
		for fact: CombatFact in batch.facts:
			if fact.kind == CombatFact.Kind.OBJECT_USED and fact.target_id == house_turn.target_id:
				resolved = true
	_check.call("use: the house's listed command resolves to Object used", resolved)

	var rig: Rig = _rig(true)
	if rig == null:
		return
	var offered: int = 0
	for unit_id: String in TurnInputModel.acting_units(rig.h.session, 0):
		for tile: Vector2i in _sample_tiles(rig.h.session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(rig.h.session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					rig.h.session, unit_id, path
			):
				if option.kind == USE:
					offered += 1
	_check.call("use: never offered on M1, which has no map objects", (
			rig.h.session.state.map.objects.is_empty() and offered == 0
	), "%d offered" % [offered])
	rig.close()


# --- Checks ----------------------------------------------------------------------------------


# Why panel doesn't show unit_id as the session has it; empty when it does.
func _unit_problem(session: CombatSession, unit_id: String, panel: UnitPanel) -> String:
	var view: HudViewModel.UnitView = panel.get_view()
	if view == null or not panel.visible or view.unit_id != unit_id:
		return "not shown"
	var state: CombatState = session.state
	var sheet: StatSheet = session.stats(unit_id)
	var unit: CombatUnitState = state.unit(unit_id)
	var values: PackedInt32Array = []
	for row: Array in HudViewModel.STAT_ROWS:
		values.append(sheet.get_int(row[1] as int))
	var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
	var weapon_name: String = "" if held == null else BattleText.name_of(session, held.id)
	if (
			view.name != BattleText.name_of(session, unit_id)
			or view.hp != state.get_hp(unit_id)
			or view.max_hp != sheet.get_int(CombatValue.Key.HP)
			or view.block != state.get_block(unit_id)
			or view.stance != state.get_stance(unit_id)
			or view.stance_max != sheet.get_int(CombatValue.Key.STANCE_MAX)
			or view.stat_values != values
			or view.weapon_name != weapon_name
			or view.pouch_name != BattleText.name_of(session, unit.pouch_item_id)
	):
		return "view differs"
	var texts: PackedStringArray = panel.get_texts()
	if (
			texts[0] != view.name
			or texts[2] != panel.hp_format % [view.hp, view.max_hp]
			or texts[3] != panel.guard_format % [view.block, view.stance, view.stance_max]
			or (not weapon_name.is_empty() and not texts[5].begins_with(weapon_name))
	):
		return "shows %s" % [texts]
	return ""


# Appends why the counter doesn't show the session's turn against par, coloured iff past it.
func _check_turn(session: CombatSession, counter: TurnCounter, wrong: PackedStringArray) -> void:
	var turn: int = session.state.turn
	var par: int = session.setup.map.turn_par
	var expected: String = counter.turn_format % [turn, par]
	if counter.get_text() != expected or counter.is_past_par_shown() != (turn > par):
		wrong.append("turn %d: '%s', coloured %s" % [
			turn, counter.get_text(), counter.is_past_par_shown(),
		])


# Why the darkness counter doesn't match source_counters; empty when it does.
func _darkness_problem(session: CombatSession, darkness: DarknessCounter) -> String:
	var counters: PackedInt32Array = Darkness.source_counters(session.state)
	var view: HudViewModel.DarknessView = darkness.get_view()
	if counters.is_empty() or view == null:
		return "no counter (%s)" % [counters]
	var arrived: bool = session.state.map.has_darkness_arrived
	if view.turns != counters[0] or view.has_arrived != arrived or not view.is_coming:
		return "view %d %s, counters %s %s" % [view.turns, view.has_arrived, counters, arrived]
	var expected: String = darkness.arrives_format % [view.turns]
	if arrived:
		expected = darkness.wave_format % [view.turns]
	if view.turns <= 1:
		expected = darkness.wave_now_text if arrived else darkness.arrives_now_text
	if darkness.get_text() != expected:
		return "shows '%s', expected '%s'" % [darkness.get_text(), expected]
	return ""


# Appends why target's label isn't its target's name.
func _check_label(
		session: CombatSession, target: TurnInputModel.TargetOption, wrong: PackedStringArray
) -> void:
	var expected: String = BattleText.name_of(session, target.target_id)
	if target.command is CastRuneCommand:
		if not target.label.ends_with(" on " + expected):
			wrong.append("rune '%s'" % [target.label])
		return
	if target.label != expected or target.label.contains(target.target_id):
		wrong.append("'%s' for %s" % [target.label, target.target_id])


# --- Fixtures --------------------------------------------------------------------------------


# The unit's own tile and its move tile nearest an enemy: where most targets are on offer, and few
# enough tiles that each phase's menus stay cheap (a tile pick runs ~25 validations).
static func _sample_tiles(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var origin: Vector2i = session.state.tile_of(unit_id)
	var tiles: Array[Vector2i] = [origin]
	var best: Vector2i = origin
	var best_distance: int = 1 << 30
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		for enemy_id: String in session.state.units_of(ENEMY):
			var distance: int = session.state.grid.distance(tile, session.state.tile_of(enemy_id))
			if distance < best_distance:
				best = tile
				best_distance = distance
	if best != origin:
		tiles.append(best)
	return tiles


# The harness with the HUD; after the opening swap window's Start when is_started.
func _rig(is_started: bool) -> Rig:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("hud: the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	var rig: Rig = Rig.new()
	rig.h = h
	rig.hud = HUD_SCENE.instantiate()
	h.hud.add_child(rig.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	for widget: Control in [h.bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.forecast_panel_scene = FORECAST_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	_root.add_child(h.controller)
	h.view.map_area = rig.hud.get_map_area()
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	rig.hud.bind(h.session, h.controller, h.view)
	h.session.batch_resolved.connect(h.record)
	h.session.batch_resolved.connect(rig.record_line)
	h.session.bus.flow.phase_started.connect(rig.count_phase)
	if is_started:
		h.controller.request_start()
		BattleViewCases.settle(h.view)
	return rig


# Where the M1 map is on screen, with the camera's scroll applied as a frame would.
func _map_on_screen(rig: Rig) -> Rect2:
	var camera: Camera2D = _root.get_viewport().get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	return rig.h.view.get_global_transform_with_canvas() * rig.h.view.map_rect()


# The first [unit_id, tile, option, target] with a forecast (attack, staff, shove); empty for none.
func _find_forecast(session: CombatSession) -> Array:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				for target: TurnInputModel.TargetOption in option.targets:
					var turn: UnitTurnCommand = target.command as UnitTurnCommand
					if turn != null and turn.needs_fresh_forecast():
						return [unit_id, tile, option, target]
	return []


# Walks the controller from IDLE to the forecast for pick with the panels' own rows; the panel, or
# null with the problem in steps.
func _open_forecast(rig: Rig, pick: Array, steps: PackedStringArray) -> ForecastPanel:
	var h: TurnInputCases.Harness = rig.h
	var option: TurnInputModel.ActionOption = pick[2]
	var target: TurnInputModel.TargetOption = pick[3]
	h.controller.confirm_tile(h.session.state.tile_of(pick[0] as String))
	h.controller.confirm_tile(pick[1] as Vector2i)
	var menu: ActionMenu = h.host.top() as ActionMenu
	if menu == null:
		steps.append("no action menu")
		return null
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == option.kind:
			menu.get_rows()[i].pressed.emit()
			break
	var picker: TargetPicker = h.host.top() as TargetPicker
	if picker == null:
		steps.append("no target picker")
		return null
	var targets: Array[TurnInputModel.TargetOption] = picker.get_options()
	for i: int in targets.size():
		if targets[i].target_id == target.target_id:
			picker.get_rows()[i].pressed.emit()
			break
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	if panel == null:
		steps.append("no forecast panel")
	return panel


## The turn input harness with the HUD on it, and what the session sent and played since bind.
class Rig:
	extends RefCounted

	## The board, widgets and controller (turn_input_cases.gd).
	var h: TurnInputCases.Harness = null
	## The HUD.
	var hud: BattleHud = null
	## describe_batch's line for every batch since bind, in order.
	var lines: PackedStringArray = []
	## Phase Start facts played since bind.
	var phase_starts: int = 0
	## The side of the last one.
	var last_phase_side: CombatFact.CombatSide = CombatFact.CombatSide.NONE

	## Keeps [param batch]'s log line.
	func record_line(batch: CombatSession.FactBatch) -> void:
		lines.append(h.session.describe_batch(batch))

	## Counts [param fact], a Phase Start played.
	func count_phase(fact: CombatFact) -> void:
		phase_starts += 1
		last_phase_side = fact.side

	## Sends [param command] straight to the encounter and lets it play.
	func send(command: Command) -> void:
		h.battle.submit(command, h.session.session_id)
		h.battle.resolve_queued()
		BattleViewCases.settle(h.view)

	## Every acting unit waits, then End Turn.
	func wait_phase() -> void:
		for unit_id: String in TurnInputModel.acting_units(h.session, 0):
			send(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
		if not h.session.is_finished:
			send(EndTurnCommand.new(0))

	## Frees the nodes and closes the run.
	func close() -> void:
		if h.session.batch_resolved.is_connected(record_line):
			h.session.batch_resolved.disconnect(record_line)
		if h.session.bus.flow.phase_started.is_connected(count_phase):
			h.session.bus.flow.phase_started.disconnect(count_phase)
		h.close()
