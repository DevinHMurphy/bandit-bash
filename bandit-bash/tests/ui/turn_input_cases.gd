# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     turn_input_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## Turn input's cases for tests/ui/run_all.gd (combat UI plan, UI2 row): what the action menu
## lists, the move and attack overlays against pathing and the validator, the drawn path against
## [method UnitTurnCommand.walk_path], cancel from every stage, End Turn and Start, a rejection,
## input during playback, a second move, and a smoke test that plays the M1 battle's player turns
## by input events. No autoload is named or needed.
##
## [b]The harness[/b] is the gameplay screen's turn-input pieces without the screen: the board,
## the HUD widgets under a [CanvasLayer] and a [BattleController], on the M1 battle begun as in
## [code]battle_view_cases.gd[/code]. Input goes through the root viewport
## ([method Viewport.push_input]), so the GUI, [method Node._input] and
## [method Node._unhandled_input] see it as they would in play.[br]
## [b]The twin[/b]: the smoke test begins a second M1 battle from the same seed and sends it the
## headless driver's commands directly (each player unit attacks the first enemy it can hit from
## the first reachable tile, row-major, else walks to the reachable tile nearest an enemy and
## waits); after every command made by input, both sessions' [method CombatSession.state_hash]
## must agree, so input sent exactly the driver's command.

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://scenes/ui/battle/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://scenes/ui/battle/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/battle/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://scenes/ui/battle/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/battle/confirm_dialog.tscn")

# Any fixed seed: no case compares golden numbers, and the twin uses the same one.
const SEED: int = 0x0C0FFEE

# Player phases a case may drive forward to find what it needs (an enemy in reach, an attack).
const MAX_PHASES: int = 8

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# The stages and actions the cases check, by name.
const SWAP: BattleController.Stage = BattleController.Stage.SWAP
const SWAP_PICKED: BattleController.Stage = BattleController.Stage.SWAP_PICKED
const IDLE: BattleController.Stage = BattleController.Stage.IDLE
const MOVE: BattleController.Stage = BattleController.Stage.MOVE
const ACTION: BattleController.Stage = BattleController.Stage.ACTION
const TARGET: BattleController.Stage = BattleController.Stage.TARGET
const CONFIRM: BattleController.Stage = BattleController.Stage.CONFIRM
const END_CONFIRM: BattleController.Stage = BattleController.Stage.END_CONFIRM
const WAIT_ACTION: TurnInputModel.ActionKind = TurnInputModel.ActionKind.WAIT
const ATTACK_ACTION: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null

# How many tiles _go_to() and _pick() reached with the mouse, and with the arrows.
var _mouse_picks: int = 0
var _key_picks: int = 0


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
		_check.call("turn input: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_view_model()
	_test_enemy_range_toggle()
	_test_cancel_steps()
	_test_end_turn_and_start()
	_test_rejection()
	_test_playback_blocks_input()
	_test_second_move()
	_test_smoke_turn()


# Before Start nothing acts; then, over several player phases, each acting unit's overlays match
# Pathing and the validator, every path walks, and the menu lists exactly the legal actions.
func _test_view_model() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	var session: CombatSession = h.session
	var state: CombatState = session.state
	var first: String = state.units_of(PLAYER)[0]
	_check.call("view-model: nothing acts in the opening swap window", (
			TurnInputModel.acting_units(session, 0).is_empty()
			and TurnInputModel.actions_at(session, first, []).is_empty()
			and TurnInputModel.end_turn_command(session, 0) == null
			and TurnInputModel.start_command(session, 0) != null
	))
	_send(h, StartCommand.new(0))

	var wrong_move: PackedStringArray = []
	var wrong_attack: PackedStringArray = []
	var wrong_path: PackedStringArray = []
	var wrong_menu: PackedStringArray = []
	var listed_attack: int = 0
	for _phase: int in MAX_PHASES:
		if session.is_finished:
			break
		for unit_id: String in TurnInputModel.acting_units(session, 0):
			_check_unit(session, unit_id, wrong_move, wrong_attack, wrong_path)
			for tile: Vector2i in _sample_tiles(session, unit_id):
				var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
				var found: String = _menu_mismatch(session, unit_id, path)
				if not found.is_empty():
					wrong_menu.append("%s at %s: %s" % [unit_id, tile, found])
				for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
						session, unit_id, path
				):
					if option.kind == ATTACK_ACTION:
						listed_attack += 1
		_drive_phase(h)
	_check.call("view-model: move tiles are Pathing.reach's, row-major", wrong_move.is_empty(), (
			"; ".join(wrong_move.slice(0, 3))
	))
	_check.call("view-model: an enemy is on an attack tile iff some legal attack reaches it", (
			wrong_attack.is_empty()
	), "; ".join(wrong_attack.slice(0, 3)))
	_check.call("view-model: every path to a move tile walks there (walk_path)", (
			wrong_path.is_empty()
	), "; ".join(wrong_path.slice(0, 3)))
	_check.call("view-model: the menu lists exactly the legal actions, in menu order", (
			wrong_menu.is_empty()
	), "; ".join(wrong_menu.slice(0, 3)))
	_check.call("view-model: the fixture reached a tile where Attack is listed", (
			listed_attack > 0
	))
	var acted: String = ""
	for unit_id: String in state.units_of(PLAYER):
		if state.unit(unit_id).has_acted and not state.unit(unit_id).is_second_move_pending:
			acted = unit_id
	if acted.is_empty() and not session.is_finished:
		var mover: String = TurnInputModel.acting_units(session, 0)[0]
		_send(h, UnitTurnCommand.new(0, mover, UnitTurnCommand.Action.WAIT))
		acted = mover
	_check.call("view-model: a unit that has acted gets no menu and no attack tiles", (
			acted.is_empty()
			or (
					TurnInputModel.actions_at(session, acted, []).is_empty()
					and TurnInputModel.attack_tiles(session, acted).is_empty()
					and not TurnInputModel.can_act(session, acted)
			)
	), acted)
	h.close()


