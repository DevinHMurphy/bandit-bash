# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_instance.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name UnitInstance
extends RefCounted
## One unit in a run: its unit type, prefix, level, upgrade, three slots and everything it gained.
##
## The event bus plan's unit contract (Definitions and instances). Stats are computed, never
## stored: the type's bases plus [method stat_sources] (prefix, upgrade, Sidearm, permanent
## deltas), each a sourced modifier through the same value queries as every other, so a breakdown
## names each source. [method stats] answers outside combat; in battle [Loadout] registers the same
## sources as effects. Commanders never use a prefix or an upgrade, so both are ignored on one.[br]
## Plain data with ids only. [method capture] gives plain JSON and [method restore] reads it back;
## the run flow (P08) stores it in its [code]roster[/code] section. Its trait's campaign-lane
## counters and charges are kept by effect id and written back after every battle.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Unit roster): docs/design/unit-roster.md

## [member hp] of a unit at its maximum HP, such as a new recruit.
const FULL_HP: int = -1

## Instance id, such as [code]unit:57[/code]; minted by the run's [InstanceIdAllocator] and never
## parsed. Its combat state on a map has the same id.
var instance_id: String = ""

## Content id of its [UnitTypeDefinition], such as [code]archer[/code].
var unit_type_id: String = ""

## Content id of its [UnitPrefixDefinition]. [b]Empty:[/b] no prefix, the type in its pure form.
var prefix_id: String = ""

## Its level; 1 for a unit that never levelled.
var level: int = 1

## Whether it was upgraded ("Archer+"): the "+" trait, the stat gains and any big change.
var is_upgraded: bool = false

## Item instance id in its Weapon slot. [b]Empty:[/b] unarmed.
var weapon_id: String = ""

## Item instance id in its Equipment slot. [b]Empty:[/b] none.
var equipment_id: String = ""

## Item instance id in its Pouch: a trinket, a consumable or a stowed weapon. [b]Empty:[/b] none.
var pouch_id: String = ""

## Permanent changes to its values, each with its source: stat boosters, Dark Goblet, level-up
## gains, a cooked ingredient's Hit. Keys are [CombatValue] keys. [b]Empty:[/b] none.
var stat_deltas: Array[ItemInstance.StatDelta] = []

## Permanent changes to its growths, each with its source (an eaten ingredient). Keys are
## [enum CombatValue.Stat]s; amounts are percentage points. [b]Empty:[/b] none.
var growth_deltas: Array[ItemInstance.StatDelta] = []

## Gains its next level-ups add on top of their rolls, such as [i]Drink the Sap[/i]'s "+1 MGT, 2
## remaining". Read by the level-up (P08). [b]Empty:[/b] none.
var pending_gains: Array[PendingGain] = []

## Experience toward its next level.[br]
## [b]Units:[/b] XP; 100 per level.
var xp: int = 0

## Current HP, which carries over between battles. [constant FULL_HP]: at its maximum.
var hp: int = FULL_HP

## Charges left of its trait's run-long effects (campaign lane), by effect id. An effect with no
## entry has all its charges.
var charges: Dictionary[String, int] = {}

## Campaign-lane counters of its trait's effects, by effect id. An effect with no entry is at 0.
var counters: Dictionary[String, int] = {}


func _init(id: String = "", unit_type: String = "") -> void:
	instance_id = id
	unit_type_id = unit_type


## Item instance ids in its slots, Weapon, Equipment, then Pouch, empty slots left out.
func item_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for item_id: String in [weapon_id, equipment_id, pouch_id]:
		if not item_id.is_empty():
			ids.append(item_id)
	return ids


## Its values outside combat (the roster screen, a recruit's preview): the type's base stats and
## Stance, then every [method stat_sources] change, sourced. Items and effects aren't counted. An
## unknown unit type gives an empty sheet.
func stats(catalog: EffectCatalog.Index) -> StatSheet:
	var sheet: StatSheet = StatSheet.new(instance_id)
	var unit_type: UnitTypeDefinition = catalog.unit_type(unit_type_id)
	if unit_type == null:
		return sheet
	var bases: Dictionary[int, float] = base_values(unit_type)
	for key: int in bases:
		sheet.set_base(key, bases[key], unit_type.display_name)
	var owner: EffectOwner = EffectOwner.for_unit(instance_id, -1, CombatFact.CombatSide.PLAYER)
	for source: StatSource in stat_sources(catalog):
		# The same conversion the engine makes for an always-on effect, so both sheets agree.
		var holder: EffectInstance = EffectInstance.new(
				instance_id, null, owner, Modifier.SourceKind.UNIT_TRAIT, source.label
		)
		for operation: EffectOperation in source.operations:
			var modifier: Modifier = operation.make_modifier(holder)
			if modifier != null:
				sheet.add_modifier(modifier)
	return sheet


