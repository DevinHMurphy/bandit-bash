# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     stream_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/rng/rng_case_base.gd"
## Stream cases for tests/rng/run_all.gd ([RngStream]): golden draws, capture and restore, JSON
## survival, and the rolls and picks built on the stream.


func run() -> void:
	_test_stream_golden_first_draws()
	_test_stream_capture_restore_continues()
	_test_stream_capture_survives_json()
	_test_stream_restore_rejects_bad_text()
	_test_roll_percent_draws_once()
	_test_pick_index()
	_test_pick_weighted_distribution()
	_test_pick_weighted_rejects_bad_weights()
	_test_shuffle_indices()


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
				(stream.capture() == golden[1]) as bool,
				stream.capture()
		)
		var rolls: Array[int] = []
		for i: int in 8:
			rolls.append(stream.randi_range(0, 99))
		_check(
				"stream golden: %s first eight d100" % [seed_hex],
				rolls == Array(golden[2] as Array, TYPE_INT, &"", null),
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
