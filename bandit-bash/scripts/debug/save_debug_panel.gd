# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_debug_panel.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends PanelContainer
## Debug-only panel that fires save checkpoints and run endings before gameplay exists.
##
## Removes itself outside debug builds ([method OS.is_debug_build]). Acts on
## [code]SaveService.campaign[/code]; with no active campaign (a multiplayer match, or a run that
## already ended) its buttons are disabled.[br]
## "Room Entered" stands in for the campaign system: it bumps the floor and level id, then saves a
## checkpoint. Battle buttons join in plan milestone M6.

@onready var _info_label: Label = %Info
@onready var _room_button: Button = %RoomButton
@onready var _win_button: Button = %WinButton
@onready var _lose_button: Button = %LoseButton


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return

	_room_button.pressed.connect(_on_room_button_pressed)
	_win_button.pressed.connect(_on_win_button_pressed)
	_lose_button.pressed.connect(_on_lose_button_pressed)
	_refresh("")


func _refresh(message: String) -> void:
	var campaign: CampaignData = SaveService.campaign
	var is_active: bool = campaign != null
	_room_button.disabled = not is_active
	_win_button.disabled = not is_active
	_lose_button.disabled = not is_active

	var lines: PackedStringArray = []
	if is_active:
		lines.append(
				"Checkpoint %d  ·  floor %d  ·  run time %ds"
				% [campaign.checkpoint_seq, campaign.floors_climbed, campaign.play_time_seconds]
		)
	else:
		lines.append("No active campaign.")
	if not message.is_empty():
		lines.append(message)
	_info_label.text = "\n".join(lines)


func _on_room_button_pressed() -> void:
	var campaign: CampaignData = SaveService.campaign
	campaign.floors_climbed += 1
	campaign.level_id = "debug_room_%d" % [campaign.floors_climbed]
	var err: Error = SaveService.save_checkpoint()
	_refresh("Saved." if err == OK else "Save failed: %s" % [error_string(err)])


func _on_win_button_pressed() -> void:
	_end_run(true)


func _on_lose_button_pressed() -> void:
	_end_run(false)


func _end_run(won: bool) -> void:
	var err: Error = SaveService.end_solo_run(won)
	if err != OK:
		_refresh("Ending the run failed: %s" % [error_string(err)])
		return
	SceneRouter.goto_screen(SceneRouter.Screen.RESULTS)
