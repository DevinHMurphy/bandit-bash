# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     sandbox_cases.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

extends "res://tests/effects/golden_cases.gd"
## The roll sources, the sandbox, ExchangeOutcome and worker-thread cases, for
## tests/effects/run_all.gd. Shares the fixtures and helpers of golden_cases.gd.

# Draws per Hit value when checking LiveRolls against the exact 2RN odds.
const DRAWS: int = 100000

# Records kept before clearing them, so a long draw doesn't hold 10^5 records.
const RECORD_BATCH: int = 1000

# Allowed distance of a measured rate from its probability, in standard deviations.
const SIGMAS: float = 4.0

# Stream seed for the live-roll cases; any fixed value works.
const LIVE_SEED: int = 0x5EED

# Branch budget for the enumeration cases: far above what their exchanges need.
const BUDGET: int = 4096


## A result slot written by one worker thread only.
class Slot:
	extends RefCounted

	## The candidate's summary.
	var text: String = ""


func run() -> void:
	_test_2rn_probability_table()
	_test_live_rolls_match_the_odds()
	_test_live_rolls_draw_only_their_stream()
	_test_forecast_rolls()
	_test_sampled_rolls_repeat()
	_test_sandbox_refuses_live_rolls()
	_test_sandbox_purity()
	_test_forced_forecast_equals_real()
	_test_outcome_kill_odds()
	_test_outcome_momentum_branch()
	_test_worker_threads_match()


func _test_2rn_probability_table() -> void:
	var expected: Dictionary[int, float] = {
		0: 0.0, 1: 3.0 / 10000.0, 50: 5050.0 / 10000.0, 99: 9999.0 / 10000.0, 100: 1.0,
	}
	var wrong: PackedStringArray = []
	for hit: int in expected:
		if RollSource.hit_2rn_probability(hit) != expected[hit]:
			wrong.append("%d: %s" % [hit, RollSource.hit_2rn_probability(hit)])
	_ok(
			"2RN: reported odds are the exact two-roll counts at 0, 1, 50, 99, 100",
			wrong.is_empty(), str(wrong)
	)


func _test_live_rolls_match_the_odds() -> void:
	var wrong: PackedStringArray = []
	for hit: int in [0, 1, 50, 99, 100]:
		var rolls: LiveRolls = LiveRolls.new(RngStream.new(LIVE_SEED + hit))
		var hits: int = 0
		for i: int in DRAWS:
			if rolls.roll_hit_2rn(hit):
				hits += 1
			if rolls.records.size() >= RECORD_BATCH:
				rolls.records.clear()
		var p: float = RollSource.hit_2rn_probability(hit)
		var rate: float = hits / float(DRAWS)
		var allowed: float = SIGMAS * sqrt(p * (1.0 - p) / DRAWS)
		if absf(rate - p) > allowed:
			wrong.append("%d: %s vs %s" % [hit, rate, p])
	_ok("2RN: 10^5 live draws per Hit match the reported odds", wrong.is_empty(), str(wrong))


func _test_live_rolls_draw_only_their_stream() -> void:
	var used: RngStream = RngStream.new(LIVE_SEED)
	var other: RngStream = RngStream.new(LIVE_SEED)
	var by_hand: RngStream = RngStream.new(LIVE_SEED)
	var before: String = other.capture()
	var rolls: LiveRolls = LiveRolls.new(used)
	rolls.roll_hit_2rn(70)
	rolls.roll_percent(25)
	rolls.pick_index(3)
	rolls.pick_index(1)
	# Two d100 for the hit, one for the percent roll, one for the pick of 3, none for the pick of 1.
	for i: int in 4:
		by_hand.randi_range(0, 99 if i < 3 else 2)
	_ok(
			"live rolls: draw only from their own stream, as many draws as documented",
			other.capture() == before and used.capture() == by_hand.capture()
	)


func _test_forecast_rolls() -> void:
	var rolls: ForecastRolls = ForecastRolls.new()
	_ok(
			"forecast rolls: hits land, chances fail, picks take the first",
			rolls.roll_hit_2rn(40) and not rolls.roll_percent(90) and rolls.pick_index(4) == 0
	)
	_ok(
			"forecast rolls: every probability is still reported",
			is_equal_approx(rolls.records[0].probability, RollSource.hit_2rn_probability(40))
			and is_equal_approx(rolls.records[1].probability, 0.9)
	)


