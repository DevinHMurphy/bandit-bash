# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     catalog_cases.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

extends RefCounted
## The catalog's cases and the content test, for tests/content/run_all.gd: [EffectCatalog] over
## [code]res://data/[/code] and over the fixture trees, its typed lookups and kinds, and the
## content rules of content_rules.gd over all of [code]res://data/[/code], a valid tree with one
## file of every kind, and one bad tree per rule.
##
## Each tree under [constant RULES_DIR] is a small data root, loaded by
## [method EffectCatalog.load_tree] exactly as the catalog loads [code]res://data/[/code]; a bad
## tree must break its own rule and no other. [method fingerprint] hashes a definition with every
## stored value and sub-resource, for run_all.gd's check that no catalog definition changes
## during the run. Reports each case through the check callable it is given.

# A preloaded script used as a type (gdscript.md, Naming): the rules script has no class name.
const ContentRules = preload("res://tests/content/content_rules.gd")

## The folder holding one data root per rule fixture.
const RULES_DIR: String = "res://tests/content/fixtures/rules/"

# Each bad tree and the one rule it breaks, checked against the real price table.
const BAD_TREES: Dictionary[String, String] = {
	"load_not_definition": ContentRules.LOAD,
	"id_file_name": ContentRules.ID_FILE_NAME,
	"duplicate_id": ContentRules.DUPLICATE_ID,
	"dangling_missing": ContentRules.DANGLING_REFERENCE,
	"dangling_wrong_kind": ContentRules.DANGLING_REFERENCE,
	"empty_text": ContentRules.EMPTY_TEXT,
	"heirloom_this_unit": ContentRules.HEIRLOOM_THIS_UNIT,
	"inline_without_window": ContentRules.INLINE_WITHOUT_WINDOW,
	"folder_weapon_type": ContentRules.FOLDER,
	"folder_staff_type": ContentRules.FOLDER,
	"folder_commander_outside": ContentRules.FOLDER,
	"folder_not_commander_inside": ContentRules.FOLDER,
	"folder_prefix_all_typed": ContentRules.FOLDER,
	"folder_prefix_two_types": ContentRules.FOLDER,
	"range_empty": ContentRules.RANGE,
	"range_attack_at_zero": ContentRules.RANGE,
	"range_attack_staff": ContentRules.RANGE,
	"unknown_tag": ContentRules.UNKNOWN_ID,
	"unknown_curse_tier": ContentRules.UNKNOWN_ID,
	"no_operations": ContentRules.NO_OPERATIONS,
	"commander_starting": ContentRules.COMMANDER_STARTING,
	"gear_slot": ContentRules.GEAR_SLOT,
}

# The trees checked by their own cases rather than BAD_TREES.
const OTHER_TREES: PackedStringArray = [
	"valid",
	"heirloom_not_unique",
	"unpriced",
	"unsellable_priced",
]

# The valid tree's ids and their own kinds.
const VALID_KINDS: Dictionary[String, EffectCatalog.Kind] = {
	"fixture_archer": EffectCatalog.Kind.UNIT_TYPE,
	"fixture_drengr": EffectCatalog.Kind.COMMANDER,
	"fixture_sturdy": EffectCatalog.Kind.UNIT_PREFIX,
	"fixture_keen_edge": EffectCatalog.Kind.WEAPON_PREFIX,
	"fixture_long_draw": EffectCatalog.Kind.WEAPON_PREFIX,
	"fixture_mercenary": EffectCatalog.Kind.FACTION,
	"fixture_bow": EffectCatalog.Kind.WEAPON,
	"fixture_everwall": EffectCatalog.Kind.STAFF,
	"fixture_buckler": EffectCatalog.Kind.EQUIPMENT,
	"fixture_charm": EffectCatalog.Kind.TRINKET,
	"fixture_potion": EffectCatalog.Kind.CONSUMABLE,
	"fixture_mend": EffectCatalog.Kind.RUNE,
	"fixture_iron_heart": EffectCatalog.Kind.HEIRLOOM,
	"fixture_family_relic": EffectCatalog.Kind.HEIRLOOM,
	"fixture_brittle_guard": EffectCatalog.Kind.CURSE,
	"fixture_adjacent": EffectCatalog.Kind.SHAPE,
	"fixture_infuse": EffectCatalog.Kind.EFFECT,
	"fixture_plain": EffectCatalog.Kind.TERRAIN,
}

