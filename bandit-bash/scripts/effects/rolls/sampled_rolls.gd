# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     sampled_rolls.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name SampledRolls
extends RollSource
## AI sampling's rolls, for when a candidate has too many branches to enumerate: a private
## generator seeded with [method RngKey.mix] over the session's [code]seq[/code] and the candidate
## (unit, tile, target, weapon), never a session's stream (RNG streams plan, need R-N2).
##
## The same seq and candidate always give the same draws, whatever thread or order evaluates them,
## so a resumed enemy phase decides identically. Candidate parts are folded into the seed in order:
## an int as itself, a [Vector2i] as x then y, a [String] as its length then its UTF-8 bytes, seven
## to a number, so ids never pass through [method @GlobalScope.hash].
##
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

# Bytes packed into one seed value: seven keep every value positive.
const _BYTES_PER_VALUE: int = 7

var _generator: RngStream = null


## [param candidate]: the parts naming it, such as
## [code][unit_id, tile, target_id, weapon_id][/code];
## ints, [Vector2i]s and [String]s.
func _init(session_seq: int, candidate: Array) -> void:
	_generator = RngStream.new(seed_for(session_seq, candidate))


# Two d100, as LiveRolls draws them.
func _draw_hit_2rn(hit_percent: int, _odds: float) -> bool:
	var first: int = _generator.randi_range(0, _D100 - 1)
	var second: int = _generator.randi_range(0, _D100 - 1)
	return first + second < 2 * hit_percent


func _draw_percent(chance: int, _odds: float) -> bool:
	return _generator.roll_percent(chance)


func _draw_index(count: int) -> int:
	return _generator.pick_index(count)


## The seed for [param session_seq] and [param candidate]. A part of another type is skipped.
static func seed_for(session_seq: int, candidate: Array) -> int:
	# The encoding in the class doc is a determinism contract (event bus plan, question 36): a
	# resumed battle must decide the same, so it stays fixed within a build.
	var values: PackedInt64Array = [session_seq]
	for part: Variant in candidate:
		match typeof(part):
			TYPE_INT:
				values.append(part as int)
			TYPE_VECTOR2I:
				var tile: Vector2i = part
				values.append(tile.x)
				values.append(tile.y)
			TYPE_STRING, TYPE_STRING_NAME:
				var bytes: PackedByteArray = (part as String).to_utf8_buffer()
				values.append(bytes.size())
				for start: int in range(0, bytes.size(), _BYTES_PER_VALUE):
					var packed: int = 0
					for i: int in range(start, mini(start + _BYTES_PER_VALUE, bytes.size())):
						packed = (packed << 8) | bytes[i]
					values.append(packed)
	return RngKey.mix(values)
