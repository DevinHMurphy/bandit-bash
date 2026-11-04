# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     setup_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## The setup cases for tests/darkness/run_all.gd: [DarknessSetup]'s candidates, the active pick by
## combat type, the drain per objective with Rout's tie from the stream, maps with no darkness, the
## draw order on the shared stream, and battles on the M1 map through [CampaignSession]: the same
## seed and a restart from Begin give the same darkness, and Short Wick moves the first release.
## Reports each case through the check callable it is given.
##
## Fixture maps are plain rows built here; the battles use the loadout fixture tree with no packs,
## so no enemy is drawn, and an empty army.

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const TREE: String = "res://tests/content/fixtures/loadout/"
const RUN_SEED: int = 4242
const FLOOR: int = 2
const NODE: int = 5

const ROUT: CombatMapDefinition.Objective = CombatMapDefinition.Objective.ROUT
const STANDARD: CombatMapDefinition.CombatType = CombatMapDefinition.CombatType.STANDARD
const SOURCE: MapLayout.MarkerKind = MapLayout.MarkerKind.DARKNESS_SOURCE

# M1's candidates (maps/standard/m1_greybox.tscn) and the tiles farthest from each, row-major, by
# walking distance over its floodable tiles, worked by hand from the map (only the walls at
# (8..9, 6..7) block): from the west, three tie at 11 steps; from the south, (9, 0) at 13.
const M1_WEST: String = "(0, 2) (0, 3)"
const M1_SOUTH: String = "(2, 7) (3, 7)"
const M1_FARTHEST: Dictionary[String, Array] = {
	M1_WEST: [Vector2i(9, 0), Vector2i(9, 5), Vector2i(7, 7)],
	M1_SOUTH: [Vector2i(9, 0)],
}

# Seeds enough to see both outcomes of a two-way draw.
const SEEDS: int = 16

var _check: Callable = Callable()
var _terrains: Dictionary[String, MapLayout.Terrain] = {}
var _m1: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_m1 = load(M1_DEFINITION) as CombatMapDefinition


