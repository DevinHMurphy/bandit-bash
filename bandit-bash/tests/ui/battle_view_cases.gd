# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_view_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## The battle board's cases for tests/ui/run_all.gd (combat UI plan, UI1 row): the view-model,
## the board built on the M1 map, a whole M1 battle's facts played through the session's
## playback, and the darkness overlay. No autoload is named or needed.
##
## [b]The battle:[/b] the Mercenary army ([method StartingArmy.build]) against the M1 pack on the
## greybox map, begun through [method CampaignSession.begin_battle] on the real catalog, as in
## [code]tests/enemies/m1_battle_cases.gd[/code], with a driver of the same shape: in the opening
## swap window it sends Start; each player unit attacks the first enemy it can hit from the first
## reachable tile (row-major), else walks to the reachable tile nearest an enemy and waits; then
## the seat ends its turn. After every command the board is stepped frame by frame until it
## settles, and it must then agree with the state.

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")

# Any fixed seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Floor 1 is step 1, whose enemies are level 1 (game-vision.md, Run structure).
const FLOOR: int = 1
const NODE: int = 1

# Player phases the battle may take: past what the M1 battle needs, so only a stall reaches it.
const MAX_PHASES: int = 40

# One frame at 30 frames per second: the board is stepped as the game steps it.
const FRAME: float = 1.0 / 30.0

# Frames a board may take to settle after one command: a minute of playback.
const MAX_SETTLE_FRAMES: int = 1800

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

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
	var map: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	if map == null:
		_check.call("board: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_view_model(map)
	_test_board_and_playback(map)
	_test_darkness_overlay(map)


## Begins the M1 battle for a new solo run; null, with the problem reported, when it can't.
static func begin_m1(
		catalog: EffectCatalog.Index, map: CombatMapDefinition, run: CampaignSession
) -> CombatEncounter:
	var mercenary: StartingArmy = StartingArmy.build(catalog, "mercenary", run.ids)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	army.heirloom_ids = mercenary.heirloom_ids
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = catalog
	request.armies[0] = army
	return run.begin_battle(request)


## Steps [param view] a frame at a time until it settles. Returns whether it did.
static func settle(view: BattleView) -> bool:
	for _frame: int in MAX_SETTLE_FRAMES:
		if view.is_settled():
			return true
		view.advance(FRAME)
	return view.is_settled()


func _test_view_model(map: CombatMapDefinition) -> void:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("view-model: the M1 battle begins", false, "begin_battle gave no battle")
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var model: BoardViewModel = BoardViewModel.build(session)
	var wrong: PackedStringArray = []
	var ids: PackedStringArray = []
	for view: BoardViewModel.UnitView in model.units:
		ids.append(view.id)
		var expected: Array = [
			state.side_of(view.id),
			state.seat_of(view.id),
			state.get_hp(view.id),
			session.stats(view.id).get_int(CombatValue.Key.HP),
			state.tile_of(view.id),
			state.unit_type_of(view.id).left(1).to_upper(),
		]
		var shown: Array = [view.side, view.seat, view.hp, view.max_hp, view.tile, view.letter]
		if shown != expected:
			wrong.append("%s %s, not %s" % [view.id, shown, expected])
	_check.call("view-model: one view per unit, in the state's order", (
			ids == state.unit_ids()
	), "%s / %s" % [ids, state.unit_ids()])
	_check.call("view-model: side, seat, HP, max HP, tile and letter match the state", (
			wrong.is_empty() and not model.units.is_empty()
	), "; ".join(wrong))
	var players: int = 0
	for view: BoardViewModel.UnitView in model.units:
		if view.side == PLAYER and view.seat == 0 and view.max_hp > 0 and view.hp == view.max_hp:
			players += 1
	_check.call("view-model: the four Mercenaries start on seat 0 at full HP", (
			players == 4
	), str(players))
	_check.call("view-model: an empty unit type shows ?", BoardViewModel.letter_of("") == "?")
	run.close()


func _test_board_and_playback(map: CombatMapDefinition) -> void:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("board: the M1 battle begins", false, "begin_battle gave no battle")
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)

	var sorted_ids: PackedStringArray = state.unit_ids()
	sorted_ids.sort()
	var step: Vector2 = (
			view.tile_to_position(Vector2i(1, 0)) - view.tile_to_position(Vector2i.ZERO)
	)
	_check.call("board: the M1 map is instanced, 32 px tiles", (
			step.is_equal_approx(Vector2(32.0, 0.0)) and view.map_rect().size.x > 0.0
	), "%s, %s" % [step, view.map_rect()])
	_check.call("board: one token per unit", view.token_ids() == sorted_ids, (
			"%s / %s" % [view.token_ids(), sorted_ids]
	))
	_check.call("board: every token on its unit's tile, at full HP", (
			view.mismatches().is_empty()
	), "; ".join(view.mismatches()))

	var played: Dictionary[int, int] = {}
	var on_played: Callable = func(fact: CombatFact) -> void:
		var count: int = played.get(fact.kind, 0)
		played[fact.kind] = count + 1
	session.bus.fact_played.connect(on_played)
	var result: Played = _play(battle, session, view)
	session.bus.fact_played.disconnect(on_played)

	_check.call("playback: the battle runs to its end with no rejected command", (
			session.is_finished and result.rejected.is_empty() and result.stalls.is_empty()
	), "finished %s after turn %d; rejected %s; stalls %s" % [
		session.is_finished, state.turn, result.rejected, result.stalls,
	])
	_check.call("playback: after every command the board agrees with the state", (
			result.disagreements.is_empty()
	), "; ".join(result.disagreements.slice(0, 3)))
	var defeated: PackedStringArray = []
	for unit_id: String in sorted_ids:
		if not state.has_unit(unit_id):
			defeated.append(unit_id)
	var leftover: PackedStringArray = []
	for unit_id: String in defeated:
		if view.token_of(unit_id) != null:
			leftover.append(unit_id)
	_check.call("playback: defeated units are gone from the board", (
			not defeated.is_empty() and leftover.is_empty()
	), "defeated %s, still shown %s" % [defeated, leftover])
	var survivors: PackedStringArray = state.unit_ids()
	survivors.sort()
	_check.call("playback: the survivors' tokens stand where the state says", (
			view.token_ids() == survivors and view.mismatches().is_empty()
	), "; ".join(view.mismatches()))
	var animated: Array[CombatFact.Kind] = [
		CombatFact.Kind.UNIT_MOVED,
		CombatFact.Kind.DAMAGE_TAKEN,
		CombatFact.Kind.DEFEATED,
		CombatFact.Kind.COMBAT_ENDED,
	]
	var missing: Array[String] = []
	for kind: CombatFact.Kind in animated:
		if played.get(kind, 0) == 0:
			missing.append(CombatFact.Kind.find_key(kind) as String)
	_check.call("playback: moves, damage, defeats and the end all played on the bus", (
			missing.is_empty()
	), "never played: %s" % [missing])
	view.free()
	run.close()


