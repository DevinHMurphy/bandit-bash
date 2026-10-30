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
## carry that state, as plain JSON, into session snapshots and save sections. A definition the
## loadout made at runtime travels with the instance and restores as itself, never re-resolved
## from the catalog ([Loadout]: staff uses, prefixes, stat changes, an enemy's charge-free use).
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

# A saved stat name that names no stat; never a stat or Modifier.NO_STAT.
const _BAD_STAT: int = -2

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
## reference and its charge limit, its owner, its counters by lane name and its charges. A
## definition no catalog entry names, made only of always-on value and permission changes (one
## the loadout made), is also described in [code]"made"[/code]. [method from_capture] reverses
## it.
## [param reference]: [code]reference(definition) -> String[/code], which then names every
## definition; when invalid, [method catalog_reference].
func capture(reference: Callable = Callable()) -> Dictionary:
	var definition_ref: String = ""
	if reference.is_valid():
		definition_ref = reference.call(definition)
	else:
		definition_ref = EffectInstance.catalog_reference(definition)
	var counters: Dictionary = {}
	for lane: int in EffectTerms.Lane.values():
		counters[EffectTerms.Lane.find_key(lane) as String] = get_counter(lane as EffectTerms.Lane)
	var data: Dictionary = {
		"id": instance_id,
		"definition": definition_ref,
		"definition_charges": 0 if definition == null else definition.charges,
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
	if (
			not reference.is_valid()
			and _is_plain(definition)
			and EffectInstance.catalog_definition(definition_ref) != definition
	):
		data["made"] = _describe_made(definition)
	return data


func _full_charges() -> int:
	if definition == null or definition.charges <= 0:
		return -1
	return definition.charges


## An instance from [method capture] output, also after a trip through JSON, where numbers arrive
## as floats. A [code]"made"[/code] definition is built from its description. Any other is found
## by [param resolve]: [code]resolve(reference) -> EffectDefinition[/code], null for an unknown
## reference; when invalid, [method catalog_definition]. A found definition whose charge limit
## isn't the captured one (an enemy's charge-free use) is copied with the captured limit, as
## [Loadout] made it. Returns [code]null[/code], with an error, when the definition can't be
## found or a field is missing or unknown.
static func from_capture(data: Dictionary, resolve: Callable = Callable()) -> EffectInstance:
	var reference: String = str(data.get("definition", ""))
	var made: Variant = data.get("made", null)
	var limit: Variant = data.get("definition_charges", null)
	var effect: EffectDefinition = null
	if made is Dictionary:
		effect = _made_from(made as Dictionary, reference)
	elif reference.is_empty():
		effect = null
	elif resolve.is_valid():
		effect = resolve.call(reference)
	else:
		effect = EffectInstance.catalog_definition(reference)
	if effect != null and (limit is float or limit is int):
		var limit_number: float = limit
		effect = _with_charges(effect, roundi(limit_number))
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
## an effect inside a catalog carrier (its effects, and a unit type's innate and upgraded
## effects) as [code]<carrier id>#<effect id>[/code], anything else by its own id (empty when it
## has none).
## Ids, not places, so reordering a carrier's effects never breaks a save; the content test
## requires every effect inside a carrier to have an id unique within it (event bus plan,
## question 60). [method catalog_definition] reverses it.
static func catalog_reference(effect: EffectDefinition) -> String:
	if effect == null:
		return ""
	if not effect.id.is_empty() and EffectCatalog.effect(effect.id) == effect:
		return effect.id
	for carrier_id: String in EffectCatalog.ids():
		var carrier: EffectCarrierDefinition = (
				EffectCatalog.definition(carrier_id) as EffectCarrierDefinition
		)
		if carrier != null and _carried_effects(carrier).has(effect):
			return "%s#%s" % [carrier_id, effect.id]
	return effect.id


## The definition a [method catalog_reference] names; null when the catalog has none.
static func catalog_definition(reference: String) -> EffectDefinition:
	var parts: PackedStringArray = reference.split("#")
	if parts.size() == 1:
		return EffectCatalog.effect(reference)
	if parts.size() != 2 or parts[1].is_empty():
		return null
	var carrier: EffectCarrierDefinition = (
			EffectCatalog.definition(parts[0]) as EffectCarrierDefinition
	)
	if carrier == null:
		return null
	for effect: EffectDefinition in _carried_effects(carrier):
		if effect != null and effect.id == parts[1]:
			return effect
	return null


# Every effect carrier holds, in its lists' order: its effects and, for a unit type, its innate
# and upgraded effects.
# NOTE: The same lists as the content test's carrier id rule (tests/content/content_rules.gd,
# _effects_of); keep them in step.
static func _carried_effects(carrier: EffectCarrierDefinition) -> Array[EffectDefinition]:
	var effects: Array[EffectDefinition] = []
	effects.append_array(carrier.effects)
	var unit_type: UnitTypeDefinition = carrier as UnitTypeDefinition
	if unit_type != null:
		effects.append_array(unit_type.innate_effects)
		effects.append_array(unit_type.upgraded_effects)
	return effects


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


# Whether capture() can describe effect: always-on, no conditions, only value and permission
# changes. The shapes the loadout makes at runtime (Loadout._add_runtime, Loadout._staff_uses).
static func _is_plain(effect: EffectDefinition) -> bool:
	if effect == null or effect.trigger != EffectTerms.Trigger.ALWAYS:
		return false
	if not effect.conditions.is_empty():
		return false
	for operation: EffectOperation in effect.operations:
		if operation == null:
			return false
		if operation.get_script() != ModifyValue and operation.get_script() != SetPermission:
			return false
	return true


# A plain definition as JSON: its id, scope, charge lane and tags, and each operation as
# ["modify", key, mode, value, stat] or ["permission", key, allow, stat], keys and enums by name.
# Its charges are the capture's "definition_charges".
static func _describe_made(effect: EffectDefinition) -> Dictionary:
	var operations: Array = []
	for operation: EffectOperation in effect.operations:
		var change: ModifyValue = operation as ModifyValue
		if change != null:
			operations.append([
				"modify",
				Modifier.key_id(change.key),
				Modifier.Mode.find_key(change.mode) as String,
				change.value,
				_stat_name(change.stat),
			])
			continue
		var permission: SetPermission = operation as SetPermission
		operations.append([
			"permission",
			Modifier.key_id(permission.permission),
			permission.allow,
			_stat_name(permission.stat),
		])
	return {
		"id": effect.id,
		"scope": EffectTerms.Scope.find_key(effect.scope) as String,
		"charge_lane": EffectTerms.Lane.find_key(effect.charge_lane) as String,
		"tags": effect.tags,
		"operations": operations,
	}


# The definition _describe_made() described; null, with an error, when anything in it is unknown.
static func _made_from(data: Dictionary, reference: String) -> EffectDefinition:
	var scope_name: String = str(data.get("scope", ""))
	var lane_name: String = str(data.get("charge_lane", ""))
	var tags: Variant = data.get("tags", null)
	var listed: Variant = data.get("operations", null)
	if (
			not EffectTerms.Scope.has(scope_name)
			or not EffectTerms.Lane.has(lane_name)
			or not (tags is float or tags is int)
			or not listed is Array
	):
		push_error("EffectInstance: made definition \"%s\" is malformed - %s" % [reference, data])
		return null
	var effect: EffectDefinition = EffectDefinition.new()
	effect.id = str(data.get("id", ""))
	var scope_value: int = EffectTerms.Scope[scope_name]
	effect.scope = scope_value as EffectTerms.Scope
	var lane_value: int = EffectTerms.Lane[lane_name]
	effect.charge_lane = lane_value as EffectTerms.Lane
	var tag_bits: float = tags
	effect.tags = roundi(tag_bits)
	# Untyped: the parts come from JSON and are checked entry by entry.
	for entry: Variant in listed:
		var operation: EffectOperation = _operation_from(entry)
		if operation == null:
			push_error("EffectInstance: \"%s\" has a malformed operation - %s" % [reference, entry])
			return null
		effect.operations.append(operation)
	return effect


# One operation of a made definition; null when it is malformed or names something unknown.
static func _operation_from(entry: Variant) -> EffectOperation:
	if not entry is Array:
		return null
	var parts: Array = entry
	if parts.size() == 5 and parts[0] == "modify":
		var key: int = Modifier.key_from_id(str(parts[1]))
		var mode_name: String = str(parts[2])
		var stat: int = _stat_from(parts[4])
		if (
				key == Modifier.NO_KEY
				or not Modifier.Mode.has(mode_name)
				or not (parts[3] is float or parts[3] is int)
				or stat == _BAD_STAT
		):
			return null
		var change: ModifyValue = ModifyValue.new()
		change.key = key
		var mode_value: int = Modifier.Mode[mode_name]
		change.mode = mode_value as Modifier.Mode
		var amount: float = parts[3]
		change.value = amount
		change.stat = stat
		return change
	if parts.size() == 4 and parts[0] == "permission":
		var permission_key: int = Modifier.key_from_id(str(parts[1]))
		var permission_stat: int = _stat_from(parts[3])
		if (
				permission_key == Modifier.NO_KEY
				or not parts[2] is bool
				or permission_stat == _BAD_STAT
		):
			return null
		var permission: SetPermission = SetPermission.new()
		permission.permission = permission_key
		var is_allowed: bool = parts[2]
		permission.allow = is_allowed
		permission.stat = permission_stat
		return permission
	return null


# effect with a charge limit of charges: itself when it has that limit, else a copy, so the shared
# .tres is never changed.
# NOTE: The same copy Loadout._without_charges makes for an enemy's charged use, which changes only
# the charges; keep them in step.
static func _with_charges(effect: EffectDefinition, charges: int) -> EffectDefinition:
	if effect.charges == charges:
		return effect
	var copy: EffectDefinition = effect.duplicate()
	copy.charges = charges
	return copy


static func _stat_name(stat: int) -> String:
	return "" if stat == Modifier.NO_STAT else CombatValue.Stat.find_key(stat) as String


# A stat by its saved name: Modifier.NO_STAT for "", _BAD_STAT for a name it doesn't know.
static func _stat_from(value: Variant) -> int:
	var stat_name: String = str(value)
	if stat_name.is_empty():
		return Modifier.NO_STAT
	if not CombatValue.Stat.has(stat_name):
		return _BAD_STAT
	return CombatValue.Stat[stat_name]
