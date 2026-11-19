# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     music_deck.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MusicDeck
extends Node
## Plays one music track at a time on the Music bus, crossfading between tracks.
##
## Two [AudioStreamPlayer] children take turns: a new track fades in on the idle one while the
## old one fades out and stops. Asking for the track already playing does nothing, so a screen
## that keeps the same music never restarts it (as Godot_FE's [code]play_music[/code] did).
## Ducking lowers whichever track plays by [member duck_db] without touching the bus, so the
## player's Music volume ([SettingsData]) stays as set. Fades run on this node's tweens, so they
## follow its process mode.
##
## @tutorial(Audio scope): docs/design/audio.md

# ASSUMPTION: a 1 s crossfade; Godot_FE cut between tracks with no fade.
## Default fade between tracks. [b]Units:[/b] seconds.
const DEFAULT_CROSSFADE_SECONDS: float = 1.0
# ASSUMPTION: ducking lowers the music by 10 dB over 0.25 s; Godot_FE never ducked.
## Default duck depth. [b]Units:[/b] dB.
const DEFAULT_DUCK_DB: float = -10.0
## Default time to duck or come back. [b]Units:[/b] seconds.
const DEFAULT_DUCK_SECONDS: float = 0.25

# Quietest gain a fade reaches before the player stops: -80 dB, the settings' mute level.
const _SILENT_GAIN: float = 0.0001

## Fade between tracks, and of a stop with no time given. [b]Units:[/b] seconds. [b]0:[/b] cut.
var crossfade_seconds: float = DEFAULT_CROSSFADE_SECONDS
## How far a duck lowers the music. [b]Units:[/b] dB, at most 0. [b]0:[/b] no duck.
var duck_db: float = DEFAULT_DUCK_DB
## Time a duck takes to go down or come back. [b]Units:[/b] seconds. [b]0:[/b] at once.
var duck_seconds: float = DEFAULT_DUCK_SECONDS

var _players: Array[AudioStreamPlayer] = []
# Each player's fade gain, 0 to 1, and its track's own volume (AudioCue.volume_db).
var _gains: Array[float] = [0.0, 0.0]
var _cue_db: Array[float] = [0.0, 0.0]
var _tweens: Array[Tween] = [null, null]
var _active: int = 0
var _current_id: StringName = &""
# The duck's gain, 1 when not ducked.
var _duck_gain: float = 1.0
var _duck_tween: Tween = null
var _is_ducked: bool = false


func _ready() -> void:
	for index: int in 2:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Track%d" % [index]
		player.bus = AudioCue.MUSIC_BUS_NAME
		add_child(player)
		_players.append(player)
		_apply_volume(index)


## Plays [param track], fading over [param fade_seconds] ([member crossfade_seconds] when
## negative). Does nothing for the track already playing, or for null or a cue with no stream.
func play(track: AudioCue, fade_seconds: float = -1.0) -> void:
	if track == null or track.streams.is_empty() or _players.is_empty():
		return
	if track.id == _current_id and _players[_active].playing:
		return
	var seconds: float = crossfade_seconds if fade_seconds < 0.0 else fade_seconds
	var old: int = _active
	_active = 1 - _active
	var player: AudioStreamPlayer = _players[_active]
	player.stop()
	player.stream = track.streams[0]
	_cue_db[_active] = track.volume_db
	_current_id = track.id
	_fade(_active, 0.0, 1.0, seconds, false)
	player.play()
	if _players[old].playing:
		_fade(old, _gains[old], 0.0, seconds, true)


## Fades the track out over [param fade_seconds] ([member crossfade_seconds] when negative), then
## stops it. Nothing plays until the next [method play].
func stop(fade_seconds: float = -1.0) -> void:
	var seconds: float = crossfade_seconds if fade_seconds < 0.0 else fade_seconds
	_current_id = &""
	for index: int in _players.size():
		if _players[index].playing:
			_fade(index, _gains[index], 0.0, seconds, true)


## Stops both players at once and lets go of their tracks, so nothing plays on into shutdown.
## Returns a weak reference to each playback that was playing, which the audio server frees on a
## later mix.
func release_all() -> Array[WeakRef]:
	_current_id = &""
	var released: Array[WeakRef] = []
	for index: int in _players.size():
		if is_instance_valid(_tweens[index]):
			_tweens[index].kill()
		var player: AudioStreamPlayer = _players[index]
		if player.playing and player.has_stream_playback():
			released.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	return released


## Lowers the music by [member duck_db] ([param is_on]), or brings it back.
func set_ducked(is_on: bool) -> void:
	if is_on == _is_ducked:
		return
	_is_ducked = is_on
	if is_instance_valid(_duck_tween):
		_duck_tween.kill()
	var target: float = db_to_linear(minf(duck_db, 0.0)) if is_on else 1.0
	if duck_seconds <= 0.0:
		_set_duck_gain(target)
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck_gain, _duck_gain, target, duck_seconds)


## The id of the track playing or fading in; empty when stopped.
func current_id() -> StringName:
	return _current_id


## Whether the music is ducked.
func is_ducked() -> bool:
	return _is_ducked


## The volume the playing track is heard at, fade and duck included. [b]Units:[/b] dB.
func current_volume_db() -> float:
	if _players.is_empty():
		return linear_to_db(_SILENT_GAIN)
	return _players[_active].volume_db


## The player of the track playing or fading in, for tests.
func get_active_player() -> AudioStreamPlayer:
	return _players[_active] if not _players.is_empty() else null


# Fades player index from one gain to another over seconds, stopping it at the end when asked.
func _fade(index: int, from: float, to: float, seconds: float, is_stopping: bool) -> void:
	if is_instance_valid(_tweens[index]):
		_tweens[index].kill()
	_tweens[index] = null
	if seconds <= 0.0:
		_set_gain(to, index)
		if is_stopping:
			_players[index].stop()
		return
	var tween: Tween = create_tween()
	tween.tween_method(_set_gain.bind(index), from, to, seconds)
	if is_stopping:
		tween.tween_callback(_players[index].stop)
	_tweens[index] = tween


func _set_gain(gain: float, index: int) -> void:
	_gains[index] = gain
	_apply_volume(index)


func _set_duck_gain(gain: float) -> void:
	_duck_gain = gain
	for index: int in _players.size():
		_apply_volume(index)


func _apply_volume(index: int) -> void:
	var gain: float = maxf(_gains[index] * _duck_gain, _SILENT_GAIN)
	_players[index].volume_db = _cue_db[index] + linear_to_db(gain)