# Accept on an enemy in IDLE toggles its range on the enemy range overlay, and off again.
func _test_enemy_range_toggle() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	_send(h, StartCommand.new(0))
	var enemy: String = h.session.state.units_of(ENEMY)[0]
	var tile: Vector2i = h.session.state.tile_of(enemy)
	var expected: Array[Vector2i] = TurnInputModel.enemy_range_tiles(h.session, enemy)
	var danger: Array[Vector2i] = DangerZone.tiles_for(h.session.engine, enemy)
	var covers_danger: bool = true
	for danger_tile: Vector2i in danger:
		covers_danger = covers_danger and expected.has(danger_tile)
	_key_to(h, tile)
	_press(&"ui_accept")
	var shown: Array[Vector2i] = h.view.get_enemy_range_overlay().shown_tiles()
	_check.call("enemy range: accept on an enemy shows its move and danger tiles", (
			h.controller.get_stage() == IDLE
			and h.controller.get_shown_enemies() == PackedStringArray([enemy])
			and shown == expected
			and not expected.is_empty()
			and covers_danger
	), "%d shown, %d expected" % [shown.size(), expected.size()])
	_press(&"ui_accept")
	_check.call("enemy range: accept on it again hides it", (
			h.controller.get_shown_enemies().is_empty()
			and h.view.get_enemy_range_overlay().shown_tiles().is_empty()
	))
	h.close()


# Cancel (ui_cancel, and the right mouse button once) steps back exactly one stage, and one panel,
# from every stage; in SWAP and IDLE it does nothing, leaving the key to the pause menu.
func _test_cancel_steps() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	var steps: PackedStringArray = []
	var c: BattleController = h.controller
	var state: CombatState = h.session.state
	_press(&"ui_cancel")
	_expect(steps, "SWAP cancel", c.get_stage() == SWAP and h.host.depth() == 0)
	var swapper: String = _first_swapper(h.session)
	if not swapper.is_empty():
		_key_to(h, state.tile_of(swapper))
		_press(&"ui_accept")
		_expect(steps, "SWAP -> SWAP_PICKED", c.get_stage() == SWAP_PICKED)
		_press(&"ui_cancel")
		_expect(steps, "SWAP_PICKED cancel -> SWAP", (
				c.get_stage() == SWAP and c.get_selected_unit().is_empty()
		))
	_press(&"end_turn")
	BattleViewCases.settle(h.view)
	_expect(steps, "end_turn in SWAP starts turn 1", (
			c.get_stage() == IDLE and state.turn == 1
	))
	_press(&"ui_cancel")
	_expect(steps, "IDLE cancel stays", c.get_stage() == IDLE)

	var found: Array = _find_targeted(h)
	if found.is_empty():
		_check.call("cancel: a unit with a targeted action is found", false, "none in reach")
		h.close()
		return
	var unit_id: String = found[0]
	var tile: Vector2i = found[1]
	var kind: TurnInputModel.ActionKind = found[2]
	_key_to(h, state.tile_of(unit_id))
	_press(&"ui_accept")
	_expect(steps, "IDLE -> MOVE", c.get_stage() == MOVE and c.get_selected_unit() == unit_id)
	_press(&"ui_cancel")
	_expect(steps, "MOVE cancel -> IDLE", (
			c.get_stage() == IDLE and c.get_selected_unit().is_empty()
			and h.view.get_move_overlay().shown_tiles().is_empty()
	))
	_key_to(h, state.tile_of(unit_id))
	_press(&"ui_accept")
	_key_to(h, tile)
	_press(&"ui_accept")
	_expect(steps, "MOVE -> ACTION", c.get_stage() == ACTION and h.host.depth() == 1)
	_press(&"ui_cancel")
	_expect(steps, "ACTION cancel -> MOVE", c.get_stage() == MOVE and h.host.depth() == 0)
	_press(&"ui_accept")
	_choose_kind(h, kind, steps)
	_expect(steps, "ACTION -> TARGET", c.get_stage() == TARGET and h.host.depth() == 2)
	_press(&"ui_cancel")
	_expect(steps, "TARGET cancel -> ACTION", (
			c.get_stage() == ACTION and h.host.depth() == 1
			and h.host.top() is ActionMenu and h.host.top().visible
	))
	_choose_kind(h, kind, steps)
	_press(&"ui_accept")
	_expect(steps, "TARGET -> CONFIRM", c.get_stage() == CONFIRM and h.host.depth() == 3)
	_press(&"ui_cancel")
	_expect(steps, "CONFIRM cancel -> TARGET", (
			c.get_stage() == TARGET and h.host.depth() == 2 and h.host.top() is TargetPicker
	))
	_press(&"ui_accept")
	_click_at(h, Vector2(1.0, 1.0), MOUSE_BUTTON_RIGHT)
	_expect(steps, "CONFIRM right click -> TARGET", (
			c.get_stage() == TARGET and h.host.depth() == 2
	))
	_press(&"ui_cancel")
	_press(&"ui_cancel")
	_press(&"ui_cancel")
	_expect(steps, "three more cancels -> IDLE", c.get_stage() == IDLE and h.host.depth() == 0)
	_press(&"end_turn")
	_expect(steps, "IDLE end_turn -> END_CONFIRM", (
			c.get_stage() == END_CONFIRM and h.host.top() is ConfirmDialog
	))
	_press(&"ui_cancel")
	_expect(steps, "END_CONFIRM cancel -> IDLE", c.get_stage() == IDLE and h.host.depth() == 0)
	_key_to(h, state.tile_of(unit_id))
	_press(&"ui_accept")
	_press(&"end_turn")
	_press(&"ui_cancel")
	_expect(steps, "END_CONFIRM from MOVE cancel -> MOVE", (
			c.get_stage() == MOVE and c.get_selected_unit() == unit_id
	))
	_check.call("cancel: steps back exactly one stage from every stage", steps.is_empty(), (
			"; ".join(steps)
	))
	_check.call("cancel: no command was sent", h.batches.size() == 1, str(h.batch_labels()))
	h.close()


