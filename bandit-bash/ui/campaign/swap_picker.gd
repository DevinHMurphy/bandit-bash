# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_picker.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SwapPicker
extends VBoxContainer
## Picks the two units of a swap proposal inside the [SwapPanel]: first one of the viewer's own,
## to go to the teammate's map, then one of the teammate's, to come to the viewer's
## ([signal picked]). Lists each seat's living army; a unit the rules can't swap
## ([method UnitSwap.unit_problem]: the commander, a unit already in an accepted swap) shows why
## and can't be pressed. Back returns a step, then cancels ([method back]). Only asks: the panel
## sends the proposal.

# ============================================================
# STATE MACHINE:
#   OWN     -> PARTNER : a unit of the viewer's pressed
#   PARTNER -> OWN     : back()
#   PARTNER -> (done)  : a unit of the teammate's pressed; picked is emitted
#   OWN     -> (done)  : back(); cancelled is emitted
# ============================================================

## The viewer chose [param own_unit] to send and [param partner_unit] to receive.
signal picked(own_unit: String, partner_unit: String)

## The viewer backed out before choosing both units.
signal cancelled()

## Which seat's unit is being chosen.
enum Step {
	## One of the viewer's own units.
	OWN = 0,
	## One of the teammate's units.
	PARTNER = 1,
}

## Each unit button's least size, applied as each step lists its units.[br]
## [b]Units:[/b] base units. [b](0, 0):[/b] as large as its text.
@export var button_size: Vector2 = Vector2(420.0, 36.0)

var _run: CampaignRunState = null
var _viewer: int = CampaignData.HOST_SEAT
var _partner: int = -1
var _catalog: EffectCatalog.Index = null
var _step: Step = Step.OWN
var _own_unit: String = ""

@onready var _prompt_label: Label = %Prompt
@onready var _units: VBoxContainer = %Units
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(back)


## Starts choosing a swap between [param viewer] and [param partner] on [param run], the viewer's
## unit first, focusing the first that can be pressed.
func start(
		run: CampaignRunState, viewer: int, partner: int, catalog: EffectCatalog.Index
) -> void:
	_run = run
	_viewer = viewer
	_partner = partner
	_catalog = catalog
	_own_unit = ""
	_show_step(Step.OWN)


## Back one step: from the teammate's units to the viewer's; from the viewer's, cancels.
func back() -> void:
	if _step == Step.PARTNER:
		_own_unit = ""
		_show_step(Step.OWN)
		return
	cancelled.emit()


## The step shown.
func get_step() -> Step:
	return _step


## The teammate the swap is with.
func get_partner() -> int:
	return _partner


## The prompt's text, for tests.
func get_prompt() -> String:
	return _prompt_label.text


## Each listed unit's button, in army order, for tests.
func get_unit_buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child: Node in _units.get_children():
		if child is Button and not child.is_queued_for_deletion():
			found.append(child as Button)
	return found


## The Back button, for tests.
func get_back_button() -> Button:
	return _back_button


func _show_step(step: Step) -> void:
	_step = step
	var seat: int = _viewer if step == Step.OWN else _partner
	var name: String = CampaignLink.seat_name(_partner)
	_prompt_label.text = (
			"Choose your unit to send to %s's map." % [name] if step == Step.OWN
			else "Choose %s's unit to come to your map." % [name]
	)
	for child: Node in _units.get_children():
		_units.remove_child(child)
		child.queue_free()
	var seat_run: SeatRun = _run.seat_run(seat)
	var listed: Array[UnitInstance] = []
	if seat_run != null:
		listed = seat_run.army
	var column: Array[Button] = []
	for unit: UnitInstance in listed:
		var button: Button = Button.new()
		var problem: String = UnitSwap.unit_problem(_run, seat, unit.instance_id)
		button.custom_minimum_size = button_size
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _unit_text(unit, seat_run, problem)
		button.disabled = not problem.is_empty()
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		button.pressed.connect(_on_unit_pressed.bind(unit.instance_id))
		_units.add_child(button)
		if not button.disabled:
			column.append(button)
	column.append(_back_button)
	_link_column(column)
	column[0].grab_focus()


# The unit's type and HP, and why it can't be swapped when it can't.
func _unit_text(unit: UnitInstance, seat_run: SeatRun, problem: String) -> String:
	var max_hp: int = unit.stats(_catalog).get_int(CombatValue.Key.HP)
	var hp: int = max_hp if unit.hp == UnitInstance.FULL_HP else unit.hp
	var text: String = "%s · HP %d/%d" % [RecruitOfferCard.title_of(unit, _catalog), hp, max_hp]
	if unit.instance_id == seat_run.commander_id:
		return text + " (commander)"
	if not problem.is_empty():
		return text + " (in a swap)"
	return text


# The pressable buttons and Back as one column: up and down, the ends stop; left and right stay.
func _link_column(column: Array[Button]) -> void:
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


func _on_unit_pressed(unit_id: String) -> void:
	if _step == Step.OWN:
		_own_unit = unit_id
		_show_step(Step.PARTNER)
		return
	picked.emit(_own_unit, unit_id)
