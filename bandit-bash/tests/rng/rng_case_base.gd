# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_case_base.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends RefCounted
## Shared by the RNG suite's case files: reporting through the runner's check, and the values
## and helpers more than one of them uses. Expected 64-bit values are written as 16 hex digits
## (unsigned two's complement) and were computed outside Godot with arbitrary-precision
## integers, so they check the limb arithmetic rather than repeat it.

# The plan's example run seed (3F9A-12C0-77E1-A), 52 bits.
const RUN_SEED: int = 0x3F9A12C077E1A

# PCG32 golden draws, computed outside Godot with a reference PCG32 seeded the way Godot seeds it
# (it reproduces Godot's own state and first draws for seed 12345, pinned below):
# [stream seed, state after seeding, first eight d100 rolls (0-99), state after those eight].
const STREAM_GOLDENS: Array = [
	[
		"bc77f654851212ec", "62431fcec4f6c10e",
		[70, 21, 59, 87, 64, 45, 60, 70], "cc2d5a3f97d8faf6",
	],
	[
		"3a4d5c5407d30526", "0e0c0dfeacce1b40",
		[50, 97, 0, 20, 87, 3, 36, 30], "",
	],
]
const SEED_12345_STATE: String = "946bacc26b2c1a97"

# 2^53: the largest integer below which every integer survives as a JSON number.
const JSON_EXACT_LIMIT: int = 9007199254740992

const _LOW_32: int = 0xFFFFFFFF
const _TWO_POW_31: int = 0x80000000
const _TWO_POW_32: int = 0x100000000
const _NO_SIGN_BIT: int = 0x7FFFFFFFFFFFFFFF

var _report: Callable


func _init(check: Callable) -> void:
	_report = check


# A registry with live streams in both sections and an unsaved ENCOUNTER_SETUP stream, each drawn
# a little so no state is the fresh one.
func _registry_with_every_section() -> RngStreams:
	var registry: RngStreams = RngStreams.new(RUN_SEED)
	var keys: Array[RngKey] = [
		RngKey.new(RngKey.RngPurpose.MAP_GENERATION),
		RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5),
		RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0),
		RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 0),
		RngKey.new(RngKey.RngPurpose.LEVEL_UPS, 2, 5, 1),
		RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 1),
		RngKey.new(RngKey.RngPurpose.MAP_LOOT, 2, 5, 1, 3),
	]
	for i: int in keys.size():
		_draws(registry.stream(keys[i]), i + 1)
	return registry


# The next `count` d100 rolls of a stream.
func _draws(stream: RngStream, count: int) -> Array[int]:
	var rolls: Array[int] = []
	for i: int in count:
		rolls.append(stream.randi_range(0, 99))
	return rolls


# The int whose two's-complement bits are 16 hex digits.
func _from_hex(text: String) -> int:
	var high: int = text.substr(0, 8).hex_to_int()
	var low: int = text.substr(8, 8).hex_to_int()
	var signed_high: int = high - _TWO_POW_32 if high >= _TWO_POW_31 else high
	return signed_high * _TWO_POW_32 + low


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
