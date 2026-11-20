# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_heirloom_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Control
## The run's starting heirloom offer, after New Run and before the first node (Slay the Spire's
## first choice): the [StartingOfferView] over the run's header and [HeirloomBar]. The faction and
## commander pickers before it are skipped while the MVP has one of each.
##
## The view's command goes through [method CampaignService.submit_command], which saves; a
## rejection shows its reason on the view and changes nothing. Once it resolves, the run's facts
## play ([CampaignPlayback]), the bar shows the new heirloom and the run goes to the map
## ([method RunScreen.go]). A quit before then Continues here with the same offer, saved in the
## seat's pending offers. Opened at any other stage, it sends the run on at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI and the view; the view's own block
# lists what it reads):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick      (along the cards and Back or Skip)
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick      (along a unit column or a placement)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (take the focused card or choice)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back in a sub-choice, read by
#                             the view or the placement panel; at the three heirlooms the pause
#                             menu reads it; on the heirloom bar the bar reads it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses it,
#                             then back; hints HEIRLOOMS meanwhile)
#   Mouse: a click on a card or choice takes it; hovering an heirloom shows its tooltip.
# ============================================================

## The hint context of each step of the view.
const HINT_CONTEXTS: Dictionary[StartingOfferView.Step, StringName] = {
	StartingOfferView.Step.HEIRLOOM: &"OFFER",
	StartingOfferView.Step.RECRUIT: &"PICK",
	StartingOfferView.Step.WEAPON: &"PICK",
	StartingOfferView.Step.UNIT: &"CHOOSE",
	StartingOfferView.Step.PLACEMENT: &"CHOOSE",
}

var _is_leaving: bool = false
var _step_context: StringName = &"OFFER"

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _view: StartingOfferView = %StartingOfferView
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.STARTING_HEIRLOOM:
		_is_leaving = true
		RunScreen.go()
		return
	var seat: int = session.seats[0]
	_header.show_run(session.run, seat)
	_header.title = "Starting heirloom"
	_heirlooms.show_views(HeirloomViewModel.for_run(session.run.seat_run(seat)))
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_view.step_changed.connect(_on_view_step_changed)
	_view.command_ready.connect(_on_view_command_ready)
	_view.open(session, seat)
	CampaignPlayback.play_pending(session)


## The offer view, for tests and captures.
func get_view() -> StartingOfferView:
	return _view


## The heirloom bar, for tests.
func get_heirloom_bar() -> HeirloomBar:
	return _heirlooms


func _on_view_command_ready(command: StartingHeirloomCommand) -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	var batch: CampaignBatch = CampaignService.submit_command(command)
	if batch == null or batch.is_rejected():
		_view.show_problem("Can't take it: %s." % [
			batch.rejected_reason if batch != null else "no run in progress",
		])
		return
	_is_leaving = true
	CampaignPlayback.play_pending(session)
	_heirlooms.show_views(HeirloomViewModel.for_run(session.run.seat_run(session.seats[0])))
	RunScreen.go()


func _on_view_step_changed(step: StartingOfferView.Step) -> void:
	_step_context = HINT_CONTEXTS.get(step, &"OFFER")
	_hints.context = _step_context


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _step_context
