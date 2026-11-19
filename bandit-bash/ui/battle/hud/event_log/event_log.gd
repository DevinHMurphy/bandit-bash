# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_log.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name EventLog
extends VBoxContainer
## The battle's event log, a player's record of the combat (ui-lift.md, Event log): an
## [EventLogLine] or [EventLogHeader] per entry [EventLogWriter] writes from each fact as it plays
## ([signal CombatBus.fact_played]), so a line appears when the board shows it. Newest at the
## bottom; it follows new lines unless scrolled up, when "↓ N new" brings it back down. Keeps the
## newest [member max_lines]. Not saved: a resumed battle starts it with one note.[br]
## [b]Layout:[/b] the scene fills the HUD's right column above the turn bar, where the panel stack
## opens; the panel grows up from the column's foot. Collapsed, only its 40-unit header shows. It
## hides while a panel is open ([method set_covered]).[br]
## [b]Input[/b] is [BattleController]'s (its EVENT_LOG stage, the scroll actions): the mouse wheel,
## the header and the filters are the GUI's own.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## Whether the log can scroll, or whether it shows, may have changed; what the scroll actions can
## do follows it.
signal scroll_range_changed()

## The line scene ([EventLogLine]).[br]
## [b]Unset:[/b] no line shows and an error is reported at the first.
@export var line_scene: PackedScene = null

## The header scene ([EventLogHeader]), for turns, phases and the battle's end.[br]
## [b]Unset:[/b] no header shows and an error is reported at the first.
@export var header_scene: PackedScene = null

## How many entries are kept, headers included; older ones are dropped (as the debug fact log).
@export_range(10, 2000, 10) var max_lines: int = 200

## Whether the log is open when a battle binds it; its header toggles it.
@export var is_open_at_start: bool = true

## The header's title.
@export var title_text: String = "Event log"

## The header's word while open, which collapses it.
@export var hide_text: String = "Hide"

## The header's word while collapsed, which opens it.
@export var show_text: String = "Show"

## The header's count of lines added while collapsed: [code]%d[/code] the count.
@export var new_format: String = "%d new"

## The button back to the newest line while scrolled up: [code]%d[/code] the lines below.
@export var jump_format: String = "↓ %d new"

## What stands between the header's parts.
@export var separator: String = "  ·  "

var _session: CombatSession = null
var _writer: EventLogWriter = null

# Each entry's node and group by entry id, and the ids oldest first.
var _nodes: Dictionary[int, Control] = {}
var _groups: Dictionary[int, EventLogWriter.Group] = {}
var _order: Array[int] = []

var _is_open: bool = true
var _is_covered: bool = false
var _is_navigable: bool = false

# Whether the view sits at the newest line and follows new ones. Only the player's own scrolling
# changes it (_is_player_scroll): the layout moving the bar as lines grow never does.
var _is_following: bool = true

# Whether the bar's next value change is the player's (the wheel, the bar, the scroll methods);
# cleared each frame.
var _is_player_scroll: bool = false

# Lines added unseen: while collapsed, or scrolled up.
var _unseen: int = 0

# can_scroll() when scroll_range_changed last went out.
var _could_scroll: bool = false

@onready var _frame: PanelContainer = %Frame
@onready var _toggle: Button = %Toggle
@onready var _filters: EventLogFilterRow = %FilterRow
@onready var _scroll: ScrollContainer = %Scroll
@onready var _lines: VBoxContainer = %Lines
@onready var _jump: Button = %JumpButton


func _ready() -> void:
	_toggle.pressed.connect(_on_toggle_pressed)
	_jump.pressed.connect(_on_jump_button_pressed)
	_filters.filters_changed.connect(_on_filter_row_filters_changed)
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	bar.changed.connect(_on_scroll_bar_changed)
	bar.value_changed.connect(_on_scroll_bar_value_changed)
	bar.gui_input.connect(_on_player_scroll_input)
	_scroll.gui_input.connect(_on_player_scroll_input)
	visibility_changed.connect(_on_visibility_changed)
	_is_open = is_open_at_start
	_apply_open()


func _exit_tree() -> void:
	unbind()


# While navigable, focus stays inside, as the panel stack keeps it in its top panel.
func _process(_delta: float) -> void:
	_is_player_scroll = false
	if not _is_navigable or not is_visible_in_tree():
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not is_ancestor_of(focused):
		_toggle.grab_focus()


## Writes [param session]'s facts from now on, starting empty and open with every filter on.
## Binding again replaces it.
func bind(session: CombatSession) -> void:
	unbind()
	clear()
	_filters.reset()
	if session == null:
		return
	_session = session
	_writer = EventLogWriter.new(session)
	_session.bus.fact_played.connect(_on_bus_fact_played)
	set_open(is_open_at_start)
	scroll_to_end()


