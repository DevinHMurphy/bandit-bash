# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## The forecast's and move preview's cases for tests/ui/run_all.gd (combat UI plan, UI3 row):
## forecast rows against [CombatForecast] for an attack, a staff and a shove; the forecast panel
## as the confirm, its breakdown toggle against explain's stages; weapon cycling with a Sidearm
## unit, the forecast and the command sent; the move preview against [method Darkness.damage_at]
## and [method Intents.preview], at most one per frame under a burst of hovers; and FR-GRID-6, a
## ranged attack forecast from each tile it can be made from. No autoload is named or needed.
##
## [b]The harness[/b] is turn_input_cases.gd's (the board, the HUD widgets and a
## [BattleController] on the M1 battle) with the forecast panel scene set and [MovePreviewMarks]
## on the board, as in the gameplay scene. Cases drive the controller through its public methods
## and the panels' own buttons; cycle_weapon goes through the root viewport as an input action.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/turn_input_cases.gd")

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
const MARKS_SCENE: PackedScene = preload("res://scenes/ui/battle/move_preview_marks.tscn")

# turn_input_cases.gd's seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Player phases a case may drive forward to find what it needs.
const MAX_PHASES: int = 3

# Hovers in the burst: more than one frame's worth, fewer than any unit's move tiles.
const BURST: int = 12

