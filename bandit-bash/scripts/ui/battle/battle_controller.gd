# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_controller.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name BattleController
extends Node
## Turns the player's input on the battle screen into commands: the tile cursor, selecting a
## unit, its move and attack tiles and path, the action menu, the target picker, confirm, End
## Turn, the opening swap window and Start (combat UI plan, UI2; question 6's flow, ported from
## Godot_FE's player FSM).
##
## [b]Commands only:[/b] it never changes combat state. What it offers comes from
## [TurnInputModel], whose every action already passed its command's own validation; confirming
## submits that command to the encounter for the seat and resolves it. A rejection
## ([signal CombatSession.command_rejected]) shows its reason in the [BattleMessage]. Panels go
## through one [PanelHost]: each stage that opens a panel pushes one, and cancel pops exactly one.
## Input waits while playback runs ([method BattleView.is_settled]), except fast-forward and the
## skip.[br]
## [b]Forecast:[/b] an attack, a staff or a shove is confirmed on a [ForecastPanel]
## ([ForecastViewModel]), which cycles the target's weapons ([method cycle_weapon]).
## [b]Move preview:[/b] hovering a move tile requests a [MovePreview]; [method run_preview_frame]
## runs at most one per frame, for the newest hover, and [MovePreviewMarks] draws it.[br]
## [BattleScreen] binds it to the seat's map ([method bind]); its widgets are the nodes set in its
## exports, which the gameplay scene points at.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
##
## @todo: TOD-001 - Show the danger zone in the swap window (question 12) and on
## toggle_danger_zone; both are UI4's (DangerZone, intents).

# ============================================================
# INPUT MAP SETUP (Project Settings -> Input Map; ui_* are Godot's built-in actions):
#   "ui_up" / "ui_down" /   -> arrow keys     (IDLE, MOVE, SWAP, SWAP_PICKED: move the cursor one
#   "ui_left" / "ui_right"                       tile. In a panel the focused row takes them first
#                                                and moves focus instead)
#   (mouse motion)                            (IDLE, MOVE, TARGET, SWAP, SWAP_PICKED: the cursor
#                                                follows the mouse over the board)
#   "ui_accept"             -> Enter, Space   (on the board: confirm the cursor's tile. In a panel
#                                                the focused row takes it first and is pressed)
#   (Left Mouse Button)                       (confirm the tile under the mouse; on a panel row the
#                                                row takes the click)
#   "ui_cancel"             -> Escape         (step back one stage. Read in _input, before the
#                                                pause menu's _unhandled_input, and only consumed
#                                                when there is a stage to step back from: in IDLE
#                                                and SWAP, and while input is ignored (below), it
#                                                is left to open the pause menu -- deliberate
#                                                reuse of one key by stage)
#   (Right Mouse Button)                      (step back one stage, as ui_cancel; nothing in IDLE
#                                                and SWAP)
#   "end_turn"              -> T              (IDLE, MOVE: End Turn, asking first while units can
#                                                act. SWAP, SWAP_PICKED: Start -- deliberate reuse,
#                                                the keyboard's way to Start. Harmless elsewhere)
#   "fast_forward"          -> F (hold)       (any stage, even during playback: while held, the
#                                                board plays its waits and animations
#                                                BattleView.fast_forward_speed times faster, in
#                                                order; released, normal speed)
#   "skip_playback"         -> X              (any stage, while playback runs: the board skips it
#                                                behind a fade to black, BattleView.skip_playback.
#                                                Harmless with nothing playing or during a skip)
#   "toggle_danger_zone"    -> R              (bound for UI4; not read here)
#   "cycle_weapon"          -> C              (CONFIRM with the forecast panel open: the forecast
#                                                and the command move to the target's next weapon,
#                                                wrapping. Harmless elsewhere, and with one weapon)
#   "toggle_save_debug"     -> F3             (read by the save debug panel; not read here)
# While a command's playback runs, the map's combat is over, or the seat has no turn, every input
# but fast_forward and skip_playback is ignored: that guard is deliberate, not a missing check.
# ============================================================

