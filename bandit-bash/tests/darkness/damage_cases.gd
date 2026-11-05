# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     damage_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## [Darkness]'s damage and readers for tests/darkness/run_all.gd: 10/25/50% of max HP rounded down
## with a minimum of 1, at each side's own Phase End; a Phase End heal landing first; a unit
## passing through taking none; a commander it defeats ending the battle; "that darkness damage"
## halving it; no terrain heal on a flooded tile; the AI's dry tile; dry-first arrivals and the
## free-tile search; [method Darkness.damage_at] matching the damage taken; the intents preview
## foreseeing it and changing nothing; [method Darkness.next_deepening] matching the step and
## [method Darkness.source_counters]; [constant DarknessState.NO_RELEASE]; the damage as
## [method CampaignSession.begin_battle] registers it, after point closing; and the queries timed
## on the M1 map (NOTE).
##
## Layers are set on the tiles directly ([method DarknessWorld.flood]) where no wave is needed.

const DarknessWorld = preload("res://tests/darkness/darkness_world.gd")
const AiWorld = preload("res://tests/enemies/ai_world.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")
const ReinforcementCases = preload("res://tests/map/reinforcement_cases.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const DRY: WhileLayerCondition.Layer = WhileLayerCondition.Layer.DRY
const DUSK: WhileLayerCondition.Layer = WhileLayerCondition.Layer.DUSK
const GLOOM: WhileLayerCondition.Layer = WhileLayerCondition.Layer.GLOOM
const ABYSS: WhileLayerCondition.Layer = WhileLayerCondition.Layer.ABYSS
const DAMAGED: CombatFact.Kind = CombatFact.Kind.DARKNESS_DAMAGE_TAKEN
const ADVANCED: CombatFact.Kind = CombatFact.Kind.DARKNESS_ADVANCED
const WAIT: UnitTurnCommand.Action = UnitTurnCommand.Action.WAIT
const DEBRIS: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS
const BRUTE: String = "loadout_brute"

const CORRIDOR_7: Array[String] = ["plain plain plain plain plain plain plain"]

const FORTS: Array[String] = ["fort fort plain"]

const PLAIN_6X4: Array[String] = [
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
	"plain plain plain plain plain plain",
]

const PLAIN_8X8: Array[String] = [
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain",
]

# A corridor (row 0) and a side room (row 2), walled apart but for debris at (2, 1).
const SIDE_ROOM: Array[String] = [
	"plain plain plain plain plain",
	"wall wall plain wall wall",
	"plain plain plain plain plain",
]

# The sessions suite's map: rows "plain plain forest wall river", "plain road road mountain
# river", "house plain fort plain plain", "plain plain plain plain plain".
const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# Any fixed seed and node for the battles begun here.
const SEED: int = 0xD4_0001
const FLOOR: int = 1
const NODE: int = 1

# The timed M1 hovers: every tile each player unit can reach, this many times over.
const TIMED_ROUNDS: int = 20

# The timed M1 next_deepening calls: one per turn through this turn, on one battle.
const TIMED_TURNS: int = 12

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_layer_damage()
	_test_heal_first()
	_test_passing_through()
	_test_commander_defeat()
	_test_that_darkness_damage()
	_test_no_terrain_heal()
	_test_ai_dry_tile()
	_test_free_tile_search()
	_test_dry_first_arrivals()
	_test_damage_at()
	_test_intents_preview()
	_test_next_deepening()
	_test_no_release()
	_test_begin_battle_registers()
	_test_point_closing_first()
	_test_m1_timing()


# Each layer's share of max HP, rounded down, at least 1, at that side's own Phase End: the player
# units after the player PHASE_END, the enemy after the enemy's. A dry unit takes none.
func _test_layer_damage() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4)
	world.register_damage()
	# Unit, max HP, layer: 20 gives 2 / 5 / 10, 27 floors 2.7 / 6.75 / 13.5, 5 lifts 0.5 and 1.25
	# to the minimum.
	var cases: Array = [
		["p1", 20, DUSK], ["p2", 20, GLOOM], ["p3", 20, ABYSS],
		["p4", 27, DUSK], ["p5", 27, GLOOM], ["p6", 27, ABYSS],
		["p7", 5, DUSK], ["p8", 5, GLOOM], ["p9", 5, ABYSS],
	]
	for i: int in cases.size():
		var entry: Array = cases[i]
		var tile: Vector2i = Vector2i(i % 6, floori(i / 6.0))
		world.add_unit(entry[0] as String, PLAYER, tile, entry[1] as int)
		world.flood(tile, entry[2] as WhileLayerCondition.Layer)
	world.add_unit("p0", PLAYER, Vector2i(5, 3))
	world.add_unit("e1", ENEMY, Vector2i(4, 3))
	world.flood(Vector2i(4, 3), GLOOM)
	world.session.open_battle()
	var start: int = world.engine().fact_log.size()
	world.end_turns(1)
	var phases: Array = [CombatFact.Kind.PHASE_START, CombatFact.Kind.PHASE_END, DAMAGED]
	_same_lines("layers: 10/25/50%, floor, minimum 1, each side at its own Phase End",
			world.lines(phases, start), [
				"t1 PHASE_END side player",
				"t1 DARKNESS_DAMAGE_TAKEN p1 amount 2 (hp 2, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p2 amount 5 (hp 5, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p3 amount 10 (hp 10, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p4 amount 2 (hp 2, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p5 amount 6 (hp 6, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p6 amount 13 (hp 13, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p7 amount 1 (hp 1, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p8 amount 1 (hp 1, block 0) source darkness",
				"t1 DARKNESS_DAMAGE_TAKEN p9 amount 2 (hp 2, block 0) source darkness",
				"t1 PHASE_START side enemy amount 1",
				"t1 PHASE_END side enemy",
				"t1 DARKNESS_DAMAGE_TAKEN e1 amount 5 (hp 5, block 0) source darkness",
				"t2 PHASE_START side player amount 2",
			])
	_ok("layers: HP lost", (
			world.state().get_hp("p3") == 10
			and world.state().get_hp("p6") == 14
			and world.state().get_hp("p9") == 3
			and world.state().get_hp("p0") == 20
			and world.state().get_hp("e1") == 15
	))
	_quiet(world)


