# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     mini_boss_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## Mini-bosses on the real catalog (enemies and AI plan, EN8 row; enemy-packs.md, Key pool;
## enemy-roster.md, Mini-bosses): a run's order never repeats one before all four fought and the
## same seed gives the same order; on every key map the drawn mini-boss stands on the leader slot
## at its step's level +2 with a positive prefix, its escort on the enemy slots at the key level;
## the Hall is won when it falls. Each signature move fires as enemy-roster.md and P05's EN8
## answers word it, shown as a SIGNATURE intent the phase before (the Bloodhound's on its kill).
## Reports each case through the check callable it is given.
##
## @tutorial(Enemy packs): docs/design/enemy-packs.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/roster"

const AiWorld = preload("res://tests/enemies/ai_world.gd")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

## The key maps, each [code]res://maps/key/<id>.tres[/code].
const KEY_MAPS: Array[String] = ["hall", "gatehouse", "hilltop", "village"]

## The mini-bosses enemy-roster.md lists, in id order.
const MINI_BOSSES: Array[String] = ["bloodhound", "brigand_captain", "hex_matron", "iron_wall"]

const RUN_SEED: int = 8080
const SEEDS: int = 40
const NODE: int = 3
const FLOORS: Array[int] = [6, 12]
const BATTLE_FLOOR: int = 6

## High enough that no test unit falls to the enemies the cases field.
const STURDY: Dictionary = {
	CombatValue.Key.HP: 99.0,
	CombatValue.Key.DEF: 20.0,
	CombatValue.Key.RES: 20.0,
}

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_catalog_mini_bosses()
	_test_order_never_repeats()
	_test_key_map_draws()
	_test_run_draws()
	_test_hall_battle()
	_test_command()
	_test_fortify()
	_test_hex_storm()
	_test_blood_scent()
	_test_blood_scent_wait()
	_test_second_move_commands()


func _test_catalog_mini_bosses() -> void:
	var ids: PackedStringArray = EnemySetup.mini_boss_ids(_catalog)
	_check.call("catalog: the four mini-bosses, each named by a key pack", (
			ids == PackedStringArray(MINI_BOSSES)
	), str(ids))
	var standard: PackedStringArray = EnemySetup.standard_classes(_catalog)
	var mixed: PackedStringArray = []
	for boss_id: String in MINI_BOSSES:
		if standard.has(boss_id):
			mixed.append(boss_id)
	_check.call("catalog: no mini-boss is a standard class, so Hunted never adds one", (
			mixed.is_empty()
	), str(mixed))


# The first four key combats of a run field all four mini-bosses, for every seed; the next four
# again all four; the same seed gives the same order; seeds differ in order.
func _test_order_never_repeats() -> void:
	var repeats: PackedStringArray = []
	var orders: Dictionary[String, bool] = {}
	for run_seed: int in range(1, SEEDS + 1):
		var first: PackedStringArray = _order(run_seed, 0, 4)
		var second: PackedStringArray = _order(run_seed, 4, 8)
		orders[",".join(first)] = true
		if _sorted(first) != PackedStringArray(MINI_BOSSES):
			repeats.append("seed %d: %s" % [run_seed, first])
		if _sorted(second) != PackedStringArray(MINI_BOSSES):
			repeats.append("seed %d, second round: %s" % [run_seed, second])
	_check.call("order: a run's first four key combats field four different mini-bosses", (
			repeats.is_empty()
	), "; ".join(repeats.slice(0, 5)))
	var once: PackedStringArray = _order(RUN_SEED, 0, 4)
	var twice: PackedStringArray = _order(RUN_SEED, 0, 4)
	_check.call("order: the same seed gives the same mini-bosses twice", once == twice, (
			"%s / %s" % [once, twice]
	))
	_check.call("order: seeds give different orders", orders.size() > 1, str(orders.size()))


