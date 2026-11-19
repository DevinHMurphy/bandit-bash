# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     content_rules.gd
# Author:
# Created:  October 29, 2026
# Modified: November 18, 2026
# ==============================================================================

extends RefCounted
## The content test's rules, run over one [EffectCatalog.Index]: the catalog's own or a fixture
## folder's, loaded the same way ([method EffectCatalog.load_tree]).
##
## [method check] returns one [code]Finding[/code] per broken rule per place; a warning doesn't
## fail the test. P01's rules (event bus plan, Definitions and instances): the id is the file
## name, no id repeats, every reference resolves, every block has text, no heirloom is scoped
## This unit, no inline operation sits on a trigger with no inline window, and a warning for a
## heirloom scoped Any Ally Unit or wider without the unique tag. P03's rules (content catalog
## plan, Data layout): the folder matches the data, weapons and staves have a range and attacks
## start at 1, string ids are in their [ContentIds] list (a while-attack condition's id and a
## held-weapon-type condition's too; a
## unit type it names is a unit type or enemy class in the tree), every sellable item has a price,
## no Basic, Legendary or Unique item has one, and an item with uses has no charged use effect of
## its own (enemies and AI plan, question 18 (d)), every [Area] reuses a shape file from
## [code]shapes/[/code] (question 17); and (event bus plan, question 50) no effect lacks
## operations but an opener (a key's or lockpick's use effect, Burglar's Roll), no faction lists
## its commander among its starting units, and starting gear fits its slots. P05's rules (enemies and AI plan, EN1): enemy
## classes live in enemies/ and packs in enemies/packs/, a pack names only enemy classes, each at
## least once at every step, and an enemy class has target rule text and is never a commander or
## given a role; and (EN17) a drawn pack fields its step's size at every step, a basic or hard
## pack names a leader it fields at every step, and only a key pack names a mini-boss; and (EN8)
## that mini-boss is a class built on a base class it matches, with a signature move, in no pack.
## P02's rule (event bus plan, question 60): every effect inside a carrier has an id unique within
## it, which saves name it by. [constant LOAD] fails a file the catalog turned away.[br]
## The price rules read the price through a callable, so their fixtures can run against a table
## with a row missing or a price for an unsold rarity, which [Prices] itself never has.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## A file the catalog couldn't load, or that is no content definition.
const LOAD: String = "load"
## An id that isn't its file name.
const ID_FILE_NAME: String = "id_file_name"
## An id two files use.
const DUPLICATE_ID: String = "duplicate_id"
## A content id field naming nothing in the catalog, or a definition of the wrong kind.
const DANGLING_REFERENCE: String = "dangling_reference"
## A block whose describe() is empty, or an empty slot in a list of blocks.
const EMPTY_TEXT: String = "empty_text"
## A heirloom effect scoped This unit.
const HEIRLOOM_THIS_UNIT: String = "heirloom_this_unit"
## An inline operation on a trigger with no inline window.
const INLINE_WITHOUT_WINDOW: String = "inline_without_window"
## Warning: a heirloom effect scoped Any Ally Unit or wider without the unique tag.
const HEIRLOOM_NOT_UNIQUE: String = "heirloom_not_unique"
## A file whose folder doesn't match its data.
const FOLDER: String = "folder"
## A weapon or staff with no range, or an attack that starts below 1.
const RANGE: String = "range"
## A string id that isn't in its [ContentIds] list.
const UNKNOWN_ID: String = "unknown_id"
## A sellable item whose kind and rarity have no price.
const UNPRICED: String = "unpriced"
## A Basic, Legendary or Unique item that has a price.
const UNSELLABLE_PRICED: String = "unsellable_priced"
## An effect with no operations: it can never do anything.
const NO_OPERATIONS: String = "no_operations"
## A commander among a faction's starting unit types; the commander is its own field.
const COMMANDER_STARTING: String = "commander_starting"
## A faction's starting gear in the wrong slot: a non-weapon in the Weapon slot, a non-equipment
## in the Equipment slot, equipment in the Pouch, or more than three slots.
const GEAR_SLOT: String = "gear_slot"
## A pack that lists no enemy class at a step, a class count below 1, or a drawn pack
## ([method PackDefinition.is_drawn]) whose units at a step aren't that step's
## [constant PackDefinition.STEP_SIZES].
const PACK_COUNT: String = "pack_count"
## A basic or hard pack with no leader, a leader the pack doesn't field at every step, a key pack
## with no mini-boss or with a leader, or a mini-boss on a pack outside the key pool.
const PACK_ROLE: String = "pack_role"
## An enemy class with no target rule text, a commander flag or a role.
const ENEMY_CLASS: String = "enemy_class"
## An effect inside a carrier with no id, or with the id of another effect of that carrier: a
## saved instance names it by both ([method EffectInstance.catalog_reference]).
const CARRIER_EFFECT_ID: String = "carrier_effect_id"
## A staff or consumable with uses and its own charged use effect: combat would count its uses
## twice.
const DOUBLE_USES: String = "double_uses"
## An [Area] with no shape, or whose shape isn't the tree's file of that id in
## [code]shapes/[/code]: areas reuse the shared shapes, never a copy of their own.
const AREA_SHAPE: String = "area_shape"
## A key pack's mini-boss that is no class built on a base class; a mini-boss or boss that differs
## from its base class (stats, growths, gear, behavior unless it holds its post, target rule,
## movement, tags, Stance, trait), lacks one of its base's trait effects or a signature move, or
## sits in a pack's units (a post-holding boss may lead an undrawn pack).
const MINI_BOSS: String = "mini_boss"

