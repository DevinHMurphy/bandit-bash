# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effects_case_base.gd
# Author:
# Created:  November 9, 2026
# Modified: November 21, 2026
# ==============================================================================

extends RefCounted
## Shared by the case files split from the effects suite's runner: reporting through its check,
## and the values and helpers more than one of them uses.

# Short names for the modifier modes and source kinds, to keep the value cases readable.
const REPLACE_BASE: Modifier.Mode = Modifier.Mode.REPLACE_BASE
const ADD: Modifier.Mode = Modifier.Mode.ADD
const MULTIPLY: Modifier.Mode = Modifier.Mode.MULTIPLY
const FLOOR: Modifier.Mode = Modifier.Mode.FLOOR
const CAP: Modifier.Mode = Modifier.Mode.CAP
const FIXED: Modifier.Mode = Modifier.Mode.FIXED
const GRANT: Modifier.Mode = Modifier.Mode.GRANT
const DENY: Modifier.Mode = Modifier.Mode.DENY
const UNIT_TRAIT: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT
const WEAPON: Modifier.SourceKind = Modifier.SourceKind.WEAPON
const EQUIPMENT: Modifier.SourceKind = Modifier.SourceKind.EQUIPMENT
const HEIRLOOM: Modifier.SourceKind = Modifier.SourceKind.HEIRLOOM
const CURSE: Modifier.SourceKind = Modifier.SourceKind.CURSE

# Display names the fake describe uses, standing in for a session's describe.
const NAMES: Dictionary[String, String] = {
	"unit:57": "Hakkapel",
	"enemy:61": "Brute",
	"item:412": "Iron Axe",
}

var _report: Callable


func _init(check: Callable) -> void:
	_report = check


# Compares the words alone: blocks and EffectTerms return keyword-tagged text, which the markup
# cases check on their own; a snapshot holds that the words shown never change.
func _snapshot(case_name: String, actual: String, expected: String) -> void:
	var words: String = EffectTerms.plain_text(actual)
	_check("describe %s" % [case_name], words == expected, actual)


# Stands in for a session's describe: "unit:57" -> "unit:57 (Hakkapel)".
func _describe(id: String) -> String:
	return "%s (%s)" % [id, NAMES[id]] if NAMES.has(id) else id


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