# The stowed weapon the cycling case gives the Hakkapel: game-vision.md's Simple Sword.
const STOWED_ID: String = "test:stowed_sword"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const CONFIRM: BattleController.Stage = BattleController.Stage.CONFIRM
const TARGET: BattleController.Stage = BattleController.Stage.TARGET
const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK
const STAFF: TurnInputModel.ActionKind = TurnInputModel.ActionKind.STAFF
const SHOVE: TurnInputModel.ActionKind = TurnInputModel.ActionKind.SHOVE

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the harness is added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("forecast: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_rows_match_forecast()
	_test_panel_confirms()
	_test_weapon_cycle()
	_test_move_preview()
	_test_preview_marks_widget()
	_test_ranged_origins()


# For the first attack, staff use and shove the M1 battle offers, the model's rows are the
# forecast's numbers, and its preview is the command's own.
func _test_rows_match_forecast() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var found: Dictionary[int, UnitTurnCommand] = {}
	for _phase: int in MAX_PHASES:
		_collect(h.session, found)
		if found.size() == 3 or h.session.is_finished:
			break
		_wait_phase(h)
	for kind: int in [ATTACK, STAFF, SHOVE]:
		var label: String = TurnInputModel.ACTION_LABELS[kind]
		if not found.has(kind):
			_check.call("forecast rows: %s found in the M1 battle" % [label], false, "none")
			continue
		var command: UnitTurnCommand = found[kind]
		var model: ForecastViewModel = ForecastViewModel.build(h.session, command)
		var direct: CombatForecast.Forecast = _direct(h.session, command)
		var problems: PackedStringArray = _row_problems(h.session, model, direct)
		_check.call("forecast rows: %s's rows are CombatForecast's numbers" % [label], (
				problems.is_empty() and model.forecast.is_legal
		), "; ".join(problems))
		_check.call("forecast rows: %s previews the command's own facts" % [label], (
				_fact_lines(model.forecast) == _fact_lines(direct)
				and not _fact_lines(direct).is_empty()
		), "%d facts against %d" % [model.forecast.facts.size(), direct.facts.size()])
	h.close()


# Attack, Staff and Shove confirm on the forecast panel, showing the model's rows; the breakdown
# toggle shows explain's stages; Back steps to the target picker; Confirm sends the command.
func _test_panel_confirms() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var steps: PackedStringArray = []
	for kind: TurnInputModel.ActionKind in [STAFF, SHOVE]:
		var pick: Array = _find(h.session, kind)
		if pick.is_empty():
			steps.append("no %s" % [TurnInputModel.ACTION_LABELS[kind]])
			continue
		var panel: ForecastPanel = _open_forecast(h, pick, steps)
		if panel != null:
			var model: ForecastViewModel = panel.get_model()
			var expected: ForecastViewModel.Kind = (
					ForecastViewModel.Kind.STAFF if kind == STAFF else ForecastViewModel.Kind.SHOVE
			)
			_expect(steps, "%s kind" % [kind], model.kind == expected)
			_expect(steps, "%s rows shown" % [kind], _rows_shown(panel) == _rows_of(model))
		h.controller.step_back()
		h.controller.step_back()
		h.controller.step_back()
		h.controller.step_back()
	_check.call("forecast panel: Staff and Shove confirm on their forecast", steps.is_empty(), (
			"; ".join(steps)
	))

	steps.clear()
	var attack: Array = _find(h.session, ATTACK)
	var panel: ForecastPanel = null
	if attack.is_empty():
		steps.append("no attack on turn 1")
	else:
		panel = _open_forecast(h, attack, steps)
	if panel == null:
		_check.call("forecast panel: an attack confirms on its forecast", false, "; ".join(steps))
		h.close()
		return
	var model: ForecastViewModel = panel.get_model()
	var direct: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			h.session.engine, model.command
	)
	_expect(steps, "rows shown are the model's", _rows_shown(panel) == _rows_of(model))
	_expect(steps, "Confirm has focus", (
			_root.get_viewport().gui_get_focus_owner() == panel.get_confirm_button()
	))
	_check.call("forecast panel: an attack confirms on its forecast, Confirm focused", (
			steps.is_empty() and h.controller.get_stage() == CONFIRM
	), "; ".join(steps))

	var closed: bool = not panel.is_breakdown_showing()
	panel.set_breakdown_open(true)
	var shown: PackedStringArray = panel.get_breakdown().get_texts()
	var expected_actor: String = "%s\n%s" % [
		model.actor_label, "\n".join(direct.attacker.breakdown.to_text().split("; ")),
	]
	_check.call("breakdown: closed at first; the toggle shows the hit's stages, as explain lists", (
			closed
			and panel.is_breakdown_showing()
			and direct.attacker.breakdown != null
			and shown[0] == expected_actor
			and direct.attacker.breakdown.to_text().split("; ").size() >= 3
	), "%s | expected %s" % [shown[0].replace("\n", " / "), expected_actor.replace("\n", " / ")])

	h.controller.step_back()
	var backed: bool = h.controller.get_stage() == TARGET and h.host.top() is TargetPicker
	_check.call("forecast panel: cancel steps back to the target picker", backed, (
			"stage %d" % [h.controller.get_stage()]
	))
	panel = _open_forecast(h, attack, steps)
	if panel == null:
		h.close()
		return
	var sent: UnitTurnCommand = panel.get_model().command
	panel.get_confirm_button().pressed.emit()
	BattleViewCases.settle(h.view)
	var batch: CombatSession.FactBatch = h.last_batch()
	_check.call("forecast panel: Confirm sends the command forecast", (
			batch != null
			and not batch.is_rejected()
			and batch.actor_id == sent.actor_id
			and batch.target_id == sent.target_id
			and batch.label == sent.get_label()
	), "%s" % [h.batch_labels()])
	h.close()


