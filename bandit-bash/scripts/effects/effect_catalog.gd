# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_catalog.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name EffectCatalog
extends RefCounted
## Every content definition under [code]res://data/[/code], loaded once and looked up by id.
##
## Walks [constant DATA_ROOT] recursively with [method ResourceLoader.list_directory], which lists
## files by their source names in exported builds too, so nothing is registered by hand. Folders
## don't change what a definition is: its [enum Kind] comes from its class (and
## [member UnitTypeDefinition.is_commander]), and the content test checks each file's folder
## against its data. Ids are unique across the catalog; when one repeats, the first file in path
## order wins and the repeat is reported in [method problems].[br]
## [b]Read-only:[/b] definitions are shared Resources, so never change one; per-unit and per-item
## state lives on instances. The content test hashes every definition before and after its run.[br]
## Loads once, on the main thread: the [code]CampaignService[/code] autoload calls
## [method load_catalog] at startup, and a main-thread lookup before then loads it too. A lookup
## from another thread (P05's AI) before it has loaded is an error and finds nothing, since
## loading there could race. Static; never instantiated, and not an autoload.
## [method load_tree] builds a separate [EffectCatalog.Index] of any folder, which is how the
## content test runs the same loading on its fixtures; [method index] hands the loaded catalog to
## code that reads through an index ([Loadout]), so tests can pass a fixture tree instead.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Content catalog plan): docs/plans/2026-10-29-content-catalog.md

## What a definition is. A kind includes its sub-kinds in lookups and [method all_of]: weapons
## include staves, unit types include commanders, and heirlooms include curses. Never saved.
enum Kind {
	## A [UnitTypeDefinition] that is not a commander ([code]units/[/code]).
	UNIT_TYPE,
	## A [UnitTypeDefinition] with [member UnitTypeDefinition.is_commander]
	## ([code]units/commanders/[/code]).
	COMMANDER,
	## A [UnitPrefixDefinition] ([code]prefixes/units/[/code]).
	UNIT_PREFIX,
	## A [WeaponPrefixDefinition] ([code]prefixes/weapons/[/code]).
	WEAPON_PREFIX,
	## A [FactionDefinition] ([code]factions/[/code]).
	FACTION,
	## A [WeaponDefinition], staves included ([code]items/weapons/<type>/[/code]).
	WEAPON,
	## A [StaffDefinition] ([code]items/weapons/staff/[/code]).
	STAFF,
	## An [EquipmentDefinition] ([code]items/equipment/[/code]).
	EQUIPMENT,
	## A [TrinketDefinition] ([code]items/trinkets/[/code]).
	TRINKET,
	## A [ConsumableDefinition] ([code]items/consumables/[/code]).
	CONSUMABLE,
	## A [RuneDefinition] ([code]runes/[/code]).
	RUNE,
	## A [HeirloomDefinition], curses included ([code]heirlooms/[/code]).
	HEIRLOOM,
	## A [CurseDefinition] ([code]curses/[/code]).
	CURSE,
	## A [TargetShape] ([code]shapes/[/code]).
	SHAPE,
	## A standalone [EffectDefinition], such as a granted effect ([code]effects/[/code]).
	EFFECT,
	## A [TerrainDefinition] ([code]terrain/[/code]); [MapLoader] still loads these by path.
	TERRAIN,
}

## The folder the catalog loads.
const DATA_ROOT: String = "res://data/"

## [method kind_of] for an id the catalog doesn't have.
const NO_KIND: int = -1

## The kind each sub-kind also counts as.
const PARENT_KINDS: Dictionary[Kind, Kind] = {
	Kind.COMMANDER: Kind.UNIT_TYPE,
	Kind.STAFF: Kind.WEAPON,
	Kind.CURSE: Kind.HEIRLOOM,
}

# The catalog of DATA_ROOT once loaded; null until then.
static var _index: Index = null

# Stands in for the catalog when a lookup comes from another thread before it loaded.
static var _empty: Index = Index.new()


## Loads [constant DATA_ROOT] into the catalog, once; later calls do nothing. Call it on the main
## thread at startup; a call from another thread does nothing. Each problem is logged.
static func load_catalog() -> void:
	if _index != null:
		return
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	_index = load_tree(DATA_ROOT)
	for problem: String in _index.problems:
		push_error(problem)


## Whether [method load_catalog] has run.
static func is_loaded() -> bool:
	return _index != null


## The loaded catalog as an [EffectCatalog.Index], loading it first on the main thread. Never
## null: an empty index from another thread before it has loaded (reported as an error).
static func index() -> Index:
	return _require()