# Setup step 4 alone on every key map and step: the named mini-boss's own key pack, the mini-boss
# on the leader slot at step +2 with a positive prefix, the escort on the enemy slots at step +1.
func _test_key_map_draws() -> void:
	var wrong: PackedStringArray = []
	var checked: int = 0
	for map_id: String in KEY_MAPS:
		var map: CombatMapDefinition = _map(map_id)
		for floor_number: int in FLOORS:
			for boss_id: String in MINI_BOSSES:
				for run_seed: int in [RUN_SEED, RUN_SEED + 1]:
					var setup: CombatEncounter.EncounterSetup = _draw_only(
							map, floor_number, boss_id, run_seed
					)
					checked += 1
					var problem: String = _mini_boss_problem(setup, floor_number, boss_id)
					if not problem.is_empty():
						wrong.append("%s floor %d %s: %s" % [
							map_id, floor_number, boss_id, problem,
						])
	_check.call(
			"key map: the mini-boss stands on the leader slot at step level +2 with a positive "
			+ "prefix, its own key pack's escort on the enemy slots",
			checked > 0 and wrong.is_empty(),
			"; ".join(wrong.slice(0, 5))
	)
	var map: CombatMapDefinition = _map(KEY_MAPS[0])
	var first: String = _entries_text(_draw_only(map, BATTLE_FLOOR, MINI_BOSSES[0], RUN_SEED))
	var again: String = _entries_text(_draw_only(map, BATTLE_FLOOR, MINI_BOSSES[0], RUN_SEED))
	_check.call("key map: the same seed draws the same mini-boss, prefix and escort twice", (
			not first.is_empty() and first == again
	), first)


# Through the campaign session: the k-th key combat of one run fields the k-th mini-boss of its
# order, so a run's four key combats meet four different ones, and a second run on the same seed
# meets the same ones.
func _test_run_draws() -> void:
	var met: PackedStringArray = _met_in_run(RUN_SEED)
	_check.call("run: four key combats meet four different mini-bosses", (
			_sorted(met) == PackedStringArray(MINI_BOSSES)
	), str(met))
	_check.call("run: the same seed meets the same mini-bosses in the same order", (
			_met_in_run(RUN_SEED) == met
	), str(met))
	_check.call("run: the battle fields the run order's mini-boss", (
			met == _order(RUN_SEED, 0, 4)
	), "%s / %s" % [met, _order(RUN_SEED, 0, 4)])


# A real battle on the Hall at floor 6 (step 2): the mini-boss is the one marked enemy, with its
# escort's step-2 count beside it; another enemy's fall leaves the map open, the mini-boss's wins
# it.
func _test_hall_battle() -> void:
	var run: CampaignSession = _run(RUN_SEED)
	var battle: CombatEncounter = run.begin_battle(_request(run, _map("hall"), 0))
	if battle == null:
		_check.call("hall: the battle begins", false)
		run.close()
		return
	var session: CombatSession = battle.get_session(0)
	var state: CombatState = session.state
	var slot: Vector2i = session.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT)[0]
	var boss_id: String = state.occupant_at(slot)
	var expected_class: String = _order(RUN_SEED, 0, 1)[0]
	_check.call("hall: the run's first mini-boss is the one marked enemy, on the leader slot", (
			not boss_id.is_empty()
			and state.unit_type_of(boss_id) == expected_class
			and Objectives.marked_ids(session) == PackedStringArray([boss_id])
	), "%s (%s); marked %s" % [
		boss_id, state.unit_type_of(boss_id), Objectives.marked_ids(session),
	])
	_check.call("hall: its escort numbers step 2's count, the mini-boss on top", (
			state.units_of(ENEMY).size() == PackDefinition.STEP_SIZES[1] + 1
	), "%d enemies" % [state.units_of(ENEMY).size()])
	var players: PackedStringArray = state.units_of(PLAYER)
	var player_id: String = players[0] if not players.is_empty() else ""
	var other_id: String = ""
	for enemy_id: String in state.units_of(ENEMY):
		if enemy_id != boss_id:
			other_id = enemy_id
			break
	_send(session, DefeatFixture.new([other_id], player_id))
	_check.call("hall: an escort's fall leaves the map open", not session.is_finished)
	_send(session, DefeatFixture.new([boss_id], player_id))
	_check.call("hall: the mini-boss's fall wins the map with enemies left", (
			session.is_won and not state.units_of(ENEMY).is_empty() and _has_ended(session)
	), "won %s, %d enemies left" % [session.is_won, state.units_of(ENEMY).size()])
	run.close()


