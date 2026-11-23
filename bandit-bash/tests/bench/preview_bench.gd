# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     preview_bench.gd
# Author:
# Created:  November 20, 2026
# Modified: November 22, 2026
# ==============================================================================

extends Node
## The move preview's benchmark (move-preview.md, Where it stands): on four boards
## ([code]bench_boards.gd[/code]: M1 turn 1, M1 engaged, a 9-enemy 6-unit key board on the Hall,
## the Powder Keep engaged), every tile each acting unit can end on is hovered through a threaded
## [MovePreview.Queue] as the battle runs it, giving the latency per hover and per sweep (all of
## one unit's tiles in turn), the frame that starts each, the decisions and attack forecasts each
## made and reused, and the memory the sweep left held; then a per-phase profile of sampled hovers
## on the main thread.[br]
## Run from the repo root, with board names after [code]--[/code] to run only those,
## [code]check[/code] to hover in checking mode ([member Intents.is_checking], debug only) and
## count what it finds instead of timing, [code]after_action[/code] to sweep again after one
## unit acts, [code]sweep[/code] to time the sweep of layer 5 and the hovers it serves, and
## [code]refresh[/code] to time the intents refresh after an action, instead of the profile:[br]
## [code]godot --headless --path bandit-bash res://tests/bench/preview_bench.tscn -- key_engaged
## [/code][br]
## A release build runs it through [code]tests/bench/release_bench.sh[/code]. Measures only;
## exits with code 1 if a board is not the intended one, or checking mode finds a difference.
##
## @tutorial(The move preview): docs/design/move-preview.md

# Preloaded scripts used as types (gdscript.md, Naming): the test helpers have no class name.
const BenchBoards = preload("res://tests/bench/bench_boards.gd")
const PreviewProfile = preload("res://tests/bench/preview_profile.gd")

# The argument after "--" that hovers every tile in checking mode instead of timing.
const CHECK_ARGUMENT: String = "check"

# The argument after "--" that, after the sweep, has the first acting unit walk to its last move
# tile and wait (a fact, so new intents), then sweeps the other units again: what a fact costs
# the previews after it.
const AFTER_ACTION_ARGUMENT: String = "after_action"

# The argument after "--" that, instead of the profile, sweeps every acting unit's tiles through a
# sweeping queue (layer 5): the sweep's time and its frames, hovers on swept tiles, hovers that
# jump into a running sweep, and the memory the done previews hold.
const SWEEP_ARGUMENT: String = "sweep"

# The argument after "--" that times the intents refresh instead (Intents.compute, as the refresh
# after each action runs it), with the session's verify mode on and off, and its parts.
const REFRESH_ARGUMENT: String = "refresh"

# Refreshes timed per board and verify setting.
const REFRESH_RUNS: int = 3

# Hovers that jump into a running sweep, per board, and the sweep frames between two of them.
const JUMPS: int = 12
const FRAMES_BETWEEN_JUMPS: int = 20

# P05 question 10's target per hover, in microseconds (move-preview.md, its decision 4: p95, debug).
const TARGET_USEC: float = 50000.0

# The wait between polls of the worker: finer than a 60 Hz frame, so a latency is the worker's own
# to within a millisecond, without a busy loop taking a core from it.
const POLL_USEC: int = 1000

const BYTES_PER_MB: float = 1048576.0
const USEC_PER_SECOND: float = 1000000.0

# One frame at 60 Hz, as the battle's _process polls the queue, in microseconds.
const FRAME_USEC: int = 16667

# The longest a sweep may run before the bench gives up on it, in microseconds.
const MAX_SWEEP_USEC: int = 600000000

# The checking-mode lines printed per board, at most.
const MAX_FLAGS_SHOWN: int = 5

var _failures: PackedStringArray = []
var _catalog: EffectCatalog.Index = null
var _boards: BenchBoards = null
# Per hover of the board being benched: the decisions its preview made, and the attack forecasts
# it made afresh and reused from the latest intents' store (Intents.decisions,
# Intents.forecasts_made, Intents.forecasts_reused).
var _decided: PackedInt64Array = []
var _made: PackedInt64Array = []
var _reused: PackedInt64Array = []
# In checking mode, over the board: what it checked, and the lines reporting a difference.
var _checked: int = 0
var _flags: PackedStringArray = []


