# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 18, 2026
# ==============================================================================

extends "res://tests/effects/effects_case_base.gd"
## Fact cases for tests/effects/run_all.gd ([CombatFact], [CampaignFact]): wire round trips and
## refused data, amendments, item ids, fact keys and log lines.

# The documented example line (event bus plan, Logging and debugging), without NetLog's prefix.
const DOCUMENTED_HIT_LINE: String = (
		"s0#143 HIT_TAKEN unit:57 (Hakkapel) <- enemy:61 (Brute) amount 6 (hp 4, block 2)"
		+ " source attack"
)


func run() -> void:
	_test_combat_wire_round_trip()
	_test_combat_wire_through_json()
	_test_combat_wire_rejects_bad_data()
	_test_combat_fact_amendments()
	_test_combat_fact_item_id()
	_test_combat_fact_key()
	_test_campaign_wire_round_trip()
	_test_campaign_wire_rejects_bad_data()
	_test_combat_log_line_documented_shape()
	_test_combat_log_line_optional_parts()
	_test_campaign_log_line()


func _test_combat_wire_round_trip() -> void:
	var fact: CombatFact = _full_combat_fact()
	var back: CombatFact = CombatFact.from_wire(fact.to_wire())
	_check("combat wire: round trip returns a fact", back != null)
	if back == null:
		return
	_check("combat wire: every field kept", back.to_wire() == fact.to_wire(), str(back.to_wire()))
	_check(
			"combat wire: typed fields",
			back.kind == CombatFact.Kind.DAMAGE_TAKEN and back.tile == Vector2i(4, 7)
			and back.damage_type == CombatFact.DamageType.SPLIT
			and back.source == CombatFact.Source.SPLASH
	)

	var blank: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	var empty: CombatFact = CombatFact.from_wire(blank.to_wire())
	_check(
			"combat wire: defaults kept",
			empty != null and empty.tile == CombatFact.NO_TILE and empty.actor_id.is_empty()
	)


func _test_combat_wire_through_json() -> void:
	var fact: CombatFact = _full_combat_fact()
	fact.seq = 9007199254740991
	var parsed: Variant = JSON.parse_string(JSON.stringify(fact.to_wire()))
	var parsed_array: Array = parsed if typeof(parsed) == TYPE_ARRAY else []
	var back: CombatFact = CombatFact.from_wire(parsed_array)
	_check("combat json: numbers arrive as floats", typeof(parsed_array[0]) == TYPE_FLOAT)
	_check(
			"combat json: round trip equal",
			back != null and back.to_wire() == fact.to_wire(),
			"" if back == null else str(back.to_wire())
	)


func _test_combat_wire_rejects_bad_data() -> void:
	var good: Array = _full_combat_fact().to_wire()
	var cases: Dictionary[String, Array] = {
		"too short": good.slice(0, good.size() - 1),
		"too long": good + [0],
		"string in an int slot": _with(good, 5, "6"),
		"int in a string slot": _with(good, 3, 57),
		"fractional number": _with(good, 5, 6.5),
		"number beyond 2^53": _with(good, 1, 1.0e17),
		"unknown kind": _with(good, 0, 9999),
		"unknown damage type": _with(good, 8, 99),
		"unknown source": _with(good, 9, 99),
		"negative seq": _with(good, 1, -1),
		"negative session": _with(good, 2, -1),
		"unknown side": _with(good, 14, 9),
		"int in the item id slot": _with(good, 15, 412),
		"string in the key slot": _with(good, 16, "1"),
		"int in the unit types slot": _with(good, 17, 2),
		"int among the unit types": _with(good, 17, ["Bandit", 2]),
		"null slot": _with(good, 13, null),
	}
	for case_name: String in cases:
		_check(
				"combat wire bad data: %s refused" % [case_name],
				CombatFact.from_wire(cases[case_name]) == null
		)


