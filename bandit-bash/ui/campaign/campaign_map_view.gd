# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_map_view.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name CampaignMapView
extends Control
## The whole campaign map at once (game-vision.md, Run structure: fully visible from the start):
## every node a [MapNodeButton] in its floor and column, floor 1 at the bottom and the Boss at the
## top, the paths between them drawn as lines, the route taken and the next steps in their colours.
##
## The grid fills the view's rect less [member padding], one row per floor and one column per map
## column, re-laid out on resize, so nothing scrolls. Only the reachable nodes take focus; left
## and right move between them in column order and stop at the ends (Godot_FE's campaign map),
## up and down stay put. Pressing one emits [signal node_chosen]; the screen sends the command.
## Reading only: it never changes the run.

## The player pressed reachable node [param node_id], by click, key or pad.
signal node_chosen(node_id: int)

## Node [param node_id] was hovered or took focus, so the screen can describe it.
signal node_inspected(node_id: int)

const NODE_SCENE: PackedScene = preload("res://ui/campaign/map_node_button.tscn")

## Each node type's name, as the map's tooltips, its legend and the node placeholder show it.
const TYPE_NAMES: Dictionary[CampaignGraph.NodeType, String] = {
	CampaignGraph.NodeType.STANDARD: "Combat",
	CampaignGraph.NodeType.KEY: "Key combat",
	CampaignGraph.NodeType.BOSS: "Boss",
	CampaignGraph.NodeType.ARMORY: "Armory",
	CampaignGraph.NodeType.GUILDHALL: "Guildhall",
	CampaignGraph.NodeType.UNKNOWN: "Unknown",
	CampaignGraph.NodeType.CAMP: "Camp",
	CampaignGraph.NodeType.TREASURE: "Treasure",
}

# Greybox colours and letters per node type until the map has art; Godot_FE drew an icon per room
# type, which type_icons takes once there are icons.
## Each node type's fill colour.
@export var type_colors: Dictionary[CampaignGraph.NodeType, Color] = {
	CampaignGraph.NodeType.STANDARD: Color(0.75, 0.75, 0.75),
	CampaignGraph.NodeType.KEY: Color(0.95, 0.6, 0.3),
	CampaignGraph.NodeType.BOSS: Color(0.9, 0.3, 0.3),
	CampaignGraph.NodeType.ARMORY: Color(0.45, 0.65, 0.95),
	CampaignGraph.NodeType.GUILDHALL: Color(0.6, 0.5, 0.9),
	CampaignGraph.NodeType.UNKNOWN: Color(0.85, 0.85, 0.5),
	CampaignGraph.NodeType.CAMP: Color(0.45, 0.8, 0.5),
	CampaignGraph.NodeType.TREASURE: Color(0.95, 0.8, 0.3),
}

## Each node type's letter, shown when it has no icon in [member type_icons].
@export var type_letters: Dictionary[CampaignGraph.NodeType, String] = {
	CampaignGraph.NodeType.STANDARD: "S",
	CampaignGraph.NodeType.KEY: "K",
	CampaignGraph.NodeType.BOSS: "B",
	CampaignGraph.NodeType.ARMORY: "A",
	CampaignGraph.NodeType.GUILDHALL: "G",
	CampaignGraph.NodeType.UNKNOWN: "?",
	CampaignGraph.NodeType.CAMP: "C",
	CampaignGraph.NodeType.TREASURE: "T",
}

## Each node type's icon, drawn instead of its letter. [b]A type left out:[/b] its letter shows.
@export var type_icons: Dictionary[CampaignGraph.NodeType, Texture2D] = {}

## The size of each node's square.[br]
## [b]Units:[/b] pixels at the base size. Keep below one floor's row ([member size] less
## [member padding], over the floor count) or neighbouring floors touch.
@export var node_size: Vector2 = Vector2(26.0, 26.0)

## The gap between the view's edges and the grid.[br]
## [b]Units:[/b] pixels at the base size.
@export var padding: Vector2 = Vector2(16.0, 6.0)

@export_group("Paths")

## How thick a path is drawn.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(1.0, 8.0, 0.5) var edge_width: float = 2.0

## A path off the route and not leading on from the current node. Defaults to the
## [code]border[/code] token.
@export var edge_color: Color = UiTokens.color(UiTokens.BORDER)

## A path the route took. Defaults to the [code]block[/code] token (the player's side) at 0.9.
@export var route_edge_color: Color = UiTokens.with_alpha(UiTokens.BLOCK, 0.9)

## A path from the current node to a node it can enter next. Defaults to the [code]accent[/code]
## token at 0.8.
@export var next_edge_color: Color = UiTokens.with_alpha(UiTokens.ACCENT, 0.8)

@export_group("")

var _run: CampaignRunState = null
var _buttons: Dictionary[int, MapNodeButton] = {}
var _reachable: PackedInt32Array = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_lay_out()


