# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     full_run_pilot.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## Plays one seeded solo run from its start to the Boss's end through the real SaveService and
## CampaignService, as a player would with fixed choices, for full_run_cases.gd. The route is the
## one that visits the most kinds of node; each node is played by its own commands, and each
## battle is set up on its real map and pack, then won by recording its end, not played. With
## [member is_quitting], it saves, quits and continues at every stop (see [enum Stop]); without,
## it plays straight through, saving at the same stops. After each node it keeps a snapshot of
## the whole run, for comparing two plays. It never names an autoload: they are reached as nodes.

## Where a play may quit and continue.
enum Stop {
	## On the map, once the starting heirloom is taken.
	MAP,
	## Inside a battle, once it has begun and saved a checkpoint.
	BATTLE,
	## At a combat's results, before its rewards are taken.
	RESULTS,
	## Inside a non-combat node, once its offer is rolled and before anything is taken.
	NODE,
}

# The save file the pilot writes, in the test user folder only; it deletes user://saves/ before
# and after each play, as the suite's other save cases do.
const SAVE_NUMBER: int = 2

# The most nodes a run can enter: one per floor.
const MAX_NODES: int = 18

const SAVES_DIR: String = "user://saves/"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const HOST_SEAT: int = 0

# The campaign suite's run_text(), which turns a run into comparable text.
const RunStateCases = preload("res://tests/campaign/run_state_cases.gd")

## Whether the play quits and continues at every stop.
var is_quitting: bool = false

## What went wrong, in order; empty for a play that reached the Boss's end.
var errors: PackedStringArray = []

## The route planned on the new run's map, one node per floor.
var route: PackedInt32Array = []

## Each node entered, in order: [code]{"floor", "type", "plays_as", "snapshot"}[/code], the
## snapshot taken once the node is left (the Boss's at its results).
var nodes: Array[Dictionary] = []

## Every battle begun, in order: [code]{"floor", "type", "map", "pack", "units", "unplaced",
## "mini_boss", "pool_maps"}[/code], read once its setup ran.
var battles: Array[Dictionary] = []

## The stops quit at, by node type name: each kind of node the play quit inside.
var quit_in: Dictionary[String, int] = {}

## The seed line Results showed for the ended run, and whether the run was still there to take
## after Results took it (it must not be).
var results_seed_text: String = ""
var is_record_left: bool = false

## Milliseconds the play took, from the new run to the Results screen.
var elapsed_msec: int = 0

var _root: Window = null
var _saves: Node = null
var _service: Node = null
var _pools: CombatMapPools = null
var _catalog: EffectCatalog.Index = null


func _init(tree_root: Window, quitting: bool) -> void:
	_root = tree_root
	is_quitting = quitting
	_saves = _root.get_node(^"SaveService")
	_service = _root.get_node(^"CampaignService")
	_pools = CombatMapPools.load_default()
	_catalog = EffectCatalog.index()


## Plays a new run on [param run_seed] to the Boss's end, then the Results screen
## ([param results_scene]). Returns true when it got there; [member errors] says why not.
func play(run_seed: int, results_scene: String) -> bool:
	var started: int = Time.get_ticks_msec()
	SaveFile.delete_folder(SAVES_DIR)
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = _saves.call(&"start_new_solo_run", run_seed)
	if err != OK or _session() == null:
		return _fail("new run: %s" % [error_string(err)])
	route = plan_route(_session().run.graph)
	if route.size() != MAX_NODES:
		return _fail("no route from floor 1 to the Boss")
	if not _take_starting_heirloom() or not _stop(Stop.MAP, ""):
		return false
	for node_id: int in route:
		if not _play_node(node_id):
			return false
	if not _end_run(results_scene):
		return false
	elapsed_msec = Time.get_ticks_msec() - started
	_saves.call(&"close_save_file")
	SaveFile.delete_folder(SAVES_DIR)
	return errors.is_empty()


