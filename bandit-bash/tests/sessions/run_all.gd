# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_all.gd
# Author:
# Created:  October 28, 2026
# Modified: October 28, 2026
# ==============================================================================

extends SceneTree
## Headless tests for the sessions layer: [InstanceIdAllocator], [Command] and the session queue,
## [CombatSession], [FactPlayback] and [PresentationRequest]; [CombatEncounter]'s setup steps,
## stream injection, cross-map effects, routing and transfers.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/sessions/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## commands make the sessions log warnings and errors on purpose; only FAIL lines mean a
## problem.[br]
## The cases run on the first frame, not in [code]_init[/code]: autoloads exist only from then on
## in [code]--script[/code] mode, and the sessions log through [code]NetLog[/code]. This script
## never names an autoload, since it compiles before they are registered; it reaches them as nodes.

# The combat map tests' fixture: 5 × 4, deployment (0, 3) (1, 3) (2, 3), an enemy slot at (3, 2),
# a chest (container 0) at (0, 0) and a house (container 1) at (0, 2).
const FIXTURE_SCENE: PackedScene = preload("res://tests/map/fixture_map.tscn")

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# Any fixed seed: these cases compare runs with each other, never with golden numbers.
const TEST_STREAM_SEED: int = 0x5EED

# Any fixed run seed and combat node, for the same reason.
const RUN_SEED: int = 0x3F9A12C077E1A
const FLOOR: int = 2
const NODE: int = 5

# NetLog.Level values: this script can't name the autoload (see the class doc).
const LOG_WARN: int = 1
const LOG_DEBUG: int = 3

var _failures: int = 0
var _passes: int = 0
var _has_run: bool = false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	print("--- Sessions tests. Warnings and errors from rejected commands are expected. ---")
	_set_log_level(LOG_WARN)

	_test_allocator()
	_test_presentation_request()
	_test_playback_order_and_speed()
	_test_playback_fast_forward_and_hold()
	_test_arrival_and_atomic_resolution()
	_test_chest_race()
	_test_ownership()
	_test_stale_forecast()
	_test_batches_and_catch_up()
	_test_diagnostics_reported()
	_test_finished_map()
	_test_describe_and_log_lines()

	_test_setup_order()
	_test_map_choice()
	_test_setup_streams()
	_test_container_contents()
	_test_setup_draws_only_inside_setup()
	_test_combat_rolls_injection()
	_test_deploy_after_setup()
	_test_cross_map_counting()
	_test_positional_never_across()
	_test_rune_routing()
	_test_arrival_order_across_maps()
	_test_unit_transfer()

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)
	return false


func _test_allocator() -> void:
	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var item: String = ids.next_item_id("Iron Axe")
	var unit: String = ids.next_unit_id("Drengr")
	var enemy: String = ids.next_enemy_id()
	var effect: String = ids.next_effect_id()
	var first_rune: String = ids.next_rune_id("Mend")
	var second_rune: String = ids.next_rune_id("Mend")
	_check(
			"allocator: one counter behind every kind",
			[item, unit, enemy, effect, first_rune, second_rune]
			== ["item:1", "unit:2", "enemy:3", "effect:4", "rune:5", "rune:6"],
			str([item, unit, enemy, effect, first_rune, second_rune])
	)
	_check("allocator: two copies of one rune differ", first_rune != second_rune)
	_check("allocator: next value", ids.get_next_value() == 7)
	_check("allocator: describe with a label", ids.describe(item) == "item:1 (Iron Axe)")
	_check("allocator: describe without one", ids.describe(enemy) == "enemy:3")
	_check("allocator: unknown id is bare and unknown", (
			ids.describe("item:99") == "item:99" and not ids.is_known("item:99")
	))
	var seat_id: String = InstanceIdAllocator.seat_subject_id(1)
	ids.set_label(seat_id, "army of seat 1")
	_check("allocator: a named seat id is known", (
			ids.is_known(seat_id) and ids.describe(seat_id) == "seat:1 (army of seat 1)"
	))
	_check("allocator: naming mints nothing", ids.get_next_value() == 7)


func _test_presentation_request() -> void:
	var request: PresentationRequest = PresentationRequest.new("choice")
	var answers: Array = []
	request.completed.connect(func(result: Variant) -> void: answers.append(result))
	request.complete(2)
	request.complete(3)
	var answered: bool = (request.result == 2) as bool
	_check("request: completes once", answers == [2] and request.is_done and answered)
	var cancelled: PresentationRequest = PresentationRequest.new()
	cancelled.cancel()
	var no_answer: bool = (cancelled.result == null) as bool
	_check("request: cancel", cancelled.is_done and cancelled.is_cancelled and no_answer)


