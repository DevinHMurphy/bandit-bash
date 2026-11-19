# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     control_hint_bar.gd
# Author:
# Created:  November 6, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name ControlHintBar
extends PanelContainer
## A screen's control hints: the keys of the actions live now, with what each does
## ("T End turn · R Danger zone · Q/E Target"), built from action names, not a per-screen enum.
##
## [b]Which actions:[/b] [method HintSource.get_live_actions] of [member controller], less any with
## no binding in the family in use (the save debug panel's on a pad); this bar adds none.
## Neighbours that share a label show as one hint, their keys joined ("Q/E").[br]
## [b]Keys:[/b] read from the [InputMap] at each draw, for [member device]'s family: the first key
## on keyboard and mouse, the first joypad event on a pad, as [member glyphs]' glyph or as text.[br]
## [b]When it draws:[/b] it polls [method HintSource.get_hint_context] once a frame, as the pause
## menu pauses the tree silently; at once on [signal HintSource.live_actions_changed] and
## [signal InputDeviceAdapter.family_changed]. It runs while paused, so PAUSED shows.[br]
## [b]Layout:[/b] one clipped line along a screen edge (the Position exports; by default the
## battle's strip beside the turn bar, clear of the map), styled by [code]battle_theme.tres[/code].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ============================================================
# INPUT MAP SETUP: none read. The bar takes no input (mouse_filter ignore) and only reads the
# bindings of the actions its controller lists, from the InputMap: on keyboard and mouse the first
# keyboard event of each, its physical key shown in the keyboard's own layout outside headless
# runs; on a pad the first joypad button or axis event of each.
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

## The key text of an action with no binding for the family in use.
const UNBOUND_KEY: String = "(unbound)"

## Whose live actions the bar shows: the battle's [BattleController], another screen's
## [ScreenHints].[br]
## [b]Unset:[/b] the bar stays hidden.
@export var controller: HintSource = null:
	set(value):
		_disconnect_controller()
		controller = value
		_connect_controller()

@export_group("Glyphs")

## Reports the device family in use, whose glyphs and labels the bar draws.[br]
## [b]Unset:[/b] the bar draws for keyboard and mouse.
@export var device: InputDeviceAdapter = null:
	set(value):
		_disconnect_device()
		device = value
		_connect_device()

## The glyph and label of each input per family
## ([code]assets/sprites/controls/control_glyphs.tres[/code]).[br]
## [b]Unset:[/b] keys show their names and pad inputs their table ids ([code]button:3[/code]).
@export var glyphs: ControlGlyphTable = null

# ASSUMPTION: no basis in Godot_FE (its ControlsUI drew its 256 px icons scaled by its layout);
# sized to sit inside the 40 px bar beside its 13 px text.
## How tall a glyph is drawn in the bar; its width follows its own proportions.[br]
## [b]Units:[/b] pixels at the base size.
@export_range(8, 64, 1) var glyph_height: int = 20

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
# Pick, Swap, Pick tile, Info, Scroll, Close, Runes, Discard, Log, Scroll log, Toggle.
## What each action does, by action name, or by [code]CONTEXT/action[/code] where a context
## ([method HintSource.get_hint_context]) gives it another meaning; the context's key wins.
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
	"unit_detail": "Info",
	"open_runes": "Runes",
	"event_log_focus": "Log",
	"event_log_scroll_up": "Scroll log",
	"event_log_scroll_down": "Scroll log",
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
	"RUNE/ui_up": "Choose",
	"RUNE/ui_down": "Choose",
	"TARGET/ui_up": "Choose",
	"TARGET/ui_down": "Choose",
	"PAIR_TARGET/ui_up": "Choose",
	"PAIR_TARGET/ui_down": "Choose",
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
	"WALK/ui_cancel": "Pause",
	"PAUSED/ui_up": "Choose",
	"PAUSED/ui_down": "Choose",
	"PAUSED/ui_cancel": "Resume",
	"DETAIL/ui_up": "Scroll",
	"DETAIL/ui_down": "Scroll",
	"DETAIL/ui_accept": "Close",
	"DETAIL/ui_cancel": "Close",
	"DETAIL/unit_detail": "Close",
	"RUNE_SLOTS/ui_left": "Choose",
	"RUNE_SLOTS/ui_right": "Choose",
	"RUNE_SLOTS/ui_up": "Discard",
	"RUNE_SLOTS/ui_down": "Discard",
	"RUNE_SLOTS/ui_accept": "Pick",
	"RUNE_SLOTS/ui_cancel": "Close",
	"RUNE_SLOTS/open_runes": "Close",
	"DISCARD_CONFIRM/ui_left": "Choose",
	"DISCARD_CONFIRM/ui_right": "Choose",
	"DISCARD_CONFIRM/ui_accept": "Confirm",
	"EVENT_LOG/ui_up": "Scroll",
	"EVENT_LOG/ui_down": "Scroll",
	"EVENT_LOG/ui_left": "Choose",
	"EVENT_LOG/ui_right": "Choose",
	"EVENT_LOG/ui_accept": "Toggle",
	"EVENT_LOG/ui_cancel": "Close",
	"EVENT_LOG/event_log_focus": "Close",
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


func _exit_tree() -> void:
	_disconnect_controller()
	_disconnect_device()


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
	if not is_node_ready():
		return
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


