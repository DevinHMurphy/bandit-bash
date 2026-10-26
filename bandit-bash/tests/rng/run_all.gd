# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the RNG streams: keys and the SplitMix64 mixer ([RngKey]).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/rng/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails.[br]
## Expected 64-bit values are written as 16 hex digits (unsigned two's complement) and were
## computed outside Godot with arbitrary-precision integers, so they check the limb arithmetic
## rather than repeat it.

# SplitMix64 reference pairs: [state, first output]. The first five are the sequence seeded with
# 0 and the next five the sequence seeded with 1234567 (each state is the seed plus k times the
# golden-ratio increment), matching the published reference outputs. The rest have the top bit set
# or sit at the edges of the int range; 61c8864680b583eb is minus the increment, so it mixes 0.
const SPLITMIX_VECTORS: Array = [
	["0000000000000000", "e220a8397b1dcdaf"],
	["9e3779b97f4a7c15", "6e789e6aa1b965f4"],
	["3c6ef372fe94f82a", "06c45d188009454f"],
	["daa66d2c7ddf743f", "f88bb8a8724c81ec"],
	["78dde6e5fd29f054", "1b39896a51a8749b"],
	["000000000012d687", "599ed017fb08fc85"],
	["9e3779b97f5d529c", "2c73f08458540fa5"],
	["3c6ef372fea7ceb1", "883ebce5a3f27c77"],
	["daa66d2c7df24ac6", "3fbef740e9177b3f"],
	["78dde6e5fd3cc6db", "e3b8346708cb5ecd"],
	["0000000000000001", "910a2dec89025cc1"],
	["7fffffffffffffff", "2a67d7552e039ea7"],
	["8000000000000000", "481ec0a212a9f3db"],
	["ffffffffffffffff", "e4d971771b652c20"],
	["deadbeefcafebabe", "0d7d93560d1929d2"],
	["61c8864680b583eb", "0000000000000000"],
]

# The plan's example run seed (3F9A-12C0-77E1-A), 52 bits.
const RUN_SEED: int = 0x3F9A12C077E1A

# Golden derived seeds for RUN_SEED: [purpose, floor, node, seat, index, seed].
const DERIVED_SEEDS: Array = [
	[RngKey.RngPurpose.MAP_GENERATION, -1, -1, -1, -1, "1260e28498e67436"],
	[RngKey.RngPurpose.REWARD, 2, 5, 0, -1, "bc77f654851212ec"],
	[RngKey.RngPurpose.REWARD, 2, 5, 1, -1, "6931c41f55cf6359"],
	[RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5, -1, -1, "76a862b66d068701"],
	[RngKey.RngPurpose.MAP_LOOT, 3, 1, 1, 4, "5c761d110a79194b"],
	[RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 0, -1, "3a4d5c5407d30526"],
]

# Every purpose's number. These are part of every seed and save key: a change here is a change to
# every saved run, so a failure means the enum was renumbered, not that this table is stale.
const PURPOSE_VALUES: Dictionary[String, int] = {
	"MAP_GENERATION": 0,
	"ROUTE_DRAW": 1,
	"UNKNOWN_RESOLUTION": 2,
	"EVENT_DRAW": 3,
	"TEAM_CHOICE": 4,
	"EVENT_OUTCOME": 5,
	"STARTING_OFFER": 6,
	"SHOP_STOCK": 7,
	"PREFIX_REROLL": 8,
	"REWARD": 9,
	"LEVEL_UPS": 10,
	"ENCOUNTER_SETUP": 11,
	"MAP_LOOT": 12,
	"COMBAT_ROLLS": 13,
}

const _LOW_32: int = 0xFFFFFFFF
const _TWO_POW_31: int = 0x80000000
const _TWO_POW_32: int = 0x100000000
const _NO_SIGN_BIT: int = 0x7FFFFFFFFFFFFFFF

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- RNG stream tests ---")

	_test_hex_helpers_round_trip()
	_test_mix_matches_splitmix64_reference()
	_test_mix_chains_values_in_order()
	_test_derive_seed_golden_values()
	_test_derive_seed_is_mix_of_key()
	_test_purpose_values_are_pinned()
	_test_each_key_part_changes_the_seed()
	_test_save_key_round_trip()
	_test_save_key_rejects_bad_text()

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_hex_helpers_round_trip() -> void:
	var values: PackedInt64Array = [0, 1, -1, 9223372036854775807, -9223372036854775807 - 1]
	var all_match: bool = true
	for value: int in values:
		all_match = all_match and _from_hex(_hex(value)) == value
	_check("hex helpers: round trip at the int range edges", all_match)
	_check("hex helpers: -1 is all ones", _hex(-1) == "ffffffffffffffff", _hex(-1))
	_check(
			"hex helpers: int min is the top bit",
			_hex(-9223372036854775807 - 1) == "8000000000000000"
	)


func _test_mix_matches_splitmix64_reference() -> void:
	for pair: Array in SPLITMIX_VECTORS:
		var state: String = pair[0]
		var expected: String = pair[1]
		var actual: String = _hex(RngKey.mix(PackedInt64Array([_from_hex(state)])))
		_check("splitmix64: %s -> %s" % [state, expected], actual == expected, actual)


