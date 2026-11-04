# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     step_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## [Darkness]'s cases for tests/darkness/run_all.gd: golden fact logs of real turn loops on
## fixture maps (the first release at the end of turn par − 1 and every 2 turns after, creep 2 per
## turn; a par 1 map released at the end of turn 1; erosion breaking debris after 3 contacts and
## the next creep using the lane; a door closing holding its layer and reopening resuming the
## flow; no reinforcement after arrival), the AI turning aggressive, the intents preview and a
## sandbox step changing nothing on the real session, and the step timed on the M1 map (NOTE).
##
## Golden logs are worked by hand from the flow rules (heights from the drain; steps downhill 1,
## level 2, uphill 3) and written as [method DarknessWorld.lines] gives them. Each map's turn par
## is given as its [member DarknessState.first_release] (par − 1).

const DarknessWorld = preload("res://tests/darkness/darkness_world.gd")
const AiWorld = preload("res://tests/enemies/ai_world.gd")
const LoadoutCases = preload("res://tests/content/loadout_cases.gd")
const ReinforcementCases = preload("res://tests/map/reinforcement_cases.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ADVANCED: CombatFact.Kind = CombatFact.Kind.DARKNESS_ADVANCED
const CHANGED: CombatFact.Kind = CombatFact.Kind.OBJECT_STATE_CHANGED
const DEBRIS: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const LEVER: MapLayout.ObjectKind = MapLayout.ObjectKind.LEVER

const CORRIDOR_7: Array[String] = ["plain plain plain plain plain plain plain"]

# A corridor (row 0) and a side room (row 2), walled apart but for debris at (2, 1).
const SIDE_ROOM: Array[String] = [
	"plain plain plain plain plain",
	"wall wall plain wall wall",
	"plain plain plain plain plain",
]

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

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# The timed M1 runs: fresh battles, and the turns each plays (arrival at the end of turn 4).
const TIMED_RUNS: int = 20
const TIMED_TURNS: int = 16

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_schedule()
	_test_par_one()
	_test_no_darkness()
	_test_erosion()
	_test_door()
	_test_reinforcements()
	_test_ai_turns_aggressive()
	_test_stand_in()
	_test_m1_timing()


# Par 3: the first wave at the end of turn 2 (arrival), the next at 4 and 6; each wave's reach
# grows by 2 per turn. Flow cost on the corridor is x, all downhill to the drain at (6, 0).
func _test_schedule() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
	world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
	world.darkness().first_release = 2
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(6, 0))
	world.session.open_battle()
	world.end_turns(1)
	_ok("schedule: not arrived after turn 1", (
			not world.state().map.has_darkness_arrived and world.darkness().waves.is_empty()
	))
	world.end_turns(1)
	_ok("schedule: arrived at the end of turn 2 (par 3)", (
			world.state().map.has_darkness_arrived
			and Reinforcements.has_darkness_arrived(world.state())
	))
	world.end_turns(4)
	_same_lines("schedule: golden log, turns 1-6", world.lines([ADVANCED]), [
		"t2 DARKNESS_ADVANCED flags 0x6 key 0",
		"t2 DARKNESS_ADVANCED amount 1 tile (0, 0) key 0",
		"t3 DARKNESS_ADVANCED amount 1 tile (1, 0) key 0",
		"t3 DARKNESS_ADVANCED amount 1 tile (2, 0) key 0",
		"t4 DARKNESS_ADVANCED amount 1 tile (3, 0) key 0",
		"t4 DARKNESS_ADVANCED amount 1 tile (4, 0) key 0",
		"t4 DARKNESS_ADVANCED flags 0x2 key 0",
		"t4 DARKNESS_ADVANCED amount 2 tile (0, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 1 tile (5, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 1 tile (6, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (1, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (2, 0) key 0",
		"t6 DARKNESS_ADVANCED amount 2 tile (3, 0) key 0",
		"t6 DARKNESS_ADVANCED amount 2 tile (4, 0) key 0",
		"t6 DARKNESS_ADVANCED flags 0x2 key 0",
		"t6 DARKNESS_ADVANCED amount 3 tile (0, 0) key 0",
	])
	_same("schedule: reaches grow by 2 per turn, oldest first", world.reaches(), "8 4 0")
	_same("schedule: layers after turn 6", world.row_layers(0, 7), "3 2 2 2 2 1 1")
	_quiet(world)