func _test_playback_order_and_speed() -> void:
	var bus: CombatBus = CombatBus.new()
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(bus)
	var playback: FactPlayback = FactPlayback.new(bus)
	playback.duration_hook = func(_fact: CombatFact) -> float: return 1.0
	playback.enqueue(_facts([CombatFact.Kind.UNIT_MOVED, CombatFact.Kind.ATTACK_MADE]))
	playback.enqueue(_facts([CombatFact.Kind.HIT_DEALT]))

	_check("playback: the first fact plays at once", playback.advance(0.5) == 1)
	_check("playback: nothing during its wait", playback.advance(0.25) == 0)
	_check("playback: the next after the wait", playback.advance(0.25) == 1)
	playback.speed = 2.0
	_check("playback: speed shortens the wait", playback.advance(0.5) == 1)
	_check("playback: queue empty", playback.pending() == 0)
	_check(
			"playback: bus order",
			_kinds_of(tracer.combat_facts) == "UNIT_MOVED ATTACK_MADE HIT_DEALT"
	)

	var long_frame: FactPlayback = FactPlayback.new(CombatBus.new())
	long_frame.duration_hook = func(_fact: CombatFact) -> float: return 1.0
	long_frame.enqueue(_facts([
		CombatFact.Kind.UNIT_MOVED, CombatFact.Kind.UNIT_MOVED, CombatFact.Kind.UNIT_MOVED,
	]))
	_check("playback: a long frame carries its leftover time", long_frame.advance(2.0) == 3)


func _test_playback_fast_forward_and_hold() -> void:
	var bus: CombatBus = CombatBus.new()
	var tracer: BusTracer = BusTracer.new()
	tracer.attach_combat(bus)
	var playback: FactPlayback = FactPlayback.new(bus)
	playback.duration_hook = func(_fact: CombatFact) -> float: return 1.0
	playback.pause_hook = func(fact: CombatFact) -> bool:
		return fact.kind == CombatFact.Kind.DEFEATED
	var stops: Array[CombatFact] = []
	playback.paused_before.connect(func(fact: CombatFact) -> void: stops.append(fact))
	playback.is_fast_forward = true
	playback.enqueue(_facts([
		CombatFact.Kind.ATTACK_MADE,
		CombatFact.Kind.HIT_DEALT,
		CombatFact.Kind.DEFEATED,
		CombatFact.Kind.UNIT_MOVED,
	]))
	_check("fast-forward: plays without waiting up to the pause", playback.advance(0.0) == 2)
	_check("fast-forward: stops before the marked fact", (
			playback.is_paused
			and not playback.is_fast_forward
			and stops.size() == 1
			and stops[0].kind == CombatFact.Kind.DEFEATED
	))
	_check("fast-forward: nothing while paused", playback.advance(10.0) == 0)
	playback.resume()
	_check("fast-forward: resumes at normal speed", playback.advance(0.0) == 1)
	_check("fast-forward: then waits again", playback.advance(0.5) == 0)

	var held_bus: CombatBus = CombatBus.new()
	var held: FactPlayback = FactPlayback.new(held_bus)
	var request: PresentationRequest = PresentationRequest.new("hit animation")
	# Kept, so the connection can be cut: the lambda holds the playback that holds the bus.
	var hold_on_hit: Callable = func(_fact: CombatFact) -> void: held.hold(request)
	held_bus.action.hit_dealt.connect(hold_on_hit)
	held.enqueue(_facts([
		CombatFact.Kind.ATTACK_MADE, CombatFact.Kind.HIT_DEALT, CombatFact.Kind.DAMAGE_DEALT,
	]))
	_check("hold: stops after the fact that held it", held.advance(10.0) == 2)
	_check("hold: still held", held.advance(10.0) == 0)
	request.complete()
	_check("hold: continues once completed", held.advance(0.0) == 1 and held.pending() == 0)
	held_bus.action.hit_dealt.disconnect(hold_on_hit)