# A Unit Turn End heal of 5 lands before the darkness (combat core plan, question 12): p1 at 3 HP
# on Gloom (5) heals to 8 and keeps 3; p2, the same without the heal, loses its last 3 and falls,
# its fact the HP it lost.
func _test_heal_first() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4)
	world.register_damage()
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(2, 0))
	world.add_unit("p3", PLAYER, Vector2i(5, 3))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.flood(Vector2i(0, 0), GLOOM)
	world.flood(Vector2i(2, 0), GLOOM)
	var gain: GainResource = GainResource.new()
	gain.pool = GainResource.Pool.HP
	gain.amount = _constant(5.0)
	var band: EffectDefinition = EffectDefinition.new()
	band.trigger = EffectTerms.Trigger.UNIT_TURN_END
	band.operations.assign([gain])
	world.engine().register(EffectInstance.new(
			"effect:band", band, EffectOwner.for_unit("p1", 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT, "effect:band"
	))
	world.session.open_battle()
	world.state().set_hp("p1", 3)
	world.state().set_hp("p2", 3)
	var start: int = world.engine().fact_log.size()
	world.send(EndTurnCommand.new(0))
	var kinds: Array = [CombatFact.Kind.HEALED, DAMAGED, CombatFact.Kind.DEFEATED]
	_same_lines("heal first: the Phase End heal, then the darkness", world.lines(kinds, start), [
		"t1 HEALED p1 amount 5 (hp 5, block 0) source effect effect effect:band",
		"t1 DARKNESS_DAMAGE_TAKEN p1 amount 5 (hp 5, block 0) source darkness",
		"t1 DARKNESS_DAMAGE_TAKEN p2 amount 3 (hp 3, block 0) source darkness",
		"t1 DEFEATED p2",
	])
	_ok("heal first: the heal saved p1", (
			world.state().has_unit("p1") and world.state().get_hp("p1") == 3
			and not world.state().has_unit("p2")
	))
	_quiet(world)


# p1 walks the corridor through two Abyss tiles and ends dry: no darkness damage.
func _test_passing_through() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
	world.register_damage()
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.flood(Vector2i(2, 0), ABYSS)
	world.flood(Vector2i(3, 0), ABYSS)
	world.session.open_battle()
	var path: Array[Vector2i] = []
	for x: int in 6:
		path.append(Vector2i(x, 0))
	var batch: CombatSession.FactBatch = world.send(UnitTurnCommand.new(0, "p1", WAIT, "", path))
	world.end_turns(1)
	_ok("passing through: the walk resolved", (
			batch != null and not batch.is_rejected()
			and world.state().tile_of("p1") == Vector2i(5, 0)
	), "" if batch == null else batch.rejected_reason)
	_ok("passing through: no darkness damage", (
			world.lines([DAMAGED]).is_empty() and world.state().get_hp("p1") == 20
	), str(world.lines([DAMAGED])))
	_quiet(world)


# The commander at 1 HP on Dusk falls to the darkness at the player Phase End: the map is lost at
# that step's end, as for any defeat, and the enemy phase never starts.
func _test_commander_defeat() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4)
	var definition: CombatMapDefinition = CombatMapDefinition.new()
	definition.id = "darkness"
	world.session.setup = CombatEncounter.EncounterSetup.new()
	world.session.setup.map = definition
	world.session.commander_ids[0] = "p1"
	Objectives.register(world.session)
	world.register_damage()
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(5, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	world.flood(Vector2i(0, 0), DUSK)
	world.session.open_battle()
	world.state().set_hp("p1", 1)
	var start: int = world.engine().fact_log.size()
	world.end_turns(1)
	var kinds: Array = [
		DAMAGED,
		CombatFact.Kind.DEFEATED,
		CombatFact.Kind.COMBAT_ENDED,
		CombatFact.Kind.PHASE_START,
	]
	_same_lines("commander: defeated by the darkness, the map is lost", world.lines(kinds, start), [
		"t1 DARKNESS_DAMAGE_TAKEN p1 amount 1 (hp 1, block 0) source darkness",
		"t1 DEFEATED p1",
		"t1 COMBAT_ENDED side enemy amount 1",
	])
	_ok("commander: the session is finished and lost", (
			world.session.is_finished and not world.session.is_won
	))


# "That darkness damage": Lantern Oil's ×0.5 on the Multipliers stage (event bus plan) and a ×0.5
# on the amount each halve p1's and p3's 5 on Gloom to 2 (2.5 rounded down); p2 takes 5.
# damage_at foresees each on a sandbox and leaves the real session as it was.
func _test_that_darkness_damage() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4)
	world.register_damage()
	for i: int in 3:
		var tile: Vector2i = Vector2i(i, 0)
		world.add_unit("p%d" % [i + 1], PLAYER, tile)
		world.flood(tile, GLOOM)
	world.add_unit("e1", ENEMY, Vector2i(5, 3))
	_halve("effect:lantern", "p1", ModifyThat.What.VALUE, DamageStage.Key.MULTIPLIERS, world)
	_halve("effect:amount", "p3", ModifyThat.What.AMOUNT, 0, world)
	world.session.open_battle()
	var facts: int = world.engine().fact_log.size()
	var foreseen: Array[int] = []
	for i: int in 3:
		foreseen.append(Darkness.damage_at(world.engine(), "p%d" % [i + 1], Vector2i(i, 0)))
	_ok("that darkness damage: damage_at changes nothing", (
			world.engine().fact_log.size() == facts and world.state().get_hp("p1") == 20
	))
	world.end_turns(1)
	var taken: Array[int] = []
	for fact: CombatFact in world.engine().fact_log:
		if fact.kind == DAMAGED and fact.actor_id.begins_with("p"):
			taken.append(fact.amount)
	_same("that darkness damage: Multipliers ×0.5, none, amount ×0.5", str(taken), str([2, 5, 2]))
	_same("that darkness damage: damage_at matches", str(foreseen), str(taken))
	_quiet(world)