# A Hakkapel with Sidearm and a stowed sword: the attack's targets in reach of both weapons cycle
# between them on cycle_weapon, the forecast follows, and Confirm sends the stowed weapon's
# command, which Sidearm's free swap resolves.
func _test_weapon_cycle() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var hakkapel: String = _unit_of_type(h.session, "Hakkapel")
	if hakkapel.is_empty():
		_check.call("cycle: the M1 battle has a Hakkapel", false, "")
		h.close()
		return
	_give_sidearm(h.session, hakkapel)
	var pick: Array = []
	for _phase: int in MAX_PHASES:
		pick = _find(h.session, ATTACK, hakkapel, 2)
		if not pick.is_empty() or h.session.is_finished:
			break
		_wait_phase(h)
	if pick.is_empty():
		_check.call("cycle: the Hakkapel reaches a target with both weapons", false, "")
		h.close()
		return
	var steps: PackedStringArray = []
	var panel: ForecastPanel = _open_forecast(h, pick, steps)
	if panel == null:
		_check.call("cycle: the forecast opens", false, "; ".join(steps))
		h.close()
		return
	var target: TurnInputModel.TargetOption = pick[3]
	var first: ForecastViewModel = panel.get_model()
	_press(&"cycle_weapon")
	var second: ForecastViewModel = panel.get_model()
	var expected: ForecastViewModel = ForecastViewModel.build(
			h.session, target.commands[1] as UnitTurnCommand, 1, 2
	)
	_check.call("cycle: cycle_weapon moves the forecast to the stowed weapon", (
			first.weapon_index == 0
			and first.command.weapon_id.is_empty()
			and first.can_cycle()
			and second.weapon_index == 1
			and second.command.weapon_id == STOWED_ID
			and _rows_of(second) == _rows_of(expected)
			and _rows_shown(panel) == _rows_of(expected)
			and second.row("Weapon").actor != first.row("Weapon").actor
	), "%s -> %s" % [first.row("Weapon").actor, second.row("Weapon").actor])
	_check.call("cycle: the command Confirm sends follows the forecast", (
			h.controller.get_confirm_command() == second.command
			and _wire(second.command) == _wire(target.commands[1])
	), "%s against %s" % [_wire(h.controller.get_confirm_command()), _wire(target.commands[1])])
	_press(&"cycle_weapon")
	var wrapped: bool = (
			panel.get_model().weapon_index == 0
			and h.controller.get_confirm_command() == panel.get_model().command
			and _wire(h.controller.get_confirm_command()) == _wire(target.commands[0])
	)
	panel.get_cycle_button().pressed.emit()
	_check.call("cycle: it wraps, and Next weapon cycles as the key does", (
			wrapped and panel.get_model().weapon_index == 1
	))
	panel.get_confirm_button().pressed.emit()
	BattleViewCases.settle(h.view)
	var batch: CombatSession.FactBatch = h.last_batch()
	var swapped: bool = false
	if batch != null:
		for fact: CombatFact in batch.facts:
			swapped = swapped or fact.kind == CombatFact.Kind.WEAPON_SWAPPED
	_check.call("cycle: confirming with the stowed weapon swaps it in for free and attacks", (
			batch != null
			and not batch.is_rejected()
			and swapped
			and (not h.session.state.has_unit(hakkapel)
					or h.session.state.unit(hakkapel).equipped_weapon_id == STOWED_ID)
	), "%s" % [h.batch_labels()])

	var single: Array = _find(h.session, ATTACK, "", 1)
	var inert: bool = true
	if not single.is_empty() and (single[3] as TurnInputModel.TargetOption).commands.size() == 1:
		var other: ForecastPanel = _open_forecast(h, single, steps)
		inert = (
				other != null
				and not other.get_model().can_cycle()
				and not h.controller.cycle_weapon()
				and other.get_model().weapon_index == 0
		)
	_check.call("cycle: with one weapon cycle_weapon is inert and Next weapon hidden", inert, (
			"; ".join(steps)
	))
	h.close()