## Its chance to gain [param stat] (a [enum CombatValue.Stat]) on a level-up: the type's growth,
## its prefix's and every growth delta, never below 0.[br]
## [b]Units:[/b] percent.
func growth(catalog: EffectCatalog.Index, stat: int) -> int:
	var unit_type: UnitTypeDefinition = catalog.unit_type(unit_type_id)
	if unit_type == null:
		return 0
	var total: int = unit_type.growths.get(stat, 0)
	var prefix: UnitPrefixDefinition = _prefix(catalog, unit_type)
	if prefix != null:
		total += prefix.growth_deltas.get(stat, 0)
	for delta: ItemInstance.StatDelta in growth_deltas:
		if delta.key == stat:
			total += roundi(delta.amount)
	return maxi(total, 0)


## The effects of its trait: the "+" trait once upgraded, when the type has one, else the trait.
func trait_effects(unit_type: UnitTypeDefinition) -> Array[EffectDefinition]:
	if _upgrade_counts(unit_type) and not unit_type.upgraded_effects.is_empty():
		return unit_type.upgraded_effects
	return unit_type.effects


## Every change on top of its type's bases, one source each, in a fixed order: the prefix, the
## upgrade's stat gains, Sidearm, then each permanent delta's source. Each holds always-on
## operations ([ModifyValue], [SetPermission]). Unknown types and prefixes add nothing.
func stat_sources(catalog: EffectCatalog.Index) -> Array[StatSource]:
	var sources: Array[StatSource] = []
	var unit_type: UnitTypeDefinition = catalog.unit_type(unit_type_id)
	if unit_type == null:
		return sources
	var prefix: UnitPrefixDefinition = _prefix(catalog, unit_type)
	if prefix != null:
		sources.append(_prefix_source(unit_type, prefix))
	if _upgrade_counts(unit_type):
		var upgrade: StatSource = StatSource.new("upgrade", unit_type.display_name + "+")
		for stat: int in unit_type.upgrade_stat_gains:
			upgrade.add(CombatValue.STAT_KEYS[stat], unit_type.upgrade_stat_gains[stat])
		if not upgrade.operations.is_empty():
			sources.append(upgrade)
		if unit_type.grants_sidearm():
			var sidearm: StatSource = StatSource.new("sidearm", "Sidearm")
			var grant: SetPermission = SetPermission.new()
			grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
			sidearm.operations.append(grant)
			sources.append(sidearm)
	var by_source: Dictionary[String, StatSource] = {}
	for delta: ItemInstance.StatDelta in stat_deltas:
		var source_key: String = "%s|%s" % [delta.source_id, delta.label]
		if not by_source.has(source_key):
			by_source[source_key] = StatSource.new("delta:" + delta.source_id, delta.label)
			sources.append(by_source[source_key])
		by_source[source_key].add(delta.key, delta.amount)
	return sources


## This unit as plain JSON, for the run flow's [code]roster[/code] section.
func capture() -> Dictionary:
	return {
		"instance_id": instance_id,
		"unit_type_id": unit_type_id,
		"prefix_id": prefix_id,
		"level": level,
		"is_upgraded": is_upgraded,
		"weapon_id": weapon_id,
		"equipment_id": equipment_id,
		"pouch_id": pouch_id,
		"stat_deltas": _capture_deltas(stat_deltas),
		"growth_deltas": _capture_deltas(growth_deltas),
		"pending_gains": _capture_gains(),
		"xp": xp,
		"hp": hp,
		"charges": charges.duplicate(),
		"counters": counters.duplicate(),
	}


func _prefix(catalog: EffectCatalog.Index, unit_type: UnitTypeDefinition) -> UnitPrefixDefinition:
	if prefix_id.is_empty() or unit_type.is_commander:
		return null
	return catalog.unit_prefix(prefix_id)


func _upgrade_counts(unit_type: UnitTypeDefinition) -> bool:
	return is_upgraded and not unit_type.is_commander


# ASSUMPTION: "no stat can go below 0" (unit-roster.md, Prefixes) limits the prefix's own change,
# so a Feeble Suncaster (MGT 1, prefix -2) has MGT 0; other deltas and effects aren't limited.
func _prefix_source(unit_type: UnitTypeDefinition, prefix: UnitPrefixDefinition) -> StatSource:
	var source: StatSource = StatSource.new("prefix", prefix.display_name)
	for stat: int in prefix.stat_deltas:
		var base: int = unit_type.base_stats.get(stat, 0)
		source.add(CombatValue.STAT_KEYS[stat], maxi(prefix.stat_deltas[stat], -base))
	if prefix.hit_delta != 0:
		source.add(CombatValue.Key.HIT, prefix.hit_delta)
	return source


func _capture_gains() -> Array:
	var gains: Array = []
	for gain: PendingGain in pending_gains:
		gains.append(gain.capture())
	return gains


