# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_screen.gd
# Author:
# Created:  November 4, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name BattleScreen
extends Node2D
## The gameplay screen: the run's battle on this machine's own map
## ([method CampaignService.local_seat]), from Begin to its results, solo, co-op host or client.
##
## The host and solo begin the run's combat node ([method CampaignRunState.battle_request], in the
## swap window only while [member SettingsData.is_opening_swap_on]), resume one saved mid-fight or
## show one already on (its [EventLog] starting "Battle resumed"), and send any other run to
## [RunScreen]; each player phase's end, on any map, saves the battle. A client shows its mirror's
## battle once the host's snapshot built it, and again after a resync. Once this map has ended and
## settled, input stops and the end banner shows; once every map has, the host waits
## [member end_banner_time] and saves the result: a won solo combat's [VictoryOverlay] opens, else
## everyone moves on. A client waits for that move. The save debug panel hides during a battle.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

const VICTORY_SCENE: PackedScene = preload("res://ui/campaign/victory/victory_overlay.tscn")

# ASSUMPTION: Godot_FE has no end banner; 2.0 s is its turn transition's length.
## How long the Victory or Defeat banner shows before the route to Results, counted from when it
## appears; it pauses with the pause menu. Shorter than the banner's fade-in
## ([member PhaseBanner.fade_in_time]) routes before it is fully shown.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] routes at once, so the banner is never seen.
@export_range(0.0, 10.0, 0.1) var end_banner_time: float = 2.0

# The player's map in the battle shown; null when the placeholder shows.
var _session: CombatSession = null

# The battle shown, whose every map's save points save it; null when the placeholder shows.
var _encounter: CombatEncounter = null

# Whether this map has ended and its banner shows; and whether the hold before the battle's end
# has started (once every map has ended).
var _is_ending: bool = false
var _is_end_held: bool = false

# Whether the battle shown was resumed or already on, not begun by this screen.
var _is_resumed: bool = false

# A client's mirrored run, whose battle this screen shows as it is built; null on the host.
var _mirror: CampaignSession = null

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
	if run == null:
		_show_placeholder("")
		return
	if run.is_mirror:
		# Built from the host's snapshot, never begun here; a resync builds it again.
		_mirror = run
		_mirror.combat_encounter_opened.connect(_on_mirror_combat_encounter_opened)
		if run.encounter != null:
			_open(run.encounter, CampaignService.local_seat())
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
	_open(run.encounter, CampaignService.local_seat())


func _exit_tree() -> void:
	if _mirror != null and _mirror.combat_encounter_opened.is_connected(
			_on_mirror_combat_encounter_opened
	):
		_mirror.combat_encounter_opened.disconnect(_on_mirror_combat_encounter_opened)


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
	request.opening_swap[CampaignService.local_seat()] = SaveService.settings.is_opening_swap_on
	if SaveService.combat != null:
		var err: Error = CampaignService.resume_battle(request)
		# A resume that fell back to Begin (BATTLE_RETRY) is a new battle.
		_is_resumed = err == OK and SaveService.resume_point == CombatData.ResumePoint.BATTLE
		return err
	return CampaignService.begin_battle(request)


# Shows seat's map of encounter, letting go of a battle shown before (a client's resync).
func _open(encounter: CombatEncounter, seat: int) -> void:
	_let_go_of_battle()
	_session = encounter.session_of_seat(seat)
	if _session == null:
		_show_placeholder("The battle has no map for seat %d." % [seat])
		return
	if is_instance_valid(_save_debug_panel):
		_save_debug_panel.visible = false
	_view.settled.connect(_on_battle_view_settled)
	_encounter = encounter
	for map: CombatSession in encounter.get_sessions():
		map.batch_resolved.connect(_on_session_batch_resolved)
	_view.bind(_session)
	_controller.bind(encounter, _session, seat)
	_controller.run_units = _run_units_of(seat)
	_hud.bind(_session, _controller, _view)
	_hud.bind_heirlooms(CampaignService.session, seat)
	AudioService.follow_battle(_session)
	if _is_resumed:
		_hud.get_event_log().add_resumed_line()
	# The unit panel's Details button is the mouse's way to unit detail; the controller decides.
	_hud.get_unit_panel().details_pressed.connect(_on_unit_panel_details_pressed)
	_on_battle_view_settled()