## Stops writing. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	if _session.bus.fact_played.is_connected(_on_bus_fact_played):
		_session.bus.fact_played.disconnect(_on_bus_fact_played)
	_session = null
	_writer = null


## Adds the "Battle resumed" note ([constant EventLogWriter.RESUMED_TEXT]). [BattleScreen] calls
## it once, right after binding a battle it didn't just begin.
func add_resumed_line() -> void:
	if _writer != null:
		add_entry(_writer.resumed_entry())


## Shows [param entry]: a new one at the bottom, dropping the oldest past [member max_lines]; one
## already shown (the same [member EventLogWriter.Entry.id]) in its place.
func add_entry(entry: EventLogWriter.Entry) -> void:
	if entry == null:
		return
	if _nodes.has(entry.id):
		_draw_entry(_nodes[entry.id], entry)
		return
	var is_header: bool = entry.tone in [
		EventLogWriter.Tone.HEADER, EventLogWriter.Tone.DARKNESS_HEADER,
	]
	var scene: PackedScene = header_scene if is_header else line_scene
	if scene == null:
		push_error("EventLog: no %s scene set" % ["header" if is_header else "line"])
		return
	var node: Control = scene.instantiate()
	_lines.add_child(node)
	_draw_entry(node, entry)
	_nodes[entry.id] = node
	_groups[entry.id] = entry.group
	_order.append(entry.id)
	node.visible = _filters.is_group_shown(entry.group)
	while _order.size() > max_lines:
		_drop(_order[0])
	if node.visible and (not _is_open or not _is_following):
		_unseen += 1
	_refresh_header()


## Drops every entry.
func clear() -> void:
	for id: int in _order.duplicate():
		_drop(id)
	_unseen = 0
	_refresh_header()


## Every entry's text, oldest first, filtered or not.
func get_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for id: int in _order:
		texts.append(_text_of(_nodes[id]))
	return texts


## The text of every entry the filters show, oldest first.
func get_shown_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for id: int in _order:
		if _nodes[id].visible:
			texts.append(_text_of(_nodes[id]))
	return texts


## Each entry's node, oldest first: [EventLogLine]s and [EventLogHeader]s.
func get_entry_nodes() -> Array[Control]:
	var nodes: Array[Control] = []
	for id: int in _order:
		nodes.append(_nodes[id])
	return nodes


## The filter row.
func get_filter_row() -> EventLogFilterRow:
	return _filters


## Opens the log or collapses it to its header.
func set_open(is_open: bool) -> void:
	if not is_node_ready():
		is_open_at_start = is_open
		return
	_is_open = is_open
	_apply_open()


## Whether the log is open, not collapsed to its header.
func is_open() -> bool:
	return _is_open


## Hides the log while [param is_covered] (a panel is open in the column), shows it again after.
func set_covered(is_covered: bool) -> void:
	if is_covered == _is_covered:
		return
	_is_covered = is_covered
	_frame.visible = not is_covered
	_notify_scroll_range()


## Whether a panel covers it ([method set_covered]).
func is_covered() -> bool:
	return _is_covered


## Whether its lines can be seen: shown in the tree, open and not covered.
func is_shown() -> bool:
	return is_visible_in_tree() and _is_open and not _is_covered


## Whether it holds more than it shows, so the scroll actions move it.
func can_scroll() -> bool:
	if not is_shown():
		return false
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 0.5


## Scrolls [param steps] lines down (up when negative). Scrolled to the bottom, it follows again.
func scroll_lines(steps: int) -> void:
	_scroll_by(steps * _line_height())


## Scrolls [param steps] pages down (up when negative): its height less one line, so a line stays
## in view across the step.
func scroll_pages(steps: int) -> void:
	var page: int = maxi(int(_scroll.get_v_scroll_bar().page) - _line_height(), _line_height())
	_scroll_by(steps * page)


## Scrolls to the newest line and follows new ones again.
func scroll_to_end() -> void:
	_is_following = true
	_unseen = 0
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = int(bar.max_value)
	_refresh_header()


## Whether it follows new lines (it sits at the bottom).
func is_following() -> bool:
	return _is_following


## How far it is scrolled down.[br]
## [b]Units:[/b] pixels at the base size.
func get_scroll() -> int:
	return _scroll.scroll_vertical


## Lets its header and filters take focus while [param is_navigable], focusing the header;
## left and right move between them, wrapping. Off, they give focus up.
func set_navigable(is_navigable: bool) -> void:
	if is_navigable == _is_navigable:
		return
	_is_navigable = is_navigable
	_toggle.focus_mode = Control.FOCUS_ALL if is_navigable else Control.FOCUS_NONE
	_filters.set_navigable(is_navigable and _is_open)
	_link_focus()
	if is_navigable:
		_toggle.grab_focus()
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


