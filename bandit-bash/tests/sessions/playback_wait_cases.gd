# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     playback_wait_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## [FactPlayback] waits across batches: the last fact's wait runs out while nothing is queued, so
## a batch queued after it plays at once, and one queued sooner waits only what is left. Speed,
## pause and hold apply to that wait as to any other; a skip (fast-forward and play_all) and
## fast-forward's stop before a marked fact behave as before. Every fact plays once, in order.


# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "sessions"

# Every fact's wait in these cases, in seconds at speed 1.0.
const WAIT: float = 1.0


func run() -> void:
	_run(_test_idle_past_the_last_wait)
	_run(_test_batches_back_to_back)
	_run(_test_speed_pause_and_hold)
	_run(_test_fast_forward_and_skip)


# BUG-018: a batch, then an idle longer than its last wait, then a second batch.
func _test_idle_past_the_last_wait() -> bool:
	var bus: CombatBus = CombatBus.new()
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(bus)
	var playback: FactPlayback = _playback(bus)
	playback.enqueue(_facts([CombatFact.Kind.UNIT_MOVED, CombatFact.Kind.ATTACK_MADE]))
	var first: int = playback.advance(0.0)
	var second: int = playback.advance(WAIT)
	_check("idle: the first batch plays fact by fact", first == 1 and second == 1)
	# Twice the last fact's wait passes with nothing queued: the player deciding.
	var idle: int = playback.advance(WAIT * 2.0)
	playback.enqueue(_facts([CombatFact.Kind.HIT_DEALT, CombatFact.Kind.DAMAGE_TAKEN]))
	var at_once: int = playback.advance(0.0)
	_check("idle: nothing plays while nothing is queued", idle == 0)
	_check("idle: the next batch's first fact plays at once", at_once == 1, "%d played" % [at_once])
	_check("idle: its next fact still waits its own wait", (
			playback.advance(WAIT * 0.5) == 0 and playback.advance(WAIT * 0.5) == 1
	))
	_check("idle: every fact once, in order", (
			_kinds_of(tracer.combat_facts) == "UNIT_MOVED ATTACK_MADE HIT_DEALT DAMAGE_TAKEN"
	), _kinds_of(tracer.combat_facts))
	return true


# Batches queued before the last wait runs out: each wait is still kept in full.
func _test_batches_back_to_back() -> bool:
	var bus: CombatBus = CombatBus.new()
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(bus)
	var playback: FactPlayback = _playback(bus)
	playback.enqueue(_facts([CombatFact.Kind.UNIT_MOVED]))
	playback.enqueue(_facts([CombatFact.Kind.ATTACK_MADE]))
	_check("back to back: the first fact plays at once", playback.advance(0.0) == 1)
	_check("back to back: the second batch waits the first's wait", (
			playback.advance(WAIT * 0.75) == 0 and playback.advance(WAIT * 0.25) == 1
	))
	# Part of the last wait passes with nothing queued; the batch queued then waits the rest.
	var early: int = playback.advance(WAIT * 0.4)
	playback.enqueue(_facts([CombatFact.Kind.HIT_DEALT]))
	var before_rest: int = playback.advance(WAIT * 0.5)
	var after_rest: int = playback.advance(WAIT * 0.1)
	_check("back to back: a batch queued mid-wait waits only what is left", (
			early == 0 and before_rest == 0 and after_rest == 1
	), "%d, %d, %d played" % [early, before_rest, after_rest])
	_check("back to back: every fact once, in order", (
			_kinds_of(tracer.combat_facts) == "UNIT_MOVED ATTACK_MADE HIT_DEALT"
	), _kinds_of(tracer.combat_facts))
	return true