# The swap window's Start button sends StartCommand; End Turn's button asks while units can act,
# and its Confirm sends EndTurnCommand.
func _test_end_turn_and_start() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	_check.call("start: the swap window shows before turn 1", (
			h.swap.visible and h.controller.get_stage() == SWAP
	))
	h.swap.get_start_button().pressed.emit()
	var start: CombatSession.FactBatch = h.last_batch()
	BattleViewCases.settle(h.view)
	_check.call("start: its button submits StartCommand, and turn 1 begins", (
			start != null and start.label == "start" and not start.is_rejected()
			and h.session.state.turn == 1 and not h.swap.visible
			and h.controller.get_stage() == IDLE
	), str(h.batch_labels()))
	var button: Button = h.bar.get_end_turn_button()
	var before: int = h.batches.size()
	_check.call("end turn: the button is live in IDLE", not button.disabled)
	button.pressed.emit()
	var dialog: ConfirmDialog = h.host.top() as ConfirmDialog
	_check.call("end turn: with units left to act it asks first, sending nothing", (
			dialog != null
			and dialog.get_message().contains("can still act")
			and h.batches.size() == before
	), dialog.get_message() if dialog != null else "no dialog")
	if dialog == null:
		h.close()
		return
	dialog.get_confirm_button().pressed.emit()
	var ended: CombatSession.FactBatch = h.last_batch()
	BattleViewCases.settle(h.view)
	_check.call("end turn: Confirm submits EndTurnCommand and the next player turn comes", (
			ended != null and ended.label == "end turn" and not ended.is_rejected()
			and (h.session.is_finished or h.session.state.turn == 2)
	), "%s, turn %d" % [h.batch_labels(), h.session.state.turn])
	h.close()


# A command the session rejects (the menu went stale) shows its reason and changes nothing.
func _test_rejection() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	_send(h, StartCommand.new(0))
	var state: CombatState = h.session.state
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	_key_to(h, state.tile_of(unit_id))
	_press(&"ui_accept")
	_press(&"ui_accept")
	var is_menu_open: bool = h.controller.get_stage() == ACTION
	# The menu is now stale: the same unit waits behind its back.
	_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	var hash_before: int = h.session.state_hash()
	var steps: PackedStringArray = []
	_choose_kind(h, WAIT_ACTION, steps)
	var batch: CombatSession.FactBatch = h.last_batch()
	_check.call("rejection: a stale Wait is sent and rejected", (
			is_menu_open and steps.is_empty() and batch != null and batch.is_rejected()
	), "%s %s" % [steps, h.batch_labels()])
	_check.call("rejection: its reason shows in the message", (
			batch != null
			and h.message.is_showing()
			and h.message.get_text().contains(batch.rejected_reason)
	), h.message.get_text())
	_check.call("rejection: nothing changed, and input is back at IDLE", (
			h.session.state_hash() == hash_before
			and h.controller.get_stage() == IDLE
			and h.host.depth() == 0
			and h.controller.is_accepting_input()
	))
	h.close()