func _test_darkness_overlay(map: CombatMapDefinition) -> void:
	var run: CampaignSession = _new_run()
	var battle: CombatEncounter = begin_m1(_catalog, map, run)
	if battle == null:
		_check.call("darkness: the M1 battle begins", false, "begin_battle gave no battle")
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var view: BattleView = VIEW_SCENE.instantiate()
	_root.add_child(view)
	view.bind(session)
	var overlay: DarknessOverlay = view.get_darkness()
	_check.call("darkness: a dry map draws no tile", overlay.drawn_tiles().is_empty(), (
			str(overlay.drawn_tiles())
	))

	# A fixture state over the same grid: one tile of each layer.
	var fixture: CombatState = CombatState.new(session.state.grid)
	fixture.map.darkness.layers[Vector2i(0, 0)] = WhileLayerCondition.Layer.DUSK
	fixture.map.darkness.layers[Vector2i(1, 0)] = WhileLayerCondition.Layer.GLOOM
	fixture.map.darkness.layers[Vector2i(2, 0)] = WhileLayerCondition.Layer.ABYSS
	overlay.show_layers(BoardViewModel.darkness_of(fixture))
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	_check.call("darkness: each layer of a fixture state is drawn on its tile", (
			overlay.drawn_tiles() == expected
			and overlay.layer_at(Vector2i(0, 0)) == WhileLayerCondition.Layer.DUSK
			and overlay.layer_at(Vector2i(1, 0)) == WhileLayerCondition.Layer.GLOOM
			and overlay.layer_at(Vector2i(2, 0)) == WhileLayerCondition.Layer.ABYSS
			and overlay.layer_at(Vector2i(3, 0)) == WhileLayerCondition.Layer.DRY
	), str(overlay.drawn_tiles()))
	var dusk: Color = overlay.color_of(WhileLayerCondition.Layer.DUSK)
	var gloom: Color = overlay.color_of(WhileLayerCondition.Layer.GLOOM)
	var abyss: Color = overlay.color_of(WhileLayerCondition.Layer.ABYSS)
	_check.call("darkness: each layer draws at its own alpha, deeper darker", (
			is_equal_approx(dusk.a, overlay.dusk_alpha)
			and is_equal_approx(gloom.a, overlay.gloom_alpha)
			and is_equal_approx(abyss.a, overlay.abyss_alpha)
			and dusk.a < gloom.a
			and gloom.a < abyss.a
			and overlay.color_of(WhileLayerCondition.Layer.DRY).a == 0.0
	), "%s %s %s" % [dusk.a, gloom.a, abyss.a])

	# DARKNESS_ADVANCED reaches the board through playback and redraws its tile; a wave's release
	# (no tile) draws nothing.
	var deepened: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_ADVANCED)
	deepened.tile = Vector2i(4, 4)
	deepened.amount = WhileLayerCondition.Layer.GLOOM
	var released: CombatFact = CombatFact.new(CombatFact.Kind.DARKNESS_ADVANCED)
	var facts: Array[CombatFact] = [released, deepened]
	session.playback.enqueue(facts)
	var has_settled: bool = settle(view)
	_check.call("darkness: DARKNESS_ADVANCED played back redraws that tile only", (
			has_settled
			and overlay.layer_at(Vector2i(4, 4)) == WhileLayerCondition.Layer.GLOOM
			and overlay.drawn_tiles().size() == 4
	), str(overlay.drawn_tiles()))
	view.free()
	run.close()


