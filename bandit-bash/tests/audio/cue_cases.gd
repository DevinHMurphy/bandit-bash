# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     cue_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The cue catalog: every cue in [code]data/audio/cues/[/code] loads with its streams and no
## problem; every file in [code]assets/audio/[/code] has a cue, music on the Music bus and looping;
## the cue resource reports a cue that can't play; and a missing cue is reported once and plays
## nothing.

# Every audio file AU1 brought over from Godot_FE: 54 sounds and 8 tracks.
const AUDIO_ROOT: String = "res://assets/audio/"
const EXPECTED_FILES: int = 62
# The files plus ui_refused, a second cue on menu_back.ogg.
const EXPECTED_CUES: int = 63

var _check: Callable
var _root: Window


func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	var catalog: AudioCueCatalog = AudioCueCatalog.new(AudioCueCatalog.CUES_ROOT)
	_check.call(
			"cues: the catalog loads with no problem",
			catalog.problems.is_empty(),
			"; ".join(catalog.problems),
	)
	_check.call(
			"cues: %d cues load" % [EXPECTED_CUES],
			catalog.ids().size() == EXPECTED_CUES,
			"found %d" % [catalog.ids().size()],
	)
	_check_streams(catalog)
	_check_files_have_cues(catalog)
	_check_bad_cue()
	_check_missing_cue(catalog)


func _check_streams(catalog: AudioCueCatalog) -> void:
	var bad: PackedStringArray = []
	var not_looping: PackedStringArray = []
	for id: StringName in catalog.ids():
		var audio_cue: AudioCue = catalog.cue(id)
		if audio_cue.streams.is_empty() or audio_cue.streams[0] == null:
			bad.append(String(id))
			continue
		if audio_cue.streams[0].get_length() <= 0.0:
			bad.append("%s (no length)" % [id])
		if audio_cue.bus == AudioCue.Bus.MUSIC:
			var track: AudioStreamOggVorbis = audio_cue.streams[0] as AudioStreamOggVorbis
			if track == null or not track.loop:
				not_looping.append(String(id))
	_check.call("cues: every cue's stream loads and has a length", bad.is_empty(), ", ".join(bad))
	_check.call(
			"cues: every music track loops, as Godot_FE's did",
			not_looping.is_empty(),
			", ".join(not_looping),
	)


func _check_files_have_cues(catalog: AudioCueCatalog) -> void:
	var used: Dictionary[String, bool] = {}
	for id: StringName in catalog.ids():
		for stream: AudioStream in catalog.cue(id).streams:
			used[stream.resource_path] = true
	var files: PackedStringArray = []
	_collect(AUDIO_ROOT, files)
	var orphans: PackedStringArray = []
	for path: String in files:
		if not used.has(path):
			orphans.append(path)
	_check.call(
			"cues: assets/audio holds %d audio files" % [EXPECTED_FILES],
			files.size() == EXPECTED_FILES,
			"found %d" % [files.size()],
	)
	_check.call("cues: every audio file has a cue", orphans.is_empty(), ", ".join(orphans))
	var music_on_music_bus: bool = true
	for id: StringName in catalog.ids():
		var audio_cue: AudioCue = catalog.cue(id)
		var is_music_file: bool = audio_cue.streams[0].resource_path.begins_with(
				AUDIO_ROOT + "music/"
		)
		if is_music_file != (audio_cue.bus == AudioCue.Bus.MUSIC):
			music_on_music_bus = false
	_check.call(
			"cues: exactly the music files' cues are on the Music bus", music_on_music_bus
	)


func _check_bad_cue() -> void:
	var bad: AudioCue = AudioCue.new()
	bad.pitch_min = 1.5
	bad.pitch_max = 1.0
	bad.voice_limit = 0
	var found: PackedStringArray = bad.problems()
	_check.call(
			"cues: no id, no streams, reversed pitches and no voices: 4 problems",
			found.size() == 4,
			"; ".join(found),
	)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	_check.call("cues: a cue with no stream picks none", bad.pick_stream(rng) == null)


func _check_missing_cue(catalog: AudioCueCatalog) -> void:
	var player: CuePlayer = CuePlayer.new()
	player.catalog = catalog
	_root.add_child(player)
	print("--- An error for the missing cue no_such_cue is expected once below. ---")
	var first: bool = player.play(&"no_such_cue")
	var second: bool = player.play(&"no_such_cue")
	_check.call(
			"cues: a missing cue plays nothing and is reported",
			not first and not second and player.is_reported_missing(&"no_such_cue"),
	)
	_check.call(
			"cues: a missing cue makes no voice",
			player.voice_count(&"no_such_cue") == 0 and player.get_child_count() == 0,
	)
	player.free()


func _collect(folder: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(folder + sub + "/", out)
	for file: String in dir.get_files():
		if file.ends_with(".import") or file.ends_with(".md") or file.ends_with(".uid"):
			continue
		out.append(folder + file)