## Every rule that fails the test.
const FAILURE_RULES: PackedStringArray = [
	LOAD,
	ID_FILE_NAME,
	DUPLICATE_ID,
	DANGLING_REFERENCE,
	EMPTY_TEXT,
	HEIRLOOM_THIS_UNIT,
	INLINE_WITHOUT_WINDOW,
	FOLDER,
	RANGE,
	UNKNOWN_ID,
	UNPRICED,
	UNSELLABLE_PRICED,
	NO_OPERATIONS,
	COMMANDER_STARTING,
	GEAR_SLOT,
	PACK_COUNT,
	PACK_ROLE,
	ENEMY_CLASS,
	CARRIER_EFFECT_ID,
	DOUBLE_USES,
	AREA_SHAPE,
	MINI_BOSS,
]

# A faction's starting gear slots in order (FactionDefinition.starting_gear).
const WEAPON_SLOT: int = 0
const EQUIPMENT_SLOT: int = 1
const SLOT_COUNT: int = 3

# The one folder of each kind whose folder doesn't depend on its data, relative to the root.
const KIND_FOLDERS: Dictionary[EffectCatalog.Kind, String] = {
	EffectCatalog.Kind.UNIT_TYPE: "units/",
	EffectCatalog.Kind.COMMANDER: "units/commanders/",
	EffectCatalog.Kind.UNIT_PREFIX: "prefixes/units/",
	EffectCatalog.Kind.FACTION: "factions/",
	EffectCatalog.Kind.EQUIPMENT: "items/equipment/",
	EffectCatalog.Kind.TRINKET: "items/trinkets/",
	EffectCatalog.Kind.CONSUMABLE: "items/consumables/",
	EffectCatalog.Kind.RUNE: "runes/",
	EffectCatalog.Kind.HEIRLOOM: "heirlooms/",
	EffectCatalog.Kind.CURSE: "curses/",
	EffectCatalog.Kind.SHAPE: "shapes/",
	EffectCatalog.Kind.EFFECT: "effects/",
	EffectCatalog.Kind.TERRAIN: "terrain/",
	EffectCatalog.Kind.ENEMY_CLASS: "enemies/",
	EffectCatalog.Kind.PACK: "enemies/packs/",
}

# The staff kind that attacks, so its range starts at 1 like a weapon's. ContentIds.STAFF_KINDS
# lists it without a named constant.
const ATTACK_STAFF: String = "attack"

var _index: EffectCatalog.Index = null
var _price_of: Callable
var _findings: Array[Finding] = []


## [param index]: the tree to check. [param price_of]: called as
## [code]price_of(kind: String, rarity: ItemDefinition.Rarity) -> int[/code], returning
## [constant Prices.NO_PRICE] for no price. [b]Invalid (the default):[/b] [method Prices.buy_price].
func _init(index: EffectCatalog.Index, price_of: Callable = Callable()) -> void:
	_index = index
	_price_of = price_of if price_of.is_valid() else Prices.buy_price


## Runs every rule over every file of the index, in path order.
func check() -> Array[Finding]:
	_findings = []
	for path: String in _index.rejected:
		_fail(LOAD, path, _index.rejected[path])
	_check_duplicates()
	for path: String in _index.paths:
		var resource: Resource = _index.at_path(path)
		if resource != null:
			_check_definition(path, resource)
	return _findings


func _check_definition(path: String, resource: Resource) -> void:
	var id: String = EffectCatalog.id_of(resource)
	if id != path.get_file().get_basename():
		_fail(ID_FILE_NAME, path, "id \"%s\" is not the file name" % [id])
	_check_folder(path, resource)
	_check_references(path, resource)
	_check_string_ids(path, resource)
	_check_effects(path, resource)
	if resource is WeaponDefinition:
		var weapon: WeaponDefinition = resource
		_check_range(path, weapon)
	if resource is ItemDefinition:
		var item: ItemDefinition = resource
		_check_price(path, item)
		_check_uses(path, item)
	if resource is EnemyClassDefinition:
		var enemy: EnemyClassDefinition = resource
		_check_enemy_class(path, enemy)
		_check_mini_boss(path, enemy)
	elif resource is PackDefinition:
		var pack: PackDefinition = resource
		_check_pack_counts(path, pack)
		_check_pack_roles(path, pack)
		_check_pack_mini_boss(path, pack)