## The route through [param graph] that visits the most node types, one node per floor from floor 1
## to the Boss, each a child of the one before; among equals, the one whose node ids come first.
## Empty when the map has no such route.
static func plan_route(graph: CampaignGraph) -> PackedInt32Array:
	# For each node, the type sets a route reaching it can hold, each with the node it came from.
	var reached: Dictionary[int, Dictionary] = {}
	for node_id: int in graph.nodes_on_floor(1):
		reached[node_id] = {1 << graph.type_of(node_id): [CampaignGraph.NO_NODE, 0]}
	var last: PackedInt32Array = graph.nodes_on_floor(1)
	for floor_number: int in range(2, MAX_NODES + 1):
		var found: PackedInt32Array = graph.nodes_on_floor(floor_number)
		if found.is_empty():
			break
		found.sort()
		for node_id: int in found:
			reached[node_id] = {}
		var parents: PackedInt32Array = last.duplicate()
		parents.sort()
		for parent: int in parents:
			var parent_sets: Dictionary = reached.get(parent, {})
			var masks: Array = parent_sets.keys()
			masks.sort()
			for child: int in graph.children_of(parent):
				var child_sets: Dictionary = reached[child]
				for mask: Variant in masks:
					var next: int = (mask as int) | (1 << graph.type_of(child))
					if not child_sets.has(next):
						child_sets[next] = [parent, mask as int]
		last = found
	var best_node: int = CampaignGraph.NO_NODE
	var best_mask: int = 0
	for node_id: int in last:
		for mask: Variant in reached.get(node_id, {}):
			if _bits(mask as int) > _bits(best_mask):
				best_node = node_id
				best_mask = mask as int
	var path: PackedInt32Array = []
	var at: int = best_node
	var at_mask: int = best_mask
	while at != CampaignGraph.NO_NODE:
		path.insert(0, at)
		var came_from: Array = reached[at][at_mask]
		at = came_from[0] as int
		at_mask = came_from[1] as int
	return path


# Chooses node_id and plays it to the point it is left (the Boss: to its results).
func _play_node(node_id: int) -> bool:
	var run: CampaignRunState = _session().run
	var type: CampaignGraph.NodeType = run.graph.type_of(node_id)
	if not _submit(ChooseNodeCommand.new(HOST_SEAT, node_id)):
		return false
	var type_name: String = CampaignGraph.NodeType.find_key(type) as String
	if type == CampaignGraph.NodeType.UNKNOWN and not _enter_unknown():
		return false
	var plays_as: CampaignGraph.NodeType = _session().run.node_type()
	var entry: Dictionary = {
		"floor": _session().run.floor_number,
		"type": type_name,
		"plays_as": CampaignGraph.NodeType.find_key(plays_as) as String,
		"snapshot": "",
	}
	nodes.append(entry)
	var played: bool = false
	match plays_as:
		CampaignGraph.NodeType.STANDARD, CampaignGraph.NodeType.KEY, CampaignGraph.NodeType.BOSS:
			played = _play_combat(type_name)
		CampaignGraph.NodeType.TREASURE:
			played = _play_treasure(type_name)
		CampaignGraph.NodeType.CAMP:
			played = _play_camp(type_name)
		CampaignGraph.NodeType.ARMORY:
			played = _play_armory(type_name)
		CampaignGraph.NodeType.GUILDHALL:
			played = _play_guildhall(type_name)
		CampaignGraph.NodeType.UNKNOWN:
			played = _play_event(type_name)
		_:
			return _fail("floor %d: no way to play a %s node" % [entry["floor"], type_name])
	if not played:
		return false
	entry["snapshot"] = _snapshot()
	return true


# Settles an Unknown node's entry as RunScreen.enter_unknown does: rolls it, then opens an
# event outcome's event, each saved. An event that can't be drawn stays on the placeholder.
func _enter_unknown() -> bool:
	var run: CampaignRunState = _session().run
	if ResolveUnknownCommand.is_due(run):
		if not _submit(ResolveUnknownCommand.for_session(_session())):
			return false
	if UnknownResolution.needs_event(_session().run):
		var open: OpenEventCommand = EventNode.open(_session())
		if open != null:
			_try(open)
	return true