var _check: Callable


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check


## Runs every case.
func run() -> void:
	_test_catalog_loads_data()
	_test_catalog_lookups_miss()
	_test_tree_walk()
	_test_valid_tree_kinds()
	_test_valid_tree_lookups()
	_test_sub_kinds()
	_test_catalog_problems()
	_test_content_test_over_data()
	_test_valid_tree_passes()
	_test_bad_trees()
	_test_warning_tree()
	_test_price_trees()
	_test_every_rule_has_a_tree()
	_test_fingerprint_detects_changes()


func _test_catalog_loads_data() -> void:
	EffectCatalog.load_catalog()
	_check.call("catalog: loaded", EffectCatalog.is_loaded(), "")
	_check.call(
			"catalog: res://data/ loads without problems",
			EffectCatalog.problems().is_empty(),
			" | ".join(EffectCatalog.problems())
	)
	var files: PackedStringArray = _files_under(EffectCatalog.DATA_ROOT)
	_check.call("catalog: one id per file under res://data/ (%d)" % [files.size()], (
			EffectCatalog.ids().size() == files.size()
	), "%d ids" % [EffectCatalog.ids().size()])
	var terrain_files: PackedStringArray = _files_under(EffectCatalog.DATA_ROOT + "terrain/")
	var terrain_ok: bool = (
			EffectCatalog.all_of(EffectCatalog.Kind.TERRAIN).size() == terrain_files.size()
	)
	for path: String in terrain_files:
		var id: String = path.get_file().get_basename()
		var found: TerrainDefinition = EffectCatalog.terrain(id)
		# The same shared instance MapLoader gets by path: the catalog copies nothing.
		terrain_ok = terrain_ok and found != null and found == ResourceLoader.load(path)
	_check.call(
			"catalog: every terrain file, the instance the loader shares (%d)" % [
				terrain_files.size(),
			],
			terrain_ok,
			""
	)
	_check.call("catalog: a terrain's kind", (
			EffectCatalog.kind_of("plain") == EffectCatalog.Kind.TERRAIN
			and EffectCatalog.has("plain")
			and EffectCatalog.definition("plain") is TerrainDefinition
	), "")


func _test_catalog_lookups_miss() -> void:
	var missing: String = "no_such_definition"
	var misses: Array[Resource] = [
		EffectCatalog.definition(missing),
		EffectCatalog.unit_type(missing),
		EffectCatalog.commander(missing),
		EffectCatalog.unit_prefix(missing),
		EffectCatalog.weapon_prefix(missing),
		EffectCatalog.faction(missing),
		EffectCatalog.item(missing),
		EffectCatalog.weapon(missing),
		EffectCatalog.staff(missing),
		EffectCatalog.equipment(missing),
		EffectCatalog.trinket(missing),
		EffectCatalog.consumable(missing),
		EffectCatalog.rune(missing),
		EffectCatalog.heirloom(missing),
		EffectCatalog.curse(missing),
		EffectCatalog.shape(missing),
		EffectCatalog.effect(missing),
		EffectCatalog.terrain(missing),
	]
	var all_null: bool = true
	for found: Resource in misses:
		all_null = all_null and found == null
	_check.call("catalog: every lookup of a missing id is null", all_null, "")
	_check.call("catalog: a missing id has no kind", (
			EffectCatalog.kind_of(missing) == EffectCatalog.NO_KIND
			and not EffectCatalog.has(missing)
	), "")
	_check.call("catalog: a lookup of another kind is null", (
			EffectCatalog.shape("plain") == null and EffectCatalog.item("plain") == null
	), "")


func _test_tree_walk() -> void:
	var index: EffectCatalog.Index = _tree("valid")
	var files: PackedStringArray = _files_under(RULES_DIR + "valid/")
	_check.call(
			"tree: every file of the valid tree, in path order",
			index.paths == files,
			"%s vs %s" % [index.paths, files]
	)
	_check.call("tree: the root ends with a slash", (
			EffectCatalog.load_tree(RULES_DIR + "valid").root == RULES_DIR + "valid/"
	), "")
	var empty: EffectCatalog.Index = EffectCatalog.load_tree(RULES_DIR + "no_such_folder/")
	_check.call("tree: a missing folder loads nothing", (
			empty.paths.is_empty() and empty.ids().is_empty() and empty.problems.is_empty()
	), "")


