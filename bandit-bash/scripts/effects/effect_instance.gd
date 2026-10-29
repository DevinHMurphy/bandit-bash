# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_instance.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name EffectInstance
extends RefCounted
## The runtime state of one [EffectDefinition] on one owner: its counters, one per lane, and its
## charges.
##
## Definitions are shared and read-only; everything that changes lives here, keyed by
## [member instance_id]. Combat-lane state starts fresh in every battle and moves with the instance
## when its unit changes maps; campaign-lane values are copied in at battle start and written back
## before the battle ends (the session bridge's job).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## Allocator id, such as [code]effect:12[/code]. Never parsed; breaks reaction-order ties.
var instance_id: String = ""

## The shared definition. Never modified.
var definition: EffectDefinition = null

## Who the effect belongs to.
var owner: EffectOwner = null

## The kind of carrier it comes from: reaction order and override specificity.
var source_kind: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT

## Display name of the carrier for breakdown text, such as "Iron Skin".
var label: String = ""

## Charges left in [member EffectDefinition.charge_lane]'s period; [code]-1[/code] when the
## definition has no limit.
var charges_left: int = -1

# Count per lane (EffectTerms.Lane); a lane with no entry is at 0.
var _counters: Dictionary[int, int] = {}


func _init(
		id: String,
		effect: EffectDefinition,
		effect_owner: EffectOwner,
		kind: Modifier.SourceKind,
		carrier_label: String = ""
) -> void:
	instance_id = id
	definition = effect
	owner = effect_owner
	source_kind = kind
	label = carrier_label
	charges_left = _full_charges()


## The count of [param lane]'s counter.
func get_counter(lane: EffectTerms.Lane) -> int:
	return _counters.get(lane, 0)


## Sets [param lane]'s counter, such as a campaign-lane value copied in at battle start.
func set_counter(lane: EffectTerms.Lane, value: int) -> void:
	_counters[lane] = value


## Whether the effect may still fire: it has no charge limit or a charge left.
func has_charge() -> bool:
	return charges_left != 0


## Spends one charge, if the definition has a limit.
func spend_charge() -> void:
	if charges_left > 0:
		charges_left -= 1


## Starts [param lane]'s period over: its counter goes to 0 and, if the charges refill in that
## lane, they refill.
func reset_lane(lane: EffectTerms.Lane) -> void:
	_counters.erase(lane)
	if definition != null and definition.charge_lane == lane:
		charges_left = _full_charges()


## A copy with the same state, for a sandbox. The definition stays shared.
func copy() -> EffectInstance:
	var instance: EffectInstance = EffectInstance.new(
			instance_id, definition, owner.copy(), source_kind, label
	)
	instance.charges_left = charges_left
	for lane: int in _counters:
		instance.set_counter(lane as EffectTerms.Lane, _counters[lane])
	return instance


func _full_charges() -> int:
	if definition == null or definition.charges <= 0:
		return -1
	return definition.charges
