# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_context.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name EffectContext
extends RefCounted
## The action in flight, as effects see it: "that attack", "that hit", "that heal", "that Block
## gain".
##
## Rules code creates one per attack (kept from Attack made through the hit's stage 8), per heal and
## per Block gain, fills the attack fields, and passes it to every inline window and value query of
## that action. Inline operations write their changes here: flags that only turn on, and "that"
## modifiers that join every query made with this context. The engine sets [member instance],
## [member fact] and [member subject_id] while it tests and applies each effect, and restores them
## afterwards.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## The key of "that" modifiers on the amount itself (that heal, that Block gain, that darkness
## damage). Outside every value key class's block, so no stat sheet has it.
const AMOUNT_KEY: int = -1

## The key of "that" modifiers on the hit's extra Stance loss, added at stage 8 (Breaker).
const EXTRA_STANCE_LOSS_KEY: int = -2

## The engine evaluating effects on this context.
var engine: EffectEngine = null

## The effect being tested or applied; null outside the engine's evaluation.
var instance: EffectInstance = null

## The triggering combat fact; null for a value query or a command activation (a rune).
var fact: CombatFact = null

## The triggering campaign fact, on a campaign engine; null otherwise.
var campaign_fact: CampaignFact = null

## The unit "this unit" means in conditions: the fact's actor (the unit the trigger is about), the
## queried unit for a value query, or the owner's unit when the fact has no actor.
var subject_id: String = ""

## Whether the engine is answering a value query: counters and chances never pass and never change.
var is_query: bool = false

## The unit making this attack; for Before and After Combat, the exchange's initiator.
var attacker_id: String = ""

## The unit this attack targets; for Before and After Combat, the exchange's defender.
var defender_id: String = ""

## The unit that started the current exchange. Empty outside an exchange.
var initiator_id: String = ""

## Instance id of the attacker's weapon.
var weapon_id: String = ""

## The tile the attacker attacks from.
var origin_tile: Vector2i = CombatFact.NO_TILE

## Tiles between attacker and defender.
var distance: int = 0

## Position of this attack within the exchange, from 0; -1 outside an attack.
var attack_index: int = -1

## Whether the defender's Stance was 0 before this hit (crits need it).
var defender_was_exposed: bool = false

## Whether this hit is a critical hit.
var is_crit: bool = false

## The attacker's weapon-triangle result against the defender.
var matchup: WhileMatchupCondition.Matchup = WhileMatchupCondition.Matchup.STANDOFF

## The unit or object a command (a rune, a Pouch item) targets; empty otherwise.
var command_target_id: String = ""

## Where the effect's own unit stood when its reaction was queued, so a queued splash lands from
## that tile even if the unit was defeated since; [constant CombatFact.NO_TILE] outside a reaction.
var owner_tile: Vector2i = CombatFact.NO_TILE

## Bit set of [enum ModifyThat.Flag] turned on by inline operations.
var flags: int = 0

# "That" modifiers from inline operations: value keys, AMOUNT_KEY and EXTRA_STANCE_LOSS_KEY.
var _that_modifiers: Array[Modifier] = []


## Whether an inline operation turned [param flag] on.
func has_flag(flag: ModifyThat.Flag) -> bool:
	return flags & (1 << flag) != 0


## Turns [param flag] on. Flags never turn off, so the order of inline operations can't matter.
func set_flag(flag: ModifyThat.Flag) -> void:
	flags |= 1 << flag


## Adds a "that" modifier. A value-key modifier joins every query made with this context.
func add_that_modifier(modifier: Modifier) -> void:
	_that_modifiers.append(modifier)


## The "that" modifiers of [param key], in the order added. A copy.
func that_modifiers(key: int) -> Array[Modifier]:
	var list: Array[Modifier] = []
	for modifier: Modifier in _that_modifiers:
		if modifier.key == key:
			list.append(modifier)
	return list


## [param base] shaped by the "that" modifiers on the amount, exact. The caller rounds it once.
func shaped_amount(base: float, base_label: String = "") -> ValueBreakdown:
	return ValueBreakdown.compute(AMOUNT_KEY, base, base_label, that_modifiers(AMOUNT_KEY))


## The hit's extra Stance loss from inline operations, exact.
func extra_stance_loss() -> float:
	return ValueBreakdown.compute(
			EXTRA_STANCE_LOSS_KEY, 0.0, "", that_modifiers(EXTRA_STANCE_LOSS_KEY)
	).total


## Whether the context belongs to an exchange.
func in_exchange() -> bool:
	return not initiator_id.is_empty()


## The other unit in the attack or exchange; empty when [param unit_id] isn't in it.
func opponent_of(unit_id: String) -> String:
	if unit_id.is_empty():
		return ""
	if unit_id == attacker_id:
		return defender_id
	if unit_id == defender_id:
		return attacker_id
	return ""


## [param unit_id]'s [enum WhileRoleCondition.Role] in the exchange, or -1 when it isn't in one.
func role_of(unit_id: String) -> int:
	if not in_exchange() or opponent_of(unit_id).is_empty():
		return -1
	if unit_id == initiator_id:
		return WhileRoleCondition.Role.INITIATOR
	return WhileRoleCondition.Role.DEFENDER


## [param unit_id]'s triangle result, or -1 when it isn't the attacker or the defender.
func matchup_of(unit_id: String) -> int:
	if unit_id.is_empty():
		return -1
	if unit_id == attacker_id:
		return matchup
	if unit_id != defender_id:
		return -1
	match matchup:
		WhileMatchupCondition.Matchup.ADVANTAGE:
			return WhileMatchupCondition.Matchup.DISADVANTAGE
		WhileMatchupCondition.Matchup.DISADVANTAGE:
			return WhileMatchupCondition.Matchup.ADVANTAGE
	return WhileMatchupCondition.Matchup.STANDOFF


## The owner's unit of [member instance]: the unit holding it, or empty.
func owner_unit_id() -> String:
	return "" if instance == null else instance.owner.holder_id


## A context for a queued reaction to this one: the same action's identity (attack fields,
## command target), with no flags or "that" modifiers, since a queued operation is a new action.
func copy_for_reaction() -> EffectContext:
	var copy: EffectContext = EffectContext.new()
	copy.engine = engine
	copy.instance = instance
	copy.fact = fact
	copy.campaign_fact = campaign_fact
	copy.subject_id = subject_id
	copy.attacker_id = attacker_id
	copy.defender_id = defender_id
	copy.initiator_id = initiator_id
	copy.weapon_id = weapon_id
	copy.origin_tile = origin_tile
	copy.distance = distance
	copy.attack_index = attack_index
	copy.defender_was_exposed = defender_was_exposed
	copy.is_crit = is_crit
	copy.matchup = matchup
	copy.command_target_id = command_target_id
	copy.owner_tile = owner_tile
	return copy
