# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 14, 2026
# Modified: October 14, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the save file layer ([SaveFile], [SaveMigrations]).
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/save/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in broken
## files make [SaveFile] log errors and warnings on purpose; only FAIL lines mean a problem.[br]
## Works in [constant TEST_DIR] and deletes it afterwards. Autoloads don't exist in
## [code]--script[/code] mode, so nothing here may use [code]SaveService[/code].

## Scratch folder for test files. Emptied before and after the run.
const TEST_DIR: String = "user://test_saves/"

## A file path inside [constant TEST_DIR] used by most cases.
const TEST_PATH: String = TEST_DIR + "test.json"

# Text that can't parse as JSON, standing in for a write cut off by a crash.
const TRUNCATED_JSON: String = "{\"schema_version\": 1, \"core\": {"

# A real Steam id. Above 2^53, so it can't survive as a JSON number.
const STEAM_ID: String = "76561198000000001"

var _failures: int = 0
var _passes: int = 0


func _init() -> void:
	print("--- Save layer tests. Errors and warnings from SaveFile below are expected. ---")
	_clear_test_dir()

	_test_round_trip()
	_test_write_rotates_backup()
	_test_steam_id_and_float_precision()
	_test_crash_while_writing_temp()
	_test_crash_before_backup_rotation()
	_test_crash_before_final_rename()
	_test_corrupt_live_uses_backup()
	_test_all_copies_corrupt()
	_test_missing_file()
	_test_newer_game_version_refused()
	_test_malformed_envelope_not_written()
	_test_version_comparison()
	_test_migrations_run_in_order()
	_test_migrations_reject_bad_versions()

	_clear_test_dir()
	DirAccess.remove_absolute(TEST_DIR)
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_round_trip() -> void:
	_clear_test_dir()
	var sections: Dictionary = {"unlocks": {"version": 1, "data": {"knight": true}}}
	var envelope: Dictionary = SaveFile.make_envelope(1, {"name": "Ada", "count": 3}, sections)
	var write_err: Error = SaveFile.write(TEST_PATH, envelope)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("round trip: write OK", write_err == OK, error_string(write_err))
	_check("round trip: read OK", result.error == OK, error_string(result.error))
	_check("round trip: from live file", result.source == SaveFile.Source.LIVE)
	_check("round trip: string field", _core(result).get("name") == "Ada")
	_check("round trip: int field", int(_core(result).get("count", 0)) == 3)
	var data: Dictionary = result.envelope[SaveFile.KEY_SECTIONS]["unlocks"]["data"]
	_check("round trip: section data", data.get("knight") == true)
	_check(
			"round trip: game version stamped",
			result.envelope[SaveFile.KEY_GAME_VERSION] == SaveFile.get_running_version()
	)
	_check("round trip: saved_at stamped", int(result.envelope[SaveFile.KEY_SAVED_AT]) > 0)
	_check("round trip: no .tmp left", not FileAccess.file_exists(_temp()))
	_check("round trip: first write makes no .bak", not FileAccess.file_exists(_backup()))


func _test_write_rotates_backup() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	SaveFile.write(TEST_PATH, _envelope_with_seq(2))

	_check("rotation: live holds newest", _seq_on_disk(TEST_PATH) == 2)
	_check("rotation: .bak holds previous", _seq_on_disk(_backup()) == 1)
	_check("rotation: no .tmp left", not FileAccess.file_exists(_temp()))


func _test_steam_id_and_float_precision() -> void:
	_clear_test_dir()
	var ratio: float = 0.1 + 0.2
	SaveFile.write(TEST_PATH, SaveFile.make_envelope(1, {"steam_id": STEAM_ID, "ratio": ratio}))
	var core: Dictionary = _core(SaveFile.read(TEST_PATH))

	var steam_id_back: int = str(core.get("steam_id")).to_int()
	var ratio_back: float = float(core.get("ratio", 0.0))
	_check("precision: Steam id exact as string", core.get("steam_id") == STEAM_ID)
	_check("precision: Steam id converts back exactly", steam_id_back == 76561198000000001)
	_check("precision: float exact", ratio_back == ratio, str(ratio_back))


# Crash during save step 1: the .tmp is incomplete, the live file is untouched.
func _test_crash_while_writing_temp() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	_write_raw(_temp(), TRUNCATED_JSON)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("crash in step 1: read OK", result.error == OK, error_string(result.error))
	_check("crash in step 1: uses live", result.source == SaveFile.Source.LIVE)
	_check("crash in step 1: live data", _seq(result) == 1)
	_check("crash in step 1: broken .tmp removed", not FileAccess.file_exists(_temp()))
	_check("crash in step 1: not reported as recovered", not result.was_recovered())


