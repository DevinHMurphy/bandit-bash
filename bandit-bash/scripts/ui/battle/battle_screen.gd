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
## [b]Commands only:[/b] the screen changes no combat state; its [BattleController] turns the run
## seat's input into commands on that map.[br]
## [b]Co-op[/b] (any run that isn't solo, and a multiplayer client, which holds no run) keeps the
## placeholder: its label and the End Round button to Results (plan, question 2).[br]
## [b]The save debug panel[/b] (debug builds) is hidden when a battle opens, as it would take
## clicks meant for the map; toggle_save_debug shows it beside the map. With the placeholder it
## stays shown.
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

# The player's map in the battle shown; null when the placeholder shows.
var _session: CombatSession = null

var _is_ending: bool = false

@onready var _view: BattleView = %BattleView
@onready var _controller: BattleController = %BattleController
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


## The board, for tests that drive its playback.
func get_view() -> BattleView:
	return _view


## Turn input, for tests that drive it.
func get_controller() -> BattleController:
	return _controller


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
	_session = encounter.session_of_seat(seat)
	if _session == null:
		_show_placeholder("The battle has no map for seat %d." % [seat])
		return
	if is_instance_valid(_save_debug_panel):
		_save_debug_panel.visible = false
	_view.settled.connect(_on_battle_view_settled)
	_view.bind(_session)
	_controller.bind(encounter, _session, seat)
	_on_battle_view_settled()


# Hides the battle and shows the co-op placeholder; a non-empty note replaces its text.
func _show_placeholder(note: String) -> void:
	_controller.unbind()
	_view.visible = false
	_view.process_mode = Node.PROCESS_MODE_DISABLED
	_placeholder.visible = true
	if not note.is_empty():
		_placeholder_note.text = note


func _end_battle() -> void:
	if _is_ending:
		return
	_is_ending = true
	_controller.unbind()
	_view.unbind()
	if CampaignService.end_battle() == null:
		_show_placeholder("Couldn't save the battle's end; see the log.")
		return
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.RESULTS)


func _on_battle_view_settled() -> void:
	if _session.is_finished and _view.is_settled():
		_end_battle()