# --- Turn input stage (meaningful once bind() has a session) -------------------------------
# INACTIVE:    nothing to do: unbound, the combat is over, the seat has no turn (another phase,
#              or it ended its turn), or a sent command's playback is running. Input is ignored
#              and the board shows no selection.
# SWAP:        the opening swap window, before the seat's Start. Cursor free. Accept on one of
#              the seat's units that has a swap partner picks it (SWAP_PICKED). end_turn or the
#              window's Start sends StartCommand. Cancel is left to the pause menu.
# SWAP_PICKED: a unit picked to swap; its partners' tiles show on the move overlay. Accept on a
#              partner sends the swap (UnitTurnCommand OPENING_SWAP) with no confirm; accept
#              elsewhere is inert. Cancel -> SWAP.
# IDLE:        the seat's player phase, nothing selected. Cursor free. Accept on a unit that can
#              act selects it (MOVE); on an enemy toggles its range on the enemy range overlay
#              (Godot_FE toggle_selected_unit); elsewhere inert -- Godot_FE's game menu on an
#              empty tile is not ported, End Turn has its own key and button.
# MOVE:        a unit selected: its move and attack tiles drawn, and the path to the cursor while
#              the cursor is on a move tile, with that tile's move preview (requested on each
#              hover, run by run_preview_frame, cleared off a move tile and on leaving MOVE).
#              Accept on a move tile (its own included) opens the action menu (ACTION); elsewhere
#              inert. Cancel -> IDLE.
# ACTION:      the action menu on top of PanelHost; the cursor stays on the picked tile, and board
#              clicks and hovers are inert. An action with targets opens the target picker
#              (TARGET); Wait and Swap send their command at once, as Godot_FE's Wait does.
#              Cancel -> MOVE.
# TARGET:      the target picker; the cursor (target colour) shows the focused row's target or
#              follows the mouse. A row, or accept on a target's tile, opens the confirm
#              (CONFIRM). Cancel -> ACTION.
# CONFIRM:     Attack, Staff, Shove: the forecast panel (with forecast_panel_scene set), whose
#              Confirm sends the command of the weapon shown; cycle_weapon and Next weapon move to
#              the target's next weapon. Item, Rune, or no forecast scene: the confirm dialog,
#              whose Confirm sends the command. Cancel or Back -> TARGET, back to the first weapon.
# END_CONFIRM: End Turn's question while units can still act: Confirm sends EndTurnCommand.
#              Cancel or Back -> the stage it was asked from (IDLE or MOVE).
# There is no separate forecast stage: the forecast is CONFIRM's panel, as Godot_FE's forecast
# took the confirm. There is no walk before the action menu either: Godot_FE moved the unit first,
# but here the move and the action are one command, so the token stays put until it plays.
# Cycling changes no state: each weapon has its own command (TargetOption.commands), where
# Godot_FE equipped the weapon on the unit at each step and left it equipped on Back.
# Global: cancel pops exactly one stage (_history), and one panel with it. Sending a command
# flushes every panel, stage and mark and waits in INACTIVE; when its playback settles the stage
# is rebuilt from the session:
# a rejection's reason shows and the flow returns to IDLE, a unit with a second move pending
# reopens MOVE on its new tile, and otherwise IDLE, SWAP or INACTIVE as the session stands.
## The steps of turn input; see the block above.
enum Stage {
	## Nothing to do; input is ignored.
	INACTIVE = 0,
	## The opening swap window, nothing picked.
	SWAP = 1,
	## The opening swap window, one unit picked.
	SWAP_PICKED = 2,
	## The player phase, nothing selected.
	IDLE = 3,
	## A unit selected, picking its tile.
	MOVE = 4,
	## The action menu.
	ACTION = 5,
	## The target picker.
	TARGET = 6,
	## The confirm dialog before a targeted action is sent.
	CONFIRM = 7,
	## End Turn's question while units can still act.
	END_CONFIRM = 8,
}

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

@export_group("Panels")

## The action menu scene ([ActionMenu]).[br]
## [b]Unset:[/b] picking a tile opens nothing and an error is reported.
@export var action_menu_scene: PackedScene = null

## The target picker scene ([TargetPicker]).[br]
## [b]Unset:[/b] actions with targets open nothing and an error is reported.
@export var target_picker_scene: PackedScene = null

## The confirm dialog scene ([ConfirmDialog]), for targeted actions and End Turn.[br]
## [b]Unset:[/b] no confirm opens and an error is reported.
@export var confirm_dialog_scene: PackedScene = null

## The forecast panel scene ([ForecastPanel]), the confirm of an attack, a staff or a shove.[br]
## [b]Unset:[/b] those confirm on the confirm dialog, with no forecast.
@export var forecast_panel_scene: PackedScene = null

@export_group("Widgets")

## The board: its cursor, overlays and path, and the playback input waits on.[br]
## [b]Unset:[/b] [method bind] reports an error and turn input stays off.
@export var view: BattleView = null

