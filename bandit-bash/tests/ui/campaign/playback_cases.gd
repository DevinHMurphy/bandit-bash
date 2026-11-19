# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     playback_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Campaign fact playback ([CampaignPlayback]) on a session and run built here, no autoloads:
## the run's facts play on its bus once each, in seq order; play_through plays up to a fact and
## no further, play_before stops short of a kind; next_pending finds a seat's and unit's fact and
## none in a resumed run's empty log, so a resumed level-up card is silent. Through the real
## campaign map ([code]campaign_facts.tres[/code]): the run's start sounds begin_campaign, a
## chosen combat node battle_map_enter and any other node nothing, and a level-up level_up once.

const CAMPAIGN_MAP_PATH: String = "res://data/audio/maps/campaign_facts.tres"

const SEAT: int = 0
const OTHER_SEAT: int = 1
const UNIT_A: String = "unit:1"
const UNIT_B: String = "unit:2"

# What the listener should hear: the run's start then the combat node chosen; a level-up alone.
const START_AND_COMBAT: Array[StringName] = [&"begin_campaign", &"battle_map_enter"]
const LEVEL_UP_ONLY: Array[StringName] = [&"level_up"]

var _check: Callable
var _played: Array[CampaignFact] = []
var _heard: Array[StringName] = []


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_check_order_and_once()
	_check_through_and_before()
	_check_resumed_log()
	_check_sounds()


# A session for SEAT and OTHER_SEAT whose run holds a one-floor graph (node 0 a combat, node 1 a
# camp) and facts, recorded in order; its bus's plays land in _played.
func _session(facts: Array[CampaignFact]) -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, 1, PackedInt32Array([SEAT, OTHER_SEAT])
	)
	var run: CampaignRunState = CampaignRunState.new()
	run.graph = CampaignGraph.new(1, 2)
	run.graph.add_node(1, 0, CampaignGraph.NodeType.STANDARD)
	run.graph.add_node(1, 1, CampaignGraph.NodeType.CAMP)
	for fact: CampaignFact in facts:
		run.record(fact)
	session.run = run
	session.bus.fact_played.connect(_on_bus_fact_played)
	return session


func _fact(kind: CampaignFact.Kind, seat: int = SEAT, actor_id: String = "") -> CampaignFact:
	return CampaignFact.new(kind, seat, actor_id)


func _check_order_and_once() -> void:
	_played.clear()
	var session: CampaignSession = _session([
		_fact(CampaignFact.Kind.RUN_STARTED),
		_fact(CampaignFact.Kind.NODE_CHOSEN),
		_fact(CampaignFact.Kind.NODE_LEFT),
	])
	var first: int = CampaignPlayback.play_pending(session)
	var again: int = CampaignPlayback.play_pending(session)
	_check.call("playback: the run's facts play once each, in seq order", (
			first == 3
			and again == 0
			and _seqs() == PackedInt32Array([1, 2, 3])
			and session.played_seq == 3
	), "%d then %d; %s" % [first, again, _seqs()])
	session.run.record(_fact(CampaignFact.Kind.NODE_CHOSEN))
	CampaignPlayback.play_pending(session)
	_check.call("playback: a fact recorded later plays on the next call, alone", (
			_seqs() == PackedInt32Array([1, 2, 3, 4])
	), str(_seqs()))


func _check_through_and_before() -> void:
	_played.clear()
	var session: CampaignSession = _session([
		_fact(CampaignFact.Kind.COMBAT_ENDED),
		_fact(CampaignFact.Kind.LEVELED_UP, OTHER_SEAT, UNIT_A),
		_fact(CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_A),
		_fact(CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_B),
		_fact(CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_A),
	])
	var before: int = CampaignPlayback.play_before(session, CampaignFact.Kind.LEVELED_UP, SEAT)
	_check.call("playback: play_before plays up to the seat's first level-up, not it", (
			before == 2 and _seqs() == PackedInt32Array([1, 2])
	), str(_seqs()))
	var second_a: CampaignFact = null
	for _card: int in 2:
		second_a = CampaignPlayback.next_pending(
				session, CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_A
		)
		CampaignPlayback.play_through(session, second_a)
	_check.call("playback: each card plays its unit's next level-up, the ones before it too", (
			second_a != null
			and second_a.seq == 5
			and _seqs() == PackedInt32Array([1, 2, 3, 4, 5])
	), str(_seqs()))
	_check.call("playback: a fact already played doesn't play again", (
			not CampaignPlayback.play_through(session, second_a)
			and _played.size() == 5
	))


# A resumed run's log starts empty, so its recap's level-up cards find no fact and play nothing.
func _check_resumed_log() -> void:
	_played.clear()
	var session: CampaignSession = _session([])
	var found: CampaignFact = CampaignPlayback.next_pending(
			session, CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_A
	)
	var played: bool = CampaignPlayback.play_through(session, found)
	_check.call("playback: a resumed run's level-up card finds no fact and is silent", (
			found == null and not played and _played.is_empty()
	))


func _check_sounds() -> void:
	var map: FactCueMap = load(CAMPAIGN_MAP_PATH) as FactCueMap
	if map == null:
		_check.call("playback sounds: the campaign map loads", false, CAMPAIGN_MAP_PATH)
		return
	var combat_node: CampaignFact = _fact(CampaignFact.Kind.NODE_CHOSEN)
	combat_node.amount = 0
	var camp_node: CampaignFact = _fact(CampaignFact.Kind.NODE_CHOSEN)
	camp_node.amount = 1
	var session: CampaignSession = _session([
		_fact(CampaignFact.Kind.RUN_STARTED), combat_node, camp_node,
		_fact(CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_A),
	])
	var listener: FactCueListener = FactCueListener.new(map, _on_listener_cue)
	listener.bind_campaign(session.bus, _node_type.bind(session))
	_heard.clear()
	CampaignPlayback.play_before(session, CampaignFact.Kind.LEVELED_UP, SEAT)
	_check.call("playback sounds: the run's start and a combat node chosen sound; a camp doesn't", (
			_heard == START_AND_COMBAT
	), str(_heard))
	_heard.clear()
	var card: CampaignFact = CampaignPlayback.next_pending(
			session, CampaignFact.Kind.LEVELED_UP, SEAT, UNIT_A
	)
	CampaignPlayback.play_through(session, card)
	CampaignPlayback.play_through(session, card)
	CampaignPlayback.play_pending(session)
	_check.call("playback sounds: a level-up sounds level_up exactly once", (
			_heard == LEVEL_UP_ONLY
	), str(_heard))
	listener.unbind()


func _seqs() -> PackedInt32Array:
	var seqs: PackedInt32Array = []
	for fact: CampaignFact in _played:
		seqs.append(fact.seq)
	return seqs


static func _node_type(node_id: int, session: CampaignSession) -> int:
	if not session.run.graph.has_node_id(node_id):
		return -1
	return session.run.graph.type_of(node_id)


func _on_bus_fact_played(fact: CampaignFact) -> void:
	_played.append(fact)


func _on_listener_cue(cue_id: StringName) -> void:
	_heard.append(cue_id)
