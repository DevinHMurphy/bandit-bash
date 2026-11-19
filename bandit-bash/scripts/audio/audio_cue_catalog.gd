# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     audio_cue_catalog.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name AudioCueCatalog
extends RefCounted
## Every [AudioCue] under a folder, loaded once and looked up by id.
##
## Walks the folder recursively with [method ResourceLoader.list_directory], as [EffectCatalog]
## does, so a new cue file is found without registering it. An id is unique; when one repeats, the
## first file in path order wins and the repeat is a problem. A file that isn't a sound cue, or
## whose [method AudioCue.problems] isn't empty, is a problem and left out.[br]
## Not part of [EffectCatalog]: that is the rules' catalog, read from sandboxes and other threads,
## and audio is presentation only, so [code]data/audio/[/code] is one of its skipped folders.
## The [code]AudioService[/code] autoload holds one of [constant CUES_ROOT].
##
## @tutorial(Audio scope): docs/design/audio.md

## Where the game's cues live.
const CUES_ROOT: String = "res://data/audio/cues/"

## The folder walked, ending in "/".
var root: String = ""

## What went wrong, one line each. [b]Empty:[/b] every file is a sound cue.
var problems: PackedStringArray = []

var _by_id: Dictionary[StringName, AudioCue] = {}
var _path_by_id: Dictionary[StringName, String] = {}


## Loads every cue under [param folder], logging nothing: its problems are in [member problems].
## [b]Empty:[/b] an empty catalog.
func _init(folder: String = "") -> void:
	if folder.is_empty():
		return
	root = folder if folder.ends_with("/") else folder + "/"
	if not DirAccess.dir_exists_absolute(root):
		problems.append("AudioCueCatalog: no folder %s" % [root])
		return
	_walk(root)


## The cue [param id]; null when there is none.
func cue(id: StringName) -> AudioCue:
	return _by_id.get(id, null)


## Whether there is a cue [param id].
func has_cue(id: StringName) -> bool:
	return _by_id.has(id)


## Every cue id, sorted.
func ids() -> Array[StringName]:
	var all: Array[StringName] = []
	for id: StringName in _by_id:
		all.append(id)
	all.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return all


## The file cue [param id] was loaded from; empty when there is none.
func path_of(id: StringName) -> String:
	return _path_by_id.get(id, "")


func _walk(folder: String) -> void:
	var entries: PackedStringArray = ResourceLoader.list_directory(folder)
	entries.sort()
	for entry: String in entries:
		if entry.ends_with("/"):
			_walk(folder + entry)
		else:
			_add(folder + entry)


func _add(path: String) -> void:
	var loaded: Resource = ResourceLoader.load(path)
	var audio_cue: AudioCue = loaded as AudioCue
	if audio_cue == null:
		problems.append("AudioCueCatalog: %s is not a sound cue" % [path])
		return
	var found: PackedStringArray = audio_cue.problems()
	if not found.is_empty():
		problems.append("AudioCueCatalog: %s - %s" % [path, "; ".join(found)])
		return
	if _by_id.has(audio_cue.id):
		problems.append("AudioCueCatalog: %s repeats id %s from %s" % [
			path, audio_cue.id, _path_by_id[audio_cue.id],
		])
		return
	_by_id[audio_cue.id] = audio_cue
	_path_by_id[audio_cue.id] = path