## The panel stack the menu, picker and dialogs open on.[br]
## [b]Unset:[/b] [method bind] reports an error and turn input stays off.
@export var panel_host: PanelHost = null

## The status line and End Turn button.[br]
## [b]Unset:[/b] no status shows; the end_turn action still works.
@export var turn_bar: TurnBar = null

## The opening swap window's panel and Start button.[br]
## [b]Unset:[/b] no hint shows; the end_turn action still sends Start.
@export var swap_window: SwapWindow = null

## Where rejection reasons show.[br]
## [b]Unset:[/b] rejections are only logged by the session.
@export var message: BattleMessage = null

## The move preview on the board, a child of [member view].[br]
## [b]Unset:[/b] no move preview is requested or run.
@export var move_preview_marks: MovePreviewMarks = null

@export_group("")

var _encounter: CombatEncounter = null
var _session: CombatSession = null
var _seat: int = -1

var _stage: Stage = Stage.INACTIVE

# The stage to return to from each stage entered by a step forward; cancel pops one.
var _history: Array[Stage] = []

var _cursor: Vector2i = CombatFact.NO_TILE

# The selection, filled as the flow steps forward and cleared as it steps back.
var _unit_id: String = ""
var _move_tiles: Array[Vector2i] = []
var _attack_tiles: Array[Vector2i] = []
var _is_move_tile: Dictionary[Vector2i, bool] = {}
var _end_tile: Vector2i = CombatFact.NO_TILE
var _path: Array[Vector2i] = []
var _action: TurnInputModel.ActionOption = null
var _target: TurnInputModel.TargetOption = null

# In CONFIRM, which of _target.commands is shown and sent.
var _weapon_index: int = 0

# The forecast panel open in CONFIRM; null with the confirm dialog or outside CONFIRM.
var _forecast_panel: ForecastPanel = null

# The newest hover's move preview, waiting for run_preview_frame.
var _previews: MovePreview.Queue = MovePreview.Queue.new()

# What accept on a tile picks in TARGET (the action's targets) and SWAP_PICKED (the partners).
var _targets_by_tile: Dictionary[Vector2i, TurnInputModel.TargetOption] = {}

# The enemies whose range is toggled on, in the order they were toggled.
var _shown_enemies: PackedStringArray = []

# A command was sent and its playback hasn't settled.
var _is_waiting: bool = false

# The unit the command being waited on acted for; empty for none.
var _sent_unit_id: String = ""

# The rejection of the command last sent; empty when it resolved.
var _rejection: String = ""


func _ready() -> void:
	_show_widgets(false)
	if turn_bar != null:
		turn_bar.end_turn_pressed.connect(_on_turn_bar_end_turn_pressed)
	if swap_window != null:
		swap_window.start_pressed.connect(_on_swap_window_start_pressed)


func _exit_tree() -> void:
	unbind()


func _input(event: InputEvent) -> void:
	if not _is_cancel(event) or not is_accepting_input():
		return
	if step_back():
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _session == null:
		return
	if event.is_action(&"fast_forward") and not event.is_echo():
		view.set_fast_forward(event.is_pressed())
		return
	if event.is_action_pressed(&"skip_playback"):
		view.skip_playback()
		return
	if not is_accepting_input():
		return
	var mouse: InputEventMouse = event as InputEventMouse
	if mouse != null:
		_read_mouse(mouse)
	elif event.is_action_pressed(&"ui_accept"):
		confirm_tile(_cursor)
	elif event.is_action_pressed(&"end_turn"):
		request_end_turn()
	elif event.is_action_pressed(&"cycle_weapon"):
		cycle_weapon()
	elif event.is_action_pressed(&"ui_up", true):
		_step_cursor(Vector2i.UP)
	elif event.is_action_pressed(&"ui_down", true):
		_step_cursor(Vector2i.DOWN)
	elif event.is_action_pressed(&"ui_left", true):
		_step_cursor(Vector2i.LEFT)
	elif event.is_action_pressed(&"ui_right", true):
		_step_cursor(Vector2i.RIGHT)


func _process(_delta: float) -> void:
	run_preview_frame()