func _check_duplicates() -> void:
	var paths_by_id: Dictionary[String, PackedStringArray] = {}
	for path: String in _index.paths:
		var resource: Resource = _index.at_path(path)
		var id: String = EffectCatalog.id_of(resource)
		if resource == null or id.is_empty():
			continue
		var listed: PackedStringArray = paths_by_id.get(id, PackedStringArray())
		listed.append(path)
		paths_by_id[id] = listed
	for id: String in paths_by_id:
		var listed: PackedStringArray = paths_by_id[id]
		if listed.size() < 2:
			continue
		for path: String in listed:
			_fail(DUPLICATE_ID, path, "id \"%s\" is used by %d files: %s" % [
				id, listed.size(), ", ".join(listed),
			])


func _check_folder(path: String, resource: Resource) -> void:
	var folder: String = (path.get_base_dir() + "/").substr(_index.root.length())
	var kind: int = EffectCatalog.classify(resource)
	var expected: String = ""
	if resource is WeaponDefinition:
		var weapon: WeaponDefinition = resource
		expected = "items/weapons/%s/" % [weapon.weapon_type]
		if kind == EffectCatalog.Kind.STAFF and weapon.weapon_type != "staff":
			_fail(FOLDER, path, "a staff has weapon type \"staff\", not \"%s\"" % [
				weapon.weapon_type,
			])
	elif resource is WeaponPrefixDefinition:
		var prefix: WeaponPrefixDefinition = resource
		if prefix.weapon_types.size() > 1:
			_fail(FOLDER, path, "a prefix folder holds one weapon type or all; it lists %s" % [
				", ".join(prefix.weapon_types),
			])
			return
		var types: PackedStringArray = prefix.weapon_types
		expected = "prefixes/weapons/%s/" % ["all" if types.is_empty() else types[0]]
	else:
		expected = KIND_FOLDERS[kind]
	if folder != expected:
		_fail(FOLDER, path, "a %s belongs in %s, not %s" % [
			_kind_name(kind), expected, "the root" if folder.is_empty() else folder,
		])


func _check_references(path: String, resource: Resource) -> void:
	if resource is UnitTypeDefinition:
		var unit: UnitTypeDefinition = resource
		_reference(path, "starting_weapon_id", unit.starting_weapon_id, EffectCatalog.Kind.WEAPON)
		_reference(
				path, "commander_heirloom_id", unit.commander_heirloom_id,
				EffectCatalog.Kind.HEIRLOOM
		)
		if resource is EnemyClassDefinition:
			var enemy: EnemyClassDefinition = resource
			_reference(
					path, "starting_equipment_id", enemy.starting_equipment_id,
					EffectCatalog.Kind.EQUIPMENT
			)
	elif resource is FactionDefinition:
		var faction: FactionDefinition = resource
		# ASSUMPTION: a faction must name a commander and unit types; empty ids there are dangling.
		_reference(path, "commander_id", faction.commander_id, EffectCatalog.Kind.COMMANDER, true)
		for type_id: String in faction.starting_unit_type_ids:
			_reference(path, "starting_unit_type_ids", type_id, EffectCatalog.Kind.UNIT_TYPE, true)
			if _index.kind_of(type_id) == EffectCatalog.Kind.COMMANDER:
				_fail(COMMANDER_STARTING, path, "starting_unit_type_ids names commander \"%s\"" % [
					type_id,
				])
		for gear: PackedStringArray in faction.starting_gear:
			for item_id: String in gear:
				_item_reference(path, item_id)
			_check_gear_slots(path, gear)
	elif resource is PackDefinition:
		var pack: PackDefinition = resource
		for class_id: String in pack.class_ids():
			_reference(path, "a step's counts", class_id, EffectCatalog.Kind.ENEMY_CLASS, true)
		_reference(path, "leader_class_id", pack.leader_class_id, EffectCatalog.Kind.ENEMY_CLASS)
		_reference(path, "mini_boss_id", pack.mini_boss_id, EffectCatalog.Kind.ENEMY_CLASS)
	elif resource is StaffDefinition:
		var staff: StaffDefinition = resource
		_reference(path, "area_shape_id", staff.area_shape_id, EffectCatalog.Kind.SHAPE)
	for effect: EffectDefinition in _effects_of(resource):
		if effect == null:
			continue
		for operation: EffectOperation in effect.operations:
			if operation is CampaignGrant:
				var grant: CampaignGrant = operation
				_grant_reference(path, grant)


