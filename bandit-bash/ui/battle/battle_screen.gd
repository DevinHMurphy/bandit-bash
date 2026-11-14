# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_screen.gd
# Author:
# Created:  November 4, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name BattleScreen
extends Node2D
## The gameplay screen: a solo run's battle, from Begin to Results.
##
## With a solo run and no battle on, it begins the run's combat node's battle from the run's request
## (army from the roster, map from the node's pool: [method CampaignRunState.battle_request]),
## opening in the swap window only while [member SettingsData.is_opening_swap_on]; a battle saved
## mid-fight resumes from the same request, and one already on shows as it stands. Once the
## player's map has ended and settled, input stops, the banner shows for [member end_banner_time],
## then [code]CampaignService.end_battle()[/code] applies and saves the result and all go to
## Results. [b]Commands only:[/b] its [BattleController] turns input into commands. Co-op and a
## multiplayer client keep the placeholder. The save debug panel hides while a battle shows, as it
## would take the map's clicks; toggle_save_debug shows it.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Drop the node pick on entry once the campaign map screen chooses nodes (RN5).
## @todo: TOD-002 - Drop the skipped item pick on entry once the Results screen takes it (RN5).

## How long the Victory or Defeat banner shows before the route to Results, counted from when it
## appears; it pauses with the pause menu. Shorter than the banner's fade-in
## ([member PhaseBanner.fade_in_time]) routes before it is fully shown.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] routes at once, so the banner is never seen.
# ASSUMPTION: Godot_FE has no end banner; 2.0 s is its turn transition's length, as the phase
# banner's 1.0 s fade-in and 1.0 s fade-out.
@export_range(0.0, 10.0, 0.1) var end_banner_time: float = 2.0

# The player's map in the battle shown; null when the placeholder shows.
var _session: CombatSession = null

var _is_ending: bool = false

@onready var _view: BattleView = %BattleView
@onready var _controller: BattleController = %BattleController
@onready var _hud: BattleHud = %BattleHud
@onready var _placeholder: Control = %CoopPlaceholder
@onready var _placeholder_note: Label = %PlaceholderNote

# Outside debug builds the panel frees itself, so it is checked before each use.
@onready var _save_debug_panel: Control = %SaveDebugPanel


func _ready() -> void:
	_placeholder.visible = false
	var run: CampaignSession = CampaignService.session
	if run == null or run.mode != CampaignData.Mode.SOLO:
		_show_placeholder("")
		return
	if run.encounter == null:
		var err: Error = _begin_battle(run)
		if err != OK:
			_show_placeholder("Couldn't begin the battle (%s)." % [error_string(err)])
			return
	_open(run.encounter, run.seats[0])


## The board, for tests that drive its playback.
func get_view() -> BattleView:
	return _view


## Turn input, for tests that drive it.
func get_controller() -> BattleController:
	return _controller


## The HUD, for tests that read it.
func get_hud() -> BattleHud:
	return _hud


# The run's battle request for its combat node, then Begin, or the resume of the battle a
# continued run saved mid-fight, from the same request (the run is as Begin saved it). Returns the
# error the screen reports.
func _begin_battle(run: CampaignSession) -> Error:
	if run.run == null:
		push_error("BattleScreen: the run has no campaign state")
		return ERR_UNCONFIGURED
	if run.run.flow.stage == RunFlow.Stage.RESULTS:
		var left: Error = _leave_results(run)
		if left != OK:
			return left
	if run.run.is_on_map():
		var chosen: Error = _choose_next_combat(run)
		if chosen != OK:
			return chosen
	var request: CampaignSession.BattleRequest = run.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return ERR_CANT_CREATE
	# The player's opening-swap setting, read as the battle begins. A resumed battle keeps the
	# window's saved state; a resume that falls back to Begin reads the setting again.
	request.opening_swap[run.seats[0]] = SaveService.settings.is_opening_swap_on
	if SaveService.combat != null:
		return CampaignService.resume_battle(request)
	return CampaignService.begin_battle(request)


