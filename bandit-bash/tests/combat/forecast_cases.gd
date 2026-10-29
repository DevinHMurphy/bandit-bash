# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_cases.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

extends RefCounted
## [CombatForecast]'s cases for tests/combat/run_all.gd: the forecast equals execution over 1,000
## seeded exchanges (combat core plan, Verification), the AI summary's probabilities sum to 1, a
## forecast never changes the real state, each side's numbers and a hit's breakdown (inline "that
## hit" changes included, matching the real hit's), chance-gated effects listed apart, staff
## previews (range 0 included) and shove previews equal their results, an illegal preview gives the
## command's own rejection, and the stale rule: any fact since the forecast makes an attack, staff
## or shove stale, never a move.
##
## Each case runs a real [CombatSession] on a small hand-built map, so the real side of every
## comparison is the command resolving through the session's queue. Every case also asserts that
## the engines reported no diagnostics.

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: UnitTurnCommand.Action = UnitTurnCommand.Action.ATTACK
const STAFF: UnitTurnCommand.Action = UnitTurnCommand.Action.STAFF
const SHOVE: UnitTurnCommand.Action = UnitTurnCommand.Action.SHOVE

# The seed of the fixtures; each seeded exchange draws its fixture from SEED + index and rolls its
# combat from a stream seeded SEED - 1 - index.
const SEED: int = 20261029

# Seeded exchanges compared with execution (combat core plan, Verification: 1,000).
const EXCHANGES: int = 1000

# Every this many seeded exchanges also checks the AI summary, which costs a sandbox per branch.
const OUTCOME_EVERY: int = 50

# Branch runs for an exact summary; one that needs more is checked only for being partial.
const BRANCH_BUDGET: int = 32

# Samples for a sampled summary.
const SAMPLES: int = 16

# Allowed float error in a probability sum.
const PROBABILITY_TOLERANCE: float = 1e-9

# Percent of seeded exchanges with each feature, so every path through the forecast is covered.
const WALK_PERCENT: int = 70
const SIDEARM_PERCENT: int = 20
const CLEAVE_PERCENT: int = 30
const MOMENTUM_PERCENT: int = 30
const LIFESTEAL_PERCENT: int = 20
const DOUBLE_HIT_PERCENT: int = 15

# The defender's column in a seeded exchange; the attacker walks along its row toward it.
const DEFENDER_X: int = 5

# 7 × 5: plain, with forest at (3, 1) and (5, 3), so origin and defender tiles vary in avoid.
const ROWS: Array[String] = [
	"plain plain plain plain plain plain plain",
	"plain plain plain forest plain plain plain",
	"plain plain plain plain plain plain plain",
	"plain plain plain plain plain forest plain",
	"plain plain plain plain plain plain plain",
]

# 7 × 3 for shoves: oil at (2, 1) and (3, 1), a spiked wall at (5, 2).
const SHOVE_ROWS: Array[String] = [
	"plain plain plain plain plain plain plain",
	"plain plain spilled_oil spilled_oil plain plain plain",
	"plain plain plain plain plain spiked_wall plain",
]

# Weapon presets, from game-vision.md's Simple weapons and weapons.md's staves. Columns: damage,
# AtkX, profile, range min, range max, Hit, CritX, weight, staff kind, staff amount.
const WEAPONS: Dictionary[String, Array] = {
	"sword": [5, 1, WeaponTriangle.Profile.NIMBLE, 1, 1, 80, 3.0, 8, 0, 0],
	"axe": [10, 1, WeaponTriangle.Profile.POWER, 1, 1, 65, 3.0, 15, 0, 0],
	"lance": [7, 1, WeaponTriangle.Profile.BALANCE, 1, 1, 80, 3.0, 12, 0, 0],
	"bow": [6, 1, WeaponTriangle.Profile.NONE, 2, 3, 100, 3.0, 5, 0, 0],
	"gauntlets": [2, 2, WeaponTriangle.Profile.NONE, 1, 1, 100, 2.0, 1, 0, 0],
	"dagger": [2, 1, WeaponTriangle.Profile.NIMBLE, 1, 2, 100, 5.0, 3, 0, 0],
	"fire": [5, 1, WeaponTriangle.Profile.BALANCE, 1, 2, 80, 3.0, 1, 0, 0],
	"harm": [15, 1, WeaponTriangle.Profile.NONE, 1, 2, 100, 3.0, 10, 3, 0],
	"shelter": [0, 1, WeaponTriangle.Profile.NONE, 1, 1, 0, 3.0, 0, 1, 3],
	"minor_heal": [0, 1, WeaponTriangle.Profile.NONE, 1, 1, 0, 3.0, 0, 2, 5],
	"everwall": [0, 1, WeaponTriangle.Profile.NONE, 0, 0, 0, 3.0, 0, 1, 5],
}

# What a seeded attacker may hold; the defender may also hold a Block staff, which never counters.
const ATTACKER_WEAPONS: Array[String] = [
	"sword", "axe", "lance", "bow", "gauntlets", "dagger", "fire", "harm",
]
const DEFENDER_WEAPONS: Array[String] = [
	"sword", "axe", "lance", "bow", "gauntlets", "dagger", "fire", "shelter",
]

var _check: Callable
var _grid: MapGrid = null
var _shove_grid: MapGrid = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_grid = _grid_of(ROWS)
	_shove_grid = _grid_of(SHOVE_ROWS)


## Runs every case.
func run() -> void:
	_test_forecast_equals_execution()
	_test_outcome_kill_odds()
	_test_side_numbers()
	_test_breakdown()
	_test_inline_breakdown()
	_test_chance_lines()
	_test_staff_previews()
	_test_range_zero_staff()
	_test_shove_previews()
	_test_rejections_match()
	_test_stale_rule()


