# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_intent.gd
# Author:
# Created:  November 3, 2026
# Modified: November 3, 2026
# ==============================================================================

class_name EnemyIntent
extends RefCounted
## One enemy's next turn as the intents show it: its icon, its target rule, why it chose this, and
## what P07 draws its line and area from (game-vision.md, Enemy intentions; enemies and AI plan,
## questions 3, 4 and 9).
##
## Built by [Intents] from the [EnemyPlan] the AI chose on the board as the AI expects it, so
## [member order] is its place in the phase if every forecast hit lands. Kills are read from the
## plan's forecast ([member defeats]), not only [member decided_by]: a Cleave splash kill usually
## wins on [constant EnemyPlan.Step.KILL_CHANCE], because the Brute could strike that unit
## directly too. Plain data.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

## The intent icon. Append only: P07 keys its icons by it.
enum Kind {
	## Attacks [member target_id] from [member tile].
	ATTACK = 0,
	## Heals [member target_id] from [member tile] with its staff.
	HEAL = 1,
	## Holds near its pack or its tile: a Support regroup, or a Wait.
	GUARD = 2,
	## Walks toward [member target_id], the nearest foe by path cost.
	ADVANCE = 3,
}

## The enemy.
var unit_id: String = ""

## Its place in the phase as the AI expects it, from 0.
var order: int = 0

## The icon.
var kind: Kind = Kind.GUARD

## The behavior it plays, after the darkness switch.
var behavior: EnemyClassDefinition.Behavior = EnemyClassDefinition.Behavior.AGGRESSIVE

## The target rule it plays ([constant ContentIds.TARGET_RULES]); empty for an enemy with no class.
var target_rule_id: String = ""

## The rule as players read it beside the icon ([member EnemyClassDefinition.target_rule_text]);
## empty when it plays another rule than its class's, as after the darkness.
var target_rule_text: String = ""

## Whether its forecast defeats a player unit: its target, or another by splash.
var is_kill: bool = false

## The rating step that chose this plan over its best rival ([member EnemyPlan.decided_by]).
var decided_by: EnemyPlan.Step = EnemyPlan.Step.ONLY_OPTION

## The unit it attacks, heals or advances on; empty for [constant Kind.GUARD].
var target_id: String = ""

## The tile it acts from: the end of [member path], or its own tile.
var tile: Vector2i = CombatFact.NO_TILE

## The tiles it walks, starting on its own tile; empty when it stays.
var path: Array[Vector2i] = []

## The weapon an attack names: empty for the one in hand, the stowed one for a Sidearm swap.
var weapon_id: String = ""

## The tiles its splash would hit (Cleave around [member tile]), in row-major order; empty when
## no splash fires in its forecast.
var area: Array[Vector2i] = []

## Every player unit its forecast defeats, in state order.
var defeats: PackedStringArray = []

## Every other unit of its own side its forecast defeats (friendly fire), in state order; never the
## enemy itself, whose fall to a counter its plan's forecast shows.
var allies_defeated: PackedStringArray = []

## The plan it came from, with its forecast; read-only.
var plan: EnemyPlan = null


## Why it chose this, as the player reads it: [constant EnemyPlan.Step.KILL] whenever its
## forecast defeats a player unit, else [member decided_by].
func reason() -> EnemyPlan.Step:
	return EnemyPlan.Step.KILL if is_kill else decided_by


## The intent as one line for logs and tests, such as
## [code]1 e1 attack p2 from (3, 2), kill, defeats p2[/code].
func describe() -> String:
	var icon: String = (Kind.find_key(kind) as String).to_lower()
	var parts: PackedStringArray = ["%d %s %s" % [order, unit_id, icon]]
	if not target_id.is_empty():
		parts[0] += " %s" % [target_id]
	parts[0] += " from %s" % [tile]
	parts.append((EnemyPlan.Step.find_key(reason()) as String).to_lower())
	if not defeats.is_empty():
		parts.append("defeats %s" % [" ".join(defeats)])
	if not allies_defeated.is_empty():
		parts.append("fells allies %s" % [" ".join(allies_defeated)])
	if not area.is_empty():
		parts.append("area %d tiles" % [area.size()])
	return ", ".join(parts)