func _test_arrival_and_atomic_resolution() -> void:
	var world: World = World.new()
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	var e: String = world.add_unit("Brute", ENEMY, -1, Vector2i(1, 3))
	# "Hit dealt: gain 2 Block", so an attack's batch holds its reaction.
	world.add_trait(a, _hit_dealt_block("steady_hands", 2.0))

	var attack: AttackFixture = AttackFixture.new(0, a, e)
	var needs_block: NeedsBlockFixture = NeedsBlockFixture.new(0, a, 2)
	var first: int = world.session.submit(attack)
	var second: int = world.session.submit(needs_block)
	_check("queue: arrival stamps rise", first == 1 and second == 2)
	_check("queue: nothing resolves on submit", world.session.last_seq() == 2)
	_check("queue: next arrival", world.session.next_arrival() == 1)

	var batches: Array[CombatSession.FactBatch] = world.session.resolve_queued()
	_check("queue: one batch per command, in arrival order", (
			batches.size() == 2 and batches[0].arrival == 1 and batches[1].arrival == 2
	))
	_check(
			"atomic: the reaction is in the attack's batch",
			_kinds_of(batches[0].facts) == (
					"ATTACK_MADE HIT_DEALT EFFECT_ACTIVATED HIT_TAKEN BLOCK_GAINED"
			),
			_kinds_of(batches[0].facts)
	)
	_check(
			"atomic: the next command sees the drained result",
			not batches[1].is_rejected(),
			batches[1].rejected_reason
	)
	_check("queue: empty afterwards", (
			world.session.next_arrival() == CombatSession.NO_ARRIVAL
			and world.session.resolve_next() == null
	))
	_check("atomic: no diagnostics", world.session.engine.diagnostics.is_empty())


func _test_chest_race() -> void:
	var world: World = World.new(PackedInt32Array([0, 1]))
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(1, 0))
	var b: String = world.add_unit("Archer", PLAYER, 1, Vector2i(0, 1))
	var chest: FixtureChest = FixtureChest.new("chest:0", Vector2i(0, 0))
	world.ids.set_label(chest.id, "chest")
	var rejections: Array[String] = []
	world.session.command_rejected.connect(
			func(seat: int, arrival: int, reason: String) -> void:
				rejections.append("%d %d %s" % [seat, arrival, reason])
	)
	var start: int = world.session.last_seq()
	world.session.submit(OpenChestFixture.new(0, a, chest))
	world.session.submit(OpenChestFixture.new(1, b, chest))
	var batches: Array[CombatSession.FactBatch] = world.session.resolve_queued()

	_check("race: the first arrival opens it", (
			not batches[0].is_rejected()
			and _kinds_of(batches[0].facts) == "OBJECT_USED"
			and batches[0].facts[0].actor_id == a
	))
	_check("race: the second is rejected", batches[1].rejected_reason == "the chest is open")
	_check("race: only the second seat is told", (
			rejections == ["1 2 the chest is open"]
	), str(rejections))
	_check("race: the rejection costs nothing", (
			batches[1].facts.is_empty()
			and not world.session.state.unit(b).has_acted
			and world.session.state.tile_of(b) == Vector2i(0, 1)
			and world.session.last_seq() == start + 1
	))


func _test_ownership() -> void:
	var world: World = World.new(PackedInt32Array([0, 1]))
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	var b: String = world.add_unit("Archer", PLAYER, 1, Vector2i(2, 3))
	var e: String = world.add_unit("Brute", ENEMY, -1, Vector2i(3, 2))
	world.session.submit(MoveFixture.new(0, b, Vector2i(2, 2)))
	world.session.submit(MoveFixture.new(0, e, Vector2i(3, 3)))
	world.session.submit(MoveFixture.new(0, a, Vector2i(1, 2)))
	world.session.submit(RuneFixture.new(1, world.ids.next_rune_id("Mend"), a))
	var batches: Array[CombatSession.FactBatch] = world.session.resolve_queued()
	_check(
			"ownership: another seat's unit is rejected",
			batches[0].rejected_reason == "%s isn't seat 0's unit" % [b],
			batches[0].rejected_reason
	)
	_check("ownership: an enemy is rejected", batches[1].is_rejected())
	_check("ownership: its own unit resolves", not batches[2].is_rejected())
	_check("ownership: any seat may cast a rune", not batches[3].is_rejected())


func _test_stale_forecast() -> void:
	var world: World = World.new(PackedInt32Array([0, 1]))
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	var b: String = world.add_unit("Archer", PLAYER, 1, Vector2i(2, 3))
	var e: String = world.add_unit("Brute", ENEMY, -1, Vector2i(1, 3))
	var forecast_seq: int = world.session.last_seq()

	world.session.submit(AttackFixture.new(1, b, e))
	var stale: AttackFixture = AttackFixture.new(0, a, e)
	stale.based_on_seq = forecast_seq
	world.session.submit(stale)
	var old_move: MoveFixture = MoveFixture.new(0, a, Vector2i(0, 2))
	old_move.based_on_seq = forecast_seq
	world.session.submit(old_move)
	var batches: Array[CombatSession.FactBatch] = world.session.resolve_queued()
	var touched: int = batches[0].first_seq()

	_check("stale: the partner's attack resolves", not batches[0].is_rejected())
	_check(
			"stale: an attack on a target touched since its forecast is rejected",
			batches[1].rejected_reason == "stale forecast (s0#%d touched %s)" % [touched, e],
			batches[1].rejected_reason
	)
	_check("stale: a legal move from an old forecast is accepted", (
			not batches[2].is_rejected()
			and world.session.state.tile_of(a) == Vector2i(0, 2)
	))

	var fresh: AttackFixture = AttackFixture.new(0, a, e)
	fresh.based_on_seq = world.session.last_seq()
	world.session.submit(fresh)
	_check("stale: a forecast from now resolves", not world.session.resolve_next().is_rejected())


