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
## stream injection, cross-map effects, routing, transfers and each map's end; [CampaignSession]'s
## battle bridge and grants; and the [code]CampaignService[/code] autoload's lifecycle.
##
## Run from the repo root:[br]
## [code]godot --headless --path bandit-bash --script res://tests/sessions/run_all.gd[/code][br]
## Prints PASS or FAIL per case and exits with code 1 if any case fails. Cases that feed in bad
## commands make the sessions log warnings and errors on purpose; only FAIL lines mean a
## problem.[br]
## The cases run on the first frame, not in [code]_init[/code]: autoloads exist only from then on
## in [code]--script[/code] mode, and the sessions log through [code]NetLog[/code]. This script
## never names an autoload, since it compiles before they are registered; it reaches them as nodes.
## [br][b]Lifecycle cases[/b] drive the real [code]SaveService[/code], which writes save files, so
## they run only with a test user folder and are skipped otherwise. Put an [code]override.cfg[/code]
## in [code]bandit-bash/[/code] for the run, then delete it (never commit it):[br]
## [code][application][/code][br]
## [code]config/use_custom_user_dir=true[/code][br]
## [code]config/custom_user_dir_name="bandit_bash_tests"[/code]

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

# NetLog's levels and categories through the script CombatSession preloads, for its logger().
const ERROR_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.ERROR
const WARN_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.WARN
const INFO_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.INFO
const DEBUG_LEVEL: CombatSession.NetLogScript.Level = CombatSession.NetLogScript.Level.DEBUG
const COMBAT_CATEGORY: CombatSession.NetLogScript.Category = (
		CombatSession.NetLogScript.Category.COMBAT
)
const EFFECTS_CATEGORY: CombatSession.NetLogScript.Category = (
		CombatSession.NetLogScript.Category.EFFECTS
)

# A second run seed for the debug panel's seed restart.
const OTHER_SEED: int = 0x123456789ABCD

var _failures: int = 0
var _passes: int = 0
var _skips: int = 0
var _has_run: bool = false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	print("--- Sessions tests. Warnings and errors from rejected commands are expected. ---")
	_set_log_level(LOG_WARN)

	_run(_test_allocator)
	_run(_test_presentation_request)
	_run(_test_playback_order_and_speed)
	_run(_test_playback_fast_forward_and_hold)
	_run(_test_arrival_and_atomic_resolution)
	_run(_test_chest_race)
	_run(_test_ownership)
	_run(_test_stale_forecast)
	_run(_test_batches_and_catch_up)
	_run(_test_diagnostics_reported)
	_run(_test_finished_map)
	_run(_test_describe_and_log_lines)

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

	_run(_test_bridge_begin_and_end)
	_run(_test_bridge_cross_map_grants)
	_run(_test_dropped_grant_not_recorded)
	_run(_test_bridge_restart_rolls_the_same)
	_run(_test_bridge_close_mid_battle)
	_run(_test_service_lifecycle)

	_run(_test_logger_gating)
	_run(_test_logging_changes_nothing)

	print("--- %d passed, %d failed, %d skipped ---" % [_passes, _failures, _skips])
	quit(1 if _failures > 0 else 0)
	return false


func _test_allocator() -> bool:
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
	return true


func _test_presentation_request() -> bool:
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
	return true


func _test_playback_order_and_speed() -> bool:
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
	return true


func _test_playback_fast_forward_and_hold() -> bool:
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
	return true


func _test_arrival_and_atomic_resolution() -> bool:
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
	return true


func _test_chest_race() -> bool:
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
	return true


func _test_ownership() -> bool:
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
	return true


func _test_stale_forecast() -> bool:
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
	return true


func _test_batches_and_catch_up() -> bool:
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
	return true


func _test_diagnostics_reported() -> bool:
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
	return true


func _test_finished_map() -> bool:
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
	return true


func _test_describe_and_log_lines() -> bool:
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
	return true


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
	resolve.set_counter(EffectDefinition.Lane.COMBAT, 3)
	resolve.set_counter(EffectDefinition.Lane.CAMPAIGN, 5)
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


