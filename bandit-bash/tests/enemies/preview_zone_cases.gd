# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     preview_zone_cases.gd
# Author:
# Created:  November 21, 2026
# Modified: November 25, 2026
# ==============================================================================

extends RefCounted
## The move preview's bounded zones and incremental danger zone (move-preview.md, layers 3 and 4).
## [b]Bounds:[/b] for each reading a decision's [EnemyAI.Footprint] keeps (the walk and its
## reach, an advance's nearer foe and routes, a Hound's pack, a Stonelet's routes to its
## ally, the whole-map flood of an enemy that waits, the player units' threats), a tile just
## inside the bound can change the decision and a tile just outside can't; then the same moves
## previewed: the one outside keeps the decision, the one inside decides again, and both equal a
## full re-plan. These use the loadout fixture tree's classes and hand-built player units, which
## carry no effect, so the effect margin is 0 and each bound is exact.
## [b]Behaviors:[/b] Guard, Skirmisher, the Stonelet, the mini-bosses and the Powder Baron, on
## the real catalog: every tile two player units can end on, previewed in checking mode, equals a
## full re-plan, and some previews keep decisions.
## [b]Danger zone:[/b] on every benchmark board, seeded random moves give the danger zone a full
## rebuild gives. Reports each case through the check callable it is given.
##
## @tutorial(The move preview): docs/design/move-preview.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/preview"

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")
const BenchBoards = preload("res://tests/bench/bench_boards.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")
const PreviewEqualityCases = preload("res://tests/enemies/preview_equality_cases.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

const BRUTE: String = "loadout_brute"
const CROSSBOWMAN: String = "loadout_crossbowman"
const HEALER: String = "loadout_hedge_healer"

# The real catalog's classes each behavior case fields, with the ally it needs ("" for none):
# a Stonelet and a Stone Golem guard a ranged ally.
const BEHAVIORS: Dictionary[String, String] = {
	"duelist": "",
	"stonelet": "crossbowman",
	"hexer": "",
	"raider": "",
	"bloodhound": "brute",
	"brigand_captain": "",
	"hex_matron": "",
	"stone_golem": "crossbowman",
	"powder_baron": "",
}

# The behavior boards' size, and the enemy phases played first, so cooldowns (the mini-bosses'
# signature moves, the Powder Baron's barrage) can fire at the crossing a preview makes.
const BEHAVIOR_WIDTH: int = 16
const BEHAVIOR_HEIGHT: int = 9
const BEHAVIOR_TURNS: int = 1

# Random moves per benchmark board for the danger zone, and the seed of the first board's.
const DANGER_MOVES: int = 10
const DANGER_SEED: int = 1521

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null
var _fixtures: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()
	_fixtures = EffectCatalog.load_tree(LoadoutCases.TREE)


## Runs every case. Checking mode is a static switch, so it is restored before returning.
func run() -> void:
	var was_checking: bool = Intents.is_checking
	_test_walk_bound()
	_test_advance_nearer_foe_bound()
	_test_advance_route_bound()
	_test_pack_bound()
	_test_stonelet_route_bound()
	_test_far_bound()
	_test_threat_bound()
	_test_behaviors()
	_test_danger_zone_on_bench_boards()
	Intents.is_checking = was_checking


# An attacking Brute reads the units within its weapon's range of every tile it can walk
# through: a unit one tile past its walk can change it, two tiles past can't (margin 0), and a
# margin of 1 widens the bound by one.
func _test_walk_bound() -> void:
	var walk: int = _budget(_fixtures, BRUTE)
	var at: Vector2i = Vector2i(walk + 4, 4)
	var world: AiWorld = AiWorld.new(_fixtures, _plain(at.x + 4, 9))
	world.add_enemy("e1", BRUTE, at)
	world.add_player("p1", at + Vector2i(2, 0))
	world.add_player("p_far", Vector2i(0, 4))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _fixtures, "e1", {}, [], null, footprint)
	var inside: Vector2i = Vector2i(3, 4)
	var outside: Vector2i = Vector2i(2, 4)
	_check.call("zone bounds: an attack reads one tile past its walk, not two", (
			plan.kind == EnemyPlan.Kind.ATTACK
			and footprint.can_change(inside, 0)
			and not footprint.can_change(outside, 0)
			and footprint.can_change(outside, 1)
	), "plan %s; inside %s, outside %s, outside with margin 1 %s" % [
		EnemyPlan.Kind.find_key(plan.kind), footprint.can_change(inside, 0),
		footprint.can_change(outside, 0), footprint.can_change(outside, 1),
	])
	_open(world, _fixtures)
	_preview_pair("attack's walk", world, "p_far", outside, inside)


