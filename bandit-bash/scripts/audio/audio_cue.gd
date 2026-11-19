# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     audio_cue.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name AudioCue
extends Resource
## One sound or track as data: its streams, bus, volume, pitch range and voice limit.
##
## Lives in [code]res://data/audio/cues/[/code], loaded by [AudioCueCatalog] and played by id
## through the [code]AudioService[/code] autoload. Presentation only: rules code never reads one.
## Pitch and stream variation draw from the generator the caller hands in, never the global RNG
## or a run stream, so a sound can never change a seed.[br]
## [b]Read-only at runtime,[/b] like every definition: a voice copies the values it needs.
##
## @tutorial(Audio scope): docs/design/audio.md

## The bus a cue plays on. Every bus sits under Master ([constant MASTER_BUS_NAME]).
enum Bus {
	## Sound effects of the game world: combat, rewards. Follows the SFX volume.
	SFX = 0,
	## Interface sounds: menus, focus, level-ups. Follows the SFX volume too.
	UI = 1,
	## Music. Follows the Music volume; played by the service's music deck, not as a voice.
	MUSIC = 2,
}

## The bus everything sits under; follows the Master volume.
const MASTER_BUS_NAME: StringName = &"Master"
## [constant Bus.SFX]'s bus name in [code]res://data/audio/bus_layout.tres[/code].
const SFX_BUS_NAME: StringName = &"SFX"
## [constant Bus.UI]'s bus name.
const UI_BUS_NAME: StringName = &"UI"
## [constant Bus.MUSIC]'s bus name.
const MUSIC_BUS_NAME: StringName = &"Music"

## The id code plays this cue by. Lowercase snake_case, unique across [code]data/audio/cues/[/code];
## [b]empty:[/b] the catalog rejects the file.
@export var id: StringName = &""

## The streams one play chooses from, evenly. [b]One:[/b] the same sound every time.
## [b]Empty:[/b] the catalog rejects the file. A music cue plays its first stream only.
@export var streams: Array[AudioStream] = []

## The bus the cue plays on, which picks the volume slider it follows.
@export var bus: Bus = Bus.SFX

## Loudness against the bus. [b]Units:[/b] dB. [b]0:[/b] the file as recorded; -6 about half.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = 0.0

## Lowest random pitch scale. [b]1:[/b] the recorded pitch; 0.5 an octave down. Equal to
## [member pitch_max] for no variation. Ignored by music.
@export_range(0.25, 4.0, 0.01) var pitch_min: float = 1.0

## Highest random pitch scale; at least [member pitch_min]. [b]1:[/b] the recorded pitch.
@export_range(0.25, 4.0, 0.01) var pitch_max: float = 1.0

# ASSUMPTION: 4 voices per sound effect (the game's UI cues set 2); Godot_FE had no limit.
## Most copies of this cue sounding at once; a play past it cuts the oldest copy. [b]1:[/b] a new
## play restarts the cue. Ignored by music, which has one track at a time.
@export_range(1, 16) var voice_limit: int = 4


## The bus name [member bus] plays on.
func bus_name() -> StringName:
	match bus:
		Bus.UI:
			return UI_BUS_NAME
		Bus.MUSIC:
			return MUSIC_BUS_NAME
	return SFX_BUS_NAME


## One stream of [member streams], drawn from [param rng]; null when there is none. A single
## stream draws nothing.
func pick_stream(rng: RandomNumberGenerator) -> AudioStream:
	if streams.is_empty():
		return null
	if streams.size() == 1:
		return streams[0]
	return streams[rng.randi_range(0, streams.size() - 1)]


## A pitch scale in [member pitch_min]-[member pitch_max], drawn from [param rng]. A fixed pitch
## draws nothing.
func pick_pitch(rng: RandomNumberGenerator) -> float:
	if pitch_max <= pitch_min:
		return pitch_min
	return rng.randf_range(pitch_min, pitch_max)


## What makes this cue unplayable or wrong, one line each; empty when it is sound.
func problems() -> PackedStringArray:
	var found: PackedStringArray = []
	if id.is_empty():
		found.append("no id")
	if streams.is_empty():
		found.append("no streams")
	for index: int in streams.size():
		if streams[index] == null:
			found.append("stream %d is missing" % [index])
	if pitch_min > pitch_max:
		found.append("pitch_min %.2f above pitch_max %.2f" % [pitch_min, pitch_max])
	if voice_limit < 1:
		found.append("voice_limit %d below 1" % [voice_limit])
	return found
