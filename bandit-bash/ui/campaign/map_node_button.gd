# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     map_node_button.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MapNodeButton
extends Button
## One node of the campaign map: a square in its type's colour with its letter (or icon), marked
## by where it stands on the run's route ([enum Mark]).
##
## Only a [constant Mark.REACHABLE] node takes focus and presses; the others stay disabled, but
## still show their tooltip and report hovering, so any node can be inspected. Placed and wired by
## [CampaignMapView], which sets its colour, letter and mark; it reads no input action itself.

## Where the node stands on the run's route.
enum Mark {
	## Not on the route and not reachable: dimmed and inert.
	OTHER = 0,
	## One of the nodes the run can enter next: focusable and pressable.
	REACHABLE = 1,
	## On the route taken, before the current node.
	VISITED = 2,
	## The node the run last entered.
	CURRENT = 3,
}

# What focus on a node sounds (Godot_FE's campaign_map_room.gd).
const _FOCUS_CUE: StringName = &"campaign_map_room_hovered"

## How a node off the route and out of reach is tinted (Godot_FE drew its unfocused rooms at
## [code]#828282[/code]).[br]
## [b]White:[/b] no dimming.
@export var dimmed_modulate: Color = Color("828282")

## The outline of a reachable node, so the choices stand out. Defaults to the [code]accent[/code]
## token.
@export var reachable_color: Color = UiTokens.color(UiTokens.ACCENT)

## The outline of a node on the route taken, the current one included. Defaults to the
## [code]block[/code] token (the player's side).
@export var route_color: Color = UiTokens.color(UiTokens.BLOCK)

# A greybox outline width; Godot_FE marked reachable rooms with a highlight animation and visited
# rooms as selected, with no width to carry over.

## How thick the outline of a reachable or route node is.[br]
## [b]Units:[/b] pixels at the base size. [b]0:[/b] no outline, only the colour shows the mark.
@export_range(0, 8, 1) var outline_width: int = 3

## The node's [CampaignGraph] id.
var node_id: int = CampaignGraph.NO_NODE

## The node's type.
var node_type: CampaignGraph.NodeType = CampaignGraph.NodeType.STANDARD

var _mark: Mark = Mark.OTHER
var _fill: Color = Color.GRAY


# Focus on a node sounds Godot_FE's room-hover cue, not the menu cursor ([UiSoundHook]).
func _ready() -> void:
	set_meta(UiSoundHook.FOCUS_CUE_META, _FOCUS_CUE)


## Shows node [param id] of [param type]: its [param fill] colour, its [param node_icon] when
## set, else its [param letter], and [param tooltip] on hover.
func setup(
		id: int,
		type: CampaignGraph.NodeType,
		tooltip: String,
		fill: Color,
		letter: String,
		node_icon: Texture2D
) -> void:
	node_id = id
	node_type = type
	_fill = fill
	icon = node_icon
	text = "" if node_icon != null else letter
	tooltip_text = tooltip
	_apply_mark()


## Marks the node as [param mark]: how it is drawn, and whether it takes focus and presses.
func set_mark(mark: Mark) -> void:
	_mark = mark
	_apply_mark()


## How the node is marked.
func get_mark() -> Mark:
	return _mark


func _apply_mark() -> void:
	var is_reachable: bool = _mark == Mark.REACHABLE
	disabled = not is_reachable
	focus_mode = Control.FOCUS_ALL if is_reachable else Control.FOCUS_NONE
	modulate = dimmed_modulate if _mark == Mark.OTHER else Color.WHITE
	var outline: Color = Color.TRANSPARENT
	if is_reachable:
		outline = reachable_color
	elif _mark != Mark.OTHER:
		outline = route_color
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = _fill.lightened(0.2) if style_name == &"hover" else _fill
		box.border_color = outline
		box.set_border_width_all(outline_width if outline.a > 0.0 else 0)
		box.set_corner_radius_all(4)
		add_theme_stylebox_override(style_name, box)
