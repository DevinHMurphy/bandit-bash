# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     fact_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Facts to cues: the shipped maps compile and name only cues the catalog has (and music moments
## the music map has); a fact played on a [CombatBus] sounds its rule (each AU1 cue, every shape)
## and a fact with no rule nothing; a [CampaignBus] level-up sounds; bad keys are reported; an
## unbound listener is silent. Then the music map: screens, battle moments and the node-type
## fallback. The listener here records instead of playing.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "audio"

const COMBAT_MAP_PATH: String = "res://data/audio/maps/combat_facts.tres"
const CAMPAIGN_MAP_PATH: String = "res://data/audio/maps/campaign_facts.tres"
const MUSIC_MAP_PATH: String = "res://data/audio/maps/music.tres"

# Ids the test's sides lookup knows: a player unit, an enemy and a map object.
const PLAYER_ID: String = "unit:1"
const ENEMY_ID: String = "enemy:2"
const OBJECT_ID: String = "object:3"

# A hit's damage, any above 0.
const SOME_DAMAGE: int = 5

var _check: Callable
var _root: Window
var _heard: Array[StringName] = []


func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


func run() -> void:
	var catalog: AudioCueCatalog = AudioCueCatalog.new(AudioCueCatalog.CUES_ROOT)
	var combat_map: FactCueMap = load(COMBAT_MAP_PATH) as FactCueMap
	var campaign_map: FactCueMap = load(CAMPAIGN_MAP_PATH) as FactCueMap
	var music_map: MusicCueMap = load(MUSIC_MAP_PATH) as MusicCueMap
	if combat_map == null or campaign_map == null or music_map == null:
		_check.call("facts: the maps load", false)
		return
	_check_maps(catalog, combat_map, campaign_map, music_map)
	_check_combat(combat_map)
	_check_campaign(campaign_map)
	_check_bad_keys()
	_check_music_map(music_map)


func _check_maps(
		catalog: AudioCueCatalog,
		combat_map: FactCueMap,
		campaign_map: FactCueMap,
		music_map: MusicCueMap,
) -> void:
	var problems: PackedStringArray = combat_map.compile()
	problems.append_array(campaign_map.compile())
	_check.call("facts: both fact maps compile", problems.is_empty(), "; ".join(problems))
	var unknown: PackedStringArray = []
	for map: FactCueMap in [combat_map, campaign_map]:
		for key: String in map.cues:
			var value: String = map.cues[key]
			if value.begins_with(FactCueMap.MUSIC_PREFIX):
				var moment: String = value.trim_prefix(FactCueMap.MUSIC_PREFIX)
				if music_map.for_battle(MusicCueMap.FALLBACK_NODE_TYPE, moment).is_empty():
					unknown.append(value)
			elif not catalog.has_cue(StringName(value)):
				unknown.append(value)
	for tracks: Dictionary[String, String] in [music_map.by_screen, music_map.by_battle]:
		for key: String in tracks:
			var track: AudioCue = catalog.cue(StringName(tracks[key]))
			if track == null or track.bus != AudioCue.Bus.MUSIC:
				unknown.append(tracks[key])
	_check.call(
			"facts: every cue the maps name exists, music as music",
			unknown.is_empty(),
			", ".join(unknown),
	)


func _check_combat(map: FactCueMap) -> void:
	var listener: FactCueListener = FactCueListener.new(map, _record)
	var bus: CombatBus = CombatBus.new()
	listener.bind_combat(bus, _side_of)
	var hit_dealt: CombatFact.Kind = CombatFact.Kind.HIT_DEALT
	_expect(bus, _fact(CombatFact.Kind.ATTACK_MADE, PLAYER_ID, ENEMY_ID), &"sword_swing_light")
	_expect(bus, _fact(CombatFact.Kind.MISSED, PLAYER_ID, ENEMY_ID), &"unit_miss")
	_expect(bus, _fact(hit_dealt, PLAYER_ID, ENEMY_ID, SOME_DAMAGE), &"flesh_impact")
	_expect(bus, _fact(hit_dealt, PLAYER_ID, ENEMY_ID, 0), &"no_damage")
	_expect(bus, _fact(hit_dealt, PLAYER_ID, OBJECT_ID, SOME_DAMAGE), &"entity_hit")
	_expect(bus, _fact(hit_dealt, PLAYER_ID, OBJECT_ID, 0), &"no_damage")
	_expect(bus, _fact(CombatFact.Kind.CRIT_DEALT, PLAYER_ID, ENEMY_ID), &"crit_sound")
	_expect(bus, _fact(CombatFact.Kind.HEALED, PLAYER_ID), &"unit_heal")
	_expect(bus, _fact(CombatFact.Kind.DEFEATED, PLAYER_ID, ENEMY_ID), &"friendly_unit_die")
	_expect(bus, _fact(CombatFact.Kind.DEFEATED, ENEMY_ID, PLAYER_ID), &"")
	var ended: CombatFact.Kind = CombatFact.Kind.COMBAT_ENDED
	var phase: CombatFact.Kind = CombatFact.Kind.PHASE_START
	var player: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
	var enemy: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
	_expect(bus, _side_fact(ended, player), &"level_win")
	_expect(bus, _side_fact(ended, enemy), &"")
	_expect(bus, _side_fact(phase, player), &"music:player")
	_expect(bus, _side_fact(phase, enemy), &"music:enemy")
	_expect(bus, _fact(CombatFact.Kind.UNIT_MOVED, PLAYER_ID), &"")
	listener.bind_combat(bus)
	_expect(bus, _fact(hit_dealt, PLAYER_ID, OBJECT_ID, SOME_DAMAGE), &"flesh_impact")
	listener.unbind()
	_expect(bus, _fact(CombatFact.Kind.ATTACK_MADE, PLAYER_ID, ENEMY_ID), &"")


