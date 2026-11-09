# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     intent_display.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name IntentDisplay
extends Node2D
## The enemies' intents on the board (combat UI plan, question 10; game-vision.md, Enemy
## intentions): an [IntentIcon] over each acting enemy, a numbered [IntentLine] from each to its
## target in the expected enemy-phase order, and the hovered enemy's target rule in the
## [IntentRuleTooltip].
##
## A child of the board ([BattleView]), so positions are the board's. [BattleController] calls
## [method show_intents] with an [IntentViewModel] (the session's intents, or a move preview's,
## drawn as previewed), [method set_hovered] as the cursor moves, and [method clear] when none
## apply. Icons and lines are [member icon_scene] and [member line_scene] instances, reused from
## draw to draw. Reading only: it draws what it is given.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Which lines show while an enemy is hovered or not.
enum LineMode {
	## Every enemy's line; hovering an enemy shows its line alone.
	ALL = 0,
	## Only the hovered enemy's line; none while no enemy is hovered.
	HOVERED = 1,
}

## The icon placed over each acting enemy: an [IntentIcon] scene.[br]
## [b]Unset:[/b] no icon shows and an error is reported once.
@export var icon_scene: PackedScene = null

## The line drawn from each enemy to its target: an [IntentLine] scene.[br]
## [b]Unset:[/b] no line shows and an error is reported once.
@export var line_scene: PackedScene = null

# ASSUMPTION: "for one when it is hovered" read as hovering narrowing the lines to that enemy's.
## Which lines show: all, narrowed to the hovered enemy's, or the hovered enemy's only.
@export var line_mode: LineMode = LineMode.ALL:
	set(value):
		line_mode = value
		if is_node_ready():
			_apply_hover()

var _model: IntentViewModel = null
var _icons: Array[IntentIcon] = []
var _lines: Array[IntentLine] = []
var _positions: Dictionary[String, Vector2] = {}
var _hovered_id: String = ""
var _has_reported: bool = false

@onready var _line_layer: Node2D = %Lines
@onready var _icon_layer: Node2D = %Icons
@onready var _tooltip: IntentRuleTooltip = %RuleTooltip


func _ready() -> void:
	clear()


## Draws [param model], with [param to_position] giving a tile's centre in the board's space
## (called as to_position(tile: Vector2i) -> Vector2, such as [method BattleView.tile_to_position]).
## The hovered enemy is kept.
func show_intents(model: IntentViewModel, to_position: Callable) -> void:
	_model = model
	_positions.clear()
	if icon_scene == null or line_scene == null:
		if not _has_reported:
			push_error("IntentDisplay: the icon and line scenes must be set")
			_has_reported = true
		_release_all()
		return
	var lined: Array[IntentViewModel.Entry] = model.lines()
	_grow(_icons, icon_scene, _icon_layer, model.entries.size())
	_grow(_lines, line_scene, _line_layer, lined.size())
	for i: int in _icons.size():
		if i >= model.entries.size():
			_icons[i].release()
			continue
		var entry: IntentViewModel.Entry = model.entries[i]
		var at: Vector2 = to_position.call(entry.enemy_tile)
		_positions[entry.enemy_id] = at
		_icons[i].show_entry(entry, at, model.is_preview)
	for i: int in _lines.size():
		if i >= lined.size():
			_lines[i].release()
			continue
		var entry: IntentViewModel.Entry = lined[i]
		var to: Vector2 = to_position.call(entry.target_tile)
		_lines[i].show_entry(entry, _positions[entry.enemy_id], to, model.is_preview)
	_apply_hover()


## Shows [param enemy_id]'s rule and, by [member line_mode], narrows the lines to its own; empty,
## or an enemy with no intent shown, hovers none.
func set_hovered(enemy_id: String) -> void:
	_hovered_id = enemy_id
	_apply_hover()


## Draws nothing.
func clear() -> void:
	_model = null
	_positions.clear()
	if is_node_ready():
		_release_all()


## The model drawn; null after [method clear].
func get_model() -> IntentViewModel:
	return _model


## The icon of [param enemy_id]; null when none shows.
func icon_of(enemy_id: String) -> IntentIcon:
	for icon: IntentIcon in _icons:
		if icon.visible and icon.enemy_id == enemy_id:
			return icon
	return null


## The lines showing, in order, for tests.
func shown_lines() -> Array[IntentLine]:
	var shown: Array[IntentLine] = []
	for line: IntentLine in _lines:
		if line.visible:
			shown.append(line)
	return shown


## The enemies with an icon showing, in order, for tests.
func shown_icons() -> PackedStringArray:
	var shown: PackedStringArray = []
	for icon: IntentIcon in _icons:
		if icon.visible:
			shown.append(icon.enemy_id)
	return shown


## The rule tooltip's text; empty while it is hidden.
func get_rule_text() -> String:
	return _tooltip.get_text()


func _apply_hover() -> void:
	if _model == null:
		_tooltip.hide_rule()
		return
	var hovered: IntentViewModel.Entry = _model.entry_of(_hovered_id)
	if hovered != null and not hovered.rule_text.is_empty():
		_tooltip.show_rule(hovered.enemy_id, hovered.rule_text, _positions[hovered.enemy_id])
	else:
		_tooltip.hide_rule()
	var lined: int = _model.lines().size()
	for i: int in mini(lined, _lines.size()):
		var line: IntentLine = _lines[i]
		if hovered != null:
			line.visible = line.enemy_id == hovered.enemy_id
		else:
			line.visible = line_mode == LineMode.ALL


func _release_all() -> void:
	for icon: IntentIcon in _icons:
		icon.release()
	for line: IntentLine in _lines:
		line.release()
	_tooltip.hide_rule()


# Adds instances of scene under layer until pool holds count.
func _grow(pool: Array, scene: PackedScene, layer: Node2D, count: int) -> void:
	while pool.size() < count:
		var added: Node2D = scene.instantiate()
		layer.add_child(added)
		pool.append(added)
