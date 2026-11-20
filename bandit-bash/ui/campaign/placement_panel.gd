# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     placement_panel.gd
# Author:
# Created:  November 14, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name PlacementPanel
extends Control
## Where a newly gained item goes, asked over the screen ([enum Step]): equip it on a living unit
## that can use it, send it to the convoy, or scrap it; then, as needed, what happens to the item
## it displaces, and which convoy item to scrap to make room (unit-roster.md's hand-over: gear a
## unit can't use is greyed out).
##
## It builds one [ItemPlacement] by [ItemPlacement]'s own rules and emits
## [signal placement_chosen]; the screen sends the command, which checks it again. Each step lists
## its choices as one column of buttons, so a pad moves up and down within it; the panel's dimmed
## backdrop takes every click outside it. Each choice shows the unit's item in that slot and the
## scrap gold, with the icon of any held item it names; there is no stat comparison.

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

## The player settled where the item goes.
signal placement_chosen(placement: ItemPlacement)

## The player backed out of the first step: nothing is taken.
signal cancelled()

# --- Placement step (meaningful only while the panel is shown, after open()) ---------------
# DESTINATION:  equip on a unit (greyed out when it can't use the item), the convoy, or scrap.
#               Back closes the panel (cancelled).
# DISPLACED:    only after equipping into a full slot: the item there goes to the convoy or is
#               scrapped. Back returns to DESTINATION.
# CONVOY_SCRAP: only when an item must enter a full convoy (the new one, or a displaced one kept):
#               one convoy item to scrap. Back returns to the step that led here.
# Any step ends by emitting placement_chosen once nothing more is needed; the panel stays shown
# until the screen closes it, so a rejection can be shown on it (show_problem). ui_cancel acts as
# Back in every step.
## Which question the panel asks.
enum Step {
	## Where the item goes.
	DESTINATION = 0,
	## What happens to the item the new one displaces.
	DISPLACED = 1,
	## Which convoy item is scrapped to make room.
	CONVOY_SCRAP = 2,
}

var _step: Step = Step.DESTINATION
var _seat_run: SeatRun = null
var _definition: ItemDefinition = null
var _catalog: EffectCatalog.Index = null
var _ids: InstanceIdAllocator = null
var _placement: ItemPlacement = null

@onready var _icon: RewardIcon = %Icon
@onready var _title_label: Label = %Title
@onready var _details_label: Label = %Details
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


## Opens the panel for the item of [param definition] (content id [param definition_id]) gained
## by [param seat_run]; [param ids] names its units, [param catalog] is their content.
func open(
		seat_run: SeatRun,
		definition: ItemDefinition,
		definition_id: String,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator
) -> void:
	_seat_run = seat_run
	_definition = definition
	_catalog = catalog
	_ids = ids
	_placement = null
	_icon.texture = null if definition == null else definition.icon
	_title_label.text = "Place %s" % [CombatResultsModel.item_name(definition, definition_id)]
	_details_label.text = CombatResultsModel.item_details(definition)
	visible = true
	_show_destination()


## Hides the panel.
func close() -> void:
	visible = false
	_placement = null


## Shows [param problem] under the choices, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	_problem_label.text = problem


## The step shown.
func get_step() -> Step:
	return _step


## The choices of the step shown, in order, Back last.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## Goes back one step, or closes the panel from the first ([signal cancelled]).
func step_back() -> void:
	match _step:
		Step.DESTINATION:
			close()
			cancelled.emit()
		Step.DISPLACED:
			_show_destination()
		Step.CONVOY_SCRAP:
			if _placement != null and _placement.destination == ItemPlacement.Destination.EQUIP:
				_show_displaced()
			else:
				_show_destination()


func _show_destination() -> void:
	_step = Step.DESTINATION
	_placement = null
	_question_label.text = "Where does it go?"
	_clear_choices()
	var slot: Loadout.Slot = ItemPlacement.slot_for(_definition)
	for unit: UnitInstance in _seat_run.army:
		var unit_name: String = CombatResultsModel.unit_name(
				_ids, _seat_run, unit.instance_id, _catalog
		)
		var problem: String = ItemPlacement.equip_problem(
				_seat_run, unit.instance_id, _definition, _catalog
		)
		var held: String = ItemPlacement.item_in(unit, slot)
		var text: String = "Equip on %s" % [unit_name]
		if not problem.is_empty():
			text += " (can't use it)"
		elif held.is_empty():
			text += " (%s slot empty)" % [(Loadout.Slot.find_key(slot) as String).to_lower()]
		else:
			text += ", replacing %s" % [_held_name(held)]
		_add_choice(text, problem.is_empty(), _on_equip_chosen.bind(unit.instance_id))
	_add_choice(
			"Send it to the convoy (%s)" % [_convoy_text()], true, _on_convoy_chosen
	)
	_add_choice(
			"Scrap it for %d gold" % [ItemPlacement.scrap_value(_definition, _seat_run, _catalog)],
			true,
			_on_scrap_chosen
	)
	_finish_column()