# While a command's playback runs, accept, end_turn, clicks and the arrows do nothing; holding
# fast_forward sets FactPlayback.is_fast_forward and releasing it clears it.
func _test_playback_blocks_input() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	_press(&"end_turn")
	var is_playing: bool = not h.view.is_settled()
	var c: BattleController = h.controller
	var state: CombatState = h.session.state
	var unit_id: String = state.units_of(PLAYER)[0]
	var batches: int = h.batches.size()
	var cursor: Vector2i = c.get_cursor_tile()
	_key_to(h, state.tile_of(unit_id))
	_press(&"ui_accept")
	_click_tile(h, state.tile_of(unit_id))
	_press(&"end_turn")
	_check.call("playback: input is ignored while it runs", (
			is_playing
			and not c.is_accepting_input()
			and h.batches.size() == batches
			and c.get_cursor_tile() == cursor
			and c.get_selected_unit().is_empty()
			and h.host.depth() == 0
	), "playing %s, stage %d, batches %d" % [is_playing, c.get_stage(), h.batches.size()])
	_hold(&"fast_forward", true)
	var is_fast: bool = h.session.playback.is_fast_forward
	_hold(&"fast_forward", false)
	_check.call("playback: holding fast_forward sets is_fast_forward, releasing clears it", (
			is_fast and not h.session.playback.is_fast_forward
	))
	BattleViewCases.settle(h.view)
	_check.call("playback: input is taken again once it settles", (
			c.is_accepting_input() and c.get_stage() == IDLE
	))
	h.close()


