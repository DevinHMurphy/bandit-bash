# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     swap_row.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name SwapRow
extends VBoxContainer
## One teammate in the [SwapPanel]: what the viewer and they have between them
## ([method SwapText.row_summary]) and the buttons that state allows. No swap: Propose. The
## viewer's open proposal, or an accepted swap: Withdraw. The teammate's proposal to the viewer:
## Accept and Decline. Only asks: the panel builds and sends the commands. Reads no input action
## itself; the panel links the buttons for keys and pads.

## The viewer pressed Propose for a swap with [param partner].
signal propose_pressed(partner: int)

## The viewer answered [param partner]'s proposal as shown: [param accepts] true accepts it;
## [param partner_unit] and [param own_unit] are the units the row showed, which the answer names.
signal answer_pressed(partner: int, accepts: bool, partner_unit: String, own_unit: String)

## The viewer pressed Withdraw on the proposal or swap with [param partner].
signal withdraw_pressed(partner: int)

## The summary's width, so long lines wrap inside the panel.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text (no wrapping room).
@export var summary_width: float = 640.0:
	set(value):
		summary_width = value
		if not is_node_ready():
			return
		_summary_label.custom_minimum_size.x = summary_width

## The teammate shown; -1 before [method show_swap].
var partner: int = -1

var _status: SwapText.PairStatus = SwapText.PairStatus.NONE
# The proposal's units as shown, the teammate's then the viewer's; empty with none to answer.
var _shown_units: PackedStringArray = []

@onready var _summary_label: Label = %Summary
@onready var _propose_button: Button = %ProposeButton
@onready var _accept_button: Button = %AcceptButton
@onready var _decline_button: Button = %DeclineButton
@onready var _withdraw_button: Button = %WithdrawButton


func _ready() -> void:
	_summary_label.custom_minimum_size.x = summary_width
	_propose_button.pressed.connect(_on_propose_button_pressed)
	_accept_button.pressed.connect(_on_answer.bind(true))
	_decline_button.pressed.connect(_on_answer.bind(false))
	_withdraw_button.pressed.connect(_on_withdraw_button_pressed)


## Shows what [param viewer] and [param teammate] have between them on [param run], its units
## named through [param catalog].
func show_swap(
		run: CampaignRunState, viewer: int, teammate: int, catalog: EffectCatalog.Index
) -> void:
	partner = teammate
	_status = SwapText.status_of(run, viewer, teammate)
	_shown_units = []
	if _status == SwapText.PairStatus.PROPOSED_TO_VIEWER:
		var proposal: UnitSwap = UnitSwap.between(run, viewer, teammate)
		_shown_units = [proposal.unit_a, proposal.unit_b]
	_summary_label.text = SwapText.row_summary(run, viewer, teammate, catalog)
	_propose_button.visible = _status == SwapText.PairStatus.NONE
	_accept_button.visible = _status == SwapText.PairStatus.PROPOSED_TO_VIEWER
	_decline_button.visible = _accept_button.visible
	_withdraw_button.visible = (
			_status == SwapText.PairStatus.PROPOSED_BY_VIEWER
			or _status == SwapText.PairStatus.ACCEPTED
	)


## What the row shows.
func get_status() -> SwapText.PairStatus:
	return _status


## The buttons shown, left to right, for the panel's focus and for tests.
func get_buttons() -> Array[Button]:
	var shown: Array[Button] = []
	for button: Button in [_propose_button, _accept_button, _decline_button, _withdraw_button]:
		if button.visible:
			shown.append(button)
	return shown


## The summary's text, for tests.
func get_summary() -> String:
	return _summary_label.text


## The Propose button, for tests.
func get_propose_button() -> Button:
	return _propose_button


## The Accept button, for tests.
func get_accept_button() -> Button:
	return _accept_button


## The Decline button, for tests.
func get_decline_button() -> Button:
	return _decline_button


## The Withdraw button, for tests.
func get_withdraw_button() -> Button:
	return _withdraw_button


func _on_propose_button_pressed() -> void:
	propose_pressed.emit(partner)


func _on_answer(accepts: bool) -> void:
	if _shown_units.size() != 2:
		return
	answer_pressed.emit(partner, accepts, _shown_units[0], _shown_units[1])


func _on_withdraw_button_pressed() -> void:
	withdraw_pressed.emit(partner)
