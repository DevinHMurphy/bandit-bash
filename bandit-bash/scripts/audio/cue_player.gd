# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     cue_player.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name CuePlayer
extends Node
## Plays sound cues by id from an [AudioCueCatalog], each on its own small pool of voices.
##
## A cue's voices are [AudioStreamPlayer] children made as it first needs them, up to its
## [member AudioCue.voice_limit]; a play with every voice sounding cuts the one started longest
## ago. Pitch and stream variation draw from this node's own [RandomNumberGenerator], seeded from
## the clock and never saved, so playing a sound never touches the global RNG or a run stream
## (Godot_FE's random pitch called the global RNG, which broke its seeds).[br]
## A cue id the catalog doesn't have is reported once and plays nothing. Music cues are not
## played here: the music deck ([MusicDeck]) plays one track at a time.
##
## @tutorial(Audio scope): docs/design/audio.md

## The cues this player reads. [b]Null:[/b] every play is a missing cue.
var catalog: AudioCueCatalog = null

# Cosmetic randomness only: pitch and stream variation.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Each cue's voices, Array[AudioStreamPlayer] each, in creation order.
var _voices: Dictionary[StringName, Array] = {}
# When each voice last started, as a play count, so the oldest is cut first.
var _started: Dictionary[AudioStreamPlayer, int] = {}
var _plays: int = 0
# Cue ids already reported missing.
var _reported: Dictionary[StringName, bool] = {}


func _init() -> void:
	_rng.randomize()


## Plays cue [param id]. Returns whether a voice started: false for a missing cue (reported the
## first time only), a music cue, or a cue that has no stream.
func play(id: StringName) -> bool:
	var audio_cue: AudioCue = catalog.cue(id) if catalog != null else null
	if audio_cue == null:
		if not _reported.has(id):
			_reported[id] = true
			push_error("CuePlayer: no sound cue %s" % [id])
		return false
	if audio_cue.bus == AudioCue.Bus.MUSIC:
		return false
	var stream: AudioStream = audio_cue.pick_stream(_rng)
	if stream == null:
		return false
	var voice: AudioStreamPlayer = _voice_for(audio_cue)
	voice.stop()
	voice.stream = stream
	voice.bus = audio_cue.bus_name()
	voice.volume_db = audio_cue.volume_db
	voice.pitch_scale = audio_cue.pick_pitch(_rng)
	voice.play()
	_plays += 1
	_started[voice] = _plays
	return true


## How many of cue [param id]'s voices are sounding now.
func playing_count(id: StringName) -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in _voices.get(id, []):
		if voice.playing:
			count += 1
	return count


## How many voices cue [param id] has made; never more than its voice limit.
func voice_count(id: StringName) -> int:
	var voices: Array = _voices.get(id, [])
	return voices.size()


## Every voice of cue [param id], for tests. Changing one changes playback.
func get_voices(id: StringName) -> Array[AudioStreamPlayer]:
	var voices: Array[AudioStreamPlayer] = []
	for voice: AudioStreamPlayer in _voices.get(id, []):
		voices.append(voice)
	return voices


## The voice of cue [param id] started last; null when it has none.
func last_started(id: StringName) -> AudioStreamPlayer:
	var latest: AudioStreamPlayer = null
	for voice: AudioStreamPlayer in _voices.get(id, []):
		if latest == null or _started.get(voice, 0) > _started.get(latest, 0):
			latest = voice
	return latest


## Whether cue [param id] has been reported missing.
func is_reported_missing(id: StringName) -> bool:
	return _reported.has(id)


## Stops every voice.
func stop_all() -> void:
	for id: StringName in _voices:
		for voice: AudioStreamPlayer in _voices[id]:
			voice.stop()


## Stops every voice and lets go of its stream, so nothing plays on into shutdown. Returns a weak
## reference to each playback that was sounding, which the audio server frees on a later mix.
func release_all() -> Array[WeakRef]:
	var released: Array[WeakRef] = []
	for id: StringName in _voices:
		for voice: AudioStreamPlayer in _voices[id]:
			if voice.playing and voice.has_stream_playback():
				released.append(weakref(voice.get_stream_playback()))
			voice.stop()
			voice.stream = null
	return released


# A free voice of audio_cue, a new one while under its limit, or else the one started longest ago.
func _voice_for(audio_cue: AudioCue) -> AudioStreamPlayer:
	if not _voices.has(audio_cue.id):
		_voices[audio_cue.id] = []
	var voices: Array = _voices[audio_cue.id]
	for voice: AudioStreamPlayer in voices:
		if not voice.playing:
			return voice
	if voices.size() < audio_cue.voice_limit:
		var made: AudioStreamPlayer = AudioStreamPlayer.new()
		made.name = "%s_%d" % [audio_cue.id, voices.size()]
		add_child(made)
		voices.append(made)
		return made
	var oldest: AudioStreamPlayer = voices[0]
	for voice: AudioStreamPlayer in voices:
		if _started.get(voice, 0) < _started.get(oldest, 0):
			oldest = voice
	return oldest
