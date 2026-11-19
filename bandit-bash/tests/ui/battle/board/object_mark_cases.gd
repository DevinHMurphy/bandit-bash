# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     object_mark_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The map object marks' cases for the ui/board suite (BUG-013: doors and levers were never
## drawn): the Old Mill board marks every object that isn't a token, a lever and its doors share a
## tag, the tile panel names each one's state and link, and pulling either lever opens and closes
## the door on the board as in the state; the Hall's passage ends, brazier, chest and key-only
## door draw from its start state.
##
## [b]The battle:[/b] the Old Mill with the M1 pack, begun as the board cases begin M1
## ([method BattleViewCases.begin_m1]). After Start, two player units are put on the levers
## (state only, before the board is bound) so each can pull one with no walk.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const OLD_MILL: String = "res://maps/standard/old_mill.tres"
const HALL: String = "res://maps/key/hall.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const MARK_SCENE: PackedScene = preload("res://ui/battle/board/map_object_mark.tscn")

# Any fixed seed: no case compares golden numbers.
const SEED: int = 0x0B1ECD

# The Old Mill's door, its levers outside and inside the mill, and its stone debris (gen_maps.gd).
const MILL_DOOR: Vector2i = Vector2i(3, 4)
const OUTER_LEVER: Vector2i = Vector2i(5, 1)
const INNER_LEVER: Vector2i = Vector2i(2, 3)
const MILL_DEBRIS: Vector2i = Vector2i(8, 3)

# The Hall's passage ends, a brazier, its chest and its key-only door (gen_maps.gd).
const HALL_PASSAGE: Vector2i = Vector2i(0, 6)
const HALL_PASSAGE_END: Vector2i = Vector2i(11, 1)
const HALL_BRAZIER: Vector2i = Vector2i(4, 4)
const HALL_CHEST: Vector2i = Vector2i(1, 0)
const HALL_DOOR: Vector2i = Vector2i(2, 3)

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where boards are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_mill_board()
	_test_hall_marks()


func _test_mill_board() -> void:
	var map: CombatMapDefinition = load(OLD_MILL) as CombatMapDefinition
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = null
	if map != null:
		battle = BattleViewCases.begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("marks: the Old Mill battle begins", false, OLD_MILL)
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	if state.map.opening_swap_open:
		battle.submit(StartCommand.new(0), session.session_id)
		battle.resolve_queued()
	var players: PackedStringArray = state.units_of(CombatFact.CombatSide.PLAYER)
	state.move_unit(players[0], OUTER_LEVER)
	state.move_unit(players[1], INNER_LEVER)
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)

	var drawn: PackedStringArray = []
	for placed: MapState.ObjectState in state.map.objects.values():
		if BoardViewModel.is_drawn(placed.kind):
			drawn.append(placed.id)
	drawn.sort()
	_check.call("marks: one per object that isn't a breakable", (
			view.object_mark_ids() == drawn and drawn.size() == 4
	), "%s / %s" % [view.object_mark_ids(), drawn])
	var debris: MapState.ObjectState = _object_at(state, MILL_DEBRIS)
	_check.call("marks: the debris is a token, not a mark", (
			debris != null
			and view.object_mark_of(debris.id) == null
			and view.token_of(debris.id) != null
	))
	var door: MapObjectMark = view.object_mark_of(_object_at(state, MILL_DOOR).id)
	var outer: MapObjectMark = view.object_mark_of(_object_at(state, OUTER_LEVER).id)
	var inner: MapObjectMark = view.object_mark_of(_object_at(state, INNER_LEVER).id)
	_check.call("marks: the door shows closed and shares its levers' tag", (
			door.get_glyph_text() == door.closed_door_glyph
			and door.get_tag_text() == "A"
			and outer.get_tag_text() == "A"
			and inner.get_tag_text() == "A"
			and outer.get_glyph_text() == outer.lever_glyph
	), "door %s %s, levers %s %s" % [
		door.get_glyph_text(), door.get_tag_text(), outer.get_tag_text(), inner.get_tag_text(),
	])
	_check.call("marks: each mark sits on its tile", (
			door.position.is_equal_approx(view.tile_to_position(MILL_DOOR))
			and view.mismatches().is_empty()
	), "; ".join(view.mismatches()))
	_same_names("tile panel: a closed lever door", session, MILL_DOOR, ["Door (closed, lever A)"])
	_same_names(
			"tile panel: a lever names its doors",
			session,
			OUTER_LEVER,
			["Lever (opens and closes doors A)"]
	)

	_pull(battle, session, view, players[0], OUTER_LEVER)
	_check.call("marks: pulling the lever outside opens the door on the board", (
			door.get_glyph_text() == door.open_door_glyph
			and door.modulate.is_equal_approx(door.spent_modulate)
			and view.mismatches().is_empty()
	), "%s; %s" % [door.get_glyph_text(), "; ".join(view.mismatches())])
	_same_names("tile panel: the door is open", session, MILL_DOOR, ["Door (open, lever A)"])

	_pull(battle, session, view, players[1], INNER_LEVER)
	_check.call("marks: pulling the lever inside closes it again", (
			door.get_glyph_text() == door.closed_door_glyph
			and door.modulate.is_equal_approx(Color.WHITE)
			and view.mismatches().is_empty()
	), "%s; %s" % [door.get_glyph_text(), "; ".join(view.mismatches())])
	view.free()
	run.close()