# The last fact's wait runs at the game speed, and a pause or a hold stops it as it stops any wait.
func _test_speed_pause_and_hold() -> bool:
	var fast: FactPlayback = _playback(CombatBus.new())
	fast.speed = 2.0
	fast.enqueue(_facts([CombatFact.Kind.UNIT_MOVED]))
	fast.advance(0.0)
	var short_idle: int = fast.advance(WAIT * 0.4)
	fast.enqueue(_facts([CombatFact.Kind.ATTACK_MADE]))
	var still_waiting: int = fast.advance(0.0)
	var due: int = fast.advance(WAIT * 0.1)
	_check("speed: the last fact's wait runs at the game speed", (
			short_idle == 0 and still_waiting == 0 and due == 1
	), "%d, %d, %d played" % [short_idle, still_waiting, due])

	var paused: FactPlayback = _playback(CombatBus.new())
	paused.enqueue(_facts([CombatFact.Kind.UNIT_MOVED]))
	paused.advance(0.0)
	paused.pause()
	paused.advance(WAIT * 5.0)
	paused.resume()
	paused.enqueue(_facts([CombatFact.Kind.ATTACK_MADE]))
	_check("pause: the last fact's wait stops while paused", (
			paused.advance(0.0) == 0 and paused.advance(WAIT) == 1
	))

	var held_bus: CombatBus = CombatBus.new()
	var held: FactPlayback = _playback(held_bus)
	var request: PresentationRequest = PresentationRequest.new("hit animation")
	# Kept, so the connection can be cut: the lambda holds the playback that holds the bus.
	var hold_on_hit: Callable = func(_fact: CombatFact) -> void: held.hold(request)
	held_bus.action.hit_dealt.connect(hold_on_hit)
	held.enqueue(_facts([CombatFact.Kind.HIT_DEALT]))
	held.advance(0.0)
	held.advance(WAIT * 5.0)
	request.complete()
	held.enqueue(_facts([CombatFact.Kind.DAMAGE_TAKEN]))
	_check("hold: the last fact's wait starts once the hold completes", (
			held.advance(0.0) == 0 and held.advance(WAIT) == 1
	))
	held_bus.action.hit_dealt.disconnect(hold_on_hit)
	return true


# A skip (fast-forward, then play_all, as the battle view's flush does) plays everything queued
# and leaves no wait; fast-forward still stops before a marked fact in a later batch.
func _test_fast_forward_and_skip() -> bool:
	var bus: CombatBus = CombatBus.new()
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(bus)
	var playback: FactPlayback = _playback(bus)
	playback.enqueue(_facts([CombatFact.Kind.UNIT_MOVED]))
	playback.advance(0.0)
	playback.enqueue(_facts([CombatFact.Kind.ATTACK_MADE, CombatFact.Kind.HIT_DEALT]))
	playback.is_fast_forward = true
	var flushed: int = playback.play_all()
	playback.is_fast_forward = false
	playback.enqueue(_facts([CombatFact.Kind.DAMAGE_TAKEN]))
	_check("skip: plays everything queued at once", flushed == 2, "%d played" % [flushed])
	_check("skip: leaves no wait behind", playback.advance(0.0) == 1)
	_check("skip: every fact once, in order", (
			_kinds_of(tracer.combat_facts) == "UNIT_MOVED ATTACK_MADE HIT_DEALT DAMAGE_TAKEN"
	), _kinds_of(tracer.combat_facts))

	var marked: FactPlayback = _playback(CombatBus.new())
	marked.pause_hook = func(fact: CombatFact) -> bool:
		return fact.kind == CombatFact.Kind.DEFEATED
	var stops: Array[CombatFact] = []
	marked.paused_before.connect(func(fact: CombatFact) -> void: stops.append(fact))
	marked.enqueue(_facts([CombatFact.Kind.UNIT_MOVED]))
	marked.advance(0.0)
	marked.advance(WAIT * 2.0)
	marked.is_fast_forward = true
	marked.enqueue(_facts([CombatFact.Kind.ATTACK_MADE, CombatFact.Kind.DEFEATED]))
	var before_stop: int = marked.advance(0.0)
	_check("fast-forward: stops before a marked fact in a later batch", (
			before_stop == 1
			and marked.is_paused
			and not marked.is_fast_forward
			and stops.size() == 1
			and marked.pending() == 1
	), "%d played, %d stops" % [before_stop, stops.size()])
	marked.resume()
	_check("fast-forward: the marked fact plays on resume", (
			marked.advance(0.0) == 1 and marked.pending() == 0
	))
	return true


# A playback on bus where every fact waits WAIT.
func _playback(bus: CombatBus) -> FactPlayback:
	var playback: FactPlayback = FactPlayback.new(bus)
	playback.duration_hook = func(_fact: CombatFact) -> float: return WAIT
	return playback


func _facts(kinds: Array[CombatFact.Kind]) -> Array[CombatFact]:
	var facts: Array[CombatFact] = []
	for kind: CombatFact.Kind in kinds:
		facts.append(CombatFact.new(kind))
	return facts