# A combat: begun on the run's own request and read, a checkpoint, the stop, the win recorded and
# the battle ended; then its results and the rewards taken, unless it was the Boss.
func _play_combat(type_name: String) -> bool:
	var request: CampaignSession.BattleRequest = _request()
	if request == null:
		return _fail("floor %d: no battle request" % [_session().run.floor_number])
	var begun: Error = _service.call(&"begin_battle", request)
	if begun != OK or _session().encounter == null:
		return _fail("floor %d: the battle didn't begin (%s)" % [
			_session().run.floor_number, error_string(begun),
		])
	_read_battle(request)
	_session().encounter.submit(StartCommand.new(HOST_SEAT), HOST_SEAT)
	_session().encounter.resolve_queued()
	if not _checkpoint():
		return false
	if not _stop(Stop.BATTLE, type_name):
		return false
	var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
	ended.side = PLAYER
	_session().encounter.get_session(0).engine.record(ended)
	if _service.call(&"end_battle") == null:
		return _fail("floor %d: the battle didn't end" % [_session().run.floor_number])
	if _session() == null or _session().run.flow.stage != RunFlow.Stage.RESULTS:
		return _fail("floor %d: the won battle isn't at its results" % [_floor()])
	if not _stop(Stop.RESULTS, type_name):
		return false
	if _session().run.is_boss_beaten():
		return true
	_take_rewards()
	return _leave()


# A combat's rewards: the item pick taken to the convoy, else scrapped, else skipped; a Key
# combat's heirloom taken.
func _take_rewards() -> void:
	var seat_run: SeatRun = _seat_run()
	var pick: ItemPick = ItemPick.pending(seat_run)
	if pick != null and not pick.is_resolved:
		var placements: Array[ItemPlacement] = [
			ItemPlacement.new(ItemPlacement.Destination.CONVOY),
			ItemPlacement.new(ItemPlacement.Destination.SCRAP),
		]
		var taken: bool = false
		for placement: ItemPlacement in placements:
			if not taken:
				taken = _try(ItemPickCommand.new(HOST_SEAT, 0, placement))
		if not taken:
			_try(ItemPickCommand.new(HOST_SEAT, ItemPickCommand.SKIP))
	if KeyHeirloom.is_open(_seat_run()):
		_try(KeyHeirloomCommand.new(HOST_SEAT, true))


func _play_treasure(type_name: String) -> bool:
	if not _submit(OpenTreasureCommand.for_session(_session())):
		return false
	if not _stop(Stop.NODE, type_name):
		return false
	var taken: bool = false
	for where: ItemPlacement.Destination in [
		ItemPlacement.Destination.CONVOY, ItemPlacement.Destination.SCRAP,
	]:
		if not taken:
			taken = _try(TreasureCommand.new(HOST_SEAT, true, ItemPlacement.new(where)))
	if not taken:
		taken = _try(TreasureCommand.new(HOST_SEAT, true))
	if not taken:
		return _fail("floor %d: the chest couldn't be taken" % [_floor()])
	return _leave()


func _play_camp(type_name: String) -> bool:
	if not _stop(Stop.NODE, type_name):
		return false
	if not _submit(FeastCommand.new(HOST_SEAT)):
		return false
	return _leave()


# An Armory: its stock rolled, then the first entry the seat can buy onto a living unit, if any.
func _play_armory(type_name: String) -> bool:
	if not _submit(OpenArmoryCommand.for_session(_session())):
		return false
	if not _stop(Stop.NODE, type_name):
		return false
	var stock: ArmoryStock = ArmoryStock.pending(_session().run)
	var entry_count: int = 0 if stock == null else stock.entries.size()
	var bought: bool = false
	for entry: int in entry_count:
		for unit: UnitInstance in _seat_run().army:
			if not bought:
				bought = _try(ArmoryPurchaseCommand.for_session(
						_session(), HOST_SEAT, entry, unit.instance_id, true
				))
	return _leave()


