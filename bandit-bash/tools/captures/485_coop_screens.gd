# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     485_coop_screens.gd
# Author:
# Created:  November 21, 2026
# Modified: November 21, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The campaign screens in a 2-seat host run, for the host's seat: the starting offer, the map, its
## army view's Team button and the Team panel, a Treasure and a Camp each waiting on the teammate
## (Leave refused by name, the Camp's teammate line), an Armory and a Guildhall card bought by the
## teammate, and the placeholder with Team.[br]
## A seeded 2-seat session stands in for the solo run's in CampaignService while the shots are
## taken; every offer is staged on it directly, which saves nothing, and only refused commands go
## through the service. The solo session then comes back and the group ends on its map, as it
## found it, so 500 starts where 480 left it.[br]
## Needs: the map, as the guildhall shots leave it (480_guildhall).

# SceneRouter.Screen values the base doesn't list (see the base's class doc).
const SCREEN_PLACEHOLDER: int = 11
const SCREEN_TREASURE: int = 14
const SCREEN_CAMP: int = 15
const SCREEN_ARMORY: int = 16
const SCREEN_GUILDHALL: int = 17

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const FACTION: String = "mercenary"

# The teammate's seat.
const TEAMMATE: int = 1

# Gold staged so the teammate can buy a card. Units: gold.
const STAGED_GOLD: int = 300

var _coop: CampaignSession = null
var _solo: CampaignSession = null


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the co-op shots need the map (screen %d)" % [router_screen()])
		return true
	_solo = campaign()
	_coop = _new_coop()
	if _coop == null:
		fail("the 2-seat run couldn't be built")
		return true
	node(^"CampaignService").set(&"session", _coop)
	note("co-op shots: a 2-seat run seeded %X stands in for the solo run, shown for the host" % [
		RUN_SEED,
	])
	await _starting_offer()
	await _map()
	await _treasure()
	await _camp()
	await _armory()
	await _guildhall()
	await _placeholder()
	node(^"CampaignService").set(&"session", _solo)
	node(^"CampaignService").call(&"set_local_seat", CampaignData.HOST_SEAT)
	_coop.close()
	node(^"SceneRouter").call(&"goto_screen", SCREEN_MAP)
	await frames(SETTLE_FRAMES)
	return true


# A new 2-seat run on RUN_SEED, as CampaignService builds one, each seat's starting offer open.
func _new_coop() -> CampaignSession:
	var made: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, TEAMMATE])
	)
	var factions: Dictionary[int, String] = {0: FACTION, TEAMMATE: FACTION}
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			made.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			EffectCatalog.index(),
			factions,
			made.ids,
			made.starting_offer_streams()
	)
	if start.run == null:
		return null
	made.run = start.run
	return made


# The host's starting offer; then both seats take one, staged.
func _starting_offer() -> void:
	await goto(SCREEN_STARTING_HEIRLOOM, "coop_starting_heirloom")
	for seat: int in _coop.seats:
		_take_starting_offer(seat)


