# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     army_view.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name ArmyView
extends Control
## The army and its convoy, over the screen that opened it: a [UnitGearRow] per unit and the
## [ConvoyPanel]. Gear changes only where it is gained and when re-gearing at a Camp; elsewhere
## the army can only be viewed and items scrapped (game-vision.md, Inventory), so it has two modes
## ([enum Mode]).
##
## Re-gearing is pick up, then put down: press a filled slot (or a convoy item) to pick its item
## up, then a living unit's slot or "Put it in the convoy" to move it there ([RegearCommand]); a
## move [Regear] refuses says why and sends nothing. Scrapping is one press ([ScrapItemCommand]).
## It only asks: [signal command_ready] goes to the screen, which sends the command and calls
## [method refresh], or [method show_problem] with the rejection.

# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input while shown: drops the
#                  item being moved, else closes; taken first, so the pause menu doesn't open)
#   "ui_left" / "ui_right" / "ui_up" / "ui_down" / "ui_accept"  (not read here: the GUI moves
#                  focus between the slots, convoy items and Scrap buttons by their layout, and
#                  presses the focused one)
#   Mouse: clicks on the slots, convoy items, Scrap buttons and Close.
# ============================================================

## The player chose a change; the screen sends it.
signal command_ready(command: CampaignCommand)

## The view closed.
signal closed()

## What the view allows.
enum Mode {
	## View the army and scrap convoy items: anywhere on the campaign map.
	VIEW,
	## Also move items between units and the convoy: at a Camp only.
	REGEAR,
}

const ROW_SCENE: PackedScene = preload("res://ui/campaign/unit_gear_row.tscn")

## How dark the backdrop over the screen is.[br]
## [b]0.0:[/b] no dimming; [b]1.0:[/b] the screen hidden. 0.6 matches the [PlacementPanel]'s.
@export_range(0.0, 1.0, 0.05) var backdrop_alpha: float = 0.6

var _mode: Mode = Mode.VIEW
var _session: CampaignSession = null
var _seat: int = 0
# The item picked up to move; empty while none is.
var _carrying: String = ""

@onready var _backdrop: ColorRect = %Backdrop
@onready var _title_label: Label = %Title
@onready var _note_label: Label = %Note
@onready var _rows: VBoxContainer = %Rows
@onready var _convoy: ConvoyPanel = %ConvoyPanel
@onready var _status_label: Label = %Status
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, backdrop_alpha)
	_convoy.item_pressed.connect(_on_convoy_item_pressed)
	_convoy.scrap_pressed.connect(_on_convoy_scrap_pressed)
	_convoy.to_convoy_pressed.connect(_on_convoy_to_convoy_pressed)
	_close_button.pressed.connect(close)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not _carrying.is_empty():
		_carrying = ""
		refresh()
		return
	close()


## Opens over the screen for seat [param seat] of [param session]'s run, in [param mode].
func open(session: CampaignSession, seat: int, mode: Mode) -> void:
	_session = session
	_seat = seat
	_mode = mode
	_carrying = ""
	_status_label.text = ""
	_title_label.text = "Re-gear the army" if mode == Mode.REGEAR else "Army"
	_note_label.text = (
			"Pick an item up, then choose where it goes. Scrap convoy items for gold."
			if mode == Mode.REGEAR
			else "Gear changes at a Camp. Convoy items can be scrapped here for gold."
	)
	visible = true
	refresh()


## Shows the run as saved again, dropping any item being moved, and focuses the first choice.
func refresh() -> void:
	if _session == null or _session.run == null:
		return
	_carrying = ""
	_status_label.text = ""
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var can_move: bool = _mode == Mode.REGEAR
	var shown: Array[UnitInstance] = seat_run.army.duplicate()
	if can_move:
		shown.append_array(seat_run.fallen)
	for unit: UnitInstance in shown:
		var row: UnitGearRow = ROW_SCENE.instantiate()
		_rows.add_child(row)
		row.show_unit(unit, seat_run, catalog, seat_run.fallen.has(unit), can_move)
		row.slot_pressed.connect(_on_row_slot_pressed)
	_convoy.show_convoy(seat_run, catalog, can_move, not _carrying.is_empty())
	_focus_first()


## Hides the view and reports [signal closed].
func close() -> void:
	if not visible:
		return
	visible = false
	_carrying = ""
	closed.emit()


## Shows [param problem] on the status line, such as a rejection's reason.
func show_problem(problem: String) -> void:
	_status_label.text = problem


## The mode it opened in.
func get_mode() -> Mode:
	return _mode


## The item being moved; empty when none is.
func get_carrying() -> String:
	return _carrying


## Each unit's row, living then (re-gearing) fallen, for tests.
func get_rows() -> Array[UnitGearRow]:
	var found: Array[UnitGearRow] = []
	for child: Node in _rows.get_children():
		if child is UnitGearRow and not child.is_queued_for_deletion():
			found.append(child as UnitGearRow)
	return found


## The convoy panel, for tests.
func get_convoy_panel() -> ConvoyPanel:
	return _convoy


## The Close button, for tests.
func get_close_button() -> Button:
	return _close_button


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


# The first slot when re-gearing, else the first Scrap button, else Close.
func _focus_first() -> void:
	var rows: Array[UnitGearRow] = get_rows()
	if _mode == Mode.REGEAR and not rows.is_empty():
		rows[0].get_slot_button(Loadout.Slot.WEAPON).grab_focus()
		return
	var scraps: Array[Button] = _convoy.get_scrap_buttons()
	(scraps[0] if not scraps.is_empty() else _close_button).grab_focus()


func _pick_up(item_id: String) -> void:
	_carrying = item_id
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var item: ItemInstance = seat_run.items[item_id]
	_convoy.show_convoy(seat_run, EffectCatalog.index(), true, true)
	_status_label.text = "Moving %s: choose a unit's slot or the convoy (Back to cancel)." % [
		CombatResultsModel.item_name(EffectCatalog.index().item(item.definition_id), item_id),
	]


# Sends moving the carried item to unit_id's slot (empty: the convoy), or says why not.
func _put_down(unit_id: String, slot: Loadout.Slot) -> void:
	var problem: String = Regear.move_problem(
			_session.run, _seat, _carrying, unit_id, slot, EffectCatalog.index()
	)
	if not problem.is_empty():
		_status_label.text = "Can't move it there: %s." % [problem]
		return
	command_ready.emit(RegearCommand.new(_seat, _carrying, unit_id, slot))


func _on_row_slot_pressed(unit_id: String, slot: Loadout.Slot) -> void:
	if _mode != Mode.REGEAR:
		return
	var seat_run: SeatRun = _session.run.seat_run(_seat)
	var unit: UnitInstance = seat_run.unit(unit_id)
	var held: String = ItemPlacement.item_in(unit, slot)
	if _carrying.is_empty():
		if held.is_empty():
			_status_label.text = "That slot is empty: pick up an item to move first."
			return
		_pick_up(held)
		return
	if held == _carrying:
		_carrying = ""
		refresh()
		return
	_put_down(unit_id, slot)


func _on_convoy_item_pressed(item_id: String) -> void:
	if _mode != Mode.REGEAR:
		return
	if _carrying == item_id:
		_carrying = ""
		refresh()
		return
	_pick_up(item_id)


func _on_convoy_to_convoy_pressed() -> void:
	if not _carrying.is_empty():
		_put_down("", Loadout.Slot.WEAPON)


func _on_convoy_scrap_pressed(item_id: String) -> void:
	command_ready.emit(ScrapItemCommand.new(_seat, item_id))
