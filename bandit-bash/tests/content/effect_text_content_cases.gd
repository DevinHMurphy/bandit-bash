# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_text_content_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

extends RefCounted
## The catalog's effect text against the grammar (effect-triggers.md, Reading effect text), for
## the content suite: Burglar's Roll's written text (heirlooms.md's sentence) with its charge
## kept, the Key's and Lockpick's; every carrier's lines as sentences, none saying "Always" or a
## value key's code name, every keyword ([constant EffectTerms.KEYWORDS]) in its own case; an
## ingredient's eat effect opening "When eaten" and no other consumable's; and
## tools/dump_effect_text.gd run headless, listing every carrier once per section.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "content"

const DumpEffectText = preload("res://tools/dump_effect_text.gd")

# Burglar's Roll's text: heirlooms.md's sentence, its scope in the text's plain words.
const BURGLAR_TEXT: String = (
		"Once per combat, one of your units can open a chest or door without a Key or Lockpick"
		+ " (still its action)."
)

const KEY_TEXT: String = "Open a chest or door."
const LOCKPICK_TEXT: String = "Open a chest or door. Lock pickers only."

# Keywords that are also plain words, so their lower case is allowed ("that attack", "a hit",
# "the darkness arrives").
const PLAIN_WORDS: PackedStringArray = [
	"Attack", "Hit", "Crit", "Range", "Magic", "Physical", "Darkness",
]

# Words that only a value key's code name puts in text ("Unit Xp Percent").
const CODE_NAME_WORDS: PackedStringArray = ["Percent", "Xp", "Level Up", "Stance Max", "Atk X"]

# The dump tool's script, run as its own headless process, and the file it writes its tables to
# in the suite's test user folder.
const DUMP_SCRIPT: String = "res://tools/dump_effect_text.gd"
const DUMP_OUT: String = "user://effect_text_dump.md"

# Needs the test user folder: the tool's tables are written there.
const NEEDS_TEST_USER_FOLDER: bool = true

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_openers()
	_test_grammar()
	_test_ingredients()
	_test_dump_tool()


# Burglar's Roll, the Key and the Lockpick have no operations, so their text is written.
func _test_openers() -> void:
	var burglar: HeirloomDefinition = _catalog.heirloom("burglars_roll")
	var lines: PackedStringArray = PackedStringArray() if burglar == null else burglar.describe()
	_same("burglar's roll: heirlooms.md's sentence", " | ".join(lines), BURGLAR_TEXT)
	var effect: EffectDefinition = null if burglar == null else burglar.effects[0]
	_ok("burglar's roll: still one charge per combat, read by its id", (
			effect != null and effect.charges == 1
			and effect.charge_lane == EffectTerms.Lane.COMBAT
			and effect.id == MapObjects.BURGLAR_EFFECT_ID
	))
	_same("key: its written text", " | ".join(_lines_of("key")), KEY_TEXT)
	_same("lockpick: its written text", " | ".join(_lines_of("lockpick")), LOCKPICK_TEXT)


# Every carrier's every line: a sentence, no "Always", no code name, keywords in their case.
func _test_grammar() -> void:
	var not_sentences: PackedStringArray = []
	var always: PackedStringArray = []
	var code_names: PackedStringArray = []
	var lower_keywords: PackedStringArray = []
	var checks: Array[RegEx] = []
	var checked_words: PackedStringArray = []
	for keyword: String in EffectTerms.KEYWORDS:
		if PLAIN_WORDS.has(keyword) or keyword == keyword.to_lower():
			continue
		checks.append(RegEx.create_from_string("\\b%s\\b" % [keyword.to_lower()]))
		checked_words.append(keyword)
	for carrier: EffectCarrierDefinition in _carriers():
		for line: String in carrier.describe():
			var where: String = "%s: %s" % [carrier.id, line]
			if not line.ends_with(".") or line.left(1) != line.left(1).to_upper():
				not_sentences.append(where)
			if line.contains("Always"):
				always.append(where)
			for word: String in CODE_NAME_WORDS:
				if line.contains(word):
					code_names.append(where)
			for i: int in checks.size():
				if checks[i].search(line) != null:
					lower_keywords.append("%s (%s)" % [where, checked_words[i]])
	_ok("grammar: every line is a sentence", not_sentences.is_empty(), "; ".join(not_sentences))
	_ok("grammar: no line says Always", always.is_empty(), "; ".join(always))
	_ok("grammar: no value key reads as its code name", code_names.is_empty(), (
			"; ".join(code_names)
	))
	_ok("grammar: keywords keep their case", lower_keywords.is_empty(), (
			"; ".join(lower_keywords)
	))