## A new [EffectCatalog.Index] of every definition under [param root], walked the way the catalog
## walks [constant DATA_ROOT]. It never becomes the catalog and logs nothing: its problems are in
## [member EffectCatalog.Index.problems]. The content test uses it on its fixture folders.
static func load_tree(root: String) -> Index:
	var index: Index = Index.new()
	index.root = root if root.ends_with("/") else root + "/"
	_walk(index, index.root)
	index.finish()
	return index


## The definition [param id], of any kind; null when there is none.
static func definition(id: String) -> Resource:
	return _require().definition(id)


## Whether the catalog has a definition [param id].
static func has(id: String) -> bool:
	return _require().has(id)


## The [enum Kind] of definition [param id] (its own, never its parent kind); [constant NO_KIND]
## when there is none.
static func kind_of(id: String) -> int:
	return _require().kind_of(id)


## Every definition of [param kind], its sub-kinds included, in id order.
static func all_of(kind: Kind) -> Array[Resource]:
	return _require().all_of(kind)


## Every id in the catalog, in order.
static func ids() -> PackedStringArray:
	return _require().ids()


## What went wrong loading the catalog: files that didn't load or aren't definitions, and empty
## or repeated ids. [b]Empty:[/b] it loaded cleanly.
static func problems() -> PackedStringArray:
	return _require().problems


## The unit type [param id], commanders included; null when there is none.
static func unit_type(id: String) -> UnitTypeDefinition:
	return _require().unit_type(id)


## The commander [param id]; null when there is none or it isn't a commander.
static func commander(id: String) -> UnitTypeDefinition:
	return _require().commander(id)


## The unit prefix [param id]; null when there is none.
static func unit_prefix(id: String) -> UnitPrefixDefinition:
	return _require().unit_prefix(id)


## The weapon prefix [param id]; null when there is none.
static func weapon_prefix(id: String) -> WeaponPrefixDefinition:
	return _require().weapon_prefix(id)


## The faction [param id]; null when there is none.
static func faction(id: String) -> FactionDefinition:
	return _require().faction(id)


## The item [param id] of any item kind (weapon, staff, equipment, trinket, consumable); null when
## there is none.
static func item(id: String) -> ItemDefinition:
	return _require().item(id)


## The weapon [param id], staves included; null when there is none.
static func weapon(id: String) -> WeaponDefinition:
	return _require().weapon(id)


## The staff [param id]; null when there is none.
static func staff(id: String) -> StaffDefinition:
	return _require().staff(id)


## The equipment [param id]; null when there is none.
static func equipment(id: String) -> EquipmentDefinition:
	return _require().equipment(id)


## The trinket [param id]; null when there is none.
static func trinket(id: String) -> TrinketDefinition:
	return _require().trinket(id)


## The consumable [param id]; null when there is none.
static func consumable(id: String) -> ConsumableDefinition:
	return _require().consumable(id)


## The rune [param id]; null when there is none.
static func rune(id: String) -> RuneDefinition:
	return _require().rune(id)


## The heirloom [param id], curses included; null when there is none.
static func heirloom(id: String) -> HeirloomDefinition:
	return _require().heirloom(id)


## The curse [param id]; null when there is none.
static func curse(id: String) -> CurseDefinition:
	return _require().curse(id)


## The target shape [param id]; null when there is none.
static func shape(id: String) -> TargetShape:
	return _require().shape(id)


## The standalone effect [param id]; null when there is none. Effects inside a carrier are not in
## the catalog.
static func effect(id: String) -> EffectDefinition:
	return _require().effect(id)


## The terrain [param id]; null when there is none.
static func terrain(id: String) -> TerrainDefinition:
	return _require().terrain(id)


## The [enum Kind] of [param resource]; [constant NO_KIND] when it is no content definition.
static func classify(resource: Resource) -> int:
	if resource is StaffDefinition:
		return Kind.STAFF
	if resource is WeaponDefinition:
		return Kind.WEAPON
	if resource is EquipmentDefinition:
		return Kind.EQUIPMENT
	if resource is TrinketDefinition:
		return Kind.TRINKET
	if resource is ConsumableDefinition:
		return Kind.CONSUMABLE
	if resource is CurseDefinition:
		return Kind.CURSE
	if resource is HeirloomDefinition:
		return Kind.HEIRLOOM
	if resource is UnitTypeDefinition:
		var unit: UnitTypeDefinition = resource
		return Kind.COMMANDER if unit.is_commander else Kind.UNIT_TYPE
	if resource is UnitPrefixDefinition:
		return Kind.UNIT_PREFIX
	if resource is WeaponPrefixDefinition:
		return Kind.WEAPON_PREFIX
	if resource is FactionDefinition:
		return Kind.FACTION
	if resource is RuneDefinition:
		return Kind.RUNE
	if resource is TargetShape:
		return Kind.SHAPE
	if resource is EffectDefinition:
		return Kind.EFFECT
	if resource is TerrainDefinition:
		return Kind.TERRAIN
	return NO_KIND