# Par 1 (first release 0) and par 1 with Short Wick (-1): released at the end of turn 1, never
# before, then every 2 turns from there.
func _test_par_one() -> void:
	for first_release: int in [0, -1]:
		var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
		world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
		world.darkness().first_release = first_release
		world.register()
		world.add_unit("p1", PLAYER, Vector2i(6, 0))
		world.session.open_battle()
		_ok("par 1 (first release %d): not arrived during turn 1" % [first_release], (
				not world.state().map.has_darkness_arrived
		))
		world.end_turns(5)
		var released: PackedStringArray = []
		for line: String in world.lines([ADVANCED]):
			if line.contains("flags"):
				released.append(line)
		_same("par 1 (first release %d): releases at the end of turns 1, 3, 5" % [first_release],
				" | ".join(released), " | ".join([
					"t1 DARKNESS_ADVANCED flags 0x6 key 0",
					"t3 DARKNESS_ADVANCED flags 0x2 key 0",
					"t5 DARKNESS_ADVANCED flags 0x2 key 0",
				]))
		_ok("par 1 (first release %d): release turn 1" % [first_release],
				Darkness.release_turn(world.darkness()) == Darkness.EARLIEST_RELEASE)


# A map with no active source: no step does anything, whatever first_release says.
func _test_no_darkness() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(6, 0))
	world.session.open_battle()
	world.end_turns(3)
	_ok("no source: no fact, no arrival", (
			world.lines([ADVANCED]).is_empty() and not world.state().map.has_darkness_arrived
	))
	_ok("no source: no release turn",
			Darkness.release_turn(world.darkness()) == DarknessState.NO_RELEASE
			and not Darkness.is_release_due(world.darkness(), 1))


# Par 2: debris at (2, 1) touches the corridor's (2, 0) from turn 2, breaks at turn 4's third
# contact, the recalculation lets wave 0 (reach 6) into (2, 1) at cost 2 + 3 uphill, and turn 5's
# creep (reach 8) carries it on into the side room's (2, 2).
func _test_erosion() -> void:
	var world: DarknessWorld = DarknessWorld.new(SIDE_ROOM, [[Vector2i(2, 1), DEBRIS]])
	world.set_up([[Vector2i(0, 0)]], Vector2i(4, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 2))
	world.session.open_battle()
	var debris: String = world.object_at(Vector2i(2, 1)).id
	world.end_turns(6)
	var expected: Array[String] = [
		"t1 DARKNESS_ADVANCED flags 0x6 key 0",
		"t1 DARKNESS_ADVANCED amount 1 tile (0, 0) key 0",
		"t2 DARKNESS_ADVANCED amount 1 tile (1, 0) key 0",
		"t2 DARKNESS_ADVANCED amount 1 tile (2, 0) key 0",
		"t2 OBJECT_STATE_CHANGED %s change 7 amount 1 tile (2, 1)" % [debris],
		"t3 DARKNESS_ADVANCED amount 1 tile (3, 0) key 0",
		"t3 DARKNESS_ADVANCED amount 1 tile (4, 0) key 0",
		"t3 DARKNESS_ADVANCED flags 0x2 key 0",
		"t3 DARKNESS_ADVANCED amount 2 tile (0, 0) key 0",
		"t3 OBJECT_STATE_CHANGED %s change 7 amount 2 tile (2, 1)" % [debris],
		"t4 DARKNESS_ADVANCED amount 2 tile (1, 0) key 0",
		"t4 DARKNESS_ADVANCED amount 2 tile (2, 0) key 0",
		"t4 OBJECT_STATE_CHANGED %s change 8 amount 3 tile (2, 1)" % [debris],
		"t4 OBJECT_STATE_CHANGED %s change 5 tile (2, 1)" % [debris],
		"t4 DARKNESS_ADVANCED amount 1 tile (2, 1) key 0",
		"t5 DARKNESS_ADVANCED amount 1 tile (2, 2) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (3, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (4, 0) key 0",
		"t5 DARKNESS_ADVANCED flags 0x2 key 0",
		"t5 DARKNESS_ADVANCED amount 3 tile (0, 0) key 0",
		"t6 DARKNESS_ADVANCED amount 2 tile (2, 1) key 0",
		"t6 DARKNESS_ADVANCED amount 3 tile (1, 0) key 0",
		"t6 DARKNESS_ADVANCED amount 3 tile (2, 0) key 0",
	]
	_same_lines("erosion: golden log, turns 1-6", world.lines([ADVANCED, CHANGED]), expected)
	_ok("erosion: the debris is off the map and its tile floodable", (
			world.object_at(Vector2i(2, 1)).is_destroyed
			and not world.state().has_unit(debris)
			and DarknessFlow.is_floodable(world.state(), Vector2i(2, 1))
	))
	var contacts: int = world.darkness().contacts.get(debris, 0)
	_ok("erosion: its contact count stays at the limit", contacts == Darkness.CONTACT_LIMIT)
	_quiet(world)


