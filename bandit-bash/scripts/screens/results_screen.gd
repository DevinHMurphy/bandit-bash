# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     results_screen.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends Control
## Results: shows how a run ended and whether it reached the archive.
##
## Takes the ended run from [code]SaveService.take_ended_run()[/code], so each run is shown once.
## With no ended run (the multiplayer round placeholder) it keeps the scene's round text and both
## buttons. After a run, Next Round is hidden: the run is over, so only the way back to the Main
## Menu remains.

@onready var _title_label: Label = %Title
@onready var _note_label: Label = %Note
@onready var _next_round_button: Button = %NextRoundButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	var record: ArchiveRecord = SaveService.take_ended_run()
	if record == null:
		return

	_title_label.text = "Run Won" if record.won else "Run Lost"
	var minutes: int = floori(record.play_time_seconds / 60.0)
	var lines: PackedStringArray = [
		"Floor %d  ·  %d min played" % [record.floors_climbed, minutes],
	]
	var archive_err: Error = SaveService.last_archive_error
	if archive_err == OK:
		lines.append("Saved to archive.")
	else:
		lines.append("Couldn't save it to the archive (%s)." % [error_string(archive_err)])
	_note_label.text = "\n".join(lines)

	_next_round_button.visible = false
	_leave_button.text = "Main Menu"
	_leave_button.grab_focus.call_deferred()
