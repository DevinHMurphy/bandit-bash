# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     phase_save_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The battle's end-of-phase save for the ui/board suite, on a real solo run's gameplay screen
## through the real [code]SaveService[/code] and [code]CampaignService[/code]: a move alone saves
## nothing, and a crash then resumes at Begin; ending the player phase writes the combat file
## paired with its campaign (equal checkpoint numbers) as the command resolves, and a crash then
## resumes at the next player phase with every unit, HP, the turn and phase as saved; Save & Quit
## mid-phase still saves and resumes; a second phase end overwrites the first. A crash is the save
## file closed with nothing written. It deletes [code]user://saves/[/code] before and after, and
## never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

# Preloaded script used as a type (gdscript.md, Naming): the cases settle the board with it.
const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const GAMEPLAY_SCENE: String = "res://ui/battle/gameplay.tscn"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 1

# The board suite's seed: its first battle is a Standard map that lasts past turn 3.
const RUN_SEED: int = 0x51A7E

# CombatData.ResumePoint.BATTLE, as an int for the detail text.
const RESUME_BATTLE: int = CombatData.ResumePoint.BATTLE

var _check: Callable
var _root: Node = null
var _saves: Node = null
var _service: Node = null

# The screen open now; null between screens.
var _screen: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_saves = root.get_node(^"SaveService")
	_service = root.get_node(^"CampaignService")


## Runs every case, in order, on one run. Call only with a test user folder.
func run() -> void:
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	if _start_battle():
		_test_resume_before_phase_end()
		_test_phase_end_save()
		_test_save_and_quit()
		_test_second_phase_end()
	_close_screen()
	_saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# A move and Wait after Begin writes no save; a crash then resumes at Begin: the swap window as
# Begin opened it, the state as Begin saved it.
func _test_resume_before_phase_end() -> void:
	var session: CombatSession = _session()
	var begin_hash: int = session.state_hash()
	var begin_window: bool = session.state.map.opening_swap_open
	var begin_seq: int = _read_combat().checkpoint_seq
	_press_start()
	var unit_id: String = _move_and_wait()
	var unsaved_seq: int = _read_combat().checkpoint_seq
	var point: int = _crash_and_continue()
	var again: CombatSession = _session()
	_check.call("phase save: a move alone saves nothing; a crash then resumes at Begin", (
			unsaved_seq == begin_seq
			and point == RESUME_BATTLE
			and again != null
			and again.state_hash() == begin_hash
			and again.state.map.opening_swap_open == begin_window
			and not unit_id.is_empty()
			and not again.state.unit(unit_id).has_acted
	), "seq %d then %d, point %d, %s" % [
		begin_seq, unsaved_seq, point, "no battle" if again == null else _describe(again),
	])


# A move, then End Turn: the save lands as the command resolves, the combat file paired with
# the campaign at the next player phase; a crash then resumes there, every unit (the one moved
# included) on the tile and at the HP saved.
func _test_phase_end_save() -> void:
	_press_start()
	_move_and_wait()
	var seq_before: int = _read_campaign().checkpoint_seq
	_end_turn()
	var core: CombatData = _saves.get(&"combat")
	var turn_at_resolve: int = -1 if core == null else core.turn
	var campaign: CampaignData = _read_campaign()
	var combat: CombatData = _read_combat()
	var session: CombatSession = _session()
	BattleViewCases.settle(_view())
	_check.call("phase save: ending the phase writes the combat file paired with its campaign", (
			campaign != null
			and combat != null
			and campaign.checkpoint_seq == seq_before + 1
			and combat.checkpoint_seq == campaign.checkpoint_seq
			and campaign.combat_in_progress
			and combat.turn == 2
			and combat.phase == CombatData.Phase.PLAYER
			and turn_at_resolve == 2
			and session.state.turn == 2
	), "%s; %s; turn at resolve %d" % [
		_describe_campaign(campaign), _describe_combat(combat), turn_at_resolve,
	])
	var saved_hash: int = session.state_hash()
	var saved_units: PackedStringArray = _unit_lines(session)
	var point: int = _crash_and_continue()
	var again: CombatSession = _session()
	_check.call("phase save: a resume after it restores units, HP, turn and phase exactly", (
			point == RESUME_BATTLE
			and again != null
			and again.state_hash() == saved_hash
			and _unit_lines(again) == saved_units
			and again.state.turn == 2
			and again.state.phase_side == CombatFact.CombatSide.PLAYER
			and not again.state.map.opening_swap_open
			and (_screen.call(&"get_controller") as BattleController).is_accepting_input()
	), "point %d; saved %s; resumed %s" % [
		point, saved_units, "no battle" if again == null else str(_unit_lines(again)),
	])


# Save & Quit mid-phase after a phase-end save: saved, paired, and resumed with the move made.
func _test_save_and_quit() -> void:
	var unit_id: String = _move_and_wait()
	var session: CombatSession = _session()
	var saved: Error = _saves.call(&"save_checkpoint")
	var campaign: CampaignData = _read_campaign()
	var combat: CombatData = _read_combat()
	var saved_hash: int = session.state_hash()
	var point: int = _crash_and_continue()
	var again: CombatSession = _session()
	_check.call("phase save: Save & Quit mid-phase still saves and resumes with the move", (
			saved == OK
			and campaign != null
			and combat != null
			and combat.checkpoint_seq == campaign.checkpoint_seq
			and point == RESUME_BATTLE
			and again != null
			and again.state_hash() == saved_hash
			and not unit_id.is_empty()
			and again.state.unit(unit_id).has_acted
	), "saved %s, %s, point %d" % [error_string(saved), _describe_combat(combat), point])


