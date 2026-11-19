# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     resolver_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Resolver cases for tests/events/run_all.gd: an option applies all or nothing (a later block's
## refusal leaves an earlier one unapplied); blocks apply in order with the curse last; a named
## curse; a tier's curse once drawn, refused before it is and when it is of another tier; a seat
## outside the run; the result's facts are exactly the log's new ones; and neither rolling nor
## resolving touches the global RNG, while the same stream state rolls the same result.
## Touches no save files.

const Fixture = preload("res://tests/events/event_fixture.gd")

const GLOBAL_SEED: int = 4242

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("resolver: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_all_or_nothing()
	_test_order_and_curses()
	_test_seat_outside()
	_test_global_rng_untouched()


func _test_all_or_nothing() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var log_size: int = made.run.fact_log.size()
	var stat: StatOutcome = StatOutcome.new()
	stat.amount = 2
	var result: EventResult = EventResolver.resolve(_fx.context(made, _fx.event_of([
		_gold(40), stat,
	])))
	_check("resolver: a refused second block leaves the first unapplied", (
			result.is_rejected() and seat_run.gold == 100
			and made.run.fact_log.size() == log_size and result.facts.is_empty()
	), result.rejected_reason)


func _test_order_and_curses() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	made.run.fact_log.append(CampaignFact.new(CampaignFact.Kind.NODE_LEFT))
	var named: EventResult = EventResolver.resolve(_fx.context(
			made, _fx.event_of([_gold(80)], null, "leaden_boots")
	))
	_check("resolver: blocks first, then the named curse; facts are only this option's", (
			not named.is_rejected()
			and _fx.kinds(named.facts) == [
				CampaignFact.Kind.GOLD_CHANGED, CampaignFact.Kind.GAINED,
			]
			and named.facts[1].definition_id == "leaden_boots"
			and seat_run.heirloom_ids().has("leaden_boots")
			and named.facts[0].seq == made.run.fact_log.size() - 1
	), named.rejected_reason)

	var tiered: EventDefinition = _fx.event_of([_gold(40)], null, "", "minor")
	var undrawn: EventResult = EventResolver.resolve(_fx.context(made, tiered))
	_check("resolver: a tier's curse not yet drawn is refused", (
			undrawn.is_rejected() and undrawn.rejected_reason.contains("isn't named yet")
	), undrawn.rejected_reason)
	var wrong: EventContext = _fx.context(made, tiered)
	wrong.rolls.curse_id = "hunted"
	var wrong_result: EventResult = EventResolver.resolve(wrong)
	_check("resolver: a drawn curse of another tier is refused", (
			wrong_result.is_rejected() and wrong_result.rejected_reason.contains("minor")
	), wrong_result.rejected_reason)
	var drawn: EventContext = _fx.context(made, tiered)
	drawn.rolls.curse_id = "haunted"
	var gold_before: int = seat_run.gold
	var drawn_result: EventResult = EventResolver.resolve(drawn)
	_check("resolver: a minor tier's drawn curse is given with the reward", (
			not drawn_result.is_rejected() and seat_run.heirloom_ids().has("haunted")
			and seat_run.gold == gold_before + 40
	), drawn_result.rejected_reason)


func _test_seat_outside() -> void:
	var made: CampaignSession = _fx.session()
	var ctx: EventContext = _fx.context(made, _fx.event_of([_gold(40)]))
	ctx.seat = 3
	var result: EventResult = EventResolver.resolve(ctx)
	_check("resolver: a seat outside the run is refused", (
			result.is_rejected() and result.rejected_reason.contains("isn't in the run")
	), result.rejected_reason)


# The global generator's next value after seeding is fixed, so any draw from it in between
# shows as a different value.
func _test_global_rng_untouched() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	seed(GLOBAL_SEED)
	var expected: int = randi()
	var weapon: ItemGrantOutcome = ItemGrantOutcome.new()
	weapon.random = ItemGrantOutcome.RandomItem.RARE_WEAPON
	var rune: RuneOutcome = RuneOutcome.new()
	rune.is_random = true
	var event: EventDefinition = _fx.event_of([weapon, rune, PrefixRerollOutcome.new()])
	var stream: RngStream = _fx.stream(made)
	var state: String = stream.capture()

	seed(GLOBAL_SEED)
	var rolls: EventRolls = EventResolver.roll(
			event.options[0], seat_run, stream, _fx.catalog, _fx.rules
	)
	var ctx: EventContext = _fx.context(made, event, EventChoice.new(seat_run.army[1].instance_id))
	ctx.rolls = rolls
	ctx.stream = stream
	var result: EventResult = EventResolver.resolve(ctx)
	var actual: int = randi()
	_check("resolver: rolling and resolving never draw from the global RNG", (
			not result.is_rejected() and actual == expected
	), "%s; %d vs %d" % [result.rejected_reason, actual, expected])

	var replay: RngStream = _fx.stream(made)
	replay.restore(state)
	var same: EventRolls = EventResolver.roll(
			event.options[0], seat_run, replay, _fx.catalog, _fx.rules
	)
	_check("resolver: the same stream state rolls the same parts", (
			same.picks == rolls.picks
	), "%s / %s" % [same.picks, rolls.picks])


func _gold(amount: int) -> GoldOutcome:
	var block: GoldOutcome = GoldOutcome.new()
	block.amount = amount
	return block


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