# Crash after step 1, before step 2: a complete newer .tmp beside a valid older live file.
func _test_crash_before_backup_rotation() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	_write_raw(_temp(), _envelope_text(2, SaveFile.get_running_version()))
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("crash before step 2: read OK", result.error == OK, error_string(result.error))
	_check("crash before step 2: uses .tmp", result.source == SaveFile.Source.TEMP)
	_check("crash before step 2: newest data", _seq(result) == 2)
	_check("crash before step 2: live repaired", _seq_on_disk(TEST_PATH) == 2)
	_check("crash before step 2: old live became .bak", _seq_on_disk(_backup()) == 1)
	_check("crash before step 2: .tmp gone", not FileAccess.file_exists(_temp()))
	_check("crash before step 2: reported as recovered", result.was_recovered())


# Crash between steps 2 and 3: no live file, .bak holds the previous save, .tmp the new one.
func _test_crash_before_final_rename() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	SaveFile.write(TEST_PATH, _envelope_with_seq(2))
	DirAccess.rename_absolute(TEST_PATH, _temp())
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("crash before step 3: read OK", result.error == OK, error_string(result.error))
	_check("crash before step 3: uses .tmp", result.source == SaveFile.Source.TEMP)
	_check("crash before step 3: newest data", _seq(result) == 2)
	_check("crash before step 3: live restored", _seq_on_disk(TEST_PATH) == 2)
	_check("crash before step 3: .bak kept", _seq_on_disk(_backup()) == 1)
	_check("crash before step 3: .tmp gone", not FileAccess.file_exists(_temp()))


func _test_corrupt_live_uses_backup() -> void:
	_clear_test_dir()
	SaveFile.write(TEST_PATH, _envelope_with_seq(1))
	SaveFile.write(TEST_PATH, _envelope_with_seq(2))
	_write_raw(TEST_PATH, TRUNCATED_JSON)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check("corrupt live: read OK", result.error == OK, error_string(result.error))
	_check("corrupt live: uses .bak", result.source == SaveFile.Source.BACKUP)
	_check("corrupt live: backup data", _seq(result) == 1)
	_check("corrupt live: live repaired from .bak", _seq_on_disk(TEST_PATH) == 1)
	_check("corrupt live: .bak kept", _seq_on_disk(_backup()) == 1)
	_check("corrupt live: reported as recovered", result.was_recovered())


func _test_all_copies_corrupt() -> void:
	_clear_test_dir()
	_write_raw(TEST_PATH, TRUNCATED_JSON)
	_write_raw(_temp(), TRUNCATED_JSON)
	_write_raw(_backup(), "not json at all")
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check(
			"all corrupt: ERR_FILE_CORRUPT",
			result.error == ERR_FILE_CORRUPT,
			error_string(result.error)
	)
	_check("all corrupt: empty envelope", result.envelope.is_empty())
	_check(
			"all corrupt: files left for inspection",
			FileAccess.file_exists(TEST_PATH)
			and FileAccess.file_exists(_temp())
			and FileAccess.file_exists(_backup())
	)


func _test_missing_file() -> void:
	_clear_test_dir()
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check(
			"missing: ERR_FILE_NOT_FOUND",
			result.error == ERR_FILE_NOT_FOUND,
			error_string(result.error)
	)
	_check("missing: not reported as recovered", not result.was_recovered())


func _test_newer_game_version_refused() -> void:
	_clear_test_dir()
	var text: String = _envelope_text(1, "999.0.0")
	_write_raw(TEST_PATH, text)
	var result: SaveFile.ReadResult = SaveFile.read(TEST_PATH)

	_check(
			"newer version: ERR_FILE_UNRECOGNIZED",
			result.error == ERR_FILE_UNRECOGNIZED,
			error_string(result.error)
	)
	_check("newer version: empty envelope", result.envelope.is_empty())
	_check("newer version: file untouched", FileAccess.get_file_as_string(TEST_PATH) == text)


func _test_malformed_envelope_not_written() -> void:
	_clear_test_dir()
	var err: Error = SaveFile.write(TEST_PATH, {"core": {}})

	_check(
			"malformed write: ERR_INVALID_PARAMETER",
			err == ERR_INVALID_PARAMETER,
			error_string(err)
	)
	_check("malformed write: nothing on disk", not FileAccess.file_exists(TEST_PATH))


# Exercises version ordering through read(): a file is refused only when strictly newer.
func _test_version_comparison() -> void:
	var running: String = SaveFile.get_running_version()
	_check(
			"version: running version is set",
			not running.is_empty(),
			"set application/config/version"
	)

	var cases: Dictionary[String, bool] = {
		running: true,
		"0.0.1": true,
		running + ".0": true,
		running + ".1": false,
	}
	for version: String in cases:
		_clear_test_dir()
		_write_raw(TEST_PATH, _envelope_text(1, version))
		var accepted: bool = SaveFile.read(TEST_PATH).error == OK
		_check("version: %s accepted=%s" % [version, cases[version]], accepted == cases[version])