# A unit with a second move pending (a Skirmisher effect, as the combat suite grants it) reopens
# the flow at its new tile, with only Wait, which sends the second move.
func _test_second_move() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	_send(h, StartCommand.new(0))
	var state: CombatState = h.session.state
	var unit_id: String = TurnInputModel.acting_units(h.session, 0)[0]
	var skirmisher: SetPermission = SetPermission.new()
	skirmisher.permission = CombatValue.Permission.MAY_MOVE_AFTER_ACTING
	skirmisher.allow = true
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = EffectTerms.Trigger.ALWAYS
	definition.operations.assign([skirmisher])
	h.session.engine.register(EffectInstance.new(
			"effect:test_skirmisher",
			definition,
			EffectOwner.for_unit(unit_id, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT,
			"effect:test_skirmisher"
	))
	var step: Vector2i = CombatFact.NO_TILE
	for tile: Vector2i in TurnInputModel.move_tiles(h.session, unit_id):
		if state.grid.distance(tile, state.tile_of(unit_id)) == 1:
			step = tile
			break
	_key_to(h, state.tile_of(unit_id))
	_press(&"ui_accept")
	_key_to(h, step)
	_press(&"ui_accept")
	var steps: PackedStringArray = []
	_choose_kind(h, WAIT_ACTION, steps)
	BattleViewCases.settle(h.view)
	var c: BattleController = h.controller
	_check.call("second move: the flow reopens at the unit's new tile", (
			step != CombatFact.NO_TILE
			and steps.is_empty()
			and state.unit(unit_id).is_second_move_pending
			and c.get_stage() == MOVE
			and c.get_selected_unit() == unit_id
			and c.get_cursor_tile() == step
			and state.tile_of(unit_id) == step
			and h.view.get_attack_overlay().shown_tiles().is_empty()
	), "stage %d, %s at %s, %s" % [c.get_stage(), unit_id, state.tile_of(unit_id), steps])
	var options: Array[TurnInputModel.ActionOption] = TurnInputModel.actions_at(
			h.session, unit_id, []
	)
	var second: UnitTurnCommand = null
	if options.size() == 1:
		second = options[0].command as UnitTurnCommand
	_check.call("second move: only Wait, which sends the second move", (
			options.size() == 1
			and options[0].kind == WAIT_ACTION
			and second != null
			and second.action == UnitTurnCommand.Action.MOVE
	))
	_press(&"ui_accept")
	_choose_kind(h, WAIT_ACTION, steps)
	BattleViewCases.settle(h.view)
	_check.call("second move: Wait spends it, and the unit is done", (
			steps.is_empty()
			and not state.unit(unit_id).is_second_move_pending
			and not TurnInputModel.can_act(h.session, unit_id)
			and c.get_stage() == IDLE
			and h.last_batch() != null and not h.last_batch().is_rejected()
	), "%s %s" % [steps, h.batch_labels()])
	h.close()


# The smoke test: the opening swap, Start, then whole player turns by input events (mouse where
# no widget covers the tile, else the arrows), each command checked against the twin.
func _test_smoke_turn() -> void:
	var h: Harness = _harness()
	if h == null:
		return
	var twin_run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var twin_battle: CombatEncounter = BattleViewCases.begin_m1(_catalog, _map, twin_run)
	var twin: CombatSession = twin_battle.get_session(0)
	var state: CombatState = h.session.state
	var problems: PackedStringArray = []
	var attacks: int = 0
	var turns: int = 0
	var path_checks: PackedStringArray = []

	var swapper: String = _first_swapper(h.session)
	if not swapper.is_empty():
		var partner: TurnInputModel.TargetOption = TurnInputModel.swap_partners(
				h.session, swapper
		)[0]
		_pick(h, state.tile_of(swapper))
		_pick(h, partner.tile)
		BattleViewCases.settle(h.view)
		_twin_send(twin_battle, twin, UnitTurnCommand.new(
				0, swapper, UnitTurnCommand.Action.OPENING_SWAP, partner.target_id
		))
		_compare(h, twin, "swap", problems)
	_press(&"end_turn")
	BattleViewCases.settle(h.view)
	_twin_send(twin_battle, twin, StartCommand.new(0))
	_compare(h, twin, "start", problems)

	for _phase: int in MAX_PHASES:
		if h.session.is_finished or (turns > 0 and attacks > 0):
			break
		for unit_id: String in state.units_of(PLAYER):
			if h.session.is_finished or not problems.is_empty():
				break
			if not state.has_unit(unit_id) or state.unit(unit_id).has_acted:
				continue
			var turn: UnitTurnCommand = _driver_turn(twin, unit_id)
			var end: Vector2i = state.tile_of(unit_id)
			if not turn.path.is_empty():
				end = turn.path[turn.path.size() - 1]
			_pick(h, state.tile_of(unit_id))
			_go_to(h, end)
			var drawn: Array[Vector2i] = h.view.get_path_preview().shown_tiles()
			var trial: EffectEngine = h.session.engine.copy_for_sandbox(ForcedRolls.new())
			var trial_state: CombatState = trial.state
			var check: CombatGrid.PathCheck = UnitTurnCommand.walk_path(
					trial, trial_state, unit_id, drawn
			)
			if drawn != turn.path or not check.is_legal or trial_state.tile_of(unit_id) != end:
				path_checks.append("%s: drawn %s, driver %s, %s" % [
					unit_id, drawn, turn.path, check.reason,
				])
			_pick(h, end)
			var steps: PackedStringArray = []
			if turn.action == UnitTurnCommand.Action.ATTACK:
				_choose_kind(h, ATTACK_ACTION, steps)
				_choose_target(h, turn.target_id, steps)
				_press(&"ui_accept")
				attacks += 1
			else:
				_choose_kind(h, WAIT_ACTION, steps)
			problems.append_array(steps)
			BattleViewCases.settle(h.view)
			_twin_send(twin_battle, twin, turn)
			_compare(h, twin, turn.get_label(), problems)
		if h.session.is_finished or not problems.is_empty():
			break
		_press(&"end_turn")
		if h.host.top() is ConfirmDialog:
			problems.append("end turn asked with every unit done")
			_press(&"ui_accept")
		BattleViewCases.settle(h.view)
		_twin_send(twin_battle, twin, EndTurnCommand.new(0))
		_compare(h, twin, "end turn", problems)
		turns += 1
	_check.call("smoke: whole player turns played by input match the headless driver's", (
			problems.is_empty() and turns > 0 and attacks > 0
	), "turns %d, attacks %d; %s" % [turns, attacks, "; ".join(problems.slice(0, 3))])
	_check.call("smoke: the path drawn is the driver's walk, and walk_path walks it", (
			path_checks.is_empty()
	), "; ".join(path_checks.slice(0, 3)))
	_check.call("smoke: the mouse hovered and picked tiles, the arrows the rest", (
			_mouse_picks > 0
	), "%d by mouse, %d by arrow keys" % [_mouse_picks, _key_picks])
	print("      (smoke: %d tiles by mouse, %d by arrow keys)" % [_mouse_picks, _key_picks])
	_check.call("smoke: the board agrees with the state after it", (
			h.view.mismatches().is_empty()
	), "; ".join(h.view.mismatches()))
	twin_run.close()
	h.close()


# --- Fixtures --------------------------------------------------------------------------------


func _harness() -> Harness:
	var h: Harness = Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("turn input: the M1 battle begins", false, "begin_battle gave no battle")
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
	for widget: Control in [h.bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	_root.add_child(h.controller)
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	h.session.batch_resolved.connect(h.record)
	return h


# Sends command straight to the harness's encounter (not by input) and lets it play.
func _send(h: Harness, command: Command) -> void:
	h.battle.submit(command, h.session.session_id)
	h.battle.resolve_queued()
	BattleViewCases.settle(h.view)


# The driver's player phase on the harness: each acting unit's driver turn, then End Turn.
func _drive_phase(h: Harness) -> void:
	for unit_id: String in h.session.state.units_of(PLAYER):
		if h.session.is_finished:
			return
		if TurnInputModel.can_act(h.session, unit_id):
			_send(h, _driver_turn(h.session, unit_id))
	if not h.session.is_finished:
		_send(h, EndTurnCommand.new(0))


func _twin_send(battle: CombatEncounter, twin: CombatSession, command: Command) -> void:
	battle.submit(command, twin.session_id)
	for batch: CombatSession.FactBatch in battle.resolve_queued():
		twin.playback.play_all()
		if batch.is_rejected():
			push_warning("TurnInputCases: the twin rejected %s - %s" % [
				batch.label, batch.rejected_reason,
			])


func _compare(h: Harness, twin: CombatSession, label: String, problems: PackedStringArray) -> void:
	var batch: CombatSession.FactBatch = h.last_batch()
	if batch == null or batch.is_rejected():
		problems.append("%s: %s" % [label, "nothing sent" if batch == null else batch.rejected_reason])
	elif h.session.state_hash() != twin.state_hash():
		problems.append("%s: the state differs from the twin's after %s" % [label, batch.label])


# The headless driver's turn for unit_id (class doc), read from session.
static func _driver_turn(session: CombatSession, unit_id: String) -> UnitTurnCommand:
	var state: CombatState = session.state
	var reach: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
	var ends: Array[Vector2i] = []
	ends.assign(reach.keys())
	ends.sort_custom(MapLayout.is_before)
	var foes: PackedStringArray = state.units_of(ENEMY)
	for tile: Vector2i in ends:
		for foe: String in foes:
			var attack: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, UnitTurnCommand.Action.ATTACK, foe, _driver_walk(session, unit_id, tile)
			)
			if attack.validate(session).is_empty():
				return attack
	var goal: Vector2i = state.tile_of(unit_id)
	var nearest: int = -1
	for tile: Vector2i in ends:
		for foe: String in foes:
			var distance: int = state.grid.distance(tile, state.tile_of(foe))
			if nearest < 0 or distance < nearest:
				nearest = distance
				goal = tile
	return UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.WAIT, "", _driver_walk(session, unit_id, goal)
	)


