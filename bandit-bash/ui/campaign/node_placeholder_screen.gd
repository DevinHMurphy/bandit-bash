# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     node_placeholder_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 20, 2026
# ==============================================================================

extends Control
## The fallback for an Unknown node with no event open: one that became an event when no event
## can be drawn there ([OpenEventCommand] refused), or one not rolled. Names the node and lets the
## run move on.
##
## Continue sends [LeaveNodeCommand] through [method CampaignService.submit_command], which saves,
## and returns to the map; the node stays visited and its floor locked. It keeps a route through
## such a node reaching the Boss; with the game's events it never shows in play, as only the
## shrine has an eligibility rule. Opened at any other stage, it sends the run on at once. The
## [HeirloomBar] under the header shows the seat's heirlooms as the run saved them. The run's facts
## still to play ([CampaignPlayback]) play once Continue resolves.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_accept" -> Enter, Space; pad A [Cross]               (press Continue, which has focus)
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]       (the pause menu, which reads it;
#                  on the heirloom bar the bar reads it, closing itself)
#   "heirloom_bar_focus" -> H; RS pushed left [R stick]      (read by the HeirloomBar: focuses
#                  it, then back to Continue; left and right move between its icons, and the
#                  hints are HEIRLOOMS meanwhile)
#   Mouse: a click on Continue; hovering an heirloom shows its tooltip.
# ============================================================

## The hint context while the placeholder shows.
const HINT_CONTEXT: StringName = &"NODE"

var _is_leaving: bool = false

@onready var _header: RunHeader = %RunHeader
@onready var _title_label: Label = %Title
@onready var _status_label: Label = %Status
@onready var _continue_button: Button = %ContinueButton
@onready var _hints: ScreenHints = %ScreenHints
@onready var _heirlooms: HeirloomBar = %HeirloomBar


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.NODE_PLACEHOLDER:
		_is_leaving = true
		RunScreen.go()
		return
	var run: CampaignRunState = session.run
	_header.show_run(run, session.seats[0])
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(session.seats[0])))
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
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
	CampaignPlayback.play_pending(session)
	RunScreen.go()


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = HINT_CONTEXT