# Command, every 3rd enemy Phase Start: shown on turn 3 only; after it, every ally of the Captain,
# itself included, enters the player phase with 1 Stance over its maximum.
func _test_command() -> void:
	var world: AiWorld = _world(_rows(20, 2))
	world.add_enemy("e1", "brigand_captain", Vector2i(0, 0))
	world.add_enemy("e2", "brute", Vector2i(0, 1))
	world.add_player("p1", Vector2i(19, 1), "bow", STURDY)
	world.session.open_battle()
	var shown: PackedStringArray = []
	for turn: int in range(1, 4):
		var intent: EnemyIntent = _intent(world, "e1")
		var is_signature: bool = intent != null and intent.kind == EnemyIntent.Kind.SIGNATURE
		shown.append("%d %s" % [turn, intent.signature_name if is_signature else "-"])
		if turn < 3:
			_send(world.session, EndTurnCommand.new(0))
	_check.call("command: shown as its intent on turn 3 only, the phase before it fires", (
			shown == PackedStringArray(["1 -", "2 -", "3 Command"])
	), str(shown))
	var before: int = world.engine().fact_log.size()
	_send(world.session, EndTurnCommand.new(0))
	_check.call("command: fires once at the 3rd enemy Phase Start", (
			_activations(world.session, before, "command") == 1
	), str(_activations(world.session, before, "command")))
	var stances: PackedStringArray = []
	var all_over: bool = true
	for unit_id: String in ["e1", "e2"]:
		var stance_max: int = world.engine().stats(unit_id).get_int(CombatValue.Key.STANCE_MAX)
		var stance: int = world.state().get_stance(unit_id)
		stances.append("%s %d/%d" % [unit_id, stance, stance_max])
		all_over = all_over and stance == stance_max + 1
	_check.call("command: every ally, the Captain too, enters the player phase 1 over its max", (
			all_over and world.state().turn == 4
	), str(stances))


# Fortify, every 2nd enemy Phase Start: shown on turn 2 over the tiles beside it; 4 Block to every
# unit beside it, friend or foe, not itself; +1 Parry that lasts through the player phase after.
func _test_fortify() -> void:
	var world: AiWorld = _world(_rows(8, 8))
	world.add_enemy("e1", "iron_wall", Vector2i(3, 3))
	# A Crossbowman holds its tile while a foe is in range, so it is still beside the wall when
	# Fortify fires.
	world.add_enemy("e2", "crossbowman", Vector2i(3, 2))
	world.add_player("p1", Vector2i(4, 3), "sword", STURDY)
	world.session.open_battle()
	var base_parry: int = world.engine().stats("e2").get_int(CombatValue.Key.PARRY)
	var turn_1: EnemyIntent = _intent(world, "e1")
	_check.call("fortify: turn 1 shows no signature", (
			turn_1 != null and turn_1.kind != EnemyIntent.Kind.SIGNATURE
	), "" if turn_1 == null else turn_1.describe())
	_send(world.session, EndTurnCommand.new(0))
	var turn_2: EnemyIntent = _intent(world, "e1")
	var beside: Array[Vector2i] = [
		Vector2i(3, 2), Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 4),
	]
	var covers: bool = turn_2 != null
	for tile: Vector2i in beside:
		covers = covers and turn_2.area.has(tile)
	_check.call("fortify: turn 2 shows Fortify the phase before it fires, over its neighbors", (
			covers
			and turn_2.kind == EnemyIntent.Kind.SIGNATURE
			and turn_2.signature_name == "Fortify"
			and not turn_2.area.has(Vector2i(3, 3))
	), "" if turn_2 == null else "%s; area %s" % [turn_2.describe(), turn_2.area])
	var before: int = world.engine().fact_log.size()
	_send(world.session, EndTurnCommand.new(0))
	var gained: PackedStringArray = _changed(
			world.session, before, "fortify", CombatFact.Kind.BLOCK_GAINED
	)
	_check.call("fortify: 4 Block to every unit beside it, friend or foe, not itself", (
			gained == PackedStringArray(["e2 4", "p1 4"])
	), str(gained))
	var parry_3: int = world.engine().stats("e2").get_int(CombatValue.Key.PARRY)
	var foe_parry_3: int = world.engine().stats("p1").get_int(CombatValue.Key.PARRY)
	_check.call("fortify: +1 Parry for both sides through the player phase after it fires", (
			parry_3 == base_parry + 1 and foe_parry_3 == 1 and world.state().turn == 3
	), "ally %d, foe %d, base %d" % [parry_3, foe_parry_3, base_parry])
	_send(world.session, EndTurnCommand.new(0))
	var parry_4: int = world.engine().stats("e2").get_int(CombatValue.Key.PARRY)
	_check.call("fortify: the Parry ends with that player phase", (
			parry_4 == base_parry
	), "%d, base %d" % [parry_4, base_parry])