# Phase Start terrain healing: the dry fort heals 20% of max HP (4), the flooded one nothing.
func _test_no_terrain_heal() -> void:
	var world: DarknessWorld = DarknessWorld.new(FORTS)
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(1, 0))
	world.flood(Vector2i(0, 0), DUSK)
	world.state().set_hp("p1", 10)
	world.state().set_hp("p2", 10)
	world.session.open_battle()
	# Terrain healing comes before its Phase Start's PHASE_START, so lines() counts it as turn 0.
	_same_lines("terrain: only the dry fort heals", world.lines([CombatFact.Kind.HEALED]), [
		"t0 HEALED p2 amount 4 (hp 4, block 0)",
	])
	_ok("terrain: HP", world.state().get_hp("p1") == 10 and world.state().get_hp("p2") == 14)
	_quiet(world)


# The Brute attacks p1 from (2, 1) on a dry board; with (2, 1) flooded in the darkness state, the
# AI and its registration take the dry (1, 2), which serves the same attack.
func _test_ai_dry_tile() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	var world: AiWorld = AiWorld.new(catalog, PLAIN_6X4)
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 2), "bow")
	var state: CombatState = world.state()
	var none: Dictionary[Vector2i, bool] = EnemyAI.flooded_tiles(state)
	var dry: EnemyPlan = EnemyAI.decide(world.engine(), catalog, "e1", none)
	state.map.darkness.layers[Vector2i(2, 1)] = DUSK
	var flooded: Dictionary[Vector2i, bool] = EnemyAI.flooded_tiles(state)
	var plan: EnemyPlan = EnemyAI.decide(world.engine(), catalog, "e1", flooded)
	EnemyAI.register(world.session, catalog)
	world.session.open_battle()
	world.session.submit(EndTurnCommand.new(0))
	world.session.resolve_next()
	var moved_to: Vector2i = CombatFact.NO_TILE
	for fact: CombatFact in world.engine().fact_log:
		if fact.kind == CombatFact.Kind.UNIT_MOVED and fact.actor_id == "e1":
			moved_to = fact.tile
	_ok("AI: on a dry board it attacks from (2, 1)", dry.tile == Vector2i(2, 1), str(dry.tile))
	_ok("AI: the darkness state's flooded tiles", (
			flooded.size() == 1 and flooded.has(Vector2i(2, 1))
	), str(flooded))
	_ok("AI: a dry tile that serves the same attack", (
			plan.target_id == "p1" and plan.tile == Vector2i(1, 2) and not plan.is_flooded
	), "%s at %s" % [plan.target_id, plan.tile])
	_ok("AI: its registration, in the enemy phase, takes the dry tile too",
			moved_to == Vector2i(1, 2), str(moved_to))