func _test_migrations_run_in_order() -> void:
	var steps: Array[Callable] = [_step_add_gold, _step_rename_gold]

	var from_one: Dictionary = SaveFile.make_envelope(1, {})
	var err_one: Error = SaveMigrations.run(from_one, 3, steps)
	var core_one: Dictionary = from_one[SaveFile.KEY_CORE]
	_check("migrate 1->3: OK", err_one == OK, error_string(err_one))
	_check(
			"migrate 1->3: both steps ran",
			core_one.get("coins") == 100 and not core_one.has("gold")
	)
	_check("migrate 1->3: version set", int(from_one[SaveFile.KEY_SCHEMA_VERSION]) == 3)

	var from_two: Dictionary = SaveFile.make_envelope(2, {"gold": 7})
	SaveMigrations.run(from_two, 3, steps)
	var core_two: Dictionary = from_two[SaveFile.KEY_CORE]
	_check("migrate 2->3: only the last step ran", core_two.get("coins") == 7)

	var current: Dictionary = SaveFile.make_envelope(3, {"coins": 5})
	var err_current: Error = SaveMigrations.run(current, 3, steps)
	var core_current: Dictionary = current[SaveFile.KEY_CORE]
	_check("migrate 3->3: no-op", err_current == OK and core_current.get("coins") == 5)


func _test_migrations_reject_bad_versions() -> void:
	var steps: Array[Callable] = [_step_add_gold, _step_rename_gold]
	var too_new: Error = SaveMigrations.run(SaveFile.make_envelope(4, {}), 3, steps)
	var too_old: Error = SaveMigrations.run(SaveFile.make_envelope(0, {}), 3, steps)
	var wrong_steps: Error = SaveMigrations.run(SaveFile.make_envelope(1, {}), 3, [_step_add_gold])
	var failing: Error = SaveMigrations.run(SaveFile.make_envelope(1, {}), 2, [_step_fail])

	_check(
			"migrate: newer schema refused",
			too_new == ERR_FILE_UNRECOGNIZED,
			error_string(too_new)
	)
	_check("migrate: schema 0 refused", too_old == ERR_INVALID_DATA, error_string(too_old))
	_check("migrate: step count mismatch", wrong_steps == ERR_BUG, error_string(wrong_steps))
	_check("migrate: failing step reported", failing == ERR_INVALID_DATA, error_string(failing))


func _step_add_gold(envelope: Dictionary) -> Error:
	envelope[SaveFile.KEY_CORE]["gold"] = 100
	return OK


func _step_rename_gold(envelope: Dictionary) -> Error:
	var core: Dictionary = envelope[SaveFile.KEY_CORE]
	core["coins"] = core.get("gold", 0)
	core.erase("gold")
	return OK


func _step_fail(_envelope: Dictionary) -> Error:
	return ERR_INVALID_DATA


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])


func _envelope_with_seq(seq: int) -> Dictionary:
	return SaveFile.make_envelope(1, {"seq_marker": seq}, {}, seq)


# A complete envelope as raw text, for planting files a crash would leave behind.
func _envelope_text(seq: int, game_version: String) -> String:
	var envelope: Dictionary = SaveFile.make_envelope(1, {"seq_marker": seq}, {}, seq)
	envelope[SaveFile.KEY_GAME_VERSION] = game_version
	envelope[SaveFile.KEY_SAVED_AT] = 1
	return JSON.stringify(envelope)


func _core(result: SaveFile.ReadResult) -> Dictionary:
	if result.error != OK:
		return {}
	return result.envelope[SaveFile.KEY_CORE]


func _seq(result: SaveFile.ReadResult) -> int:
	return int(_core(result).get("seq_marker", -1))


# Reads checkpoint_seq straight from one file on disk, bypassing SaveFile's recovery.
func _seq_on_disk(path: String) -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return -1
	var envelope: Dictionary = data
	return int(envelope.get(SaveFile.KEY_CHECKPOINT_SEQ, -1))


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_err: Error = FileAccess.get_open_error()
		push_error("run_all: can't open %s - %s" % [path, error_string(open_err)])
		return
	file.store_string(text)
	file.close()


func _clear_test_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for file_name: String in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR + file_name)


func _temp() -> String:
	return TEST_PATH + SaveFile.TEMP_SUFFIX


func _backup() -> String:
	return TEST_PATH + SaveFile.BACKUP_SUFFIX
