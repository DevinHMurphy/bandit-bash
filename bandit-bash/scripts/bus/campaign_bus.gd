# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_bus.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name CampaignBus
extends RefCounted
## Presentation signals for the campaign layer's facts, grouped by domain.
##
## The campaign counterpart of [CombatBus], owned by the run's campaign session. Facts reach it
## only during playback, on every peer, in fact order: [method play] emits the fact's domain
## signal, then [signal fact_played].[br]
## [b]Presentation and observers only.[/b] Nothing connected here may change rules state, and
## effects never listen here; they react through the effect engine's dispatch.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Emitted for every fact, after its domain signal. Used by [BusTracer].
signal fact_played(fact: CampaignFact)

## The run's progress: combats ending.
var run: RunChannel = RunChannel.new()

## A player's army: heirlooms and items gained, level-ups.
var army: ArmyChannel = ArmyChannel.new()

## Effect activations and counters.
var effect: EffectChannel = EffectChannel.new()

# The channel each CampaignFact.Kind plays on.
var _channel_by_kind: Dictionary[int, BusChannel] = {}


func _init() -> void:
	var channels: Array[BusChannel] = [run, army, effect]
	for channel: BusChannel in channels:
		for kind: int in channel.get_kinds():
			_channel_by_kind[kind] = channel


## Plays [param fact]: its domain signal, then [signal fact_played].
##
## Call only from playback, in fact order. A kind with no channel is a bug in this class; it is
## reported and still reaches [signal fact_played].
func play(fact: CampaignFact) -> void:
	var channel: BusChannel = _channel_by_kind.get(fact.kind, null)
	if channel == null:
		push_error("CampaignBus: no channel for kind %d" % [fact.kind])
	else:
		channel.emit_fact(fact.kind, fact)
	fact_played.emit(fact)


## The run's progress: combats ending.
class RunChannel:
	extends BusChannel

	## [constant CampaignFact.COMBAT_ENDED].
	signal combat_ended(fact: CampaignFact)

	func _init() -> void:
		_route(CampaignFact.Kind.COMBAT_ENDED, combat_ended)


## A player's army: heirlooms and items gained, level-ups.
class ArmyChannel:
	extends BusChannel

	## [constant CampaignFact.GAINED].
	signal gained(fact: CampaignFact)
	## [constant CampaignFact.LEVELED_UP].
	signal leveled_up(fact: CampaignFact)

	func _init() -> void:
		_route(CampaignFact.Kind.GAINED, gained)
		_route(CampaignFact.Kind.LEVELED_UP, leveled_up)


## Effect activations and counters.
class EffectChannel:
	extends BusChannel

	## [constant CampaignFact.EFFECT_ACTIVATED].
	signal activated(fact: CampaignFact)
	## [constant CampaignFact.COUNTER_CHANGED].
	signal counter_changed(fact: CampaignFact)

	func _init() -> void:
		_route(CampaignFact.Kind.EFFECT_ACTIVATED, activated)
		_route(CampaignFact.Kind.COUNTER_CHANGED, counter_changed)
