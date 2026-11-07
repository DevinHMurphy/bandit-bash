# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     control_hint_bar.gd
# Author:
# Created:  November 6, 2026
# Modified: November 6, 2026
# ==============================================================================

class_name ControlHintBar
extends PanelContainer
## The battle screen's control hints: the keys of the actions live now, with what each does
## ("T End turn · R Danger zone · Q/E Target"), changing as turn input moves between stages
## (combat UI plan, question 24; Godot_FE FR-UI-1, rebuilt from action names, not a per-screen
## enum, as its own rebuild recipe asks).
##
## [b]Which actions:[/b] exactly [method BattleController.get_live_actions] of [member controller],
## whose [constant BattleController.LIVE_ACTIONS] is the one table of them; this bar adds none.
## Neighbours that share a label show as one hint, their keys joined ("Q/E").[br]
## [b]Keys:[/b] read from the [InputMap] each time the bar draws ([method key_markup]), so a
## rebinding shows at the next stage change or [method refresh]. Controller glyphs (UI9) replace
## [method key_markup] alone.[br]
## [b]When it draws:[/b] it compares [method BattleController.get_hint_context] once a frame and
## redraws only when it changes, as the pause menu says nothing when it pauses the tree and
## playback can start from a command sent elsewhere. It runs while paused, so PAUSED shows.[br]
## [b]Layout:[/b] a strip along one screen edge set by the Position exports, applied at run time;
## at its defaults it is the bottom strip under the HUD's left column and the map area, beside the
## turn bar, so at the 1152×648 base size and wider it never covers the map. Its text is one line,
## clipped, never wrapped, so it never grows over the map. Font, colours and panel are
## [code]battle_theme.tres[/code]'s [code]ControlHintBar[/code] and [code]ControlHintText[/code].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ============================================================
# INPUT MAP SETUP: none read. The bar takes no input (mouse_filter ignore) and only reads the
# bindings of the actions its controller lists, from the InputMap: the first keyboard event of
# each, its physical key shown in the keyboard's own layout outside headless runs.
# ============================================================

## The screen edge the bar runs along.
enum Edge {
	## Along the top of the screen.
	TOP = 0,
	## Along the bottom of the screen.
	BOTTOM = 1,
}

## Key names shortened for the bar, by [method OS.get_keycode_string]'s name. Only how a key is
## written: which key an action has always comes from the [InputMap].
const SHORT_KEY_NAMES: Dictionary[String, String] = {
	"Escape": "Esc",
	"Up": "↑",
	"Down": "↓",
	"Left": "←",
	"Right": "→",
}

## The key text of an action with no keyboard binding.
const UNBOUND_KEY: String = "(unbound)"

## The turn input whose live actions the bar shows.[br]
## [b]Unset:[/b] the bar stays hidden.
@export var controller: BattleController = null

@export_group("Position")

## The screen edge the bar runs along, at [member edge_margin] from it.
@export var edge: Edge = Edge.BOTTOM:
	set(value):
		edge = value
		_apply_position()

## The gap between the bar and [member edge].[br]
## [b]Units:[/b] pixels at the base size. [b]Default tuned for:[/b] the turn bar's 8 px.
@export_range(0.0, 200.0, 1.0) var edge_margin: float = 8.0:
	set(value):
		edge_margin = value
		_apply_position()

## The gap between the bar and the screen's left edge.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(0.0, 2000.0, 1.0) var left_margin: float = 8.0:
	set(value):
		left_margin = value
		_apply_position()

## The gap between the bar and the screen's right edge. Set with the turn bar's width in
## [code]gameplay.tscn[/code]: at 316 the turn bar fills the 300 px beside it, above which the
## panel stack's column runs.[br]
## [b]Units:[/b] pixels at the base size. [b]0:[/b] the bar runs to the right edge.
@export_range(0.0, 2000.0, 1.0) var right_margin: float = 316.0:
	set(value):
		right_margin = value
		_apply_position()

## The bar's height. With [member edge_margin] it must stay within the strip the HUD's map area
## leaves along that edge ([code]battle_hud.tscn[/code]'s 56 px at the bottom), or it covers the
## map.[br]
## [b]Units:[/b] pixels at the base size. [b]Default tuned for:[/b] the turn bar's 40 px.
@export_range(16.0, 200.0, 1.0) var height: float = 40.0:
	set(value):
		height = value
		_apply_position()

@export_group("Text")

## What stands between two hints.
@export var separator: String = "  ·  "

## What joins the keys of neighbouring actions that share a label ("Q/E").
@export var key_joiner: String = "/"

