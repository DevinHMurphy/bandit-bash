# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_detail_panel.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name UnitDetailPanel
extends BattlePanel
## One unit's detail, player or enemy (combat UI plan, UI11; Godot_FE's combat unit detail
## screen, minus XP and growths): name and type, HP, Stance and its maximum, Block, the base stats
## and combat values, the weapon and its profile, the stowed weapon, Equipment and Pouch, traits
## and heirlooms as effect text, movement type and tags.
##
## Opened on [PanelHost] by [BattleController] with a [UnitDetailViewModel] as its payload; it
## formats the view and holds no rules. Its Close button has focus, so accept (Enter, Space, A
## [Cross]) or a click closes it, as Back does; up and down scroll the body by [member scroll_step]
## while it is taller than the panel, which [method can_scroll] reports and
## [signal scroll_range_changed] announces, so the hints list scrolling only when it does
## something. The mouse wheel scrolls it too.

## Whether the body can scroll may have changed: its content or its size changed.
signal scroll_range_changed()

# ASSUMPTION: about two lines of HUD text per press; no basis.
## How far up and down scroll the body per press.[br]
## [b]Units:[/b] pixels.
@export_range(4.0, 400.0, 1.0) var scroll_step: float = 48.0

## The line under the name: [code]%s[/code] the unit type, then its side.
@export var summary_format: String = "%s · %s"

## Added to the summary for its army's commander.[br]
## [b]Empty:[/b] commanders aren't called out.
@export var commander_text: String = "Commander"

## The vitals line: [code]%d[/code] HP and its maximum, Stance and its maximum, then Block.
@export var vitals_format: String = "HP %d/%d · Stance %d/%d · Block %d"

## The weapon line: name, type, profile, then damage, damage type, AtkX, Hit, Crit, CritX, range
## and weight ([code]%s[/code], [code]%d[/code] and [code]%.1f[/code] in that order).
@export var weapon_format: String = (
		"%s (%s, %s): Dmg %d %s · AtkX %d · Hit %d · Crit %d ×%.1f · Rng %s · Wt %d"
)

## A staff's line: name, its kind, the amount before Might, range and weight.
@export var staff_format: String = "%s (staff, %s): %d + Might · Rng %s · Wt %d"

## The line when a slot holds nothing.
@export var empty_slot_text: String = "—"

## One effect line: [code]%s[/code] the carrier's name, then its text.
@export var effect_format: String = "%s: %s"

## Added to an effect line with limited charges: [code]%d[/code] the charges left.
@export var charges_format: String = " (%d left)"

var _view: UnitDetailViewModel = null

@onready var _close: Button = %CloseButton
@onready var _body: ScrollContainer = %Body
@onready var _name: Label = %UnitName
@onready var _summary: Label = %Summary
@onready var _vitals: Label = %Vitals
@onready var _stats: Label = %Stats
@onready var _combat: Label = %Combat
@onready var _weapon: Label = %Weapon
@onready var _stowed: Label = %Stowed
@onready var _equipment: Label = %Equipment
@onready var _pouch: Label = %Pouch
@onready var _traits: Label = %Traits
@onready var _heirlooms: Label = %Heirlooms
@onready var _tags: Label = %Tags


func _ready() -> void:
	_close.pressed.connect(_on_close_button_pressed)
	_body.get_v_scroll_bar().changed.connect(_on_body_scroll_changed)
	BattlePanel.chain_focus([_close])


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_up", true):
		if scroll_by(-scroll_step):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down", true):
		if scroll_by(scroll_step):
			get_viewport().set_input_as_handled()


## Draws [param payload], a [UnitDetailViewModel]; anything else shows nothing.
func open_with(payload: Variant) -> void:
	show_detail(payload as UnitDetailViewModel)


func focus_first() -> void:
	_close.grab_focus()