## Whether its controls take focus ([method set_navigable]).
func is_navigable() -> bool:
	return _is_navigable


## The controls focus moves between: the header, then the filters while open.
func get_focusables() -> Array[Button]:
	var buttons: Array[Button] = [_toggle]
	if _is_open:
		buttons.append_array(_filters.get_buttons())
	return buttons


## The header button.
func get_toggle() -> Button:
	return _toggle


# The player's scroll by pixels: following stops unless it ends at the bottom.
func _scroll_by(pixels: int) -> void:
	_is_player_scroll = true
	_scroll.scroll_vertical += pixels
	_is_player_scroll = false


# One line of the log's font, the step the arrows scroll by.
func _line_height() -> int:
	var font: Font = get_theme_font(&"normal_font", &"EventLogText")
	var size: int = get_theme_font_size(&"normal_font_size", &"EventLogText")
	return maxi(roundi(font.get_height(size)), 1) if font != null else size


func _draw_entry(node: Control, entry: EventLogWriter.Entry) -> void:
	var line: EventLogLine = node as EventLogLine
	if line != null:
		line.show_entry(entry)
		return
	var header: EventLogHeader = node as EventLogHeader
	if header != null:
		header.show_entry(entry)


func _drop(id: int) -> void:
	var node: Control = _nodes.get(id, null)
	_nodes.erase(id)
	_groups.erase(id)
	_order.erase(id)
	if is_instance_valid(node):
		_lines.remove_child(node)
		node.queue_free()


static func _text_of(node: Control) -> String:
	var line: EventLogLine = node as EventLogLine
	if line != null:
		return line.get_text()
	var header: EventLogHeader = node as EventLogHeader
	return header.get_text() if header != null else ""


func _apply_open() -> void:
	_filters.visible = _is_open
	_scroll.visible = _is_open
	_frame.size_flags_vertical = (
			Control.SIZE_EXPAND_FILL if _is_open else Control.SIZE_SHRINK_END
	)
	_filters.set_navigable(_is_navigable and _is_open)
	_link_focus()
	if _is_open and _is_following:
		_unseen = 0
	_refresh_header()
	_notify_scroll_range()


# The header's text and the jump button: "Event log · Hide" open, "Event log · 3 new · Show"
# collapsed; "↓ 3 new" while scrolled up with lines below.
func _refresh_header() -> void:
	if not is_node_ready():
		return
	var parts: PackedStringArray = [title_text]
	if not _is_open and _unseen > 0:
		parts.append(new_format % [_unseen])
	parts.append(hide_text if _is_open else show_text)
	_toggle.text = separator.join(parts)
	_jump.visible = _is_open and not _is_following and _unseen > 0
	if _jump.visible:
		_jump.text = jump_format % [_unseen]


# Left and right walk the header and the filters, wrapping; up and down stay put (the arrows
# scroll the log instead, BattleController's EVENT_LOG stage).
func _link_focus() -> void:
	var buttons: Array[Button] = get_focusables()
	for i: int in buttons.size():
		var button: Button = buttons[i]
		var own: NodePath = button.get_path_to(button)
		button.focus_neighbor_left = button.get_path_to(buttons[i - 1])
		button.focus_neighbor_right = button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_neighbor_top = own
		button.focus_neighbor_bottom = own
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right


func _notify_scroll_range() -> void:
	var can: bool = can_scroll()
	if can != _could_scroll:
		_could_scroll = can
		scroll_range_changed.emit()


func _on_bus_fact_played(fact: CombatFact) -> void:
	if _writer == null:
		return
	for entry: EventLogWriter.Entry in _writer.write(fact):
		add_entry(entry)


func _on_toggle_pressed() -> void:
	set_open(not _is_open)


func _on_jump_button_pressed() -> void:
	scroll_to_end()


func _on_filter_row_filters_changed() -> void:
	for id: int in _order:
		_nodes[id].visible = _filters.is_group_shown(_groups[id])


# The content grew or shrank: a following log keeps to the bottom.
func _on_scroll_bar_changed() -> void:
	if _is_following:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	_notify_scroll_range()


# Reaching the bottom always follows again; only the player's scroll stops following.
func _on_scroll_bar_value_changed(value: float) -> void:
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	var is_at_bottom: bool = value >= bar.max_value - bar.page - 1.0
	if is_at_bottom:
		_is_following = true
	elif _is_player_scroll:
		_is_following = false
	elif _is_following:
		_scroll.scroll_vertical = int(bar.max_value)
	if _is_following:
		_unseen = 0
	_refresh_header()


# The wheel, a pan or the bar under the mouse: the value change it makes is the player's. The
# signal comes before the control handles the event, so the flag is set in time.
func _on_player_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventPanGesture:
		_is_player_scroll = true
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		_is_player_scroll = true


func _on_visibility_changed() -> void:
	_notify_scroll_range()