func _test_sampled_rolls_repeat() -> void:
	var candidate: Array = ["enemy:4", Vector2i(3, 5), "unit:7", "item:9"]
	var first: SampledRolls = SampledRolls.new(143, candidate)
	var again: SampledRolls = SampledRolls.new(143, candidate)
	var moved: SampledRolls = SampledRolls.new(143, ["enemy:4", Vector2i(3, 6), "unit:7", "item:9"])
	var later: SampledRolls = SampledRolls.new(144, candidate)
	var draws: PackedStringArray = ["", "", "", ""]
	var sources: Array[SampledRolls] = [first, again, moved, later]
	for i: int in sources.size():
		for roll: int in 40:
			draws[i] += "1" if sources[i].roll_hit_2rn(50) else "0"
	_ok("sampled rolls: the same seq and candidate give the same draws", draws[0] == draws[1])
	_ok(
			"sampled rolls: another tile or seq gives other draws",
			draws[0] != draws[2] and draws[0] != draws[3]
	)
	_ok(
			"sampled rolls: the seed is RngKey.mix() of the parts",
			SampledRolls.seed_for(143, [5, Vector2i(1, 2)]) == RngKey.mix([143, 5, 1, 2])
	)


func _test_sandbox_refuses_live_rolls() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	var stream: RngStream = RngStream.new(LIVE_SEED)
	var before: String = stream.capture()
	var sandbox: Sandbox = Sandbox.new(engine, LiveRolls.new(stream))
	_harness(sandbox.engine).exchange("p1", "e1", "ad")
	_ok(
			"sandbox: a live roll source is refused, its stream untouched",
			sandbox.engine.rolls is ForecastRolls and stream.capture() == before
			and sandbox.engine.diagnostics.size() == 1
	)


func _test_sandbox_purity() -> void:
	var stream: RngStream = RngStream.new(LIVE_SEED)
	var engine: EffectEngine = _live_battle(stream)
	_harness(engine).phase_start(PLAYER)
	_harness(engine).exchange("p1", "e1", "ad")
	var momentum: EffectInstance = engine.get_instance("effect:mo")
	var before: PackedStringArray = _fingerprint(engine, stream)
	for i: int in 6:
		var rolls: RollSource = ForecastRolls.new()
		if i % 3 == 1:
			rolls = ForcedRolls.new(PackedInt32Array([0, 1, 0, 1]))
		elif i % 3 == 2:
			rolls = SampledRolls.new(engine.fact_log.size(), ["p2", Vector2i(1, 0), "e1", ""])
		var sandbox: Sandbox = Sandbox.new(engine, rolls)
		var harness: FakeExchange = _harness(sandbox.engine)
		harness.exchange("p2", "e1", "aad")
		harness.phase_end(PLAYER)
		harness.phase_start(ENEMY_SIDE)
		_ok("sandbox %d: resolved facts of its own" % [i], not sandbox.facts().is_empty())
	_same(
			"sandbox: real state, stream, log and counters unchanged",
			"\n".join(_fingerprint(engine, stream)), "\n".join(before)
	)
	_ok(
			"sandbox: the real instance is not the copy's",
			momentum == engine.get_instance("effect:mo")
	)


func _test_forced_forecast_equals_real() -> void:
	var stream: RngStream = RngStream.new(LIVE_SEED + 1)
	var engine: EffectEngine = _live_battle(stream)
	var before: Sandbox = Sandbox.new(engine, ForecastRolls.new())
	var start: int = engine.fact_log.size()
	var real: FakeExchange = _harness(engine)
	real.exchange("p1", "e1", "aad")
	real.exchange("e1", "p2", "ad")
	var outcomes: PackedInt32Array = []
	for record: RollRecord in engine.rolls.records:
		outcomes.append(record.outcome)

	var replay: Sandbox = Sandbox.new(before.engine, ForcedRolls.new(outcomes))
	var forecast: FakeExchange = _harness(replay.engine)
	forecast.exchange("p1", "e1", "aad")
	forecast.exchange("e1", "p2", "ad")
	var real_lines: PackedStringArray = []
	for i: int in range(start, engine.fact_log.size()):
		real_lines.append(engine.fact_log[i].to_log_line())
	var forecast_lines: PackedStringArray = []
	for fact: CombatFact in replay.facts():
		forecast_lines.append(fact.to_log_line())
	_ok(
			"forecast: ForcedRolls with the real outcomes give the real facts, seq included",
			not real_lines.is_empty() and forecast_lines == real_lines,
			"\n\t" + "\n\t".join(forecast_lines) + "\n\tvs\n\t" + "\n\t".join(real_lines)
	)


