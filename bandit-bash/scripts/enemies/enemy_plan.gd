# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_plan.gd
# Author:
# Created:  October 30, 2026
# Modified: October 30, 2026
# ==============================================================================

class_name EnemyPlan
extends RefCounted
## One enemy's turn as the AI rates it: where it ends, what it does there, to whom, and the
## numbers each rating step compares ([EnemyAI]; enemies and AI plan, question 7).
##
## [method is_better_than] compares two plans step by step in [enum Step] order and stops at the
## first difference, so [member decided_by] names the step a player can read the choice from: the
## kill, the target rule, the damage share, the terrain. Every key is a number the forecast panel
## or the map shows. The target rule only compares one enemy's own options: two enemies' rules
## measure different things, so the turn order ([method EnemyAI.next_plan]) skips that step.[br]
## Plain data, built by [EnemyAI] only; [method to_command] gives the turn it plans.
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md

## What the plan does, which also orders plans of different kinds: attacks first, then staves,
## then moves, then a plain Wait ([constant Step.ACTION]).
enum Kind {
	## Attacks [member target_id] from [member tile].
	ATTACK = 0,
	## Uses its heal staff on [member target_id] from [member tile].
	STAFF = 1,
	## Walks toward [member target_id], the nearest foe by path cost, and waits.
	ADVANCE = 2,
	## Support with nobody to heal: walks to the tile fewest player units can attack, near its
	## allies, and waits.
	REGROUP = 3,
	## Waits where it stands: no option, or no enemy class to play.
	WAIT = 4,
}

## The rating steps, in the order they are compared. Each names what the player sees decide it.
enum Step {
	## The plan had nothing to beat.
	ONLY_OPTION = 0,
	## (a) It defeats its target if its hits land.
	KILL = 1,
	## (a) Among kills, the higher chance that those hits land.
	KILL_CHANCE = 2,
	## Its [enum Kind]: attacks before staves before moves before Wait.
	ACTION = 3,
	## (b) The behavior's target rule. Same enemy only.
	TARGET_RULE = 4,
	## (c) Expected damage as a share of the target's maximum HP.
	VALUE = 5,
	## Support: fewer player units can attack the end tile next phase.
	SAFETY = 6,
	## Support regrouping: nearer its allies.
	PACK = 7,
	## Advancing: less path cost left to a tile it could attack its foe from.
	PROGRESS = 8,
	## (d) The end tile's terrain: avoid ÷ 50 + DEF + RES.
	TERRAIN = 9,
	## (e) Less path cost to the end tile.
	PATH_COST = 10,
	## (e) The end tile first in row-major order (row, then column).
	TILE_ORDER = 11,
	## (e) The target's id first in string order.
	TARGET_ORDER = 12,
	## The weapon in hand before the stowed one.
	WEAPON_ORDER = 13,
	## The acting enemy's id first in string order; two enemies never end on one tile, so this
	## only separates plans built on different boards.
	ACTOR_ORDER = 14,
}

## The enemy whose turn it is.
var actor_id: String = ""

## What it does.
var kind: Kind = Kind.WAIT

## The behavior it played, after the darkness switch ([method EnemyAI.decide]).
var behavior: EnemyClassDefinition.Behavior = EnemyClassDefinition.Behavior.AGGRESSIVE

## The target rule it played, from [constant ContentIds.TARGET_RULES]; empty for an enemy with no
## enemy class.
var target_rule_id: String = ""

## The unit it attacks, heals or advances on; the user itself for a range-0 staff; empty for
## [constant Kind.REGROUP] and [constant Kind.WAIT].
var target_id: String = ""

## The weapon an attack names: empty for the one in hand, the stowed one for a free Sidearm swap.
var weapon_id: String = ""

## The tiles it walks, starting on its own tile ([member UnitTurnCommand.path]); empty when it
## stays.
var path: Array[Vector2i] = []

## The tile it ends on and acts from.
var tile: Vector2i = CombatFact.NO_TILE

## Movement cost of [member path].
var path_cost: int = 0

## Whether [member tile] is flooded by the darkness.
var is_flooded: bool = false

## (a) Whether its target is defeated in the forecast, where every hit lands.
var is_kill: bool = false

## (a) The chance every one of its attacks in that forecast lands; 0 for no kill.
var kill_chance: float = 0.0

## (b) The target rule's measure of [member target_id]; lower is better. Path cost to the
## nearest tile it attacks the foe from, the foe's DEF, or minus the ally's missing HP.
var target_rule_key: float = 0.0

