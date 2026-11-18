# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     value_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 18, 2026
# ==============================================================================

extends "res://tests/effects/effects_case_base.gd"
## Value query cases for tests/effects/run_all.gd ([Modifier], [ValueBreakdown], [StatSheet]):
## source order, modes, clamps, overrides, permissions, rounding, keys and caching.


func run() -> void:
	_test_value_source_order_never_changes_total()
	_test_value_replace_base_keeps_bonuses()
	_test_value_fixed_ignores_everything_and_names_it()
	_test_value_rule_clamps_after_fixed()
	_test_value_highest_floor_lowest_cap()
	_test_value_override_precedence_and_warning()
	_test_value_skips_modifiers_that_cannot_apply()
	_test_permissions_denial_beats_grant()
	_test_rounding_per_key()
	_test_rounding_tolerance_at_half()
	_test_value_keys_seeded_and_disjoint()
	_test_stat_sheet_caches_and_invalidates()


# Every insertion order of the same sources gives the same total, text and warnings, exactly.
func _test_value_source_order_never_changes_total() -> void:
	var hit: int = CombatValue.Key.HIT
	var sources: Array[Modifier] = [
		_mod(hit, REPLACE_BASE, 80.0, WEAPON, "item:3", "Scope"),
		_mod(hit, REPLACE_BASE, 75.0, HEIRLOOM, "h:1", "Eye"),
		_mod(hit, ADD, 15.0, UNIT_TRAIT, "unit:2", "Momentum"),
		_mod(hit, ADD, -5.0, CURSE, "h:4", "Fog"),
		_mod(hit, ADD, 2.5, EQUIPMENT, "item:6", "Lens"),
		_mod(hit, MULTIPLY, 0.5, CURSE, "h:7", "Blind"),
		_mod(hit, MULTIPLY, 1.2, HEIRLOOM, "h:8", "Focus"),
		_mod(hit, MULTIPLY, 0.75, WEAPON, "item:9", "Heavy"),
		_mod(hit, FLOOR, 10.0, HEIRLOOM, "h:10", "Steady"),
		_mod(hit, CAP, 95.0, UNIT_TRAIT, "unit:2", "Wild"),
	]
	var reference: ValueBreakdown = ValueBreakdown.compute(hit, 70.0, "", sources)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var mismatches: int = 0
	for round_index: int in 50:
		var shuffled: Array[Modifier] = sources.duplicate()
		for i: int in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap: Modifier = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = swap
		var result: ValueBreakdown = ValueBreakdown.compute(hit, 70.0, "", shuffled)
		if (
				result.total != reference.total
				or result.to_text() != reference.to_text()
				or result.warnings != reference.warnings
		):
			mismatches += 1
	_check("value order: 50 shuffles give the same answer", mismatches == 0, str(mismatches))
	_check(
			"value order: expected total",
			is_equal_approx(reference.total, (80.0 + 15.0 - 5.0 + 2.5) * 0.5 * 1.2 * 0.75),
			str(reference.total)
	)


func _test_value_replace_base_keeps_bonuses() -> void:
	var scrap: int = CampaignValue.Key.SCRAP_PERCENT
	var modifiers: Array[Modifier] = [
		_mod(scrap, ADD, 20.0, HEIRLOOM, "h:1", "Scrapper's Tongs"),
		_mod(scrap, REPLACE_BASE, 10.0, HEIRLOOM, "h:2", "Haggler"),
	]
	var result: ValueBreakdown = ValueBreakdown.compute(scrap, 20.0, "Scrapping", modifiers)
	_check("replace base: keeps the bonus (10 + 20)", result.total == 30.0, str(result.total))
	_check(
			"replace base: text",
			result.to_text() == "10 Haggler (instead of 20) +20 Scrapper's Tongs = 30",
			result.to_text()
	)
	_check("replace base: base line kept, not applied", not result.lines[0].applied)