func _test_bridge_begin_and_end() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr", "Archer"]})
	var a: String = request.armies[0].units[0].id
	var stubborn: EffectDefinition = _counting("stubborn", EffectDefinition.Lane.CAMPAIGN)
	var counted: EffectInstance = _carrier(run, a, stubborn)
	counted.set_counter(EffectDefinition.Lane.CAMPAIGN, 5)
	counted.set_counter(EffectDefinition.Lane.COMBAT, 7)
	var flask: EffectDefinition = _hit_dealt_block("flask", 1.0)
	flask.charges = 3
	flask.charge_lane = EffectDefinition.Lane.CAMPAIGN
	var charged: EffectInstance = _carrier(run, a, flask)
	charged.charges_left = 2
	var benched: EffectInstance = _carrier(run, "unit:99", _hit_dealt_block("benched", 1.0))
	var banner_definition: EffectDefinition = _every_hit_by_allies(3)
	banner_definition.scope = EffectDefinition.Scope.YOUR_UNIT
	var banner: EffectInstance = EffectInstance.new(
			run.ids.next_effect_id(),
			banner_definition,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	)
	run.add_carrier(banner)

	var events: Array[String] = []
	run.combat_encounter_opened.connect(func(encounter: CombatEncounter) -> void:
		events.append("encounter opened")
		encounter.session_opened.connect(
				func(session: CombatSession) -> void:
					events.append("s%d opened" % [session.session_id])
		)
	)
	run.combat_encounter_closed.connect(
			func(_encounter: CombatEncounter) -> void: events.append("encounter closed")
	)
	var battle: CombatEncounter = run.begin_battle(request)
	_check("bridge: begins", battle != null and run.encounter == battle)
	if battle == null:
		return true
	var session: CombatSession = battle.get_session(0)
	var copy: EffectInstance = session.engine.get_instance(counted.instance_id)
	_check("bridge: observers hear the encounter, then each session", (
			events == ["encounter opened", "s0 opened"]
	), str(events))
	_check("bridge: carriers registered as copies", copy != null and copy != counted)
	_check("bridge: campaign lane copied in, combat lane fresh", (
			copy.get_counter(EffectDefinition.Lane.CAMPAIGN) == 5
			and copy.get_counter(EffectDefinition.Lane.COMBAT) == 0
	))
	_check("bridge: a unit outside the battle brings nothing", (
			session.engine.get_instance(benched.instance_id) == null
	))
	_check("bridge: a Your Unit heirloom joins its seat's map", (
			session.engine.get_instance(banner.instance_id) != null
			and battle.get_cross_map_instances().is_empty()
	))
	_check("bridge: the army is deployed", (
			session.state.has_unit(a)
			and _layout_has_deployment(session, session.state.tile_of(a))
	))
	print("    (one error about a battle already on follows)")
	_check("bridge: one battle at a time", run.begin_battle(request) == null)

	var e: String = run.ids.next_enemy_id("Brute")
	var enemy: CombatUnitState = CombatUnitState.new()
	enemy.id = e
	enemy.side = ENEMY
	enemy.tile = Vector2i(3, 2)
	enemy.hp = 20
	session.add_unit(enemy, Battle.unit_bases())
	for i: int in 2:
		battle.submit(AttackFixture.new(0, a, e), 0)
	battle.resolve_queued()
	session.engine.add_growth(a, CombatValue.Stat.RES, 5)
	_check("bridge: the battle counts on the copies", (
			copy.get_counter(EffectDefinition.Lane.CAMPAIGN) == 7
			and copy.get_counter(EffectDefinition.Lane.COMBAT) == 0
			and counted.get_counter(EffectDefinition.Lane.CAMPAIGN) == 5
	))

	var result: CampaignSession.BattleResult = run.end_battle()
	_check("bridge: campaign lanes written back", (
			counted.get_counter(EffectDefinition.Lane.CAMPAIGN) == 7
			and charged.charges_left == 0
	), "%d, %d charges" % [
			counted.get_counter(EffectDefinition.Lane.CAMPAIGN), charged.charges_left
	])
	_check("bridge: combat lanes dropped", counted.get_counter(EffectDefinition.Lane.COMBAT) == 7)
	_check("bridge: growth changes left for the run flow", (
			result.growth_changes.has(a)
			and result.growth_changes[a] == {CombatValue.Stat.RES: 5}
	), str(result.growth_changes))
	_check("bridge: the encounter is closed and announced", (
			run.encounter == null
			and battle.is_closed
			and events[events.size() - 1] == "encounter closed"
	))
	_check("bridge: no battle, nothing to end", run.end_battle() == null)
	return true


