# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     board_view_model.gd
# Author:
# Created:  November 4, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name BoardViewModel
extends RefCounted
## What the battle board draws, as plain data read from a [CombatSession]: each unit on the map,
## with its HP, Stance, Block and turn, each flooded tile's darkness layer, and each map object
## that isn't a token, with its state and the tag linking a lever to its doors and a passage's ends.
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

## Each map object drawn as a mark ([method is_drawn]), in id order.
var objects: Array[ObjectView] = []


## The board of [param session] as it stands now.
static func build(session: CombatSession) -> BoardViewModel:
	var model: BoardViewModel = BoardViewModel.new()
	for unit_id: String in session.state.unit_ids():
		model.units.append(unit_view(session, unit_id))
	model.darkness = darkness_of(session.state)
	model.objects = objects_of(session.state)
	return model


## Whether a [MapObjectMark] draws objects of [param kind]: every kind but the breakables
## (debris, powder kegs), which stand on the map as units and draw as tokens.
static func is_drawn(kind: MapLayout.ObjectKind) -> bool:
	return kind != MapLayout.ObjectKind.NONE and not MapObjects.BREAKABLE_STATS.has(kind)


## Each object of [param state] a mark draws ([method is_drawn]), in id order.
static func objects_of(state: CombatState) -> Array[ObjectView]:
	var ids: Array[String] = []
	ids.assign(state.map.objects.keys())
	ids.sort()
	var views: Array[ObjectView] = []
	for object_id: String in ids:
		var placed: MapState.ObjectState = state.map.objects[object_id]
		if is_drawn(placed.kind) and not placed.is_destroyed:
			views.append(object_view(state, placed))
	return views


## [param placed] of [param state] as its mark draws it.
static func object_view(state: CombatState, placed: MapState.ObjectState) -> ObjectView:
	var view: ObjectView = ObjectView.new()
	view.id = placed.id
	view.kind = placed.kind
	view.tile = placed.tile
	view.is_open = placed.is_open
	view.is_used = placed.is_used
	view.is_lit = placed.is_lit
	view.group_id = placed.group_id
	view.pair_id = placed.pair_id
	view.tag = tag_of(placed)
	if placed.kind == MapLayout.ObjectKind.PASSAGE:
		var other: MapState.ObjectState = MapObjects.other_end(state, placed)
		if other != null:
			view.other_end = other.tile
	return view


## The short tag a mark shows to link objects: the lever group's letter on a lever and its doors
## ([code]A[/code] for group 0), the pair's number on both ends of a passage ([code]1[/code] for
## pair 0); empty for anything else, a key-only door included.
static func tag_of(placed: MapState.ObjectState) -> String:
	match placed.kind:
		MapLayout.ObjectKind.DOOR, MapLayout.ObjectKind.LEVER:
			if placed.group_id >= 0:
				return String.chr("A".unicode_at(0) + placed.group_id)
		MapLayout.ObjectKind.PASSAGE:
			if placed.pair_id >= 0:
				return str(placed.pair_id + 1)
	return ""


## The state and link of [param placed] in words, for the tile panel, such as
## [code]closed, lever A[/code] or [code]to (11, 1)[/code]; empty when there is nothing to say.
static func object_note(state: CombatState, placed: MapState.ObjectState) -> String:
	var tag: String = tag_of(placed)
	match placed.kind:
		MapLayout.ObjectKind.DOOR:
			if tag.is_empty():
				return "open" if placed.is_open else "locked, needs a key"
			return "%s, lever %s" % ["open" if placed.is_open else "closed", tag]
		MapLayout.ObjectKind.LEVER:
			return "opens and closes doors %s" % [tag] if not tag.is_empty() else ""
		MapLayout.ObjectKind.PASSAGE:
			var other: MapState.ObjectState = MapObjects.other_end(state, placed)
			return "" if other == null else "%s, to %s" % [tag, other.tile]
		MapLayout.ObjectKind.BRAZIER:
			return "lit" if placed.is_lit else "unlit"
		MapLayout.ObjectKind.CHEST:
			return "opened" if placed.is_used else "locked"
	if MapLayout.CONTAINERS.has(placed.kind) and placed.is_used:
		return "searched"
	return ""


