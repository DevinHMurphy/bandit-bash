# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_cue_listener.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name FactCueListener
extends RefCounted
## Sounds facts as they play: on each [signal CombatBus.fact_played] or
## [signal CampaignBus.fact_played] it finds the fact's rule in a [FactCueMap] and hands its cue
## id to the play callable. Facts reach a bus only during playback, so a sound plays when the
## board shows its fact, not when its batch arrives (as the event log writes its lines).[br]
## [b]Presentation only:[/b] it reads facts and, for the shapes that need it, the side of an id
## through the callable it was bound with; it never changes state.
##
## @tutorial(Audio scope): docs/design/audio.md

var _map: FactCueMap = null
var _play: Callable = Callable()
var _combat_bus: CombatBus = null
var _campaign_bus: CampaignBus = null
# Returns the CombatFact.CombatSide of an id, units and map objects alike (CombatState.side_of).
var _side_of: Callable = Callable()


## A listener reading [param map] that calls [param play] with a cue id (a [StringName]).
func _init(map: FactCueMap, play: Callable) -> void:
	_map = map
	_play = play
	if _map != null:
		for problem: String in _map.compile():
			push_error(problem)


## Sounds [param bus]'s facts from now on, reading sides through [param side_of]
## ([method CombatState.side_of]; invalid: the shapes that need it never match). Replaces any bus
## bound before.
func bind_combat(bus: CombatBus, side_of: Callable = Callable()) -> void:
	unbind()
	if bus == null:
		return
	_combat_bus = bus
	_side_of = side_of
	_combat_bus.fact_played.connect(_on_combat_bus_fact_played)


## Sounds [param bus]'s facts from now on. Replaces any bus bound before.
func bind_campaign(bus: CampaignBus) -> void:
	unbind()
	if bus == null:
		return
	_campaign_bus = bus
	_campaign_bus.fact_played.connect(_on_campaign_bus_fact_played)


## Stops sounding facts. Does nothing when nothing is bound.
func unbind() -> void:
	if _combat_bus != null and _combat_bus.fact_played.is_connected(_on_combat_bus_fact_played):
		_combat_bus.fact_played.disconnect(_on_combat_bus_fact_played)
	if (
			_campaign_bus != null
			and _campaign_bus.fact_played.is_connected(_on_campaign_bus_fact_played)
	):
		_campaign_bus.fact_played.disconnect(_on_campaign_bus_fact_played)
	_combat_bus = null
	_campaign_bus = null
	_side_of = Callable()


## Whether [param bus] is the bus bound.
func is_bound_to(bus: RefCounted) -> bool:
	return bus != null and (bus == _combat_bus or bus == _campaign_bus)


## The cue id (or [code]music:<moment>[/code]) [param fact] sounds; empty for none.
func cue_for_combat(fact: CombatFact) -> StringName:
	if _map == null or fact == null:
		return &""
	for rule: FactCueMap.Rule in _map.rules_for(fact.kind):
		if _matches(rule.shape, fact):
			return rule.cue_id
	return &""


## The cue id [param fact] sounds; empty for none. Campaign facts match the bare kind only.
func cue_for_campaign(fact: CampaignFact) -> StringName:
	if _map == null or fact == null:
		return &""
	for rule: FactCueMap.Rule in _map.rules_for(fact.kind):
		if rule.shape == FactCueMap.Shape.ANY:
			return rule.cue_id
	return &""


func _matches(shape: FactCueMap.Shape, fact: CombatFact) -> bool:
	match shape:
		FactCueMap.Shape.NO_DAMAGE:
			return fact.amount == 0
		FactCueMap.Shape.ON_OBJECT:
			return (
					not fact.target_id.is_empty()
					and _side(fact.target_id) == CombatFact.CombatSide.NONE
					and _side_of.is_valid()
			)
		FactCueMap.Shape.PLAYER_ACTOR:
			return _side(fact.actor_id) == CombatFact.CombatSide.PLAYER
		FactCueMap.Shape.PLAYER_SIDE:
			return fact.side == CombatFact.CombatSide.PLAYER
		FactCueMap.Shape.ENEMY_SIDE:
			return fact.side == CombatFact.CombatSide.ENEMY
	return true


# The side of id through the bound lookup; NONE without one.
func _side(id: String) -> CombatFact.CombatSide:
	if not _side_of.is_valid() or id.is_empty():
		return CombatFact.CombatSide.NONE
	var side: CombatFact.CombatSide = _side_of.call(id)
	return side


func _on_combat_bus_fact_played(fact: CombatFact) -> void:
	var cue_id: StringName = cue_for_combat(fact)
	if not cue_id.is_empty() and _play.is_valid():
		_play.call(cue_id)


func _on_campaign_bus_fact_played(fact: CampaignFact) -> void:
	var cue_id: StringName = cue_for_campaign(fact)
	if not cue_id.is_empty() and _play.is_valid():
		_play.call(cue_id)
