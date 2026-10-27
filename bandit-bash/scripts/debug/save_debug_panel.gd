# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_debug_panel.gd
# Author:
# Created:  October 14, 2026
# Modified: October 27, 2026
# ==============================================================================

extends PanelContainer
## Debug-only panel that fires save checkpoints, battle saves and run endings before gameplay
## exists.
##
## Removes itself outside debug builds ([method OS.is_debug_build]). Acts on
## [code]SaveService.campaign[/code] and [code]SaveService.combat[/code]; buttons that don't apply
## right now are disabled.[br]
## Stand-ins for systems that don't exist yet: "Room Entered" bumps the floor and saves a
## checkpoint; "End Player Phase" moves to the enemy phase and saves (the only battle save point
## besides Begin); "End Enemy Phase" starts the next turn without saving, as the real combat flow
## will.[br]
## "New Solo Run From Seed" starts a solo run from the seed typed in the field above it
## ([method RunSeed.parse]'s form), abandoning any solo run first, and stays on this screen.[br]
## Works the same for a multiplayer host, whose saves also reach the clients. On a client every
## button is disabled, since clients never save a campaign; it shows the host's replica instead.

@onready var _info_label: Label = %Info
@onready var _room_button: Button = %RoomButton
@onready var _begin_button: Button = %BeginButton
@onready var _player_phase_button: Button = %PlayerPhaseButton
@onready var _enemy_phase_button: Button = %EnemyPhaseButton
@onready var _end_battle_button: Button = %EndBattleButton
@onready var _win_button: Button = %WinButton
@onready var _lose_button: Button = %LoseButton
@onready var _seed_field: LineEdit = %SeedField
@onready var _seed_run_button: Button = %SeedRunButton


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return

	_room_button.pressed.connect(_on_room_button_pressed)
	_begin_button.pressed.connect(_on_begin_button_pressed)
	_player_phase_button.pressed.connect(_on_player_phase_button_pressed)
	_enemy_phase_button.pressed.connect(_on_enemy_phase_button_pressed)
	_end_battle_button.pressed.connect(_on_end_battle_button_pressed)
	_win_button.pressed.connect(_on_win_button_pressed)
	_lose_button.pressed.connect(_on_lose_button_pressed)
	_seed_run_button.pressed.connect(_on_seed_run_button_pressed)
	_refresh(_describe_resume())


func _refresh(message: String) -> void:
	var campaign: CampaignData = SaveService.campaign
	var combat: CombatData = SaveService.combat
	var has_campaign: bool = campaign != null
	var in_battle: bool = combat != null

	_room_button.disabled = not has_campaign or campaign.combat_in_progress
	_begin_button.disabled = not has_campaign or in_battle
	_player_phase_button.disabled = not in_battle or combat.phase != CombatData.Phase.PLAYER
	_enemy_phase_button.disabled = not in_battle or combat.phase != CombatData.Phase.ENEMY
	_end_battle_button.disabled = not in_battle
	_win_button.disabled = not has_campaign
	_lose_button.disabled = not has_campaign

	var lines: PackedStringArray = []
	var is_client: bool = SteamNetwork.has_active_session() and not SteamNetwork.is_authoritative()
	_seed_run_button.disabled = (
			is_client
			or not SaveService.has_open_save_file()
			or (has_campaign and campaign.mode != CampaignData.Mode.SOLO)
	)
	if is_client:
		var replica: CampaignData = SaveService.multiplayer_replica
		var floor_text: String = "?" if replica == null else str(replica.floors_climbed)
		lines.append("Multiplayer client: the host saves this run (floor %s)." % [floor_text])
	elif not has_campaign:
		lines.append("No active campaign.")
	else:
		lines.append(
				"Checkpoint %d  ·  floor %d  ·  run time %ds"
				% [campaign.checkpoint_seq, campaign.floors_climbed, campaign.play_time_seconds]
		)
		lines.append("Seed %s" % [RunSeed.format(campaign.run_seed)])
		if in_battle:
			var phase_name: String = (CombatData.Phase.find_key(combat.phase) as String).to_lower()
			lines.append("Battle: turn %d, %s phase" % [combat.turn, phase_name])
		elif campaign.combat_in_progress:
			lines.append("Battle waiting to restart: press Begin Battle.")
		else:
			lines.append("No battle.")
	if not message.is_empty():
		lines.append(message)
	_info_label.text = "\n".join(lines)


func _describe_resume() -> String:
	match SaveService.resume_point:
		CombatData.ResumePoint.BATTLE:
			return "Resumed the saved battle."
		CombatData.ResumePoint.BATTLE_RETRY:
			return "The saved battle couldn't be resumed; it restarts from Begin."
	return ""


func _report(action: String, err: Error) -> void:
	_refresh("%s: %s" % [action, "saved" if err == OK else "failed, " + error_string(err)])


func _on_room_button_pressed() -> void:
	var campaign: CampaignData = SaveService.campaign
	campaign.floors_climbed += 1
	campaign.level_id = "debug_room_%d" % [campaign.floors_climbed]
	_report("Room entered", SaveService.save_checkpoint())


func _on_begin_button_pressed() -> void:
	_report("Battle begun", SaveService.begin_battle())


func _on_player_phase_button_pressed() -> void:
	SaveService.combat.phase = CombatData.Phase.ENEMY
	_report("Player phase ended", SaveService.save_checkpoint())


func _on_enemy_phase_button_pressed() -> void:
	SaveService.combat.turn += 1
	SaveService.combat.phase = CombatData.Phase.PLAYER
	_refresh("Enemy phase ended (not a save point).")


func _on_end_battle_button_pressed() -> void:
	_report("Battle ended", SaveService.end_battle())


func _on_win_button_pressed() -> void:
	_end_run(true)


func _on_lose_button_pressed() -> void:
	_end_run(false)


# Stays on the gameplay screen: going back through Loading would be a screen edge that
# scene_router.gd's flow block doesn't list, and nothing on this placeholder screen reads the seed.
func _on_seed_run_button_pressed() -> void:
	var typed_seed: int = RunSeed.parse(_seed_field.text)
	if typed_seed == RunSeed.NO_SEED:
		_refresh("Not a run seed: '%s'." % [_seed_field.text])
		return

	# The solo slot holds one run, so an existing one is abandoned first: archived as lost, as the
	# Main Menu's Abandon does.
	if SaveService.has_solo_campaign():
		var abandon_err: Error = SaveService.abandon_run(CampaignData.Mode.SOLO)
		if abandon_err != OK:
			_refresh("Abandoning the solo run failed: %s" % [error_string(abandon_err)])
			return
	var err: Error = SaveService.start_new_solo_run(typed_seed)
	_report("Run started from seed %s" % [RunSeed.format(typed_seed)], err)


# In multiplayer the host's end_run() sends the archive record before this moves everyone, and
# both go out reliably in order, so clients have the record when their Results screen opens.
func _end_run(won: bool) -> void:
	var err: Error = SaveService.end_run(won)
	if err != OK:
		_refresh("Ending the run failed: %s" % [error_string(err)])
		return
	SceneRouter.goto_screen_for_everyone(SceneRouter.Screen.RESULTS)
