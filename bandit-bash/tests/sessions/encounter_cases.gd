# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     encounter_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## [CombatEncounter] cases for tests/sessions/run_all.gd: setup steps, stream injection,
## cross-map effects, routing, transfers and each map's end.


func run() -> void:
	_run(_test_setup_order)
	_run(_test_map_choice)
	_run(_test_setup_streams)
	_run(_test_container_contents)
	_run(_test_setup_draws_only_inside_setup)
	_run(_test_combat_rolls_injection)
	_run(_test_deploy_after_setup)
	_run(_test_cross_map_counting)
	_run(_test_positional_never_across)
	_run(_test_rune_routing)
	_run(_test_arrival_order_across_maps)
	_run(_test_unit_transfer)
	_run(_test_arrivals_before_refresh)
	_run(_test_objectives_end_each_map)


func _test_setup_order() -> bool:
	# An Array, not a PackedStringArray: lambdas capture packed arrays by value.
	var trace: Array[String] = []
	var battle: Battle = Battle.new(PackedInt32Array([1, 0]))
	var encounter: CombatEncounter = battle.encounter
	# Registered out of order on purpose: steps run in step order, a step's runs in registration
	# order.
	encounter.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, _recorder(trace, "7"))
	encounter.add_setup_step(CombatEncounter.SetupStep.DARKNESS_SOURCES, _recorder(trace, "3"))
	encounter.add_setup_step(CombatEncounter.SetupStep.SEAT_ADDITIONS, _recorder(trace, "6"))
	encounter.add_setup_step(CombatEncounter.SetupStep.OBJECTS, _recorder(trace, "2a"))
	encounter.add_setup_step(CombatEncounter.SetupStep.REINFORCEMENT_WAVES, _recorder(trace, "5"))
	encounter.add_setup_step(CombatEncounter.SetupStep.ENEMY_SLOTS, _recorder(trace, "4"))
	encounter.add_setup_step(CombatEncounter.SetupStep.OBJECTS, _recorder(trace, "2b"))
	encounter.add_setup_step(CombatEncounter.SetupStep.MAP_CHOICE, _recorder(trace, "1"))
	var err: Error = battle.set_up()
	_check("setup: runs", err == OK, error_string(err))
	var order: String = " ".join(PackedStringArray(trace))
	_check("setup: fixed step order, then per seat", order == (
			"1 2a 2b 3 4 5 6(s0) 7(s0) 6(s1) 7(s1)"
	), order)
	_check("setup: the map is loaded before step 1's own runs", (
			encounter.setup.layout != null and encounter.setup.map.id == "map_a"
	))
	_check("setup: runs once", battle.set_up() == ERR_ALREADY_IN_USE)
	return true


func _test_map_choice() -> bool:
	var pool: Array[CombatMapDefinition] = Battle.pool(["map_a", "map_b", "map_c"])
	var first: Battle = Battle.new()
	var second: Battle = Battle.new()
	first.set_up(pool)
	second.set_up(pool)
	var expected: int = Battle.fresh_stream(RngKey.RngPurpose.ENCOUNTER_SETUP, -1, -1).pick_index(3)
	_check("map: drawn from the pool with ENCOUNTER_SETUP", (
			first.encounter.setup.map == pool[expected]
	), first.encounter.setup.map.id)
	_check("map: the same seed draws the same map", (
			second.encounter.setup.map == first.encounter.setup.map
	))

	var single: Battle = Battle.new()
	var untouched: Array[String] = []
	single.encounter.add_setup_step(
			CombatEncounter.SetupStep.OBJECTS,
			func(ctx: CombatEncounter.SetupContext) -> void: untouched.append(ctx.stream.capture())
	)
	single.set_up()
	_check("map: a pool of one draws nothing", (
			untouched.size() == 1
			and untouched[0] == Battle.fresh_stream(
					RngKey.RngPurpose.ENCOUNTER_SETUP, -1, -1
			).capture()
	))
	var empty: Array[CombatMapDefinition] = []
	print("    (one error about an empty pool follows)")
	var no_map: Battle = Battle.new()
	_check("map: an empty pool sets nothing up", (
			no_map.set_up(empty) == ERR_CANT_OPEN and no_map.encounter.setup == null
	))
	return true


