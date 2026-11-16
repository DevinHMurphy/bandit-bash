# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 14, 2026
# Modified: November 16, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the save layer and the lobby admission rules, a case file per topic (each
## one's class doc lists its checks): save_file_cases.gd, profile_settings_cases.gd,
## campaign_cases.gd, section_cases.gd, combat_archive_cases.gd and multiplayer_cases.gd.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/save/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## files make [SaveFile] log errors and warnings on purpose; only FAIL lines mean a problem.[br]
## Works in the cases' scratch folder and deletes it afterwards. The cases run in
## [code]_init[/code], before autoloads exist (in [code]--script[/code] mode they exist from the
## first frame, and their names are unknown while this script compiles), so nothing here may use
## [code]SaveService[/code].

# The test report's line on this suite; tools/run_tests.sh reads it from this one line.
const SUITE_DESCRIPTION: String = "Save files, profile settings, sections, archive, lobby rules"

# Preloaded scripts used as types (gdscript.md, Naming): the case scripts have no class name.
const GroupClock = preload("res://tests/group_clock.gd")
const SaveCaseBase = preload("res://tests/save/save_case_base.gd")
const SaveFileCases = preload("res://tests/save/save_file_cases.gd")
const ProfileSettingsCases = preload("res://tests/save/profile_settings_cases.gd")
const CampaignCases = preload("res://tests/save/campaign_cases.gd")
const SectionCases = preload("res://tests/save/section_cases.gd")
const CombatArchiveCases = preload("res://tests/save/combat_archive_cases.gd")
const MultiplayerCases = preload("res://tests/save/multiplayer_cases.gd")

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Save layer tests. Errors and warnings from SaveFile below are expected. ---")

	GroupClock.lap("save_file_cases")
	SaveFileCases.new(_check).run()
	GroupClock.lap("profile_settings_cases")
	ProfileSettingsCases.new(_check).run()
	GroupClock.lap("campaign_cases")
	CampaignCases.new(_check).run()
	GroupClock.lap("section_cases")
	SectionCases.new(_check).run()
	GroupClock.lap("combat_archive_cases")
	CombatArchiveCases.new(_check).run()
	GroupClock.lap("multiplayer_cases")
	MultiplayerCases.new(_check).run()

	SaveFile.delete_folder(SaveCaseBase.TEST_DIR)
	GroupClock.stop()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])