func _test_value_fixed_ignores_everything_and_names_it() -> void:
	var scrap: int = CampaignValue.Key.SCRAP_PERCENT
	var modifiers: Array[Modifier] = [
		_mod(scrap, ADD, 20.0, HEIRLOOM, "h:1", "Scrapper's Tongs"),
		_mod(scrap, FLOOR, 60.0, HEIRLOOM, "h:2", "Guild Rate"),
		_mod(scrap, FIXED, 50.0, CURSE, "h:3", "Bad Deal"),
	]
	var result: ValueBreakdown = ValueBreakdown.compute(scrap, 20.0, "Scrapping", modifiers)
	_check("fixed: ignores bonuses and floors", result.total == 50.0, str(result.total))
	_check(
			"fixed: text names what it overrode",
			result.to_text() == (
					"50 fixed by Bad Deal (ignoring 20 Scrapping, +20 Scrapper's Tongs,"
					+ " at least 60 Guild Rate) = 50"
			),
			result.to_text()
	)
	var all_ignored: bool = true
	for line: ValueBreakdown.Line in result.lines:
		if line.modifier != null and line.modifier.label == "Scrapper's Tongs":
			all_ignored = not line.applied and line.note.contains("Bad Deal")
	_check("fixed: overridden lines say why", all_ignored)


func _test_value_rule_clamps_after_fixed() -> void:
	var army: int = CampaignValue.Key.MAX_ARMY_SIZE
	var fixed: Array[Modifier] = [
		_mod(army, FIXED, 10.0, HEIRLOOM, "h:1", "Big Tent"),
	]
	var fixed_result: ValueBreakdown = ValueBreakdown.compute(army, 6.0, "", fixed)
	_check(
			"rule clamp: still applies after fixed",
			fixed_result.total == 8.0,
			str(fixed_result.total)
	)
	_check(
			"rule clamp: shown as a rule",
			fixed_result.to_text().ends_with("at most 8 (rule) = 8"),
			fixed_result.to_text()
	)

	var added: Array[Modifier] = [
		_mod(army, ADD, 5.0, HEIRLOOM, "h:2", "Muster Roll"),
	]
	_check("rule clamp: caps additions", ValueBreakdown.compute(army, 6.0, "", added).total == 8.0)
	_check("rule clamp: no effect below it", ValueBreakdown.compute(army, 6.0, "", []).total == 6.0)


func _test_value_highest_floor_lowest_cap() -> void:
	var hit: int = CombatValue.Key.HIT
	var floors: Array[Modifier] = [
		_mod(hit, FLOOR, 60.0, HEIRLOOM, "h:1", "Low"),
		_mod(hit, FLOOR, 70.0, HEIRLOOM, "h:2", "High"),
	]
	var floored: ValueBreakdown = ValueBreakdown.compute(hit, 50.0, "", floors)
	_check("floor: the highest applies", floored.total == 70.0, str(floored.total))
	_check(
			"floor: the lower is listed, not applied",
			floored.to_text() == "50 base at least 70 High = 70",
			floored.to_text()
	)

	var caps: Array[Modifier] = [
		_mod(hit, CAP, 90.0, HEIRLOOM, "h:3", "Loose"),
		_mod(hit, CAP, 80.0, HEIRLOOM, "h:4", "Tight"),
	]
	_check("cap: the lowest applies", ValueBreakdown.compute(hit, 100.0, "", caps).total == 80.0)
	var unreached: ValueBreakdown = ValueBreakdown.compute(hit, 50.0, "", caps)
	_check("cap: an unreached cap changes nothing", unreached.total == 50.0, unreached.to_text())

	var both: Array[Modifier] = floors + caps
	both.append(_mod(hit, CAP, 65.0, HEIRLOOM, "h:5", "Clamp"))
	var bounded: ValueBreakdown = ValueBreakdown.compute(hit, 50.0, "", both)
	_check("floor and cap: floor first, then cap", bounded.total == 65.0, bounded.to_text())


func _test_value_override_precedence_and_warning() -> void:
	var range_max: int = CombatValue.Key.RANGE_MAX
	var collision: Array[Modifier] = [
		_mod(range_max, REPLACE_BASE, 4.0, HEIRLOOM, "h:2", "Far Sight"),
		_mod(range_max, REPLACE_BASE, 2.0, WEAPON, "item:9", "Short Quiver"),
		_mod(range_max, REPLACE_BASE, 5.0, UNIT_TRAIT, "unit:1", "Keen"),
	]
	var result: ValueBreakdown = ValueBreakdown.compute(range_max, 3.0, "", collision)
	_check("override: the unit's own item wins", result.total == 2.0, str(result.total))
	_check(
			"override: one warning per losing value",
			result.warnings.size() == 2 and result.warnings[0].contains("Short Quiver"),
			str(result.warnings)
	)
	var losers: int = 0
	for line: ValueBreakdown.Line in result.lines:
		if not line.applied and line.note.begins_with("lost to Short Quiver"):
			losers += 1
	_check("override: losers listed with the winner's name", losers == 2)

	var tie: Array[Modifier] = [
		_mod(range_max, FIXED, 3.0, WEAPON, "item:5", "A"),
		_mod(range_max, FIXED, 6.0, EQUIPMENT, "item:12", "B"),
	]
	_check(
			"override: equal specificity, lowest source id wins",
			ValueBreakdown.compute(range_max, 3.0, "", tie).total == 6.0
	)

	var copies: Array[Modifier] = [
		_mod(range_max, REPLACE_BASE, 2.0, WEAPON, "item:9", "Quiver"),
		_mod(range_max, REPLACE_BASE, 2.0, WEAPON, "item:8", "Quiver"),
	]
	var copied: ValueBreakdown = ValueBreakdown.compute(range_max, 3.0, "", copies)
	_check(
			"override: copies don't stack and don't warn",
			copied.total == 2.0 and copied.warnings.is_empty(),
			str(copied.warnings)
	)