func _test_setup_streams() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	var shared: Array[RngStream] = []
	var seat_draws: Dictionary[int, int] = {}
	var loot_draws: Dictionary[int, int] = {}
	var loot_in_step_2: Array[RngStream] = []
	var seat_stream_in_step_7: Array[RngStream] = []
	for step: CombatEncounter.SetupStep in [
		CombatEncounter.SetupStep.OBJECTS,
		CombatEncounter.SetupStep.DARKNESS_SOURCES,
		CombatEncounter.SetupStep.ENEMY_SLOTS,
		CombatEncounter.SetupStep.REINFORCEMENT_WAVES,
	]:
		battle.encounter.add_setup_step(
				step, func(ctx: CombatEncounter.SetupContext) -> void: shared.append(ctx.stream)
		)
	battle.encounter.add_setup_step(
			CombatEncounter.SetupStep.OBJECTS,
			func(ctx: CombatEncounter.SetupContext) -> void:
				loot_in_step_2.append(ctx.loot_stream(0))
	)
	battle.encounter.add_setup_step(
			CombatEncounter.SetupStep.SEAT_ADDITIONS,
			func(ctx: CombatEncounter.SetupContext) -> void:
				seat_draws[ctx.seat] = ctx.stream.randi_range(0, 1 << 30)
	)
	battle.encounter.add_setup_step(
			CombatEncounter.SetupStep.CONTAINER_CONTENTS,
			func(ctx: CombatEncounter.SetupContext) -> void:
				seat_stream_in_step_7.append(ctx.stream)
				loot_draws[ctx.seat] = ctx.loot_stream(1).randi_range(0, 1 << 30)
	)
	battle.set_up()

	_check("streams: steps 2 to 5 share step 1's stream", (
			shared.size() == 4
			and shared[0] != null
			and shared[1] == shared[0]
			and shared[2] == shared[0]
			and shared[3] == shared[0]
	))
	_check("streams: step 6 draws from the seat's ENCOUNTER_SETUP", (
			seat_draws[0] == Battle.fresh_stream(
					RngKey.RngPurpose.ENCOUNTER_SETUP, 0, -1
			).randi_range(0, 1 << 30)
			and seat_draws[1] == Battle.fresh_stream(
					RngKey.RngPurpose.ENCOUNTER_SETUP, 1, -1
			).randi_range(0, 1 << 30)
			and seat_draws[0] != seat_draws[1]
	))
	_check("streams: step 7 draws from the container's MAP_LOOT", (
			loot_draws[1] == Battle.fresh_stream(
					RngKey.RngPurpose.MAP_LOOT, 1, 1
			).randi_range(0, 1 << 30)
	))
	_check("streams: loot only in step 7", loot_in_step_2 == [null])
	_check("streams: no ENCOUNTER_SETUP stream in step 7", seat_stream_in_step_7 == [null, null])
	return true


func _test_container_contents() -> bool:
	var first: Battle = Battle.new(PackedInt32Array([0, 1]), true)
	var again: Battle = Battle.new(PackedInt32Array([0, 1]), true)
	first.set_up()
	again.set_up()
	var seat_0: Dictionary[int, Variant] = first.encounter.setup.seats[0].map.contents
	var seat_1: Dictionary[int, Variant] = first.encounter.setup.seats[1].map.contents
	_check("loot: every container is filled", (
			seat_0.keys() == [0, 1] and seat_1.keys() == [0, 1]
	), str(seat_0))
	var differ: bool = (seat_0[0] != seat_1[0] and seat_0[1] != seat_1[1]) as bool
	_check("loot: two seats, the same container, different contents", differ)
	_check("loot: the same seat gets the same contents twice", (
			again.encounter.setup.seats[0].map.contents == seat_0
			and again.encounter.setup.seats[1].map.contents == seat_1
	))
	_check(
			"setup: twice from fresh streams, identical results",
			again.encounter.setup.summary() == first.encounter.setup.summary(),
			first.encounter.setup.summary()
	)
	return true


