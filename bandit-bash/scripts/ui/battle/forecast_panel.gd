# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_panel.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

class_name ForecastPanel
extends BattlePanel
## The forecast before an attack, a staff or a shove is sent: one [ForecastRow] per row of a
## [ForecastViewModel], the notes under them, the per-stage [ForecastBreakdown] on a toggle, and
## Confirm, Back and, when the target can be hit with more than one weapon, Next weapon (combat UI
## plan, question 7).
##
## Opened by [BattleController] through [PanelHost] with the model; Confirm emits
## [signal BattlePanel.confirmed] with it, Back emits [signal BattlePanel.cancelled]. Next weapon,
## and the cycle_weapon key the controller reads, ask for the next weapon
## ([signal weapon_cycle_requested]); the controller builds that weapon's model and calls
## [method show_forecast]. The panel holds no rules. Rows are [member row_scene] instances, reused
## when the forecast changes; everything else is authored in the scene.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The player asked for the next weapon that can make this attack.
signal weapon_cycle_requested()

## The row placed for each forecast row: a [ForecastRow] scene.[br]
## [b]Unset:[/b] no rows are shown and an error is reported.
@export var row_scene: PackedScene = null

## Next weapon's text; [code]%d[/code] and [code]%d[/code] are the weapon shown and how many there
## are, such as "Next weapon (C) 1/2".
@export var cycle_text: String = "Next weapon (C) %d/%d"

## Whether the breakdown is open when the panel opens.
@export var is_breakdown_open: bool = false

var _model: ForecastViewModel = null
var _rows: Array[ForecastRow] = []

@onready var _title: Label = %Title
@onready var _actor_heading: Label = %ActorHeading
@onready var _target_heading: Label = %TargetHeading
@onready var _row_box: VBoxContainer = %Rows
@onready var _notes: Label = %Notes
@onready var _breakdown: ForecastBreakdown = %Breakdown
@onready var _breakdown_button: Button = %BreakdownButton
@onready var _cycle_button: Button = %CycleButton
@onready var _confirm_button: Button = %ConfirmButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)
	_cycle_button.pressed.connect(_on_cycle_button_pressed)
	_breakdown_button.toggled.connect(_on_breakdown_button_toggled)
	_breakdown_button.set_pressed_no_signal(is_breakdown_open)
	_breakdown.visible = is_breakdown_open


## [param payload]: the [ForecastViewModel] to show.
func open_with(payload: Variant) -> void:
	show_forecast(payload as ForecastViewModel)


func focus_first() -> void:
	_confirm_button.grab_focus()


## Shows [param model], replacing what was shown: after a weapon cycle, the new weapon's forecast.
func show_forecast(model: ForecastViewModel) -> void:
	_model = model
	if model == null:
		return
	_title.text = model.title
	_actor_heading.text = model.actor_label
	_target_heading.text = model.target_label
	_show_rows(model.rows)
	_notes.text = "\n".join(model.notes)
	_notes.visible = not model.notes.is_empty()
	_breakdown.show_breakdowns(model)
	_breakdown_button.visible = model.kind == ForecastViewModel.Kind.EXCHANGE
	_cycle_button.visible = model.can_cycle()
	_cycle_button.text = cycle_text % [model.weapon_index + 1, model.weapon_count]
	_confirm_button.disabled = model.forecast == null or not model.forecast.is_legal


## Opens or closes the per-stage breakdown.
func set_breakdown_open(is_open: bool) -> void:
	_breakdown_button.button_pressed = is_open


## The model shown; null before [method show_forecast].
func get_model() -> ForecastViewModel:
	return _model


## Whether the breakdown is showing.
func is_breakdown_showing() -> bool:
	return _breakdown.visible


## The rows shown, in order, for tests.
func get_rows() -> Array[ForecastRow]:
	var shown: Array[ForecastRow] = []
	for row: ForecastRow in _rows:
		if row.visible:
			shown.append(row)
	return shown


## The breakdown widget, for tests.
func get_breakdown() -> ForecastBreakdown:
	return _breakdown


## The Confirm button, for tests that press it.
func get_confirm_button() -> Button:
	return _confirm_button


## The Next weapon button, for tests that press it.
func get_cycle_button() -> Button:
	return _cycle_button


# One reused ForecastRow per row; extras are hidden.
func _show_rows(rows: Array[ForecastViewModel.Row]) -> void:
	if row_scene == null:
		push_error("ForecastPanel: no row scene set")
		return
	while _rows.size() < rows.size():
		var added: ForecastRow = row_scene.instantiate()
		_row_box.add_child(added)
		_rows.append(added)
	for i: int in _rows.size():
		var is_used: bool = i < rows.size()
		_rows[i].visible = is_used
		if is_used:
			_rows[i].show_row(rows[i])


func _on_confirm_button_pressed() -> void:
	confirmed.emit(_model)


func _on_back_button_pressed() -> void:
	cancelled.emit()


func _on_cycle_button_pressed() -> void:
	weapon_cycle_requested.emit()


func _on_breakdown_button_toggled(is_open: bool) -> void:
	_breakdown.visible = is_open
