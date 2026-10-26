# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_stream.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name RngStream
extends RefCounted
## One seeded sequence of random results, named by an [RngKey].
##
## Gameplay code draws only from a stream handed to it, never from the global generator, so no
## other draw can shift its results. Each stream owns one [RandomNumberGenerator] (PCG32), and its
## whole position is that generator's 64-bit state: [method capture] writes it as a string, because
## JSON numbers lose integers above 2^53, and [method restore] continues the same sequence.[br]
## [method roll_percent] and [method pick_weighted] compare integers only, so their results match
## on every platform. Drawing through a helper with equal bounds, such as [method pick_index] of 1,
## consumes nothing; the sequence is still the same on every run.
##
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

# A d100 is 0 to 99, as in Godot_FE's random_rolls_bool and P01's RollSource table.
const _PERCENT_SIDES: int = 100

# RandomNumberGenerator.randi_range takes 32-bit bounds, so a weighted roll's total is capped here.
const _MAX_WEIGHT_TOTAL: int = 0x80000000

const _STATE_LENGTH: int = 16
const _LOW_32: int = 0xFFFFFFFF
const _TWO_POW_31: int = 0x80000000
const _TWO_POW_32: int = 0x100000000
const _NO_SIGN_BIT: int = 0x7FFFFFFFFFFFFFFF

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## [param stream_seed] is usually [method RngKey.derive_seed] of the stream's key.
func _init(stream_seed: int) -> void:
	_rng.seed = stream_seed


## A uniform integer from [param from_value] to [param to_value], both included, in either order.
## Both bounds must fit in 32 bits.
func randi_range(from_value: int, to_value: int) -> int:
	return _rng.randi_range(from_value, to_value)


## A uniform float from 0.0 to 1.0, both included.
func randf() -> float:
	return _rng.randf()


## One d100 (0 to 99): true if it is below [param chance]. Always draws once, so the stream
## advances the same way whatever the chance; 0 or less never succeeds, 100 or more always does.
func roll_percent(chance: int) -> bool:
	return _rng.randi_range(0, _PERCENT_SIDES - 1) < chance


## A uniform index from 0 to [param count] - 1.
## Returns -1, without drawing, if [param count] is below 1.
func pick_index(count: int) -> int:
	if count < 1:
		push_error("RngStream: pick_index needs a count of at least 1 - %d" % [count])
		return -1
	return _rng.randi_range(0, count - 1)


## An index into [param weights], each picked with probability weight / total, by one integer roll
## over the total. A weight of 0 is never picked.
## Returns -1, without drawing, if a weight is negative or the total is 0 or above 2^31.
func pick_weighted(weights: PackedInt32Array) -> int:
	var total: int = 0
	for weight: int in weights:
		if weight < 0:
			push_error("RngStream: pick_weighted got a negative weight - %s" % [weights])
			return -1
		total += weight
	if total < 1 or total > _MAX_WEIGHT_TOTAL:
		push_error("RngStream: pick_weighted total must be 1 to 2^31 - %d" % [total])
		return -1

	var roll: int = _rng.randi_range(0, total - 1)
	for i: int in weights.size():
		roll -= weights[i]
		if roll < 0:
			return i
	return -1


## The indices 0 to [param count] - 1 in a uniformly random order (Fisher-Yates, from the end).
## Returns an empty array, without drawing, if [param count] is below 1.
func shuffle_indices(count: int) -> PackedInt32Array:
	var order: PackedInt32Array = []
	for i: int in maxi(count, 0):
		order.append(i)
	for i: int in range(count - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swapped: int = order[i]
		order[i] = order[j]
		order[j] = swapped
	return order


## The stream's position as 16 lowercase hex digits (the state's two's-complement bits).
## [method restore] reads it back; nothing else may parse it.
func capture() -> String:
	var state: int = _rng.state
	# GDScript rejects shifting a negative value, so the sign bit is cleared first and put back.
	var high: int = (
			state >> 32 if state >= 0
			else ((state & _NO_SIGN_BIT) >> 32) | _TWO_POW_31
	)
	return "%08x%08x" % [high, state & _LOW_32]


## Continues the sequence from a string written by [method capture], whatever this stream's seed.
## Returns false, leaving the stream unchanged, if [param state_text] isn't such a string.
func restore(state_text: String) -> bool:
	var is_hex: bool = (
			state_text.length() == _STATE_LENGTH
			and state_text.is_valid_hex_number(false)
			and not state_text.begins_with("-")
			and not state_text.begins_with("+")
	)
	if not is_hex:
		push_error("RngStream: not a captured state - \"%s\"" % [state_text])
		return false

	var high: int = state_text.substr(0, 8).hex_to_int()
	var low: int = state_text.substr(8, 8).hex_to_int()
	# The high half is made signed before scaling, so neither the product nor the sum overflows.
	var signed_high: int = high - _TWO_POW_32 if high >= _TWO_POW_31 else high
	_rng.state = signed_high * _TWO_POW_32 + low
	return true
