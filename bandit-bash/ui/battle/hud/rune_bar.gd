# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_bar.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name RuneBar
extends PanelContainer
## The seat's rune slots on the battle HUD, laid out like potion slots: one [RuneSlotButton] per
## slot ([constant SeatRun.RUNE_SLOT_COUNT]), the held runes in slot order and then empty circles,
## with the pointed rune's text, or why it can't be used, under them.
##
## A click on a rune or its Discard emits [signal rune_pressed] or [signal discard_pressed]. Keys
## and pads reach it only while [method set_navigable] is on: left and right move between runes,
## down and up between a rune and its Discard, accept presses. It holds no rules: the
## [BattleController] hands it the runes and the bar's refusal ([method show_runes]) and decides
## on every press.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## A held rune's circle was pressed. [param rune_id]: its instance id.
signal rune_pressed(rune_id: String)

## A held rune's Discard was pressed. [param rune_id]: its instance id.
signal discard_pressed(rune_id: String)

## The slot placed for each of the seat's rune slots: a [RuneSlotButton] scene.[br]
## [b]Unset:[/b] no slots are shown and an error is reported.
@export var slot_scene: PackedScene = null

## Each rune's icon, by its [RuneDefinition] id ([code]mend[/code]).[br]
## [b]Missing:[/b] the slot shows the rune's name instead.
@export var icons: Dictionary[String, Texture2D] = {}

## The text shown while Discard is pointed at: [code]%s[/code] the rune's name.
@export var discard_text_format: String = "Discard %s"

# ASSUMPTION: the wording; no design doc words it.
## The text shown while an empty slot is pointed at and the bar can be used.
@export var empty_text: String = "An empty rune slot."

var _slots: Array[RuneSlotButton] = []
var _runes: Array[TurnInputModel.HeldRune] = []
var _reason: String = ""
var _is_navigable: bool = false

# The slot and part last pointed at; -1 for none.
var _pointed: int = -1
var _is_discard_pointed: bool = false

# The bar's width as the scene lays it out, which it never shrinks below.
var _base_width: float = 0.0

@onready var _slot_box: HBoxContainer = %Slots
@onready var _text: Label = %RuneText


func _ready() -> void:
	_base_width = size.x
	if slot_scene == null:
		push_error("RuneBar: no slot scene set")
	else:
		_add_slots(SeatRun.RUNE_SLOT_COUNT)
	_show_text()


## Shows [param runes] in slot order, the rest of the slots empty; a seat holding more runes than
## [constant SeatRun.RUNE_SLOT_COUNT] gets a slot for each, so no held rune is hidden.
## [param reason]: why the bar can't be used now, which dims every rune and shows under the slots
## while one is pointed at; empty when it can, when only a rune's own
## [member TurnInputModel.HeldRune.reason] dims it.
func show_runes(runes: Array[TurnInputModel.HeldRune], reason: String) -> void:
	_runes = runes.duplicate()
	_reason = reason
	var count: int = maxi(SeatRun.RUNE_SLOT_COUNT, _runes.size())
	if slot_scene != null and count != _slots.size():
		_add_slots(count)
		while _slots.size() > count:
			var extra: RuneSlotButton = _slots.pop_back()
			_slot_box.remove_child(extra)
			extra.queue_free()
		_fit_width()
	for i: int in _slots.size():
		if i < _runes.size():
			var rune: TurnInputModel.HeldRune = _runes[i]
			var can_cast: bool = reason.is_empty() and rune.option != null
			var icon: Texture2D = icons.get(rune.definition_id, null)
			_slots[i].show_rune(rune, icon, can_cast)
		else:
			_slots[i].show_empty()
	set_navigable(_is_navigable)
	_show_text()


## The runes shown, in slot order.
func get_runes() -> Array[TurnInputModel.HeldRune]:
	return _runes.duplicate()


## Lets keys and pads move through the held runes and their Discards, wrapping, or stops them,
## dropping a focus held inside. Mouse clicks work either way.
func set_navigable(is_navigable: bool) -> void:
	_is_navigable = is_navigable
	for slot: RuneSlotButton in _slots:
		slot.set_navigable(is_navigable)
	if is_navigable:
		_link_focus()


## Whether keys and pads can move through the bar.
func is_navigable() -> bool:
	return _is_navigable


## Focuses the circle of [param rune_id]; with none given or not held, the first rune that can be
## cast, else the first held. Returns false, focusing nothing, while not navigable or empty.
func focus_rune(rune_id: String = "") -> bool:
	if not _is_navigable or _runes.is_empty():
		return false
	var index: int = -1
	for i: int in _runes.size():
		if _runes[i].rune_id == rune_id:
			index = i
	if index < 0:
		index = 0
		for i: int in _runes.size():
			if _runes[i].option != null:
				index = i
				break
	_slots[index].get_slot_button().grab_focus()
	return true