# Par 2, a lever at (1, 0) working the door at (3, 0). Open from turn 1, the corridor costs x;
# closed, (0..2, 0) can't reach the drain, so their steps are level (2) and nothing passes.
func _test_door() -> void:
	var world: DarknessWorld = DarknessWorld.new(
			CORRIDOR_7, [[Vector2i(3, 0), DOOR], [Vector2i(1, 0), LEVER]]
	)
	var door: MapState.ObjectState = world.object_at(Vector2i(3, 0))
	var lever: MapState.ObjectState = world.object_at(Vector2i(1, 0))
	door.group_id = 0
	lever.group_id = 0
	world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	world.session.open_battle()
	var pull: UnitTurnCommand = UnitTurnCommand.new(
			0, "p1", UnitTurnCommand.Action.USE_OBJECT, lever.id
	)
	var problems: PackedStringArray = []
	_pull(world, pull, problems)
	world.end_turns(3)
	var before_closing: int = world.session.engine.fact_log.size()
	_pull(world, pull, problems)
	var closed_layer: int = world.darkness().layer_at(door.tile)
	var closing: Array[String] = world.lines([ADVANCED], before_closing)
	world.end_turns(1)
	_pull(world, pull, problems)
	world.end_turns(1)
	_ok("door: every pull resolved", problems.is_empty(), str(problems))
	_same_lines("door: golden log, turns 1-5", world.lines([ADVANCED, CHANGED]), [
		"t1 OBJECT_STATE_CHANGED %s -> p1 change 0 tile (3, 0)" % [door.id],
		"t1 DARKNESS_ADVANCED flags 0x6 key 0",
		"t1 DARKNESS_ADVANCED amount 1 tile (0, 0) key 0",
		"t2 DARKNESS_ADVANCED amount 1 tile (1, 0) key 0",
		"t2 DARKNESS_ADVANCED amount 1 tile (2, 0) key 0",
		"t3 DARKNESS_ADVANCED amount 1 tile (3, 0) key 0",
		"t3 DARKNESS_ADVANCED amount 1 tile (4, 0) key 0",
		"t3 DARKNESS_ADVANCED flags 0x2 key 0",
		"t3 DARKNESS_ADVANCED amount 2 tile (0, 0) key 0",
		"t4 OBJECT_STATE_CHANGED %s -> p1 change 1 tile (3, 0)" % [door.id],
		"t4 DARKNESS_ADVANCED amount 2 tile (1, 0) key 0",
		"t5 OBJECT_STATE_CHANGED %s -> p1 change 0 tile (3, 0)" % [door.id],
		"t5 DARKNESS_ADVANCED amount 1 tile (5, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 1 tile (6, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (2, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (3, 0) key 0",
		"t5 DARKNESS_ADVANCED amount 2 tile (4, 0) key 0",
		"t5 DARKNESS_ADVANCED flags 0x2 key 0",
		"t5 DARKNESS_ADVANCED amount 3 tile (0, 0) key 0",
	])
	_ok("door: closing keeps the door tile's layer and deepens nothing", (
			closed_layer == WhileLayerCondition.Layer.DUSK and closing.is_empty()
	), "layer %d; %s" % [closed_layer, closing])
	_quiet(world)