func _test_bridge_cross_map_grants() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([1, 0])
	)
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr"], 1: ["Archer"]})
	var a0: String = request.armies[0].units[0].id
	var a1: String = request.armies[1].units[0].id
	# "Every 2nd Hit dealt by Any Ally Unit: gain 50 gold" on seat 0's army.
	var purse: EffectDefinition = _every_hit_by_allies(2)
	var gold: CampaignGrant = CampaignGrant.new()
	gold.amount = 50
	purse.operations.assign([gold])
	var heirloom: EffectInstance = EffectInstance.new(
			run.ids.next_effect_id(),
			purse,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	)
	run.add_carrier(heirloom)
	var recorded: Array[CampaignSession.Grant] = []
	run.grant_recorded.connect(
			func(grant: CampaignSession.Grant) -> void: recorded.append(grant)
	)
	var battle: CombatEncounter = run.begin_battle(request)
	var e0: String = _add_enemy(run, battle.get_session(0))
	var e1: String = _add_enemy(run, battle.get_session(1))
	_check("grants: the heirloom went to the encounter", (
			battle.get_cross_map_instances().size() == 1
			and battle.get_cross_map_instances()[0].instance_id == heirloom.instance_id
	))

	var sandbox: Sandbox = Sandbox.new(battle.get_session(0).engine, ForecastRolls.new())
	for i: int in 2:
		sandbox.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, a0, e0))
	sandbox.engine.drain()
	_check("grants: a forecast grants nothing", (
			sandbox.engine.grants.size() == 1
			and battle.get_session(0).engine.grants.is_empty()
			and recorded.is_empty()
			and run.grants.is_empty()
	))

	battle.submit(AttackFixture.new(0, a0, e0), 0)
	battle.resolve_queued()
	_check("grants: nothing before the effect fires", run.grants.is_empty())
	battle.submit(AttackFixture.new(1, a1, e1), 1)
	battle.resolve_queued()
	var grant: CampaignSession.Grant = null if run.grants.is_empty() else run.grants[0]
	_check("grants: recorded for the owner's seat when it fires", (
			run.grants.size() == 1
			and recorded.size() == 1
			and grant.seat == 0
			and grant.grant == CampaignGrant.Grant.GOLD
			and grant.amount == 50
			and grant.source_effect_id == heirloom.instance_id
			and grant.describe() == "gold 50"
	))
	_check("grants: no diagnostics", battle.get_session(1).engine.diagnostics.is_empty())
	var result: CampaignSession.BattleResult = run.end_battle()
	_check("grants: the battle's grants come with its result", (
			result.grants.size() == 1 and result.grants[0] == grant
	))
	return true


func _test_dropped_grant_not_recorded() -> bool:
	var world: World = World.new()
	var a: String = world.add_unit("Drengr", PLAYER, 0, Vector2i(0, 3))
	# "Hit dealt: gain 1 gold", one reaction per hit.
	var tithe: EffectDefinition = _hit_dealt_block("tithe", 1.0)
	var gold: CampaignGrant = CampaignGrant.new()
	gold.amount = 1
	tithe.operations.assign([gold])
	world.add_trait(a, tithe)
	var received: Array[int] = []
	world.session.grant_received.connect(
			func(_seat: int, _grant: int, amount: int, _id: String, _effect: String) -> void:
				received.append(amount)
	)
	print("    (one error about a step stopped at 256 reactions follows)")
	world.session.submit(HitsFixture.new(0, a, ReactionQueue.MAX_PER_STEP + 1))
	var batch: CombatSession.FactBatch = world.session.resolve_next()
	_check("grants: a reaction dropped by the cap grants nothing", (
			received.size() == ReactionQueue.MAX_PER_STEP
			and world.session.engine.grants.size() == ReactionQueue.MAX_PER_STEP
			and batch.diagnostics.size() == 1
			and batch.diagnostics[0].contains("step stopped")
	), "%d grants" % [received.size()])
	return true


