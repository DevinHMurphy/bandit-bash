# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bus_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/effects/effects_case_base.gd"
## Bus cases for tests/effects/run_all.gd ([CombatBus], [CampaignBus], [BusChannel]): routing,
## signal order, [BusTracer], and NetLog's appended categories.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "effects"

const NetLogScript: GDScript = preload("res://scripts/autoload/net_log.gd")


func run() -> void:
	_test_combat_bus_routes_every_kind_once()
	_test_campaign_bus_routes_every_kind_once()
	_test_bus_domain_signal_before_fact_played()
	_test_tracer_records_play_order()
	_test_tracer_attach_detach_clear()
	_test_net_log_categories_appended()


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


func _seq_fact(kind: CombatFact.Kind, session_id: int, seq: int) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind)
	fact.session_id = session_id
	fact.seq = seq
	return fact