## The unit [param unit_id] of [param session] as a token draws it; its max HP and Stance
## maximum are read through [method CombatSession.stats].
static func unit_view(session: CombatSession, unit_id: String) -> UnitView:
	var state: CombatState = session.state
	var sheet: StatSheet = session.stats(unit_id)
	var view: UnitView = UnitView.new()
	view.id = unit_id
	view.side = state.side_of(unit_id)
	view.seat = state.seat_of(unit_id)
	view.unit_type = state.unit_type_of(unit_id)
	view.letter = letter_of(view.unit_type)
	view.hp = state.get_hp(unit_id)
	view.max_hp = sheet.get_int(CombatValue.Key.HP)
	view.tile = state.tile_of(unit_id)
	view.stance_max = sheet.get_int(CombatValue.Key.STANCE_MAX)
	view.can_gain_block = sheet.is_allowed(CombatValue.Permission.CAN_GAIN_BLOCK)
	var unit: CombatUnitState = state.unit(unit_id)
	if unit != null:
		view.block = unit.block
		view.stance = unit.stance
		view.has_acted = unit.has_acted
		view.is_second_move_pending = unit.is_second_move_pending
	return view


## Each flooded tile's layer in [param state]'s darkness ([member MapState.darkness]).
static func darkness_of(state: CombatState) -> Dictionary[Vector2i, int]:
	var layers: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in state.map.darkness.layers:
		layers[tile] = state.map.darkness.layers[tile]
	return layers


## Whether [param fact], a [constant CombatFact.Kind.MODIFIER_GAINED] or
## [constant CombatFact.Kind.MODIFIER_EXPIRED], is a timed ban on gaining Block (Haunted's):
## the [AddTimedModifier] it names denies [constant CombatValue.Permission.CAN_GAIN_BLOCK]. Read
## from the effect's definition, so it holds while the fact plays, whatever the state is by then.
static func is_block_ban(session: CombatSession, fact: CombatFact) -> bool:
	var instance: EffectInstance = session.engine.get_instance(fact.source_effect_id)
	if instance == null or instance.definition == null:
		return false
	var operations: Array[EffectOperation] = instance.definition.operations
	if fact.key < 0 or fact.key >= operations.size():
		return false
	var timed: AddTimedModifier = operations[fact.key] as AddTimedModifier
	return (
			timed != null
			and timed.key == CombatValue.Permission.CAN_GAIN_BLOCK
			and timed.mode == Modifier.Mode.DENY
	)


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
	## Its Block now.
	var block: int = 0
	## Its Stance now; Triage can raise it past [member stance_max].
	var stance: int = 0
	## Its Stance maximum, which its side's Phase Start refills it to.
	var stance_max: int = 0
	## Whether it has taken its action.
	var has_acted: bool = false
	## Whether it may still move after its action.
	var is_second_move_pending: bool = false
	## Whether it may gain Block ([constant CombatValue.Permission.CAN_GAIN_BLOCK]); Haunted's
	## ban denies it.
	var can_gain_block: bool = true


## One map object as its [MapObjectMark] draws it.
class ObjectView:
	extends RefCounted

	## The object's id.
	var id: String = ""
	## What it is.
	var kind: MapLayout.ObjectKind = MapLayout.ObjectKind.NONE
	## Its tile.
	var tile: Vector2i = CombatFact.NO_TILE
	## A door: whether it is open.
	var is_open: bool = false
	## A container: whether it was opened or searched.
	var is_used: bool = false
	## A brazier: whether it is lit.
	var is_lit: bool = false
	## A door's or lever's lever group; -1 for none.
	var group_id: int = -1
	## A passage end's pair; -1 for none.
	var pair_id: int = -1
	## The link tag ([method BoardViewModel.tag_of]); empty for none.
	var tag: String = ""
	## A passage end's other end; [constant CombatFact.NO_TILE] for anything else.
	var other_end: Vector2i = CombatFact.NO_TILE

	## Whether it shows spent: an open door, a used container, an unlit brazier.
	func is_spent() -> bool:
		match kind:
			MapLayout.ObjectKind.DOOR:
				return is_open
			MapLayout.ObjectKind.BRAZIER:
				return not is_lit
		return is_used