## Takes turn input for [param seat] on [param session], a map of [param encounter], and shows the
## widgets. Binding again replaces the map.
func bind(encounter: CombatEncounter, session: CombatSession, seat: int) -> void:
	unbind()
	if view == null or panel_host == null:
		push_error("BattleController: the view and the panel host must be set")
		return
	_encounter = encounter
	_session = session
	_seat = seat
	_session.command_rejected.connect(_on_session_command_rejected)
	view.settled.connect(_on_view_settled)
	_show_widgets(true)
	var units: PackedStringArray = TurnInputModel.acting_units(session, seat)
	if units.is_empty():
		for unit_id: String in session.state.units_of(PLAYER):
			if session.state.seat_of(unit_id) == seat:
				units.append(unit_id)
	move_cursor(session.state.tile_of(units[0]) if not units.is_empty() else Vector2i.ZERO)
	_rebuild()


## Stops taking input and hides the widgets. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	if _session.command_rejected.is_connected(_on_session_command_rejected):
		_session.command_rejected.disconnect(_on_session_command_rejected)
	if view != null and view.settled.is_connected(_on_view_settled):
		view.settled.disconnect(_on_view_settled)
	if view != null:
		view.set_fast_forward(false)
	if panel_host != null:
		panel_host.flush()
	_session = null
	_encounter = null
	_set_stage(Stage.INACTIVE)
	_show_widgets(false)


## The stage turn input is at.
func get_stage() -> Stage:
	return _stage


## The unit selected; empty when none is.
func get_selected_unit() -> String:
	return _unit_id


## The tile the cursor is on.
func get_cursor_tile() -> Vector2i:
	return _cursor


## The walk the selected unit would be sent with: to the hovered tile in MOVE, to the picked tile
## after; empty for none or its own tile.
func get_walk() -> Array[Vector2i]:
	return _path.duplicate()


## The enemies whose range is toggled on.
func get_shown_enemies() -> PackedStringArray:
	return _shown_enemies.duplicate()


## Whether input is taken now: a session is bound and still fought, no command's playback is
## running, and the seat has something to do ([enum Stage] isn't INACTIVE).
func is_accepting_input() -> bool:
	return (
			_session != null
			and not _session.is_finished
			and not _is_waiting
			and view.is_settled()
			and _stage != Stage.INACTIVE
	)


## Moves the cursor to [param tile] when it is on the map, redrawing the path in MOVE and asking
## for the tile's move preview there. Returns whether it moved.
func move_cursor(tile: Vector2i) -> bool:
	if _session == null or not _is_on_map(tile):
		return false
	_cursor = tile
	view.get_cursor().show_at(tile, view.tile_to_position(tile))
	if _stage == Stage.MOVE:
		_path = TurnInputModel.path_to(_session, _unit_id, tile)
		_draw_path()
		_request_preview(tile)
	return true


## Weapon cycling in the forecast (cycle_weapon, Next weapon): shows the target's next weapon's
## forecast, wrapping, and makes its command the one Confirm sends. Returns false, doing nothing,
## outside CONFIRM's forecast panel or with one weapon.
func cycle_weapon() -> bool:
	if _stage != Stage.CONFIRM or _forecast_panel == null or _target == null:
		return false
	if _target.commands.size() < 2:
		return false
	_weapon_index = (_weapon_index + 1) % _target.commands.size()
	_forecast_panel.show_forecast(_forecast_model())
	return true


## The command Confirm would send now: in CONFIRM, the weapon shown's; null elsewhere.
func get_confirm_command() -> Command:
	if _stage != Stage.CONFIRM or _target == null:
		return null
	if _weapon_index < _target.commands.size():
		return _target.commands[_weapon_index]
	return _target.command


## Runs the newest hover's move preview, if one waits, and draws it: at most one per call.
## [method Node._process] calls it once a frame; tests call it to stand for a frame. Returns
## whether a preview ran.
func run_preview_frame() -> bool:
	if _session == null or move_preview_marks == null or _stage != Stage.MOVE:
		return false
	var preview: MovePreview = _previews.run_pending(_session)
	if preview == null:
		return false
	var enemy_positions: Array[Vector2] = []
	for enemy_id: String in preview.changed_enemies:
		enemy_positions.append(view.tile_to_position(_session.state.tile_of(enemy_id)))
	move_preview_marks.show_preview(preview, view.tile_to_position(preview.tile), enemy_positions)
	return true


## The move preview queue, for tests and benchmarks that count the previews run.
func get_preview_queue() -> MovePreview.Queue:
	return _previews