func _test_value_skips_modifiers_that_cannot_apply() -> void:
	var damage_type: int = CombatValue.Key.DAMAGE_TYPE
	var physical: float = CombatFact.DamageType.PHYSICAL
	var magic: float = CombatFact.DamageType.MAGIC
	var modifiers: Array[Modifier] = [
		_mod(damage_type, ADD, 1.0, WEAPON, "item:1", "Odd"),
		_mod(damage_type, REPLACE_BASE, magic, WEAPON, "item:2", "Spirit Coating"),
		_mod(CombatValue.Key.HIT, ADD, 10.0, WEAPON, "item:3", "Elsewhere"),
		_mod(damage_type, GRANT, 0.0, WEAPON, "item:4", "Permission"),
	]
	var result: ValueBreakdown = ValueBreakdown.compute(damage_type, physical, "", modifiers)
	_check("enum key: replace base applies", result.get_int() == CombatFact.DamageType.MAGIC)
	_check(
			"enum key: add, wrong key and permission skipped with warnings",
			result.warnings.size() == 3,
			str(result.warnings)
	)


func _test_permissions_denial_beats_grant() -> void:
	var counter: int = CombatValue.Permission.CAN_COUNTER
	var by_default: ValueBreakdown = ValueBreakdown.compute_permission(counter, [])
	_check("permission: CAN_COUNTER allowed by default", by_default.is_allowed())

	var staff: Array[Modifier] = [
		_mod(counter, GRANT, 0.0, UNIT_TRAIT, "unit:1", "Riposte"),
		_mod(counter, DENY, 0.0, WEAPON, "item:2", "Mend Staff"),
	]
	var denied: ValueBreakdown = ValueBreakdown.compute_permission(counter, staff)
	_check("permission: denial beats grant", not denied.is_allowed())
	var denied_text: String = denied.to_text()
	_check("permission: text", denied_text == "denied by Mend Staff = denied", denied_text)
	var grant_line: ValueBreakdown.Line = denied.lines[1]
	_check(
			"permission: the grant is listed and overruled",
			not grant_line.applied and grant_line.note == "denial beats grant"
	)

	var may_move: int = CombatValue.Permission.MAY_MOVE_AFTER_ACTING
	var skirmisher: Array[Modifier] = [
		_mod(may_move, GRANT, 0.0, UNIT_TRAIT, "unit:3", "Skirmisher"),
	]
	_check(
			"permission: off by default, a grant turns it on",
			not ValueBreakdown.compute_permission(may_move, []).is_allowed()
			and ValueBreakdown.compute_permission(may_move, skirmisher).is_allowed()
	)

	var shovable: int = CombatValue.Permission.CAN_BE_SHOVED
	var boss: Array[Modifier] = [
		_mod(shovable, DENY, 0.0, UNIT_TRAIT, "enemy:1", "Unshovable"),
		_mod(shovable, GRANT, 0.0, HEIRLOOM, "h:9", "Battering Ram"),
	]
	var boss_answer: ValueBreakdown = ValueBreakdown.compute_permission(shovable, boss)
	_check(
			"permission: CAN_BE_SHOVED allowed by default",
			ValueBreakdown.compute_permission(shovable, []).is_allowed()
	)
	_check(
			"permission: a grant can't cancel Unshovable's denial",
			not boss_answer.is_allowed()
			and boss_answer.to_text() == "denied by Unshovable = denied",
			boss_answer.to_text()
	)

	var grow: int = CampaignValue.Permission.STAT_CAN_GROW
	var weights: Array[Modifier] = [
		_mod(grow, DENY, 0.0, EQUIPMENT, "item:7", "Training Weights"),
	]
	_check(
			"permission: STAT_CAN_GROW allowed by default, denied by Training Weights",
			ValueBreakdown.compute_permission(grow, []).is_allowed()
			and not ValueBreakdown.compute_permission(grow, weights).is_allowed()
	)
	var value_mode: Array[Modifier] = [
		_mod(grow, ADD, 1.0, EQUIPMENT, "item:7", "Wrong"),
	]
	var skipped: ValueBreakdown = ValueBreakdown.compute_permission(grow, value_mode)
	_check(
			"permission: value modes skipped with a warning",
			skipped.is_allowed() and skipped.warnings.size() == 1
	)