## The base values a unit of [param unit_type] starts from, value key to number: its seven stats
## (MOV as [constant CombatValue.Key.MOVEMENT]) and its Stance as
## [constant CombatValue.Key.STANCE_MAX]. A stat the type leaves out isn't listed (it is 0).
static func base_values(unit_type: UnitTypeDefinition) -> Dictionary[int, float]:
	var bases: Dictionary[int, float] = {}
	for stat: int in unit_type.base_stats:
		bases[CombatValue.STAT_KEYS[stat]] = float(unit_type.base_stats[stat])
	bases[CombatValue.Key.STANCE_MAX] = float(unit_type.stance)
	return bases


## The unit [param data] describes, as [method capture] wrote it; numbers come back as ints where
## they were ints. Null, with an error, when it isn't a unit's data.
static func restore(data: Dictionary) -> UnitInstance:
	var id: Variant = data.get("instance_id")
	var unit_type: Variant = data.get("unit_type_id")
	if not (id is String and unit_type is String) or (id as String).is_empty():
		push_error("UnitInstance: not a unit's data - %s" % [data])
		return null
	var unit: UnitInstance = UnitInstance.new(id as String, unit_type as String)
	unit.prefix_id = str(data.get("prefix_id", ""))
	unit.level = ItemInstance.read_int(data.get("level"), 1)
	unit.is_upgraded = data.get("is_upgraded", false) == true
	unit.weapon_id = str(data.get("weapon_id", ""))
	unit.equipment_id = str(data.get("equipment_id", ""))
	unit.pouch_id = str(data.get("pouch_id", ""))
	unit.stat_deltas = _restore_deltas(data.get("stat_deltas", []))
	unit.growth_deltas = _restore_deltas(data.get("growth_deltas", []))
	var gains: Variant = data.get("pending_gains", [])
	if gains is Array:
		for entry: Variant in gains as Array:
			if entry is Dictionary:
				unit.pending_gains.append(PendingGain.restore(entry as Dictionary))
	unit.xp = ItemInstance.read_int(data.get("xp"))
	unit.hp = ItemInstance.read_int(data.get("hp"), FULL_HP)
	unit.charges = ItemInstance.read_counts(data.get("charges", {}))
	unit.counters = ItemInstance.read_counts(data.get("counters", {}))
	return unit


static func _capture_deltas(deltas: Array[ItemInstance.StatDelta]) -> Array:
	var captured: Array = []
	for delta: ItemInstance.StatDelta in deltas:
		captured.append(delta.capture())
	return captured


static func _restore_deltas(value: Variant) -> Array[ItemInstance.StatDelta]:
	var deltas: Array[ItemInstance.StatDelta] = []
	if not value is Array:
		return deltas
	for entry: Variant in value as Array:
		if entry is Dictionary:
			deltas.append(ItemInstance.StatDelta.restore(entry as Dictionary))
	return deltas


## One source of changes on top of a unit type's bases: a prefix, an upgrade, Sidearm or a
## permanent delta's source. In battle each becomes one always-on effect on the unit.
class StatSource:
	extends RefCounted

	## Id of the runtime effect it becomes, such as [code]prefix[/code] or
	## [code]delta:dark_goblet[/code]; for logs only.
	var id: String = ""
	## The source's name in breakdowns, such as "Swift" or "Archer+".
	var label: String = ""
	## Its always-on operations.
	var operations: Array[EffectOperation] = []

	func _init(source_id: String, source_label: String) -> void:
		id = source_id
		label = source_label

	## Adds "+[param amount] [param key]".
	func add(key: int, amount: float) -> void:
		var change: ModifyValue = ModifyValue.new()
		change.key = key
		change.value = amount
		operations.append(change)


## Gains a unit's next level-ups add on top of their rolls (the level-up queries, P08).
class PendingGain:
	extends RefCounted

	## The stat gained, a [enum CombatValue.Stat].
	var stat: int = CombatValue.Stat.HP
	## Points per level-up.
	var amount: int = 0
	## Level-ups left that add it.
	var remaining: int = 0
	## Id of what granted it, such as an ingredient's content id. Never parsed.
	var source_id: String = ""
	## The source's name, such as "Drink the Sap".
	var label: String = ""

	## This gain as plain JSON.
	func capture() -> Dictionary:
		return {
			"stat": stat,
			"amount": amount,
			"remaining": remaining,
			"source_id": source_id,
			"label": label,
		}

	## The gain [param data] describes, as [method capture] wrote it.
	static func restore(data: Dictionary) -> PendingGain:
		var gain: PendingGain = PendingGain.new()
		gain.stat = ItemInstance.read_int(data.get("stat"), CombatValue.Stat.HP)
		gain.amount = ItemInstance.read_int(data.get("amount"))
		gain.remaining = ItemInstance.read_int(data.get("remaining"))
		gain.source_id = str(data.get("source_id", ""))
		gain.label = str(data.get("label", ""))
		return gain
