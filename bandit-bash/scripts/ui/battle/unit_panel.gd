# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_panel.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name UnitPanel
extends PanelContainer
## The hovered or selected unit: its HP, base stats, weapon, Block and Stance (combat UI plan,
## question 11; Godot_FE FR-UI-3's unit footer, without XP, which is P08's).
##
## Draws a [HudViewModel.UnitView]; [BattleHud] picks the unit (the one under the cursor, else the
## selected one) and builds the view. Holds no rules. With no unit it hides.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The HP line: [code]%d[/code] HP now, then its maximum.
@export var hp_format: String = "HP %d / %d"

## The Block and Stance line: [code]%d[/code] Block, then Stance now and after a refresh.
@export var guard_format: String = "Block %d · Stance %d / %d"

## The weapon line: [code]%s[/code] its name, then [code]%d[/code] damage, Hit and a range text.
@export var weapon_format: String = "%s · Dmg %d · Hit %d · Rng %s"

## The weapon line for a staff: [code]%s[/code] its name and a range text.
@export var staff_format: String = "%s (staff) · Rng %s"

## The weapon line when the Weapon slot is empty.
@export var no_weapon_text: String = "No weapon"

## The line under the name once the unit has acted this phase; empty hides it.
@export var acted_text: String = "Has acted"

## The name's colour for each side: player units.
@export var player_color: Color = Color(0.55, 0.75, 1.0, 1.0)

## The name's colour for enemy units; anything else (a breakable) keeps the theme's.
@export var enemy_color: Color = Color(1.0, 0.5, 0.45, 1.0)

var _view: HudViewModel.UnitView = null

@onready var _name: Label = %UnitName
@onready var _status: Label = %Status
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp: Label = %Hp
@onready var _guard: Label = %Guard
@onready var _stats: Label = %Stats
@onready var _weapon: Label = %Weapon
@onready var _gear: Label = %Gear


## Shows [param view]; hides for null.
func show_unit(view: HudViewModel.UnitView) -> void:
	_view = view
	visible = view != null
	if view == null:
		return
	_name.text = view.name
	match view.side:
		CombatFact.CombatSide.PLAYER:
			_name.add_theme_color_override(&"font_color", player_color)
		CombatFact.CombatSide.ENEMY:
			_name.add_theme_color_override(&"font_color", enemy_color)
		_:
			_name.remove_theme_color_override(&"font_color")
	_status.text = acted_text if view.has_acted else ""
	_status.visible = not _status.text.is_empty()
	_hp_bar.max_value = maxf(float(view.max_hp), 1.0)
	_hp_bar.value = float(view.hp)
	_hp.text = hp_format % [view.hp, view.max_hp]
	_guard.text = guard_format % [view.block, view.stance, view.stance_max]
	var stats: PackedStringArray = []
	for i: int in view.stat_names.size():
		stats.append("%s %d" % [view.stat_names[i], view.stat_values[i]])
	# Two rows of three, which fit the HUD column.
	var half: int = ceili(stats.size() / 2.0)
	_stats.text = "%s\n%s" % ["  ".join(stats.slice(0, half)), "  ".join(stats.slice(half))]
	_weapon.text = _weapon_text(view)
	var gear: PackedStringArray = []
	if not view.stowed_name.is_empty():
		gear.append("Stowed: %s" % [view.stowed_name])
	if not view.pouch_name.is_empty():
		gear.append("Pouch: %s" % [view.pouch_name])
	_gear.text = " · ".join(gear)
	_gear.visible = not gear.is_empty()


## The view shown; null when none is.
func get_view() -> HudViewModel.UnitView:
	return _view


## Every line shown, for tests: name, status, HP, Block and Stance, stats, weapon, gear.
func get_texts() -> PackedStringArray:
	return PackedStringArray([
		_name.text, _status.text, _hp.text, _guard.text, _stats.text, _weapon.text, _gear.text,
	])


func _weapon_text(view: HudViewModel.UnitView) -> String:
	if view.weapon_name.is_empty():
		return no_weapon_text
	var reach: String = "%d" % [view.range_max]
	if view.range_min != view.range_max:
		reach = "%d-%d" % [view.range_min, view.range_max]
	if view.is_staff:
		return staff_format % [view.weapon_name, reach]
	return weapon_format % [view.weapon_name, view.weapon_damage, view.weapon_hit, reach]
