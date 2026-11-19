# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     audio_service.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends Node
## The game's sound: plays cues by id, music by screen and battle moment, the interface sounds of
## every screen, and the facts of the battle and the run as they play.
##
## Autoload [code]AudioService[/code], after [code]SceneRouter[/code]. Owns the cue catalog
## ([AudioCueCatalog]), a [CuePlayer] for sounds, a [MusicDeck] for music, a [UiSoundHook] on the
## whole tree, and a [FactCueListener] each for the battle the screen shows
## ([method follow_battle]) and the run's [CampaignBus]. The maps in
## [code]res://data/audio/maps/[/code] say which fact and which screen sounds what. Runs while
## paused, so the pause menu sounds. Volumes are the buses', set by [method SettingsData.apply].
## [b]Presentation only:[/b] rules code never calls it, and nothing here is saved or networked.
##
## @tutorial(Audio scope): docs/design/audio.md
## @todo: TOD-001 HACK - Quitting waits out one audio mix so playing streams aren't reported as
## leaked; drop it if the engine frees playbacks at shutdown itself.

## Which combat facts sound which cue.
const COMBAT_MAP_PATH: String = "res://data/audio/maps/combat_facts.tres"
## Which campaign facts sound which cue.
const CAMPAIGN_MAP_PATH: String = "res://data/audio/maps/campaign_facts.tres"
## Which music plays where.
const MUSIC_MAP_PATH: String = "res://data/audio/maps/music.tres"

# At quit, how long to wait at most for the audio thread to free stopped playbacks, and how often
# to look. The thread needs a few mixes (each about 23 ms at 1024 frames, 44.1 kHz) to free one;
# the cap only bounds a stuck driver. Units: milliseconds.
const _SHUTDOWN_WAIT_MSEC: int = 500
const _SHUTDOWN_POLL_MSEC: int = 5

var _catalog: AudioCueCatalog = null
var _cues: CuePlayer = null
var _music: MusicDeck = null
var _music_map: MusicCueMap = null
var _ui_hook: UiSoundHook = null
var _combat_listener: FactCueListener = null
var _campaign_listener: FactCueListener = null
# The CampaignGraph.NodeType name of the battle followed, for its music.
var _battle_node_type: String = MusicCueMap.FALLBACK_NODE_TYPE
# Music cue ids already reported missing.
var _reported_music: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_catalog = AudioCueCatalog.new(AudioCueCatalog.CUES_ROOT)
	for problem: String in _catalog.problems:
		push_error(problem)
	_cues = CuePlayer.new()
	_cues.name = "Cues"
	_cues.catalog = _catalog
	add_child(_cues)
	_music = MusicDeck.new()
	_music.name = "Music"
	add_child(_music)
	# The last child leaves the tree first at quit, while the players still play.
	var shutdown_watch: Node = Node.new()
	shutdown_watch.name = "ShutdownWatch"
	add_child(shutdown_watch)
	shutdown_watch.tree_exiting.connect(_on_shutdown_watch_tree_exiting)

	_music_map = _load_map(MUSIC_MAP_PATH) as MusicCueMap
	if _music_map == null:
		_music_map = MusicCueMap.new()
	_combat_listener = FactCueListener.new(_load_map(COMBAT_MAP_PATH) as FactCueMap, play_cue)
	_campaign_listener = FactCueListener.new(_load_map(CAMPAIGN_MAP_PATH) as FactCueMap, play_cue)
	_ui_hook = UiSoundHook.new(play_cue)
	_ui_hook.attach(get_tree())

	SceneRouter.screen_changed.connect(_on_scene_router_screen_changed)
	CampaignService.session_started.connect(_on_campaign_service_session_started)
	CampaignService.session_ended.connect(_on_campaign_service_session_ended)


func _exit_tree() -> void:
	if _ui_hook != null:
		_ui_hook.detach()
	if _combat_listener != null:
		_combat_listener.unbind()
	if _campaign_listener != null:
		_campaign_listener.unbind()


## Plays cue [param cue_id]: a sound on its bus, a music cue as the track, or
## [code]music:<moment>[/code] as the followed battle's track for that moment. A missing cue is
## reported once and plays nothing.
func play_cue(cue_id: StringName) -> void:
	if String(cue_id).begins_with(FactCueMap.MUSIC_PREFIX):
		_play_battle_moment(String(cue_id).trim_prefix(FactCueMap.MUSIC_PREFIX))
		return
	var audio_cue: AudioCue = _catalog.cue(cue_id) if _catalog != null else null
	if audio_cue != null and audio_cue.bus == AudioCue.Bus.MUSIC:
		play_music(cue_id)
		return
	if _cues != null:
		_cues.play(cue_id)