func _test_batches_and_catch_up() -> void:
	var world: World = World.new()
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	var deployed: CombatSession.FactBatch = world.session.flush("deployment")
	_check("batch: facts outside commands go out first", (
			deployed != null
			and _kinds_of(deployed.facts) == "UNIT_SPAWNED"
			and deployed.arrival == CombatSession.NO_ARRIVAL
	))
	_check("batch: nothing new, no batch", world.session.flush("nothing") == null)

	var sent: Array[CombatSession.FactBatch] = []
	world.session.batch_resolved.connect(
			func(batch: CombatSession.FactBatch) -> void: sent.append(batch)
	)
	world.session.submit(MoveFixture.new(0, a, Vector2i(0, 2)))
	world.session.submit(MoveFixture.new(0, a, Vector2i(1, 2)))
	world.session.resolve_queued()
	_check("batch: each command's batch is sent", sent.size() == 2)
	_check("batch: seqs run on without gaps", (
			sent[0].first_seq() == 2 and sent[0].last_seq() == 2 and sent[1].first_seq() == 3
	))
	_check("batch: facts carry the session", sent[1].facts[0].session_id == 0)
	_check("batch: playback has them all", world.session.playback.pending() == 3)

	_check(
			"catch-up: a client at seq 1 gets the rest",
			_seqs(world.session.facts_since(1)) == "2 3"
	)
	_check("catch-up: a current client gets nothing", world.session.facts_since(3).is_empty())
	world.session.mark_checkpoint()
	world.session.submit(MoveFixture.new(0, a, Vector2i(2, 2)))
	world.session.resolve_queued()
	_check("catch-up: from the checkpoint on", _seqs(world.session.facts_since(3)) == "4")
	_check("catch-up: behind the checkpoint needs a snapshot", (
			not world.session.can_catch_up(2) and world.session.facts_since(2).is_empty()
	))
	_check("catch-up: ahead of the session is refused", not world.session.can_catch_up(9))


func _test_diagnostics_reported() -> void:
	var world: World = World.new()
	world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	print("    (one ERROR line about a fixture diagnostic follows)")
	world.session.submit(DiagnosticFixture.new("fixture: deliberate content error"))
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	_check("diagnostics: reported with the batch", (
			batch.diagnostics == PackedStringArray(["fixture: deliberate content error"])
	))
	world.session.submit(DiagnosticFixture.new(""))
	_check("diagnostics: reported once", world.session.resolve_next().diagnostics.is_empty())


func _test_finished_map() -> void:
	var world: World = World.new()
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	world.session.submit(EndMapFixture.new())
	world.session.submit(MoveFixture.new(0, a, Vector2i(0, 2)))
	var batches: Array[CombatSession.FactBatch] = world.session.resolve_queued()
	_check("finished: COMBAT_ENDED ends the map", world.session.is_finished)
	_check(
			"finished: later commands are rejected",
			batches[1].rejected_reason == "the combat on this map has ended"
	)


