# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     save_file.gd
# Author:
# Created:  October 14, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name SaveFile
extends RefCounted
## Reads and writes one save file atomically, recovering from an interrupted write.
##
## Every save file is a JSON envelope built by [method make_envelope]. [method write] goes through
## [code]<path>.tmp[/code] and keeps the previous file as [code]<path>.bak[/code]; [method read]
## picks the newest complete copy of the three and repairs the live file from it.[br]
## [b]Only this class touches save files on disk[/b], so tamper resistance can be added here later
## without changing any caller.[br]
## Static only, with no dependency on the [code]SaveService[/code] autoload: autoloads don't exist
## in [code]--script[/code] mode, and the headless tests in [code]res://tests/save/[/code] drive
## this class directly.
##
## @tutorial(Save system design): docs/design/save-system.md

## Which on-disk copy [method read] returned.
enum Source {
	## [code]<path>[/code], the normal case.
	LIVE = 0,
	## [code]<path>.tmp[/code]: a write that finished but was never renamed into place.
	TEMP = 1,
	## [code]<path>.bak[/code]: the previous save, used because the newer copies were unreadable.
	BACKUP = 2,
}

## Envelope key: schema version of the block's [code]core[/code] and layout. Starts at 1.
const KEY_SCHEMA_VERSION: String = "schema_version"
## Envelope key: [code]application/config/version[/code] of the build that wrote the file.
const KEY_GAME_VERSION: String = "game_version"
## Envelope key: when the file was written, in Unix seconds (UTC).
const KEY_SAVED_AT: String = "saved_at"
## Envelope key: campaign and combat files only; [constant NO_CHECKPOINT] elsewhere.
const KEY_CHECKPOINT_SEQ: String = "checkpoint_seq"
## Envelope key: fields owned by the block's data class.
const KEY_CORE: String = "core"
## Envelope key: section key to [code]{"version": int, "data": Dictionary}[/code].
const KEY_SECTIONS: String = "sections"

## [constant KEY_CHECKPOINT_SEQ] value for files that don't take part in checkpoints.
const NO_CHECKPOINT: int = -1

## Suffix of the in-progress copy.
const TEMP_SUFFIX: String = ".tmp"
## Suffix of the previous-save copy.
const BACKUP_SUFFIX: String = ".bak"

## Project setting that holds the running game version.
const VERSION_SETTING: String = "application/config/version"

# Read order. On a tie in checkpoint_seq and saved_at the earlier source wins, so the live file is
# preferred over a leftover copy holding the same data.
const _SOURCE_ORDER: Array[Source] = [Source.LIVE, Source.TEMP, Source.BACKUP]

# Envelope keys whose values must be numbers. JSON returns every number as a float.
const _NUMERIC_KEYS: Array[String] = [KEY_SCHEMA_VERSION, KEY_SAVED_AT, KEY_CHECKPOINT_SEQ]

# Envelope keys whose values must be dictionaries.
const _DICTIONARY_KEYS: Array[String] = [KEY_CORE, KEY_SECTIONS]


## Returns a new envelope ready for [method write].
##
## [method write] stamps [constant KEY_GAME_VERSION] and [constant KEY_SAVED_AT] itself.
## [param schema_version]: the block's current schema version, 1 or higher.
## [param core]: fields owned by the block's data class.
## [param sections]: section key to [code]{"version": int, "data": Dictionary}[/code].
## [param checkpoint_seq]: campaign and combat files only; [constant NO_CHECKPOINT] elsewhere.
static func make_envelope(
		schema_version: int,
		core: Dictionary,
		sections: Dictionary = {},
		checkpoint_seq: int = NO_CHECKPOINT
) -> Dictionary:
	return {
		KEY_SCHEMA_VERSION: schema_version,
		KEY_GAME_VERSION: get_running_version(),
		KEY_SAVED_AT: 0,
		KEY_CHECKPOINT_SEQ: checkpoint_seq,
		KEY_CORE: core,
		KEY_SECTIONS: sections,
	}


