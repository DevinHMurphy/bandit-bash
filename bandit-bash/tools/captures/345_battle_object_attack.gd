# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     345_battle_object_attack.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Attacks on breakable map objects: wooden debris and a powder keg (with a second keg in its
## blast) staged beside the seat's units in this throwaway run (said in a NOTE), then Attack opened
## on each from the unit's own tile: the debris targeted and its forecast, the keg targeted with
## its chain of blasts drawn and its forecast with the splash on friendly units. Backs out of every
## panel after; the objects stay in the run.[br]
## Needs: the battle started and idle, its units yet to act (300_battle_start; 340_battle_attack
## backs out without acting).

const KEG: MapLayout.ObjectKind = MapLayout.ObjectKind.POWDER_KEG
const DEBRIS: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS

# The staged objects' spot indices: far above any map's own, so their ids are new.
const OBJECT_INDEX: int = 960

# Q / E presses at most while making the staged object the current target.
const MAX_CYCLES: int = 32


func run() -> bool:
	var view: BattleView = battle_view()
	var controller: BattleController = battle_controller()
	var session: CombatSession = view.get_session()
	var staged: Array[Array] = _stage_objects(session)
	if staged.is_empty():
		note("object attack: no room beside an acting unit for a keg and debris: no shots")
		return true
	var placed: PackedStringArray = []
	for entry: Array in staged:
		placed.append("%s at %s for %s" % [
			BattleText.name_of(session, entry[1] as String),
			session.state.tile_of(entry[1] as String),
			BattleText.name_of(session, entry[0] as String),
		])
	note("object attack: staged %s" % [", ".join(placed)])
	settle(view)
	await frames(SETTLE_FRAMES)
	for entry: Array in staged:
		var attacker_id: String = entry[0]
		var object_id: String = entry[1]
		var shot: String = entry[2]
		await _attack_shots(view, controller, session, attacker_id, object_id, shot)
	return true


# Opens attacker_id's Attack on its own tile, makes object_id the current target, and shoots
# TARGET and the forecast as battle_target_<shot> and battle_forecast_<shot>; then backs out.
func _attack_shots(
		view: BattleView,
		controller: BattleController,
		session: CombatSession,
		attacker_id: String,
		object_id: String,
		shot: String
) -> void:
	var tile: Vector2i = session.state.tile_of(attacker_id)
	controller.confirm_tile(tile)
	controller.confirm_tile(tile)
	settle(view)
	await frames(SETTLE_FRAMES)
	var host: PanelHost = scene().get_node(^"%PanelHost")
	var menu: ActionMenu = host.top() as ActionMenu
	if menu != null:
		var options: Array[TurnInputModel.ActionOption] = menu.get_options()
		for i: int in options.size():
			if options[i].kind == TurnInputModel.ActionKind.ATTACK:
				menu.get_rows()[i].pressed.emit()
				break
	var list: TargetList = controller.get_target_list()
	if list == null or list.index_of(object_id) < 0:
		fail("object attack: %s isn't an Attack target of %s" % [object_id, attacker_id])
	else:
		for _i: int in MAX_CYCLES:
			if list.current().target_id == object_id:
				break
			controller.cycle_target(true)
		await frames(SETTLE_FRAMES)
		await capture("battle_target_%s" % [shot])
		controller.confirm_tile(session.state.tile_of(object_id))
		await frames(SETTLE_FRAMES)
		await capture("battle_forecast_%s" % [shot])
	while controller.step_back():
		await tree.process_frame
	settle(view)
	await frames(SETTLE_FRAMES)


