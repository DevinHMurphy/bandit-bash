# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Control
## The event an Unknown node holds: the [EventPanel] under the run's header and [HeirloomBar].
##
## The panel's commands go through [method CampaignService.submit_command], which saves; a
## rejection shows its reason on the panel and changes nothing. After each, the run's facts play
## ([CampaignPlayback]: the event's draw sounds as the screen opens), the header and bar follow,
## and the panel shows the saved step again, so a quit Continues at the option list, the chooser
## or the outcome. Leave sends [LeaveNodeCommand] and returns to the map; with a surprise combat
## pending it is Fight, which goes to the battle ([method RunScreen.go]). Opened at any other
## stage, it sends the run on at once. Shows the game's events ([method EventPool.load_default]).
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI and the panel; the panel's own block
# lists what it reads):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick      (along the option cards)
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick      (along a chooser or a placement)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (choose or vote for the focused card,
#                             the focused choice, or Leave / Fight)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back in a chooser or the rune
#                             discard, read by the panel; in a placement the placement panel reads
#                             it; on the cards and the outcome the pause menu reads it; on the
#                             heirloom bar the bar reads it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses it,
#                             then back; hints HEIRLOOMS meanwhile)
#   Mouse: a click on a card, choice or Leave presses it; hovering an heirloom shows its tooltip.
# ============================================================

## The hint context of each step of the panel; the outcome's is [constant FIGHT_CONTEXT] with a
## surprise combat pending.
const HINT_CONTEXTS: Dictionary[EventPanel.Step, StringName] = {
	EventPanel.Step.CLOSED: &"DONE",
	EventPanel.Step.OPTIONS: &"OPTIONS",
	EventPanel.Step.VOTE: &"VOTE",
	EventPanel.Step.DRAWN: &"OPTIONS",
	EventPanel.Step.CHOOSER: &"CHOOSE",
	EventPanel.Step.PLACEMENT: &"CHOOSE",
	EventPanel.Step.RUNE: &"CHOOSE",
	EventPanel.Step.OUTCOME: &"DONE",
}

## The outcome's hint context while a surprise combat waits.
const FIGHT_CONTEXT: StringName = &"FIGHT"

## The header's title while no event can be shown.
const NO_EVENT_TITLE: String = "Event"

var _is_leaving: bool = false
var _step_context: StringName = &"OPTIONS"

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _panel: EventPanel = %EventPanel
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.EVENT:
		_is_leaving = true
		RunScreen.go()
		return
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_panel.step_changed.connect(_on_panel_step_changed)
	_panel.command_ready.connect(_on_panel_command_ready)
	_panel.leave_requested.connect(_on_panel_leave_requested)
	_panel.open(session, session.seats[0])
	_show_run()
	CampaignPlayback.play_pending(session)


## Shows the open event again from [param pool], read with [param catalog] (null: the game's
## own), header included: for tests and captures, whose test-only events the game's pool lacks.
func reopen(pool: EventPool, catalog: EffectCatalog.Index = null) -> void:
	var session: CampaignSession = CampaignService.session
	_panel.open(session, session.seats[0], pool, catalog)
	_show_run()


## The event panel, for tests and captures.
func get_panel() -> EventPanel:
	return _panel


## The heirloom bar, for tests.
func get_heirloom_bar() -> HeirloomBar:
	return _heirlooms


## The header, for tests.
func get_header() -> RunHeader:
	return _header


## The hint context shown, for tests.
func get_hint_context() -> StringName:
	return _hints.context


# The header and bar as the run stands, titled with the event's name.
func _show_run() -> void:
	var session: CampaignSession = CampaignService.session
	var seat: int = session.seats[0]
	var view: EventView = _panel.get_view()
	_header.show_run(session.run, seat)
	_header.title = view.event.title if view.is_open() else NO_EVENT_TITLE
	_heirlooms.show_views(HeirloomViewModel.for_run(session.run.seat_run(seat)))


func _on_panel_command_ready(command: CampaignCommand) -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	var batch: CampaignBatch = (
			null if command == null else CampaignService.submit_command(command)
	)
	if batch == null or batch.is_rejected():
		_panel.show_problem("Can't do that: %s." % [
			batch.rejected_reason if batch != null else "no run in progress",
		])
		return
	CampaignPlayback.play_pending(session)
	_panel.refresh()
	_show_run()


func _on_panel_leave_requested() -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	if _panel.get_view().is_combat_pending:
		_is_leaving = true
		RunScreen.go()
		return
	var batch: CampaignBatch = CampaignService.submit_command(
			LeaveNodeCommand.new(session.seats[0])
	)
	if batch == null or batch.is_rejected():
		_panel.show_problem("Couldn't leave: %s." % [
			batch.rejected_reason if batch != null else "no run in progress",
		])
		return
	_is_leaving = true
	CampaignPlayback.play_pending(session)
	RunScreen.go()


func _on_panel_step_changed(step: EventPanel.Step) -> void:
	_step_context = HINT_CONTEXTS.get(step, &"OPTIONS")
	if step == EventPanel.Step.OUTCOME and _panel.get_view().is_combat_pending:
		_step_context = FIGHT_CONTEXT
	_hints.context = _step_context


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _step_context