## Accept on [param tile]: what it does depends on the stage (see the state block). Ignored while
## input isn't taken.
func confirm_tile(tile: Vector2i) -> void:
	if not is_accepting_input() or not _is_on_map(tile):
		return
	var occupant: String = _session.state.occupant_at(tile)
	match _stage:
		Stage.SWAP:
			if not occupant.is_empty() and _session.state.seat_of(occupant) == _seat:
				_pick_swap_unit(occupant)
		Stage.SWAP_PICKED:
			if _targets_by_tile.has(tile):
				_send(_targets_by_tile[tile].command)
		Stage.IDLE:
			if occupant.is_empty():
				return
			if (
					_session.state.seat_of(occupant) == _seat
					and TurnInputModel.can_act(_session, occupant)
			):
				_select(occupant)
			elif _session.state.side_of(occupant) == ENEMY:
				_toggle_enemy_range(occupant)
		Stage.MOVE:
			if _is_move_tile.has(tile):
				_pick_tile(tile)
		Stage.TARGET:
			if _targets_by_tile.has(tile):
				_on_target_picker_confirmed(_targets_by_tile[tile])


## Cancel: steps back exactly one stage, closing the panel that stage opened. Returns false, doing
## nothing, where there is nothing to step back from (INACTIVE, SWAP, IDLE).
func step_back() -> bool:
	if _history.is_empty():
		return false
	match _stage:
		Stage.ACTION, Stage.TARGET, Stage.CONFIRM, Stage.END_CONFIRM:
			panel_host.back()
	var leaving: Stage = _stage
	var previous: Stage = _history.pop_back()
	_set_stage(previous)
	match leaving:
		Stage.SWAP_PICKED, Stage.MOVE:
			_clear_selection()
		Stage.ACTION:
			_action = null
			_end_tile = CombatFact.NO_TILE
			move_cursor(_cursor)
		Stage.TARGET:
			_targets_by_tile.clear()
			move_cursor(_end_tile)
		Stage.CONFIRM:
			move_cursor(_target.tile)
			_target = null
			_weapon_index = 0
			_forecast_panel = null
	_redraw()
	return true


## End Turn, from the key or the button: in the swap window it is Start; in IDLE or MOVE it sends
## [EndTurnCommand], asking first while any of the seat's units can still act. Ignored elsewhere.
func request_end_turn() -> void:
	if not is_accepting_input():
		return
	if _stage == Stage.SWAP or _stage == Stage.SWAP_PICKED:
		# ASSUMPTION: end_turn presses Start in the swap window, the keyboard's only way to it.
		request_start()
		return
	if _stage != Stage.IDLE and _stage != Stage.MOVE:
		return
	var command: EndTurnCommand = TurnInputModel.end_turn_command(_session, _seat)
	if command == null:
		return
	var left: int = TurnInputModel.acting_units(_session, _seat).size()
	if left == 0:
		_send(command)
		return
	var dialog: BattlePanel = _open_panel(Stage.END_CONFIRM, confirm_dialog_scene, (
			"%d %s can still act. End the turn?" % [left, "unit" if left == 1 else "units"]
	))
	if dialog != null:
		dialog.confirmed.connect(_on_end_turn_dialog_confirmed)
		dialog.cancelled.connect(_on_panel_cancelled)


## Start in the opening swap window ([StartCommand]). Ignored outside it.
func request_start() -> void:
	if not is_accepting_input():
		return
	if _stage != Stage.SWAP and _stage != Stage.SWAP_PICKED:
		return
	var command: StartCommand = TurnInputModel.start_command(_session, _seat)
	if command != null:
		_send(command)


func _read_mouse(mouse: InputEventMouse) -> void:
	var local: InputEventMouse = view.make_input_local(mouse) as InputEventMouse
	var tile: Vector2i = view.tile_at(local.position)
	var button: InputEventMouseButton = mouse as InputEventMouseButton
	if button != null:
		if not button.pressed:
			return
		# A HUD button clicked earlier keeps keyboard focus, and would take ui_accept from the
		# board; a panel's rows keep theirs.
		if panel_host.depth() == 0:
			get_viewport().gui_release_focus()
		if button.button_index == MOUSE_BUTTON_LEFT and _follows_mouse():
			move_cursor(tile)
			confirm_tile(tile)
		return
	if _follows_mouse() and tile != _cursor:
		move_cursor(tile)


func _follows_mouse() -> bool:
	return _stage in [Stage.SWAP, Stage.SWAP_PICKED, Stage.IDLE, Stage.MOVE, Stage.TARGET]


func _step_cursor(direction: Vector2i) -> void:
	if _stage in [Stage.SWAP, Stage.SWAP_PICKED, Stage.IDLE, Stage.MOVE]:
		move_cursor(_cursor + direction)


