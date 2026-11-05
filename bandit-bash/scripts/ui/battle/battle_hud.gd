# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_hud.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name BattleHud
extends Control
## The battle screen's HUD (combat UI plan, question 11; Godot_FE FR-UI-3 minus XP): the
## [TurnCounter], [ObjectivePanel], [DarknessCounter], [TileInfo] and [UnitPanel] down the left,
## the [FactLog] under them, the [PhaseBanner] at the top, and the [code]%MapArea[/code] it leaves
## free for the map ([member BattleView.map_area]).
##
## [b]Reading only:[/b] it draws [HudViewModel] views of the session and never changes combat
## state or turn input. What it reads, and when:[br]
## - the board settling ([signal BattleView.settled]): every widget, from state;[br]
## - the cursor's tile and the selected unit changing ([BattleController]'s getters, compared each
## frame while the board is settled): the tile info and the unit panel, for the unit under the
## cursor, else the selected one. While playback runs nothing redraws from state, which already
## holds the command's outcome, so the panels never show a result before the board plays it;[br]
## - each Phase Start fact as it plays: the banner, and the turn counter's turn;[br]
## - each batch the session sends ([signal CombatSession.batch_resolved]): a fact log line.[br]
## [b]Layout:[/b] the columns and the map area are set in the scene; at the 1152×648 base size and
## wider nothing here covers the map, because the camera frames it inside the map area. The panel
## stack ([PanelHost]) and the turn bar are the screen's, laid out in their own scenes to match.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

var _session: CombatSession = null
var _controller: BattleController = null
var _view: BattleView = null

# The cursor tile and the unit the panels last drew; redrawn when either changes.
var _shown_tile: Vector2i = CombatFact.NO_TILE
var _shown_unit: String = ""

@onready var _turn_counter: TurnCounter = %TurnCounter
@onready var _objective: ObjectivePanel = %ObjectivePanel
@onready var _darkness: DarknessCounter = %DarknessCounter
@onready var _tile_info: TileInfo = %TileInfo
@onready var _unit_panel: UnitPanel = %UnitPanel
@onready var _fact_log: FactLog = %FactLog
@onready var _banner: PhaseBanner = %PhaseBanner
@onready var _map_area: Control = %MapArea


func _ready() -> void:
	_show_widgets(false)


func _exit_tree() -> void:
	unbind()


func _process(_delta: float) -> void:
	if _session == null or not is_instance_valid(_view) or not _view.is_settled():
		return
	var tile: Vector2i = _cursor_tile()
	if tile != _shown_tile or _unit_to_show(tile) != _shown_unit:
		_draw_cursor()


## Draws [param session] (the map [param view] shows and [param controller] takes input on) and
## shows the widgets. Binding again replaces it.
func bind(session: CombatSession, controller: BattleController, view: BattleView) -> void:
	unbind()
	if session == null:
		return
	_session = session
	_controller = controller
	_view = view
	_session.batch_resolved.connect(_on_session_batch_resolved)
	_session.bus.flow.phase_started.connect(_on_flow_phase_started)
	if is_instance_valid(_view):
		_view.settled.connect(_on_view_settled)
	_fact_log.clear()
	_objective.show_objective(HudViewModel.objective_text(session))
	_show_widgets(true)
	refresh()


## Stops drawing and hides the widgets. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	if _session.batch_resolved.is_connected(_on_session_batch_resolved):
		_session.batch_resolved.disconnect(_on_session_batch_resolved)
	if _session.bus.flow.phase_started.is_connected(_on_flow_phase_started):
		_session.bus.flow.phase_started.disconnect(_on_flow_phase_started)
	if is_instance_valid(_view) and _view.settled.is_connected(_on_view_settled):
		_view.settled.disconnect(_on_view_settled)
	_session = null
	_controller = null
	_view = null
	_show_widgets(false)


## Redraws every widget from the session as it stands. [signal BattleView.settled] calls it; tests
## call it to stand for a settle.
func refresh() -> void:
	if _session == null:
		return
	_turn_counter.show_turn(HudViewModel.turn_view(_session))
	_darkness.show_darkness(HudViewModel.darkness_view(_session))
	_draw_cursor()


## The empty area the map is framed in, for [member BattleView.map_area].
func get_map_area() -> Control:
	return _map_area


## The turn counter, for tests.
func get_turn_counter() -> TurnCounter:
	return _turn_counter


## The objective, for tests.
func get_objective() -> ObjectivePanel:
	return _objective


## The darkness counter, for tests.
func get_darkness_counter() -> DarknessCounter:
	return _darkness


## The tile info, for tests.
func get_tile_info() -> TileInfo:
	return _tile_info


## The unit panel, for tests.
func get_unit_panel() -> UnitPanel:
	return _unit_panel


## The fact log, for tests.
func get_fact_log() -> FactLog:
	return _fact_log


## The phase banner, for tests.
func get_phase_banner() -> PhaseBanner:
	return _banner


# The tile info and unit panel for the cursor's tile.
func _draw_cursor() -> void:
	var tile: Vector2i = _cursor_tile()
	_shown_tile = tile
	_shown_unit = _unit_to_show(tile)
	if tile == CombatFact.NO_TILE:
		_tile_info.show_tile(null)
	else:
		_tile_info.show_tile(HudViewModel.tile_view(_session, tile))
	_unit_panel.show_unit(HudViewModel.unit_view(_session, _shown_unit))


func _cursor_tile() -> Vector2i:
	if not is_instance_valid(_controller):
		return CombatFact.NO_TILE
	return _controller.get_cursor_tile()


# The unit under tile, else the selected one; empty for none.
func _unit_to_show(tile: Vector2i) -> String:
	# ASSUMPTION: question 11's "the selected or hovered unit" read as hovered first, as Fire
	# Emblem's footer follows the cursor; the selected unit shows when the cursor is on no unit.
	if tile != CombatFact.NO_TILE:
		var occupant: String = _session.state.occupant_at(tile)
		if not occupant.is_empty():
			return occupant
	if is_instance_valid(_controller):
		return _controller.get_selected_unit()
	return ""


func _show_widgets(is_shown: bool) -> void:
	var widgets: Array[Control] = [
		_turn_counter, _objective, _darkness, _tile_info, _unit_panel, _fact_log,
	]
	for widget: Control in widgets:
		widget.visible = is_shown
	if not is_shown:
		_banner.visible = false


func _on_view_settled() -> void:
	refresh()


func _on_session_batch_resolved(batch: CombatSession.FactBatch) -> void:
	_fact_log.add_line(_session.describe_batch(batch))


# Played as the fact's turn comes, so the counter changes with the banner, not before.
func _on_flow_phase_started(fact: CombatFact) -> void:
	# ASSUMPTION: "phase banners at each phase change" are a side's Phase Start (Player Phase,
	# Enemy Phase), as Godot_FE's turn banners; the vision's per-unit and per-combat windows (Unit
	# Turn Start, Before Combat, ...) get none, as a banner would flash over every exchange.
	_banner.show_phase(fact.side, fact.amount)
	var turn: HudViewModel.TurnView = HudViewModel.turn_view(_session)
	turn.turn = fact.amount
	_turn_counter.show_turn(turn)
