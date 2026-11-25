# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_intent.gd
# Author:
# Created:  November 3, 2026
# Modified: November 24, 2026
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
	## Uses the map object [member target_id] from [member tile]: loots a chest or searchable,
	## pulls a lever or douses a Brazier; [member area] shows what changes.
	USE_OBJECT = 4,
	## Its signature move ([member EnemyClassDefinition.signature_move]) fires at the coming enemy
	## Phase Start, before it acts: [member signature_name] names it, and [member area] holds the
	## tiles it covers. Target, tile and path still show the action its [member plan] takes after.
	SIGNATURE = 5,
}

# The rule text once the darkness has switched an enemy to the nearest foe (enemies and AI plan,
# question 23): the-darkness.md's "moves toward and attacks the nearest reachable target", read at
# a glance like the classes' first clauses.
const _DARKNESS_RULE_TEXT: String = "Nearest foe"

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
## "Nearest foe" once the darkness has switched it. Empty for an enemy with no class.
var target_rule_text: String = ""

## Whether its forecast defeats a player unit: its target, or another by splash.
var is_kill: bool = false

## The rating step that chose this plan over its best rival ([member EnemyPlan.decided_by]).
var decided_by: EnemyPlan.Step = EnemyPlan.Step.ONLY_OPTION

## The unit it attacks, heals or advances on; a map object's id for [constant Kind.USE_OBJECT]
## and for a powder keg it blows (an attack); empty for [constant Kind.GUARD].
var target_id: String = ""

## The tile it acts from: the end of [member path], or its own tile.
var tile: Vector2i = CombatFact.NO_TILE

## The tiles it walks, starting on its own tile; empty when it stays.
var path: Array[Vector2i] = []

## The weapon an attack names: empty for the one in hand, the stowed one for a Sidearm swap.
var weapon_id: String = ""

## The tiles its splash or curse would hit (Cleave around [member tile], Trample and Curse
## around its target, each powder keg's blast that goes off), in row-major order; for an object
## use, the doors a lever moves or the tiles a Brazier lights. Empty when none applies.
var area: Array[Vector2i] = []

## Every player unit its forecast defeats, in state order.
var defeats: PackedStringArray = []

## Every other unit of its own side its forecast defeats (friendly fire), in state order; never the
## enemy itself, whose fall to a counter its plan's forecast shows.
var allies_defeated: PackedStringArray = []

## The plan it came from, with its forecast; read-only.
var plan: EnemyPlan = null

## The signature move it fires first, as players read it ("War Horn", its class's trait name);
## empty unless [member kind] is [constant Kind.SIGNATURE].
var signature_name: String = ""


## Why it chose this, as the player reads it: [constant EnemyPlan.Step.KILL] whenever its
## forecast defeats a player unit, else [member decided_by].
func reason() -> EnemyPlan.Step:
	return EnemyPlan.Step.KILL if is_kill else decided_by


## The intent as one line for logs and tests, such as
## [code]1 e1 attack p2 from (3, 2), kill, defeats p2[/code].
func describe() -> String:
	var icon: String = (Kind.find_key(kind) as String).to_lower()
	var parts: PackedStringArray = ["%d %s %s" % [order, unit_id, icon]]
	if kind == Kind.SIGNATURE:
		parts[0] += " %s" % [signature_name]
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


