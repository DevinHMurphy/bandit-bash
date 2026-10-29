# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     loadout.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name Loadout
extends RefCounted
## The loadout step: turns a unit's and its items' instances, with their definitions, into what a
## battle places, for player and enemy units alike (content catalog plan, questions 4 and 14).
##
## [method load_unit] builds the [CombatUnitState] (type, role, tags, movement type, HP, slots),
## its base values (the type's seven stats and Stance), one weapon record per carried weapon from
## its [WeaponDefinition], and its effect instances: the trait (the "+" trait once upgraded),
## innate effects, each [method UnitInstance.stat_sources] change, and each carried item's
## effects, granted effects, weapon prefix and stat deltas. Every change on top of a base is an
## always-on effect sourced to what made it, so breakdowns name it; a stowed weapon's sleep with
## it (event bus plan, fix F8). [method heirloom_effects] builds a seat's heirloom carriers.[br]
## Campaign-lane counters and charges are copied in from the instances and back out by
## [method LoadedUnit.write_back]. Bad data (an unknown id, gear in the wrong slot) is reported in
## [member LoadedUnit.problems] and skipped, never guessed at. Static and pure: it reads only the
## [EffectCatalog.Index] it is given, and mints ids only from the allocator it is given.
##
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md
##
## @todo: TOD-001 - Build an area staff's [Area] from its [member StaffDefinition.area_shape_id]
## (P03 CT6); until then a staff covers its target only.

## A unit's three item slots (game-vision.md, Units: Inventory). Never saved.
enum Slot {
	## The weapon or tool in hand.
	WEAPON,
	## One piece of passive gear.
	EQUIPMENT,
	## One trinket or consumable, or a stowed weapon.
	POUCH,
}

# What each staff kind does in combat. A status staff is a stub until status effects exist.
const _STAFF_KINDS: Dictionary[String, int] = {
	ContentIds.STAFF_BLOCK: CombatState.WeaponStats.Staff.BLOCK,
	ContentIds.STAFF_HEAL: CombatState.WeaponStats.Staff.HEAL,
	ContentIds.STAFF_ATTACK: CombatState.WeaponStats.Staff.ATTACK,
}

# The only scaling combat reads: every MVP weapon adds Might one-for-one ([DamagePipeline]).
const _SCALING_STAT: CombatValue.Stat = CombatValue.Stat.MGT


## Loads [param unit] for a battle, on [param side] for [param seat] ([code]-1[/code] for an
## enemy). [param items]: the item instances it may carry, by instance id. Its effect ids come
## from [param ids]. Read [member LoadedUnit.problems]; [member LoadedUnit.state] is null when
## its unit type is unknown.
static func load_unit(
		catalog: EffectCatalog.Index,
		unit: UnitInstance,
		items: Dictionary[String, ItemInstance],
		side: CombatFact.CombatSide,
		seat: int,
		ids: InstanceIdAllocator
) -> LoadedUnit:
	var loaded: LoadedUnit = LoadedUnit.new()
	var unit_type: UnitTypeDefinition = catalog.unit_type(unit.unit_type_id)
	if unit_type == null:
		loaded.problems.append("%s: unit type \"%s\" is not in the catalog" % [
			unit.instance_id, unit.unit_type_id,
		])
		return loaded
	_check_unit(loaded, catalog, unit, unit_type)

	var state: CombatUnitState = CombatUnitState.new()
	state.id = unit.instance_id
	state.side = side
	state.seat = seat
	state.unit_type = unit_type.id
	state.role = unit_type.role
	state.movement_type = unit_type.movement_type
	var tags: PackedStringArray = unit_type.tags.duplicate()
	var weapon_types: PackedStringArray = unit_type.weapon_types.duplicate()
	if unit.is_upgraded and not unit_type.is_commander:
		if unit_type.upgrade_changes_movement():
			state.movement_type = unit_type.upgrade_movement_type as CombatGrid.MovementType
		_append_new(tags, unit_type.upgrade_tags)
		_append_new(weapon_types, unit_type.upgrade_weapon_types)
	_check_listed(loaded, unit.instance_id, "tag", tags, ContentIds.TAGS)
	_check_listed(loaded, unit.instance_id, "weapon type", weapon_types, ContentIds.WEAPON_TYPES)
	state.tags = tags
	var max_hp: int = unit.stats(catalog).get_int(CombatValue.Key.HP)
	state.hp = max_hp if unit.hp == UnitInstance.FULL_HP else mini(unit.hp, max_hp)
	loaded.state = state
	loaded.bases = UnitInstance.base_values(unit_type)

	var owner: EffectOwner = EffectOwner.for_unit(unit.instance_id, seat, side)
	var trait_label: String = unit_type.trait_label(unit.is_upgraded and not unit_type.is_commander)
	if trait_label.is_empty():
		trait_label = unit_type.display_name
	var trait_home: CounterHome = CounterHome.new(unit.counters, unit.charges)
	_add_effects(loaded, ids, unit.trait_effects(unit_type), owner, trait_label, trait_home)
	_add_effects(loaded, ids, unit_type.innate_effects, owner, unit_type.display_name, trait_home)
	for source: UnitInstance.StatSource in unit.stat_sources(catalog):
		_add_runtime(loaded, ids, source.id, source.operations, owner, source.label)

	_load_slot(loaded, catalog, ids, items, unit.weapon_id, Slot.WEAPON, weapon_types)
	_load_slot(loaded, catalog, ids, items, unit.equipment_id, Slot.EQUIPMENT, weapon_types)
	_load_slot(loaded, catalog, ids, items, unit.pouch_id, Slot.POUCH, weapon_types)
	return loaded


