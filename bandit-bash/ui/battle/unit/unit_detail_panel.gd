# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_detail_panel.gd
# Author:
# Created:  November 7, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitDetailPanel
extends BattlePanel
## One unit's detail, player or enemy, as a centred pop-up over the dimmed board (ui-lift.md, Unit
## detail pop-up; Godot_FE's [code]unit_detailed_info[/code] layout): the [UnitDetailHeader], each
## stat and combat value with its sources ([DetailStatRow]), the gear ([DetailGearRow]), traits and
## heirlooms as effect text ([DetailEffectRow]), an enemy's intent and signature move
## ([DetailEnemySection]), movement type and tags.[br]
## Opened on [PanelHost] by [BattleController] with a [UnitDetailViewModel]; it draws on its own
## canvas layer so it centres over the screen, not in the panel column. It holds no rules. Close
## keeps focus, so accept, a click or Back closes it; up and down and the wheel scroll the body
## ([method can_scroll], [signal scroll_range_changed]); Previous and Next ask for the side's other
## units ([signal step_requested]), as Q / E and the shoulder buttons do through the controller.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## Whether the body can scroll may have changed: its content or its size changed.
signal scroll_range_changed()

## Previous ([param forward] false) or Next (true) was clicked: show the side's other unit.
signal step_requested(forward: bool)

## How far up and down scroll the body per press: about two lines of HUD text.[br]
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

## A weapon's profile under its name in the gear: type, profile, then damage, damage type, AtkX,
## Hit, Crit, CritX, range and weight, as [member weapon_format] without the name.
@export var weapon_profile_format: String = (
		"%s, %s · Dmg %d %s · AtkX %d · Hit %d · Crit %d ×%.1f · Rng %s · Wt %d"
)

## A staff's profile under its name in the gear: its kind, the amount before Might, range and
## weight.
@export var staff_profile_format: String = "Staff, %s · %d + Might · Rng %s · Wt %d"

## The line when a slot holds nothing.
@export var empty_slot_text: String = "—"

## One effect line: [code]%s[/code] the carrier's name, then its text.
@export var effect_format: String = "%s: %s"

## Added to an effect line with limited charges: [code]%d[/code] the charges left.
@export var charges_format: String = " (%d left)"

## The row placed for each stat and combat value: a [DetailStatRow] scene.[br]
## [b]Unset:[/b] no value rows show and an error is reported.
@export var stat_row_scene: PackedScene = null

## The row placed for each trait, heirloom and curse: a [DetailEffectRow] scene.[br]
## [b]Unset:[/b] no effect rows show and an error is reported.
@export var effect_row_scene: PackedScene = null

var _view: UnitDetailViewModel = null

# The lines get_texts() reports, in its order, as the panel last drew them.
var _texts: PackedStringArray = []

# The board dims to bg at 50% (battle_theme.tres ModalDim, the panel shadow's alpha), stopping 56
# units short of the bottom so the hint bar stays readable.
@onready var _modal: CanvasLayer = %Modal
@onready var _header: UnitDetailHeader = %Header
@onready var _body: ScrollContainer = %Body
@onready var _stat_rows: VBoxContainer = %StatRows
@onready var _combat_rows: VBoxContainer = %CombatRows
@onready var _weapon: DetailGearRow = %WeaponRow
@onready var _stowed: DetailGearRow = %StowedRow
@onready var _equipment: DetailGearRow = %EquipmentRow
@onready var _pouch: DetailGearRow = %PouchRow
@onready var _enemy: DetailEnemySection = %EnemySection
@onready var _effect_rows: VBoxContainer = %EffectRows
@onready var _no_effects: Label = %NoEffects
@onready var _tags: Label = %Tags


func _ready() -> void:
	_header.summary_format = summary_format
	_header.commander_text = commander_text
	_header.vitals_format = vitals_format
	_header.close_pressed.connect(_on_header_close_pressed)
	_header.step_pressed.connect(_on_header_step_pressed)
	_body.get_v_scroll_bar().changed.connect(_on_body_scroll_changed)
	BattlePanel.chain_focus([_header.get_close_button()])


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_up", true):
		if scroll_by(-scroll_step):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down", true):
		if scroll_by(scroll_step):
			get_viewport().set_input_as_handled()


# Its canvas layer is no CanvasItem, so it follows the panel's visibility by hand: a panel the host
# covers or hides takes its pop-up with it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_modal.visible = is_visible_in_tree()


## Draws [param payload], a [UnitDetailViewModel]; anything else shows nothing.
func open_with(payload: Variant) -> void:
	show_detail(payload as UnitDetailViewModel)


func focus_first() -> void:
	_header.get_close_button().grab_focus()


## Draws [param view] from the top of the body; the controller calls it again to step to another
## unit without closing.
func show_detail(view: UnitDetailViewModel) -> void:
	_view = view
	if view == null:
		return
	_header.show_header(view)
	_show_values(_stat_rows, view.stat_rows)
	_show_values(_combat_rows, view.combat_rows)
	_weapon.show_gear("Weapon", _item_name(view.weapon), _weapon_detail(view.weapon))
	_stowed.show_gear("Stowed", _item_name(view.stowed), _weapon_detail(view.stowed))
	_stowed.visible = view.stowed != null
	_equipment.show_gear("Equipment", view.equipment_name, _lines_text(view.equipment_effects))
	_pouch.show_gear("Pouch", view.pouch_name, _lines_text(view.pouch_effects))
	_enemy.show_enemy(view)
	_show_effects(view)
	var tags: String = ", ".join(view.tags) if not view.tags.is_empty() else empty_slot_text
	_tags.text = "Movement: %s · Tags: %s" % [view.movement_name, tags]
	_texts = _report_texts(view)
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
	return _header.get_close_button()