func _test_bridge_restart_rolls_the_same() -> bool:
	var summaries: PackedStringArray = []
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	run.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers)
	var again: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	again.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers)
	for campaign: CampaignSession in [run, run, again]:
		var battle: CombatEncounter = campaign.begin_battle(_request(campaign, {}))
		summaries.append(battle.setup.summary())
		battle.get_session(0).engine.rolls.roll_percent(50)
		campaign.end_battle()
	_check("restart: the same node set up twice in one run gives the same results", (
			summaries[1] == summaries[0]
	))
	_check("restart: a fresh run with the same seed gives the same results", (
			summaries[2] == summaries[0]
	))
	_check("restart: the sessions roll from the registry's COMBAT_ROLLS", (
			run.rng.stream(Battle.rolls_key(0)).capture()
			!= Battle.fresh_stream(RngKey.RngPurpose.COMBAT_ROLLS, 0, -1).capture()
	))
	return true


func _test_bridge_close_mid_battle() -> bool:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var request: CampaignSession.BattleRequest = _request(run, {0: ["Drengr"]})
	var a: String = request.armies[0].units[0].id
	var stubborn: EffectDefinition = _counting("stubborn", EffectDefinition.Lane.CAMPAIGN)
	var counted: EffectInstance = _carrier(run, a, stubborn)
	var closed: Array[CombatEncounter] = []
	run.combat_encounter_closed.connect(
			func(encounter: CombatEncounter) -> void: closed.append(encounter)
	)
	var battle: CombatEncounter = run.begin_battle(request)
	var e: String = _add_enemy(run, battle.get_session(0))
	battle.submit(AttackFixture.new(0, a, e), 0)
	battle.resolve_queued()
	run.close()
	_check("close: a battle in progress is dropped and announced", (
			run.is_closed and run.encounter == null and closed == [battle] and battle.is_closed
	))
	_check("close: nothing is written back", (
			counted.get_counter(EffectDefinition.Lane.CAMPAIGN) == 0
	))
	print("    (one error about beginning a battle on a closed run follows)")
	_check("close: nothing begins again", run.begin_battle(request) == null)
	return true