## The intent of [param chosen], the [param place]-th enemy to act on [param engine]'s board,
## read before the plan is carried out. [param definition]: the enemy's class; null for none.
static func from_plan(
		engine: EffectEngine,
		chosen: EnemyPlan,
		place: int,
		definition: EnemyClassDefinition
) -> EnemyIntent:
	var state: CombatState = engine.state
	var intent: EnemyIntent = EnemyIntent.new()
	intent.plan = chosen
	intent.unit_id = chosen.actor_id
	intent.order = place
	intent.kind = _kind_of(state, chosen)
	intent.behavior = chosen.behavior
	intent.target_rule_id = chosen.target_rule_id
	if definition != null and definition.target_rule_id == chosen.target_rule_id:
		intent.target_rule_text = definition.target_rule_text
	intent.is_kill = chosen.is_kill
	intent.decided_by = chosen.decided_by
	if intent.kind != Kind.GUARD:
		intent.target_id = chosen.target_id
	intent.tile = chosen.tile
	intent.path = chosen.path.duplicate()
	intent.weapon_id = chosen.weapon_id
	if chosen.forecast == null:
		return intent
	for outcome: CombatForecast.UnitOutcome in chosen.forecast.units:
		if not outcome.is_defeated:
			continue
		if state.side_of(outcome.unit_id) == CombatFact.CombatSide.PLAYER:
			intent.defeats.append(outcome.unit_id)
		elif outcome.unit_id != chosen.actor_id:
			if state.side_of(outcome.unit_id) == state.side_of(chosen.actor_id):
				intent.allies_defeated.append(outcome.unit_id)
	intent.area = _splash_area(engine, chosen)
	return intent


static func _kind_of(state: CombatState, chosen: EnemyPlan) -> Kind:
	match chosen.kind:
		EnemyPlan.Kind.ATTACK:
			return Kind.ATTACK
		EnemyPlan.Kind.STAFF:
			var held: CombatState.WeaponStats = state.equipped_weapon(chosen.actor_id)
			if held != null and held.staff == CombatState.WeaponStats.Staff.HEAL:
				return Kind.HEAL
		EnemyPlan.Kind.ADVANCE:
			return Kind.ADVANCE
	# ASSUMPTION: a Support regroup and a Wait show the guard icon; the vision's icon list
	# (attack, guard, buff, advance) has no regroup or wait icon.
	return Kind.GUARD


# The tiles of every splash area the plan's forecast fired: each of the enemy's activated effects
# that deals splash to an Area, centered where the enemy acts from (the owner, or the fact's
# actor on its Hit dealt) or on its target (the fact's target, the command's target).
static func _splash_area(engine: EffectEngine, chosen: EnemyPlan) -> Array[Vector2i]:
	var state: CombatState = engine.state
	var covered: Dictionary[Vector2i, bool] = {}
	var fired: Dictionary[String, bool] = {}
	for fact: CombatFact in chosen.forecast.facts:
		if fact.kind != CombatFact.Kind.EFFECT_ACTIVATED or fact.actor_id != chosen.actor_id:
			continue
		if fired.has(fact.source_effect_id):
			continue
		fired[fact.source_effect_id] = true
		var instance: EffectInstance = engine.get_instance(fact.source_effect_id)
		if instance == null:
			continue
		for operation: EffectOperation in instance.definition.operations:
			var splash: DealSplash = operation as DealSplash
			if splash == null or not splash.target is Area:
				continue
			var shape: Area = splash.target
			var center: Vector2i = chosen.tile
			if shape.center != Area.Center.OWNER and shape.center != Area.Center.FACT_ACTOR:
				center = state.tile_of(chosen.target_id)
			var span: Vector2i = Vector2i(0 if shape.include_center else 1, shape.radius)
			for tile: Vector2i in DangerZone.tiles_within(center, span):
				if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					covered[tile] = true
	var tiles: Array[Vector2i] = []
	tiles.assign(covered.keys())
	tiles.sort_custom(EnemyPlan.tile_precedes)
	return tiles