func _test_setup_draws_only_inside_setup() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]), true)
	var setup_streams: Array[RngStream] = []
	var contexts: Array[CombatEncounter.SetupContext] = []
	battle.encounter.add_setup_step(
			CombatEncounter.SetupStep.OBJECTS,
			func(ctx: CombatEncounter.SetupContext) -> void:
				setup_streams.append(ctx.stream)
				contexts.append(ctx)
	)
	battle.encounter.add_setup_step(
			CombatEncounter.SetupStep.CONTAINER_CONTENTS,
			func(ctx: CombatEncounter.SetupContext) -> void:
				setup_streams.append(ctx.loot_stream(0))
				setup_streams.append(ctx.loot_stream(1))
				contexts.append(ctx)
	)
	battle.encounter.add_setup_step(
			CombatEncounter.SetupStep.SEAT_ADDITIONS,
			func(ctx: CombatEncounter.SetupContext) -> void: setup_streams.append(ctx.stream)
	)
	var streams: CombatEncounter.SetupStreams = battle.make_streams()
	battle.encounter.run_setup(Battle.pool(["map_a"]), streams)
	var after_setup: PackedStringArray = []
	for stream: RngStream in setup_streams:
		after_setup.append(stream.capture())

	battle.open()
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	var e0: String = battle.add_unit(0, "Brute", ENEMY, -1, Vector2i(1, 3))
	var a1: String = battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 3))
	for i: int in 5:
		battle.encounter.submit(RollFixture.new(0, a0, e0), 0)
		battle.encounter.submit(RollFixture.new(1, a1, ""), 1)
	battle.encounter.resolve_queued()
	var after_battle: PackedStringArray = []
	for stream: RngStream in setup_streams:
		after_battle.append(stream.capture())

	_check("only in setup: the battle drew nothing from a setup stream", (
			setup_streams.size() == 7 and after_battle == after_setup
	), "%d streams" % [setup_streams.size()])
	print("    (one error about a setup stream asked for after setup follows)")
	_check("only in setup: the streams are closed afterwards", (
			not streams.is_open() and streams.shared() == null
	))
	var closed: bool = true
	for ctx: CombatEncounter.SetupContext in contexts:
		closed = closed and ctx.stream == null and ctx.loot_stream(0) == null
	_check("only in setup: a kept context gives no stream", closed)
	var holds: PackedStringArray = _stream_holders(battle.encounter, "encounter")
	for session: CombatSession in battle.encounter.get_sessions():
		holds.append_array(_stream_holders(session, "s%d" % [session.session_id]))
	_check("only in setup: no session or encounter holds a stream or the registry", (
			holds.is_empty()
	), ", ".join(holds))
	return true


func _test_combat_rolls_injection() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var s0: CombatSession = battle.encounter.get_session(0)
	var s1: CombatSession = battle.encounter.get_session(1)
	_check("rolls: each session rolls live", (
			s0.engine.rolls is LiveRolls and s1.engine.rolls is LiveRolls
	))
	var stream_0: RngStream = battle.rng.stream(Battle.rolls_key(0))
	var stream_1: RngStream = battle.rng.stream(Battle.rolls_key(1))
	var before_0: String = stream_0.capture()
	var before_1: String = stream_1.capture()
	var draws_0: Array[bool] = []
	for i: int in 24:
		draws_0.append(s0.engine.rolls.roll_percent(50))
	_check("rolls: a session advances only its seat's COMBAT_ROLLS", (
			stream_0.capture() != before_0 and stream_1.capture() == before_1
	))
	var draws_1: Array[bool] = []
	for i: int in 24:
		draws_1.append(s1.engine.rolls.roll_percent(50))
	_check("rolls: two seats roll independently", (
			draws_0 != draws_1 and stream_1.capture() != before_1
	))
	var fresh: RngStream = Battle.fresh_stream(RngKey.RngPurpose.COMBAT_ROLLS, 0, -1)
	_check("rolls: the session's draws are its seat stream's", draws_0[0] == fresh.roll_percent(50))
	return true