## Writes [param envelope] to [param path] so that a crash at any point leaves a readable copy.
##
## Steps: write and verify [code].tmp[/code]; move the current file to [code].bak[/code]; rename
## [code].tmp[/code] into place. [method read] knows how to finish each interrupted step.
## Creates the parent folder if needed. Floats are written at full precision.
## Returns [constant OK], [constant ERR_INVALID_PARAMETER] for a malformed envelope, or the
## file-system error that stopped the write. The live file is untouched on any error before the
## final rename.
static func write(path: String, envelope: Dictionary) -> Error:
	if not _is_valid_envelope(envelope):
		push_error("SaveFile: refusing to write a malformed envelope to %s" % [path])
		return ERR_INVALID_PARAMETER

	var stamped: Dictionary = envelope.duplicate()
	stamped[KEY_GAME_VERSION] = get_running_version()
	stamped[KEY_SAVED_AT] = int(Time.get_unix_time_from_system())
	var text: String = JSON.stringify(stamped, "\t", false, true)

	var dir_err: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_err != OK:
		push_error("SaveFile: can't create folder for %s - %s" % [path, error_string(dir_err)])
		return dir_err

	var temp_path: String = path + TEMP_SUFFIX
	var temp_err: Error = _write_verified(temp_path, text)
	if temp_err != OK:
		DirAccess.remove_absolute(temp_path)
		push_error("SaveFile: writing %s failed - %s" % [temp_path, error_string(temp_err)])
		return temp_err

	if FileAccess.file_exists(path):
		var backup_err: Error = DirAccess.rename_absolute(path, path + BACKUP_SUFFIX)
		if backup_err != OK:
			DirAccess.remove_absolute(temp_path)
			push_error("SaveFile: backing up %s failed - %s" % [path, error_string(backup_err)])
			return backup_err

	# If this rename fails, the verified .tmp stays on disk and read() promotes it.
	var promote_err: Error = DirAccess.rename_absolute(temp_path, path)
	if promote_err != OK:
		push_error("SaveFile: promoting %s failed - %s" % [temp_path, error_string(promote_err)])
	return promote_err


## Reads the newest complete copy of [param path], repairing the live file if it had to fall back.
##
## Candidates are [code]<path>[/code], [code].tmp[/code] and [code].bak[/code]. Unparsable or
## malformed copies are skipped; the newest of the rest wins, by [constant KEY_CHECKPOINT_SEQ]
## and then [constant KEY_SAVED_AT]. A file from a newer game version is refused untouched.
## When no copy is readable, every file is left in place for inspection.
## Returns a [SaveFile.ReadResult]; check its [member ReadResult.error] first.
static func read(path: String) -> ReadResult:
	var result: ReadResult = ReadResult.new()
	var any_exists: bool = false
	var live_is_valid: bool = false
	var has_best: bool = false

	for source: Source in _SOURCE_ORDER:
		var candidate_path: String = _path_for(path, source)
		if not FileAccess.file_exists(candidate_path):
			continue
		any_exists = true

		var envelope: Dictionary = _parse_file(candidate_path)
		if envelope.is_empty():
			continue
		if source == Source.LIVE:
			live_is_valid = true
		if not has_best or _is_newer(envelope, result.envelope):
			result.envelope = envelope
			result.source = source
			has_best = true

	if not has_best:
		result.envelope = {}
		if not any_exists:
			result.error = ERR_FILE_NOT_FOUND
			return result
		result.error = ERR_FILE_CORRUPT
		push_error("SaveFile: no readable copy of %s; files left for inspection." % [path])
		return result

	var file_version: String = str(result.envelope[KEY_GAME_VERSION])
	if _compare_versions(file_version, get_running_version()) > 0:
		push_error(
				"SaveFile: %s was written by game version %s, newer than this build (%s)."
				% [path, file_version, get_running_version()]
		)
		result.error = ERR_FILE_UNRECOGNIZED
		result.envelope = {}
		return result

	_repair(path, result.source, live_is_valid)
	return result