# A Brute advancing on p1, its nearest tile to attack from costing C: a unit within C plus its
# range of the Brute (behind it here) could be as near, one farther can't.
func _test_advance_nearer_foe_bound() -> void:
	var walk: int = _budget(_fixtures, BRUTE)
	var gap: int = walk + 3
	var at: Vector2i = Vector2i(gap + 3, 2)
	var world: AiWorld = AiWorld.new(_fixtures, _plain(2 * gap + 6, 5))
	world.add_enemy("e1", BRUTE, at)
	world.add_player("p1", at + Vector2i(gap, 0))
	world.add_player("p_far", Vector2i(0, 2))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _fixtures, "e1", {}, [], null, footprint)
	var inside: Vector2i = at - Vector2i(gap, 0)
	var outside: Vector2i = inside - Vector2i(1, 0)
	_check.call("zone bounds: an advance reads a foe as near as its own, not one tile farther", (
			_is_advance_on(plan, "p1")
			and footprint.can_change(inside, 0)
			and not footprint.can_change(outside, 0)
	), "plan %s on %s; inside %s, outside %s" % [
		EnemyPlan.Kind.find_key(plan.kind), plan.target_id, footprint.can_change(inside, 0),
		footprint.can_change(outside, 0),
	])
	_open(world, _fixtures)
	_preview_pair("advance's nearer foe", world, "p_far", outside, inside)


# The same advance reads every route from an end tile to p1's stand tiles that costs no more than
# the one it has: the stand tile above p1 lies on a cheapest route from an end tile, the one past
# p1 on none.
func _test_advance_route_bound() -> void:
	var walk: int = _budget(_fixtures, BRUTE)
	var gap: int = walk + 3
	var at: Vector2i = Vector2i(gap + 3, 2)
	var target: Vector2i = at + Vector2i(gap, 0)
	var world: AiWorld = AiWorld.new(_fixtures, _plain(2 * gap + 8, 5))
	world.add_enemy("e1", BRUTE, at)
	world.add_player("p1", target)
	world.add_player("p_far", target + Vector2i(3, 0))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _fixtures, "e1", {}, [], null, footprint)
	var inside: Vector2i = target + Vector2i(0, -1)
	var outside: Vector2i = target + Vector2i(1, 0)
	_check.call("zone bounds: an advance reads its cheapest routes, not a tile past its foe", (
			_is_advance_on(plan, "p1")
			and footprint.can_change(inside, 0)
			and not footprint.can_change(outside, 0)
	), "plan %s on %s; inside %s, outside %s" % [
		EnemyPlan.Kind.find_key(plan.kind), plan.target_id, footprint.can_change(inside, 0),
		footprint.can_change(outside, 0),
	])
	_open(world, _fixtures)
	_preview_pair("advance's routes", world, "p_far", outside, inside)


# A Hound advances on the foe nearest its pack: a unit as near the pack as p1 could take its
# place, one tile farther can't (the real catalog's Hound; the bound reads no margin).
func _test_pack_bound() -> void:
	var walk: int = _budget(_catalog, "hound")
	var gap: int = walk + 4
	var behind: int = 3
	var pack: int = gap + behind
	var at: Vector2i = Vector2i(pack + behind + 1, 2)
	var world: AiWorld = AiWorld.new(_catalog, _plain(at.x + gap + 2, 5))
	world.add_enemy("e1", "hound", at)
	world.add_enemy("e2", "hound", at - Vector2i(behind, 0))
	world.add_player("p1", at + Vector2i(gap, 0))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _catalog, "e1", {}, [], null, footprint)
	var inside: Vector2i = at - Vector2i(behind + pack, 0)
	var outside: Vector2i = inside - Vector2i(1, 0)
	_check.call("zone bounds: a Hound reads a foe as near its pack as its own, not one farther", (
			_is_advance_on(plan, "p1")
			and footprint.can_change(inside, 0)
			and not footprint.can_change(outside, 0)
	), "plan %s on %s; inside %s, outside %s" % [
		EnemyPlan.Kind.find_key(plan.kind), plan.target_id, footprint.can_change(inside, 0),
		footprint.can_change(outside, 0),
	])


