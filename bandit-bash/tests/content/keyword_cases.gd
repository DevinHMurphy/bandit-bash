# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     keyword_cases.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

extends RefCounted
## Keyword markup and the glossary (docs/design/keywords.md), for the content suite: every
## catalog carrier's marked text parses, its tags balanced and naming only known ids, with no
## keyword left unmarked, and reads as its plain text; the tag helpers on hand-made text; one
## [constant EffectTerms.KEYWORD_IDS] id per keyword; and the glossary holding one entry per id,
## each with a name, a colour group and an explanation, and nothing besides.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "content"

# How each keyword is found unmarked in a plain stretch of text: its spelling as a whole word,
# case kept; the lower-case terms and the darkness in any case, and heal's other forms too.
const LOOSE_PATTERNS: Dictionary[String, String] = {
	"damage": "\\b[Dd]amage\\b",
	"heal": "\\b[Hh]eal(s|ed|ing)?\\b",
	"Darkness": "\\b[Dd]arkness\\b",
}

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_helpers()
	_test_ids()
	_test_catalog_markup()
	_test_glossary()


# mark, plain_text, split_marked, markup_problems and sentence on text made here.
func _test_helpers() -> void:
	var marked: String = "gain 2 %s and %s" % [
		EffectTerms.mark("Block"), EffectTerms.mark("heal", "heals"),
	]
	_ok("helpers: mark tags a keyword by its id, showing the word given", (
			marked == "gain 2 [kw=block]Block[/kw] and [kw=heal]heals[/kw]"
	), marked)
	_ok("helpers: plain_text keeps the words alone", (
			EffectTerms.plain_text(marked) == "gain 2 Block and heals"
	), EffectTerms.plain_text(marked))
	var pieces: Array[PackedStringArray] = EffectTerms.split_marked(marked)
	_ok("helpers: split_marked gives plain and keyword pieces in order", (
			pieces.size() == 4 and pieces[1] == PackedStringArray(["block", "Block"])
			and pieces[2] == PackedStringArray(["", " and "]) and pieces[3][0] == "heal"
	), str(pieces))
	_ok("helpers: mark_if_keyword leaves a word that isn't one", (
			EffectTerms.mark_if_keyword("MOV") == "MOV"
			and EffectTerms.mark_if_keyword("SPD") == "[kw=spd]SPD[/kw]"
	))
	_ok("helpers: a sentence opening with a tag capitalizes its word", (
			EffectTerms.sentence("[kw=heal]heal[/kw] an ally")
			== "[kw=heal]Heal[/kw] an ally."
	), EffectTerms.sentence("[kw=heal]heal[/kw] an ally"))
	var bad: Dictionary[String, String] = {
		"unknown id": "gain 2 [kw=shield]Block[/kw]",
		"unclosed": "gain 2 [kw=block]Block",
		"stray close": "gain 2 Block[/kw]",
		"nested": "[kw=block]a [kw=hp]HP[/kw][/kw]",
		"empty word": "gain [kw=block][/kw]",
		"no id": "gain [kw=]Block[/kw]",
	}
	var missed: PackedStringArray = []
	for name: String in bad:
		if EffectTerms.markup_problems(bad[name]).is_empty():
			missed.append(name)
	_ok("helpers: markup_problems reports each broken tag", missed.is_empty(), ", ".join(missed))
	_ok("helpers: markup_problems passes good text", EffectTerms.markup_problems(marked).is_empty())


# One id per keyword, snake_case and unique.
func _test_ids() -> void:
	var wrong: PackedStringArray = []
	var seen: PackedStringArray = []
	var snake: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	for keyword: String in EffectTerms.KEYWORDS:
		var id: String = EffectTerms.KEYWORD_IDS.get(keyword, "")
		if id.is_empty() or snake.search(id) == null or seen.has(id):
			wrong.append("%s (%s)" % [keyword, id])
		seen.append(id)
	_ok("ids: every keyword has its own snake_case id, and only keywords do", (
			wrong.is_empty() and EffectTerms.KEYWORD_IDS.size() == EffectTerms.KEYWORDS.size()
	), "; ".join(wrong))


