# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_screen.gd
# Author:
# Created:  November 19, 2026
# Modified: November 24, 2026
# ==============================================================================

extends Control
## The event an Unknown node holds, for the local seat: the [EventPanel] under the run's header and
## [HeirloomBar]; in co-op, Team opens the [TeamPanel] with each teammate's vote or choice.
##
## Commands go through a [CampaignLink] ([method CampaignService.submit_command], which saves),
## and the screen rebuilds from what the session reports, never the submit's return: the seat's
## own batches show the saved step again (a quit Continues there), a teammate's updates votes and
## choices but keeps the seat's picks, and a refusal shows on the panel. Facts play
## ([CampaignPlayback]) for the batches it follows. Leave (the panel's [ReadyToggle], its glyph
## from this hint bar) sends [LeaveNodeCommand]; with a combat pending, Fight goes to the battle
## ([method RunScreen.go]). Opened elsewhere, it sends the run on. Uses the game's events.
##
## @tutorial(Events and curses plan): docs/plans/2026-11-12-events-and-curses.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions, read through the GUI and the panel; the panel's own block
# lists what it reads):
#   "ui_left" / "ui_right" -> arrows; d-pad, left stick      (along the option cards)
#   "ui_up" / "ui_down"    -> arrows; d-pad, left stick      (along a chooser, the unit that
#                             leaves, its hand-over's rows, or a placement; in co-op, down from
#                             the cards or Leave to Team, and the team panel's rows)
#   "ui_accept"            -> Enter, Space; pad A [Cross]    (choose or vote for the focused card,
#                             the focused choice or place, or Leave / Fight / Team; the hints say
#                             Team while it has focus)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options] (Back in a chooser, the unit
#                             that leaves, its hand-over or the rune discard, read by the panel;
#                             in a placement
#                             the placement panel reads it; the team panel reads it while open; on
#                             the cards and the outcome the pause menu reads it; on the heirloom
#                             bar the bar reads it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]    (read by the HeirloomBar: focuses it,
#                             then back; hints HEIRLOOMS meanwhile)
#   Mouse: a click on a card, choice, Leave or Team presses it; hovering an heirloom or a keyword
#   shows its tooltip.
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
	EventPanel.Step.LEAVING: &"CHOOSE",
	EventPanel.Step.HAND_OVER: &"HAND_OVER",
}

## The outcome's hint context while a surprise combat waits.
const FIGHT_CONTEXT: StringName = &"FIGHT"

## The hint context while the Team button holds focus, on whatever step shows it: accept opens
## the team panel, whatever the step's own accept does.
const TEAM_FOCUS_CONTEXT: StringName = &"ON_TEAM"

## The outcome's hint context while teammates still choose: Leave is closed, so accept presses
## whatever has focus (Team in co-op).
const WAITING_CONTEXT: StringName = &"WAITING"

## The header's title while no event can be shown.
const NO_EVENT_TITLE: String = "Event"

var _is_leaving: bool = false
var _step_context: StringName = &"OPTIONS"
var _is_on_heirlooms: bool = false
var _seat: int = CampaignData.HOST_SEAT
var _link: CampaignLink = null

@onready var _header: RunHeader = %RunHeader
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _panel: EventPanel = %EventPanel
@onready var _team_panel: TeamPanel = %TeamPanel
@onready var _hints: ScreenHints = %ScreenHints
@onready var _hint_bar: ControlHintBar = %ControlHintBar


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.EVENT:
		_is_leaving = true
		RunScreen.go()
		return
	_seat = CampaignService.local_seat()
	_link = CampaignLink.new(session, _seat, CampaignService.submit_command)
	_link.batch_resolved.connect(_on_link_batch_resolved)
	_link.refused.connect(_on_link_refused)
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_panel.step_changed.connect(_on_panel_step_changed)
	_panel.command_ready.connect(_on_panel_command_ready)
	_panel.leave_requested.connect(_on_panel_leave_requested)
	_panel.team_requested.connect(_on_panel_team_requested)
	_team_panel.closed.connect(_on_team_panel_closed)
	get_viewport().gui_focus_changed.connect(_on_viewport_gui_focus_changed)
	_panel.offers_team = _link.is_coop()
	var leave: ReadyToggle = _panel.get_leave_button() as ReadyToggle
	if leave != null:
		leave.hint_bar = _hint_bar
	_panel.open(session, _seat)
	_show_run()
	CampaignPlayback.play_pending(session)