## The content id of [param resource], a content definition; empty for anything else.
static func id_of(resource: Resource) -> String:
	if resource is EffectCarrierDefinition:
		var carrier: EffectCarrierDefinition = resource
		return carrier.id
	if resource is EffectDefinition:
		var effect_definition: EffectDefinition = resource
		return effect_definition.id
	if resource is TerrainDefinition:
		var terrain_definition: TerrainDefinition = resource
		return terrain_definition.id
	return ""


# The catalog, loading it first on the main thread. From another thread before it loaded, the
# empty index, with an error: a silent miss there would read as "no such content".
static func _require() -> Index:
	load_catalog()
	if _index == null:
		push_error("EffectCatalog: looked up from another thread before load_catalog() ran")
		return _empty
	return _index


# Adds every file under [param folder] to [param index], folders depth first, in name order, so
# paths are added in path order.
static func _walk(index: Index, folder: String) -> void:
	var entries: PackedStringArray = ResourceLoader.list_directory(folder)
	entries.sort()
	for entry: String in entries:
		if entry.ends_with("/"):
			_walk(index, folder + entry)
		else:
			index.add(folder + entry, ResourceLoader.load(folder + entry))


## One loaded folder tree: every file found, by path, and its definitions by id and kind.
##
## The catalog keeps one for [constant EffectCatalog.DATA_ROOT]; [method EffectCatalog.load_tree]
## builds others. Every file is listed in [member paths], so the content test sees repeated ids
## and files that aren't definitions; lookups see only the first file of each id.
class Index:
	extends RefCounted

	## The folder walked, ending in "/".
	var root: String = ""

	## Every file found, in path order, whether or not it is a definition.
	var paths: PackedStringArray = []

	## What went wrong, one line each: files that didn't load or aren't definitions, and empty or
	## repeated ids. [b]Empty:[/b] the tree loaded cleanly.
	var problems: PackedStringArray = []

	## Why each file in [member paths] that isn't in the index was turned away, by path.
	var rejected: Dictionary[String, String] = {}

	# Every loaded definition by path, repeats included.
	var _by_path: Dictionary[String, Resource] = {}
	# The first definition of each id, and its kind and path.
	var _by_id: Dictionary[String, Resource] = {}
	var _kind_by_id: Dictionary[String, Kind] = {}
	var _path_by_id: Dictionary[String, String] = {}
	# Ids of each kind, sub-kinds included under their parent, sorted by finish().
	var _ids_by_kind: Dictionary[Kind, PackedStringArray] = {}


	## Adds the file at [param path], loaded as [param resource] (null when it didn't load).
	func add(path: String, resource: Resource) -> void:
		paths.append(path)
		if resource == null:
			_reject(path, "it did not load")
			return
		var kind: int = EffectCatalog.classify(resource)
		if kind == EffectCatalog.NO_KIND:
			_reject(path, "it is not a content definition")
			return
		_by_path[path] = resource
		var id: String = EffectCatalog.id_of(resource)
		if id.is_empty():
			problems.append("EffectCatalog: %s - it has no id" % [path])
			return
		if _by_id.has(id):
			problems.append("EffectCatalog: %s - id \"%s\" is already used by %s" % [
				path, id, _path_by_id[id],
			])
			return
		_by_id[id] = resource
		_kind_by_id[id] = kind
		_path_by_id[id] = path
		_list_under(kind, id)
		if EffectCatalog.PARENT_KINDS.has(kind):
			_list_under(EffectCatalog.PARENT_KINDS[kind], id)


	## Sorts each kind's ids; [method EffectCatalog.load_tree] calls it once every file is added.
	func finish() -> void:
		for kind: Kind in _ids_by_kind:
			var listed: PackedStringArray = _ids_by_kind[kind]
			listed.sort()
			_ids_by_kind[kind] = listed


	## The definition loaded from [param path], repeats included; null when the file was turned
	## away ([member rejected]).
	func at_path(path: String) -> Resource:
		return _by_path.get(path, null)


	## The definition [param id], of any kind; null when there is none.
	func definition(id: String) -> Resource:
		return _by_id.get(id, null)


	## Whether there is a definition [param id].
	func has(id: String) -> bool:
		return _by_id.has(id)


	## The [enum EffectCatalog.Kind] of definition [param id], never its parent kind;
	## [constant EffectCatalog.NO_KIND] when there is none.
	func kind_of(id: String) -> int:
		return _kind_by_id.get(id, EffectCatalog.NO_KIND)


	## The file definition [param id] was loaded from; empty when there is none.
	func path_of(id: String) -> String:
		return _path_by_id.get(id, "")


	## Whether definition [param id] is of [param kind] or one of its sub-kinds.
	func is_of(id: String, kind: Kind) -> bool:
		if not _kind_by_id.has(id):
			return false
		var own: Kind = _kind_by_id[id]
		return own == kind or EffectCatalog.PARENT_KINDS.get(own, EffectCatalog.NO_KIND) == kind


	## Every definition of [param kind], its sub-kinds included, in id order.
	func all_of(kind: Kind) -> Array[Resource]:
		var found: Array[Resource] = []
		for id: String in _ids_by_kind.get(kind, PackedStringArray()):
			found.append(_by_id[id])
		return found


	## Every id, in order.
	func ids() -> PackedStringArray:
		var all: PackedStringArray = PackedStringArray(_by_id.keys())
		all.sort()
		return all


	## The unit type [param id], commanders included; null when there is none.
	func unit_type(id: String) -> UnitTypeDefinition:
		return _of_kind(id, Kind.UNIT_TYPE) as UnitTypeDefinition


	## The commander [param id]; null when there is none or it isn't a commander.
	func commander(id: String) -> UnitTypeDefinition:
		return _of_kind(id, Kind.COMMANDER) as UnitTypeDefinition


	## The unit prefix [param id]; null when there is none.
	func unit_prefix(id: String) -> UnitPrefixDefinition:
		return _of_kind(id, Kind.UNIT_PREFIX) as UnitPrefixDefinition


	## The weapon prefix [param id]; null when there is none.
	func weapon_prefix(id: String) -> WeaponPrefixDefinition:
		return _of_kind(id, Kind.WEAPON_PREFIX) as WeaponPrefixDefinition


	## The faction [param id]; null when there is none.
	func faction(id: String) -> FactionDefinition:
		return _of_kind(id, Kind.FACTION) as FactionDefinition


	## The item [param id] of any item kind; null when there is none.
	func item(id: String) -> ItemDefinition:
		return definition(id) as ItemDefinition


	## The weapon [param id], staves included; null when there is none.
	func weapon(id: String) -> WeaponDefinition:
		return _of_kind(id, Kind.WEAPON) as WeaponDefinition


	## The staff [param id]; null when there is none.
	func staff(id: String) -> StaffDefinition:
		return _of_kind(id, Kind.STAFF) as StaffDefinition


	## The equipment [param id]; null when there is none.
	func equipment(id: String) -> EquipmentDefinition:
		return _of_kind(id, Kind.EQUIPMENT) as EquipmentDefinition


	## The trinket [param id]; null when there is none.
	func trinket(id: String) -> TrinketDefinition:
		return _of_kind(id, Kind.TRINKET) as TrinketDefinition


	## The consumable [param id]; null when there is none.
	func consumable(id: String) -> ConsumableDefinition:
		return _of_kind(id, Kind.CONSUMABLE) as ConsumableDefinition


	## The rune [param id]; null when there is none.
	func rune(id: String) -> RuneDefinition:
		return _of_kind(id, Kind.RUNE) as RuneDefinition


	## The heirloom [param id], curses included; null when there is none.
	func heirloom(id: String) -> HeirloomDefinition:
		return _of_kind(id, Kind.HEIRLOOM) as HeirloomDefinition


	## The curse [param id]; null when there is none.
	func curse(id: String) -> CurseDefinition:
		return _of_kind(id, Kind.CURSE) as CurseDefinition


	## The target shape [param id]; null when there is none.
	func shape(id: String) -> TargetShape:
		return _of_kind(id, Kind.SHAPE) as TargetShape


	## The standalone effect [param id]; null when there is none.
	func effect(id: String) -> EffectDefinition:
		return _of_kind(id, Kind.EFFECT) as EffectDefinition


	## The terrain [param id]; null when there is none.
	func terrain(id: String) -> TerrainDefinition:
		return _of_kind(id, Kind.TERRAIN) as TerrainDefinition


	func _of_kind(id: String, kind: Kind) -> Resource:
		return _by_id[id] if is_of(id, kind) else null


	# Assigned back rather than appended in place: a packed array read from a Dictionary is a copy.
	func _list_under(kind: Kind, id: String) -> void:
		var listed: PackedStringArray = _ids_by_kind.get(kind, PackedStringArray())
		listed.append(id)
		_ids_by_kind[kind] = listed


	func _reject(path: String, reason: String) -> void:
		rejected[path] = reason
		problems.append("EffectCatalog: %s - %s" % [path, reason])
