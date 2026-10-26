# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the event bus and effects layer: facts ([CombatFact], [CampaignFact]),
## buses ([CombatBus], [CampaignBus], [BusChannel]), [BusTracer], and value queries ([Modifier],
## [ValueBreakdown], [StatSheet] and the keys of [CombatValue], [DamageStage], [CampaignValue]).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/effects/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## wire data make the fact classes log warnings on purpose; only FAIL lines mean a problem.[br]
## Autoloads don't exist in [code]--script[/code] mode, so nothing here may use them; NetLog's enum
## is read from its script.

const NetLogScript: GDScript = preload("res://scripts/autoload/net_log.gd")

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

# The documented example line (event bus plan, Logging and debugging), without NetLog's prefix.
const DOCUMENTED_HIT_LINE: String = (
		"s0#143 HIT_TAKEN unit:57 (Hakkapel) <- enemy:61 (Brute) amount 6 (hp 4, block 2)"
		+ " source attack"
)

# Display names the fake describe uses, standing in for a session's describe.
const NAMES: Dictionary[String, String] = {
	"unit:57": "Hakkapel",
	"enemy:61": "Brute",
	"item:412": "Iron Axe",
}

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Event bus tests. Warnings from CombatFact and CampaignFact below are expected. ---")

	_test_combat_wire_round_trip()
	_test_combat_wire_through_json()
	_test_combat_wire_rejects_bad_data()
	_test_campaign_wire_round_trip()
	_test_campaign_wire_rejects_bad_data()
	_test_combat_log_line_documented_shape()
	_test_combat_log_line_optional_parts()
	_test_campaign_log_line()
	_test_combat_bus_routes_every_kind_once()
	_test_campaign_bus_routes_every_kind_once()
	_test_bus_domain_signal_before_fact_played()
	_test_tracer_records_play_order()
	_test_tracer_attach_detach_clear()
	_test_net_log_categories_appended()
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

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


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
		"null slot": _with(good, 13, null),
	}
	for case_name: String in cases:
		_check(
				"combat wire bad data: %s refused" % [case_name],
				CombatFact.from_wire(cases[case_name]) == null
		)


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
	var through_json: CampaignFact = CampaignFact.from_wire(parsed if parsed is Array else [])
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
			+ " source splash type split effect effect:9 tile (4, 7) flags 0x3"
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


# Every kind plays on exactly one domain signal, and always on fact_played.
func _test_combat_bus_routes_every_kind_once() -> void:
	var bus: CombatBus = CombatBus.new()
	var counts: Dictionary[String, int] = {}
	var channels: Dictionary[String, BusChannel] = {
		"flow": bus.flow,
		"unit": bus.unit,
		"action": bus.action,
		"world": bus.world,
		"effect": bus.effect,
	}
	_count_channel_signals(channels, counts)
	var played: Array[int] = [0]
	bus.fact_played.connect(func(_fact: CombatFact) -> void: played[0] += 1)

	var unrouted: PackedStringArray = []
	for kind: int in CombatFact.Kind.values():
		var before: int = _sum(counts)
		bus.play(CombatFact.new(kind as CombatFact.Kind))
		if _sum(counts) - before != 1:
			unrouted.append(str(CombatFact.Kind.find_key(kind)))
	var kind_count: int = CombatFact.Kind.size()
	_check("combat bus: every kind on one domain signal", unrouted.is_empty(), ", ".join(unrouted))
	_check("combat bus: fact_played for every kind", played[0] == kind_count, str(played[0]))
	_check("combat bus: no idle signals", counts.size() == kind_count, str(counts.size()))


func _test_campaign_bus_routes_every_kind_once() -> void:
	var bus: CampaignBus = CampaignBus.new()
	var counts: Dictionary[String, int] = {}
	var channels: Dictionary[String, BusChannel] = {
		"run": bus.run,
		"army": bus.army,
		"effect": bus.effect,
	}
	_count_channel_signals(channels, counts)

	var unrouted: PackedStringArray = []
	for kind: int in CampaignFact.Kind.values():
		var before: int = _sum(counts)
		bus.play(CampaignFact.new(kind as CampaignFact.Kind))
		if _sum(counts) - before != 1:
			unrouted.append(str(CampaignFact.Kind.find_key(kind)))
	var kind_count: int = CampaignFact.Kind.size()
	_check(
			"campaign bus: every kind on one domain signal",
			unrouted.is_empty(),
			", ".join(unrouted)
	)
	_check("campaign bus: no idle signals", counts.size() == kind_count, str(counts.size()))


func _test_bus_domain_signal_before_fact_played() -> void:
	var bus: CombatBus = CombatBus.new()
	# An Array, not a PackedStringArray: lambdas capture packed arrays by value.
	var order: Array[String] = []
	bus.action.hit_taken.connect(func(_fact: CombatFact) -> void: order.append("hit_taken"))
	bus.fact_played.connect(func(_fact: CombatFact) -> void: order.append("fact_played"))
	bus.play(CombatFact.new(CombatFact.Kind.HIT_TAKEN, "unit:57", "enemy:61"))
	_check(
			"bus order: domain signal, then fact_played",
			order == ["hit_taken", "fact_played"],
			str(order)
	)

	var payload: Array[CombatFact] = []
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, "unit:57")
	bus.unit.moved.connect(func(received: CombatFact) -> void: payload.append(received))
	bus.play(fact)
	_check("bus payload: the same fact object", payload.size() == 1 and payload[0] == fact)