# Hex Storm, every 3rd enemy Phase Start: shown on turn 3, the storm's area around its target in
# the intent; that phase its hit takes 1 Stance from every unit within 2 tiles of the target, once
# each, and the plain Curse doesn't fire; the storm is spent by the next player phase.
func _test_hex_storm() -> void:
	var world: AiWorld = _world(_rows(10, 10), ForecastRolls.new())
	world.add_enemy("e1", "hex_matron", Vector2i(5, 2))
	world.add_player("p1", Vector2i(5, 5), "sword", STURDY)
	world.add_player("p2", Vector2i(5, 7), "sword", STURDY)
	world.add_player("p3", Vector2i(6, 5), "sword", STURDY)
	world.session.open_battle()
	var early: PackedStringArray = []
	for turn: int in range(1, 3):
		var intent: EnemyIntent = _intent(world, "e1")
		if intent == null or intent.kind == EnemyIntent.Kind.SIGNATURE:
			early.append("turn %d's intent" % [turn])
		var before: int = world.engine().fact_log.size()
		_send(world.session, EndTurnCommand.new(0))
		var kind: CombatFact.Kind = CombatFact.Kind.STANCE_CHANGED
		if not _changed(world.session, before, "hex_storm_curse", kind).is_empty():
			early.append("a storm on turn %d" % [turn])
	var turn_3: EnemyIntent = _intent(world, "e1")
	_check.call("hex storm: turns 1 and 2 show no signature and fire no storm", (
			early.is_empty()
	), str(early))
	_check.call("hex storm: turn 3 shows Hex Storm, the storm's area around its target", (
			turn_3 != null
			and turn_3.kind == EnemyIntent.Kind.SIGNATURE
			and turn_3.signature_name == "Hex Storm"
			and turn_3.target_id == "p1"
			and turn_3.area.has(Vector2i(5, 7))
	), "" if turn_3 == null else "%s; area %s" % [turn_3.describe(), turn_3.area])
	var before: int = world.engine().fact_log.size()
	_send(world.session, EndTurnCommand.new(0))
	var stormed: PackedStringArray = _changed(
			world.session, before, "hex_storm_curse", CombatFact.Kind.STANCE_CHANGED
	)
	var cursed: PackedStringArray = _changed(
			world.session, before, "curse", CombatFact.Kind.STANCE_CHANGED
	)
	_check.call("hex storm: every unit within 2 tiles of its target loses Stance, once a hit", (
			_units_of(stormed).has("p1")
			and _units_of(stormed).has("p2")
			and _units_of(stormed).has("p3")
			and cursed.is_empty()
	), "storm %s; curse %s" % [stormed, cursed])
	_check.call("hex storm: spent by the next player phase", (
			not world.engine().stats("e1").is_allowed(CombatValue.Permission.HEX_STORM)
			and world.state().turn == 4
	))