# The driver's walk (battle_view_cases.gd's): a cheapest walk stepping back through the flood's
# costs, neighbors in CombatGrid order; empty for the unit's own tile.
static func _driver_walk(
		session: CombatSession, unit_id: String, tile: Vector2i
) -> Array[Vector2i]:
	var state: CombatState = session.state
	var mover: CombatUnitState = state.unit(unit_id)
	var walk: Array[Vector2i] = []
	if tile == mover.tile:
		return walk
	var costs: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(session.engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	walk.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var before: Vector2i = CombatFact.NO_TILE
		for next: Vector2i in state.grid.neighbors(at):
			if costs.has(next) and costs[next] + entry == costs[at]:
				before = next
				break
		if before == CombatFact.NO_TILE:
			walk.clear()
			return walk
		walk.push_front(before)
		at = before
	return walk


# The first of seat 0's units with a swap partner; empty outside the window or with none.
static func _first_swapper(session: CombatSession) -> String:
	for unit_id: String in session.state.units_of(PLAYER):
		if not TurnInputModel.swap_partners(session, unit_id).is_empty():
			return unit_id
	return ""


# A unit, a move tile and an action kind with targets there, driving the battle forward until one
# turns up: [unit_id, tile, kind], or empty.
func _find_targeted(h: Harness) -> Array:
	for _phase: int in MAX_PHASES:
		if h.session.is_finished:
			return []
		for unit_id: String in TurnInputModel.acting_units(h.session, 0):
			for tile: Vector2i in TurnInputModel.move_tiles(h.session, unit_id):
				var path: Array[Vector2i] = TurnInputModel.path_to(h.session, unit_id, tile)
				for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
						h.session, unit_id, path
				):
					if option.has_targets():
						return [unit_id, tile, option.kind]
		_drive_phase(h)
	return []