func _test_describe_and_log_lines() -> void:
	var world: World = World.new()
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	var e: String = world.add_unit("Brute", ENEMY, -1, Vector2i(1, 3))
	var axe: String = world.ids.next_item_id("Iron Axe")
	world.session.state.unit(a).equipped_weapon_id = axe
	var effect_id: String = world.add_trait(a, _hit_dealt_block("bulwark", 2.0, 2))

	_check("describe: a unit", world.session.describe(a) == "%s (Drengr)" % [a])
	_check("describe: a held item", (
			world.session.describe(axe) == "%s (Iron Axe, held by %s Drengr)" % [axe, a]
	), world.session.describe(axe))
	_check("describe: an effect", (
			world.session.describe(effect_id) == "bulwark on %s (Drengr)" % [a]
	), world.session.describe(effect_id))

	_set_log_level(LOG_DEBUG)
	print("    (DEBUG lines follow: every log path once)")
	world.session.submit(AttackFixture.new(0, a, e))
	world.session.submit(AttackFixture.new(0, a, e))
	var batches: Array[CombatSession.FactBatch] = world.session.resolve_queued()
	var stale: AttackFixture = AttackFixture.new(0, a, e)
	stale.based_on_seq = 1
	world.session.submit(stale)
	var rejected: CombatSession.FactBatch = world.session.resolve_next()
	_set_log_level(LOG_WARN)

	var hit: CombatFact = _first_of(batches[0].facts, CombatFact.Kind.HIT_DEALT)
	_check("log: fact lines describe ids", hit.to_log_line(world.session.describe).begins_with(
			"s0#%d HIT_DEALT %s (Drengr) -> %s (Brute)" % [hit.seq, a, e]
	), hit.to_log_line(world.session.describe))
	var counted: CombatFact = _first_of(batches[0].facts, CombatFact.Kind.COUNTER_CHANGED)
	var counter_line: String = world.session.describe_effect(counted)
	_check("log: an effect's counter line", counter_line == (
			"s0#%d EFFECT bulwark on %s (Drengr) owner %s (Drengr): HIT_DEALT counter 0 -> 1"
			% [counted.seq, a, a]
	), counter_line)
	var completed: CombatFact = _first_of(batches[1].facts, CombatFact.Kind.COUNTER_CHANGED)
	_check(
			"log: a completed counter shows the count it reached",
			world.session.describe_effect(completed).ends_with("counter 1 -> 2"),
			world.session.describe_effect(completed)
	)
	var fired: CombatFact = _first_of(batches[1].facts, CombatFact.Kind.EFFECT_ACTIVATED)
	_check(
			"log: an activation line says what it did",
			world.session.describe_effect(fired).ends_with("HIT_DEALT FIRED queued gain 2 Block"),
			world.session.describe_effect(fired)
	)
	_check("log: an accepted command line", world.session.describe_batch(batches[0]) == (
			"s0 CMD arrival 1 seat 0 %s (Drengr) attack %s (Brute) -> OK s0#%d-s0#%d"
			% [a, e, batches[0].first_seq(), batches[0].last_seq()]
	), world.session.describe_batch(batches[0]))
	_check("log: a rejected command line", world.session.describe_batch(rejected).begins_with(
			"s0 CMD arrival 3 seat 0 %s (Drengr) attack %s (Brute) based_on s0#1 -> REJECTED "
			% [a, e] + "stale forecast (s0#"
	), world.session.describe_batch(rejected))


func _test_setup_order() -> void:
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


func _test_map_choice() -> void:
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


func _test_setup_streams() -> void:
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


func _test_container_contents() -> void:
	var first: Battle = Battle.new(PackedInt32Array([0, 1]), true)
	var again: Battle = Battle.new(PackedInt32Array([0, 1]), true)
	first.set_up()
	again.set_up()
	var seat_0: Dictionary[int, Variant] = first.encounter.setup.seats[0].contents
	var seat_1: Dictionary[int, Variant] = first.encounter.setup.seats[1].contents
	_check("loot: every container is filled", (
			seat_0.keys() == [0, 1] and seat_1.keys() == [0, 1]
	), str(seat_0))
	var differ: bool = (seat_0[0] != seat_1[0] and seat_0[1] != seat_1[1]) as bool
	_check("loot: two seats, the same container, different contents", differ)
	_check("loot: the same seat gets the same contents twice", (
			again.encounter.setup.seats[0].contents == seat_0
			and again.encounter.setup.seats[1].contents == seat_1
	))
	_check(
			"setup: twice from fresh streams, identical results",
			again.encounter.setup.summary() == first.encounter.setup.summary(),
			first.encounter.setup.summary()
	)


func _test_setup_draws_only_inside_setup() -> void:
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


func _test_combat_rolls_injection() -> void:
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


func _test_deploy_after_setup() -> void:
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


func _test_cross_map_counting() -> void:
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
			heirloom.get_counter(EffectDefinition.Lane.COMBAT) == 0
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
	narrower.scope = EffectDefinition.Scope.YOUR_UNIT
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


func _test_positional_never_across() -> void:
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


func _test_rune_routing() -> void:
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


func _test_arrival_order_across_maps() -> void:
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


func _test_unit_transfer() -> void:
	var battle: Battle = Battle.new(PackedInt32Array([0, 1]))
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
	resolve.set_counter(EffectDefinition.Lane.COMBAT, 3)
	resolve.set_counter(EffectDefinition.Lane.CAMPAIGN, 5)
	s0.state.set_block(a0, 4)

	_check(
			"transfer: a map still being fought sends no one",
			battle.encounter.send_unit(a0, 0, 1, Vector2i(0, 3)) == "s0 is still being fought"
	)
	battle.encounter.submit(EndMapFixture.new(), 0)
	battle.encounter.resolve_queued()
	var reason: String = battle.encounter.send_unit(a0, 0, 1, Vector2i(0, 3))
	_check("transfer: a finished map sends a survivor", reason.is_empty(), reason)
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
			and resolve.get_counter(EffectDefinition.Lane.COMBAT) == 3
			and resolve.get_counter(EffectDefinition.Lane.CAMPAIGN) == 5
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
			resolve.get_counter(EffectDefinition.Lane.COMBAT) == 4
			and s1.engine.diagnostics.is_empty()
	))