## Plays music cue [param cue_id], crossfading over [param fade_seconds] (the deck's default when
## negative). The track already playing doesn't restart. A missing music cue is reported once.
func play_music(cue_id: StringName, fade_seconds: float = -1.0) -> void:
	var track: AudioCue = _catalog.cue(cue_id) if _catalog != null else null
	if track == null or track.bus != AudioCue.Bus.MUSIC:
		if not _reported_music.has(cue_id):
			_reported_music[cue_id] = true
			push_error("AudioService: no music cue %s" % [cue_id])
		return
	_music.play(track, fade_seconds)


## Fades the music out over [param fade_seconds] (the deck's default when negative).
func stop_music(fade_seconds: float = -1.0) -> void:
	_music.stop(fade_seconds)


## Lowers the music under a sound that must be heard ([param is_on]), or brings it back.
func set_music_ducked(is_on: bool) -> void:
	_music.set_ducked(is_on)


## Sounds [param session]'s facts as its board plays them, and plays its battle music: the
## opening swap's track before turn 1, else the phase's. [BattleScreen] calls it for the map it
## shows; leaving the battle screen stops it. Null stops following.
func follow_battle(session: CombatSession) -> void:
	if session == null or session.bus == null:
		_combat_listener.unbind()
		return
	var state: CombatState = session.state
	var side_of: Callable = state.side_of if state != null else Callable()
	_combat_listener.bind_combat(session.bus, side_of)
	_battle_node_type = _node_type_of_run()
	var moment: String = MusicCueMap.MOMENT_PREP
	if state != null and state.turn >= 1:
		var is_enemy: bool = state.phase_side == CombatFact.CombatSide.ENEMY
		moment = MusicCueMap.MOMENT_ENEMY if is_enemy else MusicCueMap.MOMENT_PLAYER
	_play_battle_moment(moment)


## The cues, for tests.
func get_catalog() -> AudioCueCatalog:
	return _catalog


## The sound player, for tests.
func get_cue_player() -> CuePlayer:
	return _cues


## The music player, for tests.
func get_music_deck() -> MusicDeck:
	return _music


## The listener of the battle followed, for tests.
func get_combat_listener() -> FactCueListener:
	return _combat_listener


func _play_battle_moment(moment: String) -> void:
	var track: StringName = _music_map.for_battle(_battle_node_type, moment)
	if not track.is_empty():
		play_music(track)


# The CampaignGraph.NodeType name of the node the run is in; the fallback outside a run.
func _node_type_of_run() -> String:
	var run: CampaignSession = CampaignService.session
	if run == null or run.run == null or run.run.graph == null:
		return MusicCueMap.FALLBACK_NODE_TYPE
	if not run.run.graph.has_node_id(run.run.node):
		return MusicCueMap.FALLBACK_NODE_TYPE
	var type_name: Variant = CampaignGraph.NodeType.find_key(run.run.graph.type_of(run.run.node))
	if type_name == null:
		return MusicCueMap.FALLBACK_NODE_TYPE
	var text: String = type_name
	return text


static func _is_any_alive(refs: Array[WeakRef]) -> bool:
	for ref: WeakRef in refs:
		if ref.get_ref() != null:
			return true
	return false


# A map resource, reported when it doesn't load.
func _load_map(path: String) -> Resource:
	var map: Resource = load(path)
	if map == null:
		push_error("AudioService: can't load %s" % [path])
	return map


# At quit, before any player leaves the tree: stops them all, as a playback still running is held
# by the audio server and reported as leaked, and the server frees a stopped one only on a mix.
func _on_shutdown_watch_tree_exiting() -> void:
	var released: Array[WeakRef] = _cues.release_all()
	released.append_array(_music.release_all())
	# HACK(TOD-001): waits for the audio thread to free the stopped playbacks before the engine's
	# leak check; there is no frame left at quit to wait for.
	var waited: int = 0
	while waited < _SHUTDOWN_WAIT_MSEC and _is_any_alive(released):
		OS.delay_msec(_SHUTDOWN_POLL_MSEC)
		waited += _SHUTDOWN_POLL_MSEC


func _on_scene_router_screen_changed(screen: SceneRouter.Screen) -> void:
	if screen != SceneRouter.Screen.GAMEPLAY:
		_combat_listener.unbind()
	var found: Variant = SceneRouter.Screen.find_key(screen)
	if found == null:
		return
	var screen_name: String = found
	var track: StringName = _music_map.for_screen(screen_name)
	if not track.is_empty():
		play_music(track)


func _on_campaign_service_session_started(session: CampaignSession) -> void:
	_campaign_listener.bind_campaign(session.bus if session != null else null)


func _on_campaign_service_session_ended(session: CampaignSession) -> void:
	if session != null and _campaign_listener.is_bound_to(session.bus):
		_campaign_listener.unbind()