# ASSUMPTION: the labels beyond the plan's examples (Danger zone, End turn, Target, Weapon, Fast,
# Skip, Debug) have no basis: Move, Select, Back, Pause, Resume, Start, Units, Choose, Confirm,
# Pick, Swap, Pick tile.
## What each action does, by action name, or by [code]CONTEXT/action[/code] where a context
## ([method BattleController.get_hint_context]) gives it another meaning; the context's key wins.
## [b]Missing:[/b] the action's own name shows.
@export var labels: Dictionary[String, String] = {
	"ui_up": "Move",
	"ui_down": "Move",
	"ui_left": "Move",
	"ui_right": "Move",
	"ui_accept": "Select",
	"ui_cancel": "Back",
	"end_turn": "End turn",
	"toggle_danger_zone": "Danger zone",
	"cycle_weapon": "Weapon",
	"fast_forward": "Fast",
	"skip_playback": "Skip",
	"toggle_save_debug": "Debug",
	"target_prev": "Target",
	"target_next": "Target",
	"SWAP/ui_accept": "Pick",
	"SWAP/end_turn": "Start",
	"SWAP/ui_cancel": "Pause",
	"SWAP_PICKED/ui_accept": "Swap",
	"SWAP_PICKED/end_turn": "Start",
	"IDLE/target_prev": "Units",
	"IDLE/target_next": "Units",
	"IDLE/ui_cancel": "Pause",
	"MOVE/ui_accept": "Pick tile",
	"ACTION/ui_up": "Choose",
	"ACTION/ui_down": "Choose",
	"TARGET/ui_up": "Choose",
	"TARGET/ui_down": "Choose",
	"FORECAST/ui_up": "Choose",
	"FORECAST/ui_down": "Choose",
	"FORECAST/ui_left": "Choose",
	"FORECAST/ui_right": "Choose",
	"FORECAST/ui_accept": "Confirm",
	"CONFIRM/ui_left": "Choose",
	"CONFIRM/ui_right": "Choose",
	"CONFIRM/ui_accept": "Confirm",
	"END_CONFIRM/ui_left": "Choose",
	"END_CONFIRM/ui_right": "Choose",
	"END_CONFIRM/ui_accept": "Confirm",
	"PLAYBACK/ui_cancel": "Pause",
	"INACTIVE/ui_cancel": "Pause",
	"PAUSED/ui_up": "Choose",
	"PAUSED/ui_down": "Choose",
	"PAUSED/ui_cancel": "Resume",
}

@export_group("")

# The context and actions last drawn; _is_drawn is false until the first draw.
var _context: StringName = &""
var _actions: Array[StringName] = []
var _is_drawn: bool = false

@onready var _text: RichTextLabel = %Text


func _ready() -> void:
	_apply_position()
	visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(controller):
		if visible:
			visible = false
		return
	var context: StringName = controller.get_hint_context()
	if not _is_drawn or context != _context:
		_draw_hints(context)


## Redraws now, reading the keys again: after a rebinding, or in tests standing for a frame.
func refresh() -> void:
	var context: StringName = &""
	if is_instance_valid(controller):
		context = controller.get_hint_context()
	_draw_hints(context)


## The hint context last drawn; empty for none.
func get_context() -> StringName:
	return _context


## The actions last drawn, in order; empty while hidden.
func get_shown_actions() -> Array[StringName]:
	return _actions.duplicate()


## The hints as shown, without markup ("T End turn  ·  R Danger zone").
func get_text() -> String:
	return _text.get_parsed_text()


## The label, for tests that measure whether its line fits.
func get_text_label() -> RichTextLabel:
	return _text


## What [param action] does in [param context]: [member labels]' [code]CONTEXT/action[/code]
## entry, else its action entry, else the action's name.
func label_for(context: StringName, action: StringName) -> String:
	var key: String = "%s/%s" % [context, action]
	if labels.has(key):
		return labels[key]
	var label: String = labels.get(String(action), String(action))
	return label


# Draws the hints for context: one per run of neighbouring live actions that share a label.
func _draw_hints(context: StringName) -> void:
	_context = context
	_is_drawn = true
	_actions.clear()
	if is_instance_valid(controller):
		_actions = controller.get_live_actions()
	visible = not _actions.is_empty()
	var key_colour: String = get_theme_color(&"key_color", &"ControlHintBar").to_html()
	var hints: PackedStringArray = []
	var i: int = 0
	while i < _actions.size():
		var label: String = label_for(context, _actions[i])
		var keys: PackedStringArray = [key_markup(_actions[i])]
		i += 1
		while i < _actions.size() and label_for(context, _actions[i]) == label:
			keys.append(key_markup(_actions[i]))
			i += 1
		hints.append("[color=#%s]%s[/color] %s" % [
			key_colour, _escape(key_joiner).join(keys), _escape(label),
		])
	_text.text = _escape(separator).join(hints)


# Anchors the bar along edge from the Position exports. Run from _ready() and each setter once
# the node is ready, as a setter can run before it.
func _apply_position() -> void:
	if not is_node_ready():
		return
	var at_bottom: bool = edge == Edge.BOTTOM
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0 if at_bottom else 0.0
	anchor_bottom = anchor_top
	offset_left = left_margin
	offset_right = -right_margin
	offset_top = -edge_margin - height if at_bottom else edge_margin
	offset_bottom = -edge_margin if at_bottom else edge_margin + height


## The bar's markup for [param action]'s key: its [method key_name], escaped for BBCode. The one
## place a key becomes what the bar draws, so controller glyphs (UI9) replace only this.
static func key_markup(action: StringName) -> String:
	return _escape(key_name(action))


## [param action]'s key as text, read from the [InputMap]: its first keyboard event's key with its
## modifiers ("T", "F3", "Shift+T"), shortened by [constant SHORT_KEY_NAMES]; a physical key is
## named as the keyboard's layout labels it, except headless, which has no layout.
## [constant UNBOUND_KEY] when it has no keyboard event.
static func key_name(action: StringName) -> String:
	if not InputMap.has_action(action):
		return UNBOUND_KEY
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key == null:
			continue
		var code: Key = key.keycode
		if key.physical_keycode != KEY_NONE:
			code = _layout_label(key.physical_keycode)
		if code == KEY_NONE:
			code = key.key_label
		if code == KEY_NONE:
			continue
		var name: String = OS.get_keycode_string((code | key.get_modifiers_mask()) as Key)
		var short: String = SHORT_KEY_NAMES.get(name, name)
		return short
	return UNBOUND_KEY


# Escapes text for BBCode: only "[" opens a tag.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


# The key the keyboard's layout prints on physical; the physical key itself headless, where
# DisplayServer has no layout and reports an error for the query.
static func _layout_label(physical: Key) -> Key:
	if DisplayServer.get_name() == "headless":
		return physical
	var label: Key = DisplayServer.keyboard_get_label_from_physical(physical)
	return physical if label == KEY_NONE else label
