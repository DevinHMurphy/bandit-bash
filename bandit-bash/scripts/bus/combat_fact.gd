# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_fact.gd
# Author:
# Created:  October 26, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name CombatFact
extends RefCounted
## One thing that happened in a combat session, in the past tense.
##
## Rules code creates facts while it resolves a command; effects react to them through the effect
## engine, and presentation plays them afterwards on every peer through [CombatBus]. Every trigger
## in effect-triggers.md is a [enum Kind]; state facts (moves, spawns, counters) exist too, so a
## client mirror and the presentation can follow along.[br]
## [b]Paired triggers are two facts:[/b] a hit emits [constant HIT_DEALT], then
## [constant HIT_TAKEN]. [member actor_id] is always the unit the kind is about, which is the
## unit an effect's scope tests; [member target_id] is the other party.[br]
## Facts carry ids, never objects or Resources, so they can cross the network
## ([method to_wire]). Ids are opaque: never parse them; use the session's describe for text.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md

## What happened. Sent over the network as an int: [b]append only[/b], with explicit values.
enum Kind {
	## [member side]'s phase began, after its Block and Stance refresh; [member amount] is the turn,
	## which rises at the player Phase Start.
	PHASE_START = 0,
	## The actor's turn began, in its side's Phase Start window, before the side gets control.
	UNIT_TURN_START = 1,
	## An exchange began, before the first attack. One fact per participant; target: its opponent.
	BEFORE_COMBAT = 2,
	## An exchange resolved. One fact per surviving participant; target: its opponent.
	AFTER_COMBAT = 3,
	## The actor's turn ended, in its side's Phase End window, whether it acted or not.
	UNIT_TURN_END = 4,
	## [member side]'s phase ended.
	PHASE_END = 5,
	## The actor attacked the target, hit or miss. Each attack counts, so AtkX 2 is two facts.
	ATTACK_MADE = 6,
	## The actor's attack hit the target, even if the damage was fully countered or absorbed.
	HIT_DEALT = 7,
	## The actor was hit by the target's attack, even if the damage was fully countered or absorbed.
	HIT_TAKEN = 8,
	## The actor's attack missed the target.
	MISSED = 9,
	## The actor dodged the target's attack.
	DODGED = 10,
	## Real damage from the actor got through to the target's Block or HP.
	DAMAGE_DEALT = 11,
	## Real damage from the target got through to the actor's Block or HP.
	DAMAGE_TAKEN = 12,
	## The actor's hit on the target was a critical hit.
	CRIT_DEALT = 13,
	## The actor took a critical hit from the target.
	CRIT_TAKEN = 14,
	## The actor's Stance reached 0.
	EXPOSED = 15,
	## The actor defeated the target.
	DEFEATED_AN_ENEMY = 16,
	## The actor was defeated; the target is the unit that defeated it, if a unit did.
	DEFEATED = 17,
	## The actor restored the target's HP, overhealing included.
	HEALED_AN_ALLY = 18,
	## The actor regained HP, overhealing included; the target is the healer, if a unit healed it.
	HEALED = 19,
	## The actor used a staff (heal or Block) on the target.
	USED_STAFF_ON_ALLY = 20,
	## The actor took darkness damage at its side's Phase End. Not an attack.
	DARKNESS_DAMAGE_TAKEN = 21,
	## The actor used the map object named by the target, at [member tile]; [member item_id] is
	## the key or lockpick it opened a lock with, if any.
	OBJECT_USED = 22,
	## The actor shoved the target.
	SHOVED_A_UNIT = 23,
	## The actor was shoved by the target.
	SHOVED = 24,
	## The actor gained Block; the target is the unit that gave it, if another unit did.
	BLOCK_GAINED = 25,
	## The actor moved; [member tile] is where it stopped.
	UNIT_MOVED = 26,
	## The actor appeared on the map at [member tile].
	UNIT_SPAWNED = 27,
	## This session's combat ended; [member side] is the side that won it, [member amount] the
	## turn it ended on, and [member key] the turns a Survive or Defend map was won early
	## ([Objectives]).
	COMBAT_ENDED = 28,
	## The darkness advanced.
	DARKNESS_ADVANCED = 29,
	## The map object named by the actor changed state at [member tile]: [member key] is the
	## [enum MapObjects.Change]; the target is the unit or object that caused it, if one did.
	OBJECT_STATE_CHANGED = 30,
	## The effect named by [member source_effect_id] fired.
	EFFECT_ACTIVATED = 31,
	## A counter of the effect named by [member source_effect_id] changed: [member amount] is the
	## new count, [member key] its [enum EffectTerms.Lane].
	COUNTER_CHANGED = 32,
	## The actor gained a timed modifier from [member source_effect_id].
	MODIFIER_GAINED = 33,
	## A timed modifier from [member source_effect_id] on the actor expired.
	MODIFIER_EXPIRED = 34,
	## The actor's Block was cleared to 0 and its Stance set to its maximum, at its side's Phase
	## Start. Not a Block gain or loss.
	BLOCK_STANCE_REFRESHED = 35,
	## The actor's Stance changed outside a refresh (a hit, Shatter, an effect), never below 0.
	STANCE_CHANGED = 36,
	## The actor used the Pouch item [member item_id] on the target (itself or an adjacent ally).
	ITEM_USED = 37,
	## The actor swapped its Weapon slot and stowed weapon; [member item_id] is the weapon now in
	## the Weapon slot.
	WEAPON_SWAPPED = 38,
	## The rune [member item_id] was cast on the target at [member tile]. A rune has no owner, so
	## the actor is empty and [member amount] is the casting seat.
	RUNE_USED = 39,
	## The actor waited, ending its turn.
	UNIT_WAITED = 40,
	## The actor lost Block outside damage (Haunted's "loses 2 Block"). No inline window.
	BLOCK_LOST = 41,
	## The actor's base stat [member key] (an [enum CombatValue.Stat]) changed permanently by
	## [member amount], such as a stat booster's +1 MGT.
	STAT_CHANGED = 42,
	## The actor's growth for base stat [member key] (an [enum CombatValue.Stat]) changed by
	## [member amount] percentage points, such as an eaten ingredient's +5% RES growth. Changes no
	## value in battle; the battle-end bridge writes it to the roster.
	GROWTH_CHANGED = 43,
}

