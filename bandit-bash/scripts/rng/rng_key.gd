# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_key.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name RngKey
extends RefCounted
## The name of one random stream: what it is for and where in the run it is used.
##
## A stream's seed comes from the run seed and its key alone ([method derive_seed]), never from
## earlier draws, so a new purpose, an extra draw in one system or a different node order can't
## shift another stream. [member floor_number], [member node], [member seat] and [member index] are
## [code]-1[/code] when the key doesn't use them: run-level streams have no floor or node, shared
## streams have no seat.[br]
## The mixer is SplitMix64 written for GDScript's signed 64-bit [int], which must never overflow
## and can't shift a negative value: products are built from 16-bit limbs (each partial product
## stays below 2^32), sums from 32-bit halves, and right shifts clear the sign bit first.
## [method @GlobalScope.hash] is never used: it isn't guaranteed stable across engine versions.
##
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

## What a stream is for. Append-only with explicit values: a value is part of every seed and save
## key that uses it, so renumbering or reusing one changes saved runs. Names may change freely.
enum RngPurpose {
	## The campaign map graph. Run key, shared.
	MAP_GENERATION = 0,
	## Drawing the next node from route votes. Floor key, shared.
	ROUTE_DRAW = 1,
	## What a [code]?[/code] node becomes. Node key, shared.
	UNKNOWN_RESOLUTION = 2,
	## Which event appears. Node key, shared.
	EVENT_DRAW = 3,
	## The vote-weighted draw deciding a team-choice event's option. Node key, shared.
	TEAM_CHOICE = 4,
	## An event option's random rewards and named curses. Node key, per seat.
	EVENT_OUTCOME = 5,
	## The starting heirloom offer and the chosen heirloom's own draws. Run key, per seat.
	STARTING_OFFER = 6,
	## Armory stock and Guildhall recruits and runes. Node key, shared.
	SHOP_STOCK = 7,
	## Guildhall prefix re-rolls. Node key, per seat.
	PREFIX_REROLL = 8,
	## Post-combat items and heirlooms, and Treasure. Node key, per seat.
	REWARD = 9,
	## Level-up growth rolls and random guaranteed gains. Node key, per seat.
	LEVEL_UPS = 10,
	## A battle's whole setup, drawn once at battle start. Node key; shared, or per seat for one
	## player's additions.
	ENCOUNTER_SETUP = 11,
	## One authored container's contents on one seat's map copy. Node key, per seat, with
	## [member index].
	MAP_LOOT = 12,
	## One seat's hit, crit and Chance rolls and random targets for one battle. Node key, per seat.
	COMBAT_ROLLS = 13,
}

# SplitMix64's golden-ratio increment and finalizer multipliers, as signed decimals: GDScript can't
# parse a hex literal above 2^63 - 1. The reference vectors in tests/rng/run_all.gd pin them.
const _GAMMA: int = -7046029254386353131  # 0x9E3779B97F4A7C15
const _MIX_1: int = -4658895280553007687  # 0xBF58476D1CE4E5B9
const _MIX_2: int = -7723592293110705685  # 0x94D049BB133111EB

const _LOW_16: int = 0xFFFF
const _LOW_32: int = 0xFFFFFFFF
const _TWO_POW_31: int = 0x80000000
const _TWO_POW_32: int = 0x100000000
const _NO_SIGN_BIT: int = 0x7FFFFFFFFFFFFFFF

# The save key's layout: [method to_save_key] writes it, [method from_save_key] splits it.
const _SAVE_KEY_FORMAT: String = "%d:%d:%d:%d:%d"
const _SAVE_KEY_SEPARATOR: String = ":"
const _SAVE_KEY_PARTS: int = 5

## What the stream is for.
var purpose: RngPurpose = RngPurpose.MAP_GENERATION

## The campaign floor, or [code]-1[/code] for a run-level stream. Named to avoid shadowing
## [method @GlobalScope.floor].
var floor_number: int = -1

## The node on [member floor_number], or [code]-1[/code] for a run- or floor-level stream.
var node: int = -1

## The player's seat for a personal stream, or [code]-1[/code] for a shared one.
var seat: int = -1

## Separates several streams of one purpose in one node, such as an authored chest's index on the
## map; [code]-1[/code] when unused.
var index: int = -1


func _init(
		key_purpose: RngPurpose,
		key_floor: int = -1,
		key_node: int = -1,
		key_seat: int = -1,
		key_index: int = -1
) -> void:
	purpose = key_purpose
	floor_number = key_floor
	node = key_node
	seat = key_seat
	index = key_index