# Stages the objects and returns [attacker, object id, shot name] per shot, debris first; empty,
# staging nothing, when there is no room. The keg goes orthogonally next to an acting unit that
# attacks at range 1, a second keg next to it, preferring the pair whose blasts reach another
# player unit; the debris in another acting unit's reach, out of both blasts. Their tokens spawn
# through playback, as a session's facts would draw them.
func _stage_objects(session: CombatSession) -> Array[Array]:
	var shots: Array[Array] = []
	var state: CombatState = session.state
	var acting: PackedStringArray = _attackers(session)
	var keg_pick: Array = []
	var best_friends: int = -1
	for unit_id: String in acting:
		var reach: Vector2i = _reach_of(session, unit_id)
		if reach.x > 1 or reach.y < 1:
			continue
		var tile: Vector2i = state.tile_of(unit_id)
		for keg: Vector2i in MapObjects.KEG_BLAST.tiles(tile):
			if state.grid.distance(tile, keg) != 1 or not _is_free(state, keg):
				continue
			for chain: Vector2i in MapObjects.KEG_BLAST.tiles(keg):
				if chain == keg or chain == tile or not _is_free(state, chain):
					continue
				var friends: int = _friends_in(state, unit_id, keg, chain)
				if friends > best_friends:
					best_friends = friends
					keg_pick = [unit_id, keg, chain]
	if keg_pick.is_empty():
		return shots
	var keg_attacker: String = keg_pick[0]
	var keg_tile: Vector2i = keg_pick[1]
	var chain_tile: Vector2i = keg_pick[2]
	var debris_pick: Array = []
	for unit_id: String in acting:
		if unit_id == keg_attacker or not debris_pick.is_empty():
			continue
		var reach: Vector2i = _reach_of(session, unit_id)
		var tile: Vector2i = state.tile_of(unit_id)
		for dy: int in range(-reach.y, reach.y + 1):
			for dx: int in range(-reach.y, reach.y + 1):
				var spot: Vector2i = tile + Vector2i(dx, dy)
				var distance: int = state.grid.distance(tile, spot)
				var is_blasted: bool = (
						MapObjects.KEG_BLAST.covers(keg_tile, spot)
						or MapObjects.KEG_BLAST.covers(chain_tile, spot)
				)
				var fits: bool = distance >= reach.x and distance <= reach.y
				if debris_pick.is_empty() and fits and not is_blasted and _is_free(state, spot):
					debris_pick = [unit_id, spot]
	if debris_pick.is_empty():
		return shots
	var debris_attacker: String = debris_pick[0]
	var debris_tile: Vector2i = debris_pick[1]
	var tiles: Array[Vector2i] = [debris_tile, keg_tile, chain_tile]
	var kinds: Array[MapLayout.ObjectKind] = [DEBRIS, KEG, KEG]
	var layout: MapLayout = MapLayout.new()
	for i: int in tiles.size():
		var marker: MapLayout.Marker = layout.add_marker(
				MapLayout.MarkerKind.OBJECT_SPOT, tiles[i], kinds[i]
		)
		marker.index = OBJECT_INDEX + i
		marker.container_index = -1
	MapObjects.place_objects(session.engine, state, layout, session.ids)
	var spawned: Array[CombatFact] = []
	for i: int in tiles.size():
		var fact: CombatFact = CombatFact.new(
				CombatFact.Kind.UNIT_SPAWNED, InstanceIdAllocator.object_id(OBJECT_INDEX + i)
		)
		fact.tile = tiles[i]
		spawned.append(fact)
	session.playback.enqueue(spawned)
	shots.append([debris_attacker, InstanceIdAllocator.object_id(OBJECT_INDEX), "debris"])
	shots.append([keg_attacker, InstanceIdAllocator.object_id(OBJECT_INDEX + 1), "keg"])
	return shots


# Seat 0's acting units holding a weapon that attacks, in state order.
func _attackers(session: CombatSession) -> PackedStringArray:
	var found: PackedStringArray = []
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		var held: CombatState.WeaponStats = session.state.equipped_weapon(unit_id)
		if held == null:
			continue
		if held.is_staff() and held.staff != CombatState.WeaponStats.Staff.ATTACK:
			continue
		found.append(unit_id)
	return found


# How many player units besides unit_id stand in the blasts of kegs on keg and chain.
func _friends_in(state: CombatState, unit_id: String, keg: Vector2i, chain: Vector2i) -> int:
	var friends: int = 0
	for other: String in state.units_of(CombatFact.CombatSide.PLAYER):
		var at: Vector2i = state.tile_of(other)
		if other == unit_id:
			continue
		if MapObjects.KEG_BLAST.covers(keg, at) or MapObjects.KEG_BLAST.covers(chain, at):
			friends += 1
	return friends


# unit_id's range with the weapon in hand, as (shortest, longest).
func _reach_of(session: CombatSession, unit_id: String) -> Vector2i:
	var sheet: StatSheet = session.stats(unit_id)
	return Vector2i(
			sheet.get_int(CombatValue.Key.RANGE_MIN), sheet.get_int(CombatValue.Key.RANGE_MAX)
	)


# Whether tile is on the map, empty of units and objects, and walkable ground.
func _is_free(state: CombatState, tile: Vector2i) -> bool:
	if state.grid.step(tile, Vector2i.ZERO) == CombatFact.NO_TILE:
		return false
	if not state.occupant_at(tile).is_empty() or not state.map.objects_at(tile).is_empty():
		return false
	return state.can_stand(tile, CombatGrid.MovementType.DEFAULT)
