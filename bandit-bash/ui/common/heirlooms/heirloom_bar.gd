# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_bar.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name HeirloomBar
extends HBoxContainer
## The seat's heirlooms and curses in a row under the top header (ui-lift.md, Heirloom bar): one
## [HeirloomIcon] per held copy, heirlooms in gain order, a divider, then curses; a [GameTooltip]
## under the icon pointed at, its keywords' [KeywordTooltip]s beside it. Hidden while the seat
## holds none.
##
## Draws the [HeirloomViewModel]s it is handed ([method show_views]) and recounts nothing. Bound to
## a battle's session ([method bind]) it follows facts as they play: COUNTER_CHANGED moves its
## icon's count, EFFECT_ACTIVATED pulses it (the event log writes that line). Keys and pads reach
## it only while navigable: left and right move between icons, wrapping. In battle the
## [BattleController] decides when (HEIRLOOM_BAR); with [member handles_focus_input] on, as on
## campaign screens, the bar takes heirloom_bar_focus and Back itself.
##
## @tutorial(UI lift, Heirloom bar): docs/design/ui-lift.md

# ============================================================
# INPUT MAP SETUP (read only with handles_focus_input on; bindings in project.godot):
#   "heirloom_bar_focus" -> H; RS pushed left   (focuses the first icon, remembering the focus it
#                           [R stick]              took (navigation_started); again, closes the bar.
#                                                  The stick counts once per push, until let back)
#   "ui_cancel"          -> Esc; B [Circle],     (while an icon has focus: closes the bar and gives
#                           Menu [Options]         the focus back (navigation_ended), read in _input
#                                                  before the pause menu's _unhandled_input)
#   ui_left / ui_right   -> in the bar           (GUI focus between icons, wrapping; up and down
#                                                  stay on the icon: its own focus links)
#   (mouse over an icon)                         (its tooltip, at any time)
# ============================================================

## Keys and pads moved focus onto the bar ([method open_focus]).
signal navigation_started()

## Focus left the bar ([method close_focus]).
signal navigation_ended()

## The hint context a screen shows while the bar has focus.
const HINT_CONTEXT: StringName = &"HEIRLOOMS"

## The icon placed for each held copy: a [HeirloomIcon] scene.[br]
## [b]Unset:[/b] no icons show and an error is reported.
@export var icon_scene: PackedScene = null

## Whether the bar reads heirloom_bar_focus and Back itself, as on campaign screens.[br]
## [b]Off:[/b] its owner makes it navigable ([method set_navigable]), as the battle controller
## does.
@export var handles_focus_input: bool = false

# ASSUMPTION: the gap; ui-style.md places tooltips but sets no distance.
## The space between an icon's bottom edge and its tooltip.[br]
## [b]Units:[/b] base units. [b]0.0:[/b] the tooltip touches the icon.
@export_range(0.0, 32.0, 1.0) var tooltip_gap: float = 4.0

var _views: Array[HeirloomViewModel] = []
var _heirloom_icons: Array[HeirloomIcon] = []
var _curse_icons: Array[HeirloomIcon] = []
var _session: CombatSession = null
var _is_navigable: bool = false

# The icon the tooltip describes; null while it is hidden.
var _pointed: HeirloomIcon = null

# The icon last focused, which focus_icon() returns to; -1 for none.
var _focused_index: int = -1

# The control that had focus before open_focus(), given it back by close_focus().
var _return_focus: Control = null

# Whether the stick's push has opened or closed the bar and not yet been let back.
var _is_stick_latched: bool = false

@onready var _heirloom_box: HBoxContainer = %Heirlooms
@onready var _divider: VSeparator = %Divider
@onready var _curse_box: HBoxContainer = %Curses
@onready var _tooltip: GameTooltip = %Tooltip


func _ready() -> void:
	if icon_scene == null:
		push_error("HeirloomBar: no icon scene set")
	_tooltip.visible = false
	show_views(_views)


func _exit_tree() -> void:
	unbind()


func _input(event: InputEvent) -> void:
	if not handles_focus_input or not _is_navigable:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close_focus()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not handles_focus_input:
		return
	var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if motion != null:
		if not motion.is_action(&"heirloom_bar_focus"):
			return
		var is_pushed: bool = motion.is_action_pressed(&"heirloom_bar_focus")
		if is_pushed and not _is_stick_latched:
			_toggle_focus()
		_is_stick_latched = is_pushed
		return
	if event.is_action_pressed(&"heirloom_bar_focus"):
		_toggle_focus()
		get_viewport().set_input_as_handled()