## The effects of the heirloom or curse [param heirloom_id], owned by [param seat]'s army, in its
## list's order, ids from [param ids]. Add them to the run as carriers once, so their
## campaign-lane counters live there between battles. Empty when the catalog has no such heirloom.
static func heirloom_effects(
		catalog: EffectCatalog.Index, heirloom_id: String, seat: int, ids: InstanceIdAllocator
) -> Array[EffectInstance]:
	var instances: Array[EffectInstance] = []
	var heirloom: HeirloomDefinition = catalog.heirloom(heirloom_id)
	if heirloom == null:
		return instances
	var owner: EffectOwner = EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(seat), seat)
	var kind: Modifier.SourceKind = (
			Modifier.SourceKind.CURSE if heirloom is CurseDefinition
			else Modifier.SourceKind.HEIRLOOM
	)
	for effect: EffectDefinition in heirloom.effects:
		if effect != null:
			instances.append(EffectInstance.new(
					ids.next_effect_id(heirloom.display_name), effect, owner, kind,
					heirloom.display_name
			))
	return instances


## The combat record of [param definition], a weapon or staff, for the item [param item_id]: its
## numbers as the definition gives them. A prefix and deltas never change it; they apply as effects.
static func weapon_record(definition: WeaponDefinition, item_id: String) -> CombatState.WeaponStats:
	var record: CombatState.WeaponStats = CombatState.WeaponStats.new()
	record.id = item_id
	record.label = definition.display_name
	record.weapon_type = definition.weapon_type
	record.damage = definition.damage
	record.atk_x = definition.atk_x
	record.profile = definition.profile
	record.range_min = definition.range_min
	record.range_max = definition.range_max
	record.hit = definition.hit
	record.crit = definition.crit
	record.crit_x = definition.crit_x
	record.weight = definition.weight
	record.damage_type = definition.damage_type
	record.effective_against = definition.effective_against.duplicate()
	if definition is StaffDefinition:
		var staff: StaffDefinition = definition
		var does: int = _STAFF_KINDS.get(staff.staff_kind, CombatState.WeaponStats.Staff.NONE)
		record.staff = does as CombatState.WeaponStats.Staff
		record.staff_amount = staff.base_amount
		# TODO(TOD-001): Set record.area from staff.area_shape_id once Area reads a TargetShape.
	return record


static func _check_unit(
		loaded: LoadedUnit,
		catalog: EffectCatalog.Index,
		unit: UnitInstance,
		unit_type: UnitTypeDefinition
) -> void:
	var who: String = unit.instance_id
	if unit_type.is_commander and (not unit.prefix_id.is_empty() or unit.is_upgraded):
		loaded.problems.append(
				"%s: a commander never has a prefix or an upgrade; both are ignored" % [who]
		)
	elif not unit.prefix_id.is_empty() and catalog.unit_prefix(unit.prefix_id) == null:
		loaded.problems.append("%s: prefix \"%s\" is not in the catalog" % [who, unit.prefix_id])


