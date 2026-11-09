# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     section_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/save/save_case_base.gd"
## [SaveSectionRegistry] cases for tests/save/run_all.gd: capture, restore, reset, migration,
## refusal, raw sections and per-seat player sections.


func run() -> void:
	_test_sections_capture_keeps_unregistered()
	_test_sections_restore_and_reset()
	_test_sections_migrate_and_refuse()
	_test_sections_raw_and_replace()
	_test_player_sections_per_seat()


func _test_sections_capture_keeps_unregistered() -> void:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var unlocks: FakeSection = FakeSection.new("unlocks", 1)
	unlocks.data = {"knight": true}
	registry.register(SaveSection.Block.PROFILE, unlocks)

	var on_disk: Dictionary = {"removed_feature": {"version": 3, "data": {"x": 1}}}
	var captured: Dictionary = registry.capture(SaveSection.Block.PROFILE, on_disk)
	_check(
			"sections capture: unregistered kept",
			(captured.get("removed_feature") == on_disk["removed_feature"]) as bool
	)
	_check(
			"sections capture: registered written with version",
			(captured.get("unlocks") == {"version": 1, "data": {"knight": true}}) as bool
	)
	_check("sections capture: input not modified", not on_disk.has("unlocks"))
	_check(
			"sections capture: other blocks untouched",
			registry.capture(SaveSection.Block.CAMPAIGN, {}).is_empty()
	)


func _test_sections_restore_and_reset() -> void:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var present: FakeSection = FakeSection.new("present", 1)
	var missing: FakeSection = FakeSection.new("missing", 1)
	missing.data = {"stale": true}
	registry.register(SaveSection.Block.CAMPAIGN, present)
	registry.register(SaveSection.Block.CAMPAIGN, missing)

	var sections: Dictionary = {"present": {"version": 1, "data": {"gold": 7}}}
	var err: Error = registry.restore(SaveSection.Block.CAMPAIGN, sections)
	_check("sections restore: OK", err == OK, error_string(err))
	_check("sections restore: data handed over", present.data == {"gold": 7})
	_check(
			"sections restore: missing section reset",
			missing.reset_count == 1 and missing.data.is_empty()
	)

	registry.reset(SaveSection.Block.CAMPAIGN)
	_check("sections reset: every section", present.reset_count == 1 and missing.reset_count == 2)


func _test_sections_migrate_and_refuse() -> void:
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	var upgraded: FakeSection = FakeSection.new("upgraded", 2)
	registry.register(SaveSection.Block.PROFILE, upgraded)
	var err: Error = registry.restore(
			SaveSection.Block.PROFILE, {"upgraded": {"version": 1, "data": {"old": true}}}
	)
	_check("sections migrate: OK", err == OK, error_string(err))
	_check("sections migrate: from version 1", upgraded.migrated_from == 1)
	_check(
			"sections migrate: restored migrated data",
			(upgraded.data.get("migrated") == true) as bool
	)

	var two_phase: SaveSectionRegistry = SaveSectionRegistry.new()
	var fine: FakeSection = FakeSection.new("fine", 1)
	var future: FakeSection = FakeSection.new("future", 1)
	two_phase.register(SaveSection.Block.PROFILE, fine)
	two_phase.register(SaveSection.Block.PROFILE, future)
	var newer: Dictionary = {
		"fine": {"version": 1, "data": {}},
		"future": {"version": 2, "data": {}},
	}
	var newer_err: Error = two_phase.restore(SaveSection.Block.PROFILE, newer)
	_check("sections newer version: refused", newer_err == ERR_FILE_UNRECOGNIZED)
	_check("sections newer version: nothing restored", fine.restore_count == 0)

	var malformed_err: Error = two_phase.restore(
			SaveSection.Block.PROFILE, {"fine": {"version": 1, "data": "not a dictionary"}}
	)
	_check("sections malformed: refused", malformed_err == ERR_INVALID_DATA)

	var no_migration: FakeSection = FakeSection.new("no_migration", 2)
	no_migration.use_default_migrate = true
	var strict: SaveSectionRegistry = SaveSectionRegistry.new()
	strict.register(SaveSection.Block.PROFILE, no_migration)
	var missing_err: Error = strict.restore(
			SaveSection.Block.PROFILE, {"no_migration": {"version": 1, "data": {}}}
	)
	_check("sections default migrate: fails loudly", missing_err == ERR_UNAVAILABLE)

	var refusing: FakeSection = FakeSection.new("refusing", 1)
	refusing.refuse_restore = true
	var picky: SaveSectionRegistry = SaveSectionRegistry.new()
	picky.register(SaveSection.Block.PROFILE, refusing)
	var refused_err: Error = picky.restore(
			SaveSection.Block.PROFILE, {"refusing": {"version": 1, "data": {}}}
	)
	_check("sections restore refusal: reported", refused_err == ERR_INVALID_DATA)