## The header, for tests: its texts and its Previous and Next buttons.
func get_header() -> UnitDetailHeader:
	return _header


## The value rows shown, stats then combat values, for tests.
func get_value_rows() -> Array[DetailStatRow]:
	var rows: Array[DetailStatRow] = []
	for box: VBoxContainer in [_stat_rows, _combat_rows]:
		for child: Node in box.get_children():
			var row: DetailStatRow = child as DetailStatRow
			if row != null and row.visible:
				rows.append(row)
	return rows


## The enemy section, for tests.
func get_enemy_section() -> DetailEnemySection:
	return _enemy


## The pop-up's frame on screen, for tests and the layout check.
func get_popup_rect() -> Rect2:
	return (%Popup as Control).get_global_rect()


## Every line shown, in order, for tests and the report: name, summary, vitals, stats, combat,
## weapon, stowed, equipment, pouch, traits, heirlooms, tags (a hidden one as empty).
func get_texts() -> PackedStringArray:
	return _texts.duplicate()


# One reused row per value in box; extras are hidden.
func _show_values(box: VBoxContainer, values: Array[UnitDetailViewModel.ValueRow]) -> void:
	if stat_row_scene == null:
		push_error("UnitDetailPanel: no stat row scene set")
		return
	while box.get_child_count() < values.size():
		box.add_child(stat_row_scene.instantiate())
	for i: int in box.get_child_count():
		var row: DetailStatRow = box.get_child(i) as DetailStatRow
		if row == null:
			continue
		row.visible = i < values.size()
		if row.visible:
			row.show_row(values[i])


# One reused row per trait, then per heirloom and curse; "—" with none.
func _show_effects(view: UnitDetailViewModel) -> void:
	if effect_row_scene == null:
		push_error("UnitDetailPanel: no effect row scene set")
		return
	var lines: Array[UnitDetailViewModel.EffectLine] = view.traits.duplicate()
	lines.append_array(view.heirlooms)
	while _effect_rows.get_child_count() < lines.size():
		_effect_rows.add_child(effect_row_scene.instantiate())
	for i: int in _effect_rows.get_child_count():
		var row: DetailEffectRow = _effect_rows.get_child(i) as DetailEffectRow
		if row == null:
			continue
		row.visible = i < lines.size()
		if row.visible:
			row.show_effect(lines[i], i >= view.traits.size())
	_no_effects.visible = lines.is_empty()
	_no_effects.text = empty_slot_text


# The lines get_texts() reports, as one string each.
func _report_texts(view: UnitDetailViewModel) -> PackedStringArray:
	var summary: String = summary_format % [
		view.type_name, (CombatFact.CombatSide.find_key(view.side) as String).capitalize(),
	]
	if view.is_commander and not commander_text.is_empty():
		summary += " · " + commander_text
	var combat: PackedStringArray = view.combat_pairs()
	combat.append("Crit %d ×%.1f" % [view.crit_chance, view.crit_x])
	var is_player: bool = view.side == CombatFact.CombatSide.PLAYER
	return PackedStringArray([
		view.name,
		summary,
		vitals_format % [view.hp, view.max_hp, view.stance, view.stance_max, view.block],
		"  ".join(view.stat_pairs()),
		"  ".join(combat),
		"Weapon: " + _weapon_text(view.weapon),
		"Stowed: " + _weapon_text(view.stowed) if view.stowed != null else "",
		_slot_text("Equipment", view.equipment_name, view.equipment_effects),
		_slot_text("Pouch", view.pouch_name, view.pouch_effects),
		_list_text("Traits", view.traits),
		_list_text("Heirlooms", view.heirlooms) if is_player else "",
		_tags.text,
	])


func _item_name(line: UnitDetailViewModel.WeaponLine) -> String:
	return "" if line == null else line.name


# A weapon's profile and its effects, without its name, for its gear row.
func _weapon_detail(line: UnitDetailViewModel.WeaponLine) -> String:
	if line == null:
		return ""
	var text: String = ""
	if line.is_staff:
		text = staff_profile_format % [
			line.staff_kind, line.staff_amount, line.range_text(), line.weight,
		]
	else:
		text = weapon_profile_format % [
			line.weapon_type, line.profile, line.damage, line.damage_type, line.atk_x, line.hit,
			line.crit, line.crit_x, line.range_text(), line.weight,
		]
	if not line.effective_against.is_empty():
		text += " · Effective vs %s" % [", ".join(line.effective_against)]
	for effect: UnitDetailViewModel.EffectLine in line.effects:
		text += "\n" + _effect_text(effect)
	return text


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


# An item's effect lines, one per line, for its gear row.
func _lines_text(effects: Array[UnitDetailViewModel.EffectLine]) -> String:
	var lines: PackedStringArray = []
	for effect: UnitDetailViewModel.EffectLine in effects:
		lines.append(_effect_text(effect))
	return "\n".join(lines)


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


func _on_header_close_pressed() -> void:
	cancelled.emit()


func _on_header_step_pressed(forward: bool) -> void:
	step_requested.emit(forward)


func _on_body_scroll_changed() -> void:
	scroll_range_changed.emit()
