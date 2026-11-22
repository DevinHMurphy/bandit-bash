# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     preview_sweep_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The move preview's sweep (move-preview.md, layer 5) through [MovePreview.Queue], on the M1 turn
## 1 benchmark board: the order (the sweep order's units in turn, each unit's tiles nearest
## first), a hover on a tile not yet done running next, a hover on a done tile returned at once
## with no preview started, a fact dropping the done previews and restarting the sweep in the
## same frame, a preview asked on an older board ignored when it finishes, another session never
## served, no sweep without the worker, and swept previews equal to a full re-plan in checking
## mode. Reports each case through the check callable it is given.
##
## @tutorial(The move preview): docs/design/move-preview.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/preview"

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const BenchBoards = preload("res://tests/bench/bench_boards.gd")
const PreviewEqualityCases = preload("res://tests/enemies/preview_equality_cases.gd")

const BOARD: String = "m1_turn_1"

# Frames the order case follows: every tile of the first unit and this many of the second's.
const SECOND_UNIT_TILES: int = 3

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null
var _boards: BenchBoards = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case. Checking mode is a static switch, so it is restored before returning.
func run() -> void:
	var was_checking: bool = Intents.is_checking
	_boards = BenchBoards.new(_catalog)
	_boards.is_verbose = false
	_test_order_and_lookup()
	_test_jump_to_front()
	_test_fact_restarts()
	_test_late_job_ignored()
	_test_other_session()
	_test_unthreaded()
	_test_checking()
	_boards.close()
	Intents.is_checking = was_checking


# The sweep of two units, the second named first: its tiles first, nearest by walking cost, ties
# in row-major order, then the other's; then a hover on each done tile returns that preview in
# one call and starts none.
func _test_order_and_lookup() -> void:
	var session: CombatSession = _session("order")
	if session == null:
		return
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var order: PackedStringArray = [units[1], units[0]]
	var expected: Array[String] = []
	for tile: Vector2i in _nearest_first(session, order[0]):
		expected.append(_name_of(order[0], tile))
	var second: Array[Vector2i] = _nearest_first(session, order[1])
	for index: int in mini(SECOND_UNIT_TILES, second.size()):
		expected.append(_name_of(order[1], second[index]))
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var seen: Array[String] = _sweep_steps(queue, session, order, expected.size())
	_check.call("sweep: the first unit's tiles nearest first, then the next unit's", (
			seen == expected
	), "seen %s / expected %s" % [seen, expected])

	var runs: int = queue.runs
	var missed: PackedStringArray = []
	for tile: Vector2i in _nearest_first(session, order[0]):
		queue.request(order[0], tile)
		var ready: MovePreview = queue.run_pending(session)
		if ready == null or ready.tile != tile or ready.unit_id != order[0]:
			missed.append(str(tile))
		queue.clear()
	_check.call("sweep: a hover on a done tile is returned in one call, starting no preview", (
			missed.is_empty() and queue.runs == runs
	), "missed %s; previews started %d" % [missed, queue.runs - runs])
	var tile_done: Vector2i = second[0]
	queue.request(order[1], tile_done)
	var kept: MovePreview = queue.run_pending(session)
	var fresh: MovePreview = MovePreview.compute(session, order[1], tile_done)
	_check.call("sweep: a done preview equals one computed afresh", (
			kept != null
			and kept.intents != null
			and PreviewEqualityCases.intents_text(kept.intents)
			== PreviewEqualityCases.intents_text(fresh.intents)
			and kept.changed_enemies == fresh.changed_enemies
			and kept.darkness_damage == fresh.darkness_damage
	))
	queue.wait()


