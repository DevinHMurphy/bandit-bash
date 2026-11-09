# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_case_base.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends RefCounted
## Shared by the save suite's case files: reporting through the runner's check, the scratch
## folder, and the helpers more than one of them uses.

## Scratch folder for test files. Emptied before and after the run.
const TEST_DIR: String = "user://test_saves/"

## A file path inside [constant TEST_DIR] used by most cases.
const TEST_PATH: String = TEST_DIR + "test.json"

# A real Steam id. Above 2^53, so it can't survive as a JSON number.
const STEAM_ID: String = "76561198000000001"

var _report: Callable


func _init(check: Callable) -> void:
	_report = check


func _core(result: SaveFile.ReadResult) -> Dictionary:
	if result.error != OK:
		return {}
	return result.envelope[SaveFile.KEY_CORE]


func _clear_test_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for file_name: String in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR + file_name)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