# One starting unit's gear, Weapon, Equipment then Pouch: each item that resolves must fit its slot.
# Ids that don't resolve are the dangling rule's.
func _check_gear_slots(path: String, gear: PackedStringArray) -> void:
	if gear.size() > SLOT_COUNT:
		_fail(GEAR_SLOT, path, "starting_gear lists %d slots; a unit has %d" % [
			gear.size(), SLOT_COUNT,
		])
	for slot: int in mini(gear.size(), SLOT_COUNT):
		var item: ItemDefinition = _index.item(gear[slot])
		if item == null:
			continue
		var fits: bool = not item is EquipmentDefinition
		if slot == WEAPON_SLOT:
			fits = item is WeaponDefinition
		elif slot == EQUIPMENT_SLOT:
			fits = item is EquipmentDefinition
		if not fits:
			_fail(GEAR_SLOT, path, "starting_gear puts \"%s\", a %s, in the %s slot" % [
				gear[slot], item.kind, ["Weapon", "Equipment", "Pouch"][slot],
			])


func _grant_reference(path: String, grant: CampaignGrant) -> void:
	match grant.grant:
		CampaignGrant.Grant.HEIRLOOM:
			_reference(path, "definition_id", grant.definition_id, EffectCatalog.Kind.HEIRLOOM)
		CampaignGrant.Grant.RECRUIT:
			_reference(path, "definition_id", grant.definition_id, EffectCatalog.Kind.UNIT_TYPE)
		CampaignGrant.Grant.RUNE:
			_reference(path, "definition_id", grant.definition_id, EffectCatalog.Kind.RUNE)


# ASSUMPTION: a reference to a definition of the wrong kind (a staff's shape naming a weapon) counts
# as dangling, since nothing of the kind the field needs resolves.
func _reference(
		path: String, field: String, id: String, kind: EffectCatalog.Kind, required: bool = false
) -> void:
	if id.is_empty():
		if required:
			_fail(DANGLING_REFERENCE, path, "%s is empty" % [field])
		return
	if not _index.has(id):
		_fail(DANGLING_REFERENCE, path, "%s names \"%s\", which is not in the catalog" % [
			field, id,
		])
	elif not _index.is_of(id, kind):
		_fail(DANGLING_REFERENCE, path, "%s names \"%s\", a %s, not a %s" % [
			field, id, _kind_name(_index.kind_of(id)), _kind_name(kind),
		])


func _item_reference(path: String, id: String) -> void:
	if id.is_empty():
		return
	if not _index.has(id):
		_fail(DANGLING_REFERENCE, path, "starting_gear names \"%s\", not in the catalog" % [id])
	elif _index.item(id) == null:
		_fail(DANGLING_REFERENCE, path, "starting_gear names \"%s\", a %s, not an item" % [
			id, _kind_name(_index.kind_of(id)),
		])


# NOTE: item tags aren't checked; there is no list of item tags yet (item_definition.gd).
func _check_string_ids(path: String, resource: Resource) -> void:
	if resource is UnitTypeDefinition:
		var unit: UnitTypeDefinition = resource
		_known(path, "role", unit.role, ContentIds.ROLES, true)
		_known_all(path, "weapon_types", unit.weapon_types, ContentIds.WEAPON_TYPES)
		_known_all(path, "tags", unit.tags, ContentIds.TAGS)
		_known_all(path, "upgrade_weapon_types", unit.upgrade_weapon_types, ContentIds.WEAPON_TYPES)
		_known_all(path, "upgrade_tags", unit.upgrade_tags, ContentIds.TAGS)
		if resource is EnemyClassDefinition:
			var enemy: EnemyClassDefinition = resource
			_known(path, "target_rule_id", enemy.target_rule_id, ContentIds.TARGET_RULES)
	elif resource is WeaponDefinition:
		var weapon: WeaponDefinition = resource
		_known(path, "weapon_type", weapon.weapon_type, ContentIds.WEAPON_TYPES)
		_known_all(path, "effective_against", weapon.effective_against, ContentIds.TAGS)
		if resource is StaffDefinition:
			var staff: StaffDefinition = resource
			_known(path, "staff_kind", staff.staff_kind, ContentIds.STAFF_KINDS)
	elif resource is EquipmentDefinition:
		var equipment: EquipmentDefinition = resource
		_known(path, "category", equipment.category, ContentIds.EQUIPMENT_CATEGORIES)
		_known_all(path, "granted_tags", equipment.granted_tags, ContentIds.TAGS)
	elif resource is ConsumableDefinition:
		var consumable: ConsumableDefinition = resource
		_known(path, "use_kind", consumable.use_kind, ContentIds.CONSUMABLE_USE_KINDS)
	elif resource is HeirloomDefinition:
		var heirloom: HeirloomDefinition = resource
		var tiers: PackedStringArray = (
				ContentIds.CURSE_TIERS if resource is CurseDefinition else ContentIds.HEIRLOOM_TIERS
		)
		_known(path, "tier", heirloom.tier, tiers)
		_known(path, "kind", heirloom.kind, ContentIds.HEIRLOOM_KINDS, true)
	elif resource is RuneDefinition:
		var rune: RuneDefinition = resource
		_known(path, "target_kind", rune.target_kind, ContentIds.RUNE_TARGET_KINDS)
		# A side is only read by unit runes, so only they must name one.
		var is_side_optional: bool = rune.target_kind != ContentIds.RUNE_UNIT
		_known(
				path,
				"target_side",
				rune.target_side,
				ContentIds.RUNE_TARGET_SIDES,
				is_side_optional
		)
	elif resource is TargetShape:
		var shape: TargetShape = resource
		_known(path, "kind", shape.kind, ContentIds.SHAPE_KINDS)
	elif resource is WeaponPrefixDefinition:
		var prefix: WeaponPrefixDefinition = resource
		_known_all(path, "weapon_types", prefix.weapon_types, ContentIds.WEAPON_TYPES)
		_known_all(path, "staff_kinds", prefix.staff_kinds, ContentIds.STAFF_KINDS)