func _check_campaign(map: FactCueMap) -> void:
	var listener: FactCueListener = FactCueListener.new(map, _record)
	var bus: CampaignBus = CampaignBus.new()
	listener.bind_campaign(bus)
	bus.play(CampaignFact.new(CampaignFact.Kind.LEVELED_UP))
	_check.call(
			"facts: a campaign level-up sounds level_up",
			_heard == [&"level_up"],
			_text(),
	)
	_heard.clear()
	bus.play(CampaignFact.new(CampaignFact.Kind.NODE_CHOSEN))
	_check.call("facts: a campaign fact with no rule is silent", _heard.is_empty(), _text())
	_heard.clear()
	_check.call("facts: the listener knows its bus", listener.is_bound_to(bus))
	listener.unbind()


func _check_bad_keys() -> void:
	var map: FactCueMap = FactCueMap.new()
	map.cues = {
		"NOT_A_KIND": "menu_back",
		"HIT_DEALT/sideways": "menu_back",
		"HIT_DEALT/no_damage/extra": "menu_back",
		"MISSED": "unit_miss",
	}
	var problems: PackedStringArray = map.compile()
	_check.call(
			"facts: keys naming no kind or shape are reported, the rest kept",
			problems.size() == 3 and map.rules_for(CombatFact.Kind.MISSED).size() == 1,
			"; ".join(problems),
	)


func _check_music_map(map: MusicCueMap) -> void:
	_check.call(
			"music map: the start and main menus play Dreaming Darkly, as Godot_FE's did",
			map.for_screen("START") == &"menu_dreaming_darkly"
			and map.for_screen("MAIN_MENU") == &"menu_dreaming_darkly",
	)
	_check.call(
			"music map: the battle screen has no screen track",
			map.for_screen("GAMEPLAY").is_empty(),
	)
	_check.call(
			"music map: a standard combat's prep, player and enemy tracks are Godot_FE's",
			map.for_battle("STANDARD", MusicCueMap.MOMENT_PREP) == &"menu_adventures_await"
			and map.for_battle("STANDARD", MusicCueMap.MOMENT_PLAYER) == &"menu_noble_kingdom"
			and map.for_battle("STANDARD", MusicCueMap.MOMENT_ENEMY)
					== &"action_knightly_fighting",
	)
	_check.call(
			"music map: the Powder Baron's map plays Perilous Prince in the player phase",
			map.for_battle("BOSS", MusicCueMap.MOMENT_PLAYER) == &"boss_perilous_prince",
	)
	_check.call(
			"music map: a key combat falls back to the standard tracks",
			map.for_battle("KEY", MusicCueMap.MOMENT_ENEMY) == &"action_knightly_fighting",
	)


func _expect(bus: CombatBus, fact: CombatFact, cue_id: StringName) -> void:
	_heard.clear()
	bus.play(fact)
	var expected: Array[StringName] = []
	if not cue_id.is_empty():
		expected.append(cue_id)
	var label: String = String(cue_id) if not cue_id.is_empty() else "nothing"
	var shape: String = "%s %s->%s amount %d side %d" % [
		CombatFact.Kind.find_key(fact.kind), fact.actor_id, fact.target_id, fact.amount, fact.side,
	]
	_check.call("facts: %s sounds %s" % [shape, label], _heard == expected, _text())
	_heard.clear()


func _fact(
		kind: CombatFact.Kind, actor: String, target: String = "", amount: int = 0
) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor, target)
	fact.amount = amount
	return fact


func _side_fact(kind: CombatFact.Kind, side: CombatFact.CombatSide) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind)
	fact.side = side
	return fact


# The sides lookup a battle's state gives (CombatState.side_of): objects are on no side.
func _side_of(id: String) -> CombatFact.CombatSide:
	match id:
		PLAYER_ID:
			return CombatFact.CombatSide.PLAYER
		ENEMY_ID:
			return CombatFact.CombatSide.ENEMY
	return CombatFact.CombatSide.NONE


func _text() -> String:
	return "heard [%s]" % [", ".join(PackedStringArray(_heard))]


func _record(cue_id: StringName) -> void:
	_heard.append(cue_id)