func _test_deploy_after_setup() -> bool:
	var placements: PackedStringArray = []
	var before_draws: PackedStringArray = []
	var after_draws: PackedStringArray = []
	for run: int in 2:
		var battle: Battle = Battle.new()
		battle.set_up()
		battle.open()
		var session: CombatSession = battle.encounter.get_session(0)
		var units: Array[CombatUnitState] = []
		var bases: Dictionary[String, Dictionary] = {}
		for unit_type: String in ["Drengr", "Archer", "Hakkapel"]:
			var unit: CombatUnitState = CombatUnitState.new()
			unit.id = battle.ids.next_unit_id(unit_type)
			unit.seat = 0
			unit.unit_type = unit_type
			unit.hp = 20
			units.append(unit)
			bases[unit.id] = Battle.unit_bases()
		before_draws.append(battle.rng.stream(Battle.rolls_key(0)).capture())
		var placement: AutoDeploy.Placement = session.deploy(units, bases, "")
		after_draws.append(battle.rng.stream(Battle.rolls_key(0)).capture())
		var tiles: PackedStringArray = []
		for unit: CombatUnitState in units:
			tiles.append("%s" % [session.state.tile_of(unit.id)])
		placements.append(" ".join(tiles))
		if run == 0:
			var spawns: String = _kinds_of(session.engine.fact_log)
			_check("deploy: every unit on a deployment tile", (
					placement.unplaced.is_empty()
					and spawns == "UNIT_SPAWNED UNIT_SPAWNED UNIT_SPAWNED"
			), placements[0])
			var hp: int = session.stats(units[0].id).get_int(CombatValue.Key.HP)
			_check("deploy: bases set", hp == 20)
	_check("deploy: no draw", before_draws == after_draws)
	_check("deploy: the same army and map, the same layout", placements[0] == placements[1])
	return true