# A Stonelet out of reach of a post beside its Crossbowman ends where the least movement is
# left to one: the stand tile on its side of the Crossbowman lies on a cheapest route, the one past
# it on none. Then a move far from both keeps both decisions: the Stonelet is not re-planned.
func _test_stonelet_route_bound() -> void:
	var walk: int = _budget(_catalog, "stonelet")
	var gap: int = walk + 4
	var at: Vector2i = Vector2i(8, 4)
	var ally: Vector2i = at + Vector2i(gap, 0)
	var world: AiWorld = AiWorld.new(_catalog, _plain(ally.x + 6, 9))
	world.add_enemy("e1", "stonelet", at)
	world.add_enemy("e2", "crossbowman", ally)
	world.add_player("p2", ally + Vector2i(3, 0))
	world.add_player("p_far", Vector2i(0, 8))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _catalog, "e1", {}, [], null, footprint)
	var inside: Vector2i = ally - Vector2i(1, 0)
	var outside: Vector2i = ally + Vector2i(1, 0)
	_check.call("zone bounds: a Stonelet reads its cheapest routes to its ally, no others", (
			plan.kind == EnemyPlan.Kind.REGROUP
			and footprint.can_change(inside, 0)
			and not footprint.can_change(outside, 0)
	), "plan %s; inside %s, outside %s" % [
		EnemyPlan.Kind.find_key(plan.kind), footprint.can_change(inside, 0),
		footprint.can_change(outside, 0),
	])
	_open(world, _catalog)
	var far: Vector2i = Vector2i(1, 8)
	_preview_case(
			"zone previews: a move far from a Stonelet and its ally keeps both",
			world, "p_far", far, true
	)


# A Crossbowman shut in a corridor has no foe it can reach and waits: a unit within its range of
# the corridor could become one, one tile farther can't.
func _test_far_bound() -> void:
	var span: Vector2i = _range(_fixtures, CROSSBOWMAN)
	var width: int = 18
	var rows: Array[String] = [_row("wall", width)]
	rows.append("wall " + _row("plain", width - 2) + " wall")
	rows.append(_row("wall", width))
	for _y: int in span.y + 3:
		rows.append(_row("plain", width))
	var world: AiWorld = AiWorld.new(_fixtures, rows)
	world.add_enemy("e1", CROSSBOWMAN, Vector2i(1, 1))
	world.add_player("p_far", Vector2i(14, span.y + 3))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _fixtures, "e1", {}, [], null, footprint)
	var inside: Vector2i = Vector2i(14, 1 + span.y)
	var outside: Vector2i = inside + Vector2i(0, 1)
	_check.call("zone bounds: a shut-in enemy's wait reads its range of its whole flood, no more", (
			plan.kind == EnemyPlan.Kind.WAIT
			and footprint.can_change(inside, 0)
			and not footprint.can_change(outside, 0)
	), "plan %s; inside %s, outside %s" % [
		EnemyPlan.Kind.find_key(plan.kind), footprint.can_change(inside, 0),
		footprint.can_change(outside, 0),
	])
	_open(world, _fixtures)
	_preview_pair("a shut-in wait", world, "p_far", outside, inside)


