# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ui_sound_hook.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UiSoundHook
extends RefCounted
## The interface sounds for every screen, with no sound code in any scene: focus, press, back and
## refused, heard through the scene tree instead of per button.
##
## [method attach] connects the root viewport's [signal Viewport.gui_focus_changed] and, through
## [signal SceneTree.node_added], each [BaseButton] and [Slider] as it enters the tree:[br]
## - [b]Focus[/b] ([constant FOCUS_CUE], or the control's [constant FOCUS_CUE_META]) when focus
## moves from one live control to another, not a screen's first focus or a click's.[br]
## - [b]Press[/b] ([constant PRESS_CUE]) on a button's [signal BaseButton.pressed]; [b]back[/b]
## ([constant BACK_CUE]) instead for a button in [constant BACK_GROUP] ([NavButton]'s Go Back).[br]
## - [b]Refused[/b] ([constant REFUSED_CUE]) on a click or accept on a disabled button.[br]
## - A focused slider's step sounds the focus cue, as Godot_FE's Options did.[br]
## A control in [constant OFF_GROUP], or under a node in it, makes no sound.
##
## @tutorial(Audio scope): docs/design/audio.md

## Focus moved, and a slider stepped.
const FOCUS_CUE: StringName = &"menu_cursor"
## A button pressed.
const PRESS_CUE: StringName = &"menu_confirm"
## A Back button pressed.
const BACK_CUE: StringName = &"menu_back"
# ASSUMPTION: the ui_refused cue plays menu_back.ogg until AU2; Godot_FE had no refused sound.
## A disabled button clicked or accepted.
const REFUSED_CUE: StringName = &"ui_refused"

## Put a control, or a node above controls, in this group to silence them.
const OFF_GROUP: StringName = &"ui_sound_off"
## Put a button in this group for its press to sound [constant BACK_CUE].
const BACK_GROUP: StringName = &"ui_sound_back"
## Metadata naming the cue a control's focus sounds instead of [constant FOCUS_CUE], a
## [StringName], such as the campaign map's nodes ([MapNodeButton]).
const FOCUS_CUE_META: StringName = &"ui_focus_cue"

var _play: Callable = Callable()
var _tree: SceneTree = null
var _last_focus: Control = null
# Marks a node this hook already connected, so one that leaves and re-enters the tree connects
# once. Per hook, so a second hook (a test's) connects beside the service's.
var _hooked_meta: StringName = &""


## A hook that calls [param play] with a cue id (a [StringName]).
func _init(play: Callable) -> void:
	_play = play
	# A RefCounted's id is negative, and a metadata name takes no "-".
	_hooked_meta = StringName("_ui_sound_hooked_%d" % [absi(get_instance_id())])


## Starts sounding [param tree]'s interface: its root viewport's focus and every button and
## slider in it now or later. Attach once; a second call does nothing.
func attach(tree: SceneTree) -> void:
	if _tree != null or tree == null:
		return
	_tree = tree
	_tree.node_added.connect(_on_tree_node_added)
	_tree.root.gui_focus_changed.connect(_on_root_gui_focus_changed)
	_hook_below(_tree.root)


## Stops sounding the tree attached; [method attach] may follow again.
func detach() -> void:
	if _tree == null:
		return
	if _tree.node_added.is_connected(_on_tree_node_added):
		_tree.node_added.disconnect(_on_tree_node_added)
	if _tree.root.gui_focus_changed.is_connected(_on_root_gui_focus_changed):
		_tree.root.gui_focus_changed.disconnect(_on_root_gui_focus_changed)
	_tree = null
	_last_focus = null


## Whether [param node] is silenced: it, or a node above it, is in [constant OFF_GROUP].
static func is_silenced(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current.is_in_group(OFF_GROUP):
			return true
		current = current.get_parent()
	return false


func _hook_below(node: Node) -> void:
	_hook(node)
	for child: Node in node.get_children():
		_hook_below(child)


func _hook(node: Node) -> void:
	if not (node is BaseButton or node is Slider) or node.has_meta(_hooked_meta):
		return
	node.set_meta(_hooked_meta, true)
	var button: BaseButton = node as BaseButton
	if button != null:
		button.pressed.connect(_on_button_pressed.bind(button))
		button.gui_input.connect(_on_button_gui_input.bind(button))
		return
	var slider: Slider = node as Slider
	if slider != null:
		slider.value_changed.connect(_on_slider_value_changed.bind(slider))


# Detached, the buttons already connected stay connected but sound nothing.
func _sound(cue_id: StringName, node: Node) -> void:
	if _tree == null or is_silenced(node) or not _play.is_valid():
		return
	_play.call(cue_id)


func _on_tree_node_added(node: Node) -> void:
	_hook(node)


func _on_root_gui_focus_changed(control: Control) -> void:
	var previous: Control = _last_focus
	_last_focus = control
	if not is_instance_valid(previous) or not previous.is_inside_tree() or previous == control:
		return
	# A click focuses what it presses; the press sounds, so its focus doesn't.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var cue_id: StringName = FOCUS_CUE
	if control.has_meta(FOCUS_CUE_META):
		cue_id = control.get_meta(FOCUS_CUE_META)
	_sound(cue_id, control)


func _on_button_pressed(button: BaseButton) -> void:
	_sound(BACK_CUE if button.is_in_group(BACK_GROUP) else PRESS_CUE, button)


func _on_button_gui_input(event: InputEvent, button: BaseButton) -> void:
	if not button.disabled:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	var is_click: bool = (
			click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	)
	if is_click or event.is_action_pressed(&"ui_accept"):
		_sound(REFUSED_CUE, button)


func _on_slider_value_changed(_value: float, slider: Slider) -> void:
	if slider.has_focus():
		_sound(FOCUS_CUE, slider)
