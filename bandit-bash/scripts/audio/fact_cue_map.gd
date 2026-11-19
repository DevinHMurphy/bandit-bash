# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_cue_map.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name FactCueMap
extends Resource
## Which cue a played fact sounds, as data: one line of [member cues] per rule.
##
## A key is a fact kind's name, [code]"HIT_DEALT"[/code], or a kind and a [enum Shape],
## [code]"HIT_DEALT/no_damage"[/code]; its value is a cue id, or [code]music:<moment>[/code] for
## the service's battle music ([MusicCueMap]). A fact sounds at most one rule: its kind's first
## matching shape in [enum Shape] order, [code]any[/code] (the bare kind) last. Read by
## [FactCueListener]; [method compile] reports keys that name no kind or shape.
## Lives in [code]res://data/audio/maps/[/code]: one map for [CombatFact], one for [CampaignFact].
##
## @tutorial(Audio scope): docs/design/audio.md

## Which fact kinds the keys name.
enum Domain {
	## [enum CombatFact.Kind], played on a [CombatBus].
	COMBAT = 0,
	## [enum CampaignFact.Kind], played on a [CampaignBus].
	CAMPAIGN = 1,
}

## What else a fact must be for a rule to match, tried in this order with [constant ANY] last. A
## shape that needs the battle's or run's state ([code]on_object[/code], [code]player_actor[/code],
## [code]combat[/code]) never matches without it.
enum Shape {
	## [code]no_damage[/code]: [member CombatFact.amount] is 0, a hit fully countered.
	NO_DAMAGE = 0,
	## [code]on_object[/code]: the target is a map object, not a unit.
	ON_OBJECT = 1,
	## [code]player_actor[/code]: the actor is on the player side.
	PLAYER_ACTOR = 2,
	## [code]player_side[/code]: the fact's [member CombatFact.side] is the player side (its phase,
	## or the side that won).
	PLAYER_SIDE = 3,
	## [code]enemy_side[/code]: the fact's side is the enemy side.
	ENEMY_SIDE = 4,
	## The bare kind: any fact of it.
	ANY = 5,
	## [code]combat[/code]: a campaign fact whose [member CampaignFact.amount] is a node of a
	## combat type ([constant COMBAT_NODE_TYPES]), such as [code]NODE_CHOSEN[/code].
	COMBAT_NODE = 6,
}

## The [enum CampaignGraph.NodeType]s a [code]combat[/code] rule matches: the nodes that open a
## battle.
const COMBAT_NODE_TYPES: Array[CampaignGraph.NodeType] = [
	CampaignGraph.NodeType.STANDARD,
	CampaignGraph.NodeType.KEY,
	CampaignGraph.NodeType.BOSS,
]

## The prefix of a value naming a battle music moment instead of a cue id.
const MUSIC_PREFIX: String = "music:"

# Each shape's word in a key, after the "/".
const _SHAPE_WORDS: Dictionary[String, Shape] = {
	"no_damage": Shape.NO_DAMAGE,
	"on_object": Shape.ON_OBJECT,
	"player_actor": Shape.PLAYER_ACTOR,
	"player_side": Shape.PLAYER_SIDE,
	"enemy_side": Shape.ENEMY_SIDE,
	"combat": Shape.COMBAT_NODE,
}

## Which kinds the keys name.
@export var domain: Domain = Domain.COMBAT

## The rules: [code]"KIND"[/code] or [code]"KIND/shape"[/code] to a cue id or
## [code]music:<moment>[/code]. [b]Empty:[/b] no fact sounds.
@export var cues: Dictionary[String, String] = {}

# Built by compile(): each kind's rules, Array[Rule] in Shape order.
var _rules: Dictionary[int, Array] = {}
var _is_compiled: bool = false


## Builds the lookup from [member cues] and returns what is wrong with it, one line per bad key;
## a bad key is left out. Called by the first lookup when not called before.
func compile() -> PackedStringArray:
	_rules.clear()
	_is_compiled = true
	var problems: PackedStringArray = []
	var kinds: Dictionary = CombatFact.Kind if domain == Domain.COMBAT else CampaignFact.Kind
	for key: String in cues:
		var parts: PackedStringArray = key.split("/")
		var shape: Shape = Shape.ANY
		if parts.size() > 2 or not kinds.has(parts[0]):
			problems.append("FactCueMap: %s names no %s fact kind" % [key, Domain.find_key(domain)])
			continue
		if parts.size() == 2:
			if not _SHAPE_WORDS.has(parts[1]):
				problems.append("FactCueMap: %s names no shape" % [key])
				continue
			shape = _SHAPE_WORDS[parts[1]]
		var kind: int = kinds[parts[0]]
		if not _rules.has(kind):
			_rules[kind] = []
		_rules[kind].append(Rule.new(shape, StringName(cues[key])))
	for kind: int in _rules:
		_rules[kind].sort_custom(
				func(a: Rule, b: Rule) -> bool: return _try_order(a.shape) < _try_order(b.shape)
		)
	return problems


## The rules for fact kind [param kind], in the order they are tried; empty for none.
func rules_for(kind: int) -> Array[Rule]:
	if not _is_compiled:
		compile()
	var rules: Array[Rule] = []
	for rule: Rule in _rules.get(kind, []):
		rules.append(rule)
	return rules


# Where shape is tried: in Shape order, except ANY, which is always last; the shapes added after
# it keep their enum values.
static func _try_order(shape: Shape) -> int:
	return Shape.size() if shape == Shape.ANY else shape


## One rule: a shape and the cue id (or music moment) it sounds.
class Rule:
	extends RefCounted

	## What the fact must also be.
	var shape: Shape = Shape.ANY
	## The cue id, or [code]music:<moment>[/code].
	var cue_id: StringName = &""

	func _init(rule_shape: Shape, rule_cue_id: StringName) -> void:
		shape = rule_shape
		cue_id = rule_cue_id