## Runs every case.
func run() -> void:
	_test_candidates()
	_test_active_count()
	_test_same_seed()
	_test_rout_drain()
	_test_rout_tie()
	_test_objective_drains()
	_test_no_darkness()
	_test_draw_order()
	_test_copy_keeps_release()
	if _m1 == null:
		_check.call("setup: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_m1_candidates()
	_test_m1_battle()
	_test_restart_from_begin()
	_test_short_wick()
	_test_battle_without_darkness()


func _test_candidates() -> void:
	var layout: MapLayout = _layout(["plain plain plain plain plain plain plain", "plain"], [
		[Vector2i(3, 0), 1], [Vector2i(0, 1), 0], [Vector2i(5, 0), -1], [Vector2i(6, 0), -1],
		[Vector2i(4, 0), 1], [Vector2i(0, 1), 0],
	])
	_same(
			"candidates: by group, a marker in no group alone, in layout order",
			_describe_candidates(DarknessSetup.candidates(layout)),
			"(3, 0) (4, 0); (5, 0); (6, 0); (0, 1)"
	)


func _test_active_count() -> void:
	var layout: MapLayout = _three_candidates()
	var counts: PackedStringArray = []
	for combat_type: CombatMapDefinition.CombatType in CombatMapDefinition.CombatType.values():
		var drawn: Dictionary = _draw(_definition(ROUT, combat_type), layout, RUN_SEED)
		counts.append(str((drawn.get(DarknessSetup.SOURCES_KEY, []) as Array).size()))
	_same("active: standard 1, key 2, boss 2", " ".join(counts), "1 2 2")

	var two: Dictionary = _draw(_definition(ROUT, CombatMapDefinition.CombatType.KEY), (
			_layout(["plain plain plain"], [[Vector2i(0, 0), -1], [Vector2i(2, 0), -1]])
	), RUN_SEED)
	_same(
			"active: two from two candidates, in candidate order",
			JSON.stringify(two.get(DarknessSetup.SOURCES_KEY, [])),
			"[[[0,0]],[[2,0]]]"
	)


func _test_same_seed() -> void:
	var layout: MapLayout = _three_candidates()
	var key_map: CombatMapDefinition = _definition(ROUT, CombatMapDefinition.CombatType.KEY)
	var first: String = JSON.stringify(_draw(key_map, layout, RUN_SEED))
	_same(
			"same seed: the same sources and drain twice",
			JSON.stringify(_draw(key_map, layout, RUN_SEED)),
			first
	)
	var picks: Dictionary[String, bool] = {}
	for run_seed: int in range(1, SEEDS + 1):
		var drawn: Dictionary = _draw(_definition(), layout, run_seed)
		picks[JSON.stringify(drawn.get(DarknessSetup.SOURCES_KEY, []))] = true
	_check.call("same seed: across seeds every candidate is picked", picks.size() == 3, str(picks))


# Walking distance, not grid distance: the wall sends the darkness the long way round, so the
# farthest tile is (0, 2), 8 steps away, where grid distance would pick (3, 2).
func _test_rout_drain() -> void:
	var layout: MapLayout = _layout(
			["plain plain plain plain", "wall wall wall plain", "plain plain plain plain"],
			[[Vector2i(0, 0), -1]]
	)
	_same(
			"rout: the floodable tile farthest by walking distance",
			_drain_of(_draw(_definition(), layout, RUN_SEED)),
			str(Vector2i(0, 2))
	)
	var door: MapLayout = _layout(
			["plain plain plain plain", "wall wall wall plain", "plain plain plain plain"],
			[[Vector2i(0, 0), -1]],
			[[Vector2i(3, 1), MapLayout.ObjectKind.DOOR]]
	)
	_same(
			"rout: a closed door blocks the walk, so its far side is never the drain",
			_drain_of(_draw(_definition(), door, RUN_SEED)),
			str(Vector2i(3, 0))
	)


# One candidate, so the pick draws nothing and the tie is the stream's first draw.
func _test_rout_tie() -> void:
	var layout: MapLayout = _layout(["plain plain plain plain plain"], [[Vector2i(2, 0), -1]])
	var ties: Array[Vector2i] = [Vector2i(0, 0), Vector2i(4, 0)]
	var outcomes: Dictionary[String, bool] = {}
	var wrong: PackedStringArray = []
	for run_seed: int in range(1, SEEDS + 1):
		var drain: String = _drain_of(_draw(_definition(), layout, run_seed))
		var expected: String = str(ties[RngStream.new(run_seed).pick_index(ties.size())])
		outcomes[drain] = true
		if drain != expected:
			wrong.append("seed %d: %s, not %s" % [run_seed, drain, expected])
	_check.call("rout tie: drawn from the stream", wrong.is_empty(), "; ".join(wrong))
	_check.call("rout tie: across seeds both ends drain", outcomes.size() == 2, str(outcomes))


func _test_objective_drains() -> void:
	var layout: MapLayout = _three_candidates()
	layout.add_marker(MapLayout.MarkerKind.LEADER_SLOT, Vector2i(5, 2))
	layout.add_marker(MapLayout.MarkerKind.LEADER_SLOT, Vector2i(6, 3))
	layout.add_marker(MapLayout.MarkerKind.SEIZE, Vector2i(4, 1))
	layout.index_markers()
	var drains: PackedStringArray = []
	for objective: CombatMapDefinition.Objective in [
		CombatMapDefinition.Objective.DEFEAT_LEADER,
		CombatMapDefinition.Objective.DEFEAT_BOSS,
		CombatMapDefinition.Objective.SEIZE,
	]:
		drains.append(_drain_of(_draw(_definition(objective), layout, RUN_SEED)))
	_same(
			"drain: the first leader slot (leader, boss), then the seize tile",
			" ".join(drains),
			"(5, 2) (5, 2) (4, 1)"
	)
	var bare: Dictionary = _draw(
			_definition(CombatMapDefinition.Objective.SEIZE), _three_candidates(), RUN_SEED
	)
	_check.call(
			"drain: none without the objective's tile, sources still drawn",
			not bare.has(DarknessSetup.DRAIN_KEY) and bare.has(DarknessSetup.SOURCES_KEY),
			JSON.stringify(bare)
	)


func _test_no_darkness() -> void:
	var layout: MapLayout = _three_candidates()
	var none: PackedStringArray = []
	var survive: CombatMapDefinition = _definition(CombatMapDefinition.Objective.SURVIVE)
	var defend: CombatMapDefinition = _definition(CombatMapDefinition.Objective.DEFEND)
	var no_par: CombatMapDefinition = _definition()
	no_par.turn_par = 0
	for definition: CombatMapDefinition in [survive, defend, no_par]:
		var results: CombatEncounter.EncounterSetup = _results(definition, layout)
		DarknessSetup.draw(_context(results, RngStream.new(RUN_SEED)))
		none.append(str(results.shared.has(DarknessSetup.DARKNESS_KEY)))
	_same("none: Survive, Defend and a map without par draw nothing", " ".join(none), (
			"false false false"
	))
	var bare: CombatEncounter.EncounterSetup = _results(_definition(), _layout(["plain"], []))
	DarknessSetup.draw(_context(bare, RngStream.new(RUN_SEED)))
	_check.call(
			"none: a map with no candidate draws nothing",
			not bare.shared.has(DarknessSetup.DARKNESS_KEY)
	)


# Step 3 now draws before step 4 on the shared stream: step 4's first draw follows the pick.
func _test_draw_order() -> void:
	var trace: Array[int] = []
	var battle: CombatEncounter = CombatEncounter.new(
			FLOOR, NODE, PackedInt32Array([0]), InstanceIdAllocator.new()
	)
	battle.add_setup_step(CombatEncounter.SetupStep.DARKNESS_SOURCES, DarknessSetup.draw)
	battle.add_setup_step(
			CombatEncounter.SetupStep.ENEMY_SLOTS,
			func(ctx: CombatEncounter.SetupContext) -> void:
				trace.append(ctx.stream.randi_range(0, 1 << 30))
	)
	var pool: Array[CombatMapDefinition] = [_m1]
	battle.run_setup(pool, CombatEncounter.SetupStreams.new(RUN_SEED, FLOOR, NODE))
	var shared: RngStream = RngStream.new(
			RngKey.derive_seed(RUN_SEED, RngKey.RngPurpose.ENCOUNTER_SETUP, FLOOR, NODE, -1, -1)
	)
	# M1 is a standard Rout map with two candidates: one pick, then the west one's three-way tie
	# (M1_FARTHEST); the south one's far tile is unique, so it draws no tie.
	if shared.pick_index(2) == 0:
		shared.pick_index(M1_FARTHEST[M1_WEST].size())
	_check.call(
			"order: step 4's draws follow step 3's pick on the shared stream",
			trace.size() == 1 and trace[0] == shared.randi_range(0, 1 << 30),
			str(trace)
	)


func _test_copy_keeps_release() -> void:
	var darkness: DarknessState = DarknessState.new()
	_check.call(
			"copy: no release before setup", darkness.first_release == DarknessState.NO_RELEASE
	)
	darkness.first_release = 4
	_check.call("copy: a sandbox copy keeps the first release", darkness.copy().first_release == 4)


func _test_m1_candidates() -> void:
	var layout: MapLayout = MapLoader.load_layout(_m1)
	_same(
			"M1: two candidates from marker nodes, by group",
			_describe_candidates(DarknessSetup.candidates(layout)),
			"%s; %s" % [M1_WEST, M1_SOUTH]
	)


func _test_m1_battle() -> void:
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(_m1))
	if battle == null:
		_check.call("M1 battle: begins", false)
		return
	var darkness: DarknessState = battle.get_session(0).state.map.darkness
	var source: String = (
			_describe_candidates(darkness.sources) if darkness.sources.size() == 1 else ""
	)
	_check.call("M1 battle: one active source, one of the candidates", (
			M1_FARTHEST.has(source)
	), _describe_darkness(darkness))
	_check.call("M1 battle: the drain is a tile farthest from it", (
			M1_FARTHEST.has(source) and M1_FARTHEST[source].has(darkness.drain)
	), _describe_darkness(darkness))
	_check.call("M1 battle: the first wave is released at the end of turn 4 (par 5)", (
			darkness.first_release == 4
	), str(darkness.first_release))
	_check.call("M1 battle: no wave released and every tile dry", (
			darkness.waves.is_empty() and darkness.layers.is_empty() and not darkness.has_arrived()
	))
	run.close()

	var both: Dictionary[String, bool] = {}
	for run_seed: int in range(1, SEEDS + 1):
		var other: CampaignSession = _run(run_seed)
		var on_m1: CombatEncounter = other.begin_battle(_request(_m1))
		if on_m1 != null:
			var placed: DarknessState = on_m1.get_session(0).state.map.darkness
			both[_describe_candidates(placed.sources)] = true
		other.close()
	_check.call("M1 battle: across seeds both candidates are picked", both.size() == 2, str(both))