func _test_rounding_per_key() -> void:
	var halve_hit: Array[Modifier] = [
		_mod(CombatValue.Key.HIT, MULTIPLY, 0.5, CURSE, "h:1", "Half"),
	]
	var hit: ValueBreakdown = ValueBreakdown.compute(CombatValue.Key.HIT, 3.0, "", halve_hit)
	_check("rounding: get_value stays exact (3 halved is 1.5)", hit.total == 1.5, str(hit.total))
	_check("rounding: HALF_UP key rounds 1.5 to 2", hit.get_int() == 2, str(hit.get_int()))

	var multipliers: int = DamageStage.Key.MULTIPLIERS
	var halve_stage: Array[Modifier] = [
		_mod(multipliers, MULTIPLY, 0.5, CURSE, "h:1", "Half"),
	]
	var stage: ValueBreakdown = ValueBreakdown.compute(multipliers, 3.0, "", halve_stage)
	_check(
			"rounding: DamageStage keys are EXACT and untouched",
			stage.rounding == ValueBreakdown.Rounding.EXACT and stage.total == 1.5
	)
	_check(
			"rounding: FLOOR rounds 1.5 to 1",
			ValueBreakdown.round_to_int(1.5, ValueBreakdown.Rounding.FLOOR) == 1
	)
	_check(
			"rounding: HALF_UP rounds -2.5 to -2",
			ValueBreakdown.round_to_int(-2.5, ValueBreakdown.Rounding.HALF_UP) == -2
	)


func _test_rounding_tolerance_at_half() -> void:
	var hit: int = CombatValue.Key.HIT
	var times_1_1: Array[Modifier] = [
		_mod(hit, MULTIPLY, 1.1, HEIRLOOM, "h:1", "Sharp"),
	]
	var five: ValueBreakdown = ValueBreakdown.compute(hit, 5.0, "", times_1_1)
	_check("tolerance: 5 × 1.1 rounds to 6", five.get_int() == 6, str(five.total))

	var times_0_145: Array[Modifier] = [
		_mod(hit, MULTIPLY, 0.145, HEIRLOOM, "h:1", "Sharp"),
	]
	var below_half: ValueBreakdown = ValueBreakdown.compute(hit, 100.0, "", times_0_145)
	_check(
			"tolerance: 100 × 0.145 lands just below 14.5 in floats",
			below_half.total < 14.5,
			str(below_half.total)
	)
	_check("tolerance: and still rounds to 15", below_half.get_int() == 15)
	var almost_29: float = 0.29 * 100.0
	_check("tolerance: 0.29 × 100 lands just below 29 in floats", almost_29 < 29.0, str(almost_29))
	_check(
			"tolerance: and FLOOR still gives 29",
			ValueBreakdown.round_to_int(almost_29, ValueBreakdown.Rounding.FLOOR) == 29
	)