# 1,000 seeded exchanges, each forecast on the session, then sent as a command: the forecast
# changes nothing; with the real rolls forced it gives the executed facts, seq included, and the
# executed state; with its own rolls it equals execution whenever the real rolls matched them;
# every 50th also checks that the AI summary's probabilities sum to 1.
func _test_forecast_equals_execution() -> void:
	var mismatched: PackedStringArray = []
	var impure: PackedStringArray = []
	var illegal: PackedStringArray = []
	var stages_wrong: PackedStringArray = []
	var plain_wrong: PackedStringArray = []
	var sums_wrong: PackedStringArray = []
	var noisy: PackedStringArray = []
	var plain_matches: int = 0
	var summaries: int = 0
	var coverage: Dictionary[String, int] = {
		"crit": 0, "defeat": 0, "walk": 0, "sidearm": 0, "inline": 0, "no counter": 0,
	}
	for index: int in EXCHANGES:
		var trial: Trial = _exchange_trial(index)
		var field: Field = trial.field
		var engine: EffectEngine = field.engine()
		var before: String = _fingerprint(field)
		var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				engine, trial.command
		)
		if not forecast.is_legal:
			illegal.append("#%d %s" % [index, forecast.reason])
			continue
		if forecast.based_on_seq != field.session.last_seq():
			mismatched.append("#%d based on %d, last seq %d" % [
				index, forecast.based_on_seq, field.session.last_seq(),
			])
		if index % OUTCOME_EVERY == 0:
			summaries += 1
			var problem: String = _summary_problem(field, trial.command)
			if not problem.is_empty():
				sums_wrong.append("#%d %s" % [index, problem])
		if _fingerprint(field) != before:
			impure.append("#%d" % [index])

		var snapshot: Sandbox = Sandbox.new(engine, ForecastRolls.new())
		var first_roll: int = engine.rolls.records.size()
		trial.command.based_on_seq = forecast.based_on_seq
		var batch: CombatSession.FactBatch = field.send(trial.command)
		if batch.is_rejected():
			illegal.append("#%d rejected: %s" % [index, batch.rejected_reason])
			continue
		var outcomes: PackedInt32Array = []
		var as_forecast: bool = true
		for i: int in range(first_roll, engine.rolls.records.size()):
			var record: RollRecord = engine.rolls.records[i]
			outcomes.append(record.outcome)
			var guess: int = 1 if record.kind == RollRecord.Kind.HIT_2RN else 0
			as_forecast = as_forecast and record.outcome == guess
		var replay: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				snapshot.engine, trial.command, ForcedRolls.new(outcomes)
		)
		var real_lines: Array[String] = _lines(batch.facts)
		var problem_text: String = _units_problem(replay, field.state())
		if _lines(replay.facts) != real_lines or not problem_text.is_empty():
			mismatched.append("#%d %s\n\t%s\n\tvs\n\t%s" % [
				index, problem_text, "\n\t".join(_lines(replay.facts)), "\n\t".join(real_lines),
			])
		if as_forecast:
			plain_matches += 1
			if _lines(forecast.facts) != real_lines:
				plain_wrong.append("#%d" % [index])
		for attack: CombatForecast.AttackForecast in replay.attacks:
			if attack.is_crit:
				coverage["crit"] += 1
			if attack.defeated:
				coverage["defeat"] += 1
			if attack.is_hit and attack.breakdown.stages.damage != attack.damage:
				stages_wrong.append("#%d attack %d: %s, dealt %d" % [
					index, attack.index, attack.breakdown.to_text(), attack.damage,
				])
		if trial.has_inline:
			coverage["inline"] += 1
		if trial.command.path.size() > 1:
			coverage["walk"] += 1
		if not trial.command.weapon_id.is_empty():
			coverage["sidearm"] += 1
		if not replay.can_counter:
			coverage["no counter"] += 1
		for diagnostics: PackedStringArray in [
			engine.diagnostics, forecast.diagnostics, replay.diagnostics,
		]:
			if not diagnostics.is_empty():
				noisy.append("#%d %s" % [index, diagnostics])

	_ok("forecast = execution: every seeded fixture is legal", illegal.is_empty(), _first(illegal))
	_ok(
			"forecast = execution: %d seeded exchanges, real rolls forced" % [EXCHANGES],
			mismatched.is_empty(),
			_first(mismatched)
	)
	_ok(
			"forecast: changes no real state, stream, counter or log (%d forecasts)" % [EXCHANGES],
			impure.is_empty(),
			_first(impure)
	)
	_ok(
			"forecast: with its own rolls equals execution when those were the real ones (%d)"
			% [plain_matches],
			plain_matches > 0 and plain_wrong.is_empty(),
			_first(plain_wrong)
	)
	_ok(
			"forecast: every hit's breakdown gives its damage, inline changes included",
			stages_wrong.is_empty(),
			_first(stages_wrong)
	)
	var uncovered: PackedStringArray = []
	for feature: String in coverage:
		if coverage[feature] == 0:
			uncovered.append(feature)
	_ok(
			"forecast = execution: covers crits, defeats, walks, Sidearm, inline, no counter",
			uncovered.is_empty(),
			"missing %s; %s" % [uncovered, coverage]
	)
	_ok(
			"summary: exact and sampled probabilities sum to 1 (%d candidates)" % [summaries],
			summaries > 0 and sums_wrong.is_empty(),
			_first(sums_wrong)
	)
	_ok("forecast = execution: no diagnostics", noisy.is_empty(), _first(noisy))


# The exact summary's kill and death odds are the hand-computed 2RN odds: each unit dies to one
# hit; the attacker hits first, and the counter comes only after a miss.
func _test_outcome_kill_odds() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "axe")
	field.add_weapon("w:e1", "axe")
	field.add_unit("p1", PLAYER, 0, Vector2i(2, 2), "w:p1", _bases(20))
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(20))
	field.session.open_battle()
	field.state().set_hp("p1", 1)
	field.state().set_hp("e1", 1)
	var command: UnitTurnCommand = UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	var before: String = _fingerprint(field)
	var exact: ExchangeOutcome = CombatForecast.outcome(field.engine(), command, BRANCH_BUDGET)
	# Axe against axe with the same stats: one Hit for both, read as the resolver reads it.
	var ctx: EffectContext = ExchangeResolver.context(
			field.engine(), field.state(), "p1", "e1", "p1", 0
	)
	var p: float = RollSource.hit_2rn_probability(
			ExchangeResolver.hit_chance(field.engine(), field.state(), ctx)
	)
	_ok(
			"summary: kill and death odds are the 2RN odds",
			(
					exact.complete
					and is_equal_approx(exact.kill_probability, p)
					and is_equal_approx(exact.death_probability, (1.0 - p) * p)
					and is_equal_approx(exact.total_probability, 1.0)
					and is_equal_approx(exact.expected_dealt_hp, p)
					and exact.max_damage == 1
			),
			exact.to_text()
	)
	var sampled: ExchangeOutcome = CombatForecast.sampled_outcome(
			field.engine(), command, field.session.last_seq(), SAMPLES
	)
	var again: ExchangeOutcome = CombatForecast.sampled_outcome(
			field.engine(), command, field.session.last_seq(), SAMPLES
	)
	_ok(
			"summary: sampled odds sum to 1, are an estimate, and repeat for the same seq",
			(
					absf(sampled.total_probability - 1.0) < PROBABILITY_TOLERANCE
					and not sampled.complete
					and sampled.branch_count == SAMPLES
					and sampled.to_text() == again.to_text()
			),
			"%s vs %s" % [sampled.to_text(), again.to_text()]
	)
	var refused: UnitTurnCommand = UnitTurnCommand.new(0, "p1", ATTACK, "p1")
	_ok(
			"summary: an illegal attack has no branches",
			CombatForecast.outcome(field.engine(), refused, BRANCH_BUDGET).total_probability == 0.0
			and CombatForecast.branch(field.engine(), refused, ForcedRolls.new()) == null
	)
	_ok("summary: changes no real state", _fingerprint(field) == before)
	_quiet("summary kill odds", field)


