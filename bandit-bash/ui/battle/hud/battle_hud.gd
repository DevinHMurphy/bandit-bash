# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_hud.gd
# Author:
# Created:  November 5, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BattleHud
extends Control
## The battle screen's HUD (combat UI plan, question 11; Godot_FE FR-UI-3 minus XP): the
## [TurnCounter], [ObjectivePanel], [DarknessCounter], [TileInfo] and [UnitPanel] down the left,
## the debug [FactLog] under them (hidden; [BattleScreen] shows it with the F3 panel), the
## [EventLog] at the foot of the right column, the [PhaseBanner] at the top, the seat's
## [HeirloomBar] in the top strip over the map, and the [code]%MapArea[/code] it leaves free for
## the map ([member BattleView.map_area]).
##
## [b]Reading only:[/b] it draws [HudViewModel] views of the session and never changes combat
## state or turn input. What it reads, and when:[br]
## - the board settling ([signal BattleView.settled]): every widget, from state, the objective's
## progress included, which it also hands the board to draw ([method BattleView.show_objective]:
## seize and defend tiles, open reinforcement points, marked enemies), and the heirloom bar once
## [method bind_heirlooms] named the run;[br]
## - the cursor's tile and the selected unit changing ([BattleController]'s getters, compared each
## frame while the board is settled): the tile info and the unit panel, for the unit under the
## cursor, else the selected one. While playback runs nothing redraws from state, which already
## holds the command's outcome, so the panels never show a result before the board plays it;[br]
## - each Phase Start fact as it plays: the banner, and the turn counter's turn; a darkness phase
## as it begins to play ([signal BattleView.darkness_phase_started]): its banner;[br]
## - [method show_result], called by the screen once the battle has ended: the end banner;[br]
## - each batch the session sends ([signal CombatSession.batch_resolved]): a fact log line;[br]
## - each fact as it plays: the event log's lines, which it writes itself once bound, and the
## heirloom bar's counts and pulses.[br]
## [b]Layout:[/b] the columns and the map area are set in the scene; at the 1280×720 base size and
## wider nothing here covers the map, because the camera frames it inside the map area. The panel
## stack ([PanelHost]) and the turn bar are the screen's, laid out in their own scenes to match.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

var _session: CombatSession = null
var _controller: BattleController = null
var _view: BattleView = null

# The run whose heirlooms the bar shows, and the seat; null until bind_heirlooms().
var _campaign: CampaignSession = null
var _seat: int = -1

# The cursor tile and the unit the panels last drew; redrawn when either changes.
var _shown_tile: Vector2i = CombatFact.NO_TILE
var _shown_unit: String = ""

@onready var _turn_counter: TurnCounter = %TurnCounter
@onready var _objective: ObjectivePanel = %ObjectivePanel
@onready var _darkness: DarknessCounter = %DarknessCounter
@onready var _tile_info: TileInfo = %TileInfo
@onready var _unit_panel: UnitPanel = %UnitPanel
@onready var _fact_log: FactLog = %FactLog
@onready var _event_log: EventLog = %EventLog
@onready var _banner: PhaseBanner = %PhaseBanner
@onready var _map_area: Control = %MapArea
# ASSUMPTION: "the battle HUD's top strip" (ui-lift.md) read as the band above the map area, the
# bar at its left edge, under the phase banner; the scene sets its place.
@onready var _heirloom_bar: HeirloomBar = %HeirloomBar


func _ready() -> void:
	_show_widgets(false)


func _exit_tree() -> void:
	unbind()


func _process(_delta: float) -> void:
	if _session == null or not is_instance_valid(_view) or not _view.is_settled():
		return
	# The unit panel holds its unit while the mouse is over it, so its Details button is reachable.
	if _unit_panel.is_mouse_over():
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
		_view.darkness_phase_started.connect(_on_view_darkness_phase_started)
	_fact_log.clear()
	_event_log.bind(session)
	_heirloom_bar.bind(session)
	_show_widgets(true)
	refresh()


## Shows seat [param seat]'s heirlooms and curses of [param campaign], the run the bound battle
## belongs to, on the heirloom bar, from the battle's live effects
## ([method HeirloomViewModel.for_battle]); null: none show. Call after [method bind]; unbinding
## forgets it.
func bind_heirlooms(campaign: CampaignSession, seat: int) -> void:
	_campaign = campaign
	_seat = seat
	_show_heirlooms()


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
	if (
			is_instance_valid(_view)
			and _view.darkness_phase_started.is_connected(_on_view_darkness_phase_started)
	):
		_view.darkness_phase_started.disconnect(_on_view_darkness_phase_started)
	if is_instance_valid(_view):
		_view.show_objective(null)
	_event_log.unbind()
	_heirloom_bar.unbind()
	_session = null
	_controller = null
	_view = null
	_campaign = null
	_seat = -1
	_show_heirlooms()
	_show_widgets(false)


## Redraws every widget from the session as it stands. [signal BattleView.settled] calls it; tests
## call it to stand for a settle.
func refresh() -> void:
	if _session == null:
		return
	_turn_counter.show_turn(HudViewModel.turn_view(_session))
	_darkness.show_darkness(HudViewModel.darkness_view(_session))
	var objective: HudViewModel.ObjectiveView = HudViewModel.objective_view(_session)
	_objective.show_view(objective)
	if is_instance_valid(_view):
		_view.show_objective(objective)
	_show_heirlooms()
	_draw_cursor()


## Shows the battle's end on the banner ([method PhaseBanner.show_result]): victory when
## [param is_won], else defeat. [BattleScreen] calls it before the route to Results.
func show_result(is_won: bool) -> void:
	_banner.show_result(is_won)


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


## The debug fact log, hidden unless [BattleScreen] shows it with the save debug panel.
func get_fact_log() -> FactLog:
	return _fact_log


## The event log: [BattleController] takes its input, [BattleScreen] adds its resume note.
func get_event_log() -> EventLog:
	return _event_log


## The phase banner, for tests.
func get_phase_banner() -> PhaseBanner:
	return _banner


## The heirloom bar: [BattleController] takes its input; tests read it.
func get_heirloom_bar() -> HeirloomBar:
	return _heirloom_bar


# The bar from the battle's live effects, once bind_heirlooms() named the run; empty otherwise.
func _show_heirlooms() -> void:
	_heirloom_bar.show_views(HeirloomViewModel.for_battle(_campaign, _session, _seat))


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


# The fact log is only hidden here: BattleScreen shows it with the save debug panel.
func _show_widgets(is_shown: bool) -> void:
	var widgets: Array[Control] = [
		_turn_counter, _objective, _darkness, _tile_info, _unit_panel, _event_log,
	]
	for widget: Control in widgets:
		widget.visible = is_shown
	if not is_shown:
		_banner.visible = false
		_fact_log.visible = false


func _on_view_settled() -> void:
	refresh()


func _on_view_darkness_phase_started(_turn: int) -> void:
	_banner.show_darkness()


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