# Mid-sweep, a hover on the last unit's farthest tile runs as soon as the preview running ends:
# the next run_pending after it starts the hover's, and the one after returns it.
func _test_jump_to_front() -> void:
	var session: CombatSession = _session("jump")
	if session == null:
		return
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	_sweep_steps(queue, session, units, 2)
	var last: String = units[units.size() - 1]
	var far: Array[Vector2i] = _nearest_first(session, last)
	var tile: Vector2i = far[far.size() - 1]
	var swept: int = queue.swept
	queue.request(last, tile)
	var first: MovePreview = queue.run_pending(session, units)
	# The hover's preview started, not the sweep's next: the sweep goes on once it returns.
	var swept_then: int = queue.swept
	queue.wait()
	var second: MovePreview = queue.run_pending(session, units)
	_check.call("sweep: a hover on a tile not yet done jumps to the front", (
			first == null
			and second != null
			and second.unit_id == last
			and second.tile == tile
			and swept_then == swept
			and queue.swept == swept + 1
	), "first %s, second %s, swept %d -> %d -> %d" % [
		first != null, second.tile if second != null else CombatFact.NO_TILE, swept, swept_then,
		queue.swept,
	])
	queue.wait()


# A fact drops every done preview, and the same run_pending starts the sweep again on the new
# board, skipping the unit that acted.
func _test_fact_restarts() -> void:
	var session: CombatSession = _session("fact")
	if session == null:
		return
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var done: Array[String] = _sweep_steps(queue, session, units, 3)
	var origin: Vector2i = session.state.tile_of(units[1])
	if not _wait_on(session, units[0]):
		return
	var still_done: bool = queue.is_done(session, units[1], origin)
	var swept: int = queue.swept
	queue.run_pending(session, units)
	var restarted: bool = queue.swept == swept + 1
	queue.wait()
	queue.run_pending(session, units)
	var first_again: bool = queue.is_done(session, units[1], origin)
	_check.call("sweep: a fact drops the done previews and the sweep restarts at once", (
			done.size() == 3 and not still_done and restarted and first_again
	), "done %d, still done %s, restarted %s, the next unit's own tile first %s" % [
		done.size(), still_done, restarted, first_again,
	])
	queue.wait()


# A preview asked before a fact is ignored when it finishes after it: a sweep's isn't kept, and a
# hover's is asked again on the new board, which returns it.
func _test_late_job_ignored() -> void:
	var session: CombatSession = _session("late")
	if session == null:
		return
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var hovered: Vector2i = _nearest_first(session, units[1])[1]
	queue.request(units[1], hovered)
	queue.run_pending(session, units)
	if not _wait_on(session, units[0]):
		return
	queue.wait()
	var late: MovePreview = queue.run_pending(session, units)
	var is_ignored: bool = late == null and not queue.is_done(session, units[1], hovered)
	queue.wait()
	var again: MovePreview = queue.run_pending(session, units)
	_check.call("sweep: a preview finishing after a fact is ignored, the hover asked again", (
			is_ignored
			and again != null
			and again.tile == hovered
			and again.based_on_seq == session.last_seq()
	), "ignored %s, again %s" % [is_ignored, again != null])
	queue.wait()


# Done previews belong to their session: another session at the same seq is never served them.
func _test_other_session() -> void:
	var session: CombatSession = _session("first session")
	var other: CombatSession = _session("second session")
	if session == null or other == null:
		return
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var done: Array[String] = _sweep_steps(queue, session, units, 1)
	var origin: Vector2i = session.state.tile_of(units[0])
	_check.call("sweep: another session's board is never served the done previews", (
			done.size() == 1
			and session.last_seq() == other.last_seq()
			and queue.is_done(session, units[0], origin)
			and not queue.is_done(other, units[0], origin)
	), "seqs %d / %d" % [session.last_seq(), other.last_seq()])
	queue.wait()