# A Hedge Healer with nobody to heal counts the player units that could attack each end tile: a
# moved unit's movement plus range reaching an end tile can change it, one tile short can't; and
# another unit's MOVEMENT changing changes it wherever that unit stands.
func _test_threat_bound() -> void:
	var walk: int = _budget(_fixtures, HEALER)
	var at: Vector2i = Vector2i(3, 4)
	var edge: int = at.x + walk
	var reach: int = int(AiWorld.PLAYER_BASES[CombatValue.Key.MOVEMENT]) + 1
	var start: Vector2i = Vector2i(edge + reach + 2, 4)
	var world: AiWorld = AiWorld.new(_fixtures, _plain(start.x + 2, 9))
	world.add_enemy("e1", HEALER, at)
	world.add_player("p_far", start)
	world.add_player("p2", Vector2i(start.x, 8))
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), _fixtures, "e1", {}, [], null, footprint)
	var inside: Vector2i = Vector2i(edge + reach, 4)
	var outside: Vector2i = inside + Vector2i(1, 0)
	var at_inside: EffectEngine = _walked(world, "p_far", inside)
	var at_outside: EffectEngine = _walked(world, "p_far", outside)
	var faster: EffectEngine = _walked(world, "p_far", outside)
	faster.stats("p2").set_base(CombatValue.Key.MOVEMENT, reach + 1.0)
	var to_inside: Array[Vector2i] = [start, inside]
	var to_outside: Array[Vector2i] = [start, outside]
	_check.call("zone bounds: threats read a moved unit's movement plus range, and stats", (
			plan.kind == EnemyPlan.Kind.REGROUP
			and footprint.threat_changed(at_inside, to_inside, "p_far")
			and not footprint.threat_changed(at_outside, to_outside, "p_far")
			and footprint.threat_changed(faster, to_outside, "p_far")
	), "plan %s; inside %s, outside %s, another faster %s" % [
		EnemyPlan.Kind.find_key(plan.kind),
		footprint.threat_changed(at_inside, to_inside, "p_far"),
		footprint.threat_changed(at_outside, to_outside, "p_far"),
		footprint.threat_changed(faster, to_outside, "p_far"),
	])
	_open(world, _fixtures)
	_preview_pair("threats", world, "p_far", outside, inside)
	_test_threat_left_bound(inside)
	_test_threat_left_bound(outside)


# The same Hedge Healer, with the moved unit starting on start (just inside or just outside the
# bound of _test_threat_bound) and walking two tiles away: leaving start can change the threat
# counts only if its movement plus range reached an end tile from there.
func _test_threat_left_bound(start: Vector2i) -> void:
	var walk: int = _budget(_fixtures, HEALER)
	var at: Vector2i = Vector2i(3, 4)
	var reach: int = int(AiWorld.PLAYER_BASES[CombatValue.Key.MOVEMENT]) + 1
	var is_inside: bool = start.x - (at.x + walk) <= reach
	var away: Vector2i = start + Vector2i(2, 0)
	var world: AiWorld = AiWorld.new(_fixtures, _plain(away.x + 2, 9))
	world.add_enemy("e1", HEALER, at)
	world.add_player("p_far", start)
	var footprint: EnemyAI.Footprint = EnemyAI.Footprint.new()
	EnemyAI.decide(world.engine(), _fixtures, "e1", {}, [], null, footprint)
	var moved: EffectEngine = _walked(world, "p_far", away)
	var tiles: Array[Vector2i] = [start, away]
	var changed: bool = footprint.threat_changed(moved, tiles, "p_far")
	_check.call("zone bounds: threats read where a moved unit stood, %s the bound" % [
		"just inside" if is_inside else "just outside",
	], changed == is_inside, "from %s: changed %s" % [start, changed])


