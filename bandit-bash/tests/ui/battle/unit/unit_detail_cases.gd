# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_detail_cases.gd
# Author:
# Created:  November 7, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Unit detail's cases for the ui/input suite (combat UI plan, UI11 row): [UnitDetailViewModel]
## against the session for a player unit (the Drengr) and an enemy (HP, Stance and its maximum,
## Block, the stats through [method CombatSession.stats], the weapon and its profile, each effect
## the unit carries as text, its army's heirlooms, none for the enemy); the [UnitDetailPanel]
## drawing it; opening it from IDLE by Ctrl and closing it by Esc and by Ctrl again; from MOVE on
## an enemy by the pad's L3 and closing by B, the selection, cursor and overlays as they were;
## by the mouse through the unit panel's Details button, closed by a right click and by its Close
## button; focus on Close while it is open and back where it was after; the hints: unit_detail
## listed in IDLE and MOVE only while there is a unit to show, and DETAIL's row; each value's
## sources against [method StatSheet.explain]; catalog type names (BUG-005); level, XP and
## growths from a run record; an enemy's intent, target rule and signature move; stepping through
## a side by Q / E, LB / RB and Next; and a right click on a unit opening its detail.[br]
## [b]The rig[/b] is turn_input_cases.gd's harness on the M1 battle past Start, with the
## [BattleHud] (for the unit panel's button, wired to the controller as [BattleScreen] wires it)
## and the detail scene set. Keys and pad buttons go through the root viewport. No autoload is
## named or needed.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/input"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://ui/battle/forecast/forecast_panel.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/battle/hud/battle_hud.tscn")
const DETAIL_SCENE: PackedScene = preload("res://ui/battle/unit/unit_detail_panel.tscn")

# turn_input_cases.gd's seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# The pad's L3 (unit_detail) and B (ui_cancel), as project.godot binds them.
const PAD_DETAIL: JoyButton = JOY_BUTTON_LEFT_STICK
const PAD_BACK: JoyButton = JOY_BUTTON_B

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const IDLE: BattleController.Stage = BattleController.Stage.IDLE
const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const DETAIL: BattleController.Stage = BattleController.Stage.DETAIL

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the rig is added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("unit detail: the M1 map definition loads", false, M1_DEFINITION)
		return
	var rig: Rig = _rig()
	if rig == null:
		return
	_test_view_models(rig)
	_test_keyboard(rig)
	_test_pad(rig)
	_test_mouse(rig)
	_test_hints(rig)
	_test_sources(rig)
	_test_names(rig)
	_test_run_record(rig)
	_test_enemy_section(rig)
	_test_stepping(rig)
	_test_right_click(rig)
	rig.close()


# The Drengr's and an enemy's detail against the session, and the panel drawing them.
func _test_view_models(rig: Rig) -> void:
	var session: CombatSession = rig.h.session
	var drengr: String = _unit_of_type(session, "drengr")
	var enemy: String = session.state.units_of(ENEMY)[0]
	for unit_id: String in [drengr, enemy]:
		var view: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
		var problems: PackedStringArray = _view_problems(session, unit_id, view)
		_check.call("unit detail: %s's view is the session's" % [
			BattleText.name_of(session, unit_id),
		], problems.is_empty(), "; ".join(problems))
	var player_view: UnitDetailViewModel = UnitDetailViewModel.build(session, drengr)
	var enemy_view: UnitDetailViewModel = UnitDetailViewModel.build(session, enemy)
	_check.call("unit detail: the Drengr commands, with its army's heirlooms; the enemy has none", (
			player_view.is_commander
			and not player_view.heirlooms.is_empty()
			and enemy_view.heirlooms.is_empty()
			and enemy_view.side == ENEMY
	), "commander %s, heirlooms %d / %d" % [
		player_view.is_commander, player_view.heirlooms.size(), enemy_view.heirlooms.size(),
	])
	_check.call("unit detail: no view for an id off the map", (
			UnitDetailViewModel.build(session, "") == null
			and UnitDetailViewModel.build(session, "unit:999999") == null
	))
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	rig.h.hud.add_child(panel)
	panel.open_with(player_view)
	var texts: PackedStringArray = panel.get_texts()
	var weapon: String = "Weapon: %s (%s, %s)" % [
		player_view.weapon.name, player_view.weapon.weapon_type, player_view.weapon.profile,
	]
	var heirloom: String = "(none)"
	if not player_view.heirlooms.is_empty():
		heirloom = "%s: %s" % [player_view.heirlooms[0].label, player_view.heirlooms[0].text]
	print("      (detail: %s)" % [" / ".join(texts).replace("\n", " ")])
	_check.call("unit detail: the panel draws name, vitals, weapon profile and effect text", (
			texts[0] == player_view.name
			and texts[1].contains("Commander")
			and texts[2] == "HP %d/%d · Stance %d/%d · Block %d" % [
				player_view.hp, player_view.max_hp, player_view.stance, player_view.stance_max,
				player_view.block,
			]
			and texts[5].begins_with(weapon)
			and texts[10].contains(heirloom)
	), " / ".join(texts))
	panel.free()