func _known(
		path: String, field: String, value: String, ids: PackedStringArray, optional: bool = false
) -> void:
	if optional and value.is_empty():
		return
	if not ids.has(value):
		_fail(UNKNOWN_ID, path, "%s \"%s\" is not one of %s" % [field, value, ", ".join(ids)])


func _known_all(
		path: String, field: String, values: PackedStringArray, ids: PackedStringArray
) -> void:
	for value: String in values:
		_known(path, field, value, ids)


func _check_effects(path: String, resource: Resource) -> void:
	var is_heirloom: bool = resource is HeirloomDefinition
	var effects: Array[EffectDefinition] = _effects_of(resource)
	if resource is EffectCarrierDefinition:
		_check_carrier_ids(path, effects)
	for index: int in effects.size():
		var effect: EffectDefinition = effects[index]
		var where: String = "effect %d" % [index]
		if effect == null:
			# ASSUMPTION: an unset slot in a list of blocks fails the text rule: it has no text.
			_fail(EMPTY_TEXT, path, "%s is empty" % [where])
			continue
		_check_effect_text(path, where, effect)
		if effect.operations.is_empty() and not _is_opener(resource, effect):
			_fail(NO_OPERATIONS, path, "%s has no operations" % [where])
		if is_heirloom:
			_check_heirloom_scope(path, where, effect)
		if not EffectEngine.INLINE_TRIGGERS.has(effect.trigger):
			for operation: EffectOperation in effect.operations:
				if operation != null and operation.is_inline():
					_fail(INLINE_WITHOUT_WINDOW, path, "%s: \"%s\" is inline on %s" % [
						where, operation.describe(), EffectTerms.TRIGGER_TEXT[effect.trigger],
					])


# Whether [param effect] opens locks: a key's or lockpick's use effect (its id is the one MapObjects
# finds it by, and the consumable's use kind is the same word), or an heirloom's Burglar's Roll
# effect, by its id. It needs no operations: opening the lock is MapObjects'.
func _is_opener(resource: Resource, effect: EffectDefinition) -> bool:
	if resource is HeirloomDefinition:
		return effect.id == MapObjects.BURGLAR_EFFECT_ID
	if not resource is ConsumableDefinition:
		return false
	var consumable: ConsumableDefinition = resource
	var opener_ids: PackedStringArray = [MapObjects.KEY_EFFECT_ID, MapObjects.LOCKPICK_EFFECT_ID]
	return opener_ids.has(effect.id) and consumable.use_kind == effect.id


# An unset slot is the text rule's, so only the set effects are checked here.
func _check_carrier_ids(path: String, effects: Array[EffectDefinition]) -> void:
	var seen: Dictionary[String, int] = {}
	for index: int in effects.size():
		var effect: EffectDefinition = effects[index]
		if effect == null:
			continue
		if effect.id.is_empty():
			_fail(CARRIER_EFFECT_ID, path, "effect %d has no id" % [index])
		elif seen.has(effect.id):
			_fail(CARRIER_EFFECT_ID, path, "effects %d and %d share the id \"%s\"" % [
				seen[effect.id], index, effect.id,
			])
		else:
			seen[effect.id] = index


func _check_effect_text(path: String, where: String, effect: EffectDefinition) -> void:
	if effect.describe().strip_edges().is_empty():
		_fail(EMPTY_TEXT, path, "%s has no text" % [where])
	for index: int in effect.conditions.size():
		_check_block(path, "%s condition %d" % [where, index], effect.conditions[index])
	for index: int in effect.operations.size():
		_check_block(path, "%s operation %d" % [where, index], effect.operations[index])


