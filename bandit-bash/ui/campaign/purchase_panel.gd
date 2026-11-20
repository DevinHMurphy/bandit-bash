# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     purchase_panel.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name PurchasePanel
extends Control
## Buying one Armory entry, asked over the screen ([enum Step]): an item's unit, then the deal
## with a before/after [ItemComparison] (trade the replaced item in, or send it to the convoy); an
## heirloom's price alone. Every choice shows its gold; one [Armory] refuses is greyed out and says
## why, as [PlacementPanel] greys out gear a unit can't use.
##
## It emits [signal purchase_chosen] once the deal is settled; the screen sends the command, which
## checks it again, and a rejection shows here ([method show_problem]). Each step lists its choices
## as one column of buttons, so a pad moves up and down within it; the dimmed backdrop takes every
## click outside it.

# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input while shown: steps back
#                  one step, or closes from the first; taken first, so the pause menu doesn't
#                  open over the panel)
#   "ui_up" / "ui_down" / "ui_accept"                     (not read here: the GUI moves focus
#                  within the column and presses the focused choice, by key, d-pad, stick or A
#                  [Cross]); left and right stay put
#   Mouse: a click on a choice presses it; Back steps back as ui_cancel does.
# ============================================================

## The player settled the deal: onto [param unit_id] (empty for an heirloom), the replaced item
## traded in when [param is_traded_in].
signal purchase_chosen(unit_id: String, is_traded_in: bool)

## The player backed out of the first step: nothing is bought.
signal cancelled()

# --- Purchase step (meaningful only while the panel is shown, after open()) ----------------
# UNIT:      an item's living units (greyed out when one can't use it). Back closes (cancelled).
# DEAL:      the comparison and the deal: buy into an empty slot, or trade the replaced item in,
#            or send it to the convoy. Back returns to UNIT.
# HEIRLOOM:  an heirloom's price. Back closes (cancelled).
# DEAL and HEIRLOOM end by emitting purchase_chosen; the panel stays shown until the screen closes
# it, so a rejection can be shown on it. ui_cancel acts as Back in every step.
## Which question the panel asks.
enum Step {
	## Which unit an item goes onto.
	UNIT = 0,
	## Which deal, with the comparison.
	DEAL = 1,
	## An heirloom's price.
	HEIRLOOM = 2,
}

var _run: CampaignRunState = null
var _seat: int = 0
var _index: int = -1
var _catalog: EffectCatalog.Index = null
var _ids: InstanceIdAllocator = null
var _entry: ArmoryStock.Entry = null
var _definition: ItemDefinition = null
var _unit_id: String = ""
var _step: Step = Step.UNIT

@onready var _icon: RewardIcon = %Icon
@onready var _title_label: Label = %Title
@onready var _details_label: Label = %Details
@onready var _comparison: ItemComparison = %ItemComparison
@onready var _question_label: Label = %Question
@onready var _choices: VBoxContainer = %Choices
@onready var _problem_label: Label = %Problem


func _ready() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	step_back()


## Opens the panel for stock entry [param index] of [param run]'s Armory, bought by seat
## [param seat]; [param ids] names its units, [param catalog] is their content.
func open(
		run: CampaignRunState,
		seat: int,
		index: int,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator
) -> void:
	_run = run
	_seat = seat
	_index = index
	_catalog = catalog
	_ids = ids
	_entry = ArmoryStock.pending(run).entries[index]
	_definition = null if _entry.is_heirloom() else catalog.item(_entry.definition_id)
	_unit_id = ""
	_icon.texture = ArmoryModel.entry_icon(_entry, catalog)
	_title_label.text = "Buy %s" % [ArmoryModel.entry_name(_entry, catalog)]
	_details_label.text = ArmoryModel.entry_details(_entry, catalog)
	visible = true
	if _entry.is_heirloom():
		_show_heirloom()
	else:
		_show_units()


## Hides the panel.
func close() -> void:
	visible = false


## Shows [param problem] under the choices, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	_problem_label.text = problem


## The step shown.
func get_step() -> Step:
	return _step


## The comparison, shown at [constant Step.DEAL].
func get_comparison() -> ItemComparison:
	return _comparison


## The choices of the step shown, in order, Back last.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## Goes back one step, or closes the panel from the first ([signal cancelled]).
func step_back() -> void:
	if _step == Step.DEAL:
		_show_units()
		return
	close()
	cancelled.emit()


