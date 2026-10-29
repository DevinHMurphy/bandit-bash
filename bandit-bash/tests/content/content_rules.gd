# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     content_rules.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
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
## start at 1, string ids are in their [ContentIds] list, every sellable item has a price, and
## no Basic, Legendary or Unique item has one. [constant LOAD] fails a file the catalog turned
## away.[br]
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
]

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
	elif resource is FactionDefinition:
		var faction: FactionDefinition = resource
		# ASSUMPTION: a faction must name a commander and unit types; empty ids there are dangling.
		_reference(path, "commander_id", faction.commander_id, EffectCatalog.Kind.COMMANDER, true)
		for type_id: String in faction.starting_unit_type_ids:
			_reference(path, "starting_unit_type_ids", type_id, EffectCatalog.Kind.UNIT_TYPE, true)
		for gear: PackedStringArray in faction.starting_gear:
			for item_id: String in gear:
				_item_reference(path, item_id)
	elif resource is StaffDefinition:
		var staff: StaffDefinition = resource
		_reference(path, "area_shape_id", staff.area_shape_id, EffectCatalog.Kind.SHAPE)
	elif resource is RuneDefinition:
		var rune: RuneDefinition = resource
		_reference(path, "shape_id", rune.shape_id, EffectCatalog.Kind.SHAPE)
	for effect: EffectDefinition in _effects_of(resource):
		if effect == null:
			continue
		for operation: EffectOperation in effect.operations:
			if operation is CampaignGrant:
				var grant: CampaignGrant = operation
				_grant_reference(path, grant)


func _grant_reference(path: String, grant: CampaignGrant) -> void:
	match grant.grant:
		CampaignGrant.Grant.HEIRLOOM:
			_reference(path, "definition_id", grant.definition_id, EffectCatalog.Kind.HEIRLOOM)
		CampaignGrant.Grant.RECRUIT:
			_reference(path, "definition_id", grant.definition_id, EffectCatalog.Kind.UNIT_TYPE)
		CampaignGrant.Grant.RUNE:
			_reference(path, "definition_id", grant.definition_id, EffectCatalog.Kind.RUNE)


# ASSUMPTION: a reference to a definition of the wrong kind (a rune's shape naming a weapon) counts
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
	for index: int in effects.size():
		var effect: EffectDefinition = effects[index]
		var where: String = "effect %d" % [index]
		if effect == null:
			# ASSUMPTION: an unset slot in a list of blocks fails the text rule: it has no text.
			_fail(EMPTY_TEXT, path, "%s is empty" % [where])
			continue
		_check_effect_text(path, where, effect)
		if is_heirloom:
			_check_heirloom_scope(path, where, effect)
		if not EffectEngine.INLINE_TRIGGERS.has(effect.trigger):
			for operation: EffectOperation in effect.operations:
				if operation != null and operation.is_inline():
					_fail(INLINE_WITHOUT_WINDOW, path, "%s: \"%s\" is inline on %s" % [
						where, operation.describe(), EffectDefinition.TRIGGER_TEXT[effect.trigger],
					])


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
	for property: Dictionary in block.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var property_name: String = property["name"]
		var value: Variant = block.get(property_name)
		if value is Resource and _is_block(value as Resource):
			_check_block(path, "%s %s" % [where, property_name], value as Resource)


func _check_heirloom_scope(path: String, where: String, effect: EffectDefinition) -> void:
	if effect.scope == EffectDefinition.Scope.THIS_UNIT:
		_fail(HEIRLOOM_THIS_UNIT, path, "%s is scoped This unit" % [where])
	elif (
			effect.scope >= EffectDefinition.Scope.ANY_ALLY_UNIT
			and not effect.has_tag(EffectDefinition.Tag.UNIQUE)
	):
		_warn(HEIRLOOM_NOT_UNIQUE, path, "%s is scoped %s without the unique tag" % [
			where, EffectDefinition.SCOPE_TEXT[effect.scope],
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