func _ready() -> void:
	_catalog = EffectCatalog.index()
	_boards = BenchBoards.new(_catalog)
	var is_checking: bool = OS.get_cmdline_user_args().has(CHECK_ARGUMENT)
	var is_after_action: bool = OS.get_cmdline_user_args().has(AFTER_ACTION_ARGUMENT)
	var is_sweep: bool = OS.get_cmdline_user_args().has(SWEEP_ARGUMENT)
	var is_refresh: bool = OS.get_cmdline_user_args().has(REFRESH_ARGUMENT)
	_print_header(is_checking)
	for board: String in _chosen_boards():
		var session: CombatSession = _boards.build(board)
		if session == null or not _boards.is_intended(board, session):
			continue
		var units: PackedStringArray = TurnInputModel.acting_units(session, 0)
		if is_checking:
			_check_board(board, session)
		elif is_sweep:
			_bench_sweep(session, units)
		elif is_refresh:
			_bench_refresh(session)
		elif is_after_action:
			_bench_worker(session, units)
			var actor: String = units[0]
			_act(session, actor)
			units.remove_at(0)
			print("\n-- After %s walked and waited: the other units' tiles --" % [
				session.describe(actor),
			])
			_bench_worker(session, units)
		else:
			_bench_worker(session, units)
			PreviewProfile.new(session, _catalog).run()
	_boards.close()
	_failures.append_array(_boards.failures)
	if _failures.is_empty():
		print("\nDone: every check passed.")
	else:
		print("\nDone with %d failures:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _print_header(is_checking: bool) -> void:
	var version: Dictionary = Engine.get_version_info()
	print("=== Move preview benchmark%s ===" % [" (checking mode)" if is_checking else ""])
	print("Godot %s, %s build; verify mode off in every preview sandbox, as the preview sets it" % [
		version.get("string", "?"), "debug" if OS.is_debug_build() else "release",
	])
	print("CPU: %s, %d logical cores; previews on one worker thread (WorkerThreadPool)" % [
		OS.get_processor_name(), OS.get_processor_count(),
	])
	print("Times in microseconds. One hover per move tile of every acting unit; one warm-up first.")


# The boards named after "--", in BenchBoards.BOARDS order; every board when none is named.
func _chosen_boards() -> PackedStringArray:
	var named: PackedStringArray = OS.get_cmdline_user_args()
	named.erase(CHECK_ARGUMENT)
	named.erase(AFTER_ACTION_ARGUMENT)
	named.erase(SWEEP_ARGUMENT)
	named.erase(REFRESH_ARGUMENT)
	var chosen: PackedStringArray = []
	for board: String in BenchBoards.BOARDS:
		if named.is_empty() or named.has(board):
			chosen.append(board)
	for named_board: String in named:
		if not BenchBoards.BOARDS.has(named_board):
			_failures.append("no board named %s (boards: %s)" % [
				named_board, ", ".join(BenchBoards.BOARDS),
			])
	return chosen


# Every move tile of each of units through one threaded queue, a unit's tiles in turn: the
# latency of each hover (request to the preview returned), of each unit's sweep, and the
# main thread's frame that starts each hover (Intents.prepare_preview).
func _bench_worker(session: CombatSession, units: PackedStringArray) -> void:
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var hovers: PackedInt64Array = []
	var starts: PackedInt64Array = []
	var sweeps: PackedInt64Array = []
	var warm: Array[Vector2i] = TurnInputModel.move_tiles(session, units[0])
	_hover(queue, session, units[0], warm[warm.size() - 1], PackedInt64Array())
	_decided.clear()
	_made.clear()
	_reused.clear()
	var memory_before: int = OS.get_static_memory_usage()
	for unit_id: String in units:
		var swept: int = Time.get_ticks_usec()
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			hovers.append(_hover(queue, session, unit_id, tile, starts))
		sweeps.append(Time.get_ticks_usec() - swept)
	print("\n-- On the worker thread, as the battle runs it --")
	_report("hover to preview (latency)", hovers)
	_report("  frame that starts it (main thread)", starts)
	_report("sweep: every move tile of one unit", sweeps)
	_report_count("decisions made per hover", _decided)
	_report_count("attack forecasts made per hover", _made)
	_report_count("attack forecasts reused per hover", _reused)
	# Static memory is counted in debug builds only; a release build prints 0.
	print("Memory the sweep left held (the latest intents' forecasts): %+.1f MB" % [
		(OS.get_static_memory_usage() - memory_before) / BYTES_PER_MB,
	])
	print("Target %.0f per hover: median %s, p95 %s" % [
		TARGET_USEC,
		"met" if _median(hovers) <= TARGET_USEC else "missed",
		"met" if _p95(hovers) <= TARGET_USEC else "missed",
	])


# The sweep (layer 5) of every move tile of units, in that order, through a sweeping queue polled
# once a 60 Hz frame, from fresh intents (only their own forecasts in the store): the sweep's
# time, the main thread's time in each frame (one starting a preview prepares it), a hover on
# every swept tile (a lookup, which must start no preview) and the memory the done previews hold;
# then, from fresh intents again, hovers that jump into a running sweep at tiles it hasn't reached.
func _bench_sweep(session: CombatSession, units: PackedStringArray) -> void:
	var total: int = 0
	for unit_id: String in units:
		total += TurnInputModel.move_tiles(session, unit_id).size()
	session.intents = Intents.compute(session, _catalog)
	var memory_before: int = OS.get_static_memory_usage()
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var frames: PackedInt64Array = []
	var starting: PackedInt64Array = []
	var started: int = Time.get_ticks_usec()
	while queue.swept < total and Time.get_ticks_usec() - started < MAX_SWEEP_USEC:
		var swept_before: int = queue.swept
		var spent: int = _frame(queue, session, units)
		frames.append(spent)
		if queue.swept > swept_before:
			starting.append(spent)
	queue.wait()
	queue.run_pending(session, units)
	var sweep_time: int = Time.get_ticks_usec() - started
	var done: int = 0
	for unit_id: String in units:
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			if queue.is_done(session, unit_id, tile):
				done += 1
	if done != total:
		_failures.append("the sweep did %d of %d tiles" % [done, total])
	var lookups: PackedInt64Array = []
	var runs_before: int = queue.runs
	var missed: int = 0
	for unit_id: String in units:
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var asked: int = Time.get_ticks_usec()
			queue.request(unit_id, tile)
			var ready: MovePreview = queue.run_pending(session, units)
			lookups.append(Time.get_ticks_usec() - asked)
			if ready == null:
				missed += 1
			queue.clear()
	if missed > 0 or queue.runs != runs_before:
		_failures.append("hovers on swept tiles: %d not returned at once, %d previews started" % [
			missed, queue.runs - runs_before,
		])
	var memory_swept: int = OS.get_static_memory_usage()
	queue = null
	var memory_dropped: int = OS.get_static_memory_usage()
	print("\n-- The sweep (60 Hz frames), from fresh intents --")
	print("Sweep of %d tiles over %d units: %d (%.1f s), %d frames" % [
		total, units.size(), sweep_time, sweep_time / USEC_PER_SECOND, frames.size(),
	])
	_report("frame, main thread (every frame)", frames)
	_report("frame, main thread (one starting a preview)", starting)
	_report("hover on a swept tile (one call)", lookups)
	# Static memory is counted in debug builds only; a release build prints 0.
	print("Memory held after the sweep: %+.1f MB; the done previews alone %.1f MB" % [
		(memory_swept - memory_before) / BYTES_PER_MB,
		(memory_swept - memory_dropped) / BYTES_PER_MB,
	])
	_bench_jumps(session, units, total)


# Hovers that jump into a running sweep: from fresh intents, a sweep runs JUMPS times for
# FRAMES_BETWEEN_JUMPS frames, then a tile it reaches last and hasn't done is hovered, polled as
# the other hovers are: the wait for the sweep's preview running to stop (cancelled), until the
# hover's own starts, then the hover's own.
func _bench_jumps(session: CombatSession, units: PackedStringArray, total: int) -> void:
	session.intents = Intents.compute(session, _catalog)
	var queue: MovePreview.Queue = MovePreview.Queue.new()
	var last: String = units[units.size() - 1]
	var far: Array[Vector2i] = TurnInputModel.move_tiles(session, last)
	far.reverse()
	var jumps: PackedInt64Array = []
	var waits: PackedInt64Array = []
	for tile: Vector2i in far:
		if jumps.size() >= JUMPS or queue.swept >= total:
			break
		for _frame_index: int in FRAMES_BETWEEN_JUMPS:
			_frame(queue, session, units)
		if queue.is_done(session, last, tile):
			continue
		var runs: int = queue.runs
		var requested: int = Time.get_ticks_usec()
		queue.request(last, tile)
		var ready: MovePreview = queue.run_pending(session, units)
		while queue.runs == runs and ready == null:
			OS.delay_usec(POLL_USEC)
			ready = queue.run_pending(session, units)
		waits.append(Time.get_ticks_usec() - requested)
		while ready == null:
			OS.delay_usec(POLL_USEC)
			ready = queue.run_pending(session, units)
		jumps.append(Time.get_ticks_usec() - requested)
		queue.clear()
	queue.wait()
	_report("hover jumping into a running sweep (latency)", jumps)
	_report("  its wait for the sweep's preview to stop", waits)
	print("Sweep previews cancelled by those hovers: %d" % [queue.cancelled])
	print("Target %.0f per hover jumping in: median %s, p95 %s" % [
		TARGET_USEC,
		"met" if _median(jumps) <= TARGET_USEC else "missed",
		"met" if _p95(jumps) <= TARGET_USEC else "missed",
	])


# One 60 Hz frame of queue on session sweeping units: its run_pending, then a wait to the frame's
# end. Returns the main thread's time in run_pending.
func _frame(queue: MovePreview.Queue, session: CombatSession, units: PackedStringArray) -> int:
	var frame: int = Time.get_ticks_usec()
	queue.run_pending(session, units)
	var spent: int = Time.get_ticks_usec() - frame
	OS.delay_usec(maxi(FRAME_USEC - spent, 0))
	return spent


# The intents refresh after a fact, as Intents.refresh runs it (Intents.compute on the main
# thread), REFRESH_RUNS times with the session's verify mode on and then off; and its parts before
# the phase is played: the sandbox copy, the danger zone and the phase crossing, rebuilt with the
# same calls, verify copied from the session. The refresh's own sandbox keeps verify only in
# checking mode, so its two rows differ only by noise; the parts show what verify costs a copy.
func _bench_refresh(session: CombatSession) -> void:
	print("\n-- The intents refresh (Intents.compute, main thread) --")
	var was_verifying: bool = session.engine.verify
	for is_verifying: bool in [true, false]:
		session.engine.verify = is_verifying and OS.is_debug_build()
		var totals: PackedInt64Array = []
		var parts: PackedInt64Array = []
		for _run: int in REFRESH_RUNS:
			var started: int = Time.get_ticks_usec()
			var found: Intents = Intents.compute(session, _catalog)
			totals.append(Time.get_ticks_usec() - started)
			if found == null:
				_failures.append("the refresh computed no intents")
			started = Time.get_ticks_usec()
			var sandbox: Sandbox = Sandbox.new(session.engine, ForecastRolls.new())
			DangerZone.compute(sandbox.engine)
			PhaseRunner.cross_to_enemy_phase(session, sandbox.engine)
			parts.append(Time.get_ticks_usec() - started)
		var label: String = "verify %s" % ["on" if session.engine.verify else "off"]
		_report("refresh, %s" % [label], totals)
		_report("  its copy, zone and crossing, %s" % [label], parts)
	session.engine.verify = was_verifying


# Every move tile of every acting unit previewed on the main thread in checking mode: every kept
# decision and reused forecast is made afresh and compared. A difference fails the run.
func _check_board(board: String, session: CombatSession) -> void:
	if not OS.is_debug_build():
		_failures.append("%s: checking mode runs in debug builds only" % [board])
		return
	_checked = 0
	_flags.clear()
	var hovers: int = 0
	var was_checking: bool = Intents.is_checking
	Intents.is_checking = true
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
			var found: Intents = Intents.preview(session, unit_id, tile)
			hovers += 1
			if found == null:
				continue
			_checked += found.checked
			for line: String in found.diagnostics:
				if line.begins_with(Intents.CHECK_PREFIX):
					_flags.append("%s to %s: %s" % [unit_id, tile, line])
	Intents.is_checking = was_checking
	print("\n-- Checking mode: %d hovers, %d kept decisions and reused forecasts checked --" % [
		hovers, _checked,
	])
	print("Differences found: %d" % [_flags.size()])
	for index: int in mini(_flags.size(), MAX_FLAGS_SHOWN):
		print("  %s" % [_flags[index]])
	if not _flags.is_empty():
		_failures.append("%s: checking mode found %d differences" % [board, _flags.size()])


# unit_id walks to its last move tile and waits, a fact the intents refresh after: prints how long
# the command took with that refresh (Intents.compute on the main thread) and what it decided.
func _act(session: CombatSession, unit_id: String) -> void:
	var tiles: Array[Vector2i] = TurnInputModel.move_tiles(session, unit_id)
	var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tiles[tiles.size() - 1])
	session.submit(UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT, "", path))
	var started: int = Time.get_ticks_usec()
	var batch: CombatSession.FactBatch = session.resolve_next()
	var spent: int = Time.get_ticks_usec() - started
	if batch == null or batch.is_rejected():
		_failures.append("%s's walk was rejected" % [unit_id])
		return
	var latest: Intents = session.intents
	print("\nThe walk and its intents refresh (main thread): %d; %d decisions, attack forecasts" % [
		spent, latest.decisions,
	] + " made %d, reused %d" % [latest.forecasts_made, latest.forecasts_reused])