func _test_service_lifecycle() -> bool:
	var custom_dir: bool = ProjectSettings.get_setting(
			"application/config/use_custom_user_dir", false
	)
	var dir_name: String = ProjectSettings.get_setting(
			"application/config/custom_user_dir_name", ""
	)
	if not custom_dir or not dir_name.contains("test"):
		_skips += 1
		print("SKIP  service lifecycle: needs a test user folder (see the class doc)")
		return true
	var saves: Node = root.get_node(^"SaveService")
	var service: Node = root.get_node(^"CampaignService")
	var activations: Array[String] = []
	var run_ends: Array[int] = []
	var started: Array[CampaignSession] = []
	var ended: Array[CampaignSession] = []
	var on_activated: Callable = func(mode: CampaignData.Mode, resumed: bool) -> void:
		activations.append("%s %s" % [CampaignData.Mode.find_key(mode), resumed])
	var on_run_ended: Callable = func(mode: CampaignData.Mode, _won: bool) -> void:
		run_ends.append(mode)
	var on_started: Callable = func(session: CampaignSession) -> void: started.append(session)
	var on_ended: Callable = func(session: CampaignSession) -> void: ended.append(session)
	saves.connect(&"campaign_activated", on_activated)
	saves.connect(&"run_ended", on_run_ended)
	service.connect(&"session_started", on_started)
	service.connect(&"session_ended", on_ended)
	SaveFile.delete_folder("user://saves/")

	saves.call(&"open_save_file", 1)
	saves.call(&"start_new_solo_run", RUN_SEED)
	var first: CampaignSession = service.get(&"session")
	_check("service: a new run builds a session", (
			first != null
			and first.mode == CampaignData.Mode.SOLO
			and first.rng.run_seed == RUN_SEED
			and first.seats == PackedInt32Array([0])
			and activations == ["SOLO false"]
	), str(activations))
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	_check("service: abandoning tears it down", (
			service.get(&"session") == null and first.is_closed and ended == [first]
	))

	saves.call(&"start_new_solo_run", RUN_SEED)
	var second: CampaignSession = service.get(&"session")
	saves.call(&"close_save_file")
	_check("service: closing the save file tears it down", (
			second != null and second.is_closed and service.get(&"session") == null
	))

	# Closing the save file kept the run in its slot, so it is continued.
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var third: CampaignSession = service.get(&"session")
	_check("service: a continued run builds a session", (
			third != null
			and third.rng.run_seed == RUN_SEED
			and activations[activations.size() - 1] == "SOLO true"
	), str(activations))
	var panel_scene: PackedScene = load("res://scenes/debug/save_debug_panel.tscn")
	var panel: Node = panel_scene.instantiate()
	root.add_child(panel)
	var field: LineEdit = panel.get_node(^"%SeedField")
	var button: Button = panel.get_node(^"%SeedRunButton")
	field.text = RunSeed.format(OTHER_SEED)
	started.clear()
	ended.clear()
	run_ends.clear()
	button.pressed.emit()
	var fourth: CampaignSession = service.get(&"session")
	_check("service: the debug seed restart ends with exactly one live session", (
			third.is_closed
			and fourth != null
			and not fourth.is_closed
			and fourth.rng.run_seed == OTHER_SEED
			and started == [fourth]
			and ended == [third]
			and run_ends == [CampaignData.Mode.SOLO]
	), "%d started, %d ended" % [started.size(), ended.size()])
	panel.free()

	saves.call(&"close_save_file")
	saves.call(&"open_save_file", 1)
	saves.call(&"continue_solo_run")
	var fifth: CampaignSession = service.get(&"session")
	_check("service: the restarted run continues from its seed", (
			fifth != null
			and fourth.is_closed
			and fifth.rng.run_seed == OTHER_SEED
			and activations[activations.size() - 1] == "SOLO true"
	), str(activations))

	var begun: int = service.call(&"begin_battle", _request(fifth, {0: ["Drengr"]}))
	_check("service: a battle begins and is saved", (
			begun == OK and fifth.encounter != null and saves.get(&"combat") != null
	), error_string(begun))
	var result: CampaignSession.BattleResult = service.call(&"end_battle")
	_check("service: the battle ends and is saved", (
			result != null and fifth.encounter == null and saves.get(&"combat") == null
	))

	saves.call(&"clear_campaign")
	_check("service: clearing the campaign tears the session down", (
			fifth.is_closed and service.get(&"session") == null and saves.get(&"campaign") == null
	))
	var steam_ids: PackedInt64Array = [76561198000000001, 76561198000000002]
	saves.call(&"start_new_multiplayer_run", steam_ids)
	var hosted: CampaignSession = service.get(&"session")
	var loaded: int = saves.call(&"load_multiplayer_campaign")
	_check("service: loading a multiplayer campaign tears the session down", (
			hosted != null
			and hosted.seats == PackedInt32Array([0, 1])
			and hosted.is_closed
			and service.get(&"session") == null
			and loaded == OK
	), error_string(loaded))

	saves.call(&"abandon_run", CampaignData.Mode.MULTIPLAYER)
	saves.call(&"abandon_run", CampaignData.Mode.SOLO)
	saves.call(&"close_save_file")
	saves.disconnect(&"campaign_activated", on_activated)
	saves.disconnect(&"run_ended", on_run_ended)
	service.disconnect(&"session_started", on_started)
	service.disconnect(&"session_ended", on_ended)
	SaveFile.delete_folder("user://saves/")
	return true