func _show_displaced() -> void:
	_step = Step.DISPLACED
	_placement.is_displaced_scrapped = false
	_placement.convoy_scrap_id = ""
	var unit: UnitInstance = _seat_run.unit(_placement.unit_id)
	var held: String = ItemPlacement.item_in(unit, ItemPlacement.slot_for(_definition))
	var held_name: String = _held_name(held)
	_question_label.text = "What happens to %s?" % [held_name]
	_clear_choices()
	var held_icon: Texture2D = _held_icon(held)
	_add_choice(
			"Send %s to the convoy (%s)" % [held_name, _convoy_text()], true,
			_on_displaced_chosen.bind(false), held_icon
	)
	_add_choice(
			"Scrap %s for %d gold" % [held_name, _scrap_gold(held)], true,
			_on_displaced_chosen.bind(true), held_icon
	)
	_finish_column()


func _show_convoy_scrap() -> void:
	_step = Step.CONVOY_SCRAP
	_placement.convoy_scrap_id = ""
	_question_label.text = "The convoy is full (%d / %d). Scrap one of its items to make room:" % [
		_seat_run.convoy.size(), ItemPlacement.convoy_capacity(_seat_run, _catalog),
	]
	_clear_choices()
	for item_id: String in _seat_run.convoy:
		_add_choice(
				"Scrap %s for %d gold" % [_held_name(item_id), _scrap_gold(item_id)], true,
				_on_convoy_scrap_chosen.bind(item_id), _held_icon(item_id)
		)
	_finish_column()


# Emits the placement once it needs nothing more, else asks for the convoy item to scrap.
func _settle() -> void:
	if (
			_placement.needs_convoy_room(_seat_run, _definition)
			and ItemPlacement.is_convoy_full(_seat_run, _catalog)
	):
		_show_convoy_scrap()
		return
	placement_chosen.emit(_placement)


func _clear_choices() -> void:
	_problem_label.text = ""
	for child: Node in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()


# A choice naming a held item shows that item's icon; null shows none.
func _add_choice(
		text: String, is_enabled: bool, chosen: Callable, item_icon: Texture2D = null
) -> void:
	var button: Button = Button.new()
	button.text = text
	button.icon = item_icon
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
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


func _convoy_text() -> String:
	var capacity: int = ItemPlacement.convoy_capacity(_seat_run, _catalog)
	var text: String = "%d / %d" % [_seat_run.convoy.size(), capacity]
	return text + ", full" if ItemPlacement.is_convoy_full(_seat_run, _catalog) else text


func _held_definition(item_id: String) -> ItemDefinition:
	var item: ItemInstance = _seat_run.items.get(item_id, null)
	return null if item == null else _catalog.item(item.definition_id)


func _held_icon(item_id: String) -> Texture2D:
	var definition: ItemDefinition = _held_definition(item_id)
	return null if definition == null else definition.icon


func _held_name(item_id: String) -> String:
	return CombatResultsModel.item_name(_held_definition(item_id), item_id)


# The gold scrapping the held item item_id pays at the seat's rate: its own value, so a modified
# item pays more.
func _scrap_gold(item_id: String) -> int:
	var item: ItemInstance = _seat_run.items.get(item_id, null)
	return ItemPlacement.held_scrap_value(item, _catalog, _seat_run)


func _on_equip_chosen(unit_id: String) -> void:
	_placement = ItemPlacement.new(ItemPlacement.Destination.EQUIP, unit_id)
	var unit: UnitInstance = _seat_run.unit(unit_id)
	if not ItemPlacement.item_in(unit, ItemPlacement.slot_for(_definition)).is_empty():
		_show_displaced()
		return
	_settle()


func _on_convoy_chosen() -> void:
	_placement = ItemPlacement.new(ItemPlacement.Destination.CONVOY)
	_settle()


func _on_scrap_chosen() -> void:
	_placement = ItemPlacement.new(ItemPlacement.Destination.SCRAP)
	_settle()


func _on_displaced_chosen(is_scrapped: bool) -> void:
	_placement.is_displaced_scrapped = is_scrapped
	_settle()


func _on_convoy_scrap_chosen(item_id: String) -> void:
	_placement.convoy_scrap_id = item_id
	placement_chosen.emit(_placement)