func _test_value_keys_seeded_and_disjoint() -> void:
	var expected_combat: PackedStringArray = [
		"ATTACK_SPEED", "NET_WEIGHT", "ATK_X", "PARRY", "HIT", "AVOID", "CRIT_CHANCE", "CRIT_X",
		"STANCE_MAX", "SHOVE_DISTANCE", "RANGE_MIN", "RANGE_MAX", "DAMAGE_TYPE",
		"EFFECTIVE_MODIFIER", "STAFF_AMOUNT", "MOVEMENT", "HP", "MGT", "SPD", "DEF", "RES", "CON",
	]
	var expected_permissions: PackedStringArray = [
		"CAN_COUNTER", "CAN_BE_SHOVED", "MAY_MOVE_AFTER_ACTING", "FREE_WEAPON_SWAP",
		"SKIP_MITIGATION_ON_CRIT", "CAN_PICK_LOCKS", "CAN_GAIN_BLOCK", "CAN_LOOT", "HEX_STORM",
	]
	var expected_stages: PackedStringArray = [
		"ATTACK", "MITIGATION", "CRITICAL", "MULTIPLIERS", "INCOMING_MULTIPLIERS",
	]
	_check(
			"keys: combat core's CombatValue keys and the base stats seeded",
			_has_keys(CombatValue.Key, expected_combat)
	)
	_check(
			"keys: combat core's permissions seeded",
			_has_keys(CombatValue.Permission, expected_permissions)
	)
	_check("keys: DamageStage keys seeded", _has_keys(DamageStage.Key, expected_stages))
	_check(
			"keys: POUCH_ITEM_WEIGHT on the campaign list",
			CampaignValue.Key.has("POUCH_ITEM_WEIGHT")
	)

	var blocks: Dictionary[int, Dictionary] = {
		0: CombatValue.Key,
		1000: DamageStage.Key,
		2000: CampaignValue.Key,
		3000: CombatValue.Permission,
		4000: CampaignValue.Permission,
	}
	var seen: Dictionary[int, bool] = {}
	var problems: PackedStringArray = []
	for block_start: int in blocks:
		var keys: Dictionary = blocks[block_start]
		for key_name: String in keys:
			var value: int = keys[key_name]
			if value < block_start or value >= block_start + 1000:
				problems.append("%s outside its block" % [key_name])
			if seen.has(value):
				problems.append("%s reuses %d" % [key_name, value])
			seen[value] = true
	_check(
			"keys: every key unique and in its class's block",
			problems.is_empty(),
			", ".join(problems)
	)

	var stage_rounding: bool = true
	for key_name: String in DamageStage.Key:
		var stage_key: int = DamageStage.Key[key_name]
		var rule: int = DamageStage.ROUNDING.get(stage_key, -1)
		stage_rounding = stage_rounding and rule == ValueBreakdown.Rounding.EXACT
	_check("keys: every DamageStage key is EXACT", stage_rounding)
	var defaults_complete: bool = (
			CombatValue.PERMISSION_DEFAULTS.size() == CombatValue.Permission.size()
			and CampaignValue.PERMISSION_DEFAULTS.size() == CampaignValue.Permission.size()
	)
	_check("keys: every permission has a default", defaults_complete)


func _test_stat_sheet_caches_and_invalidates() -> void:
	var sheet: StatSheet = StatSheet.new("unit:57")
	var hit: int = CombatValue.Key.HIT
	sheet.set_base(hit, 70.0, "Iron Axe")
	var first: ValueBreakdown = sheet.explain(hit)
	_check(
			"sheet: base value",
			sheet.get_value(hit) == 70.0 and first.to_text() == "70 Iron Axe = 70",
			first.to_text()
	)
	_check("sheet: answers are cached", sheet.explain(hit) == first)

	sheet.add_modifier(_mod(hit, ADD, 15.0, UNIT_TRAIT, "unit:57", "Keen"))
	_check(
			"sheet: a new modifier recomputes",
			sheet.explain(hit) != first and sheet.get_int(hit) == 85
	)
	sheet.set_base(hit, 60.0)
	_check("sheet: a new base recomputes", sheet.get_value(hit) == 75.0)
	_check("sheet: unset keys start at 0", sheet.get_value(CombatValue.Key.AVOID) == 0.0)

	var counter: int = CombatValue.Permission.CAN_COUNTER
	_check("sheet: permission default", sheet.is_allowed(counter))
	sheet.add_modifier(_mod(counter, DENY, 0.0, WEAPON, "item:1", "Staff"))
	_check("sheet: permission recomputed after a denial", not sheet.is_allowed(counter))

	var copy: Array[Modifier] = sheet.get_modifiers(hit)
	copy.clear()
	_check("sheet: get_modifiers returns a copy", sheet.get_modifiers(hit).size() == 1)


func _has_keys(keys: Dictionary, names: PackedStringArray) -> bool:
	for key_name: String in names:
		if not keys.has(key_name):
			return false
	return keys.size() == names.size()


func _mod(
		key: int,
		mode: Modifier.Mode,
		value: float,
		kind: Modifier.SourceKind,
		source_id: String,
		label: String
) -> Modifier:
	return Modifier.new(key, mode, value, kind, source_id, label)
