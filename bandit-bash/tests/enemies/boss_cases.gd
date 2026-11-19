# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     boss_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The Powder Baron on the real catalog (Powder Baron plan; enemy-roster.md, The boss): its data;
## the keep's fixed garrison; the boss pool's battle, won by its fall; Unshovable; it holds the
## throne, after the darkness too; the throne's heal stops once flooded. Keg Barrage picks the
## tile catching the most player units, ties by the seeded stream, fires every 2nd enemy phase and
## shows as a SIGNATURE intent the phase before, over the blast it then throws. A thrown keg burns
## its fuse to the end of the 2nd enemy phase after it lands; splash and the darkness set it off
## early, a chain resolves, and a mirror follows it hash for hash. Reports each case through the
## check callable it is given.
##
## @tutorial(Powder Baron plan): docs/plans/2026-11-18-powder-baron.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

const AiWorld = preload("res://tests/enemies/ai_world.gd")
const DarknessWorld = preload("res://tests/darkness/darkness_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

const BOSS_ID: String = "powder_baron"
const KEEP_PATH: String = "res://maps/boss/powder_keep.tres"
const POOLS_PATH: String = "res://data/campaign/combat_map_pools.tres"
const THRONE: Vector2i = Vector2i(8, 1)
const BOSS_FLOOR: int = 18
const NODE: int = 0
const RUN_SEED: int = 1818

## The keep's garrison in slot order (data/enemies/packs/powder_keep_garrison.tres).
const GARRISON: Array[String] = [
	"shieldbearer", "shieldbearer", "crossbowman", "crossbowman", "hedge_healer", "brute",
	"cutthroat", "cutthroat",
]

## High enough that no test unit falls to what the cases field.
const STURDY: Dictionary = {
	CombatValue.Key.HP: 99.0,
	CombatValue.Key.DEF: 20.0,
	CombatValue.Key.RES: 20.0,
}

const LANDED: MapObjects.Change = MapObjects.Change.LANDED
const BURNED: MapObjects.Change = MapObjects.Change.FUSE_BURNED
const DESTROYED: MapObjects.Change = MapObjects.Change.DESTROYED

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_catalog()
	_test_fixed_setup()
	_test_boss_battle()
	_test_unshovable()
	_test_holds_throne()
	_test_throne_heal()
	_test_pick_most_caught()
	_test_pick_reach_and_ties()
	_test_cadence_and_intent()
	_test_fuse()
	_test_early_and_chain()
	_test_darkness_lit_keg()
	_test_mirror()


func _test_catalog() -> void:
	var boss: EnemyClassDefinition = _catalog.enemy_class(BOSS_ID)
	_check.call("catalog: the Powder Baron, a Brute that holds its post with Keg Barrage", (
			boss != null
			and boss.base_class_id == "brute"
			and boss.holds_post
			and boss.behavior == EnemyClassDefinition.Behavior.GUARD
			and KegBarrage.is_barrage(boss.signature_move)
			and boss.signature_name == "Keg Barrage"
	))
	_check.call("catalog: the Baron is neither a mini-boss nor a standard class", (
			not EnemySetup.mini_boss_ids(_catalog).has(BOSS_ID)
			and not EnemySetup.standard_classes(_catalog).has(BOSS_ID)
	))


# Setup step 4 alone on the keep: the garrison on the slots in order at level 6, the Baron on the
# throne at level 8 with Stalwart, and nothing drawn, so two seeds give the same board.
func _test_fixed_setup() -> void:
	var map: CombatMapDefinition = load(KEEP_PATH) as CombatMapDefinition
	var first: Dictionary = _draw_only(map, RUN_SEED)
	var second: Dictionary = _draw_only(map, RUN_SEED + 7)
	var units: Array = first.get(EnemySetup.UNITS_KEY, [])
	var classes: PackedStringArray = []
	var problems: PackedStringArray = []
	for entry: Variant in units:
		var unit: Dictionary = entry
		var class_id: String = str(unit[EnemySetup.CLASS_KEY])
		var level: int = _whole(unit[EnemySetup.LEVEL_KEY])
		if class_id == BOSS_ID:
			var is_right: bool = (
					level == 8
					and str(unit.get(EnemySetup.PREFIX_KEY, "")) == "stalwart"
					and _tile_of(unit) == THRONE
			)
			if not is_right:
				problems.append("baron %s" % [unit])
			continue
		classes.append(class_id)
		if level != 6:
			problems.append("%s at level %d" % [class_id, level])
	_check.call("setup: the garrison on the slots in order at level 6, the Baron on the throne", (
			first.get(EnemySetup.PACK_KEY, "") == "powder_keep_garrison"
			and classes == PackedStringArray(GARRISON)
			and units.size() == GARRISON.size() + 1
			and problems.is_empty()
	), "%s; %s" % [classes, problems])
	_check.call("setup: nothing is drawn, so another seed gives the same board", (
			JSON.stringify(first) == JSON.stringify(second)
	))


# The boss pool's battle: the keep, the Baron the one marked enemy; a guard's fall leaves the map
# open, the Baron's wins it.
func _test_boss_battle() -> void:
	var pools: CombatMapPools = load(POOLS_PATH) as CombatMapPools
	var pool: CombatMapPool = pools.pool_for(CampaignGraph.NodeType.BOSS, BOSS_FLOOR)
	_check.call("pools: the boss pool holds the keep alone", (
			pool != null and pool.map_ids() == PackedStringArray(["powder_keep"])
	), "" if pool == null else str(pool.map_ids()))
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var keep: CombatMapDefinition = load(KEEP_PATH) as CombatMapDefinition
	var battle: CombatEncounter = run.begin_battle(_request(run, keep))
	if battle == null:
		_check.call("boss battle: it begins", false)
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var boss_id: String = state.occupant_at(THRONE)
	_check.call("boss battle: the Baron is the one marked enemy, on the throne", (
			not boss_id.is_empty()
			and state.unit_type_of(boss_id) == BOSS_ID
			and Objectives.marked_ids(session) == PackedStringArray([boss_id])
			and state.units_of(ENEMY).size() == GARRISON.size() + 1
	), "%s; %d enemies" % [boss_id, state.units_of(ENEMY).size()])
	var players: PackedStringArray = state.units_of(PLAYER)
	var player_id: String = players[0] if not players.is_empty() else ""
	var guard_id: String = ""
	for enemy_id: String in state.units_of(ENEMY):
		if enemy_id != boss_id:
			guard_id = enemy_id
			break
	_send(session, DefeatFixture.new([guard_id], player_id))
	_check.call("boss battle: a guard's fall leaves the map open", not session.is_finished)
	_send(session, DefeatFixture.new([boss_id], player_id))
	_check.call("boss battle: defeating the Baron wins the map with guards left", (
			session.is_won and not state.units_of(ENEMY).is_empty()
	), "won %s, %d enemies left" % [session.is_won, state.units_of(ENEMY).size()])
	run.close()


func _test_unshovable() -> void:
	var world: AiWorld = _world(_rows(6, 3))
	world.add_enemy("e1", BOSS_ID, Vector2i(2, 1))
	world.add_enemy("e2", "brute", Vector2i(4, 1))
	_check.call("unshovable: the Baron can't be shoved, a Brute can", (
			not world.engine().stats("e1").is_allowed(CombatValue.Permission.CAN_BE_SHOVED)
			and world.engine().stats("e2").is_allowed(CombatValue.Permission.CAN_BE_SHOVED)
	))


# A foe in its walking reach but not beside it: it waits on the throne. A foe beside it: it attacks
# from the throne. The same after the darkness arrives, where every other enemy turns Aggressive.
# Its danger zone is its axe's reach from where it stands.
func _test_holds_throne() -> void:
	var world: AiWorld = _world(_rows(9, 5))
	world.add_enemy("e1", BOSS_ID, Vector2i(1, 2))
	world.add_player("p1", Vector2i(4, 2), "sword", STURDY)
	var waits: EnemyPlan = world.decide("e1")
	_check.call("holds: with a foe 3 tiles off it stays on its tile", (
			waits.tile == Vector2i(1, 2) and waits.kind == EnemyPlan.Kind.WAIT
	), "%s at %s" % [EnemyPlan.Kind.find_key(waits.kind), waits.tile])
	var zone: Array[Vector2i] = DangerZone.tiles_for(world.engine(), "e1")
	var beyond: Array[Vector2i] = []
	for tile: Vector2i in zone:
		if world.state().grid.distance(tile, Vector2i(1, 2)) > 1:
			beyond.append(tile)
	_check.call("holds: its danger zone is its axe's reach from the throne", (
			not zone.is_empty() and beyond.is_empty()
	), str(zone))
	world.add_player("p2", Vector2i(2, 2), "sword", STURDY)
	var hits: EnemyPlan = world.decide("e1")
	_check.call("holds: with a foe beside it, it attacks from its tile", (
			hits.kind == EnemyPlan.Kind.ATTACK and hits.tile == Vector2i(1, 2)
	), "%s at %s" % [EnemyPlan.Kind.find_key(hits.kind), hits.tile])
	world.state().map.has_darkness_arrived = true
	world.add_enemy("e2", "brute", Vector2i(8, 4))
	var dark: EnemyPlan = world.decide("e1")
	var brute: EnemyPlan = world.decide("e2")
	_check.call("holds: after the darkness it keeps Guard and its tile; a Brute turns Aggressive", (
			dark.tile == Vector2i(1, 2)
			and dark.behavior == EnemyClassDefinition.Behavior.GUARD
			and brute.behavior == EnemyClassDefinition.Behavior.AGGRESSIVE
	), "%s %s / %s" % [
		dark.tile,
		EnemyClassDefinition.Behavior.find_key(dark.behavior),
		EnemyClassDefinition.Behavior.find_key(brute.behavior),
	])


# Wounded on a dry throne, it heals 4 at its Phase Start; on a flooded one it doesn't, and the
# darkness phase wears it down.
func _test_throne_heal() -> void:
	var rows: Array[String] = ["plain plain plain plain", "plain throne plain plain"]
	var world: AiWorld = _world(rows)
	Darkness.register(world.session)
	world.add_enemy("e1", BOSS_ID, Vector2i(1, 1))
	world.add_player("p1", Vector2i(3, 0), "bow", STURDY)
	world.session.open_battle()
	world.wound("e1", 10)
	_send(world.session, EndTurnCommand.new(0))
	var dry: int = world.state().get_hp("e1")
	world.wound("e1", 10)
	world.state().map.darkness.layers[Vector2i(1, 1)] = WhileLayerCondition.Layer.DUSK
	_send(world.session, EndTurnCommand.new(0))
	var flooded: int = world.state().get_hp("e1")
	_check.call("throne: heals the Baron 4 while dry, nothing once flooded, and it wears down", (
			dry == 14 and flooded < 10
	), "dry %d, flooded %d" % [dry, flooded])


# Three player units around one free tile in reach: that tile, whatever a guard beside it loses.
func _test_pick_most_caught() -> void:
	var world: AiWorld = _world(_rows(10, 8))
	world.add_enemy("e1", BOSS_ID, Vector2i(0, 4))
	world.add_enemy("e2", "brute", Vector2i(3, 5))
	for entry: Array in [["p1", Vector2i(2, 4)], ["p2", Vector2i(4, 4)], ["p3", Vector2i(3, 3)]]:
		world.add_player(entry[0] as String, entry[1] as Vector2i, "sword", STURDY)
	world.add_player("p4", Vector2i(9, 0), "sword", STURDY)
	var tile: Vector2i = KegBarrage.pick_tile(world.state(), "e1", RUN_SEED)
	_check.call("pick: the free tile whose blast catches three player units, a guard beside it", (
			tile == Vector2i(3, 4)
	), str(tile))


# A cluster beyond 5 tiles loses to a lone unit within them; lone units tie, broken by the seeded
# stream the same way twice, and differently for some seed; with no free tile, no throw.
func _test_pick_reach_and_ties() -> void:
	var world: AiWorld = _world(_rows(14, 3))
	world.add_enemy("e1", BOSS_ID, Vector2i(0, 1))
	world.add_player("p1", Vector2i(3, 1), "sword", STURDY)
	for entry: Array in [["p2", Vector2i(9, 1)], ["p3", Vector2i(10, 0)], ["p4", Vector2i(10, 2)]]:
		world.add_player(entry[0] as String, entry[1] as Vector2i, "sword", STURDY)
	var tile: Vector2i = KegBarrage.pick_tile(world.state(), "e1", RUN_SEED)
	_check.call("pick: nothing beyond 5 tiles; it catches the one unit in reach", (
			tile != CombatFact.NO_TILE
			and world.state().grid.distance(Vector2i(0, 1), tile) <= KegBarrage.REACH
			and MapObjects.KEG_BLAST.covers(tile, Vector2i(3, 1))
	), str(tile))
	var again: Vector2i = KegBarrage.pick_tile(world.state(), "e1", RUN_SEED)
	var picks: Dictionary[Vector2i, bool] = {}
	for run_seed: int in range(1, 13):
		picks[KegBarrage.pick_tile(world.state(), "e1", run_seed)] = true
	_check.call("pick: ties go the same way twice with one seed and differ between seeds", (
			again == tile and picks.size() > 1
	), "%s / %s; %d picks" % [tile, again, picks.size()])
	var boxed: AiWorld = _world(["plain"])
	boxed.add_enemy("e1", BOSS_ID, Vector2i(0, 0))
	_check.call("pick: with no free tile, no tile", (
			KegBarrage.pick_tile(boxed.state(), "e1", RUN_SEED) == CombatFact.NO_TILE
	))


# Players out of its axe's reach, so nobody fights: the intent shows Keg Barrage in player phases
# 2 and 4 only, over the blast of the tile it then throws to; keg lands at enemy phases 2 and 4.
func _test_cadence_and_intent() -> void:
	var world: AiWorld = _world(_rows(12, 6))
	MapObjects.place(world.session)
	world.add_enemy("e1", BOSS_ID, Vector2i(0, 2))
	world.add_player("p1", Vector2i(4, 2), "bow", STURDY)
	world.add_player("p2", Vector2i(4, 4), "bow", STURDY)
	world.session.open_battle()
	var shown: PackedStringArray = []
	var landed: PackedStringArray = []
	var matches: bool = true
	for turn: int in range(1, 6):
		var intent: EnemyIntent = _intent(world, "e1")
		var is_signature: bool = intent != null and intent.kind == EnemyIntent.Kind.SIGNATURE
		shown.append("%d %s" % [turn, intent.signature_name if is_signature else "-"])
		var from: int = world.engine().fact_log.size()
		_send(world.session, EndTurnCommand.new(0))
		for fact: CombatFact in _changes(world.session, from, LANDED):
			landed.append("%d %s" % [turn, fact.tile])
			var blast: Array[Vector2i] = MapObjects.KEG_BLAST.tiles(fact.tile)
			var area: Array[Vector2i] = [] if not is_signature else intent.area
			for tile: Vector2i in blast:
				if world.state().grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
					matches = matches and area.has(tile)
			matches = matches and area.size() <= blast.size()
	_check.call("barrage: shown as its intent in player phases 2 and 4, the phase before", (
			shown == PackedStringArray(["1 -", "2 Keg Barrage", "3 -", "4 Keg Barrage", "5 -"])
	), str(shown))
	_check.call("barrage: a keg lands at enemy phases 2 and 4, inside the blast it showed", (
			landed.size() == 2
			and landed[0].begins_with("2 ")
			and landed[1].begins_with("4 ")
			and matches
	), str(landed))


# A keg landing in turn 1's player phase burns 3 → 2 → 1 → 0 at enemy Phase Ends 1, 2 and 3 and
# explodes at the last, 5 splash to the units beside it; nothing breaks it before.
func _test_fuse() -> void:
	var world: DarknessWorld = DarknessWorld.new(_rows(5, 3))
	world.add_unit("p1", PLAYER, Vector2i(0, 1))
	world.add_unit("p2", PLAYER, Vector2i(3, 1))
	world.session.open_battle()
	world.send(ThrowFixture.new(Vector2i(2, 1)))
	var keg: MapState.ObjectState = world.object_at(Vector2i(2, 1))
	var placed: bool = (
			keg != null
			and keg.is_thrown
			and keg.index == MapObjects.THROWN_INDEX_BASE
			and world.state().get_hp(keg.id) == 10
			and world.state().map.blocks(Vector2i(2, 1), CombatGrid.MovementType.DEFAULT)
	)
	_check.call("keg: a thrown keg is a 10 HP keg on a spot past the authored ones, lit", (
			placed and keg.fuse == MapObjects.FUSE_PHASES + 1
	), "" if keg == null else "fuse %d, index %d" % [keg.fuse, keg.index])
	if keg == null:
		return
	var burns: PackedStringArray = []
	for turn: int in range(1, 4):
		var from: int = world.engine().fact_log.size()
		world.end_turns(1)
		for fact: CombatFact in _changes(world.session, from, BURNED):
			burns.append("%d:%d" % [turn, fact.amount])
		if turn < 3:
			_check.call("keg: still standing after turn %d" % [turn], not keg.is_destroyed)
	_check.call("keg: its fuse burns at each enemy Phase End and it explodes at the 3rd", (
			burns == PackedStringArray(["1:2", "2:1", "3:0"])
			and keg.is_destroyed
			and not world.state().has_unit(keg.id)
			and world.state().get_hp("p2") == 15
			and world.state().get_hp("p1") == 20
	), "%s; p2 %d" % [burns, world.state().get_hp("p2")])


# Splash on a lit keg blows it at once; its blast takes an authored keg beside it, which blows a
# lit one beside that: the chain resolves in one step.
func _test_early_and_chain() -> void:
	var world: DarknessWorld = DarknessWorld.new(
			_rows(6, 3), [[Vector2i(2, 1), MapLayout.ObjectKind.POWDER_KEG]]
	)
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.session.open_battle()
	world.send(ThrowFixture.new(Vector2i(4, 1)))
	var lone: MapState.ObjectState = world.object_at(Vector2i(4, 1))
	world.send(SplashFixture.new(lone.id))
	_check.call("keg: splash on a lit keg blows it before its fuse", lone.is_destroyed)
	world.send(ThrowFixture.new(Vector2i(1, 1)))
	world.send(ThrowFixture.new(Vector2i(3, 1)))
	var first: MapState.ObjectState = world.object_at(Vector2i(1, 1))
	var authored: MapState.ObjectState = world.object_at(Vector2i(2, 1))
	var last: MapState.ObjectState = world.object_at(Vector2i(3, 1))
	world.send(SplashFixture.new(first.id))
	_check.call("keg: a chain through an authored keg takes the lit one beyond", (
			first.is_destroyed and authored.is_destroyed and last.is_destroyed
	), "%s %s %s" % [first.is_destroyed, authored.is_destroyed, last.is_destroyed])


# Next to a flooded tile, or on one, a lit keg blows at the first darkness phase; an authored keg
# beside the same darkness only gains a contact.
func _test_darkness_lit_keg() -> void:
	var world: DarknessWorld = DarknessWorld.new(
			_rows(9, 3), [[Vector2i(7, 1), MapLayout.ObjectKind.POWDER_KEG]]
	)
	world.set_up([[Vector2i(0, 0)]], Vector2i(8, 2))
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 2))
	world.flood(Vector2i(2, 0), WhileLayerCondition.Layer.DUSK)
	world.flood(Vector2i(4, 2), WhileLayerCondition.Layer.DUSK)
	world.flood(Vector2i(7, 0), WhileLayerCondition.Layer.DUSK)
	world.session.open_battle()
	world.send(ThrowFixture.new(Vector2i(2, 1)))
	world.send(ThrowFixture.new(Vector2i(4, 2)))
	var beside: MapState.ObjectState = world.object_at(Vector2i(2, 1))
	var under: MapState.ObjectState = world.object_at(Vector2i(4, 2))
	var authored: MapState.ObjectState = world.object_at(Vector2i(7, 1))
	world.end_turns(1)
	_check.call("darkness: a lit keg beside it or on it blows at the first darkness phase", (
			beside.is_destroyed and under.is_destroyed
	), "%s %s" % [beside.is_destroyed, under.is_destroyed])
	_check.call("darkness: an authored keg beside it only gains a contact", (
			not authored.is_destroyed and world.darkness().contacts.get(authored.id, 0) == 1
	), str(world.darkness().contacts))


