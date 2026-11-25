# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     team_ready_status.gd
# Author:
# Created:  November 24, 2026
# Modified: November 24, 2026
# ==============================================================================

class_name TeamReadyStatus
extends VBoxContainer
## Who a co-op hand-off waits for: a [TeamReadyRow] per seat still in the run, in seat order, with
## the player's name and Ready, Choosing, Loading or Done; on the loading screen each machine's
## load as a bar too ([member shows_bars]).
##
## [method set_state] takes the ready gate's state as the host announces it, so a screen feeds it
## unchanged. The names given are the seats shown: a seat left out (forfeited, removed) loses its
## row, and one in the other arguments with no name is ignored. Hidden below [member min_seats]
## seats. Reading only; takes no input.
##
## @tutorial(Co-op ready checks): docs/plans/2026-11-24-coop-ready-checks.md

# ============================================================
# SEAT STATES (read afresh from each set_state; nothing is held between calls):
#   LOADING   the seat's machine hasn't reported the step loaded (its bar at its progress)
#   CHOOSING  loaded, not Ready, on a step with a choice     } which of the two is
#   DONE      loaded, not Ready, on a step without one       } loaded_state
#   READY     the seat pressed Ready (its bar full)
#   A Ready taken back shows loaded_state again.
# ============================================================

## What a seat shows ([method state_of]).
enum State {
	## The seat pressed Ready.
	READY = 0,
	## Loaded, and still making the step's choice.
	CHOOSING = 1,
	## Its machine is still loading the step.
	LOADING = 2,
	## Loaded, on a step that asks no choice (the loading screen).
	DONE = 3,
}

## Each state as a row shows it.
const STATE_NAMES: Dictionary[State, String] = {
	State.READY: "Ready",
	State.CHOOSING: "Choosing",
	State.LOADING: "Loading",
	State.DONE: "Done",
}

# Loaded when the first row is made, not preloaded: the row's script names this class's State, and
# a preload here would load the row's script while this one is still loading.
const ROW_SCENE_PATH: String = "res://ui/common/team_ready_row.tscn"

## What a seat that has loaded but isn't Ready shows: [constant State.CHOOSING] on a screen with
## a choice, [constant State.DONE] on the loading screen. Any other value reads as Choosing.
@export var loaded_state: State = State.CHOOSING

## Whether each row shows its machine's load as a bar, as the loading screen does.
## [b]Off:[/b] the name and state only.
@export var shows_bars: bool = false

## The fewest seats the status shows for. [b]2:[/b] hidden in solo. [b]1:[/b] solo shows its one
## row, as the loading screen does.
@export_range(1, 4, 1) var min_seats: int = 2

# The row of each seat shown, by seat.
var _rows: Dictionary[int, TeamReadyRow] = {}

var _row_scene: PackedScene = null

# The state and progress of each seat shown, as last set.
var _states: Dictionary[int, State] = {}
var _progress: Dictionary[int, float] = {}


func _ready() -> void:
	visible = false


## Shows the gate's state: a row per seat of [param seat_names] (seat to the name shown), ascending.
## [param ready_seats] pressed Ready; [param loaded_seats] have loaded the step;
## [param progress_by_seat] is each loading machine's load, 0.0 to 1.0 (missing: 0.0).
func set_state(
		ready_seats: PackedInt32Array,
		loaded_seats: PackedInt32Array,
		progress_by_seat: Dictionary[int, float],
		seat_names: Dictionary[int, String],
) -> void:
	var seats: Array[int] = []
	seats.assign(seat_names.keys())
	seats.sort()
	var shown_seats: Array[int] = []
	shown_seats.assign(_rows.keys())
	for seat: int in shown_seats:
		if not seat_names.has(seat):
			_drop_row(seat)
	_states.clear()
	_progress.clear()
	for i: int in seats.size():
		var seat: int = seats[i]
		var state: State = state_for(seat, ready_seats, loaded_seats, loaded_state)
		var shown: float = 1.0
		if state == State.LOADING:
			var reported: float = progress_by_seat.get(seat, 0.0)
			shown = clampf(reported, 0.0, 1.0)
		_states[seat] = state
		_progress[seat] = shown
		var row: TeamReadyRow = _row_for(seat)
		if row == null:
			continue
		move_child(row, i)
		row.shows_bar = shows_bars
		row.show_seat(seat_names[seat], state, shown)
	visible = seats.size() >= min_seats


## Hides every row: the screen has no gate state to show.
func clear() -> void:
	var shown_seats: Array[int] = []
	shown_seats.assign(_rows.keys())
	for seat: int in shown_seats:
		_drop_row(seat)
	_states.clear()
	_progress.clear()
	visible = false


## The seats shown, ascending.
func get_seats() -> PackedInt32Array:
	var seats: PackedInt32Array = []
	for seat: int in _states:
		seats.append(seat)
	seats.sort()
	return seats


## What [param seat] shows; [constant State.LOADING] for a seat not shown.
func state_of(seat: int) -> State:
	var state: State = _states.get(seat, State.LOADING)
	return state


## The load [param seat]'s row shows, 0.0 to 1.0: full unless Loading. 0.0 for a seat not shown.
func progress_of(seat: int) -> float:
	var shown: float = _progress.get(seat, 0.0)
	return shown


## The row of [param seat], for tests and captures; null for a seat not shown.
func get_row(seat: int) -> TeamReadyRow:
	var row: TeamReadyRow = _rows.get(seat, null)
	return row


## Every row as text, in seat order ("Player 2 · Ready"), for tests.
func get_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for seat: int in get_seats():
		var row: TeamReadyRow = get_row(seat)
		if row != null:
			lines.append(row.get_line())
	return lines


# The row of seat, made when it has none; null if the row scene won't load.
func _row_for(seat: int) -> TeamReadyRow:
	if _rows.has(seat):
		return _rows[seat]
	if _row_scene == null:
		_row_scene = load(ROW_SCENE_PATH) as PackedScene
	var row: TeamReadyRow = (
			_row_scene.instantiate() as TeamReadyRow if _row_scene != null else null
	)
	if row == null:
		push_error("TeamReadyStatus: no row scene - %s" % [ROW_SCENE_PATH])
		return null
	add_child(row)
	_rows[seat] = row
	return row


func _drop_row(seat: int) -> void:
	var row: TeamReadyRow = get_row(seat)
	_rows.erase(seat)
	if row == null:
		return
	remove_child(row)
	row.queue_free()


## What [param seat] shows given the gate's [param ready_seats] and [param loaded_seats]: Ready
## once pressed, Loading until loaded, else [param loaded] (Choosing or Done; others read as
## Choosing).
static func state_for(
		seat: int,
		ready_seats: PackedInt32Array,
		loaded_seats: PackedInt32Array,
		loaded: State,
) -> State:
	if ready_seats.has(seat):
		return State.READY
	if not loaded_seats.has(seat):
		return State.LOADING
	return State.DONE if loaded == State.DONE else State.CHOOSING
