# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 23, 2026
# ==============================================================================

extends Control
## The campaign map for the local seat: the whole run's map, the route taken, and the nodes it can
## enter next. Solo chooses one ([ChooseNodeCommand]); co-op votes ([RouteVoteCommand]), each
## vote shown on its node and in the [RouteVoteStatus], and the vote that completes the set shows
## the node it drew, with Continue, before the screen follows the run there.
##
## Sends through a [CampaignLink]; once a batch the screen follows leaves the map it goes where
## the run belongs ([method RunScreen.go]). No confirm step (Godot_FE's had none). A refusal shows
## its reason. Army (its button, or unit_detail) opens the [ArmyView]; in co-op its Team button
## opens the [TeamPanel] (each teammate's vote and swaps as notes) and Swaps the [SwapPanel]. The
## [SwapStatus] shows the seat's open and agreed swaps. Every batch rebuilds the screen from the
## run; the run's facts play ([CampaignPlayback]) as it opens and after each batch it follows.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_left" / "ui_right" -> Left / Right arrows; d-pad, left stick    (move focus between the
#                             reachable nodes, in column order; the ends stop. On the heirloom
#                             bar: between its icons, wrapping)
#   "ui_up" / "ui_down"    -> deliberately inert: focus stays on the node; the map scrolls only
#                             to follow focus (MapScroll) and by the mouse wheel
#   "ui_accept"            -> Enter, Space; pad A [Cross]               (choose the focused node;
#                             in co-op vote for it; after the draw press Continue)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]       (the pause menu, which
#                             reads it; on the heirloom bar the bar reads it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]               (read by the HeirloomBar:
#                             focuses it, then back to the node; hints HEIRLOOMS meanwhile)
# The army view opens on battle's unit_detail: no pad button is free, and a map-only action's pad
# binding would act in battle; "view details" reads the same on both.
#   "unit_detail"          -> Ctrl; LS [L3]                             (read here in
#                             _unhandled_input, not during the draw: opens the army view; inside
#                             it the view reads ui_cancel, closing it, and the GUI moves between
#                             its Scrap buttons and, in co-op, Team and Swaps, which open the team
#                             and swap panels; each reads its own ui_cancel, back to the view)
#   Mouse: a click on a reachable node chooses or votes for it, on Army opens the army view, on
#   Continue moves on after the draw; hovering any node describes it, a vote badge names its
#   voters, and any heirloom shows its tooltip; the wheel scrolls the map.
# ============================================================

## The hint context while choosing a node, solo.
const HINT_CONTEXT: StringName = &"MAP"

## The hint context while voting for a node, co-op.
const HINT_VOTE: StringName = &"VOTE"

## The hint context while the drawn node shows, waiting on Continue.
const HINT_DRAWN: StringName = &"DRAWN"

## The hint context while the army view shows.
const HINT_ARMY: StringName = &"ARMY"

## The input action that opens the army view.
const ARMY_ACTION: StringName = &"unit_detail"

var _is_leaving: bool = false
# Whether the drawn node shows, waiting on Continue; the run is already inside it.
var _is_drawing: bool = false
# Whether the choices have been scrolled into view since the screen opened.
var _is_revealed: bool = false
# The control focused when the army view opened, given focus back when it closes.
var _focus_before_army: Control = null
var _link: CampaignLink = null

@onready var _header: RunHeader = %RunHeader
@onready var _map_view: CampaignMapView = %CampaignMapView
@onready var _map_scroll: ScrollContainer = %MapScroll
@onready var _info_label: Label = %NodeInfo
@onready var _status_label: Label = %Status
@onready var _hints: ScreenHints = %ScreenHints
@onready var _heirlooms: HeirloomBar = %HeirloomBar
@onready var _army_button: Button = %ArmyButton
@onready var _army_view: ArmyView = %ArmyView
@onready var _team_panel: TeamPanel = %TeamPanel
@onready var _swap_panel: SwapPanel = %SwapPanel
@onready var _vote_status: RouteVoteStatus = %RouteVoteStatus
@onready var _swap_status: SwapStatus = %SwapStatus
@onready var _coop_side: VBoxContainer = %CoopSide


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.CAMPAIGN_MAP:
		_is_leaving = true
		RunScreen.go()
		return
	_link = CampaignLink.new(
			session, CampaignService.local_seat(), CampaignService.submit_command
	)
	_link.batch_resolved.connect(_on_link_batch_resolved)
	_link.refused.connect(_on_link_refused)
	_map_view.node_chosen.connect(_on_map_view_node_chosen)
	_map_view.node_inspected.connect(_on_map_view_node_inspected)
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	_army_button.pressed.connect(_open_army)
	_army_view.command_ready.connect(_on_army_view_command_ready)
	_army_view.closed.connect(_on_army_view_closed)
	_army_view.team_requested.connect(_on_army_view_team_requested)
	_army_view.swaps_requested.connect(_on_army_view_swaps_requested)
	_swap_panel.command_ready.connect(_on_swap_panel_command_ready)
	_vote_status.continued.connect(_on_vote_status_continued)
	var run: CampaignRunState = session.run
	# The vote and swaps have their own column, so the legend's column keeps solo's layout.
	_coop_side.visible = _link.is_coop()
	_show_seat()
	_map_view.show_run(run)
	_show_coop()
	_status_label.text = "" if not _map_view.get_reachable().is_empty() else "No node is reachable."
	_info_label.text = "Vote for the next node." if _link.is_coop() else "Choose the next node."
	_hints.context = _map_context()
	_map_view.focus_first_reachable.call_deferred()
	# Follow-focus scrolls before the map's height is laid out, so each layout pass scrolls the
	# choices into view until they show; then never again, so the wheel stays free.
	_map_scroll.sort_children.connect(_on_map_scroll_sort_children)
	CampaignPlayback.play_pending(session)