## (c) Expected damage ÷ the target's maximum HP, capped at 1, × 100, or × 150 when the enemy
## takes no damage back ([constant EnemyAI.VALUE_WEIGHT]); 0 for anything but an attack.
var value: float = 0.0

## Support: player units that could attack [member tile] next phase; 0 for other behaviors.
var safety: int = 0

## Support regrouping: tile distance from [member tile] to every ally, summed; 0 otherwise.
var pack: int = 0

## Advancing: path cost left from [member tile] to a tile it could attack its foe from.
var progress: int = 0

## (d) The terrain of [member tile]: avoid ÷ 50 + DEF + RES ([method EnemyAI.terrain_rating]).
var terrain: float = 0.0

## 0 for the weapon in hand, 1 for the stowed one.
var weapon_order: int = 0

## The step that made it beat the enemy's best option on another target or of another kind: why
## this target. When every option shares both, its next-best option: why this tile.
var decided_by: Step = Step.ONLY_OPTION

## The preview it was rated on ([CombatForecast]); null for a move or a Wait.
var forecast: CombatForecast.Forecast = null


## The turn this plan takes, as the enemy side sends it: seat -1.
func to_command() -> UnitTurnCommand:
	var action: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT
	var command_target: String = ""
	if kind == Kind.ATTACK:
		action = UnitTurnCommand.Action.ATTACK
		command_target = target_id
	elif kind == Kind.STAFF:
		action = UnitTurnCommand.Action.STAFF
		# A range-0 staff names no target; the command fills in the user.
		command_target = "" if target_id == actor_id else target_id
	var command: UnitTurnCommand = UnitTurnCommand.new(-1, actor_id, action, command_target, path)
	command.weapon_id = weapon_id
	return command


## Whether this plan rates above [param other], step by step in [enum Step] order. The target
## rule counts only between plans of the same enemy.
func is_better_than(other: EnemyPlan) -> bool:
	return _compare(other) > 0


## The first step at which this plan and [param other] differ; [constant Step.ONLY_OPTION] when
## they rate equal or [param other] is null.
func deciding_step(other: EnemyPlan) -> Step:
	if other == null:
		return Step.ONLY_OPTION
	return absi(_compare(other)) as Step


# The first differing step, positive when this plan wins it and negative when other does; 0 when
# every step ties.
func _compare(other: EnemyPlan) -> int:
	if is_kill != other.is_kill:
		return Step.KILL if is_kill else -Step.KILL
	if kill_chance != other.kill_chance:
		return Step.KILL_CHANCE if kill_chance > other.kill_chance else -Step.KILL_CHANCE
	var rank: int = _kind_rank(kind)
	var other_rank: int = _kind_rank(other.kind)
	if rank != other_rank:
		return Step.ACTION if rank < other_rank else -Step.ACTION
	if actor_id == other.actor_id and target_rule_key != other.target_rule_key:
		return (
				Step.TARGET_RULE if target_rule_key < other.target_rule_key
				else -Step.TARGET_RULE
		)
	if value != other.value:
		return Step.VALUE if value > other.value else -Step.VALUE
	if safety != other.safety:
		return Step.SAFETY if safety < other.safety else -Step.SAFETY
	if pack != other.pack:
		return Step.PACK if pack < other.pack else -Step.PACK
	if progress != other.progress:
		return Step.PROGRESS if progress < other.progress else -Step.PROGRESS
	if terrain != other.terrain:
		return Step.TERRAIN if terrain > other.terrain else -Step.TERRAIN
	if path_cost != other.path_cost:
		return Step.PATH_COST if path_cost < other.path_cost else -Step.PATH_COST
	if tile != other.tile:
		return Step.TILE_ORDER if tile_precedes(tile, other.tile) else -Step.TILE_ORDER
	if target_id != other.target_id:
		return Step.TARGET_ORDER if target_id < other.target_id else -Step.TARGET_ORDER
	if weapon_order != other.weapon_order:
		return Step.WEAPON_ORDER if weapon_order < other.weapon_order else -Step.WEAPON_ORDER
	if actor_id != other.actor_id:
		return Step.ACTOR_ORDER if actor_id < other.actor_id else -Step.ACTOR_ORDER
	return 0


## The tile order of (e): row, then column.
static func tile_precedes(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


# Advancing and regrouping are both moves and rank together.
static func _kind_rank(of_kind: Kind) -> int:
	match of_kind:
		Kind.ATTACK:
			return 0
		Kind.STAFF:
			return 1
		Kind.ADVANCE, Kind.REGROUP:
			return 2
	return 3