func _new_run() -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))


# The driver (class doc), checking the board against the state each time it settles.
func _play(battle: CombatEncounter, session: CombatSession, view: BattleView) -> Played:
	var result: Played = Played.new()
	var state: CombatState = session.state
	if state.map.opening_swap_open:
		_send(battle, session, view, StartCommand.new(0), result)
	for _phase: int in MAX_PHASES:
		if session.is_finished:
			break
		for unit_id: String in state.units_of(PLAYER):
			if session.is_finished:
				break
			if not state.has_unit(unit_id) or state.unit(unit_id).has_acted:
				continue
			_send(battle, session, view, _turn_for(session, unit_id), result)
		if not session.is_finished:
			_send(battle, session, view, EndTurnCommand.new(0), result)
	return result


func _send(
		battle: CombatEncounter,
		session: CombatSession,
		view: BattleView,
		command: Command,
		result: Played
) -> void:
	battle.submit(command, session.session_id)
	for batch: CombatSession.FactBatch in battle.resolve_queued():
		if batch.is_rejected():
			result.rejected.append("%s: %s" % [batch.label, batch.rejected_reason])
	if not settle(view):
		result.stalls.append(command.get_label())
		return
	var found: PackedStringArray = view.mismatches()
	if not found.is_empty():
		result.disagreements.append("after %s: %s" % [command.get_label(), ", ".join(found)])


# The driver's turn for unit_id (class doc).
func _turn_for(session: CombatSession, unit_id: String) -> UnitTurnCommand:
	var state: CombatState = session.state
	var reach: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
	var ends: Array[Vector2i] = []
	ends.assign(reach.keys())
	ends.sort_custom(MapLayout.is_before)
	var foes: PackedStringArray = state.units_of(ENEMY)
	for tile: Vector2i in ends:
		for foe: String in foes:
			var walk: Array[Vector2i] = _walk_to(session, unit_id, tile)
			var attack: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, UnitTurnCommand.Action.ATTACK, foe, walk
			)
			if attack.validate(session).is_empty():
				return attack
	var goal: Vector2i = state.tile_of(unit_id)
	var nearest: int = -1
	for tile: Vector2i in ends:
		for foe: String in foes:
			var distance: int = state.grid.distance(tile, state.tile_of(foe))
			if nearest < 0 or distance < nearest:
				nearest = distance
				goal = tile
	return UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.WAIT, "", _walk_to(session, unit_id, goal)
	)


# A cheapest walk from unit_id's tile to tile (one of its reach), stepping back from tile through
# the flood's costs; empty for its own tile or when none is found.
static func _walk_to(session: CombatSession, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var state: CombatState = session.state
	var mover: CombatUnitState = state.unit(unit_id)
	var walk: Array[Vector2i] = []
	if tile == mover.tile:
		return walk
	var costs: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(session.engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	walk.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var before: Vector2i = CombatFact.NO_TILE
		for next: Vector2i in state.grid.neighbors(at):
			if costs.has(next) and costs[next] + entry == costs[at]:
				before = next
				break
		if before == CombatFact.NO_TILE:
			walk.clear()
			return walk
		walk.push_front(before)
		at = before
	return walk


## What one driven battle left to report.
class Played:
	extends RefCounted

	## Commands the session rejected, one line each.
	var rejected: PackedStringArray = []
	## Commands after which the board never settled.
	var stalls: PackedStringArray = []
	## Each settle at which the board disagreed with the state.
	var disagreements: PackedStringArray = []