# A Guildhall: its stock rolled, then the first entry the seat can buy with no unit replaced.
func _play_guildhall(type_name: String) -> bool:
	if not _submit(OpenGuildhallCommand.for_session(_session())):
		return false
	if not _stop(Stop.NODE, type_name):
		return false
	var stock: GuildhallStock = GuildhallStock.pending(_session().run)
	var entry_count: int = 0 if stock == null else stock.entries.size()
	var bought: bool = false
	for entry: int in entry_count:
		if not bought:
			bought = _try(GuildhallPurchaseCommand.new(HOST_SEAT, entry))
	return _leave()


# An Unknown that became an event: the first option open to the seat with nothing to pick and no
# surprise combat, then Leave. With no event drawn (the placeholder), Leave.
func _play_event(type_name: String) -> bool:
	var run: CampaignRunState = _session().run
	if run.events.is_open_at(run.floor_number, run.node):
		if not _stop(Stop.NODE, type_name):
			return false
		var view: EventView = EventNode.view(_session(), HOST_SEAT)
		var chosen: bool = false
		for index: int in view.options.size():
			if not chosen and _is_plain(view.options[index]):
				chosen = _try(EventNode.choose(_session(), HOST_SEAT, index))
		if not chosen:
			return _fail("floor %d: no event option could be taken" % [_floor()])
	return _leave()


# The Boss's end: the run archived as won, then the Results screen built to read its seed line.
func _end_run(results_scene: String) -> bool:
	if _session() == null or not _session().run.is_boss_beaten():
		return _fail("the route ended without the Boss beaten")
	var ended: Error = _service.call(&"end_won_run")
	if ended != OK:
		return _fail("the won run didn't end: %s" % [error_string(ended)])
	var scene: PackedScene = load(results_scene) as PackedScene
	if scene == null:
		return _fail("no Results scene at %s" % [results_scene])
	var screen: Control = scene.instantiate() as Control
	# Results takes the ended run in _ready, so each run is shown once.
	_root.add_child(screen)
	results_seed_text = screen.call(&"get_seed_text")
	is_record_left = _saves.call(&"take_ended_run") != null
	_root.remove_child(screen)
	screen.free()
	return true


# The starting heirloom offer: the first option that can be taken with its first sub-choice.
func _take_starting_heirloom() -> bool:
	var seat_run: SeatRun = _seat_run()
	var offer: StartingOffer = StartingOffer.pending(seat_run)
	if offer == null:
		return _fail("the new run has no starting heirloom offer")
	for index: int in offer.options.size():
		for command: StartingHeirloomCommand in _starting_choices(index, offer.options[index]):
			if _try(command):
				return true
	return _submit(StartingHeirloomCommand.new(HOST_SEAT, StartingHeirloomCommand.SKIP))


# The ways to take option index of the starting offer: one per unit it may name, its first
# recruit and weapon.
func _starting_choices(
		index: int, option: StartingOffer.Option
) -> Array[StartingHeirloomCommand]:
	var choices: Array[StartingHeirloomCommand] = []
	var definition: StartingHeirloomDefinition = StartingOffer.definition_of(option, _catalog)
	if definition == null:
		return choices
	var units: PackedStringArray = [""]
	match definition.bonus:
		StartingHeirloomDefinition.Bonus.UPGRADE:
			units = StartingOffer.eligible_units(_session().run, HOST_SEAT, _catalog, false)
		StartingHeirloomDefinition.Bonus.REPLACE:
			units = StartingOffer.eligible_units(_session().run, HOST_SEAT, _catalog, true)
	for unit_id: String in units:
		var command: StartingHeirloomCommand = StartingHeirloomCommand.new(HOST_SEAT, index)
		command.unit_id = unit_id
		if not option.recruits.is_empty():
			command.recruit = 0
		if not option.weapons.is_empty():
			command.weapon = 0
			command.placement = ItemPlacement.new(ItemPlacement.Destination.CONVOY)
		choices.append(command)
	return choices