func _is_cancel(event: InputEvent) -> bool:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		return button.pressed and button.button_index == MOUSE_BUTTON_RIGHT
	return event.is_action_pressed(&"ui_cancel")


func _select(unit_id: String) -> void:
	_unit_id = unit_id
	_move_tiles = TurnInputModel.move_tiles(_session, unit_id)
	_attack_tiles = TurnInputModel.attack_tiles(_session, unit_id)
	_is_move_tile.clear()
	for tile: Vector2i in _move_tiles:
		_is_move_tile[tile] = true
	_advance(Stage.MOVE)
	move_cursor(_session.state.tile_of(unit_id))
	_redraw()


func _pick_tile(tile: Vector2i) -> void:
	_end_tile = tile
	_path = TurnInputModel.path_to(_session, _unit_id, tile)
	var options: Array[TurnInputModel.ActionOption] = TurnInputModel.actions_at(
			_session, _unit_id, _path
	)
	if options.is_empty():
		return
	var menu: BattlePanel = _open_panel(Stage.ACTION, action_menu_scene, options)
	if menu == null:
		return
	menu.confirmed.connect(_on_action_menu_confirmed)
	menu.cancelled.connect(_on_panel_cancelled)
	_redraw()


func _pick_swap_unit(unit_id: String) -> void:
	var partners: Array[TurnInputModel.TargetOption] = TurnInputModel.swap_partners(
			_session, unit_id
	)
	if partners.is_empty():
		return
	_unit_id = unit_id
	_targets_by_tile.clear()
	for partner: TurnInputModel.TargetOption in partners:
		_targets_by_tile[partner.tile] = partner
	_advance(Stage.SWAP_PICKED)
	_redraw()


# The step between the target and the command: the forecast panel for an attack, a staff or a
# shove, the confirm dialog for the rest (see the state block).
func _open_confirm() -> void:
	_weapon_index = 0
	_forecast_panel = null
	var turn: UnitTurnCommand = _target.command as UnitTurnCommand
	# ASSUMPTION: the forecast takes the confirm dialog's place (Confirm on it sends), as Godot_FE's
	# forecast took ui_confirm; a second question after the forecast would ask twice.
	if forecast_panel_scene != null and turn != null and turn.needs_fresh_forecast():
		var panel: ForecastPanel = (
				_open_panel(Stage.CONFIRM, forecast_panel_scene, _forecast_model()) as ForecastPanel
		)
		if panel == null:
			return
		_forecast_panel = panel
		panel.confirmed.connect(_on_confirm_dialog_confirmed)
		panel.cancelled.connect(_on_panel_cancelled)
		panel.weapon_cycle_requested.connect(_on_forecast_panel_weapon_cycle_requested)
		_redraw()
		return
	var dialog: BattlePanel = _open_panel(Stage.CONFIRM, confirm_dialog_scene, (
			"%s %s?" % [_action.label, _target.label]
	))
	if dialog == null:
		return
	dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	dialog.cancelled.connect(_on_panel_cancelled)
	_redraw()


# The forecast of the weapon shown against _target.
func _forecast_model() -> ForecastViewModel:
	var index: int = mini(_weapon_index, _target.commands.size() - 1)
	var command: UnitTurnCommand = _target.commands[maxi(index, 0)] as UnitTurnCommand
	return ForecastViewModel.build(_session, command, index, _target.commands.size())


# Asks for tile's move preview while it is one of the selected unit's move tiles, else clears it.
func _request_preview(tile: Vector2i) -> void:
	if move_preview_marks == null:
		return
	if _is_move_tile.has(tile):
		_previews.request(_unit_id, tile)
		return
	_clear_preview()


func _clear_preview() -> void:
	_previews.clear()
	# The marks can be freed first when the screen is torn down; unbind() still calls this.
	if is_instance_valid(move_preview_marks):
		move_preview_marks.clear()


func _toggle_enemy_range(enemy_id: String) -> void:
	var at: int = _shown_enemies.find(enemy_id)
	if at >= 0:
		_shown_enemies.remove_at(at)
	else:
		_shown_enemies.append(enemy_id)
	_draw_enemy_ranges()


# Opens scene on the panel host for stage, stepping forward into it; null when it didn't open.
func _open_panel(stage: Stage, scene: PackedScene, payload: Variant) -> BattlePanel:
	var panel: BattlePanel = panel_host.open(scene, payload)
	if panel != null:
		_advance(stage)
	return panel


func _advance(stage: Stage) -> void:
	_history.append(_stage)
	_set_stage(stage)