# Each behavior on the real catalog: every tile p2 (mid-board) and p3 (far) can end on, previewed
# in checking mode, equals a full re-plan; checking mode finds nothing; some previews keep
# decisions.
func _test_behaviors() -> void:
	for class_id: String in BEHAVIORS:
		var world: AiWorld = AiWorld.new(_catalog, _plain(BEHAVIOR_WIDTH, BEHAVIOR_HEIGHT))
		world.add_enemy("e1", class_id, Vector2i(12, 4))
		var partner: String = BEHAVIORS[class_id]
		if not partner.is_empty():
			world.add_enemy("e2", partner, Vector2i(14, 6))
		world.add_player("p1", Vector2i(9, 4))
		world.add_player("p2", Vector2i(5, 2), "bow")
		world.add_player("p3", Vector2i(1, 7))
		_open(world, _catalog)
		for _turn: int in BEHAVIOR_TURNS:
			_end_turn(world)
		var session: CombatSession = world.session
		if session.is_finished or session.intents == null:
			_check.call("zone behaviors: %s has a player phase" % [class_id], false, (
					"finished %s" % [session.is_finished]
			))
			continue
		var tiles: int = 0
		var kept: int = 0
		var mismatch: String = ""
		var flagged: String = ""
		Intents.is_checking = true
		for mover: String in ["p2", "p3"]:
			if not session.state.has_unit(mover) or session.state.unit(mover).has_acted:
				continue
			var walker: EnemyAI.Board = EnemyAI.Board.new(session.engine, mover, {})
			for tile: Vector2i in walker.reach:
				tiles += 1
				var preview: Intents = Intents.preview(session, mover, tile)
				var full: Intents = PreviewEqualityCases.full_replan(
						session, _catalog, mover, walker.path_to(tile)
				)
				var seen: String = PreviewEqualityCases.intents_text(preview)
				var expected: String = PreviewEqualityCases.intents_text(full)
				if mismatch.is_empty() and seen != expected:
					mismatch = "%s to %s: preview %s / full %s" % [mover, tile, seen, expected]
				if preview == null or full == null:
					continue
				kept += maxi(0, full.decisions - preview.decisions)
				var flags: String = PreviewEqualityCases.check_lines(preview)
				if flagged.is_empty() and not flags.is_empty():
					flagged = "%s to %s: %s" % [mover, tile, flags]
		Intents.is_checking = false
		_check.call("zone behaviors: %s, %d previews equal a full re-plan, checking finds none" % [
			class_id, tiles,
		], tiles > 0 and mismatch.is_empty() and flagged.is_empty(), mismatch + flagged)
		_check.call("zone behaviors: %s, previews keep decisions" % [class_id], kept > 0, (
				"%d kept over %d previews" % [kept, tiles]
		))


# On every benchmark board, DANGER_MOVES seeded random moves of acting units: the preview's
# danger zone, built from the latest one, equals a full rebuild on the moved board, each enemy's
# tiles and the combined tiles in the same order.
func _test_danger_zone_on_bench_boards() -> void:
	var boards: BenchBoards = BenchBoards.new(_catalog)
	boards.is_verbose = false
	for index: int in BenchBoards.BOARDS.size():
		var board: String = BenchBoards.BOARDS[index]
		var session: CombatSession = boards.build(board)
		if session == null or not boards.is_intended(board, session):
			_check.call("danger zone: %s is built" % [board], false, ", ".join(boards.failures))
			continue
		var stream: RngStream = RngStream.new(DANGER_SEED + index)
		var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
		var moves: int = 0
		var mismatch: String = ""
		for _move: int in DANGER_MOVES:
			var unit_id: String = units[stream.pick_index(units.size())]
			var tiles: Array[Vector2i] = TurnInputModel.move_tiles(session, unit_id)
			var tile: Vector2i = tiles[stream.pick_index(tiles.size())]
			var preview: Intents = Intents.preview(session, unit_id, tile)
			if preview == null:
				continue
			moves += 1
			var full: DangerZone = DangerZone.compute(_walked(null, unit_id, tile, session))
			var seen: String = _danger_text(preview.danger)
			var expected: String = _danger_text(full)
			if mismatch.is_empty() and seen != expected:
				mismatch = "%s to %s: preview %s / full %s" % [unit_id, tile, seen, expected]
		_check.call("danger zone: %s, %d random moves equal a full rebuild" % [board, moves], (
				moves > 0 and mismatch.is_empty()
		), mismatch)
	boards.close()


# Previews mover to outside, which must keep every decision, and to inside, which must decide
# again; both equal a full re-plan, in checking mode.
func _preview_pair(
		label: String, world: AiWorld, mover: String, outside: Vector2i, inside: Vector2i
) -> void:
	_preview_case(
			"zone previews: %s, a move just outside keeps the decision" % [label],
			world, mover, outside, true
	)
	_preview_case(
			"zone previews: %s, a move just inside decides again" % [label],
			world, mover, inside, false
	)