# A mirror loaded from the host's snapshot follows a throw, its fuse and its blast batch for batch.
func _test_mirror() -> void:
	var world: DarknessWorld = DarknessWorld.new(_rows(5, 3))
	world.add_unit("p1", PLAYER, Vector2i(3, 1))
	# The host's grid, shared read-only as an encounter shares it.
	var grid: MapGrid = world.state().grid
	var mirror: CombatSession = CombatSession.new(
			0,
			PackedInt32Array([0]),
			grid,
			ForcedRolls.new(PackedInt32Array()),
			InstanceIdAllocator.new()
	)
	var loaded: Error = mirror.load_snapshot(
			JSON.parse_string(JSON.stringify(world.session.snapshot())) as Dictionary
	)
	var batches: Array[CombatSession.FactBatch] = []
	world.session.batch_resolved.connect(func(batch: CombatSession.FactBatch) -> void:
		batches.append(batch)
	)
	world.session.open_battle()
	world.send(ThrowFixture.new(Vector2i(2, 1)))
	var keg_id: String = world.object_at(Vector2i(2, 1)).id
	var results: Array[Error] = []
	var hashes: Array[bool] = []
	var applied: int = 0
	for turn: int in range(1, 4):
		world.end_turns(1)
		for batch: CombatSession.FactBatch in batches.slice(applied):
			var wire: Array = JSON.parse_string(JSON.stringify(batch.to_wire()))
			results.append(mirror.apply_batch(CombatSession.FactBatch.from_wire(wire)))
		applied = batches.size()
		hashes.append(mirror.state_hash() == world.session.state_hash())
	var followed: MapState.ObjectState = mirror.state.map.object(keg_id)
	_check.call("mirror: it follows the throw, the fuse and the blast, hash for hash", (
			loaded == OK
			and not results.is_empty()
			and results.count(OK) == results.size()
			and not hashes.has(false)
			and followed != null
			and followed.is_thrown
			and followed.is_destroyed
			and not mirror.state.has_unit(keg_id)
	), "%s, %s, %s" % [error_string(loaded), results, hashes])