## Whether [param action] has a binding in the family in use, so the bar can show it.
func is_bound(action: StringName) -> bool:
	return key_text(action) != UNBOUND_KEY


## The hints as shown, without markup or glyphs ("T End turn  ·  R Danger zone").
func get_text() -> String:
	return _text.get_parsed_text()


## The hints' BBCode as drawn, glyphs as [code][img][/code] tags.
func get_markup() -> String:
	return _text.text


## The label, for tests that measure whether its line fits.
func get_text_label() -> RichTextLabel:
	return _text


## The device family the bar draws for: [member device]'s, else keyboard and mouse.
func get_family() -> InputDeviceAdapter.Family:
	if is_instance_valid(device):
		return device.get_family()
	return InputDeviceAdapter.Family.KEYBOARD_MOUSE


## What [param action] does in [param context]: [member labels]' [code]CONTEXT/action[/code]
## entry, else its action entry, else the action's name.
func label_for(context: StringName, action: StringName) -> String:
	var key: String = "%s/%s" % [context, action]
	if labels.has(key):
		return labels[key]
	var label: String = labels.get(String(action), String(action))
	return label


## The bar's markup for [param action]'s binding in the family in use ([method get_family]): its
## glyph from [member glyphs] as an image [member glyph_height] tall, else [method key_text]
## escaped for BBCode. The one place a binding becomes what the bar draws.
func key_markup(action: StringName) -> String:
	var glyph: Texture2D = glyph_of(action)
	if glyph != null:
		return "[img height=%d]%s[/img]" % [glyph_height, glyph.resource_path]
	return _escape(key_text(action))


## The glyph drawn for [param action] in the family in use; null where it shows as text.
func glyph_of(action: StringName) -> Texture2D:
	if glyphs == null:
		return null
	var id: String = _glyph_id(action)
	if id.is_empty():
		return null
	return glyphs.glyph_for(get_family(), id)


## [param action]'s binding as text in the family in use: on keyboard and mouse its
## [method key_name]; on a pad its first joypad event's label in [member glyphs], else that
## event's table id. [constant UNBOUND_KEY] when the family has no binding for it.
func key_text(action: StringName) -> String:
	var family: InputDeviceAdapter.Family = get_family()
	if family == InputDeviceAdapter.Family.KEYBOARD_MOUSE:
		return key_name(action)
	var event: InputEvent = pad_event(action)
	if event == null:
		return UNBOUND_KEY
	var id: String = ControlGlyphTable.input_id(event)
	return id if glyphs == null else glyphs.label_for(family, id)


# The table id of action's binding in the family in use: its first key, named as the keyboard
# labels it, or its first joypad event; empty with none.
func _glyph_id(action: StringName) -> String:
	if get_family() != InputDeviceAdapter.Family.KEYBOARD_MOUSE:
		var event: InputEvent = pad_event(action)
		return "" if event == null else ControlGlyphTable.input_id(event)
	var key: InputEventKey = _first_key(action)
	if key == null:
		return ""
	var code: Key = _display_code(key)
	return "" if code == KEY_NONE else "key:%s" % [OS.get_keycode_string(code)]


# Draws the hints for context: one per run of neighbouring live actions that share a label,
# leaving out the ones the family in use can't press.
func _draw_hints(context: StringName) -> void:
	_context = context
	_is_drawn = true
	_actions.clear()
	if is_instance_valid(controller):
		for action: StringName in controller.get_live_actions():
			if is_bound(action):
				_actions.append(action)
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


func _connect_controller() -> void:
	if is_instance_valid(controller) and not controller.live_actions_changed.is_connected(
			_on_controller_live_actions_changed
	):
		controller.live_actions_changed.connect(_on_controller_live_actions_changed)


func _disconnect_controller() -> void:
	if is_instance_valid(controller) and controller.live_actions_changed.is_connected(
			_on_controller_live_actions_changed
	):
		controller.live_actions_changed.disconnect(_on_controller_live_actions_changed)


func _connect_device() -> void:
	if is_instance_valid(device) and not device.family_changed.is_connected(
			_on_device_family_changed
	):
		device.family_changed.connect(_on_device_family_changed)


func _disconnect_device() -> void:
	if is_instance_valid(device) and device.family_changed.is_connected(_on_device_family_changed):
		device.family_changed.disconnect(_on_device_family_changed)


func _on_controller_live_actions_changed() -> void:
	refresh()


func _on_device_family_changed(_family: InputDeviceAdapter.Family) -> void:
	refresh()


## [param action]'s first joypad event, a button or an axis; null with none.
static func pad_event(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return event
	return null


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
		var code: Key = _display_code(key)
		if code == KEY_NONE:
			continue
		var name: String = OS.get_keycode_string((code | key.get_modifiers_mask()) as Key)
		var short: String = SHORT_KEY_NAMES.get(name, name)
		return short
	return UNBOUND_KEY


# The first keyboard event of action that names a key; null with none.
static func _first_key(action: StringName) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null and _display_code(key) != KEY_NONE:
			return key
	return null


# The key key shows as: its physical key as the layout labels it, else its keycode, else its
# key label; KEY_NONE when it names none.
static func _display_code(key: InputEventKey) -> Key:
	var code: Key = key.keycode
	if key.physical_keycode != KEY_NONE:
		code = _layout_label(key.physical_keycode)
	if code == KEY_NONE:
		code = key.key_label
	return code


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
