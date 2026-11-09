# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     queue_cases.gd
# Author:
# Created:  November 9, 2026
# Modified: November 9, 2026
# ==============================================================================

extends "res://tests/sessions/sessions_case_base.gd"
## Session queue cases for tests/sessions/run_all.gd: [InstanceIdAllocator], [Command] and the
## queue, [CombatSession], [FactPlayback] and [PresentationRequest].


func run() -> void:
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
	var first: CombatFact = batches[0].facts[0]
	var expected: String = "stale forecast (s0#%d %s after s0#%d)" % [
		first.seq, CombatFact.Kind.find_key(first.kind), forecast_seq,
	]

	_check("stale: the partner's attack resolves", not batches[0].is_rejected())
	_check(
			"stale: an attack after any fact since its forecast is rejected, naming the first",
			batches[1].rejected_reason == expected,
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


func _facts(kinds: Array[CombatFact.Kind]) -> Array[CombatFact]:
	var facts: Array[CombatFact] = []
	for kind: CombatFact.Kind in kinds:
		facts.append(CombatFact.new(kind))
	return facts


func _seqs(facts: Array[CombatFact]) -> String:
	var parts: PackedStringArray = []
	for fact: CombatFact in facts:
		parts.append(str(fact.seq))
	return " ".join(parts)


# A contested object that isn't a map object yet (P04 MP6): open or not.
class FixtureChest:
	extends RefCounted

	var id: String = ""
	var tile: Vector2i = Vector2i.ZERO
	var is_open: bool = false

	func _init(chest_id: String, chest_tile: Vector2i) -> void:
		id = chest_id
		tile = chest_tile


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


# Raises an engine diagnostic, standing in for a content error found while resolving.
class DiagnosticFixture:
	extends Command

	var problem: String = ""

	func _init(text: String) -> void:
		problem = text

	func resolve(session: CombatSession) -> void:
		if not problem.is_empty():
			session.engine.diagnostics.append(problem)