# A second End Turn saves turn 3 over turn 2's save, one checkpoint later, and resumes there.
func _test_second_phase_end() -> void:
	var first_seq: int = _read_combat().checkpoint_seq
	_end_turn()
	var campaign: CampaignData = _read_campaign()
	var combat: CombatData = _read_combat()
	BattleViewCases.settle(_view())
	var saved_hash: int = _session().state_hash()
	var point: int = _crash_and_continue()
	var again: CombatSession = _session()
	_check.call("phase save: a second phase end overwrites the first", (
			campaign != null
			and combat != null
			and combat.checkpoint_seq == first_seq + 1
			and combat.checkpoint_seq == campaign.checkpoint_seq
			and combat.turn == 3
			and point == RESUME_BATTLE
			and again != null
			and again.state.turn == 3
			and again.state_hash() == saved_hash
	), "first %d; %s; point %d" % [first_seq, _describe_combat(combat), point])


# A new solo run's gameplay screen inside its first node, a Standard combat, its battle begun.
# Returns false, with the failure checked, if it didn't open.
func _start_battle() -> bool:
	var err: Error = _saves.call(&"start_new_solo_run", RUN_SEED)
	var run: CampaignSession = _service.get(&"session")
	if err != OK or run == null or run.run == null:
		_check.call("phase save: a new solo run starts", false, error_string(err))
		return false
	# These cases start past the starting heirloom offer, with nothing taken from it.
	run.run.seat_run(0).pending_offers.erase(StartingOffer.OFFER_KEY)
	_service.call(&"submit_command", ChooseNodeCommand.new(0, run.run.graph.nodes_on_floor(1)[0]))
	_open_screen()
	var opened: bool = _session() != null and _read_combat() != null
	_check.call("phase save: the run's first battle opens, saved at Begin", opened)
	return opened


func _open_screen() -> void:
	_screen = (load(GAMEPLAY_SCENE) as PackedScene).instantiate()
	_root.add_child(_screen)


func _close_screen() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


# A crash: the screen gone and the save file closed with nothing written. Then Continue and the
# gameplay screen again. Returns the continued run's resume point.
func _crash_and_continue() -> int:
	_close_screen()
	_saves.call(&"close_save_file")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	_saves.call(&"continue_solo_run")
	var point: int = _saves.get(&"resume_point")
	_open_screen()
	return point


func _view() -> BattleView:
	return _screen.call(&"get_view") as BattleView


func _session() -> CombatSession:
	return _view().get_session()


# Start in the swap window, when it is open.
func _press_start() -> void:
	var controller: BattleController = _screen.call(&"get_controller")
	if controller.swap_window.visible:
		controller.swap_window.get_start_button().pressed.emit()
		BattleViewCases.settle(_view())


# The first unit that can act walks to its first move tile and Waits, as the board suite's
# continue case does. Returns its id; empty when none can act.
func _move_and_wait() -> String:
	var session: CombatSession = _session()
	var acting: PackedStringArray = TurnInputModel.acting_units(session, 0)
	if acting.is_empty():
		return ""
	var unit_id: String = acting[0]
	var goal: Vector2i = TurnInputModel.move_tiles(session, unit_id)[0]
	var walk: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, goal)
	var encounter: CombatEncounter = (_service.get(&"session") as CampaignSession).encounter
	encounter.submit(
			UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", walk),
			session.session_id
	)
	encounter.resolve_queued()
	BattleViewCases.settle(_view())
	return unit_id


# End Turn by the controller, confirming its question when units can still act. Leaves the board
# unsettled, so a check right after reads the save made as the command resolved.
func _end_turn() -> void:
	var controller: BattleController = _screen.call(&"get_controller")
	controller.request_end_turn()
	var question: ConfirmDialog = controller.panel_host.top() as ConfirmDialog
	if question != null:
		question.get_confirm_button().pressed.emit()


func _read_campaign() -> CampaignData:
	var loaded: CampaignData = CampaignData.new()
	return loaded if _read_into(CampaignData.get_file_name(CampaignData.Mode.SOLO), loaded) else null


func _read_combat() -> CombatData:
	var loaded: CombatData = CombatData.new()
	return loaded if _read_into(CombatData.get_file_name(CampaignData.Mode.SOLO), loaded) else null


# Reads file_name in the save file's folder into target (a CampaignData or CombatData). Returns
# whether it read and loaded.
func _read_into(file_name: String, target: RefCounted) -> bool:
	var folder: String = _saves.call(&"get_save_file_dir", SAVE_NUMBER)
	var result: SaveFile.ReadResult = SaveFile.read(folder + file_name)
	if result.error != OK:
		return false
	var loaded: Error = target.call(&"load_envelope", result.envelope)
	return loaded == OK


# Each unit on the map as "id tile hp", sorted by id.
static func _unit_lines(session: CombatSession) -> PackedStringArray:
	var ids: PackedStringArray = session.state.unit_ids()
	ids.sort()
	var lines: PackedStringArray = []
	for unit_id: String in ids:
		lines.append("%s %s %d" % [
			unit_id, session.state.tile_of(unit_id), session.state.get_hp(unit_id),
		])
	return lines


static func _describe(session: CombatSession) -> String:
	return "turn %d, side %d, window %s" % [
		session.state.turn, session.state.phase_side, session.state.map.opening_swap_open,
	]


static func _describe_campaign(campaign: CampaignData) -> String:
	if campaign == null:
		return "no campaign file"
	return "campaign seq %d, in battle %s" % [
		campaign.checkpoint_seq, campaign.combat_in_progress,
	]


static func _describe_combat(combat: CombatData) -> String:
	if combat == null:
		return "no combat file"
	return "combat seq %d, turn %d, phase %d" % [combat.checkpoint_seq, combat.turn, combat.phase]
