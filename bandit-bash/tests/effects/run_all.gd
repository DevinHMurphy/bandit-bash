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
## buses ([CombatBus], [CampaignBus], [BusChannel]) and [BusTracer].
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/effects/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## wire data make the fact classes log warnings on purpose; only FAIL lines mean a problem.[br]
## Autoloads don't exist in [code]--script[/code] mode, so nothing here may use them; NetLog's enum
## is read from its script.

const NetLogScript: GDScript = preload("res://scripts/autoload/net_log.gd")

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
