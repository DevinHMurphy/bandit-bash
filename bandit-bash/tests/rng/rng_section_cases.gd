# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_section_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/rng/rng_case_base.gd"
## Save section cases for tests/rng/run_all.gd ([RngSaveSection]): the contract, a round trip
## through JSON into a new run, holding data until attached, resets and refused entries. The
## sections through the real [code]SaveService[/code] are in the sessions suite.


func run() -> void:
	_test_save_section_contract()
	_test_save_section_round_trip(SaveSection.Block.CAMPAIGN)
	_test_save_section_round_trip(SaveSection.Block.COMBAT)
	_test_save_section_holds_until_attached()
	_test_save_section_resets()
	_test_save_section_rejects_bad_entries(SaveSection.Block.CAMPAIGN)
	_test_save_section_rejects_bad_entries(SaveSection.Block.COMBAT)
	_test_save_sections_skip_unsaved_purposes()


func _test_save_section_contract() -> void:
	for block: SaveSection.Block in [SaveSection.Block.CAMPAIGN, SaveSection.Block.COMBAT]:
		var section: RngSaveSection = RngSaveSection.new(block)
		var label: String = _block_label(block)
		_check(
				"rng section %s: key rng, version 1" % [label],
				section.get_key() == "rng" and section.get_version() == 1
		)
		_check(
				"rng section %s: empty with no session and nothing held" % [label],
				section.capture().is_empty()
		)
	print("    (one error about an rng section without a session follows)")
	_check(
			"rng section: attach refuses null",
			RngSaveSection.new(SaveSection.Block.CAMPAIGN).attach(null) == ERR_INVALID_PARAMETER
	)


# Capture from one run, through JSON, restore and attach to a new run: the block's streams
# continue exactly where they were, and the other block's streams start from their keys.
func _test_save_section_round_trip(block: SaveSection.Block) -> void:
	var label: String = _block_label(block)
	var live: CampaignSession = _session_with_every_section()
	var saving: RngSaveSection = RngSaveSection.new(block)
	saving.attach(live)
	var captured: Dictionary = saving.capture()
	var has_big_state: bool = false
	for state: Variant in captured.values():
		var value: int = _from_hex(state as String)
		has_big_state = has_big_state or value > JSON_EXACT_LIMIT or value < -JSON_EXACT_LIMIT
	_check("rng section %s: some state is above 2^53" % [label], has_big_state)

	var keys: Array[RngKey] = _keys_of(captured)
	var expected: Array = []
	for key: RngKey in keys:
		expected.append(_draws(live.rng.stream(key), 10))

	var json_data: Variant = JSON.parse_string(JSON.stringify(captured))
	var loading: RngSaveSection = RngSaveSection.new(block)
	var resumed: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0, 1])
	)
	var restored: Error = loading.restore(json_data as Dictionary)
	var attached: Error = loading.attach(resumed)
	_check(
			"rng section %s: restore and attach accept the JSON" % [label],
			restored == OK and attached == OK
	)
	_check(
			"rng section %s: the attached run captures the saved data" % [label],
			loading.capture() == captured
	)
	var actual: Array = []
	for key: RngKey in keys:
		actual.append(_draws(resumed.rng.stream(key), 10))
	_check(
			"rng section %s: every stream continues identically (%d streams)"
			% [label, keys.size()],
			keys.size() >= 2 and actual == expected
	)
	var other: Dictionary = (
			resumed.rng.capture_campaign() if block == SaveSection.Block.COMBAT
			else resumed.rng.capture_combat()
	)
	_check("rng section %s: the other block's streams aren't restored" % [label], other.is_empty())


func _test_save_section_holds_until_attached() -> void:
	var saved: Dictionary = _session_with_every_section().rng.capture_campaign()
	var live: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var shop: RngStream = live.rng.stream(RngKey.new(RngKey.RngPurpose.SHOP_STOCK, 4, 4))
	_draws(shop, 3)
	var live_before: Dictionary = live.rng.capture_campaign()
	var section: RngSaveSection = RngSaveSection.new(SaveSection.Block.CAMPAIGN)
	section.attach(live)

	_check("rng section: restore accepts the data", section.restore(saved) == OK)
	_check(
			"rng section: restore leaves the attached run's registry alone",
			live.rng.capture_campaign() == live_before
			and is_same(live.rng.stream(RngKey.new(RngKey.RngPurpose.SHOP_STOCK, 4, 4)), shop)
	)
	_check(
			"rng section: until attached, capture returns the held data",
			section.capture() == saved
	)

	var built: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	section.attach(built)
	_check(
			"rng section: attach applies the held data to the new run",
			built.rng.capture_campaign() == saved
	)
	section.detach()
	_check("rng section: once applied, nothing is held", section.capture().is_empty())