## True when [param path] or its [code].tmp[/code] or [code].bak[/code] copy exists.
##
## Says nothing about readability; use [method read] for that.
static func exists(path: String) -> bool:
	for source: Source in _SOURCE_ORDER:
		if FileAccess.file_exists(_path_for(path, source)):
			return true
	return false


## Deletes [param path] and its [code].tmp[/code] and [code].bak[/code] copies.
##
## Missing copies are not an error.
## Returns [constant OK] or the first removal error.
static func delete(path: String) -> Error:
	var first_err: Error = OK
	for source: Source in _SOURCE_ORDER:
		var candidate_path: String = _path_for(path, source)
		if not FileAccess.file_exists(candidate_path):
			continue
		var err: Error = DirAccess.remove_absolute(candidate_path)
		if err != OK and first_err == OK:
			first_err = err
			push_error("SaveFile: deleting %s failed - %s" % [candidate_path, error_string(err)])
	return first_err


## Deletes the folder [param dir] and everything in it, subfolders included. Cannot be undone.
##
## Used to delete a whole save file. A missing folder is not an error. Refuses anything that
## isn't a subfolder of [code]user://[/code], so a bad path can't empty the user folder.
## Returns [constant OK], [constant ERR_INVALID_PARAMETER] for a refused path, or the first
## removal error.
static func delete_folder(dir: String) -> Error:
	var base: String = dir if dir.ends_with("/") else dir + "/"
	if not base.begins_with("user://") or base.trim_prefix("user://").trim_suffix("/").is_empty():
		push_error("SaveFile: refusing to delete folder %s" % [dir])
		return ERR_INVALID_PARAMETER
	if not DirAccess.dir_exists_absolute(base):
		return OK

	for sub_dir: String in DirAccess.get_directories_at(base):
		var sub_err: Error = delete_folder(base + sub_dir)
		if sub_err != OK:
			return sub_err
	for file_name: String in DirAccess.get_files_at(base):
		var file_path: String = base + file_name
		var file_err: Error = DirAccess.remove_absolute(file_path)
		if file_err != OK:
			push_error("SaveFile: deleting %s failed - %s" % [file_path, error_string(file_err)])
			return file_err

	var dir_err: Error = DirAccess.remove_absolute(base)
	if dir_err != OK:
		push_error("SaveFile: deleting folder %s failed - %s" % [base, error_string(dir_err)])
	return dir_err


## The running game version, from [constant VERSION_SETTING]. Empty if the setting is missing.
static func get_running_version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, ""))


static func _path_for(path: String, source: Source) -> String:
	match source:
		Source.TEMP:
			return path + TEMP_SUFFIX
		Source.BACKUP:
			return path + BACKUP_SUFFIX
	return path


