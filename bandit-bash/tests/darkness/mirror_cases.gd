# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     mirror_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The darkness on client mirrors, for tests/darkness/run_all.gd: after every batch of real turn
## loops, a mirror loaded from the host's snapshot through JSON holds the host's waves (reach and
## tiles entered), layers and contacts, the same [method Darkness.next_deepening] and the same
## state hash. Maps: a corridor's releases and creeps (a golden log of
## [constant CombatFact.Kind.DARKNESS_WAVE_SPREAD]), a creep that enters no tile, a lit Brazier's
## capped entries, an erosion break and a door's recalculations, two sources' waves, and a battle
## resumed from its saved darkness that creeps on. Solo is unchanged but for the new fact: the
## resumed host plays on as an unbroken one, and the HUD log reads the same without the fact.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "darkness"

const DarknessWorld = preload("res://tests/darkness/darkness_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ADVANCED: CombatFact.Kind = CombatFact.Kind.DARKNESS_ADVANCED
const SPREAD: CombatFact.Kind = CombatFact.Kind.DARKNESS_WAVE_SPREAD
const CHANGED: CombatFact.Kind = CombatFact.Kind.OBJECT_STATE_CHANGED
const BRAZIER: MapLayout.ObjectKind = MapLayout.ObjectKind.BRAZIER
const DEBRIS: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS
const DOOR: MapLayout.ObjectKind = MapLayout.ObjectKind.DOOR
const LEVER: MapLayout.ObjectKind = MapLayout.ObjectKind.LEVER

const CORRIDOR_3: Array[String] = ["plain plain plain"]
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

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_golden()
	_test_creep_without_tiles()
	_test_capped_entries()
	_test_erosion()
	_test_door()
	_test_two_sources()
	_test_resume()
	_test_event_log_unchanged()


# Par 3 on the corridor: each release's wave enters its source at reach 0, and each creep's
# entries follow that step's deepened tiles, wave by wave, each with the wave's reach.
func _test_golden() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7)
	world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
	world.darkness().first_release = 2
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(6, 0))
	var mirror: Mirror = Mirror.new(world.session)
	world.session.open_battle()
	var problems: PackedStringArray = []
	_play(world, mirror, 4, problems)
	_same_lines("golden: the wave facts after the deepened tiles, turns 1-4",
			world.lines([ADVANCED, SPREAD]), [
				"t2 DARKNESS_ADVANCED flags 0x6 key 0",
				"t2 DARKNESS_ADVANCED amount 1 tile (0, 0) key 0",
				"t2 DARKNESS_WAVE_SPREAD wave 0 tile (0, 0)",
				"t3 DARKNESS_ADVANCED amount 1 tile (1, 0) key 0",
				"t3 DARKNESS_ADVANCED amount 1 tile (2, 0) key 0",
				"t3 DARKNESS_WAVE_SPREAD wave 0 amount 2 tile (1, 0)",
				"t3 DARKNESS_WAVE_SPREAD wave 0 amount 2 tile (2, 0)",
				"t4 DARKNESS_ADVANCED amount 1 tile (3, 0) key 0",
				"t4 DARKNESS_ADVANCED amount 1 tile (4, 0) key 0",
				"t4 DARKNESS_WAVE_SPREAD wave 0 amount 4 tile (3, 0)",
				"t4 DARKNESS_WAVE_SPREAD wave 0 amount 4 tile (4, 0)",
				"t4 DARKNESS_ADVANCED flags 0x2 key 0",
				"t4 DARKNESS_ADVANCED amount 2 tile (0, 0) key 0",
				"t4 DARKNESS_WAVE_SPREAD wave 1 tile (0, 0)",
			])
	_ok("golden: the mirror matches after every batch", problems.is_empty(), _join(problems))
	_quiet(world)