# Setup step 4 alone on map, as plain data.
func _draw_only(map: CombatMapDefinition, run_seed: int) -> Dictionary:
	var battle: CombatEncounter = CombatEncounter.new(
			BOSS_FLOOR, NODE, PackedInt32Array([0]), InstanceIdAllocator.new()
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.ENEMY_SLOTS,
			EnemySetup.draw.bind(_catalog, BOSS_FLOOR, 0, 0, "")
	)
	var pool: Array[CombatMapDefinition] = [map]
	battle.run_setup(pool, CombatEncounter.SetupStreams.new(run_seed, BOSS_FLOOR, NODE))
	var drawn: Variant = battle.setup.shared.get(EnemySetup.ENEMIES_KEY, {})
	return drawn if drawn is Dictionary else {}


# A request on map at the boss floor whose seat 0 is one real Archer with a Simple Bow, turn 1 at
# once (no opening swap).
func _request(run: CampaignSession, map: CombatMapDefinition) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BOSS_FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = _catalog
	request.opening_swap[0] = false
	var archer: UnitInstance = UnitInstance.new(run.ids.next_unit_id("Archer"), "archer")
	var bow_id: String = run.ids.next_item_id("Simple Bow")
	archer.weapon_id = bow_id
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = [archer]
	army.item_instances[bow_id] = ItemInstance.new(bow_id, "simple_bow")
	request.armies[0] = army
	return request