func _set_stage(stage: Stage) -> void:
	_stage = stage
	if stage != Stage.MOVE:
		# ASSUMPTION: the preview shows only while picking a tile; the menu, target and forecast
		# that follow show no preview of the picked tile.
		_clear_preview()
	if view != null and view.get_cursor() != null:
		view.get_cursor().is_targeting = stage == Stage.TARGET or stage == Stage.CONFIRM
	_refresh_widgets()


func _clear_selection() -> void:
	_unit_id = ""
	_move_tiles.clear()
	_attack_tiles.clear()
	_is_move_tile.clear()
	_end_tile = CombatFact.NO_TILE
	_path.clear()
	_action = null
	_target = null
	_weapon_index = 0
	_forecast_panel = null
	_targets_by_tile.clear()


# Sends command for the seat and resolves it; input waits, with the board's marks cleared, until
# its playback settles.
func _send(command: Command) -> void:
	panel_host.flush()
	_history.clear()
	_sent_unit_id = _unit_id
	_clear_selection()
	_rejection = ""
	_is_waiting = true
	_set_stage(Stage.INACTIVE)
	_redraw()
	_encounter.submit(command, _session.session_id)
	_encounter.resolve_queued()
	if view.is_settled():
		_after_playback()


# Rebuilds the stage from the session once a command's playback has settled (see the state block).
func _after_playback() -> void:
	_is_waiting = false
	var acted_id: String = _sent_unit_id
	_sent_unit_id = ""
	_rebuild()
	# ASSUMPTION: after a rejection the flow starts over at IDLE, not at the stage it was sent from.
	if not _rejection.is_empty():
		return
	if (
			_stage == Stage.IDLE
			and not acted_id.is_empty()
			and TurnInputModel.is_second_move(_session, acted_id)
			and TurnInputModel.can_act(_session, acted_id)
	):
		_select(acted_id)


# The stage the session allows with nothing selected, with every panel and selection dropped.
func _rebuild() -> void:
	panel_host.flush()
	_history.clear()
	_clear_selection()
	var stage: Stage = _base_stage()
	var kept: PackedStringArray = []
	for enemy_id: String in _shown_enemies:
		if _session != null and _session.state.has_unit(enemy_id):
			kept.append(enemy_id)
	_shown_enemies = kept
	_set_stage(stage)
	if _session != null:
		move_cursor(_cursor)
	_redraw()


# The stage the session allows with nothing selected: SWAP in the seat's swap window, IDLE in its
# player phase, else INACTIVE.
func _base_stage() -> Stage:
	if _session == null or _session.is_finished:
		return Stage.INACTIVE
	if TurnInputModel.is_swapping(_session, _seat):
		return Stage.SWAP
	if CommandValidator.player_phase_reason(_session, _seat).is_empty():
		return Stage.IDLE
	return Stage.INACTIVE


# Draws the overlays, path and cursor colour for the stage and the selection.
func _redraw() -> void:
	if view == null or _session == null:
		return
	var move: TileOverlay = view.get_move_overlay()
	var attack: TileOverlay = view.get_attack_overlay()
	move.clear()
	attack.clear()
	match _stage:
		Stage.SWAP_PICKED:
			var partners: Array[Vector2i] = []
			partners.assign(_targets_by_tile.keys())
			move.show_tiles(partners)
		Stage.MOVE:
			move.show_tiles(_move_tiles)
			attack.show_tiles(_attack_tiles)
		Stage.TARGET, Stage.CONFIRM:
			var tiles: Array[Vector2i] = []
			for option: TurnInputModel.TargetOption in _action.targets:
				tiles.append(option.tile)
			attack.show_tiles(tiles)
		Stage.END_CONFIRM:
			if not _unit_id.is_empty():
				move.show_tiles(_move_tiles)
				attack.show_tiles(_attack_tiles)
	if (_stage == Stage.MOVE or _stage == Stage.END_CONFIRM) and not _unit_id.is_empty():
		_path = TurnInputModel.path_to(_session, _unit_id, _cursor)
	_draw_path()
	_draw_enemy_ranges()


func _draw_path() -> void:
	var points: PackedVector2Array = []
	for tile: Vector2i in _path:
		points.append(view.tile_to_position(tile))
	view.get_path_preview().show_path(_path, points)


func _draw_enemy_ranges() -> void:
	var covered: Dictionary[Vector2i, bool] = {}
	for enemy_id: String in _shown_enemies:
		for tile: Vector2i in TurnInputModel.enemy_range_tiles(_session, enemy_id):
			covered[tile] = true
	var tiles: Array[Vector2i] = []
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	view.get_enemy_range_overlay().show_tiles(tiles)