# Par 3 with a point sending at turns 1, 2 and 3: turn 1's wave arrives; at the end of turn 2 the
# darkness step comes first, arrives, and the point sends nothing again.
func _test_reinforcements() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4, [], [[Vector2i(5, 3), [1, 2, 3]]])
	world.set_up([[Vector2i(0, 0)]], Vector2i(5, 0))
	world.darkness().first_release = 2
	world.register(ReinforcementCases.FixtureGroups.new({
		1: ["Bandit"], 2: ["Brute"], 3: ["Archer"],
	}))
	world.add_unit("p1", PLAYER, Vector2i(0, 3))
	var start: int = world.session.engine.fact_log.size()
	world.session.open_battle()
	world.end_turns(3)
	var point: String = world.state().map.points[0].id
	var lines: Array[String] = []
	for line: String in world.lines([
		ADVANCED, CombatFact.Kind.REINFORCEMENT_ARRIVED, CombatFact.Kind.UNIT_SPAWNED,
	], start):
		# Releases only, not the tiles deepened.
		if not line.contains("DARKNESS_ADVANCED") or line.contains("flags"):
			lines.append(line)
	var spawned: String = ""
	for line: String in lines:
		if line.contains("UNIT_SPAWNED"):
			spawned = line
	_same_lines("reinforcements: none after arrival", lines, [
		spawned,
		"t1 REINFORCEMENT_ARRIVED %s amount 1 tile (5, 3)" % [point],
		"t2 DARKNESS_ADVANCED flags 0x6 key 0",
	])
	_ok("reinforcements: the spawn was turn 1's", spawned.begins_with("t1 UNIT_SPAWNED"), spawned)
	_ok("reinforcements: the point has nothing left to send",
			Reinforcements.waves_left(world.state(), 0) == 0)
	_quiet(world)


# Before arrival a Support healer heals and a Hold Crossbowman shoots from its tile; the step that
# releases the first wave turns both Aggressive on the nearest foe.
func _test_ai_turns_aggressive() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	var world: AiWorld = AiWorld.new(catalog, PLAIN_8X8)
	world.add_enemy("h1", "loadout_hedge_healer", Vector2i(7, 7))
	world.add_enemy("b1", "loadout_brute", Vector2i(6, 7))
	world.add_player("p1", Vector2i(3, 0))
	world.wound("b1", 10)
	var state: CombatState = world.state()
	var source: DarknessState.Source = DarknessState.Source.new()
	source.tiles = [Vector2i(0, 7)]
	state.map.darkness.sources = [source]
	state.map.darkness.drain = Vector2i(7, 0)
	state.map.darkness.first_release = 1
	state.turn = 1
	var before: EnemyPlan = world.decide("h1")
	world.engine().begin_step()
	Darkness.advance(world.engine(), state)
	world.engine().drain()
	var after: EnemyPlan = world.decide("h1")
	_ok("AI: before arrival the healer heals", before.kind == EnemyPlan.Kind.STAFF)
	_ok("AI: the first release turns it Aggressive on the nearest foe", (
			state.map.has_darkness_arrived
			and after.behavior == EnemyClassDefinition.Behavior.AGGRESSIVE
			and after.target_rule_id == ContentIds.TARGET_NEAREST_FOE
	), "kind %d behavior %d rule %s" % [after.kind, after.behavior, after.target_rule_id])