# Previews mover to tile on world in checking mode: whether it kept every decision (made none) is
# expect_kept, it equals a full re-plan, and checking mode finds nothing.
func _preview_case(
		case_name: String, world: AiWorld, mover: String, tile: Vector2i, expect_kept: bool
) -> void:
	var session: CombatSession = world.session
	Intents.is_checking = true
	var preview: Intents = Intents.preview(session, mover, tile)
	var path: Array[Vector2i] = EnemyAI.Board.new(session.engine, mover, {}).path_to(tile)
	var full: Intents = PreviewEqualityCases.full_replan(session, world.catalog, mover, path)
	Intents.is_checking = false
	var seen: String = PreviewEqualityCases.intents_text(preview)
	var expected: String = PreviewEqualityCases.intents_text(full)
	var flags: String = "" if preview == null else PreviewEqualityCases.check_lines(preview)
	var kept: bool = preview != null and preview.decisions == 0
	_check.call(case_name, (
			preview != null
			and session.intents != null
			and session.intents.decisions > 0
			and kept == expect_kept
			and seen == expected
			and flags.is_empty()
	), "decisions %d; flags %s; preview %s / full %s" % [
		-1 if preview == null else preview.decisions, flags, seen, expected,
	])


# A sandbox of world's session (or session) with unit_id walked to tile, verify mode off.
func _walked(
		world: AiWorld, unit_id: String, tile: Vector2i, session: CombatSession = null
) -> EffectEngine:
	var from: CombatSession = session if session != null else world.session
	var path: Array[Vector2i] = EnemyAI.Board.new(from.engine, unit_id, {}).path_to(tile)
	var engine: EffectEngine = Sandbox.new(from.engine, ForecastRolls.new()).engine
	engine.verify = false
	var state: CombatState = engine.state
	if not path.is_empty():
		engine.begin_step()
		UnitTurnCommand.walk_path(engine, state, unit_id, path)
		engine.drain()
	return engine


# zone's combined tiles in its own order, each with its enemies, then each enemy's tiles.
func _danger_text(zone: DangerZone) -> String:
	if zone == null:
		return "null"
	var parts: PackedStringArray = []
	for tile: Vector2i in zone.combined:
		parts.append("%s:%s" % [tile, ",".join(zone.combined[tile])])
	for enemy_id: String in zone.enemy_ids:
		parts.append("%s=%s" % [enemy_id, zone.tiles_of(enemy_id)])
	return " ".join(parts)


# Whether plan advances on target_id.
func _is_advance_on(plan: EnemyPlan, target_id: String) -> bool:
	return plan.kind == EnemyPlan.Kind.ADVANCE and plan.target_id == target_id


# The movement an enemy of class_id from catalog has on a turn, read from a world of its own.
func _budget(catalog: EffectCatalog.Index, class_id: String) -> int:
	var world: AiWorld = AiWorld.new(catalog, _plain(3, 3))
	world.add_enemy("e1", class_id, Vector2i(1, 1))
	return Pathing.budget_of(world.engine(), world.state(), "e1")


# The range of the weapon an enemy of class_id from catalog starts with.
func _range(catalog: EffectCatalog.Index, class_id: String) -> Vector2i:
	var world: AiWorld = AiWorld.new(catalog, _plain(3, 3))
	world.add_enemy("e1", class_id, Vector2i(1, 1))
	return ExchangeResolver.weapon_range(
			world.engine(), "e1", world.state().equipped_weapon_id("e1")
	)


func _open(world: AiWorld, catalog: EffectCatalog.Index) -> void:
	EnemyAI.register(world.session, catalog)
	Intents.register(world.session, catalog)
	world.session.open_battle()


func _end_turn(world: AiWorld) -> void:
	if world.session.is_finished:
		return
	world.session.submit(EndTurnCommand.new(0))
	world.session.resolve_next()


func _plain(width: int, height: int) -> Array[String]:
	var rows: Array[String] = []
	for _y: int in height:
		rows.append(_row("plain", width))
	return rows


func _row(terrain_id: String, width: int) -> String:
	var tiles: PackedStringArray = []
	for _x: int in width:
		tiles.append(terrain_id)
	return " ".join(tiles)
