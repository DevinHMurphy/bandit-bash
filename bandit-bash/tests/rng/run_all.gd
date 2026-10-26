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
## Headless tests for the RNG streams: keys and the SplitMix64 mixer ([RngKey]), streams
## ([RngStream]) and a run's registry ([RngStreams]).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/rng/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## input make the RNG classes log errors on purpose; only FAIL lines mean a problem.[br]
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

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- RNG stream tests. Errors from RngStream and RngStreams below are expected. ---")

	_test_hex_helpers_round_trip()
	_test_mix_matches_splitmix64_reference()
	_test_mix_chains_values_in_order()
	_test_derive_seed_golden_values()
	_test_derive_seed_is_mix_of_key()
	_test_purpose_values_are_pinned()
	_test_each_key_part_changes_the_seed()
	_test_save_key_round_trip()
	_test_save_key_rejects_bad_text()
	_test_stream_golden_first_draws()
	_test_stream_capture_restore_continues()
	_test_stream_capture_survives_json()
	_test_stream_restore_rejects_bad_text()
	_test_roll_percent_draws_once()
	_test_pick_index()
	_test_pick_weighted_distribution()
	_test_pick_weighted_rejects_bad_weights()
	_test_shuffle_indices()
	_test_registry_creates_lazily_by_key()
	_test_registry_seats_and_shared_keys()
	_test_registry_draws_never_cross_keys()
	_test_registry_drop_node()
	_test_registry_sections()
	_test_registry_round_trip_through_json()
	_test_registry_restore_replaces_one_section()
	_test_registry_restore_rejects_bad_data()
	_test_registry_run_seed_is_fixed()

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


func _test_stream_golden_first_draws() -> void:
	var stream_12345: RngStream = RngStream.new(12345)
	_check(
			"stream golden: Godot's state for seed 12345",
			stream_12345.capture() == SEED_12345_STATE,
			stream_12345.capture()
	)

	for golden: Array in STREAM_GOLDENS:
		var seed_hex: String = golden[0]
		var stream: RngStream = RngStream.new(_from_hex(seed_hex))
		_check(
				"stream golden: %s state after seeding" % [seed_hex],
				stream.capture() == golden[1],
				stream.capture()
		)
		var rolls: Array[int] = []
		for i: int in 8:
			rolls.append(stream.randi_range(0, 99))
		_check(
				"stream golden: %s first eight d100" % [seed_hex],
				rolls == Array(golden[2], TYPE_INT, &"", null),
				str(rolls)
		)
		var after: String = golden[3]
		if not after.is_empty():
			_check(
					"stream golden: %s state after eight draws" % [seed_hex],
					stream.capture() == after,
					stream.capture()
			)

	var derived: RngStream = RngStream.new(RngKey.derive_seed(
			RUN_SEED, RngKey.RngPurpose.REWARD, 2, 5, 0, -1
	))
	_check(
			"stream golden: seeded from a derived key",
			derived.capture() == "62431fcec4f6c10e",
			derived.capture()
	)


func _test_stream_capture_restore_continues() -> void:
	var stream: RngStream = RngStream.new(_from_hex("bc77f654851212ec"))
	for i: int in 5:
		stream.randi_range(0, 99)
	var saved: String = stream.capture()
	var expected: Array[int] = _draws(stream, 12)

	var other: RngStream = RngStream.new(999)
	_check("capture/restore: restore accepts a capture", other.restore(saved))
	_check(
			"capture/restore: another stream continues identically",
			_draws(other, 12) == expected
	)

	_check("capture/restore: restore rewinds the same stream", stream.restore(saved))
	_check("capture/restore: rewound draws repeat", _draws(stream, 12) == expected)
	_check(
			"capture/restore: capture after restore matches",
			stream.restore(saved) and stream.capture() == saved
	)


func _test_stream_capture_survives_json() -> void:
	var stream: RngStream = RngStream.new(_from_hex("bc77f654851212ec"))
	var state: int = _from_hex(stream.capture())
	_check(
			"json: the state is above 2^53",
			state > JSON_EXACT_LIMIT or state < -JSON_EXACT_LIMIT,
			str(state)
	)

	var as_number: Variant = JSON.parse_string(JSON.stringify({"state": state}))
	var number_back: float = (as_number as Dictionary).get("state", 0.0)
	_check("json: the state as a number loses bits", int(number_back) != state)

	var expected: Array[int] = _draws(RngStream.new(_from_hex("bc77f654851212ec")), 10)
	var parsed: Variant = JSON.parse_string(JSON.stringify({"state": stream.capture()}))
	var text: String = (parsed as Dictionary).get("state", "")
	var restored: RngStream = RngStream.new(0)
	_check(
			"json: the captured string restores exactly",
			restored.restore(text) and _draws(restored, 10) == expected
	)