# Hovering move tiles only asks for previews; one frame runs one, the newest; its marks are
# Darkness.damage_at and the enemies Intents.preview re-plans; leaving the move tiles clears it.
func _test_move_preview() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var marks: MovePreviewMarks = h.controller.move_preview_marks
	var unit_id: String = ""
	for candidate: String in TurnInputModel.acting_units(h.session, 0):
		if TurnInputModel.move_tiles(h.session, candidate).size() > BURST:
			unit_id = candidate
			break
	if unit_id.is_empty():
		_check.call("preview: a unit with enough move tiles", false, "")
		h.close()
		return
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	var queue: MovePreview.Queue = h.controller.get_preview_queue()
	h.controller.run_preview_frame()
	var computed: int = queue.computed
	var tiles: Array[Vector2i] = TurnInputModel.move_tiles(h.session, unit_id)
	tiles.reverse()
	var last: Vector2i = CombatFact.NO_TILE
	for i: int in BURST:
		last = tiles[i]
		h.controller.move_cursor(last)
	var hovered_only: bool = queue.computed == computed and queue.has_pending()
	var ran: bool = h.controller.run_preview_frame()
	var again: bool = h.controller.run_preview_frame()
	var shown_tile: String = "none" if marks.get_shown() == null else str(marks.get_shown().tile)
	_check.call("preview: a burst of %d hovers runs one preview in a frame, the last hover's" % [
		BURST,
	], (
			hovered_only
			and ran
			and not again
			and queue.computed == computed + 1
			and marks.get_shown() != null
			and marks.get_shown().tile == last
	), "computed %d -> %d, shown %s, last %s" % [computed, queue.computed, shown_tile, last])

	var shown: MovePreview = marks.get_shown()
	var damage: int = Darkness.damage_at(h.session.engine, unit_id, last)
	var expected_text: String = "" if damage == 0 else marks.damage_text % [damage]
	_check.call("preview: the number on the tile is Darkness.damage_at's", (
			shown != null
			and shown.darkness_damage == damage
			and marks.get_damage_text() == expected_text
	), "damage %d, shown '%s'" % [damage, marks.get_damage_text()])

	var replanned: Intents = Intents.preview(h.session, unit_id, last)
	var changed: PackedStringArray = []
	for enemy_id: String in h.session.state.units_of(ENEMY):
		if MovePreview.intent_differs(
				h.session.intents.intent_of(enemy_id), replanned.intent_of(enemy_id)
		):
			changed.append(enemy_id)
	_check.call("preview: the intents are Intents.preview's, each changed enemy marked", (
			shown != null
			and shown.intents != null
			and _intent_lines(shown.intents) == _intent_lines(replanned)
			and marks.get_marked_enemies() == changed
			and shown.changed_enemies == changed
	), "marked %s, changed %s" % [marks.get_marked_enemies(), changed])

	var changed_somewhere: int = 0
	for tile: Vector2i in tiles:
		var preview: MovePreview = MovePreview.compute(h.session, unit_id, tile)
		if not preview.changed_enemies.is_empty():
			changed_somewhere += 1
	print("      (preview: %d of %d move tiles change an enemy's intent)" % [
		changed_somewhere, tiles.size(),
	])

	var off: Vector2i = h.session.state.tile_of(h.session.state.units_of(ENEMY)[0])
	h.controller.move_cursor(off)
	var cleared: bool = marks.get_shown() == null and not queue.has_pending()
	h.controller.move_cursor(last)
	h.controller.step_back()
	var left: bool = marks.get_shown() == null and not h.controller.run_preview_frame()
	_check.call("preview: off the move tiles, and on leaving MOVE, it clears", cleared and left)
	h.close()


# The marks widget alone: a number for damage, none for 0, and one mark per changed enemy.
func _test_preview_marks_widget() -> void:
	var marks: MovePreviewMarks = MARKS_SCENE.instantiate()
	_root.add_child(marks)
	var preview: MovePreview = MovePreview.new()
	preview.darkness_damage = 5
	preview.changed_enemies = PackedStringArray(["e1", "e2"])
	var positions: Array[Vector2] = [Vector2(32.0, 0.0), Vector2(64.0, 0.0)]
	marks.show_preview(preview, Vector2.ZERO, positions)
	var with_damage: bool = (
			marks.get_damage_text() == "-5"
			and marks.get_marked_enemies() == preview.changed_enemies
	)
	var dry: MovePreview = MovePreview.new()
	var no_positions: Array[Vector2] = []
	marks.show_preview(dry, Vector2.ZERO, no_positions)
	var without: bool = marks.get_damage_text().is_empty() and marks.get_marked_enemies().is_empty()
	_check.call("preview marks: a number for darkness damage, none on a dry tile, marks reused", (
			with_damage and without
	))
	marks.free()


