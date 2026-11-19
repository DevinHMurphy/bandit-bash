# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rng_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Sounds never touch a seed (Godot_FE's random pitch broke its seeds): playing cues with random
## pitch, through a [CuePlayer] and through the [code]AudioService[/code], leaves the global RNG's
## sequence and a run's streams, campaign and combat, exactly as they were; and no audio script
## calls the global RNG or names a run stream.

# Any fixed seeds.
const GLOBAL_SEED: int = 0x5EED
const RUN_SEED: int = 0xA0D10

# Enough plays that a draw from the wrong generator couldn't hide.
const PLAYS: int = 40
const RANDOM_CUE: StringName = &"sword_swing_light"

# The scripts that make up the audio layer.
const AUDIO_SCRIPTS_DIR: String = "res://scripts/audio/"
const SERVICE_SCRIPT: String = "res://scripts/autoload/audio_service.gd"

# A call to the global RNG (not a method on a generator) or a run stream's class.
const FORBIDDEN: String = (
	"(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|seed|randomize|rand_from_seed)\\("
	+ "|\\bpick_random\\(|\\bshuffle\\(|\\bRngStreams?\\b"
)

var _check: Callable
var _root: Window
var _players: Array[CuePlayer] = []


func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	_check_global_rng()
	_check_run_streams()
	_check_sources()


## Stops the players these cases made; returns a weak reference to each playback still sounding.
func release() -> Array[WeakRef]:
	var released: Array[WeakRef] = []
	for player: CuePlayer in _players:
		if is_instance_valid(player):
			released.append_array(player.release_all())
	return released


## Frees the players; call once the released playbacks are gone.
func free_nodes() -> void:
	for player: CuePlayer in _players:
		if is_instance_valid(player):
			player.free()
	_players.clear()


func _check_global_rng() -> void:
	seed(GLOBAL_SEED)
	var expected: PackedInt64Array = [randi(), randi(), randi()]
	seed(GLOBAL_SEED)
	_play_many()
	var after: PackedInt64Array = [randi(), randi(), randi()]
	_check.call(
			"rng: %d plays with random pitch leave the global RNG's sequence unchanged" % [PLAYS * 2],
			after == expected,
	)
	randomize()


func _check_run_streams() -> void:
	var streams: RngStreams = RngStreams.new(RUN_SEED)
	streams.stream(RngKey.new(RngKey.RngPurpose.LEVEL_UPS)).randi_range(0, 99)
	streams.stream(RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, 1, 0, 0)).randi_range(0, 99)
	var campaign_before: Dictionary[String, String] = streams.capture_campaign()
	var combat_before: Dictionary[String, String] = streams.capture_combat()
	_play_many()
	_check.call(
			"rng: playing sounds leaves a run's campaign and combat streams untouched",
			streams.capture_campaign() == campaign_before
			and streams.capture_combat() == combat_before
			and not campaign_before.is_empty(),
	)


func _check_sources() -> void:
	var pattern: RegEx = RegEx.create_from_string(FORBIDDEN)
	var paths: PackedStringArray = [SERVICE_SCRIPT]
	for file: String in DirAccess.get_files_at(AUDIO_SCRIPTS_DIR):
		if file.ends_with(".gd"):
			paths.append(AUDIO_SCRIPTS_DIR + file)
	var found: PackedStringArray = []
	for path: String in paths:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for index: int in lines.size():
			var line: String = lines[index].strip_edges()
			if line.begins_with("#"):
				continue
			if pattern.search(line) != null:
				found.append("%s:%d" % [path.get_file(), index + 1])
	_check.call(
			"rng: no audio script (%d read) calls the global RNG or names a run stream" % [
				paths.size(),
			],
			found.is_empty() and paths.size() > 1,
			", ".join(found),
	)


# Plays the random-pitch cue PLAYS times on a player of its own and PLAYS through the service.
func _play_many() -> void:
	var player: CuePlayer = CuePlayer.new()
	player.catalog = AudioCueCatalog.new(AudioCueCatalog.CUES_ROOT)
	_root.add_child(player)
	_players.append(player)
	var service: Node = _root.get_node_or_null(^"AudioService")
	for count: int in PLAYS:
		player.play(RANDOM_CUE)
		if service != null:
			service.call(&"play_cue", RANDOM_CUE)