func _test_stream_restore_rejects_bad_text() -> void:
	var stream: RngStream = RngStream.new(42)
	var before: String = stream.capture()
	var all_rejected: bool = true
	for text: String in ["", "62431fcec4f6c10", "62431fcec4f6c10e0", "62431fcec4f6c1zz",
			"-2431fcec4f6c10e", "+2431fcec4f6c10e"]:
		all_rejected = all_rejected and not stream.restore(text)
	_check("restore: rejects malformed states", all_rejected)
	_check("restore: a rejected state leaves the stream unchanged", stream.capture() == before)
	_check(
			"restore: upper-case hex accepted",
			stream.restore("62431FCEC4F6C10E") and stream.capture() == "62431fcec4f6c10e"
	)


func _test_roll_percent_draws_once() -> void:
	var stream: RngStream = RngStream.new(7)
	var twin: RngStream = RngStream.new(7)
	var matches_d100: bool = true
	var never_at_0: bool = true
	var always_at_100: bool = true
	for i: int in 300:
		var chance: int = i % 3 * 50
		var rolled: bool = stream.roll_percent(chance)
		var expected: bool = twin.randi_range(0, 99) < chance
		matches_d100 = matches_d100 and rolled == expected
		never_at_0 = never_at_0 and not (chance == 0 and rolled)
		always_at_100 = always_at_100 and (chance != 100 or rolled)
	_check("roll_percent: one d100 below the chance, one draw per call", matches_d100)
	_check("roll_percent: chance 0 never succeeds", never_at_0)
	_check("roll_percent: chance 100 always succeeds", always_at_100)
	_check("roll_percent: same position as the twin", stream.capture() == twin.capture())


func _test_pick_index() -> void:
	var stream: RngStream = RngStream.new(11)
	var in_range: bool = true
	var seen: Dictionary[int, bool] = {}
	for i: int in 200:
		var picked: int = stream.pick_index(5)
		in_range = in_range and picked >= 0 and picked < 5
		seen[picked] = true
	_check("pick_index: always in range", in_range)
	_check("pick_index: every index reachable", seen.size() == 5, str(seen.keys()))

	var before: String = stream.capture()
	_check("pick_index: count 1 is 0", stream.pick_index(1) == 0)
	_check("pick_index: count 0 is -1", stream.pick_index(0) == -1)
	_check("pick_index: count 0 and 1 draw nothing", stream.capture() == before)


func _test_pick_weighted_distribution() -> void:
	var weights: PackedInt32Array = [1, 2, 3, 0, 4]
	var draws: int = 100000
	var counts: PackedInt32Array = [0, 0, 0, 0, 0]
	var stream: RngStream = RngStream.new(_from_hex("3a4d5c5407d30526"))
	for i: int in draws:
		var picked: int = stream.pick_weighted(weights)
		if picked >= 0:
			counts[picked] += 1

	_check("pick_weighted: weight 0 never picked", counts[3] == 0, str(counts))
	# NOTE: the stream is seeded, so the counts are fixed; 0.01 is about 7 standard deviations at
	# this many draws, so a correct pick passes and an off-by-one weight boundary fails.
	var within: bool = true
	for i: int in weights.size():
		var share: float = float(counts[i]) / float(draws)
		within = within and absf(share - float(weights[i]) / 10.0) < 0.01
	_check("pick_weighted: shares match weight / total", within, str(counts))

	var twin: RngStream = RngStream.new(_from_hex("3a4d5c5407d30526"))
	var expected_first: int = -1
	var remaining: int = twin.randi_range(0, 9)
	for i: int in weights.size():
		remaining -= weights[i]
		if remaining < 0:
			expected_first = i
			break
	_check(
			"pick_weighted: one integer roll over the total",
			RngStream.new(_from_hex("3a4d5c5407d30526")).pick_weighted(weights) == expected_first
	)


func _test_pick_weighted_rejects_bad_weights() -> void:
	var stream: RngStream = RngStream.new(3)
	var before: String = stream.capture()
	_check("pick_weighted: empty is -1", stream.pick_weighted(PackedInt32Array()) == -1)
	_check("pick_weighted: all zero is -1", stream.pick_weighted(PackedInt32Array([0, 0])) == -1)
	_check("pick_weighted: negative is -1", stream.pick_weighted(PackedInt32Array([3, -1])) == -1)
	_check(
			"pick_weighted: total above 2^31 is -1",
			stream.pick_weighted(PackedInt32Array([2147483647, 2])) == -1
	)
	_check("pick_weighted: rejected calls draw nothing", stream.capture() == before)
	_check(
			"pick_weighted: total of exactly 2^31 accepted",
			stream.pick_weighted(PackedInt32Array([2147483647, 1])) >= 0
	)


