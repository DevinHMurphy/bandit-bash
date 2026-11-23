# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     move_preview.gd
# Author:
# Created:  November 4, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name MovePreview
extends RefCounted
## What moving a selected unit to a hovered tile would mean, before any action: the darkness damage
## it would take there in this turn's darkness phase ([method Darkness.damage_at]) and the intents
## re-planned for it ([method Intents.preview]), with which enemies' intents differ from the
## current ones (combat UI plan, question 9).
##
## A preview takes tens to hundreds of milliseconds, so it runs off the input path: a [Queue]
## re-plans on one worker thread ([method Intents.PreviewJob.run]), sweeping every tile the
## seat's units can end on as soon as the intents are current, so a hover is usually a lookup
## (move-preview.md, layer 5). Reading only: every query runs on a sandbox copied on the main
## thread. [MovePreviewMarks] draws the damage and [IntentDisplay] the intents, as previewed.
##
## @tutorial(The move preview): docs/design/move-preview.md

## The unit previewed.
var unit_id: String = ""

## The tile it would end its move on.
var tile: Vector2i = CombatFact.NO_TILE

## The HP it would lose on [member tile] in this turn's darkness phase; 0 on a dry tile.
var darkness_damage: int = 0

## The enemies' intents with the unit on [member tile]; null when the session keeps none (before
## turn 1's Phase Start, outside the player phase).
var intents: Intents = null

## Every enemy whose intent on [member tile] differs from the session's current one (see
## [method intent_differs]), in state order.
var changed_enemies: PackedStringArray = []

## [method CombatSession.last_seq] when it was computed: any newer fact makes it stale.
var based_on_seq: int = Command.NO_SEQ

# From _prepare to _finish: the enemies' re-planning, the session's intents and its enemies (in
# state order) when it was asked for, so the changes are judged against that board.
var _job: Intents.PreviewJob = null
var _current: Intents = null
var _enemy_ids: PackedStringArray = []


## The preview of [param unit_id] ending its move on [param tile] on [param session] now, all on
## the calling thread. Main thread only.
static func compute(session: CombatSession, unit_id: String, tile: Vector2i) -> MovePreview:
	var found: MovePreview = _prepare(session, unit_id, tile)
	found._finish()
	return found


## Whether an enemy's intent [param after] the move differs from [param before] it, as the board
## marks it: one acts and the other doesn't, or its icon, target, tile or place in the order
## changed.
static func intent_differs(before: EnemyIntent, after: EnemyIntent) -> bool:
	if before == null or after == null:
		return before != after
	# ASSUMPTION: these four fields are what "changed" means; a different path to the same tile, or
	# a changed forecast against the same target, isn't tinted as changed ([IntentIcon]).
	return (
			before.kind != after.kind
			or before.target_id != after.target_id
			or before.tile != after.tile
			or before.order != after.order
	)


# Everything compute reads from session, on the main thread: the damage, the enemies' job up to its
# re-planning (Intents.prepare_preview), and the intents and enemies to compare with.
static func _prepare(session: CombatSession, unit_id: String, tile: Vector2i) -> MovePreview:
	var found: MovePreview = MovePreview.new()
	found.unit_id = unit_id
	found.tile = tile
	found.based_on_seq = session.last_seq()
	found.darkness_damage = Darkness.damage_at(session.engine, unit_id, tile)
	found._job = Intents.prepare_preview(session, unit_id, tile)
	found._current = session.intents
	found._enemy_ids = session.state.units_of(CombatFact.CombatSide.ENEMY)
	return found


# The intents (re-planned here unless a worker already ran the job) and the enemies they change.
func _finish() -> void:
	intents = _job.run()
	_job = null
	if intents != null and _current != null:
		for enemy_id: String in _enemy_ids:
			if intent_differs(_current.intent_of(enemy_id), intents.intent_of(enemy_id)):
				changed_enemies.append(enemy_id)
	_current = null


