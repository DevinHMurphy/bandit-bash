# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     move_preview.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name MovePreview
extends RefCounted
## What moving a selected unit to a hovered tile would mean, before any action: the darkness damage
## it would take ending its phase there ([method Darkness.damage_at]) and the enemies' intents
## re-planned for it ([method Intents.preview]), with which enemies' intents differ from the
## current ones (combat UI plan, question 9).
##
## A preview takes tens of milliseconds in a debug build, so it runs off the input path (question
## 16 (a)): hovering only [method Queue.request]s one, and [BattleController] hands the newest to
## a [Queue], which re-plans the enemies on a worker thread ([method Intents.PreviewJob.run]) and
## returns the preview on a later frame. Hovers in between are dropped, and so is a result that is
## no longer the newest hover's or was asked on an older board. Reading only: every query runs on
## a sandbox copied on the main thread. [MovePreviewMarks] draws the damage and [IntentDisplay] the
## intents, as previewed.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The unit previewed.
var unit_id: String = ""

## The tile it would end its move on.
var tile: Vector2i = CombatFact.NO_TILE

## The HP it would lose to the darkness ending its phase on [member tile]; 0 on a dry tile.
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


## The newest hover waiting for its preview, the one running on a worker thread, and the one
## shown. Each [method run_pending] returns a finished preview, if one is ready, and starts the
## newest [method request] when none runs, so at most one preview runs at a time.
class Queue:
	extends RefCounted

	# No task: WorkerThreadPool's task ids are never negative.
	const _NO_TASK: int = -1

	## Whether previews re-plan on a worker thread. [b]Off:[/b] [method run_pending] computes the
	## newest request whole on the main thread and returns it at once.
	var is_threaded: bool = true

	## Previews returned by [method run_pending] so far, for tests and benchmarks.
	var computed: int = 0

	var _unit_id: String = ""
	var _tile: Vector2i = CombatFact.NO_TILE
	var _has_pending: bool = false
	var _shown: MovePreview = null

	# The preview whose enemies a worker re-plans, its task (_NO_TASK once waited for), and whether
	# clear() dropped it.
	var _running: MovePreview = null
	var _task_id: int = _NO_TASK
	var _is_dropped: bool = false

	## Asks for the preview of [param unit_id] on [param tile], replacing any request not yet run.
	## A request for the preview already shown, on an unchanged session, is dropped when run.
	func request(unit_id: String, tile: Vector2i) -> void:
		_unit_id = unit_id
		_tile = tile
		_has_pending = true

	## Drops the request waiting and forgets the preview shown. A preview still running isn't
	## waited for: its result is dropped when it finishes.
	func clear() -> void:
		_has_pending = false
		_shown = null
		_is_dropped = _running != null

	## Whether a request is waiting.
	func has_pending() -> bool:
		return _has_pending

	## The preview last returned by [method run_pending]; null after [method clear].
	func shown() -> MovePreview:
		return _shown

	## Blocks until the preview running on a worker thread, if any, has finished; the next
	## [method run_pending] returns it, or drops it. For tests, benchmarks and teardown, which must
	## wait for every task before exit.
	func wait() -> void:
		if _task_id == _NO_TASK:
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = _NO_TASK

	## On [param session]: takes the finished preview, if one is, then starts the newest request
	## when nothing runs. Returns the finished preview; null while it runs, when nothing waited, or
	## when it was dropped: by [method clear], for a newer request, or because the session changed
	## while it ran (the same request is then asked again). With [member is_threaded] off, computes
	## the newest request at once and returns it. A request that would repeat the preview shown is
	## dropped.
	func run_pending(session: CombatSession) -> MovePreview:
		var ready: MovePreview = _collect(session)
		if _running != null or not _has_pending:
			return ready
		_has_pending = false
		if (
				_shown != null
				and _shown.unit_id == _unit_id
				and _shown.tile == _tile
				and _shown.based_on_seq == session.last_seq()
		):
			return ready
		var preview: MovePreview = MovePreview._prepare(session, _unit_id, _tile)
		if not is_threaded:
			preview._finish()
			_shown = preview
			computed += 1
			return preview
		_running = preview
		_is_dropped = false
		_task_id = WorkerThreadPool.add_task(preview._job.run)
		return ready

	# The running preview once its task has finished, finished on the main thread and shown; null
	# while it runs or when it is dropped.
	func _collect(session: CombatSession) -> MovePreview:
		if _running == null:
			return null
		if _task_id != _NO_TASK:
			if not WorkerThreadPool.is_task_completed(_task_id):
				return null
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = _NO_TASK
		var finished: MovePreview = _running
		_running = null
		if _is_dropped:
			return null
		var is_newest: bool = (
				not _has_pending or (_unit_id == finished.unit_id and _tile == finished.tile)
		)
		if not is_newest:
			return null
		if finished.based_on_seq != session.last_seq():
			request(finished.unit_id, finished.tile)
			return null
		_has_pending = false
		finished._finish()
		_shown = finished
		computed += 1
		return finished