# Every carrier's every marked line: well-formed, no keyword unmarked, the plain line its words.
func _test_catalog_markup() -> void:
	var broken: PackedStringArray = []
	var unmarked: PackedStringArray = []
	var different: PackedStringArray = []
	var checks: Dictionary[String, RegEx] = {}
	for keyword: String in EffectTerms.KEYWORDS:
		var pattern: String = LOOSE_PATTERNS.get(keyword, "\\b%s\\b" % [keyword])
		checks[keyword] = RegEx.create_from_string(pattern)
	var lines: int = 0
	var tags: int = 0
	for carrier: EffectCarrierDefinition in _carriers():
		var marked: PackedStringArray = carrier.describe_marked()
		var plain: PackedStringArray = carrier.describe()
		if marked.size() != plain.size():
			different.append(carrier.id)
		for i: int in marked.size():
			lines += 1
			var line: String = marked[i]
			var where: String = "%s: %s" % [carrier.id, line]
			for problem: String in EffectTerms.markup_problems(line):
				broken.append("%s (%s)" % [where, problem])
			if i < plain.size() and EffectTerms.plain_text(line) != plain[i]:
				different.append(where)
			var outside: PackedStringArray = []
			for piece: PackedStringArray in EffectTerms.split_marked(line):
				if piece[0].is_empty():
					outside.append(piece[1])
				else:
					tags += 1
			var rest: String = " | ".join(outside)
			for keyword: String in checks:
				if checks[keyword].search(rest) != null:
					unmarked.append("%s (%s)" % [where, keyword])
	_ok("catalog markup: every line's tags are balanced and name known ids", (
			lines > 0 and broken.is_empty()
	), "%d lines; %s" % [lines, "; ".join(broken)])
	_ok("catalog markup: no keyword is left unmarked", unmarked.is_empty(), "; ".join(unmarked))
	_ok("catalog markup: each plain line is its marked line's words", (
			different.is_empty() and tags > 0
	), "; ".join(different))


# One entry per id, each complete, and none for anything else.
func _test_glossary() -> void:
	var glossary: KeywordGlossary = KeywordGlossary.shared()
	if glossary == null:
		_ok("glossary: loads from %s" % [KeywordGlossary.PATH], false)
		return
	var missing: PackedStringArray = []
	var incomplete: PackedStringArray = []
	for keyword: String in EffectTerms.KEYWORDS:
		var id: String = EffectTerms.KEYWORD_IDS.get(keyword, "")
		var entry: KeywordEntry = glossary.entry(id)
		if entry == null:
			missing.append(id)
			continue
		if (
				entry.display_name.is_empty() or entry.explanation.strip_edges().is_empty()
				or not KeywordEntry.ColourGroup.values().has(entry.colour_group)
				or entry.display_name.to_lower() != keyword.to_lower()
		):
			incomplete.append(id)
	var extra: PackedStringArray = []
	var ids: Array[String] = EffectTerms.KEYWORD_IDS.values()
	for entry: KeywordEntry in glossary.entries:
		if entry == null or not ids.has(entry.id):
			extra.append("null" if entry == null else entry.id)
	_ok("glossary: an entry for every keyword id", missing.is_empty(), ", ".join(missing))
	_ok("glossary: each entry has its keyword's name, a colour group and an explanation", (
			incomplete.is_empty()
	), ", ".join(incomplete))
	_ok("glossary: no entry for anything else, none twice", (
			extra.is_empty() and glossary.entries.size() == EffectTerms.KEYWORDS.size()
	), ", ".join(extra))


# Every effect carrier in the catalog, unit types and enemy classes included.
func _carriers() -> Array[EffectCarrierDefinition]:
	var found: Array[EffectCarrierDefinition] = []
	for id: String in _catalog.ids():
		var carrier: EffectCarrierDefinition = _catalog.definition(id) as EffectCarrierDefinition
		if carrier != null:
			found.append(carrier)
	return found


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
