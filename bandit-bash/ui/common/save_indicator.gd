# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_indicator.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Label
## Shows that a checkpoint was saved, or that a save failed.
##
## Listens to [code]SaveService.checkpoint_saved[/code]. Saves finish within the frame, so there
## is no in-progress state to show: a success shows "Saved" for [constant _SAVED_SECONDS]; a
## failure stays on screen until the next successful save, because the player must know their
## progress since the last good save is at risk.

# ASSUMPTION: no basis for this duration; tune it with the UI pass. Units: seconds.
const _SAVED_SECONDS: float = 2.0

@onready var _hide_timer: Timer = %HideTimer


func _ready() -> void:
	text = ""
	_hide_timer.timeout.connect(_on_hide_timer_timeout)
	SaveService.checkpoint_saved.connect(_on_save_service_checkpoint_saved)


func _on_save_service_checkpoint_saved(error: Error) -> void:
	if error != OK:
		_hide_timer.stop()
		text = "Save failed (%s). Your last save is kept." % [error_string(error)]
		return
	text = "Saved"
	_hide_timer.start(_SAVED_SECONDS)


func _on_hide_timer_timeout() -> void:
	text = ""
