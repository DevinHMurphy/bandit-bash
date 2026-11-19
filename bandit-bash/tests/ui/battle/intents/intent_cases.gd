# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_cases.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Enemy information's cases for the ui/board suite (combat UI plan, UI4 row, question 10): each
## enemy's intent icon, its target rule on hover (the class's first clause, and the darkness's
## after arrival), the numbered lines in [EnemyPlan] order to each target, the danger overlay
## against [DangerZone] (off by default, toggled by R, shown in the opening swap window with no
## intents there, beside an enemy's own range), and the move preview's re-planned intents against
## [method Intents.preview], reverting when the hover clears, and the picked tile's kept through
## the action until Cancel (question 35 (1)); Clouded Sight hiding every intent but not the danger
## zone, and the USE_OBJECT icon with its line to the object (UI12). No autoload is named or
## needed.
##
## [b]The harness[/b] is turn_input_cases.gd's (the board, the HUD widgets and a
## [BattleController] on the M1 battle) with the [IntentDisplay] and [MovePreviewMarks] on the
## board, as in the gameplay scene. R goes through the root viewport as a key press.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

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
const MARKS_SCENE: PackedScene = preload("res://ui/battle/board/move_preview_marks.tscn")
const DISPLAY_SCENE: PackedScene = preload("res://ui/battle/intents/intent_display.tscn")

# turn_input_cases.gd's seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Previews the preview case computes at most while looking for a tile that changes an intent.
const MAX_SEARCH: int = 60

# The darkness's rule text (enemy_intent.gd), as the player reads it after arrival.
const DARKNESS_RULE: String = "Nearest foe"

