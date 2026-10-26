# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_bus.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name CombatBus
extends RefCounted
## Presentation signals for one combat session's facts, grouped by domain.
##
## Each combat session (one per map) owns one bus. Facts reach it only during playback, on every
## peer, in fact order: [method play] emits the fact's domain signal, then [signal fact_played].
## Connect as [code]bus.action.hit_taken.connect(_on_hit_taken)[/code].[br]
## [b]Presentation and observers only.[/b] Nothing connected here may change rules state, and
## effects never listen here: they react through the effect engine's dispatch, which is
## deterministic, queued, and can run in a forecast without side effects.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Emitted for every fact, after its domain signal. Used by [BusTracer] and spectating.
signal fact_played(fact: CombatFact)

## Phases, unit turns and the end of combat.
var flow: FlowChannel = FlowChannel.new()

## What happens to a unit: moves, spawns, HP, Block, Stance, defeat.
var unit: UnitChannel = UnitChannel.new()

## Exchanges, attacks, hits, shoves, and the other actions: objects, items, swaps, runes, Wait.
var action: ActionChannel = ActionChannel.new()

## The map itself: the darkness and map objects.
var world: WorldChannel = WorldChannel.new()

## Effect activations, counters and timed modifiers.
var effect: EffectChannel = EffectChannel.new()

# The channel each CombatFact.Kind plays on.
var _channel_by_kind: Dictionary[int, BusChannel] = {}


func _init() -> void:
	var channels: Array[BusChannel] = [flow, unit, action, world, effect]
	for channel: BusChannel in channels:
		for kind: int in channel.get_kinds():
			_channel_by_kind[kind] = channel


## Plays [param fact]: its domain signal, then [signal fact_played].
##
## Call only from playback, in fact order. A kind with no channel is a bug in this class; it is
## reported and still reaches [signal fact_played].
func play(fact: CombatFact) -> void:
	var channel: BusChannel = _channel_by_kind.get(fact.kind, null)
	if channel == null:
		push_error("CombatBus: no channel for kind %d" % [fact.kind])
	else:
		channel.emit_fact(fact.kind, fact)
	fact_played.emit(fact)


## Phases, unit turns and the end of combat.
class FlowChannel:
	extends BusChannel

	## [constant CombatFact.PHASE_START].
	signal phase_started(fact: CombatFact)
	## [constant CombatFact.PHASE_END].
	signal phase_ended(fact: CombatFact)
	## [constant CombatFact.UNIT_TURN_START].
	signal unit_turn_started(fact: CombatFact)
	## [constant CombatFact.UNIT_TURN_END].
	signal unit_turn_ended(fact: CombatFact)
	## [constant CombatFact.COMBAT_ENDED].
	signal combat_ended(fact: CombatFact)

	func _init() -> void:
		_route(CombatFact.Kind.PHASE_START, phase_started)
		_route(CombatFact.Kind.PHASE_END, phase_ended)
		_route(CombatFact.Kind.UNIT_TURN_START, unit_turn_started)
		_route(CombatFact.Kind.UNIT_TURN_END, unit_turn_ended)
		_route(CombatFact.Kind.COMBAT_ENDED, combat_ended)


## What happens to a unit: moves, spawns, HP, Block, Stance, defeat.
class UnitChannel:
	extends BusChannel

	## [constant CombatFact.UNIT_MOVED].
	signal moved(fact: CombatFact)
	## [constant CombatFact.UNIT_SPAWNED].
	signal spawned(fact: CombatFact)
	## [constant CombatFact.HEALED].
	signal healed(fact: CombatFact)
	## [constant CombatFact.BLOCK_GAINED].
	signal block_gained(fact: CombatFact)
	## [constant CombatFact.EXPOSED].
	signal exposed(fact: CombatFact)
	## [constant CombatFact.DEFEATED].
	signal defeated(fact: CombatFact)
	## [constant CombatFact.DARKNESS_DAMAGE_TAKEN].
	signal darkness_damage_taken(fact: CombatFact)
	## [constant CombatFact.BLOCK_STANCE_REFRESHED].
	signal block_stance_refreshed(fact: CombatFact)
	## [constant CombatFact.STANCE_CHANGED].
	signal stance_changed(fact: CombatFact)
	## [constant CombatFact.BLOCK_LOST].
	signal block_lost(fact: CombatFact)

	func _init() -> void:
		_route(CombatFact.Kind.UNIT_MOVED, moved)
		_route(CombatFact.Kind.UNIT_SPAWNED, spawned)
		_route(CombatFact.Kind.HEALED, healed)
		_route(CombatFact.Kind.BLOCK_GAINED, block_gained)
		_route(CombatFact.Kind.EXPOSED, exposed)
		_route(CombatFact.Kind.DEFEATED, defeated)
		_route(CombatFact.Kind.DARKNESS_DAMAGE_TAKEN, darkness_damage_taken)
		_route(CombatFact.Kind.BLOCK_STANCE_REFRESHED, block_stance_refreshed)
		_route(CombatFact.Kind.STANCE_CHANGED, stance_changed)
		_route(CombatFact.Kind.BLOCK_LOST, block_lost)