# A three-tile corridor is all entered by turn 2's creep: turn 3's and 4's creeps of wave 0 enter
# nothing, so each records its reach alone, with no tile; the mirror's reach still follows.
func _test_creep_without_tiles() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_3)
	world.set_up([[Vector2i(0, 0)]], Vector2i(2, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(2, 0))
	var mirror: Mirror = Mirror.new(world.session)
	world.session.open_battle()
	var problems: PackedStringArray = []
	_play(world, mirror, 4, problems)
	_same_lines("no new tile: a creep that enters nothing records the reach alone",
			world.lines([SPREAD]), [
				"t1 DARKNESS_WAVE_SPREAD wave 0 tile (0, 0)",
				"t2 DARKNESS_WAVE_SPREAD wave 0 amount 2 tile (1, 0)",
				"t2 DARKNESS_WAVE_SPREAD wave 0 amount 2 tile (2, 0)",
				"t3 DARKNESS_WAVE_SPREAD wave 0 amount 4",
				"t3 DARKNESS_WAVE_SPREAD wave 1 tile (0, 0)",
				"t4 DARKNESS_WAVE_SPREAD wave 0 amount 6",
				"t4 DARKNESS_WAVE_SPREAD wave 1 amount 2 tile (1, 0)",
				"t4 DARKNESS_WAVE_SPREAD wave 1 amount 2 tile (2, 0)",
			])
	_ok("no new tile: the mirror matches after every batch, reaches 6 and 2", (
			problems.is_empty() and _reaches(mirror.session.state) == "6 2"
	), _join(problems))
	_quiet(world)


# A lit Brazier at the corridor's east end holds tiles 4-6 at Dusk: wave 1 enters them on turns 5
# and 6 without deepening them, so no DARKNESS_ADVANCED names them, and the mirror still has them
# entered.
func _test_capped_entries() -> void:
	var world: DarknessWorld = DarknessWorld.new(CORRIDOR_7, [[Vector2i(6, 0), BRAZIER]])
	world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
	world.set_lit(Vector2i(6, 0), true)
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 0), 200)
	var mirror: Mirror = Mirror.new(world.session)
	world.session.open_battle()
	var problems: PackedStringArray = []
	_play(world, mirror, 6, problems)
	var capped: Vector2i = Vector2i(4, 0)
	var host_waves: Array[DarknessState.Wave] = world.darkness().waves
	var mirror_waves: Array[DarknessState.Wave] = mirror.session.state.map.darkness.waves
	_ok("capped: wave 1 entered the held tiles without deepening them", (
			host_waves.size() >= 2
			and host_waves[1].entered.has(capped)
			and world.darkness().layer_at(capped) == WhileLayerCondition.Layer.DUSK
	), DarknessWorld.describe_state(world.state()))
	_ok("capped: the mirror has them entered and matches after every batch", (
			problems.is_empty()
			and mirror_waves.size() >= 2
			and mirror_waves[1].entered.has(capped)
	), _join(problems))
	_quiet(world)


# The side room's erosion map (step_cases.gd), turns 1-6: the debris breaks at turn 4's third
# contact, and the recalculation lets wave 0 into the lane; the mirror follows every entry.
func _test_erosion() -> void:
	var world: DarknessWorld = DarknessWorld.new(SIDE_ROOM, [[Vector2i(2, 1), DEBRIS]])
	world.set_up([[Vector2i(0, 0)]], Vector2i(4, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 2))
	var mirror: Mirror = Mirror.new(world.session)
	world.session.open_battle()
	var problems: PackedStringArray = []
	_play(world, mirror, 6, problems)
	var lane_entry: String = "t4 DARKNESS_WAVE_SPREAD wave 0 amount 6 tile (2, 1)"
	var spread: Array[String] = world.lines([SPREAD])
	_ok("erosion: the break's recalculation records wave 0 entering the lane",
			spread.has(lane_entry), _join(PackedStringArray(spread)))
	_ok("erosion: the mirror matches after every batch", problems.is_empty(), _join(problems))
	_quiet(world)