const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const IDLE: BattleController.Stage = BattleController.Stage.IDLE
const SWAP: BattleController.Stage = BattleController.Stage.SWAP
const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const CONFIRM: BattleController.Stage = BattleController.Stage.CONFIRM

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
		_check.call("intents: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_swap_window()
	_test_icons()
	_test_rule_text()
	_test_lines()
	_test_danger_toggle()
	_test_preview()
	_test_preview_kept_after_walk()
	_test_clouded_sight()
	_test_object_intent()


# Clouded Sight on seat 0 (events.md): the session still plans intents, but no icon, line or
# rule shows, before or after a move preview's hover or an enemy phase; R still draws exactly
# DangerZone's tiles. The same battle without it shows the icons.
func _test_clouded_sight() -> void:
	var h: TurnInputCases.Harness = _harness(true, "clouded_sight")
	if h == null:
		return
	var display: IntentDisplay = h.controller.intent_display
	var overlay: TileOverlay = h.view.get_danger_overlay()
	var planned: int = 0 if h.session.intents == null else h.session.intents.enemies.size()
	var hidden_at_start: bool = (
			h.controller.are_intents_hidden()
			and display.shown_icons().is_empty()
			and display.shown_lines().is_empty()
	)
	_press_r()
	var zone: Array[Vector2i] = _zone_tiles(h.session)
	var zone_shown: bool = not zone.is_empty() and overlay.shown_tiles() == zone
	var enemy_id: String = h.session.state.units_of(ENEMY)[0]
	display.set_hovered(enemy_id)
	var no_rule: bool = display.get_rule_text().is_empty()
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	h.controller.confirm_tile(h.session.state.tile_of(unit_id))
	for option: Vector2i in TurnInputModel.move_tiles(h.session, unit_id):
		if option != h.session.state.tile_of(unit_id):
			h.controller.move_cursor(option)
			break
	h.controller.run_preview_frame()
	h.controller.get_preview_queue().wait()
	h.controller.run_preview_frame()
	var hidden_in_preview: bool = display.shown_icons().is_empty()
	h.controller.step_back()
	for acting: String in TurnInputModel.acting_units(h.session, 0):
		_send(h, UnitTurnCommand.new(0, acting, UnitTurnCommand.Action.WAIT))
	_send(h, EndTurnCommand.new(0))
	var hidden_after: bool = h.session.is_finished or display.shown_icons().is_empty()
	_check.call("clouded sight: intents planned but no icon, line or rule shows", (
			planned > 0 and hidden_at_start and no_rule and hidden_in_preview and hidden_after
	), "planned %d, start %s, rule '%s', preview %s, after %s" % [
		planned, hidden_at_start, display.get_rule_text(), hidden_in_preview, hidden_after,
	])
	_check.call("clouded sight: R still draws exactly DangerZone's tiles", zone_shown, (
			"%d of %d tiles" % [overlay.shown_tiles().size(), zone.size()]
	))
	h.close()
	var plain: TurnInputCases.Harness = _harness(true)
	if plain == null:
		return
	_check.call("clouded sight: without it the same battle shows its icons", (
			not plain.controller.are_intents_hidden()
			and not plain.controller.intent_display.shown_icons().is_empty()
	))
	plain.close()


# A USE_OBJECT intent on M1's first map object: its icon draws the object glyph in its own theme
# style, and its numbered line runs to the object's tile (the view model finds objects as targets).
func _test_object_intent() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var state: CombatState = h.session.state
	var object_id: String = ""
	for found: String in state.map.objects:
		object_id = found
		break
	var enemy_id: String = state.units_of(ENEMY)[0]
	if object_id.is_empty():
		_check.call("object intent: M1 has a map object", false)
		h.close()
		return
	var intent: EnemyIntent = EnemyIntent.new()
	intent.unit_id = enemy_id
	intent.kind = EnemyIntent.Kind.USE_OBJECT
	intent.target_id = object_id
	intent.tile = state.tile_of(enemy_id)
	var intents: Intents = Intents.new()
	intents.enemies.append(intent)
	var model: IntentViewModel = IntentViewModel.build(h.session, intents, false)
	var display: IntentDisplay = h.controller.intent_display
	display.show_intents(model, h.view.tile_to_position)
	var icon: IntentIcon = display.icon_of(enemy_id)
	var lines: Array[IntentLine] = display.shown_lines()
	var object_tile: Vector2i = state.map.object(object_id).tile
	_check.call("object intent: USE_OBJECT draws its own glyph", (
			icon != null
			and icon.get_glyph_text() == icon.use_object_glyph
			and icon.glyph_of(EnemyIntent.Kind.USE_OBJECT) != icon.glyph_of(EnemyIntent.Kind.GUARD)
			and (icon.get_node("%GlyphLabel") as Label).theme_type_variation
			== &"IntentUseObjectGlyph"
	), "glyph '%s'" % ["none" if icon == null else icon.get_glyph_text()])
	_check.call("object intent: its line runs to the object's tile", (
			model.entries.size() == 1
			and model.entries[0].target_tile == object_tile
			and (object_tile == intent.tile or (
				lines.size() == 1 and lines[0].target_tile == object_tile
			))
	), "target %s, object %s, %d lines" % [
		model.entries[0].target_tile if not model.entries.is_empty() else CombatFact.NO_TILE,
		object_tile, lines.size(),
	])
	h.close()


# Question 35 (1): the picked tile's move preview stays from WALK through ACTION, TARGET and
# CONFIRM, its danger zone with it, so no intent line points at the tile the unit left; Cancel's
# snap back to MOVE clears it, the session's intents and zone return, and no frame brings the
# preview back while the cursor stays.
func _test_preview_kept_after_walk() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var state: CombatState = h.session.state
	var display: IntentDisplay = h.controller.intent_display
	# A unit some enemy targets, so a live line points at its tile; else the first that can act.
	var unit_id: String = ""
	for intent: EnemyIntent in h.session.intents.enemies:
		if not intent.target_id.is_empty() and TurnInputModel.can_act(h.session, intent.target_id):
			unit_id = intent.target_id
			break
	var acting: PackedStringArray = TurnInputModel.acting_units(h.session, 0)
	if unit_id.is_empty() and not acting.is_empty():
		unit_id = acting[0]
	var origin: Vector2i = state.tile_of(unit_id)
	# A move tile from which the unit has a targeted action, so TARGET and CONFIRM are reached.
	var tile: Vector2i = CombatFact.NO_TILE
	var targeted: TurnInputModel.ActionKind = TurnInputModel.ActionKind.WAIT
	for option_tile: Vector2i in TurnInputModel.move_tiles(h.session, unit_id):
		if option_tile == origin:
			continue
		var path: Array[Vector2i] = TurnInputModel.path_to(h.session, unit_id, option_tile)
		for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
				h.session, unit_id, path
		):
			if option.has_targets():
				tile = option_tile
				targeted = option.kind
				break
		if tile != CombatFact.NO_TILE:
			break
	if unit_id.is_empty() or tile == CombatFact.NO_TILE:
		_check.call("kept preview: a unit with a targeted action off its own tile", false)
		h.close()
		return
	var live: PackedStringArray = _model_texts(display.get_model())
	h.controller.toggle_danger_zone()
	h.controller.confirm_tile(origin)
	h.controller.move_cursor(tile)
	h.controller.run_preview_frame()
	h.controller.get_preview_queue().wait()
	h.controller.run_preview_frame()
	h.controller.confirm_tile(tile)
	var replanned: Intents = Intents.preview(h.session, unit_id, tile)
	var expected: PackedStringArray = _entry_texts(h.session, replanned, unit_id, tile)
	var zone: Array[Vector2i] = []
	zone.assign(replanned.danger.combined.keys())
	zone.sort_custom(MapLayout.is_before)
	var problems: PackedStringArray = []
	_kept_problems(h, "WALK", origin, unit_id, expected, zone, problems)
	BattleViewCases.arrive(h.view)
	_kept_problems(h, "ACTION", origin, unit_id, expected, zone, problems)
	var menu: ActionMenu = h.host.top() as ActionMenu
	var options: Array[TurnInputModel.ActionOption] = []
	if menu != null:
		options = menu.get_options()
	for i: int in options.size():
		if options[i].kind == targeted:
			menu.get_rows()[i].pressed.emit()
			break
	_kept_problems(h, "TARGET", origin, unit_id, expected, zone, problems)
	var picker: TargetPicker = h.host.top() as TargetPicker
	if picker != null:
		picker.get_rows()[0].pressed.emit()
	_kept_problems(h, "CONFIRM", origin, unit_id, expected, zone, problems)
	print("      (kept preview: %s from %s to %s, %s)" % [
		unit_id, origin, tile, TurnInputModel.ActionKind.find_key(targeted),
	])
	_check.call("kept preview: WALK to CONFIRM show the picked tile's intents and zone", (
			problems.is_empty() and h.controller.get_stage() == CONFIRM
	), "; ".join(problems))

	while h.controller.get_stage() != MOVE and h.controller.step_back():
		pass
	for _frame: int in 3:
		h.controller.run_preview_frame()
		h.controller.get_preview_queue().wait()
	var model: IntentViewModel = display.get_model()
	var shown: Array[Vector2i] = h.view.get_danger_overlay().shown_tiles()
	_check.call("kept preview: Cancel's snap back restores the session's intents and zone", (
			h.controller.get_stage() == MOVE
			and model != null
			and not model.is_preview
			and _model_texts(model) == live
			and shown == _zone_tiles(h.session)
			and h.controller.move_preview_marks.get_shown() == null
	), "stage %d, preview %s, zone %d tiles (session %d)" % [
		h.controller.get_stage(), model != null and model.is_preview, shown.size(),
		_zone_tiles(h.session).size(),
	])
	h.close()