func _test_restart_from_begin() -> void:
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(_m1))
	var first: String = _describe_darkness(battle.get_session(0).state.map.darkness)
	run.abandon_battle()
	var again: CombatEncounter = run.begin_battle(_request(_m1))
	_check.call("restart from Begin: the same sources, drain and release", (
			again != null and _describe_darkness(again.get_session(0).state.map.darkness) == first
	), first)
	run.close()
	var fresh: CampaignSession = _run(RUN_SEED)
	var rebuilt: CombatEncounter = fresh.begin_battle(_request(_m1))
	_check.call("restart from Begin: a new run on the same seed picks them again", (
			rebuilt != null
			and _describe_darkness(rebuilt.get_session(0).state.map.darkness) == first
	), first)
	fresh.close()


# Short Wick (events.md): the darkness arrives one turn earlier on this player's maps.
func _test_short_wick() -> void:
	var run: CampaignSession = _run(RUN_SEED)
	var wick: EffectDefinition = EffectDefinition.new()
	wick.id = "test_short_wick"
	var earlier: ModifyValue = ModifyValue.new()
	earlier.key = CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET
	earlier.mode = Modifier.Mode.ADD
	earlier.value = -1.0
	wick.operations = [earlier]
	run.add_carrier(EffectInstance.new(
			run.ids.next_effect_id(),
			wick,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.CURSE
	))
	var battle: CombatEncounter = run.begin_battle(_request(_m1))
	var session: CombatSession = battle.get_session(0) if battle != null else null
	_check.call("Short Wick: the first release moves a turn earlier, to turn 3", (
			session != null
			and DarknessSetup.arrival_offset(session) == -1
			and session.state.map.darkness.first_release == 3
	), "" if session == null else str(session.state.map.darkness.first_release))
	run.close()