# Loads the item in one slot: its record if it is a weapon, its place in the unit's state, and
# its effects. Gear that doesn't fit the slot is reported and left out.
static func _load_slot(
		loaded: LoadedUnit,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator,
		items: Dictionary[String, ItemInstance],
		item_id: String,
		slot: Slot,
		weapon_types: PackedStringArray
) -> void:
	if item_id.is_empty():
		return
	var who: String = loaded.state.id
	var item: ItemInstance = items.get(item_id, null)
	if item == null:
		loaded.problems.append("%s: item %s is not among the item instances" % [who, item_id])
		return
	var definition: ItemDefinition = catalog.item(item.definition_id)
	if definition == null:
		loaded.problems.append("%s: item %s's definition \"%s\" is not in the catalog" % [
			who, item_id, item.definition_id,
		])
		return
	var kind: Modifier.SourceKind = Modifier.SourceKind.POUCH_ITEM
	var state: CombatUnitState = loaded.state
	var fits: bool = true
	match slot:
		Slot.WEAPON:
			fits = definition is WeaponDefinition
			state.equipped_weapon_id = item_id if fits else ""
			kind = Modifier.SourceKind.WEAPON
		Slot.EQUIPMENT:
			fits = definition is EquipmentDefinition
			state.equipment_id = item_id if fits else ""
			kind = Modifier.SourceKind.EQUIPMENT
		Slot.POUCH:
			fits = not definition is EquipmentDefinition
			if definition is WeaponDefinition:
				state.stowed_weapon_id = item_id
				kind = Modifier.SourceKind.WEAPON
			elif fits:
				state.pouch_item_id = item_id
	if not fits:
		loaded.problems.append("%s: %s (%s) doesn't fit its %s slot" % [
			who, item_id, item.definition_id, (Slot.find_key(slot) as String).to_lower(),
		])
		return
	if definition is WeaponDefinition:
		var weapon: WeaponDefinition = definition
		_check_weapon(loaded, item, weapon, weapon_types)
		loaded.weapons.append(weapon_record(weapon, item_id))
	_add_item_effects(loaded, catalog, ids, item, definition, kind)


static func _check_weapon(
		loaded: LoadedUnit,
		item: ItemInstance,
		weapon: WeaponDefinition,
		weapon_types: PackedStringArray
) -> void:
	var where: String = "%s: %s (%s)" % [loaded.state.id, item.instance_id, item.definition_id]
	if not weapon_types.has(weapon.weapon_type):
		loaded.problems.append("%s is a %s, which it can't wield" % [where, weapon.weapon_type])
	if weapon.scaling_stat != _SCALING_STAT or not is_equal_approx(weapon.scaling_modifier, 1.0):
		loaded.problems.append("%s scales other than Might x1, which combat doesn't read" % [where])
	if weapon is StaffDefinition:
		var staff: StaffDefinition = weapon
		if not _STAFF_KINDS.has(staff.staff_kind):
			loaded.problems.append("%s is a %s staff, which combat can't use" % [
				where, staff.staff_kind,
			])