# Pathing.nearest_free_tile: dry first, then the nearest on the lowest layer; the origin itself
# when free and dry, as before the darkness arrives.
func _test_free_tile_search() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4)
	var state: CombatState = world.state()
	var origin: Vector2i = Vector2i(0, 0)
	var walker: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT
	var first: Vector2i = Pathing.nearest_free_tile(state, origin, walker)
	_ok("search: the origin when free and dry", first == origin, str(first))
	world.flood(origin, GLOOM)
	world.flood(Vector2i(1, 0), DUSK)
	world.flood(Vector2i(0, 1), DUSK)
	var found: Vector2i = Pathing.nearest_free_tile(state, origin, walker)
	_ok("search: past flooded neighbors to the nearest dry tile", (
			world.darkness().layer_at(found) == DRY and state.grid.distance(origin, found) == 2
	), str(found))
	for y: int in 4:
		for x: int in 6:
			world.flood(Vector2i(x, y), GLOOM)
	world.flood(Vector2i(3, 3), DUSK)
	world.flood(Vector2i(5, 3), DUSK)
	var lowest: Vector2i = Pathing.nearest_free_tile(state, origin, walker)
	_ok("search: all flooded, the nearest on the lowest layer", lowest == Vector2i(3, 3),
			str(lowest))


# A unit sent from a won map to (0, 3) on a map whose darkness covers every tile but (4, 3): it
# arrives on the dry (4, 3), not its flooded arrival tile.
func _test_dry_first_arrivals() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var seats: PackedInt32Array = [0, 1]
	var encounter: CombatEncounter = CombatEncounter.new(FLOOR, NODE, seats, ids)
	var map: CombatMapDefinition = CombatMapDefinition.new()
	map.id = "map_a"
	map.scene = FIXTURE_SCENE
	var pool: Array[CombatMapDefinition] = [map]
	var err: Error = encounter.run_setup(
			pool, CombatEncounter.SetupStreams.new(SEED, FLOOR, NODE)
	)
	var rolls: Dictionary[int, RngStream] = {0: RngStream.new(1), 1: RngStream.new(2)}
	if err != OK or not encounter.open_sessions(rolls):
		_ok("arrivals: the encounter opens", false, error_string(err))
		return
	var sender: String = _place(encounter.get_session(0), ids, 0, Vector2i(0, 3))
	_place(encounter.get_session(1), ids, 1, Vector2i(0, 0))
	encounter.submit(EndMap.new(), 0)
	encounter.resolve_queued()
	var reason: String = encounter.send_unit(sender, 0, 1, Vector2i(0, 3))
	var receiving: CombatState = encounter.get_session(1).state
	for y: int in 4:
		for x: int in 5:
			receiving.map.darkness.layers[Vector2i(x, y)] = DUSK
	receiving.map.darkness.layers[Vector2i(0, 3)] = GLOOM
	receiving.map.darkness.layers.erase(Vector2i(4, 3))
	var arrived: PackedStringArray = encounter.deliver_arrivals(1)
	_ok("arrivals: sent and delivered", (
			reason.is_empty() and arrived == PackedStringArray([sender])
	), reason)
	_ok("arrivals: on the dry tile, not the flooded arrival tile", (
			receiving.tile_of(sender) == Vector2i(4, 3)
	), str(receiving.tile_of(sender)))


