# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     starting_heirloom_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 24, 2026
# ==============================================================================

extends Control
## The run's starting heirloom offer, after New Run and before the first node (Slay the Spire's
## first choice): the [StartingOfferView] over the run's header and [HeirloomBar]. The faction and
## commander pickers before it are skipped while the MVP has one of each.
##
## The local seat's offer. The view's command goes through a [CampaignLink], which saves; a
## refusal shows its reason on the view and changes nothing. Once the seat's pick resolves, the
## run's facts play ([CampaignPlayback]) and the bar shows the new heirloom; while a teammate's
## offer is open the view gives way to who the seat waits for. The team leaves together: once
## every seat's offer is resolved, the run goes to the map ([method RunScreen.go]). A quit before
## then Continues here with the same offer, saved in the seat's pending offers. Opened at any
## other stage, it sends the run on at once.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI and the view; the view's own block
# lists what it reads):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick      (along the cards and Back or Skip)
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick      (along a unit column or a placement)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (take the focused card or choice)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back in a sub-choice, read by
#                             the view or the placement panel; at the three heirlooms and while
#                             waiting the pause menu reads it; on the heirloom bar the bar reads
#                             it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses it,
#                             then back; hints HEIRLOOMS meanwhile; works while waiting too)
#   While waiting for a teammate's pick only the last two act: the cards are hidden.
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

# The hint context while the seat waits for a teammate's pick.
const _WAITING_CONTEXT: StringName = &"WAITING"

var _is_leaving: bool = false
var _step_context: StringName = &"OFFER"
var _link: CampaignLink = null

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _view: StartingOfferView = %StartingOfferView
@onready var _waiting_line: Label = %WaitingLine
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.STARTING_HEIRLOOM:
		_is_leaving = true
		RunScreen.go()
		return
	_link = CampaignLink.new(
			session, CampaignService.local_seat(), CampaignService.submit_command
	)
	_link.batch_resolved.connect(_on_link_batch_resolved)
	_link.refused.connect(_on_link_refused)
	_show_seat()
	_header.title = "Starting heirloom"
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_view.step_changed.connect(_on_view_step_changed)
	_view.command_ready.connect(_on_view_command_ready)
	_view.open(session, _link.seat)
	_show_waiting()
	CampaignPlayback.play_pending(session)


func _exit_tree() -> void:
	if _link != null:
		_link.close()


## The offer view, for tests and captures.
func get_view() -> StartingOfferView:
	return _view


## The heirloom bar, for tests.
func get_heirloom_bar() -> HeirloomBar:
	return _heirlooms


## The line naming the teammates the seat waits for, shown once its own offer is resolved; for
## tests.
func get_waiting_line() -> Label:
	return _waiting_line


# The header and heirloom bar for the local seat, as the run saved them.
func _show_seat() -> void:
	var run: CampaignRunState = _link.session.run
	_header.show_run(run, _link.seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_link.seat)))


# Once the seat's own offer is resolved: the view gives way to the teammates it waits for, and the
# hints to what still acts (the heirloom bar and the pause menu).
func _show_waiting() -> void:
	var run: CampaignRunState = _link.session.run
	var is_waiting: bool = not StartingOffer.is_open(run.seat_run(_link.seat))
	_view.visible = not is_waiting
	_waiting_line.visible = is_waiting
	if not is_waiting:
		return
	var open: PackedInt32Array = []
	for teammate: int in _link.teammates():
		if StartingOffer.is_open(run.seat_run(teammate)):
			open.append(teammate)
	_waiting_line.text = "Waiting for %s." % [EventScreenModel.seat_names(open)]
	_step_context = _WAITING_CONTEXT
	if _hints.context != HeirloomBar.HINT_CONTEXT:
		_hints.context = _step_context


func _on_view_command_ready(command: StartingHeirloomCommand) -> void:
	if _is_leaving:
		return
	_link.send(command)


# Any seat's batch: one the screen follows plays its facts; the seat's parts show again. While any
# seat's offer is open the team stays here; once none is, a batch the screen follows moves the run
# to the map, which on a client waits for the host's route.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _is_leaving:
		return
	var follows: bool = _link.moves_with(batch, is_answer)
	if follows:
		CampaignPlayback.play_pending(_link.session)
	_show_seat()
	if RunScreen.of(_link.session) == SceneRouter.Screen.STARTING_HEIRLOOM:
		_show_waiting()
		return
	if follows:
		_is_leaving = true
		RunScreen.go()


func _on_link_refused(reason: String) -> void:
	_view.show_problem("Can't take it: %s." % [reason])


func _on_view_step_changed(step: StartingOfferView.Step) -> void:
	_step_context = HINT_CONTEXTS.get(step, &"OFFER")
	_hints.context = _step_context


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _step_context