# FR-GRID-6: a target a ranged unit can hit from several tiles is forecast from each tile's own
# command; when the distance differs (the Archer's Volley at maximum range), so does the forecast.
func _test_ranged_origins() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var archer: String = _unit_of_type(h.session, "Archer")
	var problems: PackedStringArray = []
	var pairs: int = 0
	var differing: int = 0
	for _phase: int in MAX_PHASES:
		if archer.is_empty() or h.session.is_finished or not h.session.state.has_unit(archer):
			break
		var by_target: Dictionary[String, Array] = {}
		for tile: Vector2i in TurnInputModel.move_tiles(h.session, archer):
			var path: Array[Vector2i] = TurnInputModel.path_to(h.session, archer, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					h.session, archer, path
			):
				if option.kind != ATTACK:
					continue
				for target: TurnInputModel.TargetOption in option.targets:
					var list: Array = by_target.get(target.target_id, [])
					list.append([tile, target.command])
					by_target[target.target_id] = list
		for target_id: String in by_target:
			var seen: Dictionary[int, ForecastViewModel] = {}
			for entry: Array in by_target[target_id]:
				var tile: Vector2i = entry[0]
				var command: UnitTurnCommand = entry[1]
				var model: ForecastViewModel = ForecastViewModel.build(h.session, command)
				var attacker: CombatForecast.UnitOutcome = model.forecast.unit(archer)
				if attacker == null or attacker.tile_after != tile:
					var from: String = str(attacker.tile_after) if attacker != null else "?"
					problems.append("%s: forecast from %s, not %s" % [target_id, from, tile])
				var distance: int = h.session.state.grid.distance(
						tile, h.session.state.tile_of(target_id)
				)
				if not seen.has(distance):
					seen[distance] = model
			pairs += by_target[target_id].size()
			if seen.size() > 1:
				var damages: Dictionary[String, bool] = {}
				for distance: int in seen:
					damages[seen[distance].row("Damage").actor] = true
				if damages.size() > 1:
					differing += 1
		if differing > 0:
			break
		_wait_phase(h)
	print("      (FR-GRID-6: %d attack options; %d targets forecast differently by range)" % [
		pairs, differing,
	])
	_check.call("FR-GRID-6: each tile's attack is forecast from that tile", (
			problems.is_empty() and pairs > 0
	), "; ".join(problems.slice(0, 3)))
	_check.call("FR-GRID-6: one target, two ranges, two forecasts (Volley at maximum range)", (
			differing > 0
	), "%d options" % [pairs])
	h.close()


# --- Fixtures --------------------------------------------------------------------------------


# turn_input_cases.gd's harness, with the forecast panel scene and the move preview marks set, past
# the opening swap window's Start.
func _harness() -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("forecast: the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	var marks: MovePreviewMarks = MARKS_SCENE.instantiate()
	h.view.add_child(marks)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
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
	h.controller.move_preview_marks = marks
	_root.add_child(h.controller)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	h.session.batch_resolved.connect(h.record)
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	return h


# Every acting unit waits where it stands, then End Turn; the enemies close in meanwhile.
func _wait_phase(h: TurnInputCases.Harness) -> void:
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	if not h.session.is_finished:
		_send(h, EndTurnCommand.new(0))


func _send(h: TurnInputCases.Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)


# The first attack, staff use and shove TurnInputModel offers any acting unit, by kind, into found.
func _collect(session: CombatSession, found: Dictionary[int, UnitTurnCommand]) -> void:
	for kind: TurnInputModel.ActionKind in [ATTACK, STAFF, SHOVE]:
		if found.has(kind):
			continue
		var pick: Array = _find(session, kind)
		if not pick.is_empty():
			found[kind] = (pick[3] as TurnInputModel.TargetOption).command


# The first [unit_id, tile, option, target] of kind TurnInputModel offers, for only_unit when set,
# whose target has at least min_weapons commands; empty when none.
func _find(
		session: CombatSession,
		kind: TurnInputModel.ActionKind,
		only_unit: String = "",
		min_weapons: int = 1
) -> Array:
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		if not only_unit.is_empty() and unit_id != only_unit:
			continue
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
					session, unit_id, path
			):
				if option.kind != kind:
					continue
				for target: TurnInputModel.TargetOption in option.targets:
					if target.commands.size() >= min_weapons:
						return [unit_id, tile, option, target]
	return []


# Walks the controller from IDLE to CONFIRM for pick ([unit_id, tile, option, target]) with the
# panels' own rows; the forecast panel on top, or null with the problem in steps.
func _open_forecast(
		h: TurnInputCases.Harness, pick: Array, steps: PackedStringArray
) -> ForecastPanel:
	var unit_id: String = pick[0]
	var tile: Vector2i = pick[1]
	var option: TurnInputModel.ActionOption = pick[2]
	var target: TurnInputModel.TargetOption = pick[3]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	h.controller.confirm_tile(tile)
	var menu: ActionMenu = h.host.top() as ActionMenu
	if menu == null:
		steps.append("no action menu for %s at %s" % [unit_id, tile])
		return null
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == option.kind:
			menu.get_rows()[i].pressed.emit()
			break
	var picker: TargetPicker = h.host.top() as TargetPicker
	if picker == null:
		steps.append("no target picker for %s" % [option.label])
		return null
	var targets: Array[TurnInputModel.TargetOption] = picker.get_options()
	for i: int in targets.size():
		if targets[i].target_id == target.target_id:
			picker.get_rows()[i].pressed.emit()
			break
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	if panel == null or h.controller.get_stage() != CONFIRM:
		steps.append("no forecast panel for %s on %s" % [option.label, target.target_id])
	return panel