func _test_valid_tree_kinds() -> void:
	var index: EffectCatalog.Index = _tree("valid")
	_check.call("valid tree: loads without problems", (
			index.problems.is_empty()
	), " | ".join(index.problems))
	var ids: PackedStringArray = PackedStringArray(VALID_KINDS.keys())
	ids.sort()
	_check.call("valid tree: one id per file, in order", index.ids() == ids, str(index.ids()))
	for id: String in VALID_KINDS:
		_check.call("valid tree: %s is a %s" % [id, _kind_name(VALID_KINDS[id])], (
				index.kind_of(id) == VALID_KINDS[id]
		), _kind_name(index.kind_of(id)))
	var covered: Dictionary[int, bool] = {}
	for id: String in VALID_KINDS:
		covered[VALID_KINDS[id]] = true
	_check.call(
			"valid tree: every kind has a file",
			covered.size() == EffectCatalog.Kind.size(),
			str(covered.keys())
	)
	_check.call("valid tree: a definition's file", (
			index.path_of("fixture_bow") == RULES_DIR + "valid/items/weapons/bow/fixture_bow.tres"
			and index.path_of("no_such_definition").is_empty()
	), index.path_of("fixture_bow"))


func _test_valid_tree_lookups() -> void:
	var index: EffectCatalog.Index = _tree("valid")
	var typed: Dictionary[String, bool] = {
		"unit_type": index.unit_type("fixture_archer") is UnitTypeDefinition,
		"commander": index.commander("fixture_drengr") is UnitTypeDefinition,
		"unit_prefix": index.unit_prefix("fixture_sturdy") is UnitPrefixDefinition,
		"weapon_prefix": index.weapon_prefix("fixture_long_draw") is WeaponPrefixDefinition,
		"faction": index.faction("fixture_mercenary") is FactionDefinition,
		"item": index.item("fixture_potion") is ConsumableDefinition,
		"weapon": index.weapon("fixture_bow") is WeaponDefinition,
		"staff": index.staff("fixture_everwall") is StaffDefinition,
		"equipment": index.equipment("fixture_buckler") is EquipmentDefinition,
		"trinket": index.trinket("fixture_charm") is TrinketDefinition,
		"consumable": index.consumable("fixture_potion") is ConsumableDefinition,
		"rune": index.rune("fixture_mend") is RuneDefinition,
		"heirloom": index.heirloom("fixture_iron_heart") is HeirloomDefinition,
		"curse": index.curse("fixture_brittle_guard") is CurseDefinition,
		"shape": index.shape("fixture_adjacent") is TargetShape,
		"effect": index.effect("fixture_infuse") is EffectDefinition,
		"terrain": index.terrain("fixture_plain") is TerrainDefinition,
	}
	for lookup: String in typed:
		_check.call("lookups: %s finds its kind" % [lookup], typed[lookup], "")
	_check.call("lookups: another kind's id is null", (
			index.rune("fixture_bow") == null
			and index.faction("fixture_drengr") == null
			and index.effect("fixture_iron_heart") == null
			and index.item("fixture_mend") == null
	), "")
	var bow: WeaponDefinition = index.weapon("fixture_bow")
	_check.call("lookups: the definition is the file's", (
			bow != null and bow.range_max == 3 and bow == index.definition("fixture_bow")
	), "")