# IDLE, the cursor on the Drengr: Ctrl opens its detail with Close focused; Esc closes it, then
# Ctrl opens and Ctrl closes it; each time IDLE, the cursor and focus are back as they were.
func _test_keyboard(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var drengr: String = _unit_of_type(h.session, "drengr")
	h.controller.move_cursor(h.session.state.tile_of(drengr))
	var before: String = _state_line(rig)
	_press_key(KEY_CTRL)
	var opened: String = _open_problem(rig, drengr)
	_press_key(KEY_ESCAPE)
	var after_esc: String = _state_line(rig)
	_press_key(KEY_CTRL)
	var reopened: String = _open_problem(rig, drengr)
	_press_key(KEY_CTRL)
	var after_ctrl: String = _state_line(rig)
	_check.call("unit detail (keys): Ctrl opens it in IDLE; Esc and Ctrl close it, all as it was", (
			opened.is_empty() and reopened.is_empty()
			and after_esc == before and after_ctrl == before
	), "%s; %s; before %s, after Esc %s, after Ctrl %s" % [
		opened, reopened, before, after_esc, after_ctrl,
	])


# MOVE on a unit, the cursor on an enemy in reach of the board: L3 opens the enemy's detail;
# B closes it, back in MOVE with the selection, cursor and move tiles as they were.
func _test_pad(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	var enemy: String = h.session.state.units_of(ENEMY)[0]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.move_cursor(h.session.state.tile_of(enemy))
	var before: String = _state_line(rig)
	var move_tiles: Array[Vector2i] = h.view.get_move_overlay().shown_tiles()
	_press_pad(PAD_DETAIL)
	var opened: String = _open_problem(rig, enemy)
	var drawn_in_detail: bool = h.view.get_move_overlay().shown_tiles() == move_tiles
	_press_pad(PAD_BACK)
	var after: String = _state_line(rig)
	_check.call("unit detail (pad): L3 opens an enemy's from MOVE; B closes it, MOVE as it was", (
			opened.is_empty()
			and drawn_in_detail
			and after == before
			and h.controller.get_stage() == MOVE
			and h.controller.get_selected_unit() == unit_id
			and h.view.get_move_overlay().shown_tiles() == move_tiles
	), "%s; overlays kept %s; before %s, after %s" % [opened, drawn_in_detail, before, after])
	h.controller.step_back()


# IDLE: the unit panel's Details button opens the hovered unit's detail; a right click closes it;
# again, and its Close button closes it. The buttons are pressed through their signals, as the
# other cases press rows: a frame's layout hasn't placed the HUD's column yet within one frame.
# The display suite clicks Details on the laid-out gameplay screen.
func _test_mouse(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var unit_id: String = h.session.state.units_of(PLAYER)[1]
	h.controller.move_cursor(h.session.state.tile_of(unit_id))
	rig.hud.refresh()
	var before: String = _state_line(rig)
	var button: Button = rig.hud.get_unit_panel().get_details_button()
	button.pressed.emit()
	var opened: String = _open_problem(rig, unit_id)
	_click(Vector2(4.0, 4.0), MOUSE_BUTTON_RIGHT)
	var after_right: String = _state_line(rig)
	button.pressed.emit()
	var reopened: String = _open_problem(rig, unit_id)
	var panel: UnitDetailPanel = h.controller.get_detail_panel()
	if panel != null:
		panel.get_close_button().pressed.emit()
	var after_close: String = _state_line(rig)
	_check.call("unit detail (mouse): Details opens it; a right click and Close close it", (
			opened.is_empty()
			and reopened.is_empty()
			and after_right == before
			and after_close == before
			and button.focus_mode == Control.FOCUS_NONE
	), "%s; %s; before %s, after right %s, after Close %s" % [
		opened, reopened, before, after_right, after_close,
	])


# unit_detail is live in IDLE on a unit and not on an empty tile; DETAIL's row closes with accept,
# Back or unit_detail.
func _test_hints(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var unit_id: String = h.session.state.units_of(PLAYER)[0]
	h.controller.move_cursor(h.session.state.tile_of(unit_id))
	var on_unit: bool = h.controller.get_live_actions().has(&"unit_detail")
	h.controller.move_cursor(_empty_tile(h.session))
	var on_empty: bool = h.controller.get_live_actions().has(&"unit_detail")
	h.controller.move_cursor(h.session.state.tile_of(unit_id))
	h.controller.request_unit_detail()
	var context: StringName = h.controller.get_hint_context()
	var live: Array[StringName] = h.controller.get_live_actions()
	h.controller.step_back()
	_check.call("unit detail (hints): listed in IDLE on a unit only; DETAIL lists its closes", (
			on_unit
			and not on_empty
			and context == &"DETAIL"
			and live.has(&"ui_accept")
			and live.has(&"ui_cancel")
			and live.has(&"unit_detail")
	), "on unit %s, on empty %s, %s %s" % [on_unit, on_empty, context, live])


# Every stat and combat value of the Drengr and an enemy is the session's, its sources the
# applied lines of StatSheet.explain (base first) when anything changes it and none otherwise, and
# the panel's rows show them as the view has them.
func _test_sources(rig: Rig) -> void:
	var session: CombatSession = rig.h.session
	var problems: PackedStringArray = []
	var drengr: String = _unit_of_type(session, "drengr")
	for unit_id: String in [drengr, session.state.units_of(ENEMY)[0]]:
		var view: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
		var sheet: StatSheet = session.stats(unit_id)
		var rows: Array[UnitDetailViewModel.ValueRow] = view.stat_rows + view.combat_rows
		for row: UnitDetailViewModel.ValueRow in rows:
			if row.key < 0:
				continue
			var answer: ValueBreakdown = sheet.explain(row.key)
			var is_changed: bool = false
			for line: ValueBreakdown.Line in answer.lines:
				is_changed = is_changed or (line.applied and line.modifier != null)
			var shown: String = " ".join(row.sources)
			if row.value != answer.get_int():
				problems.append("%s %s is %d" % [unit_id, row.label, row.value])
			elif is_changed and "%s = %s" % [shown, answer.to_text().get_slice(" = ", 1)] != (
					answer.to_text()
			):
				problems.append("%s %s sources '%s', explain '%s'" % [
					unit_id, row.label, shown, answer.to_text(),
				])
			elif not is_changed and not row.sources.is_empty():
				problems.append("%s %s lists '%s' with nothing changing it" % [
					unit_id, row.label, shown,
				])
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	rig.h.hud.add_child(panel)
	var player_view: UnitDetailViewModel = UnitDetailViewModel.build(session, drengr)
	panel.open_with(player_view)
	var drawn: Array[DetailStatRow] = panel.get_value_rows()
	var expected: Array[UnitDetailViewModel.ValueRow] = (
			player_view.stat_rows + player_view.combat_rows
	)
	if drawn.size() != expected.size():
		problems.append("%d rows drawn for %d values" % [drawn.size(), expected.size()])
	else:
		for i: int in drawn.size():
			var cells: PackedStringArray = drawn[i].get_texts()
			if cells[0] != expected[i].label or cells[1] != "%d" % [expected[i].value]:
				problems.append("row %d draws %s" % [i, cells])
			elif cells[2] != " ".join(expected[i].sources):
				problems.append("row %d sources '%s'" % [i, cells[2]])
	panel.free()
	_check.call("unit detail (sources): each value's sources are the session's breakdown", (
			problems.is_empty()
	), "; ".join(problems))


# Every unit's type shows as the catalog's display name (BUG-005), the capitalised id only for a
# type the catalog lacks; the panel's summary starts with it.
func _test_names(rig: Rig) -> void:
	var session: CombatSession = rig.h.session
	var wrong: PackedStringArray = []
	for side: CombatFact.CombatSide in [PLAYER, ENEMY]:
		for unit_id: String in session.state.units_of(side):
			var type_id: String = session.state.unit_type_of(unit_id)
			var definition: UnitTypeDefinition = _catalog.enemy_class(type_id)
			if definition == null:
				definition = _catalog.unit_type(type_id)
			var view: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
			if definition == null or view.type_name != definition.display_name:
				wrong.append("%s: '%s'" % [type_id, view.type_name])
	_check.call("unit detail (names): unit types show the catalog's display names", (
			wrong.is_empty()
			and BattleText.type_name("no_such_type") == "No Such Type"
			and BattleText.type_name("") == ""
	), "; ".join(wrong))


# With the Drengr's run record (level 3, 40 XP) the view carries its level, XP, XP per level and
# each growing stat's growth, and the header shows "Lv 3" and the XP; without one, none shows.
# Through the controller, run_units hands the record over.
func _test_run_record(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var drengr: String = _unit_of_type(h.session, "drengr")
	var record: UnitInstance = UnitInstance.new(drengr, "drengr")
	record.level = 3
	record.xp = 40
	var rules: CombatRewardRules = CombatRewardRules.load_default()
	var view: UnitDetailViewModel = UnitDetailViewModel.build(h.session, drengr, record)
	var growths: PackedStringArray = []
	var unit_type: UnitTypeDefinition = _catalog.unit_type("drengr")
	for row: UnitDetailViewModel.ValueRow in view.stat_rows:
		for stat: int in CombatValue.STAT_KEYS:
			if CombatValue.STAT_KEYS[stat] != row.key or not unit_type.growths.has(stat):
				continue
			if row.growth != record.growth(_catalog, stat):
				growths.append("%s %d" % [row.label, row.growth])
	var plain: UnitDetailViewModel = UnitDetailViewModel.build(h.session, drengr)
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	h.hud.add_child(panel)
	panel.open_with(view)
	var with_record: PackedStringArray = panel.get_header().get_texts()
	panel.show_detail(plain)
	var without: PackedStringArray = panel.get_header().get_texts()
	panel.free()
	h.controller.run_units = {drengr: record}
	h.controller.move_cursor(h.session.state.tile_of(drengr))
	h.controller.request_unit_detail()
	var opened: UnitDetailPanel = h.controller.get_detail_panel()
	var through_controller: bool = opened != null and opened.get_view().level == 3
	h.controller.step_back()
	h.controller.run_units = {}
	_check.call("unit detail (run record): level, XP and growths show from the run's unit", (
			view.level == 3
			and view.xp == 40
			and rules != null
			and view.xp_per_level == rules.xp_per_level
			and growths.is_empty()
			and with_record[3] == "Lv 3"
			and with_record[4] == "XP 40 / %d" % [view.xp_per_level]
			and plain.xp == -1
			and without[3].is_empty()
			and through_controller
	), "level %d, xp %d / %d, growths off %s, header %s / %s, controller %s" % [
		view.level, view.xp, view.xp_per_level, growths, with_record, without, through_controller,
	])


# An enemy's view carries its intent as the intents show it and its target rule, none while the
# intents are hidden; the panel's enemy section shows them and hides for a player unit. A signature
# move, when an M1 enemy has one, carries its name and its counter.
func _test_enemy_section(rig: Rig) -> void:
	var session: CombatSession = rig.h.session
	var enemy: String = session.state.units_of(ENEMY)[0]
	var intent: EnemyIntent = session.intents.intent_of(enemy) if session.intents != null else null
	var view: UnitDetailViewModel = UnitDetailViewModel.build(session, enemy)
	var hidden: UnitDetailViewModel = UnitDetailViewModel.build(session, enemy, null, false)
	var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
	rig.h.hud.add_child(panel)
	panel.open_with(view)
	var shown: PackedStringArray = panel.get_enemy_section().get_texts()
	var enemy_visible: bool = panel.get_enemy_section().visible
	panel.show_detail(UnitDetailViewModel.build(session, _unit_of_type(session, "drengr")))
	var player_hidden: bool = not panel.get_enemy_section().visible
	panel.free()
	var expected: String = ""
	if intent != null:
		expected = UnitDetailViewModel.INTENT_TEXT[intent.kind]
	_check.call("unit detail (enemy): intent and target rule as the intents show them", (
			intent != null
			and view.intent_text.begins_with(expected)
			and view.target_rule_text == intent.target_rule_text
			and hidden.intent_text.is_empty()
			and hidden.target_rule_text.is_empty()
			and enemy_visible
			and shown[0] == "Intent: %s" % [view.intent_text]
			and player_hidden
	), "intent '%s' (expected '%s…'), hidden '%s', section %s / %s, lines %s" % [
		view.intent_text, expected, hidden.intent_text, enemy_visible, player_hidden, shown,
	])
	for unit_id: String in session.state.units_of(ENEMY):
		var enemy_class: EnemyClassDefinition = _catalog.enemy_class(
				session.state.unit_type_of(unit_id)
		)
		if enemy_class == null or enemy_class.signature_move == null:
			continue
		var signed: UnitDetailViewModel = UnitDetailViewModel.build(session, unit_id)
		_check.call("unit detail (enemy): a signature move shows its name and text", (
				not signed.signature_name.is_empty() and not signed.signature_text.is_empty()
		), "%s: '%s'" % [unit_id, signed.signature_name])
		return
	print("      (no M1 enemy has a signature move; the capture shows one in play)")


# DETAIL on the first player unit: E and RB step to the next of its side, Q and LB back, wrapping
# from the first to the last; the pop-up's Next steps too; focus stays on Close, the hints list
# Q / E, and Back returns to IDLE as it was. An enemy's detail steps through enemies only.
func _test_stepping(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var players: PackedStringArray = h.session.state.units_of(PLAYER)
	var enemies: PackedStringArray = h.session.state.units_of(ENEMY)
	h.controller.move_cursor(h.session.state.tile_of(players[0]))
	var before: String = _state_line(rig)
	h.controller.request_unit_detail()
	var seen: PackedStringArray = [_shown(rig)]
	_press_key(KEY_E)
	seen.append(_shown(rig))
	_press_pad(JOY_BUTTON_LEFT_SHOULDER)
	seen.append(_shown(rig))
	_press_key(KEY_Q)
	seen.append(_shown(rig))
	_press_pad(JOY_BUTTON_RIGHT_SHOULDER)
	seen.append(_shown(rig))
	var panel: UnitDetailPanel = h.controller.get_detail_panel()
	if panel != null:
		panel.get_header().get_step_buttons()[1].pressed.emit()
	seen.append(_shown(rig))
	var focus_kept: String = _open_problem(rig, seen[-1])
	var live: Array[StringName] = h.controller.get_live_actions()
	h.controller.step_back()
	var after: String = _state_line(rig)
	var last: String = players[players.size() - 1]
	var second: String = players[1 % players.size()]
	var expected: PackedStringArray = [players[0], second, players[0], last, players[0], second]
	h.controller.move_cursor(h.session.state.tile_of(enemies[0]))
	h.controller.request_unit_detail()
	_press_key(KEY_E)
	var enemy_next: String = _shown(rig)
	h.controller.step_back()
	_check.call("unit detail (stepping): Q / E, LB / RB and Next walk its side, wrapping", (
			players.size() > 1
			and seen == expected
			and focus_kept.is_empty()
			and live.has(&"target_prev")
			and live.has(&"target_next")
			and after == before
			and (enemies.size() < 2 or enemy_next == enemies[1])
	), "saw %s, expected %s; %s; live %s; before %s, after %s; enemy next %s" % [
		seen, expected, focus_kept, live, before, after, enemy_next,
	])


# IDLE: a right click on a player unit's tile opens its detail; in MOVE, a right click on an empty
# tile still steps back to IDLE, and one on an enemy opens its detail, the selection kept.
func _test_right_click(rig: Rig) -> void:
	var h: TurnInputCases.Harness = rig.h
	var players: PackedStringArray = h.session.state.units_of(PLAYER)
	var enemy: String = h.session.state.units_of(ENEMY)[0]
	h.controller.move_cursor(_empty_tile(h.session))
	_click(_screen_point(h, h.session.state.tile_of(players[1])), MOUSE_BUTTON_RIGHT)
	var opened: String = _open_problem(rig, players[1])
	h.controller.step_back()
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	_click(_screen_point(h, h.session.state.tile_of(enemy)), MOUSE_BUTTON_RIGHT)
	var on_enemy: String = _open_problem(rig, enemy)
	var kept: bool = h.controller.get_selected_unit() == unit_id
	h.controller.step_back()
	var in_move: bool = h.controller.get_stage() == MOVE
	_click(_screen_point(h, _empty_tile(h.session)), MOUSE_BUTTON_RIGHT)
	var back_to_idle: bool = h.controller.get_stage() == IDLE
	_check.call("unit detail (right click): on a unit it opens its detail; elsewhere it is Back", (
			opened.is_empty()
			and on_enemy.is_empty()
			and kept
			and in_move
			and back_to_idle
	), "%s; %s; selection kept %s, MOVE %s, IDLE %s" % [
		opened, on_enemy, kept, in_move, back_to_idle,
	])


# The unit the open detail shows; empty when none is open.
func _shown(rig: Rig) -> String:
	var panel: UnitDetailPanel = rig.h.controller.get_detail_panel()
	if panel == null or panel.get_view() == null:
		return ""
	return panel.get_view().unit_id


# tile's centre on screen, through the board's camera.
func _screen_point(h: TurnInputCases.Harness, tile: Vector2i) -> Vector2:
	return h.view.get_global_transform_with_canvas() * h.view.tile_to_position(tile)


# Why the detail isn't open on unit_id with Close focused; empty when it is.
func _open_problem(rig: Rig, unit_id: String) -> String:
	var h: TurnInputCases.Harness = rig.h
	var panel: UnitDetailPanel = h.controller.get_detail_panel()
	if h.controller.get_stage() != DETAIL or panel == null:
		return "not open (stage %d)" % [h.controller.get_stage()]
	if panel != h.host.top():
		return "not the top panel"
	if panel.get_view() == null or panel.get_view().unit_id != unit_id:
		return "shows %s, not %s" % [panel.get_view().unit_id if panel.get_view() else "-", unit_id]
	var focus: Control = _root.get_viewport().gui_get_focus_owner()
	if focus != panel.get_close_button():
		return "focus on %s, not Close" % [focus]
	return ""


# The stage, selection, cursor, panels and focus, as one line.
func _state_line(rig: Rig) -> String:
	var h: TurnInputCases.Harness = rig.h
	var focus: Control = _root.get_viewport().gui_get_focus_owner()
	return "stage %d, unit %s, cursor %s, panels %d, focus %s" % [
		h.controller.get_stage(), h.controller.get_selected_unit(), h.controller.get_cursor_tile(),
		h.host.depth(), "-" if focus == null else String(focus.name),
	]


func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


func _press_pad(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


func _click(point: Vector2, button: MouseButton) -> void:
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = button
		click.pressed = is_down
		_root.get_viewport().push_input(click, true)


# Why view isn't the session's for unit_id: the vitals, stats, weapon or effects; empty when it is.
static func _view_problems(
		session: CombatSession, unit_id: String, view: UnitDetailViewModel
) -> PackedStringArray:
	var problems: PackedStringArray = []
	if view == null:
		problems.append("no view")
		return problems
	var unit: CombatUnitState = session.state.unit(unit_id)
	var sheet: StatSheet = session.stats(unit_id)
	if (
			view.hp != unit.hp
			or view.max_hp != sheet.get_int(CombatValue.Key.HP)
			or view.stance != unit.stance
			or view.stance_max != sheet.get_int(CombatValue.Key.STANCE_MAX)
			or view.block != unit.block
	):
		problems.append("vitals")
	# Attack Speed as game-vision.md writes it, on M1's units, which carry no Attack Speed effect.
	var burden: int = maxi(
			sheet.get_int(CombatValue.Key.NET_WEIGHT) - sheet.get_int(CombatValue.Key.CON), 0
	)
	if view.attack_speed != sheet.get_int(CombatValue.Key.SPD) - burden:
		problems.append("attack speed %d" % [view.attack_speed])
	for i: int in HudViewModel.STAT_ROWS.size():
		if view.stat_values[i] != sheet.get_int(HudViewModel.STAT_ROWS[i][1] as int):
			problems.append("stat %s" % [view.stat_names[i]])
	var held: CombatState.WeaponStats = session.state.equipped_weapon(unit_id)
	if held == null and view.weapon != null or held != null and (
			view.weapon == null
			or view.weapon.damage != held.damage
			or view.weapon.profile != (
					WeaponTriangle.Profile.find_key(held.profile) as String
			).capitalize()
			or view.weapon.hit != sheet.get_int(CombatValue.Key.HIT)
	):
		problems.append("weapon")
	var expected: int = 0
	for instance: EffectInstance in session.engine.get_instances():
		var owner: EffectOwner = instance.owner
		if owner == null:
			continue
		var is_held: bool = (
				owner.kind in [EffectOwner.Kind.UNIT, EffectOwner.Kind.ITEM]
				and owner.holder_id == unit_id
		)
		var is_army: bool = (
				owner.kind == EffectOwner.Kind.ARMY
				and unit.side == PLAYER
				and owner.seat == unit.seat
		)
		if is_held or is_army:
			expected += 1
	var shown: int = view.traits.size() + view.heirlooms.size() + view.equipment_effects.size()
	shown += view.pouch_effects.size()
	for line: UnitDetailViewModel.WeaponLine in [view.weapon, view.stowed]:
		if line != null:
			shown += line.effects.size()
	if shown != expected:
		problems.append("%d effect lines, %d carried" % [shown, expected])
	return problems


static func _unit_of_type(session: CombatSession, unit_type: String) -> String:
	for unit_id: String in session.state.units_of(PLAYER):
		if session.state.unit_type_of(unit_id) == unit_type:
			return unit_id
	return ""


static func _empty_tile(session: CombatSession) -> Vector2i:
	var rect: Rect2i = session.layout.get_rect()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var tile: Vector2i = Vector2i(x, y)
			if session.state.occupant_at(tile).is_empty():
				return tile
	return CombatFact.NO_TILE


# turn_input_cases.gd's harness past Start with the HUD (its map area framing the board), the
# forecast and detail scenes, and the unit panel's Details wired as BattleScreen wires it.
func _rig() -> Rig:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("unit detail: the M1 battle begins", false, "begin_battle gave no battle")
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
	h.controller.unit_detail_scene = DETAIL_SCENE
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
	rig.hud.get_unit_panel().details_pressed.connect(h.controller.request_unit_detail)
	h.session.batch_resolved.connect(h.record)
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	return rig


## The harness with the HUD on it.
class Rig:
	extends RefCounted

	## The board, widgets and controller (turn_input_cases.gd).
	var h: TurnInputCases.Harness = null
	## The HUD.
	var hud: BattleHud = null

	## Frees the nodes and closes the run.
	func close() -> void:
		hud.unbind()
		h.close()