func _test_tracer_records_play_order() -> void:
	var map_a: CombatBus = CombatBus.new()
	var map_b: CombatBus = CombatBus.new()
	var campaign: CampaignBus = CampaignBus.new()
	var tracer: BusTracer = BusTracer.new(_describe)
	tracer.attach_combat(map_a)
	tracer.attach_combat(map_b)
	tracer.attach_campaign(campaign)

	map_a.play(_seq_fact(CombatFact.Kind.PHASE_START, 0, 1))
	map_b.play(_seq_fact(CombatFact.Kind.PHASE_START, 1, 1))
	map_a.play(_seq_fact(CombatFact.Kind.UNIT_MOVED, 0, 2))
	var gained: CampaignFact = CampaignFact.new(CampaignFact.Kind.GAINED, 1)
	gained.seq = 3
	campaign.play(gained)
	map_b.play(_seq_fact(CombatFact.Kind.PHASE_END, 1, 2))

	var expected: PackedStringArray = [
		"s0#1 PHASE_START",
		"s1#1 PHASE_START",
		"s0#2 UNIT_MOVED",
		"c#3 GAINED seat 1",
		"s1#2 PHASE_END",
	]
	_check("tracer: lines in play order across buses", tracer.lines == expected, str(tracer.lines))
	_check(
			"tracer: facts kept per bus type",
			tracer.combat_facts.size() == 4 and tracer.campaign_facts.size() == 1
			and tracer.combat_facts[2].kind == CombatFact.Kind.UNIT_MOVED
	)


func _test_tracer_attach_detach_clear() -> void:
	var bus: CombatBus = CombatBus.new()
	var campaign: CampaignBus = CampaignBus.new()
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(bus)
	tracer.attach_combat(bus)
	tracer.attach_campaign(campaign)
	tracer.attach_campaign(campaign)
	bus.play(CombatFact.new(CombatFact.Kind.PHASE_START))
	campaign.play(CampaignFact.new(CampaignFact.Kind.COMBAT_ENDED))
	_check("tracer: attaching twice records once", tracer.lines.size() == 2, str(tracer.lines))

	tracer.detach_combat(bus)
	tracer.detach_campaign(campaign)
	bus.play(CombatFact.new(CombatFact.Kind.PHASE_END))
	campaign.play(CampaignFact.new(CampaignFact.Kind.COMBAT_ENDED))
	_check("tracer: detached buses not recorded", tracer.lines.size() == 2)
	tracer.detach_combat(bus)
	_check("tracer: detaching twice is harmless", tracer.lines.size() == 2)

	tracer.clear()
	_check(
			"tracer: clear empties everything",
			tracer.lines.is_empty() and tracer.combat_facts.is_empty()
			and tracer.campaign_facts.is_empty()
	)
	tracer.attach_combat(bus)
	tracer.clear()
	bus.play(CombatFact.new(CombatFact.Kind.PHASE_START))
	_check("tracer: clear keeps buses attached", tracer.lines.size() == 1)


# Existing values are a network and log contract; the new ones are appended after them.
func _test_net_log_categories_appended() -> void:
	var categories: Dictionary = NetLogScript.Category
	var expected: Dictionary[String, int] = {
		"STEAM": 0,
		"LOBBY": 1,
		"SCENE": 2,
		"COMBAT": 3,
		"EFFECTS": 4,
		"CAMPAIGN": 5,
		"AI": 6,
	}
	var mismatched: PackedStringArray = []
	for key: String in expected:
		if categories.get(key, -1) != expected[key]:
			mismatched.append(key)
	_check("net log: categories and values", mismatched.is_empty(), ", ".join(mismatched))
	_check("net log: nothing else added", categories.size() == expected.size())


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

	var unshovable: int = CombatValue.Permission.UNSHOVABLE
	var boss: Array[Modifier] = [
		_mod(unshovable, GRANT, 0.0, UNIT_TRAIT, "enemy:1", "Bulwark"),
	]
	_check(
			"permission: off by default, a grant turns it on",
			not ValueBreakdown.compute_permission(unshovable, []).is_allowed()
			and ValueBreakdown.compute_permission(unshovable, boss).is_allowed()
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
		"EFFECTIVE_MODIFIER", "STAFF_AMOUNT", "MOVEMENT",
	]
	var expected_permissions: PackedStringArray = [
		"CAN_COUNTER", "UNSHOVABLE", "MAY_MOVE_AFTER_ACTING", "FREE_WEAPON_SWAP",
		"SKIP_MITIGATION_ON_CRIT",
	]
	var expected_stages: PackedStringArray = ["ATTACK", "MITIGATION", "CRITICAL", "MULTIPLIERS"]
	_check(
			"keys: combat core's CombatValue keys seeded",
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


# Connects a counter to every signal declared by each channel's script. Keys are "channel.signal".
func _count_channel_signals(
		channels: Dictionary[String, BusChannel], counts: Dictionary[String, int]
) -> void:
	for channel_name: String in channels:
		var channel: BusChannel = channels[channel_name]
		var script: Script = channel.get_script()
		for info: Dictionary in script.get_script_signal_list():
			var signal_name: String = info["name"]
			var key: String = "%s.%s" % [channel_name, signal_name]
			channel.connect(
					signal_name,
					func(_fact: RefCounted) -> void: counts[key] = counts.get(key, 0) + 1
			)


func _sum(counts: Dictionary[String, int]) -> int:
	var total: int = 0
	for key: String in counts:
		total += counts[key]
	return total


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
	return fact


func _seq_fact(kind: CombatFact.Kind, session_id: int, seq: int) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind)
	fact.session_id = session_id
	fact.seq = seq
	return fact


# A copy of data with one slot replaced.
func _with(data: Array, index: int, value: Variant) -> Array:
	var copy: Array = data.duplicate()
	copy[index] = value
	return copy


# Stands in for a session's describe: "unit:57" -> "unit:57 (Hakkapel)".
func _describe(id: String) -> String:
	return "%s (%s)" % [id, NAMES[id]] if NAMES.has(id) else id


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