# The combat core's appended fields, kinds and source (combat core plan, CC1).
func _test_combat_fact_amendments() -> void:
	var phase: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	phase.seq = 1
	phase.side = CombatFact.CombatSide.ENEMY
	phase.amount = 3
	var wire: Array = phase.to_wire()
	_check(
			"amendments: side in slot 14, item id appended after it",
			(
					wire.size() == 18 and wire[14] == CombatFact.CombatSide.ENEMY
					and wire[15] == ""
			) as bool,
			str(wire)
	)
	var back: CombatFact = CombatFact.from_wire(wire)
	_check(
			"amendments: side and turn survive the wire",
			back != null and back.side == CombatFact.CombatSide.ENEMY and back.amount == 3
	)
	var parsed: Variant = JSON.parse_string(JSON.stringify(wire))
	var through_json: CombatFact = CombatFact.from_wire(
			(parsed as Array) if parsed is Array else []
	)
	_check(
			"amendments: side survives JSON",
			through_json != null and through_json.side == CombatFact.CombatSide.ENEMY
	)
	_check(
			"amendments: phase log line shows side and turn",
			phase.to_log_line() == "s0#1 PHASE_START side enemy amount 3",
			phase.to_log_line()
	)
	_check(
			"amendments: other kinds default to no side",
			CombatFact.new(CombatFact.Kind.UNIT_MOVED).side == CombatFact.CombatSide.NONE
	)

	var spiked: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_TAKEN, "unit:57")
	spiked.amount = 4
	spiked.hp_amount = 4
	spiked.source = CombatFact.Source.SPIKE
	var spiked_line: String = spiked.to_log_line()
	_check(
			"amendments: spike source",
			spiked_line == "s0#0 DAMAGE_TAKEN unit:57 amount 4 (hp 4, block 0) source spike"
			and CombatFact.Source.SPIKE == 6,
			spiked_line
	)

	var appended: Dictionary[String, int] = {
		"BLOCK_STANCE_REFRESHED": 35,
		"STANCE_CHANGED": 36,
		"ITEM_USED": 37,
		"WEAPON_SWAPPED": 38,
		"RUNE_USED": 39,
		"UNIT_WAITED": 40,
		"BLOCK_LOST": 41,
	}
	var wrong: PackedStringArray = []
	for kind_name: String in appended:
		if CombatFact.Kind.get(kind_name, -1) != appended[kind_name]:
			wrong.append(kind_name)
	_check("amendments: seven kinds appended after the old ones", wrong.is_empty(), str(wrong))
	_check(
			"amendments: old kind values unchanged",
			CombatFact.Kind.PHASE_START == 0 and CombatFact.Kind.MODIFIER_EXPIRED == 34
			and CombatFact.Kind.size() == 47
	)
	_check(
			"amendments: the reinforcement kinds appended (combat map plan, New facts)",
			CombatFact.Kind.REINFORCEMENT_INCOMING == 44
			and CombatFact.Kind.REINFORCEMENT_ARRIVED == 45
	)
	_check(
			"amendments: the rune discard appended last (combat UI plan, UI14)",
			CombatFact.Kind.RUNE_DISCARDED == 46
	)


# The item, weapon or rune an action fact names (event bus plan, follow-up F2).
func _test_combat_fact_item_id() -> void:
	var potion: CombatFact = CombatFact.new(CombatFact.Kind.ITEM_USED, "unit:57", "unit:58")
	potion.item_id = "item:412"
	var swap: CombatFact = CombatFact.new(CombatFact.Kind.WEAPON_SWAPPED, "unit:57")
	swap.item_id = "item:9"
	var rune: CombatFact = CombatFact.new(CombatFact.Kind.RUNE_USED, "", "enemy:61")
	rune.item_id = "rune:3"
	rune.amount = 1
	rune.tile = Vector2i(5, 2)

	for fact: CombatFact in [potion, swap, rune]:
		var kind_name: String = CombatFact.Kind.find_key(fact.kind)
		var back: CombatFact = CombatFact.from_wire(fact.to_wire())
		_check(
				"item id: %s round trip" % [kind_name],
				back != null and back.item_id == fact.item_id and back.to_wire() == fact.to_wire()
		)
		var parsed: Variant = JSON.parse_string(JSON.stringify(fact.to_wire()))
		var through_json: CombatFact = CombatFact.from_wire(
				(parsed as Array) if parsed is Array else []
		)
		_check(
				"item id: %s through JSON" % [kind_name],
				through_json != null and through_json.to_wire() == fact.to_wire()
		)

	var rune_back: CombatFact = CombatFact.from_wire(rune.to_wire())
	_check(
			"item id: a rune keeps its target, tile and casting seat",
			rune_back != null and rune_back.actor_id.is_empty()
			and rune_back.target_id == "enemy:61" and rune_back.tile == Vector2i(5, 2)
			and rune_back.amount == 1
	)
	_check(
			"item id: log line names the item",
			potion.to_log_line(_describe) == (
					"s0#0 ITEM_USED unit:57 (Hakkapel) -> unit:58 item item:412 (Iron Axe)"
			),
			potion.to_log_line(_describe)
	)
	_check(
			"item id: empty on other kinds",
			CombatFact.new(CombatFact.Kind.HIT_TAKEN).item_id.is_empty()
	)