# A lever opens and closes the door at (3, 0) in player phases (step_cases.gd's door map): each
# pull's recalculation goes out in the pull's own batch, and the mirror matches after each batch.
func _test_door() -> void:
	var world: DarknessWorld = DarknessWorld.new(
			CORRIDOR_7, [[Vector2i(3, 0), DOOR], [Vector2i(1, 0), LEVER]]
	)
	var lever: MapState.ObjectState = world.object_at(Vector2i(1, 0))
	world.object_at(Vector2i(3, 0)).group_id = 0
	lever.group_id = 0
	world.set_up([[Vector2i(0, 0)]], Vector2i(6, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(1, 0))
	var mirror: Mirror = Mirror.new(world.session)
	world.session.open_battle()
	var pull: UnitTurnCommand = UnitTurnCommand.new(
			0, "p1", UnitTurnCommand.Action.USE_OBJECT, lever.id
	)
	var problems: PackedStringArray = []
	var in_pulls: int = _pull(world, mirror, pull, problems)
	_play(world, mirror, 3, problems)
	in_pulls += _pull(world, mirror, pull, problems)
	_play(world, mirror, 1, problems)
	in_pulls += _pull(world, mirror, pull, problems)
	_play(world, mirror, 1, problems)
	_ok("door: a pull's recalculation records its entries in the pull's batch", in_pulls > 0)
	_ok("door: the mirror matches after every pull and turn", problems.is_empty(),
			_join(problems))
	_quiet(world)


# Two sources release together: waves 0 and 1 at turn 1, 2 and 3 at turn 3, 4 and 5 at turn 5,
# each entering its own source's tiles; the mirror keeps every wave apart.
func _test_two_sources() -> void:
	var world: DarknessWorld = DarknessWorld.new(PLAIN_6X4)
	world.set_up([[Vector2i(0, 0)], [Vector2i(0, 3)]], Vector2i(5, 1))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(5, 1), 200)
	var mirror: Mirror = Mirror.new(world.session)
	world.session.open_battle()
	var problems: PackedStringArray = []
	_play(world, mirror, 6, problems)
	_ok("two sources: six waves, the mirror matching after every batch", (
			problems.is_empty()
			and world.darkness().waves.size() == 6
			and mirror.session.state.map.darkness.waves.size() == 6
	), _join(problems))
	_same("two sources: the mirror's reaches, oldest first", _reaches(mirror.session.state),
			"10 10 6 6 2 2")
	_quiet(world)


# The erosion map saved after turn 3 (snapshot and darkness section through JSON) and resumed on a
# rebuilt battle: a rejoining mirror follows its next three turns, and the resumed host plays them
# as the unbroken host does, fact for fact and state for state.
func _test_resume() -> void:
	var unbroken: DarknessWorld = _erosion_world()
	unbroken.session.open_battle()
	unbroken.end_turns(3)
	var saved_snapshot: String = JSON.stringify(unbroken.session.snapshot())
	var saved_darkness: Dictionary = JSON.parse_string(
			JSON.stringify(unbroken.darkness().capture())
	)
	saved_darkness.erase("first_release")
	var resume_from: int = unbroken.engine().fact_log.size()

	var resumed: DarknessWorld = _erosion_world()
	var loaded: Error = resumed.session.load_snapshot(
			JSON.parse_string(saved_snapshot) as Dictionary
	)
	# As DarknessSaveSection.load_into: the held darkness, with the rebuilt first release.
	saved_darkness["first_release"] = resumed.darkness().first_release
	var restored: DarknessState = DarknessState.new()
	var restored_ok: Error = restored.restore(saved_darkness)
	resumed.state().map.darkness = restored
	var mirror: Mirror = Mirror.new(resumed.session)

	var problems: PackedStringArray = []
	unbroken.end_turns(3)
	_play(resumed, mirror, 3, problems)
	var kinds: Array = [ADVANCED, SPREAD, CHANGED]
	var unbroken_lines: Array[String] = unbroken.lines(kinds, resume_from)
	var resumed_lines: Array[String] = resumed.lines(kinds)
	_ok("resume: loaded and restored", loaded == OK and restored_ok == OK, "%s, %s" % [
		error_string(loaded), error_string(restored_ok),
	])
	_ok("resume: the rejoined mirror matches after every batch", (
			problems.is_empty() and mirror.results.size() >= 3
	), _join(problems))
	_ok("resume: the resumed host plays on as the unbroken one", (
			resumed_lines == unbroken_lines
			and resumed_lines.size() > 0
			and DarknessWorld.describe_state(resumed.state())
			== DarknessWorld.describe_state(unbroken.state())
	), "\n      unbroken: %s\n      resumed:  %s" % [
		"\n        ".join(unbroken_lines), "\n        ".join(resumed_lines),
	])