# Each side's Hit (shown and true 2RN), crit chance, attacks per turn, turns and the turn order;
# a bow at 2 that the sword can't counter.
func _test_side_numbers() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "gauntlets")
	field.add_weapon("w:e1", "sword")
	var fast: Dictionary = _bases(30)
	fast[CombatValue.Key.SPD] = 9.0
	field.add_unit("p1", PLAYER, 0, Vector2i(2, 2), "w:p1", fast)
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(30))
	field.session.open_battle()
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			field.engine(), UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	)
	var engine: EffectEngine = field.engine()
	var state: CombatState = field.state()
	var ahead: EffectContext = ExchangeResolver.context(engine, state, "p1", "e1", "p1", 0)
	var back: EffectContext = ExchangeResolver.context(engine, state, "e1", "p1", "p1", 0)
	var p1_hit: int = ExchangeResolver.hit_chance(engine, state, ahead)
	var e1_hit: int = ExchangeResolver.hit_chance(engine, state, back)
	_same(
			"sides: turn order with a bonus turn at a gap of 4",
			forecast.turn_order,
			PackedStringArray(["p1", "e1", "p1"])
	)
	_ok(
			"sides: attacks per turn, turns and attacks made",
			(
					forecast.attacker.attacks_per_turn == 2
					and forecast.defender.attacks_per_turn == 1
					and forecast.attacker.turns == 2
					and forecast.defender.turns == 1
					and forecast.attacks.size() == 5
					and forecast.can_counter
			),
			"%d %d %d %d %d" % [
				forecast.attacker.attacks_per_turn, forecast.defender.attacks_per_turn,
				forecast.attacker.turns, forecast.defender.turns, forecast.attacks.size(),
			]
	)
	_ok(
			"sides: Hit shown and its true 2RN probability",
			(
					forecast.attacker.hit == p1_hit
					and forecast.defender.hit == e1_hit
					and is_equal_approx(
							forecast.attacker.hit_probability,
							RollSource.hit_2rn_probability(p1_hit)
					)
					and forecast.rolls[forecast.attacker.hit_roll].value == p1_hit
			),
			"%d/%d vs %d/%d" % [forecast.attacker.hit, forecast.defender.hit, p1_hit, e1_hit]
	)
	_ok(
			"sides: each side names its weapon",
			forecast.attacker.weapon_id == "w:p1" and forecast.defender.weapon_id == "w:e1"
	)
	_ok(
			"sides: crit chance against an Exposed target is the base 25",
			forecast.attacker.crit_chance == ExchangeResolver.CRIT_BASE
	)
	var p1_after: CombatForecast.UnitOutcome = forecast.attacker.outcome
	var e1_after: CombatForecast.UnitOutcome = forecast.defender.outcome
	_ok(
			"sides: predicted HP, Block and Stance after",
			(
					p1_after.hp_after == 30 - forecast.defender.damage
					and e1_after.hp_after == 30 - 4 * forecast.attacker.damage
					and e1_after.stance_after == 0
					and p1_after.stance_after == 1
					and e1_after.block_after == 0
			),
			"p1 %d/%d e1 %d/%d" % [
				p1_after.hp_after, p1_after.stance_after, e1_after.hp_after, e1_after.stance_after,
			]
	)
	# Once e1 is Exposed (after p1's second hit), p1's later hits roll a crit that the forecast
	# fails: listed as a crit chance, never as a chance line.
	_ok(
			"sides: crit rolls on an Exposed defender are not chance lines",
			forecast.attacks[3].crit_roll >= 0 and forecast.chances.is_empty(),
			"%d chances" % [forecast.chances.size()]
	)
	_quiet("sides", field)

	var archer: Field = Field.new(_grid, SEED)
	archer.add_weapon("w:p1", "bow")
	archer.add_weapon("w:e1", "sword")
	archer.add_unit("p1", PLAYER, 0, Vector2i(1, 2), "w:p1", _bases(20))
	archer.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(20))
	archer.session.open_battle()
	var shot: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			archer.engine(), UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	)
	_ok(
			"sides: a sword can't counter a bow at 2",
			(
					not shot.can_counter
					and shot.defender.turns == 0
					and shot.defender.damage == -1
					and shot.attacks.size() == 1
					and shot.turn_order == PackedStringArray(["p1"])
			)
	)
	_quiet("sides: bow", archer)


# A hit's stages: the Attack value, Might, the triangle, Mitigation and the damage, adding up.
func _test_breakdown() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "sword")
	field.add_weapon("w:e1", "lance")
	field.add_unit("p1", PLAYER, 0, Vector2i(2, 2), "w:p1", _bases(30))
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(30))
	field.session.open_battle()
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			field.engine(), UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	)
	var sword: CombatForecast.HitBreakdown = forecast.attacker.breakdown
	var lance: CombatForecast.HitBreakdown = forecast.defender.breakdown
	var sums: bool = true
	for found: CombatForecast.HitBreakdown in [sword, lance]:
		var stage_one: float = found.attack.total + found.might + found.triangle
		sums = sums and is_equal_approx(stage_one - found.mitigation.total, found.stages.exact)
	_ok(
			"breakdown: weapon damage, Might 3, the triangle each way, DEF 2",
			(
					sword.attack.total == 5.0
					and sword.might == 3.0
					and sword.triangle < 0.0
					and lance.triangle > 0.0
					and sword.mitigation.total == 2.0
					and sword.critical == null
			),
			sword.to_text()
	)
	_ok("breakdown: the stages add up to the exact damage", sums)
	_ok(
			"breakdown: the side's damage is its first hit's",
			(
					forecast.attacker.damage == sword.stages.damage
					and forecast.attacks[0].damage == sword.stages.damage
					and forecast.defender.damage == lance.stages.damage
			)
	)
	_ok("breakdown: text names each stage", sword.to_text().contains("Might"), sword.to_text())
	_quiet("breakdown", field)