func _test_shuffle_indices() -> void:
	var order: PackedInt32Array = RngStream.new(5).shuffle_indices(10)
	var sorted: PackedInt32Array = order.duplicate()
	sorted.sort()
	_check(
			"shuffle_indices: a permutation of 0 to 9",
			sorted == PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
			str(order)
	)
	_check(
			"shuffle_indices: same seed, same order",
			RngStream.new(5).shuffle_indices(10) == order
	)
	_check(
			"shuffle_indices: another seed, another order",
			RngStream.new(6).shuffle_indices(10) != order
	)
	_check("shuffle_indices: 0 is empty", RngStream.new(5).shuffle_indices(0).is_empty())
	_check(
			"shuffle_indices: 1 is [0]",
			RngStream.new(5).shuffle_indices(1) == PackedInt32Array([0])
	)


func _test_registry_creates_lazily_by_key() -> void:
	var registry: RngStreams = RngStreams.new(RUN_SEED)
	_check("registry: empty until a stream is asked for", registry.capture_campaign().is_empty())

	var key: RngKey = RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0)
	var first: RngStream = registry.stream(key)
	_check(
			"registry: a new stream starts at its derived seed",
			first.capture() == "62431fcec4f6c10e",
			first.capture()
	)
	_check(
			"registry: an equal key returns the same stream",
			is_same(first, registry.stream(RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0)))
	)

	key.seat = 1
	_check(
			"registry: changing the caller's key afterwards changes nothing",
			registry.capture_campaign().keys() == ["9:2:5:0:-1"],
			str(registry.capture_campaign().keys())
	)


func _test_registry_seats_and_shared_keys() -> void:
	var registry: RngStreams = RngStreams.new(RUN_SEED)
	var reward_0: RngStream = registry.stream(RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0))
	var reward_1: RngStream = registry.stream(RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 1))
	_check(
			"registry seats: two seats get different REWARD streams",
			not is_same(reward_0, reward_1)
	)
	_check(
			"registry seats: their draws differ",
			_draws(reward_0, 10) != _draws(reward_1, 10)
	)

	# A shared key carries no seat, so every seat's request names the same key.
	var setup_for_seat_0: RngStream = registry.stream(
			RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5)
	)
	var setup_for_seat_1: RngStream = registry.stream(
			RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5)
	)
	_check(
			"registry seats: both seats get the same ENCOUNTER_SETUP stream",
			is_same(setup_for_seat_0, setup_for_seat_1)
	)
	var other_run: RngStreams = RngStreams.new(RUN_SEED)
	_check(
			"registry seats: the shared stream is the same in another registry of the run",
			_draws(other_run.stream(RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5)), 10)
			== _draws(setup_for_seat_0, 10)
	)


func _test_registry_draws_never_cross_keys() -> void:
	var quiet: RngStreams = RngStreams.new(RUN_SEED)
	var expected: Array[int] = _draws(
			quiet.stream(RngKey.new(RngKey.RngPurpose.MAP_LOOT, 3, 1, 1, 4)), 20
	)

	var busy: RngStreams = RngStreams.new(RUN_SEED)
	var loot: RngStream = busy.stream(RngKey.new(RngKey.RngPurpose.MAP_LOOT, 3, 1, 1, 4))
	var combat: RngStream = busy.stream(RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 3, 1, 1))
	var actual: Array[int] = []
	for i: int in 20:
		_draws(combat, 7)
		busy.stream(RngKey.new(RngKey.RngPurpose.MAP_LOOT, 3, 1, 1, i + 10))
		actual.append(loot.randi_range(0, 99))
	_check(
			"registry: draws and new streams on other keys never shift a stream",
			actual == expected
	)


func _test_registry_drop_node() -> void:
	var registry: RngStreams = RngStreams.new(RUN_SEED)
	var reward: RngStream = registry.stream(RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0))
	_draws(reward, 3)
	registry.stream(RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 0))
	registry.stream(RngKey.new(RngKey.RngPurpose.REWARD, 2, 6, 0))
	registry.stream(RngKey.new(RngKey.RngPurpose.ROUTE_DRAW, 2))
	registry.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION))

	registry.drop_node(2, 5)
	_check(
			"drop_node: only that node's streams go",
			registry.capture_campaign().keys() == ["9:2:6:0:-1", "1:2:-1:-1:-1", "0:-1:-1:-1:-1"]
			and registry.capture_combat().is_empty(),
			str(registry.capture_campaign().keys())
	)
	_check(
			"drop_node: a dropped key starts again from its seed",
			registry.stream(RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0)).capture()
			== "62431fcec4f6c10e"
	)