# Why stage's board isn't the picked tile's preview: another stage, other intents, a line at the
# moved unit still at origin, or another danger zone; appended to problems.
func _kept_problems(
		h: TurnInputCases.Harness,
		stage: String,
		origin: Vector2i,
		unit_id: String,
		expected: PackedStringArray,
		zone: Array[Vector2i],
		problems: PackedStringArray,
) -> void:
	var display: IntentDisplay = h.controller.intent_display
	var model: IntentViewModel = display.get_model()
	var at_stage: String = BattleController.Stage.find_key(h.controller.get_stage())
	if at_stage != stage:
		problems.append("%s: at %s" % [stage, at_stage])
	if model == null or not model.is_preview or _model_texts(model) != expected:
		problems.append("%s: intents %s, expected %s" % [stage, _model_texts(model), expected])
	if model != null:
		for entry: IntentViewModel.Entry in model.entries:
			if entry.target_id == unit_id and entry.target_tile == origin:
				problems.append("%s: %s's line points at the vacated tile" % [
					stage, entry.enemy_id,
				])
	if h.view.get_danger_overlay().shown_tiles() != zone:
		problems.append("%s: the danger zone isn't the preview's" % [stage])


# The opening swap window shows the danger zone and no intents; R hides and shows it; Start turns
# it off and the intents appear.
func _test_swap_window() -> void:
	var h: TurnInputCases.Harness = _harness(false)
	if h == null:
		return
	var display: IntentDisplay = h.controller.intent_display
	var overlay: TileOverlay = h.view.get_danger_overlay()
	var zone: Array[Vector2i] = _zone_tiles(h.session)
	_check.call("danger: the swap window shows DangerZone's tiles and no intents", (
			h.controller.get_stage() == SWAP
			and h.session.intents == null
			and h.controller.is_danger_zone_shown()
			and not zone.is_empty()
			and overlay.shown_tiles() == zone
			and display.shown_icons().is_empty()
			and display.shown_lines().is_empty()
	), "stage %d, %d of %d tiles, icons %s" % [
		h.controller.get_stage(), overlay.shown_tiles().size(), zone.size(), display.shown_icons(),
	])
	_press_r()
	var hidden: bool = not h.controller.is_danger_zone_shown() and overlay.shown_tiles().is_empty()
	_press_r()
	_check.call("danger: R hides and shows it in the swap window", (
			hidden and overlay.shown_tiles() == zone
	))
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	_check.call("danger: Start turns it off and the intents appear", (
			h.controller.get_stage() == IDLE
			and not h.controller.is_danger_zone_shown()
			and overlay.shown_tiles().is_empty()
			and h.session.intents != null
			and not display.shown_icons().is_empty()
	), "icons %s" % [display.shown_icons()])
	h.close()