func _test_outcome_kill_odds() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	engine.set_base("p1", CombatValue.Key.HIT, 70.0)
	engine.set_base("e1", CombatValue.Key.HIT, 60.0)
	_fake(engine).unit("e1").hp = 8
	_fake(engine).unit("p1").hp = 4
	var outcome: ExchangeOutcome = ExchangeOutcome.enumerate(
			_resolver(engine, "p1", "e1", "ada"), BUDGET
	)
	# p1 needs both its hits (4 damage each, e1 has 8 HP); e1's one counter hit defeats p1 first.
	var p: float = RollSource.hit_2rn_probability(70)
	var q: float = RollSource.hit_2rn_probability(60)
	_ok(
			"outcome: kill odds are the hand-computed 2RN odds (hit, counter misses, hit)",
			is_equal_approx(outcome.kill_probability, p * (1.0 - q) * p),
			outcome.to_text()
	)
	_ok("outcome: death odds are the counter's hit", is_equal_approx(outcome.death_probability, q))
	_ok(
			"outcome: every branch enumerated, probabilities sum to 1",
			outcome.complete and is_equal_approx(outcome.total_probability, 1.0)
	)
	_ok(
			"outcome: expected damage and maximum",
			is_equal_approx(outcome.expected_dealt_hp, 4.0 * p + 4.0 * p * (1.0 - q))
			and outcome.max_damage == 8
			and is_equal_approx(outcome.expected_damage_before_defeat, 4.0 * p)
	)
	var partial: ExchangeOutcome = ExchangeOutcome.enumerate(
			_resolver(engine, "p1", "e1", "ada"), 2
	)
	_ok(
			"outcome: a budget stops the enumeration",
			not partial.complete and partial.branch_count == 2
	)
	_clean("outcome kill odds", engine)


func _test_outcome_momentum_branch() -> void:
	var engine: EffectEngine = _battle(["p1", "e1"])
	engine.register(_instance("effect:mo", _momentum(), _owner("p1"), TRAIT, "Momentum"))
	var shown: Array[String] = []
	var trace: Callable = func(sandbox: Sandbox) -> void:
		var hits: PackedStringArray = []
		for record: RollRecord in sandbox.roll_records():
			if record.kind == RollRecord.Kind.HIT_2RN:
				hits.append("%d%s" % [record.value, "h" if record.succeeded() else "m"])
		shown.append(",".join(hits))
	ExchangeOutcome.enumerate(_resolver(engine, "p1", "e1", "a", 2, trace), BUDGET)
	_ok(
			"outcome: after a miss, the branch's next exchange shows Momentum's +15",
			shown.has("80m,95h") and shown.has("80m,95m") and shown.has("80h,80h"),
			str(shown)
	)


func _test_worker_threads_match() -> void:
	var stream: RngStream = RngStream.new(LIVE_SEED + 2)
	var engine: EffectEngine = _live_battle(stream)
	var candidates: Array = [
		["p1", "e1", "ada"], ["p2", "e1", "aad"], ["p1", "e2", "aa"], ["p2", "e2", "ad"],
		["e1", "p2", "ad"], ["e2", "p1", "aad"],
	]
	var single: PackedStringArray = []
	for candidate: Array in candidates:
		single.append(_evaluate(Sandbox.new(engine, ForecastRolls.new()).engine, candidate))

	# Each worker gets a sandbox made here, on the main thread, and touches nothing else.
	var bases: Array[EffectEngine] = []
	var slots: Array[Slot] = []
	for candidate: Array in candidates:
		bases.append(Sandbox.new(engine, ForecastRolls.new()).engine)
		slots.append(Slot.new())
	var task: Callable = func(index: int) -> void:
		slots[index].text = _evaluate(bases[index], candidates[index] as Array)
	var group: int = WorkerThreadPool.add_group_task(task, candidates.size())
	WorkerThreadPool.wait_for_group_task_completion(group)
	var pooled: PackedStringArray = []
	for slot: Slot in slots:
		pooled.append(slot.text)
	_ok(
			"threads: candidates on WorkerThreadPool match the single-threaded results",
			pooled == single and not single[0].is_empty(),
			"\n\t" + "\n\t".join(pooled) + "\n\tvs\n\t" + "\n\t".join(single)
	)


# --- Helpers -------------------------------------------------------------------------------------