# damage_at for each layer and a dry tile, the unit's own and others it could move to, then the
# damage it actually takes there; capped at a 3-HP unit's HP; 0 for a unit off the map.
func _test_damage_at() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
	world.register_damage()
	world.add_unit("p1", PLAYER, Vector2i(0, 0))
	world.add_unit("p2", PLAYER, Vector2i(6, 0))
	world.add_unit("e1", ENEMY, Vector2i(5, 0))
	world.flood(Vector2i(1, 0), DUSK)
	world.flood(Vector2i(2, 0), GLOOM)
	world.flood(Vector2i(3, 0), ABYSS)
	world.flood(Vector2i(6, 0), ABYSS)
	world.session.open_battle()
	world.state().set_hp("p2", 3)
	var engine: EffectEngine = world.engine()
	var foreseen: PackedStringArray = []
	for x: int in 4:
		foreseen.append(str(Darkness.damage_at(engine, "p1", Vector2i(x, 0))))
	_same("damage_at: dry, Dusk, Gloom, Abyss", " ".join(foreseen), "0 2 5 10")
	var lethal: int = Darkness.damage_at(engine, "p2", Vector2i(6, 0))
	_ok("damage_at: at most the unit's HP", lethal == 3, str(lethal))
	_ok("damage_at: 0 off the map", Darkness.damage_at(engine, "nobody", Vector2i(3, 0)) == 0)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	world.send(UnitTurnCommand.new(0, "p1", WAIT, "", path))
	world.end_turns(1)
	var taken: Dictionary[String, int] = {}
	for fact: CombatFact in engine.fact_log:
		if fact.kind == DAMAGED:
			taken[fact.actor_id] = fact.amount
	var p1_taken: int = taken.get("p1", -1)
	var p2_taken: int = taken.get("p2", -1)
	_ok("damage_at: matches the damage taken", (
			p1_taken == int(foreseen[3]) and p2_taken == lethal
	), str(taken))
	_quiet(world)


# The Brute's hit takes 15 of p1's 20; p1's Gloom tile takes 5 more at the player Phase End. The
# intents' forecasts, on a stand-in crossing that Phase End, foresee the kill; a preview moving p1
# to a dry tile foresees none; the real session keeps its HP and fact log.
func _test_intents_preview() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	var world: AiWorld = AiWorld.new(catalog, PLAIN_8X8, ForecastRolls.new())
	world.add_enemy("e1", BRUTE, Vector2i(0, 0))
	world.add_player("p1", Vector2i(2, 0), "bow")
	world.state().map.darkness.layers[Vector2i(2, 0)] = GLOOM
	Darkness.register_damage(world.session)
	EnemyAI.register(world.session, catalog)
	Intents.register(world.session, catalog)
	world.session.open_battle()
	var facts: int = world.engine().fact_log.size()
	var shown: Intents = world.session.intents
	var intent: EnemyIntent = null if shown == null else shown.intent_of("e1")
	_ok("intents: the forecasts see the darkness damage and foresee the kill", (
			intent != null and intent.target_id == "p1" and intent.defeats.has("p1")
	), "" if intent == null else intent.describe())
	var moved: Intents = Intents.preview(world.session, "p1", Vector2i(2, 1))
	var moved_intent: EnemyIntent = null if moved == null else moved.intent_of("e1")
	_ok("intents: moved to a dry tile, no kill", (
			moved_intent != null and not moved_intent.defeats.has("p1")
	), "" if moved_intent == null else moved_intent.describe())
	_ok("intents: the real session is untouched", (
			world.state().get_hp("p1") == 20
			and world.engine().fact_log.size() == facts
			and world.engine().diagnostics.is_empty()
	), "hp %d" % [world.state().get_hp("p1")])