# The appended key field and STAT_CHANGED (event bus plan EB4, answer to question 3 of part 1).
func _test_combat_fact_key() -> void:
	var stat: CombatFact = CombatFact.new(CombatFact.Kind.STAT_CHANGED, "unit:57")
	stat.amount = 1
	stat.key = CombatValue.Stat.MGT
	var counter: CombatFact = CombatFact.new(CombatFact.Kind.COUNTER_CHANGED, "unit:57")
	counter.amount = 3
	counter.key = EffectTerms.Lane.CAMPAIGN
	_check(
			"key: STAT_CHANGED appended after BLOCK_LOST, key in slot 16",
			(
					CombatFact.Kind.STAT_CHANGED == 42 and stat.to_wire().size() == 18
					and stat.to_wire()[16] == CombatValue.Stat.MGT
			) as bool
	)
	for fact: CombatFact in [stat, counter]:
		var parsed: Variant = JSON.parse_string(JSON.stringify(fact.to_wire()))
		var back: CombatFact = CombatFact.from_wire((parsed as Array) if parsed is Array else [])
		_check(
				"key: %s keeps its key through JSON" % [CombatFact.Kind.find_key(fact.kind)],
				back != null and back.key == fact.key and back.to_wire() == fact.to_wire()
		)
	_snapshot(
			"key: stat log line",
			stat.to_log_line(),
			"s0#0 STAT_CHANGED unit:57 stat 1 amount 1"
	)
	_snapshot(
			"key: counter log line",
			counter.to_log_line(),
			"s0#0 COUNTER_CHANGED unit:57 lane 1 amount 3"
	)
	_check("key: 0 on other kinds", CombatFact.new(CombatFact.Kind.HIT_TAKEN).key == 0)


func _test_campaign_wire_round_trip() -> void:
	var fact: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, 2, "item:412")
	fact.seq = 12
	fact.target_id = "unit:57"
	fact.definition_id = "iron_axe"
	fact.amount = 3
	fact.source_effect_id = "effect:9"
	fact.flags = 5

	var back: CampaignFact = CampaignFact.from_wire(fact.to_wire())
	_check(
			"campaign wire: round trip equal",
			back != null and back.to_wire() == fact.to_wire(),
			"" if back == null else str(back.to_wire())
	)

	var parsed: Variant = JSON.parse_string(JSON.stringify(fact.to_wire()))
	var through_json: CampaignFact = CampaignFact.from_wire(
			(parsed as Array) if parsed is Array else []
	)
	_check(
			"campaign json: round trip equal",
			through_json != null and through_json.to_wire() == fact.to_wire()
	)

	var no_seat: CampaignFact = CampaignFact.from_wire(
			CampaignFact.new(CampaignFact.Kind.COMBAT_ENDED).to_wire()
	)
	_check("campaign wire: no seat kept", no_seat != null and no_seat.seat == CampaignFact.NO_SEAT)