# Saves and, when quitting, quits and continues; a battle is then resumed from the run's own
# request, as the battle screen does. Counts the stop under type_name (empty: none).
func _stop(stop: Stop, type_name: String) -> bool:
	if not _checkpoint():
		return false
	if not is_quitting:
		return true
	if not type_name.is_empty():
		quit_in[type_name] = quit_in.get(type_name, 0) + 1
	_saves.call(&"close_save_file")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var err: Error = _saves.call(&"continue_solo_run")
	if err != OK or _session() == null or _session().run == null:
		return _fail("%s stop on floor %d: the run didn't continue (%s)" % [
			Stop.find_key(stop), _floor(), error_string(err),
		])
	if stop != Stop.BATTLE:
		return true
	var resumed: Error = _service.call(&"resume_battle", _request())
	if resumed != OK or _session().encounter == null:
		return _fail("floor %d: the battle didn't resume (%s)" % [_floor(), error_string(resumed)])
	return true


# What the battle just begun drew: its map, its pack and the pack's units, and the maps its pool
# offered.
func _read_battle(request: CampaignSession.BattleRequest) -> void:
	var setup: CombatEncounter.EncounterSetup = _session().encounter.setup
	var drawn: Dictionary = setup.shared.get(EnemySetup.ENEMIES_KEY, {})
	var pool_maps: PackedStringArray = []
	for map: CombatMapDefinition in request.pool:
		pool_maps.append(map.id)
	battles.append({
		"floor": request.floor_number,
		"type": CampaignGraph.NodeType.find_key(_session().run.node_type()) as String,
		"map": setup.map.id if setup.map != null else "",
		"pack": drawn.get(EnemySetup.PACK_KEY, ""),
		"units": (drawn.get(EnemySetup.UNITS_KEY, []) as Array).size(),
		"unplaced": (drawn.get(EnemySetup.UNPLACED_KEY, []) as Array).size(),
		"mini_boss": drawn.get(EnemySetup.MINI_BOSS_KEY, ""),
		"pool_maps": pool_maps,
	})


# The whole run as text: its sections, its events, its campaign streams and its id counter.
func _snapshot() -> String:
	var session: CampaignSession = _session()
	var parts: Array = [
		JSON.parse_string(RunStateCases.run_text(session.run)),
		session.run.events.capture(),
		session.rng.capture_campaign(),
		session.ids.capture(),
	]
	# Through JSON as on disk, so a continued run's whole floats compare equal.
	return JSON.stringify(JSON.parse_string(JSON.stringify(parts)))


func _leave() -> bool:
	return _submit(LeaveNodeCommand.new(HOST_SEAT))


func _checkpoint() -> bool:
	var err: Error = _saves.call(&"save_checkpoint")
	if err != OK:
		return _fail("floor %d: the checkpoint didn't save (%s)" % [_floor(), error_string(err)])
	return true


# Submits command through the service, which saves it; false, with an error, when refused.
func _submit(command: CampaignCommand) -> bool:
	if command == null:
		return _fail("floor %d: no command to send" % [_floor()])
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	if batch == null or batch.is_rejected():
		return _fail("floor %d: \"%s\" was refused (%s)" % [
			_floor(), command.get_label(), "no batch" if batch == null else batch.rejected_reason,
		])
	return true


# Submits command through the service; whether it was accepted. A refusal costs nothing.
func _try(command: CampaignCommand) -> bool:
	if command == null:
		return false
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	return batch != null and not batch.is_rejected()


func _request() -> CampaignSession.BattleRequest:
	return _session().run.battle_request(_pools, _catalog)


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


func _seat_run() -> SeatRun:
	return _session().run.seat_run(HOST_SEAT)


func _floor() -> int:
	var session: CampaignSession = _session()
	return 0 if session == null or session.run == null else session.run.floor_number


func _fail(problem: String) -> bool:
	errors.append(problem)
	return false


# Whether option can be taken with nothing to pick and plays no surprise combat.
static func _is_plain(option: EventView.OptionView) -> bool:
	if not option.is_available() or option.chooser() != EventOutcome.Chooser.NONE:
		return false
	if not option.rolls.picks.is_empty():
		return false
	for outcome: EventOutcome in option.option.outcomes:
		if outcome is SurpriseCombatOutcome:
			return false
	return true


static func _bits(mask: int) -> int:
	var count: int = 0
	var rest: int = mask
	while rest != 0:
		count += rest & 1
		rest >>= 1
	return count