# Every acting enemy shows its intent's icon, in order, none of them previewed.
func _test_icons() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var display: IntentDisplay = h.controller.intent_display
	var intents: Intents = h.session.intents
	var problems: PackedStringArray = []
	var ids: PackedStringArray = []
	var kinds: PackedStringArray = []
	for intent: EnemyIntent in intents.enemies:
		ids.append(intent.unit_id)
		var icon: IntentIcon = display.icon_of(intent.unit_id)
		if icon == null:
			problems.append("%s has no icon" % [intent.unit_id])
			continue
		kinds.append("%s %s" % [intent.unit_id, icon.get_glyph_text()])
		if icon.kind != intent.kind or icon.get_glyph_text() != icon.glyph_of(intent.kind):
			problems.append("%s shows %s for %s" % [intent.unit_id, icon.kind, intent.kind])
		if icon.is_preview:
			problems.append("%s shown as previewed" % [intent.unit_id])
	var enemies: PackedStringArray = h.session.state.units_of(ENEMY)
	var sorted_ids: PackedStringArray = ids.duplicate()
	sorted_ids.sort()
	enemies.sort()
	print("      (icons: %s)" % [", ".join(kinds)])
	_check.call("icons: every enemy shows its intent's icon", (
			problems.is_empty()
			and display.shown_icons() == ids
			and sorted_ids == enemies
			and not ids.is_empty()
	), "; ".join(problems))
	h.close()


# The cursor (or the mouse) on an enemy shows its rule's first clause; off it, none; after the
# darkness arrives, a switched enemy shows the darkness's rule.
func _test_rule_text() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var display: IntentDisplay = h.controller.intent_display
	var state: CombatState = h.session.state
	var problems: PackedStringArray = []
	for intent: EnemyIntent in h.session.intents.enemies:
		var definition: EnemyClassDefinition = _catalog.enemy_class(
				state.unit_type_of(intent.unit_id)
		)
		var first: String = definition.target_rule_text.get_slice(";", 0).strip_edges()
		h.controller.move_cursor(state.tile_of(intent.unit_id))
		var shown: String = display.get_rule_text()
		if shown.is_empty() or shown != intent.target_rule_text or shown != first:
			problems.append("%s shows '%s', rule '%s'" % [intent.unit_id, shown, first])
	var empty: Vector2i = _empty_tile(h.session)
	h.controller.move_cursor(empty)
	var cleared: bool = display.get_rule_text().is_empty()
	_check.call("rule: the cursor on an enemy shows its rule's first clause; off it, none", (
			problems.is_empty() and cleared
	), "; ".join(problems))

	var first_enemy: String = h.session.intents.enemies[0].unit_id
	var by_mouse: String = ""
	if _is_on_screen(h, state.tile_of(first_enemy)):
		_hover(h, state.tile_of(first_enemy))
		by_mouse = display.get_rule_text()
	_check.call("rule: hovering an enemy with the mouse shows its rule", (
			not by_mouse.is_empty()
			and by_mouse == h.session.intents.intent_of(first_enemy).target_rule_text
	), "'%s'" % [by_mouse])

	# A fixture, as tests/enemies/intent_cases.gd sets it: the next step's intents read it.
	state.map.has_darkness_arrived = true
	var waiter: String = TurnInputModel.acting_units(h.session, 0)[0]
	_send(h, UnitTurnCommand.new(0, waiter, UnitTurnCommand.Action.WAIT))
	var switched: int = 0
	problems.clear()
	for intent: EnemyIntent in h.session.intents.enemies:
		var definition: EnemyClassDefinition = _catalog.enemy_class(
				state.unit_type_of(intent.unit_id)
		)
		h.controller.move_cursor(state.tile_of(intent.unit_id))
		var shown: String = display.get_rule_text()
		var expected: String = definition.target_rule_text
		if intent.target_rule_id != definition.target_rule_id:
			expected = DARKNESS_RULE
			switched += 1
		if shown != expected:
			problems.append("%s shows '%s', expected '%s'" % [intent.unit_id, shown, expected])
	_check.call("rule: after the darkness arrives, a switched enemy shows \"%s\"" % [
		DARKNESS_RULE,
	], problems.is_empty() and switched > 0, "%d switched; %s" % [switched, "; ".join(problems)])
	h.close()