## What produced an amount. Sent over the network as an int: [b]append only[/b].
enum Source {
	## Not applicable, or no amount.
	NONE = 0,
	## An attack in an exchange.
	ATTACK = 1,
	## Splash: flat area damage with no hit roll, Mitigation or crit.
	SPLASH = 2,
	## A shoved unit running into another.
	BUMP = 3,
	## The darkness.
	DARKNESS = 4,
	## An effect's operation, named by [member source_effect_id].
	EFFECT = 5,
	## A spiked wall a shoved unit was pushed into.
	SPIKE = 6,
}

## Whose phase a [constant PHASE_START] or [constant PHASE_END] fact belongs to, or who won a
## [constant COMBAT_ENDED]. Sent over the network as an int: [b]append only[/b].
enum CombatSide {
	## Not a phase fact or a combat end.
	NONE = 0,
	## The player side: every seat's units on this map.
	PLAYER = 1,
	## The enemy side.
	ENEMY = 2,
}

## The damage type of an attack, which picks the defender's mitigation stat (game-vision.md
## Damage). Sent over the network as an int: [b]append only[/b].
enum DamageType {
	## Not damage, or no type.
	NONE = 0,
	## Mitigated by Defense.
	PHYSICAL = 1,
	## Mitigated by Resistance.
	MAGIC = 2,
	## Mitigated by half of Defense plus Resistance.
	SPLIT = 3,
	## Skips the Mitigation stage.
	PURE = 4,
}

## [member tile] when a fact has no tile. Map tiles never have negative coordinates (a map rule,
## event bus plan question 37), so it names no real tile.
const NO_TILE: Vector2i = Vector2i(-1, -1)

# Slot types of the wire array, in to_wire() order: i = int, s = String.
const WIRE_PATTERN: String = "iiissiiiiisiiiisi"

