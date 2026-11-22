# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     item_comparison_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The Armory's before/after comparison for the ui/campaign suite: an equipment's Effects row
## ([method ArmoryModel.comparison_rows]) carries keyword tags, and [ItemComparison] shows each side
## in an [EffectText] whose getters, and [member ItemComparison.shown], give the plain words a
## plain label showed; hovering a keyword shows its tooltip. An empty slot's side reads
## [constant ArmoryModel.NONE]. A weapon's number rows stay plain labels, the change coloured.
## Built from the real scene on the root viewport with the loaded catalog.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/campaign"

const COMPARISON_SCENE: PackedScene = preload("res://ui/campaign/item_comparison.tscn")

# The equipment compared: the one held, and the one offered.
const HELD_ID: String = "iron_shield"
const OFFERED_ID: String = "steel_shield"

const EFFECTS_LABEL: String = "Effects"

var _check: Callable
var _root: Window = null
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the comparison is added.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	var held: ItemDefinition = _catalog.item(HELD_ID)
	var offered: ItemDefinition = _catalog.item(OFFERED_ID)
	_check.call("comparison: the compared equipment is in the catalog", (
			held != null and offered != null
	), "")
	if held == null or offered == null:
		return
	_test_marked_rows(held, offered)
	_test_shown(held, offered)
	_test_empty_slot(offered)
	_test_number_rows()


func _test_marked_rows(held: ItemDefinition, offered: ItemDefinition) -> void:
	var rows: Array[ArmoryModel.Row] = ArmoryModel.comparison_rows(
			ItemInstance.new("held_item", held.id), offered, _catalog
	)
	var effects: ArmoryModel.Row = _row(rows, EFFECTS_LABEL)
	_check.call("model: the Effects row is marked and carries both items' keyword tags", (
			effects != null and effects.is_marked
			and effects.before == "\n".join(held.describe_marked())
			and effects.after == "\n".join(offered.describe_marked())
			and effects.before.contains("[kw=") and effects.after.contains("[kw=")
	), "" if effects == null else "%s | %s" % [effects.before, effects.after])
	var kind: ArmoryModel.Row = _row(rows, "Kind")
	_check.call("model: the Kind row stays plain", kind != null and not kind.is_marked, "")


func _test_shown(held: ItemDefinition, offered: ItemDefinition) -> void:
	var rows: Array[ArmoryModel.Row] = ArmoryModel.comparison_rows(
			ItemInstance.new("held_item", held.id), offered, _catalog
	)
	var comparison: ItemComparison = _show(held.display_name, offered.display_name, rows)
	var texts: Array[EffectText] = _effect_texts(comparison)
	var plain_before: String = "\n".join(held.describe())
	var plain_after: String = "\n".join(offered.describe())
	var shown: PackedStringArray = _shown_row(comparison, EFFECTS_LABEL)
	_check.call("view: the Effects row is two EffectTexts, marked as the model gives them", (
			texts.size() == 2
			and texts[0].marked_text == _row(rows, EFFECTS_LABEL).before
			and texts[1].marked_text == _row(rows, EFFECTS_LABEL).after
	), "%d effect texts" % [texts.size()])
	if texts.size() != 2:
		comparison.free()
		return
	_check.call("view: the getters give the plain words, as describe() reads", (
			texts[0].get_plain_text() == plain_before and texts[1].get_plain_text() == plain_after
			and shown == PackedStringArray([EFFECTS_LABEL, plain_before, plain_after])
	), "%s | %s | shown %s" % [texts[0].get_plain_text(), texts[1].get_plain_text(), shown])
	var ids: PackedStringArray = texts[1].get_keyword_ids()
	_check.call("view: the offer's keywords are known to the glossary", not ids.is_empty(), "")
	if not ids.is_empty():
		texts[1].meta_hover_started.emit(ids[0])
		var tooltips: Array[KeywordTooltip] = texts[1].get_shown_tooltips()
		_check.call("view: hovering a keyword shows its one tooltip", tooltips.size() == 1, (
				"%d tooltips for %s" % [tooltips.size(), ids[0]]
		))
		texts[1].meta_hover_ended.emit(ids[0])
		_check.call("view: leaving the keyword hides it", (
				texts[1].get_shown_tooltips().is_empty()
		), "")
	comparison.free()


func _test_empty_slot(offered: ItemDefinition) -> void:
	var rows: Array[ArmoryModel.Row] = ArmoryModel.comparison_rows(null, offered, _catalog)
	var comparison: ItemComparison = _show(ArmoryModel.NONE, offered.display_name, rows)
	var texts: Array[EffectText] = _effect_texts(comparison)
	_check.call("empty slot: the replaced side of the Effects row reads none", (
			texts.size() == 2 and texts[0].get_plain_text() == ArmoryModel.NONE
			and _shown_row(comparison, EFFECTS_LABEL)[1] == ArmoryModel.NONE
	), str(_shown_row(comparison, EFFECTS_LABEL)))
	comparison.free()


func _test_number_rows() -> void:
	var kinds: Array[EffectCatalog.Kind] = [EffectCatalog.Kind.WEAPON]
	var weapons: Array[ItemDefinition] = ItemPools.items_of(_catalog, kinds)
	if weapons.size() < 2:
		_check.call("weapons: two in the catalog", false, str(weapons.size()))
		return
	var held: ItemInstance = ItemInstance.new("held_weapon", weapons[0].id)
	var rows: Array[ArmoryModel.Row] = ArmoryModel.comparison_rows(held, weapons[1], _catalog)
	var is_any_marked: bool = false
	for row: ArmoryModel.Row in rows:
		is_any_marked = is_any_marked or row.is_marked
	var comparison: ItemComparison = _show(weapons[0].display_name, weapons[1].display_name, rows)
	var cells: int = 0
	for child: Node in comparison.get_children():
		if child is Label:
			cells += 1
	_check.call("weapons: number rows stay plain labels, none marked", (
			not is_any_marked and _effect_texts(comparison).is_empty()
			and cells == (rows.size() + 1) * comparison.columns
			and _shown_row(comparison, "Damage").size() == 3
	), "%d labels for %d rows" % [cells, rows.size()])
	comparison.free()


# The comparison scene on the root, showing rows.
func _show(
		before_name: String, after_name: String, rows: Array[ArmoryModel.Row]
) -> ItemComparison:
	var comparison: ItemComparison = COMPARISON_SCENE.instantiate()
	_root.add_child(comparison)
	comparison.show_comparison(before_name, after_name, rows)
	return comparison


func _effect_texts(comparison: ItemComparison) -> Array[EffectText]:
	var texts: Array[EffectText] = []
	for child: Node in comparison.get_children():
		var text: EffectText = child as EffectText
		if text != null:
			texts.append(text)
	return texts


func _row(rows: Array[ArmoryModel.Row], label: String) -> ArmoryModel.Row:
	for row: ArmoryModel.Row in rows:
		if row.label == label:
			return row
	return null


# The comparison's shown row of label; empty when there is none.
func _shown_row(comparison: ItemComparison, label: String) -> PackedStringArray:
	for row: PackedStringArray in comparison.shown:
		if row[0] == label:
			return row
	return PackedStringArray()