# The lines are the intents with a target, numbered in EnemyPlan order and pointing at each target;
# hovering an enemy narrows them to its own; LineMode.HOVERED shows only the hovered one's.
func _test_lines() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var display: IntentDisplay = h.controller.intent_display
	var state: CombatState = h.session.state
	var intents: Intents = h.session.intents
	var expected: PackedStringArray = []
	var in_order: bool = true
	for i: int in intents.enemies.size():
		var intent: EnemyIntent = intents.enemies[i]
		in_order = in_order and intent.order == i
		if intent.target_id.is_empty() or intent.target_id == intent.unit_id:
			continue
		expected.append(
				"%d %s -> %s" % [intent.order + 1, intent.unit_id, state.tile_of(intent.target_id)]
		)
	h.controller.move_cursor(_empty_tile(h.session))
	var drawn: PackedStringArray = _line_texts(display)
	print("      (lines: %s)" % [", ".join(drawn)])
	_check.call("lines: one per target, numbered in EnemyPlan order, pointing at each target", (
			in_order and not expected.is_empty() and drawn == expected
	), "drawn %s, expected %s" % [drawn, expected])

	var lined: IntentLine = display.shown_lines()[0] if not drawn.is_empty() else null
	var narrowed: bool = false
	if lined != null:
		h.controller.move_cursor(state.tile_of(lined.enemy_id))
		var one: Array[IntentLine] = display.shown_lines()
		narrowed = one.size() == 1 and one[0].enemy_id == lined.enemy_id
		h.controller.move_cursor(_empty_tile(h.session))
		narrowed = narrowed and _line_texts(display) == expected
	display.line_mode = IntentDisplay.LineMode.HOVERED
	var none_unhovered: bool = display.shown_lines().is_empty()
	if lined != null:
		h.controller.move_cursor(state.tile_of(lined.enemy_id))
	var only_hovered: bool = display.shown_lines().size() == 1
	display.line_mode = IntentDisplay.LineMode.ALL
	_check.call("lines: hovering an enemy shows its line alone; HOVERED mode only on hover", (
			narrowed and none_unhovered and only_hovered
	))
	h.close()


# Off by default in the player phase; R draws exactly DangerZone's tiles and hides them; an enemy's
# own range shows beside it; after the enemy phase the zone is the new board's.
func _test_danger_toggle() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var overlay: TileOverlay = h.view.get_danger_overlay()
	var starts_off: bool = (
			not h.controller.is_danger_zone_shown() and overlay.shown_tiles().is_empty()
	)
	_press_r()
	var zone: Array[Vector2i] = _zone_tiles(h.session)
	_check.call("danger: off by default; R draws exactly DangerZone's tiles", (
			starts_off
			and h.controller.is_danger_zone_shown()
			and not zone.is_empty()
			and overlay.shown_tiles() == zone
	), "%d of %d tiles" % [overlay.shown_tiles().size(), zone.size()])

	var enemy_id: String = h.session.state.units_of(ENEMY)[0]
	h.controller.confirm_tile(h.session.state.tile_of(enemy_id))
	var own: Array[Vector2i] = TurnInputModel.enemy_range_tiles(h.session, enemy_id)
	var ranges: TileOverlay = h.view.get_enemy_range_overlay()
	var both: bool = ranges.shown_tiles() == own and overlay.shown_tiles() == zone
	_press_r()
	var range_kept: bool = overlay.shown_tiles().is_empty() and ranges.shown_tiles() == own
	_check.call("danger: an enemy's own range shows beside it, and R leaves that range", (
			both and range_kept and not own.is_empty()
	))

	_press_r()
	for unit_id: String in TurnInputModel.acting_units(h.session, 0):
		_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	_send(h, EndTurnCommand.new(0))
	var after: Array[Vector2i] = _zone_tiles(h.session)
	_check.call("danger: after the enemy phase it is the new board's zone", (
			h.session.is_finished
			or (h.controller.is_danger_zone_shown() and overlay.shown_tiles() == after)
	), "%d of %d tiles" % [overlay.shown_tiles().size(), after.size()])
	h.close()