# The unit's own tile, its farthest move tile and, when it has one, the driver's attack tile.
static func _sample_tiles(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [session.state.tile_of(unit_id)]
	var moves: Array[Vector2i] = TurnInputModel.move_tiles(session, unit_id)
	var origin: Vector2i = session.state.tile_of(unit_id)
	var far: Vector2i = origin
	for tile: Vector2i in moves:
		if session.state.grid.distance(tile, origin) > session.state.grid.distance(far, origin):
			far = tile
	if not tiles.has(far):
		tiles.append(far)
	var turn: UnitTurnCommand = _driver_turn(session, unit_id)
	if turn.action == UnitTurnCommand.Action.ATTACK and not turn.path.is_empty():
		var end: Vector2i = turn.path[turn.path.size() - 1]
		if not tiles.has(end):
			tiles.append(end)
	return tiles


# Records why unit_id's move tiles, attack tiles or paths disagree with Pathing and the validator.
static func _check_unit(
		session: CombatSession,
		unit_id: String,
		wrong_move: PackedStringArray,
		wrong_attack: PackedStringArray,
		wrong_path: PackedStringArray
) -> void:
	var state: CombatState = session.state
	var moves: Array[Vector2i] = TurnInputModel.move_tiles(session, unit_id)
	var reach: Array[Vector2i] = []
	reach.assign(Pathing.reach(session.engine, state, unit_id).keys())
	reach.sort_custom(MapLayout.is_before)
	if moves != reach:
		wrong_move.append("%s: %d tiles, reach %d" % [unit_id, moves.size(), reach.size()])
	var attack_tiles: Array[Vector2i] = TurnInputModel.attack_tiles(session, unit_id)
	var unit: CombatUnitState = state.unit(unit_id)
	var weapons: PackedStringArray = [""]
	if not unit.stowed_weapon_id.is_empty():
		weapons.append(unit.stowed_weapon_id)
	for enemy_id: String in state.units_of(ENEMY):
		var can_hit: bool = false
		for tile: Vector2i in moves:
			var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
			for weapon_id: String in weapons:
				var attack: UnitTurnCommand = UnitTurnCommand.new(
						0, unit_id, UnitTurnCommand.Action.ATTACK, enemy_id, path
				)
				attack.weapon_id = weapon_id
				if attack.validate(session).is_empty():
					can_hit = true
					break
			if can_hit:
				break
		var is_marked: bool = attack_tiles.has(state.tile_of(enemy_id))
		if is_marked != can_hit:
			wrong_attack.append("%s on %s: marked %s, can hit %s" % [
				unit_id, enemy_id, is_marked, can_hit,
			])
	for tile: Vector2i in moves:
		var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
		var trial: EffectEngine = session.engine.copy_for_sandbox(ForcedRolls.new())
		var trial_state: CombatState = trial.state
		var check: CombatGrid.PathCheck = UnitTurnCommand.walk_path(
				trial, trial_state, unit_id, path
		)
		if not check.is_legal or trial_state.tile_of(unit_id) != tile:
			wrong_path.append("%s to %s: %s" % [unit_id, tile, check.reason])


# Why actions_at for unit_id after path isn't exactly the legal actions in menu order; empty when
# it is. Each listed command is checked again, and each action not listed is tried against every
# unit on the map and found illegal.
static func _menu_mismatch(
		session: CombatSession, unit_id: String, path: Array[Vector2i]
) -> String:
	var state: CombatState = session.state
	var options: Array[TurnInputModel.ActionOption] = TurnInputModel.actions_at(
			session, unit_id, path
	)
	var listed: Dictionary[int, bool] = {}
	var last: int = -1
	for option: TurnInputModel.ActionOption in options:
		if option.kind <= last:
			return "out of order"
		last = option.kind
		listed[option.kind] = true
		var commands: Array[Command] = []
		if option.has_targets():
			for target: TurnInputModel.TargetOption in option.targets:
				commands.append(target.command)
		else:
			commands.append(option.command)
		for command: Command in commands:
			var reason: String = command.validate(session)
			if not reason.is_empty():
				return "%s listed but rejected: %s" % [option.label, reason]
	if not listed.has(WAIT_ACTION):
		return "no Wait"
	var tries: Dictionary[int, UnitTurnCommand.Action] = {
		ATTACK_ACTION: UnitTurnCommand.Action.ATTACK,
		TurnInputModel.ActionKind.STAFF: UnitTurnCommand.Action.STAFF,
		TurnInputModel.ActionKind.ITEM: UnitTurnCommand.Action.ITEM,
		TurnInputModel.ActionKind.SHOVE: UnitTurnCommand.Action.SHOVE,
		TurnInputModel.ActionKind.SWAP: UnitTurnCommand.Action.SWAP_WEAPON,
	}
	var targets: PackedStringArray = state.unit_ids()
	targets.append("")
	for kind: int in tries:
		if listed.has(kind):
			continue
		for target_id: String in targets:
			var command: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, tries[kind], target_id, path
			)
			command.item_id = state.unit(unit_id).pouch_item_id
			if command.validate(session).is_empty():
				return "%s is legal on %s but not listed" % [
					TurnInputModel.ACTION_LABELS[kind], target_id,
				]
	return ""


# --- Input -----------------------------------------------------------------------------------


# Every event goes in as the root viewport's own coordinates: a mouse position is a point in its
# visible rect, not a window pixel the viewport would rescale.
func _push(event: InputEvent) -> void:
	_root.get_viewport().push_input(event, true)


# A press and release of action.
func _press(action: StringName) -> void:
	_hold(action, true)
	_hold(action, false)


