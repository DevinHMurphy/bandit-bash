# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     board_view_model.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name BoardViewModel
extends RefCounted
## What the battle board draws, as plain data read from a [CombatSession]: each unit on the map
## and each flooded tile's darkness layer.
##
## Built by [method build] and read by [BattleView]; widgets draw it and hold no rules. Reading
## only: nothing here changes the session. Tests check it without rendering (combat UI plan,
## question 13).
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Each unit on the map, in [method CombatState.unit_ids] order.
var units: Array[UnitView] = []

## Each flooded tile's layer, a [enum WhileLayerCondition.Layer]; a dry tile is absent.
var darkness: Dictionary[Vector2i, int] = {}


## The board of [param session] as it stands now.
static func build(session: CombatSession) -> BoardViewModel:
	var model: BoardViewModel = BoardViewModel.new()
	for unit_id: String in session.state.unit_ids():
		model.units.append(unit_view(session, unit_id))
	model.darkness = darkness_of(session.state)
	return model


## The unit [param unit_id] of [param session] as a token draws it; its max HP is read through
## [method CombatSession.stats].
static func unit_view(session: CombatSession, unit_id: String) -> UnitView:
	var state: CombatState = session.state
	var view: UnitView = UnitView.new()
	view.id = unit_id
	view.side = state.side_of(unit_id)
	view.seat = state.seat_of(unit_id)
	view.unit_type = state.unit_type_of(unit_id)
	view.letter = letter_of(view.unit_type)
	view.hp = state.get_hp(unit_id)
	view.max_hp = session.stats(unit_id).get_int(CombatValue.Key.HP)
	view.tile = state.tile_of(unit_id)
	return view


## Each flooded tile's layer in [param state]'s darkness ([member MapState.darkness]).
static func darkness_of(state: CombatState) -> Dictionary[Vector2i, int]:
	var layers: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in state.map.darkness.layers:
		layers[tile] = state.map.darkness.layers[tile]
	return layers


## The letters a token shows for [param unit_type] by default: the first [param count] letters of
## the type id, underscores skipped, upper case; [code]?[/code] for none. [UnitToken] picks the
## count and any override ([member UnitToken.letter_count], [member UnitToken.letter_overrides]).
static func letter_of(unit_type: String, count: int = 2) -> String:
	# ASSUMPTION: content has no display names yet, so the letters are the type id's (Hakkapel HA,
	# Hedge Healer HE, Brute BR, Battle Medic BA), upper case like the single letter they replace.
	var letters: String = unit_type.replace("_", "")
	return "?" if letters.is_empty() else letters.left(maxi(count, 1)).to_upper()


## One unit as a token draws it.
class UnitView:
	extends RefCounted

	## The unit's instance id.
	var id: String = ""
	## Its side; picks the token's colour.
	var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
	## Its seat; -1 for an enemy.
	var seat: int = -1
	## Its unit type's content id.
	var unit_type: String = ""
	## The letters on its token by default ([method BoardViewModel.letter_of]); the token may
	## override them.
	var letter: String = ""
	## Its HP now.
	var hp: int = 0
	## Its maximum HP.
	var max_hp: int = 0
	## Its tile; [constant CombatFact.NO_TILE] when it isn't on the map.
	var tile: Vector2i = CombatFact.NO_TILE