func _exit_tree() -> void:
	if _link != null:
		_link.close()


func _unhandled_input(event: InputEvent) -> void:
	if (
			_is_leaving or _is_drawing or _army_view.visible or _team_panel.visible
			or _swap_panel.visible or not event.is_action_pressed(ARMY_ACTION)
	):
		return
	get_viewport().set_input_as_handled()
	_open_army()


## The army view, for tests and captures.
func get_army_view() -> ArmyView:
	return _army_view


## The Army button, for tests.
func get_army_button() -> Button:
	return _army_button


## The map, for tests.
func get_map_view() -> CampaignMapView:
	return _map_view


## The info line's text, for tests.
func get_info_text() -> String:
	return _info_label.text


## The heirloom bar, for tests.
func get_heirloom_bar() -> HeirloomBar:
	return _heirlooms


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


## The team panel, for tests and captures.
func get_team_panel() -> TeamPanel:
	return _team_panel


## The swap panel, for tests and captures.
func get_swap_panel() -> SwapPanel:
	return _swap_panel


## The route vote's status, for tests and captures.
func get_vote_status() -> RouteVoteStatus:
	return _vote_status


## The swaps' status in the side panel, for tests and captures.
func get_swap_status() -> SwapStatus:
	return _swap_status


## Whether the drawn node shows, waiting on Continue, for tests and captures.
func is_drawing() -> bool:
	return _is_drawing


# The header and heirloom bar for the local seat, as the run saved them.
func _show_seat() -> void:
	var run: CampaignRunState = _link.session.run
	_header.show_run(run, _link.seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_link.seat)))


# In co-op, the open vote on the nodes and in the side panel, and the seat's swaps.
func _show_coop() -> void:
	if not _link.is_coop():
		return
	var run: CampaignRunState = _link.session.run
	_map_view.show_votes(run.open_route_votes(), _link.seat)
	_vote_status.show_vote(run, _link.seat)
	_swap_status.show_swaps(run, _link.seat)


# The hint context while the nodes have focus.
func _map_context() -> StringName:
	return HINT_VOTE if _link != null and _link.is_coop() else HINT_CONTEXT


# Each teammate's vote and swaps, for the team panel's notes.
func _team_notes() -> Dictionary[int, String]:
	var run: CampaignRunState = _link.session.run
	var votes: Dictionary[int, int] = run.open_route_votes()
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var notes: Dictionary[int, String] = {}
	for teammate: int in _link.teammates():
		var vote: String = (
				"Voted for %s." % [RouteVoteStatus.node_text(run.graph, votes[teammate])]
				if votes.has(teammate) else "Hasn't voted."
		)
		var swaps: String = SwapText.team_note(run, teammate, _link.seat, catalog)
		notes[teammate] = (vote + " " + swaps).strip_edges()
	return notes


func _on_map_view_node_chosen(node_id: int) -> void:
	if _is_leaving or _is_drawing:
		return
	if not _link.is_coop():
		_link.send(ChooseNodeCommand.new(_link.seat, node_id))
		return
	var run: CampaignRunState = _link.session.run
	if run.open_route_votes().get(_link.seat, CampaignGraph.NO_NODE) == node_id:
		return
	var vote: RouteVoteCommand = RouteVoteCommand.for_session(_link.session, _link.seat, node_id)
	if vote != null:
		_link.send(vote)


# Any seat's batch: one the screen follows plays its facts and, once the run left the map, moves
# the screen on, after showing a co-op draw; while the run is still here its parts show again.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _is_leaving or _is_drawing:
		return
	var follows: bool = _link.moves_with(batch, is_answer)
	if follows:
		CampaignPlayback.play_pending(_link.session)
	if RunScreen.of(_link.session) != SceneRouter.Screen.CAMPAIGN_MAP:
		if not follows:
			return
		var drawn: int = _drawn_node(batch)
		if drawn != CampaignGraph.NO_NODE:
			_show_draw(drawn)
			return
		_is_leaving = true
		RunScreen.go()
		return
	if is_answer:
		_status_label.text = ""
	_show_seat()
	_show_coop()
	if _army_view.visible and (_link.touches_seat(batch) or _names_seat_in_swap(batch)):
		_army_view.refresh()
	if _link.is_coop():
		_team_panel.refresh(_team_notes())
	_swap_panel.refresh()