# The side room's erosion map (step_cases.gd): before each of turns 1 to 6, next_deepening names
# exactly the tiles that turn's step then deepens, debris breaking on turn 4 included, and changes
# nothing; the counters run 1 (first release at the end of turn 1), then 2, 1, 2, 1, 2.
func _test_next_deepening() -> void:
	var world: DarknessWorld = DarknessWorld.new(SIDE_ROOM, [[Vector2i(2, 1), DEBRIS]])
	world.set_up([[Vector2i(0, 0)]], Vector2i(4, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 2))
	_same("counters: before the battle opens, counted from turn 1",
			str(Darkness.source_counters(world.state())), str(PackedInt32Array([1])))
	world.session.open_battle()
	var mismatches: PackedStringArray = []
	var counters: PackedStringArray = []
	var untouched: bool = true
	for turn: int in range(1, 7):
		var before: String = DarknessWorld.describe_state(world.state())
		var facts: int = world.engine().fact_log.size()
		var predicted: Dictionary[Vector2i, WhileLayerCondition.Layer] = Darkness.next_deepening(
				world.engine()
		)
		counters.append(str(Darkness.source_counters(world.state())[0]))
		untouched = untouched and (
				DarknessWorld.describe_state(world.state()) == before
				and world.engine().fact_log.size() == facts
		)
		world.end_turns(1)
		var actual: Dictionary[Vector2i, WhileLayerCondition.Layer] = {}
		for i: int in range(facts, world.engine().fact_log.size()):
			var fact: CombatFact = world.engine().fact_log[i]
			if fact.kind == ADVANCED and fact.tile != CombatFact.NO_TILE:
				actual[fact.tile] = fact.amount as WhileLayerCondition.Layer
		if predicted != actual:
			mismatches.append("t%d predicted %s, got %s" % [turn, predicted, actual])
		if turn == 4 and not predicted.has(Vector2i(2, 1)):
			mismatches.append("t4 misses the lane the break opens")
	_ok("next deepening: matches each step, breaks included", mismatches.is_empty(),
			"; ".join(mismatches))
	_ok("next deepening: changes nothing", untouched)
	_same("counters: turns to arrival, then to each next wave", " ".join(counters), "1 2 1 2 1 2")
	_quiet(world)


# NO_RELEASE is a number no first release takes, -1 (par 1 with Short Wick) included, and a JSON
# round trip keeps it; a map with sources but no first release never releases.
func _test_no_release() -> void:
	_ok("no release: not a first release a map can have", (
			DarknessState.NO_RELEASE < -1 and DarknessState.NO_RELEASE != 0
	), str(DarknessState.NO_RELEASE))
	var parsed: Variant = JSON.parse_string(JSON.stringify([DarknessState.NO_RELEASE]))
	var number: float = (parsed as Array)[0]
	_ok("no release: survives a JSON round trip", int(number) == DarknessState.NO_RELEASE)
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
	world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
	_ok("no release: sources without a first release never release", (
			Darkness.release_turn(world.darkness()) == DarknessState.NO_RELEASE
			and not Darkness.is_release_due(world.darkness(), 1)
			and Darkness.source_counters(world.state()).is_empty()
	))
	world.darkness().first_release = -1
	_ok("no release: -1 is a release (turn 1)", (
			Darkness.release_turn(world.darkness()) == Darkness.EARLIEST_RELEASE
	))


