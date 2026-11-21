# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     dump_effect_text.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends SceneTree
## Prints every effect carrier's name, id and effect text
## ([method EffectCarrierDefinition.describe]) by kind, as the tables of
## docs/design/effect-text.md, so that review file can be regenerated
## after a text change: one [code]## <kind>[/code] section per kind in [constant SECTIONS], one
## row per carrier sorted by id, its lines joined by [constant LINE_JOIN], and an empty New wording
## column. Weapons include staves and heirlooms include curses, as the catalog lists them.[br]
## Run from the repo root:
## [code]godot --headless --path bandit-bash --script res://tools/dump_effect_text.gd[/code],
## optionally followed by [code]-- --out <file>[/code] to also write the tables there. Ends with a
## [code]--- N carriers ---[/code] line; exits with code 1 when the catalog has problems or the
## file can't be written. Authoring tooling: nothing in the game loads it.
##
## @tutorial(Effect text): docs/design/effect-text.md

## The sections, in order: each heading and the catalog kind it lists.
const SECTIONS: Array[Array] = [
	["Weapon", EffectCatalog.Kind.WEAPON],
	["Staff", EffectCatalog.Kind.STAFF],
	["Equipment", EffectCatalog.Kind.EQUIPMENT],
	["Trinket", EffectCatalog.Kind.TRINKET],
	["Consumable", EffectCatalog.Kind.CONSUMABLE],
	["Heirloom", EffectCatalog.Kind.HEIRLOOM],
	["Curse", EffectCatalog.Kind.CURSE],
	["Rune", EffectCatalog.Kind.RUNE],
	["Weapon prefix", EffectCatalog.Kind.WEAPON_PREFIX],
	["Unit prefix", EffectCatalog.Kind.UNIT_PREFIX],
]

## Between a carrier's effect lines in its Text cell.
const LINE_JOIN: String = " / "

## The Text cell of a carrier with no effect text.
const NO_TEXT: String = "*(no text)*"


func _initialize() -> void:
	var index: EffectCatalog.Index = EffectCatalog.load_tree(EffectCatalog.DATA_ROOT)
	for problem: String in index.problems:
		push_error("DumpEffectText: catalog problem - %s" % [problem])
	var text: String = tables(index)
	print(text)
	var exit_code: int = 0 if index.problems.is_empty() else 1
	var out_path: String = _out_path()
	if not out_path.is_empty():
		var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			push_error("DumpEffectText: can't write %s - %s" % [
				out_path, error_string(FileAccess.get_open_error()),
			])
			exit_code = 1
		else:
			file.store_string(text)
			file.close()
	print("--- %d carriers ---" % [count_carriers(index)])
	quit(exit_code)


## Every section's table for the carriers in [param index], as effect-text.md lays them out.
static func tables(index: EffectCatalog.Index) -> String:
	var parts: PackedStringArray = []
	for section: Array in SECTIONS:
		var heading: String = section[0]
		var kind: EffectCatalog.Kind = section[1]
		var rows: PackedStringArray = [
			"## %s" % [heading],
			"",
			"| Name | Id | Text now | New wording |",
			"|------|----|----------|-------------|",
		]
		for carrier: EffectCarrierDefinition in _carriers(index, kind):
			rows.append(row(carrier))
		parts.append("\n".join(rows))
	return "\n\n".join(parts) + "\n"


## One carrier's table row: its name, id and effect text, then an empty New wording cell.
static func row(carrier: EffectCarrierDefinition) -> String:
	var lines: PackedStringArray = carrier.describe()
	var shown: String = NO_TEXT if lines.is_empty() else LINE_JOIN.join(lines)
	return "| %s | `%s` | %s | |" % [
		_cell(carrier.display_name), carrier.id, _cell(shown),
	]


## How many carriers [method tables] lists, counting a staff or curse once per section it is in.
static func count_carriers(index: EffectCatalog.Index) -> int:
	var total: int = 0
	for section: Array in SECTIONS:
		var kind: EffectCatalog.Kind = section[1]
		total += _carriers(index, kind).size()
	return total


# The carriers of kind in index, by id.
static func _carriers(
		index: EffectCatalog.Index, kind: EffectCatalog.Kind
) -> Array[EffectCarrierDefinition]:
	var found: Array[EffectCarrierDefinition] = []
	for resource: Resource in index.all_of(kind):
		var carrier: EffectCarrierDefinition = resource as EffectCarrierDefinition
		if carrier != null:
			found.append(carrier)
	found.sort_custom(_is_id_before)
	return found


static func _is_id_before(a: EffectCarrierDefinition, b: EffectCarrierDefinition) -> bool:
	return a.id < b.id


# text with the table's own separators escaped.
static func _cell(text: String) -> String:
	return text.replace("|", "\\|").replace("\n", " ")


# The path after --out in the user arguments; empty for none.
func _out_path() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size() - 1:
		if args[i] == "--out":
			return args[i + 1]
	return ""
