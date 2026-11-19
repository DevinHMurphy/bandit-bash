# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     player_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The players: a cue never sounds more voices than its limit, cutting the oldest; random pitch
## stays in the cue's range and a fixed one is exact; a music cue doesn't play as a voice; the
## music deck plays one track, keeps the same one without restarting, crossfades to another,
## ducks and comes back, and stops. Runs on the Dummy driver, which mixes in real time, so every
## check reads state right after the play. [method release] stops everything for the suite to
## wait out before it quits.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "audio"

# A UI cue (2 voices), a sound effect with random pitch (4 voices), a fixed-pitch one, and tracks.
const UI_CUE: StringName = &"menu_cursor"
const RANDOM_CUE: StringName = &"flesh_impact"
const FIXED_CUE: StringName = &"crit_sound"
const TRACK_A: StringName = &"menu_dreaming_darkly"
const TRACK_B: StringName = &"action_knightly_fighting"

# Plays more than any limit, so the limit is what stops the count.
const OVERPLAYS: int = 7

# Tolerance for comparing volumes. Units: dB.
const DB_EPSILON: float = 0.01

var _check: Callable
var _root: Window
var _holder: Node = null
var _cues: CuePlayer = null
var _music: MusicDeck = null


func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	_holder = Node.new()
	_holder.name = "AudioPlayerCases"
	_root.add_child(_holder)
	_cues = CuePlayer.new()
	_cues.catalog = AudioCueCatalog.new(AudioCueCatalog.CUES_ROOT)
	_holder.add_child(_cues)
	_music = MusicDeck.new()
	_music.crossfade_seconds = 0.0
	_music.duck_seconds = 0.0
	_holder.add_child(_music)
	_check_voice_limit()
	_check_pitch()
	_check_music()


## Stops every player these cases made; returns a weak reference to each playback that was
## sounding, which the audio thread frees on a later mix.
func release() -> Array[WeakRef]:
	var released: Array[WeakRef] = []
	if is_instance_valid(_cues):
		released.append_array(_cues.release_all())
	if is_instance_valid(_music):
		released.append_array(_music.release_all())
	return released


## Frees the players; call once the released playbacks are gone.
func free_nodes() -> void:
	if is_instance_valid(_holder):
		_holder.free()


func _check_voice_limit() -> void:
	var ui_limit: int = _cues.catalog.cue(UI_CUE).voice_limit
	var sfx_limit: int = _cues.catalog.cue(RANDOM_CUE).voice_limit
	var all_started: bool = true
	for count: int in OVERPLAYS:
		all_started = _cues.play(UI_CUE) and all_started
		all_started = _cues.play(RANDOM_CUE) and all_started
	_check.call("voices: every play of a cue at its limit still starts", all_started)
	_check.call(
			"voices: a UI cue holds at its limit of %d" % [ui_limit],
			_cues.voice_count(UI_CUE) == ui_limit and _cues.playing_count(UI_CUE) <= ui_limit,
			"%d voices, %d playing" % [_cues.voice_count(UI_CUE), _cues.playing_count(UI_CUE)],
	)
	_check.call(
			"voices: a sound effect holds at its limit of %d" % [sfx_limit],
			_cues.voice_count(RANDOM_CUE) == sfx_limit,
			"%d voices" % [_cues.voice_count(RANDOM_CUE)],
	)
	# Voices start in order 0, 1, 2, 3, then 0, 1, 2 again for plays 5-7, so with every one
	# sounding the next play takes voice 3, started longest ago.
	var voices: Array[AudioStreamPlayer] = _cues.get_voices(RANDOM_CUE)
	var oldest: AudioStreamPlayer = voices[OVERPLAYS % sfx_limit]
	var all_playing: bool = _cues.playing_count(RANDOM_CUE) == sfx_limit
	_cues.play(RANDOM_CUE)
	_check.call(
			"voices: past the limit the oldest voice is the one cut and restarted",
			all_playing and _cues.last_started(RANDOM_CUE) == oldest,
			"all playing: %s" % [all_playing],
	)
	_check.call(
			"voices: a music cue doesn't play as a sound",
			not _cues.play(TRACK_A) and _cues.voice_count(TRACK_A) == 0,
	)
	_check.call(
			"voices: UI cues play on the UI bus, effects on SFX",
			_cues.get_voices(UI_CUE)[0].bus == AudioCue.UI_BUS_NAME
			and voices[0].bus == AudioCue.SFX_BUS_NAME,
	)


func _check_pitch() -> void:
	var random_cue: AudioCue = _cues.catalog.cue(RANDOM_CUE)
	var in_range: bool = true
	for voice: AudioStreamPlayer in _cues.get_voices(RANDOM_CUE):
		if voice.pitch_scale < random_cue.pitch_min or voice.pitch_scale > random_cue.pitch_max:
			in_range = false
	_check.call(
			"pitch: %s's voices pitch within %.2f-%.2f (Godot_FE's range)" % [
				RANDOM_CUE, random_cue.pitch_min, random_cue.pitch_max,
			],
			in_range and random_cue.pitch_min == 0.75 and random_cue.pitch_max == 1.25,
	)
	_cues.play(FIXED_CUE)
	_check.call(
			"pitch: a fixed-pitch cue plays at its pitch",
			_cues.get_voices(FIXED_CUE)[0].pitch_scale == 1.0,
	)


func _check_music() -> void:
	var catalog: AudioCueCatalog = _cues.catalog
	_music.play(catalog.cue(TRACK_A))
	var first: AudioStreamPlayer = _music.get_active_player()
	_check.call(
			"music: a track plays on the Music bus",
			_music.current_id() == TRACK_A
			and first.playing
			and first.bus == AudioCue.MUSIC_BUS_NAME,
	)
	_music.play(catalog.cue(TRACK_A))
	_check.call(
			"music: asking for the track playing keeps it",
			_music.get_active_player() == first and first.playing,
	)
	_music.play(catalog.cue(TRACK_B))
	var second: AudioStreamPlayer = _music.get_active_player()
	_check.call(
			"music: another track takes the other player and the first stops",
			_music.current_id() == TRACK_B and second != first and second.playing
			and not first.playing,
	)
	var full_db: float = _music.current_volume_db()
	_music.set_ducked(true)
	var ducked_db: float = _music.current_volume_db()
	_music.set_ducked(false)
	_check.call(
			"music: ducking lowers the track by %.0f dB and back" % [-_music.duck_db],
			absf(ducked_db - (full_db + _music.duck_db)) < DB_EPSILON
			and absf(_music.current_volume_db() - full_db) < DB_EPSILON,
			"full %.2f, ducked %.2f" % [full_db, ducked_db],
	)
	_music.stop()
	_check.call(
			"music: stop silences the deck",
			_music.current_id().is_empty() and not second.playing,
	)
	_music.play(catalog.cue(TRACK_A), 1.0)
	_check.call(
			"music: a crossfade starts the new track silent",
			_music.current_volume_db() <= linear_to_db(0.01),
			"%.1f dB" % [_music.current_volume_db()],
	)