# With the worker off, a hover computes at once and nothing is swept.
func _test_unthreaded() -> void:
	var session: CombatSession = _session("unthreaded")
	if session == null:
		return
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	queue.is_threaded = false
	var tile: Vector2i = _nearest_first(session, units[0])[1]
	queue.request(units[0], tile)
	var ready: MovePreview = queue.run_pending(session, units)
	for _frame: int in 3:
		queue.run_pending(session, units)
	_check.call("sweep: off without the worker, a hover computed at once", (
			ready != null and ready.tile == tile and queue.swept == 0 and queue.runs == 1
	), "swept %d, runs %d" % [queue.swept, queue.runs])


# Every tile of one unit swept in checking mode: no kept decision or reused forecast differs from
# a full re-plan.
func _test_checking() -> void:
	if not OS.is_debug_build():
		return
	var session: CombatSession = _session("checking")
	if session == null:
		return
	Intents.is_checking = true
	var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
	var order: PackedStringArray = [units[0]]
	var tiles: Array[Vector2i] = _nearest_first(session, units[0])
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	_sweep_steps(queue, session, order, tiles.size())
	var flags: PackedStringArray = []
	for tile: Vector2i in tiles:
		queue.request(units[0], tile)
		var ready: MovePreview = queue.run_pending(session)
		queue.clear()
		if ready == null or ready.intents == null:
			continue
		for line: String in ready.intents.diagnostics:
			if line.begins_with(Intents.CHECK_PREFIX):
				flags.append("%s: %s" % [tile, line])
	Intents.is_checking = false
	_check.call("sweep: every swept preview equals a full re-plan in checking mode", (
			flags.is_empty()
	), "; ".join(flags.slice(0, 3)))


# Steps queue's sweep of order on session, one preview at a time, until count are done or the
# sweep has nothing left: each preview's unit and tile (_name_of), in the order they were done.
func _sweep_steps(
		queue: MovePreview.Queue,
		session: CombatSession,
		order: PackedStringArray,
		count: int
) -> Array[String]:
	var seen: Array[String] = []
	var candidates: Dictionary[String, Vector2i] = {}
	var owners: Dictionary[String, String] = {}
	for unit_id: String in order:
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			candidates[_name_of(unit_id, tile)] = tile
			owners[_name_of(unit_id, tile)] = unit_id
	while seen.size() < count:
		var swept: int = queue.swept
		queue.run_pending(session, order)
		queue.wait()
		for name: String in candidates:
			if not seen.has(name) and queue.is_done(session, owners[name], candidates[name]):
				seen.append(name)
		if queue.swept == swept and seen.size() < count:
			queue.run_pending(session, order)
			if queue.swept == swept:
				break
	return seen


# unit_id's move tiles, nearest by walking cost (Pathing.reach), ties in row-major order.
func _nearest_first(session: CombatSession, unit_id: String) -> Array[Vector2i]:
	var costs: Dictionary[Vector2i, int] = Pathing.reach(session.engine, session.state, unit_id)
	var tiles: Array[Vector2i] = []
	tiles.assign(costs.keys())
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if costs[a] != costs[b]:
			return costs[a] < costs[b]
		return MapLayout.is_before(a, b)
	)
	return tiles


# A fresh benchmark board, its intents current; null, reported, when it can't be built.
func _session(label: String) -> CombatSession:
	var session: CombatSession = _boards.build(BOARD)
	var is_built: bool = (
			session != null
			and _boards.is_intended(BOARD, session)
			and session.intents != null
			and session.intents.based_on_seq == session.last_seq()
	)
	if not is_built:
		_check.call("sweep (%s): %s is built with current intents" % [label, BOARD], false, (
				", ".join(_boards.failures)
		))
		return null
	return session


# unit_id waits where it stands: a fact, after which the intents refresh. Reports a rejection.
func _wait_on(session: CombatSession, unit_id: String) -> bool:
	session.submit(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	var batch: CombatSession.FactBatch = session.resolve_next()
	if batch == null or batch.is_rejected():
		_check.call("sweep: %s's wait resolves" % [unit_id], false)
		return false
	return true


static func _name_of(unit_id: String, tile: Vector2i) -> String:
	return "%s %s" % [unit_id, tile]
