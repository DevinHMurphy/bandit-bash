# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_screen.gd
# Author:
# Created:  November 4, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name BattleScreen
extends Node2D
## The gameplay screen: a solo run's battle, from Begin to its results.
##
## With the run inside a combat node and no battle on, it begins that node's battle from the run's
## request ([method CampaignRunState.battle_request]), opening in the swap window only while
## [member SettingsData.is_opening_swap_on]; a battle saved mid-fight resumes from the same
## request, one already on shows as it stands, and a run anywhere else is sent to its own screen
## ([RunScreen]). Once the player's map has ended and settled, input stops, the banner shows for
## [member end_banner_time], then [code]CampaignService.end_battle()[/code] applies and saves the
## result: a won solo combat's [VictoryOverlay] opens over the board, which stays; a loss goes on
## to the run's end.
## [b]Commands only:[/b] its [BattleController] turns input into commands. Co-op and a multiplayer
## client keep the placeholder. The save debug panel hides while a battle shows, as it would take
## the map's clicks; toggle_save_debug shows it, and the debug fact log with it. A battle it
## didn't begin (a resumed save, or one already on) starts its [EventLog] with "Battle resumed".
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ASSUMPTION: Godot_FE has no end banner; 2.0 s is its turn transition's length, as the phase
# banner's 1.0 s fade-in and 1.0 s fade-out.
## How long the Victory or Defeat banner shows before the route to Results, counted from when it
## appears; it pauses with the pause menu. Shorter than the banner's fade-in
## ([member PhaseBanner.fade_in_time]) routes before it is fully shown.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] routes at once, so the banner is never seen.
@export_range(0.0, 10.0, 0.1) var end_banner_time: float = 2.0

const VICTORY_SCENE: PackedScene = preload("res://ui/campaign/victory/victory_overlay.tscn")

# The player's map in the battle shown; null when the placeholder shows.
var _session: CombatSession = null

var _is_ending: bool = false

# Whether the battle shown was resumed or already on, not begun by this screen.
var _is_resumed: bool = false

@onready var _view: BattleView = %BattleView
@onready var _controller: BattleController = %BattleController
@onready var _hud: BattleHud = %BattleHud
# Every HUD part (the HUD, the turn, rune and hint bars), hidden under the victory sequence.
@onready var _hud_layer: CanvasLayer = $Hud
@onready var _placeholder: Control = %CoopPlaceholder
@onready var _placeholder_note: Label = %PlaceholderNote

# Outside debug builds the panel frees itself, so it is checked before each use.
@onready var _save_debug_panel: Control = %SaveDebugPanel


func _ready() -> void:
	_placeholder.visible = false
	if is_instance_valid(_save_debug_panel):
		_save_debug_panel.visibility_changed.connect(_on_save_debug_panel_visibility_changed)
	var run: CampaignSession = CampaignService.session
	if run == null or run.mode != CampaignData.Mode.SOLO:
		_show_placeholder("")
		return
	if run.encounter == null and RunScreen.of(run) != SceneRouter.Screen.GAMEPLAY:
		_show_placeholder("")
		RunScreen.go()
		return
	_is_resumed = run.encounter != null
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
	var request: CampaignSession.BattleRequest = run.run.battle_request(
			CombatMapPools.load_default(), EffectCatalog.index()
	)
	if request == null:
		return ERR_CANT_CREATE
	# The player's opening-swap setting, read as the battle begins. A resumed battle keeps the
	# window's saved state; a resume that falls back to Begin reads the setting again.
	request.opening_swap[run.seats[0]] = SaveService.settings.is_opening_swap_on
	if SaveService.combat != null:
		var err: Error = CampaignService.resume_battle(request)
		# A resume that fell back to Begin (BATTLE_RETRY) is a new battle.
		_is_resumed = err == OK and SaveService.resume_point == CombatData.ResumePoint.BATTLE
		return err
	return CampaignService.begin_battle(request)


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
	_controller.run_units = _run_units_of(seat)
	_hud.bind(_session, _controller, _view)
	_hud.bind_heirlooms(CampaignService.session, seat)
	if _is_resumed:
		_hud.get_event_log().add_resumed_line()
	# The unit panel's Details button is the mouse's way to unit detail; the controller decides.
	_hud.get_unit_panel().details_pressed.connect(_on_unit_panel_details_pressed)
	_on_battle_view_settled()


# The seat's army by instance id, for the unit detail's level, XP and growths; empty off a run.
func _run_units_of(seat: int) -> Dictionary[String, UnitInstance]:
	var units: Dictionary[String, UnitInstance] = {}
	var run: CampaignSession = CampaignService.session
	var seat_run: SeatRun = null
	if run != null and run.run != null:
		seat_run = run.run.seat_run(seat)
	if seat_run == null:
		return units
	for unit: UnitInstance in seat_run.army:
		units[unit.instance_id] = unit
	return units


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


# Saves the battle's end, then shows a won solo combat's victory sequence over the board (the run
# is at its results); otherwise routes everyone on: a solo run still going to its stage's screen,
# and a run that ended, or anything but a solo run, to RESULTS. Called once, by _show_end().
func _end_battle() -> void:
	_controller.unbind()
	_hud.unbind()
	_view.unbind()
	if CampaignService.end_battle() == null:
		_show_placeholder("Couldn't save the battle's end; see the log.")
		return
	var run: CampaignSession = CampaignService.session
	var next: SceneRouter.Screen = SceneRouter.Screen.RESULTS
	if RunScreen.is_solo_run(run):
		next = RunScreen.of(run)
	if next == SceneRouter.Screen.COMBAT_RESULTS:
		_hud_layer.visible = false
		var overlay: VictoryOverlay = VICTORY_SCENE.instantiate()
		overlay.playback_speed = _view.playback_speed
		overlay.fast_forward_speed = _view.fast_forward_speed
		add_child(overlay)
		overlay.open(run.seats[0], false)
		return
	SceneRouter.goto_screen_for_everyone(next)


func _on_battle_view_settled() -> void:
	if _session.is_finished and _view.is_settled():
		_show_end()


func _on_unit_panel_details_pressed(unit_id: String) -> void:
	_controller.request_unit_detail(unit_id)


# The raw fact log shows only beside the save debug panel, and only while a battle shows.
func _on_save_debug_panel_visibility_changed() -> void:
	_hud.get_fact_log().visible = _save_debug_panel.visible and _session != null