func _hold(action: StringName, is_down: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = is_down
	_push(event)


# Where tile's centre is on screen. The camera applies a pan or zoom on its next process, and the
# cases run inside one frame, so its scroll is applied first, as a frame would.
func _screen_point(h: Harness, tile: Vector2i) -> Vector2:
	var camera: Camera2D = _root.get_viewport().get_camera_2d()
	if camera != null:
		camera.force_update_scroll()
	return h.view.get_global_transform_with_canvas() * h.view.tile_to_position(tile)


# Whether a click at tile's centre reaches the board: it is on screen and no visible widget
# covers it.
func _is_clear(h: Harness, tile: Vector2i) -> bool:
	var point: Vector2 = _screen_point(h, tile)
	if not _root.get_viewport().get_visible_rect().has_point(point):
		return false
	var covers: Array[Control] = [h.bar, h.swap, h.message]
	if h.host.top() != null:
		covers.append(h.host.top())
	for widget: Control in covers:
		if widget.is_visible_in_tree() and widget.get_global_rect().has_point(point):
			return false
	return true


func _hover(h: Harness, tile: Vector2i) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _screen_point(h, tile)
	motion.global_position = motion.position
	_push(motion)


func _click_tile(h: Harness, tile: Vector2i) -> void:
	_click_at(h, _screen_point(h, tile), MOUSE_BUTTON_LEFT)


func _click_at(_h: Harness, point: Vector2, button: MouseButton) -> void:
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = button
		click.pressed = is_down
		_push(click)


# Moves the cursor to tile with the arrow keys.
func _key_to(h: Harness, tile: Vector2i) -> void:
	var cursor: Vector2i = h.controller.get_cursor_tile()
	var dx: int = tile.x - cursor.x
	var dy: int = tile.y - cursor.y
	for _i: int in absi(dx):
		_press(&"ui_right" if dx > 0 else &"ui_left")
	for _i: int in absi(dy):
		_press(&"ui_down" if dy > 0 else &"ui_up")


# Hovers tile with the mouse where nothing covers it, else moves there with the arrows.
func _go_to(h: Harness, tile: Vector2i) -> void:
	if _is_clear(h, tile):
		_hover(h, tile)
		_mouse_picks += 1
	else:
		_key_to(h, tile)
		_key_picks += 1


# Confirms tile: a left click where nothing covers it, else the arrows and ui_accept.
func _pick(h: Harness, tile: Vector2i) -> void:
	if _is_clear(h, tile):
		_click_tile(h, tile)
		_mouse_picks += 1
	else:
		_key_to(h, tile)
		_press(&"ui_accept")
		_key_picks += 1


# Presses the open action menu's row for kind with ui_down and ui_accept.
func _choose_kind(h: Harness, kind: TurnInputModel.ActionKind, problems: PackedStringArray) -> void:
	var menu: ActionMenu = h.host.top() as ActionMenu
	if menu == null:
		problems.append("no action menu for %s" % [TurnInputModel.ACTION_LABELS[kind]])
		return
	var index: int = -1
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == kind:
			index = i
	if index < 0:
		problems.append("%s not in the menu" % [TurnInputModel.ACTION_LABELS[kind]])
		return
	_choose_row(menu.get_rows(), index, problems)


# Presses the open target picker's row for target_id with ui_down and ui_accept.
func _choose_target(h: Harness, target_id: String, problems: PackedStringArray) -> void:
	var picker: TargetPicker = h.host.top() as TargetPicker
	if picker == null:
		problems.append("no target picker for %s" % [target_id])
		return
	var index: int = -1
	var options: Array[TurnInputModel.TargetOption] = picker.get_options()
	for i: int in options.size():
		if options[i].target_id == target_id:
			index = i
	if index < 0:
		problems.append("%s not in the target picker" % [target_id])
		return
	_choose_row(picker.get_rows(), index, problems)


func _choose_row(rows: Array[Button], index: int, problems: PackedStringArray) -> void:
	for _i: int in index:
		_press(&"ui_down")
	var focused: Control = _root.get_viewport().gui_get_focus_owner()
	if focused != rows[index]:
		problems.append("row %d isn't focused (%s is)" % [index, focused])
		return
	_press(&"ui_accept")


func _expect(problems: PackedStringArray, step: String, passed: bool) -> void:
	if not passed:
		problems.append(step)


## The turn-input pieces of the gameplay screen on one M1 battle (class doc).
class Harness:
	extends RefCounted

	## The run that holds the battle.
	var run: CampaignSession = null
	## The battle.
	var battle: CombatEncounter = null
	## Seat 0's map.
	var session: CombatSession = null
	## The board.
	var view: BattleView = null
	## Where the widgets are.
	var hud: CanvasLayer = null
	## The status line and End Turn.
	var bar: TurnBar = null
	## The opening swap window.
	var swap: SwapWindow = null
	## The panel stack.
	var host: PanelHost = null
	## The rejection message.
	var message: BattleMessage = null
	## Turn input.
	var controller: BattleController = null
	## Every batch the session resolved or rejected, in order.
	var batches: Array[CombatSession.FactBatch] = []

	## Keeps [param batch].
	func record(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)

	## The last batch; null for none.
	func last_batch() -> CombatSession.FactBatch:
		return null if batches.is_empty() else batches[batches.size() - 1]

	## Each batch's label, for failure details.
	func batch_labels() -> PackedStringArray:
		var labels: PackedStringArray = []
		for batch: CombatSession.FactBatch in batches:
			labels.append(batch.label + (" (rejected)" if batch.is_rejected() else ""))
		return labels

	## Frees the nodes and closes the run.
	func close() -> void:
		if session.batch_resolved.is_connected(record):
			session.batch_resolved.disconnect(record)
		controller.free()
		hud.free()
		view.free()
		run.close()