# The node batch's route draw entered: its NODE_CHOSEN for no seat. NO_NODE without one.
func _drawn_node(batch: CampaignBatch) -> int:
	for fact: CampaignFact in batch.facts:
		if fact.kind == CampaignFact.Kind.NODE_CHOSEN and fact.seat == CampaignFact.NO_SEAT:
			return fact.amount
	return CampaignGraph.NO_NODE


# Whether a swap fact of batch names the local seat as its partner (its amount); a proposer's
# facts carry its own seat, which touches_seat() already reads.
func _names_seat_in_swap(batch: CampaignBatch) -> bool:
	for fact: CampaignFact in batch.facts:
		var is_swap: bool = (
				fact.kind == CampaignFact.Kind.SWAP_PROPOSED
				or fact.kind == CampaignFact.Kind.SWAP_ACCEPTED
				or fact.kind == CampaignFact.Kind.SWAP_ENDED
		)
		if is_swap and fact.amount == _link.seat:
			return true
	return false


# Shows the node the votes drew, the run already inside it: every panel closed, no node
# focusable, the draw's votes on their nodes, and Continue focused.
func _show_draw(drawn: int) -> void:
	_is_drawing = true
	_swap_panel.close()
	_team_panel.close()
	_army_view.close()
	var run: CampaignRunState = _link.session.run
	# The drawn node was in view while voting; the rebuild would scroll the map back to its top.
	var kept_scroll: int = _map_scroll.scroll_vertical
	_map_view.show_run(run, false)
	_map_view.show_votes(run.route_votes, _link.seat)
	_map_scroll.set_deferred(&"scroll_vertical", kept_scroll)
	_vote_status.show_draw(run, _link.seat, drawn)
	_swap_status.show_swaps(run, _link.seat)
	_show_seat()
	_info_label.text = "The team's next node is drawn."
	_status_label.text = ""
	_hints.context = HINT_DRAWN
	_vote_status.get_continue_button().grab_focus()


func _on_vote_status_continued() -> void:
	if _is_leaving or not _is_drawing:
		return
	_is_leaving = true
	RunScreen.go()


func _on_link_refused(reason: String) -> void:
	if _swap_panel.visible:
		_swap_panel.show_refusal(reason)
	elif _army_view.visible:
		_army_view.show_problem("Can't do that: %s." % [reason])
	else:
		_status_label.text = "Can't go there: %s." % [reason]


# Scrolls the focused choice (else the first) into view after a layout pass; done once it shows.
func _reveal_choices() -> void:
	var reachable: PackedInt32Array = _map_view.get_reachable()
	if _is_revealed or reachable.is_empty() or not is_inside_tree():
		return
	var target: Control = _map_view.get_node_button(reachable[0])
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is MapNodeButton:
		target = focused
	if _map_scroll.get_global_rect().encloses(target.get_global_rect()):
		_is_revealed = true
		return
	_map_scroll.ensure_control_visible(target)


func _on_map_scroll_sort_children() -> void:
	if not _is_revealed:
		_reveal_choices.call_deferred()


func _on_map_view_node_inspected(node_id: int) -> void:
	var where: String = RouteVoteStatus.node_text(CampaignService.session.run.graph, node_id)
	var hint: String = "  (vote for it)" if _link.is_coop() else "  (choose it)"
	_info_label.text = where + (hint if _map_view.get_reachable().has(node_id) else "")


# Opens the army view to view and scrap, remembering the focus to give back.
func _open_army() -> void:
	if _is_leaving or _is_drawing or _army_view.visible:
		return
	_focus_before_army = get_viewport().gui_get_focus_owner()
	_army_view.open(_link.session, _link.seat, ArmyView.Mode.VIEW)
	_hints.context = HINT_ARMY


func _on_army_view_command_ready(command: CampaignCommand) -> void:
	_link.send(command)


func _on_army_view_team_requested() -> void:
	_team_panel.open(_link.session, _link.seat, _team_notes())


func _on_army_view_swaps_requested() -> void:
	_swap_panel.open(_link.session, _link.seat)


func _on_swap_panel_command_ready(command: CampaignCommand) -> void:
	_link.send(command)


func _on_army_view_closed() -> void:
	if _is_drawing:
		_focus_before_army = null
		return
	_hints.context = _map_context()
	if is_instance_valid(_focus_before_army) and _focus_before_army.is_visible_in_tree():
		_focus_before_army.grab_focus()
	else:
		_map_view.focus_first_reachable()
	_focus_before_army = null


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = _map_context()