# Disconnects the battle shown, if any, so _open() can show another.
func _let_go_of_battle() -> void:
	if _encounter == null:
		return
	for map: CombatSession in _encounter.get_sessions():
		if map.batch_resolved.is_connected(_on_session_batch_resolved):
			map.batch_resolved.disconnect(_on_session_batch_resolved)
	if _view.settled.is_connected(_on_battle_view_settled):
		_view.settled.disconnect(_on_battle_view_settled)
	var panel: UnitPanel = _hud.get_unit_panel()
	if panel.details_pressed.is_connected(_on_unit_panel_details_pressed):
		panel.details_pressed.disconnect(_on_unit_panel_details_pressed)
	_encounter = null
	_session = null
	_is_ending = false
	_is_end_held = false


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


# Stops input and shows this map's end banner, then holds for the battle's end. Runs once.
func _show_end() -> void:
	if _is_ending:
		return
	_is_ending = true
	_controller.unbind()
	_hud.show_result(_session.is_won)
	_hold_end()


# Once every map has ended (in solo, the one map), ends the battle after end_banner_time, on the
# host; a client's banner stays until the host moves everyone on. Runs once.
func _hold_end() -> void:
	if _is_end_held or _mirror != null or not _encounter.is_finished():
		return
	_is_end_held = true
	if end_banner_time <= 0.0:
		_end_battle()
		return
	# Not processed while paused, so the pause menu holds the route too.
	var hold: SceneTreeTimer = get_tree().create_timer(end_banner_time, false)
	hold.timeout.connect(_end_battle)


# Saves the battle's end, then shows a won solo combat's victory sequence over the board (the run
# is at its results); otherwise routes everyone on: a solo run still going to its stage's screen,
# and a run that ended, or anything but a solo run, to RESULTS. Called once, by _hold_end().
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
		overlay.open(CampaignService.local_seat(), false)
		return
	SceneRouter.goto_screen_for_everyone(next)


func _on_battle_view_settled() -> void:
	if _session.is_finished and _view.is_settled():
		_show_end()


# The end-of-phase checkpoint (save-system.md, When the game saves), on any map of the battle, a
# co-op host's included: a player phase's end or a frozen map's restart saves the whole battle at
# the start of a player phase (CombatEncounter.is_save_point). Once this map has ended, a map's
# batch only checks for the battle's end, which _end_battle() saves. A failed save is reported and
# play goes on. A client's mirror sends no batches here, and never saves.
func _on_session_batch_resolved(batch: CombatSession.FactBatch) -> void:
	if _is_ending:
		_hold_end()
		return
	if _encounter.is_finished() or SaveService.combat == null:
		return
	if not CombatEncounter.is_save_point(batch):
		return
	# The save lands as the batch resolves, before its playback, so a crash while the enemy phase
	# plays resumes at the next player phase instead of losing the phase.
	var err: Error = SaveService.save_checkpoint()
	if err != OK:
		push_error("BattleScreen: the end-of-phase save failed - %s" % [error_string(err)])


# The mirror's battle was built, or built again by a resync; its snapshot loads in the same call,
# so it shows once that call is done.
func _on_mirror_combat_encounter_opened(encounter: CombatEncounter) -> void:
	_open_mirrored.call_deferred(encounter)


func _open_mirrored(encounter: CombatEncounter) -> void:
	if _mirror == null or _mirror.encounter != encounter or encounter.is_closed:
		return
	_placeholder.visible = false
	_view.visible = true
	_view.process_mode = Node.PROCESS_MODE_INHERIT
	_open(encounter, CampaignService.local_seat())


func _on_unit_panel_details_pressed(unit_id: String) -> void:
	_controller.request_unit_detail(unit_id)


# The raw fact log shows only beside the save debug panel, and only while a battle shows.
func _on_save_debug_panel_visibility_changed() -> void:
	_hud.get_fact_log().visible = _save_debug_panel.visible and _session != null

