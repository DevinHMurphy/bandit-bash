# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     registry_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/rng/rng_case_base.gd"
## Registry cases for tests/rng/run_all.gd ([RngStreams]): lazy streams by key, seats and shared
## keys, independence between keys, dropping a node, and the two saved sections.


# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "rng"

func run() -> void:
	_test_registry_creates_lazily_by_key()
	_test_registry_seats_and_shared_keys()
	_test_registry_draws_never_cross_keys()
	_test_registry_drop_node()
	_test_registry_sections()
	_test_registry_round_trip_through_json()
	_test_registry_restore_replaces_one_section()
	_test_registry_restore_rejects_bad_data()
	_test_registry_run_seed_is_fixed()


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
			"sections: combat holds only COMBAT_ROLLS",
			registry.capture_combat().keys() == ["13:2:5:0:-1", "13:2:5:1:-1"],
			str(registry.capture_combat().keys())
	)
	var all_strings: bool = true
	for state: String in registry.capture_campaign().values() + registry.capture_combat().values():
		all_strings = all_strings and state.length() == 16
	_check(
			"sections: ENCOUNTER_SETUP and MAP_LOOT are in neither; states are strings",
			all_strings
	)


func _test_registry_round_trip_through_json() -> void:
	var original: RngStreams = _registry_with_every_section()
	var campaign_json: String = JSON.stringify(original.capture_campaign())
	var combat_json: String = JSON.stringify(original.capture_combat())
	var keys: Array[RngKey] = [
		RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0),
		RngKey.new(RngKey.RngPurpose.LEVEL_UPS, 2, 5, 1),
		RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 1),
	]
	var expected: Array = []
	for key: RngKey in keys:
		expected.append(_draws(original.stream(key), 10))
	var loot_key: RngKey = RngKey.new(RngKey.RngPurpose.MAP_LOOT, 2, 5, 1, 3)

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
	var fresh_loot: RngStream = RngStreams.new(RUN_SEED).stream(loot_key)
	_check(
			"round trip: an unsaved MAP_LOOT stream starts again from its key",
			resumed.stream(loot_key).capture() == fresh_loot.capture()
	)


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
	all_rejected = all_rejected and not registry.restore_combat({"12:2:5:1:3": good_state})
	all_rejected = all_rejected and not registry.restore_campaign({"12:2:5:1:3": good_state})
	_check(
			"restore: rejects wrong-section, unsaved, unknown, malformed and bad-state entries",
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