func _test_cross_map_counting() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	var e0: String = battle.add_unit(0, "Brute", ENEMY, -1, Vector2i(1, 3))
	var a1: String = battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 3))
	var e1: String = battle.add_unit(1, "Brute", ENEMY, -1, Vector2i(1, 3))
	var heirloom: EffectInstance = battle.army_effect(0, _every_hit_by_allies(10))
	_check("cross-map: an army effect on Any Ally Unit is cross-map", (
			CombatEncounter.is_cross_map(heirloom)
	))
	_check("cross-map: added", battle.encounter.add_cross_map(heirloom))
	_check("cross-map: added once", not battle.encounter.add_cross_map(heirloom))
	var id: String = heirloom.instance_id
	_check("cross-map: one instance on every map", (
			battle.encounter.get_session(0).engine.get_instance(id) == heirloom
			and battle.encounter.get_session(1).engine.get_instance(id) == heirloom
	))
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(battle.encounter.bus)

	for i: int in 6:
		battle.encounter.submit(AttackFixture.new(0, a0, e0), 0)
	for i: int in 4:
		battle.encounter.submit(AttackFixture.new(1, a1, e1), 1)
	battle.encounter.resolve_queued()
	var s0: CombatSession = battle.encounter.get_session(0)
	var s1: CombatSession = battle.encounter.get_session(1)

	_check("cross-map: hits on both maps count toward one counter", (
			heirloom.get_counter(EffectTerms.Lane.COMBAT) == 0
			and _count_of(s1.engine.fact_log, CombatFact.Kind.EFFECT_ACTIVATED) == 1
			and _count_of(s0.engine.fact_log, CombatFact.Kind.EFFECT_ACTIVATED) == 0
	))
	_check("cross-map: the 10th hit's map gets the operation", (
			s1.state.get_block(a1) == 2
			and s0.state.get_block(a0) == 0
			and _count_of(s0.engine.fact_log, CombatFact.Kind.BLOCK_GAINED) == 0
	))
	var origins: PackedStringArray = []
	var seqs: PackedStringArray = []
	for fact: CombatFact in battle.encounter.fact_log:
		origins.append("%s@s%d" % [CombatFact.Kind.find_key(fact.kind), fact.session_id])
		seqs.append(str(fact.seq))
	_check("cross-map: counter facts mirrored with the encounter's seq", (
			seqs == PackedStringArray(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"])
	), " ".join(seqs))
	_check("cross-map: each mirrored fact names its map", (
			origins[0] == "COUNTER_CHANGED@s0"
			and origins[5] == "COUNTER_CHANGED@s0"
			and origins[6] == "COUNTER_CHANGED@s1"
			and origins[10] == "EFFECT_ACTIVATED@s1"
	), " ".join(origins))
	battle.encounter.playback.play_all()
	_check("cross-map: encounter facts play on its bus", tracer.combat_facts.size() == 11)
	_check("cross-map: no diagnostics", (
			s0.engine.diagnostics.is_empty() and s1.engine.diagnostics.is_empty()
	))

	var narrower: EffectDefinition = _every_hit_by_allies(10)
	narrower.scope = EffectTerms.Scope.YOUR_UNIT
	var unit_owned: EffectInstance = EffectInstance.new(
			"effect:x",
			_every_hit_by_allies(10),
			EffectOwner.for_unit(a0, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT
	)
	_check("cross-map: Your Unit and unit-owned effects stay on their map", (
			not CombatEncounter.is_cross_map(battle.army_effect(0, narrower))
			and not CombatEncounter.is_cross_map(unit_owned)
	))
	return true


func _test_positional_never_across() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var s0: CombatSession = battle.encounter.get_session(0)
	var s1: CombatSession = battle.encounter.get_session(1)
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	var e0: String = battle.add_unit(0, "Brute", ENEMY, -1, Vector2i(1, 3))
	var a1: String = battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 2))
	var e1: String = battle.add_unit(1, "Brute", ENEMY, -1, Vector2i(1, 2))
	# "Hit dealt by Any Ally Unit, while an ally is within 1 tile of this unit: gain 1 Block".
	var near: EffectDefinition = _every_hit_by_allies(1)
	near.conditions.clear()
	var within: WhilePositionCondition = WhilePositionCondition.new()
	within.kind = WhilePositionCondition.Kind.WITHIN
	within.tiles = 1
	near.conditions.append(within)
	var gain: GainResource = near.operations[0] as GainResource
	gain.target = null
	var instance: EffectInstance = EffectInstance.new(
			battle.ids.next_effect_id(),
			near,
			EffectOwner.for_unit(a0, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT
	)
	s0.engine.register(instance)
	_check("position: an army effect with a position condition isn't cross-map", (
			not CombatEncounter.is_cross_map(battle.army_effect(0, near))
	))

	# a1 stands at (0, 2) on map 1, next to a0's tile on map 0; it must not count as near.
	battle.encounter.submit(AttackFixture.new(1, a1, e1), 1)
	battle.encounter.submit(AttackFixture.new(0, a0, e0), 0)
	battle.encounter.resolve_queued()
	_check("position: an ally on another map is never near", (
			_count_of(s0.engine.fact_log, CombatFact.Kind.EFFECT_ACTIVATED) == 0
			and _count_of(s1.engine.fact_log, CombatFact.Kind.EFFECT_ACTIVATED) == 0
	))
	var b0: String = battle.add_unit(0, "Lancer", PLAYER, 0, Vector2i(0, 2))
	battle.encounter.submit(AttackFixture.new(0, b0, e0), 0)
	battle.encounter.resolve_queued()
	_check("position: an ally on its own map is", (
			_count_of(s0.engine.fact_log, CombatFact.Kind.EFFECT_ACTIVATED) == 1
	))
	return true


func _test_rune_routing() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	battle.encounter.get_session(0).state.set_hp(a0, 10)
	var rune: String = battle.ids.next_rune_id("Mend")
	battle.encounter.submit(RuneFixture.new(1, rune, a0), 0)
	var batches: Array[CombatSession.FactBatch] = battle.encounter.resolve_queued()
	var used: CombatFact = _first_of(batches[0].facts, CombatFact.Kind.RUNE_USED)
	_check("rune: routed to the teammate's map with the caster's seat", (
			batches.size() == 1
			and batches[0].session_id == 0
			and batches[0].seat == 1
			and used.amount == 1
			and used.item_id == rune
			and used.session_id == 0
	))
	_check("rune: resolved there", battle.encounter.get_session(0).state.get_hp(a0) == 15)
	_check("rune: an unknown map routes nothing", (
			battle.encounter.submit(RuneFixture.new(1, rune, a0), 7) == CombatSession.NO_ARRIVAL
	))
	return true


func _test_arrival_order_across_maps() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	var a1: String = battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 3))
	var stamps: Array[int] = [
		battle.encounter.submit(MoveFixture.new(1, a1, Vector2i(1, 3)), 1),
		battle.encounter.submit(MoveFixture.new(0, a0, Vector2i(1, 3)), 0),
		battle.encounter.submit(MoveFixture.new(1, a1, Vector2i(2, 3)), 1),
	]
	var order: PackedStringArray = []
	for batch: CombatSession.FactBatch in battle.encounter.resolve_queued():
		order.append("%d@s%d" % [batch.arrival, batch.session_id])
	_check("order: one clock stamps every map", stamps == [1, 2, 3])
	_check("order: resolved in arrival order across maps", (
			" ".join(order) == "1@s1 2@s0 3@s1"
	), " ".join(order))
	return true