## The newest hover waiting for its preview, the previews done on the current board, the one
## running on a worker thread, and the one shown. Each [method run_pending] takes a finished
## preview into the done ones, returns the hover's when it is done, and otherwise starts the
## hover's, or else the sweep's next tile, so at most one preview runs at a time.[br]
## [b]The sweep:[/b] while the session's intents are current, the worker previews every tile each
## unit of the sweep order can end on, nearest first, a unit's tiles before the next unit's; a
## hover on a tile not yet done cancels the sweep's preview running
## ([method Intents.PreviewJob.cancel]) and runs as soon as it stops, the cancelled tile left for
## the sweep to reach again. A hover's own preview is never cancelled. The done previews are keyed
## by the session, its [method CombatSession.last_seq], the unit and the tile, and dropped at the
## next fact, when the sweep starts over.
class Queue:
	extends RefCounted

	# No task: WorkerThreadPool's task ids are never negative.
	const _NO_TASK: int = -1

	## Whether previews re-plan on a worker thread. [b]Off:[/b] [method run_pending] computes the
	## newest request whole on the main thread and returns it at once, and nothing is swept.
	var is_threaded: bool = true

	## Whether the worker sweeps while no hover waits (see the class doc), with
	## [member is_threaded] on. [b]Off:[/b] only hovers run.
	var is_sweeping: bool = true

	## Previews returned by [method run_pending] so far, for tests and benchmarks.
	var computed: int = 0

	## Previews started so far, for hovers and the sweep, for tests and benchmarks. A hover on a
	## done tile starts none.
	var runs: int = 0

	## Of [member runs], those the sweep started.
	var swept: int = 0

	## Of [member swept], those a hover cancelled before they ended, their results dropped; each
	## cancelled tile is swept again later, so it counts in [member swept] again.
	var cancelled: int = 0

	# The newest request; whether it waits to start, and whether it is owed: waiting, or started
	# and not yet returned.
	var _unit_id: String = ""
	var _tile: Vector2i = CombatFact.NO_TILE
	var _has_pending: bool = false
	var _is_owed: bool = false
	var _shown: MovePreview = null

	# The previews done on one board, by _key_of, with that board: the session's instance id and
	# its last_seq; and each unit's tiles in sweep order there, computed as the sweep reaches it.
	var _done: Dictionary[String, MovePreview] = {}
	var _done_session: int = 0
	var _done_seq: int = Command.NO_SEQ
	var _tiles_of: Dictionary[String, Array] = {}

	# The preview a worker re-plans, its task (_NO_TASK once waited for), the session's instance
	# id when it was asked for, and whether the sweep started it (a hover may cancel it).
	var _running: MovePreview = null
	var _task_id: int = _NO_TASK
	var _running_session: int = 0
	var _is_running_swept: bool = false

	## Asks for the preview of [param unit_id] on [param tile], replacing any request not yet run.
	## A request for the preview already shown, on an unchanged session, is dropped when run.
	func request(unit_id: String, tile: Vector2i) -> void:
		_unit_id = unit_id
		_tile = tile
		_has_pending = true
		_is_owed = true

	## Drops the request waiting and forgets the preview shown. A preview still running isn't
	## waited for: it finishes into the done previews, as a sweep's would.
	func clear() -> void:
		_has_pending = false
		_is_owed = false
		_shown = null

	## Whether a request is waiting to start; false once its preview runs.
	func has_pending() -> bool:
		return _has_pending

	## The preview last returned by [method run_pending]; null after [method clear].
	func shown() -> MovePreview:
		return _shown

	## Whether the preview of [param unit_id] on [param tile] is done on [param session]'s board
	## as it stands, so a hover there returns it with no work.
	func is_done(session: CombatSession, unit_id: String, tile: Vector2i) -> bool:
		return _is_done_board(session) and _done.has(_key_of(unit_id, tile))

	## Blocks until the preview running on a worker thread, if any, has finished; the next
	## [method run_pending] takes it. For tests, benchmarks and teardown, which must wait for
	## every task before exit.
	func wait() -> void:
		if _task_id == _NO_TASK:
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = _NO_TASK

	## On [param session]: takes the finished preview into the done ones, then returns the
	## newest request's when it is done, or starts it when nothing runs, cancelling a sweep's
	## preview of another tile that runs; with no request waiting, starts the next tile of
	## [param sweep] (the units to sweep, in order) not yet done. Returns null while the request's
	## preview isn't done, when nothing waited, or for a request that would repeat the preview
	## shown. A preview asked on an older board, or cancelled, is ignored when it finishes. With
	## [member is_threaded] off, computes the newest request at once instead.
	func run_pending(session: CombatSession, sweep: PackedStringArray = []) -> MovePreview:
		_drop_stale(session)
		_collect(session)
		var ready: MovePreview = _take_done(session)
		if _running != null:
			if _is_owed and _is_running_swept and not _runs_request(session):
				# The hover's starts on the first call after the cancelled one stops, so one
				# preview runs at a time.
				_running._job.cancel()
			return ready
		# Owed and not running: waiting, or its preview was asked on an older board.
		if _is_owed:
			var preview: MovePreview = MovePreview._prepare(session, _unit_id, _tile)
			runs += 1
			_has_pending = false
			if not is_threaded:
				preview._finish()
				_is_owed = false
				_keep(session, preview)
				_shown = preview
				computed += 1
				return preview
			_start(session, preview)
			return ready
		if is_threaded and is_sweeping and _has_current_intents(session):
			_sweep_next(session, sweep)
		return ready

	# Drops the done previews and the sweep's tiles when session's board isn't theirs.
	func _drop_stale(session: CombatSession) -> void:
		if _is_done_board(session):
			return
		_done.clear()
		_tiles_of.clear()
		_done_session = session.get_instance_id()
		_done_seq = session.last_seq()

	func _is_done_board(session: CombatSession) -> bool:
		return _done_session == session.get_instance_id() and _done_seq == session.last_seq()

	# The running preview once its task has finished: finished on the main thread and kept as
	# done while it was asked on session's board as it stands, else ignored; ignored and counted
	# when a cancel stopped it.
	func _collect(session: CombatSession) -> void:
		if _running == null:
			return
		if _task_id != _NO_TASK:
			if not WorkerThreadPool.is_task_completed(_task_id):
				return
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = _NO_TASK
		var finished: MovePreview = _running
		_running = null
		if finished._job.is_cancelled():
			cancelled += 1
			return
		if _running_session != session.get_instance_id():
			return
		if finished.based_on_seq != session.last_seq():
			return
		finished._finish()
		_keep(session, finished)

	# The waiting request's preview, shown, when it is done; null while it isn't, or when it
	# repeats the preview shown (the request is then dropped).
	func _take_done(session: CombatSession) -> MovePreview:
		if not _is_owed:
			return null
		if (
				_shown != null
				and _shown.unit_id == _unit_id
				and _shown.tile == _tile
				and _shown.based_on_seq == session.last_seq()
		):
			_has_pending = false
			_is_owed = false
			return null
		var done: MovePreview = _done.get(_key_of(_unit_id, _tile), null)
		if done == null:
			return null
		_has_pending = false
		_is_owed = false
		_shown = done
		computed += 1
		return done

	func _keep(session: CombatSession, preview: MovePreview) -> void:
		if _is_done_board(session) and preview.based_on_seq == _done_seq:
			_done[_key_of(preview.unit_id, preview.tile)] = preview

	# Whether the preview running is the request's, on session's board as it stands: its result
	# will serve the hover, so cancelling it would only start the same preview again.
	func _runs_request(session: CombatSession) -> bool:
		return (
				_running.unit_id == _unit_id
				and _running.tile == _tile
				and _running.based_on_seq == session.last_seq()
				and _running_session == session.get_instance_id()
		)

	func _start(session: CombatSession, preview: MovePreview, is_swept: bool = false) -> void:
		_running = preview
		_running_session = session.get_instance_id()
		_is_running_swept = is_swept
		_task_id = WorkerThreadPool.add_task(preview._job.run)

	# Starts the first tile of sweep's units, in order, not yet done.
	func _sweep_next(session: CombatSession, sweep: PackedStringArray) -> void:
		for unit_id: String in sweep:
			for tile: Vector2i in _sweep_tiles(session, unit_id):
				if _done.has(_key_of(unit_id, tile)):
					continue
				runs += 1
				swept += 1
				_start(session, MovePreview._prepare(session, unit_id, tile), true)
				return

	# Every tile unit_id can end its move on (Pathing.reach), nearest first, ties in row-major
	# order; empty for a unit that isn't a player unit yet to act. Kept until the board changes.
	func _sweep_tiles(session: CombatSession, unit_id: String) -> Array:
		if _tiles_of.has(unit_id):
			return _tiles_of[unit_id]
		var tiles: Array[Vector2i] = []
		var state: CombatState = session.state
		var is_player: bool = (
				state.has_unit(unit_id)
				and state.side_of(unit_id) == CombatFact.CombatSide.PLAYER
		)
		if is_player and not state.unit(unit_id).has_acted:
			# ASSUMPTION: "nearest" is the walk's cost from the unit's tile, not grid distance.
			var costs: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
			tiles.assign(costs.keys())
			tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				if costs[a] != costs[b]:
					return costs[a] < costs[b]
				return MapLayout.is_before(a, b)
			)
		_tiles_of[unit_id] = tiles
		return tiles

	# Whether session's intents are current: a preview on stale ones computes them afresh on the
	# main thread first (Intents.prepare_preview), which the sweep must never cost.
	static func _has_current_intents(session: CombatSession) -> bool:
		return (
				not session.is_finished
				and session.intents != null
				and session.intents.based_on_seq == session.last_seq()
		)

	static func _key_of(unit_id: String, tile: Vector2i) -> String:
		return "%s %d %d" % [unit_id, tile.x, tile.y]