# Blood Scent: a kill lets the Bloodhound move again. Its kill shows as Blood Scent; after it, it
# walks toward the next foe with the movement it has left, and its turn ends with no fault.
func _test_blood_scent() -> void:
	var world: AiWorld = _world(_rows(16, 3), ForecastRolls.new())
	world.add_enemy("e1", "bloodhound", Vector2i(1, 1))
	world.add_player("p1", Vector2i(2, 1), "sword", {CombatValue.Key.HP: 1.0})
	world.add_player("p2", Vector2i(15, 1), "sword", STURDY)
	world.session.open_battle()
	var turn_1: EnemyIntent = _intent(world, "e1")
	_check.call("blood scent: its kill shows as Blood Scent", (
			turn_1 != null
			and turn_1.kind == EnemyIntent.Kind.SIGNATURE
			and turn_1.signature_name == "Blood Scent"
			and turn_1.target_id == "p1"
	), "" if turn_1 == null else turn_1.describe())
	var before: int = world.engine().fact_log.size()
	var diagnostics: int = world.engine().diagnostics.size()
	_send(world.session, EndTurnCommand.new(0))
	var second_moves: int = 0
	for index: int in range(before, world.engine().fact_log.size()):
		var fact: CombatFact = world.engine().fact_log[index]
		var is_second: bool = fact.flags & CombatFact.Flag.SECOND_MOVE != 0
		if fact.kind == CombatFact.Kind.UNIT_MOVED and fact.actor_id == "e1" and is_second:
			second_moves += 1
	var tile: Vector2i = world.state().tile_of("e1")
	var faults: PackedStringArray = world.engine().diagnostics.slice(diagnostics)
	_check.call("blood scent: the kill lands, then it moves again toward the next foe", (
			not world.state().has_unit("p1")
			and second_moves == 1
			and tile.x > 2
			and faults.is_empty()
	), "tile %s, %d second moves; %s" % [tile, second_moves, faults])
	var turn_2: EnemyIntent = _intent(world, "e1")
	_check.call("blood scent: with no kill in reach, no signature", (
			turn_2 != null and turn_2.kind != EnemyIntent.Kind.SIGNATURE
	), "" if turn_2 == null else turn_2.describe())


# Blood Scent with no better tile than its own: the Bloodhound kills from where it stands, already
# beside its next foe, so its second move is a Wait. The Wait's command builds, it waits, and the
# enemy phase carries on into turn 2's player phase with no fault.
func _test_blood_scent_wait() -> void:
	var world: AiWorld = _world(_rows(3, 1), ForecastRolls.new())
	world.add_player("p2", Vector2i(0, 0), "sword", STURDY)
	world.add_enemy("e1", "bloodhound", Vector2i(1, 0))
	world.add_player("p1", Vector2i(2, 0), "sword", {CombatValue.Key.HP: 1.0})
	world.session.open_battle()
	var before: int = world.engine().fact_log.size()
	var diagnostics: int = world.engine().diagnostics.size()
	_send(world.session, EndTurnCommand.new(0))
	var moves: int = 0
	var waits: int = 0
	for index: int in range(before, world.engine().fact_log.size()):
		var fact: CombatFact = world.engine().fact_log[index]
		if fact.actor_id != "e1":
			continue
		if fact.kind == CombatFact.Kind.UNIT_MOVED:
			moves += 1
		elif fact.kind == CombatFact.Kind.UNIT_WAITED:
			waits += 1
	var faults: PackedStringArray = world.engine().diagnostics.slice(diagnostics)
	_check.call("blood scent: a second move that ends in a Wait waits, and the phase carries on", (
			not world.state().has_unit("p1")
			and world.state().tile_of("e1") == Vector2i(1, 0)
			and moves == 0
			and waits == 1
			and world.state().turn == 2
			and world.state().phase_side == PLAYER
			and faults.is_empty()
	), "turn %d, %d moves, %d waits; %s" % [world.state().turn, moves, waits, faults])


# A second move's plan as its command: a Wait builds with an empty path, an advance as a Move along
# the plan's path; neither names a target.
func _test_second_move_commands() -> void:
	var wait_plan: EnemyPlan = EnemyPlan.new()
	wait_plan.actor_id = "e1"
	wait_plan.is_second_move = true
	var waits: UnitTurnCommand = wait_plan.to_command()
	_check.call("second move: a Wait plan builds a Wait command with an empty path", (
			waits != null
			and waits.action == UnitTurnCommand.Action.WAIT
			and waits.path.is_empty()
			and waits.target_id.is_empty()
	), "null" if waits == null else "%s, %s" % [waits.get_label(), waits.path])
	var move_plan: EnemyPlan = EnemyPlan.new()
	move_plan.actor_id = "e1"
	move_plan.kind = EnemyPlan.Kind.ADVANCE
	move_plan.path = [Vector2i(1, 0), Vector2i(2, 0)]
	move_plan.is_second_move = true
	var moves: UnitTurnCommand = move_plan.to_command()
	_check.call("second move: an advance builds a Move command along its path", (
			moves != null
			and moves.action == UnitTurnCommand.Action.MOVE
			and moves.path == move_plan.path
			and moves.target_id.is_empty()
	), "null" if moves == null else "%s, %s" % [moves.get_label(), moves.path])