func _test_unit_transfer() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1, 2]))
	battle.set_up()
	battle.open()
	var s0: CombatSession = battle.encounter.get_session(0)
	var s1: CombatSession = battle.encounter.get_session(1)
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 3))
	var e1: String = battle.add_unit(1, "Brute", ENEMY, -1, Vector2i(3, 2))
	var resolve: EffectInstance = EffectInstance.new(
			battle.ids.next_effect_id(),
			_hit_dealt_block("resolve", 1.0, 5),
			EffectOwner.for_unit(a0, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT
	)
	s0.engine.register(resolve)
	resolve.set_counter(EffectTerms.Lane.COMBAT, 3)
	resolve.set_counter(EffectTerms.Lane.CAMPAIGN, 5)
	s0.state.set_block(a0, 4)

	_check(
			"transfer: a map still being fought sends no one",
			battle.encounter.send_unit(a0, 0, 1, Vector2i(0, 3)) == "s0 is still being fought"
	)
	var s2: CombatSession = battle.encounter.get_session(2)
	var a2: String = battle.add_unit(2, "Lancer", PLAYER, 2, Vector2i(0, 3))
	battle.encounter.submit(EndMapFixture.new(ENEMY), 2)
	battle.encounter.submit(EndMapFixture.new(), 0)
	battle.encounter.resolve_queued()
	_check("transfer: the ending fact says who won", (
			s0.is_finished and s0.is_won and s2.is_finished and not s2.is_won and not s1.is_won
	))
	_check(
			"transfer: a lost map sends no one; its player spectates",
			battle.encounter.send_unit(a2, 2, 1, Vector2i(0, 3)) == "s2 was lost"
			and s2.state.has_unit(a2)
	)
	var reason: String = battle.encounter.send_unit(a0, 0, 1, Vector2i(0, 3))
	_check("transfer: a won map sends a survivor", reason.is_empty(), reason)
	_check("transfer: its effects leave the sending map", (
			s0.engine.get_instance(resolve.instance_id) == null
			and battle.encounter.units_in_transit() == PackedStringArray([a0])
	))
	_check("transfer: it isn't on the receiving map before Phase Start", not s1.state.has_unit(a0))

	var arrived: PackedStringArray = battle.encounter.deliver_arrivals(1)
	var unit: CombatUnitState = s1.state.unit(a0)
	_check("transfer: it arrives at the receiving map's Phase Start", (
			arrived == PackedStringArray([a0])
			and s1.state.has_unit(a0)
			and battle.encounter.units_in_transit().is_empty()
	))
	_check("transfer: on the nearest free tile when its tile is taken", (
			unit.tile != Vector2i(0, 3) and s1.state.occupant_at(unit.tile) == a0
	), str(unit.tile))
	_check("transfer: its effects keep their counters", (
			s1.engine.get_instance(resolve.instance_id) == resolve
			and resolve.get_counter(EffectTerms.Lane.COMBAT) == 3
			and resolve.get_counter(EffectTerms.Lane.CAMPAIGN) == 5
	))
	var last: CombatFact = s1.engine.fact_log[s1.engine.fact_log.size() - 1]
	_check("transfer: placed fresh, with its bases", (
			unit.block == 0
			and unit.stance == 2
			and s1.stats(a0).get_int(CombatValue.Key.HP) == 20
			and last.kind == CombatFact.Kind.UNIT_SPAWNED
			and last.actor_id == a0
	))
	battle.encounter.submit(AttackFixture.new(0, a0, e1), 1)
	battle.encounter.resolve_queued()
	_check("transfer: its effects work on the new map", (
			resolve.get_counter(EffectTerms.Lane.COMBAT) == 4
			and s1.engine.diagnostics.is_empty()
	))
	return true


# The receiving map's player Phase Start delivers units on their way (the ARRIVALS hook) before the
# Block and Stance refresh, so an arrival gets the refresh and its Unit Turn Start like the rest.
func _test_arrivals_before_refresh() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var s0: CombatSession = battle.encounter.get_session(0)
	var s1: CombatSession = battle.encounter.get_session(1)
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	var a1: String = battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 3))
	# An enemy, so the objective check (Rout) doesn't end the map at its Phase Start.
	battle.add_unit(1, "Brute", ENEMY, -1, Vector2i(1, 2))
	battle.encounter.submit(EndMapFixture.new(), 0)
	battle.encounter.resolve_queued()
	battle.encounter.send_unit(a0, 0, 1, Vector2i(1, 3))
	var start: int = s1.engine.fact_log.size()
	s1.open_battle()
	var order: PackedStringArray = []
	for i: int in range(start, s1.engine.fact_log.size()):
		var fact: CombatFact = s1.engine.fact_log[i]
		order.append("%s %s" % [CombatFact.Kind.find_key(fact.kind), fact.actor_id])
	_check("arrivals: before the refresh, then refreshed and started like the rest", (
			order == PackedStringArray([
				"UNIT_SPAWNED %s" % [a0],
				"BLOCK_STANCE_REFRESHED %s" % [a1],
				"BLOCK_STANCE_REFRESHED %s" % [a0],
				"PHASE_START ",
				"UNIT_TURN_START %s" % [a1],
				"UNIT_TURN_START %s" % [a0],
			])
	), str(order))
	_check("arrivals: none left on the way", battle.encounter.units_in_transit().is_empty())
	_check("arrivals: no diagnostics", s1.engine.diagnostics.is_empty())
	return true