# The HUD log of the erosion map's six turns reads the same with the wave facts as without them:
# they are silent, and none splits a run of deepened tiles into two spread lines.
func _test_event_log_unchanged() -> void:
	var world: DarknessWorld = _erosion_world()
	world.session.open_battle()
	world.end_turns(6)
	var with_spread: String = _transcript(world.session, false)
	var without: String = _transcript(world.session, true)
	_ok("event log: the same lines without the wave facts", (
			with_spread == without and with_spread.contains("The darkness spreads")
	), "\n      with:    %s\n      without: %s" % [with_spread, without])


# The side room's erosion map, set up and registered, with p1 in the side room.
func _erosion_world() -> DarknessWorld:
	var world: DarknessWorld = DarknessWorld.new(SIDE_ROOM, [[Vector2i(2, 1), DEBRIS]])
	world.set_up([[Vector2i(0, 0)]], Vector2i(4, 0))
	world.darkness().first_release = 1
	world.register()
	world.add_unit("p1", PLAYER, Vector2i(0, 2))
	return world


# Ends turns one at a time, comparing mirror with world after each.
func _play(
		world: DarknessWorld, mirror: Mirror, turns: int, problems: PackedStringArray
) -> void:
	for i: int in turns:
		world.end_turns(1)
		_compare(world, mirror, "t%d" % [world.state().turn - 1], problems)


# Sends pull, then compares mirror with world. Returns the DARKNESS_WAVE_SPREAD facts in its batch.
func _pull(
		world: DarknessWorld,
		mirror: Mirror,
		pull: UnitTurnCommand,
		problems: PackedStringArray
) -> int:
	var batch: CombatSession.FactBatch = world.send(pull)
	if batch == null or batch.is_rejected():
		problems.append("t%d pull: %s" % [
			world.state().turn, "no batch" if batch == null else batch.rejected_reason,
		])
	_compare(world, mirror, "t%d pull" % [world.state().turn], problems)
	var spread: int = 0
	if batch != null:
		for fact: CombatFact in batch.facts:
			if fact.kind == SPREAD:
				spread += 1
	return spread


# Applies the host's new batches to mirror, then adds a line to problems for each difference: an
# apply that failed, the next deepening, the darkness's state (waves, layers, contacts) or the hash.
func _compare(
		world: DarknessWorld, mirror: Mirror, label: String, problems: PackedStringArray
) -> void:
	var applied: int = mirror.results.size()
	mirror.catch_up()
	for i: int in range(applied, mirror.results.size()):
		if mirror.results[i] != OK:
			problems.append("%s: batch %d applied %s" % [label, i, error_string(mirror.results[i])])
	if mirror.loaded != OK:
		problems.append("%s: snapshot %s" % [label, error_string(mirror.loaded)])
	var host_next: String = _deepening(world.engine())
	var mirror_next: String = _deepening(mirror.session.engine)
	if host_next != mirror_next:
		problems.append("%s: next deepening host [%s], mirror [%s]" % [
			label, host_next, mirror_next,
		])
	var host_state: String = DarknessWorld.describe_state(world.state())
	var mirror_state: String = DarknessWorld.describe_state(mirror.session.state)
	if host_state != mirror_state:
		problems.append("%s: darkness host %s; mirror %s" % [label, host_state, mirror_state])
	if world.session.state_hash() != mirror.session.state_hash():
		problems.append("%s: state hashes differ" % [label])