# Hovering a move tile shows Intents.preview's intents for it, previewed, with the moved unit's
# line at the hovered tile and the changed enemies tinted; clearing the hover reverts.
func _test_preview() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var display: IntentDisplay = h.controller.intent_display
	var state: CombatState = h.session.state
	var unit_id: String = ""
	var tile: Vector2i = CombatFact.NO_TILE
	var fallback: Vector2i = CombatFact.NO_TILE
	# The first tile, by unit, where the preview changes an enemy's target to the moved unit; else
	# any tile that changes an intent. Each preview takes tens of milliseconds, so the search stops.
	var searched: int = 0
	for candidate: String in TurnInputModel.acting_units(h.session, 0):
		for option: Vector2i in TurnInputModel.move_tiles(h.session, candidate):
			searched += 1
			if searched > MAX_SEARCH:
				break
			var preview: MovePreview = MovePreview.compute(h.session, candidate, option)
			if preview.intents == null or preview.changed_enemies.is_empty():
				continue
			if fallback == CombatFact.NO_TILE:
				fallback = option
				unit_id = candidate
			for intent: EnemyIntent in preview.intents.enemies:
				if intent.target_id == candidate and preview.changed_enemies.has(intent.unit_id):
					unit_id = candidate
					tile = option
					break
			if tile != CombatFact.NO_TILE:
				break
		if tile != CombatFact.NO_TILE:
			break
	if tile == CombatFact.NO_TILE:
		tile = fallback
	if unit_id.is_empty() or tile == CombatFact.NO_TILE:
		_check.call("preview: a move tile that changes an intent", false, "none on turn 1")
		h.close()
		return
	var live: PackedStringArray = _entry_texts(h.session, h.session.intents, "", CombatFact.NO_TILE)
	h.controller.confirm_tile(state.tile_of(unit_id))
	h.controller.move_cursor(tile)
	h.controller.run_preview_frame()
	h.controller.get_preview_queue().wait()
	var ran: bool = h.controller.run_preview_frame()
	var replanned: Intents = Intents.preview(h.session, unit_id, tile)
	var expected: PackedStringArray = _entry_texts(h.session, replanned, unit_id, tile)
	var model: IntentViewModel = display.get_model()
	var shown: PackedStringArray = _model_texts(model)
	var all_previewed: bool = true
	var tinted: bool = true
	var changed: PackedStringArray = h.controller.get_preview_queue().shown().changed_enemies
	for enemy_id: String in display.shown_icons():
		var icon: IntentIcon = display.icon_of(enemy_id)
		all_previewed = all_previewed and icon.is_preview
		var tint: Color = icon.changed_modulate if changed.has(enemy_id) else icon.preview_modulate
		tinted = tinted and icon.modulate == tint
	for line: IntentLine in display.shown_lines():
		all_previewed = all_previewed and line.is_preview
	var points_at_tile: bool = false
	for line: IntentLine in display.shown_lines():
		var intent: EnemyIntent = replanned.intent_of(line.enemy_id)
		if intent != null and intent.target_id == unit_id:
			points_at_tile = line.target_tile == tile
	print("      (preview %s to %s: %s)" % [unit_id, tile, ", ".join(shown)])
	_check.call("preview: the icons and lines are Intents.preview's for the hovered tile", (
			ran
			and model != null
			and model.is_preview
			and shown == expected
			and all_previewed
	), "shown %s, expected %s" % [shown, expected])
	_check.call("preview: a line at the moved unit points at the hovered tile; changes tinted", (
			points_at_tile and tinted
	), "changed %s" % [changed])

	var enemy_tile: Vector2i = state.tile_of(state.units_of(ENEMY)[0])
	h.controller.move_cursor(enemy_tile)
	var off_tiles: bool = (
			display.get_model() != null
			and not display.get_model().is_preview
			and _model_texts(display.get_model()) == live
	)
	h.controller.move_cursor(tile)
	h.controller.run_preview_frame()
	h.controller.get_preview_queue().wait()
	h.controller.run_preview_frame()
	var back_in: bool = display.get_model().is_preview
	h.controller.step_back()
	var left: bool = (
			h.controller.get_stage() == IDLE
			and not display.get_model().is_preview
			and _model_texts(display.get_model()) == live
	)
	_check.call("preview: off the move tiles, and on leaving MOVE, the live intents return", (
			off_tiles and back_in and left
	))
	h.close()