# The item's own effects, its granted effects, its weapon prefix and its stat deltas, all owned by
# the item and acting through the unit carrying it.
static func _add_item_effects(
		loaded: LoadedUnit,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator,
		item: ItemInstance,
		definition: ItemDefinition,
		kind: Modifier.SourceKind
) -> void:
	var state: CombatUnitState = loaded.state
	var owner: EffectOwner = EffectOwner.for_item(
			item.instance_id, state.id, state.seat, state.side
	)
	var label: String = definition.display_name
	var home: CounterHome = CounterHome.new(item.counters, item.charges)
	_add_effects(loaded, ids, definition.effects, owner, label, home, kind)
	var granted: Array[EffectDefinition] = []
	for effect_id: String in item.granted_effect_ids:
		var effect: EffectDefinition = catalog.effect(effect_id)
		if effect == null:
			loaded.problems.append("%s: granted effect \"%s\" is not in the catalog" % [
				item.instance_id, effect_id,
			])
		else:
			granted.append(effect)
	_add_effects(loaded, ids, granted, owner, label, home, kind)

	if not item.prefix_id.is_empty():
		var prefix: WeaponPrefixDefinition = catalog.weapon_prefix(item.prefix_id)
		if prefix == null or not definition is WeaponDefinition:
			loaded.problems.append("%s: weapon prefix \"%s\" is unknown or not on a weapon" % [
				item.instance_id, item.prefix_id,
			])
		else:
			_add_runtime(loaded, ids, "prefix", _prefix_operations(prefix), owner, (
					prefix.display_name
			), kind)
	if definition is EquipmentDefinition and definition.weight != 0:
		var weight: Array[EffectOperation] = [
			_add_operation(CombatValue.Key.NET_WEIGHT, definition.weight),
		]
		_add_runtime(loaded, ids, "weight", weight, owner, label, kind)
	var by_source: Dictionary[String, Array] = {}
	var labels: Dictionary[String, String] = {}
	for delta: ItemInstance.StatDelta in item.stat_deltas:
		var source_key: String = "%s|%s" % [delta.source_id, delta.label]
		if not by_source.has(source_key):
			var operations: Array[EffectOperation] = []
			by_source[source_key] = operations
			labels[source_key] = delta.label
		by_source[source_key].append(_add_operation(delta.key, delta.amount))
	for source_key: String in by_source:
		var operations: Array[EffectOperation] = []
		operations.assign(by_source[source_key])
		_add_runtime(loaded, ids, "delta:" + source_key.get_slice("|", 0), operations, owner, (
				labels[source_key]
		), kind)


# ASSUMPTION: a damage prefix adds to the Attack stage, so the triangle and effectiveness still
# measure the weapon's own damage (DamagePipeline reads them from the record), and a range prefix
# changes the longest range only (content catalog plan, question 18 (e)). No MVP weapon rolls one.
static func _prefix_operations(prefix: WeaponPrefixDefinition) -> Array[EffectOperation]:
	var operations: Array[EffectOperation] = []
	var changes: Dictionary[int, float] = {
		DamageStage.Key.ATTACK: prefix.damage_delta,
		CombatValue.Key.HIT: prefix.hit_delta,
		CombatValue.Key.CRIT_CHANCE: prefix.crit_delta,
		CombatValue.Key.CRIT_X: prefix.crit_x_delta,
		CombatValue.Key.ATK_X: prefix.atk_x_delta,
		CombatValue.Key.NET_WEIGHT: prefix.weight_delta,
		CombatValue.Key.RANGE_MAX: prefix.range_max_delta,
	}
	for key: int in changes:
		if not is_zero_approx(changes[key]):
			operations.append(_add_operation(key, changes[key]))
	return operations


# One instance per effect of [param effects], each keeping its campaign-lane state in [param home]
# by its key ([method CounterHome.for_effect]).
static func _add_effects(
		loaded: LoadedUnit,
		ids: InstanceIdAllocator,
		effects: Array[EffectDefinition],
		owner: EffectOwner,
		label: String,
		home: CounterHome,
		kind: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT
) -> void:
	for index: int in effects.size():
		var effect: EffectDefinition = effects[index]
		if effect == null:
			continue
		var instance: EffectInstance = EffectInstance.new(
				ids.next_effect_id(label), effect, owner.copy(), kind, label
		)
		var effect_home: CounterHome = home.for_effect(instance, index)
		effect_home.copy_in()
		loaded.add_effect(instance, effect_home)


# One always-on instance of a runtime effect holding [param operations]: a change on top of a
# base, sourced to [param label]. Nothing for no operations.
static func _add_runtime(
		loaded: LoadedUnit,
		ids: InstanceIdAllocator,
		effect_id: String,
		operations: Array[EffectOperation],
		owner: EffectOwner,
		label: String,
		kind: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT
) -> void:
	if operations.is_empty():
		return
	# Made here rather than loaded: it is this one unit's or item's, so no shared .tres changes.
	var effect: EffectDefinition = EffectDefinition.new()
	effect.id = effect_id
	effect.operations = operations
	loaded.add_effect(EffectInstance.new(
			ids.next_effect_id(label), effect, owner.copy(), kind, label
	))


