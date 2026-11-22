# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     node_placeholder_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 21, 2026
# ==============================================================================

extends Control
## The quiet road: an Unknown node with no event open, one that became an event when no event can
## be drawn there ([OpenEventCommand] refused), or one not rolled. Names the node, says nothing
## happens here, and lets the run go on.
##
## Continue sends the local seat's [LeaveNodeCommand] through a [CampaignLink], which saves; once
## any seat's Leave resolves the run returns to the map. The node stays visited and its floor
## locked, so a route through it still reaches the Boss. With the game's events it never shows in
## play, as only the shrine has an eligibility rule. Opened at any other stage, it sends the run on
## at once. The [HeirloomBar] shows the seat's heirlooms; in co-op, Team opens the [TeamPanel].
## The run's facts still to play ([CampaignPlayback]) play after each batch.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_accept" -> Enter, Space; pad A [Cross]               (press Continue, which has focus, or
#                  Team)
#   "ui_up" / "ui_down" -> arrows; d-pad, left stick         (co-op: between Continue and Team)
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]       (the pause menu, which reads it;
#                  on the heirloom bar the bar reads it, closing itself; the team panel reads
#                  its own)
#   "heirloom_bar_focus" -> H; RS pushed left [R stick]      (read by the HeirloomBar: focuses
#                  it, then back to Continue; left and right move between its icons, and the
#                  hints are HEIRLOOMS meanwhile)
#   Mouse: a click on Continue; hovering an heirloom shows its tooltip.
# ============================================================

# ASSUMPTION: the Note label's copy in the scene, "The road is quiet. Nothing happens here." (P08
# question 71).

## The hint context while the placeholder shows.
const HINT_CONTEXT: StringName = &"NODE"

var _is_leaving: bool = false
var _link: CampaignLink = null

@onready var _header: RunHeader = %RunHeader
@onready var _title_label: Label = %Title
@onready var _status_label: Label = %Status
@onready var _continue_button: Button = %ContinueButton
@onready var _team_button: Button = %TeamButton
@onready var _team_panel: TeamPanel = %TeamPanel
@onready var _hints: ScreenHints = %ScreenHints
@onready var _heirlooms: HeirloomBar = %HeirloomBar


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.NODE_PLACEHOLDER:
		_is_leaving = true
		RunScreen.go()
		return
	_link = CampaignLink.new(
			session, CampaignService.local_seat(), CampaignService.submit_command
	)
	_link.batch_resolved.connect(_on_link_batch_resolved)
	_link.refused.connect(_on_link_refused)
	var run: CampaignRunState = session.run
	_show_seat()
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	var type_name: String = CampaignMapView.TYPE_NAMES.get(run.graph.type_of(run.node), "?")
	_header.title = type_name
	_title_label.text = type_name
	_continue_button.pressed.connect(_on_continue_button_pressed)
	_team_button.visible = _link.is_coop()
	_team_button.pressed.connect(_on_team_button_pressed)
	_hints.context = HINT_CONTEXT
	_continue_button.grab_focus.call_deferred()


func _exit_tree() -> void:
	if _link != null:
		_link.close()


## The Continue button, for tests.
func get_continue_button() -> Button:
	return _continue_button


## The Team button, shown in co-op, for tests.
func get_team_button() -> Button:
	return _team_button


## The team panel, for tests and captures.
func get_team_panel() -> TeamPanel:
	return _team_panel


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


# The header and heirloom bar for the local seat, as the run saved them.
func _show_seat() -> void:
	var run: CampaignRunState = _link.session.run
	_header.show_run(run, _link.seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_link.seat)))


func _on_continue_button_pressed() -> void:
	if _is_leaving:
		return
	_link.send(LeaveNodeCommand.new(_link.seat))


# Any seat's batch: one the screen follows plays its facts and, once the run left the node, moves
# the screen on.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _is_leaving:
		return
	var follows: bool = _link.moves_with(batch, is_answer)
	if follows:
		CampaignPlayback.play_pending(_link.session)
	if RunScreen.of(_link.session) != SceneRouter.Screen.NODE_PLACEHOLDER:
		if follows:
			_is_leaving = true
			RunScreen.go()
		return
	_show_seat()
	_team_panel.refresh()


func _on_link_refused(reason: String) -> void:
	_status_label.text = "Couldn't leave: %s." % [reason]


func _on_team_button_pressed() -> void:
	_team_panel.open(_link.session, _link.seat)


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = HINT_CONTEXT