func _test_registry_sections() -> void:
	var registry: RngStreams = _registry_with_every_section()
	_check(
			"sections: campaign holds every other purpose",
			registry.capture_campaign().keys() == ["0:-1:-1:-1:-1", "9:2:5:0:-1", "10:2:5:1:-1"],
			str(registry.capture_campaign().keys())
	)
	_check(
			"sections: combat holds COMBAT_ROLLS and MAP_LOOT",
			registry.capture_combat().keys() == ["13:2:5:0:-1", "13:2:5:1:-1", "12:2:5:1:3"],
			str(registry.capture_combat().keys())
	)
	var all_strings: bool = true
	for state: String in registry.capture_campaign().values() + registry.capture_combat().values():
		all_strings = all_strings and state.length() == 16
	_check("sections: ENCOUNTER_SETUP is in neither; states are strings", all_strings)


func _test_registry_round_trip_through_json() -> void:
	var original: RngStreams = _registry_with_every_section()
	var campaign_json: String = JSON.stringify(original.capture_campaign())
	var combat_json: String = JSON.stringify(original.capture_combat())
	var keys: Array[RngKey] = [
		RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0),
		RngKey.new(RngKey.RngPurpose.LEVEL_UPS, 2, 5, 1),
		RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 1),
		RngKey.new(RngKey.RngPurpose.MAP_LOOT, 2, 5, 1, 3),
	]
	var expected: Array = []
	for key: RngKey in keys:
		expected.append(_draws(original.stream(key), 10))

	var resumed: RngStreams = RngStreams.new(RUN_SEED)
	var campaign_data: Dictionary = JSON.parse_string(campaign_json)
	var combat_data: Dictionary = JSON.parse_string(combat_json)
	var campaign_ok: bool = resumed.restore_campaign(campaign_data)
	var combat_ok: bool = resumed.restore_combat(combat_data)
	_check("round trip: both sections restore from JSON", campaign_ok and combat_ok)
	var actual: Array = []
	for key: RngKey in keys:
		actual.append(_draws(resumed.stream(key), 10))
	_check("round trip: every restored stream continues identically", actual == expected)


func _test_registry_restore_replaces_one_section() -> void:
	var saved: Dictionary[String, String] = _registry_with_every_section().capture_campaign()
	var registry: RngStreams = RngStreams.new(RUN_SEED)
	registry.stream(RngKey.new(RngKey.RngPurpose.SHOP_STOCK, 4, 4))
	var combat: RngStream = registry.stream(RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 4, 4, 0))
	_check("restore: campaign data accepted", registry.restore_campaign(saved))
	_check(
			"restore: the campaign section is exactly the saved one",
			registry.capture_campaign() == saved,
			str(registry.capture_campaign().keys())
	)
	_check(
			"restore: the combat section is untouched",
			is_same(registry.stream(RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 4, 4, 0)), combat)
	)
	_check(
			"restore: empty data clears a section",
			registry.restore_combat({}) and registry.capture_combat().is_empty()
	)


func _test_registry_restore_rejects_bad_data() -> void:
	var registry: RngStreams = _registry_with_every_section()
	var campaign_before: Dictionary[String, String] = registry.capture_campaign()
	var combat_before: Dictionary[String, String] = registry.capture_combat()
	var good_state: String = "62431fcec4f6c10e"
	var bad_campaign: Array[Dictionary] = [
		{"13:2:5:0:-1": good_state},
		{"11:2:5:-1:-1": good_state},
		{"99:0:0:0:0": good_state},
		{"9:2:5": good_state},
		{9: good_state},
		{"9:2:5:0:-1": 7.0},
		{"9:2:5:0:-1": "zz"},
		{"0:-1:-1:-1:-1": good_state, "9:2:5:0:-1": "zz"},
	]
	var all_rejected: bool = true
	for data: Dictionary in bad_campaign:
		all_rejected = all_rejected and not registry.restore_campaign(data)
	all_rejected = all_rejected and not registry.restore_combat({"9:2:5:0:-1": good_state})
	_check(
			"restore: rejects wrong-section, unknown, malformed and bad-state entries",
			all_rejected
	)
	_check(
			"restore: a rejected section changes nothing",
			registry.capture_campaign() == campaign_before
			and registry.capture_combat() == combat_before
	)


func _test_registry_run_seed_is_fixed() -> void:
	var registry: RngStreams = RngStreams.new(RUN_SEED)
	registry.run_seed = 5
	_check("run_seed: reads back the construction seed", registry.run_seed == RUN_SEED)


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