# Checks [param block]'s text, then every block it holds (selectors, value sources) the same way.
func _check_block(path: String, where: String, block: Resource) -> void:
	if block == null:
		_fail(EMPTY_TEXT, path, "%s is empty" % [where])
		return
	if _block_text(block).strip_edges().is_empty():
		_fail(EMPTY_TEXT, path, "%s (%s) has no text" % [where, _script_name(block)])
	if block is WhileAttackCondition:
		var condition: WhileAttackCondition = block
		_check_attack_condition(path, where, condition)
	if block is WhileStateCondition:
		var state_condition: WhileStateCondition = block
		if state_condition.state == WhileStateCondition.State.WIELDING_TYPE:
			_known(
					path,
					"%s weapon_type" % [where],
					state_condition.weapon_type,
					ContentIds.WEAPON_TYPES
			)
	if block is Area:
		var area: Area = block
		_check_area_shape(path, where, area)
	for property: Dictionary in block.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var property_name: String = property["name"]
		var value: Variant = block.get(property_name)
		if value is Resource and _is_block(value as Resource):
			_check_block(path, "%s %s" % [where, property_name], value as Resource)


# The condition matches its id exactly against what the loadout puts in combat, so an id the data
# doesn't use never matches. The damage type and crit kinds ignore the id.
func _check_attack_condition(
		path: String, where: String, condition: WhileAttackCondition
) -> void:
	var field: String = "%s type_name" % [where]
	var id: String = condition.type_name
	match condition.kind:
		WhileAttackCondition.Kind.OPPONENT_TAG:
			_known(path, field, id, ContentIds.TAGS)
		WhileAttackCondition.Kind.WEAPON_TYPE:
			_known(path, field, id, ContentIds.WEAPON_TYPES)
		WhileAttackCondition.Kind.OPPONENT_UNIT_TYPE:
			if (
					_index.is_of(id, EffectCatalog.Kind.UNIT_TYPE)
					or _index.is_of(id, EffectCatalog.Kind.ENEMY_CLASS)
			):
				return
			_fail(DANGLING_REFERENCE, path, "%s \"%s\" is no unit type or enemy class" % [
				field, id,
			])


# The shape must be the very file the tree lists under its id, so an inline copy or a file from
# another tree fails even when its id matches a shared shape.
func _check_area_shape(path: String, where: String, area: Area) -> void:
	if area.shape == null:
		_fail(AREA_SHAPE, path, "%s has no shape" % [where])
		return
	var shape_id: String = area.shape.id
	var shape_path: String = area.shape.resource_path
	if (
			not _index.is_of(shape_id, EffectCatalog.Kind.SHAPE)
			or _index.path_of(shape_id) != shape_path
	):
		_fail(AREA_SHAPE, path, "%s's shape \"%s\" (%s) is not a file in shapes/" % [
			where, shape_id, "inline" if shape_path.contains("::") else shape_path,
		])


func _check_heirloom_scope(path: String, where: String, effect: EffectDefinition) -> void:
	if effect.scope == EffectTerms.Scope.THIS_UNIT:
		_fail(HEIRLOOM_THIS_UNIT, path, "%s is scoped This unit" % [where])
	elif (
			effect.scope >= EffectTerms.Scope.ANY_ALLY_UNIT
			and not effect.has_tag(EffectDefinition.Tag.UNIQUE)
	):
		_warn(HEIRLOOM_NOT_UNIQUE, path, "%s is scoped %s without the unique tag" % [
			where, EffectTerms.SCOPE_TEXT[effect.scope],
		])


func _check_range(path: String, weapon: WeaponDefinition) -> void:
	if weapon.range_min < 0 or weapon.range_max < weapon.range_min:
		_fail(RANGE, path, "range %d to %d is no range" % [weapon.range_min, weapon.range_max])
	var attacks: bool = true
	if weapon is StaffDefinition:
		var staff: StaffDefinition = weapon
		attacks = staff.staff_kind == ATTACK_STAFF
	if attacks and weapon.range_min < 1:
		_fail(RANGE, path, "its attack starts at range %d; attacks start at 1" % [weapon.range_min])


func _check_price(path: String, item: ItemDefinition) -> void:
	var price: int = _price_of.call(item.kind, item.rarity)
	var rarity_name: String = (ItemDefinition.Rarity.find_key(item.rarity) as String).capitalize()
	if Prices.is_sellable(item.rarity):
		if price == Prices.NO_PRICE:
			_fail(UNPRICED, path, "a %s %s is sold but has no price" % [rarity_name, item.kind])
	elif price != Prices.NO_PRICE:
		_fail(UNSELLABLE_PRICED, path, "a %s %s is never sold but costs %d" % [
			rarity_name, item.kind, price,
		])


# The loadout turns a staff's or consumable's uses into a use effect that combat counts, so its own
# charged use effect would be a second count. Uses 0 with no use effect is unlimited.
func _check_uses(path: String, item: ItemDefinition) -> void:
	var uses: int = 0
	if item is StaffDefinition:
		var staff: StaffDefinition = item
		uses = staff.uses
	elif item is ConsumableDefinition:
		var consumable: ConsumableDefinition = item
		uses = consumable.uses
	if uses <= 0:
		return
	for index: int in item.effects.size():
		var effect: EffectDefinition = item.effects[index]
		if effect != null and _is_charged_use(effect):
			_fail(DOUBLE_USES, path, "uses is %d and effect %d is a use effect with %d charges" % [
				uses, index, effect.charges,
			])