## Shows [param views]: an icon per copy, heirlooms in their order, then the divider and the
## curses in theirs; the divider only when both show, the bar only when any does. Icons are reused
## in place, so a pulse under way and a focus held survive a redraw with the same copies.
func show_views(views: Array[HeirloomViewModel]) -> void:
	_views = views.duplicate()
	if not is_node_ready():
		return
	var heirlooms: Array[HeirloomViewModel] = []
	var curses: Array[HeirloomViewModel] = []
	for view: HeirloomViewModel in _views:
		if view.is_curse:
			curses.append(view)
		else:
			heirlooms.append(view)
	_fill(_heirloom_box, _heirloom_icons, heirlooms)
	_fill(_curse_box, _curse_icons, curses)
	_divider.visible = not heirlooms.is_empty() and not curses.is_empty()
	visible = not _views.is_empty()
	set_navigable(_is_navigable and not _views.is_empty())
	if is_instance_valid(_pointed) and _pointed.is_inside_tree():
		_show_tip(_pointed)
	else:
		_hide_tip()


## The copies shown, heirlooms and curses, in the order [method show_views] was handed them.
func get_views() -> Array[HeirloomViewModel]:
	return _views.duplicate()


## Every icon in the bar's order: heirlooms, then curses.
func get_icons() -> Array[HeirloomIcon]:
	var icons: Array[HeirloomIcon] = _heirloom_icons.duplicate()
	icons.append_array(_curse_icons)
	return icons


## Whether the bar shows any icon.
func has_icons() -> bool:
	return not _views.is_empty()


## Whether the divider between heirlooms and curses shows.
func is_divider_shown() -> bool:
	return _divider.visible


## The tooltip, for tests that read it.
func get_tip() -> GameTooltip:
	return _tooltip


## Follows [param session]'s facts as they play (class doc). Binding again replaces it.
func bind(session: CombatSession) -> void:
	unbind()
	if session == null:
		return
	_session = session
	_session.bus.effect.counter_changed.connect(_on_effect_counter_changed)
	_session.bus.effect.activated.connect(_on_effect_activated)


## Stops following facts. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	if _session.bus.effect.counter_changed.is_connected(_on_effect_counter_changed):
		_session.bus.effect.counter_changed.disconnect(_on_effect_counter_changed)
	if _session.bus.effect.activated.is_connected(_on_effect_activated):
		_session.bus.effect.activated.disconnect(_on_effect_activated)
	_session = null


## Lets keys and pads move between the icons, wrapping, or stops them, dropping a focus held
## inside. The mouse hovers either way.
func set_navigable(is_navigable: bool) -> void:
	_is_navigable = is_navigable
	for icon: HeirloomIcon in get_icons():
		icon.set_navigable(is_navigable)
	if is_navigable:
		_link_focus()


## Whether keys and pads can move through the bar.
func is_navigable() -> bool:
	return _is_navigable


## Focuses the icon at [param index] in [method get_icons]; -1 for the one last focused, else the
## first. Returns false, focusing nothing, while not navigable or empty.
func focus_icon(index: int = -1) -> bool:
	var icons: Array[HeirloomIcon] = get_icons()
	if not _is_navigable or icons.is_empty():
		return false
	var chosen: int = index if index >= 0 else _focused_index
	if chosen < 0 or chosen >= icons.size():
		chosen = 0
	icons[chosen].grab_focus()
	return true


## The index in [method get_icons] of the icon with focus; -1 for none.
func get_focused_index() -> int:
	var icons: Array[HeirloomIcon] = get_icons()
	for i: int in icons.size():
		if icons[i].has_focus():
			return i
	return -1


## Moves keys' and pads' focus onto the bar's last focused icon (the first at first), keeping the
## control that had it for [method close_focus]; emits [signal navigation_started]. Returns false,
## doing nothing, while hidden, empty or already navigable.
func open_focus() -> bool:
	if _is_navigable or not is_visible_in_tree() or _views.is_empty():
		return false
	_return_focus = get_viewport().gui_get_focus_owner()
	set_navigable(true)
	focus_icon()
	navigation_started.emit()
	return true


## Takes keys' and pads' focus off the bar and gives it back to the control that had it before
## [method open_focus]; emits [signal navigation_ended]. Returns false while not navigable.
func close_focus() -> bool:
	if not _is_navigable:
		return false
	set_navigable(false)
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	_return_focus = null
	navigation_ended.emit()
	return true


