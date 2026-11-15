# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     node_placeholder_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

extends Control
## Stands in for the screen of a node that isn't fought (Treasure, Camp, Armory, Guildhall,
## Unknown) until its own exists: names the node and lets the run move on.
##
## Continue sends [LeaveNodeCommand] through [method CampaignService.submit_command], which saves,
## and returns to the map; the node stays visited and its floor locked, and its rules never run.
## It exists so a route through the fixed Treasure and Camp floors still reaches the Boss (Godot_FE
## sent its unbuilt rooms to a placeholder scene the same way). Opened at any other stage, it
## sends the run on at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md
##
## @todo: TOD-001 - Give Treasure, Camp, Armory, Guildhall and Unknown their own screens
## (RN7-RN10), and route each there from [method RunScreen.of].

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_accept" -> Enter, Space; pad A [Cross]               (press Continue, which has focus)
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]       (the pause menu, which reads it)
#   Mouse: a click on Continue.
# ============================================================

## The hint context while the placeholder shows.
const HINT_CONTEXT: StringName = &"NODE"

var _is_leaving: bool = false

@onready var _header: RunHeader = %RunHeader
@onready var _title_label: Label = %Title
@onready var _status_label: Label = %Status
@onready var _continue_button: Button = %ContinueButton
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.NODE_PLACEHOLDER:
		_is_leaving = true
		RunScreen.go()
		return
	var run: CampaignRunState = session.run
	_header.show_run(run, session.seats[0])
	# TODO(TOD-001): each node type's own screen (RN7-RN10) replaces this one for that type.
	var type_name: String = CampaignMapView.TYPE_NAMES.get(run.graph.type_of(run.node), "?")
	_header.title = type_name
	_title_label.text = type_name
	_continue_button.pressed.connect(_on_continue_button_pressed)
	_hints.context = HINT_CONTEXT
	_continue_button.grab_focus.call_deferred()


## The Continue button, for tests.
func get_continue_button() -> Button:
	return _continue_button


func _on_continue_button_pressed() -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	var batch: CampaignBatch = CampaignService.submit_command(
			LeaveNodeCommand.new(session.seats[0])
	)
	if batch == null or batch.is_rejected():
		_status_label.text = "Couldn't leave: %s." % [
			batch.rejected_reason if batch != null else "no run in progress",
		]
		return
	_is_leaving = true
	RunScreen.go()