# A campaign reset belongs to a new run or none; a combat reset happens at Begin, while the run's
# battle streams are live.
func _test_save_section_resets() -> void:
	var live: CampaignSession = _session_with_every_section()
	var campaign: RngSaveSection = RngSaveSection.new(SaveSection.Block.CAMPAIGN)
	var combat: RngSaveSection = RngSaveSection.new(SaveSection.Block.COMBAT)
	campaign.attach(live)
	combat.attach(live)
	campaign.reset()
	combat.reset()
	_check("rng section: a campaign reset lets go of the run", campaign.capture().is_empty())
	_check(
			"rng section: a combat reset keeps reading the run",
			combat.capture() == live.rng.capture_combat() and not combat.capture().is_empty()
	)

	var held: RngSaveSection = RngSaveSection.new(SaveSection.Block.COMBAT)
	held.restore(live.rng.capture_combat())
	held.reset()
	var fresh: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	held.attach(fresh)
	_check(
			"rng section: a reset drops the held data, so nothing is applied",
			held.capture().is_empty() and fresh.rng.capture_combat().is_empty()
	)


# A bad entry fails the load through the real section registry, and neither the run's registry
# nor what the section reads changes.
func _test_save_section_rejects_bad_entries(block: SaveSection.Block) -> void:
	var label: String = _block_label(block)
	var live: CampaignSession = _session_with_every_section()
	var section: RngSaveSection = RngSaveSection.new(block)
	section.attach(live)
	var registry: SaveSectionRegistry = SaveSectionRegistry.new()
	registry.register(block, section)
	var campaign_before: Dictionary = live.rng.capture_campaign()
	var combat_before: Dictionary = live.rng.capture_combat()
	var rolls_key: RngKey = RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 2, 5, 0)
	var reward_key: RngKey = RngKey.new(RngKey.RngPurpose.REWARD, 2, 5, 0)
	var rolls: RngStream = live.rng.stream(rolls_key)
	var reward: RngStream = live.rng.stream(reward_key)

	var good_state: String = "62431fcec4f6c10e"
	var own_key: String = "13:2:5:0:-1" if block == SaveSection.Block.COMBAT else "9:2:5:0:-1"
	var other_key: String = "9:2:5:0:-1" if block == SaveSection.Block.COMBAT else "13:2:5:0:-1"
	var bad_data: Array[Dictionary] = [
		{"99:0:0:0:0": good_state},
		{other_key: good_state},
		{"12:2:5:1:3": good_state},
		{own_key: 7.0},
		{own_key: good_state, "x": good_state},
	]
	print("    (errors from %d refused %s rng sections follow)" % [bad_data.size(), label])
	var all_failed: bool = true
	for data: Dictionary in bad_data:
		var err: Error = registry.restore(block, {"rng": {"version": 1, "data": data}})
		all_failed = all_failed and err != OK
	_check(
			"rng section %s: unknown, other-block, unsaved and non-string entries fail the load"
			% [label],
			all_failed
	)
	_check(
			"rng section %s: a failed load leaves the run's registry untouched" % [label],
			live.rng.capture_campaign() == campaign_before
			and live.rng.capture_combat() == combat_before
			and is_same(live.rng.stream(rolls_key), rolls)
			and is_same(live.rng.stream(reward_key), reward)
	)
	var still_reads_run: bool = (
			section.capture() == combat_before if block == SaveSection.Block.COMBAT
			else section.capture() == campaign_before
	)
	_check("rng section %s: and the section still reads the run" % [label], still_reads_run)


func _test_save_sections_skip_unsaved_purposes() -> void:
	var live: CampaignSession = _session_with_every_section()
	var loot_key: String = RngKey.new(RngKey.RngPurpose.MAP_LOOT, 2, 5, 1, 3).to_save_key()
	var setup_key: String = RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5).to_save_key()
	var campaign: RngSaveSection = RngSaveSection.new(SaveSection.Block.CAMPAIGN)
	var combat: RngSaveSection = RngSaveSection.new(SaveSection.Block.COMBAT)
	campaign.attach(live)
	combat.attach(live)
	var captured: Dictionary = campaign.capture()
	captured.merge(combat.capture())
	_check(
			"rng sections: a MAP_LOOT stream is in neither capture",
			not captured.has(loot_key) and not captured.is_empty()
	)
	_check("rng sections: nor is an ENCOUNTER_SETUP stream", not captured.has(setup_key))


# A two-seat run whose registry has the same streams as _registry_with_every_section().
func _session_with_every_section() -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	var fixture: RngStreams = _registry_with_every_section()
	var restored: bool = session.rng.restore_campaign(fixture.capture_campaign())
	restored = session.rng.restore_combat(fixture.capture_combat()) and restored
	for unsaved: RngKey in [
		RngKey.new(RngKey.RngPurpose.ENCOUNTER_SETUP, 2, 5),
		RngKey.new(RngKey.RngPurpose.MAP_LOOT, 2, 5, 1, 3),
	]:
		_draws(session.rng.stream(unsaved), 2)
	if not restored:
		push_error("rng tests: the fixture run didn't restore")
	return session


# The keys of captured section data, in its order.
func _keys_of(data: Dictionary) -> Array[RngKey]:
	var keys: Array[RngKey] = []
	for save_key: Variant in data:
		keys.append(RngKey.from_save_key(save_key as String))
	return keys


func _block_label(block: SaveSection.Block) -> String:
	return "combat" if block == SaveSection.Block.COMBAT else "campaign"