## The rune whose circle or Discard has focus; empty for none.
func get_focused_rune() -> String:
	for i: int in mini(_slots.size(), _runes.size()):
		var slot: RuneSlotButton = _slots[i]
		if slot.get_slot_button().has_focus() or slot.get_discard_button().has_focus():
			return _runes[i].rune_id
	return ""


## The slots, in order, for tests that press them.
func get_slots() -> Array[RuneSlotButton]:
	return _slots.duplicate()


## The text under the slots; empty while it is hidden.
func get_text() -> String:
	return _text.text if _text.visible else ""


# Widens the bar to fit its slots, or back to its width in the scene, keeping its right edge where
# the scene put it. Now, not a frame later, so no slot is placed past the screen's edge meanwhile;
# a size set on a Control grows it rightwards whatever its grow direction.
func _fit_width() -> void:
	var right_edge: float = position.x + size.x
	var width: float = maxf(_base_width, get_combined_minimum_size().x)
	size = Vector2(width, size.y)
	position = Vector2(right_edge - width, position.y)


# Places slot_scene instances until there are count slots.
func _add_slots(count: int) -> void:
	while _slots.size() < count:
		var i: int = _slots.size()
		var slot: RuneSlotButton = slot_scene.instantiate()
		slot.pressed.connect(_on_slot_pressed.bind(i))
		slot.discard_pressed.connect(_on_slot_discard_pressed.bind(i))
		slot.pointed.connect(_on_slot_pointed.bind(i))
		slot.unpointed.connect(_on_slot_unpointed.bind(i))
		_slot_box.add_child(slot)
		_slots.append(slot)


# Wires each held rune's focus to its neighbours: left and right to the next held rune (or
# Discard), wrapping; down from a rune to its Discard and up back; up from a rune and down from a
# Discard stay, so focus never leaves the bar.
func _link_focus() -> void:
	var count: int = mini(_runes.size(), _slots.size())
	for i: int in count:
		var slot: Button = _slots[i].get_slot_button()
		var discard: Button = _slots[i].get_discard_button()
		var next: RuneSlotButton = _slots[(i + 1) % count]
		var previous: RuneSlotButton = _slots[(i + count - 1) % count]
		slot.focus_neighbor_left = slot.get_path_to(previous.get_slot_button())
		slot.focus_neighbor_right = slot.get_path_to(next.get_slot_button())
		slot.focus_neighbor_top = slot.get_path_to(slot)
		slot.focus_neighbor_bottom = slot.get_path_to(discard)
		slot.focus_next = slot.focus_neighbor_right
		slot.focus_previous = slot.focus_neighbor_left
		discard.focus_neighbor_left = discard.get_path_to(previous.get_discard_button())
		discard.focus_neighbor_right = discard.get_path_to(next.get_discard_button())
		discard.focus_neighbor_top = discard.get_path_to(slot)
		discard.focus_neighbor_bottom = discard.get_path_to(discard)
		discard.focus_next = discard.focus_neighbor_right
		discard.focus_previous = discard.focus_neighbor_left


# The pointed slot's line: a rune's text and why it can't be used now, Discard's, or an empty
# slot's (the bar's refusal, else empty_text); nothing, hidden, while no slot is pointed at.
func _show_text() -> void:
	var line: String = ""
	if _pointed >= _runes.size():
		line = _reason if not _reason.is_empty() else empty_text
	elif _pointed >= 0:
		var rune: TurnInputModel.HeldRune = _runes[_pointed]
		if _is_discard_pointed:
			line = discard_text_format % [rune.label]
		else:
			line = "%s: %s" % [rune.label, rune.text]
		var why: String = _reason if not _reason.is_empty() else rune.reason
		if not why.is_empty() and (not _is_discard_pointed or not _reason.is_empty()):
			line += " (%s)" % [why.trim_suffix(".")]
	_text.text = line
	_text.visible = not line.is_empty()


func _on_slot_pressed(index: int) -> void:
	if index < _runes.size():
		rune_pressed.emit(_runes[index].rune_id)


func _on_slot_discard_pressed(index: int) -> void:
	if index < _runes.size():
		discard_pressed.emit(_runes[index].rune_id)


func _on_slot_pointed(is_discard: bool, index: int) -> void:
	_pointed = index
	_is_discard_pointed = is_discard
	_show_text()


# The mouse or focus left the slot: the line follows whatever part still has focus, else clears.
func _on_slot_unpointed(index: int) -> void:
	if _pointed != index:
		return
	_pointed = -1
	for i: int in _slots.size():
		if _slots[i].get_slot_button().has_focus():
			_pointed = i
			_is_discard_pointed = false
		elif _slots[i].get_discard_button().has_focus():
			_pointed = i
			_is_discard_pointed = true
	_show_text()