## A string naming this key in a save file. Purposes are written as numbers, so renaming one never
## orphans saved streams. [method from_save_key] reads it back.
func to_save_key() -> String:
	# ASSUMPTION: the save key is the five parts as decimals joined by ":", purpose first
	# (e.g. "9:2:5:0:-1"); the plan names to_save_key() but not its format.
	return _SAVE_KEY_FORMAT % [purpose, floor_number, node, seat, index]


## The seed of the stream named by a key: [method mix] over the run seed and the five parts, in
## that order. A pure function of its arguments, stable across engine versions.
static func derive_seed(
		run_seed: int,
		key_purpose: RngPurpose,
		key_floor: int,
		key_node: int,
		key_seat: int,
		key_index: int
) -> int:
	return mix(PackedInt64Array([run_seed, key_purpose, key_floor, key_node, key_seat, key_index]))


## Mixes any number of 64-bit values into one, order-sensitively. One value [code]x[/code] gives
## SplitMix64's first output when seeded with [code]x[/code]; each further value is XORed into the
## running result and mixed again. An empty array gives [code]0[/code].[br]
## Also seeds P01's [code]SampledRolls[/code] from a session [code]seq[/code] and a candidate.
static func mix(values: PackedInt64Array) -> int:
	# ASSUMPTION: the chain starts at 0 and folds each value in as splitmix64(state ^ value); the
	# plan names SplitMix64 chained over the parts but not the chaining rule.
	var state: int = 0
	for value: int in values:
		state = _splitmix64(state ^ value)
	return state


## Reads a string written by [method to_save_key].
## Returns [code]null[/code] if [param text] isn't a save key or names a purpose this build doesn't
## have.
static func from_save_key(text: String) -> RngKey:
	var parts: PackedStringArray = text.split(_SAVE_KEY_SEPARATOR)
	if parts.size() != _SAVE_KEY_PARTS:
		return null
	for part: String in parts:
		if not part.is_valid_int():
			return null

	var purpose_value: int = parts[0].to_int()
	if not RngPurpose.values().has(purpose_value):
		return null
	return RngKey.new(
			purpose_value as RngPurpose,
			parts[1].to_int(),
			parts[2].to_int(),
			parts[3].to_int(),
			parts[4].to_int()
	)


# SplitMix64's output for state `value`: one increment by the golden ratio, then the finalizer.
static func _splitmix64(value: int) -> int:
	var mixed: int = _add64(value, _GAMMA)
	mixed = _mul64(mixed ^ _shift_right(mixed, 30), _MIX_1)
	mixed = _mul64(mixed ^ _shift_right(mixed, 27), _MIX_2)
	return mixed ^ _shift_right(mixed, 31)


# a + b mod 2^64, from 32-bit halves so no sum leaves the int range.
static func _add64(a: int, b: int) -> int:
	var low: int = (a & _LOW_32) + (b & _LOW_32)
	var high: int = (_shift_right(a, 32) + _shift_right(b, 32) + (low >> 32)) & _LOW_32
	return _join(high, low & _LOW_32)


# a * b mod 2^64, schoolbook over 16-bit limbs: every partial product is below 2^32 and every
# column sum below 2^35, so nothing overflows. Columns above the fourth are the discarded high
# half, so they are never computed.
static func _mul64(a: int, b: int) -> int:
	var a0: int = a & _LOW_16
	var a1: int = _shift_right(a, 16) & _LOW_16
	var a2: int = _shift_right(a, 32) & _LOW_16
	var a3: int = _shift_right(a, 48) & _LOW_16
	var b0: int = b & _LOW_16
	var b1: int = _shift_right(b, 16) & _LOW_16
	var b2: int = _shift_right(b, 32) & _LOW_16
	var b3: int = _shift_right(b, 48) & _LOW_16

	var column: int = a0 * b0
	var r0: int = column & _LOW_16
	column = (column >> 16) + a0 * b1 + a1 * b0
	var r1: int = column & _LOW_16
	column = (column >> 16) + a0 * b2 + a1 * b1 + a2 * b0
	var r2: int = column & _LOW_16
	column = (column >> 16) + a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0
	var r3: int = column & _LOW_16
	return _join((r3 << 16) | r2, (r1 << 16) | r0)


# Logical right shift for bits 1 to 63. GDScript rejects shifting a negative value, so the sign
# bit is cleared first and put back at its shifted position.
static func _shift_right(value: int, bits: int) -> int:
	if value >= 0:
		return value >> bits
	return ((value & _NO_SIGN_BIT) >> bits) | (1 << (63 - bits))


# The int whose two's-complement halves are high and low (each 0 to 2^32 - 1). The high half is
# made signed before scaling, so the product and the sum both stay inside the int range.
static func _join(high: int, low: int) -> int:
	var signed_high: int = high - _TWO_POW_32 if high >= _TWO_POW_31 else high
	return signed_high * _TWO_POW_32 + low