# The map, its army view with Team, and the Team panel over it.
func _map() -> void:
	await goto(SCREEN_MAP, "coop_map")
	(scene().call(&"get_army_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_map_army_team")
	var army: ArmyView = scene().call(&"get_army_view")
	army.get_team_button().pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_team_panel")
	(scene().call(&"get_team_panel") as TeamPanel).close()
	army.close()
	await frames(SETTLE_FRAMES)


# The chests rolled; the host's given up, then Leave refused while the teammate's is open.
func _treasure() -> void:
	if not _stage_node(CampaignGraph.NodeType.TREASURE):
		return
	_coop.submit(OpenTreasureCommand.for_session(_coop))
	await goto(SCREEN_TREASURE, "coop_treasure")
	_coop.submit(TreasureCommand.new(CampaignData.HOST_SEAT, false))
	(scene().call(&"get_leave_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_treasure_waiting")
	_coop.submit(TreasureCommand.new(TEAMMATE, false))
	_coop.submit(LeaveNodeCommand.new(CampaignData.HOST_SEAT))


# The teammate still choosing; the host's Feast, then Leave refused; the Team panel with the
# teammate's choice once made.
func _camp() -> void:
	if not _stage_node(CampaignGraph.NodeType.CAMP):
		return
	await goto(SCREEN_CAMP, "coop_camp")
	_coop.submit(FeastCommand.new(CampaignData.HOST_SEAT))
	(scene().call(&"get_leave_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_camp_waiting")
	_coop.submit(FeastCommand.new(TEAMMATE))
	(scene().call(&"get_team_button") as Button).pressed.emit()
	await frames(SETTLE_FRAMES)
	await capture("coop_camp_team")
	(scene().call(&"get_team_panel") as TeamPanel).close()
	_coop.submit(LeaveNodeCommand.new(CampaignData.HOST_SEAT))


# The stock rolled, a card the teammate bought.
func _armory() -> void:
	if not _stage_node(CampaignGraph.NodeType.ARMORY):
		return
	_coop.submit(OpenArmoryCommand.for_session(_coop))
	_coop.run.seat_run(TEAMMATE).gold = STAGED_GOLD
	var stock: ArmoryStock = ArmoryStock.pending(_coop.run)
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for index: int in stock.entries.size():
		if (
				stock.entries[index].is_heirloom()
				and Armory.entry_problem(_coop.run, TEAMMATE, index, catalog).is_empty()
		):
			_coop.submit(ArmoryPurchaseCommand.for_session(_coop, TEAMMATE, index))
			break
	await goto(SCREEN_ARMORY, "coop_armory_bought")
	_coop.submit(LeaveNodeCommand.new(CampaignData.HOST_SEAT))


# The stock rolled, a rune the teammate bought.
func _guildhall() -> void:
	if not _stage_node(CampaignGraph.NodeType.GUILDHALL):
		return
	_coop.submit(OpenGuildhallCommand.for_session(_coop))
	_coop.run.seat_run(TEAMMATE).gold = STAGED_GOLD
	var runes: PackedInt32Array = GuildhallStock.pending(_coop.run).indexes_of(
			GuildhallStock.CATEGORY_RUNE
	)
	if not runes.is_empty():
		_coop.submit(GuildhallPurchaseCommand.new(TEAMMATE, runes[0]))
	await goto(SCREEN_GUILDHALL, "coop_guildhall_bought")
	_coop.submit(LeaveNodeCommand.new(CampaignData.HOST_SEAT))


# An Unknown with no event open, as the quiet road shows it, with Team.
func _placeholder() -> void:
	if not _stage_node(CampaignGraph.NodeType.UNKNOWN):
		return
	await goto(SCREEN_PLACEHOLDER, "coop_placeholder")
	_coop.submit(LeaveNodeCommand.new(CampaignData.HOST_SEAT))


# Takes seat's starting offer with its first option that needs no choice, on the session alone.
func _take_starting_offer(seat: int) -> void:
	var offer: StartingOffer = StartingOffer.pending(_coop.run.seat_run(seat))
	if offer == null:
		return
	for option: int in offer.options.size():
		var command: StartingHeirloomCommand = StartingHeirloomCommand.new(seat, option)
		if command.validate(_coop.run).is_empty():
			_coop.submit(command)
			return
	_coop.submit(StartingHeirloomCommand.new(seat))


# Puts the 2-seat run inside the first node of type reached from its map's floor 1, one node per
# floor, as choosing each would. Returns false, with a NOTE and nothing changed, for none.
func _stage_node(type: CampaignGraph.NodeType) -> bool:
	var run: CampaignRunState = _coop.run
	var routes: Array[PackedInt32Array] = []
	for start: int in run.graph.nodes_on_floor(1):
		routes.append(PackedInt32Array([start]))
	while not routes.is_empty():
		var route: PackedInt32Array = routes.pop_front()
		var last: int = route[route.size() - 1]
		if run.graph.type_of(last) == type:
			run.visited = route
			run.floor_number = route.size()
			run.node = last
			run.flow.stage = RunFlow.Stage.NODE
			return true
		for child: int in run.graph.children_of(last):
			var longer: PackedInt32Array = route.duplicate()
			longer.append(child)
			routes.append(longer)
	note("the 2-seat map has no %s node to stage" % [CampaignGraph.NodeType.find_key(type)])
	return false
