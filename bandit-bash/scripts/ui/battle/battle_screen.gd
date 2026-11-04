# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_screen.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name BattleScreen
extends Node2D
## The gameplay screen: a solo run's battle, from Begin to Results.
##
## On entry with a solo run and no battle on, it begins one through
## [code]CampaignService.begin_battle()[/code] (combat UI plan, question 2): the faction's starting
## army ([method StartingArmy.build]) on [member map_definition] at [member floor_number] and
## [member combat_node], from the run's seed. A battle already on is shown as it stands. The
## [BattleView] draws the player's map; when that map's combat has ended and its playback has
## settled, [code]CampaignService.end_battle()[/code] saves the result and every player goes to
## Results.[br]
## [b]Commands only:[/b] the screen changes no combat state; the [BattleDebugBar] presses become
## [EndTurnCommand] and [StartCommand] for the run's seat, submitted to the encounter, and a
## rejection is shown. Turn input (UI2) replaces the bar.[br]
## [b]Co-op[/b] (any run that isn't solo, and a multiplayer client, which holds no run) keeps the
## placeholder: its label and the End Round button to Results (plan, question 2).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The map a solo battle is fought on.[br]
## [b]Unset:[/b] no battle begins; the screen says so.
@export var map_definition: CombatMapDefinition = null

## The faction whose starting army fights ([member FactionDefinition], by content id).
@export var faction_id: String = "mercenary"

## The campaign floor the battle is on; floor 1's enemies are level 1 (game-vision.md, Run
## structure).
@export_range(1, 99, 1) var floor_number: int = 1

## The combat node on [member floor_number], which keys the battle's random streams.
@export_range(1, 99, 1) var combat_node: int = 1

# The battle shown and the player's map in it; null when the placeholder shows.
var _encounter: CombatEncounter = null
var _session: CombatSession = null

# The seat the debug bar sends commands for: the solo run's only seat.
var _seat: int = CampaignData.HOST_SEAT

# The latest rejection, shown until the next command.
var _rejection: String = ""

var _is_ending: bool = false

@onready var _view: BattleView = %BattleView
@onready var _debug_bar: BattleDebugBar = %DebugBar
@onready var _placeholder: Control = %CoopPlaceholder
@onready var _placeholder_note: Label = %PlaceholderNote


func _ready() -> void:
	_placeholder.visible = false
	var run: CampaignSession = CampaignService.session
	if run == null or run.mode != CampaignData.Mode.SOLO:
		_show_placeholder("")
		return
	if run.encounter == null:
		# ASSUMPTION: a battle saved mid-fight can't be rebuilt yet (campaign_service.gd:TOD-001,
		# P02 CC10), so the placeholder shows instead of beginning it again over its save.
		if SaveService.combat != null:
			_show_placeholder("This battle was saved mid-fight; resuming it isn't built yet.")
			return
		var err: Error = _begin_battle(run)
		if err != OK:
			_show_placeholder("Couldn't begin the battle (%s)." % [error_string(err)])
			return
	_open(run.encounter, run.seats[0])


func _exit_tree() -> void:
	if _session != null and _session.command_rejected.is_connected(_on_session_command_rejected):
		_session.command_rejected.disconnect(_on_session_command_rejected)


## The board, for tests that drive its playback.
func get_view() -> BattleView:
	return _view


## The debug bar, for tests that press its buttons.
func get_debug_bar() -> BattleDebugBar:
	return _debug_bar


# The battle request for the solo run, then Begin. Returns the error the run flow reports.
func _begin_battle(run: CampaignSession) -> Error:
	if map_definition == null:
		push_error("BattleScreen: no map definition set")
		return ERR_UNCONFIGURED
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var built: StartingArmy = StartingArmy.build(catalog, faction_id, run.ids)
	for problem: String in built.problems:
		push_error("BattleScreen: %s" % [problem])
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = built.units
	army.item_instances = built.items
	army.heirloom_ids = built.heirloom_ids
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = floor_number
	request.node = combat_node
	request.pool = [map_definition]
	request.catalog = catalog
	request.armies[run.seats[0]] = army
	return CampaignService.begin_battle(request)


func _open(encounter: CombatEncounter, seat: int) -> void:
	_encounter = encounter
	_seat = seat
	_session = encounter.session_of_seat(seat)
	if _session == null:
		_show_placeholder("The battle has no map for seat %d." % [seat])
		return
	_session.command_rejected.connect(_on_session_command_rejected)
	_view.settled.connect(_on_battle_view_settled)
	_debug_bar.end_turn_pressed.connect(_on_debug_bar_end_turn_pressed)
	_debug_bar.start_pressed.connect(_on_debug_bar_start_pressed)
	_view.bind(_session)
	_on_battle_view_settled()


# Hides the battle and shows the co-op placeholder; a non-empty note replaces its text.
func _show_placeholder(note: String) -> void:
	_view.visible = false
	_view.process_mode = Node.PROCESS_MODE_DISABLED
	_debug_bar.visible = false
	_placeholder.visible = true
	if not note.is_empty():
		_placeholder_note.text = note


func _submit(command: Command) -> void:
	if _session == null or _session.is_finished or not _view.is_settled():
		return
	_rejection = ""
	_encounter.submit(command, _session.session_id)
	_encounter.resolve_queued()
	_refresh()


# What the bar offers: Start in the opening swap window, End Turn in the seat's own player phase
# once playback has caught up.
func _refresh() -> void:
	var state: CombatState = _session.state
	var is_swapping: bool = state.map.opening_swap_open
	var can_end_turn: bool = (
			_view.is_settled()
			and not _session.is_finished
			and not is_swapping
			and state.phase_side == CombatFact.CombatSide.PLAYER
			and not state.ended_seats.has(_seat)
	)
	_debug_bar.show_buttons(is_swapping and _view.is_settled(), can_end_turn)
	var status: String = "Turn %d · %s phase" % [
		state.turn,
		(CombatFact.CombatSide.find_key(state.phase_side) as String).to_lower(),
	]
	if is_swapping:
		status = "Opening swap: press Start"
	elif _session.is_finished:
		status = "Won" if _session.is_won else "Lost"
	if not _rejection.is_empty():
		status += "  ·  rejected: %s" % [_rejection]
	_debug_bar.show_status(status)


func _end_battle() -> void:
	if _is_ending:
		return
	_is_ending = true
	_view.unbind()
	if CampaignService.end_battle() == null:
		_debug_bar.show_status("Couldn't save the battle's end; see the log.")
		return
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.RESULTS)


func _on_battle_view_settled() -> void:
	if _session.is_finished and _view.is_settled():
		_end_battle()
		return
	_refresh()


func _on_session_command_rejected(seat: int, _arrival: int, reason: String) -> void:
	if seat == _seat:
		_rejection = reason


func _on_debug_bar_end_turn_pressed() -> void:
	_submit(EndTurnCommand.new(_seat))


func _on_debug_bar_start_pressed() -> void:
	_submit(StartCommand.new(_seat))