# The queries on the M1 battle (the Mercenary army, the real catalog), every tile at Gloom:
# damage_at for every player unit on every tile it can reach, without an effect answering darkness
# damage (stat sheet only) and with Lantern Oil (a sandbox per call); then next_deepening once per
# turn as the real darkness runs.
func _test_m1_timing() -> void:
	var run_session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var session: CombatSession = _begin_m1(run_session)
	if session == null:
		_ok("m1 queries: the battle begins", false)
		run_session.close()
		return
	var state: CombatState = session.state
	var real_layers: Dictionary[Vector2i, WhileLayerCondition.Layer] = state.map.darkness.layers
	var flooded: Dictionary[Vector2i, WhileLayerCondition.Layer] = {}
	for tile: Vector2i in session.layout.tiles():
		flooded[tile] = GLOOM
	state.map.darkness.layers = flooded
	# Verify mode (on in debug builds) rebuilds every stat sheet read fresh to check the cache; a
	# release build reads the cache only, so each query is timed both ways.
	var plain: Array[int] = _time_hovers(session)
	session.engine.verify = false
	var plain_cached: Array[int] = _time_hovers(session)
	session.engine.verify = true
	_halve("effect:lantern", "", ModifyThat.What.VALUE, DamageStage.Key.MULTIPLIERS, null, session)
	var answered: Array[int] = _time_hovers(session)
	session.engine.verify = false
	var answered_cached: Array[int] = _time_hovers(session)
	session.engine.verify = true
	_note("m1 damage_at, no effect answering", plain)
	_note("m1 damage_at, no effect answering, verify off", plain_cached)
	_note("m1 damage_at, Lantern Oil (sandbox)", answered)
	_note("m1 damage_at, Lantern Oil (sandbox), verify off", answered_cached)
	state.map.darkness.layers = real_layers

	var steps: Array[int] = []
	var counters: Array[int] = []
	for turn: int in range(1, TIMED_TURNS + 1):
		state.turn = turn
		var started: int = Time.get_ticks_usec()
		Darkness.next_deepening(session.engine)
		steps.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		Darkness.source_counters(state)
		counters.append(Time.get_ticks_usec() - started)
		session.engine.begin_step()
		Darkness.advance(session.engine, state)
		session.engine.drain()
	_note("m1 next_deepening, turns 1-%d" % [TIMED_TURNS], steps)
	_note("m1 source_counters, turns 1-%d" % [TIMED_TURNS], counters)
	_ok("m1 queries: timed", not plain.is_empty() and not answered.is_empty())
	run_session.close()


# The M1 battle as CampaignSession.begin_battle registers it: a player unit put on Gloom takes 25%
# at the first player Phase End. (The headless M1 battles in tests/enemies never end a phase in the
# darkness: held past turn 3, the commander falls in turn 5, before it reaches anyone.)
func _test_begin_battle_registers() -> void:
	var run_session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var session: CombatSession = _begin_m1(run_session)
	if session == null:
		_ok("begin_battle: the M1 battle begins", false)
		run_session.close()
		return
	var unit_id: String = session.state.units_of(PLAYER)[0]
	var max_hp: int = session.stats(unit_id).get_int(CombatValue.Key.HP)
	session.state.map.darkness.layers[session.state.tile_of(unit_id)] = GLOOM
	if session.state.map.opening_swap_open:
		session.submit(StartCommand.new(0))
		session.resolve_next()
	var start: int = session.engine.fact_log.size()
	session.submit(EndTurnCommand.new(0))
	session.resolve_next()
	var amounts: Array[int] = []
	for i: int in range(start, session.engine.fact_log.size()):
		var fact: CombatFact = session.engine.fact_log[i]
		if fact.kind == DAMAGED:
			amounts.append(fact.amount)
	_ok("begin_battle: registers the darkness damage", (
			amounts.size() == 1 and amounts[0] == floori(max_hp * 0.25)
	), "%s of max HP %d" % [amounts, max_hp])
	run_session.close()


# A player unit ending its turn on an open reinforcement point that is flooded: the point closes
# first, then the darkness hurts it (darkness plan question 5), registered in CampaignSession's
# order.
func _test_point_closing_first() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4, [], [[Vector2i(5, 3), [3]]])
	world.register(ReinforcementCases.FixtureGroups.new({3: ["Bandit"]}))
	world.register_damage()
	world.add_unit("p1", PLAYER, Vector2i(5, 3))
	world.flood(Vector2i(5, 3), DUSK)
	world.session.open_battle()
	var start: int = world.engine().fact_log.size()
	world.end_turns(1)
	var point: String = world.state().map.points[0].id
	_same_lines("point closing: before the darkness",
			world.lines([CombatFact.Kind.OBJECT_STATE_CHANGED, DAMAGED], start), [
				"t1 OBJECT_STATE_CHANGED %s -> p1 change 6 tile (5, 3)" % [point],
				"t1 DARKNESS_DAMAGE_TAKEN p1 amount 2 (hp 2, block 0) source darkness",
			])
	_quiet(world)