# A Sidearm trait and a stowed Simple Sword for unit_id, set on the session before any command, as
# a loadout would (test setup only; the UI never does this).
func _give_sidearm(session: CombatSession, unit_id: String) -> void:
	var sword: CombatState.WeaponStats = CombatState.WeaponStats.new()
	sword.id = STOWED_ID
	sword.label = "Stowed Sword"
	sword.weapon_type = "sword"
	sword.damage = 5
	sword.atk_x = 1
	sword.profile = WeaponTriangle.Profile.NIMBLE
	sword.range_min = 1
	sword.range_max = 1
	sword.hit = 80
	sword.crit_x = 3.0
	sword.weight = 8
	session.state.add_weapon(sword)
	session.state.unit(unit_id).stowed_weapon_id = STOWED_ID
	session.state.load_bases(session.engine, unit_id)
	var grant: SetPermission = SetPermission.new()
	grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
	grant.allow = true
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = "test_sidearm"
	definition.operations.append(grant)
	var state: CombatState = session.state
	var owner: EffectOwner = EffectOwner.for_unit(
			unit_id, state.seat_of(unit_id), state.side_of(unit_id)
	)
	session.engine.register(EffectInstance.new(
			"test:sidearm", definition, owner, Modifier.SourceKind.UNIT_TRAIT, "test:sidearm"
	))


static func _unit_of_type(session: CombatSession, label: String) -> String:
	for unit_id: String in session.state.units_of(PLAYER):
		if session.describe(unit_id).contains("(%s)" % [label]):
			return unit_id
	return ""


static func _direct(session: CombatSession, command: UnitTurnCommand) -> CombatForecast.Forecast:
	match command.action:
		UnitTurnCommand.Action.ATTACK:
			return CombatForecast.exchange(session.engine, command)
		UnitTurnCommand.Action.STAFF:
			return CombatForecast.staff(session.engine, command)
	return CombatForecast.shove(session.engine, command)


