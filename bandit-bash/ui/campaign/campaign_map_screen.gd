# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 21, 2026
# ==============================================================================

extends Control
## The campaign map for the local seat: the whole run's map, the route taken, and the nodes it can
## enter next; the player chooses one and the run goes in.
##
## Choosing sends [ChooseNodeCommand] through a [CampaignLink]; once any seat's choice resolves
## the screen goes where the run now belongs ([method RunScreen.go]): a Treasure, Camp, Armory or
## Guildhall to its own screen, a combat to the battle, an Unknown to what it became (an event, a
## surprise combat, a shop or treasure, or the placeholder). No confirm step (Godot_FE's had none).
## A refusal shows its reason. The [HeirloomBar] shows the seat's heirlooms; Army (its button, or
## unit_detail) opens the [ArmyView] to view and scrap, and in co-op its Team button the
## [TeamPanel]. Every batch rebuilds the screen from the run; the run's facts play
## ([CampaignPlayback]) as it opens and after each batch, before the screen changes.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_left" / "ui_right" -> Left / Right arrows; d-pad, left stick    (move focus between the
#                             reachable nodes, in column order; the ends stop. On the heirloom
#                             bar: between its icons, wrapping)
#   "ui_up" / "ui_down"    -> deliberately inert: focus stays on the node; the map scrolls only
#                             to follow focus (MapScroll) and by the mouse wheel
#   "ui_accept"            -> Enter, Space; pad A [Cross]               (choose the focused node)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]       (the pause menu, which
#                             reads it; on the heirloom bar the bar reads it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]               (read by the HeirloomBar:
#                             focuses it, then back to the node; hints HEIRLOOMS meanwhile)
# The army view opens on battle's unit_detail: no pad button is free, and a map-only action's pad
# binding would act in battle; "view details" reads the same on both.
#   "unit_detail"          -> Ctrl; LS [L3]                             (read here in
#                             _unhandled_input: opens the army view; inside it the view reads
#                             ui_cancel, closing it, and the GUI moves between its Scrap buttons
#                             and, in co-op, Team, which opens the team panel; the panel reads
#                             its own ui_cancel, back to the army view)
#   Mouse: a click on a reachable node chooses it, on Army opens the army view; hovering any node
#   describes it, and any heirloom shows its tooltip; the wheel scrolls the map.
# ============================================================

## The hint context while choosing a node.
const HINT_CONTEXT: StringName = &"MAP"

## The hint context while the army view shows.
const HINT_ARMY: StringName = &"ARMY"

## The input action that opens the army view.
const ARMY_ACTION: StringName = &"unit_detail"

var _is_leaving: bool = false
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
	var run: CampaignRunState = session.run
	_show_seat()
	_map_view.show_run(run)
	_status_label.text = "" if not _map_view.get_reachable().is_empty() else "No node is reachable."
	_info_label.text = "Choose the next node."
	_hints.context = HINT_CONTEXT
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
			_is_leaving or _army_view.visible or _team_panel.visible
			or not event.is_action_pressed(ARMY_ACTION)
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


# The header and heirloom bar for the local seat, as the run saved them.
func _show_seat() -> void:
	var run: CampaignRunState = _link.session.run
	_header.show_run(run, _link.seat)
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(_link.seat)))


func _on_map_view_node_chosen(node_id: int) -> void:
	if _is_leaving:
		return
	_link.send(ChooseNodeCommand.new(_link.seat, node_id))


# Any seat's batch: one the screen follows plays its facts and, once the run left the map, moves
# the screen on; while the run is still here the seat's parts show again.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _is_leaving:
		return
	var follows: bool = _link.moves_with(batch, is_answer)
	if follows:
		CampaignPlayback.play_pending(_link.session)
	if RunScreen.of(_link.session) != SceneRouter.Screen.CAMPAIGN_MAP:
		if follows:
			_is_leaving = true
			RunScreen.go()
		return
	_show_seat()
	if _army_view.visible and _link.touches_seat(batch):
		_army_view.refresh()
	_team_panel.refresh()


func _on_link_refused(reason: String) -> void:
	if _army_view.visible:
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
	var graph: CampaignGraph = CampaignService.session.run.graph
	var type_name: String = CampaignMapView.TYPE_NAMES.get(graph.type_of(node_id), "?")
	var where: String = "Floor %d · %s" % [graph.floor_of(node_id), type_name]
	_info_label.text = where + ("  (choose it)" if _map_view.get_reachable().has(node_id) else "")


# Opens the army view to view and scrap, remembering the focus to give back.
func _open_army() -> void:
	if _is_leaving or _army_view.visible:
		return
	_focus_before_army = get_viewport().gui_get_focus_owner()
	_army_view.open(_link.session, _link.seat, ArmyView.Mode.VIEW)
	_hints.context = HINT_ARMY


func _on_army_view_command_ready(command: CampaignCommand) -> void:
	_link.send(command)


func _on_army_view_team_requested() -> void:
	_team_panel.open(_link.session, _link.seat)


func _on_army_view_closed() -> void:
	_hints.context = HINT_CONTEXT
	if is_instance_valid(_focus_before_army) and _focus_before_army.is_visible_in_tree():
		_focus_before_army.grab_focus()
	else:
		_map_view.focus_first_reachable()
	_focus_before_army = null


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = HINT_CONTEXT