## Shows its signature move [param move_name] firing before it acts, over [param tiles]: the icon
## becomes [constant Kind.SIGNATURE], and [param tiles] join the action's own [member area].
func show_signature(move_name: String, tiles: Array[Vector2i]) -> void:
	kind = Kind.SIGNATURE
	signature_name = move_name
	var covered: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in area:
		covered[tile] = true
	for tile: Vector2i in tiles:
		covered[tile] = true
	area.assign(covered.keys())
	area.sort_custom(EnemyPlan.tile_precedes)


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
	elif definition != null:
		# Only the darkness plays a rule other than the class's ([method EnemyAI.decide]).
		intent.target_rule_text = _DARKNESS_RULE_TEXT
	intent.is_kill = chosen.is_kill
	intent.decided_by = chosen.decided_by
	if intent.kind != Kind.GUARD:
		intent.target_id = chosen.target_id
	intent.tile = chosen.tile
	intent.path = chosen.path.duplicate()
	intent.weapon_id = chosen.weapon_id
	if intent.kind == Kind.USE_OBJECT:
		intent.area = _object_area(state, state.map.object(chosen.target_id))
		return intent
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
		EnemyPlan.Kind.LOOT, EnemyPlan.Kind.USE_OBJECT:
			return Kind.USE_OBJECT
	# A Support regroup and a Wait show the guard icon (question 23): the vision's icon list
	# (attack, guard, buff, advance) has no regroup or wait icon.
	return Kind.GUARD


# What an object use changes: the doors in a lever's group, or the tiles on the map a lit
# Brazier holds at Dusk (DarknessState); empty for a container. Row-major order.
static func _object_area(state: CombatState, used: MapState.ObjectState) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if used == null:
		return tiles
	match used.kind:
		MapLayout.ObjectKind.LEVER:
			for door: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.DOOR):
				if door.group_id == used.group_id:
					tiles.append(door.tile)
		MapLayout.ObjectKind.BRAZIER:
			var light: Vector2i = Vector2i(0, DarknessState.BRAZIER_RADIUS)
			for tile: Vector2i in DangerZone.tiles_within(used.tile, light):
				if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					tiles.append(tile)
	tiles.sort_custom(EnemyPlan.tile_precedes)
	return tiles


# The tiles of every splash area the plan's forecast fired: each of the enemy's activated effects
# that deals splash to an Area or takes Block or Stance across one (_area_hit_by), centered where
# the enemy acts from (the owner, or the fact's actor on its Hit dealt) or on its target (the
# fact's target, the command's target), less the target's tile where the Area spares the fact's
# target (Cleave); and the blast of each powder keg the forecast breaks.
static func _splash_area(engine: EffectEngine, chosen: EnemyPlan) -> Array[Vector2i]:
	var state: CombatState = engine.state
	var covered: Dictionary[Vector2i, bool] = {}
	for outcome: CombatForecast.UnitOutcome in chosen.forecast.units:
		var keg: MapState.ObjectState = state.map.object(outcome.unit_id)
		if outcome.is_defeated and keg != null and keg.kind == MapLayout.ObjectKind.POWDER_KEG:
			for tile: Vector2i in MapObjects.KEG_BLAST.tiles(keg.tile):
				if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					covered[tile] = true
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
			var area: Area = _area_hit_by(operation)
			if area == null or area.shape == null:
				continue
			var struck: Vector2i = state.tile_of(chosen.target_id)
			var center: Vector2i = chosen.tile
			if area.center != Area.Center.OWNER and area.center != Area.Center.FACT_ACTOR:
				center = struck
			for tile: Vector2i in area.shape.tiles(center):
				if area.is_fact_target_excluded and tile == struck:
					continue
				if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					covered[tile] = true
	var tiles: Array[Vector2i] = []
	tiles.assign(covered.keys())
	tiles.sort_custom(EnemyPlan.tile_precedes)
	return tiles


# The Area operation hurts: splash dealt to one (Cleave, Trample), or a loss of Block or Stance
# across one (the Hexer's Curse); null for anything else.
static func _area_hit_by(operation: EffectOperation) -> Area:
	var splash: DealSplash = operation as DealSplash
	if splash != null:
		return splash.target as Area
	var gain: GainResource = operation as GainResource
	if gain == null or gain.pool == GainResource.Pool.HP:
		return null
	var amount: Constant = gain.amount as Constant
	if amount == null or amount.value >= 0.0:
		return null
	return gain.target as Area