func _test_logger_gating() -> bool:
	_set_log_level(LOG_WARN)
	_check("logging: lines below the level build nothing", (
			CombatSession.logger(DEBUG_LEVEL, COMBAT_CATEGORY) == null
			and CombatSession.logger(INFO_LEVEL, COMBAT_CATEGORY) == null
	))
	_check("logging: lines at or above the level print", (
			CombatSession.logger(WARN_LEVEL, COMBAT_CATEGORY) != null
			and CombatSession.logger(ERROR_LEVEL, EFFECTS_CATEGORY) != null
	))
	_set_log_level(LOG_DEBUG)
	_check("logging: DEBUG prints when asked for", (
			CombatSession.logger(DEBUG_LEVEL, EFFECTS_CATEGORY) != null
	))
	_set_log_level(LOG_WARN)
	return true


func _test_logging_changes_nothing() -> bool:
	var quiet: PackedStringArray = _scripted_battle(false)
	_set_log_level(LOG_DEBUG)
	print("    (DEBUG lines follow: a co-op battle with every log path and the draw trace)")
	var loud: PackedStringArray = _scripted_battle(true)
	_set_log_level(LOG_WARN)
	_check("logging: every level and the draw trace change no result", (
			quiet.size() > 20 and loud == quiet
	), "%d and %d lines" % [quiet.size(), loud.size()])
	return true


# A scripted co-op battle through the bridge: setup with loot, a cross-map heirloom that grants
# gold, rolls, a rejected command, a catch-up gap and a transfer. Returns every result as text:
# both maps' facts, the encounter's facts, the setup and the grants.
func _scripted_battle(is_tracing: bool) -> PackedStringArray:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.MULTIPLAYER, RUN_SEED, PackedInt32Array([0, 1])
	)
	run.is_tracing_draws = is_tracing
	run.add_setup_step(CombatEncounter.SetupStep.CONTAINER_CONTENTS, Battle.fill_containers)
	var request: CampaignSession.BattleRequest = _request(
			run, {0: ["Drengr", "Archer"], 1: ["Hakkapel"]}
	)
	var a0: String = request.armies[0].units[0].id
	var b0: String = request.armies[0].units[1].id
	var a1: String = request.armies[1].units[0].id
	var purse: EffectDefinition = _every_hit_by_allies(2)
	var gold: CampaignGrant = CampaignGrant.new()
	gold.amount = 50
	purse.operations.assign([gold])
	run.add_carrier(EffectInstance.new(
			run.ids.next_effect_id(),
			purse,
			EffectOwner.for_army(InstanceIdAllocator.seat_subject_id(0), 0),
			Modifier.SourceKind.HEIRLOOM
	))
	var battle: CombatEncounter = run.begin_battle(request)
	var s0: CombatSession = battle.get_session(0)
	var s1: CombatSession = battle.get_session(1)
	var e0: String = _add_enemy(run, s0)
	var e1: String = _add_enemy(run, s1)
	for i: int in 3:
		battle.submit(RollFixture.new(0, a0, e0), 0)
		battle.submit(AttackFixture.new(1, a1, e1), 1)
	battle.submit(MoveFixture.new(1, a0, Vector2i(2, 2)), 0)
	battle.resolve_queued()
	s0.mark_checkpoint()
	s0.facts_since(1)
	battle.submit(EndMapFixture.new(), 0)
	battle.resolve_queued()
	battle.send_unit(b0, 0, 1, Vector2i(1, 3))
	battle.deliver_arrivals(1)

	var lines: PackedStringArray = [battle.setup.summary()]
	for session: CombatSession in [s0, s1]:
		for fact: CombatFact in session.engine.fact_log:
			lines.append(fact.to_log_line())
		for record: RollRecord in session.engine.rolls.records:
			lines.append("roll %d %d" % [record.value, record.outcome])
	for fact: CombatFact in battle.fact_log:
		lines.append("e %s" % [fact.to_log_line()])
	for grant: CampaignSession.Grant in run.grants:
		lines.append(grant.describe())
	run.end_battle()
	return lines