# Whether [param effect] counts uses: no trigger, no always-on modifier, and charges.
# NOTE: The same test as Loadout._is_charged_use and ItemUseResolver.use_effects; keep them in
# step. A modifier needs an instance to be made from, so a throwaway one stands in.
func _is_charged_use(effect: EffectDefinition) -> bool:
	if effect.charges <= 0 or effect.trigger != EffectTerms.Trigger.ALWAYS:
		return false
	var owner: EffectOwner = EffectOwner.for_item("item", "unit", 0, CombatFact.CombatSide.PLAYER)
	var instance: EffectInstance = EffectInstance.new(
			"content_rules", effect, owner, Modifier.SourceKind.POUCH_ITEM
	)
	for operation: EffectOperation in effect.operations:
		if operation != null and operation.make_modifier(instance) != null:
			return false
	return true


# The intent shows the target rule's text, so it can't be empty; an enemy class is never a
# commander and has no role (P03 question 14), since commanders and roles are the player's. Its
# signature move is one of its trait effects, the same resource, or Intents never matches it.
func _check_enemy_class(path: String, enemy: EnemyClassDefinition) -> void:
	if enemy.target_rule_text.strip_edges().is_empty():
		_fail(ENEMY_CLASS, path, "it has no target rule text")
	if enemy.signature_move != null and not enemy.effects.has(enemy.signature_move):
		_fail(ENEMY_CLASS, path, "its signature move isn't among its trait effects")
	if enemy.is_commander:
		_fail(ENEMY_CLASS, path, "an enemy class is never a commander")
	if not enemy.role.is_empty():
		_fail(ENEMY_CLASS, path, "an enemy class has no role; it has \"%s\"" % [enemy.role])


# Every step lists a class, each at least once; a drawn pack fields exactly its step's size.
func _check_pack_counts(path: String, pack: PackDefinition) -> void:
	for step: int in range(1, PackDefinition.STEPS + 1):
		var counts: Dictionary[String, int] = pack.counts_at(step)
		if counts.is_empty():
			_fail(PACK_COUNT, path, "it lists no enemy class at step %d" % [step])
		for class_id: String in counts:
			if counts[class_id] < 1:
				_fail(PACK_COUNT, path, "\"%s\" has count %d at step %d; at least 1 each" % [
					class_id, counts[class_id], step,
				])
		var size: int = pack.units(step).size()
		var expected: int = PackDefinition.STEP_SIZES[step - 1]
		if pack.is_drawn() and size != expected:
			_fail(PACK_COUNT, path, "it fields %d at step %d, not the step's %d" % [
				size, step, expected,
			])


# enemy-packs.md, Decisions 9 and 10: a basic or hard pack's leader is one of its own units at
# every step; a key pack escorts a mini-boss and has no leader of its own.
func _check_pack_roles(path: String, pack: PackDefinition) -> void:
	var is_key: bool = pack.pool == PackDefinition.Pool.KEY
	var needs_leader: bool = (
			pack.pool == PackDefinition.Pool.BASIC or pack.pool == PackDefinition.Pool.HARD
	)
	if needs_leader and pack.leader_class_id.is_empty():
		_fail(PACK_ROLE, path, "a basic or hard pack names a leader")
	if is_key and not pack.leader_class_id.is_empty():
		_fail(PACK_ROLE, path, "a key pack has no leader; its mini-boss leads it")
	if is_key == pack.mini_boss_id.is_empty():
		_fail(PACK_ROLE, path, "only a key pack names a mini-boss, and every key pack does")
	if pack.leader_class_id.is_empty():
		return
	for step: int in range(1, PackDefinition.STEPS + 1):
		if not pack.counts_at(step).has(pack.leader_class_id):
			_fail(PACK_ROLE, path, "its leader \"%s\" isn't one of its units at step %d" % [
				pack.leader_class_id, step,
			])


# enemy-roster.md, Mini-bosses: a key pack's mini-boss is a class built on a base class (a missing
# class is DANGLING_REFERENCE's), and no pack fields a mini-boss among its units.
func _check_pack_mini_boss(path: String, pack: PackDefinition) -> void:
	var boss: EnemyClassDefinition = _index.enemy_class(pack.mini_boss_id)
	if boss != null and boss.base_class_id.is_empty():
		_fail(MINI_BOSS, path, "mini_boss_id names \"%s\", a class with no base class" % [
			pack.mini_boss_id,
		])
	for class_id: String in pack.class_ids():
		var unit: EnemyClassDefinition = _index.enemy_class(class_id)
		# A scripted map's boss stands in its undrawn pack as the leader (EnemySetup.draw).
		var is_boss_leader: bool = (
				unit != null
				and unit.holds_post
				and not pack.is_drawn()
				and pack.leader_class_id == class_id
		)
		if unit != null and not unit.base_class_id.is_empty() and not is_boss_leader:
			_fail(MINI_BOSS, path, "\"%s\" is built on a base class and never sits in a pack" % [
				class_id,
			])