func _draw() -> void:
	if _run == null or _run.graph == null:
		return
	var graph: CampaignGraph = _run.graph
	for parent: int in graph.node_count():
		for child: int in graph.children_of(parent):
			draw_line(
					node_center(parent), node_center(child), _edge_colour(parent, child),
					edge_width, true
			)


## Shows [param run]'s map: every node, marked by the route taken and what it can enter next.
## Call again after the run changes.
func show_run(run: CampaignRunState) -> void:
	_run = run
	for button: MapNodeButton in _buttons.values():
		remove_child(button)
		button.queue_free()
	_buttons.clear()
	_reachable = run.next_nodes() if run != null else PackedInt32Array()
	if run == null or run.graph == null:
		queue_redraw()
		return
	var graph: CampaignGraph = run.graph
	for node_id: int in graph.node_count():
		var button: MapNodeButton = NODE_SCENE.instantiate()
		var type: CampaignGraph.NodeType = graph.type_of(node_id)
		var fill: Color = type_colors.get(type, Color.GRAY)
		var letter: String = type_letters.get(type, "?")
		var node_icon: Texture2D = type_icons.get(type, null)
		var type_name: String = TYPE_NAMES.get(type, "?")
		var tooltip: String = "%s · floor %d" % [type_name, graph.floor_of(node_id)]
		add_child(button)
		button.setup(node_id, type, tooltip, fill, letter, node_icon)
		button.set_mark(_mark_of(node_id))
		button.pressed.connect(_on_node_pressed.bind(node_id))
		button.mouse_entered.connect(_on_node_inspected.bind(node_id))
		button.focus_entered.connect(_on_node_inspected.bind(node_id))
		_buttons[node_id] = button
	_link_focus()
	_lay_out()


## The nodes the run can enter next, as shown: reachable and focusable, in column order.
func get_reachable() -> PackedInt32Array:
	return _reachable.duplicate()


## The button of node [param node_id]; null when the map has none.
func get_node_button(node_id: int) -> MapNodeButton:
	return _buttons.get(node_id, null)


## Gives focus to the first reachable node, the leftmost; returns whether one took it.
func focus_first_reachable() -> bool:
	if _reachable.is_empty():
		return false
	_buttons[_reachable[0]].grab_focus()
	return true


## The centre of node [param node_id] in the view's own coordinates.
func node_center(node_id: int) -> Vector2:
	var graph: CampaignGraph = _run.graph
	var area: Vector2 = size - padding * 2.0
	var cell: Vector2 = Vector2(
			area.x / maxf(graph.get_column_count(), 1.0),
			area.y / maxf(graph.get_floor_count(), 1.0)
	)
	return Vector2(
			padding.x + (graph.column_of(node_id) + 0.5) * cell.x,
			padding.y + area.y - (graph.floor_of(node_id) - 0.5) * cell.y
	)


func _mark_of(node_id: int) -> MapNodeButton.Mark:
	if _reachable.has(node_id):
		return MapNodeButton.Mark.REACHABLE
	if node_id == _run.node:
		return MapNodeButton.Mark.CURRENT
	if _run.visited.has(node_id):
		return MapNodeButton.Mark.VISITED
	return MapNodeButton.Mark.OTHER


# Reachable nodes link left and right in column order, stopping at the ends; up and down, and the
# ends, point back at the node itself so focus never leaves the choices.
func _link_focus() -> void:
	var ordered: Array[MapNodeButton] = []
	for node_id: int in _reachable:
		ordered.append(_buttons[node_id])
	ordered.sort_custom(func(a: MapNodeButton, b: MapNodeButton) -> bool:
		return _run.graph.column_of(a.node_id) < _run.graph.column_of(b.node_id)
	)
	_reachable.clear()
	for i: int in ordered.size():
		var button: MapNodeButton = ordered[i]
		_reachable.append(button.node_id)
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_left = button.get_path_to(ordered[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(ordered[mini(i + 1, ordered.size() - 1)])
		button.focus_neighbor_top = self_path
		button.focus_neighbor_bottom = self_path
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right


func _lay_out() -> void:
	if _run == null or _run.graph == null:
		return
	for node_id: int in _buttons:
		var button: MapNodeButton = _buttons[node_id]
		button.size = node_size
		button.position = node_center(node_id) - node_size * 0.5
	queue_redraw()


func _edge_colour(parent: int, child: int) -> Color:
	var parent_at: int = _run.visited.find(parent)
	var is_route: bool = (
			parent_at >= 0
			and parent_at + 1 < _run.visited.size()
			and _run.visited[parent_at + 1] == child
	)
	if is_route:
		return route_edge_color
	if parent == _run.node and _reachable.has(child):
		return next_edge_color
	return edge_color


func _on_node_pressed(node_id: int) -> void:
	node_chosen.emit(node_id)


func _on_node_inspected(node_id: int) -> void:
	node_inspected.emit(node_id)