func _test_battle_without_darkness() -> void:
	var survive: CombatMapDefinition = _m1.duplicate() as CombatMapDefinition
	survive.id = "m1_survive"
	survive.objective = CombatMapDefinition.Objective.SURVIVE
	survive.survive_turns = 5
	var no_par: CombatMapDefinition = _m1.duplicate() as CombatMapDefinition
	no_par.id = "m1_no_par"
	no_par.turn_par = 0
	var empty: PackedStringArray = []
	for definition: CombatMapDefinition in [survive, no_par]:
		var run: CampaignSession = _run(RUN_SEED)
		var battle: CombatEncounter = run.begin_battle(_request(definition))
		var darkness: DarknessState = (
				null if battle == null else battle.get_session(0).state.map.darkness
		)
		empty.append(str(
				darkness != null
				and darkness.sources.is_empty()
				and darkness.drain == CombatFact.NO_TILE
				and darkness.first_release == DarknessState.NO_RELEASE
		))
		run.close()
	_same("none: a Survive battle and one without par have no darkness", " ".join(empty), (
			"true true"
	))


# Three single-tile candidates on a 7 × 4 plain map: (0, 0), (0, 3) and (6, 3).
func _three_candidates() -> MapLayout:
	var row: String = "plain plain plain plain plain plain plain"
	return _layout([row, row, row, row], [
		[Vector2i(0, 0), -1], [Vector2i(0, 3), -1], [Vector2i(6, 3), -1],
	])