# --- Fixtures --------------------------------------------------------------------------------


# turn_input_cases.gd's harness with the forecast panel, the move preview marks and the intent
# display set, as in the gameplay scene; past the swap window's Start when is_started.
func _harness(is_started: bool, curse_id: String = "") -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("intents: the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	# A curse seat 0 owns, registered before the board and the controller read the session.
	if not curse_id.is_empty():
		for instance: EffectInstance in Loadout.heirloom_effects(
				_catalog, curse_id, 0, h.session.ids
		):
			h.session.engine.register(instance)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	var display: IntentDisplay = DISPLAY_SCENE.instantiate()
	h.view.add_child(display)
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
	h.controller.intent_display = display
	_root.add_child(h.controller)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	h.session.batch_resolved.connect(h.record)
	if is_started:
		h.controller.request_start()
		BattleViewCases.settle(h.view)
	return h


func _send(h: TurnInputCases.Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)


# DangerZone's tiles on the session's board, in the overlay's order.
func _zone_tiles(session: CombatSession) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(DangerZone.compute(session.engine).combined.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


# A tile on the map with no unit on it.
func _empty_tile(session: CombatSession) -> Vector2i:
	var rect: Rect2i = session.layout.get_rect()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var tile: Vector2i = Vector2i(x, y)
			if session.state.occupant_at(tile).is_empty():
				return tile
	return CombatFact.NO_TILE


# Each intent of intents as the display should draw it, with moved_id standing on moved_to.
func _entry_texts(
		session: CombatSession, intents: Intents, moved_id: String, moved_to: Vector2i
) -> PackedStringArray:
	var texts: PackedStringArray = []
	for intent: EnemyIntent in intents.enemies:
		var target: Vector2i = CombatFact.NO_TILE
		if not intent.target_id.is_empty():
			target = moved_to if intent.target_id == moved_id else session.state.tile_of(
					intent.target_id
			)
		texts.append("%d %s %d %s %s" % [
			intent.order, intent.unit_id, intent.kind, intent.target_id, target,
		])
	return texts


func _model_texts(model: IntentViewModel) -> PackedStringArray:
	var texts: PackedStringArray = []
	if model == null:
		return texts
	for entry: IntentViewModel.Entry in model.entries:
		texts.append("%d %s %d %s %s" % [
			entry.order, entry.enemy_id, entry.kind, entry.target_id, entry.target_tile,
		])
	return texts


func _line_texts(display: IntentDisplay) -> PackedStringArray:
	var texts: PackedStringArray = []
	for line: IntentLine in display.shown_lines():
		texts.append("%d %s -> %s" % [line.number, line.enemy_id, line.target_tile])
	return texts


# A press and release of R, by its physical position, as the input map binds toggle_danger_zone.
func _press_r() -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = KEY_R
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


func _is_on_screen(h: TurnInputCases.Harness, tile: Vector2i) -> bool:
	return _root.get_viewport().get_visible_rect().has_point(_screen_point(h, tile))


func _screen_point(h: TurnInputCases.Harness, tile: Vector2i) -> Vector2:
	var camera: Camera2D = _root.get_viewport().get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	return h.view.get_global_transform_with_canvas() * h.view.tile_to_position(tile)


func _hover(h: TurnInputCases.Harness, tile: Vector2i) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _screen_point(h, tile)
	motion.global_position = motion.position
	_root.get_viewport().push_input(motion, true)
