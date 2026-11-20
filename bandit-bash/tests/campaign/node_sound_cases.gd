# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     node_sound_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The Treasure, Camp and reward sounds for tests/campaign/run_all.gd: the real campaign cue map
## (data/audio/maps/campaign_facts.tres) read by a real listener on the run's bus, each command's
## facts played as the screens play them ([CampaignPlayback]). Choosing a Treasure sounds
## treasure_map_enter, taking a chest or an heirloom item_obtained, a scrap gold_rewarded, a Feast
## unit_heal and Train promotion, each exactly once; the Feast's heals, re-gearing and a chest's
## gold sound nothing of their own.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "campaign"

const Fixture = preload("res://tests/campaign/node_fixture.gd")

const CUES_PATH: String = "res://data/audio/maps/campaign_facts.tres"
const RUN_SEED: int = 4242
const LUCKY_COIN: String = "lucky_coin"
const ARCHER: int = 2

var _report: Callable
var _catalog: EffectCatalog.Index = null
var _played: Array[StringName] = []
var _session: CampaignSession = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_catalog = EffectCatalog.index()
	_test_treasure()
	_test_scrap()
	_test_camp()
	_test_item_pick()


func _test_treasure() -> void:
	var session: CampaignSession = _listen(Fixture.session(RUN_SEED))
	var route: PackedInt32Array = Fixture.route_to(
			session.run.graph, CampaignGraph.NodeType.TREASURE
	)
	var parent: int = route[route.size() - 2]
	session.run.visited = route.slice(0, route.size() - 1)
	session.run.floor_number = route.size() - 1
	session.run.node = parent
	session.run.flow.stage = RunFlow.Stage.MAP
	_step(session, ChooseNodeCommand.new(0, route[route.size() - 1]))
	_check("treasure: choosing a Treasure node sounds treasure_map_enter once", (
			_played == [&"treasure_map_enter"]
	), str(_played))
	_step(session, OpenTreasureCommand.for_session(session, _catalog))
	var chest: TreasureChest = TreasureChest.new()
	chest.tier = ContentIds.HEIRLOOM_COMMON
	chest.gold = 40
	chest.heirloom_id = HeirloomDraw.candidates(
			session.run.seat_run(0), _catalog,
			PackedStringArray([ContentIds.HEIRLOOM_COMMON]), false
	)[0]
	chest.store(session.run.seat_run(0))
	_step(session, TreasureCommand.new(0))
	_check("treasure: the chest (gold, an heirloom) sounds item_obtained once, its gold nothing", (
			_played == [&"item_obtained"]
	), str(_played))


func _test_scrap() -> void:
	var session: CampaignSession = _listen(Fixture.session(RUN_SEED))
	var coin: String = Fixture.add_to_convoy(session.run.seat_run(0), LUCKY_COIN, session.ids)
	_step(session, ScrapItemCommand.new(0, coin))
	_check("scrap: a convoy item scrapped sounds gold_rewarded once", (
			_played == [&"gold_rewarded"]
	), str(_played))


func _test_camp() -> void:
	var session: CampaignSession = _listen(Fixture.session(RUN_SEED))
	Fixture.enter(session.run, CampaignGraph.NodeType.CAMP)
	var seat_run: SeatRun = session.run.seat_run(0)
	for unit: UnitInstance in seat_run.army:
		unit.hp = 1
	_step(session, FeastCommand.new(0))
	_check("camp: a Feast healing the whole army sounds unit_heal once", (
			_played == [&"unit_heal"]
	), str(_played))
	_step(session, RegearCommand.new(0, seat_run.army[ARCHER].weapon_id, ""))
	_check("camp: re-gearing sounds nothing", _played.is_empty(), str(_played))
	var trainer: CampaignSession = _listen(Fixture.session(RUN_SEED))
	Fixture.enter(trainer.run, CampaignGraph.NodeType.CAMP)
	trainer.run.seat_run(0).army[ARCHER].hp = 1
	_step(trainer, TrainCommand.new(0, trainer.run.seat_run(0).army[ARCHER].instance_id))
	_check("camp: Train sounds promotion once (its HP gain nothing)", (
			_played == [&"promotion"]
	), str(_played))


func _test_item_pick() -> void:
	var session: CampaignSession = _listen(Fixture.session(RUN_SEED))
	var seat_run: SeatRun = session.run.seat_run(0)
	Fixture.enter(session.run, CampaignGraph.NodeType.STANDARD)
	session.run.flow.stage = RunFlow.Stage.RESULTS
	var pick: ItemPick = ItemPick.new()
	pick.slot = ItemPick.Slot.POUCH
	pick.offers.append(ItemPick.Offer.new(LUCKY_COIN, session.ids.next_item_id("coin")))
	pick.store(seat_run)
	_step(session, ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.CONVOY)
	))
	_check("pick: taking the item pick sounds item_obtained once (from its GAINED fact)", (
			_played == [&"item_obtained"]
	), str(_played))
	var scrapping: CampaignSession = _listen(Fixture.session(RUN_SEED))
	Fixture.enter(scrapping.run, CampaignGraph.NodeType.STANDARD)
	scrapping.run.flow.stage = RunFlow.Stage.RESULTS
	var scrap_pick: ItemPick = ItemPick.new()
	scrap_pick.slot = ItemPick.Slot.POUCH
	scrap_pick.offers.append(ItemPick.Offer.new(LUCKY_COIN, scrapping.ids.next_item_id("coin")))
	scrap_pick.store(scrapping.run.seat_run(0))
	_step(scrapping, ItemPickCommand.new(
			0, 0, ItemPlacement.new(ItemPlacement.Destination.SCRAP)
	))
	_check("pick: scrapping it at pickup sounds gold_rewarded once, never item_obtained", (
			_played == [&"gold_rewarded"]
	), str(_played))


# Binds a fresh listener on session's bus, everything already logged counted as played.
func _listen(session: CampaignSession) -> CampaignSession:
	_session = session
	session.played_seq = session.run.fact_log.size()
	var listener: FactCueListener = FactCueListener.new(
			load(CUES_PATH) as FactCueMap, _on_cue
	)
	listener.bind_campaign(session.bus, _node_type)
	session.set_meta(&"listener", listener)
	return session


# Submits command and plays its facts, keeping only the cues they sound.
func _step(session: CampaignSession, command: CampaignCommand) -> void:
	_played.clear()
	var batch: CampaignBatch = session.submit(command)
	if batch.is_rejected():
		_check("%s is accepted" % [command.get_label()], false, batch.rejected_reason)
	CampaignPlayback.play_pending(session)


func _node_type(node_id: int) -> int:
	var graph: CampaignGraph = _session.run.graph
	return graph.type_of(node_id) if graph.has_node_id(node_id) else -1


func _on_cue(cue_id: StringName) -> void:
	_played.append(cue_id)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