# The intents preview crosses the player Phase End on a stand-in session sharing the real hooks
# (the darkness step among them): nothing reaches the real map. A step run on a sandbox changes
# the sandbox only.
func _test_stand_in() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.load_tree(LoadoutCases.TREE)
	var world: AiWorld = AiWorld.new(catalog, PLAIN_8X8)
	world.add_enemy("b1", "loadout_brute", Vector2i(6, 7))
	world.add_player("p1", Vector2i(0, 7))
	var session: CombatSession = world.session
	var state: CombatState = session.state
	var source: DarknessState.Source = DarknessState.Source.new()
	source.tiles = [Vector2i(0, 7)]
	state.map.darkness.sources = [source]
	state.map.darkness.drain = Vector2i(7, 0)
	state.map.darkness.first_release = 1
	Darkness.register(session)
	EnemyAI.register(session, catalog)
	Intents.register(session, catalog)
	session.open_battle()
	world.engine().begin_step()
	Darkness.advance(world.engine(), state)
	world.engine().drain()
	var real: String = DarknessWorld.describe_state(state)
	var facts: int = world.engine().fact_log.size()
	var intents: Intents = Intents.compute(session, catalog)
	_ok("stand-in: the intents preview ran", intents != null and not intents.enemies.is_empty())
	_ok("stand-in: the preview changes nothing on the real session", (
			DarknessWorld.describe_state(state) == real
			and world.engine().fact_log.size() == facts
	), DarknessWorld.describe_state(state))

	var sandbox: Sandbox = Sandbox.new(world.engine(), ForecastRolls.new())
	var copy: CombatState = sandbox.engine.state as CombatState
	copy.turn = 3
	sandbox.engine.begin_step()
	Darkness.advance(sandbox.engine, copy)
	sandbox.engine.drain()
	var sandbox_facts: int = 0
	for fact: CombatFact in sandbox.engine.fact_log:
		if fact.kind == ADVANCED:
			sandbox_facts += 1
	_ok("stand-in: a sandbox step deepens the sandbox", (
			copy.map.darkness.waves.size() == 2 and sandbox_facts > 0
	), DarknessWorld.describe_state(copy))
	_ok("stand-in: and leaves the real session as it was", (
			DarknessWorld.describe_state(state) == real
			and world.engine().fact_log.size() == facts
	), DarknessWorld.describe_state(state))


# The darkness step on M1 (10 × 8): its candidates and drain as setup finds them, the first
# release at the end of turn 4 (par 5), TIMED_TURNS steps per run. Timed with one active source
# (a standard map) and with both (as a key map would), on fresh states each run.
func _test_m1_timing() -> void:
	var definition: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	var layout: MapLayout = MapLoader.load_layout(definition) if definition != null else null
	if layout == null:
		_ok("m1 step: the map loads", false)
		return
	var candidates: Array[DarknessState.Source] = DarknessSetup.candidates(layout)
	_ok("m1 step: two candidates", candidates.size() == 2, str(candidates.size()))
	if candidates.size() < 2:
		return
	for active: int in [1, 2]:
		var sources: Array[DarknessState.Source] = candidates.slice(0, active)
		var drain: Vector2i = DarknessSetup.drain_for(definition, layout, sources, RngStream.new(1))
		var samples: Array[int] = []
		var flooded: int = 0
		var facts: int = 0
		for i: int in TIMED_RUNS:
			var session: CombatSession = CombatSession.new(
					0,
					PackedInt32Array([0]),
					MapGrid.new(layout),
					ForcedRolls.new(PackedInt32Array()),
					InstanceIdAllocator.new()
			)
			MapObjects.place(session)
			var darkness: DarknessState = session.state.map.darkness
			for source: DarknessState.Source in sources:
				darkness.sources.append(source.copy())
			darkness.drain = drain
			darkness.first_release = definition.turn_par - 1
			for turn: int in range(1, TIMED_TURNS + 1):
				session.state.turn = turn
				var started: int = Time.get_ticks_usec()
				session.engine.begin_step()
				Darkness.advance(session.engine, session.state)
				session.engine.drain()
				samples.append(Time.get_ticks_usec() - started)
			flooded = darkness.layers.size()
			facts = session.engine.fact_log.size()
		samples.sort()
		var median: int = samples[floori(samples.size() / 2.0)]
		var p95: int = samples[mini(samples.size() - 1, floori(samples.size() * 0.95))]
		var longest: int = samples[samples.size() - 1]
		print("NOTE  m1 darkness step, %d active source(s), %d turns x %d runs (%d facts, %d"
				% [active, TIMED_TURNS, TIMED_RUNS, facts, flooded]
				+ " tiles flooded by turn %d): median %d us, p95 %d us, max %d us"
				% [TIMED_TURNS, median, p95, longest])


# The lever pull as p1's action, then the step's facts are in the log.
func _pull(world: DarknessWorld, pull: UnitTurnCommand, problems: PackedStringArray) -> void:
	var batch: CombatSession.FactBatch = world.send(pull)
	if batch == null or batch.is_rejected():
		problems.append("t%d: %s" % [
			world.state().turn, "no batch" if batch == null else batch.rejected_reason,
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