# A setup step that appends [param label] (with the seat, for per-seat steps) to [param trace].
func _recorder(trace: Array[String], label: String) -> Callable:
	return func(ctx: CombatEncounter.SetupContext) -> void:
		trace.append(label if ctx.seat < 0 else "%s(s%d)" % [label, ctx.seat])


# "Hit dealt by Any Ally Unit: that unit gains 2 Block", every [param every]th hit this combat.
func _every_hit_by_allies(every: int) -> EffectDefinition:
	var definition: EffectDefinition = _hit_dealt_block("war_ledger", 2.0, every)
	definition.scope = EffectDefinition.Scope.ANY_ALLY_UNIT
	var gain: GainResource = definition.operations[0] as GainResource
	gain.target = FactActor.new()
	return definition


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


# "Hit dealt: gain [param block] Block", every [param every]th hit this combat when above 1.
func _hit_dealt_block(id: String, block: float, every: int = 1) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = id
	definition.trigger = EffectDefinition.Trigger.HIT_DEALT
	if every > 1:
		var counter: CounterCondition = CounterCondition.new()
		counter.count = every
		definition.conditions.append(counter)
	var gain: GainResource = GainResource.new()
	gain.pool = GainResource.Pool.BLOCK
	var amount: Constant = Constant.new()
	amount.value = block
	gain.amount = amount
	definition.operations.append(gain)
	return definition


func _facts(kinds: Array[CombatFact.Kind]) -> Array[CombatFact]:
	var facts: Array[CombatFact] = []
	for kind: CombatFact.Kind in kinds:
		facts.append(CombatFact.new(kind))
	return facts


func _first_of(facts: Array[CombatFact], kind: CombatFact.Kind) -> CombatFact:
	for fact: CombatFact in facts:
		if fact.kind == kind:
			return fact
	return CombatFact.new(kind)


func _kinds_of(facts: Array[CombatFact]) -> String:
	var names: PackedStringArray = []
	for fact: CombatFact in facts:
		names.append(CombatFact.Kind.find_key(fact.kind) as String)
	return " ".join(names)


func _seqs(facts: Array[CombatFact]) -> String:
	var parts: PackedStringArray = []
	for fact: CombatFact in facts:
		parts.append(str(fact.seq))
	return " ".join(parts)


func _set_log_level(level: int) -> void:
	root.get_node(^"NetLog").set(&"min_level", level)


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("PASS  %s" % [case_name])
		return
	_failures += 1
	print("FAIL  %s%s" % [case_name, "" if detail.is_empty() else "  (%s)" % [detail]])


# One session on the fixture map, rolling from a fixed stream, with units minted by its allocator.
class World:
	extends RefCounted

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var session: CombatSession = null

	func _init(seats: PackedInt32Array = PackedInt32Array([0])) -> void:
		var grid: MapGrid = MapGrid.new(World.fixture_layout())
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(TEST_STREAM_SEED))
		session = CombatSession.new(0, seats, grid, rolls, ids)
		session.engine.verify = true

	# Places a unit of [param unit_type] with HP 20, Stance 2 and 5 movement. Returns its id.
	func add_unit(
			unit_type: String, side: CombatFact.CombatSide, seat: int, tile: Vector2i
	) -> String:
		var id: String = ""
		if side == CombatFact.CombatSide.PLAYER:
			id = ids.next_unit_id(unit_type)
		else:
			id = ids.next_enemy_id(unit_type)
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.unit_type = unit_type
		unit.hp = 20
		session.add_unit(unit, {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		})
		return id

	# Registers [param definition] as a trait of [param unit_id]. Returns the instance id.
	func add_trait(unit_id: String, definition: EffectDefinition) -> String:
		var state: CombatState = session.state
		var instance: EffectInstance = EffectInstance.new(
				ids.next_effect_id(),
				definition,
				EffectOwner.for_unit(unit_id, state.seat_of(unit_id), state.side_of(unit_id)),
				Modifier.SourceKind.UNIT_TRAIT
		)
		session.engine.register(instance)
		return instance.instance_id

	# The fixture map's layout.
	static func fixture_layout() -> MapLayout:
		var definition: CombatMapDefinition = CombatMapDefinition.new()
		definition.id = "fixture"
		definition.scene = FIXTURE_SCENE
		return MapLoader.load_layout(definition)