# The Hall from its start state: no battle, as its leader slot waits for its mini-boss (EN8).
func _test_hall_marks() -> void:
	var map: CombatMapDefinition = load(HALL) as CombatMapDefinition
	var layout: MapLayout = null if map == null else MapLoader.load_layout(map)
	if layout == null:
		_check.call("marks: the Hall loads", false, HALL)
		return
	var state: CombatState = DarknessSetup.start_state(layout)
	var views: Dictionary[Vector2i, BoardViewModel.ObjectView] = {}
	for object_view: BoardViewModel.ObjectView in BoardViewModel.objects_of(state):
		views[object_view.tile] = object_view
	var passage: BoardViewModel.ObjectView = views.get(HALL_PASSAGE, null)
	var far_end: BoardViewModel.ObjectView = views.get(HALL_PASSAGE_END, null)
	_check.call("marks: a passage's ends share a number and know each other", (
			passage != null
			and far_end != null
			and passage.tag == "1"
			and far_end.tag == "1"
			and passage.other_end == HALL_PASSAGE_END
			and far_end.other_end == HALL_PASSAGE
	))
	_check.call("tile panel: a passage says where it leads", (
			BoardViewModel.object_note(state, _object_at(state, HALL_PASSAGE)) == "1, to (11, 1)"
	), BoardViewModel.object_note(state, _object_at(state, HALL_PASSAGE)))
	_check.call("tile panel: a key-only door says it needs a key", (
			BoardViewModel.object_note(state, _object_at(state, HALL_DOOR)) == "locked, needs a key"
			and views.has(HALL_DOOR)
			and views[HALL_DOOR].tag.is_empty()
	))

	var expected: Dictionary[Vector2i, Array] = {
		HALL_PASSAGE: ["passage_glyph", false],
		HALL_BRAZIER: ["brazier_glyph", true],
		HALL_CHEST: ["chest_glyph", false],
		HALL_DOOR: ["closed_door_glyph", false],
	}
	var wrong: PackedStringArray = []
	for tile: Vector2i in expected:
		var mark: MapObjectMark = MARK_SCENE.instantiate()
		_root.add_child(mark)
		mark.show_object(views[tile], Vector2.ZERO)
		var glyph: String = mark.get(expected[tile][0] as String)
		var is_spent: bool = expected[tile][1]
		var tint: Color = mark.spent_modulate if is_spent else Color.WHITE
		if mark.get_glyph_text() != glyph or not mark.modulate.is_equal_approx(tint):
			wrong.append("%s: %s, %s" % [tile, mark.get_glyph_text(), mark.modulate])
		if mark.get_tag_text() != views[tile].tag:
			wrong.append("%s: tag %s" % [tile, mark.get_tag_text()])
		mark.free()
	_check.call("marks: each kind's glyph, an unlit brazier dimmed", wrong.is_empty(), (
			"; ".join(wrong)
	))


# unit_id, standing on the lever at tile, pulls it; then the board settles.
func _pull(
		battle: CombatEncounter,
		session: CombatSession,
		view: BattleView,
		unit_id: String,
		tile: Vector2i
) -> void:
	var lever: MapState.ObjectState = _object_at(session.state, tile)
	var command: UnitTurnCommand = UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.USE_OBJECT, lever.id
	)
	battle.submit(command, session.session_id)
	var rejected: PackedStringArray = []
	for batch: CombatSession.FactBatch in battle.resolve_queued():
		if batch.is_rejected():
			rejected.append(batch.rejected_reason)
	_check.call("marks: the lever at %s is pulled and the board settles" % [tile], (
			rejected.is_empty() and BattleViewCases.settle(view)
	), ", ".join(rejected))


func _same_names(
		case_name: String, session: CombatSession, tile: Vector2i, expected: PackedStringArray
) -> void:
	var names: PackedStringArray = HudViewModel.tile_view(session, tile).object_names
	_check.call(case_name, names == expected, "%s" % [names])


# The object on tile of state; null for none.
static func _object_at(state: CombatState, tile: Vector2i) -> MapState.ObjectState:
	var found: Array[MapState.ObjectState] = state.map.objects_at(tile)
	return null if found.is_empty() else found[0]