# enemy-roster.md, Mini-bosses: an elite of its base class, the class plus a prefix and a
# signature move, so everything a unit of the base class has must match, and every one of the
# base's trait effects is there by id (a mini-boss may add a condition to one, as the Hex
# Matron's Curse does).
func _check_mini_boss(path: String, enemy: EnemyClassDefinition) -> void:
	if enemy.base_class_id.is_empty():
		return
	_reference(path, "base_class_id", enemy.base_class_id, EffectCatalog.Kind.ENEMY_CLASS)
	var base: EnemyClassDefinition = _index.enemy_class(enemy.base_class_id)
	if base == null:
		return
	if not base.base_class_id.is_empty():
		_fail(MINI_BOSS, path, "its base class \"%s\" is built on another" % [base.id])
	if enemy.signature_move == null:
		_fail(MINI_BOSS, path, "it has no signature move")
	var differs: PackedStringArray = []
	if enemy.base_stats != base.base_stats:
		differs.append("base_stats")
	if enemy.growths != base.growths:
		differs.append("growths")
	if enemy.starting_weapon_id != base.starting_weapon_id:
		differs.append("starting_weapon_id")
	if enemy.starting_equipment_id != base.starting_equipment_id:
		differs.append("starting_equipment_id")
	# A post holder (the Powder Baron) guards its tile whatever its base class does.
	if enemy.behavior != base.behavior and not enemy.holds_post:
		differs.append("behavior")
	if enemy.target_rule_id != base.target_rule_id:
		differs.append("target_rule_id")
	if enemy.movement_type != base.movement_type:
		differs.append("movement_type")
	if enemy.tags != base.tags:
		differs.append("tags")
	if enemy.weapon_types != base.weapon_types:
		differs.append("weapon_types")
	if enemy.stance != base.stance:
		differs.append("stance")
	if enemy.trait_name != base.trait_name:
		differs.append("trait_name")
	if not differs.is_empty():
		_fail(MINI_BOSS, path, "it differs from its base class \"%s\" in %s" % [
			base.id, ", ".join(differs),
		])
	var own_ids: PackedStringArray = []
	for effect: EffectDefinition in enemy.effects:
		if effect != null:
			own_ids.append(effect.id)
	for effect: EffectDefinition in base.effects:
		if effect != null and not own_ids.has(effect.id):
			_fail(MINI_BOSS, path, "it lacks its base class's trait effect \"%s\"" % [effect.id])


# NOTE: The carrier lists EffectInstance._carried_effects names saved effects in; keep them in
# step.
# Every effect [param resource] carries, in its lists' order: a carrier's effects, a unit type's
# innate and upgraded effects too, or a standalone effect itself.
func _effects_of(resource: Resource) -> Array[EffectDefinition]:
	var effects: Array[EffectDefinition] = []
	if resource is EffectDefinition:
		effects.append(resource as EffectDefinition)
		return effects
	if resource is EffectCarrierDefinition:
		var carrier: EffectCarrierDefinition = resource
		effects.append_array(carrier.effects)
	if resource is UnitTypeDefinition:
		var unit: UnitTypeDefinition = resource
		effects.append_array(unit.innate_effects)
		effects.append_array(unit.upgraded_effects)
	return effects


func _is_block(resource: Resource) -> bool:
	return (
			resource is EffectCondition
			or resource is EffectOperation
			or resource is TargetSelector
			or resource is ValueSource
	)


func _block_text(block: Resource) -> String:
	if block is EffectCondition:
		return (block as EffectCondition).describe()
	if block is EffectOperation:
		return (block as EffectOperation).describe()
	if block is TargetSelector:
		return (block as TargetSelector).describe()
	return (block as ValueSource).describe()


func _script_name(object: Object) -> String:
	var script: Script = object.get_script()
	return "a block" if script == null else script.resource_path.get_file()


func _kind_name(kind: int) -> String:
	var found: Variant = EffectCatalog.Kind.find_key(kind)
	return "definition" if found == null else (found as String).to_lower().replace("_", " ")


func _fail(rule: String, path: String, message: String) -> void:
	_findings.append(Finding.new(rule, path, message, false))


func _warn(rule: String, path: String, message: String) -> void:
	_findings.append(Finding.new(rule, path, message, true))


## One broken rule in one file.
class Finding:
	extends RefCounted

	## The rule broken, one of the rule constants, such as [code]folder[/code].
	var rule: String = ""
	## The file it is in.
	var path: String = ""
	## What is wrong, in words.
	var message: String = ""
	## Whether it only warns: the test still passes.
	var is_warning: bool = false


	func _init(rule_name: String, file_path: String, text: String, warning: bool) -> void:
		rule = rule_name
		path = file_path
		message = text
		is_warning = warning


	func _to_string() -> String:
		return "%s%s %s: %s" % ["warning " if is_warning else "", rule, path, message]