## Chooses the unit [param unit_id] at [constant Step.UNIT], as pressing its choice does.
func choose_unit(unit_id: String) -> void:
	_unit_id = unit_id
	_show_deal()


func _show_units() -> void:
	_step = Step.UNIT
	_comparison.visible = false
	_question_label.text = "Onto which unit?"
	_clear_choices()
	var seat_run: SeatRun = _run.seat_run(_seat)
	for unit: UnitInstance in seat_run.army:
		var problem: String = ItemPlacement.equip_problem(
				seat_run, unit.instance_id, _definition, _catalog
		)
		var held: ItemInstance = Armory.replaced_item(seat_run, unit.instance_id, _definition)
		var text: String = "Onto %s" % [_unit_name(unit.instance_id)]
		if not problem.is_empty():
			text += " (can't use it)"
		elif held == null:
			text += " (slot empty)"
		else:
			text += ", replacing %s" % [ArmoryModel.held_name(held, _catalog)]
		_add_choice(text, problem.is_empty(), choose_unit.bind(unit.instance_id))
	_finish_column()


func _show_deal() -> void:
	_step = Step.DEAL
	var seat_run: SeatRun = _run.seat_run(_seat)
	var held: ItemInstance = Armory.replaced_item(seat_run, _unit_id, _definition)
	_comparison.visible = true
	_comparison.show_comparison(
			ArmoryModel.held_name(held, _catalog),
			ArmoryModel.entry_name(_entry, _catalog),
			ArmoryModel.comparison_rows(held, _definition, _catalog)
	)
	_question_label.text = "Before and after, on %s:" % [_unit_name(_unit_id)]
	_clear_choices()
	var price: int = Armory.price(seat_run, _entry, _catalog)
	if held == null:
		_add_deal("Buy for %d gold" % [price], false)
	else:
		var held_name: String = ArmoryModel.held_name(held, _catalog)
		var value: int = Armory.trade_in_value(seat_run, _unit_id, _definition, _catalog)
		var traded: int = Armory.cost(seat_run, _entry, _unit_id, true, _catalog)
		_add_deal("Trade in %s: %d - %d = %s" % [held_name, price, value, _gold(traded)], true)
		_add_deal("Send %s to the convoy (%d / %d): %s" % [
			held_name, seat_run.convoy.size(), ItemPlacement.convoy_capacity(seat_run, _catalog),
			_gold(price),
		], false)
	_finish_column()


func _show_heirloom() -> void:
	_step = Step.HEIRLOOM
	_comparison.visible = false
	_question_label.text = "It joins your heirlooms."
	_clear_choices()
	_add_deal(
			"Buy for %s" % [_gold(Armory.price(_run.seat_run(_seat), _entry, _catalog))], false
	)
	_finish_column()


# A deal choice, greyed out with the rules' reason when Armory refuses it.
func _add_deal(text: String, is_traded_in: bool) -> void:
	var problem: String = Armory.purchase_problem(
			_run, _seat, _index, _unit_id, is_traded_in, _catalog
	)
	if not problem.is_empty():
		text += " - can't: %s" % [problem]
	_add_choice(text, problem.is_empty(), _on_deal_chosen.bind(is_traded_in))


func _clear_choices() -> void:
	_problem_label.text = ""
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()


func _add_choice(text: String, is_enabled: bool, chosen: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(chosen)
	_choices.add_child(button)


# Adds Back, links the enabled choices as one column that stops at its ends, and focuses the
# first.
func _finish_column() -> void:
	_add_choice("Back", true, step_back)
	var column: Array[Button] = []
	for button: Button in get_choice_buttons():
		if not button.disabled:
			column.append(button)
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom
	column[0].grab_focus()


func _unit_name(unit_id: String) -> String:
	return CombatResultsModel.unit_name(_ids, _run.seat_run(_seat), unit_id, _catalog)


# Gold as a deal shows it: "52 gold", or "+8 gold back" when the trade-in is worth more.
func _gold(amount: int) -> String:
	if amount < 0:
		return "%d gold back" % [-amount]
	return "%d gold" % [amount]


func _on_deal_chosen(is_traded_in: bool) -> void:
	purchase_chosen.emit(_unit_id, is_traded_in)