func _show_widgets(is_shown: bool) -> void:
	if turn_bar != null:
		turn_bar.visible = is_shown
	if swap_window != null:
		swap_window.visible = false
	if panel_host != null:
		panel_host.visible = is_shown
	if view != null and view.get_cursor() != null and not is_shown:
		view.get_cursor().visible = false


# The status line, End Turn's state, and the swap window with its hint.
func _refresh_widgets() -> void:
	if _session == null:
		return
	var state: CombatState = _session.state
	var is_swapping: bool = TurnInputModel.is_swapping(_session, _seat)
	# TODO(TOD-001): the swap window shows the danger zone (question 12); UI4 draws it.
	if swap_window != null:
		swap_window.visible = is_swapping and not _session.is_finished
		if _stage == Stage.SWAP_PICKED:
			swap_window.show_hint("Pick the unit to trade tiles with.")
		else:
			swap_window.show_hint("Pick two of your units to trade tiles, then Start.")
	if turn_bar == null:
		return
	turn_bar.set_can_end_turn(
			(_stage == Stage.IDLE or _stage == Stage.MOVE)
			and not _is_waiting
			and TurnInputModel.end_turn_command(_session, _seat) != null
	)
	var status: String = "Turn %d · %s phase" % [
		state.turn,
		(CombatFact.CombatSide.find_key(state.phase_side) as String).to_lower(),
	]
	if is_swapping:
		status = "Opening swap"
	elif _session.is_finished:
		status = "Won" if _session.is_won else "Lost"
	turn_bar.show_status(status)


func _is_on_map(tile: Vector2i) -> bool:
	return _session.state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE


func _on_action_menu_confirmed(result: Variant) -> void:
	var option: TurnInputModel.ActionOption = result
	if not option.has_targets():
		# ASSUMPTION: an action with no target (Wait, Swap) is sent when picked, as Godot_FE's
		# Wait is; the confirm stage is for targeted actions, where UI3's forecast goes.
		_send(option.command)
		return
	_action = option
	var request: TargetPicker.Request = TargetPicker.Request.new()
	request.title = option.label
	request.targets = option.targets
	var picker: BattlePanel = _open_panel(Stage.TARGET, target_picker_scene, request)
	if picker == null:
		_action = null
		return
	_targets_by_tile.clear()
	for target: TurnInputModel.TargetOption in option.targets:
		_targets_by_tile[target.tile] = target
	picker.confirmed.connect(_on_target_picker_confirmed)
	picker.highlighted.connect(_on_target_picker_highlighted)
	picker.cancelled.connect(_on_panel_cancelled)
	move_cursor(option.targets[0].tile)
	_redraw()


func _on_target_picker_confirmed(result: Variant) -> void:
	if _stage != Stage.TARGET:
		return
	_target = result
	move_cursor(_target.tile)
	_open_confirm()


func _on_target_picker_highlighted(result: Variant) -> void:
	var option: TurnInputModel.TargetOption = result
	if _stage == Stage.TARGET:
		move_cursor(option.tile)


func _on_confirm_dialog_confirmed(_result: Variant) -> void:
	var command: Command = get_confirm_command()
	if command != null:
		_send(command)


func _on_forecast_panel_weapon_cycle_requested() -> void:
	cycle_weapon()


func _on_end_turn_dialog_confirmed(_result: Variant) -> void:
	if _stage != Stage.END_CONFIRM:
		return
	var command: EndTurnCommand = TurnInputModel.end_turn_command(_session, _seat)
	if command != null:
		_send(command)


func _on_panel_cancelled() -> void:
	step_back()


func _on_session_command_rejected(seat: int, _arrival: int, reason: String) -> void:
	if seat != _seat:
		return
	_rejection = reason
	if message != null:
		message.show_message("Can't do that: %s" % [reason])


# Playback this controller didn't start (a command from elsewhere) can change what the seat may do:
# with no flow under way the stage follows the session; a flow under way is left to its command,
# which the session checks when it is sent.
func _on_view_settled() -> void:
	if _is_waiting:
		_after_playback()
		return
	if _stage in [Stage.INACTIVE, Stage.SWAP, Stage.IDLE] and _base_stage() != _stage:
		_rebuild()
		return
	_refresh_widgets()


func _on_turn_bar_end_turn_pressed() -> void:
	request_end_turn()


func _on_swap_window_start_pressed() -> void:
	request_start()