## Exchanges, attacks, hits, shoves, and the other actions: objects, items, swaps, runes, Wait.
class ActionChannel:
	extends BusChannel

	## [constant CombatFact.BEFORE_COMBAT].
	signal exchange_started(fact: CombatFact)
	## [constant CombatFact.AFTER_COMBAT].
	signal exchange_ended(fact: CombatFact)
	## [constant CombatFact.ATTACK_MADE].
	signal attack_made(fact: CombatFact)
	## [constant CombatFact.HIT_DEALT].
	signal hit_dealt(fact: CombatFact)
	## [constant CombatFact.HIT_TAKEN].
	signal hit_taken(fact: CombatFact)
	## [constant CombatFact.MISSED].
	signal missed(fact: CombatFact)
	## [constant CombatFact.DODGED].
	signal dodged(fact: CombatFact)
	## [constant CombatFact.DAMAGE_DEALT].
	signal damage_dealt(fact: CombatFact)
	## [constant CombatFact.DAMAGE_TAKEN].
	signal damage_taken(fact: CombatFact)
	## [constant CombatFact.CRIT_DEALT].
	signal crit_dealt(fact: CombatFact)
	## [constant CombatFact.CRIT_TAKEN].
	signal crit_taken(fact: CombatFact)
	## [constant CombatFact.DEFEATED_AN_ENEMY].
	signal defeated_enemy(fact: CombatFact)
	## [constant CombatFact.HEALED_AN_ALLY].
	signal healed_ally(fact: CombatFact)
	## [constant CombatFact.USED_STAFF_ON_ALLY].
	signal staff_used_on_ally(fact: CombatFact)
	## [constant CombatFact.SHOVED_A_UNIT].
	signal shoved_unit(fact: CombatFact)
	## [constant CombatFact.SHOVED].
	signal shoved(fact: CombatFact)
	## [constant CombatFact.OBJECT_USED].
	signal object_used(fact: CombatFact)
	## [constant CombatFact.ITEM_USED].
	signal item_used(fact: CombatFact)
	## [constant CombatFact.WEAPON_SWAPPED].
	signal weapon_swapped(fact: CombatFact)
	## [constant CombatFact.RUNE_USED].
	signal rune_used(fact: CombatFact)
	## [constant CombatFact.UNIT_WAITED].
	signal waited(fact: CombatFact)

	func _init() -> void:
		_route(CombatFact.Kind.BEFORE_COMBAT, exchange_started)
		_route(CombatFact.Kind.AFTER_COMBAT, exchange_ended)
		_route(CombatFact.Kind.ATTACK_MADE, attack_made)
		_route(CombatFact.Kind.HIT_DEALT, hit_dealt)
		_route(CombatFact.Kind.HIT_TAKEN, hit_taken)
		_route(CombatFact.Kind.MISSED, missed)
		_route(CombatFact.Kind.DODGED, dodged)
		_route(CombatFact.Kind.DAMAGE_DEALT, damage_dealt)
		_route(CombatFact.Kind.DAMAGE_TAKEN, damage_taken)
		_route(CombatFact.Kind.CRIT_DEALT, crit_dealt)
		_route(CombatFact.Kind.CRIT_TAKEN, crit_taken)
		_route(CombatFact.Kind.DEFEATED_AN_ENEMY, defeated_enemy)
		_route(CombatFact.Kind.HEALED_AN_ALLY, healed_ally)
		_route(CombatFact.Kind.USED_STAFF_ON_ALLY, staff_used_on_ally)
		_route(CombatFact.Kind.SHOVED_A_UNIT, shoved_unit)
		_route(CombatFact.Kind.SHOVED, shoved)
		_route(CombatFact.Kind.OBJECT_USED, object_used)
		_route(CombatFact.Kind.ITEM_USED, item_used)
		_route(CombatFact.Kind.WEAPON_SWAPPED, weapon_swapped)
		_route(CombatFact.Kind.RUNE_USED, rune_used)
		_route(CombatFact.Kind.UNIT_WAITED, waited)


## The map itself: the darkness and map objects.
class WorldChannel:
	extends BusChannel

	## [constant CombatFact.DARKNESS_ADVANCED].
	signal darkness_advanced(fact: CombatFact)
	## [constant CombatFact.OBJECT_STATE_CHANGED].
	signal object_state_changed(fact: CombatFact)

	func _init() -> void:
		_route(CombatFact.Kind.DARKNESS_ADVANCED, darkness_advanced)
		_route(CombatFact.Kind.OBJECT_STATE_CHANGED, object_state_changed)


## Effect activations, counters and timed modifiers.
class EffectChannel:
	extends BusChannel

	## [constant CombatFact.EFFECT_ACTIVATED].
	signal activated(fact: CombatFact)
	## [constant CombatFact.COUNTER_CHANGED].
	signal counter_changed(fact: CombatFact)
	## [constant CombatFact.MODIFIER_GAINED].
	signal modifier_gained(fact: CombatFact)
	## [constant CombatFact.MODIFIER_EXPIRED].
	signal modifier_expired(fact: CombatFact)

	func _init() -> void:
		_route(CombatFact.Kind.EFFECT_ACTIVATED, activated)
		_route(CombatFact.Kind.COUNTER_CHANGED, counter_changed)
		_route(CombatFact.Kind.MODIFIER_GAINED, modifier_gained)
		_route(CombatFact.Kind.MODIFIER_EXPIRED, modifier_expired)
