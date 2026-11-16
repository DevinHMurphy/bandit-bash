# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     gain_resource.gd
# Author:
# Created:  October 26, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name GainResource
extends EffectOperation
## Gives units HP, Block or Stance: "gain 3 Block", "heal 10", "remove 2 Block from a random one of
## your units".
##
## Queued. Every Block gain goes through the engine's one Block-gain path, which opens the Block
## gained inline window; a negative Block amount is a loss and opens none. Amounts stay exact and
## round half up when applied, never below 0.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The resource gained. Saved as an int: [b]append only[/b].
enum Pool {
	## Healing, capped at maximum HP; the excess is overheal.
	HP = 0,
	## Block, which absorbs damage before HP.
	BLOCK = 1,
	## Stance, up to its maximum unless [member can_exceed_maximum].
	STANCE = 2,
}

## Effect-text names of the pools.
const POOL_TEXT: Dictionary[int, String] = {
	Pool.HP: "HP",
	Pool.BLOCK: "Block",
	Pool.STANCE: "Stance",
}

## The resource gained.
@export var pool: Pool = Pool.BLOCK

## Who gains it. [b]Null:[/b] the effect's owner.
@export var target: TargetSelector = null

## How much. A negative amount is a loss. [b]Null:[/b] a content error (gains nothing).
@export var amount: ValueSource = null

## Stance only: the gain may go past the unit's Stance maximum (Triage). The extra lasts until the
## unit's side's next Phase Start, which sets Stance to its maximum; hits take it first.[br]
## [b]Off:[/b] the gain stops at the maximum (and never lowers Stance already above it).
## Ignored for HP and Block and for a loss.
@export var can_exceed_maximum: bool = false


func describe() -> String:
	return describe_for_trigger(EffectTerms.Trigger.ALWAYS)


## The text, with a share of the triggering fact named for [param trigger]
## ([method PercentOfFact.describe_for_trigger]): Dark Sword's "heal for 50% of the damage dealt
## to HP". A heal of a worked-out amount reads "heal for …" on the owner, and
## "heal <who> for HP equal to …" on another unit.
func describe_for_trigger(trigger: EffectTerms.Trigger) -> String:
	var pool_name: String = POOL_TEXT[pool]
	var to_owner: bool = target == null or target.is_owner()
	var who: String = "" if to_owner else target.describe()
	var constant: Constant = amount as Constant
	if constant != null and constant.value < 0.0:
		var lost: String = EffectTerms.format_number(-constant.value)
		if to_owner:
			return "lose %s %s" % [lost, pool_name]
		return "remove %s %s from %s" % [lost, pool_name, who]

	var how_much: String = "?" if amount == null else amount.describe()
	var share: PercentOfFact = amount as PercentOfFact
	if share != null:
		how_much = share.describe_for_trigger(trigger)
	if pool == Pool.HP:
		if constant == null and to_owner:
			return "heal for %s" % [how_much]
		var healing: String = how_much if constant != null else "HP equal to %s" % [how_much]
		if to_owner:
			return "heal %s" % [healing]
		return "heal %s for %s" % [who, healing]
	var gained: String = "%s %s" % [how_much, pool_name]
	if constant == null:
		gained = "%s equal to %s" % [pool_name, how_much]
	if pool == Pool.STANCE and can_exceed_maximum:
		# ASSUMPTION: the wording; no design doc gives Triage's text for going past the maximum.
		gained += ", even above its maximum"
	if to_owner:
		return "gain %s" % [gained]
	return "give %s %s" % [who, gained]


## Picks the targets, then evaluates the amount once, and gives it to each through the engine's
## paths: [method EffectEngine.heal], [method EffectEngine.gain_block] (or
## [method EffectEngine.lose_block] for a negative amount) and [method EffectEngine.change_stance].
func apply(ctx: EffectContext) -> void:
	if amount == null:
		ctx.engine.diagnostics.append("GainResource: %s has no amount" % [ctx.instance.instance_id])
		return
	var targets: PackedStringArray = _targets(target, ctx)
	var how_much: float = amount.evaluate(ctx)
	var giver: String = ctx.owner_unit_id()
	var effect_id: String = ctx.instance.instance_id
	for unit_id: String in targets:
		match pool:
			Pool.HP:
				ctx.engine.heal(unit_id, how_much, giver, effect_id)
			Pool.BLOCK:
				if how_much < 0.0:
					ctx.engine.lose_block(unit_id, -how_much, effect_id)
				else:
					ctx.engine.gain_block(unit_id, how_much, giver, effect_id)
			Pool.STANCE:
				ctx.engine.change_stance(unit_id, how_much, giver, effect_id, can_exceed_maximum)