# Begins the M1 battle on run_session: the Mercenary army, the real catalog. Null when it fails.
func _begin_m1(run_session: CampaignSession) -> CombatSession:
	var definition: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	if definition == null:
		return null
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var mercenary: StartingArmy = StartingArmy.build(catalog, "mercenary", run_session.ids)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	army.heirloom_ids = mercenary.heirloom_ids
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [definition]
	request.catalog = catalog
	request.armies[0] = army
	var battle: CombatEncounter = run_session.begin_battle(request)
	return null if battle == null else battle.get_session(0)


# Microseconds per damage_at call: every player unit on session's map, on every tile it can reach,
# TIMED_ROUNDS times.
func _time_hovers(session: CombatSession) -> Array[int]:
	var samples: Array[int] = []
	var state: CombatState = session.state
	for _round: int in TIMED_ROUNDS:
		for unit_id: String in state.units_of(PLAYER):
			for tile: Vector2i in Pathing.reach(session.engine, state, unit_id):
				var started: int = Time.get_ticks_usec()
				Darkness.damage_at(session.engine, unit_id, tile)
				samples.append(Time.get_ticks_usec() - started)
	return samples


# Registers "×0.5 <what> for that darkness damage": owned by unit_id (This unit) on world's
# session, or, with an empty unit_id, by seat 0's army (Your Unit) on session.
func _halve(
		instance_id: String,
		unit_id: String,
		what: ModifyThat.What,
		key: int,
		world: DarknessWorld,
		session: CombatSession = null
) -> void:
	var halve: ModifyThat = ModifyThat.new()
	halve.what = what
	halve.mode = Modifier.Mode.MULTIPLY
	halve.value = 0.5
	halve.key = key
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = EffectTerms.Trigger.DARKNESS_DAMAGE_TAKEN
	definition.operations.assign([halve])
	var owner: EffectOwner = EffectOwner.for_unit(unit_id, 0, PLAYER)
	var kind: Modifier.SourceKind = Modifier.SourceKind.UNIT_TRAIT
	if unit_id.is_empty():
		definition.scope = EffectTerms.Scope.YOUR_UNIT
		owner = EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0)
		kind = Modifier.SourceKind.HEIRLOOM
	var on: CombatSession = session if session != null else world.session
	on.engine.register(EffectInstance.new(instance_id, definition, owner, kind, instance_id))


# Places a player unit of seat on session's map at tile with 20 HP. Returns its id.
func _place(
		session: CombatSession, ids: InstanceIdAllocator, seat: int, tile: Vector2i
) -> String:
	var unit: CombatUnitState = CombatUnitState.new()
	unit.id = ids.next_unit_id("Archer")
	unit.side = PLAYER
	unit.seat = seat
	unit.tile = tile
	unit.unit_type = "Archer"
	unit.hp = 20
	session.add_unit(unit, {
		CombatValue.Key.HP: 20.0,
		CombatValue.Key.STANCE_MAX: 2.0,
		CombatValue.Key.MOVEMENT: 5.0,
	})
	return unit.id


func _constant(value: float) -> Constant:
	var constant: Constant = Constant.new()
	constant.value = value
	return constant


# A NOTE line: median, p95 and max of samples, in microseconds.
func _note(label: String, samples: Array[int]) -> void:
	if samples.is_empty():
		return
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var median: int = sorted[floori(sorted.size() / 2.0)]
	var p95: int = sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))]
	print("NOTE  %s (%d calls, debug): median %d us, p95 %d us, max %d us" % [
		label, sorted.size(), median, p95, sorted[sorted.size() - 1],
	])


func _quiet(world: DarknessWorld) -> void:
	var diagnostics: PackedStringArray = world.session.engine.diagnostics
	_ok("diagnostics: none", diagnostics.is_empty(), str(diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


func _same_lines(case_name: String, actual: Array[String], expected: Array[String]) -> void:
	_check.call(case_name, actual == expected, "got\n      " + "\n      ".join(actual))


## A command that ends the map it resolves on, won by the player: a won map can send its units.
class EndMap:
	extends Command

	func resolve(session: CombatSession) -> void:
		var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
		ended.side = CombatFact.CombatSide.PLAYER
		session.engine.record(ended)