# Inline effects that change two stages of a hit (+3 Attack and x2 Multipliers for that hit): the
# forecast's breakdown lines are the real hit's, read on the session with the same context
# observer, and they add up to the damage dealt.
func _test_inline_breakdown() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "dagger")
	field.add_weapon("w:e1", "sword")
	field.add_unit("p1", PLAYER, 0, Vector2i(1, 2), "w:p1", _bases(30))
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(30))
	field.add_effect("effect:double", "p1", _double_hit())
	field.add_effect("effect:sharpen", "p1", _sharpen())
	field.session.open_battle()
	var command: UnitTurnCommand = UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(field.engine(), command)
	var real: Array[String] = []
	var dealt: Array[int] = []
	# The engine comes from the context, never a capture: the engine holds this observer, so a
	# captured engine or field would be a reference cycle and leak.
	field.engine().add_context_observer(func(fact: CombatFact, ctx: EffectContext) -> void:
		if fact.kind == CombatFact.Kind.HIT_DEALT:
			var engine: EffectEngine = ctx.engine
			var state: CombatState = engine.state
			real.append(CombatForecast.HitBreakdown.explain(engine, state, ctx).to_text())
			dealt.append(fact.amount)
	)
	command.based_on_seq = forecast.based_on_seq
	var batch: CombatSession.FactBatch = field.send(command)
	var shown: CombatForecast.HitBreakdown = forecast.attacks[0].breakdown
	_ok("inline: the attack resolves", not batch.is_rejected(), batch.rejected_reason)
	_same("inline: breakdown lines are the real hit's", [shown.to_text()], real)
	# Dagger 2 + 3 that hit + Might 3, less DEF 2, doubled: 12.
	_ok(
			"inline: both stages show the change and add up to the damage dealt",
			(
					shown.attack.total == 5.0
					and shown.stages.multipliers == 2.0
					and shown.stages.damage == 12
					and dealt == [12]
					and forecast.attacks[0].damage == 12
			),
			"%s; dealt %s" % [shown.to_text(), dealt]
	)
	_quiet("inline", field)


# A chance-gated "that hit" bonus is left out of the totals and listed as "25%: +X", with the
# effect named; the preview with it passing shows the bonus as an inline effect.
func _test_chance_lines() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "sword")
	field.add_weapon("w:e1", "sword")
	field.add_unit("p1", PLAYER, 0, Vector2i(2, 2), "w:p1", _bases(30))
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(30))
	field.add_effect("effect:lucky", "p1", _lucky())
	field.session.open_battle()
	var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			field.engine(), UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	)
	var dealt: int = forecast.attacks[0].damage
	_ok(
			"chance: left out of the totals",
			forecast.defender.outcome.hp_after == 30 - dealt and forecast.chances.size() == 1,
			"%d chances" % [forecast.chances.size()]
	)
	if forecast.chances.size() != 1:
		return
	var line: CombatForecast.ChanceLine = forecast.chances[0]
	_same(
			"chance: listed as 25%: +X with its effect",
			line.to_text(),
			"25%: e1 HP -5 (effect:lucky)"
	)
	var passing: CombatForecast.ExchangeForecast = line.what_if
	var shown: CombatForecast.HitBreakdown = passing.attacks[0].breakdown
	_ok(
			"chance: the passing preview has the bonus, in its breakdown's Attack stage",
			(
					passing.attacks[0].damage == dealt + 5
					and shown.stages.damage == dealt + 5
					and shown.attack.total == forecast.attacks[0].breakdown.attack.total + 5.0
					and passing.chances.is_empty()
			),
			shown.to_text()
	)
	_quiet("chance", field)


# Shelter after a walk, and Minor Heal with overheal: the preview's facts are the executed facts,
# and its recipients and predicted state are what happened.
func _test_staff_previews() -> void:
	for preset: String in ["shelter", "minor_heal"]:
		var field: Field = Field.new(_grid, SEED)
		field.add_weapon("w:p1", preset)
		field.add_unit("p1", PLAYER, 0, Vector2i(0, 2), "w:p1", _bases(20))
		field.add_unit("p2", PLAYER, 0, Vector2i(3, 2), "", _bases(20))
		field.add_unit("e1", ENEMY, -1, Vector2i(6, 4), "", _bases(20))
		field.session.open_battle()
		field.state().set_hp("p2", 18)
		var walk: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
		var command: UnitTurnCommand = UnitTurnCommand.new(0, "p1", STAFF, "p2", walk)
		var before: String = _fingerprint(field)
		var forecast: CombatForecast.StaffForecast = CombatForecast.staff(field.engine(), command)
		_ok("staff %s: changes nothing" % [preset], _fingerprint(field) == before)
		command.based_on_seq = forecast.based_on_seq
		var batch: CombatSession.FactBatch = field.send(command)
		_same(
				"staff %s: preview = execution" % [preset],
				_lines(forecast.facts),
				_lines(batch.facts)
		)
		_same("staff %s: predicted state" % [preset], _units_problem(forecast, field.state()), "")
		# Shelter: 3 + Might 3 Block. Minor Heal: 5 + Might 3 on 18 / 20 HP restores 2 of 8.
		var shown: PackedStringArray = []
		for given: CombatForecast.Recipient in forecast.recipients:
			shown.append("%s block %d healed %d restored %d overheal %d" % [
				given.unit_id, given.block_gained, given.healed, given.restored, given.overheal(),
			])
		var expected: String = (
				"p2 block 6 healed 0 restored 0 overheal 0" if preset == "shelter"
				else "p2 block 0 healed 8 restored 2 overheal 6"
		)
		_same("staff %s: recipient" % [preset], shown, PackedStringArray([expected]))
		_same("staff %s: amount" % [preset], forecast.amount, 6.0 if preset == "shelter" else 8.0)
		_quiet("staff %s" % [preset], field)


# Everwall (range 0): no target named, so the user is the target; every ally within 3 tiles of
# the user, the user included, gains 5 + Might, an ally farther away and the enemy nothing; and a
# range-0 staff named on another ally is the command's own rejection.
func _test_range_zero_staff() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "everwall")
	field.add_unit("p1", PLAYER, 0, Vector2i(0, 2), "w:p1", _bases(20))
	field.add_unit("p2", PLAYER, 0, Vector2i(3, 2), "", _bases(20))
	field.add_unit("p3", PLAYER, 0, Vector2i(6, 4), "", _bases(20))
	field.add_unit("e1", ENEMY, -1, Vector2i(2, 3), "", _bases(20))
	field.session.open_battle()
	var walk: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
	var named: UnitTurnCommand = UnitTurnCommand.new(0, "p1", STAFF, "p2", walk)
	var refused: CombatForecast.StaffForecast = CombatForecast.staff(field.engine(), named)
	var rejection: CombatSession.FactBatch = field.send(named)
	_ok(
			"range 0: another ally named is the command's rejection",
			not refused.is_legal and refused.reason == rejection.rejected_reason,
			"%s vs %s" % [refused.reason, rejection.rejected_reason]
	)
	var command: UnitTurnCommand = UnitTurnCommand.new(0, "p1", STAFF, "", walk)
	var forecast: CombatForecast.StaffForecast = CombatForecast.staff(field.engine(), command)
	command.based_on_seq = forecast.based_on_seq
	var batch: CombatSession.FactBatch = field.send(command)
	_same("range 0: preview = execution", _lines(forecast.facts), _lines(batch.facts))
	_same("range 0: predicted state", _units_problem(forecast, field.state()), "")
	var gains: PackedStringArray = []
	for given: CombatForecast.Recipient in forecast.recipients:
		gains.append("%s +%d" % [given.unit_id, given.block_gained])
	_ok(
			"range 0: the user is the target; allies within 3 gain 5 + Might",
			forecast.target_id == "p1" and gains == PackedStringArray(["p1 +8", "p2 +8"]),
			str(gains)
	)
	_quiet("range 0", field)