# A battle request on the fixture map: each seat's army from its unit types, in roster order.
func _request(run: CampaignSession, types_by_seat: Dictionary) -> CampaignSession.BattleRequest:
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = Battle.pool(["map_a"])
	# Untyped: callers pass dictionary literals, which are untyped.
	for seat: Variant in types_by_seat:
		var army: CampaignSession.Army = CampaignSession.Army.new()
		var types: Array = types_by_seat[seat]
		for unit_type: Variant in types:
			var unit: CombatUnitState = CombatUnitState.new()
			unit.id = run.ids.next_unit_id(unit_type as String)
			unit.seat = seat as int
			unit.unit_type = unit_type as String
			unit.hp = 20
			army.units.append(unit)
			army.bases[unit.id] = Battle.unit_bases()
		request.armies[seat as int] = army
	return request


# Adds [param definition] to the run as a trait of [param unit_id] (seat 0). Returns the carrier.
func _carrier(
		run: CampaignSession, unit_id: String, definition: EffectDefinition
) -> EffectInstance:
	var instance: EffectInstance = EffectInstance.new(
			run.ids.next_effect_id(),
			definition,
			EffectOwner.for_unit(unit_id, 0, PLAYER),
			Modifier.SourceKind.UNIT_TRAIT
	)
	run.add_carrier(instance)
	return instance


# "Hit dealt: count toward 100 in [param lane]" — a counter that never passes in these cases.
func _counting(id: String, lane: EffectDefinition.Lane) -> EffectDefinition:
	var definition: EffectDefinition = _hit_dealt_block(id, 1.0, 100)
	var counter: CounterCondition = definition.conditions[0] as CounterCondition
	counter.lane = lane
	return definition


func _add_enemy(run: CampaignSession, session: CombatSession) -> String:
	var enemy: CombatUnitState = CombatUnitState.new()
	enemy.id = run.ids.next_enemy_id("Brute")
	enemy.side = ENEMY
	enemy.tile = Vector2i(3, 2)
	enemy.hp = 20
	session.add_unit(enemy, Battle.unit_bases())
	return enemy.id


func _layout_has_deployment(session: CombatSession, tile: Vector2i) -> bool:
	return session.layout.tiles_of(MapLayout.MarkerKind.DEPLOYMENT).has(tile)


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


# Runs one case. A script error aborts a case without failing a check, so each case returns true
# at its end and a case that doesn't is reported.
func _run(test: Callable) -> void:
	var finished: Variant = test.call()
	if not (finished is bool and finished as bool):
		_check("%s ran to its end" % [test.get_method()], false)


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


# Records [member count] hits by its unit in one command, so one step queues that many reactions.
class HitsFixture:
	extends Command

	var count: int = 0

	func _init(sender: int, unit_id: String, hits: int) -> void:
		seat = sender
		actor_id = unit_id
		count = hits

	func resolve(session: CombatSession) -> void:
		for i: int in count:
			session.engine.record(CombatFact.new(CombatFact.Kind.HIT_DEALT, actor_id))


# Ends the map's combat as the objectives check will (P04 MP4), naming the side that won.
class EndMapFixture:
	extends Command

	var winner: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER

	func _init(winning_side: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER) -> void:
		winner = winning_side

	func resolve(session: CombatSession) -> void:
		var ended: CombatFact = CombatFact.new(CombatFact.Kind.COMBAT_ENDED)
		ended.side = winner
		session.engine.record(ended)


# Defeats [member unit_id] through CombatState.defeat: a step that ends a map by its objective.
class DefeatFixture:
	extends Command

	var unit_id: String = ""

	func _init(defeated_id: String) -> void:
		unit_id = defeated_id

	func resolve(session: CombatSession) -> void:
		session.state.defeat(session.engine, unit_id, "")
