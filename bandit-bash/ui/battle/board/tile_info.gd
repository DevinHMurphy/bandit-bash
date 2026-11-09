# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     tile_info.gd
# Author:
# Created:  November 5, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name TileInfo
extends PanelContainer
## The tile under the cursor: its terrain, the avoid, DEF and RES it gives, and who or what stands
## on it (combat UI plan, question 11; Godot_FE FR-UI-3's tile info).
##
## Draws a [HudViewModel.TileView]; [BattleHud] builds one each time the cursor moves or the board
## settles. Holds no rules. Off the map it hides.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The bonuses line: [code]%d[/code] avoid, then [code]%+d[/code] DEF and [code]%+d[/code] RES.
@export var bonus_format: String = "Avoid %d · DEF %+d · RES %+d"

## The occupant line: [code]%s[/code] the unit's name, then its side ("player", "enemy").
@export var occupant_format: String = "%s (%s)"

## The occupant line on a tile with no unit and no object.
@export var empty_text: String = "Empty"

var _view: HudViewModel.TileView = null

@onready var _terrain: Label = %Terrain
@onready var _bonuses: Label = %Bonuses
@onready var _occupant: Label = %Occupant


## Shows [param view]; hides on a tile off the map or a null view.
func show_tile(view: HudViewModel.TileView) -> void:
	_view = view
	visible = view != null and view.is_on_map
	if not visible:
		return
	_terrain.text = view.terrain_name
	_bonuses.text = bonus_format % [view.avoid, view.defense, view.resistance]
	var parts: PackedStringArray = []
	if not view.occupant_name.is_empty():
		if view.occupant_side == CombatFact.CombatSide.NONE:
			parts.append(view.occupant_name)
		else:
			var side: String = (CombatFact.CombatSide.find_key(view.occupant_side) as String)
			parts.append(occupant_format % [view.occupant_name, side.to_lower()])
	parts.append_array(view.object_names)
	_occupant.text = " · ".join(parts) if not parts.is_empty() else empty_text


## The view shown; null before [method show_tile].
func get_view() -> HudViewModel.TileView:
	return _view


## The three lines shown, for tests: terrain, bonuses, occupant.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_terrain.text, _bonuses.text, _occupant.text])