# A bump into a unit, an oil slide, and an Exposed foe pushed into a spiked wall after a walk:
# each preview's facts are the executed facts, and its path and predicted state are what happened.
func _test_shove_previews() -> void:
	var cases: Array[Array] = [
		# Name, shover tile, path, target, target tile, target side, third unit tile, stop.
		["bump", Vector2i(0, 0), [], "p2", Vector2i(1, 0), PLAYER, Vector2i(2, 0),
				ShoveResolver.Stop.BUMP],
		["oil", Vector2i(0, 1), [], "p2", Vector2i(1, 1), PLAYER, Vector2i(6, 0),
				ShoveResolver.Stop.DISTANCE],
		["spike", Vector2i(2, 2), [Vector2i(2, 2), Vector2i(3, 2)], "e2", Vector2i(4, 2), ENEMY,
				Vector2i(6, 0), ShoveResolver.Stop.SPIKE],
	]
	for row: Array in cases:
		var label: String = row[0]
		var shover_tile: Vector2i = row[1]
		var target: String = row[3]
		var target_tile: Vector2i = row[4]
		var target_side: CombatFact.CombatSide = row[5]
		var third_tile: Vector2i = row[6]
		var stop: ShoveResolver.Stop = row[7]
		var field: Field = Field.new(_shove_grid, SEED)
		field.add_unit("p1", PLAYER, 0, shover_tile, "", _bases(20))
		var target_seat: int = 0 if target_side == PLAYER else -1
		field.add_unit(target, target_side, target_seat, target_tile, "", _bases(20))
		field.add_unit("e1", ENEMY, -1, third_tile, "", _bases(20))
		field.session.open_battle()
		if target_side == ENEMY:
			field.state().set_stance(target, 0)
		var walk: Array[Vector2i] = []
		walk.assign(row[2] as Array)
		var command: UnitTurnCommand = UnitTurnCommand.new(0, "p1", SHOVE, target, walk)
		var before: String = _fingerprint(field)
		var forecast: CombatForecast.ShoveForecast = CombatForecast.shove(field.engine(), command)
		_ok("shove %s: legal and changes nothing" % [label], (
				forecast.is_legal and _fingerprint(field) == before
		), forecast.reason)
		if not forecast.is_legal:
			continue
		command.based_on_seq = forecast.based_on_seq
		var batch: CombatSession.FactBatch = field.send(command)
		_same(
				"shove %s: preview = execution" % [label],
				_lines(forecast.facts),
				_lines(batch.facts)
		)
		_same("shove %s: predicted state" % [label], _units_problem(forecast, field.state()), "")
		_ok("shove %s: path" % [label], (
				forecast.path.stop == stop
				and forecast.path.final_tile == field.state().tile_of(target)
				and (label != "oil" or forecast.path.slid)
		), "stop %d tile %s" % [forecast.path.stop, forecast.path.final_tile])
		_quiet("shove %s" % [label], field)


# An illegal preview gives the reason the command is rejected with, and changes nothing: out of
# range, a path through a unit, a unit that has acted, the wrong action.
func _test_rejections_match() -> void:
	var field: Field = Field.new(_grid, SEED)
	field.add_weapon("w:p1", "sword")
	field.add_weapon("w:e1", "sword")
	field.add_unit("p1", PLAYER, 0, Vector2i(0, 2), "w:p1", _bases(20))
	field.add_unit("p2", PLAYER, 0, Vector2i(1, 2), "", _bases(20))
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(20))
	field.session.open_battle()
	var onto_ally: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2)]
	var commands: Array[UnitTurnCommand] = [
		UnitTurnCommand.new(0, "p1", ATTACK, "e1"),
		UnitTurnCommand.new(0, "p1", ATTACK, "e1", onto_ally),
	]
	var before: String = _fingerprint(field)
	for command: UnitTurnCommand in commands:
		var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
				field.engine(), command
		)
		var expected: String = field.send(command).rejected_reason
		_ok(
				"rejection: the preview gives the command's reason (%s)" % [expected],
				not forecast.is_legal and forecast.reason == expected,
				forecast.reason
		)
	_ok("rejection: illegal previews change nothing", _fingerprint(field) == before)
	var wrong: CombatForecast.StaffForecast = CombatForecast.staff(
			field.engine(), UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	)
	_ok("rejection: a staff preview of an attack", not wrong.is_legal, wrong.reason)
	field.send(UnitTurnCommand.new(0, "p1", UnitTurnCommand.Action.WAIT))
	var late: UnitTurnCommand = UnitTurnCommand.new(0, "p1", ATTACK, "e1")
	var acted: CombatForecast.ExchangeForecast = CombatForecast.exchange(field.engine(), late)
	var acted_reason: String = field.send(late).rejected_reason
	_ok(
			"rejection: a unit that has acted",
			not acted.is_legal and acted.reason == acted_reason,
			"%s vs %s" % [acted.reason, acted_reason]
	)
	_quiet("rejection", field)