# A layout from rows of terrain ids, with darkness source markers [tile, group id] and object
# spots [tile, MapLayout.ObjectKind], indexed.
func _layout(rows: Array[String], sources: Array, spots: Array = []) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "darkness_setup"
	for y: int in rows.size():
		var terrain_ids: PackedStringArray = rows[y].split(" ", false)
		for x: int in terrain_ids.size():
			layout.set_terrain(Vector2i(x, y), _terrain(terrain_ids[x]))
	# Untyped: each entry is an array literal.
	for entry: Variant in sources:
		var source: Array = entry
		var marker: MapLayout.Marker = layout.add_marker(SOURCE, source[0] as Vector2i)
		marker.group_id = source[1]
	for entry: Variant in spots:
		var spot: Array = entry
		layout.add_marker(MapLayout.MarkerKind.OBJECT_SPOT, spot[0] as Vector2i, spot[1] as int)
	layout.index_markers()
	return layout


func _terrain(id: String) -> MapLayout.Terrain:
	if not _terrains.has(id):
		_terrains[id] = MapLayout.Terrain.from_definition(MapLoader.load_terrain(id))
	return _terrains[id]


func _definition(
		objective: CombatMapDefinition.Objective = ROUT,
		combat_type: CombatMapDefinition.CombatType = STANDARD
) -> CombatMapDefinition:
	var definition: CombatMapDefinition = CombatMapDefinition.new()
	definition.id = "darkness_setup"
	definition.objective = objective
	definition.combat_type = combat_type
	definition.turn_par = 5
	return definition


func _results(
		definition: CombatMapDefinition, layout: MapLayout
) -> CombatEncounter.EncounterSetup:
	var results: CombatEncounter.EncounterSetup = CombatEncounter.EncounterSetup.new()
	results.map = definition
	results.layout = layout
	return results


func _context(
		results: CombatEncounter.EncounterSetup, stream: RngStream
) -> CombatEncounter.SetupContext:
	var ctx: CombatEncounter.SetupContext = CombatEncounter.SetupContext.new(
			results, -1, null, stream, null
	)
	ctx.step = CombatEncounter.SetupStep.DARKNESS_SOURCES
	return ctx


# Step 3 on layout with a fresh stream seeded run_seed. Returns what it wrote; empty for nothing.
func _draw(definition: CombatMapDefinition, layout: MapLayout, run_seed: int) -> Dictionary:
	var results: CombatEncounter.EncounterSetup = _results(definition, layout)
	DarknessSetup.draw(_context(results, RngStream.new(run_seed)))
	var drawn: Variant = results.shared.get(DarknessSetup.DARKNESS_KEY, {})
	return drawn if drawn is Dictionary else {}


# The drain step 3 wrote, as a Vector2i in text; "none" when it wrote none.
func _drain_of(drawn: Dictionary) -> String:
	var drain: Variant = drawn.get(DarknessSetup.DRAIN_KEY, null)
	if not drain is Array:
		return "none"
	var parts: Array = drain
	return str(Vector2i(parts[0] as int, parts[1] as int))


func _run(run_seed: int) -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0]))


# A battle on map with the loadout fixture tree (no packs, so no enemy) and no army.
func _request(map: CombatMapDefinition) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	var index: EffectCatalog.Index = EffectCatalog.load_tree(TREE)
	index.finish()
	request.catalog = index
	return request


# Each source's tiles, joined by spaces; sources joined by "; ".
static func _describe_candidates(found: Array[DarknessState.Source]) -> String:
	var parts: PackedStringArray = []
	for source: DarknessState.Source in found:
		var tiles: PackedStringArray = []
		for tile: Vector2i in source.tiles:
			tiles.append(str(tile))
		parts.append(" ".join(tiles))
	return "; ".join(parts)


static func _describe_darkness(darkness: DarknessState) -> String:
	return "sources %s drain %s release %d" % [
		_describe_candidates(darkness.sources), darkness.drain, darkness.first_release,
	]


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])
