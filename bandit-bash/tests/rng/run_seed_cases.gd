# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_seed_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/rng/rng_case_base.gd"
## Run seed cases for tests/rng/run_all.gd ([RunSeed]): generation range, the display format and
## parsing, and a typed seed reproducing a run's streams.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "rng"

# Generated seeds checked per run-seed case: enough to catch a bad mask, quick to run.
const RUN_SEED_SAMPLES: int = 1000


func run() -> void:
	_test_run_seed_generate_range()
	_test_run_seed_format()
	_test_run_seed_format_parse_round_trip()
	_test_run_seed_parse_forms()
	_test_typed_seed_reproduces_run()


func _test_run_seed_generate_range() -> void:
	var is_in_range: bool = true
	var distinct: Dictionary[int, bool] = {}
	for i: int in RUN_SEED_SAMPLES:
		var run_seed: int = RunSeed.generate()
		is_in_range = is_in_range and run_seed >= 0 and run_seed <= RunSeed.MAX_SEED
		distinct[run_seed] = true
	_check("run seed: MAX_SEED is 2^52 - 1", RunSeed.MAX_SEED == (1 << 52) - 1)
	_check("run seed: MAX_SEED is an exact JSON number", RunSeed.MAX_SEED < JSON_EXACT_LIMIT)
	_check("run seed: generated seeds are 0 to 2^52 - 1", is_in_range)
	# Not a randomness test: only catches a constant or a broken source.
	_check("run seed: generated seeds differ", distinct.size() > 1, str(distinct.size()))


func _test_run_seed_format() -> void:
	_check("format: plan example", RunSeed.format(RUN_SEED) == "3F9A-12C0-77E1-A")
	_check("format: 0 is zero-padded", RunSeed.format(0) == "0000-0000-0000-0")
	_check("format: largest seed", RunSeed.format(RunSeed.MAX_SEED) == "FFFF-FFFF-FFFF-F")
	_check("format: a 32-bit seed", RunSeed.format(0xFFFFFFFF) == "0000-0FFF-FFFF-F")
	_check("format: refuses -1", RunSeed.format(-1).is_empty())
	_check("format: refuses 2^52", RunSeed.format(RunSeed.MAX_SEED + 1).is_empty())


func _test_run_seed_format_parse_round_trip() -> void:
	var seeds: Array[int] = [0, 1, RunSeed.MAX_SEED, RUN_SEED, 0xFFFFFFFF]
	for i: int in RUN_SEED_SAMPLES:
		seeds.append(RunSeed.generate())
	var failed: Array[int] = []
	for run_seed: int in seeds:
		if RunSeed.parse(RunSeed.format(run_seed)) != run_seed:
			failed.append(run_seed)
	_check("format -> parse: 0 round trips", RunSeed.parse(RunSeed.format(0)) == 0)
	_check(
			"format -> parse: largest seed round trips",
			RunSeed.parse(RunSeed.format(RunSeed.MAX_SEED)) == RunSeed.MAX_SEED
	)
	_check("format -> parse: every seed round trips", failed.is_empty(), str(failed))


# Any case, dashes anywhere or none and surrounding spaces are accepted; every digit is required.
func _test_run_seed_parse_forms() -> void:
	var accepted: Array[String] = [
		"3F9A-12C0-77E1-A",
		"3f9a-12c0-77e1-a",
		"3F9A12C077E1A",
		"  3F9A-12C0-77E1-A \n",
		"3F9A12C0-77E1A",
	]
	for text: String in accepted:
		_check("parse: accepts '%s'" % [text.strip_edges()], RunSeed.parse(text) == RUN_SEED)
	var refused: Array[String] = [
		"",
		"3F9A-12C0-77E1",
		"3F9A-12C0-77E1-AB",
		"3F9A-12C0-77E1-G",
		"+F9A-12C0-77E1-A",
		"3F9A 12C0 77E1 A",
		"0x3F9A12C077E1A",
	]
	for text: String in refused:
		_check("parse: refuses '%s'" % [text], RunSeed.parse(text) == RunSeed.NO_SEED)


# Typing a seed back in gives a run the same seed and so the same streams: what a bug report
# needs. The REWARD stream of RUN_SEED is pinned in STREAM_GOLDENS.
func _test_typed_seed_reproduces_run() -> void:
	var original_seed: int = RunSeed.generate()
	var typed_seed: int = RunSeed.parse(RunSeed.format(original_seed))
	var original_run: CampaignData = CampaignData.create_solo(original_seed)
	var typed_run: CampaignData = CampaignData.create_solo(typed_seed)
	_check("typed seed: same run_seed", typed_run.run_seed == original_run.run_seed)

	var original: RngStreams = RngStreams.new(original_run.run_seed)
	var typed: RngStreams = RngStreams.new(typed_run.run_seed)
	var keys: Array[RngKey] = [
		RngKey.new(RngKey.RngPurpose.MAP_GENERATION),
		RngKey.new(RngKey.RngPurpose.STARTING_OFFER, -1, -1, 0),
		RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 1, 2),
		RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 1, 2, 0),
	]
	var is_same: bool = true
	for key: RngKey in keys:
		is_same = is_same and _draws(original.stream(key), 8) == _draws(typed.stream(key), 8)
	_check("typed seed: same first draws from derived streams", is_same)

	var golden: Array = STREAM_GOLDENS[0]
	var expected: Array[int] = []
	expected.assign(golden[2] as Array)
	var from_text: RngStreams = RngStreams.new(RunSeed.parse("3f9a-12c0-77e1-a"))
	var reward_key: RngKey = RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0)
	var rolls: Array[int] = _draws(from_text.stream(reward_key), 8)
	_check("typed seed: plan example gives the golden REWARD draws", rolls == expected, str(rolls))
