# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     music_cue_map.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name MusicCueMap
extends Resource
## Which music plays where, as data: by screen, and in battle by the combat node's type and the
## moment of the battle. Read by the [code]AudioService[/code] autoload.
##
## Keys are names, not numbers, so the file reads as text and survives an enum growing: a
## [code]SceneRouter.Screen[/code] name for [member by_screen], and
## [code]<CampaignGraph.NodeType>/<moment>[/code] for [member by_battle], the moments being
## [constant MOMENT_PREP] (the opening swap), [constant MOMENT_PLAYER] and [constant MOMENT_ENEMY]
## (each side's phase, as its Phase Start plays). Values are music cue ids. A node type with no
## entry for a moment uses [constant FALLBACK_NODE_TYPE]'s.
## Lives at [code]res://data/audio/maps/music.tres[/code].
##
## @tutorial(Audio scope): docs/design/audio.md

## The battle before turn 1: the opening swap window.
const MOMENT_PREP: String = "prep"
## The player side's phase.
const MOMENT_PLAYER: String = "player"
## The enemy side's phase.
const MOMENT_ENEMY: String = "enemy"

# ASSUMPTION: key combats have no entries in music.tres and play the standard tracks; Godot_FE
# had no key combats. Save Select, New Run, Lobby and the node placeholder keep the menu track.
## The node type whose battle music stands in for a type with none of its own.
const FALLBACK_NODE_TYPE: String = "STANDARD"

## Screen name to the track it plays. [b]A screen with no entry[/b] keeps whatever is playing;
## the battle screen's music comes from [member by_battle].
@export var by_screen: Dictionary[String, String] = {}

## [code]<node type>/<moment>[/code] to the track. [b]Missing:[/b] the
## [constant FALLBACK_NODE_TYPE] entry for the moment, else no change.
@export var by_battle: Dictionary[String, String] = {}


## The track for screen [param screen_name]; empty when the screen keeps the music playing.
func for_screen(screen_name: String) -> StringName:
	var track: String = by_screen.get(screen_name, "")
	return StringName(track)


## The track for [param moment] of a battle on a [param node_type_name] node; empty for none.
func for_battle(node_type_name: String, moment: String) -> StringName:
	var key: String = "%s/%s" % [node_type_name, moment]
	if not by_battle.has(key):
		key = "%s/%s" % [FALLBACK_NODE_TYPE, moment]
	var track: String = by_battle.get(key, "")
	return StringName(track)
