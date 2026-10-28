# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_playback.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

class_name FactPlayback
extends RefCounted
## Plays fact batches on a [CombatBus] in order, at the game's speed: the one playback path for the
## host's own batches and for the batches a client receives.
##
## Rules resolve a whole command before any of it is shown; this queue shows it afterwards. Each
## fact plays on the bus, then playback waits that fact's duration ([member duration_hook], divided
## by [member speed]) before the next. Fast-forward plays without waiting and stops before any fact
## [member pause_hook] marks (a boss combat, a player unit's death), so the player sees it.
## Presentation can hold playback on a [PresentationRequest] until it completes. Nothing here
## changes rules state. Spectating is a second playback attached to another session's facts.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Fast-forward stopped before [param fact], which [member pause_hook] marked; playback is paused
## until [method resume], which continues at normal speed.
signal paused_before(fact: CombatFact)

## The bus facts play on. Never null in use.
var bus: CombatBus = null

## Game speed, a host lobby setting: each fact's duration is divided by it.[br]
## [b]1.0:[/b] normal speed. [b]2.0:[/b] twice as fast. Values at or below 0 count as 1.0.
var speed: float = 1.0

## Whether facts play without waiting, stopping only before a fact [member pause_hook] marks.
var is_fast_forward: bool = false

## How long a fact takes to show at speed 1.0, as [code]func(fact: CombatFact) -> float[/code].[br]
## [b]Units:[/b] seconds. [b]Invalid:[/b] every fact takes no time.
var duration_hook: Callable = Callable()

## Whether fast-forward stops before a fact, as [code]func(fact: CombatFact) -> bool[/code].[br]
## [b]Invalid:[/b] fast-forward never stops.
var pause_hook: Callable = Callable()

# Playback state (meaningful while facts are queued; an empty queue plays nothing in any state):
#   PLAYING: advance() plays the next fact on the bus, then starts that fact's wait.
#   WAITING: _wait > 0; advance() counts it down by delta and plays nothing until it runs out.
#            Leftover delta carries on to the next fact, so a long frame never loses time.
#   HELD:    _held is a PresentationRequest not yet done; advance() plays nothing and counts no
#            wait down. When it completes, the next advance() goes on as WAITING or PLAYING.
#   PAUSED:  is_paused; advance() does nothing until resume(). Fast-forward reaching a fact
#            pause_hook marks pauses here with that fact still queued and turns fast-forward off,
#            so resume() shows it at normal speed. pause() enters it at any time.
# The speed and fast-forward settings change waits only; the order of facts never changes.
## Whether playback is paused; see [method pause] and [method resume].
var is_paused: bool = false

var _queue: Array[CombatFact] = []
var _next: int = 0
var _wait: float = 0.0
var _held: PresentationRequest = null


## [param target]: the bus to play on, such as [member CombatSession.bus].
func _init(target: CombatBus) -> void:
	bus = target


## Adds [param facts] after everything already queued, in their order.
func enqueue(facts: Array[CombatFact]) -> void:
	_queue.append_array(facts)


## The number of facts queued and not yet played.
func pending() -> int:
	return _queue.size() - _next


## Plays every fact that is due after [param delta] more seconds have passed, and returns how many
## played. Call it once per frame from presentation.
func advance(delta: float) -> int:
	var played: int = 0
	# Waits are kept in seconds at normal speed, so a speed change also applies to a wait already
	# running.
	var time_left: float = maxf(delta, 0.0) * (speed if speed > 0.0 else 1.0)
	while not is_paused and _next < _queue.size():
		if _held != null:
			if not _held.is_done:
				break
			_held = null
		if _wait > 0.0:
			if time_left < _wait:
				_wait -= time_left
				break
			time_left -= _wait
			_wait = 0.0
		var fact: CombatFact = _queue[_next]
		if is_fast_forward and _stops_before(fact):
			is_fast_forward = false
			is_paused = true
			paused_before.emit(fact)
			break
		_next += 1
		bus.play(fact)
		played += 1
		_wait = 0.0 if is_fast_forward else _duration_of(fact)
	if _next >= _queue.size():
		_queue.clear()
		_next = 0
	return played


## Plays every queued fact now, ignoring durations; a hold or a pause still stops it. Returns how
## many played.
func play_all() -> int:
	_wait = 0.0
	return advance(INF)


## Holds playback until [param request] completes; a held fact's wait does not count down
## meanwhile. Holding again replaces the earlier request.
func hold(request: PresentationRequest) -> void:
	if request != null and not request.is_done:
		_held = request


## Pauses playback, as the pause menu does.
func pause() -> void:
	is_paused = true


## Ends a pause. Fast-forward stays off if it was what paused.
func resume() -> void:
	is_paused = false


# The wait after a fact, in seconds at normal speed.
func _duration_of(fact: CombatFact) -> float:
	if not duration_hook.is_valid():
		return 0.0
	var seconds: float = duration_hook.call(fact)
	return maxf(seconds, 0.0)


func _stops_before(fact: CombatFact) -> bool:
	if not pause_hook.is_valid():
		return false
	var stops: bool = pause_hook.call(fact)
	return stops