func _world(rows: Array[String]) -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, rows)
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	return world


# width × height plain tiles.
func _rows(width: int, height: int) -> Array[String]:
	var row: PackedStringArray = []
	for _x: int in width:
		row.append("plain")
	var rows: Array[String] = []
	for _y: int in height:
		rows.append(" ".join(row))
	return rows


func _intent(world: AiWorld, unit_id: String) -> EnemyIntent:
	var shown: Intents = world.session.intents
	return null if shown == null else shown.intent_of(unit_id)


# Every OBJECT_STATE_CHANGED of change in session's fact log from index from on.
func _changes(
		session: CombatSession, from: int, change: MapObjects.Change
) -> Array[CombatFact]:
	var found: Array[CombatFact] = []
	var facts: Array[CombatFact] = session.engine.fact_log
	for index: int in range(from, facts.size()):
		var fact: CombatFact = facts[index]
		if fact.kind == CombatFact.Kind.OBJECT_STATE_CHANGED and fact.key == change:
			found.append(fact)
	return found


func _send(session: CombatSession, command: Command) -> void:
	session.submit(command)
	var batch: CombatSession.FactBatch = session.resolve_next()
	if batch != null and batch.is_rejected():
		_check.call("send: %s accepted" % [batch.label], false, batch.rejected_reason)