# The mini-bosses of a run's key combats from index from to index to - 1, as the campaign session
# draws them.
func _order(run_seed: int, from: int, to: int) -> PackedStringArray:
	var ids: PackedStringArray = []
	for index: int in range(from, to):
		var order: RngStream = RngStream.new(RngKey.derive_seed(
				run_seed, RngKey.RngPurpose.MINI_BOSS_DRAW, -1, -1, -1, -1
		))
		ids.append(EnemySetup.mini_boss_for(_catalog, order, index))
	return ids


# The mini-boss each of a run's first four key combats fields, each begun on the Hall through the
# campaign session.
func _met_in_run(run_seed: int) -> PackedStringArray:
	var met: PackedStringArray = []
	var run: CampaignSession = _run(run_seed)
	for index: int in MINI_BOSSES.size():
		var battle: CombatEncounter = run.begin_battle(_request(run, _map("hall"), index))
		if battle == null:
			met.append("none")
			continue
		met.append(str(_result(battle.setup).get(EnemySetup.MINI_BOSS_KEY, "")))
		run.abandon_battle()
	run.close()
	return met


# What is wrong with setup's draw on a key map at floor_number for boss_id; empty when nothing is.
func _mini_boss_problem(
		setup: CombatEncounter.EncounterSetup, floor_number: int, boss_id: String
) -> String:
	var drawn: Dictionary = _result(setup)
	var pack: PackDefinition = _catalog.pack(str(drawn.get(EnemySetup.PACK_KEY, "")))
	if pack == null or pack.mini_boss_id != boss_id:
		return "pack %s" % [drawn.get(EnemySetup.PACK_KEY, "")]
	if str(drawn.get(EnemySetup.MINI_BOSS_KEY, "")) != boss_id:
		return "mini-boss %s" % [drawn.get(EnemySetup.MINI_BOSS_KEY, "")]
	var step: int = EnemySetup.step_of(floor_number)
	var units: Array = drawn.get(EnemySetup.UNITS_KEY, [])
	var unplaced: Array = drawn.get(EnemySetup.UNPLACED_KEY, [])
	if units.size() + unplaced.size() != PackDefinition.STEP_SIZES[step - 1] + 1:
		return "%d units and %d unplaced" % [units.size(), unplaced.size()]
	var slots: Array[Vector2i] = setup.layout.tiles_of(MapLayout.MarkerKind.ENEMY_SLOT)
	var leader_slot: Vector2i = setup.layout.tiles_of(MapLayout.MarkerKind.LEADER_SLOT)[0]
	var escort: PackedStringArray = []
	var bosses: int = 0
	for entry: Variant in units:
		var unit: Dictionary = entry
		var class_id: String = str(unit.get(EnemySetup.CLASS_KEY, ""))
		var level: int = _whole(unit.get(EnemySetup.LEVEL_KEY, 0))
		if unit.has(EnemySetup.PREFIX_KEY):
			bosses += 1
			var prefix: UnitPrefixDefinition = _catalog.unit_prefix(
					str(unit.get(EnemySetup.PREFIX_KEY, ""))
			)
			if (
					class_id != boss_id
					or _tile_of(unit) != leader_slot
					or level != EnemySetup.level_for(floor_number, true, true)
					or prefix == null
					or prefix.tier <= 0
			):
				return "mini-boss entry %s" % [unit]
			continue
		escort.append(class_id)
		if not slots.has(_tile_of(unit)) or level != EnemySetup.level_for(floor_number, true):
			return "escort entry %s" % [unit]
	for class_id: Variant in unplaced:
		escort.append(str(class_id))
	escort.sort()
	var expected: PackedStringArray = pack.units(step)
	expected.sort()
	if bosses != 1 or escort != expected:
		return "%d mini-bosses; escort %s, not %s" % [bosses, escort, expected]
	return ""


