# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     board_key.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name BoardKey
extends VBoxContainer
## The battle board's key (RF-039; ui-style.md, Profile marks): a [BoardKeyRow] per
## [ProfileMark] shape, Power, Balance, Nimble and None, each naming the profile it beats as
## [method WeaponTriangle.matchup] says, so the two never disagree; then the side rule, filled for
## the player side and hollow for the enemy. Opened from the [PauseMenu] when its
## [member PauseMenu.board_key_scene] is set (the battle screen's), in the menu column's place.[br]
## [b]Focus:[/b] the rows take none; Back holds it, up and down kept on it, and pressing it asks
## to go back ([signal back_pressed]). Esc and B are the menu's to read.

## Back was pressed: the menu shows its buttons again.
signal back_pressed()

## The group every key joins, so [method is_open_in] finds one shown.
const GROUP: StringName = &"board_key"

const ROW_SCENE: PackedScene = preload("res://ui/battle/key/board_key_row.tscn")

# The shape rows' order: the triangle round, then the profile outside it.
const _PROFILES: Array[WeaponTriangle.Profile] = [
	WeaponTriangle.Profile.POWER,
	WeaponTriangle.Profile.BALANCE,
	WeaponTriangle.Profile.NIMBLE,
	WeaponTriangle.Profile.NONE,
]

## A triangle profile's row: [code]%s[/code] its name, then the name of the profile it beats.
@export var beats_format: String = "%s — beats %s"

## The None row's text.
@export var none_text: String = "No profile — outside the triangle"

## The player side's row, drawn filled.
@export var filled_text: String = "Filled — your units"

## The enemy side's row, drawn hollow.
@export var hollow_text: String = "Hollow outline — enemies"

## The side of each row's mark.[br]
## [b]Units:[/b] pixels at the base size; the board draws its marks at 14.
@export_range(8.0, 40.0, 1.0) var mark_size: float = 14.0

@onready var _rows: VBoxContainer = %Rows
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	add_to_group(GROUP)
	for profile: WeaponTriangle.Profile in _PROFILES:
		_add_row(CombatFact.CombatSide.PLAYER, profile, row_text(profile))
	_add_row(CombatFact.CombatSide.PLAYER, WeaponTriangle.Profile.BALANCE, filled_text)
	_add_row(CombatFact.CombatSide.ENEMY, WeaponTriangle.Profile.BALANCE, hollow_text)
	_back_button.pressed.connect(back_pressed.emit)
	for neighbour: StringName in [
		&"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left",
		&"focus_neighbor_right", &"focus_next", &"focus_previous",
	]:
		_back_button.set(neighbour, NodePath("."))


## Gives Back focus.
func focus_first() -> void:
	_back_button.grab_focus()


## [param profile]'s row text: its name and the profile it beats, or [member none_text].
func row_text(profile: WeaponTriangle.Profile) -> String:
	for other: WeaponTriangle.Profile in _PROFILES:
		if WeaponTriangle.matchup(profile, other) == WhileMatchupCondition.Matchup.ADVANTAGE:
			return beats_format % [_name_of(profile), _name_of(other)]
	return none_text


## Its rows, top to bottom.
func get_rows() -> Array[BoardKeyRow]:
	var rows: Array[BoardKeyRow] = []
	for child: Node in _rows.get_children():
		if child is BoardKeyRow and not child.is_queued_for_deletion():
			rows.append(child)
	return rows


## Its rows' texts, top to bottom, for tests and captures.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for row: BoardKeyRow in get_rows():
		lines.append(row.get_text())
	return lines


## The Back button.
func get_back_button() -> Button:
	return _back_button


func _add_row(
		side: CombatFact.CombatSide, profile: WeaponTriangle.Profile, text: String
) -> void:
	var row: BoardKeyRow = ROW_SCENE.instantiate()
	row.mark_size = mark_size
	_rows.add_child(row)
	row.show_row(side, profile, text)


static func _name_of(profile: WeaponTriangle.Profile) -> String:
	return (WeaponTriangle.Profile.find_key(profile) as String).capitalize()


## Whether a key in [param tree] is shown: the battle's hints show its Back while one is.
static func is_open_in(tree: SceneTree) -> bool:
	if tree == null:
		return false
	for node: Node in tree.get_nodes_in_group(GROUP):
		var key: Control = node as Control
		if key != null and key.is_visible_in_tree():
			return true
	return false
