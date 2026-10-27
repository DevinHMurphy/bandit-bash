# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     bus_tracer.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name BusTracer
extends RefCounted
## Records the facts that buses play, in play order, for tests and debugging.
##
## Attach it to any number of [CombatBus] and [CampaignBus] instances through their
## [code]fact_played[/code] signals. [member lines] interleaves every bus in the order facts were
## played; [member combat_facts] and [member campaign_facts] keep the facts themselves.[br]
## [b]Unbounded:[/b] it holds every fact until [method clear], so detach it when a test or debug
## session ends.

## Every combat fact played on an attached bus, in play order.
var combat_facts: Array[CombatFact] = []

## Every campaign fact played on an attached bus, in play order.
var campaign_facts: Array[CampaignFact] = []

## One log line per fact from every attached bus, in play order.
var lines: PackedStringArray = []

# Turns ids into display text for lines; invalid prints ids bare.
var _describe: Callable = Callable()


## [param describe]: turns an id into display text for [member lines], such as a session's
## describe. Leave it invalid to print bare ids.
func _init(describe: Callable = Callable()) -> void:
	_describe = describe


## Starts recording [param bus]. Attaching the same bus twice records it once.
func attach_combat(bus: CombatBus) -> void:
	if not bus.fact_played.is_connected(_on_combat_bus_fact_played):
		bus.fact_played.connect(_on_combat_bus_fact_played)


## Starts recording [param bus]. Attaching the same bus twice records it once.
func attach_campaign(bus: CampaignBus) -> void:
	if not bus.fact_played.is_connected(_on_campaign_bus_fact_played):
		bus.fact_played.connect(_on_campaign_bus_fact_played)


## Stops recording [param bus]. Recorded facts are kept.
func detach_combat(bus: CombatBus) -> void:
	if bus.fact_played.is_connected(_on_combat_bus_fact_played):
		bus.fact_played.disconnect(_on_combat_bus_fact_played)


## Stops recording [param bus]. Recorded facts are kept.
func detach_campaign(bus: CampaignBus) -> void:
	if bus.fact_played.is_connected(_on_campaign_bus_fact_played):
		bus.fact_played.disconnect(_on_campaign_bus_fact_played)


## Forgets everything recorded so far. Attached buses stay attached.
func clear() -> void:
	combat_facts.clear()
	campaign_facts.clear()
	lines.clear()


func _on_combat_bus_fact_played(fact: CombatFact) -> void:
	combat_facts.append(fact)
	lines.append(fact.to_log_line(_describe))


func _on_campaign_bus_fact_played(fact: CampaignFact) -> void:
	campaign_facts.append(fact)
	lines.append(fact.to_log_line(_describe))