static func _add_operation(key: int, amount: float) -> ModifyValue:
	var change: ModifyValue = ModifyValue.new()
	change.key = key
	change.value = amount
	return change


static func _append_new(list: PackedStringArray, added: PackedStringArray) -> void:
	for value: String in added:
		if not list.has(value):
			list.append(value)


static func _check_listed(
		loaded: LoadedUnit,
		who: String,
		what: String,
		values: PackedStringArray,
		allowed: PackedStringArray
) -> void:
	for value: String in values:
		if not allowed.has(value):
			loaded.problems.append("%s: %s \"%s\" is not one of %s" % [
				who, what, value, ", ".join(allowed),
			])


## What [method Loadout.load_unit] built for one unit: place it with these, after registering its
## effects, so the full Stance set at placement counts them.
class LoadedUnit:
	extends RefCounted

	## Its combat state, ready to place; null when its unit type is unknown.
	var state: CombatUnitState = null
	## Its base values, value key to number: the type's stats and Stance.
	var bases: Dictionary[int, float] = {}
	## Records of the weapons it carries, equipped and stowed. Add them before placing it.
	var weapons: Array[CombatState.WeaponStats] = []
	## Its effect instances: trait, innate effects, stat changes and items, in that order.
	var effects: Array[EffectInstance] = []
	## What was wrong with its data, one line each. The unit still loads, without the bad part,
	## unless [member state] is null.
	var problems: PackedStringArray = []

	# Where each effect's campaign-lane state came from, to write it back.
	var _homes: Array[Loadout.CounterHome] = []

	## Whether it loaded: its unit type was found.
	func is_loaded() -> bool:
		return state != null

	## Adds [param instance] to [member effects]; [param home], when given, is where its
	## campaign-lane state is written back to.
	func add_effect(instance: EffectInstance, home: Loadout.CounterHome = null) -> void:
		effects.append(instance)
		if home != null:
			_homes.append(home)

	## Copies each effect's campaign-lane counter, and its charges when they last the whole run,
	## back to the unit or item instance it came from. Call before the battle ends; calling it
	## twice changes nothing more.
	func write_back() -> void:
		for home: Loadout.CounterHome in _homes:
			home.write_back()


## Where one effect's campaign-lane state lives between battles: the counters and charges of the
## unit or item instance it came from, under the effect's key there.
class CounterHome:
	extends RefCounted

	## The instance's counters by effect key ([member UnitInstance.counters],
	## [member ItemInstance.counters]); shared, not copied.
	var counters: Dictionary[String, int] = {}
	## The instance's charges by effect key; shared, not copied.
	var charges: Dictionary[String, int] = {}
	## The battle's instance of the effect; null for a home not yet given one.
	var instance: EffectInstance = null
	## The effect's key: its id, or [code]#[/code] and its place in its list when it has none.
	var key: String = ""

	func _init(
			home_counters: Dictionary[String, int],
			home_charges: Dictionary[String, int],
			effect_instance: EffectInstance = null,
			effect_key: String = ""
	) -> void:
		counters = home_counters
		charges = home_charges
		instance = effect_instance
		key = effect_key

	## The same home for [param effect_instance], the effect at [param index] of its list.
	func for_effect(effect_instance: EffectInstance, index: int) -> CounterHome:
		var effect: EffectDefinition = effect_instance.definition
		var effect_key: String = effect.id if not effect.id.is_empty() else "#%d" % [index]
		return CounterHome.new(counters, charges, effect_instance, effect_key)

	## Copies the battle's campaign-lane counter into the home, and the charges when they last
	## the run.
	func write_back() -> void:
		var count: int = instance.get_counter(EffectTerms.Lane.CAMPAIGN)
		if count == 0:
			counters.erase(key)
		else:
			counters[key] = count
		var effect: EffectDefinition = instance.definition
		if effect.charge_lane == EffectTerms.Lane.CAMPAIGN and effect.charges > 0:
			charges[key] = instance.charges_left

	## Copies the home's campaign-lane counter and charges into the battle's instance.
	func copy_in() -> void:
		if counters.has(key):
			instance.set_counter(EffectTerms.Lane.CAMPAIGN, counters[key])
		if instance.definition.charge_lane == EffectTerms.Lane.CAMPAIGN and charges.has(key):
			instance.charges_left = charges[key]

