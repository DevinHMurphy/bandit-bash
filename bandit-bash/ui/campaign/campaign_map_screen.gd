# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_screen.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Control
## The campaign map: the whole run's map, the route taken, and the nodes it can enter next; the
## player chooses one and the run goes in.
##
## Choosing sends [ChooseNodeCommand] through [method CampaignService.submit_command], which saves;
## once it resolves the screen goes where the run now belongs ([method RunScreen.go]): the battle
## for a combat node, the placeholder for any other. There is no confirm step (Godot_FE's map had
## none). A rejected choice shows its reason and changes nothing. Opened at any other stage, it
## sends the run on at once. The info line describes the node hovered or focused. The
## [HeirloomBar] under the header shows the seat's heirlooms as the run saved them.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions; read through the GUI, not here):
#   "ui_left" / "ui_right" -> Left / Right arrows; d-pad, left stick    (move focus between the
#                             reachable nodes, in column order; the ends stop. On the heirloom
#                             bar: between its icons, wrapping)
#   "ui_up" / "ui_down"    -> deliberately inert: focus stays on the node (nothing scrolls)
#   "ui_accept"            -> Enter, Space; pad A [Cross]               (choose the focused node)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]       (the pause menu, which
#                             reads it; on the heirloom bar the bar reads it, closing itself)
#   "heirloom_bar_focus"   -> H; RS pushed left [R stick]               (read by the HeirloomBar:
#                             focuses it, then back to the node; hints HEIRLOOMS meanwhile)
#   Mouse: a click on a reachable node chooses it; hovering any node describes it, and any
#   heirloom shows its tooltip.
# ============================================================

## The hint context while choosing a node.
const HINT_CONTEXT: StringName = &"MAP"

var _is_leaving: bool = false

@onready var _header: RunHeader = %RunHeader
@onready var _map_view: CampaignMapView = %CampaignMapView
@onready var _info_label: Label = %NodeInfo
@onready var _status_label: Label = %Status
@onready var _hints: ScreenHints = %ScreenHints
@onready var _heirlooms: HeirloomBar = %HeirloomBar


func _ready() -> void:
	var session: CampaignSession = CampaignService.session
	if RunScreen.of(session) != SceneRouter.Screen.CAMPAIGN_MAP:
		_is_leaving = true
		RunScreen.go()
		return
	_map_view.node_chosen.connect(_on_map_view_node_chosen)
	_map_view.node_inspected.connect(_on_map_view_node_inspected)
	_heirlooms.navigation_started.connect(_on_heirloom_bar_navigation_started)
	_heirlooms.navigation_ended.connect(_on_heirloom_bar_navigation_ended)
	var run: CampaignRunState = session.run
	_header.show_run(run, session.seats[0])
	_heirlooms.show_views(HeirloomViewModel.for_run(run.seat_run(session.seats[0])))
	_map_view.show_run(run)
	_status_label.text = "" if not _map_view.get_reachable().is_empty() else "No node is reachable."
	_info_label.text = "Choose the next node."
	_hints.context = HINT_CONTEXT
	_map_view.focus_first_reachable.call_deferred()


## The map, for tests.
func get_map_view() -> CampaignMapView:
	return _map_view


## The info line's text, for tests.
func get_info_text() -> String:
	return _info_label.text


## The heirloom bar, for tests.
func get_heirloom_bar() -> HeirloomBar:
	return _heirlooms


func _on_map_view_node_chosen(node_id: int) -> void:
	if _is_leaving:
		return
	var session: CampaignSession = CampaignService.session
	var batch: CampaignBatch = CampaignService.submit_command(
			ChooseNodeCommand.new(session.seats[0], node_id)
	)
	if batch == null or batch.is_rejected():
		_status_label.text = "Can't go there: %s." % [
			batch.rejected_reason if batch != null else "no run in progress",
		]
		return
	_is_leaving = true
	RunScreen.go()


func _on_map_view_node_inspected(node_id: int) -> void:
	var graph: CampaignGraph = CampaignService.session.run.graph
	var type_name: String = CampaignMapView.TYPE_NAMES.get(graph.type_of(node_id), "?")
	var where: String = "Floor %d · %s" % [graph.floor_of(node_id), type_name]
	_info_label.text = where + ("  (choose it)" if _map_view.get_reachable().has(node_id) else "")


func _on_heirloom_bar_navigation_started() -> void:
	_hints.context = HeirloomBar.HINT_CONTEXT


func _on_heirloom_bar_navigation_ended() -> void:
	_hints.context = HINT_CONTEXT