# The stale rule on a two-seat map: after a partner's rune, an attack, a staff and a shove from
# older forecasts are rejected, each naming the first fact since; a move-only command from an old
# forecast still goes through; and a forecast with nothing recorded since stays fresh.
func _test_stale_rule() -> void:
	var field: Field = Field.new(_grid, SEED, PackedInt32Array([0, 1]))
	field.add_weapon("w:p1", "sword")
	field.add_weapon("w:p2", "shelter")
	field.add_weapon("w:e1", "sword")
	field.add_unit("p1", PLAYER, 0, Vector2i(2, 2), "w:p1", _bases(20))
	field.add_unit("p2", PLAYER, 0, Vector2i(1, 2), "w:p2", _bases(20))
	field.add_unit("p3", PLAYER, 0, Vector2i(2, 0), "", _bases(20))
	field.add_unit("p4", PLAYER, 0, Vector2i(3, 0), "", _bases(20))
	field.add_unit("p5", PLAYER, 0, Vector2i(0, 0), "", _bases(20))
	field.add_unit("q1", PLAYER, 1, Vector2i(0, 4), "", _bases(20))
	field.add_unit("e1", ENEMY, -1, Vector2i(3, 2), "w:e1", _bases(20))
	field.state().rune_slots[1] = PackedStringArray(["rune:mend"])
	var mend: GainResource = GainResource.new()
	mend.pool = GainResource.Pool.HP
	mend.target = CommandTarget.new()
	var ten: Constant = Constant.new()
	ten.value = 10.0
	mend.amount = ten
	field.engine().register(EffectInstance.new(
			"effect:mend",
			_definition(EffectDefinition.Trigger.ALWAYS, [], [mend]),
			EffectOwner.for_rune("rune:mend", 1),
			Modifier.SourceKind.RUNE
	))
	field.session.open_battle()
	field.state().set_hp("q1", 5)
	var commands: Array[UnitTurnCommand] = [
		UnitTurnCommand.new(0, "p1", ATTACK, "e1"),
		UnitTurnCommand.new(0, "p2", STAFF, "p1"),
		UnitTurnCommand.new(0, "p3", SHOVE, "p4"),
	]
	var previews: Array[CombatForecast.Forecast] = [
		CombatForecast.exchange(field.engine(), commands[0]),
		CombatForecast.staff(field.engine(), commands[1]),
		CombatForecast.shove(field.engine(), commands[2]),
	]
	var seen: int = field.session.last_seq()
	var walk: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	var move: UnitTurnCommand = UnitTurnCommand.new(0, "p5", UnitTurnCommand.Action.WAIT, "", walk)
	move.based_on_seq = seen

	var rune: CombatSession.FactBatch = field.send(CastRuneCommand.new(1, "rune:mend", "q1"))
	_ok("stale: the partner's rune resolves", not rune.is_rejected(), rune.rejected_reason)
	var first: CombatFact = rune.facts[0]
	var expected: String = "stale forecast (s0#%d %s after s0#%d)" % [
		first.seq, CombatFact.Kind.find_key(first.kind), seen,
	]
	for i: int in commands.size():
		var command: UnitTurnCommand = commands[i]
		command.based_on_seq = previews[i].based_on_seq
		_same(
				"stale: a partner's rune makes the %s stale" % [command.get_label()],
				field.send(command).rejected_reason,
				expected
		)
	var moved: CombatSession.FactBatch = field.send(move)
	_ok(
			"stale: a move-only command from an old forecast goes through",
			not moved.is_rejected() and field.state().tile_of("p5") == Vector2i(0, 1),
			moved.rejected_reason
	)
	for i: int in commands.size():
		var command: UnitTurnCommand = commands[i]
		var fresh: CombatForecast.Forecast = null
		match command.action:
			ATTACK:
				fresh = CombatForecast.exchange(field.engine(), command)
			STAFF:
				fresh = CombatForecast.staff(field.engine(), command)
			SHOVE:
				fresh = CombatForecast.shove(field.engine(), command)
		command.based_on_seq = fresh.based_on_seq
		var batch: CombatSession.FactBatch = field.send(command)
		_ok(
				"stale: the %s forecast with nothing since stays fresh" % [command.get_label()],
				not batch.is_rejected() and fresh.based_on_seq == batch.facts[0].seq - 1,
				batch.rejected_reason
		)
	_quiet("stale", field)


# --- Fixtures ------------------------------------------------------------------------------------


# Seeded exchange `index`: p1 attacks e1 at a distance its weapon reaches, mostly after walking
# along its row; sometimes with the stowed weapon through Sidearm, Cleave on e1 with p2 beside it,
# Momentum, lifesteal or a doubled hit on p1; random stats, HP and e1's Stance.
func _exchange_trial(index: int) -> Trial:
	var pick: RngStream = RngStream.new(SEED + index)
	var field: Field = Field.new(_grid, SEED - 1 - index)
	var row: int = 1 if pick.roll_percent(50) else 3
	var weapon: String = ATTACKER_WEAPONS[pick.pick_index(ATTACKER_WEAPONS.size())]
	var stowed: String = ""
	if pick.roll_percent(SIDEARM_PERCENT):
		stowed = ATTACKER_WEAPONS[pick.pick_index(ATTACKER_WEAPONS.size())]
	var reach: Array = WEAPONS[weapon if stowed.is_empty() else stowed]
	var shortest: int = reach[3]
	var longest: int = reach[4]
	var distance: int = pick.randi_range(shortest, longest)
	var end: Vector2i = Vector2i(DEFENDER_X - distance, row)
	var walk: Array[Vector2i] = []
	if pick.roll_percent(WALK_PERCENT):
		for x: int in end.x + 1:
			walk.append(Vector2i(x, row))
	field.add_weapon("w:p1", weapon, pick.randi_range(0, 40))
	if not stowed.is_empty():
		field.add_weapon("w:p1:stowed", stowed, pick.randi_range(0, 40))
	var held: String = DEFENDER_WEAPONS[pick.pick_index(DEFENDER_WEAPONS.size())]
	field.add_weapon("w:e1", held, pick.randi_range(0, 40))
	var start: Vector2i = end if walk.is_empty() else walk[0]
	field.add_unit(
			"p1", PLAYER, 0, start, "w:p1", _random_bases(pick),
			"" if stowed.is_empty() else "w:p1:stowed"
	)
	field.add_unit("e1", ENEMY, -1, Vector2i(DEFENDER_X, row), "w:e1", _random_bases(pick))
	if pick.roll_percent(CLEAVE_PERCENT):
		field.add_weapon("w:p2", "sword")
		field.add_unit("p2", PLAYER, 0, Vector2i(DEFENDER_X + 1, row), "w:p2", _random_bases(pick))
		field.add_effect("effect:cleave", "e1", _cleave())
	if pick.roll_percent(MOMENTUM_PERCENT):
		field.add_effect("effect:momentum", "p1", _momentum())
	var trial: Trial = Trial.new()
	if pick.roll_percent(LIFESTEAL_PERCENT):
		field.add_effect("effect:lifesteal", "p1", _lifesteal())
		trial.has_inline = true
	if pick.roll_percent(DOUBLE_HIT_PERCENT):
		field.add_effect("effect:double", "p1", _double_hit())
		trial.has_inline = true
	if not stowed.is_empty():
		field.add_effect("effect:sidearm", "p1", _sidearm())
	field.session.open_battle()

	var state: CombatState = field.state()
	for unit_id: String in ["p1", "e1"]:
		state.set_hp(unit_id, pick.randi_range(1, state.get_hp(unit_id)))
	state.set_stance("e1", pick.randi_range(0, state.get_stance("e1")))
	trial.field = field
	trial.command = UnitTurnCommand.new(0, "p1", ATTACK, "e1", walk)
	if not stowed.is_empty():
		trial.command.weapon_id = "w:p1:stowed"
	return trial


