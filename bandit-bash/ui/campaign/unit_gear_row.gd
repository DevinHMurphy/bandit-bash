# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_gear_row.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitGearRow
extends HBoxContainer
## One unit in the [ArmyView]: its name and HP (or that it fell), then its Weapon, Equipment and
## Pouch as three buttons naming what each holds.
##
## Pressing a slot (click, or accept while focused) reports [signal slot_pressed]; the view decides
## what it means. A row shown only to view ([method show_unit] with is_interactive false) has its
## slots disabled and out of the focus order. It reads no input action itself.

## A slot of the row's unit was pressed.
signal slot_pressed(unit_id: String, slot: Loadout.Slot)

## The slot names, as the row shows them.
const SLOT_NAMES: Dictionary[Loadout.Slot, String] = {
	Loadout.Slot.WEAPON: "Weapon",
	Loadout.Slot.EQUIPMENT: "Equipment",
	Loadout.Slot.POUCH: "Pouch",
}

## Each slot button's least width, so an item's name fits at 1280×720.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export var slot_width: float = 190.0

## The name column's least width, so rows line up.[br]
## [b]Units:[/b] base units. [b]0:[/b] as wide as its text.
@export var name_width: float = 210.0

## Instance id of the unit shown; empty before [method show_unit].
var unit_id: String = ""

@onready var _name_label: Label = %NameLabel
@onready var _buttons: Dictionary[Loadout.Slot, Button] = {
	Loadout.Slot.WEAPON: %WeaponSlot,
	Loadout.Slot.EQUIPMENT: %EquipmentSlot,
	Loadout.Slot.POUCH: %PouchSlot,
}


func _ready() -> void:
	_name_label.custom_minimum_size.x = name_width
	for slot: Loadout.Slot in _buttons:
		_buttons[slot].custom_minimum_size.x = slot_width
		_buttons[slot].pressed.connect(_on_slot_pressed.bind(slot))


## Shows [param unit] of [param seat_run] ([param catalog] their content), fallen when
## [param is_fallen]; its slots press only when [param is_interactive].
func show_unit(
		unit: UnitInstance,
		seat_run: SeatRun,
		catalog: EffectCatalog.Index,
		is_fallen: bool,
		is_interactive: bool
) -> void:
	unit_id = unit.instance_id
	var title: String = RecruitOfferCard.title_of(unit, catalog)
	if is_fallen:
		_name_label.text = "%s (fallen)" % [title]
	else:
		var max_hp: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
		var hp: int = max_hp if unit.hp == UnitInstance.FULL_HP else unit.hp
		_name_label.text = "%s · HP %d/%d" % [title, hp, max_hp]
	for slot: Loadout.Slot in _buttons:
		var item_id: String = ItemPlacement.item_in(unit, slot)
		var item: ItemInstance = seat_run.items.get(item_id, null)
		var held: String = "—"
		if item != null:
			held = CombatResultsModel.item_name(catalog.item(item.definition_id), item_id)
		var button: Button = _buttons[slot]
		button.text = "%s: %s" % [SLOT_NAMES[slot], held]
		button.disabled = not is_interactive
		button.focus_mode = Control.FOCUS_ALL if is_interactive else Control.FOCUS_NONE


## The button of [param slot], for the view and tests.
func get_slot_button(slot: Loadout.Slot) -> Button:
	return _buttons[slot]


func _on_slot_pressed(slot: Loadout.Slot) -> void:
	slot_pressed.emit(unit_id, slot)