# Writes text, then reads it back: a full disk can truncate a write without FileAccess reporting
# an error, and the backup rotation in write() must only happen after a known-good copy exists.
static func _write_verified(path: String, text: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var stored: bool = file.store_string(text)
	var store_err: Error = file.get_error()
	file.close()
	if not stored:
		return store_err if store_err != OK else ERR_FILE_CANT_WRITE

	if FileAccess.get_file_as_string(path) != text:
		return ERR_FILE_CANT_WRITE
	return OK


# Returns the parsed envelope, or an empty Dictionary when the file is unreadable or malformed.
# Truncated JSON fails to parse, so a successful parse means the write completed.
static func _parse_file(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	if not _is_valid_envelope(json.data):
		return {}
	var envelope: Dictionary = json.data
	return envelope


# Checks the envelope's shape only. Field contents belong to the block's data class.
static func _is_valid_envelope(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var envelope: Dictionary = data

	for key: String in _NUMERIC_KEYS:
		var value_type: int = typeof(envelope.get(key))
		if value_type != TYPE_INT and value_type != TYPE_FLOAT:
			return false
	for key: String in _DICTIONARY_KEYS:
		if typeof(envelope.get(key)) != TYPE_DICTIONARY:
			return false
	if typeof(envelope.get(KEY_GAME_VERSION)) != TYPE_STRING:
		return false
	return not _parse_version(envelope[KEY_GAME_VERSION] as String).is_empty()


# True when a is newer than b by checkpoint_seq, then saved_at.
static func _is_newer(a: Dictionary, b: Dictionary) -> bool:
	var seq_a: int = a[KEY_CHECKPOINT_SEQ] as int
	var seq_b: int = b[KEY_CHECKPOINT_SEQ] as int
	if seq_a != seq_b:
		return seq_a > seq_b
	return (a[KEY_SAVED_AT] as int) > (b[KEY_SAVED_AT] as int)


# Makes <path> hold the chosen copy and removes a leftover .tmp. Failures are warnings, not errors:
# the caller already has the data, and the next write() replaces every copy anyway.
static func _repair(path: String, chosen: Source, live_is_valid: bool) -> void:
	var temp_path: String = path + TEMP_SUFFIX
	var backup_path: String = path + BACKUP_SUFFIX
	var err: Error = OK

	match chosen:
		Source.TEMP:
			# Finish the interrupted write. Rotating a valid live file keeps the same backup a
			# completed write would have left; a corrupt live file must not overwrite a good .bak.
			if live_is_valid:
				err = DirAccess.rename_absolute(path, backup_path)
			if err == OK:
				err = DirAccess.rename_absolute(temp_path, path)
		Source.BACKUP:
			err = DirAccess.copy_absolute(backup_path, path)

	if chosen != Source.TEMP and FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)

	if chosen == Source.LIVE:
		return
	push_warning("SaveFile: %s recovered from %s." % [path, Source.find_key(chosen)])
	if err != OK:
		push_warning("SaveFile: repairing %s failed - %s" % [path, error_string(err)])


# Returns -1, 0 or 1 comparing dotted numeric versions such as "0.1.0". Missing parts count as 0.
# Returns 0 when either version is malformed, so a bad setting never locks a player out of a save.
static func _compare_versions(a: String, b: String) -> int:
	var parts_a: PackedInt32Array = _parse_version(a)
	var parts_b: PackedInt32Array = _parse_version(b)
	if parts_a.is_empty() or parts_b.is_empty():
		return 0

	var length: int = maxi(parts_a.size(), parts_b.size())
	for i: int in length:
		var part_a: int = parts_a[i] if i < parts_a.size() else 0
		var part_b: int = parts_b[i] if i < parts_b.size() else 0
		if part_a != part_b:
			return 1 if part_a > part_b else -1
	return 0


# Splits "1.2.3" into [1, 2, 3]. Empty result means the text isn't a dotted numeric version.
static func _parse_version(text: String) -> PackedInt32Array:
	var parts: PackedInt32Array = []
	for piece: String in text.split("."):
		if not piece.is_valid_int() or piece.to_int() < 0:
			return PackedInt32Array()
		parts.append(piece.to_int())
	return parts


## Outcome of [method SaveFile.read].
class ReadResult:
	extends RefCounted

	## [constant OK]; [constant ERR_FILE_NOT_FOUND] when no copy exists;
	## [constant ERR_FILE_CORRUPT] when copies exist but none is readable;
	## [constant ERR_FILE_UNRECOGNIZED] when the file comes from a newer game version.
	var error: Error = OK
	## The envelope that was read. Empty unless [member error] is [constant OK].
	var envelope: Dictionary = {}
	## Which copy [member envelope] came from.
	var source: SaveFile.Source = SaveFile.Source.LIVE

	## True when the read succeeded from a copy other than the live file. The UI shows a notice.
	func was_recovered() -> bool:
		return error == OK and source != SaveFile.Source.LIVE