# Bases with HP `hp`, Stance 2, movement 6 (enough to cross the forest), Might 3, Speed 5,
# Defense 2, Resistance 1, Constitution 20.
func _bases(hp: int) -> Dictionary:
	return {
		CombatValue.Key.HP: float(hp),
		CombatValue.Key.STANCE_MAX: 2.0,
		CombatValue.Key.MOVEMENT: 6.0,
		CombatValue.Key.MGT: 3.0,
		CombatValue.Key.SPD: 5.0,
		CombatValue.Key.DEF: 2.0,
		CombatValue.Key.RES: 1.0,
		CombatValue.Key.CON: 20.0,
	}


# Random bases: HP 8 to 30, Stance 1 to 3, Might 0 to 8, Speed 1 to 12, Defense and Resistance
# 0 to 6, Constitution 3 to 15 (so heavy weapons slow some units), movement 6.
func _random_bases(pick: RngStream) -> Dictionary:
	return {
		CombatValue.Key.HP: float(pick.randi_range(8, 30)),
		CombatValue.Key.STANCE_MAX: float(pick.randi_range(1, 3)),
		CombatValue.Key.MOVEMENT: 6.0,
		CombatValue.Key.MGT: float(pick.randi_range(0, 8)),
		CombatValue.Key.SPD: float(pick.randi_range(1, 12)),
		CombatValue.Key.DEF: float(pick.randi_range(0, 6)),
		CombatValue.Key.RES: float(pick.randi_range(0, 6)),
		CombatValue.Key.CON: float(pick.randi_range(3, 15)),
	}


# The exact (when it fits the budget) and sampled summaries of command: why their probabilities
# don't sum to 1, or empty.
func _summary_problem(field: Field, command: UnitTurnCommand) -> String:
	var exact: ExchangeOutcome = CombatForecast.outcome(field.engine(), command, BRANCH_BUDGET)
	var sampled: ExchangeOutcome = CombatForecast.sampled_outcome(
			field.engine(), command, field.session.last_seq(), SAMPLES
	)
	if exact.complete and absf(exact.total_probability - 1.0) > PROBABILITY_TOLERANCE:
		return "exact %s" % [exact.to_text()]
	if not exact.complete and exact.branch_count != BRANCH_BUDGET:
		return "partial after %d runs" % [exact.branch_count]
	if absf(sampled.total_probability - 1.0) > PROBABILITY_TOLERANCE:
		return "sampled %s" % [sampled.to_text()]
	for summary: ExchangeOutcome in [exact, sampled]:
		if not summary.diagnostics.is_empty():
			return "diagnostics %s" % [summary.diagnostics]
	return ""


# Why forecast's predicted units differ from state; empty when every one matches.
func _units_problem(forecast: CombatForecast.Forecast, state: CombatState) -> String:
	for predicted: CombatForecast.UnitOutcome in forecast.units:
		var id: String = predicted.unit_id
		var actual: String = "%d/%d/%d %s %s" % [
			state.get_hp(id), state.get_block(id), state.get_stance(id), state.tile_of(id),
			not state.has_unit(id),
		]
		var shown: String = "%d/%d/%d %s %s" % [
			predicted.hp_after, predicted.block_after, predicted.stance_after,
			predicted.tile_after, predicted.is_defeated,
		]
		if actual != shown:
			return "%s predicted %s, was %s" % [id, shown, actual]
	return ""


# Everything a forecast must leave alone: the log, the stream, the rolls, diagnostics, grants,
# every unit's state, timed modifiers, and every effect's counters and charges.
func _fingerprint(field: Field) -> String:
	var engine: EffectEngine = field.engine()
	var state: CombatState = field.state()
	var parts: PackedStringArray = [
		"seq %d" % [field.session.last_seq()],
		field.stream.capture(),
		"rolls %d diagnostics %d grants %d" % [
			engine.rolls.records.size(), engine.diagnostics.size(), engine.grants.size(),
		],
	]
	for id: String in state.unit_ids():
		var unit: CombatUnitState = state.unit(id)
		parts.append("%s %d/%d/%d %s moved %d acted %s weapon %s timed %d" % [
			id, unit.hp, unit.block, unit.stance, unit.tile, unit.tiles_moved, unit.has_acted,
			unit.equipped_weapon_id, engine.get_timed_modifiers(id).size(),
		])
	for instance: EffectInstance in engine.get_instances():
		parts.append("%s %d %d %d" % [
			instance.instance_id,
			instance.get_counter(EffectDefinition.Lane.COMBAT),
			instance.get_counter(EffectDefinition.Lane.CAMPAIGN),
			instance.charges_left,
		])
	return "\n".join(parts)


static func _grid_of(rows: Array[String]) -> MapGrid:
	var layout: MapLayout = MapLayout.new()
	layout.map_id = "forecast"
	var cache: Dictionary[String, MapLayout.Terrain] = {}
	for y: int in rows.size():
		var terrain_ids: PackedStringArray = rows[y].split(" ", false)
		for x: int in terrain_ids.size():
			var terrain_id: String = terrain_ids[x]
			if not cache.has(terrain_id):
				cache[terrain_id] = MapLayout.Terrain.from_definition(
						MapLoader.load_terrain(terrain_id)
				)
			layout.set_terrain(Vector2i(x, y), cache[terrain_id])
	return MapGrid.new(layout)


# --- Effects (bench and golden fixtures) ---------------------------------------------------------


# Momentum (Fighter): Missed: +15 Hit on the next attack this combat.
func _momentum() -> EffectDefinition:
	var bonus: AddTimedModifier = AddTimedModifier.new()
	bonus.key = CombatValue.Key.HIT
	bonus.mode = Modifier.Mode.ADD
	bonus.value = 15.0
	bonus.end = AddTimedModifier.End.THIS_COMBAT
	bonus.uses = 1
	return _definition(EffectDefinition.Trigger.MISSED, [], [bonus])


# Cleave (Brute): Hit dealt: 2 splash damage to adjacent units, friend or foe.
func _cleave() -> EffectDefinition:
	var area: Area = Area.new()
	area.center = Area.Center.OWNER
	area.radius = 1
	area.side = EffectDefinition.UnitSide.ANY
	area.include_center = false
	var amount: Constant = Constant.new()
	amount.value = 2.0
	var splash: DealSplash = DealSplash.new()
	splash.target = area
	splash.amount = amount
	return _definition(EffectDefinition.Trigger.HIT_DEALT, [], [splash])


