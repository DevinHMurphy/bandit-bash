# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     reaction_queue.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name ReactionQueue
extends RefCounted
## The queued operations waiting to resolve, in fact order, then reaction order within each fact.
##
## A queued operation is a new action ("gain 2 Block", Cleave's splash), so it waits here instead
## of running inside the action that triggered it; [method EffectEngine.drain] resolves the queue
## at every step boundary. Two safety caps catch content bugs, never gameplay: a chain stops at
## [constant MAX_DEPTH] generations, and one resolution step stops at [constant MAX_PER_STEP]
## reactions. Reactions of map objects ([constant EffectOwner.Kind.MAP_OBJECT]) count toward
## neither, since each object breaks once and the map bounds a keg chain.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Most generations one chain may reach (event bus plan, question 7). No MVP content chains past 3.
const MAX_DEPTH: int = 16

## Most reactions one resolution step may resolve: one unit's turn, one phase boundary, the darkness
## step or reinforcement arrival (event bus plan, question 7).
const MAX_PER_STEP: int = 256

## Reactions resolved in the current step, exempt ones excluded.
var resolved_this_step: int = 0

var _pending: Array[Reaction] = []
var _next: int = 0


## Adds [param reaction] after every reaction already waiting.
func push(reaction: Reaction) -> void:
	_pending.append(reaction)


## Whether no reaction is waiting.
func is_empty() -> bool:
	return _next >= _pending.size()


## The number of reactions waiting.
func size() -> int:
	return _pending.size() - _next


## Removes and returns the oldest waiting reaction; null when empty.
func pop() -> Reaction:
	if is_empty():
		return null
	var reaction: Reaction = _pending[_next]
	_next += 1
	if _next == _pending.size():
		_pending.clear()
		_next = 0
	return reaction


## Starts a new resolution step: the per-step count goes back to 0.
func begin_step() -> void:
	resolved_this_step = 0


## A copy for a sandbox: the same waiting reactions, pointed at the copied instances in
## [param instances] (by instance id).
func copy_for(instances: Dictionary[String, EffectInstance]) -> ReactionQueue:
	var queue: ReactionQueue = ReactionQueue.new()
	queue.resolved_this_step = resolved_this_step
	for i: int in range(_next, _pending.size()):
		var original: Reaction = _pending[i]
		var reaction: Reaction = Reaction.new()
		reaction.instance = instances.get(original.instance.instance_id, original.instance)
		reaction.ctx = original.ctx.copy_for_reaction()
		reaction.ctx.instance = reaction.instance
		reaction.operations = original.operations
		reaction.generation = original.generation
		reaction.exempt = original.exempt
		queue.push(reaction)
	return queue


## One queued effect activation: the operations of one effect, for one fact.
class Reaction:
	extends RefCounted

	## The effect that fired.
	var instance: EffectInstance = null
	## The context its operations run with: a copy of the triggering action's identity. Its engine
	## is set only while it resolves, so a waiting reaction holds no reference to the engine.
	var ctx: EffectContext = null
	## Its queued (not inline) operations, in authored order.
	var operations: Array[EffectOperation] = []
	## How many reactions deep this chain is: 1 for a reaction to a fact rules code recorded.
	var generation: int = 1
	## Whether it counts toward neither cap (a map object's reaction).
	var exempt: bool = false