# Co-op: the encounter registers the objective checks on every map; one map's end ends only its
# session, a map won that way may send units, and the encounter ends with the last map.
func _test_objectives_end_each_map() -> bool:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
	battle.set_up()
	battle.open()
	var s0: CombatSession = battle.encounter.get_session(0)
	var s1: CombatSession = battle.encounter.get_session(1)
	var a0: String = battle.add_unit(0, "Drengr", PLAYER, 0, Vector2i(0, 3))
	battle.add_unit(1, "Archer", PLAYER, 1, Vector2i(0, 3))
	var e1: String = battle.add_unit(1, "Brute", ENEMY, -1, Vector2i(1, 2))
	s0.open_battle()
	s1.open_battle()
	var ended: CombatFact = s0.engine.fact_log[s0.engine.fact_log.size() - 1]
	_check("objectives: a map with no enemy is won by Rout at its Phase Start", (
			s0.is_won
			and ended.kind == CombatFact.Kind.COMBAT_ENDED
			and ended.side == PLAYER
	))
	_check("objectives: the other map goes on, and so does the encounter", (
			not s1.is_finished and not battle.encounter.is_finished()
	))
	_check(
			"objectives: the won map may send a unit",
			battle.encounter.send_unit(a0, 0, 1, Vector2i(2, 3)).is_empty()
	)
	battle.encounter.submit(DefeatFixture.new(e1), 1)
	battle.encounter.resolve_queued()
	_check("objectives: the last map's end ends the encounter", (
			s1.is_won and battle.encounter.is_finished()
	))
	return true


# A setup step that appends [param label] (with the seat, for per-seat steps) to [param trace].
func _recorder(trace: Array[String], label: String) -> Callable:
	return func(ctx: CombatEncounter.SetupContext) -> void:
		trace.append(label if ctx.seat < 0 else "%s(s%d)" % [label, ctx.seat])


# Every property of [param holder], and every element of its arrays and dictionaries, that is a
# stream, the stream registry or the setup streams; [param name] prefixes each hit.
func _stream_holders(holder: Object, name: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for property: Dictionary in holder.get_property_list():
		var property_name: String = property["name"]
		var value: Variant = holder.get(property_name)
		var values: Array = [value]
		if value is Array:
			values = value
		elif value is Dictionary:
			var dictionary: Dictionary = value
			values = dictionary.values()
		for item: Variant in values:
			if item is RngStream or item is RngStreams or item is CombatEncounter.SetupStreams:
				found.append("%s.%s" % [name, property_name])
	return found


func _count_of(facts: Array[CombatFact], kind: CombatFact.Kind) -> int:
	var count: int = 0
	for fact: CombatFact in facts:
		if fact.kind == kind:
			count += 1
	return count


# Defeats [member unit_id] through CombatState.defeat: a step that ends a map by its objective.
class DefeatFixture:
	extends Command

	var unit_id: String = ""

	func _init(defeated_id: String) -> void:
		unit_id = defeated_id

	func resolve(session: CombatSession) -> void:
		session.state.defeat(session.engine, unit_id, "")