func _test_sub_kinds() -> void:
	var index: EffectCatalog.Index = _tree("valid")
	_check.call("sub-kinds: a staff is a weapon, a weapon is no staff", (
			index.weapon("fixture_everwall") != null and index.staff("fixture_bow") == null
	), "")
	_check.call("sub-kinds: a commander is a unit type, a unit type is no commander", (
			index.unit_type("fixture_drengr") != null and index.commander("fixture_archer") == null
	), "")
	_check.call("sub-kinds: a curse is a heirloom, a heirloom is no curse", (
			index.heirloom("fixture_brittle_guard") != null
			and index.curse("fixture_iron_heart") == null
	), "")
	_check.call("sub-kinds: kind_of names the own kind", (
			index.kind_of("fixture_everwall") == EffectCatalog.Kind.STAFF
			and index.is_of("fixture_everwall", EffectCatalog.Kind.WEAPON)
			and not index.is_of("fixture_bow", EffectCatalog.Kind.STAFF)
	), "")
	var expected: Dictionary[EffectCatalog.Kind, PackedStringArray] = {
		EffectCatalog.Kind.WEAPON: PackedStringArray(["fixture_bow", "fixture_everwall"]),
		EffectCatalog.Kind.STAFF: PackedStringArray(["fixture_everwall"]),
		EffectCatalog.Kind.UNIT_TYPE: PackedStringArray(["fixture_archer", "fixture_drengr"]),
		EffectCatalog.Kind.COMMANDER: PackedStringArray(["fixture_drengr"]),
		EffectCatalog.Kind.HEIRLOOM: PackedStringArray([
			"fixture_brittle_guard", "fixture_family_relic", "fixture_iron_heart",
		]),
		EffectCatalog.Kind.CURSE: PackedStringArray(["fixture_brittle_guard"]),
		EffectCatalog.Kind.WEAPON_PREFIX: PackedStringArray([
			"fixture_keen_edge", "fixture_long_draw",
		]),
	}
	for kind: EffectCatalog.Kind in expected:
		var ids: PackedStringArray = _ids_of(index.all_of(kind))
		_check.call("all of a kind: %s, sub-kinds included, by id" % [_kind_name(kind)], (
				ids == expected[kind]
		), str(ids))


func _test_catalog_problems() -> void:
	var twins: EffectCatalog.Index = _tree("duplicate_id")
	_check.call("problems: a repeated id is reported and the first file wins", (
			twins.problems.size() == 1
			and twins.problems[0].contains("fixture_twin")
			and twins.kind_of("fixture_twin") == EffectCatalog.Kind.SHAPE
			and twins.paths.size() == 2
	), " | ".join(twins.problems))
	var odd: EffectCatalog.Index = _tree("load_not_definition")
	var odd_path: String = RULES_DIR + "load_not_definition/effects/fixture_plain_resource.tres"
	_check.call("problems: a file that is no definition is turned away", (
			odd.rejected.has(odd_path)
			and odd.ids().is_empty()
			and odd.at_path(odd_path) == null
			and odd.problems.size() == 1
	), " | ".join(odd.problems))
	var renamed: EffectCatalog.Index = _tree("id_file_name")
	_check.call("problems: the catalog indexes by id, not file name", (
			renamed.has("fixture_other_shape") and not renamed.has("fixture_shape")
	), "")


func _test_content_test_over_data() -> void:
	var data: EffectCatalog.Index = EffectCatalog.load_tree(EffectCatalog.DATA_ROOT)
	var findings: Array[ContentRules.Finding] = ContentRules.new(data).check()
	_check.call(
			"content test: res://data/ breaks no rule (%d files)" % [data.paths.size()],
			_rules(findings, false).is_empty(),
			_describe(findings)
	)
	_check.call(
			"content test: res://data/ has no warnings",
			_rules(findings, true).is_empty(),
			_describe(findings)
	)
	_check.call("content test: it checks the catalog's own definitions", (
			data.ids() == EffectCatalog.ids()
			and data.definition("plain") == EffectCatalog.definition("plain")
	), "")


func _test_valid_tree_passes() -> void:
	var findings: Array[ContentRules.Finding] = ContentRules.new(_tree("valid")).check()
	_check.call(
			"content test: the valid tree breaks no rule and warns of nothing",
			findings.is_empty(),
			_describe(findings)
	)


func _test_bad_trees() -> void:
	for tree: String in BAD_TREES:
		var rule: String = BAD_TREES[tree]
		var findings: Array[ContentRules.Finding] = ContentRules.new(_tree(tree)).check()
		_check.call("bad tree %s: breaks %s and nothing else" % [tree, rule], (
				_rules(findings, false) == PackedStringArray([rule])
				and _rules(findings, true).is_empty()
		), _describe(findings))


func _test_warning_tree() -> void:
	var findings: Array[ContentRules.Finding] = (
			ContentRules.new(_tree("heirloom_not_unique")).check()
	)
	_check.call("warning tree heirloom_not_unique: warns once and fails nothing", (
			_rules(findings, false).is_empty()
			and _rules(findings, true) == PackedStringArray([ContentRules.HEIRLOOM_NOT_UNIQUE])
			and findings.size() == 1
	), _describe(findings))