# TODO(TOD-001): The campaign map screen chooses nodes (RN5). Until then, entering with the run on
# the map chooses the leftmost combat node it can reach next (floor 1 is all Standard combats).
# Returns ERR_UNAVAILABLE when no reachable node is a combat, ERR_CANT_RESOLVE when it's rejected.
func _choose_next_combat(run: CampaignSession) -> Error:
	var state: CampaignRunState = run.run
	var reachable: PackedInt32Array = (
			state.graph.nodes_on_floor(1) if state.node == CampaignGraph.NO_NODE
			else state.graph.children_of(state.node)
	)
	for node_id: int in reachable:
		var type: CampaignGraph.NodeType = state.graph.type_of(node_id)
		if (
				type != CampaignGraph.NodeType.STANDARD
				and type != CampaignGraph.NodeType.KEY
				and type != CampaignGraph.NodeType.BOSS
		):
			continue
		var batch: CampaignBatch = CampaignService.submit_command(
				ChooseNodeCommand.new(run.seats[0], node_id)
		)
		return ERR_CANT_RESOLVE if batch == null or batch.is_rejected() else OK
	push_warning("BattleScreen: no combat node is reachable from the map")
	return ERR_UNAVAILABLE


# TODO(TOD-002): The Results screen takes or skips the item pick (RN5). Until then, entering with
# the run at a combat's results skips the seat's open pick and leaves the node for the map.
# Returns ERR_CANT_RESOLVE when either command is rejected.
func _leave_results(run: CampaignSession) -> Error:
	var seat: int = run.seats[0]
	var pick: ItemPick = ItemPick.pending(run.run.seat_run(seat))
	if pick != null and not pick.is_resolved:
		var skipped: CampaignBatch = CampaignService.submit_command(
				ItemPickCommand.new(seat, ItemPickCommand.SKIP)
		)
		if skipped == null or skipped.is_rejected():
			return ERR_CANT_RESOLVE
	var left: CampaignBatch = CampaignService.submit_command(LeaveNodeCommand.new(seat))
	return ERR_CANT_RESOLVE if left == null or left.is_rejected() else OK


func _open(encounter: CombatEncounter, seat: int) -> void:
	_session = encounter.session_of_seat(seat)
	if _session == null:
		_show_placeholder("The battle has no map for seat %d." % [seat])
		return
	if is_instance_valid(_save_debug_panel):
		_save_debug_panel.visible = false
	_view.settled.connect(_on_battle_view_settled)
	_view.bind(_session)
	_controller.bind(encounter, _session, seat)
	_hud.bind(_session, _controller, _view)
	# The unit panel's Details button is the mouse's way to unit detail; the controller decides.
	_hud.get_unit_panel().details_pressed.connect(_on_unit_panel_details_pressed)
	_on_battle_view_settled()


# Hides the battle and shows the co-op placeholder; a non-empty note replaces its text.
func _show_placeholder(note: String) -> void:
	_controller.unbind()
	_hud.unbind()
	_view.visible = false
	_view.process_mode = Node.PROCESS_MODE_DISABLED
	_placeholder.visible = true
	if not note.is_empty():
		_placeholder_note.text = note


# Stops input and shows the end banner, then ends the battle after end_banner_time. Runs once.
func _show_end() -> void:
	if _is_ending:
		return
	_is_ending = true
	_controller.unbind()
	_hud.show_result(_session.is_won)
	if end_banner_time <= 0.0:
		_end_battle()
		return
	# Not processed while paused, so the pause menu holds the route too.
	var hold: SceneTreeTimer = get_tree().create_timer(end_banner_time, false)
	hold.timeout.connect(_end_battle)


# Saves the battle's end and routes everyone to Results. Called once, by _show_end().
func _end_battle() -> void:
	_controller.unbind()
	_hud.unbind()
	_view.unbind()
	if CampaignService.end_battle() == null:
		_show_placeholder("Couldn't save the battle's end; see the log.")
		return
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.RESULTS)


func _on_battle_view_settled() -> void:
	if _session.is_finished and _view.is_settled():
		_show_end()


func _on_unit_panel_details_pressed(unit_id: String) -> void:
	_controller.request_unit_detail(unit_id)