# Every attack this unit makes has lifesteal: an inline flag that changes no damage.
func _lifesteal() -> EffectDefinition:
	var flag: ModifyThat = ModifyThat.new()
	flag.what = ModifyThat.What.FLAG
	flag.flag = ModifyThat.Flag.LIFESTEAL
	return _definition(EffectDefinition.Trigger.ATTACK_MADE, [], [flag])


# Hit dealt: x2 Multipliers for that hit, an inline change the breakdown can't see (TOD-001).
func _double_hit() -> EffectDefinition:
	var twice: ModifyThat = ModifyThat.new()
	twice.what = ModifyThat.What.VALUE
	twice.key = DamageStage.Key.MULTIPLIERS
	twice.mode = Modifier.Mode.MULTIPLY
	twice.value = 2.0
	return _definition(EffectDefinition.Trigger.HIT_DEALT, [], [twice])


# Hit dealt: +3 Attack for that hit.
func _sharpen() -> EffectDefinition:
	var bonus: ModifyThat = ModifyThat.new()
	bonus.what = ModifyThat.What.VALUE
	bonus.key = DamageStage.Key.ATTACK
	bonus.mode = Modifier.Mode.ADD
	bonus.value = 3.0
	return _definition(EffectDefinition.Trigger.HIT_DEALT, [], [bonus])


# Hit dealt, 25% chance: +5 Attack for that hit.
func _lucky() -> EffectDefinition:
	var chance: ChanceCondition = ChanceCondition.new()
	chance.chance_percent = 25
	var bonus: ModifyThat = ModifyThat.new()
	bonus.what = ModifyThat.What.VALUE
	bonus.key = DamageStage.Key.ATTACK
	bonus.mode = Modifier.Mode.ADD
	bonus.value = 5.0
	return _definition(EffectDefinition.Trigger.HIT_DEALT, [chance], [bonus])


# Sidearm: always allowed a free weapon swap.
func _sidearm() -> EffectDefinition:
	var grant: SetPermission = SetPermission.new()
	grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
	grant.allow = true
	return _definition(EffectDefinition.Trigger.ALWAYS, [], [grant])


func _definition(
		trigger: EffectDefinition.Trigger, conditions: Array, operations: Array
) -> EffectDefinition:
	var definition: EffectDefinition = EffectDefinition.new()
	definition.trigger = trigger
	definition.conditions.assign(conditions)
	definition.operations.assign(operations)
	return definition


# --- Checks --------------------------------------------------------------------------------------


func _lines(facts: Array[CombatFact]) -> Array[String]:
	var found: Array[String] = []
	for fact: CombatFact in facts:
		found.append(fact.to_log_line())
	return found


# The first few entries of a failure list, for the detail.
func _first(list: PackedStringArray) -> String:
	return "%d: %s" % [list.size(), "\n".join(list.slice(0, 3))]


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)


func _same(case_name: String, actual: Variant, expected: Variant) -> void:
	_check.call(case_name, actual == expected, "got %s, expected %s" % [actual, expected])


# Asserts that the field's engine reported no diagnostics.
func _quiet(case_name: String, field: Field) -> void:
	_ok("%s: no diagnostics" % [case_name], field.engine().diagnostics.is_empty(),
			str(field.engine().diagnostics))


## A seeded exchange: its session and the command to forecast and send.
class Trial:
	extends RefCounted

	var field: Field = null
	var command: UnitTurnCommand = null
	## Whether p1 has an effect that changes its attacks inline (lifesteal, a doubled hit).
	var has_inline: bool = false


## A real [CombatSession] for one case, over a shared map, rolling through [LiveRolls].
class Field:
	extends RefCounted

	## The session.
	var session: CombatSession = null
	## The session's combat stream, so a case can tell whether anything drew from it.
	var stream: RngStream = null

	func _init(
			grid: MapGrid, stream_seed: int, seats: PackedInt32Array = PackedInt32Array([0])
	) -> void:
		stream = RngStream.new(stream_seed)
		session = CombatSession.new(
				0, seats, grid, LiveRolls.new(stream), InstanceIdAllocator.new()
		)
		session.engine.verify = true

	func state() -> CombatState:
		return session.state

	func engine() -> EffectEngine:
		return session.engine

	## Adds weapon [param weapon_id] from a WEAPONS preset, with [param crit] added to the base 25.
	func add_weapon(weapon_id: String, preset: String, crit: int = 0) -> void:
		var stats: CombatState.WeaponStats = CombatState.WeaponStats.new()
		stats.id = weapon_id
		stats.label = preset.capitalize()
		# Columns: damage, AtkX, profile, range min, range max, Hit, CritX, weight, staff kind,
		# staff amount.
		var columns: Array = WEAPONS[preset]
		stats.damage = columns[0]
		stats.atk_x = columns[1]
		stats.profile = columns[2]
		stats.range_min = columns[3]
		stats.range_max = columns[4]
		stats.hit = columns[5]
		stats.crit_x = columns[6]
		stats.weight = columns[7]
		stats.staff = columns[8]
		stats.staff_amount = columns[9]
		stats.crit = crit
		if preset == "fire" or preset == "harm":
			stats.damage_type = CombatFact.DamageType.MAGIC
		if preset == "bow":
			stats.effective_against = PackedStringArray(["Flier"])
		if preset == "everwall":
			var area: Area = Area.new()
			area.center = Area.Center.OWNER
			area.radius = 3
			area.side = EffectDefinition.UnitSide.ALLY
			area.include_center = true
			stats.area = area
		session.state.add_weapon(stats)

	## Places a unit holding [param weapon_id] (and [param stowed_id] stowed) with
	## [param bases], at full HP.
	func add_unit(
			id: String,
			side: CombatFact.CombatSide,
			seat: int,
			tile: Vector2i,
			weapon_id: String,
			bases: Dictionary,
			stowed_id: String = ""
	) -> void:
		var unit: CombatUnitState = CombatUnitState.new()
		unit.id = id
		unit.side = side
		unit.seat = seat
		unit.tile = tile
		unit.hp = roundi(bases[CombatValue.Key.HP] as float)
		unit.equipped_weapon_id = weapon_id
		unit.stowed_weapon_id = stowed_id
		session.add_unit(unit, bases)

	## Registers [param definition] as a trait of [param unit_id].
	func add_effect(instance_id: String, unit_id: String, definition: EffectDefinition) -> void:
		session.engine.register(EffectInstance.new(
				instance_id,
				definition,
				EffectOwner.for_unit(
						unit_id, session.state.seat_of(unit_id), session.state.side_of(unit_id)
				),
				Modifier.SourceKind.UNIT_TRAIT,
				instance_id
		))

	## Submits [param command] and resolves the queue; returns its batch.
	func send(command: Command) -> CombatSession.FactBatch:
		session.submit(command)
		return session.resolve_next()