func _toggle_focus() -> void:
	if _is_navigable:
		close_focus()
	else:
		open_focus()


# Gives box exactly an icon per view, reusing icons in place, and draws them.
func _fill(box: HBoxContainer, icons: Array[HeirloomIcon], views: Array[HeirloomViewModel]) -> void:
	if icon_scene == null:
		views = []
	while icons.size() < views.size():
		var icon: HeirloomIcon = icon_scene.instantiate()
		icon.pointed.connect(_on_icon_pointed.bind(icon))
		icon.unpointed.connect(_on_icon_unpointed.bind(icon))
		box.add_child(icon)
		icons.append(icon)
	while icons.size() > views.size():
		var extra: HeirloomIcon = icons.pop_back()
		if extra == _pointed:
			_pointed = null
		box.remove_child(extra)
		extra.queue_free()
	for i: int in views.size():
		icons[i].show_view(views[i])
	box.visible = not views.is_empty()


# Wires each icon's focus to its neighbours in get_icons(): left and right, wrapping; up and down
# stay, so focus never leaves the bar.
func _link_focus() -> void:
	var icons: Array[HeirloomIcon] = get_icons()
	var count: int = icons.size()
	for i: int in count:
		var icon: HeirloomIcon = icons[i]
		var next: HeirloomIcon = icons[(i + 1) % count]
		var previous: HeirloomIcon = icons[(i + count - 1) % count]
		icon.focus_neighbor_left = icon.get_path_to(previous)
		icon.focus_neighbor_right = icon.get_path_to(next)
		icon.focus_neighbor_top = icon.get_path_to(icon)
		icon.focus_neighbor_bottom = icon.get_path_to(icon)
		icon.focus_next = icon.focus_neighbor_right
		icon.focus_previous = icon.focus_neighbor_left


# The tooltip for icon's copy (name, effect text, tier and state), under it, kept on screen.
func _show_tip(icon: HeirloomIcon) -> void:
	var view: HeirloomViewModel = icon.get_view()
	if view == null:
		_hide_tip()
		return
	_pointed = icon
	_tooltip.show_tip(view.display_name, "\n".join(view.marked_lines), view.footer_text())
	_tooltip.visible = true
	_place_tip()
	# The mouse can't reach the tooltip (pointing away hides it), so its keywords' tooltips show
	# with it, beside it, by hover and by focus alike.
	_tooltip.get_body().show_all_keywords()
	# The tooltip refits a frame later when its text wraps; place it, and its keywords, again then.
	_place_tip.call_deferred()


func _hide_tip() -> void:
	_pointed = null
	_tooltip.get_body().hide_tooltips()
	_tooltip.visible = false


func _place_tip() -> void:
	if not is_instance_valid(_pointed) or not _tooltip.visible:
		return
	var screen: Vector2 = get_viewport_rect().size
	var at: Vector2 = _pointed.global_position + Vector2(0.0, _pointed.size.y + tooltip_gap)
	at.x = clampf(at.x, 0.0, maxf(screen.x - _tooltip.size.x, 0.0))
	at.y = clampf(at.y, 0.0, maxf(screen.y - _tooltip.size.y, 0.0))
	_tooltip.global_position = at
	_tooltip.get_body().place_tooltips()


func _on_icon_pointed(icon: HeirloomIcon) -> void:
	if icon.has_focus():
		_focused_index = get_icons().find(icon)
	_show_tip(icon)


# The mouse or focus left icon: the tooltip follows whichever icon still has focus, else hides.
func _on_icon_unpointed(icon: HeirloomIcon) -> void:
	if _pointed != icon:
		return
	for other: HeirloomIcon in get_icons():
		if other.has_focus():
			_show_tip(other)
			return
	_hide_tip()


# A counter moved as its fact plays: the icon of the copy whose counter it is follows the fact's
# count, in its lane.
func _on_effect_counter_changed(fact: CombatFact) -> void:
	for icon: HeirloomIcon in get_icons():
		var view: HeirloomViewModel = icon.get_view()
		if view == null or view.counter_instance_id != fact.source_effect_id:
			continue
		if fact.key != view.lane:
			continue
		view.apply_count(fact.amount)
		icon.show_view(view)
		if icon == _pointed:
			_show_tip(icon)


func _on_effect_activated(fact: CombatFact) -> void:
	for icon: HeirloomIcon in get_icons():
		var view: HeirloomViewModel = icon.get_view()
		if view != null and view.instance_ids.has(fact.source_effect_id):
			icon.pulse()