# Why model's rows aren't direct's numbers; empty when they are. Checks each side's cells against
# the forecast's fields, formatted as the panel shows them.
static func _row_problems(
		session: CombatSession, model: ForecastViewModel, direct: CombatForecast.Forecast
) -> PackedStringArray:
	var problems: PackedStringArray = []
	var expect: Dictionary[String, Array] = {}
	var target_id: String = direct.target_id
	for row_label: String in ["HP", "Block", "Stance"]:
		var cells: Array = []
		for unit_id: String in [direct.actor_id, target_id]:
			var outcome: CombatForecast.UnitOutcome = direct.unit(unit_id)
			match row_label:
				"HP":
					cells.append("%d → %d%s" % [
						outcome.hp_before, outcome.hp_after,
						" (defeated)" if outcome.is_defeated else "",
					])
				"Block":
					cells.append(ForecastViewModel.NONE_TEXT if outcome.is_defeated else (
							"%d → %d" % [outcome.block_before, outcome.block_after]
					))
				"Stance":
					cells.append(ForecastViewModel.NONE_TEXT if outcome.is_defeated else (
							"%d → %d%s" % [
								outcome.stance_before, outcome.stance_after,
								" (Exposed)" if outcome.stance_after == 0 else "",
							]
					))
		expect[row_label] = cells
	if direct is CombatForecast.ExchangeForecast:
		var exchange: CombatForecast.ExchangeForecast = direct
		var hits: Array = []
		var damages: Array = []
		var crits: Array = []
		var strikes: Array = []
		var effective: Array = []
		for side: CombatForecast.SideForecast in [exchange.attacker, exchange.defender]:
			var attacks: bool = side.turns > 0
			hits.append("%d%%" % [side.hit] if attacks else ForecastViewModel.NONE_TEXT)
			var damage: String = "%d" % [side.damage] if side.damage >= 0 else ""
			damages.append(ForecastViewModel.NONE_TEXT if damage.is_empty() else damage)
			crits.append("%d%%" % [side.crit_chance] if attacks else ForecastViewModel.NONE_TEXT)
			strikes.append(
					"%d × %d" % [side.attacks_per_turn, side.turns]
					if attacks else ForecastViewModel.NONE_TEXT
			)
			effective.append(ForecastViewModel.NONE_TEXT if side.breakdown == null else (
					"Yes" if side.breakdown.stages.is_effective else "No"
			))
		expect["Hit"] = hits
		expect["Damage"] = damages
		expect["Crit"] = crits
		expect["Strikes"] = strikes
		expect["Effective"] = effective
		var own: CombatState.WeaponStats = session.state.weapon(exchange.attacker.weapon_id)
		var theirs: CombatState.WeaponStats = session.state.weapon(exchange.defender.weapon_id)
		if own != null and theirs != null:
			var result: WhileMatchupCondition.Matchup = WeaponTriangle.matchup(
					own.profile, theirs.profile
			)
			expect["Triangle"] = [
				ForecastViewModel.MATCHUP_TEXT[result],
				ForecastViewModel.MATCHUP_TEXT[WeaponTriangle.mirror(result)],
			]
	elif direct is CombatForecast.StaffForecast:
		var staff: CombatForecast.StaffForecast = direct
		var given: PackedStringArray = []
		for recipient: CombatForecast.Recipient in staff.recipients:
			if recipient.block_gained > 0:
				given.append("Block +%d" % [recipient.block_gained])
			if recipient.healed > 0:
				given.append("HP +%d" % [recipient.restored])
		expect["Staff"] = [model.row("Staff").actor, ", ".join(given)]
		if given.is_empty():
			problems.append("the staff gives nothing")
	elif direct is CombatForecast.ShoveForecast:
		var cells: Array = []
		for unit_id: String in [direct.actor_id, target_id]:
			var outcome: CombatForecast.UnitOutcome = direct.unit(unit_id)
			cells.append("stays" if outcome.tile_after == outcome.tile_before else (
					"%s → %s" % [outcome.tile_before, outcome.tile_after]
			))
		expect["Tile"] = cells
	for row_label: String in expect:
		var row: ForecastViewModel.Row = model.row(row_label)
		var cells: Array = expect[row_label]
		if row == null:
			problems.append("no %s row" % [row_label])
		elif row.actor != cells[0] or row.target != cells[1]:
			problems.append("%s: %s | %s, expected %s | %s" % [
				row_label, row.actor, row.target, cells[0], cells[1],
			])
	return problems


# What a unit-turn command would send: its action, target, weapon and path.
static func _wire(command: Command) -> String:
	var turn: UnitTurnCommand = command as UnitTurnCommand
	if turn == null:
		return "none"
	return "%s %s %s '%s' %s" % [
		turn.actor_id, turn.action, turn.target_id, turn.weapon_id, turn.path,
	]


static func _fact_lines(forecast: CombatForecast.Forecast) -> PackedStringArray:
	var lines: PackedStringArray = []
	for fact: CombatFact in forecast.facts:
		lines.append(fact.to_log_line())
	return lines


static func _intent_lines(intents: Intents) -> PackedStringArray:
	var lines: PackedStringArray = []
	for intent: EnemyIntent in intents.enemies:
		lines.append(intent.describe())
	return lines


static func _rows_of(model: ForecastViewModel) -> PackedStringArray:
	var lines: PackedStringArray = []
	for row: ForecastViewModel.Row in model.rows:
		lines.append("%s|%s|%s" % [row.label, row.actor, row.target])
	return lines


static func _rows_shown(panel: ForecastPanel) -> PackedStringArray:
	var lines: PackedStringArray = []
	for row: ForecastRow in panel.get_rows():
		lines.append("|".join(row.get_texts()))
	return lines


# --- Input -----------------------------------------------------------------------------------


func _press(action: StringName) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


func _expect(problems: PackedStringArray, step: String, passed: bool) -> void:
	if not passed:
		problems.append(step)