func _test_price_trees() -> void:
	var unpriced: EffectCatalog.Index = _tree("unpriced")
	var with_prices: Array[ContentRules.Finding] = ContentRules.new(unpriced).check()
	_check.call("price tree unpriced: passes with the real price table", (
			with_prices.is_empty()
	), _describe(with_prices))
	var without_trinkets: Array[ContentRules.Finding] = (
			ContentRules.new(unpriced, _price_without_trinkets).check()
	)
	_check.call("price tree unpriced: breaks unpriced and nothing else, with no trinket row", (
			_rules(without_trinkets, false) == PackedStringArray([ContentRules.UNPRICED])
			and _rules(without_trinkets, true).is_empty()
	), _describe(without_trinkets))

	var relic: EffectCatalog.Index = _tree("unsellable_priced")
	var relic_real: Array[ContentRules.Finding] = ContentRules.new(relic).check()
	_check.call("price tree unsellable_priced: passes with the real price table", (
			relic_real.is_empty()
	), _describe(relic_real))
	var relic_priced: Array[ContentRules.Finding] = (
			ContentRules.new(relic, _price_everything).check()
	)
	_check.call("price tree unsellable_priced: breaks its rule and nothing else, priced", (
			_rules(relic_priced, false) == PackedStringArray([ContentRules.UNSELLABLE_PRICED])
			and _rules(relic_priced, true).is_empty()
	), _describe(relic_priced))


func _test_every_rule_has_a_tree() -> void:
	var covered: PackedStringArray = [
		ContentRules.UNPRICED, ContentRules.UNSELLABLE_PRICED,
	]
	for tree: String in BAD_TREES:
		if not covered.has(BAD_TREES[tree]):
			covered.append(BAD_TREES[tree])
	covered.sort()
	var rules: PackedStringArray = ContentRules.FAILURE_RULES.duplicate()
	rules.sort()
	_check.call("content test: every failing rule has a bad tree", covered == rules, str(covered))
	var unchecked: PackedStringArray = []
	for tree: String in DirAccess.get_directories_at(RULES_DIR):
		if not BAD_TREES.has(tree) and not OTHER_TREES.has(tree):
			unchecked.append(tree)
	_check.call(
			"content test: every tree on disk is checked",
			unchecked.is_empty(),
			str(unchecked)
	)


func _test_fingerprint_detects_changes() -> void:
	var index: EffectCatalog.Index = _tree("valid")
	var bow: WeaponDefinition = index.weapon("fixture_bow")
	var heart: HeirloomDefinition = index.heirloom("fixture_iron_heart")
	if bow == null or heart == null:
		_check.call("fingerprint: the fixtures load", false, "")
		return
	var bow_hash: String = fingerprint(bow)
	var heart_hash: String = fingerprint(heart)
	_check.call("fingerprint: stable on the same definition", (
			fingerprint(bow) == bow_hash and bow_hash != heart_hash
	), "")

	bow.damage += 1
	var changed_field: bool = fingerprint(bow) != bow_hash
	bow.damage -= 1
	var original: PackedStringArray = bow.effective_against
	var longer: PackedStringArray = original.duplicate()
	longer.append("armored")
	bow.effective_against = longer
	var changed_list: bool = fingerprint(bow) != bow_hash
	bow.effective_against = original
	var operation: ModifyThat = heart.effects[0].operations[0] as ModifyThat
	operation.flag = ModifyThat.Flag.SKIP_MITIGATION
	var changed_block: bool = fingerprint(heart) != heart_hash
	operation.flag = ModifyThat.Flag.LIFESTEAL
	_check.call("fingerprint: a changed field changes it", changed_field, "")
	_check.call("fingerprint: a changed list changes it", changed_list, "")
	_check.call("fingerprint: a changed nested block changes it", changed_block, "")
	_check.call("fingerprint: restored, it matches again", (
			fingerprint(bow) == bow_hash and fingerprint(heart) == heart_hash
	), "")


func _tree(name: String) -> EffectCatalog.Index:
	return EffectCatalog.load_tree(RULES_DIR + name)