func _exit_tree() -> void:
	if _link != null:
		_link.close()


## Shows the open event again from [param pool], read with [param catalog] (null: the game's
## own), header included: for tests and captures, whose test-only events the game's pool lacks.
func reopen(pool: EventPool, catalog: EffectCatalog.Index = null) -> void:
	_panel.open(CampaignService.session, _seat, pool, catalog)
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


## The team panel, for tests and captures.
func get_team_panel() -> TeamPanel:
	return _team_panel


## The hint context shown, for tests.
func get_hint_context() -> StringName:
	return _hints.context


# The header and bar as the run stands for the seat, titled with the event's name.
func _show_run() -> void:
	var session: CampaignSession = CampaignService.session
	var view: EventView = _panel.get_view()
	_header.show_run(session.run, _seat)
	_header.title = view.event.title if view.is_open() else NO_EVENT_TITLE
	_heirlooms.show_views(HeirloomViewModel.for_run(session.run.seat_run(_seat)))


# Whether the run has left this event: it stands elsewhere, and no surprise combat chosen here
# waits for its Fight (which shows on the outcome until pressed).
func _has_left_event() -> bool:
	var run: CampaignRunState = _link.session.run
	if RunScreen.of(_link.session) == SceneRouter.Screen.EVENT:
		return false
	return not run.events.is_combat_pending_at(run.floor_number, run.node)


# Each teammate's vote or choice as a note for the team panel's rows.
func _team_notes() -> Dictionary[int, String]:
	var notes: Dictionary[int, String] = {}
	var view: EventView = _panel.get_view()
	for teammate: int in _link.teammates():
		notes[teammate] = EventTeamStatus.choice_text(view, teammate) if view.is_open() else ""
	return notes


func _on_panel_command_ready(command: CampaignCommand) -> void:
	if _is_leaving:
		return
	if command == null:
		_panel.show_problem("Can't do that: no run in progress.")
		return
	_link.send(command)


func _on_panel_leave_requested() -> void:
	if _is_leaving:
		return
	if _panel.get_view().is_combat_pending:
		_is_leaving = true
		RunScreen.go()
		return
	_link.send(LeaveNodeCommand.new(_seat))


func _on_panel_team_requested() -> void:
	_team_panel.open(_link.session, _seat, _team_notes())


# Any seat's batch: one the screen follows plays its facts and, once the run has left the event,
# moves the screen on. While the run is still here, the seat's own batches show the saved step
# again and a teammate's updates the team's parts, keeping the seat's picks under way.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _is_leaving:
		return
	var follows: bool = _link.moves_with(batch, is_answer)
	if follows:
		CampaignPlayback.play_pending(_link.session)
	if _has_left_event():
		if follows:
			_is_leaving = true
			RunScreen.go()
		return
	if batch.seat == _seat:
		_panel.refresh()
	else:
		_panel.refresh_team()
	_show_run()
	_team_panel.refresh(_team_notes())


# A refusal of the seat's own command says why where it was made; teammates are named.
func _on_link_refused(reason: String) -> void:
	if _is_leaving:
		return
	_panel.show_problem("Can't do that: %s." % [reason])


func _on_panel_step_changed(step: EventPanel.Step) -> void:
	_step_context = HINT_CONTEXTS.get(step, &"OPTIONS")
	var view: EventView = _panel.get_view()
	if step == EventPanel.Step.OUTCOME and not view.is_finished:
		_step_context = WAITING_CONTEXT
	elif step == EventPanel.Step.OUTCOME and view.is_combat_pending:
		_step_context = FIGHT_CONTEXT
	if not _team_panel.visible:
		_show_hints()


# The step's hints, or Team's while it holds focus; the team panel and the heirloom bar keep
# their own while open.
func _show_hints() -> void:
	if _is_on_heirlooms:
		return
	var team_button: Button = _panel.get_team_button()
	var is_on_team: bool = team_button.is_visible_in_tree() and team_button.has_focus()
	_hints.context = TEAM_FOCUS_CONTEXT if is_on_team else _step_context


func _on_team_panel_closed() -> void:
	_show_hints()


func _on_heirloom_bar_navigation_started() -> void:
	_is_on_heirlooms = true
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_is_on_heirlooms = false
	_show_hints()


func _on_viewport_gui_focus_changed(_control: Control) -> void:
	if not _is_leaving and not _team_panel.visible:
		_show_hints()