func _test_mix_chains_values_in_order() -> void:
	_check("mix: empty is 0", RngKey.mix(PackedInt64Array()) == 0)
	_check(
			"mix: [1, 2] golden",
			_hex(RngKey.mix(PackedInt64Array([1, 2]))) == "bcd9dbb49673066b",
			_hex(RngKey.mix(PackedInt64Array([1, 2])))
	)
	_check(
			"mix: [2, 1] golden",
			_hex(RngKey.mix(PackedInt64Array([2, 1]))) == "e06dd043328bd285",
			_hex(RngKey.mix(PackedInt64Array([2, 1])))
	)
	_check(
			"mix: [-1, -1] golden",
			_hex(RngKey.mix(PackedInt64Array([-1, -1]))) == "6309143e67a47936",
			_hex(RngKey.mix(PackedInt64Array([-1, -1])))
	)
	var first: int = RngKey.mix(PackedInt64Array([77]))
	_check(
			"mix: each value is XORed into the running result",
			RngKey.mix(PackedInt64Array([77, -5])) == RngKey.mix(PackedInt64Array([first ^ -5]))
	)


func _test_derive_seed_golden_values() -> void:
	for row: Array in DERIVED_SEEDS:
		var key: RngKey = RngKey.new(row[0], row[1], row[2], row[3], row[4])
		var expected: String = row[5]
		var actual: String = _hex(RngKey.derive_seed(
				RUN_SEED, key.purpose, key.floor_number, key.node, key.seat, key.index
		))
		_check("derive_seed: %s golden" % [key.to_save_key()], actual == expected, actual)


func _test_derive_seed_is_mix_of_key() -> void:
	var derived: int = RngKey.derive_seed(RUN_SEED, RngKey.RngPurpose.LEVEL_UPS, 4, 2, 1, -1)
	_check(
			"derive_seed: mix over the run seed, then purpose, floor, node, seat, index",
			derived == RngKey.mix(PackedInt64Array([RUN_SEED, 10, 4, 2, 1, -1]))
	)
	_check(
			"derive_seed: same key, same seed",
			derived == RngKey.derive_seed(RUN_SEED, RngKey.RngPurpose.LEVEL_UPS, 4, 2, 1, -1)
	)
	_check(
			"derive_seed: another run seed, another seed",
			derived != RngKey.derive_seed(RUN_SEED + 1, RngKey.RngPurpose.LEVEL_UPS, 4, 2, 1, -1)
	)


# A purpose's seed depends only on its own number, so appending a purpose leaves every existing
# seed unchanged as long as no existing number moves; the golden seeds above pin the mixer.
func _test_purpose_values_are_pinned() -> void:
	for purpose_name: String in PURPOSE_VALUES:
		var has_name: bool = RngKey.RngPurpose.has(purpose_name)
		_check(
				"purposes: %s is %d" % [purpose_name, PURPOSE_VALUES[purpose_name]],
				has_name and RngKey.RngPurpose[purpose_name] == PURPOSE_VALUES[purpose_name]
		)
	_check(
			"purposes: every value is pinned here",
			RngKey.RngPurpose.size() == PURPOSE_VALUES.size(),
			"enum has %d, table has %d" % [RngKey.RngPurpose.size(), PURPOSE_VALUES.size()]
	)


func _test_each_key_part_changes_the_seed() -> void:
	var reward: RngKey.RngPurpose = RngKey.RngPurpose.REWARD
	var base: int = RngKey.derive_seed(RUN_SEED, reward, 2, 5, 0, -1)
	_check(
			"key parts: seat 0 and seat 1 differ",
			base != RngKey.derive_seed(RUN_SEED, reward, 2, 5, 1, -1)
	)
	_check(
			"key parts: shared and seat 0 differ",
			base != RngKey.derive_seed(RUN_SEED, reward, 2, 5, -1, -1)
	)
	_check(
			"key parts: index -1 and 0 differ",
			base != RngKey.derive_seed(RUN_SEED, reward, 2, 5, 0, 0)
	)
	_check(
			"key parts: floor and node are not interchangeable",
			base != RngKey.derive_seed(RUN_SEED, reward, 5, 2, 0, -1)
	)
	_check(
			"key parts: purpose changes the seed",
			base != RngKey.derive_seed(RUN_SEED, RngKey.RngPurpose.LEVEL_UPS, 2, 5, 0, -1)
	)


func _test_save_key_round_trip() -> void:
	var key: RngKey = RngKey.new(RngKey.RngPurpose.MAP_LOOT, 3, 1, 1, 4)
	_check("save key: format", key.to_save_key() == "12:3:1:1:4", key.to_save_key())

	var run_level: RngKey = RngKey.new(RngKey.RngPurpose.MAP_GENERATION)
	_check(
			"save key: unused parts are -1",
			run_level.to_save_key() == "0:-1:-1:-1:-1",
			run_level.to_save_key()
	)

	var back: RngKey = RngKey.from_save_key(key.to_save_key())
	_check(
			"save key: round trip keeps every part",
			back != null and back.purpose == key.purpose and back.floor_number == 3
			and back.node == 1 and back.seat == 1 and back.index == 4
	)


func _test_save_key_rejects_bad_text() -> void:
	for text: String in ["", "1:2:3", "1:2:3:4:5:6", "a:1:2:3:4", "9:2:x:0:-1", "99:0:0:0:0"]:
		_check("save key: rejects \"%s\"" % [text], RngKey.from_save_key(text) == null)


# 16 lowercase hex digits of value's two's-complement bits. Shifts only non-negative values,
# as GDScript requires.
func _hex(value: int) -> String:
	var high: int = (
			value >> 32 if value >= 0
			else ((value & _NO_SIGN_BIT) >> 32) | _TWO_POW_31
	)
	return "%08x%08x" % [high, value & _LOW_32]


# The int whose two's-complement bits are 16 hex digits.
func _from_hex(text: String) -> int:
	var high: int = text.substr(0, 8).hex_to_int()
	var low: int = text.substr(8, 8).hex_to_int()
	var signed_high: int = high - _TWO_POW_32 if high >= _TWO_POW_31 else high
	return signed_high * _TWO_POW_32 + low


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