func _tile_of(entry: Dictionary) -> Vector2i:
	var tile: Variant = entry.get(EnemySetup.TILE_KEY, null)
	if not tile is Array or (tile as Array).size() != 2:
		return CombatFact.NO_TILE
	var parts: Array = tile
	return Vector2i(_whole(parts[0]), _whole(parts[1]))


# A whole number from plain data, an int or a float; 0 for anything else.
func _whole(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	var number: float = value
	return roundi(number)


# Defeats each unit in order through CombatState.defeat, by by_id; a test command, so a case's
# defeats need no roll.
class DefeatFixture:
	extends Command

	var unit_ids: PackedStringArray = []
	var by_id: String = ""

	func _init(defeated: Array[String], defeated_by: String) -> void:
		unit_ids = PackedStringArray(defeated)
		by_id = defeated_by

	func get_label() -> String:
		return "defeat"

	func resolve(session: CombatSession) -> void:
		for unit_id: String in unit_ids:
			session.state.defeat(session.engine, unit_id, by_id)


# Throws a lit keg onto a tile as Keg Barrage does, by no unit; a test command, so a case can
# place one in the player phase.
class ThrowFixture:
	extends Command

	var tile: Vector2i = Vector2i.ZERO

	func _init(onto: Vector2i) -> void:
		tile = onto

	func get_label() -> String:
		return "throw"

	func resolve(session: CombatSession) -> void:
		MapObjects.throw_keg(session, tile, "")


# 1 splash to a unit or object, from no unit: what a Cleave or a blast does to a keg.
class SplashFixture:
	extends Command

	var target_id: String = ""

	func _init(onto: String) -> void:
		target_id = onto

	func get_label() -> String:
		return "splash"

	func resolve(session: CombatSession) -> void:
		session.engine.deal_splash("", target_id, 1.0)