# A battle resolved with LiveRolls over `stream`, with Momentum, Cleave and Iron Heart registered.
func _live_battle(stream: RngStream) -> EffectEngine:
	var engine: EffectEngine = _battle(["p1", "p2", "e1", "e2"])
	engine.rolls = LiveRolls.new(stream)
	var seventh: CounterCondition = CounterCondition.new()
	seventh.count = 3
	var iron_heart: EffectDefinition = _definition(
			EffectDefinition.Trigger.ATTACK_MADE, [seventh], [_lifesteal()]
	)
	iron_heart.scope = YOUR_UNIT
	engine.register(_instance("effect:mo", _momentum(), _owner("p1"), TRAIT, "Momentum"))
	engine.register(_instance("effect:cl", _cleave(), _owner("e1"), TRAIT, "Cleave"))
	engine.register(_instance("effect:ih", iron_heart, _army(), HEIRLOOM, "Iron Heart"))
	return engine


# What a sandbox must never change in the real session: map, log, stream, counters, timed
# modifiers, waiting reactions and diagnostics.
func _fingerprint(engine: EffectEngine, stream: RngStream) -> PackedStringArray:
	var counters: PackedStringArray = []
	for instance: EffectInstance in engine.get_instances():
		counters.append("%s %d/%d/%d" % [
			instance.instance_id, instance.get_counter(EffectDefinition.Lane.COMBAT),
			instance.get_counter(EffectDefinition.Lane.CAMPAIGN), instance.charges_left,
		])
	return PackedStringArray([
		_fake(engine).summary(),
		"facts %d, last %s" % [engine.fact_log.size(), engine.fact_log[-1].to_log_line()],
		"stream %s, rolls %d" % [stream.capture(), engine.rolls.records.size()],
		", ".join(counters),
		"timed %d, waiting %d, diagnostics %d" % [
			engine.get_timed_modifiers("p1").size(), engine.pending_reactions(),
			engine.diagnostics.size(),
		],
	])


# A resolver for ExchangeOutcome.enumerate: each branch runs `exchanges` exchanges of `order` in
# its own sandbox of `base`, and reports the attacker's and defender's losses. `trace`, if valid,
# is called with each branch's sandbox.
func _resolver(
		base: EffectEngine,
		attacker: String,
		defender: String,
		order: String,
		exchanges: int = 1,
		trace: Callable = Callable()
) -> Callable:
	return func(rolls: ForcedRolls) -> ExchangeOutcome.Branch:
		var sandbox: Sandbox = Sandbox.new(base, rolls)
		var state: SandboxState = sandbox.engine.state
		var defender_hp: int = state.get_hp(defender)
		var defender_block: int = state.get_block(defender)
		var attacker_hp: int = state.get_hp(attacker)
		var attacker_block: int = state.get_block(attacker)
		var harness: FakeExchange = FakeExchange.new(sandbox.engine)
		for i: int in exchanges:
			if state.has_unit(attacker) and state.has_unit(defender):
				harness.exchange(attacker, defender, order)
		var branch: ExchangeOutcome.Branch = ExchangeOutcome.Branch.new()
		branch.attacker_defeated = not state.has_unit(attacker)
		branch.defender_defeated = not state.has_unit(defender)
		branch.dealt_hp = defender_hp - state.get_hp(defender)
		branch.dealt_block = maxi(defender_block - state.get_block(defender), 0)
		branch.taken_hp = attacker_hp - state.get_hp(attacker)
		branch.taken_block = maxi(attacker_block - state.get_block(attacker), 0)
		branch.defender_exposed = state.get_stance(defender) == 0
		branch.diagnostics = sandbox.engine.diagnostics
		if trace.is_valid():
			trace.call(sandbox)
		return branch


# One candidate's summary: its exact outcome, then 8 sampled runs seeded by the candidate.
func _evaluate(base: EffectEngine, candidate: Array) -> String:
	var attacker: String = candidate[0]
	var defender: String = candidate[1]
	var order: String = candidate[2]
	var outcome: ExchangeOutcome = ExchangeOutcome.enumerate(
			_resolver(base, attacker, defender, order), BUDGET
	)
	var sampled: PackedStringArray = []
	for run_index: int in 8:
		var rolls: SampledRolls = SampledRolls.new(base.fact_log.size() + run_index, candidate)
		var sandbox: Sandbox = Sandbox.new(base, rolls)
		FakeExchange.new(sandbox.engine).exchange(attacker, defender, order)
		sampled.append(str(sandbox.engine.state.get_hp(defender)))
	return "%s | sampled %s" % [outcome.to_text(), ",".join(sampled)]