# One hover through queue: its latency; the frame that starts it is appended to starts.
func _hover(
		queue: MovePreview.Queue,
		session: CombatSession,
		unit_id: String,
		tile: Vector2i,
		starts: PackedInt64Array
) -> int:
	var requested: int = Time.get_ticks_usec()
	queue.request(unit_id, tile)
	var ready: MovePreview = queue.run_pending(session)
	starts.append(Time.get_ticks_usec() - requested)
	while ready == null:
		OS.delay_usec(POLL_USEC)
		ready = queue.run_pending(session)
	var latency: int = Time.get_ticks_usec() - requested
	if ready.intents != null:
		_decided.append(ready.intents.decisions)
		_made.append(ready.intents.forecasts_made)
		_reused.append(ready.intents.forecasts_reused)
	# The queue drops a request repeating the preview it shows, which would wait forever here.
	queue.clear()
	return latency


func _report(label: String, samples: PackedInt64Array) -> void:
	samples.sort()
	print("%-44s n=%4d  median %9.0f  p95 %9.0f  max %9.0f" % [
		label, samples.size(), _median(samples), _p95(samples),
		0.0 if samples.is_empty() else float(samples[samples.size() - 1]),
	])


# A count per hover, with its mean, which a median of whole numbers hides.
func _report_count(label: String, samples: PackedInt64Array) -> void:
	var total: int = 0
	for sample: int in samples:
		total += sample
	var mean: float = 0.0 if samples.is_empty() else total / float(samples.size())
	_report("%s (mean %.1f)" % [label, mean], samples)


static func _median(sorted: PackedInt64Array) -> float:
	var count: int = sorted.size()
	if count == 0:
		return 0.0
	var middle: int = floori(count / 2.0)
	if count % 2 == 1:
		return float(sorted[middle])
	return (sorted[middle - 1] + sorted[middle]) / 2.0


# Nearest-rank 95th percentile.
static func _p95(sorted: PackedInt64Array) -> float:
	if sorted.is_empty():
		return 0.0
	var rank: int = ceili(0.95 * sorted.size())
	return float(sorted[clampi(rank, 1, sorted.size()) - 1])