# Largest integer a JSON number (a double) holds exactly, 2^53. A wire array that went through JSON
# arrives with float numbers; anything beyond this lost precision on the way.
const MAX_EXACT_JSON_INT: float = 9007199254740992.0

# Kinds whose actor receives the action from the target; the log line draws them as "<-".
const RECEIVED_KINDS: Array[Kind] = [
	Kind.HIT_TAKEN,
	Kind.DODGED,
	Kind.DAMAGE_TAKEN,
	Kind.CRIT_TAKEN,
	Kind.DEFEATED,
	Kind.HEALED,
	Kind.SHOVED,
	Kind.BLOCK_GAINED,
]

## What happened.
var kind: Kind = Kind.PHASE_START

## Position in its session's fact log. 0 until the session assigns it.
var seq: int = 0

## The session (one per map) this fact happened in.
var session_id: int = 0

## Instance id of the unit or object the kind is about (see [enum Kind]). Empty when none.
var actor_id: String = ""

## Instance id of the other party (see [enum Kind]). Empty when none.
var target_id: String = ""

## The fact's main quantity: damage, healing, Block, a counter value or a turn. 0 when none.
var amount: int = 0

## The part of [member amount] that reached HP. For healing, [member amount] minus this is the
## overheal.
var hp_amount: int = 0

## The part of [member amount] that Block absorbed.
var block_amount: int = 0

## Damage type of the attack, for damage kinds.
var damage_type: DamageType = DamageType.NONE

## What produced [member amount].
var source: Source = Source.NONE

## Instance id of the effect that caused this fact, or the effect a [constant EFFECT_ACTIVATED],
## [constant COUNTER_CHANGED] or modifier fact is about. Empty when no effect is involved.
var source_effect_id: String = ""

## The tile the fact happened on, or [constant NO_TILE].
var tile: Vector2i = NO_TILE

## Bit set of extra details. No bits are defined yet.
var flags: int = 0

## Whose phase a phase fact belongs to, or the side that won a [constant COMBAT_ENDED];
## [constant CombatSide.NONE] on every other kind.
var side: CombatSide = CombatSide.NONE

## Instance id of the item, weapon or rune the fact is about ([constant ITEM_USED],
## [constant WEAPON_SWAPPED], [constant RUNE_USED]). Empty on every other kind.
var item_id: String = ""

## A small number whose meaning depends on the kind: the [enum EffectTerms.Lane] of a
## [constant COUNTER_CHANGED], the [enum CombatValue.Stat] of a [constant STAT_CHANGED], the turns
## won early of a [constant COMBAT_ENDED], the [enum MapObjects.Change] of an
## [constant OBJECT_STATE_CHANGED]. 0 on every other kind.
var key: int = 0


func _init(fact_kind: Kind, fact_actor_id: String = "", fact_target_id: String = "") -> void:
	kind = fact_kind
	actor_id = fact_actor_id
	target_id = fact_target_id


## This fact as an Array of primitives, for RPCs and repro dumps. [method from_wire] reverses it.
##
## The slot order is a network contract: append new fields at the end only.
func to_wire() -> Array:
	return [
		kind,
		seq,
		session_id,
		actor_id,
		target_id,
		amount,
		hp_amount,
		block_amount,
		damage_type,
		source,
		source_effect_id,
		tile.x,
		tile.y,
		flags,
		side,
		item_id,
		key,
	]