# One encounter on the fixture map for the given seats, with the run's stream registry beside it
# as the campaign session holds it. With loot, a step 7 fills every container from its stream.
class Battle:
	extends RefCounted

	var ids: InstanceIdAllocator = InstanceIdAllocator.new()
	var rng: RngStreams = RngStreams.new(RUN_SEED)
	var encounter: CombatEncounter = null

	func _init(
			seats: PackedInt32Array = PackedInt32Array([0]), with_loot: bool = false
	) -> void:
		encounter = CombatEncounter.new(FLOOR, NODE, seats, ids)
		if with_loot:
			encounter.add_setup_step(
					CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers
			)

	# Fresh setup streams for this battle's node.
	func make_streams() -> CombatEncounter.SetupStreams:
		return CombatEncounter.SetupStreams.new(rng.run_seed, FLOOR, NODE)

	func set_up(
			map_pool: Array[CombatMapDefinition] = Battle.pool(["map_a"])
	) -> Error:
		return encounter.run_setup(map_pool, make_streams())

	# Opens a session per seat, each with its seat's COMBAT_ROLLS stream from the registry.
	func open() -> bool:
		var rolls: Dictionary[int, RngStream] = {}
		for seat: int in encounter.seats:
			rolls[seat] = rng.stream(Battle.rolls_key(seat))
		return encounter.open_sessions(rolls)

	# Places a unit on a map with the standard bases. Returns its id.
	func add_unit(
			session_id: int,
			unit_type: String,
			side: CombatFact.CombatSide,
			seat: int,
			tile: Vector2i
	) -> String:
		var unit: CombatUnitState = CombatUnitState.new()
		if side == CombatFact.CombatSide.PLAYER:
			unit.id = ids.next_unit_id(unit_type)
		else:
			unit.id = ids.next_enemy_id(unit_type)
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.unit_type = unit_type
		unit.hp = 20
		encounter.get_session(session_id).add_unit(unit, Battle.unit_bases())
		return unit.id

	# An instance of [param definition] owned by [param seat]'s army, as a heirloom.
	func army_effect(seat: int, definition: EffectDefinition) -> EffectInstance:
		return EffectInstance.new(
				ids.next_effect_id(),
				definition,
				EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(seat), seat),
				Modifier.SourceKind.HEIRLOOM
		)

	# Map definitions on the fixture scene, one per id, in order.
	static func pool(map_ids: Array[String]) -> Array[CombatMapDefinition]:
		var maps: Array[CombatMapDefinition] = []
		for map_id: String in map_ids:
			var definition: CombatMapDefinition = CombatMapDefinition.new()
			definition.id = map_id
			definition.scene = FIXTURE_SCENE
			maps.append(definition)
		return maps

	# A stream of this battle's node derived from scratch, to compare draws with.
	static func fresh_stream(purpose: RngKey.RngPurpose, seat: int, index: int) -> RngStream:
		return RngStream.new(RngKey.derive_seed(RUN_SEED, purpose, FLOOR, NODE, seat, index))

	static func rolls_key(seat: int) -> RngKey:
		return RngKey.new(RngKey.RngPurpose.COMBAT_ROLLS, FLOOR, NODE, seat, -1)

	# HP 20, Stance 2 and 5 movement.
	static func unit_bases() -> Dictionary:
		return {
			CombatValue.Key.HP: 20.0,
			CombatValue.Key.STANCE_MAX: 2.0,
			CombatValue.Key.MOVEMENT: 5.0,
		}

	# A step-7 fake: each container on the map gets a numbered item from its own stream.
	static func fill_containers(ctx: CombatEncounter.SetupContext) -> void:
		for marker: MapLayout.Marker in ctx.setup.layout.markers_of(
				MapLayout.MarkerKind.OBJECT_SPOT
		):
			if marker.container_index < 0:
				continue
			var stream: RngStream = ctx.loot_stream(marker.container_index)
			ctx.seat_setup.contents[marker.container_index] = (
					"item_%d" % [stream.randi_range(0, 1 << 30)]
			)


# A contested object that isn't a map object yet (P04 MP6): open or not.
class FixtureChest:
	extends RefCounted

	var id: String = ""
	var tile: Vector2i = Vector2i.ZERO
	var is_open: bool = false

	func _init(chest_id: String, chest_tile: Vector2i) -> void:
		id = chest_id
		tile = chest_tile


# Moves its unit to a free tile and records UNIT_MOVED. Needs no forecast.
class MoveFixture:
	extends Command

	var to_tile: Vector2i = Vector2i.ZERO

	func _init(sender: int, unit_id: String, tile: Vector2i) -> void:
		seat = sender
		actor_id = unit_id
		to_tile = tile

	func get_label() -> String:
		return "move"

	func validate(session: CombatSession) -> String:
		if not session.state.has_unit(actor_id):
			return "%s isn't on the map" % [actor_id]
		if not session.state.occupant_at(to_tile).is_empty():
			return "%s is taken" % [to_tile]
		return ""

	func resolve(session: CombatSession) -> void:
		session.state.move_unit(actor_id, to_tile)
		var moved: CombatFact = CombatFact.new(CombatFact.Kind.UNIT_MOVED, actor_id)
		moved.tile = to_tile
		session.engine.record(moved)


