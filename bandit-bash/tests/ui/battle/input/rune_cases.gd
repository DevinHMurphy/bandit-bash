# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_cases.gd
# Author:
# Created:  November 16, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Rune casting's cases for the ui/input suite (combat UI plan, UI13 and UI14 rows): every rune's
## targets against what the validator accepts, by kind; the unit menu's runes, each on its own
## unit, with their text and title; each of the seven runes cast from the rune bar by keys
## (open_runes, the arrows, accept), by the mouse (a click on its slot) and by a pad, its forecast
## showing the cast's tiles; Recall swapping its two units; Spark's chain resolving as its preview
## showed; Shatter's and Haste's refusals (no ally, no unit that has acted), greyed in the picker
## and said in the message; and cancel stepping back one stage at a time on every device, from the
## bar and from the unit menu. No autoload is named or needed. rune_bar_cases.gd extends this file.
##
## The harness is targeting_cases.gd's, with the rune menu and the rune bar. Its fixture gives
## seat 0 all seven catalog runes, wounds a player unit and places two powder kegs, one in the
## other's blast and one beside an enemy (test setup only; the UI never does this).

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/input"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")
const CombatWorld = preload("res://tests/combat/combat_world.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const RUNE_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/rune_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")
const FORECAST_SCENE: PackedScene = preload("res://ui/battle/forecast/forecast_panel.tscn")
const RUNE_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/rune_bar.tscn")

# Any fixed seed; the other UI cases use the same one.
const SEED: int = 0x0C0FFEE

# items.md's seven runes, in the order the cast cases cast them: Recall last, as it moves units.
const RUNES: Array[String] = ["mend", "aegis", "shatter", "clarity", "haste", "spark", "recall"]

# HP the fixture takes from one player unit, so Mend heals something.
const WOUND: int = 8

# The fixture kegs' object spot indices: far above any map's own, so their ids are new.
const KEG_INDEX: int = 900

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const IDLE: BattleController.Stage = BattleController.Stage.IDLE
const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const ACTION: BattleController.Stage = BattleController.Stage.ACTION
const RUNE_STAGE: BattleController.Stage = BattleController.Stage.RUNE
const TARGET: BattleController.Stage = BattleController.Stage.TARGET
const PAIR_TARGET: BattleController.Stage = BattleController.Stage.PAIR_TARGET
const CONFIRM: BattleController.Stage = BattleController.Stage.CONFIRM
const RUNE_SLOTS: BattleController.Stage = BattleController.Stage.RUNE_SLOTS
const DISCARD_CONFIRM: BattleController.Stage = BattleController.Stage.DISCARD_CONFIRM
const RUNE_KIND: TurnInputModel.ActionKind = TurnInputModel.ActionKind.RUNE

## How a case drives the screen.
enum Device {
	## The actions' keys, as the InputMap binds them.
	KEYS = 0,
	## Clicks on the board and on the panels' rows and buttons.
	MOUSE = 1,
	## The actions' joypad bindings.
	PAD = 2,
}

const DEVICE_NAMES: Array[String] = ["keys", "mouse", "pad"]

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null

