# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rule_tooltip_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The intent rule tooltip's placement for the ui/board suite ([IntentRuleTooltip]): in a
## [SubViewport] the size of each capture size (1280x720, 1920x1080, 1280x800), at a few camera
## zooms, an enemy's tile centre on the top row, the bottom row, the left and right edges, the
## corners and the middle. The tooltip always stays inside the visible rect; it sits above the
## centre where there is room, below it on the top row, and moves with the camera while shown.
## No autoload is named or needed.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

const TOOLTIP_SCENE: PackedScene = preload("res://ui/battle/intents/intent_rule_tooltip.tscn")

# The capture runner's sizes (tools/run_captures.sh).
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 800)]

# Camera zooms: the HUD's scale, a close one and a far one, as CameraRig.frame fits small and
# large maps.
const ZOOMS: Array[float] = [1.0, 2.0, 0.5]

# A rule as long as the longest the content has (a heal rule), so the tip is wide.
const RULE: String = "Heals the most wounded ally"

# How far inside the screen's edge an anchor sits: half a 32-pixel tile at zoom 1, as an edge
# tile's centre would.
const EDGE_INSET: float = 16.0

# How far past the visible rect a clamped edge may land from float rounding: half a pixel.
const TOLERANCE: float = 0.5

var _check: Callable
var _root: Node = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where the viewports are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root


## Runs every case.
func run() -> void:
	var outside: PackedStringArray = []
	var wrong_side: PackedStringArray = []
	for screen: Vector2i in SIZES:
		for zoom: float in ZOOMS:
			_place_all(screen, zoom, outside, wrong_side)
	_check.call("rule tooltip: inside the viewport for every anchor, size and zoom", (
			outside.is_empty()
	), "; ".join(outside.slice(0, 4)))
	_check.call("rule tooltip: above the enemy with room, below it on the top row", (
			wrong_side.is_empty()
	), "; ".join(wrong_side.slice(0, 4)))
	_test_camera_moves()


# Shows the tooltip at each anchor in a viewport of screen at zoom, noting each that leaves the
# visible rect, and each on the wrong side of its anchor.
func _place_all(
		screen: Vector2i,
		zoom: float,
		outside: PackedStringArray,
		wrong_side: PackedStringArray
) -> void:
	var port: SubViewport = _viewport(screen, zoom)
	var tooltip: IntentRuleTooltip = TOOLTIP_SCENE.instantiate()
	port.add_child(tooltip)
	var size: Vector2 = Vector2(screen)
	var inset: float = EDGE_INSET * zoom
	var anchors: Dictionary[String, Vector2] = {
		"top": Vector2(size.x * 0.5, inset),
		"bottom": Vector2(size.x * 0.5, size.y - inset),
		"left": Vector2(inset, size.y * 0.5),
		"right": Vector2(size.x - inset, size.y * 0.5),
		"top left": Vector2(inset, inset),
		"top right": Vector2(size.x - inset, inset),
		"bottom left": Vector2(inset, size.y - inset),
		"bottom right": Vector2(size.x - inset, size.y - inset),
		"middle": size * 0.5,
	}
	var bounds: Rect2 = port.get_visible_rect().grow(TOLERANCE)
	for anchor_name: String in anchors:
		var anchor: Vector2 = anchors[anchor_name]
		tooltip.show_rule("enemy", RULE, port.canvas_transform.affine_inverse() * anchor)
		var shown: Rect2 = _shown_rect(tooltip)
		var label: String = "%s at %dx%d, zoom %s: %s" % [
			anchor_name, screen.x, screen.y, zoom, shown,
		]
		if not shown.has_area() or not bounds.encloses(shown):
			outside.append(label)
		var is_top: bool = anchor_name.begins_with("top")
		var is_above: bool = shown.end.y <= anchor.y
		var is_below: bool = shown.position.y >= anchor.y
		if (is_top and not is_below) or (not is_top and not is_above):
			wrong_side.append(label)
	_root.remove_child(port)
	port.free()


# A top-row tooltip shown, then the camera moved so the enemy is mid-screen: the next frame
# places it above again, and moved back, below again; hidden, it no longer follows.
func _test_camera_moves() -> void:
	var screen: Vector2i = SIZES[0]
	var port: SubViewport = _viewport(screen, 1.0)
	var tooltip: IntentRuleTooltip = TOOLTIP_SCENE.instantiate()
	port.add_child(tooltip)
	var top: Vector2 = Vector2(screen.x * 0.5, EDGE_INSET)
	tooltip.show_rule("enemy", RULE, top)
	var below_first: bool = _shown_rect(tooltip).position.y >= top.y
	var lowered: Vector2 = Vector2(0.0, screen.y * 0.5)
	port.canvas_transform = Transform2D(0.0, Vector2.ONE, 0.0, lowered)
	tooltip._process(0.0)
	var above_then: bool = _shown_rect(tooltip).end.y <= (top + lowered).y
	port.canvas_transform = Transform2D()
	tooltip._process(0.0)
	var below_again: bool = _shown_rect(tooltip).position.y >= top.y
	tooltip.hide_rule()
	_check.call("rule tooltip: placed again when the camera moves while it shows", (
			below_first and above_then and below_again and not tooltip.is_processing()
	), "below %s, above once lowered %s, below again %s" % [below_first, above_then, below_again])
	_root.remove_child(port)
	port.free()


# A viewport of screen's size under the root whose canvas transform zooms by zoom about the
# top-left corner, as a Camera2D's would.
func _viewport(screen: Vector2i, zoom: float) -> SubViewport:
	var port: SubViewport = SubViewport.new()
	port.size = screen
	port.disable_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_root.add_child(port)
	port.canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, Vector2.ZERO)
	return port


# The tooltip's panel in its viewport's canvas space, where get_visible_rect() measures.
static func _shown_rect(tooltip: IntentRuleTooltip) -> Rect2:
	var tip: GameTooltip = tooltip.get_tip()
	var placed: Transform2D = tip.get_global_transform_with_canvas()
	return Rect2(placed.origin, tip.size * placed.get_scale())
