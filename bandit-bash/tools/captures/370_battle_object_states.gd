# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     370_battle_object_states.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Every map object state's mark side by side on the board, from the map's top-left tile, and a
## lit keg thrown onto the first free tile: staged in this throwaway run (said in a NOTE), the
## marks removed after the shot. The keg stays in the run.[br]
## Needs: the battle started (300_battle_start).

const MARK_SCENE: String = "res://ui/battle/board/map_object_mark.tscn"


func run() -> bool:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	var mark_scene: PackedScene = load(MARK_SCENE)
	var rect: Rect2i = session.layout.get_rect()
	var staged: Array[Node] = []
	var index: int = 0
	for state: Array in _staged_object_views():
		var tile: Vector2i = rect.position + Vector2i(
				index % rect.size.x, floori(float(index) / rect.size.x)
		)
		var mark: MapObjectMark = mark_scene.instantiate()
		view.add_child(mark)
		var shown: BoardViewModel.ObjectView = state[1]
		mark.show_object(shown, view.tile_to_position(tile))
		staged.append(mark)
		index += 1
	var thrower: PackedStringArray = session.state.units_of(CombatFact.CombatSide.ENEMY)
	var keg_tile: String = "none"
	var recorded: int = session.engine.fact_log.size()
	if not thrower.is_empty():
		for y: int in range(rect.end.y - 1, rect.position.y - 1, -1):
			for x: int in range(rect.position.x, rect.end.x):
				var tile: Vector2i = Vector2i(x, y)
				if keg_tile == "none" and MapObjects.can_land(session.state, tile):
					if not MapObjects.throw_keg(session, tile, thrower[0]).is_empty():
						keg_tile = str(tile)
	# The throw's facts play as a session's do, so the keg's token spawns on the board.
	var thrown: Array[CombatFact] = []
	thrown.assign(session.engine.fact_log.slice(recorded))
	session.playback.enqueue(thrown)
	note("object states shot: %d marks staged from the top-left tile (%s), a lit keg"
			% [index, ", ".join(_staged_names())] + " thrown at %s" % [keg_tile])
	settle(view)
	await frames(SETTLE_FRAMES)
	await capture("battle_object_states")
	for mark: Node in staged:
		mark.queue_free()
	await frames(1)
	return true


# Each object state staged for the shot: [name, view].
func _staged_object_views() -> Array[Array]:
	var kinds: Array[MapLayout.ObjectKind] = [
		MapLayout.ObjectKind.CHEST, MapLayout.ObjectKind.LEVER, MapLayout.ObjectKind.HOUSE,
		MapLayout.ObjectKind.FOOD_SHELF, MapLayout.ObjectKind.BOOK_SHELF,
		MapLayout.ObjectKind.WEAPON_RACK, MapLayout.ObjectKind.PASSAGE,
	]
	var states: Array[Array] = []
	for kind: MapLayout.ObjectKind in kinds:
		var name: String = (MapLayout.ObjectKind.find_key(kind) as String).to_lower()
		states.append([name, _object_view(kind, false, false, false, -1)])
		if kind != MapLayout.ObjectKind.LEVER and kind != MapLayout.ObjectKind.PASSAGE:
			states.append([name + " used", _object_view(kind, false, true, false, -1)])
	var door: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
	var brazier: MapLayout.ObjectKind = MapLayout.ObjectKind.BRAZIER
	states.append(["key door", _object_view(door, false, false, false, -1)])
	states.append(["key door open", _object_view(door, true, false, false, -1)])
	states.append(["lever door", _object_view(door, false, false, false, 0)])
	states.append(["lever door open", _object_view(door, true, false, false, 0)])
	states.append(["brazier lit", _object_view(brazier, false, false, true, -1)])
	states.append(["brazier out", _object_view(brazier, false, false, false, -1)])
	return states


func _staged_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for state: Array in _staged_object_views():
		names.append(state[0] as String)
	return names


func _object_view(
		kind: MapLayout.ObjectKind, is_open: bool, is_used: bool, is_lit: bool, group_id: int
) -> BoardViewModel.ObjectView:
	var shown: BoardViewModel.ObjectView = BoardViewModel.ObjectView.new()
	shown.id = "object:staged"
	shown.kind = kind
	shown.is_open = is_open
	shown.is_used = is_used
	shown.is_lit = is_lit
	shown.group_id = group_id
	return shown