# Every resource file under [param folder], read with DirAccess rather than the catalog's own
# walk, in path order.
func _files_under(folder: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() in ["tres", "res"]:
			found.append(folder + file)
	for child: String in DirAccess.get_directories_at(folder):
		found.append_array(_files_under(folder + child + "/"))
	found.sort()
	return found


# The distinct rules of [param findings] that warn ([param warnings]) or fail, sorted.
func _rules(findings: Array[ContentRules.Finding], warnings: bool) -> PackedStringArray:
	var rules: PackedStringArray = []
	for finding: ContentRules.Finding in findings:
		if finding.is_warning == warnings and not rules.has(finding.rule):
			rules.append(finding.rule)
	rules.sort()
	return rules


func _describe(findings: Array[ContentRules.Finding]) -> String:
	var lines: PackedStringArray = []
	for finding: ContentRules.Finding in findings:
		lines.append(str(finding))
	return " | ".join(lines)


func _ids_of(definitions: Array[Resource]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for definition: Resource in definitions:
		ids.append(EffectCatalog.id_of(definition))
	return ids


func _kind_name(kind: int) -> String:
	var found: Variant = EffectCatalog.Kind.find_key(kind)
	return "no kind" if found == null else (found as String).to_lower()


func _price_without_trinkets(kind: String, rarity: ItemDefinition.Rarity) -> int:
	if kind == ContentIds.ITEM_TRINKET:
		return Prices.NO_PRICE
	return Prices.buy_price(kind, rarity)


func _price_everything(_kind: String, _rarity: ItemDefinition.Rarity) -> int:
	return 1


## Every catalog definition's [method fingerprint], by id.
static func hash_catalog() -> Dictionary[String, String]:
	var hashes: Dictionary[String, String] = {}
	for id: String in EffectCatalog.ids():
		hashes[id] = fingerprint(EffectCatalog.definition(id))
	return hashes


## [method hash_catalog], plus the [method fingerprint] of every definition under each fixture tree
## in [param roots], by root and id. A tree loads the same shared instances its cases use, so a
## suite whose cases change one is caught.
static func hash_definitions(roots: PackedStringArray) -> Dictionary[String, String]:
	var hashes: Dictionary[String, String] = hash_catalog()
	for root: String in roots:
		var index: EffectCatalog.Index = EffectCatalog.load_tree(root)
		for id: String in index.ids():
			hashes["%s %s" % [root, id]] = fingerprint(index.definition(id))
	return hashes


## The ids in [param before] (a [method hash_definitions] result) whose hash is different or gone
## in [param after]; also notes ids added since.
static func changed_definitions(
		before: Dictionary[String, String], after: Dictionary[String, String]
) -> PackedStringArray:
	var changed: PackedStringArray = []
	for id: String in before:
		if after.get(id, "") != before[id]:
			changed.append(id)
	for id: String in after:
		if not before.has(id):
			changed.append("%s (added)" % [id])
	return changed


## A hash of [param value] and everything it stores: every stored property of an object, its
## sub-resources' too, and the contents of arrays and dictionaries. Scripts count by path.
static func fingerprint(value: Variant) -> String:
	var parts: Array[String] = []
	_fingerprint_into(value, parts)
	return "".join(PackedStringArray(parts)).sha256_text()


static func _fingerprint_into(value: Variant, parts: Array[String]) -> void:
	match typeof(value):
		TYPE_OBJECT:
			var object: Object = value
			if object == null:
				parts.append("null;")
				return
			if object is Script:
				parts.append("script %s;" % [(object as Script).resource_path])
				return
			parts.append("%s{" % [object.get_class()])
			for property: Dictionary in object.get_property_list():
				var usage: int = property["usage"]
				if usage & PROPERTY_USAGE_STORAGE == 0:
					continue
				var property_name: String = property["name"]
				parts.append("%s=" % [property_name])
				_fingerprint_into(object.get(property_name), parts)
			parts.append("}")
		TYPE_ARRAY:
			parts.append("[")
			for item: Variant in value as Array:
				_fingerprint_into(item, parts)
			parts.append("]")
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			parts.append("{")
			for key: Variant in dictionary:
				_fingerprint_into(key, parts)
				parts.append(":")
				_fingerprint_into(dictionary[key], parts)
			parts.append("}")
		_:
			parts.append("%s;" % [var_to_str(value)])