# Darkness.next_deepening on engine as text, row-major.
static func _deepening(engine: EffectEngine) -> String:
	var tiles: Dictionary[Vector2i, int] = {}
	var next: Dictionary[Vector2i, WhileLayerCondition.Layer] = Darkness.next_deepening(engine)
	for tile: Vector2i in next:
		tiles[tile] = next[tile]
	return DarknessWorld.describe(tiles)


# Each wave's reach on state's map, oldest first, as "6 2".
static func _reaches(state: CombatState) -> String:
	var parts: PackedStringArray = []
	for wave: DarknessState.Wave in state.map.darkness.waves:
		parts.append(str(wave.reach))
	return " ".join(parts)


# The HUD log EventLogWriter writes for session's whole fact log, each entry's final text in entry
# order; without_spread leaves the DARKNESS_WAVE_SPREAD facts out.
static func _transcript(session: CombatSession, without_spread: bool) -> String:
	var writer: EventLogWriter = EventLogWriter.new(session)
	var texts: Dictionary[int, String] = {}
	for fact: CombatFact in session.engine.fact_log:
		if without_spread and fact.kind == SPREAD:
			continue
		for entry: EventLogWriter.Entry in writer.write(fact):
			texts[entry.id] = entry.text()
	var ids: Array[int] = []
	ids.assign(texts.keys())
	ids.sort()
	var lines: PackedStringArray = []
	for id: int in ids:
		lines.append(texts[id])
	return " | ".join(lines)


static func _join(problems: PackedStringArray) -> String:
	return "\n      ".join(problems)


func _quiet(world: DarknessWorld) -> void:
	var diagnostics: PackedStringArray = world.session.engine.diagnostics
	_ok("diagnostics: none", diagnostics.is_empty(), str(diagnostics))


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: String, expected: String) -> void:
	_check.call(case_name, actual == expected, "got \"%s\"" % [actual])


func _same_lines(case_name: String, actual: Array[String], expected: Array[String]) -> void:
	_check.call(case_name, actual == expected, "got\n      " + "\n      ".join(actual))


## A client's mirror of a host session, loaded from the host's snapshot through JSON, that applies
## each batch the host resolves, through JSON, at [method catch_up].
class Mirror:
	extends RefCounted

	## The mirror's session.
	var session: CombatSession = null
	## The snapshot load's result.
	var loaded: Error = OK
	## Each applied batch's result, in order.
	var results: Array[Error] = []

	var _pending: Array[CombatSession.FactBatch] = []

	func _init(host: CombatSession) -> void:
		# The host's grid, shared read-only as an encounter shares it.
		var grid: MapGrid = host.state.grid
		session = CombatSession.new(
				host.session_id,
				PackedInt32Array([0]),
				grid,
				ForcedRolls.new(PackedInt32Array()),
				InstanceIdAllocator.new()
		)
		loaded = session.load_snapshot(
				JSON.parse_string(JSON.stringify(host.snapshot())) as Dictionary
		)
		host.batch_resolved.connect(_on_host_batch_resolved)

	## Applies every batch the host resolved since the last call.
	func catch_up() -> void:
		for batch: CombatSession.FactBatch in _pending:
			var wire: Array = JSON.parse_string(JSON.stringify(batch.to_wire()))
			results.append(session.apply_batch(CombatSession.FactBatch.from_wire(wire)))
		_pending.clear()

	func _on_host_batch_resolved(batch: CombatSession.FactBatch) -> void:
		_pending.append(batch)