# Records one hit of its unit on a target, as an exchange would; its forecast read both.
class AttackFixture:
	extends Command

	var target: String = ""

	func _init(sender: int, unit_id: String, target_id: String) -> void:
		seat = sender
		actor_id = unit_id
		target = target_id

	func get_label() -> String:
		return "attack"

	func get_target_id() -> String:
		return target

	func forecast_reads() -> PackedStringArray:
		return PackedStringArray([actor_id, target])

	func validate(session: CombatSession) -> String:
		if not session.state.has_unit(actor_id) or not session.state.has_unit(target):
			return "both units must be on the map"
		return ""

	func resolve(session: CombatSession) -> void:
		session.engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, actor_id, target))
		session.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, actor_id, target))
		session.engine.record(CombatFact.new(CombatFact.Kind.HIT_TAKEN, target, actor_id))


# Legal only while its unit has at least the given Block: proves an earlier command's reactions
# resolved before it.
class NeedsBlockFixture:
	extends Command

	var block: int = 0

	func _init(sender: int, unit_id: String, needed: int) -> void:
		seat = sender
		actor_id = unit_id
		block = needed

	func validate(session: CombatSession) -> String:
		if session.state.get_block(actor_id) < block:
			return "needs %d Block" % [block]
		return ""

	func resolve(session: CombatSession) -> void:
		session.state.wait(session.engine, actor_id)


# Opens the fixture chest from an adjacent tile, using its unit's action.
class OpenChestFixture:
	extends Command

	var chest: FixtureChest = null

	func _init(sender: int, unit_id: String, target_chest: FixtureChest) -> void:
		seat = sender
		actor_id = unit_id
		chest = target_chest

	func get_label() -> String:
		return "open"

	func get_target_id() -> String:
		return chest.id

	func validate(session: CombatSession) -> String:
		if chest.is_open:
			return "the chest is open"
		var unit: CombatUnitState = session.state.unit(actor_id)
		if unit.has_acted:
			return "%s has acted" % [actor_id]
		if session.state.grid.distance(unit.tile, chest.tile) != 1:
			return "%s isn't next to the chest" % [actor_id]
		return ""

	func resolve(session: CombatSession) -> void:
		chest.is_open = true
		session.state.unit(actor_id).has_acted = true
		session.engine.record(CombatFact.new(CombatFact.Kind.OBJECT_USED, actor_id, chest.id))


# A rune cast by its seat on a unit: RUNE_USED (the casting seat in amount), then a heal of 5.
class RuneFixture:
	extends Command

	var rune_id: String = ""
	var target: String = ""

	func _init(sender: int, rune: String, target_id: String) -> void:
		seat = sender
		rune_id = rune
		target = target_id

	func get_label() -> String:
		return "rune"

	func get_target_id() -> String:
		return target

	func validate(session: CombatSession) -> String:
		return "" if session.state.has_unit(target) else "%s isn't on the map" % [target]

	func resolve(session: CombatSession) -> void:
		var used: CombatFact = CombatFact.new(CombatFact.Kind.RUNE_USED, "", target)
		used.item_id = rune_id
		used.amount = seat
		used.tile = session.state.tile_of(target)
		session.engine.record(used)
		session.engine.heal(target, 5.0)


# Raises an engine diagnostic, standing in for a content error found while resolving.
class DiagnosticFixture:
	extends Command

	var problem: String = ""

	func _init(text: String) -> void:
		problem = text

	func resolve(session: CombatSession) -> void:
		if not problem.is_empty():
			session.engine.diagnostics.append(problem)


# Draws three rolls through the session's roll source, as an exchange would, and records the
# attack.
class RollFixture:
	extends Command

	var target: String = ""

	func _init(sender: int, unit_id: String, target_id: String) -> void:
		seat = sender
		actor_id = unit_id
		target = target_id

	func resolve(session: CombatSession) -> void:
		session.engine.rolls.roll_hit_2rn(70)
		session.engine.rolls.roll_percent(25)
		session.engine.rolls.pick_index(3)
		session.engine.record(CombatFact.new(CombatFact.Kind.ATTACK_MADE, actor_id, target))


# Ends the map's combat, as the objectives check will (P04 MP4).
class EndMapFixture:
	extends Command

	func resolve(session: CombatSession) -> void:
		session.engine.record(CombatFact.new(CombatFact.Kind.COMBAT_ENDED))