## One log line in the shape the event bus plan documents, without NetLog's prefix:[br]
## [code]s0#143 HIT_TAKEN unit:57 (Hakkapel) <- enemy:61 (Brute) amount 6 (hp 4, block 2) source
## attack[/code], or [code]s0#1 PHASE_START side player amount 3[/code]
##
## Empty fields are left out, and amounts print only when one is non-zero. [member key] prints as
## "lane N", "stat N" or "change N" on the kinds that use it.
## [param describe]: turns an id into display text (the session's describe); when invalid, ids
## print bare.
func to_log_line(describe: Callable = Callable()) -> String:
	var parts: PackedStringArray = ["s%d#%d %s" % [session_id, seq, _kind_name()]]
	if not actor_id.is_empty():
		parts.append(_describe_id(actor_id, describe))
	if not target_id.is_empty():
		parts.append("<-" if RECEIVED_KINDS.has(kind) else "->")
		parts.append(_describe_id(target_id, describe))
	if side != CombatSide.NONE:
		parts.append("side %s" % [(CombatSide.find_key(side) as String).to_lower()])
	if not item_id.is_empty():
		parts.append("item %s" % [_describe_id(item_id, describe)])
	# Numbers, not names: facts stay independent of the effect classes that own these enums.
	if kind == Kind.COUNTER_CHANGED:
		parts.append("lane %d" % [key])
	elif kind == Kind.STAT_CHANGED or kind == Kind.GROWTH_CHANGED:
		parts.append("stat %d" % [key])
	elif kind == Kind.OBJECT_STATE_CHANGED:
		parts.append("change %d" % [key])
	if amount != 0 or hp_amount != 0 or block_amount != 0:
		parts.append("amount %d" % [amount])
		if hp_amount != 0 or block_amount != 0:
			parts.append("(hp %d, block %d)" % [hp_amount, block_amount])
	if source != Source.NONE:
		parts.append("source %s" % [(Source.find_key(source) as String).to_lower()])
	if damage_type != DamageType.NONE:
		parts.append("type %s" % [(DamageType.find_key(damage_type) as String).to_lower()])
	if not source_effect_id.is_empty():
		parts.append("effect %s" % [_describe_id(source_effect_id, describe)])
	if tile != NO_TILE:
		parts.append("tile %s" % [tile])
	if flags != 0:
		parts.append("flags 0x%x" % [flags])
	return " ".join(parts)


func _kind_name() -> String:
	var key: Variant = Kind.find_key(kind)
	return "KIND_%d" % [kind] if key == null else (key as String)


func _describe_id(id: String, describe: Callable) -> String:
	if not describe.is_valid():
		return id
	var text: String = describe.call(id)
	return text


## Rebuilds a fact from [method to_wire] output, including after a trip through JSON.
##
## Returns [code]null[/code] (with a warning) when [param data] has the wrong length, a wrong
## type, a non-whole number, a negative [member seq] or [member session_id], or an unknown enum
## value.
static func from_wire(data: Array) -> CombatFact:
	var values: Array = _normalize_wire(data, WIRE_PATTERN)
	if values.is_empty():
		push_warning("CombatFact: malformed wire data - %s" % [data])
		return null

	var kind_value: int = values[0]
	var type_value: int = values[8]
	var source_value: int = values[9]
	var seq_value: int = values[1]
	var session_value: int = values[2]
	var side_value: int = values[14]
	if (
			not Kind.values().has(kind_value)
			or not DamageType.values().has(type_value)
			or not Source.values().has(source_value)
			or not CombatSide.values().has(side_value)
			or seq_value < 0
			or session_value < 0
	):
		push_warning("CombatFact: wire data out of range - %s" % [data])
		return null

	var fact: CombatFact = CombatFact.new(
			kind_value as Kind, values[3] as String, values[4] as String
	)
	fact.seq = seq_value
	fact.session_id = session_value
	fact.amount = values[5]
	fact.hp_amount = values[6]
	fact.block_amount = values[7]
	fact.damage_type = type_value as DamageType
	fact.source = source_value as Source
	fact.source_effect_id = values[10]
	fact.tile = Vector2i(values[11] as int, values[12] as int)
	fact.flags = values[13]
	fact.side = side_value as CombatSide
	fact.item_id = values[15]
	fact.key = values[16]
	return fact


# Checks data against pattern and converts whole floats (from JSON) to int. Returns [] if invalid.
static func _normalize_wire(data: Array, pattern: String) -> Array:
	if data.size() != pattern.length():
		return []
	var values: Array = []
	for i: int in data.size():
		var value: Variant = data[i]
		if pattern[i] == "s":
			if typeof(value) != TYPE_STRING:
				return []
			values.append(value)
		elif typeof(value) == TYPE_INT:
			values.append(value)
		elif typeof(value) == TYPE_FLOAT:
			var number: float = value
			if number != floorf(number) or absf(number) > MAX_EXACT_JSON_INT:
				return []
			values.append(int(number))
		else:
			return []
	return values
