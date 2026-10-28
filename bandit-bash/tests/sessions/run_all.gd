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
## [CombatSession], [FactPlayback] and [PresentationRequest].
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


# Ends the map's combat, as the objectives check will (P04 MP4).
class EndMapFixture:
	extends Command

	func resolve(session: CombatSession) -> void:
		session.engine.record(CombatFact.new(CombatFact.Kind.COMBAT_ENDED))
