# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_instance.gd
# Author:
# Created:  October 26, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name EffectInstance
extends RefCounted
## The runtime state of one [EffectDefinition] on one owner: its counters, one per lane, and its
## charges.
##
## Definitions are shared and read-only; everything that changes lives here, keyed by
## [member instance_id]. Combat-lane state starts fresh in every battle and moves with the instance
## when its unit changes maps; campaign-lane values are copied in at battle start and written back
## before the battle ends (the session bridge's job). [method capture] and [method from_capture]
## carry that state, as plain JSON, into session snapshots and save sections.
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


## This instance's state as plain JSON values, for snapshots and saves: its definition by
## reference, its owner, its counters by lane name and its charges.
## [method from_capture] reverses it.
## [param reference]: [code]reference(definition) -> String[/code]; when invalid, the catalog's
## (a standalone effect by its id, an effect inside a carrier by the carrier's id and its index).
func capture(reference: Callable = Callable()) -> Dictionary:
	var definition_ref: String = ""
	if reference.is_valid():
		definition_ref = reference.call(definition)
	else:
		definition_ref = EffectInstance.catalog_reference(definition)
	var counters: Dictionary = {}
	for lane: int in EffectTerms.Lane.values():
		counters[EffectTerms.Lane.find_key(lane) as String] = get_counter(lane as EffectTerms.Lane)
	return {
		"id": instance_id,
		"definition": definition_ref,
		"owner": {
			"kind": EffectOwner.Kind.find_key(owner.kind) as String,
			"owner_id": owner.owner_id,
			"holder_id": owner.holder_id,
			"seat": owner.seat,
			"side": CombatFact.CombatSide.find_key(owner.side) as String,
		},
		"source_kind": Modifier.SourceKind.find_key(source_kind) as String,
		"label": label,
		"charges_left": charges_left,
		"counters": counters,
	}


func _full_charges() -> int:
	if definition == null or definition.charges <= 0:
		return -1
	return definition.charges


## An instance from [method capture] output, also after a trip through JSON, where numbers arrive
## as floats. [param resolve]: [code]resolve(reference) -> EffectDefinition[/code], null for an
## unknown reference; when invalid, [method catalog_definition]. Returns [code]null[/code], with
## an error, when the definition can't be found or a field is missing or unknown.
static func from_capture(data: Dictionary, resolve: Callable = Callable()) -> EffectInstance:
	var reference: String = str(data.get("definition", ""))
	var effect: EffectDefinition = null
	if reference.is_empty():
		effect = null
	elif resolve.is_valid():
		effect = resolve.call(reference)
	else:
		effect = EffectInstance.catalog_definition(reference)
	var owner_data: Variant = data.get("owner", null)
	var counters: Variant = data.get("counters", null)
	var kind_name: String = str(data.get("source_kind", ""))
	var charges: Variant = data.get("charges_left", null)
	var id: String = str(data.get("id", ""))
	if (
			effect == null
			or id.is_empty()
			or not owner_data is Dictionary
			or not counters is Dictionary
			or not Modifier.SourceKind.has(kind_name)
			or not (charges is float or charges is int)
	):
		push_error("EffectInstance: can't restore %s (definition \"%s\")" % [id, reference])
		return null
	var effect_owner: EffectOwner = _owner_from(owner_data as Dictionary)
	if effect_owner == null:
		push_error("EffectInstance: %s has a malformed owner - %s" % [id, owner_data])
		return null
	var kind_value: int = Modifier.SourceKind[kind_name]
	var instance: EffectInstance = EffectInstance.new(
			id, effect, effect_owner, kind_value as Modifier.SourceKind, str(data.get("label", ""))
	)
	var charges_number: float = charges
	instance.charges_left = roundi(charges_number)
	var lanes: Dictionary = counters
	for lane_name: Variant in lanes:
		var count: Variant = lanes[lane_name]
		if not EffectTerms.Lane.has(lane_name) or not (count is float or count is int):
			push_error("EffectInstance: %s has a malformed counter - %s" % [id, lanes])
			return null
		var lane: int = EffectTerms.Lane[lane_name]
		var count_number: float = count
		instance.set_counter(lane as EffectTerms.Lane, roundi(count_number))
	return instance


## How [method capture] names [param effect] by default: a standalone catalog effect by its id,
## an effect inside a catalog carrier as [code]<carrier id>#<index>[/code], anything else by its
## own id (empty when it has none). [method catalog_definition] reverses it.
# ASSUMPTION: an effect inside a carrier has no id of its own in the catalog (EffectCatalog.effect
# finds only standalone ones), so a saved instance names it by its carrier and its index there.
static func catalog_reference(effect: EffectDefinition) -> String:
	if effect == null:
		return ""
	if not effect.id.is_empty() and EffectCatalog.effect(effect.id) == effect:
		return effect.id
	for carrier_id: String in EffectCatalog.ids():
		var carrier: EffectCarrierDefinition = (
				EffectCatalog.definition(carrier_id) as EffectCarrierDefinition
		)
		if carrier == null:
			continue
		var index: int = carrier.effects.find(effect)
		if index >= 0:
			return "%s#%d" % [carrier_id, index]
	return effect.id


## The definition a [method catalog_reference] names; null when the catalog has none.
static func catalog_definition(reference: String) -> EffectDefinition:
	var parts: PackedStringArray = reference.split("#")
	if parts.size() == 1:
		return EffectCatalog.effect(reference)
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var carrier: EffectCarrierDefinition = (
			EffectCatalog.definition(parts[0]) as EffectCarrierDefinition
	)
	var index: int = parts[1].to_int()
	if carrier == null or index < 0 or index >= carrier.effects.size():
		return null
	return carrier.effects[index]


static func _owner_from(data: Dictionary) -> EffectOwner:
	var kind_name: String = str(data.get("kind", ""))
	var side_name: String = str(data.get("side", ""))
	var seat: Variant = data.get("seat", null)
	if (
			not EffectOwner.Kind.has(kind_name)
			or not CombatFact.CombatSide.has(side_name)
			or not (seat is float or seat is int)
	):
		return null
	var kind_value: int = EffectOwner.Kind[kind_name]
	var side_value: int = CombatFact.CombatSide[side_name]
	var seat_number: float = seat
	var effect_owner: EffectOwner = EffectOwner.new()
	effect_owner.kind = kind_value as EffectOwner.Kind
	effect_owner.owner_id = str(data.get("owner_id", ""))
	effect_owner.holder_id = str(data.get("holder_id", ""))
	effect_owner.seat = roundi(seat_number)
	effect_owner.side = side_value as CombatFact.CombatSide
	return effect_owner