## Draws [param view] from the top of the body.
func show_detail(view: UnitDetailViewModel) -> void:
	_view = view
	if view == null:
		return
	_name.text = view.name
	var summary: String = summary_format % [
		view.type_name, (CombatFact.CombatSide.find_key(view.side) as String).capitalize(),
	]
	if view.is_commander and not commander_text.is_empty():
		summary += " · " + commander_text
	_summary.text = summary
	_vitals.text = vitals_format % [view.hp, view.max_hp, view.stance, view.stance_max, view.block]
	_stats.text = "  ".join(view.stat_pairs())
	var combat: PackedStringArray = view.combat_pairs()
	combat.append("Crit %d ×%.1f" % [view.crit_chance, view.crit_x])
	_combat.text = "  ".join(combat)
	_weapon.text = "Weapon: " + _weapon_text(view.weapon)
	_stowed.text = "Stowed: " + _weapon_text(view.stowed)
	_stowed.visible = view.stowed != null
	_equipment.text = _slot_text("Equipment", view.equipment_name, view.equipment_effects)
	_pouch.text = _slot_text("Pouch", view.pouch_name, view.pouch_effects)
	_traits.text = _list_text("Traits", view.traits)
	_heirlooms.text = _list_text("Heirlooms", view.heirlooms)
	_heirlooms.visible = view.side == CombatFact.CombatSide.PLAYER
	var tags: String = ", ".join(view.tags) if not view.tags.is_empty() else empty_slot_text
	_tags.text = "Movement: %s · Tags: %s" % [view.movement_name, tags]
	_body.scroll_vertical = 0


## The view shown; null before [method show_detail].
func get_view() -> UnitDetailViewModel:
	return _view


## Whether the body is taller than the panel, so up and down scroll it.
func can_scroll() -> bool:
	var bar: VScrollBar = _body.get_v_scroll_bar()
	return bar.max_value - bar.page > 0.5


## Scrolls the body by [param pixels], down when positive. Returns whether it moved.
func scroll_by(pixels: float) -> bool:
	var before: int = _body.scroll_vertical
	_body.scroll_vertical = before + roundi(pixels)
	return _body.scroll_vertical != before


## How far the body is scrolled, for tests. [b]Units:[/b] pixels.
func get_scroll() -> int:
	return _body.scroll_vertical


## The Close button, for tests and the mouse.
func get_close_button() -> Button:
	return _close


## Every line shown, in order, for tests and the report: name, summary, vitals, stats, combat,
## weapon, stowed, equipment, pouch, traits, heirlooms, tags (a hidden one as empty).
func get_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for label: Label in [
			_name, _summary, _vitals, _stats, _combat, _weapon, _stowed, _equipment, _pouch,
			_traits, _heirlooms, _tags,
	]:
		texts.append(label.text if label.visible else "")
	return texts


func _weapon_text(line: UnitDetailViewModel.WeaponLine) -> String:
	if line == null:
		return empty_slot_text
	var text: String = ""
	if line.is_staff:
		text = staff_format % [
			line.name, line.staff_kind, line.staff_amount, line.range_text(), line.weight,
		]
	else:
		text = weapon_format % [
			line.name, line.weapon_type, line.profile, line.damage, line.damage_type, line.atk_x,
			line.hit, line.crit, line.crit_x, line.range_text(), line.weight,
		]
	if not line.effective_against.is_empty():
		text += " · Effective vs %s" % [", ".join(line.effective_against)]
	for effect: UnitDetailViewModel.EffectLine in line.effects:
		text += "\n  " + _effect_text(effect)
	return text


func _slot_text(
		heading: String, item_name: String, effects: Array[UnitDetailViewModel.EffectLine]
) -> String:
	var shown: String = item_name if not item_name.is_empty() else empty_slot_text
	var text: String = "%s: %s" % [heading, shown]
	for effect: UnitDetailViewModel.EffectLine in effects:
		text += "\n  " + _effect_text(effect)
	return text


func _list_text(heading: String, effects: Array[UnitDetailViewModel.EffectLine]) -> String:
	if effects.is_empty():
		return "%s: %s" % [heading, empty_slot_text]
	var lines: PackedStringArray = [heading + ":"]
	for effect: UnitDetailViewModel.EffectLine in effects:
		lines.append("  " + _effect_text(effect))
	return "\n".join(lines)


func _effect_text(effect: UnitDetailViewModel.EffectLine) -> String:
	var text: String = effect_format % [effect.label, effect.text]
	if effect.charges_left >= 0:
		text += charges_format % [effect.charges_left]
	return text


func _on_close_button_pressed() -> void:
	cancelled.emit()


func _on_body_scroll_changed() -> void:
	scroll_range_changed.emit()