func _test_sections_raw_and_replace() -> void:
	var raw: RawSaveSection = RawSaveSection.new("unlocks")
	raw.restore({"keep": [1, 2]})
	_check("raw section: passes data through", raw.capture() == {"keep": [1, 2]})
	raw.reset()
	_check("raw section: reset empties", raw.capture().is_empty())

	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	registry.register(SaveSection.Block.PROFILE, RawSaveSection.new("unlocks"))
	var real: FakeSection = FakeSection.new("unlocks", 1)
	real.data = {"real": true}
	registry.register(SaveSection.Block.PROFILE, real)
	var captured: Dictionary = registry.capture(SaveSection.Block.PROFILE, {})
	_check(
			"raw section: replaced by the real one",
			(captured["unlocks"]["data"] == {"real": true}) as bool
	)
	_check("raw section: has_section", registry.has_section(SaveSection.Block.PROFILE, "unlocks"))


func _test_player_sections_per_seat() -> void:
	for seat_count: int in [1, 2, 4]:
		var registry: SaveSectionRegistry = SaveSectionRegistry.new()
		var inventory: FakePlayerSection = FakePlayerSection.new()
		registry.register_player(inventory)

		var players: Array[CampaignData.PlayerRun] = []
		for seat: int in seat_count:
			var player: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
			player.seat = seat
			# The last seat has no saved inventory, as if the section was added mid-campaign.
			if seat < seat_count - 1 or seat_count == 1:
				player.sections = {"inventory": {"version": 1, "data": {"items": seat}}}
			players.append(player)

		var label: String = "player sections x%d" % [seat_count]
		var err: Error = registry.restore_players(players)
		_check("%s: OK" % [label], err == OK, error_string(err))
		_check("%s: cleared first" % [label], inventory.clear_count == 1)
		var expected_restores: int = seat_count if seat_count == 1 else seat_count - 1
		_check(
				"%s: restored once per saved seat" % [label],
				inventory.restored_seats.size() == expected_restores
		)
		if seat_count > 1:
			_check(
					"%s: missing seat reset" % [label],
					inventory.reset_seats == [seat_count - 1]
			)

		registry.capture_players(players)
		var all_written: bool = true
		for player: CampaignData.PlayerRun in players:
			var entry: Dictionary = player.sections.get("inventory", {})
			var expected: Dictionary = {"seat": player.seat}
			all_written = all_written and entry.get("data") == expected
		_check("%s: captured into every player" % [label], all_written)

	var fresh: SaveSectionRegistry = SaveSectionRegistry.new()
	var section: FakePlayerSection = FakePlayerSection.new()
	fresh.register_player(section)
	var two: Array[CampaignData.PlayerRun] = [
		CampaignData.PlayerRun.new(),
		CampaignData.PlayerRun.new(),
	]
	two[1].seat = 1
	fresh.reset_players(two)
	_check(
			"player sections reset: clear then each seat",
			section.clear_count == 1 and section.reset_seats == [0, 1]
	)


## A file-level section that records what the registry asked of it.
class FakeSection:
	extends SaveSection

	var key: String = ""
	var version: int = 1
	var data: Dictionary = {}
	var restore_count: int = 0
	var reset_count: int = 0
	var migrated_from: int = 0
	var refuse_restore: bool = false
	var use_default_migrate: bool = false

	func _init(section_key: String, section_version: int) -> void:
		key = section_key
		version = section_version

	func get_key() -> String:
		return key

	func get_version() -> int:
		return version

	func capture() -> Dictionary:
		return data.duplicate(true)

	func restore(restored: Dictionary) -> Error:
		restore_count += 1
		if refuse_restore:
			return ERR_INVALID_DATA
		data = restored
		return OK

	func reset() -> void:
		reset_count += 1
		data = {}

	func migrate(old: Dictionary, from_version: int) -> Error:
		if use_default_migrate:
			return super.migrate(old, from_version)
		migrated_from = from_version
		old["migrated"] = true
		return OK


## A per-player section that records which seats it was asked about.
class FakePlayerSection:
	extends PlayerSaveSection

	var restored_seats: Array[int] = []
	var reset_seats: Array[int] = []
	var clear_count: int = 0

	func get_key() -> String:
		return "inventory"

	func get_version() -> int:
		return 1

	func capture(seat: int) -> Dictionary:
		return {"seat": seat}

	func restore(seat: int, _data: Dictionary) -> Error:
		restored_seats.append(seat)
		return OK

	func reset(seat: int) -> void:
		reset_seats.append(seat)

	func clear() -> void:
		clear_count += 1
		restored_seats.clear()
		reset_seats.clear()