func _test_campaign_wire_rejects_bad_data() -> void:
	var good: Array = CampaignFact.new(CampaignFact.Kind.LEVELED_UP, 0, "unit:57").to_wire()
	var cases: Dictionary[String, Array] = {
		"wrong length": good.slice(1),
		"unknown kind": _with(good, 0, 50),
		"seat below NO_SEAT": _with(good, 2, -2),
		"negative seq": _with(good, 1, -3),
		"int in a string slot": _with(good, 5, 412),
		"fractional amount": _with(good, 6, 0.25),
	}
	for case_name: String in cases:
		_check(
				"campaign wire bad data: %s refused" % [case_name],
				CampaignFact.from_wire(cases[case_name]) == null
		)


func _test_combat_log_line_documented_shape() -> void:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.HIT_TAKEN, "unit:57", "enemy:61")
	fact.seq = 143
	fact.amount = 6
	fact.hp_amount = 4
	fact.block_amount = 2
	fact.source = CombatFact.Source.ATTACK
	var line: String = fact.to_log_line(_describe)
	_check("log line: documented shape", line == DOCUMENTED_HIT_LINE, line)

	var dealt: CombatFact = CombatFact.new(CombatFact.Kind.HIT_DEALT, "enemy:61", "unit:57")
	dealt.seq = 142
	_check(
			"log line: dealt points at the target",
			dealt.to_log_line() == "s0#142 HIT_DEALT enemy:61 -> unit:57",
			dealt.to_log_line()
	)


func _test_combat_log_line_optional_parts() -> void:
	var phase: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	phase.session_id = 2
	phase.seq = 1
	_check(
			"log line: empty fields left out",
			phase.to_log_line() == "s2#1 PHASE_START",
			phase.to_log_line()
	)

	var full: CombatFact = _full_combat_fact()
	var expected: String = (
			"s1#40 DAMAGE_TAKEN unit:57 (Hakkapel) <- enemy:61 (Brute) amount 5 (hp 3, block 2)"
			+ " source splash type split effect effect:9 tile (4, 7) flags 0x3 types Bandit, Archer"
	)
	var full_line: String = full.to_log_line(_describe)
	_check("log line: every optional part", full_line == expected, full_line)

	var countered: CombatFact = CombatFact.new(CombatFact.Kind.HIT_TAKEN, "unit:57", "enemy:61")
	_check(
			"log line: zero amount left out",
			countered.to_log_line() == "s0#0 HIT_TAKEN unit:57 <- enemy:61",
			countered.to_log_line()
	)

	var healed: CombatFact = CombatFact.new(CombatFact.Kind.HEALED, "unit:57")
	healed.amount = 4
	_check(
			"log line: amount without a split",
			healed.to_log_line() == "s0#0 HEALED unit:57 amount 4",
			healed.to_log_line()
	)


func _test_campaign_log_line() -> void:
	var fact: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, 0, "item:412")
	fact.seq = 12
	fact.definition_id = "iron_axe"
	var line: String = fact.to_log_line(_describe)
	_check(
			"campaign log line: shape",
			line == "c#12 GAINED seat 0 item:412 (Iron Axe) definition iron_axe",
			line
	)

	var ended: CampaignFact = CampaignFact.new(CampaignFact.Kind.COMBAT_ENDED)
	ended.amount = 8
	_check(
			"campaign log line: no seat left out",
			ended.to_log_line() == "c#0 COMBAT_ENDED amount 8",
			ended.to_log_line()
	)


func _full_combat_fact() -> CombatFact:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_TAKEN, "unit:57", "enemy:61")
	fact.seq = 40
	fact.session_id = 1
	fact.amount = 5
	fact.hp_amount = 3
	fact.block_amount = 2
	fact.damage_type = CombatFact.DamageType.SPLIT
	fact.source = CombatFact.Source.SPLASH
	fact.source_effect_id = "effect:9"
	fact.tile = Vector2i(4, 7)
	fact.flags = 3
	fact.unit_types = PackedStringArray(["Bandit", "Archer"])
	return fact


# A copy of data with one slot replaced.
func _with(data: Array, index: int, value: Variant) -> Array:
	var copy: Array = data.duplicate()
	copy[index] = value
	return copy