# Every drawn entry of setup as text, in order.
func _entries_text(setup: CombatEncounter.EncounterSetup) -> String:
	return JSON.stringify(_result(setup).get(EnemySetup.UNITS_KEY, []))


# Effect activations of the effect named effect_id on session from fact index from on.
func _activations(session: CombatSession, from: int, effect_id: String) -> int:
	var count: int = 0
	for index: int in range(from, session.engine.fact_log.size()):
		var fact: CombatFact = session.engine.fact_log[index]
		if fact.kind == CombatFact.Kind.EFFECT_ACTIVATED and _from(session, fact, effect_id):
			count += 1
	return count


# "<actor> <amount>" of every fact of kind from the effect named effect_id since index from,
# sorted.
func _changed(
		session: CombatSession, from: int, effect_id: String, kind: CombatFact.Kind
) -> PackedStringArray:
	var parts: PackedStringArray = []
	for index: int in range(from, session.engine.fact_log.size()):
		var fact: CombatFact = session.engine.fact_log[index]
		if fact.kind == kind and _from(session, fact, effect_id):
			parts.append("%s %d" % [fact.actor_id, fact.amount])
	parts.sort()
	return parts


# The unit ids of _changed's parts.
func _units_of(parts: PackedStringArray) -> PackedStringArray:
	var ids: PackedStringArray = []
	for part: String in parts:
		ids.append(part.get_slice(" ", 0))
	return ids


func _from(session: CombatSession, fact: CombatFact, effect_id: String) -> bool:
	var instance: EffectInstance = session.engine.get_instance(fact.source_effect_id)
	return instance != null and instance.definition.id == effect_id


func _sorted(ids: PackedStringArray) -> PackedStringArray:
	var copy: PackedStringArray = ids.duplicate()
	copy.sort()
	return copy


# A battle of the real catalog's classes on rows, the AI and intents registered.
func _world(rows: Array[String], rolls: RollSource = null) -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, rows, rolls)
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


func _has_ended(session: CombatSession) -> bool:
	for fact: CombatFact in session.engine.fact_log:
		if fact.kind == CombatFact.Kind.COMBAT_ENDED and fact.side == PLAYER:
			return true
	return false


func _send(session: CombatSession, command: Command) -> void:
	session.submit(command)
	var batch: CombatSession.FactBatch = session.resolve_next()
	if batch != null and batch.is_rejected():
		_check.call("send: %s accepted" % [batch.label], false, batch.rejected_reason)


func _map(map_id: String) -> CombatMapDefinition:
	return load("res://maps/key/%s.tres" % [map_id]) as CombatMapDefinition


func _run(run_seed: int) -> CampaignSession:
	return CampaignSession.new(CampaignData.Mode.SOLO, run_seed, PackedInt32Array([0]))


# A request on map at BATTLE_FLOOR, key_combats_before key combats into the run, whose seat 0 is
# one real Archer with a Simple Bow, turn 1 at once (no opening swap).
func _request(
		run: CampaignSession, map: CombatMapDefinition, key_combats_before: int
) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BATTLE_FLOOR
	request.node = NODE
	request.key_combats_before = key_combats_before
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


# Setup step 4 alone on map at floor_number, drawing boss_id's key pack.
func _draw_only(
		map: CombatMapDefinition, floor_number: int, boss_id: String, run_seed: int
) -> CombatEncounter.EncounterSetup:
	var battle: CombatEncounter = CombatEncounter.new(
			floor_number, NODE, PackedInt32Array([0]), InstanceIdAllocator.new()
	)
	battle.add_setup_step(
			CombatEncounter.SetupStep.ENEMY_SLOTS,
			EnemySetup.draw.bind(_catalog, floor_number, 0, 0, boss_id)
	)
	var pool: Array[CombatMapDefinition] = [map]
	battle.run_setup(pool, CombatEncounter.SetupStreams.new(run_seed, floor_number, NODE))
	return battle.setup


func _result(setup: CombatEncounter.EncounterSetup) -> Dictionary:
	var drawn: Variant = setup.shared.get(EnemySetup.ENEMIES_KEY, {})
	return drawn if drawn is Dictionary else {}


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