# Each ingredient's lines open "When eaten"; no other consumable's do.
func _test_ingredients() -> void:
	var wrong: PackedStringArray = []
	var ingredients: int = 0
	for resource: Resource in _catalog.all_of(EffectCatalog.Kind.CONSUMABLE):
		var consumable: ConsumableDefinition = resource as ConsumableDefinition
		if consumable == null:
			continue
		var is_ingredient: bool = consumable.use_kind == ConsumableDefinition.INGREDIENT_USE_KIND
		if is_ingredient:
			ingredients += 1
		for line: String in consumable.describe():
			if line.begins_with(ConsumableDefinition.EATEN_LEAD_IN + ", ") != is_ingredient:
				wrong.append("%s: %s" % [consumable.id, line])
	_ok("ingredients: their text opens When eaten, no other consumable's", (
			ingredients > 0 and wrong.is_empty()
	), "%d ingredients; %s" % [ingredients, "; ".join(wrong)])


# The tool run as effect-text.md is regenerated: headless, its tables naming every carrier of
# each section.
func _test_dump_tool() -> void:
	var output: Array = []
	var out_path: String = ProjectSettings.globalize_path(DUMP_OUT)
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", DUMP_SCRIPT,
		"--", "--out", out_path,
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var printed: String = "" if output.is_empty() else "\n".join(output)
	var expected: int = DumpEffectText.count_carriers(_catalog)
	_ok("dump tool: runs headless and exits 0", code == 0, "exit %d" % [code])
	_ok("dump tool: counts every carrier", (
			expected > 0 and printed.contains("--- %d carriers ---" % [expected])
	), "expected %d" % [expected])
	# Its file, not its piped output: a Windows pipe can mangle "×" and adds carriage returns.
	var text: String = FileAccess.get_file_as_string(out_path)
	DirAccess.remove_absolute(out_path)
	var missing: PackedStringArray = []
	for section: Array in DumpEffectText.SECTIONS:
		var kind: EffectCatalog.Kind = section[1]
		for resource: Resource in _catalog.all_of(kind):
			var carrier: EffectCarrierDefinition = resource as EffectCarrierDefinition
			if carrier != null and not text.contains(DumpEffectText.row(carrier)):
				missing.append(carrier.id)
	_ok("dump tool: one row per carrier, with its text", missing.is_empty(), ", ".join(missing))
	_ok("dump tool: every section heading", _has_headings(text))


func _has_headings(text: String) -> bool:
	for section: Array in DumpEffectText.SECTIONS:
		if not text.contains("## %s\n" % [section[0]]):
			return false
	return true


# Every effect carrier in the catalog, unit types and enemy classes included.
func _carriers() -> Array[EffectCarrierDefinition]:
	var found: Array[EffectCarrierDefinition] = []
	for id: String in _catalog.ids():
		var carrier: EffectCarrierDefinition = _catalog.definition(id) as EffectCarrierDefinition
		if carrier != null:
			found.append(carrier)
	return found


func _lines_of(item_id: String) -> PackedStringArray:
	var item: ItemDefinition = _catalog.item(item_id)
	return PackedStringArray() if item == null else item.describe()


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