# The kegs the last harness placed, the first then the one it chains into; empty without them.
var _kegs: Array[String] = []


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
		_check.call("runes: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_lists_match_validator()
	_test_menu_text()
	for device: Device in [Device.KEYS, Device.MOUSE, Device.PAD]:
		_test_cast_every_rune(device)
	_test_spark_chain()
	_test_refusals()
	for device: Device in [Device.KEYS, Device.MOUSE, Device.PAD]:
		_test_cancel_steps(device)


# Every rune's targets are exactly what CastRuneCommand.validate accepts, by kind: a unit rune's
# units of every unit on the map, Recall's ordered pairs of the seat's units, Spark's object tiles;
# Rune is offered on the unit's own tile only.
func _test_lists_match_validator() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var session: CombatSession = h.session
	var options: Array[TurnInputModel.RuneOption] = TurnInputModel.rune_options(session, 0)
	var listed_kinds: PackedStringArray = []
	var problems: PackedStringArray = []
	for option: TurnInputModel.RuneOption in options:
		listed_kinds.append(_definition_id(session, option))
		var listed: PackedStringArray = _listed_keys(option)
		var accepted: PackedStringArray = _accepted_keys(
				session, option.rune_id, option.target_kind == ContentIds.RUNE_PAIR
		)
		if listed != accepted or listed.is_empty():
			problems.append("%s: listed %s, accepted %s" % [option.label, listed, accepted])
		for key: String in _unvalidated(session, option):
			problems.append("%s: %s doesn't validate" % [option.label, key])
	listed_kinds.sort()
	var all: PackedStringArray = PackedStringArray(RUNES)
	all.sort()
	_check.call("runes: every rune is offered, each by its kind", listed_kinds == all, (
			"listed %s" % [listed_kinds]
	))
	_check.call("runes: each rune's targets are exactly what the validator accepts", (
			problems.is_empty()
	), "; ".join(problems))

	var caster: String = _caster(h)
	var tile: Vector2i = session.state.tile_of(caster)
	var walked: Array[Vector2i] = []
	for end: Vector2i in TurnInputModel.move_tiles(session, caster):
		if end != tile:
			walked = TurnInputModel.path_to(session, caster, end)
			break
	var here: bool = _has_rune(TurnInputModel.actions_at(session, caster, []))
	var there: bool = _has_rune(TurnInputModel.actions_at(session, caster, walked))
	_check.call("runes: Rune is offered on the unit's own tile, not after a move", (
			here and not there and walked.size() > 1
	), "own tile %s, after a move %s" % [here, there])

	var own: Array[TurnInputModel.RuneOption] = TurnInputModel.runes_for_unit(session, 0, caster)
	var own_kinds: PackedStringArray = []
	var stray: PackedStringArray = []
	for option: TurnInputModel.RuneOption in own:
		own_kinds.append(_definition_id(session, option))
		if option.targets.size() != 1 or option.targets[0].target_id != caster:
			stray.append(option.label)
		if not option.refused.is_empty():
			stray.append("%s refuses" % [option.label])
	own_kinds.sort()
	# Every player-side unit rune takes the caster; Shatter (enemies) and Spark (kegs) never do.
	var expected: PackedStringArray = ["aegis", "clarity", "haste", "mend", "recall"]
	_check.call("runes: the unit menu offers only the runes cast on that unit, aimed at it", (
			own_kinds == expected and stray.is_empty()
	), "offered %s, aimed elsewhere %s" % [own_kinds, stray])
	h.close()


# The unit menu's rune menu lists the caster's own runes and shows the focused rune's text, the
# catalog's; the picker's title names who it is cast on.
func _test_menu_text() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var problems: PackedStringArray = []
	var caster: String = _caster(h)
	if not _open_rune_menu(h, Device.KEYS, caster):
		_check.call("text: the rune menu opens", false, str(h.controller.get_stage()))
		h.close()
		return
	var menu: RuneMenu = h.host.top() as RuneMenu
	var options: Array[TurnInputModel.RuneOption] = menu.get_options()
	var own: Array[TurnInputModel.RuneOption] = TurnInputModel.runes_for_unit(h.session, 0, caster)
	for i: int in options.size():
		_focus_row(Device.KEYS, menu.get_rows(), i)
		var definition: RuneDefinition = _catalog.rune(_definition_id(h.session, options[i]))
		var expected: String = " ".join(definition.describe())
		if menu.get_text() != expected or options[i].text != expected:
			problems.append("%s shows '%s', its text is '%s'" % [
				options[i].label, menu.get_text(), expected,
			])
		var title: String = "%s: %s" % [definition.display_name, definition.target_noun()]
		if options[i].title != title:
			problems.append("%s's title is '%s'" % [options[i].label, options[i].title])
	_check.call("text: the menu shows each rune's own text, its title who it is cast on", (
			problems.is_empty() and options.size() == own.size() and not own.is_empty()
	), "; ".join(problems))
	h.close()


# Each of the seven runes, cast from the rune bar by device: its command reaches the session, the
# rune leaves the slot, its forecast showed the cast's tiles, and Recall's two units traded tiles.
func _test_cast_every_rune(device: Device) -> void:
	var tag: String = "cast (%s)" % [DEVICE_NAMES[device]]
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var session: CombatSession = h.session
	var state: CombatState = session.state
	var kegs: Array[String] = _kegs
	var caster: String = _caster(h)
	var failed: PackedStringArray = []
	var cast_count: int = 0
	for definition_id: String in RUNES:
		var rune_id: String = _rune_id_of(session, definition_id)
		var aim: Array = _aim(h, definition_id, caster, kegs)
		if rune_id.is_empty() or aim.is_empty():
			failed.append("%s: nothing to aim at" % [definition_id])
			continue
		var target_id: String = aim[0]
		var second_id: String = aim[1]
		var before_first: Vector2i = state.tile_of(target_id)
		var before_second: Vector2i = state.tile_of(second_id)
		var problem: String = _cast(h, device, rune_id, target_id, second_id)
		if problem.is_empty():
			problem = _cast_landed(h, rune_id)
		if problem.is_empty() and definition_id == "recall":
			var traded: bool = (
					state.tile_of(target_id) == before_second
					and state.tile_of(second_id) == before_first
			)
			if not traded:
				problem = "the two units didn't trade tiles"
		if problem.is_empty():
			cast_count += 1
		else:
			failed.append("%s: %s" % [definition_id, problem])
	_check.call(tag + ": each of the seven runes is cast from the rune bar", (
			cast_count == RUNES.size()
	), "; ".join(failed))
	var left: PackedStringArray = state.rune_slots.get(0, PackedStringArray())
	_check.call(tag + ": no cast was rejected, and the slots are empty", (
			_rejections(h).is_empty() and left.is_empty()
	), "rejected %s, left %s" % [_rejections(h), left])
	h.close()


# Spark on the first keg: its TARGET draws the whole chain, and once confirmed both kegs break and
# every unit ends as its preview showed.
func _test_spark_chain() -> void:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var session: CombatSession = h.session
	var state: CombatState = session.state
	var kegs: Array[String] = _kegs
	if kegs.size() != 2:
		_check.call("spark: two kegs in a chain placed", false, str(kegs))
		h.close()
		return
	var rune_id: String = _rune_id_of(session, "spark")
	var stopped: String = _cast(h, Device.KEYS, rune_id, kegs[0], "", CONFIRM)
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	if not stopped.is_empty() or panel == null or panel.get_model() == null:
		_check.call("spark: its forecast opens", false, stopped)
		h.close()
		return
	var model: ForecastViewModel = panel.get_model()
	var chain: Dictionary[Vector2i, bool] = {}
	for keg_id: String in kegs:
		for tile: Vector2i in MapObjects.KEG_BLAST.tiles(state.map.object(keg_id).tile):
			if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
				chain[tile] = true
	var drawn: Array[Vector2i] = h.view.get_attack_overlay().shown_tiles()
	var missing: PackedStringArray = []
	for tile: Vector2i in chain:
		if not model.tiles.has(tile) or not drawn.has(tile):
			missing.append(str(tile))
	_check.call("spark: the preview and the board show both kegs' blasts", (
			missing.is_empty() and model.kind == ForecastViewModel.Kind.RUNE
	), "missing %s" % [", ".join(missing)])
	var predicted: Dictionary[String, String] = {}
	for outcome: CombatForecast.UnitOutcome in model.forecast.units:
		predicted[outcome.unit_id] = _outcome_text(outcome.is_defeated, outcome.hp_after)
	var broken_before: PackedStringArray = _broken_objects(model.forecast.facts)
	_press(Device.KEYS, &"ui_accept")
	BattleViewCases.settle(h.view)
	var actual: Dictionary[String, String] = {}
	for unit_id: String in predicted:
		var gone: bool = not state.has_unit(unit_id)
		actual[unit_id] = _outcome_text(gone, 0 if gone else state.get_hp(unit_id))
	var batch: CombatSession.FactBatch = h.last_batch()
	var broken_after: PackedStringArray = (
			PackedStringArray() if batch == null else _broken_objects(batch.facts)
	)
	_check.call("spark: both kegs break, as the preview's facts said", (
			broken_before == broken_after and broken_after.has(kegs[0])
			and broken_after.has(kegs[1])
	), "preview %s, cast %s" % [broken_before, broken_after])
	_check.call("spark: every unit ends as its preview showed", (
			predicted == actual and not predicted.is_empty()
	), "predicted %s, after %s" % [predicted, actual])
	h.close()


# Shatter lists no ally and Haste no unit that has acted: no device can pick one, the picker
# lists Haste's acted unit greyed with why, and a click on either says why in the message.
func _test_refusals() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var session: CombatSession = h.session
	var state: CombatState = session.state
	var caster: String = _caster(h)
	var acted: String = ""
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		if unit_id != caster and _is_clear(h, state.tile_of(unit_id)):
			acted = unit_id
			break
	if acted.is_empty():
		_check.call("refusals: a second unit on screen to act first", false)
		h.close()
		return
	_send(h, UnitTurnCommand.new(0, acted, UnitTurnCommand.Action.WAIT))

	var shatter: String = _rune_id_of(session, "shatter")
	var stopped: String = _cast(h, Device.KEYS, shatter, "", "", TARGET)
	var list: TargetList = h.controller.get_target_list()
	var allies: PackedStringArray = []
	if list != null:
		for target: TurnInputModel.TargetOption in list.targets():
			if state.side_of(target.target_id) != ENEMY:
				allies.append(target.target_id)
	_click_board(h, state.tile_of(acted))
	var said: String = h.message.get_text()
	var shatter_stage: BattleController.Stage = h.controller.get_stage()
	_check.call("refusals: Shatter lists only enemies, and a click on an ally says why", (
			stopped.is_empty() and list != null and allies.is_empty()
			and shatter_stage == TARGET
			and said == "Shatter targets an enemy."
	), "stopped '%s', allies %s, stage %d, message '%s'" % [
		stopped, allies, shatter_stage, said,
	])
	while h.controller.step_back():
		pass

	var haste: String = _rune_id_of(session, "haste")
	stopped = _cast(h, Device.KEYS, haste, "", "", TARGET)
	list = h.controller.get_target_list()
	var picker: TargetPicker = h.host.top() as TargetPicker
	var visited: Dictionary[String, bool] = {}
	if list != null:
		for _i: int in list.size() + 1:
			visited[list.current().target_id] = true
			_press(Device.PAD, &"target_next")
	var greyed: bool = false
	if picker != null:
		var unit_name: String = BattleText.name_of(session, acted)
		for row: Button in picker.get_refused_rows():
			if (
					row.text == "%s: %s" % [unit_name, TurnInputModel.ACTED_REASON]
					and row.disabled and row.focus_mode == Control.FOCUS_NONE
			):
				greyed = true
	_click_board(h, state.tile_of(acted))
	said = h.message.get_text()
	var expected: String = "Haste: %s %s." % [
		BattleText.name_of(session, acted), TurnInputModel.ACTED_REASON,
	]
	_check.call("refusals: Haste never offers a unit that has acted, greys it, says why", (
			stopped.is_empty() and list != null and not visited.has(acted)
			and not visited.is_empty() and greyed and said == expected
			and h.controller.get_stage() == TARGET
	), "stopped '%s', visited %s, greyed %s, message '%s'" % [
		stopped, visited.keys(), greyed, said,
	])
	h.close()


# From Recall's PAIR_TARGET off the bar, cancel by device steps back one stage at a time:
# TARGET, the bar (RUNE_SLOTS, for keys and pads, which opened it), IDLE, the cursor back where it
# was; the first unit is outlined as picked in PAIR_TARGET only. From the unit menu's Recall, which
# skips the picker: RUNE, ACTION, MOVE, IDLE.
func _test_cancel_steps(device: Device) -> void:
	var tag: String = "cancel (%s)" % [DEVICE_NAMES[device]]
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var session: CombatSession = h.session
	var recall: String = _rune_id_of(session, "recall")
	var caster: String = _caster(h)
	var aim: Array = _aim(h, "recall", caster, [])
	var first_id: String = "" if aim.is_empty() else aim[0]
	var cursor: Vector2i = h.controller.get_cursor_tile()
	var stopped: String = _cast(h, device, recall, first_id, "", PAIR_TARGET)
	var picked: bool = false
	for mark: TargetMark in h.view.get_target_marks():
		if mark.is_picked and mark.tile == session.state.tile_of(first_id):
			picked = true
	_check.call(tag + ": Recall's first unit stays outlined as picked", (
			stopped.is_empty() and picked
	), stopped)
	var expected: Array[BattleController.Stage] = [TARGET, RUNE_SLOTS, IDLE]
	if device == Device.MOUSE:
		expected = [TARGET, IDLE]
	var stages: Array[BattleController.Stage] = []
	for _i: int in expected.size():
		_cancel(h, device)
		stages.append(h.controller.get_stage())
	var marks_left: int = h.view.get_target_marks().size()
	_check.call(tag + ": from the bar, cancel steps back one stage at a time, cursor back", (
			stages == expected and marks_left == 0 and h.host.depth() == 0
			and h.controller.get_cursor_tile() == cursor
	), "stages %s, marks %d, panels %d, cursor %s (was %s)" % [
		stages, marks_left, h.host.depth(), h.controller.get_cursor_tile(), cursor,
	])

	stages.clear()
	if _open_rune_menu(h, device, caster):
		var menu: RuneMenu = h.host.top() as RuneMenu
		for i: int in menu.get_options().size():
			if menu.get_options()[i].rune_id == recall:
				_pick_row(h, device, menu.get_rows(), i)
		stages.append(h.controller.get_stage())
		for _i: int in 4:
			_cancel(h, device)
			stages.append(h.controller.get_stage())
	var from_menu: Array[BattleController.Stage] = [PAIR_TARGET, RUNE_STAGE, ACTION, MOVE, IDLE]
	_check.call(tag + ": from the unit menu, Recall picks the unit itself, cancel steps back", (
			stages == from_menu and h.host.depth() == 0
			and h.view.get_target_marks().is_empty()
	), "stages %s, panels %d" % [stages, h.host.depth()])
	h.close()


# --- Driving the screen --------------------------------------------------------------------


# Casts rune_id from the rune bar by device, from the stage the flow is in (IDLE or MOVE), aiming
# at target_id (for Spark, the keg; empty: stop at TARGET) then second_id (Recall's partner), and
# confirms on the forecast. Stops early, leaving the stage as it is, once stop_at is reached. Empty
# when every step reached the stage it should, and the flow came back to the stage it began in;
# else which didn't.
func _cast(
		h: TurnInputCases.Harness,
		device: Device,
		rune_id: String,
		target_id: String,
		second_id: String,
		stop_at: BattleController.Stage = BattleController.Stage.INACTIVE
) -> String:
	var c: BattleController = h.controller
	var origin: BattleController.Stage = c.get_stage()
	var problem: String = _open_rune_targets(h, device, rune_id)
	if not problem.is_empty():
		return problem
	if stop_at == TARGET or target_id.is_empty():
		return ""
	problem = _pick_target(h, device, target_id)
	if not problem.is_empty():
		return problem
	if c.get_rune().target_kind == ContentIds.RUNE_PAIR:
		if c.get_stage() != PAIR_TARGET:
			return "Recall's partners didn't open (stage %d)" % [c.get_stage()]
		if stop_at == PAIR_TARGET or second_id.is_empty():
			return ""
		problem = _pick_target(h, device, second_id)
		if not problem.is_empty():
			return problem
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	if c.get_stage() != CONFIRM or panel == null:
		return "the forecast didn't open (stage %d)" % [c.get_stage()]
	var model: ForecastViewModel = panel.get_model()
	var command: CastRuneCommand = c.get_confirm_command() as CastRuneCommand
	if model == null or model.rune_command != command or command == null:
		return "the forecast isn't the confirm's command"
	var aimed: Array[Vector2i] = []
	for unit_id: String in [command.target_id, command.second_target_id]:
		if not unit_id.is_empty():
			aimed.append(h.session.state.tile_of(unit_id))
	if command.tile != CombatFact.NO_TILE:
		aimed.append(command.tile)
	for tile: Vector2i in aimed:
		if not model.tiles.has(tile):
			return "the forecast's tiles %s miss %s" % [model.tiles, tile]
	for outcome: CombatForecast.UnitOutcome in model.forecast.units:
		if not outcome.is_changed():
			continue
		var shown_name: String = BattleText.name_of(h.session, outcome.unit_id)
		var has_row: bool = false
		for row: ForecastViewModel.Row in model.rows:
			has_row = has_row or row.label.begins_with(shown_name + " ")
		if not has_row:
			return "the forecast has no row for %s, which the cast changes" % [shown_name]
	if stop_at == CONFIRM:
		return ""
	if device == Device.MOUSE:
		_click_control(h, panel.get_confirm_button())
	else:
		_press(device, &"ui_accept")
	BattleViewCases.settle(h.view)
	if c.get_stage() != origin:
		return "the flow didn't return to stage %d (stage %d)" % [origin, c.get_stage()]
	return ""


# Opens rune_id's targets (TARGET) from the rune bar by device: a click on its slot, or open_runes,
# the arrows to its slot and accept. Empty when TARGET opened on that rune; else why not.
func _open_rune_targets(h: TurnInputCases.Harness, device: Device, rune_id: String) -> String:
	var c: BattleController = h.controller
	var bar: RuneBar = c.rune_bar
	var index: int = -1
	for i: int in bar.get_runes().size():
		if bar.get_runes()[i].rune_id == rune_id:
			index = i
	if index < 0:
		return "%s isn't on the rune bar" % [rune_id]
	if device == Device.MOUSE:
		_click_control(h, bar.get_slots()[index].get_slot_button())
	else:
		_press(device, &"open_runes")
		if c.get_stage() != RUNE_SLOTS:
			return "open_runes didn't focus the bar (stage %d)" % [c.get_stage()]
		for _i: int in bar.get_runes().size():
			if bar.get_focused_rune() == rune_id:
				break
			_press(device, &"ui_right")
		if bar.get_focused_rune() != rune_id:
			return "the arrows never reached %s's slot" % [rune_id]
		_press(device, &"ui_accept")
	if c.get_stage() != TARGET or c.get_rune() == null or c.get_rune().rune_id != rune_id:
		return "the rune's targets didn't open (stage %d)" % [c.get_stage()]
	return ""


# Selects caster on its own tile and opens its menu's Rune by device. Returns whether the rune
# menu opened.
func _open_rune_menu(h: TurnInputCases.Harness, device: Device, caster: String) -> bool:
	var c: BattleController = h.controller
	var tile: Vector2i = h.session.state.tile_of(caster)
	if device == Device.MOUSE:
		_click(h, tile)
		_click(h, tile)
	else:
		c.move_cursor(tile)
		_press(device, &"ui_accept")
		_press(device, &"ui_accept")
	var menu: ActionMenu = h.host.top() as ActionMenu
	if c.get_stage() != ACTION or menu == null:
		return false
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == RUNE_KIND:
			_pick_row(h, device, menu.get_rows(), i)
			break
	return c.get_stage() == RUNE_STAGE and h.host.top() is RuneMenu


# Makes target_id the current target and picks it by device: Q / E then accept, or a click on its
# tile (its picker row when the tile is covered or off screen). Empty when it was picked.
func _pick_target(h: TurnInputCases.Harness, device: Device, target_id: String) -> String:
	var list: TargetList = h.controller.get_target_list()
	var index: int = -1 if list == null else list.index_of(target_id)
	if index < 0:
		return "%s isn't a target" % [target_id]
	var before: BattleController.Stage = h.controller.get_stage()
	if device == Device.MOUSE:
		var tile: Vector2i = list.targets()[index].tile
		if _is_clear(h, tile):
			_click(h, tile)
		else:
			var picker: TargetPicker = h.host.top() as TargetPicker
			_click_control(h, picker.get_rows()[index])
	else:
		for _i: int in list.size():
			if list.current_index() == index:
				break
			_press(device, &"target_next")
		if list.current_index() != index:
			return "Q / E never reached %s" % [target_id]
		_press(device, &"ui_accept")
	if h.controller.get_stage() == before:
		return "picking %s did nothing" % [target_id]
	return ""


# Focuses row index of a panel's rows by device and presses it.
func _pick_row(h: TurnInputCases.Harness, device: Device, rows: Array[Button], index: int) -> void:
	if device == Device.MOUSE:
		_click_control(h, rows[index])
		return
	_focus_row(device, rows, index)
	_press(device, &"ui_accept")


# Moves a panel's focus to row index by up and down.
func _focus_row(device: Device, rows: Array[Button], index: int) -> void:
	for _i: int in rows.size():
		if rows[0].has_focus():
			break
		_press(device, &"ui_up")
	for _i: int in index:
		_press(device, &"ui_down")


# Cancel by device: Esc's key, a right click on the board, the pad's B.
func _cancel(h: TurnInputCases.Harness, device: Device) -> void:
	if device == Device.MOUSE:
		var point: Vector2 = _screen_point(h, h.controller.get_cursor_tile())
		for is_down: bool in [true, false]:
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.position = point
			click.global_position = point
			click.button_index = MOUSE_BUTTON_RIGHT
			click.pressed = is_down
			_root.get_viewport().push_input(click, true)
		return
	_press(device, &"ui_cancel")


# Presses and lets go of action as device sends it: the InputMap's first key event, or its first
# joypad event (a button, or an axis pushed fully and let back).
func _press(device: Device, action: StringName) -> void:
	var source: InputEvent = null
	for event: InputEvent in InputMap.action_get_events(action):
		var is_key: bool = event is InputEventKey
		var is_pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if (device == Device.PAD and is_pad) or (device != Device.PAD and is_key):
			source = event
			break
	if source == null:
		_check.call("runes: %s has a %s binding" % [action, DEVICE_NAMES[device]], false)
		return
	for is_down: bool in [true, false]:
		var event: InputEvent = source.duplicate()
		var key: InputEventKey = event as InputEventKey
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if key != null:
			key.pressed = is_down
		elif button != null:
			button.pressed = is_down
		elif motion != null:
			var push: InputEventJoypadMotion = source as InputEventJoypadMotion
			motion.axis_value = push.axis_value if is_down else 0.0
		_root.get_viewport().push_input(event, true)


# Where tile's centre is on screen, with the camera's scroll applied as a frame would.
func _screen_point(h: TurnInputCases.Harness, tile: Vector2i) -> Vector2:
	var camera: Camera2D = _root.get_viewport().get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	return h.view.get_global_transform_with_canvas() * h.view.tile_to_position(tile)


# Whether a click at tile's centre reaches the board: on screen, and no visible widget covers it.
func _is_clear(h: TurnInputCases.Harness, tile: Vector2i) -> bool:
	var point: Vector2 = _screen_point(h, tile)
	if not _root.get_viewport().get_visible_rect().has_point(point):
		return false
	var covers: Array[Control] = [h.bar, h.swap, h.message, h.controller.rune_bar]
	if h.host.top() != null:
		covers.append(h.host.top())
	for widget: Control in covers:
		if widget.is_visible_in_tree() and widget.get_global_rect().has_point(point):
			return false
	return true


func _click(h: TurnInputCases.Harness, tile: Vector2i) -> void:
	_click_at(_screen_point(h, tile))


# A click on tile when it reaches the board; when a panel covers it, the same accept on it that
# the click would make (confirm_tile), so the refusal checks don't hang on the layout.
func _click_board(h: TurnInputCases.Harness, tile: Vector2i) -> void:
	if _is_clear(h, tile):
		_click(h, tile)
	else:
		h.controller.confirm_tile(tile)


# Lays the panels out, as a frame's deferred sort would, and clicks control's centre.
func _click_control(h: TurnInputCases.Harness, control: Control) -> void:
	for _pass: int in 2:
		for node: Node in h.hud.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_click_at(control.get_global_rect().get_center())


func _click_at(point: Vector2) -> void:
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		_root.get_viewport().push_input(click, true)


# --- Checks ----------------------------------------------------------------------------------


# Why the last batch isn't rune_id's cast: rejected, no Rune used for it, or the rune still in
# the slots. Empty when it landed.
func _cast_landed(h: TurnInputCases.Harness, rune_id: String) -> String:
	var batch: CombatSession.FactBatch = h.last_batch()
	if batch == null or batch.is_rejected():
		return "rejected: %s" % ["no batch" if batch == null else batch.rejected_reason]
	var used: bool = false
	for fact: CombatFact in batch.facts:
		if fact.kind == CombatFact.Kind.RUNE_USED and fact.item_id == rune_id:
			used = true
	if not used:
		return "no Rune used fact"
	var left: PackedStringArray = h.session.state.rune_slots.get(0, PackedStringArray())
	if left.has(rune_id):
		return "still in the slots"
	return ""


func _rejections(h: TurnInputCases.Harness) -> PackedStringArray:
	var found: PackedStringArray = []
	for batch: CombatSession.FactBatch in h.batches:
		if batch.is_rejected():
			found.append(batch.rejected_reason)
	return found


# The objects facts break, in order.
static func _broken_objects(facts: Array[CombatFact]) -> PackedStringArray:
	var found: PackedStringArray = []
	for fact: CombatFact in facts:
		if (
				fact.kind == CombatFact.Kind.OBJECT_STATE_CHANGED
				and fact.key == MapObjects.Change.DESTROYED
		):
			found.append(fact.actor_id)
	return found


static func _outcome_text(is_defeated: bool, hp: int) -> String:
	return "defeated" if is_defeated else "HP %d" % [hp]


# Each listed command of option as text, sorted: unit and object runes their command's, Recall's
# each partner's.
static func _listed_keys(option: TurnInputModel.RuneOption) -> PackedStringArray:
	var keys: PackedStringArray = []
	for target: TurnInputModel.TargetOption in option.targets:
		if target.partners.is_empty():
			keys.append(_key(target.command as CastRuneCommand))
		for partner: TurnInputModel.TargetOption in target.partners:
			keys.append(_key(partner.command as CastRuneCommand))
	keys.sort()
	return keys


# Every cast of rune_id the validator accepts, tried on every unit, every ordered pair of units
# (with_pairs: a pair rune's; the validator refuses a pair for any other kind, and each try costs
# a sandbox) and every object's tile, as _listed_keys writes them.
static func _accepted_keys(
		session: CombatSession, rune_id: String, with_pairs: bool
) -> PackedStringArray:
	var state: CombatState = session.state
	var tries: Array[CastRuneCommand] = []
	for first_id: String in state.unit_ids():
		tries.append(CastRuneCommand.new(0, rune_id, first_id))
		if not with_pairs:
			continue
		for second_id: String in state.unit_ids():
			if second_id != first_id:
				tries.append(CastRuneCommand.new(0, rune_id, first_id, second_id))
	for placed: MapState.ObjectState in state.map.objects.values():
		tries.append(CastRuneCommand.new(0, rune_id, "", "", placed.tile))
	var found: Dictionary[String, bool] = {}
	for cast: CastRuneCommand in tries:
		if cast.validate(session).is_empty():
			found[_key(cast)] = true
	var keys: PackedStringArray = PackedStringArray(found.keys())
	keys.sort()
	return keys


static func _unvalidated(
		session: CombatSession, option: TurnInputModel.RuneOption
) -> PackedStringArray:
	var bad: PackedStringArray = []
	for target: TurnInputModel.TargetOption in option.targets:
		var commands: Array[Command] = target.commands.duplicate()
		for partner: TurnInputModel.TargetOption in target.partners:
			commands.append(partner.command)
		for command: Command in commands:
			if command == null or not command.validate(session).is_empty():
				bad.append(target.target_id)
	return bad


static func _key(cast: CastRuneCommand) -> String:
	if cast == null:
		return "none"
	return "%s>%s+%s@%s" % [cast.rune_id, cast.target_id, cast.second_target_id, cast.tile]


static func _has_rune(options: Array[TurnInputModel.ActionOption]) -> bool:
	for option: TurnInputModel.ActionOption in options:
		if option.kind == RUNE_KIND:
			return true
	return false


# --- Fixtures --------------------------------------------------------------------------------


# The M1 battle past its Start, on targeting_cases.gd's harness with the rune menu, seat 0 holding
# all seven runes and one of its units wounded; with_kegs, two kegs in a chain, in _kegs, placed
# before the board is drawn.
func _harness(with_kegs: bool = false) -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("runes: the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	var rune_bar: RuneBar = RUNE_BAR_SCENE.instantiate()
	for widget: Control in [h.bar, rune_bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.rune_menu_scene = RUNE_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.forecast_panel_scene = FORECAST_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	h.controller.rune_bar = rune_bar
	_root.add_child(h.controller)
	var state: CombatState = h.session.state
	for definition_id: String in RUNES:
		var label: String = _catalog.rune(definition_id).display_name
		CombatWorld.give_rune(h.session.engine, 0, h.session.ids.next_rune_id(label), definition_id)
	var wounded: String = state.units_of(PLAYER)[0]
	state.set_hp(wounded, state.get_hp(wounded) - WOUND)
	_kegs = []
	if with_kegs:
		_kegs = _place_keg_chain(h)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	h.session.batch_resolved.connect(h.record)
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	return h


# Places two powder kegs on free tiles, the second beside an enemy and the first in the second's
# blast, so Spark on the first chains into the second. Returns their object ids, first then
# second; empty when the map has no room.
func _place_keg_chain(h: TurnInputCases.Harness) -> Array[String]:
	var placed_ids: Array[String] = []
	var state: CombatState = h.session.state
	for enemy_id: String in state.units_of(ENEMY):
		var enemy_tile: Vector2i = state.tile_of(enemy_id)
		for second: Vector2i in MapObjects.KEG_BLAST.tiles(enemy_tile):
			if not _is_free(state, second):
				continue
			for first: Vector2i in MapObjects.KEG_BLAST.tiles(second):
				if first == second or first == enemy_tile or not _is_free(state, first):
					continue
				var layout: MapLayout = MapLayout.new()
				var keg_tiles: Array[Vector2i] = [first, second]
				for i: int in 2:
					var marker: MapLayout.Marker = layout.add_marker(
							MapLayout.MarkerKind.OBJECT_SPOT,
							keg_tiles[i],
							MapLayout.ObjectKind.POWDER_KEG
					)
					marker.index = KEG_INDEX + i
					marker.container_index = -1
				MapObjects.place_objects(h.session.engine, state, layout, h.session.ids)
				for i: int in 2:
					placed_ids.append(InstanceIdAllocator.object_id(KEG_INDEX + i))
				return placed_ids
	return placed_ids


# Whether tile is on the map, empty of units and objects, and walkable ground.
static func _is_free(state: CombatState, tile: Vector2i) -> bool:
	if state.grid.step(tile, Vector2i.ZERO) == CombatFact.NO_TILE:
		return false
	if not state.occupant_at(tile).is_empty() or not state.map.objects_at(tile).is_empty():
		return false
	return state.can_stand(tile, CombatGrid.MovementType.DEFAULT)


# The seat's first unit that can act and stands where a click reaches it: every cast's caster.
func _caster(h: TurnInputCases.Harness) -> String:
	var acting: PackedStringArray = TurnInputModel.acting_units(h.session, 0)
	for unit_id: String in acting:
		if _is_clear(h, h.session.state.tile_of(unit_id)):
			return unit_id
	return acting[0] if not acting.is_empty() else ""


# What definition_id's cast aims at, [target, second]: Mend the wounded unit, Aegis, Clarity and
# Haste the caster, Shatter the first enemy listed, Spark the first keg, Recall the first two of
# the seat's units listed. Empty when its rune lists none.
func _aim(
		h: TurnInputCases.Harness, definition_id: String, caster: String, kegs: Array[String]
) -> Array:
	var rune_id: String = _rune_id_of(h.session, definition_id)
	for option: TurnInputModel.RuneOption in TurnInputModel.rune_options(h.session, 0):
		if option.rune_id != rune_id or option.targets.is_empty():
			continue
		match definition_id:
			"mend":
				return [h.session.state.units_of(PLAYER)[0], ""]
			"aegis", "clarity", "haste":
				return [caster, ""]
			"spark":
				return [kegs[0] if not kegs.is_empty() else option.targets[0].target_id, ""]
			"recall":
				var first: TurnInputModel.TargetOption = option.targets[0]
				return [first.target_id, first.partners[0].target_id]
		return [option.targets[0].target_id, ""]
	return []


# The instance id of seat 0's rune of definition_id; empty for none.
func _rune_id_of(session: CombatSession, definition_id: String) -> String:
	for rune_id: String in session.state.rune_slots.get(0, PackedStringArray()):
		var definition: RuneDefinition = RuneResolver.definition_of(session.engine, rune_id)
		if definition != null and definition.id == definition_id:
			return rune_id
	return ""


# The content id of option's rune, through its effect as combat finds it.
static func _definition_id(session: CombatSession, option: TurnInputModel.RuneOption) -> String:
	var definition: RuneDefinition = RuneResolver.definition_of(session.engine, option.rune_id)
	return "" if definition == null else definition.id


func _send(h: TurnInputCases.Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)
